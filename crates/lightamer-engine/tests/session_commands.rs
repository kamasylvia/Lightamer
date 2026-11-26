// SPDX-License-Identifier: GPL-3.0-or-later
//! The seven session commands through `execute`: open gates, outcomes, the
//! read-only verify, templates, and the twenty-command registry.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

mod common;

use lightamer_engine::{CommandError, Engine, command_specs};
use serde_json::{Value, json};

use common::{ScratchDir, drain_all};

/// One text field of an outcome, or a boxed complaint naming it.
fn text<'a>(outcome: &'a Value, key: &str) -> Result<&'a str, Box<dyn std::error::Error>> {
    outcome
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("outcome lacks text {key}: {outcome}").into())
}

#[test]
fn session_new_builds_package_and_holds_lock() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("new")?;
    let mut engine = Engine::new();
    let out = engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    assert!(engine.has_session());
    assert!(engine.has_real_session());
    assert!(engine.photo_ids().is_empty(), "no import yet: no photos");
    let root = scratch.path().join("Studio");
    assert_eq!(text(&out, "root")?, root.to_string_lossy());
    assert_eq!(
        text(&out, "database")?,
        root.join("Studio.lmsessiondb").to_string_lossy()
    );
    assert_ne!(text(&out, "uuid")?, "");
    for dir in ["Capture", "Selects", "Output", "Trash"] {
        assert!(root.join(dir).is_dir(), "missing {dir}");
    }
    // A second engine is refused and told who holds the session.
    let mut other = Engine::new();
    let err = other
        .execute("session.open", &json!({"path": root.to_string_lossy()}))
        .expect_err("double open");
    let msg = err.to_string();
    assert!(msg.contains("already open"), "{msg}");
    assert!(msg.contains("lightamer-engine"), "{msg}");
    engine.execute("session.close", &json!({}))?;
    assert!(!engine.has_session());
    Ok(())
}

#[test]
fn session_open_adopts_existing_folder_in_place() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("adopt")?;
    let folder = scratch.path().join("Adopt");
    std::fs::create_dir_all(folder.join("sub"))?;
    std::fs::write(folder.join("a.txt"), "hello")?;
    std::fs::write(folder.join("sub/b.bin"), [7, 8, 9])?;
    let before_a = std::fs::read(folder.join("a.txt"))?;
    let before_b = std::fs::read(folder.join("sub/b.bin"))?;

    let mut engine = Engine::new();
    let out = engine.execute("session.open", &json!({"path": folder.to_string_lossy()}))?;
    assert_eq!(
        std::fs::read(folder.join("a.txt"))?,
        before_a,
        "adopt moves nothing"
    );
    assert_eq!(
        std::fs::read(folder.join("sub/b.bin"))?,
        before_b,
        "adopt moves nothing"
    );
    assert!(folder.join("Adopt.lmsessiondb").is_file());
    assert!(text(&out, "root")?.ends_with("Adopt"));
    drain_all(&mut engine);
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_open_accepts_database_file_path() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("opendb")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    engine.execute("session.close", &json!({}))?;
    let db = scratch.path().join("Studio").join("Studio.lmsessiondb");
    let out = engine.execute("session.open", &json!({"path": db.to_string_lossy()}))?;
    assert!(engine.has_real_session());
    assert!(text(&out, "root")?.ends_with("Studio"));
    drain_all(&mut engine);
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn open_new_restore_refuse_while_session_open_with_reason() -> Result<(), Box<dyn std::error::Error>>
{
    // On a draft session.
    let mut draft = Engine::open_draft(["a"]);
    for (id, params) in [
        ("session.new", json!({"name": "s", "parent": "p"})),
        ("session.open", json!({"path": "p"})),
        ("session.restore", json!({"backup": "b", "dest": "d"})),
    ] {
        let err = draft.execute(id, &params).expect_err(id);
        assert!(matches!(err, CommandError::Disabled { .. }), "{id}: {err}");
        assert!(err.to_string().contains("already open"), "{id}: {err}");
    }
    // On a real session.
    let scratch = ScratchDir::new("busy")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    for (id, params) in [
        ("session.new", json!({"name": "s", "parent": "p"})),
        ("session.open", json!({"path": "p"})),
        ("session.restore", json!({"backup": "b", "dest": "d"})),
    ] {
        let err = engine.execute(id, &params).expect_err(id);
        assert!(matches!(err, CommandError::Disabled { .. }), "{id}: {err}");
        assert!(err.to_string().contains("already open"), "{id}: {err}");
    }
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_new_refuses_blank_name_and_parent() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("blank")?;
    let mut engine = Engine::new();
    for params in [
        json!({"name": "  ", "parent": scratch.path().to_string_lossy()}),
        json!({"name": "Studio", "parent": "  "}),
    ] {
        let err = engine.execute("session.new", &params).expect_err("blank");
        assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
    }
    assert!(!engine.has_session());
    Ok(())
}

#[test]
fn session_close_releases_lock_and_leaves_no_wal() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("close")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let root = scratch.path().join("Studio");
    let db = root.join("Studio.lmsessiondb");
    // One row through a second connection, so the WAL holds something.
    let planted = rusqlite::Connection::open(&db)?;
    planted.execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash) VALUES ('u1', 'Capture/a.arw', 0, 'a.arw', 1, 'h')",
        [],
    )?;
    drop(planted);
    let out = engine.execute("session.close", &json!({}))?;
    assert_eq!(out.get("closed"), Some(&Value::Bool(true)));
    assert!(!engine.has_session());
    let wal = db.to_string_lossy().into_owned() + "-wal";
    let shm = db.to_string_lossy().into_owned() + "-shm";
    assert!(
        !std::path::Path::new(&wal).exists() || std::fs::metadata(&wal)?.len() == 0,
        "close merges the log"
    );
    assert!(
        !std::path::Path::new(&shm).exists(),
        "no shared memory left"
    );
    // The lock is free: another engine opens the same root.
    let mut other = Engine::new();
    other.execute("session.open", &json!({"path": root.to_string_lossy()}))?;
    drain_all(&mut other);
    other.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn close_verify_backup_template_refuse_without_real_session() {
    let calls = [
        ("session.close", json!({})),
        ("session.verify", json!({})),
        ("session.backup", json!({"dest": "d"})),
        ("template.save", json!({"name": "t"})),
    ];
    // Fresh engine: no session at all.
    let mut engine = Engine::new();
    for (id, params) in &calls {
        let err = engine.execute(id, params).expect_err(id);
        assert!(matches!(err, CommandError::NoSession { .. }), "{id}: {err}");
    }
    // Draft session: the gate names the missing real session.
    let mut draft = Engine::open_draft(["a"]);
    for (id, params) in &calls {
        let err = draft.execute(id, params).expect_err(id);
        assert!(matches!(err, CommandError::Disabled { .. }), "{id}: {err}");
        assert!(err.to_string().contains("no real session"), "{id}: {err}");
    }
    assert_eq!(draft.photo_len("a"), Some(1), "refusals change nothing");
}

#[test]
fn session_verify_reports_nothing_on_healthy() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-ok")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let out = engine.execute("session.verify", &json!({}))?;
    assert_eq!(out.get("count"), Some(&json!(0)));
    assert_eq!(out.get("findings"), Some(&json!([])));
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_verify_reports_planted_problems() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-bad")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let db = scratch.path().join("Studio").join("Studio.lmsessiondb");
    let planted = rusqlite::Connection::open(&db)?;
    planted.execute("PRAGMA foreign_keys = OFF", [])?;
    planted.execute(
        "INSERT INTO snapshots (hash, json) VALUES ('h-orphan', '{\"process\": 1}')",
        [],
    )?;
    planted.execute(
        "INSERT INTO history_steps (photo_id, idx, label, snapshot_hash, created_at) VALUES (4242, 0, 'seed', 'h-gone', 1)",
        [],
    )?;
    planted.execute(
        "INSERT INTO _meta (key, value) VALUES ('display_aux', '{bad')",
        [],
    )?;
    drop(planted);
    let out = engine.execute("session.verify", &json!({}))?;
    let findings = out
        .get("findings")
        .and_then(Value::as_array)
        .ok_or("verify lacks findings")?;
    let codes: Vec<&str> = findings
        .iter()
        .filter_map(|finding| finding.get("code").and_then(Value::as_str))
        .collect();
    for want in [
        "orphan_snapshot",
        "dangling_reference",
        "display_aux_unparseable",
    ] {
        assert!(codes.contains(&want), "{want} missing from {codes:?}");
    }
    for finding in findings {
        for key in ["severity", "code", "detail", "repair"] {
            assert!(finding.get(key).is_some(), "{key} missing from {finding}");
        }
    }
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_verify_keeps_database_bytes() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-ro")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let db = scratch.path().join("Studio").join("Studio.lmsessiondb");
    std::fs::write(scratch.path().join("Studio").join("Capture/a1.arw"), "raw")?;
    rusqlite::Connection::open(&db)?.execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash) VALUES ('u1', 'Capture/a1.arw', 0, 'a1.arw', 1, 'h')",
        [],
    )?;
    let before = std::fs::read(&db)?;
    engine.execute("session.verify", &json!({}))?;
    let after = std::fs::read(&db)?;
    assert_eq!(before, after, "verify moved database bytes");
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn session_verify_changes_neither_photos_nor_digest() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("verify-digest")?;
    let mut engine = Engine::new();
    engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.path().to_string_lossy()}),
    )?;
    let calm = engine.state_digest();
    engine.execute("session.verify", &json!({}))?;
    assert_eq!(engine.state_digest(), calm, "verify is observably nothing");
    assert_eq!(engine.photo_ids(), Vec::<String>::new());
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

/// When set, this test binary runs as the template child: it builds a
/// session under the value and saves a template (the environment holds the
/// templates directory, passed by the parent — safe, unlike in-process
/// mutation under parallel test threads).
const TEMPLATE_CHILD_ENV: &str = "LIGHTAMER_ENGINE_TEMPLATE_CHILD";

#[test]
fn template_save_writes_structure_without_photos() -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(dir) = std::env::var(TEMPLATE_CHILD_ENV) {
        return template_child_main(dir.as_ref());
    }
    let scratch = ScratchDir::new("template")?;
    let templates = scratch.path().join("templates-here");
    let binary = std::env::current_exe()?;
    let output = std::process::Command::new(binary)
        .arg("--exact")
        .arg("template_save_writes_structure_without_photos")
        .env(TEMPLATE_CHILD_ENV, scratch.path())
        .env(lightamer_catalog::TEMPLATE_DIR_ENV, &templates)
        .output()?;
    assert!(
        output.status.success(),
        "template child failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let text = std::fs::read_to_string(templates.join("Desk.json"))?;
    assert!(text.contains("Picks"), "{text}");
    assert!(text.contains("Field disk"), "{text}");
    assert!(
        !text.contains("uuid-secret-9"),
        "photo identity leaked: {text}"
    );
    assert!(
        !text.contains("secret-frame.arw"),
        "photo path leaked: {text}"
    );
    Ok(())
}

fn template_child_main(scratch: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let mut engine = Engine::new();
    let out = engine.execute(
        "session.new",
        &json!({"name": "Studio", "parent": scratch.to_string_lossy()}),
    )?;
    let root = std::path::PathBuf::from(text(&out, "root")?);
    let db = root.join("Studio.lmsessiondb");
    let planted = rusqlite::Connection::open(&db)?;
    planted.execute(
        "INSERT INTO snapshots (hash, json) VALUES ('h1', '{\"process\": 1}')",
        [],
    )?;
    planted.execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash) VALUES ('uuid-secret-9', 'Capture/secret-frame.arw', 0, 'secret-frame.arw', 1, 'h1')",
        [],
    )?;
    planted.execute(
        "INSERT INTO albums (name, kind, created_at) VALUES ('Picks', 'album', 1)",
        [],
    )?;
    planted.execute(
        "INSERT INTO favorites (path, path_kind, name) VALUES ('/Volumes/Field', 1, 'Field disk')",
        [],
    )?;
    drop(planted);
    let out = engine.execute("template.save", &json!({"name": "Desk"}))?;
    let saved = std::path::PathBuf::from(text(&out, "path")?);
    assert!(
        saved.is_file(),
        "template landed nowhere: {}",
        saved.display()
    );
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn registry_holds_twenty_two_commands_with_unique_ids_and_docs()
-> Result<(), Box<dyn std::error::Error>> {
    let specs = command_specs();
    assert_eq!(
        specs.len(),
        22,
        "13 A7a commands plus 7 session commands plus merge/sync"
    );
    let mut ids: Vec<&str> = specs.iter().map(|spec| spec.id).collect();
    ids.sort_unstable();
    ids.dedup();
    assert_eq!(ids.len(), 22, "command ids repeat");
    for spec in specs {
        assert!(!spec.summary.is_empty(), "{} has no summary", spec.id);
        let mut params: Vec<&str> = spec.params.iter().map(|param| param.name).collect();
        params.sort_unstable();
        params.dedup();
        assert_eq!(
            params.len(),
            spec.params.len(),
            "{} repeats a param",
            spec.id
        );
        for param in spec.params {
            assert!(
                !param.doc.is_empty(),
                "{}.{} has no doc",
                spec.id,
                param.name
            );
        }
    }
    // The seven session contracts, pinned parameter by parameter.
    let params_of = |id: &str| {
        specs
            .iter()
            .find(|spec| spec.id == id)
            .map(|spec| spec.params)
            .ok_or_else(|| format!("{id} is not registered"))
    };
    let names = |id: &str| {
        params_of(id).map(|params| params.iter().map(|param| param.name).collect::<Vec<_>>())
    };
    assert_eq!(names("session.new")?, ["name", "parent"]);
    assert_eq!(names("session.open")?, ["path"]);
    assert_eq!(names("session.close")?, Vec::<&str>::new());
    assert_eq!(names("session.verify")?, Vec::<&str>::new());
    assert_eq!(names("session.backup")?, ["dest", "include_trash"]);
    assert_eq!(names("session.restore")?, ["backup", "dest"]);
    assert_eq!(names("template.save")?, ["name"]);
    // The two B13'-b2 merge contracts, pinned parameter by parameter.
    assert_eq!(names("develop.merge")?, ["ids", "selection"]);
    assert_eq!(names("develop.sync")?, ["id", "ids", "selection"]);
    for (id, name, required) in [
        ("session.new", "name", true),
        ("session.new", "parent", true),
        ("session.open", "path", true),
        ("session.backup", "dest", true),
        ("session.backup", "include_trash", false),
        ("session.restore", "backup", true),
        ("session.restore", "dest", true),
        ("template.save", "name", true),
        ("develop.merge", "ids", true),
        ("develop.merge", "selection", false),
        ("develop.sync", "id", true),
        ("develop.sync", "ids", true),
        ("develop.sync", "selection", false),
    ] {
        let param = params_of(id)?
            .iter()
            .find(|param| param.name == name)
            .ok_or_else(|| format!("{id} lacks {name}"))?;
        assert_eq!(param.required, required, "{id}.{name} flips required");
    }
    Ok(())
}
