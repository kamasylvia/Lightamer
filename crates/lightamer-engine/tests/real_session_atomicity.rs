// SPDX-License-Identifier: GPL-3.0-or-later
//! Failure atomicity on a real session: every persisted command under three
//! bad params and one store failure leaves memory and the store unchanged
//! (compared through the store-covering digest). Memory-only commands succeed
//! past write-blocking triggers, proving they never write.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

#[allow(dead_code)] // this target never uses the shared helpers
mod common;
#[allow(dead_code)] // this target leaves some helpers of this module unused
mod real_common;

use lightamer_engine::CommandError;
use serde_json::{Value, json};

use real_common::{close_fixture, install_refuse_triggers, open_real_fixture, set_float};

/// Asserts one bad call fails with `want` and the digest does not move.
fn assert_bad(fixture: &mut real_common::RealFixture, cmd: &str, params: &Value, want: &str) {
    let before = fixture.engine.state_digest();
    let before_len = fixture.engine.photo_len(&fixture.uuids[0]);
    let err = fixture
        .engine
        .execute(cmd, params)
        .expect_err("bad params fail");
    let hit = match want {
        "unknown" => matches!(err, CommandError::UnknownParam { .. }),
        "missing" => matches!(err, CommandError::MissingParam { .. }),
        "bad" => matches!(err, CommandError::BadParam { .. }),
        _ => false,
    };
    assert!(hit, "want {want}, got {err}");
    assert_eq!(fixture.engine.state_digest(), before);
    assert_eq!(fixture.engine.photo_len(&fixture.uuids[0]), before_len);
}

#[test]
fn set_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-set", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "develop.set",
        &json!({"ids": [&a], "module": "mod_a", "patch": {}, "bogus": 1}),
        "unknown",
    );
    assert_bad(
        &mut fixture,
        "develop.set",
        &json!({"ids": [&a], "patch": {}}),
        "missing",
    );
    assert_bad(
        &mut fixture,
        "develop.set",
        &json!({"ids": [&a], "module": "mod_a", "patch": {"p_x": {"type": "float", "value": "xx"}}}),
        "bad",
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn reset_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-reset", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "develop.reset",
        &json!({"ids": [&a], "bogus": 1}),
        "unknown",
    );
    assert_bad(&mut fixture, "develop.reset", &json!({}), "missing");
    assert_bad(&mut fixture, "develop.reset", &json!({"ids": a}), "bad");
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn copy_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-copy", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "develop.copy",
        &json!({"id": a, "bogus": 1}),
        "unknown",
    );
    assert_bad(&mut fixture, "develop.copy", &json!({}), "missing");
    assert_bad(&mut fixture, "develop.copy", &json!({"id": 5}), "bad");
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn paste_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-paste", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    fixture.engine.execute("develop.copy", &json!({"id": a}))?;
    assert_bad(
        &mut fixture,
        "develop.paste",
        &json!({"ids": [&a], "bogus": 1}),
        "unknown",
    );
    assert_bad(&mut fixture, "develop.paste", &json!({}), "missing");
    assert_bad(&mut fixture, "develop.paste", &json!({"ids": a}), "bad");
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn begin_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-begin", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "develop.beginInteraction",
        &json!({"id": a, "bogus": 1}),
        "unknown",
    );
    assert_bad(
        &mut fixture,
        "develop.beginInteraction",
        &json!({}),
        "missing",
    );
    assert_bad(
        &mut fixture,
        "develop.beginInteraction",
        &json!({"id": 5}),
        "bad",
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn update_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-update", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    fixture
        .engine
        .execute("develop.beginInteraction", &json!({"id": a}))?;
    assert_bad(
        &mut fixture,
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {}, "bogus": 1}),
        "unknown",
    );
    assert_bad(
        &mut fixture,
        "develop.updateInteraction",
        &json!({"id": a, "patch": {}}),
        "missing",
    );
    assert_bad(
        &mut fixture,
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "bool", "value": 1}}}),
        "bad",
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn end_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-end", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "develop.endInteraction",
        &json!({"id": a, "bogus": 1}),
        "unknown",
    );
    assert_bad(
        &mut fixture,
        "develop.endInteraction",
        &json!({}),
        "missing",
    );
    assert_bad(
        &mut fixture,
        "develop.endInteraction",
        &json!({"id": 5}),
        "bad",
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn cancel_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-cancel", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "develop.cancelInteraction",
        &json!({"id": a, "bogus": 1}),
        "unknown",
    );
    assert_bad(
        &mut fixture,
        "develop.cancelInteraction",
        &json!({}),
        "missing",
    );
    assert_bad(
        &mut fixture,
        "develop.cancelInteraction",
        &json!({"id": 5}),
        "bad",
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn undo_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-undo", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "history.undo",
        &json!({"id": a, "bogus": 1}),
        "unknown",
    );
    assert_bad(&mut fixture, "history.undo", &json!({}), "missing");
    assert_bad(&mut fixture, "history.undo", &json!({"id": 5}), "bad");
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn redo_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-redo", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "history.redo",
        &json!({"id": a, "bogus": 1}),
        "unknown",
    );
    assert_bad(&mut fixture, "history.redo", &json!({}), "missing");
    assert_bad(&mut fixture, "history.redo", &json!({"id": 5}), "bad");
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn goto_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-goto", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "history.goto",
        &json!({"id": a, "index": 0, "bogus": 1}),
        "unknown",
    );
    assert_bad(&mut fixture, "history.goto", &json!({"id": a}), "missing");
    assert_bad(
        &mut fixture,
        "history.goto",
        &json!({"id": a, "index": "x"}),
        "bad",
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn process_bad_params_change_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("bad-process", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    assert_bad(
        &mut fixture,
        "process.update",
        &json!({"ids": [&a], "bogus": 1}),
        "unknown",
    );
    assert_bad(&mut fixture, "process.update", &json!({}), "missing");
    assert_bad(&mut fixture, "process.update", &json!({"ids": a}), "bad");
    close_fixture(&mut fixture)?;
    Ok(())
}

/// Asserts one valid call fails as a store refusal with the digest unmoved.
fn assert_store_failure(fixture: &mut real_common::RealFixture, cmd: &str, params: &Value) {
    let before = fixture.engine.state_digest();
    let before_len = fixture.engine.photo_len(&fixture.uuids[0]);
    let err = fixture
        .engine
        .execute(cmd, params)
        .expect_err("the store refuses");
    assert!(matches!(err, CommandError::Store { .. }), "{err}");
    assert_eq!(fixture.engine.state_digest(), before);
    assert_eq!(fixture.engine.photo_len(&fixture.uuids[0]), before_len);
}

#[test]
fn set_store_failure_changes_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-set", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(
        &mut fixture,
        "develop.set",
        &json!({"ids": [&a], "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 2.0}}}),
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn reset_store_failure_changes_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>>
{
    let mut fixture = open_real_fixture("fail-reset", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "develop.reset", &json!({"ids": [&a]}));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn copy_ignores_a_store_failure() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-copy", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    install_refuse_triggers(&fixture.db)?;
    let out = fixture.engine.execute("develop.copy", &json!({"id": a}))?;
    assert_eq!(out, json!({"modules": 1}));
    assert!(fixture.engine.has_clipboard());
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn paste_store_failure_changes_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>>
{
    let mut fixture = open_real_fixture("fail-paste", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    fixture.engine.execute("develop.copy", &json!({"id": a}))?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "develop.paste", &json!({"ids": [&a]}));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn begin_fresh_ignores_a_store_failure() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-begin-fresh", 1)?;
    let a = fixture.uuids[0].clone();
    install_refuse_triggers(&fixture.db)?;
    fixture
        .engine
        .execute("develop.beginInteraction", &json!({"id": a}))?;
    fixture.engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    fixture
        .engine
        .execute("develop.cancelInteraction", &json!({"id": a}))?;
    assert_eq!(fixture.engine.photo_len(&a), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn begin_settling_store_failure_changes_neither_memory_nor_store()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-begin-settle", 1)?;
    let a = fixture.uuids[0].clone();
    fixture
        .engine
        .execute("develop.beginInteraction", &json!({"id": a}))?;
    fixture.engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "develop.beginInteraction", &json!({"id": a}));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn update_ignores_a_store_failure() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-update", 1)?;
    let a = fixture.uuids[0].clone();
    fixture
        .engine
        .execute("develop.beginInteraction", &json!({"id": a}))?;
    install_refuse_triggers(&fixture.db)?;
    fixture.engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    assert_eq!(fixture.engine.photo_len(&a), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn end_changed_store_failure_changes_neither_memory_nor_store()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-end", 1)?;
    let a = fixture.uuids[0].clone();
    fixture
        .engine
        .execute("develop.beginInteraction", &json!({"id": a}))?;
    fixture.engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "develop.endInteraction", &json!({"id": a}));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn end_noop_ignores_a_store_failure() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-end-noop", 1)?;
    let a = fixture.uuids[0].clone();
    install_refuse_triggers(&fixture.db)?;
    fixture
        .engine
        .execute("develop.endInteraction", &json!({"id": a}))?;
    assert_eq!(fixture.engine.photo_len(&a), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn cancel_ignores_a_store_failure() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-cancel", 1)?;
    let a = fixture.uuids[0].clone();
    fixture
        .engine
        .execute("develop.beginInteraction", &json!({"id": a}))?;
    fixture.engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    install_refuse_triggers(&fixture.db)?;
    fixture
        .engine
        .execute("develop.cancelInteraction", &json!({"id": a}))?;
    assert_eq!(fixture.engine.photo_len(&a), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn undo_store_failure_changes_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-undo", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "history.undo", &json!({"id": a}));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn redo_store_failure_changes_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-redo", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    fixture.engine.execute("history.undo", &json!({"id": a}))?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "history.redo", &json!({"id": a}));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn goto_store_failure_changes_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("fail-goto", 1)?;
    let a = fixture.uuids[0].clone();
    set_float(&mut fixture.engine, &a, "mod_a", "p_x", 1.0)?;
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "history.goto", &json!({"id": a, "index": 0}));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn process_store_failure_changes_neither_memory_nor_store() -> Result<(), Box<dyn std::error::Error>>
{
    let mut fixture = open_real_fixture("fail-process", 2)?;
    let (old, new) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    {
        let settings = lightamer_history::PhotoSettings {
            process: lightamer_history::ProcessVersion(0),
            ..Default::default()
        };
        let json = settings.canonical_json()?;
        let mut raw = rusqlite::Connection::open(&fixture.db)?;
        let record = lightamer_catalog::find_photo_by_uuid(&raw, &old)?.ok_or("photo vanished")?;
        lightamer_catalog::push_step(&mut raw, record.id, "develop.set", &json)?;
    }
    install_refuse_triggers(&fixture.db)?;
    assert_store_failure(&mut fixture, "process.update", &json!({"ids": [&old]}));
    // A current photo writes nothing, so the refusal never fires.
    let out = fixture
        .engine
        .execute("process.update", &json!({"ids": [&new]}))?;
    assert_eq!(out, json!({"updated": 0}));
    close_fixture(&mut fixture)?;
    Ok(())
}
