// SPDX-License-Identifier: GPL-3.0-or-later
//! Parses darktable `iop_order.c` tables and our own order fixture.

use std::env;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Upstream `iop_order.c` relative to an upstream checkout root.
pub(crate) const IOP_ORDER_REL: &str = "src/common/iop_order.c";

/// One named row of an order table, in row order.
#[derive(Debug)]
pub(crate) struct OrderEntry {
    /// Module name (sentinel `""` rows are dropped before this).
    pub(crate) name: String,
    /// Priority text for fixtures and stubs: verbatim from C, with `.0`
    /// appended when the literal has no fraction.
    pub(crate) prio_text: String,
    /// Parsed priority.
    pub(crate) prio: f32,
}

/// Named entries of one order table; the index is the tie value.
#[derive(Debug)]
pub(crate) struct OrderTable {
    /// Entries in table row order.
    pub(crate) entries: Vec<OrderEntry>,
}

/// One fixture row: both keys of one module.
#[derive(Debug)]
pub(crate) struct FixtureEntry {
    /// Module name.
    pub(crate) name: String,
    /// Raw priority text.
    pub(crate) raw_prio_text: String,
    /// Raw priority value.
    pub(crate) raw_prio: f32,
    /// Row index in `v50_order` (0-based).
    pub(crate) raw_tie: u16,
    /// Non-raw priority text.
    pub(crate) jpg_prio_text: String,
    /// Non-raw priority value.
    pub(crate) jpg_prio: f32,
    /// Row index in `v50_jpg_order` (0-based).
    pub(crate) jpg_tie: u16,
}

impl std::fmt::Display for FixtureEntry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let Self {
            name,
            raw_prio_text: raw_prio,
            raw_tie,
            jpg_prio_text: jpg_prio,
            jpg_tie,
            ..
        } = self;
        write!(f, "{name} ({raw_prio}/{raw_tie}, {jpg_prio}/{jpg_tie})")
    }
}

/// Workspace root (`crates/xtask` sits two levels below it).
pub(crate) fn workspace_root() -> PathBuf {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest
        .parent()
        .and_then(|path| path.parent())
        .expect("crates/xtask layout")
        .to_path_buf()
}

/// Full commit id of `HEAD` in `upstream`.
pub(crate) fn upstream_head(upstream: &Path) -> Result<String, String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(upstream)
        .arg("rev-parse")
        .arg("HEAD")
        .output()
        .map_err(|err| format!("cannot run git: {err}"))?;
    if !out.status.success() {
        let path = upstream.display();
        return Err(format!("git rev-parse failed in {path}"));
    }
    let head =
        String::from_utf8(out.stdout).map_err(|err| format!("non-UTF8 git output: {err}"))?;
    let head = head.trim().to_owned();
    if head.len() != 40 || !head.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(format!("bad upstream HEAD: {head:?}"));
    }
    Ok(head)
}

/// Formats an I/O failure against `path`.
pub(crate) fn io_err(action: &str, path: &Path, err: &std::io::Error) -> String {
    let path = path.display();
    format!("cannot {action} {path}: {err}")
}

/// Parses the named order table (`v50_order` or `v50_jpg_order`) from C source.
///
/// Matches the declaration with word boundaries, so `v50_order` never matches
/// the `v50_jpg_order` line (and skips the legacy tables in the same file).
pub(crate) fn parse_table(source: &str, table: &str) -> Result<OrderTable, String> {
    let body = find_table_body(source, table)?;
    let bytes = body.as_bytes();
    let mut entries = Vec::new();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'{'
            && let Some((entry, next)) = parse_entry(bytes, index)
        {
            if !entry.name.is_empty() {
                entries.push(entry);
            }
            index = next;
            continue;
        }
        index += 1;
    }
    if entries.is_empty() {
        return Err(format!("table {table}: no named entries parsed"));
    }
    Ok(OrderTable { entries })
}

/// Body of the table declaration, up to its closing `};`.
fn find_table_body<'a>(source: &'a str, table: &str) -> Result<&'a str, String> {
    let mut search = 0;
    let found = loop {
        let Some(rel) = source[search..].find(table) else {
            return Err(format!("table {table}: declaration not found"));
        };
        let abs = search + rel;
        let before_ok = abs == 0 || !is_ident_char(source.as_bytes()[abs - 1]);
        if before_ok && source[abs + table.len()..].starts_with("[]") {
            break abs;
        }
        search = abs + 1;
    };
    let rest = &source[found..];
    let open = rest
        .find('{')
        .ok_or_else(|| format!("table {table}: no opening brace"))?;
    let body_start = found + open + 1;
    let tail = &source[body_start..];
    let close = tail
        .find("\n};")
        .ok_or_else(|| format!("table {table}: no closing brace"))?;
    Ok(&source[body_start..body_start + close])
}

/// Parses `{ { <prio>f? }, "<name>" ... }` at `bytes[start] == b'{'`.
fn parse_entry(bytes: &[u8], start: usize) -> Option<(OrderEntry, usize)> {
    let mut index = skip_ws(bytes, start + 1);
    if bytes.get(index) != Some(&b'{') {
        return None;
    }
    index = skip_ws(bytes, index + 1);
    let num_start = index;
    while index < bytes.len() && (bytes[index].is_ascii_digit() || bytes[index] == b'.') {
        index += 1;
    }
    if num_start == index {
        return None;
    }
    let mut prio_text = str::from_utf8(&bytes[num_start..index]).ok()?.to_owned();
    if !prio_text.contains('.') {
        prio_text.push_str(".0");
    }
    if bytes.get(index) == Some(&b'f') {
        index += 1;
    }
    index = skip_ws(bytes, index);
    if bytes.get(index) != Some(&b'}') {
        return None;
    }
    index = skip_ws(bytes, index + 1);
    if bytes.get(index) != Some(&b',') {
        return None;
    }
    index = skip_ws(bytes, index + 1);
    if bytes.get(index) != Some(&b'"') {
        return None;
    }
    index += 1;
    let name_start = index;
    while index < bytes.len() && bytes[index] != b'"' {
        index += 1;
    }
    if index >= bytes.len() {
        return None;
    }
    let name = str::from_utf8(&bytes[name_start..index]).ok()?.to_owned();
    let prio: f32 = prio_text.parse().ok()?;
    Some((
        OrderEntry {
            name,
            prio_text,
            prio,
        },
        index + 1,
    ))
}

/// Skips ASCII whitespace from `index`.
fn skip_ws(bytes: &[u8], mut index: usize) -> usize {
    while index < bytes.len() && bytes[index].is_ascii_whitespace() {
        index += 1;
    }
    index
}

/// Whether `byte` can appear inside a C identifier.
fn is_ident_char(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

/// Joins both tables into fixture rows in raw-table order.
pub(crate) fn join_tables(
    raw_table: &OrderTable,
    jpg_table: &OrderTable,
) -> Result<Vec<FixtureEntry>, String> {
    let mut rows = Vec::with_capacity(raw_table.entries.len());
    for (raw_pos, entry) in raw_table.entries.iter().enumerate() {
        let Some(jpg_pos) = jpg_table
            .entries
            .iter()
            .position(|other| other.name == entry.name)
        else {
            let name = &entry.name;
            return Err(format!("{name}: missing from v50_jpg_order"));
        };
        let other = &jpg_table.entries[jpg_pos];
        let raw_tie =
            u16::try_from(raw_pos).map_err(|_| "raw table exceeds u16 tie range".to_owned())?;
        let jpg_tie =
            u16::try_from(jpg_pos).map_err(|_| "jpg table exceeds u16 tie range".to_owned())?;
        rows.push(FixtureEntry {
            name: entry.name.clone(),
            raw_prio_text: entry.prio_text.clone(),
            raw_prio: entry.prio,
            raw_tie,
            jpg_prio_text: other.prio_text.clone(),
            jpg_prio: other.prio,
            jpg_tie,
        });
    }
    for other in &jpg_table.entries {
        if !raw_table
            .entries
            .iter()
            .any(|entry| entry.name == other.name)
        {
            let name = &other.name;
            return Err(format!("{name}: missing from v50_order"));
        }
    }
    Ok(rows)
}

/// Renders fixture rows in the strict one-object-per-line shape.
pub(crate) fn render_fixture(rows: &[FixtureEntry]) -> String {
    let mut out = String::from("[\n");
    for (index, row) in rows.iter().enumerate() {
        let comma = if index + 1 == rows.len() { "" } else { "," };
        let name = &row.name;
        let raw_prio = &row.raw_prio_text;
        let raw_tie = row.raw_tie;
        let jpg_prio = &row.jpg_prio_text;
        let jpg_tie = row.jpg_tie;
        let _ = writeln!(
            out,
            "  {{\"name\": \"{name}\", \"raw_prio\": {raw_prio}, \"raw_tie\": {raw_tie}, \"jpg_prio\": {jpg_prio}, \"jpg_tie\": {jpg_tie}}}{comma}"
        );
    }
    out.push_str("]\n");
    out
}

/// Parses our own fixture back (strict shape: one object per line).
///
/// Twin of the parser in the `dt-registry` tests; both must accept what
/// `gen-iop-stubs` writes (tests cannot import this binary crate).
pub(crate) fn parse_fixture_json(text: &str) -> Result<Vec<FixtureEntry>, String> {
    let mut rows = Vec::new();
    for (lineno, line) in text.lines().enumerate() {
        if !line.contains("\"name\"") {
            continue;
        }
        let name = extract_string(line, "\"name\"")?;
        let raw_prio_text = extract_number(line, "\"raw_prio\"")?;
        let jpg_prio_text = extract_number(line, "\"jpg_prio\"")?;
        let raw_tie: u16 = extract_number(line, "\"raw_tie\"")?
            .parse()
            .map_err(|_| bad_line(lineno, "raw_tie"))?;
        let jpg_tie: u16 = extract_number(line, "\"jpg_tie\"")?
            .parse()
            .map_err(|_| bad_line(lineno, "jpg_tie"))?;
        let raw_prio: f32 = raw_prio_text
            .parse()
            .map_err(|_| bad_line(lineno, "raw_prio"))?;
        let jpg_prio: f32 = jpg_prio_text
            .parse()
            .map_err(|_| bad_line(lineno, "jpg_prio"))?;
        rows.push(FixtureEntry {
            name,
            raw_prio_text,
            raw_prio,
            raw_tie,
            jpg_prio_text,
            jpg_prio,
            jpg_tie,
        });
    }
    if rows.is_empty() {
        return Err("fixture holds no rows".to_owned());
    }
    Ok(rows)
}

/// Formats a fixture line error (0-based `lineno`).
fn bad_line(lineno: usize, what: &str) -> String {
    let line = lineno + 1;
    format!("fixture line {line}: bad {what}")
}

/// Value of `"key": "<value>"` on one fixture line.
fn extract_string(line: &str, key: &str) -> Result<String, String> {
    let after = after_key(line, key)?;
    let rest = after
        .strip_prefix('"')
        .ok_or_else(|| format!("{key}: expected string"))?;
    let end = rest
        .find('"')
        .ok_or_else(|| format!("{key}: unterminated string"))?;
    Ok(rest[..end].to_owned())
}

/// Value of `"key": <number>` on one fixture line.
fn extract_number(line: &str, key: &str) -> Result<String, String> {
    let after = after_key(line, key)?;
    let token: String = after
        .chars()
        .take_while(|chr| chr.is_ascii_digit() || *chr == '.')
        .collect();
    if token.is_empty() || token == "." {
        return Err(format!("{key}: expected number"));
    }
    Ok(token)
}

/// Text after `"key":` on one fixture line.
fn after_key<'a>(line: &'a str, key: &str) -> Result<&'a str, String> {
    let pos = line.find(key).ok_or_else(|| format!("{key}: missing"))?;
    let rest = &line[pos + key.len()..];
    let colon = rest
        .find(':')
        .ok_or_else(|| format!("{key}: missing colon"))?;
    Ok(rest[colon + 1..].trim_start())
}

#[cfg(test)]
mod tests {
    use super::{join_tables, parse_fixture_json, parse_table, render_fixture};
    use std::cmp::Ordering;

    const SNIPPET: &str = "const dt_iop_order_entry_t v50_order[] = {\n  { { 1.0 }, \"aaa\", 0},\n  { { 28.5f }, \"bbb\", 0},\n  { { 28.5f }, \"ccc\", 0},\n  { { 0.0f }, \"\", 0 }\n};\nconst dt_iop_order_entry_t v50_jpg_order[] = {\n  { { 1.0 }, \"aaa\", 0 },\n  { { 28.0f }, \"bbb\", 0 },\n  { { 28.0f }, \"ccc\", 0 },\n  { { 0.0f }, \"\", 0 }\n};\n";

    #[test]
    fn parses_named_rows_and_drops_sentinel() {
        let table = parse_table(SNIPPET, "v50_order").expect("snippet parses");
        let names: Vec<&str> = table
            .entries
            .iter()
            .map(|entry| entry.name.as_str())
            .collect();
        assert_eq!(names, ["aaa", "bbb", "ccc"]);
        assert_eq!(table.entries[1].prio_text, "28.5");
        assert_eq!(table.entries[1].prio.total_cmp(&28.5), Ordering::Equal);
    }

    #[test]
    fn raw_and_jpg_tables_stay_apart() {
        let raw = parse_table(SNIPPET, "v50_order").expect("snippet parses");
        let jpg = parse_table(SNIPPET, "v50_jpg_order").expect("snippet parses");
        assert_eq!(raw.entries[1].prio_text, "28.5");
        assert_eq!(jpg.entries[1].prio_text, "28.0");
    }

    #[test]
    fn join_reports_name_set_mismatch() {
        let raw = parse_table(SNIPPET, "v50_order").expect("snippet parses");
        let mut jpg = parse_table(SNIPPET, "v50_jpg_order").expect("snippet parses");
        jpg.entries.pop();
        let err = join_tables(&raw, &jpg).expect_err("ccc is missing");
        assert!(err.contains("ccc"), "unexpected error: {err}");
    }

    #[test]
    fn fixture_render_parse_round_trip() {
        let raw = parse_table(SNIPPET, "v50_order").expect("snippet parses");
        let jpg = parse_table(SNIPPET, "v50_jpg_order").expect("snippet parses");
        let rows = join_tables(&raw, &jpg).expect("sets match");
        let back = parse_fixture_json(&render_fixture(&rows)).expect("round trip");
        assert_eq!(back.len(), 3);
        assert_eq!(back[0].name, "aaa");
        assert_eq!(back[1].raw_tie, 1);
        assert_eq!(back[2].jpg_tie, 2);
        assert_eq!(back[1].jpg_prio_text, "28.0");
    }
}
