// SPDX-License-Identifier: GPL-3.0-or-later
//! Crash semantics: a killed child keeps exactly its committed steps, and
//! an uncommitted transaction comes back as if it never ran.

mod common;

use std::process::Stdio;

use lightamer_catalog::{
    HistoryWriter, close_session, create_session, open_session, read_history, register_photo,
};

use common::{ScratchDir, settings_json};

/// When set, this test binary runs as the kill child: it opens the session
/// at the value, pushes history, signals readiness, and sleeps until it is
/// killed. Only the test's own binary is ever spawned. The value selects
/// the shape: `<root>:commit` (push three steps and commit) or
/// `<root>:open` (push two steps and hold the transaction open).
const KILL_CHILD_ENV: &str = "LIGHTAMER_CATALOG_HISTORY_KILL_CHILD";

/// Spawns this test binary as the kill child for `test`, waits for the
/// ready file, kills it, and returns.
fn run_killed_child(
    test: &str,
    root: &std::path::Path,
    shape: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let binary = std::env::current_exe()?;
    let mut child = std::process::Command::new(binary)
        .arg("--exact")
        .arg(test)
        .env(
            KILL_CHILD_ENV,
            format!("{}:{shape}", root.to_string_lossy()),
        )
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let ready = root.join("history-kill-ready");
    let mut waited = 0;
    while !ready.exists() && waited < 300 {
        std::thread::sleep(std::time::Duration::from_millis(100));
        waited += 1;
    }
    assert!(ready.exists(), "kill child never signaled ready");
    child.kill()?;
    child.wait()?;
    Ok(())
}

#[test]
fn killed_after_commit_keeps_exactly_committed_steps() -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(shape) = std::env::var(KILL_CHILD_ENV) {
        return kill_child_main(&shape);
    }
    let scratch = ScratchDir::new("crash-commit")?;
    let root = scratch.path().join("Shoot");
    let setup = create_session(scratch.path(), "Shoot", "crash-parent")?;
    close_session(setup)?;

    run_killed_child(
        "killed_after_commit_keeps_exactly_committed_steps",
        &root,
        "commit",
    )?;

    let session = open_session(&root, "crash-parent")?;
    let read = read_history(session.connection(), 1)?;
    let labels: Vec<&str> = read.steps.iter().map(|step| step.label.as_str()).collect();
    assert_eq!(
        labels,
        vec!["import", "develop.set", "develop.set", "develop.set"]
    );
    assert_eq!(read.cursor, 3);
    let snapshots: i64 =
        session
            .connection()
            .query_row("SELECT COUNT(*) FROM snapshots", [], |row| row.get(0))?;
    assert_eq!(snapshots, 4);
    close_session(session)?;
    Ok(())
}

#[test]
fn killed_before_commit_loses_the_open_transaction() -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(shape) = std::env::var(KILL_CHILD_ENV) {
        return kill_child_main(&shape);
    }
    let scratch = ScratchDir::new("crash-open")?;
    let root = scratch.path().join("Shoot");
    let setup = create_session(scratch.path(), "Shoot", "crash-parent")?;
    close_session(setup)?;

    run_killed_child(
        "killed_before_commit_loses_the_open_transaction",
        &root,
        "open",
    )?;

    let session = open_session(&root, "crash-parent")?;
    // The registration committed, so the photo is there; the two pushed
    // steps never committed, so only the initial step is.
    let read = read_history(session.connection(), 1)?;
    let labels: Vec<&str> = read.steps.iter().map(|step| step.label.as_str()).collect();
    assert_eq!(labels, vec!["import"]);
    assert_eq!(read.cursor, 0);
    let snapshots: i64 =
        session
            .connection()
            .query_row("SELECT COUNT(*) FROM snapshots", [], |row| row.get(0))?;
    assert_eq!(snapshots, 1);
    close_session(session)?;
    Ok(())
}

/// The kill child: registers one photo (id 1 on the fresh session), then
/// either commits three pushed steps (`commit`) or pushes two and holds
/// the transaction open (`open`). Signals readiness, then sleeps until the
/// parent kills it.
fn kill_child_main(shape: &str) -> Result<(), Box<dyn std::error::Error>> {
    let (root, mode) = shape
        .rsplit_once(':')
        .ok_or("kill child shape has no mode")?;
    let root = std::path::Path::new(root);
    let mut session = open_session(root, "crash-child")?;
    let record = register_photo(
        session.connection_mut(),
        root,
        &root.join("Capture").join("a.arw"),
        "a.arw",
        None,
    )?;
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    let pushes: i64 = if mode == "commit" { 3 } else { 2 };
    for number in 1..=pushes {
        let json = settings_json("exposure", "ev", number)?;
        writer.push(record.id, "develop.set", &json)?;
    }
    if mode == "commit" {
        writer.commit()?;
    }
    std::fs::write(root.join("history-kill-ready"), b"ready")?;
    for _ in 0..600 {
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
    Ok(())
}
