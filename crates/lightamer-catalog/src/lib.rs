// SPDX-License-Identifier: GPL-3.0-or-later
//! Session catalog: the on-disk session package, its SQLite database, and
//! the single-writer lock.
//!
//! A session is an ordinary directory (`Capture/`, `Selects/`, `Output/`,
//! `Trash/`, `<Name>.lmsessiondb`, `session.lock`, `session.lock.owner`).
//! [`create_session`] builds one, [`open_session`] adopts an existing
//! directory or database file, and [`close_session`] checkpoints and
//! unlocks. The database holds schema v1 (see [`schema`]), migrated by the
//! append-only table in [`migrate`]. Stored photo paths convert through
//! [`paths`]; everything that can fail surfaces as [`CatalogError`].
//!
//! This wave writes history too: [`photos`] registers the library rows and
//! [`history_store`] pushes steps, moves the cursor, reads histories back,
//! and collects orphan snapshots.
// `result_large_err` is allowed crate-wide: errors here are cold paths
// (open/migrate/lock failures), and boxing the variants would only
// complicate matching for the engine wave. The success path copies nothing.
#![allow(clippy::result_large_err)]
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

pub mod backup;
pub mod error;
pub mod history_store;
pub mod lock;
pub mod migrate;
pub mod paths;
pub mod photos;
pub mod scan;
pub mod schema;
pub mod session;
pub mod template;
pub mod verify;

pub use backup::{
    CopyStats, backup_session, check_empty_dest, check_restore_source, restore_and_open,
    restore_package,
};
pub use error::CatalogError;
pub use history_store::{
    HistoryRead, HistoryStepRead, HistoryWriter, INITIAL_LABEL, MoveOutcome, PhotoCurrent,
    PushOutcome, PushRequest, PushStats, delete_orphan_snapshots, move_cursor,
    orphan_snapshot_hashes, push_step, read_history, read_photo_currents,
};
pub use lock::{LOCK_FILE, LockOwner, OWNER_FILE, SessionLock};
pub use migrate::{
    MIGRATIONS, MigrateReport, Migration, backup_database, backup_file_name, checkpoint,
    open_database, read_user_version,
};
pub use paths::{PathKind, to_absolute, to_stored};
pub use photos::{
    PhotoRecord, find_photo_by_id, find_photo_by_uuid, list_photo_uuids, register_photo,
};
pub use scan::{ScanStats, scan_missing};
pub use schema::{
    DisplayAuxRead, META_CREATED_AT, META_CREATED_BY, META_DISPLAY_AUX, META_SCHEMA_VERSION,
    META_SESSION_UUID, SCHEMA_V1_DDL, SCHEMA_VERSION, apply_pragmas, display_aux_read,
    display_aux_write, meta_get, meta_set, set_schema_version, user_version,
};
pub use session::{
    CAPTURE_DIR, DB_SUFFIX, OUTPUT_DIR, SELECTS_DIR, SESSION_DIRS, Session, TRASH_DIR,
    close_session, create_session, open_session,
};
pub use template::{TEMPLATE_DIR_ENV, save_template, template_dir};
pub use verify::{Finding, Severity, VERIFY_INLINE_PATH_LIMIT, VerifyReport, verify_session};

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
