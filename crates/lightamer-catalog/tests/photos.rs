// SPDX-License-Identifier: GPL-3.0-or-later
//! The minimal photo registry: registering writes the photo row, the
//! default snapshot, and step 0 in one transaction; lookups find it back.

mod common;

use lightamer_catalog::{
    CatalogError, INITIAL_LABEL, PathKind, close_session, create_session, find_photo_by_id,
    find_photo_by_uuid, list_photo_uuids, register_photo,
};

use common::{ScratchDir, default_settings_json};

#[test]
fn register_writes_photo_row_initial_step_and_default_snapshot()
-> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("register")?;
    let mut session = create_session(scratch.path(), "Shoot", "photos-test")?;
    let root = session.root().to_path_buf();
    let capture = root.join("Capture").join("a.arw");
    let record = register_photo(
        session.connection_mut(),
        &root,
        &capture,
        "a.arw",
        Some(1024),
    )?;
    let default_json = default_settings_json()?;
    let default_key = lightamer_history::PhotoSettings::default().hash64_decimal();
    let conn = session.connection();
    let row: (
        String,
        String,
        i64,
        String,
        Option<i64>,
        i64,
        i64,
        i64,
        String,
    ) = conn.query_row(
        "SELECT uuid, path, path_kind, file_name, file_size, imported_at, process, cursor, \
         current_hash FROM photos WHERE id = ?1",
        [record.id],
        |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
                row.get(8)?,
            ))
        },
    )?;
    assert_eq!(row.0, record.uuid);
    assert_eq!(row.1, "Capture/a.arw");
    assert_eq!(row.2, 0);
    assert_eq!(row.3, "a.arw");
    assert_eq!(row.4, Some(1024));
    assert!(row.5 > 0, "imported_at not stamped");
    assert_eq!(row.6, i64::from(default_process()));
    assert_eq!(row.7, 0);
    assert_eq!(row.8, default_key);

    let step: (i64, String, String) = conn.query_row(
        "SELECT idx, label, snapshot_hash FROM history_steps WHERE photo_id = ?1",
        [record.id],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?;
    assert_eq!(step, (0, INITIAL_LABEL.to_owned(), default_key.clone()));

    let stored: String = conn.query_row(
        "SELECT json FROM snapshots WHERE hash = ?1",
        [&default_key],
        |row| row.get(0),
    )?;
    assert_eq!(stored, default_json);
    let snapshots: i64 = conn.query_row("SELECT COUNT(*) FROM snapshots", [], |row| row.get(0))?;
    assert_eq!(snapshots, 1);
    close_session(session)?;
    Ok(())
}

#[test]
fn find_by_uuid_and_id_round_trip() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("find")?;
    let mut session = create_session(scratch.path(), "Shoot", "photos-test")?;
    let root = session.root().to_path_buf();
    let first = register_photo(
        session.connection_mut(),
        &root,
        &root.join("Capture").join("a.arw"),
        "a.arw",
        None,
    )?;
    let second = register_photo(
        session.connection_mut(),
        &root,
        &root.join("Capture").join("b.arw"),
        "b.arw",
        None,
    )?;
    assert_ne!(first.uuid, second.uuid);

    assert_eq!(
        find_photo_by_uuid(session.connection(), &first.uuid)?.as_ref(),
        Some(&first)
    );
    assert_eq!(
        find_photo_by_uuid(session.connection(), &second.uuid)?.as_ref(),
        Some(&second)
    );
    assert_eq!(
        find_photo_by_id(session.connection(), first.id)?.as_ref(),
        Some(&first)
    );
    assert_eq!(
        find_photo_by_id(session.connection(), second.id)?.as_ref(),
        Some(&second)
    );
    assert!(
        find_photo_by_uuid(session.connection(), "00000000-0000-0000-0000-000000000000")?.is_none()
    );
    assert!(find_photo_by_id(session.connection(), 9999)?.is_none());
    close_session(session)?;
    Ok(())
}

#[test]
fn list_uuids_matches_registrations_in_order() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("list")?;
    let mut session = create_session(scratch.path(), "Shoot", "photos-test")?;
    assert_eq!(
        list_photo_uuids(session.connection())?,
        Vec::<String>::new()
    );
    let root = session.root().to_path_buf();
    let mut expected = Vec::new();
    for name in ["a.arw", "b.arw", "c.arw"] {
        let record = register_photo(
            session.connection_mut(),
            &root,
            &root.join("Capture").join(name),
            name,
            None,
        )?;
        expected.push(record.uuid);
    }
    assert_eq!(list_photo_uuids(session.connection())?, expected);
    close_session(session)?;
    Ok(())
}

#[test]
fn duplicate_path_is_refused_and_writes_nothing() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("dupe")?;
    let mut session = create_session(scratch.path(), "Shoot", "photos-test")?;
    let root = session.root().to_path_buf();
    let path = root.join("Capture").join("a.arw");
    register_photo(session.connection_mut(), &root, &path, "a.arw", None)?;

    let before = db_counts(session.connection())?;
    // The same path through a redundant spelling converts to the same
    // stored text, so it is refused as the same photo.
    let redundant = root.join("Capture").join("sub").join("..").join("a.arw");
    for attempt in [&path, &redundant] {
        let Err(CatalogError::DuplicatePhoto { path, kind }) =
            register_photo(session.connection_mut(), &root, attempt, "a.arw", None)
        else {
            return Err("duplicate registration was accepted".into());
        };
        assert_eq!(path, "Capture/a.arw");
        assert_eq!(kind, 0);
    }
    assert_eq!(db_counts(session.connection())?, before);
    close_session(session)?;
    Ok(())
}

#[test]
fn register_external_absolute_path() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("external")?;
    let mut session = create_session(scratch.path(), "Shoot", "photos-test")?;
    let root = session.root().to_path_buf();
    let outside = scratch.path().join("outside.arw");
    let record = register_photo(
        session.connection_mut(),
        &root,
        &outside,
        "outside.arw",
        Some(7),
    )?;
    assert_eq!(record.kind, PathKind::External);
    assert_eq!(
        find_photo_by_id(session.connection(), record.id)?.as_ref(),
        Some(&record)
    );
    close_session(session)?;
    Ok(())
}

/// The process number inside the default settings (the register mirror).
fn default_process() -> u32 {
    lightamer_history::PhotoSettings::default().process.0
}

/// `(photos, history_steps, snapshots)` row counts.
fn db_counts(conn: &rusqlite::Connection) -> Result<(i64, i64, i64), Box<dyn std::error::Error>> {
    let photos: i64 = conn.query_row("SELECT COUNT(*) FROM photos", [], |row| row.get(0))?;
    let steps: i64 = conn.query_row("SELECT COUNT(*) FROM history_steps", [], |row| row.get(0))?;
    let snapshots: i64 = conn.query_row("SELECT COUNT(*) FROM snapshots", [], |row| row.get(0))?;
    Ok((photos, steps, snapshots))
}
