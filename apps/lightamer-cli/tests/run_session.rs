// SPDX-License-Identifier: GPL-3.0-or-later
//! `run --file` end to end through the built binary: session files, the
//! photos refusal, `--hold`, and templates under an overridden directory.
//!
//! The binary runs as a child with its own environment (safe); no test
//! here mutates this process's environment.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

/// A fresh empty directory for one test, removed when dropped.
struct ScratchDir {
    path: PathBuf,
}

impl ScratchDir {
    fn new(tag: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "lightamer-cli-test-{}-{n}-{tag}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path)?;
        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let ours = self
            .path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.starts_with("lightamer-cli-test-"));
        if ours {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }
}

/// One JSONL line, serialized so paths never break quoting.
fn jsonl(id: &str, params: &serde_json::Value) -> String {
    format!("{}\n", serde_json::json!({"id": id, "params": params}))
}

fn run_cli(
    file: &Path,
    extra_args: &[&str],
    envs: &[(&str, &Path)],
) -> Result<std::process::Output, Box<dyn std::error::Error>> {
    let binary = PathBuf::from(env!("CARGO_BIN_EXE_lightamer-cli"));
    let mut command = Command::new(binary);
    command.arg("run").arg("--file").arg(file);
    for arg in extra_args {
        command.arg(arg);
    }
    for (key, value) in envs {
        command.env(key, value);
    }
    Ok(command.output()?)
}

#[test]
fn cli_run_session_file_end_to_end() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("run-session")?;
    let file = scratch.path().join("calls.jsonl");
    let parent = scratch.path().to_string_lossy().into_owned();
    let dest = scratch.path().join("vault").to_string_lossy().into_owned();
    let mut text = String::new();
    text.push_str(&jsonl(
        "session.new",
        &serde_json::json!({"name": "Demo", "parent": parent}),
    ));
    text.push_str(&jsonl("session.verify", &serde_json::json!({})));
    text.push_str(&jsonl("session.backup", &serde_json::json!({"dest": dest})));
    text.push_str(&jsonl("session.close", &serde_json::json!({})));
    std::fs::write(&file, text)?;
    let app_support = scratch.path().join("app-support");
    let output = run_cli(&file, &[], &[("LIGHTAMER_APP_SUPPORT_DIR", &app_support)])?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "exit failed: {stdout}");
    assert!(stdout.contains("session.new ok"), "{stdout}");
    assert!(stdout.contains("session.verify ok"), "{stdout}");
    assert!(stdout.contains("session.backup ok"), "{stdout}");
    assert!(stdout.contains("job 1 started"), "{stdout}");
    assert!(
        stdout.contains("finished success=true cancelled=false"),
        "{stdout}"
    );
    assert!(stdout.contains("session.close ok"), "{stdout}");
    assert!(scratch.path().join("vault/vault.lmsessiondb").is_file());
    Ok(())
}

fn bench_cli(
    args: &[String],
    envs: &[(&str, &str)],
) -> Result<std::process::Output, Box<dyn std::error::Error>> {
    let binary = PathBuf::from(env!("CARGO_BIN_EXE_lightamer-cli"));
    let mut command = Command::new(binary);
    command.arg("bench");
    for arg in args {
        command.arg(arg);
    }
    for (key, value) in envs {
        command.env(key, value);
    }
    Ok(command.output()?)
}

/// The session's photo uuids, sorted, read through catalog.
fn session_uuids(root: &Path) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let session = lightamer_catalog::open_session(root, "run-session-test")?;
    let mut uuids = lightamer_catalog::list_photo_uuids(session.connection())?;
    uuids.sort();
    lightamer_catalog::close_session(session)?;
    Ok(uuids)
}

#[test]
fn cli_run_rejects_photos_with_starters() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("run-photos")?;
    let file = scratch.path().join("starter.jsonl");
    std::fs::write(
        &file,
        jsonl("session.open", &serde_json::json!({"path": "/tmp/nowhere"})),
    )?;
    let output = run_cli(&file, &["--photos", "a,b"], &[])?;
    assert_eq!(output.status.code(), Some(2), "usage error, not a check");
    let combined = format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(combined.contains("--photos"), "{combined}");
    Ok(())
}

#[test]
fn cli_run_hold_and_template() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("run-hold")?;
    let file = scratch.path().join("hold.jsonl");
    let parent = scratch.path().to_string_lossy().into_owned();
    let mut text = String::new();
    text.push_str(&jsonl(
        "session.new",
        &serde_json::json!({"name": "Demo", "parent": parent}),
    ));
    text.push_str(&jsonl(
        "template.save",
        &serde_json::json!({"name": "Desk"}),
    ));
    std::fs::write(&file, text)?;
    let app_support = scratch.path().join("app-support");
    // No session.close line: the hold parks the session, then closes it.
    let output = run_cli(
        &file,
        &["--hold", "1"],
        &[("LIGHTAMER_APP_SUPPORT_DIR", &app_support)],
    )?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "exit failed: {stdout}");
    assert!(stdout.contains("template.save ok"), "{stdout}");
    assert!(stdout.contains("hold: keeping"), "{stdout}");
    assert!(stdout.contains("hold: closed"), "{stdout}");
    let saved = app_support.join("Desk.json");
    assert!(
        saved.is_file(),
        "template landed nowhere under {app_support:?}"
    );
    let text = std::fs::read_to_string(&saved)?;
    assert!(text.contains("\"template\""), "{text}");
    Ok(())
}

#[test]
fn cli_run_real_session_prints_watched_photos_per_line() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("run-watched")?;
    let parent = scratch.path().to_string_lossy().into_owned();
    let setup = bench_cli(
        &[
            "setup".to_owned(),
            "--parent".to_owned(),
            parent.clone(),
            "--name".to_owned(),
            "Shoot".to_owned(),
            "--photos".to_owned(),
            "2".to_owned(),
        ],
        &[],
    )?;
    assert!(setup.status.success(), "setup failed: {setup:?}");
    let root = scratch.path().join("Shoot");
    let uuids = session_uuids(&root)?;
    assert_eq!(uuids.len(), 2);
    let (a, b) = (uuids[0].clone(), uuids[1].clone());
    let short_a: String = a.chars().take(8).collect();
    let short_b: String = b.chars().take(8).collect();
    let file = scratch.path().join("watched.jsonl");
    let mut text = String::new();
    text.push_str(&jsonl(
        "session.open",
        &serde_json::json!({"path": root.to_string_lossy()}),
    ));
    text.push_str(&jsonl(
        "develop.set",
        &serde_json::json!({"ids": [a], "module": "rawprepare", "patch": {"p_gain": {"type": "float", "value": 1.5}}}),
    ));
    text.push_str(&jsonl(
        "develop.set",
        &serde_json::json!({"ids": ["00000000-0000-0000-0000-000000000000"], "module": "rawprepare", "patch": {}}),
    ));
    text.push_str(&jsonl("session.close", &serde_json::json!({})));
    std::fs::write(&file, text)?;
    let output = run_cli(&file, &[], &[])?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        !output.status.success(),
        "the unknown photo must fail a line: {stdout}"
    );
    let line1: Vec<&str> = stdout
        .lines()
        .filter(|line| line.starts_with("line 1: session.open"))
        .collect();
    let line2: Vec<&str> = stdout
        .lines()
        .filter(|line| line.starts_with("line 2: develop.set ok"))
        .collect();
    let line3: Vec<&str> = stdout
        .lines()
        .filter(|line| line.starts_with("line 3: develop.set FAIL"))
        .collect();
    assert_eq!(line1.len(), 1, "{stdout}");
    assert_eq!(line2.len(), 1, "{stdout}");
    assert_eq!(line3.len(), 1, "{stdout}");
    // The open line already prints the watched photo at step 0; the unnamed
    // photo never prints.
    assert!(line1[0].contains(&format!("{short_a}:1:0")), "{stdout}");
    assert!(!line1[0].contains(&short_b), "{stdout}");
    // After the set, the edited photo moved.
    assert!(line2[0].contains(&format!("{short_a}:2:1")), "{stdout}");
    // The unknown id prints as unknown, full-length ids never print.
    assert!(line3[0].contains("00000000:?:?"), "{stdout}");
    assert!(!stdout.contains(&a), "full uuid leaked: {stdout}");
    Ok(())
}

#[test]
fn cli_bench_setup_and_paste_end_to_end() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("bench-e2e")?;
    let parent = scratch.path().to_string_lossy().into_owned();
    let setup = bench_cli(
        &[
            "setup".to_owned(),
            "--parent".to_owned(),
            parent,
            "--name".to_owned(),
            "Shoot".to_owned(),
            "--photos".to_owned(),
            "4".to_owned(),
        ],
        &[],
    )?;
    let setup_out = String::from_utf8_lossy(&setup.stdout);
    assert!(setup.status.success(), "setup failed: {setup_out}");
    assert!(setup_out.contains("registered 4 photos"), "{setup_out}");
    let root = scratch.path().join("Shoot").to_string_lossy().into_owned();
    // Forced measuring: this logic holds under any load.
    let paste = bench_cli(
        &[
            "paste".to_owned(),
            "--session".to_owned(),
            root,
            "--photos".to_owned(),
            "2".to_owned(),
            "--runs".to_owned(),
            "2".to_owned(),
        ],
        &[(lightamer_cli::bench::BENCH_IGNORE_BUSY_ENV, "1")],
    )?;
    let paste_out = String::from_utf8_lossy(&paste.stdout);
    assert!(paste.status.success(), "paste failed: {paste_out}");
    assert!(paste_out.contains("round 1:"), "{paste_out}");
    assert!(paste_out.contains("round 2:"), "{paste_out}");
    assert!(paste_out.contains("events=2"), "{paste_out}");
    assert!(paste_out.contains("PASS"), "{paste_out}");
    Ok(())
}

#[test]
fn cli_closed_pipe_exits_quietly() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("broken-pipe")?;
    let file = scratch.path().join("big.jsonl");
    let mut text = String::with_capacity(20_000 * 46);
    for _ in 0..20_000 {
        text.push_str(&jsonl("develop.copy", &serde_json::json!({"id": "a"})));
    }
    std::fs::write(&file, text)?;
    let binary = PathBuf::from(env!("CARGO_BIN_EXE_lightamer-cli"));
    let run = |pipe: bool| -> Result<std::process::Output, Box<dyn std::error::Error>> {
        let mut command = std::process::Command::new(&binary);
        command
            .arg("run")
            .arg("--file")
            .arg(&file)
            .arg("--photos")
            .arg("a");
        if pipe {
            command
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped());
            let mut child = command.spawn()?;
            drop(child.stdout.take());
            Ok(child.wait_with_output()?)
        } else {
            Ok(command.output()?)
        }
    };
    // The full output dwarfs the pipe buffer, so closing the read end
    // faults every later write: the run below cannot pass vacuously.
    let full = run(false)?;
    assert!(full.status.success());
    assert!(full.stdout.len() > 65536, "output too small to fault");
    // Close the read end at once, read nothing: the writer must exit 0
    // with no panic on stderr.
    let cut = run(true)?;
    assert!(cut.status.success(), "status: {}", cut.status);
    let stderr = String::from_utf8_lossy(&cut.stderr);
    assert!(!stderr.contains("panicked"), "{stderr}");
    Ok(())
}
