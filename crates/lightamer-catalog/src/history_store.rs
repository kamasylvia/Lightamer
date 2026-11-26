// SPDX-License-Identifier: GPL-3.0-or-later
//! Photo history in the session database: the write path, the cursor, reads,
//! and orphan snapshots.
//!
//! One step is one transaction: finding or storing the snapshot row,
//! inserting the step, and updating the photo row happen inside a single
//! [`HistoryWriter`] transaction. The writer takes settings text the caller
//! already computed (PLAN-B §1.8: the database is the truth, memory its
//! mirror); it parses that text only to read the process number for the
//! photo-row mirror, and refuses text that does not parse before writing a
//! byte.
//!
//! Snapshot keys default to the decimal FNV-1a of the canonical JSON (the
//! same bytes [`PhotoSettings::hash64_decimal`] hashes). A key is only a
//! lookup: on a hit the stored bytes are compared byte for byte, and a
//! mismatch is stored as a new row under a `#2`-style suffix, reported to
//! the caller through [`PushOutcome::collided`].

use std::time::{Duration, Instant};

use lightamer_history::{HISTORY_LIMIT, PhotoSettings};
use rusqlite::{Connection, OptionalExtension, Transaction, params};

use crate::error::CatalogError;

/// Label of step 0, written when a photo is registered.
///
/// NOTE (B13′-a finding, for B13′-b): the in-memory [`HistoryStack`] starts
/// its first step with label `"import"`, not this. The brief mandates
/// `"seed"` here, so the stored step 0 and a fresh in-memory step 0 differ
/// in label today; B13′-b must reconcile them (flip one constant).
///
/// [`HistoryStack`]: lightamer_history::HistoryStack
pub const SEED_LABEL: &str = "seed";

/// Where one pushed step landed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PushOutcome {
    /// The photo the step was pushed to.
    pub photo_id: i64,
    /// The step's index after trimming (`history_steps.idx`).
    pub idx: i64,
    /// The snapshot row the step points at (base key, or a `#2`-style key
    /// after a hash collision).
    pub snapshot_hash: String,
    /// True when this push stored a new snapshot row under a suffixed key
    /// (a new collision recorded). Reusing any existing row — base or
    /// suffixed — reports false.
    pub collided: bool,
    /// The photo's cursor after the push.
    pub cursor: i64,
    /// The photo's step count after the push.
    pub steps: i64,
}

/// Where a cursor move landed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MoveOutcome {
    /// The cursor after the move (the requested target).
    pub cursor: i64,
    /// The photo's step count (unchanged by the move).
    pub steps: i64,
    /// The canonical JSON of the settings under the cursor after the move.
    pub settings_json: String,
}

/// One stored step: its label plus the snapshot text it points at.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryStepRead {
    /// The step's index (`history_steps.idx`, 0-based, contiguous).
    pub idx: i64,
    /// The label the step was committed with.
    pub label: String,
    /// The snapshot row the step points at.
    pub snapshot_hash: String,
    /// The snapshot's canonical JSON.
    pub settings_json: String,
}

/// A photo's whole history: every step oldest-first plus the cursor.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryRead {
    /// The photo this history belongs to.
    pub photo_id: i64,
    /// The cursor (`photos.cursor`).
    pub cursor: i64,
    /// Every step, oldest first.
    pub steps: Vec<HistoryStepRead>,
}

/// How long one writer's pushes spent in each of the three phases.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PushStats {
    /// Finding or storing snapshot rows.
    pub snapshot: Duration,
    /// Deleting redo steps, inserting the step, trimming past the limit.
    pub steps: Duration,
    /// Updating the photo row (cursor, current snapshot, process mirror).
    pub photos: Duration,
    /// How many pushes these totals cover.
    pub pushes: u64,
}

impl PushStats {
    /// The three phases added together (saturating).
    #[must_use]
    pub fn total(&self) -> Duration {
        self.snapshot
            .saturating_add(self.steps)
            .saturating_add(self.photos)
    }
}

/// A stored snapshot row plus whether storing it recorded a new collision.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SnapshotStored {
    /// The row's key (base key, or a `#2`-style key after a collision).
    pub key: String,
    /// True when a new row was inserted under a suffixed key.
    pub collided: bool,
}

/// An open history transaction: push any number of steps, then commit.
///
/// Dropping the writer without [`HistoryWriter::commit`] rolls every pushed
/// step back, so a failed push in the middle leaves the database exactly as
/// it was before [`HistoryWriter::begin`].
pub struct HistoryWriter<'c> {
    tx: Transaction<'c>,
    key_override: Option<String>,
    stats: PushStats,
}

impl<'c> HistoryWriter<'c> {
    /// Opens a history transaction on `conn`.
    ///
    /// # Errors
    ///
    /// [`CatalogError::Sql`] when SQLite refuses the transaction.
    pub fn begin(conn: &'c mut Connection) -> Result<Self, CatalogError> {
        Ok(Self {
            tx: conn.transaction()?,
            key_override: None,
            stats: PushStats::default(),
        })
    }

    /// Pushes one step inside the transaction: stores (or reuses) the
    /// snapshot row for `canonical_json`, drops the redo steps past the
    /// cursor, inserts the new step at cursor + 1, trims past
    /// [`HISTORY_LIMIT`], and updates the photo row's cursor, current
    /// snapshot, and process mirror in one `UPDATE`.
    ///
    /// # Errors
    ///
    /// [`CatalogError::BadSettings`] when the text does not parse as
    /// settings (nothing written, the writer stays usable);
    /// [`CatalogError::UnknownPhoto`] when the photo is not in the library
    /// (nothing written); [`CatalogError::Sql`] when SQLite refuses a step.
    pub fn push(
        &mut self,
        photo_id: i64,
        label: &str,
        canonical_json: &str,
    ) -> Result<PushOutcome, CatalogError> {
        let process = settings_process(canonical_json)?;
        let cursor: Option<i64> = self
            .tx
            .query_row(
                "SELECT cursor FROM photos WHERE id = ?1",
                [photo_id],
                |row| row.get(0),
            )
            .optional()?;
        let Some(cursor) = cursor else {
            return Err(CatalogError::UnknownPhoto(photo_id));
        };

        let start = Instant::now();
        let stored = store_snapshot(&self.tx, canonical_json, self.key_override.as_deref())?;
        self.stats.snapshot = self.stats.snapshot.saturating_add(start.elapsed());

        let start = Instant::now();
        self.tx.execute(
            "DELETE FROM history_steps WHERE photo_id = ?1 AND idx > ?2",
            params![photo_id, cursor],
        )?;
        let next = cursor.saturating_add(1);
        let now = now_unix();
        self.tx.execute(
            "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![photo_id, next, label, stored.key, now],
        )?;
        let (cursor, steps) = self.enforce_limit(photo_id, next)?;
        self.stats.steps = self.stats.steps.saturating_add(start.elapsed());

        let start = Instant::now();
        let changed = self.tx.execute(
            "UPDATE photos SET cursor = ?1, current_hash = ?2, process = ?3 WHERE id = ?4",
            params![cursor, stored.key, process, photo_id],
        )?;
        self.stats.photos = self.stats.photos.saturating_add(start.elapsed());
        if changed != 1 {
            return Err(CatalogError::UnknownPhoto(photo_id));
        }
        self.stats.pushes = self.stats.pushes.saturating_add(1);
        Ok(PushOutcome {
            photo_id,
            idx: cursor,
            snapshot_hash: stored.key,
            collided: stored.collided,
            cursor,
            steps,
        })
    }

    /// Commits every pushed step.
    ///
    /// # Errors
    ///
    /// [`CatalogError::Sql`] when SQLite refuses the commit.
    pub fn commit(self) -> Result<(), CatalogError> {
        Ok(self.tx.commit()?)
    }

    /// The phase totals of this writer's pushes so far.
    #[must_use]
    pub fn stats(&self) -> &PushStats {
        &self.stats
    }

    /// Forces the snapshot base key for every later push (test only).
    ///
    /// Production pushes always hash the settings text; this override lets
    /// a test feed two different settings the same key and prove the
    /// collision path stores two rows and reports the collision.
    pub fn inject_snapshot_key_for_test(&mut self, key: &str) {
        self.key_override = Some(key.to_owned());
    }

    /// Trims a photo's steps to [`HISTORY_LIMIT`], renumbering the rest from
    /// 0 and shifting the cursor with them. Returns the new cursor and the
    /// new step count.
    fn enforce_limit(&self, photo_id: i64, inserted: i64) -> Result<(i64, i64), CatalogError> {
        let count: i64 = self.tx.query_row(
            "SELECT COUNT(*) FROM history_steps WHERE photo_id = ?1",
            [photo_id],
            |row| row.get(0),
        )?;
        let limit = step_limit()?;
        if count <= limit {
            return Ok((inserted, count));
        }
        let drop = count - limit;
        let min: Option<i64> = self.tx.query_row(
            "SELECT MIN(idx) FROM history_steps WHERE photo_id = ?1",
            [photo_id],
            |row| row.get(0),
        )?;
        let Some(min) = min else {
            return Err(CatalogError::Setup(format!(
                "photo {photo_id} counted {count} steps but holds none"
            )));
        };
        let cutoff = min.saturating_add(drop);
        self.tx.execute(
            "DELETE FROM history_steps WHERE photo_id = ?1 AND idx < ?2",
            params![photo_id, cutoff],
        )?;
        let remaining: Vec<i64> = {
            let mut select = self
                .tx
                .prepare("SELECT idx FROM history_steps WHERE photo_id = ?1 ORDER BY idx")?;
            select
                .query_map([photo_id], |row| row.get(0))?
                .collect::<Result<_, _>>()?
        };
        // Ascending: each target sits below every not-yet-moved row, so the
        // primary key never collides mid-loop.
        for (position, old) in remaining.iter().enumerate() {
            let renumbered = i64::try_from(position)
                .map_err(|_| CatalogError::Setup("step index overflowed".to_owned()))?;
            if *old != renumbered {
                self.tx.execute(
                    "UPDATE history_steps SET idx = ?1 WHERE photo_id = ?2 AND idx = ?3",
                    params![renumbered, photo_id, old],
                )?;
            }
        }
        Ok((inserted.saturating_sub(drop), limit))
    }
}

/// Pushes one step and commits: [`HistoryWriter`] opened, pushed once, and
/// committed. Most engine commands land here.
///
/// # Errors
///
/// See [`HistoryWriter::push`]; a failed push commits nothing.
pub fn push_step(
    conn: &mut Connection,
    photo_id: i64,
    label: &str,
    canonical_json: &str,
) -> Result<PushOutcome, CatalogError> {
    let mut writer = HistoryWriter::begin(conn)?;
    let outcome = writer.push(photo_id, label, canonical_json)?;
    writer.commit()?;
    Ok(outcome)
}

/// Moves a photo's cursor to `target` (undo/redo/goto): one `UPDATE` sets
/// the cursor, the current snapshot, and the process mirror together. No
/// step is added or removed.
///
/// Returns the settings now under the cursor.
///
/// # Errors
///
/// [`CatalogError::UnknownPhoto`] when the photo is not in the library;
/// [`CatalogError::CursorOutOfRange`] when the target is not a step
/// (nothing written); [`CatalogError::Setup`] when the stored rows are
/// damaged (a missing step or snapshot the verify pass would report);
/// [`CatalogError::Sql`] when SQLite refuses a step.
pub fn move_cursor(
    conn: &Connection,
    photo_id: i64,
    target: i64,
) -> Result<MoveOutcome, CatalogError> {
    let known: Option<i64> = conn
        .query_row(
            "SELECT cursor FROM photos WHERE id = ?1",
            [photo_id],
            |row| row.get(0),
        )
        .optional()?;
    if known.is_none() {
        return Err(CatalogError::UnknownPhoto(photo_id));
    }
    let steps: i64 = conn.query_row(
        "SELECT COUNT(*) FROM history_steps WHERE photo_id = ?1",
        [photo_id],
        |row| row.get(0),
    )?;
    if target < 0 || target >= steps {
        return Err(CatalogError::CursorOutOfRange {
            photo_id,
            target,
            steps,
        });
    }
    let hash: Option<String> = conn
        .query_row(
            "SELECT snapshot_hash FROM history_steps WHERE photo_id = ?1 AND idx = ?2",
            params![photo_id, target],
            |row| row.get(0),
        )
        .optional()?;
    let Some(hash) = hash else {
        return Err(CatalogError::Setup(format!(
            "photo {photo_id} holds {steps} steps but step {target} is missing"
        )));
    };
    let json: Option<String> = conn
        .query_row(
            "SELECT json FROM snapshots WHERE hash = ?1",
            [&hash],
            |row| row.get(0),
        )
        .optional()?;
    let Some(json) = json else {
        return Err(CatalogError::Setup(format!(
            "photo {photo_id} step {target} names snapshot {hash} which is missing"
        )));
    };
    let process = settings_process(&json)?;
    let changed = conn.execute(
        "UPDATE photos SET cursor = ?1, current_hash = ?2, process = ?3 WHERE id = ?4",
        params![target, hash, process, photo_id],
    )?;
    if changed != 1 {
        return Err(CatalogError::UnknownPhoto(photo_id));
    }
    Ok(MoveOutcome {
        cursor: target,
        steps,
        settings_json: json,
    })
}

/// Reads a photo's whole history: every step oldest-first with its label
/// and snapshot text, plus the cursor. The caller rebuilds an in-memory
/// stack from this with the history model's own calls.
///
/// # Errors
///
/// [`CatalogError::UnknownPhoto`] when the photo is not in the library;
/// [`CatalogError::Sql`] when SQLite refuses a read.
pub fn read_history(conn: &Connection, photo_id: i64) -> Result<HistoryRead, CatalogError> {
    let cursor: Option<i64> = conn
        .query_row(
            "SELECT cursor FROM photos WHERE id = ?1",
            [photo_id],
            |row| row.get(0),
        )
        .optional()?;
    let Some(cursor) = cursor else {
        return Err(CatalogError::UnknownPhoto(photo_id));
    };
    let mut select = conn.prepare(
        "SELECT s.idx, s.label, s.snapshot_hash, n.json \
         FROM history_steps AS s JOIN snapshots AS n ON n.hash = s.snapshot_hash \
         WHERE s.photo_id = ?1 ORDER BY s.idx",
    )?;
    let steps: Vec<HistoryStepRead> = select
        .query_map([photo_id], |row| {
            Ok(HistoryStepRead {
                idx: row.get(0)?,
                label: row.get(1)?,
                snapshot_hash: row.get(2)?,
                settings_json: row.get(3)?,
            })
        })?
        .collect::<Result<_, _>>()?;
    Ok(HistoryRead {
        photo_id,
        cursor,
        steps,
    })
}

/// Every orphan snapshot key: no step points at it and no photo holds it as
/// current. One query, ordered by key.
///
/// This is the single definition the verify pass reports from.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the read.
pub fn orphan_snapshot_hashes(conn: &Connection) -> Result<Vec<String>, CatalogError> {
    let mut select = conn.prepare(
        "SELECT hash FROM snapshots \
         WHERE hash NOT IN (SELECT snapshot_hash FROM history_steps) \
         AND hash NOT IN (SELECT current_hash FROM photos) \
         ORDER BY hash",
    )?;
    Ok(select
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?)
}

/// Deletes every orphan snapshot (see [`orphan_snapshot_hashes`]) and
/// returns how many rows went away. Callers run this inside their own
/// transaction (close does).
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the delete.
pub fn delete_orphan_snapshots(conn: &Connection) -> Result<u64, CatalogError> {
    conn.execute(
        "DELETE FROM snapshots \
         WHERE hash NOT IN (SELECT snapshot_hash FROM history_steps) \
         AND hash NOT IN (SELECT current_hash FROM photos)",
        [],
    )?;
    Ok(conn.changes())
}

/// Stores the snapshot row for `json` inside `tx`: the base key is the
/// forced key when a test injected one, else the decimal FNV-1a of the
/// bytes. A hit reuses the row only when the stored bytes match byte for
/// byte; a mismatch stores a new row under the next `#2`-style suffix.
///
/// [`Transaction`]: rusqlite::Transaction
pub(crate) fn store_snapshot(
    tx: &Transaction,
    json: &str,
    key_override: Option<&str>,
) -> Result<SnapshotStored, CatalogError> {
    let base = key_override.map_or_else(|| snapshot_key_for(json), str::to_owned);
    let mut key = base.clone();
    let mut suffix = 1_i64;
    loop {
        let stored: Option<String> = tx
            .query_row(
                "SELECT json FROM snapshots WHERE hash = ?1",
                [&key],
                |row| row.get(0),
            )
            .optional()?;
        match stored {
            None => {
                tx.execute(
                    "INSERT INTO snapshots (hash, json) VALUES (?1, ?2)",
                    params![key, json],
                )?;
                return Ok(SnapshotStored {
                    collided: key != base,
                    key,
                });
            }
            Some(text) if text == json => {
                return Ok(SnapshotStored {
                    key,
                    collided: false,
                });
            }
            Some(_) => {
                suffix = suffix.saturating_add(1);
                key = format!("{base}#{suffix}");
            }
        }
    }
}

/// The snapshot base key for settings text: FNV-1a over the bytes, decimal.
///
/// This mirrors `PhotoSettings::hash64` (`lightamer-history/src/settings.rs`,
/// same offset, prime, and fold); equality with `hash64_decimal` for
/// canonical input is pinned by test.
pub(crate) fn snapshot_key_for(json: &str) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in json.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0100_0000_01b3);
    }
    hash.to_string()
}

/// The process number inside settings text (the photo-row mirror reads it
/// from here, never from the column default).
pub(crate) fn settings_process(canonical_json: &str) -> Result<i64, CatalogError> {
    let settings =
        PhotoSettings::from_json(canonical_json).map_err(|source| CatalogError::BadSettings {
            reason: source.to_string(),
        })?;
    Ok(i64::from(settings.process.0))
}

/// Now as Unix seconds (0 when the clock refuses to answer).
pub(crate) fn now_unix() -> i64 {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |span| span.as_secs());
    i64::try_from(secs).unwrap_or(0)
}

/// [`HISTORY_LIMIT`] as a row count (it always fits; the error is typed so
/// the conversion never panics).
fn step_limit() -> Result<i64, CatalogError> {
    i64::try_from(HISTORY_LIMIT)
        .map_err(|_| CatalogError::Setup("step limit overflowed".to_owned()))
}
