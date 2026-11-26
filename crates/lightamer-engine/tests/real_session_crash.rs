// SPDX-License-Identifier: GPL-3.0-or-later
//! Crash semantics through the engine: a killed child keeps exactly its
//! committed steps, and an unended drag's live value dies with it.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

#[allow(dead_code)]
mod common;
#[allow(dead_code)]
mod real_common;

use std::process::Stdio;

use lightamer_engine::Engine;
use serde_json::json;

use common::ScratchDir;

/// When set, this test binary runs as the kill child: it opens the session at
/// the value, commits three steps, starts a drag and updates it once, signals
/// readiness, and sleeps until it is killed. Only the test's own binary is
/// ever spawned.
const KILL_CHILD_ENV: &str = "LIGHTAMER_ENGINE_CRASH_KILL_CHILD";

/// The photo's file name inside `Capture/` (also the registration key).
const PHOTO_FILE: &str = "a.arw";

#[test]
fn killed_mid_drag_keeps_committed_steps_and_loses_the_live_value()
-> Result<(), Box<dyn std::error::Error>> {
    if let Ok(root) = std::env::var(KILL_CHILD_ENV) {
        return kill_child_main(&root);
    }
    let scratch = ScratchDir::new("crash-drag")?;
    let root = scratch.path().join("Shoot");
    let uuid = {
        let mut setup = lightamer_catalog::create_session(scratch.path(), "Shoot", "crash-parent")?;
        let root = setup.root().to_path_buf();
        std::fs::write(root.join("Capture").join(PHOTO_FILE), b"")?;
        let record = lightamer_catalog::register_photo(
            setup.connection_mut(),
            &root,
            &root.join("Capture").join(PHOTO_FILE),
            PHOTO_FILE,
            Some(0),
        )?;
        lightamer_catalog::close_session(setup)?;
        record.uuid
    };

    let binary = std::env::current_exe()?;
    let mut child = std::process::Command::new(binary)
        .arg("--exact")
        .arg("killed_mid_drag_keeps_committed_steps_and_loses_the_live_value")
        .env(KILL_CHILD_ENV, &root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let ready = root.join("engine-kill-ready");
    let mut waited = 0;
    while !ready.exists() && waited < 300 {
        std::thread::sleep(std::time::Duration::from_millis(10));
        waited += 1;
    }
    // Kill our own child either way, so a failure never strands it.
    child.kill()?;
    child.wait()?;
    assert!(ready.exists(), "kill child never signaled ready");

    let mut engine = Engine::new();
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine.execute("session.open", &json!({"path": root.to_string_lossy()}))?;
    assert_eq!(engine.photo_len(&uuid), Some(4));
    assert_eq!(engine.photo_cursor(&uuid), Some(3));
    let labels = engine.photo_labels(&uuid).unwrap_or_default();
    assert_eq!(
        labels,
        vec!["import", "develop.set", "develop.set", "develop.set"]
    );
    let settings = engine.photo_settings(&uuid).expect("current");
    let instance = settings.instances.get("mod_a", 0).expect("instance");
    assert_eq!(
        instance.params.get("p_x"),
        Some(&lightamer_history::SettingValue::Float(3.0))
    );
    engine.execute("session.close", &json!({}))?;
    Ok(())
}

/// The kill child: opens the parent's session through the engine, commits
/// three steps, begins a drag and updates it once (never ended), signals
/// readiness, then sleeps until the parent kills it.
fn kill_child_main(root: &str) -> Result<(), Box<dyn std::error::Error>> {
    let root = std::path::Path::new(root);
    let uuid = {
        let raw = rusqlite::Connection::open(root.join("Shoot.lmsessiondb"))?;
        let mut found: Option<String> = None;
        for candidate in lightamer_catalog::list_photo_uuids(&raw)? {
            found = Some(candidate);
        }
        found.ok_or("parent registered no photo")?
    };
    let mut engine = Engine::new();
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine.execute("session.open", &json!({"path": root.to_string_lossy()}))?;
    for step in 1..=3 {
        engine.execute(
            "develop.set",
            &json!({"ids": [&uuid], "module": "mod_a", "patch": {"p_x": {"type": "float", "value": f64::from(step)}}}),
        )?;
    }
    engine.execute("develop.beginInteraction", &json!({"id": uuid}))?;
    engine.execute(
        "develop.updateInteraction",
        &json!({"id": uuid, "module": "mod_a", "patch": {"p_x": {"type": "float", "value": 99.0}}}),
    )?;
    std::fs::write(root.join("engine-kill-ready"), b"ready")?;
    for _ in 0..600 {
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
    Ok(())
}
