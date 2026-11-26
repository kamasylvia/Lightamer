// SPDX-License-Identifier: GPL-3.0-or-later
//! History in the database: one step is one transaction, the cursor moves
//! alone, trimming renumbers, the photo row mirrors the cursor step,
//! collisions store apart, orphans collect on close.

mod common;

use std::sync::Arc;

use lightamer_catalog::{
    CatalogError, HistoryWriter, PhotoRecord, SEED_LABEL, Session, close_session, create_session,
    move_cursor, open_session, orphan_snapshot_hashes, push_step, read_history, register_photo,
    verify_session,
};
use lightamer_history::{HistoryStack, PhotoSettings};

use common::{ScratchDir, settings_json, settings_json_with_process};

/// A scratch session holding one registered photo (`Capture/a.arw`).
fn setup_one(tag: &str) -> Result<(ScratchDir, Session, PhotoRecord), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new(tag)?;
    let mut session = create_session(scratch.path(), "Shoot", "history-test")?;
    let root = session.root().to_path_buf();
    let record = register_photo(
        session.connection_mut(),
        &root,
        &root.join("Capture").join("a.arw"),
        "a.arw",
        None,
    )?;
    Ok((scratch, session, record))
}

/// `(photos, history_steps, snapshots)` row counts.
fn db_counts(conn: &rusqlite::Connection) -> Result<(i64, i64, i64), Box<dyn std::error::Error>> {
    let photos: i64 = conn.query_row("SELECT COUNT(*) FROM photos", [], |row| row.get(0))?;
    let steps: i64 = conn.query_row("SELECT COUNT(*) FROM history_steps", [], |row| row.get(0))?;
    let snapshots: i64 = conn.query_row("SELECT COUNT(*) FROM snapshots", [], |row| row.get(0))?;
    Ok((photos, steps, snapshots))
}

/// A photo row's `(cursor, current_hash, process)`.
fn photo_row(
    conn: &rusqlite::Connection,
    id: i64,
) -> Result<(i64, String, i64), Box<dyn std::error::Error>> {
    Ok(conn.query_row(
        "SELECT cursor, current_hash, process FROM photos WHERE id = ?1",
        [id],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?)
}

/// A photo's `(idx, label, snapshot_hash)` rows, oldest first.
type StepRows = Vec<(i64, String, String)>;

/// Reads a photo's step rows, oldest first.
fn step_rows(
    conn: &rusqlite::Connection,
    photo_id: i64,
) -> Result<StepRows, Box<dyn std::error::Error>> {
    let mut select = conn.prepare(
        "SELECT idx, label, snapshot_hash FROM history_steps WHERE photo_id = ?1 ORDER BY idx",
    )?;
    Ok(select
        .query_map([photo_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })?
        .collect::<Result<_, _>>()?)
}

/// Fails unless the photo row mirrors its cursor step (hash and process).
fn assert_mirror(conn: &rusqlite::Connection, id: i64) -> Result<(), Box<dyn std::error::Error>> {
    let (cursor, hash, process) = photo_row(conn, id)?;
    let read = read_history(conn, id)?;
    assert_eq!(read.cursor, cursor);
    let Some(step) = read.steps.iter().find(|step| step.idx == cursor) else {
        return Err("cursor step missing from history".into());
    };
    assert_eq!(hash, step.snapshot_hash);
    let inside = PhotoSettings::from_json(&step.settings_json)?;
    assert_eq!(process, i64::from(inside.process.0));
    Ok(())
}

#[test]
fn push_changes_snapshot_step_and_photo_row_in_one_transaction()
-> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("push-one")?;
    let json = settings_json("exposure", "ev", 1)?;
    let key = PhotoSettings::from_json(&json)?.hash64_decimal();
    let outcome = push_step(session.connection_mut(), record.id, "develop.set", &json)?;
    assert_eq!(outcome.photo_id, record.id);
    assert_eq!(outcome.idx, 1);
    assert_eq!(outcome.snapshot_hash, key);
    assert!(!outcome.collided);
    assert_eq!(outcome.cursor, 1);
    assert_eq!(outcome.steps, 2);

    let conn = session.connection();
    assert_eq!(db_counts(conn)?, (1, 2, 2));
    let default_key = PhotoSettings::default().hash64_decimal();
    assert_eq!(
        step_rows(conn, record.id)?,
        vec![
            (0, SEED_LABEL.to_owned(), default_key),
            (1, "develop.set".to_owned(), key.clone()),
        ]
    );
    assert_eq!(photo_row(conn, record.id)?.1, key);
    let stored: String = conn.query_row(
        "SELECT json FROM snapshots WHERE hash = ?1",
        [&key],
        |row| row.get(0),
    )?;
    assert_eq!(stored, json);
    assert_mirror(conn, record.id)?;
    close_session(session)?;
    Ok(())
}

#[test]
fn failed_pushes_roll_back_with_the_writer() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("push-fail")?;
    let baseline = settings_json("exposure", "ev", 1)?;
    push_step(
        session.connection_mut(),
        record.id,
        "develop.set",
        &baseline,
    )?;
    let before = db_counts(session.connection())?;
    let photo_before = photo_row(session.connection(), record.id)?;

    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    let good = settings_json("exposure", "ev", 2)?;
    writer.push(record.id, "develop.set", &good)?;
    let Err(CatalogError::BadSettings { .. }) = writer.push(record.id, "develop.set", "{nope")
    else {
        return Err("bad settings text was accepted".into());
    };
    let Err(CatalogError::UnknownPhoto(9999)) = writer.push(9999, "develop.set", &good) else {
        return Err("unknown photo push was accepted".into());
    };
    drop(writer);
    assert_eq!(db_counts(session.connection())?, before);
    assert_eq!(photo_row(session.connection(), record.id)?, photo_before);
    close_session(session)?;
    Ok(())
}

#[test]
fn writer_stays_usable_after_a_failed_push() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("push-reuse")?;
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    let Err(CatalogError::BadSettings { .. }) = writer.push(record.id, "develop.set", "null")
    else {
        return Err("bad settings text was accepted".into());
    };
    let good = settings_json("exposure", "ev", 3)?;
    writer.push(record.id, "develop.set", &good)?;
    writer.commit()?;
    let read = read_history(session.connection(), record.id)?;
    assert_eq!(read.steps.len(), 2);
    assert_eq!(read.cursor, 1);
    close_session(session)?;
    Ok(())
}

#[test]
fn push_step_helper_commits_a_single_step() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("push-helper")?;
    let json = settings_json("exposure", "ev", 9)?;
    let outcome = push_step(session.connection_mut(), record.id, "develop.reset", &json)?;
    assert_eq!((outcome.cursor, outcome.steps), (1, 2));
    close_session(session)?;
    Ok(())
}

#[test]
fn move_cursor_updates_only_the_photo_row() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("move-only")?;
    let mut jsons = vec![PhotoSettings::default().canonical_json()?];
    for value in 1..=3_i64 {
        let json = settings_json("exposure", "ev", value)?;
        push_step(session.connection_mut(), record.id, "develop.set", &json)?;
        jsons.push(json);
    }
    let dump = step_rows(session.connection(), record.id)?;
    assert_eq!(dump.len(), 4);
    for target in [0_i64, 2, 1, 3] {
        let moved = move_cursor(session.connection(), record.id, target)?;
        assert_eq!(moved.cursor, target);
        assert_eq!(moved.steps, 4);
        let Some(expected) = jsons.get(usize::try_from(target)?) else {
            return Err("missing expected settings".into());
        };
        assert_eq!(&moved.settings_json, expected);
        assert_eq!(step_rows(session.connection(), record.id)?, dump);
        assert_mirror(session.connection(), record.id)?;
    }
    close_session(session)?;
    Ok(())
}

#[test]
fn past_200_steps_oldest_trim_and_renumber_from_zero() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("trim")?;
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    for number in 1..=205_i64 {
        let json = settings_json("exposure", "ev", number)?;
        writer.push(record.id, &format!("step-{number}"), &json)?;
    }
    assert_eq!(writer.stats().pushes, 205);
    writer.commit()?;
    let read = read_history(session.connection(), record.id)?;
    assert_eq!(read.steps.len(), 200);
    assert_eq!(read.cursor, 199);
    for (position, step) in read.steps.iter().enumerate() {
        assert_eq!(step.idx, i64::try_from(position)?);
    }
    let Some(first) = read.steps.first() else {
        return Err("trimmed history is empty".into());
    };
    let Some(last) = read.steps.last() else {
        return Err("trimmed history is empty".into());
    };
    // 1 seed + 205 pushes = 206 steps; the 6 oldest (seed..step-5) dropped.
    assert_eq!(first.label, "step-6");
    assert_eq!(last.label, "step-205");
    assert_eq!(db_counts(session.connection())?, (1, 200, 206));
    assert_mirror(session.connection(), record.id)?;
    close_session(session)?;
    Ok(())
}

#[test]
fn trimmed_snapshots_become_orphans_and_close_collects_them()
-> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("trim-orphan")?;
    let mut session = create_session(scratch.path(), "Shoot", "history-test")?;
    let root = session.root().to_path_buf();
    let record = register_photo(
        session.connection_mut(),
        &root,
        &root.join("Capture").join("a.arw"),
        "a.arw",
        None,
    )?;
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    for number in 1..=205_i64 {
        let json = settings_json("exposure", "ev", number)?;
        writer.push(record.id, &format!("step-{number}"), &json)?;
    }
    writer.commit()?;
    // 206 snapshots, 200 referenced: the default plus the 5 dropped steps.
    let orphans = orphan_snapshot_hashes(session.connection())?;
    assert_eq!(orphans.len(), 6);
    assert!(orphans.contains(&PhotoSettings::default().hash64_decimal()));
    close_session(session)?;

    let session = open_session(&root, "history-test")?;
    assert_eq!(
        orphan_snapshot_hashes(session.connection())?,
        Vec::<String>::new()
    );
    assert_eq!(db_counts(session.connection())?, (1, 200, 200));
    let read = read_history(session.connection(), record.id)?;
    assert_eq!((read.cursor, read.steps.len()), (199, 200));
    close_session(session)?;
    Ok(())
}

#[test]
fn photo_row_mirrors_cursor_step_after_pushes_and_moves() -> Result<(), Box<dyn std::error::Error>>
{
    let (_scratch, mut session, record) = setup_one("mirror")?;
    for value in 1..=3_i64 {
        let json = settings_json("exposure", "ev", value)?;
        push_step(session.connection_mut(), record.id, "develop.set", &json)?;
        assert_mirror(session.connection(), record.id)?;
    }
    for target in [0_i64, 2, 3, 1] {
        move_cursor(session.connection(), record.id, target)?;
        assert_mirror(session.connection(), record.id)?;
    }
    close_session(session)?;
    Ok(())
}

#[test]
fn non_default_process_mirror_matches_settings() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("process")?;
    let v2 = settings_json_with_process(2)?;
    push_step(session.connection_mut(), record.id, "develop.set", &v2)?;
    assert_eq!(photo_row(session.connection(), record.id)?.2, 2);
    move_cursor(session.connection(), record.id, 0)?;
    assert_eq!(
        photo_row(session.connection(), record.id)?.2,
        i64::from(PhotoSettings::default().process.0)
    );
    move_cursor(session.connection(), record.id, 1)?;
    assert_eq!(photo_row(session.connection(), record.id)?.2, 2);
    close_session(session)?;
    Ok(())
}

#[test]
fn injected_key_collision_stores_two_rows_and_reports() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("collision")?;
    let first = settings_json("exposure", "ev", 1)?;
    let second = settings_json("exposure", "ev", 2)?;
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    writer.inject_snapshot_key_for_test("7");
    let one = writer.push(record.id, "develop.set", &first)?;
    assert_eq!(one.snapshot_hash, "7");
    assert!(!one.collided);
    let two = writer.push(record.id, "develop.set", &second)?;
    assert_eq!(two.snapshot_hash, "7#2");
    assert!(two.collided);
    writer.commit()?;

    let conn = session.connection();
    let stored_one: String =
        conn.query_row("SELECT json FROM snapshots WHERE hash = '7'", [], |row| {
            row.get(0)
        })?;
    let stored_two: String =
        conn.query_row("SELECT json FROM snapshots WHERE hash = '7#2'", [], |row| {
            row.get(0)
        })?;
    assert_eq!(stored_one, first);
    assert_eq!(stored_two, second);
    assert_eq!(
        step_rows(conn, record.id)?,
        vec![
            (
                0,
                SEED_LABEL.to_owned(),
                PhotoSettings::default().hash64_decimal()
            ),
            (1, "develop.set".to_owned(), "7".to_owned()),
            (2, "develop.set".to_owned(), "7#2".to_owned()),
        ]
    );
    // Pushing the first settings again reuses its row and reports no new
    // collision.
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    writer.inject_snapshot_key_for_test("7");
    let again = writer.push(record.id, "develop.set", &first)?;
    assert_eq!(again.snapshot_hash, "7");
    assert!(!again.collided);
    writer.commit()?;
    assert_eq!(db_counts(session.connection())?, (1, 4, 3));
    close_session(session)?;
    Ok(())
}

#[test]
fn third_distinct_value_extends_suffix_chain() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("suffix")?;
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    writer.inject_snapshot_key_for_test("7");
    let mut hashes = Vec::new();
    for value in 1..=3_i64 {
        let json = settings_json("exposure", "ev", value)?;
        let outcome = writer.push(record.id, "develop.set", &json)?;
        hashes.push(outcome.snapshot_hash);
        assert_eq!(outcome.collided, value != 1);
    }
    writer.commit()?;
    assert_eq!(hashes, vec!["7", "7#2", "7#3"]);
    close_session(session)?;
    Ok(())
}

#[test]
fn read_returns_steps_labels_and_cursor_for_rebuild() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("rebuild")?;
    let mut pushed = Vec::new();
    for (label, value) in [
        ("develop.set", 1_i64),
        ("develop.reset", 2),
        ("develop.set", 3),
    ] {
        let json = settings_json("exposure", "ev", value)?;
        push_step(session.connection_mut(), record.id, label, &json)?;
        pushed.push((label, json));
    }
    move_cursor(session.connection(), record.id, 1)?;
    let read = read_history(session.connection(), record.id)?;
    assert_eq!(read.photo_id, record.id);
    assert_eq!(read.cursor, 1);
    assert_eq!(read.steps.len(), 4);
    let labels: Vec<&str> = read.steps.iter().map(|step| step.label.as_str()).collect();
    assert_eq!(
        labels,
        vec![SEED_LABEL, "develop.set", "develop.reset", "develop.set"]
    );
    // Step 0's stored label is the seed label (it differs from a fresh
    // in-memory stack's "import": the SEED_LABEL finding, for B13′-b).
    let Some(stored_first) = read.steps.first() else {
        return Err("history came back empty".into());
    };
    assert_eq!(stored_first.label, SEED_LABEL);

    let Some(first) = read.steps.first() else {
        return Err("history came back empty".into());
    };
    let mut rebuilt = HistoryStack::new(Arc::new(PhotoSettings::from_json(&first.settings_json)?));
    for step in read.steps.iter().skip(1) {
        rebuilt.commit(
            &step.label,
            Arc::new(PhotoSettings::from_json(&step.settings_json)?),
        );
    }
    assert!(rebuilt.goto(usize::try_from(read.cursor)?));

    let mut reference = HistoryStack::new(Arc::new(PhotoSettings::default()));
    for (label, json) in &pushed {
        reference.commit(label, Arc::new(PhotoSettings::from_json(json)?));
    }
    assert!(reference.goto(1));
    assert_eq!(rebuilt, reference);
    assert_eq!(rebuilt.labels(), reference.labels());
    let Some(rebuilt_current) = rebuilt.current() else {
        return Err("rebuilt stack has no current step".into());
    };
    let Some(reference_current) = reference.current() else {
        return Err("reference stack has no current step".into());
    };
    assert_eq!(
        rebuilt_current.canonical_json()?,
        reference_current.canonical_json()?
    );
    close_session(session)?;
    Ok(())
}

#[test]
fn redo_steps_drop_on_push_after_undo() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("redo")?;
    let first = settings_json("exposure", "ev", 1)?;
    let second = settings_json("exposure", "ev", 2)?;
    let first_key = PhotoSettings::from_json(&first)?.hash64_decimal();
    let second_key = PhotoSettings::from_json(&second)?.hash64_decimal();
    push_step(session.connection_mut(), record.id, "develop.set", &first)?;
    push_step(session.connection_mut(), record.id, "develop.set", &second)?;
    move_cursor(session.connection(), record.id, 0)?;
    let third = settings_json("exposure", "ev", 3)?;
    let outcome = push_step(session.connection_mut(), record.id, "develop.reset", &third)?;
    assert_eq!((outcome.cursor, outcome.steps), (1, 2));
    let read = read_history(session.connection(), record.id)?;
    let labels: Vec<&str> = read.steps.iter().map(|step| step.label.as_str()).collect();
    assert_eq!(labels, vec![SEED_LABEL, "develop.reset"]);
    let orphans = orphan_snapshot_hashes(session.connection())?;
    assert!(orphans.contains(&first_key));
    assert!(orphans.contains(&second_key));
    close_session(session)?;
    Ok(())
}

#[test]
fn snapshot_rows_dedupe_across_photos() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("dedupe")?;
    let mut session = create_session(scratch.path(), "Shoot", "history-test")?;
    let root = session.root().to_path_buf();
    let mut ids = Vec::new();
    for name in ["a.arw", "b.arw"] {
        let record = register_photo(
            session.connection_mut(),
            &root,
            &root.join("Capture").join(name),
            name,
            None,
        )?;
        ids.push(record.id);
    }
    // Both step-0 rows point at the one shared default snapshot.
    assert_eq!(db_counts(session.connection())?, (2, 2, 1));
    let json = settings_json("exposure", "ev", 1)?;
    let mut hashes = Vec::new();
    for id in ids {
        let outcome = push_step(session.connection_mut(), id, "develop.paste", &json)?;
        hashes.push(outcome.snapshot_hash);
    }
    assert_eq!(db_counts(session.connection())?, (2, 4, 2));
    let Some(first) = hashes.first() else {
        return Err("no pushes ran".into());
    };
    let Some(second) = hashes.get(1) else {
        return Err("second push missing".into());
    };
    assert_eq!(first, second);
    close_session(session)?;
    Ok(())
}

#[test]
fn snapshot_key_matches_hash64_decimal() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("keymatch")?;
    for value in 1..=3_i64 {
        let json = settings_json("exposure", "ev", value)?;
        let expected = PhotoSettings::from_json(&json)?.hash64_decimal();
        let outcome = push_step(session.connection_mut(), record.id, "develop.set", &json)?;
        assert_eq!(outcome.snapshot_hash, expected);
        assert!(!outcome.collided);
    }
    close_session(session)?;
    Ok(())
}

#[test]
fn ten_thousand_photos_one_step_each_in_a_single_transaction()
-> Result<(), Box<dyn std::error::Error>> {
    use std::sync::atomic::{AtomicU64, Ordering};

    let (_scratch, mut session, _first) = setup_one("batch-10k")?;
    let root = session.root().to_path_buf();
    for number in 2..=10_000_i64 {
        let name = format!("img-{number:05}.arw");
        register_photo(
            session.connection_mut(),
            &root,
            &root.join("Capture").join(&name),
            &name,
            None,
        )?;
    }
    let json = settings_json("exposure", "ev", 1)?;
    let key = PhotoSettings::from_json(&json)?.hash64_decimal();
    let commits = Arc::new(AtomicU64::new(0));
    let counter = Arc::clone(&commits);
    session.connection_mut().commit_hook(Some(move || {
        counter.fetch_add(1, Ordering::SeqCst);
        false
    }))?;

    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    for id in 1..=10_000_i64 {
        writer.push(id, "develop.paste", &json)?;
    }
    assert_eq!(writer.stats().pushes, 10_000);
    writer.commit()?;
    assert_eq!(commits.load(Ordering::SeqCst), 1);

    let conn = session.connection();
    assert_eq!(db_counts(conn)?, (10_000, 20_000, 2));
    let landed: i64 = conn.query_row(
        "SELECT COUNT(*) FROM photos WHERE cursor = 1 AND current_hash = ?1",
        [&key],
        |row| row.get(0),
    )?;
    assert_eq!(landed, 10_000);
    close_session(session)?;
    Ok(())
}

#[test]
fn close_collects_only_orphans() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("gc-only")?;
    let mut session = create_session(scratch.path(), "Shoot", "history-test")?;
    let root = session.root().to_path_buf();
    let register = |session: &mut Session, name: &str| -> Result<i64, Box<dyn std::error::Error>> {
        let record = register_photo(
            session.connection_mut(),
            &root,
            &root.join("Capture").join(name),
            name,
            None,
        )?;
        Ok(record.id)
    };
    let photo_a = register(&mut session, "a.arw")?;
    let photo_b = register(&mut session, "b.arw")?;
    let a1 = settings_json("exposure", "ev", 1)?;
    let a2 = settings_json("exposure", "ev", 2)?;
    let b1 = settings_json("contrast", "amount", 1)?;
    push_step(session.connection_mut(), photo_a, "develop.set", &a1)?;
    push_step(session.connection_mut(), photo_a, "develop.set", &a2)?;
    push_step(session.connection_mut(), photo_b, "develop.set", &b1)?;
    move_cursor(session.connection(), photo_a, 0)?;
    let a3 = settings_json("exposure", "ev", 3)?;
    push_step(session.connection_mut(), photo_a, "develop.reset", &a3)?;

    let orphans = orphan_snapshot_hashes(session.connection())?;
    assert_eq!(orphans.len(), 2);
    close_session(session)?;

    let session = open_session(&root, "history-test")?;
    let conn = session.connection();
    assert_eq!(orphan_snapshot_hashes(conn)?, Vec::<String>::new());
    // The default snapshot, A's reset, and B's step: every referenced
    // row survived.
    assert_eq!(db_counts(conn)?, (2, 4, 3));
    let read_a = read_history(conn, photo_a)?;
    let labels_a: Vec<&str> = read_a
        .steps
        .iter()
        .map(|step| step.label.as_str())
        .collect();
    assert_eq!(labels_a, vec![SEED_LABEL, "develop.reset"]);
    let read_b = read_history(conn, photo_b)?;
    assert_eq!(read_b.steps.len(), 2);
    close_session(session)?;
    Ok(())
}

#[test]
fn verify_reports_orphan_count_matching_query() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("verify-orphan")?;
    let first = settings_json("exposure", "ev", 1)?;
    let second = settings_json("exposure", "ev", 2)?;
    push_step(session.connection_mut(), record.id, "develop.set", &first)?;
    push_step(session.connection_mut(), record.id, "develop.set", &second)?;
    move_cursor(session.connection(), record.id, 0)?;
    let third = settings_json("exposure", "ev", 3)?;
    push_step(session.connection_mut(), record.id, "develop.reset", &third)?;

    let root = session.root().to_path_buf();
    let report = verify_session(session.connection(), &root, false)?;
    let orphan_findings = report
        .findings
        .iter()
        .filter(|finding| finding.code == "orphan_snapshot")
        .count();
    assert_eq!(
        orphan_findings,
        orphan_snapshot_hashes(session.connection())?.len()
    );
    assert_eq!(orphan_findings, 2);
    assert!(
        report
            .findings
            .iter()
            .all(|finding| finding.code != "dangling_reference"),
        "healthy history must not report dangling references"
    );
    close_session(session)?;
    Ok(())
}

#[test]
fn cursor_target_out_of_range_writes_nothing() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("cursor-oob")?;
    for value in 1..=2_i64 {
        let json = settings_json("exposure", "ev", value)?;
        push_step(session.connection_mut(), record.id, "develop.set", &json)?;
    }
    let before = db_counts(session.connection())?;
    let photo_before = photo_row(session.connection(), record.id)?;
    for target in [-1_i64, 3, 99] {
        let Err(CatalogError::CursorOutOfRange {
            photo_id,
            target: got,
            steps,
        }) = move_cursor(session.connection(), record.id, target)
        else {
            return Err("out-of-range move was accepted".into());
        };
        assert_eq!((photo_id, got, steps), (record.id, target, 3));
    }
    let Err(CatalogError::UnknownPhoto(9999)) = move_cursor(session.connection(), 9999, 0) else {
        return Err("unknown photo move was accepted".into());
    };
    let Err(CatalogError::UnknownPhoto(9999)) = read_history(session.connection(), 9999) else {
        return Err("unknown photo read was accepted".into());
    };
    assert_eq!(db_counts(session.connection())?, before);
    assert_eq!(photo_row(session.connection(), record.id)?, photo_before);
    close_session(session)?;
    Ok(())
}

#[test]
fn bad_settings_text_is_refused_before_any_write() -> Result<(), Box<dyn std::error::Error>> {
    let (_scratch, mut session, record) = setup_one("bad-json")?;
    let before = db_counts(session.connection())?;
    let photo_before = photo_row(session.connection(), record.id)?;
    for text in ["{nope", "2", "null", "\"s\""] {
        let Err(CatalogError::BadSettings { .. }) =
            push_step(session.connection_mut(), record.id, "develop.set", text)
        else {
            return Err(format!("bad settings text accepted: {text}").into());
        };
    }
    assert_eq!(db_counts(session.connection())?, before);
    assert_eq!(photo_row(session.connection(), record.id)?, photo_before);
    close_session(session)?;
    Ok(())
}
