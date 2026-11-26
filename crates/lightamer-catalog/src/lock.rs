// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from lightcraft crates/catalog/src/lock.rs (commit afa18c675):
// reworked for a session directory instead of a library directory. Lock file
// renamed to `session.lock`, owner note to `session.lock.owner`; the folder
// identity check (`OpenedFolder::vouch`, an internal LightCraft type that was
// not taken) is replaced by an atomic temp-plus-rename note write and a
// byte-compare before removing our own note; a lock-file open failure is a
// loud error instead of a silent unlocked open. The OS-lock semantics,
// explicit unlock-on-drop (#680), hint-only owner note, unlocked-open
// fallback, and crash behavior are kept.
//! Single-writer lock for a session directory.
//!
//! Opening a session takes an exclusive OS lock on `<root>/session.lock`
//! first, and a second opener gets [`CatalogError::InUse`] instead: two
//! writers would each keep their own SQLite state, and the last one to
//! checkpoint would silently drop the other's edits.
//!
//! - The lock is the OS's (`flock` on Unix via [`File::try_lock`]): it is
//!   released explicitly when the [`SessionLock`] is released or dropped
//!   and, after a crash or a kill, by the OS when the process ends. A
//!   `session.lock` file left behind is therefore never "stale": only a
//!   lock that is actually held refuses the open.
//! - Releasing calls [`File::unlock`] rather than relying on the handle
//!   closing. On Unix a `flock` lock lasts while *any* copy of the
//!   descriptor is open, and a process another thread is spawning holds a
//!   copy of every descriptor until it execs, so closing ours could leave
//!   the session "already open" for a moment and a re-open would be
//!   refused. `LOCK_UN` through our descriptor frees the lock whatever
//!   copies a child still holds.
//! - Who holds it (process id, computer, program, version) is written to
//!   `session.lock.owner`, for the error message. It is only a hint: it may
//!   be missing or left over from a crash, and a missing or unreadable note
//!   never blocks an open.
//! - File systems without lock support (some network shares): the session
//!   opens unlocked, and the caller is told via [`SessionLock::held`].
//!
//! [`File::try_lock`]: std::fs::File::try_lock
//! [`File::unlock`]: std::fs::File::unlock
//! [`CatalogError::InUse`]: crate::error::CatalogError::InUse

use std::fs::{File, OpenOptions, TryLockError};
use std::hash::{BuildHasher, Hasher, RandomState};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::error::{CatalogError, io_error};

/// The lock file in the session directory.
pub const LOCK_FILE: &str = "session.lock";
/// Who holds the lock (JSON, see [`LockOwner`]).
pub const OWNER_FILE: &str = "session.lock.owner";

/// Who has the session open (as written in [`OWNER_FILE`]).
#[derive(Clone, Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct LockOwner {
    /// Process id of the holder.
    pub pid: u32,
    /// Computer name, if known.
    pub host: String,
    /// The program (`lightamer-cli`, …) holding the session.
    pub program: String,
    /// The program version.
    pub version: String,
    /// When it opened the session (seconds since 1970).
    pub since: u64,
    /// Unique per lock: a count of locks mixed with a random key, so the
    /// bytes one lock wrote never equal another lock's note. Not a secret.
    pub token: String,
}

impl LockOwner {
    /// This process, opening as `program`.
    #[must_use]
    pub fn this_process(program: &str) -> Self {
        Self {
            pid: std::process::id(),
            host: host_name(),
            program: program.to_owned(),
            version: env!("CARGO_PKG_VERSION").to_owned(),
            since: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |d| d.as_secs()),
            token: lock_token(),
        }
    }

    /// `"lightamer-cli 0.1.0 (process 123 on this computer)"`.
    #[must_use]
    pub fn describe(&self) -> String {
        let program = if self.program.is_empty() {
            "another program"
        } else {
            self.program.as_str()
        };
        let version = if self.version.is_empty() {
            String::new()
        } else {
            format!(" {}", self.version)
        };
        let host = if self.host.is_empty() {
            String::new()
        } else if self.host == host_name() {
            " on this computer".to_owned()
        } else {
            format!(" on {}", self.host)
        };
        format!("{program}{version} (process {}{host})", self.pid)
    }
}

/// The computer's name, best effort (empty if unknown). Asked once per
/// process and then kept: [`LockOwner::describe`] compares against it on
/// every refusal message.
static HOST_NAME: LazyLock<String> = LazyLock::new(|| {
    std::env::vars()
        .find_map(|(key, value)| {
            if (key == "COMPUTERNAME" || key == "HOSTNAME") && !value.trim().is_empty() {
                Some(value)
            } else {
                None
            }
        })
        .or_else(|| std::fs::read_to_string("/etc/hostname").ok())
        .map(|name| name.trim().to_owned())
        .filter(|name| !name.is_empty())
        .or_else(system_host_name)
        .unwrap_or_default()
});

/// The cached computer name (see [`HOST_NAME`]).
fn host_name() -> String {
    HOST_NAME.clone()
}

/// Asks the OS for the computer name through `hostname(1)`: on macOS neither
/// the environment nor `/etc/hostname` names the machine, so without this
/// the holder hint is empty there. Best effort only: any spawn, wait, or
/// decode failure yields [`None`] (the tool prints one line and exits, so
/// this never hangs and never panics).
fn system_host_name() -> Option<String> {
    let output = std::process::Command::new("/bin/hostname")
        .output()
        .or_else(|_| std::process::Command::new("hostname").output())
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let name = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    (!name.is_empty()).then_some(name)
}

/// A value no other lock's note has ([`LockOwner::token`]).
fn lock_token() -> String {
    static LOCKS: AtomicU64 = AtomicU64::new(0);
    let mut hasher = RandomState::new().build_hasher();
    hasher.write_u64(LOCKS.fetch_add(1, Ordering::Relaxed));
    format!("{:016x}", hasher.finish())
}

/// The exclusive lock on a session directory; released on [`SessionLock::release`]
/// (and by the OS if the process dies).
#[derive(Debug)]
pub struct SessionLock {
    dir: PathBuf,
    /// `None` when the file system cannot lock (the session is open unlocked).
    file: Option<File>,
    held: bool,
    /// The owner note as this lock wrote it (`None`: it wrote none).
    note: Option<Vec<u8>>,
}

impl SessionLock {
    /// Locks `dir` (which must exist) for this process.
    ///
    /// Fails only when another process holds it. On a file system without
    /// lock support the session opens unlocked instead (see [`SessionLock::held`]).
    ///
    /// # Errors
    ///
    /// [`CatalogError::InUse`] when another process holds the lock, with the
    /// holder's note when it was present and readable; [`CatalogError::Io`]
    /// when the lock file cannot be opened.
    pub fn acquire(dir: &Path, program: &str) -> Result<Self, CatalogError> {
        let lock_path = dir.join(LOCK_FILE);
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&lock_path)
            .map_err(|source| io_error(&lock_path, source))?;
        match file.try_lock() {
            Ok(()) => {}
            Err(TryLockError::WouldBlock) => {
                let owner = std::fs::read(dir.join(OWNER_FILE))
                    .ok()
                    .and_then(|bytes| serde_json::from_slice::<LockOwner>(&bytes).ok());
                return Err(CatalogError::InUse {
                    path: dir.to_path_buf(),
                    owner,
                });
            }
            Err(TryLockError::Error(_)) => {
                return Ok(Self {
                    dir: dir.to_path_buf(),
                    file: None,
                    held: false,
                    note: None,
                });
            }
        }
        let note = LockOwner::this_process(program);
        let note = serde_json::to_vec_pretty(&note)
            .ok()
            .and_then(|json| write_note(dir, &json).ok().map(|()| json));
        Ok(Self {
            dir: dir.to_path_buf(),
            file: Some(file),
            held: true,
            note,
        })
    }

    /// The OS lock is held (`false`: the file system cannot lock, so the
    /// session is open unprotected and the caller was told so by this flag).
    #[must_use]
    pub fn held(&self) -> bool {
        self.held
    }

    /// The session directory this lock guards.
    #[must_use]
    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// The owner note this lock wrote (`None`: it wrote none).
    #[must_use]
    pub fn note(&self) -> Option<&[u8]> {
        self.note.as_deref()
    }

    /// Removes our own owner note (so it cannot delete the next holder's),
    /// then releases the lock explicitly. Dropping the lock without calling
    /// this does the same; calling it makes the release point explicit.
    pub fn release(mut self) {
        self.release_inner();
    }

    /// Removes the owner note if it is this lock's (the note still has the
    /// bytes this lock wrote there), then unlocks explicitly rather than
    /// relying on the handle closing (see the module docs).
    fn release_inner(&mut self) {
        if !self.held {
            return;
        }
        self.held = false;
        if let Some(ours) = &self.note
            && let Ok(current) = std::fs::read(self.dir.join(OWNER_FILE))
            && current == *ours
        {
            let _ = std::fs::remove_file(self.dir.join(OWNER_FILE));
        }
        if let Some(file) = &self.file {
            let _ = file.unlock();
        }
    }
}

impl Drop for SessionLock {
    fn drop(&mut self) {
        self.release_inner();
    }
}

/// Writes the owner note into `dir`: a new file in place of whatever is at
/// the name (an atomic rename, so a link planted there is replaced, never
/// written through).
fn write_note(dir: &Path, json: &[u8]) -> io::Result<()> {
    let tmp_path = dir.join(format!(".{OWNER_FILE}.tmp-{}", std::process::id()));
    let write_result = (|| -> io::Result<()> {
        let mut tmp = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&tmp_path)?;
        tmp.write_all(json)?;
        tmp.sync_all()?;
        drop(tmp);
        std::fs::rename(&tmp_path, dir.join(OWNER_FILE))?;
        Ok(())
    })();
    if write_result.is_err() {
        let _ = std::fs::remove_file(&tmp_path);
    }
    write_result
}
