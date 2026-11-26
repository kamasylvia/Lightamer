// SPDX-License-Identifier: GPL-3.0-or-later
//! Fixtures for the real-session persistence tests: a scratch session with
//! registered placeholder photos, opened through the engine's own commands.

use std::path::{Path, PathBuf};

use lightamer_engine::Engine;
use serde_json::json;

use super::common::ScratchDir;

/// A scratch session opened through the engine, holding registered photos.
pub struct RealFixture {
    /// Keeps the scratch directory alive (removed on drop).
    pub scratch: ScratchDir,
    /// The engine holding the open real session.
    pub engine: Engine,
    /// Photo UUIDs in registration order.
    pub uuids: Vec<String>,
    /// The session root directory.
    pub root: PathBuf,
    /// The session database file.
    pub db: PathBuf,
}

/// Opens a real session named `Shoot` under a scratch directory and registers
/// `photos` empty placeholder files (`Capture/p{i}.arw`). The engine accepts
/// every module id undescribed, like the draft unit tests.
pub fn open_real_fixture(
    tag: &str,
    photos: usize,
) -> Result<RealFixture, Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new(tag)?;
    let mut engine = Engine::new();
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    let outcome = engine.execute(
        "session.new",
        &json!({"parent": scratch.path().to_string_lossy(), "name": "Shoot"}),
    )?;
    let root = PathBuf::from(
        outcome
            .get("root")
            .and_then(serde_json::Value::as_str)
            .ok_or("session.new hid its root")?,
    );
    let db = PathBuf::from(
        outcome
            .get("database")
            .and_then(serde_json::Value::as_str)
            .ok_or("session.new hid its database")?,
    );
    let mut uuids = Vec::with_capacity(photos);
    {
        let mut raw = rusqlite::Connection::open(&db)?;
        for index in 0..photos {
            let name = format!("p{index}.arw");
            let rel = Path::new("Capture").join(&name);
            std::fs::write(root.join(&rel), b"")?;
            let record = lightamer_catalog::register_photo(
                &mut raw,
                &root,
                &root.join(&rel),
                &name,
                Some(0),
            )?;
            uuids.push(record.uuid);
        }
    }
    Ok(RealFixture {
        scratch,
        engine,
        uuids,
        root,
        db,
    })
}

/// Closes the fixture's session through the engine (checkpoints and unlocks).
pub fn close_fixture(fixture: &mut RealFixture) -> Result<(), Box<dyn std::error::Error>> {
    fixture.engine.execute("session.close", &json!({}))?;
    Ok(())
}

/// Runs `develop.set` of one float parameter on one photo.
pub fn set_float(
    engine: &mut Engine,
    id: &str,
    module: &str,
    param: &str,
    value: f64,
) -> Result<(), Box<dyn std::error::Error>> {
    engine.execute(
        "develop.set",
        &json!({"ids": [id], "module": module, "patch": {param: {"type": "float", "value": value}}}),
    )?;
    Ok(())
}

/// One float parameter of one photo's current settings, when it is there.
pub fn current_float(engine: &Engine, id: &str, module: &str, param: &str) -> Option<f64> {
    let settings = engine.photo_settings(id)?;
    let instance = settings.instances.get(module, 0)?;
    match instance.params.get(param) {
        Some(lightamer_history::SettingValue::Float(value)) => Some(*value),
        _ => None,
    }
}

/// Installs two triggers that refuse every history write (step inserts and
/// photo-row updates): any store transaction then fails deterministically.
/// Memory-only commands succeeding past these prove they never write.
pub fn install_refuse_triggers(db: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let raw = rusqlite::Connection::open(db)?;
    raw.execute(
        "CREATE TRIGGER refuse_push BEFORE INSERT ON history_steps \
         BEGIN SELECT RAISE(ABORT, 'refused'); END",
        [],
    )?;
    raw.execute(
        "CREATE TRIGGER refuse_move BEFORE UPDATE ON photos \
         BEGIN SELECT RAISE(ABORT, 'refused'); END",
        [],
    )?;
    Ok(())
}
