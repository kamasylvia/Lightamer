// SPDX-License-Identifier: GPL-3.0-or-later
//! Templates: album and favorite structure saved without any photos.
//!
//! The saves run in a child process (the repo's kill-child pattern): the
//! templates directory comes from the environment, and mutating the
//! environment in-process is both `unsafe` (edition 2024) and racy under
//! the test harness's parallel threads. The parent passes directories via
//! the child's environment instead, which is safe.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
mod common;

use lightamer_catalog::{
    CatalogError, TEMPLATE_DIR_ENV, create_session, open_session, save_template, template_dir,
};

use common::ScratchDir;

/// When set, this test binary runs as the template child: it opens the
/// session at the value and saves templates into `TEMPLATE_DIR_ENV`.
const TEMPLATE_CHILD_ENV: &str = "LIGHTAMER_CATALOG_TEMPLATE_CHILD";
/// When set, the binary checks the default directory against this `$HOME`.
const TEMPLATE_HOME_CHILD_ENV: &str = "LIGHTAMER_CATALOG_TEMPLATE_HOME_CHILD";

#[test]
fn template_round_trip_without_photo_paths() -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(root) = std::env::var(TEMPLATE_CHILD_ENV) {
        return template_child_main(root.as_ref());
    }
    let scratch = ScratchDir::new("template-save")?;
    let templates = scratch.path().join("templates-here");
    let setup = create_session(scratch.path(), "Studio", "template-parent")?;
    let root = setup.root().to_path_buf();
    // A photo with a distinctive path: its text must never reach the file.
    setup.connection().execute(
        "INSERT INTO snapshots (hash, json) VALUES ('h1', '{\"process\": 1}')",
        [],
    )?;
    setup.connection().execute(
        "INSERT INTO photos (uuid, path, path_kind, file_name, imported_at, current_hash) VALUES ('uuid-secret-1', 'Capture/secret-frame.arw', 0, 'secret-frame.arw', 1, 'h1')",
        [],
    )?;
    setup.connection().execute(
        "INSERT INTO albums (name, kind, created_at) VALUES ('Picks', 'album', 1)",
        [],
    )?;
    setup.connection().execute(
        "INSERT INTO albums (name, kind, rules_json, created_at) VALUES ('Five stars', 'smart', '{\"rating\": 5}', 2)",
        [],
    )?;
    setup.connection().execute(
        "INSERT INTO album_photos (album_id, photo_id, position) VALUES (1, 1, 0)",
        [],
    )?;
    setup.connection().execute(
        "INSERT INTO favorites (path, path_kind, name) VALUES ('/Volumes/Field', 1, 'Field disk')",
        [],
    )?;
    lightamer_catalog::close_session(setup)?;

    let binary = std::env::current_exe()?;
    let output = std::process::Command::new(binary)
        .arg("--exact")
        .arg("template_round_trip_without_photo_paths")
        .env(TEMPLATE_CHILD_ENV, &root)
        .env(TEMPLATE_DIR_ENV, &templates)
        .output()?;
    assert!(
        output.status.success(),
        "template child failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    // The child saved here; the parent checks the bytes.
    let path = templates.join("Field selects.json");
    let text = std::fs::read_to_string(&path)?;
    assert!(text.contains("Picks"), "{text}");
    assert!(text.contains("Five stars"), "{text}");
    assert!(
        !text.contains("Field disk"),
        "the overwrite must drop it: {text}"
    );
    assert!(
        !text.contains("uuid-secret-1"),
        "photo identity leaked: {text}"
    );
    assert!(
        !text.contains("secret-frame.arw"),
        "photo path leaked: {text}"
    );
    Ok(())
}

/// The template child: saves, overwrites, and refuses bad names.
fn template_child_main(root: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let session = open_session(root, "template-child")?;
    let path = save_template(session.connection(), "Field selects")?;
    let text = std::fs::read_to_string(&path)?;
    assert!(text.contains("Field disk"), "{text}");
    session.connection().execute("DELETE FROM favorites", [])?;
    let again = save_template(session.connection(), "Field selects")?;
    assert_eq!(again, path);
    for bad in ["", "../escape", "sub/name", "back\\slash", ".", ".."] {
        let err = save_template(session.connection(), bad).expect_err(bad);
        assert!(matches!(err, CatalogError::BadPath(_)), "{bad}: {err}");
    }
    lightamer_catalog::close_session(session)?;
    Ok(())
}

#[test]
fn template_default_dir_follows_home() -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(home) = std::env::var(TEMPLATE_HOME_CHILD_ENV) {
        let dir = template_dir()?;
        assert_eq!(
            dir,
            std::path::Path::new(&home).join("Library/Application Support/Lightamer/Templates"),
            "unset override falls back to $HOME"
        );
        return Ok(());
    }
    let scratch = ScratchDir::new("template-home")?;
    let home = scratch.path().join("fake-home");
    std::fs::create_dir(&home)?;
    let binary = std::env::current_exe()?;
    let output = std::process::Command::new(binary)
        .arg("--exact")
        .arg("template_default_dir_follows_home")
        .env(TEMPLATE_HOME_CHILD_ENV, &home)
        .env("HOME", &home)
        .env_remove(TEMPLATE_DIR_ENV)
        .output()?;
    assert!(
        output.status.success(),
        "home child failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(())
}
