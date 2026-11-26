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
