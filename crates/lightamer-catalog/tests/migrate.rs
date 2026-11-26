// SPDX-License-Identifier: GPL-3.0-or-later
//! Migrations: old databases migrate with their rows and a backup; newer
//! ones are refused without a write; the backup sees WAL rows.

mod common;

use lightamer_catalog::{
    CatalogError, backup_database, close_session, create_session, meta_get, open_session,
    read_user_version, user_version,
};

use common::ScratchDir;

const V0_FIXTURE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../fixtures/session/v0-legacy.lmsessiondb"
);
const FUTURE_FIXTURE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../fixtures/session/future-v999.lmsessiondb"
);

fn table_names(conn: &rusqlite::Connection) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let mut stmt =
        conn.prepare("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")?;
    let names = stmt
        .query_map([], |row| row.get(0))?
        .collect::<Result<Vec<String>, _>>()?;
    Ok(names)
}

#[test]
fn migrate_old_database_keeps_rows_and_leaves_backup() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("migrate")?;
    let root = scratch.path().join("Mig");
    std::fs::create_dir_all(&root)?;
    let db_path = root.join("Mig.lmsessiondb");
    std::fs::copy(V0_FIXTURE, &db_path)?;

    let session = open_session(&root, "b12p-a-test")?;
    assert_eq!(user_version(session.connection())?, 1);
    assert_eq!(
        meta_get(session.connection(), "schema_version")?.as_deref(),
        Some("1")
    );
    let names = table_names(session.connection())?;
    for table in [
        "_meta",
        "photos",
        "snapshots",
        "history_steps",
        "keywords",
        "photo_keywords",
        "albums",
        "album_photos",
        "favorites",
        "legacy_notes",
    ] {
        assert!(names.contains(&table.to_owned()), "missing table {table}");
    }
    let bodies: Vec<String> = session
        .connection()
        .prepare("SELECT body FROM legacy_notes ORDER BY id")?
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?;
    assert_eq!(
        bodies,
        ["alpha".to_owned(), "beta".to_owned(), "gamma".to_owned()]
    );
    close_session(session)?;

    let backup = root.join("Mig.lmsessiondb.pre-migrate.0-1.bak");
    assert!(backup.is_file(), "migration left no backup");
    assert_eq!(read_user_version(&backup)?, Some(0));
    let probe =
        rusqlite::Connection::open_with_flags(&backup, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let backup_names = table_names(&probe)?;
    assert!(backup_names.contains(&"legacy_notes".to_owned()));
    assert!(!backup_names.contains(&"photos".to_owned()));
    let backup_bodies: Vec<String> = probe
        .prepare("SELECT body FROM legacy_notes ORDER BY id")?
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?;
    assert_eq!(backup_bodies, bodies);
    Ok(())
}

#[test]
fn newer_database_refused_without_a_write() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("future")?;
    let root = scratch.path().join("Fut");
    std::fs::create_dir_all(&root)?;
    let db_path = root.join("Fut.lmsessiondb");
    std::fs::copy(FUTURE_FIXTURE, &db_path)?;
    let before = std::fs::read(&db_path)?;

    let Err(err) = open_session(&root, "b12p-a-test") else {
        return Err("future database was accepted".into());
    };
    let CatalogError::SchemaTooNew { found, current, .. } = err else {
        return Err(format!("expected SchemaTooNew, got {err}").into());
    };
    assert_eq!(found, 999);
    assert_eq!(current, 1);
    assert_eq!(std::fs::read(&db_path)?, before, "refused file was written");
    assert!(!root.join("Fut.lmsessiondb-wal").exists());
    assert!(!root.join("Fut.lmsessiondb-shm").exists());
    assert!(
        common::relative_file_list(&root)?
            .iter()
            .all(|name| !name.contains("pre-migrate")),
        "refused open left a backup"
    );
    Ok(())
}

#[test]
fn backup_captures_uncheckpointed_rows() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("backup")?;
    let session = create_session(scratch.path(), "Shot", "b12p-a-test")?;
    for n in 0..50 {
        session.connection().execute(
            "INSERT INTO keywords (name) VALUES (?1)",
            [format!("kw{n:02}")],
        )?;
    }
    let dest = scratch.path().join("copy.db");
    backup_database(session.connection(), &dest)?;
    let probe =
        rusqlite::Connection::open_with_flags(&dest, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let count: i64 = probe.query_row("SELECT COUNT(*) FROM keywords", [], |row| row.get(0))?;
    assert_eq!(count, 50);
    close_session(session)?;
    Ok(())
}
