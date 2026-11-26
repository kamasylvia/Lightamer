// SPDX-License-Identifier: GPL-3.0-or-later
//! The minimal photo registry: registering one photo, finding it, listing
//! the library.
//!
//! A photo's outside identity is its UUID (text); the integer `id` is
//! internal to the database. Registering a photo writes three things in one
//! transaction — the photo row (with the converted stored path), the default
//! settings' snapshot row, and step 0 (label [`INITIAL_LABEL`], the default
//! snapshot) — and points the photo row's cursor (0), current snapshot, and
//! process mirror at that step, so the row is never left without history.
//!
//! Registering the same stored path twice is refused ([`CatalogError::DuplicatePhoto`],
//! nothing written): one library row owns one path, and the import wave
//! (B15) keeps that ownership.

use std::path::Path;

use lightamer_history::PhotoSettings;
use rusqlite::{Connection, OptionalExtension, params};

use crate::error::CatalogError;
use crate::history_store::{INITIAL_LABEL, now_unix, settings_process, store_snapshot};
use crate::paths::{PathKind, to_stored};
use crate::session::new_uuid_v4;

/// One registered photo: its two identities plus its stored path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PhotoRecord {
    /// The internal row id (`photos.id`).
    pub id: i64,
    /// The stable outside identity (`photos.uuid`).
    pub uuid: String,
    /// The stored path text (`photos.path`, interpreted with [`PhotoRecord::kind`]).
    pub path: String,
    /// Which form [`PhotoRecord::path`] takes (`photos.path_kind`).
    pub kind: PathKind,
}

/// Registers one photo: converts `path` to its stored form, mints a UUID
/// from the OS random source, and writes the photo row, the default
/// snapshot, and step 0 in a single transaction. Retrieval columns (size
/// excepted, capture time, camera data) stay empty for the import wave to
/// fill in.
///
/// # Errors
///
/// [`CatalogError::BadPath`] when the path cannot be stored;
/// [`CatalogError::DuplicatePhoto`] when the stored path is already
/// registered (nothing written); [`CatalogError::Sql`] when SQLite refuses
/// a step; [`CatalogError::Io`] when the random source cannot be read.
pub fn register_photo(
    conn: &mut Connection,
    root: &Path,
    path: &Path,
    file_name: &str,
    file_size: Option<i64>,
) -> Result<PhotoRecord, CatalogError> {
    let (kind, stored) = to_stored(root, path)?;
    let taken: Option<i64> = conn
        .query_row(
            "SELECT id FROM photos WHERE path_kind = ?1 AND path = ?2",
            params![kind.as_db(), stored],
            |row| row.get(0),
        )
        .optional()?;
    if taken.is_some() {
        return Err(CatalogError::DuplicatePhoto {
            path: stored,
            kind: kind.as_db(),
        });
    }
    let default = PhotoSettings::default();
    let json = default
        .canonical_json()
        .map_err(|source| CatalogError::BadSettings {
            reason: source.to_string(),
        })?;
    let process = settings_process(&json)?;
    let uuid = new_uuid_v4()?;
    let now = now_unix();
    let tx = conn.transaction()?;
    // Another photo may already hold the default snapshot: the store call
    // reuses that row instead of writing a second one.
    let snapshot = store_snapshot(&tx, &json, None)?;
    tx.execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, file_size, imported_at, \
         process, cursor, current_hash) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0, ?8)",
        params![
            uuid,
            stored,
            kind.as_db(),
            file_name,
            file_size,
            now,
            process,
            snapshot.key
        ],
    )?;
    let id = tx.last_insert_rowid();
    tx.execute(
        "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) \
         VALUES (?1, 0, ?2, ?3, ?4)",
        params![id, INITIAL_LABEL, snapshot.key, now],
    )?;
    tx.commit()?;
    Ok(PhotoRecord {
        id,
        uuid,
        path: stored,
        kind,
    })
}

/// Finds a photo by its UUID: `None` when no photo carries it.
///
/// # Errors
///
/// [`CatalogError::Setup`] when the stored row's path kind is damaged;
/// [`CatalogError::Sql`] when SQLite refuses the read.
pub fn find_photo_by_uuid(
    conn: &Connection,
    uuid: &str,
) -> Result<Option<PhotoRecord>, CatalogError> {
    let row: Option<(i64, String, String, i64)> = conn
        .query_row(
            "SELECT id, uuid, path, path_kind FROM photos WHERE uuid = ?1",
            [uuid],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;
    row.map(record_from_row).transpose()
}

/// Finds a photo by its internal id: `None` when no photo carries it.
///
/// # Errors
///
/// [`CatalogError::Setup`] when the stored row's path kind is damaged;
/// [`CatalogError::Sql`] when SQLite refuses the read.
pub fn find_photo_by_id(conn: &Connection, id: i64) -> Result<Option<PhotoRecord>, CatalogError> {
    let row: Option<(i64, String, String, i64)> = conn
        .query_row(
            "SELECT id, uuid, path, path_kind FROM photos WHERE id = ?1",
            [id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;
    row.map(record_from_row).transpose()
}

/// Every photo UUID in the library, oldest registration first. Only the
/// UUID column is read, so listing never loads whole rows to fetch
/// identities.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the read.
pub fn list_photo_uuids(conn: &Connection) -> Result<Vec<String>, CatalogError> {
    let mut select = conn.prepare("SELECT uuid FROM photos ORDER BY id")?;
    Ok(select
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?)
}

/// Builds a [`PhotoRecord`] from a `(id, uuid, path, path_kind)` row.
fn record_from_row(row: (i64, String, String, i64)) -> Result<PhotoRecord, CatalogError> {
    let (id, uuid, path, kind) = row;
    let Some(kind) = PathKind::from_db(kind) else {
        return Err(CatalogError::Setup(format!(
            "photo {id} stores path kind {kind} which is neither 0 nor 1"
        )));
    };
    Ok(PhotoRecord {
        id,
        uuid,
        path,
        kind,
    })
}
