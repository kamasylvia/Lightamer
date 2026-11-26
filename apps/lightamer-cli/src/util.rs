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
#[allow(clippy::needless_pass_by_value)] // `io::Error` is small; owned keeps `map_err` closures terse
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
}
