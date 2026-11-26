// SPDX-License-Identifier: GPL-3.0-or-later
//! The `history.*` and `process.*` commands: cursor moves and process updates.
//!
//! Undo, redo, and goto only move the cursor (nothing is deleted); the step
//! labels stay so the CLI and a future UI can show where the photo stands.

use std::sync::Arc;

use serde_json::{Map, Value, json};

use crate::command::{
    self, CommandSpec, Outcome, ParamKind, ParamSpec, RunCtx, id_req, ids_req, uint_req,
};
use crate::engine::Engine;
use crate::error::CommandError;

/// The `history.*` and `process.*` specs, in command-id order.
pub(crate) static SPECS: &[CommandSpec] = &[
    CommandSpec {
        id: "history.undo",
        summary: "Moves one photo's cursor one step back.",
        params: &[ParamSpec {
            name: "id",
            kind: ParamKind::Text,
            required: true,
            doc: "The photo to undo on.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_undo,
    },
    CommandSpec {
        id: "history.redo",
        summary: "Moves one photo's cursor one step forward.",
        params: &[ParamSpec {
            name: "id",
            kind: ParamKind::Text,
            required: true,
            doc: "The photo to redo on.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_redo,
    },
    CommandSpec {
        id: "history.goto",
        summary: "Jumps one photo's cursor onto a step by index.",
        params: &[
            ParamSpec {
                name: "id",
                kind: ParamKind::Text,
                required: true,
                doc: "The photo to move.",
            },
            ParamSpec {
                name: "index",
                kind: ParamKind::Integer,
                required: true,
                doc: "The step index, oldest first.",
            },
        ],
        needs_session: true,
        enabled: command::always,
        run: run_goto,
    },
    CommandSpec {
        id: "process.update",
        summary: "Moves outdated photos to the current process version.",
        params: &[ParamSpec {
            name: "ids",
            kind: ParamKind::PhotoIds,
            required: true,
            doc: "The photos to update.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_process_update,
    },
];

fn run_undo(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "history.undo";
    if engine.has_real_session() {
        return crate::real::history_undo(engine, params, ctx);
    }
    let id = id_req(CMD, params)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    if !stack.undo() {
        return Err(CommandError::Disabled {
            cmd: CMD.to_owned(),
            reason: "nothing to undo".to_owned(),
        });
    }
    let cursor = stack.cursor_index();
    if let Some(event) = engine.photo_event(&id) {
        ctx.emit(event);
    }
    Ok(json!({"cursor": cursor}))
}

fn run_redo(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "history.redo";
    if engine.has_real_session() {
        return crate::real::history_redo(engine, params, ctx);
    }
    let id = id_req(CMD, params)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    if !stack.redo() {
        return Err(CommandError::Disabled {
            cmd: CMD.to_owned(),
            reason: "nothing to redo".to_owned(),
        });
    }
    let cursor = stack.cursor_index();
    if let Some(event) = engine.photo_event(&id) {
        ctx.emit(event);
    }
    Ok(json!({"cursor": cursor}))
}

fn run_goto(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "history.goto";
    if engine.has_real_session() {
        return crate::real::history_goto(engine, params, ctx);
    }
    let id = id_req(CMD, params)?;
    let raw = uint_req(CMD, params, "index")?;
    let Ok(index) = usize::try_from(raw) else {
        return Err(CommandError::BadParam {
            cmd: CMD.to_owned(),
            key: "index".to_owned(),
            reason: "must fit in a step index".to_owned(),
        });
    };
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    if !stack.goto(index) {
        return Err(CommandError::BadParam {
            cmd: CMD.to_owned(),
            key: "index".to_owned(),
            reason: format!("out of range (0..{})", stack.len()),
        });
    }
    if let Some(event) = engine.photo_event(&id) {
        ctx.emit(event);
    }
    Ok(json!({"cursor": index}))
}

fn run_process_update(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "process.update";
    if engine.has_real_session() {
        return crate::real::process_update(engine, params, ctx);
    }
    let ids = ids_req(CMD, params)?;
    for id in &ids {
        if !engine.state().photos_contains(id) {
            return Err(CommandError::NoPhoto {
                cmd: CMD.to_owned(),
                photo: id.clone(),
            });
        }
    }
    let mut updated = 0;
    for id in &ids {
        let mut moved = false;
        if let Some(stack) = engine.stack_mut(id)
            && let Some(current) = stack.current().cloned()
            && current.process.is_outdated()
        {
            let mut next = (*current).clone();
            next.process.update_to_latest();
            stack.commit(CMD, Arc::new(next));
            moved = true;
        }
        if moved {
            updated += 1;
            if let Some(event) = engine.photo_event(id) {
                ctx.emit(event);
            }
        }
    }
    Ok(json!({"updated": updated}))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use lightamer_iop_traits::ParamsDesc;
    use serde_json::json;

    use crate::engine::Engine;
    use crate::error::CommandError;

    /// A draft with an open lookup plus two committed steps on `a`.
    fn draft_with_two_steps() -> Engine {
        let mut engine = Engine::open_draft(["a"]);
        engine.set_param_lookup(|_| Some(ParamsDesc::unset()));
        for flag in [true, false] {
            engine
                .execute(
                    "develop.set",
                    &json!({"ids": ["a"], "module": "mod_a", "patch": {"p": {"type": "bool", "value": flag}}}),
                )
                .expect("seed step");
        }
        engine
    }

    #[test]
    fn undo_and_redo_move_the_cursor_and_report_it() {
        let mut engine = draft_with_two_steps();
        assert_eq!(engine.photo_cursor("a"), Some(2));
        let out = engine
            .execute("history.undo", &json!({"id": "a"}))
            .expect("undo");
        assert_eq!(out, json!({"cursor": 1}));
        let out = engine
            .execute("history.redo", &json!({"id": "a"}))
            .expect("redo");
        assert_eq!(out, json!({"cursor": 2}));
        assert_eq!(
            engine.photo_len("a"),
            Some(3),
            "cursor moves keep every step"
        );
    }

    #[test]
    fn undo_at_the_oldest_step_is_disabled() {
        let mut engine = Engine::open_draft(["a"]);
        let err = engine
            .execute("history.undo", &json!({"id": "a"}))
            .expect_err("nothing to undo");
        assert!(matches!(err, CommandError::Disabled { .. }), "{err}");
    }

    #[test]
    fn redo_at_the_newest_step_is_disabled() {
        let mut engine = draft_with_two_steps();
        let err = engine
            .execute("history.redo", &json!({"id": "a"}))
            .expect_err("nothing to redo");
        assert!(matches!(err, CommandError::Disabled { .. }), "{err}");
    }

    #[test]
    fn goto_jumps_to_any_step_and_rejects_out_of_range() {
        let mut engine = draft_with_two_steps();
        let out = engine
            .execute("history.goto", &json!({"id": "a", "index": 0}))
            .expect("goto");
        assert_eq!(out, json!({"cursor": 0}));
        let err = engine
            .execute("history.goto", &json!({"id": "a", "index": 9}))
            .expect_err("out of range");
        assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
        assert_eq!(
            engine.photo_cursor("a"),
            Some(0),
            "failed jump moves nothing"
        );
    }

    #[test]
    fn process_update_leaves_current_photos_untouched() {
        let mut engine = Engine::open_draft(["a", "b"]);
        let out = engine
            .execute("process.update", &json!({"ids": ["a", "b"]}))
            .expect("update runs");
        assert_eq!(out, json!({"updated": 0}));
        assert_eq!(
            engine.photo_len("a"),
            Some(1),
            "no step when nothing changes"
        );
    }
}
