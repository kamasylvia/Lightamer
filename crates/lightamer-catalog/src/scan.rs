// SPDX-License-Identifier: GPL-3.0-or-later
//! Missing-file scan: the background job behind `session.open`.
//!
//! [`scan_missing`] walks every photo row, resolves its stored path, and
//! marks the rows whose files are gone (`missing = 1`) — and unmarks rows
//! whose files are back. It opens its own database connection (the engine
//! holds another on its thread), reports progress every 64 rows plus a final
//! report, and stops early on cancel, keeping the partial marks it already
//! wrote: a cancelled scan is resumed by simply running it again.

use std::path::Path;
use std::time::Duration;

use rusqlite::Connection;

use crate::error::CatalogError;
use crate::paths::{PathKind, to_absolute};

/// Rows reported between progress callbacks (plus one final report).
const PROGRESS_EVERY_ROWS: u64 = 64;

/// What one scan did.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ScanStats {
    /// Photo rows examined.
    pub checked: u64,
    /// Rows newly marked missing.
    pub marked_missing: u64,
    /// Rows newly unmarked (their files are back).
    pub unmarked: u64,
}

/// Scans the library at `db_path` (whose session root is `root`) for files
/// that moved away, marking and unmarking rows in place. `progress` receives
/// the checked count; `cancelled` is checked before every row.
///
/// A stored path that does not resolve counts as missing: the file is
/// certainly not reachable under it.
///
/// # Errors
///
/// [`CatalogError::Cancelled`] when the predicate trips (partial marks
/// stay); [`CatalogError::Sql`] when SQLite refuses a step.
pub fn scan_missing(
    db_path: &Path,
    root: &Path,
    progress: &dyn Fn(u64),
    cancelled: &dyn Fn() -> bool,
) -> Result<ScanStats, CatalogError> {
    let conn = Connection::open(db_path)?;
    conn.busy_timeout(Duration::from_secs(5))?;
    let mut select = conn.prepare("SELECT id, path, path_kind, missing FROM photos ORDER BY id")?;
    // Collected first so the UPDATE below never fights the SELECT cursor.
    let rows: Vec<(i64, String, i64, i64)> = select
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })?
        .collect::<Result<_, _>>()?;
    let mut stats = ScanStats::default();
    for (id, stored, kind, missing) in &rows {
        if cancelled() {
            progress(stats.checked);
            return Err(CatalogError::Cancelled);
        }
        let want = i64::from(!stored_is_present(root, *kind, stored));
        if *missing != want {
            conn.execute(
                "UPDATE photos SET missing = ?1 WHERE id = ?2",
                rusqlite::params![want, id],
            )?;
            if want == 1 {
                stats.marked_missing += 1;
            } else {
                stats.unmarked += 1;
            }
        }
        stats.checked += 1;
        if stats.checked % PROGRESS_EVERY_ROWS == 0 {
            progress(stats.checked);
        }
    }
    progress(stats.checked);
    Ok(stats)
}

/// Whether the stored path resolves to a file on disk right now.
fn stored_is_present(root: &Path, kind: i64, stored: &str) -> bool {
    PathKind::from_db(kind)
        .and_then(|set| to_absolute(root, set, stored).ok())
        .is_some_and(|absolute| absolute.exists())
}
