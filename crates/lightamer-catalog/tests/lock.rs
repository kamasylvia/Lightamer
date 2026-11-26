// SPDX-License-Identifier: GPL-3.0-or-later
//! The single-writer lock: second opener refused, hint-only owner note,
//! reopen after a kill.

mod common;

use std::process::Stdio;

use lightamer_catalog::{CatalogError, LockOwner, close_session, create_session, open_session};

use common::ScratchDir;

/// When set, this test binary runs as the kill child: it opens the session
/// at the value, commits one row, signals readiness, and sleeps until it is
/// killed. Only the test's own binary is ever spawned.
const KILL_CHILD_ENV: &str = "LIGHTAMER_CATALOG_KILL_CHILD";

#[test]
fn second_opener_gets_in_use_with_owner() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("inuse")?;
    let root = scratch.path().join("Shoot");
    let first = create_session(scratch.path(), "Shoot", "holder-prog")?;

    let Err(err) = open_session(&root, "second-prog") else {
        return Err("second open was accepted".into());
    };
    let CatalogError::InUse { owner, .. } = err else {
        return Err(format!("expected InUse, got {err}").into());
    };
    let Some(owner) = owner else {
        return Err("InUse carried no owner note".into());
    };
    assert_eq!(owner.pid, std::process::id());
    assert_eq!(owner.program, "holder-prog");
    assert!(owner.describe().contains("holder-prog"));

    close_session(first)?;
    let second = open_session(&root, "second-prog")?;
    close_session(second)?;
    Ok(())
}

#[test]
fn owner_note_carries_a_nonempty_host_on_this_machine() {
    let owner = LockOwner::this_process("probe");
    assert!(
        !owner.host.trim().is_empty(),
        "the holder hint must name this computer"
    );
    assert!(owner.describe().contains("process"), "{}", owner.describe());
}

#[test]
fn missing_or_corrupt_owner_note_still_opens() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("ownerhint")?;
    let root = scratch.path().join("Shoot");
    let first = create_session(scratch.path(), "Shoot", "holder-prog")?;
    let note = root.join("session.lock.owner");

    std::fs::remove_file(&note)?;
    let Err(err) = open_session(&root, "second-prog") else {
        return Err("second open was accepted".into());
    };
    assert!(
        matches!(err, CatalogError::InUse { owner: None, .. }),
        "missing note: expected InUse without owner, got {err}"
    );

    std::fs::write(&note, b"{{{ not json")?;
    let Err(err) = open_session(&root, "second-prog") else {
        return Err("second open was accepted".into());
    };
    assert!(
        matches!(err, CatalogError::InUse { owner: None, .. }),
        "corrupt note: expected InUse without owner, got {err}"
    );
    close_session(first)?;

    // A stale corrupt note never blocks a fresh open; it is overwritten.
    std::fs::write(&note, b"{{{ not json")?;
    let second = open_session(&root, "second-prog")?;
    let bytes = std::fs::read(&note)?;
    assert_ne!(bytes, b"{{{ not json}");
    assert!(String::from_utf8(bytes)?.contains("second-prog"));
    close_session(second)?;
    Ok(())
}

#[test]
fn reopen_after_kill() -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(root) = std::env::var(KILL_CHILD_ENV) {
        return kill_child_main(root.as_ref());
    }
    let scratch = ScratchDir::new("kill")?;
    let root = scratch.path().join("Shoot");
    let setup = create_session(scratch.path(), "Shoot", "kill-parent")?;
    close_session(setup)?;

    let binary = std::env::current_exe()?;
    let mut child = std::process::Command::new(binary)
        .arg("--exact")
        .arg("reopen_after_kill")
        .env(KILL_CHILD_ENV, &root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let ready = root.join("kill-ready");
    let mut waited = 0;
    while !ready.exists() && waited < 300 {
        std::thread::sleep(std::time::Duration::from_millis(100));
        waited += 1;
    }
    assert!(ready.exists(), "kill child never signaled ready");
    child.kill()?;
    child.wait()?;

    let session = open_session(&root, "kill-parent")?;
    let count: i64 = session.connection().query_row(
        "SELECT COUNT(*) FROM keywords WHERE name = 'kill-child-row'",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(count, 1, "child's committed row did not survive the kill");
    close_session(session)?;
    Ok(())
}

/// The kill child: opens the session the parent prepared, commits one row,
/// signals readiness, then sleeps until the parent kills it.
fn kill_child_main(root: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let session = open_session(root, "kill-child")?;
    session
        .connection()
        .execute("INSERT INTO keywords (name) VALUES ('kill-child-row')", [])?;
    std::fs::write(root.join("kill-ready"), b"ready")?;
    for _ in 0..600 {
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
    close_session(session)?;
    Ok(())
}
