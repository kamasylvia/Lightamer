// SPDX-License-Identifier: GPL-3.0-or-later
//! `develop.sync` and `develop.merge` on real sessions: the three selection
//! grains persist one labelled step per target in a single transaction, each
//! target keeping its own process version, and every refusal leaves memory
//! and the store unchanged.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

#[allow(dead_code)]
mod common;
#[allow(dead_code)]
mod real_common;
use std::path::Path;

use lightamer_engine::CommandError;
use serde_json::json;

use real_common::{close_fixture, current_float, open_real_fixture, set_float};

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

/// Pushes one default-settings step with an explicit process number behind
/// the engine's back (the target stays unloaded, so the sync loads it fresh).
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
fn sync_without_selection_merges_all_source_modules_and_persists()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-all", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_b", "q", 2.0)?;
    set_float(engine, &b, "mod_a", "p", 9.0)?;
    set_float(engine, &b, "mod_c", "r", 3.0)?;
    let source_settings = engine.photo_settings(&a).expect("snapshot").clone();
    engine.execute("develop.sync", &json!({"id": a, "ids": [b]}))?;
    assert_eq!(engine.photo_len(&b), Some(4));
    assert_eq!(
        engine.photo_labels(&b).expect("labels").last(),
        Some(&"develop.sync".to_owned())
    );
    assert_eq!(current_float(engine, &b, "mod_a", "p"), Some(1.0));
    assert_eq!(current_float(engine, &b, "mod_b", "q"), Some(2.0));
    assert_eq!(current_float(engine, &b, "mod_c", "r"), Some(3.0));
    assert_eq!(engine.photo_len(&a), Some(3));
    assert_eq!(
        engine.photo_settings(&a).expect("snapshot"),
        source_settings
    );
    assert_eq!(
        stored_labels(&fixture.db, &b)?.0,
        vec!["import", "develop.set", "develop.set", "develop.sync"]
    );
    assert_eq!(
        stored_labels(&fixture.db, &a)?.0,
        vec!["import", "develop.set", "develop.set"]
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_module_grain_replaces_adds_and_leaves_the_rest() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-modules", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_b", "q", 2.0)?;
    set_float(engine, &b, "mod_a", "p", 9.0)?;
    set_float(engine, &b, "mod_c", "r", 3.0)?;
    engine.execute(
        "develop.sync",
        &json!({"id": a, "ids": [b], "selection": ["mod_a", "mod_b"]}),
    )?;
    assert_eq!(current_float(engine, &b, "mod_a", "p"), Some(1.0));
    assert_eq!(current_float(engine, &b, "mod_b", "q"), Some(2.0));
    assert_eq!(current_float(engine, &b, "mod_c", "r"), Some(3.0));
    assert_eq!(
        stored_labels(&fixture.db, &b)?.0.last(),
        Some(&"develop.sync".to_owned())
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_param_grain_overwrites_only_named_params() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-params", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_a", "q", 1.0)?;
    set_float(engine, &b, "mod_a", "p", 9.0)?;
    set_float(engine, &b, "mod_a", "q", 9.0)?;
    engine.execute(
        "develop.sync",
        &json!({"id": a, "ids": [b], "selection": ["mod_a.p"]}),
    )?;
    assert_eq!(current_float(engine, &b, "mod_a", "p"), Some(1.0));
    assert_eq!(current_float(engine, &b, "mod_a", "q"), Some(9.0));
    assert_eq!(
        stored_labels(&fixture.db, &b)?.0.last(),
        Some(&"develop.sync".to_owned())
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_param_grain_creates_a_missing_instance_with_only_named_params()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-param-new", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_a", "q", 1.0)?;
    engine.execute(
        "develop.sync",
        &json!({"id": a, "ids": [b], "selection": ["mod_a.p"]}),
    )?;
    let settings = engine.photo_settings(&b).expect("snapshot");
    let instance = settings.instances.get("mod_a", 0).expect("instance");
    assert_eq!(instance.params.len(), 1);
    assert_eq!(
        instance.params.get("p"),
        Some(&lightamer_history::SettingValue::Float(1.0))
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_keeps_the_target_process_and_labels_each_step() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-process", 3)?;
    let (a, b, c) = (
        fixture.uuids[0].clone(),
        fixture.uuids[1].clone(),
        fixture.uuids[2].clone(),
    );
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    push_with_process(&fixture.db, &b, 0)?;
    push_with_process(&fixture.db, &c, 0)?;
    let out = engine.execute("develop.sync", &json!({"id": a, "ids": [b, c]}))?;
    assert_eq!(out, json!({"synced": 2}));
    for id in [&b, &c] {
        let settings = engine.photo_settings(id).expect("snapshot");
        assert_eq!(settings.process, lightamer_history::ProcessVersion(0));
        assert!(settings.instances.get("mod_a", 0).is_some());
        assert_eq!(
            engine.photo_labels(id).expect("labels"),
            vec![
                "import".to_owned(),
                "develop.set".to_owned(),
                "develop.sync".to_owned()
            ]
        );
        assert_eq!(
            stored_labels(&fixture.db, id)?.0,
            vec!["import", "develop.set", "develop.sync"]
        );
    }
    assert_eq!(engine.photo_len(&a), Some(2));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_with_an_unknown_source_changes_neither_memory_nor_store()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-no-source", 2)?;
    let b = fixture.uuids[1].clone();
    let engine = &mut fixture.engine;
    let before = engine.state_digest();
    let err = engine
        .execute("develop.sync", &json!({"id": "ghost", "ids": [b]}))
        .expect_err("unknown source fails");
    assert!(matches!(err, CommandError::NoPhoto { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(stored_labels(&fixture.db, &b)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_rejects_an_unknown_module_in_the_selection() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-bad-module", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    engine.set_param_lookup(|_| None);
    let before = engine.state_digest();
    let err = engine
        .execute(
            "develop.sync",
            &json!({"id": a, "ids": [b], "selection": ["mod_a"]}),
        )
        .expect_err("unknown module fails");
    assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(stored_labels(&fixture.db, &b)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_rejects_an_unknown_param_in_the_selection() -> Result<(), Box<dyn std::error::Error>> {
    static FIELDS: &[lightamer_iop_traits::ParamField] = &[lightamer_iop_traits::ParamField {
        name: "p_ok",
        ty: lightamer_iop_traits::ParamType::Float,
    }];
    let mut fixture = open_real_fixture("sync-bad-param", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    engine.set_param_lookup(|_| {
        Some(lightamer_iop_traits::ParamsDesc {
            fields: Some(FIELDS),
        })
    });
    let before = engine.state_digest();
    let err = engine
        .execute(
            "develop.sync",
            &json!({"id": a, "ids": [b], "selection": ["mod_a.p_nope"]}),
        )
        .expect_err("unknown param fails");
    assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(stored_labels(&fixture.db, &b)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn sync_batch_is_one_transaction() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("sync-atomic", 4)?;
    let (a, t1, mid, t2) = (
        fixture.uuids[0].clone(),
        fixture.uuids[1].clone(),
        fixture.uuids[2].clone(),
        fixture.uuids[3].clone(),
    );
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
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
        .execute("develop.sync", &json!({"id": a, "ids": [t1, mid, t2]}))
        .expect_err("the middle photo refuses the write");
    assert!(matches!(err, CommandError::Store { .. }), "{err}");
    assert_eq!(engine.photo_len(&t1), Some(1));
    assert_eq!(engine.photo_len(&mid), Some(1));
    assert_eq!(engine.photo_len(&t2), Some(1));
    assert_eq!(engine.state_digest(), before);
    for id in [&t1, &mid, &t2] {
        assert_eq!(stored_labels(&fixture.db, id)?.0, vec!["import"]);
    }
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_without_selection_merges_all_clipboard_modules_and_persists()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("merge-all", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_b", "q", 2.0)?;
    engine.execute("develop.copy", &json!({"id": a}))?;
    set_float(engine, &b, "mod_c", "r", 3.0)?;
    let out = engine.execute("develop.merge", &json!({"ids": [b]}))?;
    assert_eq!(out, json!({"merged": 1}));
    assert_eq!(
        engine.photo_labels(&b).expect("labels").last(),
        Some(&"develop.merge".to_owned())
    );
    assert_eq!(current_float(engine, &b, "mod_a", "p"), Some(1.0));
    assert_eq!(current_float(engine, &b, "mod_b", "q"), Some(2.0));
    assert_eq!(current_float(engine, &b, "mod_c", "r"), Some(3.0));
    assert_eq!(
        stored_labels(&fixture.db, &b)?.0,
        vec!["import", "develop.set", "develop.merge"]
    );
    assert!(engine.has_clipboard());
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_module_grain_replaces_adds_and_leaves_the_rest() -> Result<(), Box<dyn std::error::Error>>
{
    let mut fixture = open_real_fixture("merge-modules", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_b", "q", 2.0)?;
    engine.execute("develop.copy", &json!({"id": a}))?;
    set_float(engine, &b, "mod_a", "p", 9.0)?;
    set_float(engine, &b, "mod_c", "r", 3.0)?;
    engine.execute(
        "develop.merge",
        &json!({"ids": [b], "selection": ["mod_a"]}),
    )?;
    assert_eq!(current_float(engine, &b, "mod_a", "p"), Some(1.0));
    assert!(
        engine
            .photo_settings(&b)
            .expect("snapshot")
            .instances
            .get("mod_b", 0)
            .is_none()
    );
    assert_eq!(current_float(engine, &b, "mod_c", "r"), Some(3.0));
    assert_eq!(
        stored_labels(&fixture.db, &b)?.0.last(),
        Some(&"develop.merge".to_owned())
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_param_grain_overwrites_only_named_params() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("merge-params", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_a", "q", 1.0)?;
    engine.execute("develop.copy", &json!({"id": a}))?;
    set_float(engine, &b, "mod_a", "p", 9.0)?;
    set_float(engine, &b, "mod_a", "q", 9.0)?;
    engine.execute(
        "develop.merge",
        &json!({"ids": [b], "selection": ["mod_a.p"]}),
    )?;
    assert_eq!(current_float(engine, &b, "mod_a", "p"), Some(1.0));
    assert_eq!(current_float(engine, &b, "mod_a", "q"), Some(9.0));
    assert_eq!(
        stored_labels(&fixture.db, &b)?.0.last(),
        Some(&"develop.merge".to_owned())
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_param_grain_creates_a_missing_instance_with_only_named_params()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("merge-param-new", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    set_float(engine, &a, "mod_a", "q", 1.0)?;
    engine.execute("develop.copy", &json!({"id": a}))?;
    engine.execute(
        "develop.merge",
        &json!({"ids": [b], "selection": ["mod_a.p"]}),
    )?;
    let settings = engine.photo_settings(&b).expect("snapshot");
    let instance = settings.instances.get("mod_a", 0).expect("instance");
    assert_eq!(instance.params.len(), 1);
    assert_eq!(
        instance.params.get("p"),
        Some(&lightamer_history::SettingValue::Float(1.0))
    );
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_keeps_the_target_process_and_labels_each_step() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("merge-process", 3)?;
    let (a, b, c) = (
        fixture.uuids[0].clone(),
        fixture.uuids[1].clone(),
        fixture.uuids[2].clone(),
    );
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
    engine.execute("develop.copy", &json!({"id": a}))?;
    push_with_process(&fixture.db, &b, 0)?;
    push_with_process(&fixture.db, &c, 0)?;
    let out = engine.execute("develop.merge", &json!({"ids": [b, c]}))?;
    assert_eq!(out, json!({"merged": 2}));
    for id in [&b, &c] {
        let settings = engine.photo_settings(id).expect("snapshot");
        assert_eq!(settings.process, lightamer_history::ProcessVersion(0));
        assert_eq!(
            engine.photo_labels(id).expect("labels"),
            vec![
                "import".to_owned(),
                "develop.set".to_owned(),
                "develop.merge".to_owned()
            ]
        );
        assert_eq!(
            stored_labels(&fixture.db, id)?.0,
            vec!["import", "develop.set", "develop.merge"]
        );
    }
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_with_an_empty_clipboard_changes_neither_memory_nor_store()
-> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("merge-no-clip", 1)?;
    let a = fixture.uuids[0].clone();
    let engine = &mut fixture.engine;
    let before = engine.state_digest();
    let err = engine
        .execute("develop.merge", &json!({"ids": [a]}))
        .expect_err("empty clipboard fails");
    assert!(matches!(err, CommandError::EmptyClipboard { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(stored_labels(&fixture.db, &a)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_rejects_an_unknown_module_in_the_selection() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("merge-bad-module", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    engine.execute("develop.copy", &json!({"id": a}))?;
    engine.set_param_lookup(|_| None);
    let before = engine.state_digest();
    let err = engine
        .execute(
            "develop.merge",
            &json!({"ids": [b], "selection": ["mod_a"]}),
        )
        .expect_err("unknown module fails");
    assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(stored_labels(&fixture.db, &b)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_rejects_an_unknown_param_in_the_selection() -> Result<(), Box<dyn std::error::Error>> {
    static FIELDS: &[lightamer_iop_traits::ParamField] = &[lightamer_iop_traits::ParamField {
        name: "p_ok",
        ty: lightamer_iop_traits::ParamType::Float,
    }];
    let mut fixture = open_real_fixture("merge-bad-param", 2)?;
    let (a, b) = (fixture.uuids[0].clone(), fixture.uuids[1].clone());
    let engine = &mut fixture.engine;
    engine.execute("develop.copy", &json!({"id": a}))?;
    engine.set_param_lookup(|_| {
        Some(lightamer_iop_traits::ParamsDesc {
            fields: Some(FIELDS),
        })
    });
    let before = engine.state_digest();
    let err = engine
        .execute(
            "develop.merge",
            &json!({"ids": [b], "selection": ["mod_a.p_nope"]}),
        )
        .expect_err("unknown param fails");
    assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(stored_labels(&fixture.db, &b)?.0, vec!["import"]);
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn merge_batch_is_one_transaction() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("merge-atomic", 4)?;
    let (a, t1, mid, t2) = (
        fixture.uuids[0].clone(),
        fixture.uuids[1].clone(),
        fixture.uuids[2].clone(),
        fixture.uuids[3].clone(),
    );
    let engine = &mut fixture.engine;
    set_float(engine, &a, "mod_a", "p", 1.0)?;
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
        .execute("develop.merge", &json!({"ids": [t1, mid, t2]}))
        .expect_err("the middle photo refuses the write");
    assert!(matches!(err, CommandError::Store { .. }), "{err}");
    assert_eq!(engine.photo_len(&t1), Some(1));
    assert_eq!(engine.photo_len(&mid), Some(1));
    assert_eq!(engine.photo_len(&t2), Some(1));
    assert_eq!(engine.state_digest(), before);
    for id in [&t1, &mid, &t2] {
        assert_eq!(stored_labels(&fixture.db, id)?.0, vec!["import"]);
    }
    close_fixture(&mut fixture)?;
    Ok(())
}
