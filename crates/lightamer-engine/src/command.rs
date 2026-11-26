// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from lightcraft crates/engine/src/cmd/mod.rs (commit 0da998f2) — reworked:
// the menus/shortcut/journal fields are dropped (UI placement and replay are not engine
// concerns), a machine-readable parameter schema (`params`) replaces the prose-only
// description, enablement takes the engine instead of the session, and runs receive a
// `RunCtx` that collects the events the call dispatches on success.
//! Command declarations, lookup, and the shared parameter vocabulary.
//!
//! Each command is one static [`CommandSpec`]: an id, a one-line summary, a
//! machine-readable parameter list, an enablement check, and the run function.
//! Per-area modules (`develop`, `history`,
//! [`jobs`][crate::jobs]) own static spec arrays; [`command_specs`] concatenates
//! them and [`find_command`] looks one id up.
//!
//! Parameters arrive as [`serde_json::Value`] (untyped at the boundary, like
//! upstream) but every command declares a [`ParamSpec`] list, so frontends,
//! the CLI, and a future MCP schema can all enumerate what a command takes
//! without calling it.

use std::sync::LazyLock;

use serde_json::{Map, Value};

use crate::engine::Engine;
use crate::error::CommandError;
use crate::event::Event;

/// What a command returns on success: small JSON (counts, cursors).
///
/// Commands report facts about what they did, never live references: the
/// caller reads richer state through the engine's snapshot accessors.
pub type Outcome = Value;

/// A command's body: validated params in, outcome or typed error out.
///
/// The engine guarantees atomicity around this call (state snapshot plus
/// restore on error), so a run function validates everything it can up
/// front and then mutates. Events go to `ctx`, never to listeners directly.
pub type Run = fn(&mut Engine, &Map<String, Value>, &mut RunCtx) -> Result<Outcome, CommandError>;

/// Whether the command may run now: `Ok` or the human-readable reason.
pub type Enabled = fn(&Engine) -> Result<(), String>;

/// The value kinds a parameter can take.
///
/// This is the command-boundary vocabulary (JSON-shaped), not the settings
/// vocabulary: values are checked here and only then converted into settings.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParamKind {
    /// JSON boolean.
    Flag,
    /// JSON integer (no fractions, no negatives where an index is wanted).
    Integer,
    /// JSON number, reserved for later commands.
    Float,
    /// JSON string.
    Text,
    /// One of a fixed option list, reserved for later commands.
    Enum {
        /// The allowed option names.
        variants: &'static [&'static str],
    },
    /// A non-empty JSON array of photo-id strings.
    PhotoIds,
    /// A JSON object mapping parameter names to typed setting values.
    Patch,
}

impl ParamKind {
    /// The short kind name used in listings.
    #[must_use]
    pub const fn kind_name(self) -> &'static str {
        match self {
            ParamKind::Flag => "flag",
            ParamKind::Integer => "integer",
            ParamKind::Float => "float",
            ParamKind::Text => "text",
            ParamKind::Enum { .. } => "enum",
            ParamKind::PhotoIds => "photo-ids",
            ParamKind::Patch => "patch",
        }
    }
}

/// One declared parameter of a command.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ParamSpec {
    /// The key in the params object.
    pub name: &'static str,
    /// The accepted value kind.
    pub kind: ParamKind,
    /// Whether the key must be present.
    pub required: bool,
    /// One line saying what the parameter means.
    pub doc: &'static str,
}

/// One command's static declaration.
///
/// Built by hand per command (no macro): twenty commands do not need a
/// macro, and the struct literal keeps every field visible at the site.
#[derive(Clone, Copy, Debug)]
pub struct CommandSpec {
    /// Stable id, e.g. `develop.set` (also the history-step label).
    pub id: &'static str,
    /// One sentence saying what the command does.
    pub summary: &'static str,
    /// The machine-readable parameter list.
    pub params: &'static [ParamSpec],
    /// Whether a session must be open; refused as `NoSession`, not `Disabled`.
    pub needs_session: bool,
    /// Whether the command may run now (dynamic conditions beyond the session).
    pub enabled: Enabled,
    /// The body.
    pub run: Run,
}

/// Events one call collects, dispatched after the call commits.
#[derive(Debug, Default)]
pub struct RunCtx {
    events: Vec<Event>,
}

impl RunCtx {
    /// Queues one event for dispatch after success.
    pub fn emit(&mut self, event: Event) {
        self.events.push(event);
    }

    /// Drains the queued events, in emission order.
    pub(crate) fn take(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.events)
    }
}

/// Always runnable: for commands whose only gate is the session flag.
///
/// # Errors
///
/// Never fails; the `Result` matches the [`Enabled`] shape.
pub fn always(_engine: &Engine) -> Result<(), String> {
    Ok(())
}

/// Every registered spec, concatenated from the per-area arrays.
#[must_use]
pub fn command_specs() -> &'static [CommandSpec] {
    static SPECS: LazyLock<Vec<CommandSpec>> = LazyLock::new(|| {
        let mut all = Vec::new();
        all.extend_from_slice(crate::develop::SPECS);
        all.extend_from_slice(crate::history::SPECS);
        all.extend_from_slice(crate::jobs::SPECS);
        all.extend_from_slice(crate::session::SPECS);
        all
    });
    &SPECS
}

/// Finds one command by id; [`None`] when nothing is registered.
#[must_use]
pub fn find_command(id: &str) -> Option<&'static CommandSpec> {
    command_specs().iter().find(|spec| spec.id == id)
}

/// Validates the raw params value against one spec: object shape, no unknown
/// keys, every required key present. Type checks stay with the extractors.
pub(crate) fn checked_params(
    spec: &CommandSpec,
    params: &Value,
) -> Result<Map<String, Value>, CommandError> {
    let map = match params {
        Value::Null => Map::new(),
        Value::Object(map) => map.clone(),
        _ => {
            return Err(CommandError::BadParam {
                cmd: spec.id.to_owned(),
                key: "params".to_owned(),
                reason: "must be an object".to_owned(),
            });
        }
    };
    for key in map.keys() {
        if !spec.params.iter().any(|decl| decl.name == key) {
            return Err(CommandError::UnknownParam {
                cmd: spec.id.to_owned(),
                key: key.clone(),
            });
        }
    }
    for decl in spec.params {
        if decl.required && !map.contains_key(decl.name) {
            return Err(CommandError::MissingParam {
                cmd: spec.id.to_owned(),
                key: decl.name.to_owned(),
            });
        }
    }
    Ok(map)
}

/// Reads one required photo id (`id`).
pub(crate) fn id_req(cmd: &str, params: &Map<String, Value>) -> Result<String, CommandError> {
    match params.get("id") {
        Some(Value::String(id)) => Ok(id.clone()),
        _ => Err(CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: "id".to_owned(),
            reason: "must be a photo-id string".to_owned(),
        }),
    }
}

/// Reads one required photo-id list (`ids`), deduplicated in first-see order.
pub(crate) fn ids_req(cmd: &str, params: &Map<String, Value>) -> Result<Vec<String>, CommandError> {
    let bad = |reason: &str| CommandError::BadParam {
        cmd: cmd.to_owned(),
        key: "ids".to_owned(),
        reason: reason.to_owned(),
    };
    let Some(Value::Array(ids)) = params.get("ids") else {
        return Err(bad("must be an array of photo-id strings"));
    };
    let mut out = Vec::with_capacity(ids.len());
    for id in ids {
        let Some(text) = id.as_str() else {
            return Err(bad("must be an array of photo-id strings"));
        };
        if !out.contains(&text.to_owned()) {
            out.push(text.to_owned());
        }
    }
    if out.is_empty() {
        return Err(bad("needs at least one photo id"));
    }
    Ok(out)
}

/// Reads one required string (`key`).
pub(crate) fn text_req(
    cmd: &str,
    params: &Map<String, Value>,
    key: &str,
) -> Result<String, CommandError> {
    match params.get(key) {
        Some(Value::String(text)) => Ok(text.clone()),
        _ => Err(CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: key.to_owned(),
            reason: "must be a string".to_owned(),
        }),
    }
}

/// Reads one required unsigned integer (`key`).
pub(crate) fn uint_req(
    cmd: &str,
    params: &Map<String, Value>,
    key: &str,
) -> Result<u64, CommandError> {
    match params.get(key) {
        Some(value) => value.as_u64().ok_or_else(|| CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: key.to_owned(),
            reason: "must be an unsigned integer".to_owned(),
        }),
        None => Err(CommandError::MissingParam {
            cmd: cmd.to_owned(),
            key: key.to_owned(),
        }),
    }
}

/// Reads one optional multi-instance index (`multi`, defaults to 0).
pub(crate) fn multi_opt(cmd: &str, params: &Map<String, Value>) -> Result<u32, CommandError> {
    match params.get("multi") {
        None => Ok(0),
        Some(value) => {
            let raw = value.as_u64().ok_or_else(|| CommandError::BadParam {
                cmd: cmd.to_owned(),
                key: "multi".to_owned(),
                reason: "must be an unsigned integer".to_owned(),
            })?;
            u32::try_from(raw).map_err(|_| CommandError::BadParam {
                cmd: cmd.to_owned(),
                key: "multi".to_owned(),
                reason: "must fit in 32 bits".to_owned(),
            })
        }
    }
}

/// Reads one optional on/off switch (`enabled`).
pub(crate) fn enabled_opt(
    cmd: &str,
    params: &Map<String, Value>,
) -> Result<Option<bool>, CommandError> {
    match params.get("enabled") {
        None => Ok(None),
        Some(Value::Bool(flag)) => Ok(Some(*flag)),
        Some(_) => Err(CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: "enabled".to_owned(),
            reason: "must be a boolean".to_owned(),
        }),
    }
}
/// Reads one optional on/off switch (`key`).
pub(crate) fn flag_opt(
    cmd: &str,
    params: &Map<String, Value>,
    key: &str,
) -> Result<Option<bool>, CommandError> {
    match params.get(key) {
        None => Ok(None),
        Some(Value::Bool(flag)) => Ok(Some(*flag)),
        Some(_) => Err(CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: key.to_owned(),
            reason: "must be a boolean".to_owned(),
        }),
    }
}

/// Reads one required patch object (`patch`): parameter name to value.
pub(crate) fn patch_req(
    cmd: &str,
    params: &Map<String, Value>,
) -> Result<Map<String, Value>, CommandError> {
    match params.get("patch") {
        Some(Value::Object(patch)) => Ok(patch.clone()),
        _ => Err(CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: "patch".to_owned(),
            reason: "must be an object mapping parameter names to values".to_owned(),
        }),
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{command_specs, find_command};

    #[test]
    fn registry_has_no_duplicate_ids() {
        let mut ids: Vec<&str> = command_specs().iter().map(|spec| spec.id).collect();
        let total = ids.len();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), total, "duplicate command ids");
        assert!(!ids.is_empty(), "no commands registered");
    }

    #[test]
    fn registry_params_have_no_duplicate_names() {
        for spec in command_specs() {
            let mut names: Vec<&str> = spec.params.iter().map(|decl| decl.name).collect();
            let total = names.len();
            names.sort_unstable();
            names.dedup();
            assert_eq!(names.len(), total, "duplicate params in {}", spec.id);
        }
    }

    #[test]
    fn registry_commands_all_carry_a_summary() {
        for spec in command_specs() {
            assert!(
                !spec.summary.trim().is_empty(),
                "{} has no summary",
                spec.id
            );
            for decl in spec.params {
                assert!(
                    !decl.doc.trim().is_empty(),
                    "{}.{} has no doc",
                    spec.id,
                    decl.name
                );
            }
        }
    }

    #[test]
    fn find_command_round_trips_every_spec() {
        for spec in command_specs() {
            let found = find_command(spec.id).expect("registered id resolves");
            assert_eq!(found.id, spec.id);
        }
        assert!(find_command("no.such.command").is_none());
    }

    #[test]
    fn param_kinds_render_short_names() {
        use super::{ParamKind, ParamSpec};
        let decl = ParamSpec {
            name: "p",
            kind: ParamKind::PhotoIds,
            required: true,
            doc: "d",
        };
        assert_eq!(decl.kind.kind_name(), "photo-ids");
        assert_eq!(ParamKind::Flag.kind_name(), "flag");
        assert_eq!(ParamKind::Integer.kind_name(), "integer");
        assert_eq!(ParamKind::Float.kind_name(), "float");
        assert_eq!(ParamKind::Text.kind_name(), "text");
        assert_eq!(ParamKind::Patch.kind_name(), "patch");
        assert_eq!(ParamKind::Enum { variants: &["a"] }.kind_name(), "enum");
    }
}
