// SPDX-License-Identifier: GPL-3.0-or-later
//! The batch fast path: multi-target commands serve unloaded photos from one
//! batch fetch instead of rebuilding every stack, and land exactly what the
//! loaded path lands. Single-target commands still load, so interactive edits
//! keep populating the cache.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

#[allow(dead_code)]
mod common;
#[allow(dead_code)]
mod real_common;

use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;

use lightamer_engine::{CommandError, Engine, Event};
use serde_json::json;

use common::ScratchDir;
use real_common::{close_fixture, open_real_fixture, set_float};

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

/// `(table, rows)` dumps, in fixed table order.
type TableDump = Vec<(String, Vec<String>)>;

/// Dumps every table's rows with `created_at` masked out (two runs stamp
/// different seconds): `history_steps` without its timestamp column, every
/// other table whole, all in rowid order.
fn dump_all_tables(db: &Path) -> Result<TableDump, Box<dyn std::error::Error>> {
    let conn = rusqlite::Connection::open(db)?;
    let mut dump = Vec::new();
    for table in [
        "_meta",
        "photos",
        "snapshots",
        "history_steps",
        "keywords",
        "photo_keywords",
        "albums",
        "album_photos",
        "favorites",
    ] {
        let sql = if table == "history_steps" {
            format!("SELECT photo_id, idx, label, snapshot_hash FROM {table} ORDER BY rowid")
        } else {
            format!("SELECT * FROM {table} ORDER BY rowid")
        };
        let mut select = conn.prepare(&sql)?;
        let columns = select.column_count();
        let rows = select.query_map([], |row| {
            let mut cells = Vec::new();
            for index in 0..columns {
                let value: rusqlite::types::Value = row.get(index)?;
                cells.push(format!("{value:?}"));
            }
            Ok(cells.join("|"))
        })?;
        dump.push((table.to_owned(), rows.collect::<Result<_, _>>()?));
    }
    Ok(dump)
}

/// Copies a closed session directory wholesale (database, placeholders,
/// lock files): the copy opens as an identical session.
fn copy_dir_all(from: &Path, to: &Path) -> Result<(), Box<dyn std::error::Error>> {
    std::fs::create_dir_all(to)?;
    for entry in std::fs::read_dir(from)? {
        let entry = entry?;
        let dest = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir_all(&entry.path(), &dest)?;
        } else {
            std::fs::copy(entry.path(), &dest)?;
        }
    }
    Ok(())
}

/// Collects every `PhotoChanged` event's facts, in emission order.
fn watch_changes(engine: &mut Engine) -> Rc<RefCell<Vec<(String, usize, usize)>>> {
    let seen: Rc<RefCell<Vec<(String, usize, usize)>>> = Rc::new(RefCell::new(Vec::new()));
    let into = Rc::clone(&seen);
    engine.subscribe(Rc::new(move |event, _| {
        if let Event::PhotoChanged {
            photo,
            steps,
            cursor,
        } = event
        {
            into.borrow_mut().push((photo.clone(), *steps, *cursor));
        }
    }));
    seen
}

/// Runs the batch sequence both sides replay: paste, multi-set, sync, merge,
/// multi-reset. The clipboard holds the source's adjustments on entry.
fn run_batch_sequence(
    engine: &mut Engine,
    source: &str,
    targets: &[String],
) -> Result<(), Box<dyn std::error::Error>> {
    let [t1, t2, t3, t4, t5] = targets else {
        return Err("need five targets".into());
    };
    engine.execute("develop.paste", &json!({"ids": targets}))?;
    engine.execute(
        "develop.set",
        &json!({"ids": [t1, t2], "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 9.0}}}),
    )?;
    engine.execute("develop.sync", &json!({"id": source, "ids": [t3, t4]}))?;
    engine.execute("develop.merge", &json!({"ids": [t4, t5]}))?;
    engine.execute("develop.reset", &json!({"ids": [t1, t2]}))?;
    Ok(())
}

#[test]
fn fast_batch_matches_loaded_batch_table_for_table() -> Result<(), Box<dyn std::error::Error>> {
    let mut build = open_real_fixture("batch-equiv-build", 6)?;
    let uuids = build.uuids.clone();
    let (source, t1, t2, t3, t4, t5) = (
        uuids[0].clone(),
        uuids[1].clone(),
        uuids[2].clone(),
        uuids[3].clone(),
        uuids[4].clone(),
        uuids[5].clone(),
    );
    let engine = &mut build.engine;
    set_float(engine, &source, "mod_a", "p_x", 2.5)?;
    // t1 stays a single step; t2 carries a redo tail; t3 sits at the 200-step
    // cap; t4 holds three steps; t5 stays a single step.
    set_float(engine, &t2, "mod_a", "p_x", 1.0)?;
    set_float(engine, &t2, "mod_a", "p_x", 2.0)?;
    engine.execute("history.undo", &json!({"id": t2}))?;
    for index in 1..=199_u32 {
        set_float(engine, &t3, "mod_c", "p", f64::from(index))?;
    }
    set_float(engine, &t4, "mod_b", "q", 1.0)?;
    set_float(engine, &t4, "mod_b", "q", 2.0)?;
    close_fixture(&mut build)?;

    let scratch = ScratchDir::new("batch-equiv-copy")?;
    let copy_root = scratch.path().join("Shoot");
    copy_dir_all(&build.root, &copy_root)?;

    let targets = vec![t1.clone(), t2.clone(), t3.clone(), t4.clone(), t5.clone()];

    // Side A: only t5 (and the source) loads; every other target takes the
    // fast path, including a mixed merge of one loaded and one unloaded.
    let mut engine_a = Engine::new();
    engine_a.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine_a.execute(
        "session.open",
        &json!({"path": build.root.to_string_lossy()}),
    )?;
    let seen_a = watch_changes(&mut engine_a);
    engine_a.execute("develop.copy", &json!({"id": t5}))?;
    engine_a.execute("develop.copy", &json!({"id": source}))?;
    run_batch_sequence(&mut engine_a, &source, &targets)?;
    assert!(!engine_a.is_photo_loaded(&t1));
    assert!(!engine_a.is_photo_loaded(&t2));
    assert!(!engine_a.is_photo_loaded(&t3));
    assert!(!engine_a.is_photo_loaded(&t4));
    assert!(engine_a.is_photo_loaded(&t5));
    engine_a.execute("session.close", &json!({}))?;

    // Side B: every target loads first, so the whole sequence walks the
    // in-memory stacks.
    let mut engine_b = Engine::new();
    engine_b.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine_b.execute(
        "session.open",
        &json!({"path": copy_root.to_string_lossy()}),
    )?;
    let seen_b = watch_changes(&mut engine_b);
    for id in &targets {
        engine_b.execute("develop.copy", &json!({"id": id}))?;
    }
    engine_b.execute("develop.copy", &json!({"id": source}))?;
    run_batch_sequence(&mut engine_b, &source, &targets)?;
    for id in &targets {
        assert!(engine_b.is_photo_loaded(id));
    }
    engine_b.execute("session.close", &json!({}))?;

    assert_eq!(*seen_a.borrow(), *seen_b.borrow());
    assert_eq!(seen_a.borrow().len(), 5 + 2 + 2 + 2 + 2);
    let db_b = copy_root.join("Shoot.lmsessiondb");
    assert_eq!(dump_all_tables(&build.db)?, dump_all_tables(&db_b)?);
    Ok(())
}

#[test]
fn fast_batch_is_one_transaction_and_atomic() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("batch-atomic", 5)?;
    let uuids = fixture.uuids.clone();
    let (source, t1, mid, t2, t3) = (
        uuids[0].clone(),
        uuids[1].clone(),
        uuids[2].clone(),
        uuids[3].clone(),
        uuids[4].clone(),
    );
    let engine = &mut fixture.engine;
    set_float(engine, &source, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.copy", &json!({"id": source}))?;
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
    // Nothing but the source is loaded: the paste takes the fast path, then
    // the middle target refuses its insert.
    assert_eq!(engine.loaded_photo_count(), 1);
    let before = engine.state_digest();
    let err = engine
        .execute("develop.paste", &json!({"ids": [t1, mid, t2, t3]}))
        .expect_err("the middle photo refuses the write");
    assert!(matches!(err, CommandError::Store { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    assert_eq!(engine.loaded_photo_count(), 1);
    for id in [&t1, &mid, &t2, &t3] {
        assert_eq!(engine.photo_len(id), Some(1));
        assert_eq!(stored_labels(&fixture.db, id)?.0, vec!["import"]);
    }
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn unknown_in_fast_batch_fails_clean() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("batch-unknown", 3)?;
    let uuids = fixture.uuids.clone();
    let (source, t1, t2) = (uuids[0].clone(), uuids[1].clone(), uuids[2].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &source, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.copy", &json!({"id": source}))?;
    let before = engine.state_digest();
    let err = engine
        .execute("develop.paste", &json!({"ids": [t1, "no-such-photo", t2]}))
        .expect_err("the unknown photo fails the batch");
    assert!(matches!(err, CommandError::NoPhoto { .. }), "{err}");
    assert_eq!(engine.state_digest(), before);
    for id in [&t1, &t2] {
        assert_eq!(engine.photo_len(id), Some(1));
        assert_eq!(stored_labels(&fixture.db, id)?.0, vec!["import"]);
    }
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn damaged_cursor_in_fast_batch_is_refused() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("batch-damaged", 3)?;
    let uuids = fixture.uuids.clone();
    let (source, t1, t2) = (uuids[0].clone(), uuids[1].clone(), uuids[2].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &source, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.copy", &json!({"id": source}))?;
    {
        let raw = rusqlite::Connection::open(&fixture.db)?;
        let record = lightamer_catalog::find_photo_by_uuid(&raw, &t1)?.ok_or("photo vanished")?;
        raw.execute("UPDATE photos SET cursor = 99 WHERE id = ?1", [record.id])?;
    }
    let err = engine
        .execute("develop.paste", &json!({"ids": [t1, t2]}))
        .expect_err("the damaged cursor fails the batch");
    assert!(matches!(err, CommandError::Store { .. }), "{err}");
    assert_eq!(stored_labels(&fixture.db, &t1)?.0, vec!["import"]);
    assert_eq!(stored_labels(&fixture.db, &t2)?.0, vec!["import"]);
    assert_eq!(engine.photo_len(&t2), Some(1));
    close_fixture(&mut fixture)?;
    Ok(())
}

#[test]
fn noncontiguous_steps_in_fast_batch_are_refused() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("batch-gap", 3)?;
    let uuids = fixture.uuids.clone();
    let (source, t1, t2) = (uuids[0].clone(), uuids[1].clone(), uuids[2].clone());
    let engine = &mut fixture.engine;
    set_float(engine, &source, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.copy", &json!({"id": source}))?;
    set_float(engine, &t1, "mod_a", "p_x", 1.0)?;
    set_float(engine, &t1, "mod_a", "p_x", 2.0)?;
    set_float(engine, &t1, "mod_a", "p_x", 3.0)?;
    close_fixture(&mut fixture)?;
    {
        let raw = rusqlite::Connection::open(&fixture.db)?;
        let record = lightamer_catalog::find_photo_by_uuid(&raw, &t1)?.ok_or("photo vanished")?;
        raw.execute(
            "DELETE FROM history_steps WHERE photo_id = ?1 AND idx = 1",
            [record.id],
        )?;
    }
    let mut engine = Engine::new();
    engine.execute(
        "session.open",
        &json!({"path": fixture.root.to_string_lossy()}),
    )?;
    engine.execute("develop.copy", &json!({"id": source}))?;
    let err = engine
        .execute("develop.paste", &json!({"ids": [t1, t2]}))
        .expect_err("the gapped steps fail the batch");
    assert!(matches!(err, CommandError::Store { .. }), "{err}");
    assert_eq!(engine.photo_len(&t2), Some(1));
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

#[test]
fn multi_target_leaves_unloaded_unloaded_and_times_thirds() -> Result<(), Box<dyn std::error::Error>>
{
    let mut fixture = open_real_fixture("batch-unloaded", 4)?;
    let uuids = fixture.uuids.clone();
    let (source, t1, t2, t3) = (
        uuids[0].clone(),
        uuids[1].clone(),
        uuids[2].clone(),
        uuids[3].clone(),
    );
    let engine = &mut fixture.engine;
    set_float(engine, &source, "mod_a", "p_x", 1.0)?;
    engine.execute("develop.copy", &json!({"id": source}))?;
    assert_eq!(engine.loaded_photo_count(), 1);
    engine.execute("develop.paste", &json!({"ids": [t1, t2, t3]}))?;
    // The batch streamed past the cache: no target loaded, reads serve from
    // the store, and the thirds describe the round.
    assert_eq!(engine.loaded_photo_count(), 1);
    for id in [&t1, &t2, &t3] {
        assert!(!engine.is_photo_loaded(id));
        assert_eq!(engine.photo_len(id), Some(2));
    }
    let thirds = engine.last_command_phases();
    assert!(
        thirds.read + thirds.compute + thirds.write > std::time::Duration::ZERO,
        "the thirds describe the round: {thirds:?}"
    );
    close_fixture(&mut fixture)?;
    Ok(())
}
