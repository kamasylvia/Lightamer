// SPDX-License-Identifier: GPL-3.0-or-later
//! Session templates: album and favorite structure without any photos.
//!
//! [`save_template`] writes the session's albums (names, kinds, smart
//! rules) and favorites (names, folder paths) to one JSON file. Membership
//! (`album_photos`) is never read, so the file cannot leak photo references;
//! photo rows are not touched at all.
//!
//! Templates live in [`template_dir`]: `~/Library/Application Support/`
//! `Lightamer/Templates/` by default, or wherever
//! [`TEMPLATE_DIR_ENV`] points. The variable replaces the Templates
//! directory itself (not its parent): with the variable set, the file lands
//! directly inside it. Tests always set the variable to a scratch directory
//! and never touch the real one.

use std::path::PathBuf;

use rusqlite::Connection;

use crate::error::{CatalogError, io_error};

/// Environment variable overriding the templates directory (see the module
/// docs). Tests set this to a scratch directory.
pub const TEMPLATE_DIR_ENV: &str = "LIGHTAMER_APP_SUPPORT_DIR";

/// Where templates are stored: the [`TEMPLATE_DIR_ENV`] directory when set
/// and non-empty, else `~/Library/Application Support/Lightamer/Templates/`.
///
/// # Errors
///
/// [`CatalogError::Setup`] when neither the variable nor `$HOME` names a
/// directory.
pub fn template_dir() -> Result<PathBuf, CatalogError> {
    if let Some(dir) = std::env::var_os(TEMPLATE_DIR_ENV)
        && !dir.is_empty()
    {
        return Ok(PathBuf::from(dir));
    }
    let Some(home) = std::env::var_os("HOME").map(PathBuf::from) else {
        return Err(CatalogError::Setup(
            "no home directory: set LIGHTAMER_APP_SUPPORT_DIR or HOME to store templates"
                .to_owned(),
        ));
    };
    Ok(home.join("Library/Application Support/Lightamer/Templates"))
}

/// Saves the session's album and favorite structure as `<name>.json` under
/// [`template_dir`], creating the directory, and returns the file written.
/// Saving over an existing name replaces it.
///
/// # Errors
///
/// [`CatalogError::BadPath`] when the name is empty, too long, dotted, or
/// holds a separator; [`CatalogError::Sql`] when the library refuses a read;
/// [`CatalogError::Setup`] when the home directory is unknown;
/// [`CatalogError::Io`] when the file refuses to be written.
pub fn save_template(conn: &Connection, name: &str) -> Result<PathBuf, CatalogError> {
    check_template_name(name)?;
    let mut albums = conn.prepare("SELECT name, kind, rules_json FROM albums ORDER BY id")?;
    let albums: Vec<(String, String, Option<String>)> = albums
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
        .collect::<Result<_, _>>()?;
    let mut favorites = conn.prepare("SELECT name, path, path_kind FROM favorites ORDER BY id")?;
    let favorites: Vec<(String, String, i64)> = favorites
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
        .collect::<Result<_, _>>()?;
    let doc = serde_json::json!({
        "template": name,
        "albums": albums.iter().map(|(album, kind, rules)| {
            serde_json::json!({
                "name": album,
                "kind": kind,
                "rules": rules_json_value(rules.as_ref()),
            })
        }).collect::<Vec<_>>(),
        "favorites": favorites.iter().map(|(favorite, path, kind)| {
            serde_json::json!({
                "name": favorite,
                "path": path,
                "path_kind": kind,
            })
        }).collect::<Vec<_>>(),
    });
    let text = serde_json::to_string_pretty(&doc)
        .map_err(|err| CatalogError::Setup(format!("template JSON refused to serialize: {err}")))?;
    let dir = template_dir()?;
    std::fs::create_dir_all(&dir).map_err(|source| io_error(&dir, source))?;
    let path = dir.join(format!("{name}.json"));
    std::fs::write(&path, text).map_err(|source| io_error(&path, source))?;
    Ok(path)
}

/// A stored smart-album rule as JSON when it parses, else the raw text
/// (lossless: an unparseable rule still round-trips).
fn rules_json_value(rules: Option<&String>) -> serde_json::Value {
    rules.map_or(serde_json::Value::Null, |text| {
        serde_json::from_str::<serde_json::Value>(text)
            .unwrap_or_else(|_| serde_json::Value::String(text.clone()))
    })
}

/// Refuses anything but a plain file stem (no separators, no dotted names).
fn check_template_name(name: &str) -> Result<(), CatalogError> {
    if name.is_empty() || name.len() > 128 {
        return Err(CatalogError::BadPath(format!(
            "template name must be 1..=128 bytes: {name:?}"
        )));
    }
    if name == "." || name == ".." {
        return Err(CatalogError::BadPath(format!(
            "template name must not be dotted: {name:?}"
        )));
    }
    if name.contains('/') || name.contains('\\') || name.contains('\0') {
        return Err(CatalogError::BadPath(format!(
            "template name must not hold a separator: {name:?}"
        )));
    }
    Ok(())
}
