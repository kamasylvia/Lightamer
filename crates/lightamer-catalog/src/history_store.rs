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

use std::collections::HashMap;
use std::time::{Duration, Instant};

use lightamer_history::{HISTORY_LIMIT, PhotoSettings};
use rusqlite::{Connection, OptionalExtension, Statement, Transaction, params, params_from_iter};

use crate::error::CatalogError;

/// Label of step 0, written when a photo is registered.
///
/// Re-exported from the history model so the stored step 0 and a fresh
/// in-memory stack share one source (B13′-b alignment, retiring the B13′-a
/// literal).
pub use lightamer_history::INITIAL_LABEL;

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

/// One step to push inside [`HistoryWriter::push_many`]: the photo, the
/// command label, and the already-computed canonical settings JSON.
#[derive(Clone, Copy, Debug)]
pub struct PushRequest<'a> {
    /// The photo's internal id (`photos.id`).
    pub photo_id: i64,
    /// The label the new step carries.
    pub label: &'a str,
    /// The already-computed canonical settings JSON.
    pub canonical_json: &'a str,
}

/// One photo's current state for the engine's batch fast path: enough to
/// compute and place a push without reading the whole history (see
/// [`read_photo_currents`]).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PhotoCurrent {
    /// The photo's outside identity.
    pub uuid: String,
    /// The photo's internal id.
    pub id: i64,
    /// The cursor (`photos.cursor`).
    pub cursor: i64,
    /// The step count.
    pub steps: i64,
    /// The highest step index (`-1` when the photo holds no step).
    pub max_idx: i64,
    /// The current settings' canonical JSON.
    pub settings_json: String,
}

/// One photo's push facts for [`HistoryWriter::push_many`]: the cursor, the
/// step count, and the highest step index, from the single batch query.
struct PushFacts {
    cursor: i64,
    steps: i64,
    max_idx: i64,
}

impl PushFacts {
    /// Whether the redo delete provably removes nothing: the cursor sits on
    /// the last step of contiguous steps from 0, so no row has `idx` past
    /// the cursor. Anything damaged (a gap, a cursor off the steps) answers
    /// false and the delete runs, exactly as before.
    fn redo_is_empty(&self) -> bool {
        self.cursor >= 0
            && self.cursor.saturating_add(1) == self.steps
            && self.max_idx.saturating_add(1) == self.steps
    }
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
    snapshot_cache: HashMap<String, SnapshotStored>,
    snapshot_cache_hits: u64,
    redo_skips: u64,
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
            snapshot_cache: HashMap::new(),
            snapshot_cache_hits: 0,
            redo_skips: 0,
        })
    }

    /// Pushes one step inside the transaction: stores (or reuses) the
    /// snapshot row for `canonical_json`, drops the redo steps past the
    /// cursor, inserts the new step at cursor + 1, trims past
    /// [`HISTORY_LIMIT`], and updates the photo row's cursor, current
    /// snapshot, and process mirror in one `UPDATE`.
    ///
    /// This is [`push_many`][Self::push_many] for a single step; the batch
    /// entry shares the one implementation, so single pushes and batch
    /// pushes cannot drift apart.
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
        let request = PushRequest {
            photo_id,
            label,
            canonical_json,
        };
        let mut outcomes = self.push_many(std::slice::from_ref(&request))?;
        outcomes
            .pop()
            .ok_or_else(|| CatalogError::Setup("push_many returned no outcome".to_owned()))
    }

    /// Pushes any number of steps inside the transaction: [`push`][Self::push]
    /// for a whole batch, with the per-push statements prepared once and
    /// held for every item.
    ///
    /// The batch runs in two phases. Validation first, in item order (each
    /// item's settings parse before its photo lookup, exactly the error
    /// precedence of pushing one by one): the photo facts for every item
    /// come from a single query. Execution second, in item order, through
    /// five held statements: the snapshot lookup/insert, the redo delete
    /// (skipped when the cursor provably sits on the last step of
    /// contiguous steps), the step insert, and the photo-row update. The
    /// same settings text pushed again inside this writer reuses its first
    /// resolution (one lookup, one byte comparison); snapshot rows only
    /// accumulate inside one transaction, so the reuse decides exactly what
    /// a second lookup would.
    ///
    /// Errors leave the writer exactly as [`push`][Self::push] does: a failed
    /// item writes nothing and the writer stays usable; dropping it without
    /// [`commit`][Self::commit] rolls every pushed step back.
    ///
    /// # Errors
    ///
    /// [`CatalogError::BadSettings`] when an item's text does not parse as
    /// settings; [`CatalogError::UnknownPhoto`] when an item names a photo
    /// that is not in the library; [`CatalogError::Sql`] when SQLite refuses
    /// a step.
    pub fn push_many(
        &mut self,
        items: &[PushRequest<'_>],
    ) -> Result<Vec<PushOutcome>, CatalogError> {
        let facts = batch_push_facts(&self.tx, items)?;
        let mut validated = Vec::with_capacity(items.len());
        for item in items {
            let process = settings_process(item.canonical_json)?;
            let Some(fact) = facts.get(&item.photo_id) else {
                return Err(CatalogError::UnknownPhoto(item.photo_id));
            };
            validated.push((item, process, fact));
        }
        // Borrowed fields, not `self`: the held statements borrow `tx`
        // while the loop also advances the cache, the counters, and `stats`.
        let Self {
            tx,
            key_override,
            stats,
            snapshot_cache,
            snapshot_cache_hits,
            redo_skips,
        } = self;
        let mut select_snapshot = tx.prepare("SELECT json FROM snapshots WHERE hash = ?1")?;
        let mut insert_snapshot =
            tx.prepare("INSERT INTO snapshots (hash, json) VALUES (?1, ?2)")?;
        let mut delete_redo =
            tx.prepare("DELETE FROM history_steps WHERE photo_id = ?1 AND idx > ?2")?;
        let mut insert_step = tx.prepare(
            "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5)",
        )?;
        let mut update_photo = tx.prepare(
            "UPDATE photos SET cursor = ?1, current_hash = ?2, process = ?3 WHERE id = ?4",
        )?;
        let limit = step_limit()?;
        // Running (cursor, steps) per photo: a photo named twice in one
        // batch pushes onto its own first push, exactly as sequential pushes
        // would (every push lands the cursor on the new step, so a second
        // push always finds the cursor at the end).
        let mut progress: HashMap<i64, (i64, i64)> = HashMap::new();
        let mut outcomes = Vec::with_capacity(items.len());
        for (item, process, initial) in validated {
            let (cursor, steps, at_end) = match progress.get(&item.photo_id) {
                Some((cursor, steps)) => (*cursor, *steps, true),
                None => (initial.cursor, initial.steps, initial.redo_is_empty()),
            };

            let start = Instant::now();
            let stored = if let Some(hit) = snapshot_cache.get(item.canonical_json) {
                *snapshot_cache_hits = snapshot_cache_hits.saturating_add(1);
                hit.clone()
            } else {
                let stored = resolve_snapshot(
                    &mut select_snapshot,
                    &mut insert_snapshot,
                    item.canonical_json,
                    key_override.as_deref(),
                )?;
                snapshot_cache.insert(item.canonical_json.to_owned(), stored.clone());
                stored
            };
            stats.snapshot = stats.snapshot.saturating_add(start.elapsed());

            let start = Instant::now();
            let removed = if at_end {
                *redo_skips = redo_skips.saturating_add(1);
                0
            } else {
                delete_redo.execute(params![item.photo_id, cursor])?
            };
            let next = cursor.saturating_add(1);
            let now = now_unix();
            insert_step.execute(params![item.photo_id, next, item.label, stored.key, now])?;
            let removed = i64::try_from(removed).unwrap_or(i64::MAX);
            let after_insert = steps.saturating_sub(removed).saturating_add(1);
            let (cursor, steps) = if after_insert <= limit {
                (next, after_insert)
            } else {
                trim_to_limit(tx, item.photo_id, next, after_insert)?
            };
            stats.steps = stats.steps.saturating_add(start.elapsed());

            let start = Instant::now();
            let changed =
                update_photo.execute(params![cursor, stored.key, process, item.photo_id])?;
            stats.photos = stats.photos.saturating_add(start.elapsed());
            if changed != 1 {
                return Err(CatalogError::UnknownPhoto(item.photo_id));
            }
            stats.pushes = stats.pushes.saturating_add(1);
            progress.insert(item.photo_id, (cursor, steps));
            outcomes.push(PushOutcome {
                photo_id: item.photo_id,
                idx: cursor,
                snapshot_hash: stored.key,
                collided: stored.collided,
                cursor,
                steps,
            });
        }
        Ok(outcomes)
    }

    /// Commits every pushed step.
    ///
    /// # Errors
    ///
    /// [`CatalogError::Sql`] when SQLite refuses the commit.
    pub fn commit(self) -> Result<(), CatalogError> {
        Ok(self.tx.commit()?)
    }

    /// Moves a photo's cursor inside this transaction: [`move_cursor`] on the
    /// open transaction instead of a fresh one. A command that both commits
    /// (ending a drag) and moves (undo/redo/goto) lands both in the single
    /// transaction the command commits.
    ///
    /// # Errors
    ///
    /// See [`move_cursor`]; a failed move writes nothing and the writer stays
    /// usable (dropping it without [`HistoryWriter::commit`] rolls back).
    pub fn move_cursor(&self, photo_id: i64, target: i64) -> Result<MoveOutcome, CatalogError> {
        move_cursor(&self.tx, photo_id, target)
    }

    /// The phase totals of this writer's pushes so far.
    #[must_use]
    pub fn stats(&self) -> &PushStats {
        &self.stats
    }

    /// How many snapshot resolutions this writer served from its
    /// within-writer cache: the same settings text pushed again costs no
    /// second lookup and no second byte comparison.
    #[must_use]
    pub fn snapshot_cache_hits(&self) -> u64 {
        self.snapshot_cache_hits
    }

    /// How many pushes skipped the redo delete because the cursor provably
    /// sat on the last step of contiguous steps (no row could match it).
    #[must_use]
    pub fn redo_delete_skips(&self) -> u64 {
        self.redo_skips
    }

    /// Forces the snapshot base key for every later push (test only).
    ///
    /// Production pushes always hash the settings text; this override lets
    /// a test feed two different settings the same key and prove the
    /// collision path stores two rows and reports the collision.
    pub fn inject_snapshot_key_for_test(&mut self, key: &str) {
        self.key_override = Some(key.to_owned());
        // A new forced base re-resolves every text: cached resolutions
        // belong to the previous base.
        self.snapshot_cache.clear();
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

/// The current state of every photo in `uuids`, in one query: each photo's
/// store id, cursor, step count, highest step index, and current settings
/// text. Photos that are not in the library have no entry; the caller
/// reports the first missing one in batch order. A photo whose current
/// snapshot row is gone is damaged ([`CatalogError::Setup`]).
///
/// # Errors
///
/// [`CatalogError::Setup`] when a matched photo's current snapshot is
/// missing; [`CatalogError::Sql`] when SQLite refuses the read.
pub fn read_photo_currents(
    conn: &Connection,
    uuids: &[String],
) -> Result<Vec<PhotoCurrent>, CatalogError> {
    if uuids.is_empty() {
        return Ok(Vec::new());
    }
    let mut sql = String::from(
        "SELECT p.uuid, p.id, p.cursor, \
         (SELECT COUNT(*) FROM history_steps WHERE photo_id = p.id), \
         (SELECT COALESCE(MAX(idx), -1) FROM history_steps WHERE photo_id = p.id), \
         p.current_hash, s.json \
         FROM photos AS p LEFT JOIN snapshots AS s ON s.hash = p.current_hash \
         WHERE p.uuid IN (",
    );
    for position in 0..uuids.len() {
        if position > 0 {
            sql.push_str(", ");
        }
        sql.push('?');
    }
    sql.push(')');
    let mut select = conn.prepare(&sql)?;
    let rows = select.query_map(params_from_iter(uuids.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, i64>(2)?,
            row.get::<_, i64>(3)?,
            row.get::<_, i64>(4)?,
            row.get::<_, String>(5)?,
            row.get::<_, Option<String>>(6)?,
        ))
    })?;
    let mut currents = Vec::with_capacity(uuids.len());
    for row in rows {
        let (uuid, id, cursor, steps, max_idx, current_hash, json) = row?;
        let Some(settings_json) = json else {
            return Err(CatalogError::Setup(format!(
                "photo {id} current snapshot {current_hash} is missing"
            )));
        };
        currents.push(PhotoCurrent {
            uuid,
            id,
            cursor,
            steps,
            max_idx,
            settings_json,
        });
    }
    Ok(currents)
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

/// Every batch item's push facts in one query: the cursor, the step count,
/// and the highest step index per photo. Photos that are not in the library
/// simply have no entry; the caller reports the first missing one in item
/// order.
fn batch_push_facts(
    tx: &Transaction,
    items: &[PushRequest<'_>],
) -> Result<HashMap<i64, PushFacts>, CatalogError> {
    let mut found = HashMap::with_capacity(items.len());
    if items.is_empty() {
        return Ok(found);
    }
    let mut sql = String::from(
        "SELECT p.id, p.cursor, COUNT(s.idx), COALESCE(MAX(s.idx), -1) \
         FROM photos AS p LEFT JOIN history_steps AS s ON s.photo_id = p.id \
         WHERE p.id IN (",
    );
    for position in 0..items.len() {
        if position > 0 {
            sql.push_str(", ");
        }
        sql.push('?');
    }
    sql.push_str(") GROUP BY p.id");
    let mut select = tx.prepare(&sql)?;
    let ids = items.iter().map(|item| item.photo_id);
    let rows = select.query_map(params_from_iter(ids), |row| {
        Ok((
            row.get::<_, i64>(0)?,
            PushFacts {
                cursor: row.get(1)?,
                steps: row.get(2)?,
                max_idx: row.get(3)?,
            },
        ))
    })?;
    for row in rows {
        let (id, facts) = row?;
        found.insert(id, facts);
    }
    Ok(found)
}

/// Resolves the snapshot row for `json` through the batch's held statements:
/// the base key is the forced key when a test injected one, else the decimal
/// FNV-1a of the bytes. A hit reuses the row only when the stored bytes
/// match byte for byte; a mismatch stores a new row under the next
/// `#2`-style suffix. The same rule as [`store_snapshot`], which keeps
/// serving single-statement callers (photo registration).
fn resolve_snapshot(
    select: &mut Statement,
    insert: &mut Statement,
    json: &str,
    key_override: Option<&str>,
) -> Result<SnapshotStored, CatalogError> {
    let base = key_override.map_or_else(|| snapshot_key_for(json), str::to_owned);
    let mut key = base.clone();
    let mut suffix = 1_i64;
    loop {
        let found: Option<String> = select.query_row([&key], |row| row.get(0)).optional()?;
        match found {
            None => {
                insert.execute(params![key, json])?;
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

/// Trims a photo's steps to [`HISTORY_LIMIT`] after an insert left
/// `count_after` rows: deletes the oldest rows, renumbers the rest from 0,
/// and shifts the cursor with them. Returns the new cursor and the new step
/// count. Only the over-limit path calls this; within-limit pushes place the
/// step from the already-known counts without another query.
fn trim_to_limit(
    tx: &Transaction,
    photo_id: i64,
    inserted: i64,
    count_after: i64,
) -> Result<(i64, i64), CatalogError> {
    let limit = step_limit()?;
    let drop = count_after.saturating_sub(limit);
    let min: Option<i64> = tx.query_row(
        "SELECT MIN(idx) FROM history_steps WHERE photo_id = ?1",
        [photo_id],
        |row| row.get(0),
    )?;
    let Some(min) = min else {
        return Err(CatalogError::Setup(format!(
            "photo {photo_id} counted {count_after} steps but holds none"
        )));
    };
    let cutoff = min.saturating_add(drop);
    tx.execute(
        "DELETE FROM history_steps WHERE photo_id = ?1 AND idx < ?2",
        params![photo_id, cutoff],
    )?;
    let remaining: Vec<i64> = {
        let mut select =
            tx.prepare("SELECT idx FROM history_steps WHERE photo_id = ?1 ORDER BY idx")?;
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
            tx.execute(
                "UPDATE history_steps SET idx = ?1 WHERE photo_id = ?2 AND idx = ?3",
                params![renumbered, photo_id, old],
            )?;
        }
    }
    Ok((inserted.saturating_sub(drop), limit))
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
