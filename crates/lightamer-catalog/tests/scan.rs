// SPDX-License-Identifier: GPL-3.0-or-later
//! The missing-file scan: marks gone files, unmarks returned ones, stops.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
mod common;

use lightamer_catalog::{CatalogError, create_session, scan_missing};
use std::cell::RefCell;

use common::ScratchDir;

fn insert_photo(
    conn: &rusqlite::Connection,
    uuid: &str,
    path: &str,
    kind: i64,
    missing: i64,
) -> rusqlite::Result<usize> {
    conn.execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash, missing) VALUES (?1, ?2, ?3, ?4, 1, 'h1', ?5)",
        rusqlite::params![uuid, path, kind, "frame.arw", missing],
    )
}

fn missing_of(session: &lightamer_catalog::Session, uuid: &str) -> i64 {
    session
        .connection()
        .query_row(
            "SELECT missing FROM photos WHERE uuid = ?1",
            rusqlite::params![uuid],
            |row| row.get(0),
        )
        .expect("row present")
}

#[test]
fn scan_marks_missing_and_unmarks_returned() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("scan-marks")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    session.connection().execute(
        "INSERT INTO snapshots (hash, json) VALUES ('h1', '{\"process\": 1}')",
        [],
    )?;
    std::fs::write(session.root().join("Capture/kept.arw"), "raw")?;
    let outside = scratch.path().join("outside.arw");
    std::fs::write(&outside, "raw")?;
    insert_photo(session.connection(), "uuid-kept", "Capture/kept.arw", 0, 0)?;
    insert_photo(session.connection(), "uuid-gone", "Capture/gone.arw", 0, 0)?;
    insert_photo(
        session.connection(),
        "uuid-back",
        &outside.to_string_lossy(),
        1,
        1,
    )?;
    let progress: RefCell<Vec<u64>> = RefCell::new(Vec::new());
    let stats = scan_missing(
        session.db_path(),
        session.root(),
        &|done| progress.borrow_mut().push(done),
        &|| false,
    )?;
    assert_eq!(stats.checked, 3);
    assert_eq!(stats.marked_missing, 1);
    assert_eq!(stats.unmarked, 1);
    assert_eq!(
        progress.borrow().last().copied(),
        Some(3),
        "the final report lands"
    );
    assert_eq!(missing_of(&session, "uuid-kept"), 0);
    assert_eq!(missing_of(&session, "uuid-gone"), 1);
    assert_eq!(missing_of(&session, "uuid-back"), 0);
    drop(session);
    Ok(())
}

#[test]
fn scan_cancel_stops_early_and_keeps_partial_marks() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("scan-cancel")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    session.connection().execute(
        "INSERT INTO snapshots (hash, json) VALUES ('h1', '{\"process\": 1}')",
        [],
    )?;
    for index in 0..200 {
        insert_photo(
            session.connection(),
            &format!("uuid-{index}"),
            &format!("Capture/f{index}.arw"),
            0,
            0,
        )?;
    }
    // Cancel deterministically after exactly one row: the predicate trips on
    // its second call (no timing involved, no progress throttle involved).
    let calls = std::cell::Cell::new(0);
    let err = scan_missing(session.db_path(), session.root(), &|_| {}, &|| {
        calls.set(calls.get() + 1);
        calls.get() > 1
    })
    .expect_err("cancelled");
    assert!(matches!(err, CatalogError::Cancelled), "{err}");
    let marked: i64 = session.connection().query_row(
        "SELECT COUNT(*) FROM photos WHERE missing = 1",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(marked, 1, "the one finished row keeps its mark");
    drop(session);
    Ok(())
}
