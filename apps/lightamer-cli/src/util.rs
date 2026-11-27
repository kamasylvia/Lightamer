// SPDX-License-Identifier: GPL-3.0-or-later
//! Shared helpers: error type, subprocess capture, unique temp dirs.

use std::ffi::OsStr;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Crate-wide error: a human-readable message.
#[derive(Debug)]
pub struct Error(pub String);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

impl Error {
    /// Build an error from a message.
    #[must_use]
    pub fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

/// Attach path context to an I/O error.
#[must_use]
#[expect(clippy::needless_pass_by_value)] // `io::Error` is small; owned keeps `map_err` closures terse
pub fn io_error(path: &Path, err: io::Error) -> Error {
    Error(format!("{}: {err}", path.display()))
}

/// Captured result of a child process.
#[derive(Debug)]
pub struct CmdOutput {
    /// True when the child exited with status 0.
    pub success: bool,
    /// Exit code, when the platform reports one.
    pub code: Option<i32>,
    /// Raw stdout bytes.
    pub stdout: Vec<u8>,
    /// Raw stderr bytes.
    pub stderr: Vec<u8>,
}

/// Run `program` with `args` and extra env vars, capturing both streams.
///
/// # Errors
///
/// Returns [`Error`] when the child cannot be spawned or waited on.
pub fn run_capture(
    program: &str,
    args: &[impl AsRef<OsStr>],
    env_extra: &[(&str, &OsStr)],
) -> Result<CmdOutput, Error> {
    let mut cmd = Command::new(program);
    cmd.args(args);
    for (key, value) in env_extra {
        cmd.env(key, value);
    }
    let output = cmd
        .output()
        .map_err(|e| Error(format!("spawn {program}: {e}")))?;
    Ok(CmdOutput {
        success: output.status.success(),
        code: output.status.code(),
        stdout: output.stdout,
        stderr: output.stderr,
    })
}

/// Lossy stderr tail (at most `max` bytes) for error messages.
#[must_use]
pub fn stderr_tail(output: &CmdOutput, max: usize) -> String {
    let bytes = &output.stderr;
    let start = bytes.len().saturating_sub(max);
    String::from_utf8_lossy(bytes.get(start..).unwrap_or_default()).into_owned()
}

/// Writes `text` to stdout. A closed pipe (the reader went away, as in
/// `lightamer-cli ... | head -1`) exits quietly with status 0 instead of
/// panicking; any other write failure reports to stderr and exits 1. Never
/// returns on a write failure.
pub fn print_stdout(text: &str) {
    use std::io::Write;
    let mut out = std::io::stdout().lock();
    match out.write_all(text.as_bytes()) {
        Ok(()) => {}
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => std::process::exit(0),
        Err(err) => {
            eprintln!("lightamer-cli: stdout: {err}");
            std::process::exit(1);
        }
    }
}

/// Writes one `text` line to stdout; see [`print_stdout`] for failures.
pub fn print_stdout_line(text: &str) {
    let mut line = String::with_capacity(text.len() + 1);
    line.push_str(text);
    line.push('\n');
    print_stdout(&line);
}

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Create a unique directory under the system temp dir.
///
/// # Errors
///
/// Returns [`Error`] when the directory cannot be created.
pub fn make_temp_dir(prefix: &str) -> Result<PathBuf, Error> {
    let pid = std::process::id();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    for _ in 0..100 {
        let n = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("{prefix}-{pid}-{nanos}-{n}"));
        match fs::create_dir(&dir) {
            Ok(()) => return Ok(dir),
            Err(e) => {
                if e.kind() != io::ErrorKind::AlreadyExists {
                    return Err(io_error(&dir, e));
                }
            }
        }
    }
    Err(Error::new(format!(
        "cannot create unique temp dir for {prefix}"
    )))
}

/// Remove a dir tree, ignoring any failure (best-effort cleanup).
pub fn remove_dir_quiet(path: &Path) {
    let _ = fs::remove_dir_all(path);
}

/// Deletes stale temp dirs of one [`make_temp_dir`] prefix: entries whose
/// embedded pid is dead (a previous run killed mid-test can never clean
/// after itself, so the next run sweeps its predecessors). Live pids —
/// this process, a parallel lane's — and unparsable names are never
/// touched. Best-effort: unreadable directories and removal failures are
/// ignored. Returns how many were removed.
#[must_use]
pub fn sweep_stale_temp_dirs(prefix: &str) -> usize {
    let mut removed = 0;
    let entries = std::fs::read_dir(std::env::temp_dir()).map_or(Vec::new(), |entries| {
        entries.filter_map(Result::ok).collect()
    });
    for entry in entries {
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        let Some(rest) = name.strip_prefix(prefix) else {
            continue;
        };
        let Some(pid_text) = rest
            .strip_prefix('-')
            .and_then(|tail| tail.split('-').next())
        else {
            continue;
        };
        let Ok(pid) = pid_text.parse::<u32>() else {
            continue;
        };
        if pid == std::process::id() || process_alive(pid) {
            continue;
        }
        if std::fs::remove_dir_all(entry.path()).is_ok() {
            removed += 1;
        }
    }
    removed
}

/// Whether `pid` names a live process (`kill -0`, no signal sent).
fn process_alive(pid: u32) -> bool {
    std::process::Command::new("kill")
        .args(["-0", &pid.to_string()])
        .output()
        .is_ok_and(|out| out.status.success())
}

/// User home from `$HOME`.
#[must_use]
pub fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

/// Read a whole file as UTF-8, with path context on failure.
///
/// # Errors
///
/// Returns [`Error`] when the file cannot be read.
pub fn read_to_string(path: &Path) -> Result<String, Error> {
    fs::read_to_string(path).map_err(|e| io_error(path, e))
}

/// Write bytes to a file, creating parent dirs, with path context on failure.
///
/// # Errors
///
/// Returns [`Error`] when the file cannot be written.
pub fn write_file(path: &Path, bytes: &[u8]) -> Result<(), Error> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| io_error(parent, e))?;
    }
    fs::write(path, bytes).map_err(|e| io_error(path, e))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;

    #[test]
    fn temp_dirs_are_unique() {
        let a = make_temp_dir("lightamer-cli-test").unwrap();
        let b = make_temp_dir("lightamer-cli-test").unwrap();
        assert_ne!(a, b);
        assert!(a.is_dir() && b.is_dir());
        remove_dir_quiet(&a);
        remove_dir_quiet(&b);
        assert!(!a.exists() && !b.exists());
    }

    #[test]
    fn run_capture_echo() {
        let out = run_capture("/bin/echo", &["hi"], &[]).unwrap();
        assert!(out.success);
        assert_eq!(out.stdout, b"hi\n");
    }

    #[test]
    fn run_capture_reports_failure() {
        let out = run_capture("/usr/bin/false", &[] as &[&str], &[]).unwrap();
        assert!(!out.success);
    }

    #[test]
    fn error_display() {
        assert_eq!(Error::new("boom").to_string(), "boom");
    }

    #[test]
    fn sweep_removes_dead_pid_dirs_and_keeps_live_ones() {
        // A pid past the platform maximum is dead by definition.
        let dead = std::env::temp_dir().join("lightamer-cli-sweep-999999999-0-0");
        let _ = std::fs::remove_dir_all(&dead);
        std::fs::create_dir(&dead).unwrap();
        let live = make_temp_dir("lightamer-cli-sweep").unwrap();
        let foreign = std::env::temp_dir().join("lightamer-cli-sweep-no-pid-here");
        let _ = std::fs::remove_dir_all(&foreign);
        std::fs::create_dir(&foreign).unwrap();
        assert_eq!(sweep_stale_temp_dirs("lightamer-cli-sweep"), 1);
        assert!(!dead.exists());
        assert!(live.is_dir());
        assert!(foreign.is_dir());
        remove_dir_quiet(&live);
        remove_dir_quiet(&foreign);
    }
}
