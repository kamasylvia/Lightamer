// SPDX-License-Identifier: GPL-3.0-or-later
//! The real-session path of the edit, history, and process commands.
//!
//! Draft bodies live beside the specs (`develop`, `history`); each one hands
//! off here when a real session is open. Every function below runs PLAN-B
//! §1.8: **compute** the new stacks in memory (this half may fail, and the
//! store is untouched then), **commit** one store transaction (single-step
//! commands through [`push_step`][lightamer_catalog::push_step] /
//! [`move_cursor`][lightamer_catalog::move_cursor], anything wider through
//! one [`HistoryWriter`][lightamer_catalog::HistoryWriter]), then **swap**
//! the computed stacks into the cache (infallible: the stacks were fully
//! computed before the commit). Any error leaves memory and the store
//! unchanged; loading a photo only adds a mirror of committed store rows.
//!
//! Drags stay memory-only until they end: begin/update never touch the store,
//! and end commits exactly the step [`HistoryStack::pending_interaction`]
//! reports. Commands that would end a drag in memory (`set`, `reset`,
//! `paste`, `undo`, `redo`, `goto`, `process.update`, `begin`) settle it on
//! the probe first, so the store learns the drag's step inside the same
//! single transaction.
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::{Map, Value, json};

use crate::command::{Outcome, RunCtx, id_req, ids_req, uint_req};
use crate::develop::{SetArgs, full_selection, merged_settings, parse_selection, set_args};
use crate::engine::Engine;
use crate::error::CommandError;
use crate::event::Event;

/// Stopwatch splitting one batch command into the three thirds the bench
/// reports: explicit store-fetch spans accumulate into `read`, the commit
/// span into `write`, and `compute` is the rest (settings, serialization,
/// the infallible swap-in, events), derived by subtraction so the three add
/// up to the whole command.
struct PhaseClock {
    start: Instant,
    read: Duration,
    write: Duration,
}

impl PhaseClock {
    fn start() -> Self {
        Self {
            start: Instant::now(),
            read: Duration::ZERO,
            write: Duration::ZERO,
        }
    }

    fn add_read(&mut self, span: Duration) {
        self.read = self.read.saturating_add(span);
    }

    fn add_write(&mut self, span: Duration) {
        self.write = self.write.saturating_add(span);
    }

    fn finish(self, engine: &mut Engine) {
        let compute = self
            .start
            .elapsed()
            .saturating_sub(self.read)
            .saturating_sub(self.write);
        engine.set_last_phases(crate::engine::CommandPhases {
            read: self.read,
            compute,
            write: self.write,
        });
    }
}

/// Whether `id` is one of the fourteen persisted commands: on a real session
/// these run the §1.8 path instead of the draft clone/restore (see
/// [`Engine::execute`]).
pub(crate) fn is_persisted(id: &str) -> bool {
    matches!(
        id,
        "develop.set"
            | "develop.reset"
            | "develop.copy"
            | "develop.paste"
            | "develop.merge"
            | "develop.sync"
            | "develop.beginInteraction"
            | "develop.updateInteraction"
            | "develop.endInteraction"
            | "develop.cancelInteraction"
            | "history.undo"
            | "history.redo"
            | "history.goto"
            | "process.update"
    )
}

/// One store op inside a command's single transaction.
enum StoreOp {
    Push {
        db: i64,
        label: String,
        json: String,
    },
    Move {
        db: i64,
        target: i64,
    },
}

/// One photo's computed half: the store ops plus the stack to swap in and
/// the event facts. Everything in here was built before the commit. `stack`
/// is `None` for batch targets that were never loaded: their new state lives
/// in the store alone (snapshot accessors read it back through), so a batch
/// neither pays for rebuilding stacks it never held nor evicts the
/// interactive working set from the cache.
struct Computed {
    id: String,
    stack: Option<lightamer_history::HistoryStack>,
    steps: usize,
    cursor: usize,
    emit: bool,
}

/// Wraps a store refusal in the command that met it.
#[allow(clippy::needless_pass_by_value)] // owned error keeps `map_err` closures terse; cold path
fn store_err(cmd: &str, err: lightamer_catalog::CatalogError) -> CommandError {
    CommandError::Store {
        cmd: cmd.to_owned(),
        reason: err.to_string(),
    }
}

/// Wraps settings the store cannot take (serialization refused them) in the
/// command that computed them. Unreachable from wire input (JSON floats are
/// finite) and from stored rows (the store only holds canonical bytes), but
/// the compute half must still answer it without touching the store.
#[allow(clippy::needless_pass_by_value)] // owned error keeps `map_err` closures terse; cold path
fn unserializable(cmd: &str, err: lightamer_history::SettingsError) -> CommandError {
    CommandError::Store {
        cmd: cmd.to_owned(),
        reason: err.to_string(),
    }
}

/// Ends an open interaction on `probe` exactly as the memory call would,
/// returning the store push for the drag's step when the drag changed
/// anything. Serialization runs here (compute half): a failure returns
/// before the store is touched.
fn settle_interaction(
    cmd: &str,
    db: i64,
    probe: &mut lightamer_history::HistoryStack,
) -> Result<Option<StoreOp>, CommandError> {
    let Some((label, live)) = probe.pending_interaction() else {
        if probe.is_interaction_open() {
            probe.end_interaction();
        }
        return Ok(None);
    };
    let label = label.to_owned();
    let json = live
        .canonical_json()
        .map_err(|err| unserializable(cmd, err))?;
    probe.end_interaction();
    Ok(Some(StoreOp::Push { db, label, json }))
}

/// Commits every op in one store transaction: nothing when there is nothing
/// to do, the single-step helpers for one op, one writer otherwise (an
/// all-push batch through the writer's single prepared-statements pass).
/// The caller computed everything beforehand; dropping the writer on error
/// rolls the whole batch back.
fn commit_ops(engine: &mut Engine, cmd: &str, ops: &[StoreOp]) -> Result<(), CommandError> {
    let Some(first) = ops.first() else {
        return Ok(());
    };
    if ops.len() == 1 {
        let Some(session) = engine.real_session_mut() else {
            return Err(CommandError::NoSession {
                cmd: cmd.to_owned(),
            });
        };
        return match first {
            StoreOp::Push { db, label, json } => {
                lightamer_catalog::push_step(session.connection_mut(), *db, label, json)
                    .map(|_| ())
                    .map_err(|err| store_err(cmd, err))
            }
            StoreOp::Move { db, target } => {
                lightamer_catalog::move_cursor(session.connection(), *db, *target)
                    .map(|_| ())
                    .map_err(|err| store_err(cmd, err))
            }
        };
    }
    let mut requests = Vec::with_capacity(ops.len());
    let mut all_push = true;
    for op in ops {
        match op {
            StoreOp::Push { db, label, json } => {
                requests.push(lightamer_catalog::PushRequest {
                    photo_id: *db,
                    label: label.as_str(),
                    canonical_json: json.as_str(),
                });
            }
            StoreOp::Move { .. } => {
                all_push = false;
                break;
            }
        }
    }
    let Some(session) = engine.real_session_mut() else {
        return Err(CommandError::NoSession {
            cmd: cmd.to_owned(),
        });
    };
    let mut writer = lightamer_catalog::HistoryWriter::begin(session.connection_mut())
        .map_err(|err| store_err(cmd, err))?;
    if all_push {
        writer
            .push_many(&requests)
            .map(|_| ())
            .map_err(|err| store_err(cmd, err))?;
        return writer.commit().map_err(|err| store_err(cmd, err));
    }
    for op in ops {
        match op {
            StoreOp::Push { db, label, json } => {
                writer
                    .push(*db, label, json)
                    .map(|_| ())
                    .map_err(|err| store_err(cmd, err))?;
            }
            StoreOp::Move { db, target } => {
                writer
                    .move_cursor(*db, *target)
                    .map(|_| ())
                    .map_err(|err| store_err(cmd, err))?;
            }
        }
    }
    writer.commit().map_err(|err| store_err(cmd, err))
}

/// Swaps every computed stack into the cache and emits the change events.
/// Infallible: nothing here can fail.
fn swap_in(engine: &mut Engine, computed: Vec<Computed>, ctx: &mut RunCtx) {
    for one in computed {
        let event = Event::PhotoChanged {
            photo: one.id.clone(),
            steps: one.steps,
            cursor: one.cursor,
        };
        if let Some(stack) = one.stack {
            engine.insert_photo_stack(&one.id, stack);
        }
        if one.emit {
            ctx.emit(event);
        }
    }
}

/// Fetches the unloaded targets of a multi-target command in one query: each
/// photo's store id, cursor, step count, highest step index, and current
/// settings text. Loaded photos keep the in-memory path (their cached stack
/// mirrors the store and may hold an open interaction); single-target
/// commands never call this, so interactive edits keep populating the cache
/// while batches stream past it without evicting the working set.
fn fetch_unloaded_batch(
    engine: &Engine,
    cmd: &str,
    ids: &[String],
) -> Result<HashMap<String, lightamer_catalog::PhotoCurrent>, CommandError> {
    let unloaded: Vec<String> = ids
        .iter()
        .filter(|id| !engine.is_photo_loaded(id))
        .cloned()
        .collect();
    let Some(session) = engine.real_session() else {
        return Err(CommandError::NoSession {
            cmd: cmd.to_owned(),
        });
    };
    lightamer_catalog::read_photo_currents(session.connection(), &unloaded)
        .map(|currents| {
            currents
                .into_iter()
                .map(|one| (one.uuid.clone(), one))
                .collect()
        })
        .map_err(|err| store_err(cmd, err))
}

/// The fast-path facts for one batch target: `Some` when the photo is
/// unloaded (its facts came from the batch fetch), `None` when it is loaded
/// (the caller runs the in-memory path). Unknown ids fail here, in batch
/// order, before the store is touched.
fn fast_facts<'b>(
    batch: Option<&'b HashMap<String, lightamer_catalog::PhotoCurrent>>,
    engine: &Engine,
    cmd: &str,
    id: &str,
) -> Result<Option<&'b lightamer_catalog::PhotoCurrent>, CommandError> {
    let Some(currents) = batch else {
        return Ok(None);
    };
    if let Some(facts) = currents.get(id) {
        return Ok(Some(facts));
    }
    if engine.is_photo_loaded(id) {
        return Ok(None);
    }
    Err(CommandError::NoPhoto {
        cmd: cmd.to_owned(),
        photo: id.to_owned(),
    })
}

/// Validates one batch target's stored facts and parses its current
/// settings: contiguous steps from 0 with the cursor on a step are exactly
/// the states [`HistoryStack::from_steps`][lightamer_history::HistoryStack::from_steps]
/// accepts, and the push arithmetic below mirrors its `commit`. Anything
/// damaged fails before the store is touched.
fn parse_stored_current(
    cmd: &str,
    facts: &lightamer_catalog::PhotoCurrent,
) -> Result<lightamer_history::PhotoSettings, CommandError> {
    if facts.cursor < 0
        || facts.cursor >= facts.steps
        || facts.max_idx.saturating_add(1) != facts.steps
    {
        return Err(CommandError::Store {
            cmd: cmd.to_owned(),
            reason: format!(
                "stored cursor {} of photo {} names no step ({} steps)",
                facts.cursor, facts.id, facts.steps
            ),
        });
    }
    lightamer_history::PhotoSettings::from_json(&facts.settings_json).map_err(|err| {
        CommandError::Store {
            cmd: cmd.to_owned(),
            reason: format!(
                "stored current settings of photo {} do not parse: {err}",
                facts.id
            ),
        }
    })
}

/// Where a push lands without the stack: the redo tail drops, the new step
/// appends at cursor + 1, past [`HISTORY_LIMIT`][lightamer_history::HISTORY_LIMIT]
/// the oldest steps drop, and the cursor parks on the new step. `cursor` is
/// the validated stored pre-push cursor.
fn post_push_position(cursor: i64) -> (usize, usize) {
    let limit = lightamer_history::HISTORY_LIMIT;
    let after_insert = cursor.saturating_add(2);
    let capped = i64::try_from(limit).unwrap_or(i64::MAX);
    if after_insert > capped {
        (limit, limit.saturating_sub(1))
    } else {
        let steps = usize::try_from(after_insert).unwrap_or(limit);
        let at = usize::try_from(cursor.saturating_add(1)).unwrap_or(0);
        (steps, at)
    }
}

/// Computes `develop.set` on a real session: merge the patch per photo.
pub(crate) fn develop_set(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.set";
    let ids = ids_req(CMD, params)?;
    let args: SetArgs = set_args(engine, CMD, params)?;
    let mut clock = PhaseClock::start();
    let unloaded = if ids.len() > 1 {
        let tick = Instant::now();
        let fetched = fetch_unloaded_batch(engine, CMD, &ids)?;
        clock.add_read(tick.elapsed());
        Some(fetched)
    } else {
        None
    };
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        if let Some(facts) = fast_facts(unloaded.as_ref(), engine, CMD, id)? {
            let current = parse_stored_current(CMD, facts)?;
            let next = merged_settings(
                &current,
                &args.module,
                args.multi,
                args.enabled,
                &args.patch,
            );
            let json = next
                .canonical_json()
                .map_err(|err| unserializable(CMD, err))?;
            let (new_steps, new_cursor) = post_push_position(facts.cursor);
            ops.push(StoreOp::Push {
                db: facts.id,
                label: CMD.to_owned(),
                json,
            });
            computed.push(Computed {
                id: id.clone(),
                steps: new_steps,
                cursor: new_cursor,
                stack: None,
                emit: true,
            });
            continue;
        }
        let tick = Instant::now();
        let db = engine.ensure_photo_loaded(CMD, id)?;
        clock.add_read(tick.elapsed());
        let Some(stack) = engine.stack_mut(id) else {
            continue;
        };
        let Some(current) = stack.current().cloned() else {
            continue;
        };
        let next = merged_settings(
            &current,
            &args.module,
            args.multi,
            args.enabled,
            &args.patch,
        );
        let json = next
            .canonical_json()
            .map_err(|err| unserializable(CMD, err))?;
        let mut probe = stack.clone();
        if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
            ops.push(settled);
        }
        probe.commit(CMD, Arc::new(next));
        ops.push(StoreOp::Push {
            db,
            label: CMD.to_owned(),
            json,
        });
        computed.push(Computed {
            id: id.clone(),
            steps: probe.len(),
            cursor: probe.cursor_index(),
            stack: Some(probe),
            emit: true,
        });
    }
    let tick = Instant::now();
    commit_ops(engine, CMD, &ops)?;
    clock.add_write(tick.elapsed());
    swap_in(engine, computed, ctx);
    clock.finish(engine);
    Ok(json!({"updated": ids.len()}))
}

/// Computes `develop.reset` on a real session: default settings per photo.
pub(crate) fn develop_reset(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.reset";
    let ids = ids_req(CMD, params)?;
    let mut clock = PhaseClock::start();
    let unloaded = if ids.len() > 1 {
        let tick = Instant::now();
        let fetched = fetch_unloaded_batch(engine, CMD, &ids)?;
        clock.add_read(tick.elapsed());
        Some(fetched)
    } else {
        None
    };
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        if let Some(facts) = fast_facts(unloaded.as_ref(), engine, CMD, id)? {
            parse_stored_current(CMD, facts)?;
            let next = lightamer_history::PhotoSettings::default();
            let json = next
                .canonical_json()
                .map_err(|err| unserializable(CMD, err))?;
            let (new_steps, new_cursor) = post_push_position(facts.cursor);
            ops.push(StoreOp::Push {
                db: facts.id,
                label: CMD.to_owned(),
                json,
            });
            computed.push(Computed {
                id: id.clone(),
                steps: new_steps,
                cursor: new_cursor,
                stack: None,
                emit: true,
            });
            continue;
        }
        let tick = Instant::now();
        let db = engine.ensure_photo_loaded(CMD, id)?;
        clock.add_read(tick.elapsed());
        let Some(stack) = engine.stack_mut(id) else {
            continue;
        };
        let next = lightamer_history::PhotoSettings::default();
        let json = next
            .canonical_json()
            .map_err(|err| unserializable(CMD, err))?;
        let mut probe = stack.clone();
        if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
            ops.push(settled);
        }
        probe.commit(CMD, Arc::new(next));
        ops.push(StoreOp::Push {
            db,
            label: CMD.to_owned(),
            json,
        });
        computed.push(Computed {
            id: id.clone(),
            steps: probe.len(),
            cursor: probe.cursor_index(),
            stack: Some(probe),
            emit: true,
        });
    }
    let tick = Instant::now();
    commit_ops(engine, CMD, &ops)?;
    clock.add_write(tick.elapsed());
    swap_in(engine, computed, ctx);
    clock.finish(engine);
    Ok(json!({"reset": ids.len()}))
}

/// Computes `develop.copy` on a real session: the clipboard is memory-only
/// and never reaches the store.
pub(crate) fn develop_copy(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.copy";
    let id = id_req(CMD, params)?;
    engine.ensure_photo_loaded(CMD, &id)?;
    let Some(current) = engine.photo_settings(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let batch = lightamer_history::BatchAdjustments::from_settings(&current);
    let modules = batch.instances.len();
    *engine.clipboard_mut() = Some(batch);
    ctx.emit(Event::ClipboardChanged);
    Ok(json!({"modules": modules}))
}

/// Computes `develop.paste` on a real session: the clipboard onto every
/// target in one transaction, each target keeping its own process version.
pub(crate) fn develop_paste(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.paste";
    let ids = ids_req(CMD, params)?;
    let Some(batch) = engine.clipboard_mut().clone() else {
        return Err(CommandError::EmptyClipboard {
            cmd: CMD.to_owned(),
        });
    };
    let mut clock = PhaseClock::start();
    let unloaded = if ids.len() > 1 {
        let tick = Instant::now();
        let fetched = fetch_unloaded_batch(engine, CMD, &ids)?;
        clock.add_read(tick.elapsed());
        Some(fetched)
    } else {
        None
    };
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        if let Some(facts) = fast_facts(unloaded.as_ref(), engine, CMD, id)? {
            let current = parse_stored_current(CMD, facts)?;
            let next = lightamer_history::PhotoSettings {
                format_version: current.format_version,
                process: current.process,
                instances: batch.instances.clone(),
            };
            let json = next
                .canonical_json()
                .map_err(|err| unserializable(CMD, err))?;
            let (new_steps, new_cursor) = post_push_position(facts.cursor);
            ops.push(StoreOp::Push {
                db: facts.id,
                label: CMD.to_owned(),
                json,
            });
            computed.push(Computed {
                id: id.clone(),
                steps: new_steps,
                cursor: new_cursor,
                stack: None,
                emit: true,
            });
            continue;
        }
        let tick = Instant::now();
        let db = engine.ensure_photo_loaded(CMD, id)?;
        clock.add_read(tick.elapsed());
        let Some(stack) = engine.stack_mut(id) else {
            continue;
        };
        let Some(current) = stack.current().cloned() else {
            continue;
        };
        let next = lightamer_history::PhotoSettings {
            format_version: current.format_version,
            process: current.process,
            instances: batch.instances.clone(),
        };
        let json = next
            .canonical_json()
            .map_err(|err| unserializable(CMD, err))?;
        let mut probe = stack.clone();
        if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
            ops.push(settled);
        }
        probe.commit(CMD, Arc::new(next));
        ops.push(StoreOp::Push {
            db,
            label: CMD.to_owned(),
            json,
        });
        computed.push(Computed {
            id: id.clone(),
            steps: probe.len(),
            cursor: probe.cursor_index(),
            stack: Some(probe),
            emit: true,
        });
    }
    let tick = Instant::now();
    commit_ops(engine, CMD, &ops)?;
    clock.add_write(tick.elapsed());
    swap_in(engine, computed, ctx);
    clock.finish(engine);
    Ok(json!({"pasted": ids.len()}))
}

/// Computes `develop.sync` on a real session: the source's selected
/// adjustments merge onto every target in one transaction, each target
/// keeping its own process version. The source itself is only read.
pub(crate) fn develop_sync(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.sync";
    let source_id = id_req(CMD, params)?;
    let ids = ids_req(CMD, params)?;
    let parsed = parse_selection(engine, CMD, params)?;
    let Some(source) = engine.photo_settings(&source_id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: source_id,
        });
    };
    let selection = parsed.unwrap_or_else(|| full_selection(&source));
    let mut clock = PhaseClock::start();
    let unloaded = if ids.len() > 1 {
        let tick = Instant::now();
        let fetched = fetch_unloaded_batch(engine, CMD, &ids)?;
        clock.add_read(tick.elapsed());
        Some(fetched)
    } else {
        None
    };
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        if let Some(facts) = fast_facts(unloaded.as_ref(), engine, CMD, id)? {
            let current = parse_stored_current(CMD, facts)?;
            let next = lightamer_history::merge_adjustments(&current, &source, &selection);
            let json = next
                .canonical_json()
                .map_err(|err| unserializable(CMD, err))?;
            let (new_steps, new_cursor) = post_push_position(facts.cursor);
            ops.push(StoreOp::Push {
                db: facts.id,
                label: CMD.to_owned(),
                json,
            });
            computed.push(Computed {
                id: id.clone(),
                steps: new_steps,
                cursor: new_cursor,
                stack: None,
                emit: true,
            });
            continue;
        }
        let tick = Instant::now();
        let db = engine.ensure_photo_loaded(CMD, id)?;
        clock.add_read(tick.elapsed());
        let Some(stack) = engine.stack_mut(id) else {
            continue;
        };
        let Some(current) = stack.current().cloned() else {
            continue;
        };
        let next = lightamer_history::merge_adjustments(&current, &source, &selection);
        let json = next
            .canonical_json()
            .map_err(|err| unserializable(CMD, err))?;
        let mut probe = stack.clone();
        if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
            ops.push(settled);
        }
        probe.commit(CMD, Arc::new(next));
        ops.push(StoreOp::Push {
            db,
            label: CMD.to_owned(),
            json,
        });
        computed.push(Computed {
            id: id.clone(),
            steps: probe.len(),
            cursor: probe.cursor_index(),
            stack: Some(probe),
            emit: true,
        });
    }
    let tick = Instant::now();
    commit_ops(engine, CMD, &ops)?;
    clock.add_write(tick.elapsed());
    swap_in(engine, computed, ctx);
    clock.finish(engine);
    Ok(json!({"synced": ids.len()}))
}

/// Computes `develop.merge` on a real session: the clipboard's selected
/// adjustments merge onto every target in one transaction, each target
/// keeping its own process version.
pub(crate) fn develop_merge(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.merge";
    let ids = ids_req(CMD, params)?;
    let parsed = parse_selection(engine, CMD, params)?;
    let Some(batch) = engine.clipboard_mut().clone() else {
        return Err(CommandError::EmptyClipboard {
            cmd: CMD.to_owned(),
        });
    };
    // The merge only reads the source's instances; the format and process
    // versions below never reach any target (each keeps its own).
    let source = lightamer_history::PhotoSettings {
        instances: batch.instances.clone(),
        ..lightamer_history::PhotoSettings::default()
    };
    let selection = parsed.unwrap_or_else(|| full_selection(&source));
    let mut clock = PhaseClock::start();
    let unloaded = if ids.len() > 1 {
        let tick = Instant::now();
        let fetched = fetch_unloaded_batch(engine, CMD, &ids)?;
        clock.add_read(tick.elapsed());
        Some(fetched)
    } else {
        None
    };
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        if let Some(facts) = fast_facts(unloaded.as_ref(), engine, CMD, id)? {
            let current = parse_stored_current(CMD, facts)?;
            let next = lightamer_history::merge_adjustments(&current, &source, &selection);
            let json = next
                .canonical_json()
                .map_err(|err| unserializable(CMD, err))?;
            let (new_steps, new_cursor) = post_push_position(facts.cursor);
            ops.push(StoreOp::Push {
                db: facts.id,
                label: CMD.to_owned(),
                json,
            });
            computed.push(Computed {
                id: id.clone(),
                steps: new_steps,
                cursor: new_cursor,
                stack: None,
                emit: true,
            });
            continue;
        }
        let tick = Instant::now();
        let db = engine.ensure_photo_loaded(CMD, id)?;
        clock.add_read(tick.elapsed());
        let Some(stack) = engine.stack_mut(id) else {
            continue;
        };
        let Some(current) = stack.current().cloned() else {
            continue;
        };
        let next = lightamer_history::merge_adjustments(&current, &source, &selection);
        let json = next
            .canonical_json()
            .map_err(|err| unserializable(CMD, err))?;
        let mut probe = stack.clone();
        if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
            ops.push(settled);
        }
        probe.commit(CMD, Arc::new(next));
        ops.push(StoreOp::Push {
            db,
            label: CMD.to_owned(),
            json,
        });
        computed.push(Computed {
            id: id.clone(),
            steps: probe.len(),
            cursor: probe.cursor_index(),
            stack: Some(probe),
            emit: true,
        });
    }
    let tick = Instant::now();
    commit_ops(engine, CMD, &ops)?;
    clock.add_write(tick.elapsed());
    swap_in(engine, computed, ctx);
    clock.finish(engine);
    Ok(json!({"merged": ids.len()}))
}

/// Computes `develop.beginInteraction` on a real session: memory-only, except
/// the drag it ends (whose step commits first, in the same transaction).
pub(crate) fn develop_begin(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.beginInteraction";
    let id = id_req(CMD, params)?;
    let db = engine.ensure_photo_loaded(CMD, &id)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let mut probe = stack.clone();
    let mut ops = Vec::new();
    if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
        ops.push(settled);
    }
    probe.begin_interaction("develop.endInteraction");
    let computed = Computed {
        id: id.clone(),
        steps: probe.len(),
        cursor: probe.cursor_index(),
        stack: Some(probe),
        emit: false,
    };
    commit_ops(engine, CMD, &ops)?;
    if let Some(stack) = computed.stack {
        engine.insert_photo_stack(&computed.id, stack);
    }
    Ok(Value::Null)
}

/// Computes `develop.updateInteraction` on a real session: the live value is
/// memory-only and never reaches the store.
pub(crate) fn develop_update(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.updateInteraction";
    let id = id_req(CMD, params)?;
    let args: SetArgs = set_args(engine, CMD, params)?;
    engine.ensure_photo_loaded(CMD, &id)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    if !stack.is_interaction_open() {
        return Err(CommandError::NoInteraction {
            cmd: CMD.to_owned(),
            photo: id,
        });
    }
    let live = stack
        .current()
        .cloned()
        .unwrap_or_else(|| Arc::new(lightamer_history::PhotoSettings::default()));
    let next = merged_settings(&live, &args.module, args.multi, args.enabled, &args.patch);
    stack.update_interaction(Arc::new(next));
    if let Some(event) = engine.photo_event(&id) {
        ctx.emit(event);
    }
    Ok(Value::Null)
}

/// Computes `develop.endInteraction` on a real session: the drag's final
/// value commits one step. Ending without a changed drag succeeds and stores
/// nothing, mirroring the draft.
pub(crate) fn develop_end(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.endInteraction";
    let id = id_req(CMD, params)?;
    let db = engine.ensure_photo_loaded(CMD, &id)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let mut probe = stack.clone();
    let mut ops = Vec::new();
    if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
        ops.push(settled);
    }
    let committed = !ops.is_empty();
    let computed = Computed {
        id: id.clone(),
        steps: probe.len(),
        cursor: probe.cursor_index(),
        stack: Some(probe),
        emit: committed,
    };
    commit_ops(engine, CMD, &ops)?;
    swap_in(engine, vec![computed], ctx);
    Ok(Value::Null)
}

/// Computes `develop.cancelInteraction` on a real session: dropping the live
/// value is memory-only and never reaches the store.
pub(crate) fn develop_cancel(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.cancelInteraction";
    let id = id_req(CMD, params)?;
    engine.ensure_photo_loaded(CMD, &id)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let before = stack.current().cloned();
    stack.cancel_interaction();
    if stack.current().cloned() != before
        && let Some(event) = engine.photo_event(&id)
    {
        ctx.emit(event);
    }
    Ok(Value::Null)
}

/// Computes `history.undo` on a real session: the cursor moves in the store.
pub(crate) fn history_undo(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "history.undo";
    move_cursor(engine, CMD, params, CursorMove::Undo, ctx)
}

/// Computes `history.redo` on a real session: the cursor moves in the store.
pub(crate) fn history_redo(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "history.redo";
    move_cursor(engine, CMD, params, CursorMove::Redo, ctx)
}

/// Computes `history.goto` on a real session: the cursor moves in the store.
pub(crate) fn history_goto(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "history.goto";
    let id = id_req(CMD, params)?;
    let raw = uint_req(CMD, params, "index")?;
    let Ok(index) = usize::try_from(raw) else {
        return Err(CommandError::BadParam {
            cmd: CMD.to_owned(),
            key: "index".to_owned(),
            reason: "must fit in a step index".to_owned(),
        });
    };
    let db = engine.ensure_photo_loaded(CMD, &id)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let mut probe = stack.clone();
    let mut ops = Vec::new();
    if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
        ops.push(settled);
    }
    if !probe.goto(index) {
        return Err(CommandError::BadParam {
            cmd: CMD.to_owned(),
            key: "index".to_owned(),
            reason: format!("out of range (0..{})", probe.len()),
        });
    }
    let target = i64::try_from(probe.cursor_index()).map_err(|_| CommandError::Store {
        cmd: CMD.to_owned(),
        reason: format!("cursor {} does not fit a step index", probe.cursor_index()),
    })?;
    ops.push(StoreOp::Move { db, target });
    let computed = Computed {
        id: id.clone(),
        steps: probe.len(),
        cursor: probe.cursor_index(),
        stack: Some(probe),
        emit: true,
    };
    commit_ops(engine, CMD, &ops)?;
    swap_in(engine, vec![computed], ctx);
    Ok(json!({"cursor": index}))
}

/// Which way [`move_cursor`] moves.
#[derive(Clone, Copy)]
enum CursorMove {
    Undo,
    Redo,
}

/// Computes `history.undo`/`history.redo` on a real session: settle the drag
/// (if any), move the cursor, commit both in one transaction.
fn move_cursor(
    engine: &mut Engine,
    cmd: &str,
    params: &Map<String, Value>,
    direction: CursorMove,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    let id = id_req(cmd, params)?;
    let db = engine.ensure_photo_loaded(cmd, &id)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: cmd.to_owned(),
            photo: id,
        });
    };
    let mut probe = stack.clone();
    let mut ops = Vec::new();
    if let Some(settled) = settle_interaction(cmd, db, &mut probe)? {
        ops.push(settled);
    }
    let moved = match direction {
        CursorMove::Undo => probe.undo(),
        CursorMove::Redo => probe.redo(),
    };
    if !moved {
        let reason = match direction {
            CursorMove::Undo => "nothing to undo",
            CursorMove::Redo => "nothing to redo",
        };
        return Err(CommandError::Disabled {
            cmd: cmd.to_owned(),
            reason: reason.to_owned(),
        });
    }
    let cursor = probe.cursor_index();
    let target = i64::try_from(cursor).map_err(|_| CommandError::Store {
        cmd: cmd.to_owned(),
        reason: format!("cursor {cursor} does not fit a step index"),
    })?;
    ops.push(StoreOp::Move { db, target });
    let computed = Computed {
        id: id.clone(),
        steps: probe.len(),
        cursor,
        stack: Some(probe),
        emit: true,
    };
    commit_ops(engine, cmd, &ops)?;
    swap_in(engine, vec![computed], ctx);
    Ok(json!({"cursor": cursor}))
}

/// Computes `process.update` on a real session: outdated photos commit one
/// step each, in one transaction; current photos are untouched (an open drag
/// on a current photo stays open, mirroring the draft, which never calls
/// `commit` there).
pub(crate) fn process_update(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "process.update";
    let ids = ids_req(CMD, params)?;
    let mut clock = PhaseClock::start();
    let unloaded = if ids.len() > 1 {
        let tick = Instant::now();
        let fetched = fetch_unloaded_batch(engine, CMD, &ids)?;
        clock.add_read(tick.elapsed());
        Some(fetched)
    } else {
        None
    };
    let mut computed = Vec::new();
    let mut ops = Vec::new();
    let mut updated = 0;
    for id in &ids {
        if let Some(facts) = fast_facts(unloaded.as_ref(), engine, CMD, id)? {
            let current = parse_stored_current(CMD, facts)?;
            if !current.process.is_outdated() {
                continue;
            }
            let mut next = current;
            next.process.update_to_latest();
            let json = next
                .canonical_json()
                .map_err(|err| unserializable(CMD, err))?;
            let (new_steps, new_cursor) = post_push_position(facts.cursor);
            ops.push(StoreOp::Push {
                db: facts.id,
                label: CMD.to_owned(),
                json,
            });
            updated += 1;
            computed.push(Computed {
                id: id.clone(),
                steps: new_steps,
                cursor: new_cursor,
                stack: None,
                emit: true,
            });
            continue;
        }
        let tick = Instant::now();
        let db = engine.ensure_photo_loaded(CMD, id)?;
        clock.add_read(tick.elapsed());
        let Some(stack) = engine.stack_mut(id) else {
            continue;
        };
        let Some(current) = stack.current().cloned() else {
            continue;
        };
        if !current.process.is_outdated() {
            continue;
        }
        let mut next = (*current).clone();
        next.process.update_to_latest();
        let json = next
            .canonical_json()
            .map_err(|err| unserializable(CMD, err))?;
        let mut probe = stack.clone();
        if let Some(settled) = settle_interaction(CMD, db, &mut probe)? {
            ops.push(settled);
        }
        probe.commit(CMD, Arc::new(next));
        ops.push(StoreOp::Push {
            db,
            label: CMD.to_owned(),
            json,
        });
        updated += 1;
        computed.push(Computed {
            id: id.clone(),
            steps: probe.len(),
            cursor: probe.cursor_index(),
            stack: Some(probe),
            emit: true,
        });
    }
    let tick = Instant::now();
    commit_ops(engine, CMD, &ops)?;
    clock.add_write(tick.elapsed());
    swap_in(engine, computed, ctx);
    clock.finish(engine);
    Ok(json!({"updated": updated}))
}
