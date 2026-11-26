// SPDX-License-Identifier: GPL-3.0-or-later
//! Session backup and restore: whole-package duplication with progress and
//! cancellation.
//!
//! [`backup_session`] duplicates the session at a root into a directory: the
//! WAL is merged, the database travels through SQLite's online backup API
//! (never a bare file duplication, which would drop the WAL tail), and the
//! photo directories travel file by file. [`restore_package`] duplicates a
//! backup back; the caller then opens the result through the normal
//! [`open_session`][crate::open_session] path. Both take a progress callback
//! (files finished so far) and a cancel predicate checked between files and
//! between backup steps. On cancel or error the partial destination the call
//! created is removed before the error is returned, so a cancelled backup
//! leaves either nothing (it created the root) or the pre-existing empty
//! root it was given.

use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::time::Duration;

use rusqlite::Connection;
use rusqlite::backup::Backup;

use crate::error::{CatalogError, io_error};
use crate::session::{SESSION_DIRS, TRASH_DIR, database_path};

/// How many database pages one online-backup step moves before the cancel
/// predicate is checked again.
const BACKUP_PAGES_PER_STEP: i32 = 64;

/// What one backup or restore moved.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CopyStats {
    /// Photo files duplicated (the database file is not counted here).
    pub files: u64,
    /// Bytes of photo files duplicated.
    pub bytes: u64,
}

/// Refuses a backup or restore destination that already holds something: it
/// must be absent or an empty directory. Commands call this before spawning
/// the job so the refusal touches nothing; the job calls it again at start
/// (a directory created in between is refused as a job failure, not
/// silently adopted).
///
/// # Errors
///
/// [`CatalogError::NotEmpty`] when the destination exists and is not an
/// empty directory; [`CatalogError::Io`] when the file system refuses a step.
pub fn check_empty_dest(dest: &Path) -> Result<(), CatalogError> {
    match std::fs::symlink_metadata(dest) {
        Err(source) if source.kind() == ErrorKind::NotFound => Ok(()),
        Err(source) => Err(io_error(dest, source)),
        Ok(meta) => {
            if !meta.is_dir() {
                return Err(CatalogError::NotEmpty(dest.to_path_buf()));
            }
            let mut entries = std::fs::read_dir(dest).map_err(|source| io_error(dest, source))?;
            match entries.next() {
                None => Ok(()),
                Some(Ok(_)) => Err(CatalogError::NotEmpty(dest.to_path_buf())),
                Some(Err(source)) => Err(io_error(dest, source)),
            }
        }
    }
}

/// Refuses a restore source that is not a session package: it must be a
/// directory holding its own database file (named after the directory, the
/// same rule [`open_session`][crate::open_session] applies).
///
/// # Errors
///
/// [`CatalogError::BadPath`] when the source is not a directory;
/// [`CatalogError::Missing`] when its database file is absent.
pub fn check_restore_source(backup: &Path) -> Result<(), CatalogError> {
    if !backup.is_dir() {
        return Err(CatalogError::BadPath(format!(
            "not a session backup directory: {}",
            backup.display()
        )));
    }
    let db = database_path(backup)?;
    if !db.is_file() {
        return Err(CatalogError::Missing(db));
    }
    Ok(())
}

/// Duplicates the session at `src_root` into `dest`: merge the WAL, move the
/// database through the online backup API under its destination name
/// (`<dest dir name>.lmsessiondb`), then duplicate the four photo
/// directories file by file (`Trash/` only when `include_trash` is set;
/// `Cache/` never travels). The product opens directly as a session.
///
/// `progress` receives the file count after every file; `cancelled` is
/// checked between files and between backup steps.
///
/// # Errors
///
/// [`CatalogError::Cancelled`] when the predicate trips (the partial
/// destination is removed first); [`CatalogError::NotEmpty`] when `dest`
/// holds something; [`CatalogError::BadPath`] when `dest` sits inside the
/// source (a recursive duplication is refused);
/// [`CatalogError::Missing`] when the source database is absent;
/// [`CatalogError::Io`] / [`CatalogError::Sql`] when a step is refused (the
/// partial destination is removed first).
pub fn backup_session(
    src_root: &Path,
    dest: &Path,
    include_trash: bool,
    progress: &dyn Fn(u64),
    cancelled: &dyn Fn() -> bool,
) -> Result<CopyStats, CatalogError> {
    if dest.starts_with(src_root) {
        return Err(CatalogError::BadPath(format!(
            "backup destination {} sits inside the session {}; refusing a recursive duplication",
            dest.display(),
            src_root.display()
        )));
    }
    check_empty_dest(dest)?;
    let src_db = database_path(src_root)?;
    if !src_db.is_file() {
        return Err(CatalogError::Missing(src_db));
    }
    let dest_db = database_path(dest)?;
    let created_root = !dest.exists();
    let outcome = copy_package(
        &src_db,
        &dest_db,
        src_root,
        dest,
        include_trash,
        true,
        progress,
        cancelled,
    );
    cleanup_on_outcome(outcome, dest, &dest_db, created_root)
}

/// Duplicates the backup package at `backup` into `dest` (the database plus
/// the four photo directories, never `Cache/`). The source is only read
/// (never checkpointed); the caller opens `dest` through the normal open
/// path afterwards.
///
/// # Errors
///
/// Same as [`backup_session`], plus whatever [`check_restore_source`]
/// reports for a source that is not a session package.
pub fn restore_package(
    backup: &Path,
    dest: &Path,
    progress: &dyn Fn(u64),
    cancelled: &dyn Fn() -> bool,
) -> Result<CopyStats, CatalogError> {
    check_restore_source(backup)?;
    if dest.starts_with(backup) {
        return Err(CatalogError::BadPath(format!(
            "restore destination {} sits inside the backup {}; refusing a recursive duplication",
            dest.display(),
            backup.display()
        )));
    }
    check_empty_dest(dest)?;
    let src_db = database_path(backup)?;
    let dest_db = database_path(dest)?;
    let created_root = !dest.exists();
    let outcome = copy_package(
        &src_db, &dest_db, backup, dest, true, false, progress, cancelled,
    );
    cleanup_on_outcome(outcome, dest, &dest_db, created_root)
}
/// Duplicates the backup package at `backup` into `dest` and opens the
/// result: [`restore_package`] followed by the normal open path. The job
/// behind `session.restore` calls this (not the two halves): when the open
/// half fails, the just-written destination is removed under the same rule
/// (a created root goes whole, a given root is emptied), so a failed
/// restore never strands a half-opened package.
///
/// # Errors
///
/// Same as [`restore_package`], plus whatever the open path reports (a
/// too-new database, a lock held elsewhere); the destination is removed
/// first in every failure.
pub fn restore_and_open(
    backup: &Path,
    dest: &Path,
    program: &str,
    progress: &dyn Fn(u64),
    cancelled: &dyn Fn() -> bool,
) -> Result<crate::session::Session, CatalogError> {
    let created_root = !dest.exists();
    restore_package(backup, dest, progress, cancelled)?;
    let dest_db = database_path(dest)?;
    match crate::session::open_session(dest, program) {
        Ok(session) => Ok(session),
        Err(err) => {
            remove_partial_dest(dest, &dest_db, created_root);
            Err(err)
        }
    }
}

/// Moves one package: destination shape first, then the database, then the
/// photo directories. `checkpoint_src` merges the source WAL (backup only);
// restoring never writes to the backup.
#[allow(clippy::too_many_arguments)] // one package move with one progress/cancel pair; splitting would scatter the cleanup
fn copy_package(
    src_db: &Path,
    dest_db: &Path,
    src_root: &Path,
    dest_root: &Path,
    include_trash: bool,
    checkpoint_src: bool,
    progress: &dyn Fn(u64),
    cancelled: &dyn Fn() -> bool,
) -> Result<CopyStats, CatalogError> {
    std::fs::create_dir_all(dest_root).map_err(|source| io_error(dest_root, source))?;
    for dir in SESSION_DIRS {
        let path = dest_root.join(dir);
        std::fs::create_dir_all(&path).map_err(|source| io_error(&path, source))?;
    }
    if cancelled() {
        return Err(CatalogError::Cancelled);
    }
    let source = Connection::open(src_db)?;
    source.busy_timeout(Duration::from_secs(5))?;
    if checkpoint_src {
        crate::migrate::checkpoint(&source)?;
    }
    if cancelled() {
        return Err(CatalogError::Cancelled);
    }
    copy_database(&source, dest_db, cancelled)?;
    copy_dirs(src_root, dest_root, include_trash, progress, cancelled)
}

/// Moves the database through the online backup API in small steps so a
/// cancel lands between steps, not after a multi-gigabyte blocking move.
fn copy_database(
    source: &Connection,
    dest_db: &Path,
    cancelled: &dyn Fn() -> bool,
) -> Result<(), CatalogError> {
    let mut target = Connection::open(dest_db)?;
    let backup = Backup::new(source, &mut target)?;
    loop {
        if cancelled() {
            return Err(CatalogError::Cancelled);
        }
        backup.step(BACKUP_PAGES_PER_STEP)?;
        if backup.progress().remaining == 0 {
            return Ok(());
        }
    }
}

/// Duplicates the photo directories file by file in sorted order (so two
/// runs visit files in the same order), reporting the file count after
/// every file.
fn copy_dirs(
    src_root: &Path,
    dest_root: &Path,
    include_trash: bool,
    progress: &dyn Fn(u64),
    cancelled: &dyn Fn() -> bool,
) -> Result<CopyStats, CatalogError> {
    let mut stats = CopyStats::default();
    for dir in SESSION_DIRS {
        if !include_trash && dir == TRASH_DIR {
            continue;
        }
        copy_tree(
            &src_root.join(dir),
            &dest_root.join(dir),
            progress,
            cancelled,
            &mut stats,
        )?;
    }
    Ok(stats)
}

/// Duplicates one directory tree. A missing source directory duplicates as
/// empty (a hand-deleted source directory is tolerated, not fatal);
/// non-plain files (sockets, fifos) are skipped: a session package holds
/// plain files.
fn copy_tree(
    src_dir: &Path,
    dest_dir: &Path,
    progress: &dyn Fn(u64),
    cancelled: &dyn Fn() -> bool,
    stats: &mut CopyStats,
) -> Result<(), CatalogError> {
    if !src_dir.is_dir() {
        return Ok(());
    }
    let mut stack = vec![src_dir.to_path_buf()];
    while let Some(top) = stack.pop() {
        if cancelled() {
            return Err(CatalogError::Cancelled);
        }
        let mut entries: Vec<PathBuf> = Vec::new();
        for entry in std::fs::read_dir(&top).map_err(|source| io_error(&top, source))? {
            entries.push(entry.map_err(|source| io_error(&top, source))?.path());
        }
        entries.sort();
        for path in entries {
            if cancelled() {
                return Err(CatalogError::Cancelled);
            }
            let relative = path.strip_prefix(src_dir).map_err(|_| {
                CatalogError::BadPath(format!(
                    "session file {} escaped its directory {}",
                    path.display(),
                    src_dir.display()
                ))
            })?;
            let dest_path = dest_dir.join(relative);
            if path.is_dir() {
                std::fs::create_dir_all(&dest_path)
                    .map_err(|source| io_error(&dest_path, source))?;
                stack.push(path);
            } else if path.is_file() {
                if let Some(parent) = dest_path.parent() {
                    std::fs::create_dir_all(parent).map_err(|source| io_error(parent, source))?;
                }
                std::fs::copy(&path, &dest_path).map_err(|source| io_error(&dest_path, source))?;
                stats.files += 1;
                stats.bytes += dest_path.metadata().map_or(0, |meta| meta.len());
                progress(stats.files);
            }
        }
    }
    Ok(())
}

/// Removes what a failed or cancelled move created: the whole root when the
/// call created it, otherwise only the known children (the database file
/// plus the four directories), leaving the pre-existing empty root behind.
/// Best effort: a removal failure never masks the original error.
fn remove_partial_dest(dest: &Path, dest_db: &Path, created_root: bool) {
    if created_root {
        let _ = std::fs::remove_dir_all(dest);
    } else {
        let _ = std::fs::remove_file(dest_db);
        for dir in SESSION_DIRS {
            let _ = std::fs::remove_dir_all(dest.join(dir));
        }
    }
}

/// Runs [`remove_partial_dest`] unless the move succeeded; success passes
/// through untouched.
fn cleanup_on_outcome(
    outcome: Result<CopyStats, CatalogError>,
    dest: &Path,
    dest_db: &Path,
    created_root: bool,
) -> Result<CopyStats, CatalogError> {
    if outcome.is_err() {
        remove_partial_dest(dest, dest_db, created_root);
    }
    outcome
}
