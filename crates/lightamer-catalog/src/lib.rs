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
//! This wave builds the store only: no history is written here (that is the
//! next wave's write path, on top of [`Session::connection`]).
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

pub mod error;
pub mod lock;
pub mod migrate;
pub mod paths;
pub mod schema;
pub mod session;

pub use error::CatalogError;
pub use lock::{LOCK_FILE, LockOwner, OWNER_FILE, SessionLock};
pub use migrate::{
    MIGRATIONS, MigrateReport, Migration, backup_database, backup_file_name, checkpoint,
    open_database, read_user_version,
};
pub use paths::{PathKind, to_absolute, to_stored};
pub use schema::{
    DisplayAuxRead, META_CREATED_AT, META_CREATED_BY, META_DISPLAY_AUX, META_SCHEMA_VERSION,
    META_SESSION_UUID, SCHEMA_V1_DDL, SCHEMA_VERSION, apply_pragmas, display_aux_read,
    display_aux_write, meta_get, meta_set, set_schema_version, user_version,
};
pub use session::{
    CAPTURE_DIR, DB_SUFFIX, OUTPUT_DIR, SELECTS_DIR, SESSION_DIRS, Session, TRASH_DIR,
    close_session, create_session, open_session,
};

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
