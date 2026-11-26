// SPDX-License-Identifier: GPL-3.0-or-later
//! Typed errors for session catalog operations.
//!
//! Every failure in this crate surfaces as [`CatalogError`]; its [`Display`]
//! text is the human-readable message shown to callers. No function in this
//! crate fails with a panic on bad input.
//!
//! [`Display`]: std::fmt::Display

use std::fmt;
use std::io;
use std::path::{Path, PathBuf};

use crate::lock::LockOwner;

/// Everything that can go wrong while creating, opening, migrating, closing,
/// or locking a session, while converting stored paths, or while reading
/// and writing photo history.
#[derive(Debug)]
#[non_exhaustive]
pub enum CatalogError {
    /// A file-system operation failed.
    Io {
        /// The path the operation targeted.
        path: PathBuf,
        /// The underlying failure.
        source: io::Error,
    },
    /// SQLite refused an operation.
    Sql(rusqlite::Error),
    /// The database would not take the required storage settings, or a
    /// migration step the schema needs is not registered.
    Setup(String),
    /// Another process holds the session lock.
    InUse {
        /// The session root that is already open.
        path: PathBuf,
        /// Who holds it, when the owner note was present and readable.
        owner: Option<LockOwner>,
    },
    /// The database schema is newer than this build understands. Nothing
    /// was written: the caller must upgrade, never downgrade-write.
    SchemaTooNew {
        /// The database file that was refused.
        path: PathBuf,
        /// The `user_version` found in the file.
        found: i64,
        /// The newest schema this build can open.
        current: i64,
    },
    /// `create_session` found something already there that is not an
    /// empty directory.
    NotEmpty(PathBuf),
    /// `open_session` found nothing at the path.
    Missing(PathBuf),
    /// A session name or stored path is malformed, or a stored path
    /// escapes the session root.
    BadPath(String),
    /// A history call named a photo id that is not in the library.
    /// Nothing was written.
    UnknownPhoto(i64),
    /// `register_photo` found the stored path already registered.
    /// Nothing was written.
    DuplicatePhoto {
        /// The stored path text (`photos.path`).
        path: String,
        /// The stored path kind (`photos.path_kind`, 0 or 1).
        kind: i64,
    },
    /// A cursor move named a step that is not there (`target < 0` or past
    /// the last step). Nothing was written.
    CursorOutOfRange {
        /// The photo the move named.
        photo_id: i64,
        /// The requested step index.
        target: i64,
        /// How many steps the photo holds.
        steps: i64,
    },
    /// A history write was handed settings text that does not parse as
    /// settings. Nothing was written.
    BadSettings {
        /// Why the text was refused (the parser's message).
        reason: String,
    },
    /// A background job observed its cancel flag and stopped before doing
    /// more work. A backup or restore that stops this way removes its own
    /// partial destination before returning this.
    Cancelled,
}

impl fmt::Display for CatalogError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { path, source } => {
                write!(f, "file {}: {source}", path.display())
            }
            Self::Sql(source) => write!(f, "database error: {source}"),
            Self::Setup(message) => write!(f, "database setup refused: {message}"),
            Self::InUse { path, owner } => {
                let holder = owner
                    .as_ref()
                    .map_or_else(|| "another program".to_owned(), LockOwner::describe);
                write!(
                    f,
                    "session {} is already open in {holder}; close it there first",
                    path.display()
                )
            }
            Self::SchemaTooNew {
                path,
                found,
                current,
            } => write!(
                f,
                "database {} has schema version {found}, newer than this build understands (up to {current}); upgrade instead",
                path.display()
            ),
            Self::NotEmpty(path) => write!(
                f,
                "refusing to create a session over non-empty {}",
                path.display()
            ),
            Self::Missing(path) => {
                write!(f, "no session at {}", path.display())
            }
            Self::BadPath(reason) => write!(f, "bad session path: {reason}"),
            Self::UnknownPhoto(id) => write!(f, "photo {id} is not in the library"),
            Self::DuplicatePhoto { path, kind } => write!(
                f,
                "photo with stored path kind {kind} and text {path:?} is already registered"
            ),
            Self::CursorOutOfRange {
                photo_id,
                target,
                steps,
            } => write!(
                f,
                "photo {photo_id} holds {steps} history steps, so step {target} is out of range"
            ),
            Self::BadSettings { reason } => write!(f, "settings text refused: {reason}"),
            Self::Cancelled => write!(f, "operation cancelled"),
        }
    }
}

impl std::error::Error for CatalogError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            Self::Sql(source) => Some(source),
            Self::Setup(_)
            | Self::InUse { .. }
            | Self::SchemaTooNew { .. }
            | Self::NotEmpty(_)
            | Self::Missing(_)
            | Self::BadPath(_)
            | Self::UnknownPhoto(_)
            | Self::DuplicatePhoto { .. }
            | Self::CursorOutOfRange { .. }
            | Self::BadSettings { .. }
            | Self::Cancelled => None,
        }
    }
}

impl From<rusqlite::Error> for CatalogError {
    fn from(source: rusqlite::Error) -> Self {
        Self::Sql(source)
    }
}

/// Builds the [`CatalogError::Io`] for a failed file-system call.
pub(crate) fn io_error(path: &Path, source: io::Error) -> CatalogError {
    CatalogError::Io {
        path: path.to_path_buf(),
        source,
    }
}
