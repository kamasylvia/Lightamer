// SPDX-License-Identifier: GPL-3.0-or-later
//! Read-only session verification: structural and content checks that never
//! write.
//!
//! [`verify_session`] runs every check against an open connection and
//! returns a [`VerifyReport`]: one [`Finding`] per problem with a severity,
//! a stable code, a human-readable detail, and the id of the command that
//! repairs it (empty for informational findings, which need no repair).
//! Repair ids name the owning command even when that command lands in a
//! later wave (`library.relink`, `library.sync`, `display.set`); only
//! `session.restore` and `session.close` are registered today, and the
//! report never claims otherwise.
//!
//! The function only reads: `SELECT` statements plus
//! `PRAGMA integrity_check`. Verifying the same database bytes twice leaves
//! the same bytes behind (tests assert the file hash is unchanged).

use std::collections::BTreeMap;
use std::path::Path;

use rusqlite::Connection;

use crate::error::CatalogError;
use crate::paths::{PathKind, to_absolute};
use crate::schema::{DisplayAuxRead, display_aux_read};

/// Photos above this count skip the per-file existence check: stating every
/// file is unbounded work, so large sessions defer it to the background
/// scan (`library.sync`) while verify reports one informational finding
/// instead. Small sessions are fully covered below this line.
pub const VERIFY_INLINE_PATH_LIMIT: usize = 1000;

/// Findings kept per check before an overflow note replaces the rest (a
/// badly damaged database must not turn the report into a second database).
const FINDINGS_PER_CHECK: usize = 200;

/// How much a [`Finding`] matters.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    /// Harmless or already handled (orphans, hints): no repair needed.
    Info,
    /// One row or file disagrees: a repair command can fix it.
    Warning,
    /// Structural damage (the database itself or a broken reference):
    /// restore from a backup.
    Error,
}

impl Severity {
    /// The lowercase name used in reports (`info`, `warning`, `error`).
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Info => "info",
            Self::Warning => "warning",
            Self::Error => "error",
        }
    }
}

/// One thing verification found.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    /// How much it matters.
    pub severity: Severity,
    /// Stable code (`integrity`, `orphan_snapshot`, …).
    pub code: &'static str,
    /// What is wrong, with the row or file that is wrong.
    pub detail: String,
    /// The command id that repairs it; empty for informational findings.
    pub repair: &'static str,
}

/// Everything [`verify_session`] found, in check order.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct VerifyReport {
    /// The findings, in check order (integrity first, hints last).
    pub findings: Vec<Finding>,
}

/// Verifies the session behind `conn` (whose root is `root`): the database
/// integrity check, orphan snapshots, dangling references, cursor bounds,
/// the process mirror, the `display_aux` parse, and stored-file existence.
/// `unlocked` reports an open without its lock as a hint. Read-only: only
/// `SELECT` plus `integrity_check`, never a write.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses a read.
pub fn verify_session(
    conn: &Connection,
    root: &Path,
    unlocked: bool,
) -> Result<VerifyReport, CatalogError> {
    let mut findings = Vec::new();
    check_integrity(conn, &mut findings)?;
    check_orphan_snapshots(conn, &mut findings)?;
    check_dangling(conn, &mut findings)?;
    check_cursors(conn, &mut findings)?;
    check_process_mirror(conn, &mut findings)?;
    check_display_aux(conn, &mut findings)?;
    check_paths(conn, root, &mut findings)?;
    if unlocked {
        findings.push(Finding {
            severity: Severity::Info,
            code: "opened_unlocked",
            detail: "the session is open without its lock (the file system refused locking)"
                .to_owned(),
            repair: "",
        });
    }
    Ok(VerifyReport { findings })
}

/// One check's capped finding sink: the first [`FINDINGS_PER_CHECK`] findings
/// land individually, the rest collapse into one overflow note.
struct Capped<'a> {
    out: &'a mut Vec<Finding>,
    remaining: usize,
    overflow: usize,
    severity: Severity,
    code: &'static str,
    repair: &'static str,
}

impl Capped<'_> {
    fn push(&mut self, detail: String) {
        if self.remaining == 0 {
            self.overflow += 1;
            return;
        }
        self.remaining -= 1;
        self.out.push(Finding {
            severity: self.severity,
            code: self.code,
            detail,
            repair: self.repair,
        });
    }

    fn finish(self) {
        if self.overflow > 0 {
            self.out.push(Finding {
                severity: self.severity,
                code: self.code,
                detail: format!("… and {} more", self.overflow),
                repair: self.repair,
            });
        }
    }
}
fn capped<'a>(
    out: &'a mut Vec<Finding>,
    severity: Severity,
    code: &'static str,
    repair: &'static str,
) -> Capped<'a> {
    Capped {
        out,
        remaining: FINDINGS_PER_CHECK,
        overflow: 0,
        severity,
        code,
        repair,
    }
}

/// `PRAGMA integrity_check`: healthy is exactly one row saying `ok`.
fn check_integrity(conn: &Connection, out: &mut Vec<Finding>) -> Result<(), CatalogError> {
    let mut stmt = conn.prepare("PRAGMA integrity_check")?;
    let rows: Vec<String> = stmt
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?;
    if rows.len() == 1 && rows.first().is_some_and(|line| line == "ok") {
        return Ok(());
    }
    let mut capped = capped(out, Severity::Error, "integrity", "session.restore");
    for line in rows {
        capped.push(format!("database integrity check reports: {line}"));
    }
    capped.finish();
    Ok(())
}

/// Snapshots no step references and no photo holds as current.
fn check_orphan_snapshots(conn: &Connection, out: &mut Vec<Finding>) -> Result<(), CatalogError> {
    let rows = crate::history_store::orphan_snapshot_hashes(conn)?;
    let mut capped = capped(out, Severity::Info, "orphan_snapshot", "");
    for hash in rows {
        capped.push(format!(
            "orphan snapshot {hash}: referenced by no history step and no photo"
        ));
    }
    capped.finish();
    Ok(())
}

/// References naming rows that are not there (steps, current snapshots,
/// keyword and album links).
fn check_dangling(conn: &Connection, out: &mut Vec<Finding>) -> Result<(), CatalogError> {
    let mut capped = capped(
        out,
        Severity::Error,
        "dangling_reference",
        "session.restore",
    );
    let mut stmt = conn.prepare(
        "SELECT photo_id, idx FROM history_steps \
         WHERE photo_id NOT IN (SELECT id FROM photos) \
         ORDER BY photo_id, idx",
    )?;
    let rows: Vec<(i64, i64)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<_, _>>()?;
    for (photo, index) in rows {
        capped.push(format!(
            "history step (photo {photo}, index {index}) names a photo that is not in the library"
        ));
    }
    let mut stmt = conn.prepare(
        "SELECT photo_id, idx, snapshot_hash FROM history_steps \
         WHERE snapshot_hash NOT IN (SELECT hash FROM snapshots) \
         ORDER BY photo_id, idx",
    )?;
    let rows: Vec<(i64, i64, String)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
        .collect::<Result<_, _>>()?;
    for (photo, index, hash) in rows {
        capped.push(format!(
            "history step (photo {photo}, index {index}) names snapshot {hash} which is missing"
        ));
    }
    let mut stmt = conn.prepare(
        "SELECT id, current_hash FROM photos \
         WHERE current_hash NOT IN (SELECT hash FROM snapshots) \
         ORDER BY id",
    )?;
    let rows: Vec<(i64, String)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<_, _>>()?;
    for (photo, hash) in rows {
        capped.push(format!(
            "photo {photo} names current snapshot {hash} which is missing"
        ));
    }
    let mut stmt = conn.prepare(
        "SELECT photo_id, keyword_id FROM photo_keywords \
         WHERE photo_id NOT IN (SELECT id FROM photos) \
         OR keyword_id NOT IN (SELECT id FROM keywords) \
         ORDER BY photo_id, keyword_id",
    )?;
    let rows: Vec<(i64, i64)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<_, _>>()?;
    for (photo, keyword) in rows {
        capped.push(format!(
            "keyword link (photo {photo}, keyword {keyword}) names a row that is not in the library"
        ));
    }
    let mut stmt = conn.prepare(
        "SELECT album_id, photo_id FROM album_photos \
         WHERE album_id NOT IN (SELECT id FROM albums) \
         OR photo_id NOT IN (SELECT id FROM photos) \
         ORDER BY album_id, photo_id",
    )?;
    let rows: Vec<(i64, i64)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<_, _>>()?;
    for (album, photo) in rows {
        capped.push(format!(
            "album link (album {album}, photo {photo}) names a row that is not in the library"
        ));
    }
    capped.finish();
    Ok(())
}

/// Cursors that point past their photo's steps (or anywhere with no steps).
fn check_cursors(conn: &Connection, out: &mut Vec<Finding>) -> Result<(), CatalogError> {
    let mut stmt = conn.prepare("SELECT id, cursor FROM photos ORDER BY id")?;
    let photos: Vec<(i64, i64)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<_, _>>()?;
    let mut stmt =
        conn.prepare("SELECT photo_id, COUNT(*) FROM history_steps GROUP BY photo_id")?;
    let counts: Vec<(i64, i64)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<_, _>>()?;
    let steps_of: BTreeMap<i64, i64> = counts.into_iter().collect();
    let mut capped = capped(
        out,
        Severity::Warning,
        "cursor_out_of_range",
        "session.restore",
    );
    for (photo, cursor) in photos {
        let steps = steps_of.get(&photo).copied().unwrap_or(0);
        if steps == 0 {
            if cursor != 0 {
                capped.push(format!(
                    "photo {photo} holds no history steps but its cursor is {cursor}"
                ));
            }
        } else if cursor < 0 || cursor >= steps {
            capped.push(format!(
                "photo {photo} holds {steps} history steps but its cursor is {cursor}"
            ));
        }
    }
    capped.finish();
    Ok(())
}

/// `photos.process` against the process number inside the current snapshot.
fn check_process_mirror(conn: &Connection, out: &mut Vec<Finding>) -> Result<(), CatalogError> {
    let mut stmt = conn.prepare("SELECT id, process, current_hash FROM photos ORDER BY id")?;
    let photos: Vec<(i64, i64, String)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
        .collect::<Result<_, _>>()?;
    let mut stmt = conn.prepare("SELECT json FROM snapshots WHERE hash = ?1")?;
    let mut capped = capped(
        out,
        Severity::Warning,
        "process_mirror_mismatch",
        "session.restore",
    );
    for (photo, mirror, hash) in photos {
        let stored: Option<String> = stmt
            .query_map([&hash], |row| row.get(0))?
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .next();
        let Some(json) = stored else {
            continue; // the dangling check already reported the missing snapshot
        };
        match snapshot_process(&json) {
            Some(inside) if inside == mirror => {}
            Some(inside) => capped.push(format!(
                "photo {photo} mirrors process {mirror} but its current snapshot holds {inside}"
            )),
            None => capped.push(format!(
                "photo {photo} mirrors process {mirror} but its current snapshot has no readable process number"
            )),
        }
    }
    capped.finish();
    Ok(())
}

/// The top-level `process` number of a snapshot document, if it parses.
fn snapshot_process(json: &str) -> Option<i64> {
    serde_json::from_str::<serde_json::Value>(json)
        .ok()?
        .get("process")?
        .as_i64()
}

/// The `display_aux` row must parse (readers treat an unparseable row as
/// empty; only the owning writer command may replace it).
fn check_display_aux(conn: &Connection, out: &mut Vec<Finding>) -> Result<(), CatalogError> {
    if matches!(
        display_aux_read(conn)?,
        DisplayAuxRead { corrupt: true, .. }
    ) {
        out.push(Finding {
            severity: Severity::Warning,
            code: "display_aux_unparseable",
            detail: "the display_aux row does not parse; readers see empty parameters".to_owned(),
            repair: "display.set",
        });
    }
    Ok(())
}

/// Stored photo paths resolve inside the session (or absolutely outside it)
/// and name files that exist. Above [`VERIFY_INLINE_PATH_LIMIT`] photos the
/// per-file walk is deferred to the background scan instead.
fn check_paths(conn: &Connection, root: &Path, out: &mut Vec<Finding>) -> Result<(), CatalogError> {
    let count: i64 = conn.query_row("SELECT COUNT(*) FROM photos", [], |row| row.get(0))?;
    if usize::try_from(count).is_ok_and(|have| have > VERIFY_INLINE_PATH_LIMIT) {
        out.push(Finding {
            severity: Severity::Info,
            code: "path_scan_deferred",
            detail: format!(
                "the library holds {count} photos, above the inline existence-check limit {VERIFY_INLINE_PATH_LIMIT}; the background scan covers them"
            ),
            repair: "library.sync",
        });
        return Ok(());
    }
    let mut stmt = conn.prepare("SELECT id, path, path_kind FROM photos ORDER BY id")?;
    let rows: Vec<(i64, String, i64)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
        .collect::<Result<_, _>>()?;
    // Two passes: each capped sink borrows the report alone.
    let mut invalid = capped(
        out,
        Severity::Warning,
        "stored_path_invalid",
        "library.relink",
    );
    for (photo, stored, kind) in &rows {
        let resolved = PathKind::from_db(*kind).and_then(|set| to_absolute(root, set, stored).ok());
        if resolved.is_none() {
            invalid.push(invalid_detail(*photo, *kind, stored));
        }
    }
    invalid.finish();
    let mut missing = capped(out, Severity::Warning, "missing_file", "library.relink");
    for (photo, stored, kind) in &rows {
        let resolved = PathKind::from_db(*kind).and_then(|set| to_absolute(root, set, stored).ok());
        if let Some(resolved) = resolved
            && !resolved.exists()
        {
            missing.push(format!(
                "photo {photo} names {} which is not on disk",
                resolved.display()
            ));
        }
    }
    missing.finish();
    Ok(())
}

fn invalid_detail(photo: i64, kind: i64, stored: &str) -> String {
    format!("photo {photo} stores path kind {kind} with text {stored:?} which does not resolve")
}
