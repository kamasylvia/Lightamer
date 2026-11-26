// SPDX-License-Identifier: GPL-3.0-or-later
//! Append-only migrations, the online backup, and the open-time migrate path.
//!
//! The schema version's only fact is `PRAGMA user_version`; `_meta` holds a
//! mirror, and both are written only by [`set_schema_version`]. Migrating an
//! old database first keeps a pre-migration backup
//! (`<name>.pre-migrate.<old>-<new>.bak`) through SQLite's online backup
//! API — never a bare file copy, which would drop the WAL tail — then runs
//! each step in its own transaction. A database newer than this build is
//! refused before a single byte is written (the version is probed through a
//! read-only connection first).
//!
//! [`set_schema_version`]: crate::schema::set_schema_version

use std::path::{Path, PathBuf};

use rusqlite::backup::Backup;
use rusqlite::{Connection, OpenFlags};

use crate::error::{CatalogError, io_error};
use crate::schema::{
    SCHEMA_V1_DDL, SCHEMA_VERSION, apply_pragmas, set_schema_version, user_version,
};

/// One append-only migration step: running it inside its transaction moves a
/// database from [`Migration::from`] to [`Migration::to`]. Steps are only
/// ever appended; existing ones are never edited.
pub struct Migration {
    /// The schema version this step starts from.
    pub from: i64,
    /// The schema version this step reaches.
    pub to: i64,
    /// A short stable name for reports (`v1-initial-schema`, …).
    pub name: &'static str,
    /// The step body (runs inside the step's transaction).
    pub apply: fn(&Connection) -> Result<(), CatalogError>,
}

/// Every migration step, in order. Today only `0 → 1` (a fresh database
/// file starts at `user_version` 0, so creating a session migrates too).
pub const MIGRATIONS: &[Migration] = &[Migration {
    from: 0,
    to: 1,
    name: "v1-initial-schema",
    apply: migrate_0_to_1,
}];

/// Builds schema v1 ([`SCHEMA_V1_DDL`]) and stamps version 1 on both the
/// `user_version` and the `_meta` mirror.
fn migrate_0_to_1(conn: &Connection) -> Result<(), CatalogError> {
    conn.execute_batch(SCHEMA_V1_DDL)?;
    set_schema_version(conn, 1)?;
    Ok(())
}

/// What opening a database did.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MigrateReport {
    /// The `user_version` the file had on entry.
    pub from: i64,
    /// The `user_version` it has now (always [`SCHEMA_VERSION`]).
    pub to: i64,
    /// The pre-migration backup, when a migration ran on a non-empty file.
    pub backup: Option<PathBuf>,
}

/// Opens the database at `db_path`, migrating it when it is old.
///
/// This is the only entry to the migrate path: it probes the version through
/// a read-only connection first (so a too-new database is refused without
/// writing a byte), then opens read-write, applies the storage pragmas, and
/// migrates step by step when needed.
///
/// # Errors
///
/// [`CatalogError::SchemaTooNew`] when the file is newer than this build
/// (nothing written); [`CatalogError::Sql`] when SQLite refuses any step;
/// [`CatalogError::Setup`] when a needed migration step is not registered;
/// [`CatalogError::Io`] when the backup cannot be written.
pub fn open_database(db_path: &Path) -> Result<(Connection, MigrateReport), CatalogError> {
    if db_path.exists()
        && let Some(found) = read_user_version(db_path)?
        && found > SCHEMA_VERSION
    {
        return Err(CatalogError::SchemaTooNew {
            path: db_path.to_path_buf(),
            found,
            current: SCHEMA_VERSION,
        });
    }
    let mut conn = Connection::open(db_path)?;
    migrate(&mut conn, db_path).map(|report| (conn, report))
}

/// Reads `user_version` through a read-only connection (writes nothing, so
/// it is safe to probe a database this build may refuse).
///
/// Returns `None` when the file does not exist (a fresh database).
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite cannot read the file (including a
/// corrupted file that is not a database at all).
pub fn read_user_version(db_path: &Path) -> Result<Option<i64>, CatalogError> {
    if !db_path.exists() {
        return Ok(None);
    }
    let conn = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    Ok(Some(user_version(&conn)?))
}

/// Copies `source` to `dest` through SQLite's online backup API, so rows
/// still sitting in the WAL land in the copy. `dest` may exist (it is
/// overwritten).
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the copy.
pub fn backup_database(source: &Connection, dest: &Path) -> Result<(), CatalogError> {
    let mut target = Connection::open(dest)?;
    let backup = Backup::new(source, &mut target)?;
    backup.run_to_completion(100, std::time::Duration::ZERO, None)?;
    Ok(())
}

/// Merges the WAL back into the database file and truncates it, so a closed
/// session leaves no `-wal` content behind.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the checkpoint.
pub fn checkpoint(conn: &Connection) -> Result<(), CatalogError> {
    conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_row| Ok(()))?;
    Ok(())
}
/// The pre-migration backup path for `db_path`:
/// `<name>.pre-migrate.<from>-<to>.bak` next to the database.
///
/// # Errors
///
/// [`CatalogError::BadPath`] when `db_path` has no file name.
pub fn backup_file_name(db_path: &Path, from: i64, to: i64) -> Result<PathBuf, CatalogError> {
    let Some(name) = db_path.file_name().and_then(|n| n.to_str()) else {
        return Err(CatalogError::BadPath(format!(
            "database path has no file name: {}",
            db_path.display()
        )));
    };
    let Some(parent) = db_path.parent() else {
        return Err(CatalogError::BadPath(format!(
            "database path has no parent: {}",
            db_path.display()
        )));
    };
    Ok(parent.join(format!("{name}.pre-migrate.{from}-{to}.bak")))
}

/// Runs the migrate path on an open read-write connection: pragmas first,
/// then the backup and one transaction per step when the file is old.
///
/// # Errors
///
/// See [`open_database`]; a failed backup aborts before any migration write.
fn migrate(conn: &mut Connection, db_path: &Path) -> Result<MigrateReport, CatalogError> {
    let found = user_version(conn)?;
    if found > SCHEMA_VERSION {
        // The read-only probe in `open_database` normally refuses these
        // before a read-write connection exists; this arm covers a file
        // swapped in between the two opens.
        return Err(CatalogError::SchemaTooNew {
            path: db_path.to_path_buf(),
            found,
            current: SCHEMA_VERSION,
        });
    }
    if found == SCHEMA_VERSION {
        apply_pragmas(conn)?;
        return Ok(MigrateReport {
            from: found,
            to: found,
            backup: None,
        });
    }
    let backup = if database_file_nonempty(db_path)? {
        let dest = backup_file_name(db_path, found, SCHEMA_VERSION)?;
        backup_database(conn, &dest)?;
        Some(dest)
    } else {
        None
    };
    apply_pragmas(conn)?;
    let mut version = found;
    while version < SCHEMA_VERSION {
        let Some(step) = MIGRATIONS.iter().find(|step| step.from == version) else {
            return Err(CatalogError::Setup(format!(
                "no migration registered from schema version {version}"
            )));
        };
        let transaction = conn.transaction()?;
        (step.apply)(&transaction)?;
        transaction.commit()?;
        version = step.to;
    }
    Ok(MigrateReport {
        from: found,
        to: version,
        backup,
    })
}

/// True when `db_path` exists and holds at least one byte (a fresh session
/// file that SQLite has not materialized yet needs no pre-migration backup).
fn database_file_nonempty(db_path: &Path) -> Result<bool, CatalogError> {
    match std::fs::metadata(db_path) {
        Ok(meta) => Ok(meta.len() > 0),
        Err(source) if source.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(source) => Err(io_error(db_path, source)),
    }
}
