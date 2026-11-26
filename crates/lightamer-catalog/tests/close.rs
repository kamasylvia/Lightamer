// SPDX-License-Identifier: GPL-3.0-or-later
//! Closing checkpoints the WAL; reopening keeps committed data and identity.

mod common;

use lightamer_catalog::{close_session, create_session, open_session};

use common::ScratchDir;

#[test]
fn close_checkpoints_and_reopen_keeps_data() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("close")?;
    let root = scratch.path().join("Shot");
    let session = create_session(scratch.path(), "Shot", "b12p-a-test")?;
    let uuid = session.session_uuid()?;
    session
        .connection()
        .execute("INSERT INTO keywords (name) VALUES ('keep-me')", [])?;
    close_session(session)?;

    let wal = root.join("Shot.lmsessiondb-wal");
    if wal.exists() {
        assert_eq!(std::fs::metadata(&wal)?.len(), 0, "-wal not truncated");
    }

    let session = open_session(&root, "b12p-a-test")?;
    assert_eq!(
        session.session_uuid()?,
        uuid,
        "identity changed across reopen"
    );
    let count: i64 = session.connection().query_row(
        "SELECT COUNT(*) FROM keywords WHERE name = 'keep-me'",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(count, 1);
    close_session(session)?;
    Ok(())
}
