// SPDX-License-Identifier: GPL-3.0-or-later
//! `gen-iop-stubs`: order fixture plus one stub directory per module.

use super::iop_order::{self, FixtureEntry};
use std::fmt::Write as _;
use std::fs;
use std::path::Path;

/// Frozen T2 assignments as `(module, domain)`. T2 names modules with globs
/// (`channelmixer*`, `colorbalance*`); both expansions are listed here.
const FROZEN: &[(&str, &str)] = &[
    ("rawprepare", "raw"),
    ("hotpixels", "raw"),
    ("demosaic", "raw"),
    ("rawdenoise", "raw"),
    ("demosaicscale", "raw"),
    ("rawoverexposed", "raw"),
    ("rasterfile", "raw"),
    ("lens", "geom"),
    ("cacorrect", "geom"),
    ("cacorrectrgb", "geom"),
    ("ashift", "geom"),
    ("flip", "geom"),
    ("crop", "geom"),
    ("rotatepixels", "geom"),
    ("scalepixels", "geom"),
    ("enlargecanvas", "geom"),
    ("temperature", "color"),
    ("colorin", "color"),
    ("colorout", "color"),
    ("lut3d", "color"),
    ("spektrafilm", "color"),
    ("channelmixer", "color"),
    ("channelmixerrgb", "color"),
    ("colorbalance", "color"),
    ("colorbalancergb", "color"),
    ("colorzones", "color"),
    ("exposure", "display"),
    ("highlights", "display"),
    ("rgbcurve", "display"),
    ("rgblevels", "display"),
    ("tonecurve", "display"),
    ("finalscale", "display"),
    ("gamma", "display"),
    ("dither", "display"),
    ("overexposed", "display"),
];

/// Domain crates in registry aggregation order.
const DOMAINS: &[&str] = &["raw", "geom", "color", "display"];

/// Rust keywords a module id must not collide with (checked loudly).
const KEYWORDS: &[&str] = &[
    "as", "break", "const", "continue", "crate", "else", "enum", "extern", "false", "fn", "for",
    "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
    "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where",
    "while", "async", "await", "dyn", "abstract", "become", "box", "do", "final", "macro",
    "override", "priv", "typeof", "unsized", "virtual", "yield", "try", "gen",
];

/// Generates the order fixture and every module stub from `upstream`.
pub(crate) fn run(upstream: &Path) -> Result<(), String> {
    let root = iop_order::workspace_root();
    let order_path = upstream.join(iop_order::IOP_ORDER_REL);
    let source = fs::read_to_string(&order_path)
        .map_err(|err| iop_order::io_err("read", &order_path, &err))?;
    let raw = iop_order::parse_table(&source, "v50_order")?;
    let jpg = iop_order::parse_table(&source, "v50_jpg_order")?;
    let rows = iop_order::join_tables(&raw, &jpg)?;
    let head = iop_order::upstream_head(upstream)?;
    let short = head[..10].to_owned();
    let fixtures = root.join("crates/lightamer-registry/fixtures");
    fs::create_dir_all(&fixtures).map_err(|err| iop_order::io_err("create", &fixtures, &err))?;
    remove_stale_fixtures(&fixtures, &short)?;
    let fixture_path = fixtures.join(format!("dt-order-{short}.json"));
    fs::write(&fixture_path, iop_order::render_fixture(&rows))
        .map_err(|err| iop_order::io_err("write", &fixture_path, &err))?;
    let readme_path = fixtures.join("README.md");
    fs::write(&readme_path, readme_text(&short, &head, upstream))
        .map_err(|err| iop_order::io_err("write", &readme_path, &err))?;
    let mut planned: Vec<(&FixtureEntry, &'static str)> = Vec::with_capacity(rows.len());
    for row in &rows {
        assert_usable_ident(&row.name)?;
        planned.push((row, assign(upstream, row)));
    }
    for (row, domain) in &planned {
        refuse_to_clobber(&root, domain, &row.name)?;
    }
    let mut counts = [0usize; 4];
    for (row, domain) in &planned {
        let index = DOMAINS
            .iter()
            .position(|known| *known == *domain)
            .expect("assign returns known domains");
        counts[index] += 1;
        sweep_other_domains(&root, domain, &row.name)?;
        write_stub(&root, domain, row, &short)?;
    }
    remove_stale_stubs(&root, &rows)?;
    let total = rows.len();
    let breakdown = format!(
        "raw={} geom={} color={} display={}",
        counts[0], counts[1], counts[2], counts[3]
    );
    println!("gen-iop-stubs: {total} modules from {short} ({breakdown})");
    let fixture_display = fixture_path.display();
    println!("gen-iop-stubs: fixture {fixture_display}");
    Ok(())
}

/// Assigns a domain: frozen T2 list, raw head band, tags, groups, fallback.
///
/// Rule order: (1) frozen T2 names; (2) raw pipe head (`raw_prio < 9.0`, the
/// segment the jpg table keeps fixed — its own comment says `[8.5; 28]` is
/// what moves); (3) `DECORATION` tags to display; (4) geometric tags to geom;
/// (5) primary old-group tab (`COLOR` to color, `TONE`/old-`EFFECT` to
/// display, `CORRECT` to geom, `BASIC` to display); (6) `EFFECTS`-only
/// leftovers to display; (7) fallback to display with a warning.
fn assign(upstream: &Path, row: &FixtureEntry) -> &'static str {
    if let Some((_, domain)) = FROZEN.iter().find(|(name, _)| *name == row.name) {
        return domain;
    }
    if row.raw_prio < 9.0 {
        return "raw";
    }
    let (groups, tags) = dt_group_and_tags(upstream, &row.name);
    if tags.contains("DECORATION") {
        return "display";
    }
    if tags.contains("DISTORT") || tags.contains("CROPPING") || tags.contains("GEOMETRY") {
        return "geom";
    }
    let tokens = group_tokens(&groups);
    if tokens.contains(&"COLOR") {
        return "color";
    }
    if tokens.contains(&"TONE") {
        return "display";
    }
    if tokens.contains(&"EFFECT") {
        return "display";
    }
    if tokens.contains(&"CORRECT") {
        return "geom";
    }
    if tokens.contains(&"BASIC") {
        return "display";
    }
    if tokens.contains(&"EFFECTS") {
        return "display";
    }
    if groups.is_empty() && tags.is_empty() {
        let name = &row.name;
        eprintln!(
            "gen-iop-stubs: warn: {name}: no darktable source or group info; fallback to display"
        );
    }
    "display"
}

/// Exact `IOP_GROUP_*` suffixes in a `default_group()` expression.
///
/// Exact tokens (not substrings): `EFFECTS` must not match `EFFECT`, so a
/// `CORRECT | EFFECTS` module classifies as `CORRECT`, not as effects.
fn group_tokens(expr: &str) -> Vec<&str> {
    let mut tokens = Vec::new();
    let mut search = 0;
    while let Some(rel) = expr[search..].find("IOP_GROUP_") {
        let base = search + rel + "IOP_GROUP_".len();
        let rest = &expr[base..];
        let end = rest
            .find(|chr: char| !chr.is_ascii_uppercase())
            .map_or(expr.len(), |offset| base + offset);
        tokens.push(&expr[base..end]);
        search = end;
    }
    tokens
}

/// `default_group()` / `operation_tags()` return expressions from `src/iop/<name>.c*`.
fn dt_group_and_tags(upstream: &Path, name: &str) -> (String, String) {
    let iop = upstream.join("src/iop");
    let source = ["c", "cc"]
        .iter()
        .map(|ext| iop.join(format!("{name}.{ext}")))
        .find_map(|path| fs::read_to_string(path).ok());
    let Some(source) = source else {
        return (String::new(), String::new());
    };
    (
        function_return(&source, "default_group"),
        function_return(&source, "operation_tags"),
    )
}

/// Return expression of the `name()` function definition in C source.
fn function_return(source: &str, name: &str) -> String {
    let mut search = 0;
    while let Some(rel) = source[search..].find(name) {
        let after_name = &source[search + rel + name.len()..];
        let trimmed = after_name.trim_start();
        if !trimmed.starts_with('(') {
            search += rel + name.len();
            continue;
        }
        let Some(open) = trimmed.find('{') else {
            return String::new();
        };
        if trimmed[..open].contains(';') {
            search += rel + name.len();
            continue;
        }
        let window: String = trimmed[open + 1..].chars().take(600).collect();
        let Some((_, ret)) = window.split_once("return") else {
            return String::new();
        };
        return ret.split(';').next().unwrap_or("").to_owned();
    }
    String::new()
}

/// Writes one stub directory (rigid shape; `check-order-sync` parses it back).
fn write_stub(root: &Path, domain: &str, row: &FixtureEntry, short: &str) -> Result<(), String> {
    let name = &row.name;
    let dir = root.join(format!("crates/lightamer-iop-{domain}/src/modules/{name}"));
    fs::create_dir_all(&dir).map_err(|err| iop_order::io_err("create", &dir, &err))?;
    let raw_prio = &row.raw_prio_text;
    let raw_tie = row.raw_tie;
    let jpg_prio = &row.jpg_prio_text;
    let jpg_tie = row.jpg_tie;
    let mut text = String::new();
    let _ = writeln!(text, "// SPDX-License-Identifier: GPL-3.0-or-later");
    let _ = writeln!(
        text,
        "//! Auto-generated stub for darktable module `{name}` (baseline {short})."
    );
    let _ = writeln!(
        text,
        "//! Only `id` and `order` are set; later waves fill the rest."
    );
    let _ = writeln!(text);
    let _ = writeln!(
        text,
        "/// Module descriptor stub. See `lightamer_iop_traits::ModuleDesc`."
    );
    let _ = writeln!(
        text,
        "pub static DESC: ::lightamer_iop_traits::ModuleDesc = ::lightamer_iop_traits::ModuleDesc::stub("
    );
    let _ = writeln!(text, "    \"{name}\",");
    let _ = writeln!(text, "    ::lightamer_iop_traits::OrderKey {{");
    let _ = writeln!(text, "        priority: {raw_prio},");
    let _ = writeln!(text, "        tie: {raw_tie},");
    let _ = writeln!(text, "    }},");
    let _ = writeln!(text, "    ::lightamer_iop_traits::OrderKey {{");
    let _ = writeln!(text, "        priority: {jpg_prio},");
    let _ = writeln!(text, "        tie: {jpg_tie},");
    let _ = writeln!(text, "    }},");
    let _ = writeln!(text, ");");
    let path = dir.join("mod.rs");
    fs::write(&path, text).map_err(|err| iop_order::io_err("write", &path, &err))?;
    Ok(())
}

/// Whether `text` is a stub this generator owns (safe to overwrite/remove).
fn is_ours(text: &str) -> bool {
    text.contains("Auto-generated stub for darktable module")
}

/// Fails before writing anything when the target holds a foreign file.
fn refuse_to_clobber(root: &Path, domain: &str, name: &str) -> Result<(), String> {
    let path = root.join(format!(
        "crates/lightamer-iop-{domain}/src/modules/{name}/mod.rs"
    ));
    if !path.is_file() {
        return Ok(());
    }
    let text = fs::read_to_string(&path).map_err(|err| iop_order::io_err("read", &path, &err))?;
    if is_ours(&text) {
        return Ok(());
    }
    let path = path.display();
    Err(format!(
        "{path}: foreign file; move it aside before regenerating"
    ))
}

/// Removes our own same-named dirs from the other three domains (moves).
fn sweep_other_domains(root: &Path, domain: &str, name: &str) -> Result<(), String> {
    for other in DOMAINS {
        if *other == domain {
            continue;
        }
        let dir = root.join(format!("crates/lightamer-iop-{other}/src/modules/{name}"));
        let file = dir.join("mod.rs");
        if !file.is_file() {
            continue;
        }
        let text =
            fs::read_to_string(&file).map_err(|err| iop_order::io_err("read", &file, &err))?;
        if !is_ours(&text) {
            let kept = dir.display();
            eprintln!("gen-iop-stubs: warn: {kept} kept (foreign; sync will flag the duplicate)");
            continue;
        }
        fs::remove_dir_all(&dir).map_err(|err| iop_order::io_err("remove", &dir, &err))?;
        println!("gen-iop-stubs: moved {name} to {domain} (removed from {other})");
    }
    Ok(())
}

/// Removes our own stub dirs for modules gone from the tables.
fn remove_stale_stubs(root: &Path, rows: &[FixtureEntry]) -> Result<(), String> {
    for domain in DOMAINS {
        let modules = root.join(format!("crates/lightamer-iop-{domain}/src/modules"));
        let Ok(entries) = fs::read_dir(&modules) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if rows.iter().any(|row| row.name == name) {
                continue;
            }
            let is_stub = fs::read_to_string(path.join("mod.rs"))
                .is_ok_and(|text| text.contains("Auto-generated stub for darktable module"));
            if !is_stub {
                let kept = path.display();
                eprintln!("gen-iop-stubs: warn: {kept} kept (not ours, not in tables)");
                continue;
            }
            fs::remove_dir_all(&path).map_err(|err| iop_order::io_err("remove", &path, &err))?;
            println!("gen-iop-stubs: removed stale {name}");
        }
    }
    Ok(())
}

/// Removes fixture files from older baselines (one baseline at a time).
fn remove_stale_fixtures(fixtures: &Path, short: &str) -> Result<(), String> {
    let keep = format!("dt-order-{short}.json");
    let Ok(entries) = fs::read_dir(fixtures) else {
        return Ok(());
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        let is_fixture = path
            .extension()
            .is_some_and(|ext| ext.eq_ignore_ascii_case("json"));
        if is_fixture && name.starts_with("dt-order-") && name != keep {
            fs::remove_file(&path).map_err(|err| iop_order::io_err("remove", &path, &err))?;
            println!("gen-iop-stubs: removed stale {name}");
        }
    }
    Ok(())
}

/// Rejects module ids that cannot become Rust module names (loudly).
fn assert_usable_ident(name: &str) -> Result<(), String> {
    let mut chars = name.chars();
    let head_ok = chars
        .next()
        .is_some_and(|chr| chr.is_ascii_alphabetic() || chr == '_');
    let tail_ok = chars.all(|chr| chr.is_ascii_alphanumeric() || chr == '_');
    if !head_ok || !tail_ok {
        return Err(format!("{name}: not a Rust module name"));
    }
    if KEYWORDS.contains(&name) {
        return Err(format!("{name}: collides with a Rust keyword"));
    }
    Ok(())
}

/// Fixture directory notes (JSON holds no comments, so they live here).
fn readme_text(short: &str, head: &str, upstream: &Path) -> String {
    let path = upstream.display();
    format!(
        "# Order fixture\n\
        \n\
        Upstream: {path}\n\
        Commit: {head} (short {short})\n\
        \n\
        Regenerate with (from the workspace root):\n\
        \n\
        cargo run -p xtask -- gen-iop-stubs\n\
        \n\
        Add `--upstream PATH` to parse another checkout.\n\
        \n\
        `dt-order-{short}.json`: one row per named module of `v50_order` and\n\
        `v50_jpg_order` in `src/common/iop_order.c` at that commit, in raw-table\n\
        order. Each row:\n\
        \n\
        {{\"name\": \"<op>\", \"raw_prio\": <f>, \"raw_tie\": <u>, \"jpg_prio\": <f>, \"jpg_tie\": <u>}}\n\
        \n\
        - `raw_prio` / `jpg_prio`: priority verbatim from C (never with the `f`\n\
        suffix; integral values gain `.0` so JSON and Rust both read floats).\n\
        - `raw_tie` / `jpg_tie`: 0-based row index among named rows of that\n\
        table; the sentinel `\"\"` row is dropped and never counted.\n\
        \n\
        `check-order-sync` re-parses the upstream tables and compares them with\n\
        this fixture and with the stub directories; any drift fails the check.\n"
    )
}
