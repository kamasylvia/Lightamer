// SPDX-License-Identifier: GPL-3.0-or-later
//! `check-order-sync`: upstream tables vs fixture vs stubs.

use super::iop_order::{self, FixtureEntry};
use std::cmp::Ordering;
use std::fs;
use std::path::{Path, PathBuf};

/// Domain crates in registry aggregation order.
const DOMAINS: &[&str] = &["raw", "geom", "color", "display"];

/// Re-parses upstream and compares it with the fixture and the stubs.
pub(crate) fn run(upstream: &Path) -> Result<(), String> {
    let root = iop_order::workspace_root();
    let order_path = upstream.join(iop_order::IOP_ORDER_REL);
    let source = fs::read_to_string(&order_path)
        .map_err(|err| iop_order::io_err("read", &order_path, &err))?;
    let raw = iop_order::parse_table(&source, "v50_order")?;
    let jpg = iop_order::parse_table(&source, "v50_jpg_order")?;
    let expected = iop_order::join_tables(&raw, &jpg)?;
    let fixture_path = find_fixture(&root)?;
    let text = fs::read_to_string(&fixture_path)
        .map_err(|err| iop_order::io_err("read", &fixture_path, &err))?;
    let fixture = iop_order::parse_fixture_json(&text)?;
    compare_rows(&expected, &fixture)?;
    check_stubs(&root, &fixture)?;
    let total = fixture.len();
    let path = fixture_path.display();
    println!("check-order-sync: OK ({total} modules, fixture {path})");
    Ok(())
}

/// Locates the one order fixture (exactly one may exist).
fn find_fixture(root: &Path) -> Result<PathBuf, String> {
    let dir = root.join("crates/lightamer-registry/fixtures");
    let entries = fs::read_dir(&dir).map_err(|err| iop_order::io_err("read", &dir, &err))?;
    let mut found = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        let is_fixture = path
            .extension()
            .is_some_and(|ext| ext.eq_ignore_ascii_case("json"));
        if is_fixture && name.starts_with("dt-order-") {
            found.push(path);
        }
    }
    if found.len() != 1 {
        let path = dir.display();
        let count = found.len();
        return Err(format!(
            "expected one dt-order-*.json in {path}, found {count}"
        ));
    }
    found
        .pop()
        .ok_or_else(|| "fixture search failed".to_owned())
}

/// Compares upstream rows with fixture rows position by position.
fn compare_rows(expected: &[FixtureEntry], fixture: &[FixtureEntry]) -> Result<(), String> {
    if expected.len() != fixture.len() {
        let want = expected.len();
        let got = fixture.len();
        return Err(format!("row count: upstream {want} vs fixture {got}"));
    }
    for (index, (want, got)) in expected.iter().zip(fixture.iter()).enumerate() {
        if want.name != got.name
            || want.raw_prio.total_cmp(&got.raw_prio) != Ordering::Equal
            || want.raw_tie != got.raw_tie
            || want.jpg_prio.total_cmp(&got.jpg_prio) != Ordering::Equal
            || want.jpg_tie != got.jpg_tie
        {
            return Err(format!("row {index}: upstream {want} vs fixture {got}"));
        }
    }
    Ok(())
}

/// Every fixture row owns exactly one stub dir with matching keys.
fn check_stubs(root: &Path, fixture: &[FixtureEntry]) -> Result<(), String> {
    let mut stubs: Vec<(String, PathBuf)> = Vec::new();
    for domain in DOMAINS {
        let modules = root.join(format!("crates/lightamer-iop-{domain}/src/modules"));
        let entries =
            fs::read_dir(&modules).map_err(|err| iop_order::io_err("read", &modules, &err))?;
        for entry in entries.flatten() {
            if entry.path().join("mod.rs").is_file() {
                stubs.push((
                    entry.file_name().to_string_lossy().into_owned(),
                    entry.path(),
                ));
            }
        }
    }
    for row in fixture {
        let hits: Vec<&Path> = stubs
            .iter()
            .filter(|(name, _)| *name == row.name)
            .map(|(_, path)| path.as_path())
            .collect();
        if hits.len() != 1 {
            let name = &row.name;
            let count = hits.len();
            return Err(format!("{name}: stub dirs found: {count}"));
        }
        check_stub_keys(hits[0], row)?;
    }
    for (name, path) in &stubs {
        if !fixture.iter().any(|row| row.name == *name) {
            let path = path.display();
            return Err(format!("{path}: stub dir without a fixture row"));
        }
    }
    Ok(())
}

/// The stub's id literal and both `priority`/`tie` pairs match the row.
fn check_stub_keys(path: &Path, row: &FixtureEntry) -> Result<(), String> {
    let file = path.join("mod.rs");
    let text = fs::read_to_string(&file).map_err(|err| iop_order::io_err("read", &file, &err))?;
    let name = &row.name;
    let id = format!("\"{name}\"");
    if !text.contains(&id) {
        let path = path.display();
        return Err(format!("{path}: id literal missing"));
    }
    let pairs = stub_key_pairs(&text);
    let want = [
        (row.raw_prio_text.clone(), row.raw_tie),
        (row.jpg_prio_text.clone(), row.jpg_tie),
    ];
    if pairs != want {
        let path = path.display();
        return Err(format!("{path}: keys {pairs:?} vs fixture {want:?}"));
    }
    Ok(())
}

/// `[(priority text, tie)]` pairs in file order (raw first, then jpg).
fn stub_key_pairs(text: &str) -> Vec<(String, u16)> {
    let mut pairs = Vec::new();
    let mut search = 0;
    while let Some(rel) = text[search..].find("priority:") {
        let base = search + rel + "priority:".len();
        let prio: String = text[base..]
            .trim_start()
            .chars()
            .take_while(|chr| chr.is_ascii_digit() || *chr == '.')
            .collect();
        let Some(tie_rel) = text[base..].find("tie:") else {
            break;
        };
        let tie_base = base + tie_rel + "tie:".len();
        let tie_text: String = text[tie_base..]
            .trim_start()
            .chars()
            .take_while(char::is_ascii_digit)
            .collect();
        let Ok(tie) = tie_text.parse::<u16>() else {
            break;
        };
        if prio.is_empty() {
            break;
        }
        pairs.push((prio, tie));
        search = tie_base + tie_text.len();
    }
    pairs
}
