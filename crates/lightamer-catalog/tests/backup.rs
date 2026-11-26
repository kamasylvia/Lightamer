// SPDX-License-Identifier: GPL-3.0-or-later
//! Whole-package backup and restore: contents, refusal, cancellation.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
mod common;

use lightamer_catalog::{
    CatalogError, backup_session, check_empty_dest, close_session, create_session, open_session,
    restore_package,
};
use std::cell::{Cell, RefCell};
use std::sync::atomic::{AtomicBool, Ordering};

use common::ScratchDir;

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

fn db_row_counts(db: &std::path::Path) -> Result<Vec<(String, i64)>, Box<dyn std::error::Error>> {
    let conn = rusqlite::Connection::open(db)?;
    let tables = [
        "_meta",
        "photos",
        "snapshots",
        "history_steps",
        "keywords",
        "photo_keywords",
        "albums",
        "album_photos",
        "favorites",
    ];
    let mut out = Vec::new();
    for table in tables {
        let count: i64 = conn.query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })?;
        out.push((table.to_owned(), count));
    }
    Ok(out)
}

#[test]
fn backup_duplicates_package_and_opens_directly() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-ok")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    let root = session.root().to_path_buf();
    write_tree(
        &root,
        &[
            "Capture/a1.arw",
            "Capture/nested/a2.arw",
            "Selects/pick.arw",
            "Output/print.jpg",
            "Trash/gone.arw",
            "Cache/Thumbs/junk.bin",
        ],
    )?;
    // One committed row still sitting in the WAL must land in the backup.
    session.connection().execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash) VALUES (?1, ?2, 0, ?3, 1, ?4)",
        rusqlite::params!["uuid-1", "Capture/a1.arw", "a1.arw", "h1"],
    )?;
    let dest = scratch.path().join("Studio-backup");
    let progress: RefCell<Vec<u64>> = RefCell::new(Vec::new());
    let stats = backup_session(
        &root,
        &dest,
        true,
        &|done| progress.borrow_mut().push(done),
        &|| false,
    )?;
    assert_eq!(stats.files, 5, "four dirs, Cache excluded: {stats:?}");
    assert!(stats.bytes > 0);
    assert_eq!(
        *progress.borrow(),
        vec![1, 2, 3, 4, 5],
        "one report per file, cumulative"
    );
    for relative in [
        "Studio-backup.lmsessiondb",
        "Capture/a1.arw",
        "Capture/nested/a2.arw",
        "Selects/pick.arw",
        "Output/print.jpg",
        "Trash/gone.arw",
        "Capture",
        "Selects",
        "Output",
        "Trash",
    ] {
        assert!(dest.join(relative).exists(), "missing {relative}");
    }
    assert!(!dest.join("Cache").exists(), "Cache must not travel");
    assert!(!dest.join("session.lock").exists(), "no lock file travels");
    let check: String = rusqlite::Connection::open(dest.join("Studio-backup.lmsessiondb"))?
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))?;
    assert_eq!(check, "ok");
    assert_eq!(
        db_row_counts(session.db_path())?,
        db_row_counts(&dest.join("Studio-backup.lmsessiondb"))?,
        "every table travels whole"
    );
    // The product opens directly as a session (under its own name).
    let reopened = open_session(&dest, "test")?;
    assert_eq!(
        db_row_counts(&dest.join("Studio-backup.lmsessiondb"))?.len(),
        9
    );
    close_session(reopened)?;
    drop(session);
    Ok(())
}

#[test]
fn backup_skips_trash_when_asked() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-notrash")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    let root = session.root().to_path_buf();
    write_tree(&root, &["Capture/a1.arw", "Trash/gone.arw"])?;
    let dest = scratch.path().join("slim");
    let stats = backup_session(&root, &dest, false, &|_| {}, &|| false)?;
    assert_eq!(stats.files, 1);
    assert!(dest.join("Trash").is_dir(), "the shape keeps four dirs");
    assert!(
        std::fs::read_dir(dest.join("Trash"))?.next().is_none(),
        "Trash travels empty"
    );
    assert!(dest.join("Capture/a1.arw").is_file());
    drop(session);
    Ok(())
}

#[test]
fn backup_refuses_nonempty_dest_and_touches_nothing() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-refuse")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    let root = session.root().to_path_buf();
    write_tree(&root, &["Capture/a1.arw"])?;
    let busy = scratch.path().join("busy");
    write_tree(&busy, &["someone.txt"])?;
    let before = common::relative_file_list(&busy)?;
    let err = backup_session(&root, &busy, true, &|_| {}, &|| false).expect_err("busy dest");
    assert!(matches!(err, CatalogError::NotEmpty(_)), "{err}");
    assert_eq!(
        common::relative_file_list(&busy)?,
        before,
        "refused means untouched"
    );
    assert!(matches!(
        check_empty_dest(&busy).expect_err("busy"),
        CatalogError::NotEmpty(_)
    ));
    // A destination that is a file, and a destination inside the source.
    let file_dest = scratch.path().join("afile");
    std::fs::write(&file_dest, "x")?;
    assert!(matches!(
        check_empty_dest(&file_dest).expect_err("file"),
        CatalogError::NotEmpty(_)
    ));
    let inside = root.join("Capture").join("nested-backup");
    let err = backup_session(&root, &inside, true, &|_| {}, &|| false).expect_err("inside");
    assert!(matches!(err, CatalogError::BadPath(_)), "{err}");
    assert!(!inside.exists());
    drop(session);
    Ok(())
}

#[test]
fn backup_cancelled_mid_run_removes_dest() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup-cancel")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    let root = session.root().to_path_buf();
    let mut files = Vec::new();
    for index in 0..300 {
        files.push(format!("Capture/f{index:04}.arw"));
    }
    let refs: Vec<&str> = files.iter().map(String::as_str).collect();
    write_tree(&root, &refs)?;
    // Cancel deterministically after five files (no timing involved).
    let stop = AtomicBool::new(false);
    let dest = scratch.path().join("half");
    let err = backup_session(
        &root,
        &dest,
        true,
        &|done| {
            if done >= 5 {
                stop.store(true, Ordering::SeqCst);
            }
        },
        &|| stop.load(Ordering::SeqCst),
    )
    .expect_err("cancelled");
    assert!(matches!(err, CatalogError::Cancelled), "{err}");
    assert!(!dest.exists(), "a created root is removed on cancel");
    // A pre-existing empty root survives as an empty root.
    let given = scratch.path().join("given");
    std::fs::create_dir(&given)?;
    stop.store(false, Ordering::SeqCst);
    let err = backup_session(
        &root,
        &given,
        true,
        &|done| {
            if done >= 5 {
                stop.store(true, Ordering::SeqCst);
            }
        },
        &|| stop.load(Ordering::SeqCst),
    )
    .expect_err("cancelled again");
    assert!(matches!(err, CatalogError::Cancelled), "{err}");
    assert!(given.is_dir());
    assert!(
        std::fs::read_dir(&given)?.next().is_none(),
        "only our own children are removed"
    );
    drop(session);
    Ok(())
}

#[test]
fn restore_brings_package_back_and_opens() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("restore-ok")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    let root = session.root().to_path_buf();
    write_tree(&root, &["Capture/a1.arw", "Trash/gone.arw"])?;
    session.connection().execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash) VALUES (?1, ?2, 0, ?3, 1, ?4)",
        rusqlite::params!["uuid-1", "Capture/a1.arw", "a1.arw", "h1"],
    )?;
    let backup = scratch.path().join("vault");
    backup_session(&root, &backup, true, &|_| {}, &|| false)?;
    drop(session);
    let back = scratch.path().join("Studio-again");
    let progress = Cell::new(0);
    let stats = restore_package(&backup, &back, &|done| progress.set(done), &|| false)?;
    assert_eq!(stats.files, 2);
    assert_eq!(progress.get(), 2);
    assert!(back.join("Studio-again.lmsessiondb").is_file());
    assert!(back.join("Capture/a1.arw").is_file());
    assert!(back.join("Trash/gone.arw").is_file());
    let reopened = open_session(&back, "test")?;
    let photos: i64 =
        reopened
            .connection()
            .query_row("SELECT COUNT(*) FROM photos", [], |row| row.get(0))?;
    assert_eq!(photos, 1);
    close_session(reopened)?;
    Ok(())
}

#[test]
fn restore_refuses_a_source_without_a_database() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("restore-refuse")?;
    let empty = scratch.path().join("empty");
    std::fs::create_dir(&empty)?;
    let dest = scratch.path().join("nowhere");
    let err = restore_package(&empty, &dest, &|_| {}, &|| false).expect_err("no database");
    assert!(
        matches!(err, CatalogError::Missing(_) | CatalogError::BadPath(_)),
        "{err}"
    );
    assert!(!dest.exists(), "a refused restore touches nothing");
    Ok(())
}
