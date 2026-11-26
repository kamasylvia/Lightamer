// SPDX-License-Identifier: GPL-3.0-or-later
//! A7a contracts replayed on a real session, plus the persistence behaviors:
//! lazy loading, eviction, close/reopen, batch atomicity, trimming, and the
//! store-covering digest.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

#[allow(dead_code)]
mod common;
#[allow(dead_code)]
mod real_common;
use std::path::Path;

use lightamer_engine::{CommandError, Engine};
use serde_json::json;

use real_common::{close_fixture, current_float, open_real_fixture, set_float};

/// Every step label of one photo, oldest first.
fn labels(engine: &Engine, id: &str) -> Vec<String> {
    engine.photo_labels(id).unwrap_or_default()
}

/// Stored labels and cursor of one photo, read behind the engine's back.
fn stored_labels(db: &Path, uuid: &str) -> Result<(Vec<String>, i64), Box<dyn std::error::Error>> {
    let raw = rusqlite::Connection::open(db)?;
    let record = lightamer_catalog::find_photo_by_uuid(&raw, uuid)?.ok_or("photo vanished")?;
    let read = lightamer_catalog::read_history(&raw, record.id)?;
    Ok((
        read.steps.iter().map(|step| step.label.clone()).collect(),
        read.cursor,
    ))
}

/// Pushes one step with an explicit process number behind the engine's back.
fn push_with_process(
    db: &Path,
    uuid: &str,
    process: u32,
) -> Result<(), Box<dyn std::error::Error>> {
    let settings = lightamer_history::PhotoSettings {
        process: lightamer_history::ProcessVersion(process),
        ..Default::default()
    };
    let json = settings.canonical_json()?;
    let mut raw = rusqlite::Connection::open(db)?;
    let record = lightamer_catalog::find_photo_by_uuid(&raw, uuid)?.ok_or("photo vanished")?;
    lightamer_catalog::push_step(&mut raw, record.id, "develop.set", &json)?;
    Ok(())
}

#[test]
fn set_commits_one_step_per_photo_and_persists_it() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-set", 2)?;
    let engine = &mut fixture.engine;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    engine.execute(
        "develop.set",
        &json!({"ids": [&a, &b], "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 1.5}}}),
    )?;
    for id in [&a, &b] {
        assert_eq!(engine.photo_len(id), Some(2));
        assert_eq!(engine.photo_cursor(id), Some(1));
        assert_eq!(labels(engine, id), vec!["import", "develop.set"]);
        assert_eq!(current_float(engine, id, "mod_a", "p_x"), Some(1.5));
    }
    assert_eq!(
        stored_labels(&fixture.db, &a)?,
        (vec!["import".to_owned(), "develop.set".to_owned()], 1)
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn reset_commits_default_settings_as_one_step() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-reset", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.reset", &json!({"ids": [&a]}))?;
    assert_eq!(engine.photo_len(&a), Some(3));
    assert_eq!(
        labels(engine, &a),
        vec!["import", "develop.set", "develop.reset"]
    );
    let current = engine.photo_settings(&a).expect("current");
    assert_eq!(*current, lightamer_history::PhotoSettings::default());
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn copy_fills_the_clipboard_without_a_step() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-copy", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    assert!(!engine.has_clipboard());
    let out = engine.execute("develop.copy", &json!({"id": a}))?;
    assert_eq!(out, json!({"modules": 1}));
    assert!(engine.has_clipboard());
    assert_eq!(engine.photo_len(&fixture.uuids[0]), Some(2));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn paste_commits_one_step_per_target_and_keeps_their_process()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-paste", 3)?;
    let (a, b, c) = (
        fixture.uuids[0].clone(),
        fixture.uuids[1].clone(),
        fixture.uuids[2].clone(),
    );
    push_with_process(&fixture.db, &c, 0)?;
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.copy", &json!({"id": a}))?;
    let out = engine.execute("develop.paste", &json!({"ids": [&b, &c]}))?;
    assert_eq!(out, json!({"pasted": 2}));
    assert_eq!(labels(engine, &b), vec!["import", "develop.paste"]);
    assert_eq!(
        labels(engine, &c),
        vec!["import", "develop.set", "develop.paste"]
    );
    for id in [&b, &c] {
        assert_eq!(current_float(engine, id, "mod_a", "p_x"), Some(1.0));
    }
    let kept = engine.photo_settings(&c).expect("target");
    assert_eq!(kept.process, lightamer_history::ProcessVersion(0));
    assert_eq!(
        stored_labels(&fixture.db, &c)?.0,
        vec!["import", "develop.set", "develop.paste"]
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn paste_with_an_empty_clipboard_fails_and_changes_nothing()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-paste-empty", 1)?;
    let engine = &mut fixture.engine;
    let before = engine.state_digest();
    let err = engine
        .execute("develop.paste", &json!({"ids": [fixture.uuids[0]]}))
        .expect_err("empty clipboard fails");
    assert!(matches!(err, CommandError::EmptyClipboard { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(engine.photo_len(&fixture.uuids[0]), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn drag_updates_fold_into_one_step_on_end() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-drag", 2)?;
    let engine = &mut fixture.engine;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    engine.execute("develop.beginInteraction", &json!({"id": a}))?;
    for value in [1.0, 2.0] {
        engine.execute(
            "develop.updateInteraction",
            &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": value}}}),
        )?;
    }
    assert_eq!(engine.photo_len(&a), Some(1));
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(2.0));
    engine.execute("develop.endInteraction", &json!({"id": a}))?;
    assert_eq!(engine.photo_len(&a), Some(2));
    assert_eq!(labels(engine, &a), vec!["import", "develop.endInteraction"]);
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(2.0));
    // Begin then end without any update stores nothing.
    engine.execute("develop.beginInteraction", &json!({"id": b}))?;
    engine.execute("develop.endInteraction", &json!({"id": b}))?;
    assert_eq!(engine.photo_len(&b), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn drag_cancel_restores_the_pre_drag_settings() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-cancel", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.beginInteraction", &json!({"id": a}))?;
    engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(9.0));
    engine.execute("develop.cancelInteraction", &json!({"id": a}))?;
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(1.0));
    assert_eq!(engine.photo_len(&a), Some(2));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn undo_redo_goto_move_only_the_cursor() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-moves", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    set_float(engine, &a, "mod_a", "p_x", 2.0)?;
    assert_eq!(engine.photo_cursor(&a), Some(2));
    engine.execute("history.undo", &json!({"id": a}))?;
    assert_eq!(engine.photo_cursor(&a), Some(1));
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(1.0));
    engine.execute("history.redo", &json!({"id": a}))?;
    assert_eq!(engine.photo_cursor(&a), Some(2));
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(2.0));
    engine.execute("history.goto", &json!({"id": a, "index": 0}))?;
    assert_eq!(engine.photo_cursor(&a), Some(0));
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), None);
    engine.execute("history.goto", &json!({"id": a, "index": 2}))?;
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(2.0));
    assert_eq!(engine.photo_len(&a), Some(3));
    assert_eq!(stored_labels(&fixture.db, &a)?, (labels(engine, &a), 2));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn process_update_commits_only_outdated_photos() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-process", 3)?;
    let (old, new, newer) = (
        fixture.uuids[0].clone(),
        fixture.uuids[1].clone(),
        fixture.uuids[2].clone(),
    );
    push_with_process(&fixture.db, &old, 0)?;
    push_with_process(&fixture.db, &newer, 7)?;
    let engine = &mut fixture.engine;
    let out = engine.execute("process.update", &json!({"ids": [&old, &new, &newer]}))?;
    assert_eq!(out, json!({"updated": 1}));
    assert_eq!(engine.photo_len(&old), Some(3));
    assert_eq!(
        engine.photo_settings(&old).expect("updated").process,
        lightamer_history::ProcessVersion::LATEST
    );
    assert_eq!(labels(engine, &old)[2], "process.update");
    assert_eq!(engine.photo_len(&new), Some(1));
    assert_eq!(engine.photo_len(&newer), Some(2));
    assert_eq!(
        engine.photo_settings(&newer).expect("newer").process,
        lightamer_history::ProcessVersion(7)
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn undo_with_nowhere_to_go_is_refused() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("parity-stuck", 1)?;
    let engine = &mut fixture.engine;
    let before = engine.state_digest();
    for cmd in ["history.undo", "history.redo"] {
        let err = engine
            .execute(cmd, &json!({"id": fixture.uuids[0]}))
            .expect_err("nowhere to move fails");
        assert!(matches!(err, CommandError::Disabled { .. }), "{err}");
    }
    let err = engine
        .execute("history.goto", &json!({"id": fixture.uuids[0], "index": 9}))
        .expect_err("out of range fails");
    assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(engine.photo_len(&fixture.uuids[0]), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn stored_step_zero_is_labelled_import() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("seed-align", 1)?;
    let engine = &fixture.engine;
    assert_eq!(labels(engine, &fixture.uuids[0]), vec!["import"]);
    assert_eq!(
        stored_labels(&fixture.db, &fixture.uuids[0])?.0,
        vec!["import"]
    );
    assert_eq!(lightamer_catalog::INITIAL_LABEL, "import");
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn unknown_uuid_reports_no_photo_like_a_draft() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("lazy-unknown", 1)?;
    let engine = &mut fixture.engine;
    let err = engine
        .execute(
            "develop.set",
            &json!({"ids": ["no-such-photo"], "module": "mod_a", "patch": {}}),
        )
        .expect_err("unknown uuid fails");
    assert!(matches!(err, CommandError::NoPhoto { .. }), "{err}");
    let mut draft = Engine::open_draft(["a"]);
    draft.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    let draft_err = draft
        .execute(
            "develop.set",
            &json!({"ids": ["no-such-photo"], "module": "mod_a", "patch": {}}),
        )
        .expect_err("draft fails the same way");
    assert!(matches!(draft_err, CommandError::NoPhoto { .. }));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn first_use_loads_the_photo_from_the_store() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("lazy-first", 3)?;
    let engine = &mut fixture.engine;
    assert_eq!(engine.loaded_photo_count(), 0);
    let mut wanted = fixture.uuids.clone();
    wanted.sort();
    assert_eq!(engine.photo_ids(), wanted);
    assert_eq!(engine.loaded_photo_count(), 0);
    set_float(engine, &fixture.uuids[0], "mod_a", "p_x", 1.0)?;
    assert_eq!(engine.loaded_photo_count(), 1);
    assert!(engine.is_photo_loaded(&fixture.uuids[0]));
    assert!(!engine.is_photo_loaded(&fixture.uuids[1]));
    assert_eq!(engine.photo_len(&fixture.uuids[0]), Some(2));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn photo_ids_list_the_store_not_the_cache() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("lazy-ids", 2)?;
    let fourth = {
        let mut raw = rusqlite::Connection::open(&fixture.db)?;
        let name = "extra.arw";
        let rel = Path::new("Capture").join(name);
        std::fs::write(fixture.root.join(&rel), b"")?;
        let record = lightamer_catalog::register_photo(
            &mut raw,
            &fixture.root,
            &fixture.root.join(&rel),
            name,
            Some(0),
        )?;
        record.uuid
    };
    let engine = &fixture.engine;
    assert_eq!(engine.loaded_photo_count(), 0);
    let mut wanted = fixture.uuids.clone();
    wanted.push(fourth);
    wanted.sort();
    assert_eq!(engine.photo_ids(), wanted);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn evicted_photos_reload_exactly_from_the_store() -> Result<(), Box<dyn std::error::Error>> {
    use lightamer_engine::engine::PHOTO_CACHE_LIMIT;
    let mut fixture = open_real_fixture("lazy-evict", 70)?;
    let engine = &mut fixture.engine;
    let pin = fixture.uuids[0].clone();
    engine.execute("develop.beginInteraction", &json!({"id": pin}))?;
    for (index, uuid) in fixture.uuids.clone().iter().enumerate().skip(1) {
        let value = f64::from(u32::try_from(index)?);
        set_float(engine, uuid, "mod_a", "p_x", value)?;
    }
    assert_eq!(engine.loaded_photo_count(), PHOTO_CACHE_LIMIT);
    assert!(engine.is_photo_loaded(&pin));
    let evicted = fixture.uuids[1..]
        .iter()
        .find(|uuid| !engine.is_photo_loaded(uuid))
        .expect("one photo evicted")
        .clone();
    let position = fixture
        .uuids
        .iter()
        .position(|uuid| *uuid == evicted)
        .expect("index");
    assert_eq!(
        current_float(engine, &evicted, "mod_a", "p_x"),
        Some(f64::from(u32::try_from(position)?))
    );
    assert_eq!(labels(engine, &evicted), vec!["import", "develop.set"]);
    engine.execute("develop.copy", &json!({"id": evicted}))?;
    assert!(engine.is_photo_loaded(&evicted));
    assert_eq!(
        current_float(engine, &evicted, "mod_a", "p_x"),
        Some(f64::from(u32::try_from(position)?))
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn close_and_reopen_reads_back_identical_histories() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("reopen", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    set_float(engine, &a, "mod_b", "p_y", 2.0)?;
    set_float(engine, &b, "mod_a", "p_x", 3.0)?;
    engine.execute("history.undo", &json!({"id": a}))?;
    engine.execute("history.goto", &json!({"id": b, "index": 0}))?;
    let snapshot = |engine: &Engine, id: &str| {
        let current = engine.photo_settings(id).expect("current");
        (
            engine.photo_len(id),
            labels(engine, id),
            engine.photo_cursor(id),
            current.canonical_json().expect("canonical"),
        )
    };
    let (snap_a, snap_b) = (snapshot(engine, &a), snapshot(engine, &b));
    close_fixture(&mut fixture)?;
    let mut engine = Engine::new();
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine.execute(
        "session.open",
        &json!({"path": fixture.root.to_string_lossy()}),
    )?;
    assert_eq!(engine.loaded_photo_count(), 0);
    assert_eq!(snapshot(&engine, &a), snap_a);
    assert_eq!(snapshot(&engine, &b), snap_b);
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn paste_batch_is_one_transaction() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("paste-atomic", 3)?;
    let (a, mid, b) = (
        fixture.uuids[0].clone(),
        fixture.uuids[1].clone(),
        fixture.uuids[2].clone(),
    );
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.copy", &json!({"id": a}))?;
    {
        let raw = rusqlite::Connection::open(&fixture.db)?;
        let record = lightamer_catalog::find_photo_by_uuid(&raw, &mid)?.ok_or("photo vanished")?;
        raw.execute(
            &format!(
                "CREATE TRIGGER refuse_mid BEFORE INSERT ON history_steps \
                 WHEN NEW.photo_id = {} BEGIN SELECT RAISE(ABORT, 'refused'); END",
                record.id
            ),
            [],
        )?;
    }
    let before = engine.state_digest();
    let err = engine
        .execute("develop.paste", &json!({"ids": [&a, &mid, &b]}))
        .expect_err("the middle photo refuses the write");
    assert!(matches!(err, CommandError::Store { .. }), "{err}");
    assert_eq!(engine.photo_len(&a), Some(2));
    assert_eq!(engine.photo_len(&mid), Some(1));
    assert_eq!(engine.photo_len(&b), Some(1));
    assert_eq!(engine.state_digest(), before);
    assert_eq!(
        stored_labels(&fixture.db, &a)?.0,
        vec!["import", "develop.set"]
    );
    assert_eq!(stored_labels(&fixture.db, &b)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn trimming_past_200_steps_holds_on_a_real_session() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("trim-200", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    for step in 0..205 {
        set_float(engine, &a, "mod_a", "p_x", f64::from(step))?;
    }
    assert_eq!(engine.photo_len(&a), Some(200));
    assert_eq!(engine.photo_cursor(&a), Some(199));
    engine.execute("history.goto", &json!({"id": a, "index": 0}))?;
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(5.0));
    engine.execute("history.goto", &json!({"id": a, "index": 199}))?;
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(204.0));
    let (stored, cursor) = stored_labels(&fixture.db, &a)?;
    assert_eq!(stored.len(), 200);
    assert_eq!(cursor, 199);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn digest_moves_when_the_store_is_poked_behind_the_engine() -> Result<(), Box<dyn std::error::Error>>
{
    let mut fixture = open_real_fixture("digest-poke", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    let before = engine.state_digest();
    push_with_process(&fixture.db, &a, 1)?;
    assert_ne!(engine.state_digest(), before);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn digest_round_trips_a_drag_begin_and_cancel() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("digest-drag", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    let before = engine.state_digest();
    engine.execute("develop.beginInteraction", &json!({"id": a}))?;
    engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    assert_ne!(engine.state_digest(), before);
    engine.execute("develop.cancelInteraction", &json!({"id": a}))?;
    assert_eq!(engine.state_digest(), before);
    assert!(engine.is_photo_loaded(&a));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn digest_ignores_cache_loads_and_evictions() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("digest-churn", 70)?;
    let engine = &mut fixture.engine;
    let anchor = fixture.uuids[0].clone();
    engine.execute("develop.beginInteraction", &json!({"id": anchor}))?;
    engine.execute(
        "develop.updateInteraction",
        &json!({"id": anchor, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    let before = engine.state_digest();
    for uuid in fixture.uuids.clone().iter().skip(1) {
        engine.execute("develop.beginInteraction", &json!({"id": uuid}))?;
        engine.execute("develop.cancelInteraction", &json!({"id": uuid}))?;
    }
    assert_eq!(engine.state_digest(), before);
    assert!(engine.is_photo_loaded(&anchor));
    assert_eq!(current_float(engine, &anchor, "mod_a", "p_x"), Some(9.0));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn set_during_a_drag_commits_the_drag_first() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("settle-set", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    engine.execute("develop.beginInteraction", &json!({"id": a}))?;
    engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 5.0}}}),
    )?;
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    assert_eq!(
        labels(engine, &a),
        vec!["import", "develop.endInteraction", "develop.set"]
    );
    assert_eq!(engine.photo_cursor(&a), Some(2));
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(1.0));
    assert_eq!(
        stored_labels(&fixture.db, &a)?.0,
        vec!["import", "develop.endInteraction", "develop.set"]
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn undo_after_a_drag_commits_the_drag_then_moves() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("settle-undo", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    set_float(engine, &a, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.beginInteraction", &json!({"id": a}))?;
    engine.execute(
        "develop.updateInteraction",
        &json!({"id": a, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 5.0}}}),
    )?;
    engine.execute("history.undo", &json!({"id": a}))?;
    assert_eq!(
        labels(engine, &a),
        vec!["import", "develop.set", "develop.endInteraction"]
    );
    assert_eq!(engine.photo_cursor(&a), Some(1));
    assert_eq!(current_float(engine, &a, "mod_a", "p_x"), Some(1.0));
    assert_eq!(stored_labels(&fixture.db, &a)?, (labels(engine, &a), 1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn set_with_a_later_unknown_photo_commits_nothing() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("partial-unknown", 1)?;
    let engine = &mut fixture.engine;
    let a = fixture.uuids[0].clone();
    let before = engine.state_digest();
    let err = engine
        .execute(
            "develop.set",
            &json!({"ids": [&a, "no-such-photo"], "module": "mod_a", "patch": {}}),
        )
        .expect_err("the unknown photo fails the call");
    assert!(matches!(err, CommandError::NoPhoto { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(engine.photo_len(&a), Some(1));
    assert_eq!(stored_labels(&fixture.db, &a)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn set_with_cache_fully_pinned_is_refused_cleanly() -> Result<(), Box<dyn std::error::Error>> {
    use lightamer_engine::engine::PHOTO_CACHE_LIMIT;
    let mut fixture = open_real_fixture("pinned-full", PHOTO_CACHE_LIMIT + 1)?;
    let engine = &mut fixture.engine;
    for uuid in fixture.uuids.clone().iter().take(PHOTO_CACHE_LIMIT) {
        engine.execute("develop.beginInteraction", &json!({"id": uuid}))?;
    }
    assert_eq!(engine.loaded_photo_count(), PHOTO_CACHE_LIMIT);
    let outsider = fixture.uuids[PHOTO_CACHE_LIMIT].clone();
    let before = engine.state_digest();
    let err = engine
        .execute(
            "develop.set",
            &json!({"ids": [&outsider], "module": "mod_a", "patch": {}}),
        )
        .expect_err("a pinned-full cache refuses the load");
    assert!(matches!(err, CommandError::Disabled { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(engine.photo_len(&outsider), Some(1));
    assert_eq!(stored_labels(&fixture.db, &outsider)?.0, vec!["import"]);
    for uuid in fixture.uuids.iter().take(PHOTO_CACHE_LIMIT) {
        assert!(engine.is_photo_loaded(uuid));
    }
    close_fixture(&mut fixture)?;
    Ok(())
}
