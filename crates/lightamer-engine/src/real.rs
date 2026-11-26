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
use std::sync::Arc;

use serde_json::{Map, Value, json};

use crate::command::{Outcome, RunCtx, id_req, ids_req, uint_req};
use crate::develop::{SetArgs, merged_settings, set_args};
use crate::engine::Engine;
use crate::error::CommandError;
use crate::event::Event;

/// Whether `id` is one of the twelve persisted commands: on a real session
/// these run the §1.8 path instead of the draft clone/restore (see
/// [`Engine::execute`]).
pub(crate) fn is_persisted(id: &str) -> bool {
    matches!(
        id,
        "develop.set"
            | "develop.reset"
            | "develop.copy"
            | "develop.paste"
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
/// the event facts. Everything in here was built before the commit.
struct Computed {
    id: String,
    stack: lightamer_history::HistoryStack,
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
/// to do, the single-step helpers for one op, one writer otherwise. The
/// caller computed everything beforehand; dropping the writer on error rolls
/// the whole batch back.
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
    let Some(session) = engine.real_session_mut() else {
        return Err(CommandError::NoSession {
            cmd: cmd.to_owned(),
        });
    };
    let mut writer = lightamer_catalog::HistoryWriter::begin(session.connection_mut())
        .map_err(|err| store_err(cmd, err))?;
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
        engine.insert_photo_stack(&one.id, one.stack);
        if one.emit {
            ctx.emit(event);
        }
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
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        let db = engine.ensure_photo_loaded(CMD, id)?;
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
            stack: probe,
            emit: true,
        });
    }
    commit_ops(engine, CMD, &ops)?;
    swap_in(engine, computed, ctx);
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
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        let db = engine.ensure_photo_loaded(CMD, id)?;
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
            stack: probe,
            emit: true,
        });
    }
    commit_ops(engine, CMD, &ops)?;
    swap_in(engine, computed, ctx);
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
    let mut computed = Vec::with_capacity(ids.len());
    let mut ops = Vec::new();
    for id in &ids {
        let db = engine.ensure_photo_loaded(CMD, id)?;
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
            stack: probe,
            emit: true,
        });
    }
    commit_ops(engine, CMD, &ops)?;
    swap_in(engine, computed, ctx);
    Ok(json!({"pasted": ids.len()}))
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
        stack: probe,
        emit: false,
    };
    commit_ops(engine, CMD, &ops)?;
    engine.insert_photo_stack(&computed.id, computed.stack);
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
        stack: probe,
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
        stack: probe,
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
        stack: probe,
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
    let mut computed = Vec::new();
    let mut ops = Vec::new();
    let mut updated = 0;
    for id in &ids {
        let db = engine.ensure_photo_loaded(CMD, id)?;
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
            stack: probe,
            emit: true,
        });
    }
    commit_ops(engine, CMD, &ops)?;
    swap_in(engine, computed, ctx);
    Ok(json!({"updated": updated}))
}
