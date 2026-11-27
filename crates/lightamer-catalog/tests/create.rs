// SPDX-License-Identifier: GPL-3.0-or-later
//! Creating sessions: full layout, and refusing non-empty roots.

mod common;

use lightamer_catalog::{CatalogError, close_session, create_session, meta_get, user_version};

use common::ScratchDir;

fn pragma_text(
    conn: &rusqlite::Connection,
    name: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    Ok(conn.pragma_query_value(None, name, |row| row.get(0))?)
}

fn pragma_int(conn: &rusqlite::Connection, name: &str) -> Result<i64, Box<dyn std::error::Error>> {
    Ok(conn.pragma_query_value(None, name, |row| row.get(0))?)
}

/// A v4 UUID looks like `8-4-4-4-12` hex with a `4` version nibble and an
/// `8/9/a/b` variant nibble. Checked without indexing (crate lint).
fn is_uuid_v4(text: &str) -> bool {
    let mut parts = text.split('-');
    for expected in [8_usize, 4, 4, 4, 12] {
        let Some(part) = parts.next() else {
            return false;
        };
        if part.len() != expected || !part.chars().all(|c| c.is_ascii_hexdigit()) {
            return false;
        }
    }
    if parts.next().is_some() {
        return false;
    }
    let version_ok = text
        .split('-')
        .nth(2)
        .and_then(|part| part.chars().next())
        .is_some_and(|c| c == '4');
    let variant_ok = text
        .split('-')
        .nth(3)
        .and_then(|part| part.chars().next())
        .is_some_and(|c| matches!(c, '8' | '9' | 'a' | 'b'));
    version_ok && variant_ok
}

fn expect_err<T>(
    result: Result<T, CatalogError>,
    what: &str,
) -> Result<CatalogError, Box<dyn std::error::Error>> {
    match result {
        Ok(_) => Err(format!("accepted what must be refused: {what}").into()),
        Err(err) => Ok(err),
    }
}

#[test]
fn create_builds_full_layout() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("create")?;
    let session = create_session(scratch.path(), "Shoot", "b12p-a-test")?;
    let root = session.root().to_path_buf();

    for dir in ["Capture", "Selects", "Output", "Trash"] {
        assert!(root.join(dir).is_dir(), "missing subdir {dir}");
    }
    assert!(root.join("Shoot.lmsessiondb").is_file(), "missing database");
    assert!(root.join("session.lock").is_file(), "missing lock file");
    assert!(
        root.join("session.lock.owner").is_file(),
        "missing owner note"
    );

    assert_eq!(user_version(session.connection())?, 1);
    assert_eq!(
        meta_get(session.connection(), "schema_version")?.as_deref(),
        Some("1")
    );
    assert_eq!(pragma_text(session.connection(), "journal_mode")?, "wal");
    assert_eq!(pragma_int(session.connection(), "foreign_keys")?, 1);
    assert_eq!(pragma_int(session.connection(), "synchronous")?, 2);

    let uuid = session.session_uuid()?;
    assert!(is_uuid_v4(&uuid), "not a v4 UUID: {uuid}");
    assert_eq!(session.session_uuid()?, uuid);

    let owner_bytes = std::fs::read(root.join("session.lock.owner"))?;
    let owner_text = String::from_utf8(owner_bytes)?;
    assert!(
        owner_text.contains("b12p-a-test"),
        "owner note: {owner_text}"
    );

    let created_by = meta_get(session.connection(), "created_by")?;
    assert!(
        created_by
            .as_ref()
            .is_some_and(|who| who.starts_with("b12p-a-test ")),
        "created_by names the calling program: {created_by:?}"
    );

    close_session(session)?;
    assert!(root.join("Shoot.lmsessiondb").is_file());
    assert!(
        !root.join("Shoot.lmsessiondb.pre-migrate.0-1.bak").exists(),
        "fresh sessions keep no migration backup"
    );
    Ok(())
}

#[test]
fn create_refuses_nonempty_root() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("nonempty")?;
    let root = scratch.path().join("Shoot");
    std::fs::create_dir_all(&root)?;
    std::fs::write(root.join("keep.txt"), b"keep me")?;

    let err = expect_err(
        create_session(scratch.path(), "Shoot", "b12p-a-test"),
        "non-empty",
    )?;
    assert!(
        matches!(err, CatalogError::NotEmpty(_)),
        "expected NotEmpty, got {err}"
    );
    assert_eq!(std::fs::read(root.join("keep.txt"))?, b"keep me");
    assert!(!root.join("Shoot.lmsessiondb").exists());
    assert!(!root.join("session.lock").exists());

    std::fs::write(scratch.path().join("Blocked"), b"in the way")?;
    let err = expect_err(
        create_session(scratch.path(), "Blocked", "b12p-a-test"),
        "file in the way",
    )?;
    assert!(
        matches!(err, CatalogError::NotEmpty(_)),
        "expected NotEmpty, got {err}"
    );

    let empty = scratch.path().join("Empty");
    std::fs::create_dir_all(&empty)?;
    let session = create_session(scratch.path(), "Empty", "b12p-a-test")?;
    assert!(empty.join("Empty.lmsessiondb").is_file());
    close_session(session)?;

    for bad in ["", ".", "..", "a/b", "a\0b"] {
        let err = expect_err(
            create_session(scratch.path(), bad, "b12p-a-test"),
            "bad name",
        )?;
        assert!(
            matches!(err, CatalogError::BadPath(_)),
            "name {bad:?}: expected BadPath, got {err}"
        );
    }
    Ok(())
}

#[test]
fn session_uuid_differs_between_sessions() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("uuid")?;
    let first = create_session(scratch.path(), "One", "b12p-a-test")?;
    let second = create_session(scratch.path(), "Two", "b12p-a-test")?;
    assert_ne!(first.session_uuid()?, second.session_uuid()?);
    close_session(first)?;
    close_session(second)?;
    Ok(())
}

#[test]
fn missing_path_opens_nothing() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("missing")?;
    let target = scratch.path().join("NoSuch");
    let err = expect_err(
        lightamer_catalog::open_session(&target, "b12p-a-test"),
        "missing",
    )?;
    assert!(
        matches!(err, CatalogError::Missing(_)),
        "expected Missing, got {err}"
    );
    assert!(!target.exists());
    Ok(())
}
