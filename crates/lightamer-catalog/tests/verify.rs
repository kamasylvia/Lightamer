// SPDX-License-Identifier: GPL-3.0-or-later
//! Read-only verification: healthy silence, broken rows reported, bytes kept.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
mod common;

use lightamer_catalog::{
    Finding, Severity, VERIFY_INLINE_PATH_LIMIT, create_session, display_aux_write, verify_session,
};

use common::ScratchDir;

fn insert_snapshot(conn: &rusqlite::Connection, hash: &str, json: &str) -> rusqlite::Result<usize> {
    conn.execute(
        "INSERT INTO snapshots (hash, json) VALUES (?1, ?2)",
        rusqlite::params![hash, json],
    )
}

fn insert_photo(
    conn: &rusqlite::Connection,
    uuid: &str,
    path: &str,
    kind: i64,
    hash: &str,
    process: i64,
    cursor: i64,
) -> rusqlite::Result<usize> {
    conn.execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash, process, cursor) VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6, ?7)",
        rusqlite::params![uuid, path, kind, "frame.arw", hash, process, cursor],
    )
}

fn finding_codes(findings: &[Finding]) -> Vec<&str> {
    let mut codes: Vec<&str> = findings.iter().map(|finding| finding.code).collect();
    codes.sort_unstable();
    codes.dedup();
    codes
}

#[test]
fn verify_healthy_session_reports_nothing() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-quiet")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    insert_snapshot(session.connection(), "h1", "{\"process\": 1}")?;
    insert_photo(
        session.connection(),
        "uuid-1",
        "Capture/a1.arw",
        0,
        "h1",
        1,
        0,
    )?;
    session.connection().execute(
        "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) VALUES (1, 0, 'import', 'h1', 1)",
        [],
    )?;
    std::fs::write(session.root().join("Capture/a1.arw"), "raw")?;
    let report = verify_session(session.connection(), session.root(), false)?;
    assert!(report.findings.is_empty(), "{:?}", report.findings);
    drop(session);
    Ok(())
}

#[test]
fn verify_reports_each_planted_problem() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-noisy")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    let conn = session.connection();
    insert_snapshot(conn, "h-orphan", "{\"process\": 1}")?;
    insert_snapshot(conn, "h-current", "{\"process\": 2}")?;
    insert_snapshot(conn, "h-step", "{\"process\": 1}")?;
    // Mirror says 1 but the snapshot says 2; the cursor overshoots the steps;
    // the file is absent from disk.
    insert_photo(conn, "uuid-1", "Capture/gone.arw", 0, "h-current", 1, 5)?;
    conn.execute(
        "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) VALUES (1, 0, 'import', 'h-step', 1)",
        [],
    )?;
    conn.execute(
        "INSERT INTO albums (name, kind, created_at) VALUES ('Picks', 'album', 1)",
        [],
    )?;
    conn.execute("INSERT INTO keywords (name) VALUES ('desert')", [])?;
    display_aux_write(conn, "{not json")?;
    // Dangling rows need foreign keys off (the session runs with them on).
    {
        let raw = rusqlite::Connection::open(session.db_path())?;
        raw.execute("PRAGMA foreign_keys = OFF", [])?;
        raw.execute(
            "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) VALUES (1, 1, 'import', 'h-gone', 1)",
            [],
        )?;
        raw.execute(
            "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) VALUES (999, 0, 'import', 'h-step', 1)",
            [],
        )?;
        raw.execute(
            "INSERT INTO album_photos (album_id, photo_id, position) VALUES (1, 999, 0)",
            [],
        )?;
        raw.execute(
            "INSERT INTO photo_keywords (photo_id, keyword_id) VALUES (999, 1)",
            [],
        )?;
    }
    let report = verify_session(session.connection(), session.root(), false)?;
    let codes = finding_codes(&report.findings);
    for want in [
        "orphan_snapshot",
        "dangling_reference",
        "cursor_out_of_range",
        "process_mirror_mismatch",
        "display_aux_unparseable",
        "missing_file",
    ] {
        assert!(codes.contains(&want), "{want} missing from {codes:?}");
    }
    assert!(
        report
            .findings
            .iter()
            .filter(|finding| finding.code == "dangling_reference")
            .count()
            >= 4,
        "all four dangling plants: {:?}",
        report.findings
    );
    // Every warning or error names its repair; none of them is silent.
    for finding in &report.findings {
        if finding.severity != Severity::Info {
            assert!(!finding.repair.is_empty(), "{finding:?} names no repair");
        }
        assert!(!finding.detail.is_empty(), "{finding:?} says nothing");
    }
    let orphan = report
        .findings
        .iter()
        .find(|finding| finding.code == "orphan_snapshot")
        .expect("orphan");
    assert_eq!(orphan.severity, Severity::Info);
    drop(session);
    Ok(())
}

#[test]
fn verify_writes_nothing() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-readonly")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    insert_snapshot(session.connection(), "h1", "{\"process\": 1}")?;
    insert_photo(
        session.connection(),
        "uuid-1",
        "Capture/a1.arw",
        0,
        "h1",
        1,
        0,
    )?;
    std::fs::write(session.root().join("Capture/a1.arw"), "raw")?;
    // Merge the WAL first so the comparison is file against file.
    lightamer_catalog::checkpoint(session.connection())?;
    let before = std::fs::read(session.db_path())?;
    let report = verify_session(session.connection(), session.root(), false)?;
    assert!(report.findings.is_empty(), "{:?}", report.findings);
    let after = std::fs::read(session.db_path())?;
    assert_eq!(before, after, "verify moved database bytes");
    drop(session);
    Ok(())
}

#[test]
fn verify_defers_path_check_above_limit() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-defer")?;
    let session = create_session(scratch.path(), "Studio", "test")?;
    insert_snapshot(session.connection(), "h1", "{\"process\": 1}")?;
    for index in 0..=VERIFY_INLINE_PATH_LIMIT {
        insert_photo(
            session.connection(),
            &format!("uuid-{index}"),
            &format!("Capture/f{index}.arw"),
            0,
            "h1",
            1,
            0,
        )?;
    }
    let report = verify_session(session.connection(), session.root(), false)?;
    let codes = finding_codes(&report.findings);
    assert!(codes.contains(&"path_scan_deferred"), "{codes:?}");
    assert!(
        !codes.contains(&"missing_file"),
        "deferred means no per-file findings: {codes:?}"
    );
    drop(session);
    Ok(())
}
