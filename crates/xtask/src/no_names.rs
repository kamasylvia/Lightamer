// SPDX-License-Identifier: GPL-3.0-or-later
//! `check-no-iop-names`: no baseline module name inside core sources.

use super::iop_order;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

/// Crate roots that must not name any module.
const SCAN_ROOTS: &[&str] = &["crates/dt-core", "crates/dt-api", "crates/dt-registry"];

/// Fails when a fixture name appears as a string literal under a scan root.
///
/// The `fixtures` data directory is not source and is skipped; everything
/// else ending in `.rs` under the three roots is scanned.
pub(crate) fn run() -> Result<(), String> {
    let root = iop_order::workspace_root();
    let names = fixture_names(&root)?;
    let mut hits = Vec::new();
    for scan in SCAN_ROOTS {
        for file in rust_files(&root.join(scan)) {
            hits.extend(scan_file(&file, &names));
        }
    }
    if hits.is_empty() {
        let total = names.len();
        let roots = SCAN_ROOTS.len();
        println!("check-no-iop-names: OK ({total} names, {roots} roots clean)");
        return Ok(());
    }
    let mut report = format!("{} forbidden literals:", hits.len());
    for (file, lineno, name) in hits.iter().take(20) {
        let path = file.display();
        let _ = writeln!(report, "\n  {path}:{lineno}: \"{name}\"");
    }
    Err(report)
}

/// Baseline module names from the one order fixture.
fn fixture_names(root: &Path) -> Result<Vec<String>, String> {
    let dir = root.join("crates/dt-registry/fixtures");
    let entries = fs::read_dir(&dir).map_err(|err| iop_order::io_err("read", &dir, &err))?;
    let mut files = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        let is_fixture = path
            .extension()
            .is_some_and(|ext| ext.eq_ignore_ascii_case("json"));
        if is_fixture && name.starts_with("dt-order-") {
            files.push(path);
        }
    }
    if files.len() != 1 {
        let count = files.len();
        return Err(format!("expected one dt-order-*.json, found {count}"));
    }
    let text =
        fs::read_to_string(&files[0]).map_err(|err| iop_order::io_err("read", &files[0], &err))?;
    Ok(iop_order::parse_fixture_json(&text)?
        .into_iter()
        .map(|row| row.name)
        .collect())
}

/// Every `.rs` file under `dir`, skipping `fixtures` data directories.
fn rust_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    collect_rust_files(dir, &mut out);
    out.sort();
    out
}

/// Recursively collects `.rs` files, skipping `fixtures` directories.
fn collect_rust_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if !path.ends_with("fixtures") {
                collect_rust_files(&path, out);
            }
        } else if path.extension().is_some_and(|ext| ext == "rs") {
            out.push(path);
        }
    }
}

/// `(file, line, name)` hits: quoted baseline names inside one file.
fn scan_file(file: &Path, names: &[String]) -> Vec<(PathBuf, usize, String)> {
    let Ok(text) = fs::read_to_string(file) else {
        return Vec::new();
    };
    let mut hits = Vec::new();
    for name in names {
        let needle = format!("\"{name}\"");
        if !text.contains(&needle) {
            continue;
        }
        for (lineno, line) in text.lines().enumerate() {
            if line.contains(&needle) {
                hits.push((file.to_path_buf(), lineno + 1, name.clone()));
            }
        }
    }
    hits
}
