// SPDX-License-Identifier: GPL-3.0-or-later
//! The session package on disk: layout, open/close, identity.
//!
//! A session is an ordinary directory:
//!
//! ```text
//! <Name>/
//! ├── Capture/                 # default import landing
//! ├── Selects/                 # Move to Selects destination
//! ├── Output/                  # default export landing
//! ├── Trash/                   # delete moves here; emptying is permanent
//! ├── <Name>.lmsessiondb       # SQLite (WAL): the only truth for history
//! ├── session.lock             # single-writer OS lock
//! └── session.lock.owner       # lock holder hint (JSON, may be missing)
//! ```
//!
//! [`create_session`] builds this shape under a new name (refusing a
//! non-empty directory); [`open_session`] adopts an existing directory or
//! database file, filling in whatever is missing without moving any file
//! that is already there; [`close_session`] checkpoints the WAL and
//! releases the lock explicitly. Every session carries a UUID in `_meta`,
//! minted from the OS random source on first sight.

use std::fmt::Write as _;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

use rusqlite::Connection;

use crate::error::{CatalogError, io_error};
use crate::lock::SessionLock;
use crate::migrate::{checkpoint, open_database};
use crate::schema::{META_CREATED_AT, META_CREATED_BY, META_SESSION_UUID, meta_get, meta_set};

/// Default import landing inside a session.
pub const CAPTURE_DIR: &str = "Capture";
/// Move to Selects destination inside a session.
pub const SELECTS_DIR: &str = "Selects";
/// Default export landing inside a session.
pub const OUTPUT_DIR: &str = "Output";
/// Trash inside a session (delete moves here; photos inside are read-only).
pub const TRASH_DIR: &str = "Trash";
/// The four subdirectories every session holds, in creation order.
pub const SESSION_DIRS: [&str; 4] = [CAPTURE_DIR, SELECTS_DIR, OUTPUT_DIR, TRASH_DIR];
/// The session database file suffix (`<Name>.lmsessiondb`).
pub const DB_SUFFIX: &str = ".lmsessiondb";

/// An open session: the root directory, its database connection, and the
/// single-writer lock. Dropping it without [`close_session`] still releases
/// the lock (via the OS handle); [`close_session`] additionally checkpoints
/// the WAL first, so prefer it.
pub struct Session {
    root: PathBuf,
    db_path: PathBuf,
    conn: Connection,
    lock: SessionLock,
}

impl Session {
    /// The session root directory.
    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// The session database file.
    #[must_use]
    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    /// The open database connection.
    #[must_use]
    pub fn connection(&self) -> &Connection {
        &self.conn
    }

    /// The open database connection, mutably (for transactions).
    #[must_use]
    pub fn connection_mut(&mut self) -> &mut Connection {
        &mut self.conn
    }

    /// True when the file system could not lock, so this session is open
    /// without single-writer protection. Callers surface this; it is never
    /// silent.
    #[must_use]
    pub fn opened_unlocked(&self) -> bool {
        !self.lock.held()
    }

    /// The session UUID from `_meta`.
    ///
    /// # Errors
    ///
    /// [`CatalogError::Sql`] when the read fails, or
    /// [`CatalogError::Setup`] when the row is missing (only possible when
    /// another writer deleted it out from under the session).
    pub fn session_uuid(&self) -> Result<String, CatalogError> {
        meta_get(&self.conn, META_SESSION_UUID)?.ok_or_else(|| {
            CatalogError::Setup(format!(
                "session {} lost its {META_SESSION_UUID} row",
                self.root.display()
            ))
        })
    }
}

/// Creates a session named `name` under `parent`: the root directory, the
/// four subdirectories, an empty database, and the lock.
///
/// An existing but empty directory is filled in; an existing non-empty one
/// is refused and left untouched.
///
/// # Errors
///
/// [`CatalogError::BadPath`] when the name is not a single directory name;
/// [`CatalogError::NotEmpty`] when the root exists and is not an empty
/// directory; [`CatalogError::InUse`] when the adopted directory is already
/// open elsewhere; [`CatalogError::Io`] / [`CatalogError::Sql`] /
/// [`CatalogError::Setup`] when the file system or SQLite refuses a step.
pub fn create_session(parent: &Path, name: &str, program: &str) -> Result<Session, CatalogError> {
    check_session_name(name)?;
    let root = parent.join(name);
    if root.exists() && (!root.is_dir() || directory_nonempty(&root)?) {
        return Err(CatalogError::NotEmpty(root));
    }
    open_locked(&root, program)
}

/// Opens the session at `path`: either the session root directory or the
/// session's own `<Name>.lmsessiondb` file. Missing subdirectories and a
/// missing database are created in place; every file already there is left
/// exactly where it is. A database file whose name does not match its
/// directory is refused rather than silently ignored.
///
/// # Errors
///
/// [`CatalogError::Missing`] when nothing is at the path;
/// [`CatalogError::BadPath`] when the path is neither a directory nor the
/// session's own database file; [`CatalogError::InUse`] when the session is
/// already open elsewhere; [`CatalogError::SchemaTooNew`] when the database
/// is newer than this build (nothing written); [`CatalogError::Io`] /
/// [`CatalogError::Sql`] / [`CatalogError::Setup`] when a step is refused.
pub fn open_session(path: &Path, program: &str) -> Result<Session, CatalogError> {
    let root = if path.is_dir() {
        path.to_path_buf()
    } else if path.is_file() {
        let root = session_root_from_db(path)?;
        let canonical = database_path(&root)?;
        let matches = path
            .file_name()
            .is_some_and(|given| canonical.file_name().is_some_and(|want| given == want));
        if !matches {
            return Err(CatalogError::BadPath(format!(
                "database file does not match its session directory: {}",
                path.display()
            )));
        }
        root
    } else if !path.exists() {
        return Err(CatalogError::Missing(path.to_path_buf()));
    } else {
        return Err(CatalogError::BadPath(format!(
            "not a session directory or database: {}",
            path.display()
        )));
    };
    open_locked(&root, program)
}

/// Closes a session: checkpoints the WAL into the database file (so `-wal`
/// is empty or gone afterwards), then releases the lock explicitly.
///
/// # Errors
///
/// [`CatalogError::Sql`] when the checkpoint is refused. The lock is still
/// released (dropping the session releases it either way).
pub fn close_session(session: Session) -> Result<(), CatalogError> {
    let Session { conn, lock, .. } = session;
    let checkpoint_result = checkpoint(&conn);
    lock.release();
    drop(conn);
    checkpoint_result
}

/// Takes the lock, ensures the directories and the database, and fills in
/// the session `_meta` rows. Shared by create and open so both converge.
fn open_locked(root: &Path, program: &str) -> Result<Session, CatalogError> {
    for dir in SESSION_DIRS {
        let path = root.join(dir);
        std::fs::create_dir_all(&path).map_err(|source| io_error(&path, source))?;
    }
    let lock = SessionLock::acquire(root, program)?;
    let db_path = database_path(root)?;
    let (conn, _report) = open_database(&db_path)?;
    ensure_session_meta(&conn, program)?;
    Ok(Session {
        root: root.to_path_buf(),
        db_path,
        conn,
        lock,
    })
}

/// The `<Name>.lmsessiondb` path for a session root (the root's own name
/// plus the suffix).
fn database_path(root: &Path) -> Result<PathBuf, CatalogError> {
    let Some(stem) = root.file_name().and_then(|n| n.to_str()) else {
        return Err(CatalogError::BadPath(format!(
            "session root has no directory name: {}",
            root.display()
        )));
    };
    Ok(root.join(format!("{stem}{DB_SUFFIX}")))
}

/// The session root holding `db_path` (its parent directory), refusing files
/// that are not session databases.
fn session_root_from_db(db_path: &Path) -> Result<PathBuf, CatalogError> {
    let name = db_path.file_name().and_then(|n| n.to_str()).unwrap_or("");
    if !name.ends_with(DB_SUFFIX) || name.len() == DB_SUFFIX.len() {
        return Err(CatalogError::BadPath(format!(
            "not a session database (expected *{DB_SUFFIX}): {}",
            db_path.display()
        )));
    }
    db_path.parent().map_or_else(
        || {
            Err(CatalogError::BadPath(format!(
                "database path has no parent: {}",
                db_path.display()
            )))
        },
        |parent| Ok(parent.to_path_buf()),
    )
}

/// Refuses anything but a single directory name (no separators, no `.`).
fn check_session_name(name: &str) -> Result<(), CatalogError> {
    if name.is_empty() || name == "." || name == ".." || name.contains('/') || name.contains('\0') {
        return Err(CatalogError::BadPath(format!(
            "session name must be a single directory name: {name}"
        )));
    }
    Ok(())
}

/// True when `dir` holds at least one entry.
fn directory_nonempty(dir: &Path) -> Result<bool, CatalogError> {
    match std::fs::read_dir(dir) {
        Ok(mut entries) => Ok(entries.next().is_some()),
        Err(source) if source.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(source) => Err(io_error(dir, source)),
    }
}

/// Fills in the session `_meta` rows that are missing (UUID, creator,
/// creation time), leaving present rows alone so adopting an existing
/// database never rewrites its identity. The creator names the calling
/// program (T-B1 `<app+版本>`); the version is this crate's (one workspace
/// version everywhere).
fn ensure_session_meta(conn: &Connection, program: &str) -> Result<(), CatalogError> {
    if meta_get(conn, META_SESSION_UUID)?.is_none() {
        meta_set(conn, META_SESSION_UUID, &new_uuid_v4()?)?;
    }
    if meta_get(conn, META_CREATED_BY)?.is_none() {
        let created_by = format!("{program} {}", env!("CARGO_PKG_VERSION"));
        meta_set(conn, META_CREATED_BY, &created_by)?;
    }
    if meta_get(conn, META_CREATED_AT)?.is_none() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_secs());
        meta_set(conn, META_CREATED_AT, &now.to_string())?;
    }
    Ok(())
}

/// Mints a v4 UUID from the OS random source (`/dev/urandom`, present on
/// macOS and Linux), with the version and variant bits set. No hand-rolled
/// randomness: every bit comes from the kernel.
///
/// # Errors
///
/// [`CatalogError::Io`] when the random source cannot be read.
fn new_uuid_v4() -> Result<String, CatalogError> {
    let random_path = Path::new("/dev/urandom");
    let mut bytes = [0_u8; 16];
    File::open(random_path)
        .and_then(|mut file| file.read_exact(&mut bytes))
        .map_err(|source| io_error(random_path, source))?;
    let Some(version_byte) = bytes.get_mut(6) else {
        return Err(CatalogError::Setup("/dev/urandom short read".to_owned()));
    };
    *version_byte = (*version_byte & 0x0f) | 0x40;
    let Some(variant_byte) = bytes.get_mut(8) else {
        return Err(CatalogError::Setup("/dev/urandom short read".to_owned()));
    };
    *variant_byte = (*variant_byte & 0x3f) | 0x80;
    let mut text = String::with_capacity(36);
    for (index, byte) in bytes.iter().enumerate() {
        if index == 4 || index == 6 || index == 8 || index == 10 {
            text.push('-');
        }
        write!(text, "{byte:02x}")
            .map_err(|_| CatalogError::Setup("UUID hex failed".to_owned()))?;
    }
    Ok(text)
}
