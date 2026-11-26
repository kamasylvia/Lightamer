// SPDX-License-Identifier: GPL-3.0-or-later
//! The `session.*` and `template.*` commands: real sessions on disk.
//!
//! A fresh engine holds nothing; `session.new`, `session.open`, and
//! `session.restore` each install a real session (the store's lock plus
//! its connection) and refuse while one is already open. `session.close`
//! merges the log and releases the lock; `session.verify` reads the open
//! session without writing a byte; `session.backup` and `session.restore`
//! start jobs that duplicate whole packages; `template.save` stores album
//! and favorite structure. None of the seven writes a history step: they
//! move sessions, not photo settings.
//!
//! This module never touches the file system itself: every byte travels
//! through `lightamer-catalog`. Long work never runs inside a command:
//! the backup, restore, and scan jobs run on the pool and report through
//! the job table and events.

use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

use crate::command::{CommandSpec, Outcome, ParamKind, ParamSpec, RunCtx, flag_opt, text_req};
use crate::engine::Engine;
use crate::error::CommandError;

/// The `session.*` and `template.*` specs, in command-id order.
pub(crate) static SPECS: &[CommandSpec] = &[
    CommandSpec {
        id: "session.new",
        summary: "Creates a session package and opens it.",
        params: &[
            ParamSpec {
                name: "name",
                kind: ParamKind::Text,
                required: true,
                doc: "The session name: one directory name.",
            },
            ParamSpec {
                name: "parent",
                kind: ParamKind::Text,
                required: true,
                doc: "The directory that will hold the new session folder.",
            },
        ],
        needs_session: false,
        enabled: require_no_session,
        run: run_new,
    },
    CommandSpec {
        id: "session.open",
        summary: "Opens a session and starts its missing-file scan.",
        params: &[ParamSpec {
            name: "path",
            kind: ParamKind::Text,
            required: true,
            doc: "The session folder, or its database file.",
        }],
        needs_session: false,
        enabled: require_no_session,
        run: run_open,
    },
    CommandSpec {
        id: "session.close",
        summary: "Merges the session log, then releases the lock.",
        params: &[],
        needs_session: true,
        enabled: require_real_session,
        run: run_close,
    },
    CommandSpec {
        id: "session.verify",
        summary: "Reports read-only findings for the open session.",
        params: &[],
        needs_session: true,
        enabled: require_real_session,
        run: run_verify,
    },
    CommandSpec {
        id: "session.backup",
        summary: "Starts a job that duplicates the session package elsewhere.",
        params: &[
            ParamSpec {
                name: "dest",
                kind: ParamKind::Text,
                required: true,
                doc: "The directory to write the backup into.",
            },
            ParamSpec {
                name: "include_trash",
                kind: ParamKind::Flag,
                required: false,
                doc: "Whether Trash/ travels too (default yes).",
            },
        ],
        needs_session: true,
        enabled: require_real_session,
        run: run_backup,
    },
    CommandSpec {
        id: "session.restore",
        summary: "Starts a job that restores a backup package and opens it.",
        params: &[
            ParamSpec {
                name: "backup",
                kind: ParamKind::Text,
                required: true,
                doc: "The backup package to restore from.",
            },
            ParamSpec {
                name: "dest",
                kind: ParamKind::Text,
                required: true,
                doc: "The directory to restore into.",
            },
        ],
        needs_session: false,
        enabled: require_no_session,
        run: run_restore,
    },
    CommandSpec {
        id: "template.save",
        summary: "Saves the album and favorite structure as a template.",
        params: &[ParamSpec {
            name: "name",
            kind: ParamKind::Text,
            required: true,
            doc: "The template name: one file stem.",
        }],
        needs_session: true,
        enabled: require_real_session,
        run: run_template_save,
    },
];

/// Refuses while any session (draft or real) is open: opening a second one
/// would strand the first.
///
/// # Errors
///
/// The human-readable reason when a session is already open.
pub fn require_no_session(engine: &Engine) -> Result<(), String> {
    if engine.has_session() {
        Err("a session is already open; close it first".to_owned())
    } else {
        Ok(())
    }
}

/// Refuses unless a real session is open (drafts hold no store).
///
/// # Errors
///
/// The human-readable reason when no real session is open.
pub fn require_real_session(engine: &Engine) -> Result<(), String> {
    if engine.has_real_session() {
        Ok(())
    } else {
        Err("no real session is open".to_owned())
    }
}

/// Wraps a store refusal in the command that met it.
#[allow(clippy::needless_pass_by_value)] // owned error keeps `map_err` closures terse; cold path
fn store_err(cmd: &str, err: lightamer_catalog::CatalogError) -> CommandError {
    CommandError::Store {
        cmd: cmd.to_owned(),
        reason: err.to_string(),
    }
}

/// The facts every open path reports: root, database, identity, and the
/// unlocked flag. Reads only; the caller installs the session afterwards.
fn open_facts(
    cmd: &str,
    session: &lightamer_catalog::Session,
) -> Result<Map<String, Value>, CommandError> {
    let uuid = session.session_uuid().map_err(|err| store_err(cmd, err))?;
    let mut facts = Map::new();
    facts.insert(
        "root".to_owned(),
        Value::String(session.root().display().to_string()),
    );
    facts.insert(
        "database".to_owned(),
        Value::String(session.db_path().display().to_string()),
    );
    facts.insert("uuid".to_owned(), Value::String(uuid));
    facts.insert(
        "unlocked".to_owned(),
        Value::Bool(session.opened_unlocked()),
    );
    Ok(facts)
}

fn run_new(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "session.new";
    let name = text_req(CMD, params, "name")?;
    let parent = text_req(CMD, params, "parent")?;
    if name.trim().is_empty() {
        return Err(CommandError::BadParam {
            cmd: CMD.to_owned(),
            key: "name".to_owned(),
            reason: "must not be blank".to_owned(),
        });
    }
    if parent.trim().is_empty() {
        return Err(CommandError::BadParam {
            cmd: CMD.to_owned(),
            key: "parent".to_owned(),
            reason: "must not be blank".to_owned(),
        });
    }
    let session = lightamer_catalog::create_session(Path::new(&parent), &name, engine.program())
        .map_err(|err| store_err(CMD, err))?;
    let facts = open_facts(CMD, &session)?;
    engine.install_real_session(session);
    Ok(Value::Object(facts))
}

fn run_open(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "session.open";
    let path = text_req(CMD, params, "path")?;
    let session = lightamer_catalog::open_session(Path::new(&path), engine.program())
        .map_err(|err| store_err(CMD, err))?;
    let root = session.root().to_path_buf();
    let db = session.db_path().to_path_buf();
    let mut facts = open_facts(CMD, &session)?;
    engine.install_real_session(session);
    let job = engine.spawn_scan_job(root, db);
    facts.insert("job".to_owned(), Value::from(job));
    Ok(Value::Object(facts))
}

fn run_close(
    engine: &mut Engine,
    _params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "session.close";
    let Some(session) = engine.take_real_session() else {
        return Err(CommandError::Disabled {
            cmd: CMD.to_owned(),
            reason: "no real session is open".to_owned(),
        });
    };
    let root = session.root().display().to_string();
    engine.clear_after_close();
    lightamer_catalog::close_session(session).map_err(|err| store_err(CMD, err))?;
    Ok(json!({"root": root, "closed": true}))
}

fn run_verify(
    engine: &mut Engine,
    _params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "session.verify";
    let Some(session) = engine.real_session() else {
        return Err(CommandError::Disabled {
            cmd: CMD.to_owned(),
            reason: "no real session is open".to_owned(),
        });
    };
    let report = lightamer_catalog::verify_session(
        session.connection(),
        session.root(),
        session.opened_unlocked(),
    )
    .map_err(|err| store_err(CMD, err))?;
    let findings: Vec<Value> = report
        .findings
        .iter()
        .map(|finding| {
            json!({
                "severity": finding.severity.name(),
                "code": finding.code,
                "detail": finding.detail,
                "repair": finding.repair,
            })
        })
        .collect();
    Ok(json!({"count": findings.len(), "findings": findings}))
}

fn run_backup(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "session.backup";
    let dest = text_req(CMD, params, "dest")?;
    let include_trash = flag_opt(CMD, params, "include_trash")?.unwrap_or(true);
    let dest_path = PathBuf::from(dest);
    // Refuse before spawning, while nothing is touched.
    lightamer_catalog::check_empty_dest(&dest_path).map_err(|err| store_err(CMD, err))?;
    let Some(session) = engine.real_session() else {
        return Err(CommandError::Disabled {
            cmd: CMD.to_owned(),
            reason: "no real session is open".to_owned(),
        });
    };
    let src_root = session.root().to_path_buf();
    let label = format!("backup to {}", dest_path.display());
    let dest_text = dest_path.display().to_string();
    let job = engine.spawn_job("session.backup", label, 0, move |ctx| {
        match lightamer_catalog::backup_session(
            &src_root,
            &dest_path,
            include_trash,
            &|done| ctx.report(done),
            &|| ctx.is_cancelled(),
        ) {
            Ok(_) | Err(lightamer_catalog::CatalogError::Cancelled) => {}
            Err(err) => ctx.fail(err.to_string()),
        }
    });
    Ok(json!({"job": job, "dest": dest_text}))
}

fn run_restore(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "session.restore";
    let backup = text_req(CMD, params, "backup")?;
    let dest = text_req(CMD, params, "dest")?;
    let backup_path = PathBuf::from(backup);
    let dest_path = PathBuf::from(dest);
    // Refuse before spawning, while nothing is touched.
    lightamer_catalog::check_restore_source(&backup_path).map_err(|err| store_err(CMD, err))?;
    lightamer_catalog::check_empty_dest(&dest_path).map_err(|err| store_err(CMD, err))?;
    let program = engine.program().to_owned();
    let label = format!("restore to {}", dest_path.display());
    let dest_text = dest_path.display().to_string();
    let (tx, rx) = std::sync::mpsc::channel();
    let job = engine.spawn_job("session.restore", label, 0, move |ctx| {
        match lightamer_catalog::restore_and_open(
            &backup_path,
            &dest_path,
            &program,
            &|done| ctx.report(done),
            &|| ctx.is_cancelled(),
        ) {
            Ok(session) => {
                let _ = tx.send(session);
            }
            Err(lightamer_catalog::CatalogError::Cancelled) => {}
            Err(err) => ctx.fail(err.to_string()),
        }
    });
    engine.track_restore(job, rx);
    Ok(json!({"job": job, "dest": dest_text}))
}

fn run_template_save(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "template.save";
    let name = text_req(CMD, params, "name")?;
    let Some(session) = engine.real_session() else {
        return Err(CommandError::Disabled {
            cmd: CMD.to_owned(),
            reason: "no real session is open".to_owned(),
        });
    };
    let path = lightamer_catalog::save_template(session.connection(), &name)
        .map_err(|err| store_err(CMD, err))?;
    Ok(json!({"name": name, "path": path.display().to_string()}))
}
