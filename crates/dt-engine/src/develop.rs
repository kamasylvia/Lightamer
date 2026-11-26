// SPDX-License-Identifier: GPL-3.0-or-later
//! The `develop.*` commands: per-photo edits and the drag-merge interaction.
//!
//! Each mutating command commits exactly one history step per photo it
//! touches, labelled with the command id. Patch parameters name settings
//! values in the tagged wire form ([`SettingValue`][dt_history::SettingValue]):
//! `{"p_bool": {"type": "bool", "value": true}}`.

use std::sync::Arc;

use dt_history::{BatchAdjustments, ModuleInstance, PhotoSettings, SettingValue};
use serde_json::{Map, Value, json};

use crate::command::{
    self, CommandSpec, Outcome, ParamKind, ParamSpec, RunCtx, enabled_opt, id_req, ids_req,
    multi_opt, patch_req, text_req,
};
use crate::engine::Engine;
use crate::error::CommandError;

/// The `develop.*` specs, in command-id order.
pub(crate) static SPECS: &[CommandSpec] = &[
    CommandSpec {
        id: "develop.set",
        summary: "Sets one module instance's parameters on photos, one step each.",
        params: &[
            ParamSpec {
                name: "ids",
                kind: ParamKind::PhotoIds,
                required: true,
                doc: "The photos to change.",
            },
            ParamSpec {
                name: "module",
                kind: ParamKind::Text,
                required: true,
                doc: "The module id; must resolve in the registry.",
            },
            ParamSpec {
                name: "patch",
                kind: ParamKind::Patch,
                required: true,
                doc: "Parameter names to tagged setting values.",
            },
            ParamSpec {
                name: "multi",
                kind: ParamKind::Integer,
                required: false,
                doc: "Multi-instance index (default 0).",
            },
            ParamSpec {
                name: "enabled",
                kind: ParamKind::Flag,
                required: false,
                doc: "The instance switch (default keeps or enables).",
            },
        ],
        needs_session: true,
        enabled: command::always,
        run: run_set,
    },
    CommandSpec {
        id: "develop.reset",
        summary: "Resets photos to default settings, one step each.",
        params: &[ParamSpec {
            name: "ids",
            kind: ParamKind::PhotoIds,
            required: true,
            doc: "The photos to reset.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_reset,
    },
    CommandSpec {
        id: "develop.copy",
        summary: "Copies one photo's adjustments into the clipboard.",
        params: &[ParamSpec {
            name: "id",
            kind: ParamKind::Text,
            required: true,
            doc: "The photo to copy from.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_copy,
    },
    CommandSpec {
        id: "develop.paste",
        summary: "Pastes the clipboard adjustments onto photos, one step each.",
        params: &[ParamSpec {
            name: "ids",
            kind: ParamKind::PhotoIds,
            required: true,
            doc: "The photos to paste onto.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_paste,
    },
    CommandSpec {
        id: "develop.beginInteraction",
        summary: "Starts a drag-merge interaction on one photo.",
        params: &[ParamSpec {
            name: "id",
            kind: ParamKind::Text,
            required: true,
            doc: "The photo being dragged.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_begin,
    },
    CommandSpec {
        id: "develop.updateInteraction",
        summary: "Replaces the live value mid-interaction (no step yet).",
        params: &[
            ParamSpec {
                name: "id",
                kind: ParamKind::Text,
                required: true,
                doc: "The photo being dragged.",
            },
            ParamSpec {
                name: "module",
                kind: ParamKind::Text,
                required: true,
                doc: "The module id; must resolve in the registry.",
            },
            ParamSpec {
                name: "patch",
                kind: ParamKind::Patch,
                required: true,
                doc: "Parameter names to tagged setting values.",
            },
            ParamSpec {
                name: "multi",
                kind: ParamKind::Integer,
                required: false,
                doc: "Multi-instance index (default 0).",
            },
            ParamSpec {
                name: "enabled",
                kind: ParamKind::Flag,
                required: false,
                doc: "The instance switch (default keeps or enables).",
            },
        ],
        needs_session: true,
        enabled: command::always,
        run: run_update,
    },
    CommandSpec {
        id: "develop.endInteraction",
        summary: "Ends the interaction, committing the live value as one step.",
        params: &[ParamSpec {
            name: "id",
            kind: ParamKind::Text,
            required: true,
            doc: "The photo being dragged.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_end,
    },
    CommandSpec {
        id: "develop.cancelInteraction",
        summary: "Abandons the interaction, restoring the pre-drag settings.",
        params: &[ParamSpec {
            name: "id",
            kind: ParamKind::Text,
            required: true,
            doc: "The photo being dragged.",
        }],
        needs_session: true,
        enabled: command::always,
        run: run_cancel,
    },
];

/// Parses one patch object into typed values, keyed by parameter name.
fn parse_patch(
    cmd: &str,
    patch: &Map<String, Value>,
) -> Result<Vec<(String, SettingValue)>, CommandError> {
    let mut out = Vec::with_capacity(patch.len());
    for (name, raw) in patch {
        let value: SettingValue =
            serde_json::from_value(raw.clone()).map_err(|err| CommandError::BadParam {
                cmd: cmd.to_owned(),
                key: format!("patch.{name}"),
                reason: format!("must be a tagged setting value ({err})"),
            })?;
        out.push((name.clone(), value));
    }
    Ok(out)
}

/// Resolves the module id and validates the patch values against its declared
/// fields (undeclared names pass through; an undescribed module takes all).
fn checked_instance(
    engine: &Engine,
    cmd: &str,
    module: &str,
    multi: u32,
    enabled: Option<bool>,
    patch: &[(String, SettingValue)],
) -> Result<ModuleInstance, CommandError> {
    let Some(desc) = engine.params_for(module) else {
        return Err(CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: "module".to_owned(),
            reason: format!("unknown module '{module}'"),
        });
    };
    let instance = ModuleInstance {
        module: module.to_owned(),
        multi,
        name: None,
        enabled: enabled.unwrap_or(true),
        params: patch.iter().cloned().collect(),
    };
    instance
        .validate(desc)
        .map_err(|err| CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: "patch".to_owned(),
            reason: err.to_string(),
        })?;
    Ok(instance)
}

/// Merges one validated instance over `current`: named parameters overwrite,
/// unmentioned ones survive, and the switch applies only when given.
fn merged_settings(
    current: &PhotoSettings,
    module: &str,
    multi: u32,
    enabled: Option<bool>,
    patch: &[(String, SettingValue)],
) -> PhotoSettings {
    let mut next = current.clone();
    let mut instance = next
        .instances
        .get(module, multi)
        .cloned()
        .unwrap_or_else(|| ModuleInstance {
            module: module.to_owned(),
            multi,
            name: None,
            enabled: true,
            params: std::collections::BTreeMap::new(),
        });
    for (name, value) in patch {
        instance.params.insert(name.clone(), value.clone());
    }
    if let Some(flag) = enabled {
        instance.enabled = flag;
    }
    next.instances.upsert(instance);
    next
}

/// Extracts the shared `set`/`update` arguments: module, multi, switch, patch.
struct SetArgs {
    module: String,
    multi: u32,
    enabled: Option<bool>,
    patch: Vec<(String, SettingValue)>,
}

fn set_args(
    engine: &Engine,
    cmd: &str,
    params: &Map<String, Value>,
) -> Result<SetArgs, CommandError> {
    let module = text_req(cmd, params, "module")?;
    let multi = multi_opt(cmd, params)?;
    let enabled = enabled_opt(cmd, params)?;
    let raw_patch = patch_req(cmd, params)?;
    let patch = parse_patch(cmd, &raw_patch)?;
    checked_instance(engine, cmd, &module, multi, enabled, &patch)?;
    Ok(SetArgs {
        module,
        multi,
        enabled,
        patch,
    })
}

fn run_set(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.set";
    let ids = ids_req(CMD, params)?;
    let args = set_args(engine, CMD, params)?;
    for id in &ids {
        if !engine.state().photos_contains(id) {
            return Err(CommandError::NoPhoto {
                cmd: CMD.to_owned(),
                photo: id.clone(),
            });
        }
    }
    for id in &ids {
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
        stack.commit(CMD, Arc::new(next));
        if let Some(event) = engine.photo_event(id) {
            ctx.emit(event);
        }
    }
    Ok(json!({"updated": ids.len()}))
}

fn run_reset(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.reset";
    let ids = ids_req(CMD, params)?;
    for id in &ids {
        if !engine.state().photos_contains(id) {
            return Err(CommandError::NoPhoto {
                cmd: CMD.to_owned(),
                photo: id.clone(),
            });
        }
    }
    for id in &ids {
        if let Some(stack) = engine.stack_mut(id) {
            stack.commit(CMD, Arc::new(PhotoSettings::default()));
        }
        if let Some(event) = engine.photo_event(id) {
            ctx.emit(event);
        }
    }
    Ok(json!({"reset": ids.len()}))
}

fn run_copy(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.copy";
    let id = id_req(CMD, params)?;
    let Some(current) = engine.photo_settings(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let batch = BatchAdjustments::from_settings(&current);
    let modules = batch.instances.len();
    *engine.clipboard_mut() = Some(batch);
    ctx.emit(crate::event::Event::ClipboardChanged);
    Ok(json!({"modules": modules}))
}

fn run_paste(
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
    for id in &ids {
        if !engine.state().photos_contains(id) {
            return Err(CommandError::NoPhoto {
                cmd: CMD.to_owned(),
                photo: id.clone(),
            });
        }
    }
    // Same per-photo shape as `dt_history::apply_batch` (replace the
    // instances, keep the photo's own process), applied through the map.
    for id in &ids {
        if let Some(stack) = engine.stack_mut(id)
            && let Some(current) = stack.current().cloned()
        {
            let next = PhotoSettings {
                format_version: current.format_version,
                process: current.process,
                instances: batch.instances.clone(),
            };
            stack.commit(CMD, Arc::new(next));
        }
        if let Some(event) = engine.photo_event(id) {
            ctx.emit(event);
        }
    }
    Ok(json!({"pasted": ids.len()}))
}

fn run_begin(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.beginInteraction";
    let id = id_req(CMD, params)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    // The step the interaction eventually commits is labelled with the
    // command that commits it, `develop.endInteraction`.
    stack.begin_interaction("develop.endInteraction");
    Ok(Value::Null)
}

fn run_update(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.updateInteraction";
    let id = id_req(CMD, params)?;
    let args = set_args(engine, CMD, params)?;
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
        .unwrap_or_else(|| Arc::new(PhotoSettings::default()));
    let next = merged_settings(&live, &args.module, args.multi, args.enabled, &args.patch);
    stack.update_interaction(Arc::new(next));
    if let Some(event) = engine.photo_event(&id) {
        ctx.emit(event);
    }
    Ok(Value::Null)
}

fn run_end(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.endInteraction";
    let id = id_req(CMD, params)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let before = stack.len();
    stack.end_interaction();
    // Ending without an open interaction (or without a change) commits
    // nothing and succeeds, mirroring upstream's end-of-drag.
    if stack.len() != before
        && let Some(event) = engine.photo_event(&id)
    {
        ctx.emit(event);
    }
    Ok(Value::Null)
}

fn run_cancel(
    engine: &mut Engine,
    params: &Map<String, Value>,
    ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "develop.cancelInteraction";
    let id = id_req(CMD, params)?;
    let Some(stack) = engine.stack_mut(&id) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo: id,
        });
    };
    let before = stack.current().cloned();
    stack.cancel_interaction();
    // Cancelling without an open interaction changes nothing and succeeds.
    if stack.current().cloned() != before
        && let Some(event) = engine.photo_event(&id)
    {
        ctx.emit(event);
    }
    Ok(Value::Null)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use dt_history::SettingValue;
    use dt_iop_traits::{ParamField, ParamType, ParamsDesc};
    use serde_json::{Value, json};

    use crate::engine::Engine;
    use crate::error::CommandError;

    /// A draft whose lookup accepts every module id undescribed (like the
    /// current registry stubs): patch plumbing without registry coupling.
    fn open_draft() -> Engine {
        let mut engine = Engine::open_draft(["a", "b"]);
        engine.set_param_lookup(|_| Some(ParamsDesc::unset()));
        engine
    }

    fn set_params(module: &str, patch: &Value) -> Value {
        json!({"ids": ["a"], "module": module, "patch": patch})
    }

    #[test]
    fn set_commits_one_labelled_step_and_merges_params() {
        let mut engine = open_draft();
        let out = engine
            .execute(
                "develop.set",
                &set_params("mod_a", &json!({"p_bool": {"type": "bool", "value": true}})),
            )
            .expect("set runs");
        assert_eq!(out, json!({"updated": 1}));
        assert_eq!(engine.photo_len("a"), Some(2));
        assert_eq!(
            engine.photo_labels("a"),
            Some(vec!["import".to_owned(), "develop.set".to_owned()])
        );
        let settings = engine.photo_settings("a").expect("snapshot");
        let instance = settings.instances.get("mod_a", 0).expect("instance");
        assert_eq!(
            instance.params.get("p_bool"),
            Some(&SettingValue::Bool(true))
        );
        assert!(instance.enabled);
        // A second call merges: the unmentioned parameter survives.
        engine
            .execute(
                "develop.set",
                &set_params("mod_a", &json!({"p_num": {"type": "float", "value": 1.5}})),
            )
            .expect("second set runs");
        let settings = engine.photo_settings("a").expect("snapshot");
        let instance = settings.instances.get("mod_a", 0).expect("instance");
        assert_eq!(instance.params.len(), 2);
        assert_eq!(
            instance.params.get("p_bool"),
            Some(&SettingValue::Bool(true))
        );
    }

    #[test]
    fn set_honors_multi_and_enabled() {
        let mut engine = open_draft();
        engine
            .execute(
                "develop.set",
                &json!({"ids": ["a"], "module": "mod_a", "multi": 2, "enabled": false, "patch": {}}),
            )
            .expect("set runs");
        let settings = engine.photo_settings("a").expect("snapshot");
        let instance = settings.instances.get("mod_a", 2).expect("instance");
        assert!(!instance.enabled);
        assert!(settings.instances.get("mod_a", 0).is_none());
    }

    #[test]
    fn set_dedupes_repeated_ids_to_one_step() {
        let mut engine = open_draft();
        engine
            .execute(
                "develop.set",
                &json!({"ids": ["a", "a"], "module": "mod_a", "patch": {}}),
            )
            .expect("set runs");
        assert_eq!(engine.photo_len("a"), Some(2));
    }

    #[test]
    fn set_rejects_an_unknown_module() {
        let mut engine = Engine::open_draft(["a"]);
        let err = engine
            .execute("develop.set", &set_params("__no_such_module__", &json!({})))
            .expect_err("unknown module fails");
        assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
        assert_eq!(engine.photo_len("a"), Some(1));
    }

    #[test]
    fn set_accepts_a_registry_id_resolved_at_runtime() {
        let first = dt_registry::all_descs()
            .into_iter()
            .next()
            .map(|desc| desc.id.to_owned())
            .expect("registry non-empty");
        let mut engine = Engine::open_draft(["a"]);
        engine
            .execute("develop.set", &set_params(&first, &json!({})))
            .expect("registry id runs");
        assert_eq!(engine.photo_len("a"), Some(2));
    }

    #[test]
    fn set_validates_declared_fields_and_passes_undeclared_through() {
        static FIELDS: &[ParamField] = &[ParamField {
            name: "p_num",
            ty: ParamType::Float,
        }];
        let mut engine = Engine::open_draft(["a"]);
        engine.set_param_lookup(|_| {
            Some(ParamsDesc {
                fields: Some(FIELDS),
            })
        });
        let err = engine
            .execute(
                "develop.set",
                &set_params("mod_a", &json!({"p_num": {"type": "bool", "value": true}})),
            )
            .expect_err("wrong kind fails");
        assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
        // Declared and correct, plus an undeclared name: both land.
        engine
            .execute(
                "develop.set",
                &set_params(
                    "mod_a",
                    &json!({"p_num": {"type": "float", "value": 2.0}, "p_free": {"type": "text", "value": "kept"}}),
                ),
            )
            .expect("mixed patch runs");
        let settings = engine.photo_settings("a").expect("snapshot");
        let instance = settings.instances.get("mod_a", 0).expect("instance");
        assert_eq!(instance.params.len(), 2);
    }

    #[test]
    fn set_rejects_an_untagged_patch_value() {
        let mut engine = open_draft();
        let err = engine
            .execute("develop.set", &set_params("mod_a", &json!({"p_num": 1.5})))
            .expect_err("raw number fails");
        assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
    }

    #[test]
    fn reset_returns_photos_to_defaults() {
        let mut engine = open_draft();
        engine
            .execute(
                "develop.set",
                &set_params("mod_a", &json!({"p": {"type": "bool", "value": true}})),
            )
            .expect("set");
        let out = engine
            .execute("develop.reset", &json!({"ids": ["a", "b"]}))
            .expect("reset runs");
        assert_eq!(out, json!({"reset": 2}));
        for (id, steps) in [("a", 3), ("b", 2)] {
            assert_eq!(engine.photo_len(id), Some(steps));
            assert_eq!(
                engine.photo_labels(id).expect("labels").last(),
                Some(&"develop.reset".to_owned())
            );
            let settings = engine.photo_settings(id).expect("snapshot");
            assert_eq!(settings.instances.len(), 0);
            assert_eq!(settings.process, dt_history::ProcessVersion::LATEST);
        }
    }

    #[test]
    fn copy_paste_replaces_instances_and_keeps_the_target_process() {
        let mut engine = open_draft();
        engine
            .execute(
                "develop.set",
                &set_params("mod_a", &json!({"p": {"type": "bool", "value": true}})),
            )
            .expect("set");
        let out = engine
            .execute("develop.copy", &json!({"id": "a"}))
            .expect("copy runs");
        assert_eq!(out, json!({"modules": 1}));
        assert!(engine.has_clipboard());
        let before_process = engine.photo_settings("b").expect("snapshot").process;
        engine
            .execute("develop.paste", &json!({"ids": ["b"]}))
            .expect("paste runs");
        assert_eq!(engine.photo_len("b"), Some(2));
        assert_eq!(
            engine.photo_labels("b").expect("labels").last(),
            Some(&"develop.paste".to_owned())
        );
        let target = engine.photo_settings("b").expect("snapshot");
        assert_eq!(target.process, before_process);
        assert_eq!(target.instances.len(), 1);
        assert!(target.instances.get("mod_a", 0).is_some());
    }

    #[test]
    fn paste_with_an_empty_clipboard_is_an_error() {
        let mut engine = open_draft();
        let err = engine
            .execute("develop.paste", &json!({"ids": ["a"]}))
            .expect_err("empty clipboard fails");
        assert!(matches!(err, CommandError::EmptyClipboard { .. }), "{err}");
        assert_eq!(engine.photo_len("a"), Some(1));
    }

    #[test]
    fn interaction_folds_many_updates_into_one_step() {
        let mut engine = open_draft();
        engine
            .execute("develop.beginInteraction", &json!({"id": "a"}))
            .expect("begin");
        for value in [1.0, 2.0, 3.0] {
            engine
                .execute(
                    "develop.updateInteraction",
                    &json!({"id": "a", "module": "mod_a", "patch": {"p": {"type": "float", "value": value}}}),
                )
                .expect("update runs");
            assert_eq!(engine.photo_len("a"), Some(1), "no step mid-drag");
        }
        let live = engine.photo_settings("a").expect("live snapshot");
        assert_eq!(
            live.instances
                .get("mod_a", 0)
                .expect("instance")
                .params
                .get("p"),
            Some(&SettingValue::Float(3.0))
        );
        engine
            .execute("develop.endInteraction", &json!({"id": "a"}))
            .expect("end");
        assert_eq!(engine.photo_len("a"), Some(2));
        assert_eq!(
            engine.photo_labels("a").expect("labels").last(),
            Some(&"develop.endInteraction".to_owned())
        );
    }

    #[test]
    fn interaction_cancel_restores_the_pre_drag_settings() {
        let mut engine = open_draft();
        engine
            .execute(
                "develop.set",
                &set_params("mod_a", &json!({"p": {"type": "float", "value": 1.0}})),
            )
            .expect("set");
        let before = engine.photo_settings("a").expect("snapshot");
        engine
            .execute("develop.beginInteraction", &json!({"id": "a"}))
            .expect("begin");
        engine
            .execute(
                "develop.updateInteraction",
                &json!({"id": "a", "module": "mod_a", "patch": {"p": {"type": "float", "value": 9.0}}}),
            )
            .expect("update");
        engine
            .execute("develop.cancelInteraction", &json!({"id": "a"}))
            .expect("cancel");
        assert_eq!(engine.photo_settings("a").expect("snapshot"), before);
        assert_eq!(engine.photo_len("a"), Some(2));
    }

    #[test]
    fn update_without_a_begin_reports_no_interaction() {
        let mut engine = open_draft();
        let err = engine
            .execute(
                "develop.updateInteraction",
                &json!({"id": "a", "module": "mod_a", "patch": {}}),
            )
            .expect_err("update without begin fails");
        assert!(matches!(err, CommandError::NoInteraction { .. }), "{err}");
    }

    #[test]
    fn end_and_cancel_without_a_begin_succeed_quietly() {
        let mut engine = open_draft();
        for cmd in ["develop.endInteraction", "develop.cancelInteraction"] {
            let out = engine
                .execute(cmd, &json!({"id": "a"}))
                .expect("quiet success");
            assert_eq!(out, Value::Null);
        }
        assert_eq!(engine.photo_len("a"), Some(1));
    }
}
