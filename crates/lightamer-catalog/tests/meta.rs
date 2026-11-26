// SPDX-License-Identifier: GPL-3.0-or-later
//! `display_aux` storage, and the T1/T2 schema shape.

mod common;

use lightamer_catalog::{close_session, create_session, display_aux_read, display_aux_write};

use common::ScratchDir;

fn column_names(
    conn: &rusqlite::Connection,
    table: &str,
) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    let names = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(names)
}

#[test]
fn display_aux_roundtrip_missing_and_corrupt() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("aux")?;
    let session = create_session(scratch.path(), "Shot", "b12p-a-test")?;

    let missing = display_aux_read(session.connection())?;
    assert_eq!(missing.json, "");
    assert!(!missing.corrupt);

    let text = "{\"overexposed_threshold\":0.5,\"nested\":{\"a\":[1,2]}}";
    display_aux_write(session.connection(), text)?;
    let back = display_aux_read(session.connection())?;
    assert_eq!(back.json, text);
    assert!(!back.corrupt);

    display_aux_write(session.connection(), "not json {{{")?;
    let corrupt = display_aux_read(session.connection())?;
    assert_eq!(corrupt.json, "");
    assert!(corrupt.corrupt, "unparseable aux must flag corrupt");

    display_aux_write(session.connection(), text)?;
    let healed = display_aux_read(session.connection())?;
    assert_eq!(healed.json, text);
    assert!(!healed.corrupt);
    close_session(session)?;
    Ok(())
}

#[test]
fn schema_matches_t1_t2_shape() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("shape")?;
    let session = create_session(scratch.path(), "Shot", "b12p-a-test")?;

    // T2: snapshots holds only the key and the content, no reference count.
    assert_eq!(
        column_names(session.connection(), "snapshots")?,
        ["hash".to_owned(), "json".to_owned()]
    );
    // T1: the snapshot key is plain text (hash plus collision suffix).
    let hash_type: String = session.connection().query_row(
        "SELECT type FROM pragma_table_info('snapshots') WHERE name = 'hash'",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(hash_type, "TEXT");
    let photo_columns = column_names(session.connection(), "photos")?;
    assert!(photo_columns.contains(&"is_export".to_owned()));
    assert!(photo_columns.contains(&"current_hash".to_owned()));
    close_session(session)?;
    Ok(())
}
