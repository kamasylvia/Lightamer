// SPDX-License-Identifier: GPL-3.0-or-later
//! Session jobs through `execute`: backup and restore return first and
//! report through events; the open scan marks missing files.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::cell::RefCell;
use std::rc::Rc;

use lightamer_engine::{Engine, Event, JobStatus};
use serde_json::{Value, json};

use common::{ScratchDir, drain_all, gate_pool};

/// Records every event the engine dispatches from here on.
fn recorder(engine: &mut Engine) -> Rc<RefCell<Vec<Event>>> {
    let seen: Rc<RefCell<Vec<Event>>> = Rc::new(RefCell::new(Vec::new()));
    let into = Rc::clone(&seen);
    engine.subscribe(Rc::new(move |event, _| {
        into.borrow_mut().push(event.clone());
    }));
    seen
}

/// The job an event belongs to, if it is a job event.
fn event_job(event: &Event) -> Option<u64> {
    match event {
        Event::PhotoChanged { .. } | Event::ClipboardChanged => None,
        Event::JobStarted { job }
        | Event::JobProgress { job, .. }
        | Event::JobFinished { job, .. } => Some(*job),
    }
}

/// One integer field of an outcome, or a boxed complaint naming it.
fn count(outcome: &Value, key: &str) -> Result<u64, Box<dyn std::error::Error>> {
    outcome
        .get(key)
        .and_then(Value::as_u64)
        .ok_or_else(|| format!("outcome lacks integer {key}: {outcome}").into())
}

fn write_tree(root: &std::path::Path, files: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    for relative in files {
        let path = root.join(relative);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, format!("contents of {relative}"))?;
    }
    Ok(())
}

#[test]
fn session_backup_returns_before_job_finishes() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-job")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let root = scratch.path().join("Studio");
    write_tree(
        &root,
        &[
            "Capture/a1.arw",
            "Selects/s1.arw",
            "Output/o1.jpg",
            "Trash/t1.arw",
            "Cache/Thumbs/junk.bin",
        ],
    )?;
    let seen = recorder(&mut engine);
    let gate = gate_pool(&mut engine);
    let dest = scratch.path().join("vault");
    let out = engine.execute("session.backup", &json!({"dest": dest.to_string_lossy()}))?;
    let job = count(&out, "job")?;
    // The command returned while the job never ran: still queued.
    let info = engine.job(job).ok_or("backup job missing from the table")?;
    assert!(matches!(info.status, JobStatus::Queued), "{info:?}");
    drop(gate);
    drain_all(&mut engine);
    let info = engine.job(job).ok_or("backup job left the table")?;
    assert!(
        matches!(info.status, JobStatus::Finished { cancelled: false }),
        "{info:?}"
    );
    // Progress arrives in order: start, one cumulative report per file, finish.
    let events: Vec<Event> = seen
        .borrow()
        .iter()
        .filter(|event| event_job(event) == Some(job))
        .cloned()
        .collect();
    assert_eq!(
        events,
        vec![
            Event::JobStarted { job },
            Event::JobProgress {
                job,
                done: 1,
                total: 0
            },
            Event::JobProgress {
                job,
                done: 2,
                total: 0
            },
            Event::JobProgress {
                job,
                done: 3,
                total: 0
            },
            Event::JobProgress {
                job,
                done: 4,
                total: 0
            },
            Event::JobFinished {
                job,
                success: true,
                cancelled: false
            },
        ],
        "{events:?}"
    );
    // The product is whole and opens directly.
    let check: String = rusqlite::Connection::open(dest.join("vault.lmsessiondb"))?.query_row(
        "PRAGMA integrity_check",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(check, "ok");
    for relative in [
        "Capture/a1.arw",
        "Selects/s1.arw",
        "Output/o1.jpg",
        "Trash/t1.arw",
    ] {
        assert!(dest.join(relative).is_file(), "missing {relative}");
    }
    assert!(!dest.join("Cache").exists(), "Cache must not travel");
    engine.execute("session.close", &json!({}))?;
    engine.execute("session.open", &json!({"path": dest.to_string_lossy()}))?;
    drain_all(&mut engine);
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_backup_cancel_before_start_removes_nothing_and_reports_cancelled()
-> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-early-cancel")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    write_tree(&scratch.path().join("Studio"), &["Capture/a1.arw"])?;
    let gate = gate_pool(&mut engine);
    let dest = scratch.path().join("vault");
    let out = engine.execute("session.backup", &json!({"dest": dest.to_string_lossy()}))?;
    let job = count(&out, "job")?;
    engine.execute("job.cancel", &json!({"job": job}))?;
    drop(gate);
    drain_all(&mut engine);
    let info = engine.job(job).ok_or("cancelled job left the table")?;
    assert!(
        matches!(info.status, JobStatus::Finished { cancelled: true }),
        "{info:?}"
    );
    assert!(!dest.exists(), "a job that never ran builds nothing");
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_backup_cancel_mid_run_removes_partial_dest() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-mid-cancel")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    // Twelve hundred files take tens of milliseconds to duplicate; the
    // cancel below lands microseconds after the spawn, so the job always
    // observes it mid-run (or before starting — both report cancelled and
    // both remove the destination).
    let mut files = Vec::new();
    for index in 0..1200 {
        files.push(format!("Capture/f{index:04}.arw"));
    }
    let refs: Vec<&str> = files.iter().map(String::as_str).collect();
    write_tree(&scratch.path().join("Studio"), &refs)?;
    let dest = scratch.path().join("vault");
    let out = engine.execute("session.backup", &json!({"dest": dest.to_string_lossy()}))?;
    let job = count(&out, "job")?;
    engine.execute("job.cancel", &json!({"job": job}))?;
    drain_all(&mut engine);
    let info = engine.job(job).ok_or("cancelled job left the table")?;
    assert!(
        matches!(info.status, JobStatus::Finished { cancelled: true }),
        "{info:?}"
    );
    assert!(!dest.exists(), "a cancelled backup leaves no destination");
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_backup_refuses_busy_dest_without_spawning() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-busy")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let busy = scratch.path().join("busy");
    std::fs::create_dir(&busy)?;
    std::fs::write(busy.join("someone.txt"), "held")?;
    let err = engine
        .execute("session.backup", &json!({"dest": busy.to_string_lossy()}))
        .expect_err("busy dest");
    assert!(err.to_string().contains("non-empty"), "{err}");
    assert!(engine.jobs().is_empty(), "a refused backup spawns no job");
    assert_eq!(std::fs::read(busy.join("someone.txt"))?, b"held");
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_restore_duplicates_and_opens() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("restore-job")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let root = scratch.path().join("Studio");
    write_tree(&root, &["Capture/a1.arw", "Trash/t1.arw"])?;
    rusqlite::Connection::open(root.join("Studio.lmsessiondb"))?.execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash) VALUES ('u1', 'Capture/a1.arw', 0, 'a1.arw', 1, 'h')",
        [],
    )?;
    let vault = scratch.path().join("vault");
    engine.execute("session.backup", &json!({"dest": vault.to_string_lossy()}))?;
    drain_all(&mut engine);
    engine.execute("session.close", &json!({}))?;

    let seen = recorder(&mut engine);
    let back = scratch.path().join("Studio-again");
    let out = engine.execute(
        "session.restore",
        &json!({"backup": vault.to_string_lossy(), "dest": back.to_string_lossy()}),
    )?;
    let job = count(&out, "job")?;
    assert!(!engine.has_session(), "restore returns before it opens");
    drain_all(&mut engine);
    assert!(engine.has_real_session(), "the restored session opens");
    assert_eq!(engine.session_root(), Some(back.as_path()));
    let photos: i64 = rusqlite::Connection::open(back.join("Studio-again.lmsessiondb"))?
        .query_row("SELECT COUNT(*) FROM photos", [], |row| row.get(0))?;
    assert_eq!(photos, 1);
    // The restore job reported progress and success; the open scan followed.
    let events: Vec<Event> = seen
        .borrow()
        .iter()
        .filter(|event| event_job(event) == Some(job))
        .cloned()
        .collect();
    assert!(
        events.iter().any(|event| matches!(
            event,
            Event::JobProgress { done, .. } if *done > 0
        )),
        "no restore progress: {events:?}"
    );
    assert!(
        events.contains(&Event::JobFinished {
            job,
            success: true,
            cancelled: false
        }),
        "{events:?}"
    );
    assert!(
        engine.jobs().iter().any(|info| info.kind == "session.scan"
            && matches!(info.status, JobStatus::Finished { cancelled: false })),
        "the restored session scans like any opened one"
    );
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_restore_cancel_removes_dest_and_opens_nothing() -> Result<(), Box<dyn std::error::Error>>
{
    let scratch = ScratchDir::new("restore-cancel")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    write_tree(&scratch.path().join("Studio"), &["Capture/a1.arw"])?;
    let vault = scratch.path().join("vault");
    engine.execute("session.backup", &json!({"dest": vault.to_string_lossy()}))?;
    drain_all(&mut engine);
    engine.execute("session.close", &json!({}))?;

    let gate = gate_pool(&mut engine);
    let back = scratch.path().join("Studio-again");
    let out = engine.execute(
        "session.restore",
        &json!({"backup": vault.to_string_lossy(), "dest": back.to_string_lossy()}),
    )?;
    let job = count(&out, "job")?;
    engine.execute("job.cancel", &json!({"job": job}))?;
    drop(gate);
    drain_all(&mut engine);
    let info = engine.job(job).ok_or("cancelled job left the table")?;
    assert!(
        matches!(info.status, JobStatus::Finished { cancelled: true }),
        "{info:?}"
    );
    assert!(!back.exists(), "a cancelled restore leaves no destination");
    assert!(!engine.has_session());
    Ok(())
}

#[test]
fn session_restore_refuses_bad_source_without_spawning() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("restore-bad")?;
    let empty = scratch.path().join("empty");
    std::fs::create_dir(&empty)?;
    let mut engine = Engine::new();
    let dest = scratch.path().join("nowhere");
    let err = engine
        .execute(
            "session.restore",
            &json!({"backup": empty.to_string_lossy(), "dest": dest.to_string_lossy()}),
        )
        .expect_err("bad source");
    assert_ne!(err.to_string(), "");
    assert!(engine.jobs().is_empty(), "a refused restore spawns no job");
    assert!(!dest.exists());
    Ok(())
}

#[test]
fn session_open_scans_missing_files_as_job() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("open-scan")?;
    let root = scratch.path().join("Studio");
    let setup = lightamer_catalog::create_session(scratch.path(), "Studio", "test")?;
    std::fs::write(root.join("Capture/kept.arw"), "raw")?;
    let outside = scratch.path().join("outside.arw");
    std::fs::write(&outside, "raw")?;
    setup.connection().execute(
        "INSERT INTO snapshots (hash, json) VALUES ('h1', '{\"process\": 1}')",
        [],
    )?;
    for (uuid, path, kind, missing) in [
        ("uuid-kept", "Capture/kept.arw".to_owned(), 0, 0),
        ("uuid-gone", "Capture/gone.arw".to_owned(), 0, 0),
        ("uuid-back", outside.to_string_lossy().into_owned(), 1, 1),
    ] {
        setup.connection().execute(
            "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash, missing) VALUES (?1, ?2, ?3, 'f.arw', 1, 'h1', ?4)",
            rusqlite::params![uuid, path, kind, missing],
        )?;
    }
    lightamer_catalog::close_session(setup)?;

    let mut engine = Engine::new();
    let seen = recorder(&mut engine);
    let gate = gate_pool(&mut engine);
    let out = engine.execute("session.open", &json!({"path": root.to_string_lossy()}))?;
    let job = count(&out, "job")?;
    // Open returns at once: the scan waits behind the gate.
    let info = engine.job(job).ok_or("scan job missing from the table")?;
    assert!(matches!(info.status, JobStatus::Queued), "{info:?}");
    assert_eq!(info.kind, "session.scan");
    drop(gate);
    drain_all(&mut engine);
    let info = engine.job(job).ok_or("scan job left the table")?;
    assert!(
        matches!(info.status, JobStatus::Finished { cancelled: false }),
        "{info:?}"
    );
    let events: Vec<Event> = seen
        .borrow()
        .iter()
        .filter(|event| event_job(event) == Some(job))
        .cloned()
        .collect();
    assert!(
        events
            .iter()
            .any(|event| matches!(event, Event::JobProgress { .. })),
        "no scan progress: {events:?}"
    );
    let check = rusqlite::Connection::open(root.join("Studio.lmsessiondb"))?;
    for (uuid, want) in [("uuid-kept", 0), ("uuid-gone", 1), ("uuid-back", 0)] {
        let missing: i64 = check.query_row(
            "SELECT missing FROM photos WHERE uuid = ?1",
            rusqlite::params![uuid],
            |row| row.get(0),
        )?;
        assert_eq!(missing, want, "{uuid} mis-marked");
    }
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn restore_delivery_closes_when_session_opened_meantime() -> Result<(), Box<dyn std::error::Error>>
{
    let scratch = ScratchDir::new("restore-race")?;
    let src = lightamer_catalog::create_session(scratch.path(), "Src", "test")?;
    let src_root = src.root().to_path_buf();
    std::fs::write(src_root.join("Capture/a1.arw"), "raw")?;
    lightamer_catalog::close_session(src)?;
    let vault = scratch.path().join("vault");
    lightamer_catalog::backup_session(&src_root, &vault, true, &|_| {}, &|| false)?;

    let mut engine = Engine::new();
    let gate = gate_pool(&mut engine);
    let back = scratch.path().join("Restored");
    engine.execute(
        "session.restore",
        &json!({"backup": vault.to_string_lossy(), "dest": back.to_string_lossy()}),
    )?;
    // A session opens while the restore still waits: the delivery must not
    // clobber it when it lands.
    engine.execute(
        "session.new",
        &json!({"name": "Live", "parent": scratch.path().to_string_lossy()}),
    )?;
    drop(gate);
    drain_all(&mut engine);
    assert_eq!(
        engine.session_root(),
        Some(scratch.path().join("Live").as_path())
    );
    // The delivered session was closed, not stranded: its lock is free.
    let mut other = Engine::new();
    other.execute("session.open", &json!({"path": back.to_string_lossy()}))?;
    drain_all(&mut other);
    other.execute("session.close", &json!({}))?;
    engine.execute("session.close", &json!({}))?;
    Ok(())
}
#[test]
fn session_restore_fails_clean_on_unreadable_backup() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("restore-garbage")?;
    // A "backup" whose database file is garbage: the duplication half fails.
    let vault = scratch.path().join("vault");
    std::fs::create_dir_all(vault.join("Capture"))?;
    std::fs::write(vault.join("vault.lmsessiondb"), "not a database")?;
    let mut engine = Engine::new();
    let back = scratch.path().join("Studio-again");
    let out = engine.execute(
        "session.restore",
        &json!({"backup": vault.to_string_lossy(), "dest": back.to_string_lossy()}),
    )?;
    let job = count(&out, "job")?;
    drain_all(&mut engine);
    let info = engine.job(job).ok_or("failed job left the table")?;
    assert!(matches!(info.status, JobStatus::Failed(_)), "{info:?}");
    assert!(!back.exists(), "a failed restore leaves no destination");
    assert!(!engine.has_session());
    Ok(())
}

#[test]
fn session_restore_fails_clean_when_open_refuses() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("restore-toonew")?;
    // A backup whose database the open half refuses (schema 999): the
    // duplication half succeeds, then the destination is removed again.
    let setup = lightamer_catalog::create_session(scratch.path(), "Src", "test")?;
    let src_db = setup.db_path().to_path_buf();
    lightamer_catalog::close_session(setup)?;
    rusqlite::Connection::open(&src_db)?.execute("PRAGMA user_version = 999", [])?;
    let mut engine = Engine::new();
    let back = scratch.path().join("Studio-again");
    let out = engine.execute(
        "session.restore",
        &json!({
            "backup": scratch.path().join("Src").to_string_lossy(),
            "dest": back.to_string_lossy()
        }),
    )?;
    let job = count(&out, "job")?;
    drain_all(&mut engine);
    let info = engine.job(job).ok_or("failed job left the table")?;
    assert!(matches!(info.status, JobStatus::Failed(_)), "{info:?}");
    assert!(!back.exists(), "a refused open removes the destination");
    assert!(!engine.has_session());
    Ok(())
}
