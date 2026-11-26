// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from lightcraft xtask/src/layers.rs (commit 0da998f2) — reworked:
// TABLE/chains/UI list swapped for FRAMEWORK.md T-F9, full package names (no
// prefix stripping), `Dangling` rule added for registered-but-absent crates
// with a `PLANNED` carve-out, and `from_metadata` takes raw JSON text parsed
// by a dependency-free reader (this wave adds no dependencies).
//! Dependency layering rules (FRAMEWORK.md §1, layout T-F9).
//!
//! The rule engine works on a small, metadata-independent model so it can be
//! unit-tested; [`from_metadata`] builds that model from the text of
//! `cargo metadata --format-version 1 --no-deps`.
//!
//! What this check cannot see (same gap as upstream, stated here instead of
//! fixed): **transitive dependencies**. Only direct edges appear in the
//! input, so a crate can still reach a higher layer through an intermediate
//! crate without a violation. Direct edges are what the layer table governs.
//!
//! What this check adds over upstream: [`Violation::Dangling`]. A TABLE entry
//! with no matching workspace crate is a violation — renames and folds must
//! update the table in the same commit. [`PLANNED`] names the narrow
//! exception: crates already in the table whose creation is scheduled for a
//! later wave (missing is expected, present is fine).

/// Where a workspace crate sits.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Class {
    /// Regular layered crate.
    Layer(u8),
    /// Layer 0, and additionally may depend on no workspace crate at all.
    Standalone,
    /// Test tooling: may depend on anything up to L5 (it sits at L5 for rule
    /// purposes); other crates may use it only as a dev-dependency.
    Testkit,
    /// Binaries and build tooling: exempt from the rules.
    Exempt,
}

impl Class {
    fn layer(self) -> Option<u8> {
        match self {
            Class::Layer(l) => Some(l),
            Class::Standalone => Some(0),
            Class::Testkit => Some(5),
            Class::Exempt => None,
        }
    }
}

/// The layering table (FRAMEWORK-TABLES.md T-F9). Names are full package
/// names. Every workspace member must appear exactly once; see `PLANNED`
/// for the one scheduled-but-absent entry.
pub const TABLE: &[(&str, Class)] = &[
    ("lightamer-geom", Class::Layer(0)),
    ("lightamer-raster", Class::Layer(0)),
    ("lightamer-color-math", Class::Layer(0)),
    ("lightamer-iop-traits", Class::Layer(0)),
    ("lightamer-sysmem", Class::Layer(0)),
    ("lightamer-iop-raw", Class::Layer(1)),
    ("lightamer-iop-geom", Class::Layer(1)),
    ("lightamer-iop-color", Class::Layer(1)),
    ("lightamer-iop-display", Class::Layer(1)),
    ("lightamer-meta", Class::Layer(1)),
    ("lightamer-color", Class::Layer(1)),
    ("lightamer-blend", Class::Layer(1)),
    ("lightamer-decode", Class::Layer(1)),
    ("lightamer-scenes", Class::Layer(1)),
    ("lightamer-registry", Class::Layer(2)),
    ("lightamer-history", Class::Layer(2)),
    ("lightamer-pipeline", Class::Layer(2)),
    ("lightamer-catalog", Class::Layer(3)),
    ("lightamer-preview", Class::Layer(3)),
    ("lightamer-apple", Class::Layer(3)),
    ("lightamer-gpu", Class::Layer(3)),
    ("lightamer-merge", Class::Layer(3)),
    ("lightamer-ai", Class::Layer(3)),
    ("lightamer-engine", Class::Layer(4)),
    ("lightamer-gpui", Class::Layer(5)),
    ("lightamer-mcp", Class::Layer(5)),
    ("lightamer-testkit", Class::Testkit),
    // Binaries and tooling.
    ("lightamer-cli", Class::Exempt),
    ("xtask", Class::Exempt),
];

/// TABLE entries scheduled for a later wave: absent from the workspace is
/// expected, present is fine. Everything else dangling is a violation.
pub const PLANNED: &[&str] = &[
    // A7b builds the gpui interface.
    "lightamer-gpui",
];

/// Explicit orderings *within* a layer (earlier may be used by later).
/// L0: `lightamer-raster` builds on `lightamer-color-math` and `lightamer-geom`.
/// L1: `lightamer-decode` reads metadata through `lightamer-meta`.
/// L2: history aggregates the registry; the pipeline runs on both.
pub const INTRA_LAYER_ORDER: &[&[&str]] = &[
    &["lightamer-geom", "lightamer-color-math", "lightamer-raster"],
    &["lightamer-meta", "lightamer-decode"],
    &[
        "lightamer-registry",
        "lightamer-history",
        "lightamer-pipeline",
    ],
];

fn intra_layer_allowed(from: &str, to: &str) -> bool {
    INTRA_LAYER_ORDER.iter().any(|chain| {
        match (
            chain.iter().position(|n| *n == from),
            chain.iter().position(|n| *n == to),
        ) {
            (Some(f), Some(t)) => t < f,
            _ => false,
        }
    })
}

/// External crates that constitute a UI toolkit / windowing dependency.
/// Entries ending in `*` are prefixes.
pub const UI_CRATES: &[&str] = &["gpui*"];

/// First layer allowed to use UI crates.
pub const UI_MIN_LAYER: u8 = 5;

/// Classifies a full package name against [`TABLE`].
pub fn classify(name: &str) -> Option<Class> {
    classify_in(name, TABLE)
}

fn classify_in(name: &str, table: &[(&str, Class)]) -> Option<Class> {
    table.iter().find(|(n, _)| *n == name).map(|(_, c)| *c)
}

fn is_ui_crate(name: &str) -> bool {
    UI_CRATES.iter().any(|p| match p.strip_suffix('*') {
        Some(prefix) => name.starts_with(prefix),
        None => name == *p,
    })
}

/// Dependency edge kind, from the `kind` field of `cargo metadata`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DepKind {
    /// Normal (build-time and runtime) dependency.
    Normal,
    /// Dev-dependency (tests, examples, benches).
    Dev,
    /// Build-dependency (`build.rs`).
    Build,
}

/// One direct dependency edge.
#[derive(Debug, Clone)]
pub struct Dep {
    /// Dependency package name.
    pub name: String,
    /// Edge kind.
    pub kind: DepKind,
    /// `true` if the dependency is a workspace member.
    pub workspace: bool,
}

/// One workspace crate and its direct edges.
#[derive(Debug, Clone)]
pub struct Crate {
    /// Package name.
    pub name: String,
    /// Direct dependencies.
    pub deps: Vec<Dep>,
}

/// One layering violation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Violation {
    /// A workspace crate with no TABLE entry.
    Unregistered {
        /// Offending crate.
        krate: String,
    },
    /// An edge to the same or a higher layer, off any intra-layer chain.
    Upward {
        /// Depending crate.
        krate: String,
        /// Depended-upon crate.
        dep: String,
        /// Layer of `krate`.
        from: u8,
        /// Layer of `dep`.
        to: u8,
        /// Edge kind.
        kind: DepKind,
    },
    /// A standalone crate with a workspace edge.
    StandaloneHasWorkspaceDep {
        /// Offending crate.
        krate: String,
        /// Workspace dependency.
        dep: String,
    },
    /// `lightamer-testkit` used as anything but a dev-dependency.
    TestkitAsNormalDep {
        /// Offending crate.
        krate: String,
    },
    /// A UI toolkit below [`UI_MIN_LAYER`].
    UiBelowL5 {
        /// Offending crate.
        krate: String,
        /// UI dependency.
        dep: String,
        /// Layer of `krate`.
        layer: u8,
    },
    /// A TABLE entry with no matching workspace crate (and not [`PLANNED`]).
    Dangling {
        /// Stale registered name.
        name: String,
    },
}

impl std::fmt::Display for Violation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Violation::Unregistered { krate } => {
                write!(
                    f,
                    "{krate}: unknown workspace crate; register it in crates/xtask/src/layers.rs TABLE (FRAMEWORK.md T-F9)"
                )
            }
            Violation::Upward {
                krate,
                dep,
                from,
                to,
                kind,
            } => {
                write!(
                    f,
                    "{krate} (L{from}) -> {dep} (L{to}) [{kind:?}]: may only depend on strictly lower layers"
                )
            }
            Violation::StandaloneHasWorkspaceDep { krate, dep } => {
                write!(
                    f,
                    "{krate}: standalone crate must not depend on workspace crate {dep}"
                )
            }
            Violation::TestkitAsNormalDep { krate } => {
                write!(f, "{krate}: lightamer-testkit may only be a dev-dependency")
            }
            Violation::UiBelowL5 { krate, dep, layer } => {
                write!(
                    f,
                    "{krate} (L{layer}) depends on UI crate `{dep}`; UI toolkits are only allowed in L5+"
                )
            }
            Violation::Dangling { name } => {
                write!(
                    f,
                    "{name}: registered in TABLE but no such crate in the workspace; remove it or move it to PLANNED"
                )
            }
        }
    }
}

/// Check all rules against [`TABLE`]. Returns violations sorted for stable output.
pub fn check(crates: &[Crate]) -> Vec<Violation> {
    check_with(crates, TABLE)
}

fn check_with(crates: &[Crate], table: &[(&str, Class)]) -> Vec<Violation> {
    let mut out = Vec::new();
    for c in crates {
        let Some(class) = classify_in(&c.name, table) else {
            out.push(Violation::Unregistered {
                krate: c.name.clone(),
            });
            continue;
        };
        if class == Class::Exempt {
            continue;
        }
        let layer = class.layer().unwrap_or(0);
        for d in &c.deps {
            // Self dev-dependencies (e.g. to enable features in tests) are fine.
            if d.name == c.name {
                continue;
            }
            if d.workspace {
                if class == Class::Standalone {
                    out.push(Violation::StandaloneHasWorkspaceDep {
                        krate: c.name.clone(),
                        dep: d.name.clone(),
                    });
                    continue;
                }
                match classify_in(&d.name, table) {
                    Some(Class::Testkit) if d.kind != DepKind::Dev => {
                        out.push(Violation::TestkitAsNormalDep {
                            krate: c.name.clone(),
                        });
                    }
                    // Unregistered deps are reported on their own entry; dev testkit is fine.
                    None | Some(Class::Testkit) => {}
                    Some(dc) => {
                        let to = dc.layer().unwrap_or(u8::MAX);
                        if to >= layer && !(to == layer && intra_layer_allowed(&c.name, &d.name)) {
                            out.push(Violation::Upward {
                                krate: c.name.clone(),
                                dep: d.name.clone(),
                                from: layer,
                                to: if to == u8::MAX { 7 } else { to },
                                kind: d.kind,
                            });
                        }
                    }
                }
            } else if layer < UI_MIN_LAYER && is_ui_crate(&d.name) {
                out.push(Violation::UiBelowL5 {
                    krate: c.name.clone(),
                    dep: d.name.clone(),
                    layer,
                });
            }
        }
    }
    for (name, _) in table {
        if !PLANNED.contains(name) && !crates.iter().any(|c| c.name == *name) {
            out.push(Violation::Dangling {
                name: (*name).to_owned(),
            });
        }
    }
    out.sort_by_key(std::string::ToString::to_string);
    out.dedup();
    out
}

/// Build the model from the stdout of `cargo metadata --format-version 1
/// --no-deps`. Only `packages[].name` and each package's `dependencies[]`
/// (`name`, `kind`, `path`) are read; the rest is skipped.
pub fn from_metadata(text: &str) -> Result<Vec<Crate>, String> {
    let root = parse_json(text)?;
    let pkgs = root
        .get("packages")
        .and_then(Json::as_array)
        .ok_or_else(|| "metadata: no packages array".to_owned())?;
    let members: Vec<&str> = pkgs
        .iter()
        .filter_map(|p| p.get("name").and_then(Json::as_str))
        .collect();
    let mut out = Vec::new();
    for p in pkgs {
        let name = p
            .get("name")
            .and_then(Json::as_str)
            .ok_or_else(|| "metadata: package without name".to_owned())?
            .to_owned();
        let mut deps = Vec::new();
        if let Some(list) = p.get("dependencies").and_then(Json::as_array) {
            for d in list {
                let dname = d
                    .get("name")
                    .and_then(Json::as_str)
                    .unwrap_or_default()
                    .to_owned();
                let kind = match d.get("kind").and_then(Json::as_str) {
                    Some("dev") => DepKind::Dev,
                    Some("build") => DepKind::Build,
                    _ => DepKind::Normal,
                };
                let workspace =
                    members.contains(&dname.as_str()) || d.get("path").is_some_and(Json::is_string);
                deps.push(Dep {
                    name: dname,
                    kind,
                    workspace,
                });
            }
        }
        out.push(Crate { name, deps });
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}

/// One-line rendering of a crate's class for the report table.
pub fn describe(class: Option<Class>) -> String {
    match class {
        Some(Class::Layer(l)) => format!("L{l}"),
        Some(Class::Standalone) => "L0 standalone".to_owned(),
        Some(Class::Testkit) => "testkit".to_owned(),
        Some(Class::Exempt) => "exempt".to_owned(),
        None => "UNREGISTERED".to_owned(),
    }
}

// --- Dependency-free JSON reader: exactly what `from_metadata` needs. ---

#[derive(Debug, Clone, PartialEq)]
enum Json {
    Null,
    Bool(bool),
    Num,
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(pairs) => pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    fn as_array(&self) -> Option<&[Json]> {
        match self {
            Json::Arr(items) => Some(items),
            _ => None,
        }
    }

    fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }

    fn is_string(&self) -> bool {
        matches!(self, Json::Str(_))
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(text: &'a str) -> Self {
        Self {
            bytes: text.as_bytes(),
            pos: 0,
        }
    }

    fn parse(mut self) -> Result<Json, String> {
        let value = self.value()?;
        self.ws();
        if self.pos == self.bytes.len() {
            Ok(value)
        } else {
            Err(format!("JSON: trailing bytes at {}", self.pos))
        }
    }

    fn value(&mut self) -> Result<Json, String> {
        self.ws();
        match self.peek() {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => Ok(Json::Str(self.string()?)),
            Some(b't') => self.literal("true", Json::Bool(true)),
            Some(b'f') => self.literal("false", Json::Bool(false)),
            Some(b'n') => self.literal("null", Json::Null),
            Some(c) if c == b'-' || c.is_ascii_digit() => self.number(),
            _ => Err(format!("JSON: unexpected value at {}", self.pos)),
        }
    }

    fn object(&mut self) -> Result<Json, String> {
        self.pos += 1; // `{`
        let mut pairs = Vec::new();
        self.ws();
        if self.eat(b'}') {
            return Ok(Json::Obj(pairs));
        }
        loop {
            self.ws();
            if self.peek() != Some(b'"') {
                return Err(format!("JSON: expected key at {}", self.pos));
            }
            let key = self.string()?;
            self.ws();
            if !self.eat(b':') {
                return Err(format!("JSON: expected ':' at {}", self.pos));
            }
            pairs.push((key, self.value()?));
            self.ws();
            if self.eat(b'}') {
                return Ok(Json::Obj(pairs));
            }
            if !self.eat(b',') {
                return Err(format!("JSON: expected ',' at {}", self.pos));
            }
        }
    }

    fn array(&mut self) -> Result<Json, String> {
        self.pos += 1; // `[`
        let mut items = Vec::new();
        self.ws();
        if self.eat(b']') {
            return Ok(Json::Arr(items));
        }
        loop {
            items.push(self.value()?);
            self.ws();
            if self.eat(b']') {
                return Ok(Json::Arr(items));
            }
            if !self.eat(b',') {
                return Err(format!("JSON: expected ',' at {}", self.pos));
            }
        }
    }

    fn string(&mut self) -> Result<String, String> {
        self.pos += 1; // `"`
        let mut out = String::new();
        loop {
            let Some(c) = self.next() else {
                return Err("JSON: unterminated string".to_owned());
            };
            match c {
                b'"' => return Ok(out),
                b'\\' => {
                    let Some(e) = self.next() else {
                        return Err("JSON: unterminated escape".to_owned());
                    };
                    match e {
                        b'"' | b'\\' | b'/' => out.push(e as char),
                        b'b' => out.push('\u{0008}'),
                        b'f' => out.push('\u{000C}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => out.push(self.unicode()?),
                        _ => return Err(format!("JSON: bad escape at {}", self.pos)),
                    }
                }
                0x00..=0x1F => return Err(format!("JSON: control byte at {}", self.pos)),
                _ => {
                    let start = self.pos - 1;
                    let rest = &self.bytes[start..];
                    let len =
                        utf8_len(rest).ok_or_else(|| format!("JSON: bad UTF-8 at {start}"))?;
                    out.push_str(
                        std::str::from_utf8(&rest[..len])
                            .map_err(|_| format!("JSON: bad UTF-8 at {start}"))?,
                    );
                    self.pos += len - 1;
                }
            }
        }
    }

    fn unicode(&mut self) -> Result<char, String> {
        let hi = self.hex4()?;
        if (0xD800..0xDC00).contains(&hi) {
            if self.peek() == Some(b'\\') && self.bytes.get(self.pos + 1) == Some(&b'u') {
                self.pos += 2;
                let lo = self.hex4()?;
                if (0xDC00..0xE000).contains(&lo) {
                    let n = 0x1_0000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
                    return char::from_u32(n).ok_or_else(|| "JSON: bad surrogate".to_owned());
                }
            }
            return Err("JSON: lone surrogate".to_owned());
        }
        char::from_u32(hi).ok_or_else(|| "JSON: bad \\u escape".to_owned())
    }

    fn hex4(&mut self) -> Result<u32, String> {
        if self.pos + 4 > self.bytes.len() {
            return Err("JSON: truncated \\u escape".to_owned());
        }
        let mut n = 0u32;
        for i in 0..4 {
            let d = self.bytes[self.pos + i];
            let v = (d as char)
                .to_digit(16)
                .ok_or_else(|| format!("JSON: bad hex at {}", self.pos + i))?;
            n = n * 16 + v;
        }
        self.pos += 4;
        Ok(n)
    }

    fn number(&mut self) -> Result<Json, String> {
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        if !self.peek().is_some_and(|c| c.is_ascii_digit()) {
            return Err(format!("JSON: bad number at {}", self.pos));
        }
        while self.peek().is_some_and(|c| c.is_ascii_digit()) {
            self.pos += 1;
        }
        if self.peek() == Some(b'.') {
            self.pos += 1;
            if !self.peek().is_some_and(|c| c.is_ascii_digit()) {
                return Err(format!("JSON: bad fraction at {}", self.pos));
            }
            while self.peek().is_some_and(|c| c.is_ascii_digit()) {
                self.pos += 1;
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.pos += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.pos += 1;
            }
            if !self.peek().is_some_and(|c| c.is_ascii_digit()) {
                return Err(format!("JSON: bad exponent at {}", self.pos));
            }
            while self.peek().is_some_and(|c| c.is_ascii_digit()) {
                self.pos += 1;
            }
        }
        Ok(Json::Num)
    }

    fn literal(&mut self, word: &str, value: Json) -> Result<Json, String> {
        if self.bytes[self.pos..].starts_with(word.as_bytes()) {
            self.pos += word.len();
            Ok(value)
        } else {
            Err(format!("JSON: bad literal at {}", self.pos))
        }
    }

    fn ws(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.pos += 1;
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn next(&mut self) -> Option<u8> {
        let c = self.peek()?;
        self.pos += 1;
        Some(c)
    }

    fn eat(&mut self, want: u8) -> bool {
        if self.peek() == Some(want) {
            self.pos += 1;
            true
        } else {
            false
        }
    }
}

fn utf8_len(rest: &[u8]) -> Option<usize> {
    let b = *rest.first()?;
    let len = if b < 0x80 {
        1
    } else if b >> 5 == 0b110 {
        2
    } else if b >> 4 == 0b1110 {
        3
    } else if b >> 3 == 0b11110 {
        4
    } else {
        return None;
    };
    if rest.len() < len {
        return None;
    }
    if rest[1..len].iter().all(|c| c >> 6 == 0b10) {
        Some(len)
    } else {
        None
    }
}

fn parse_json(text: &str) -> Result<Json, String> {
    Reader::new(text).parse()
}

#[cfg(test)]
mod tests {
    use super::*;
    use DepKind::{Build, Dev, Normal};

    fn c(name: &str, deps: &[(&str, DepKind, bool)]) -> Crate {
        Crate {
            name: name.into(),
            deps: deps
                .iter()
                .map(|(n, k, w)| Dep {
                    name: (*n).into(),
                    kind: *k,
                    workspace: *w,
                })
                .collect(),
        }
    }

    /// Full TABLE-shaped graph minus `lightamer-gpui` (PLANNED): every entry present.
    fn full_graph() -> Vec<Crate> {
        TABLE
            .iter()
            .filter(|(n, _)| *n != "lightamer-gpui")
            .map(|(n, _)| c(n, &[]))
            .collect()
    }

    #[test]
    fn clean_downward_graph_passes() {
        let mut g = full_graph();
        g.push(c(
            "lightamer-iop-raw",
            &[("lightamer-iop-traits", Normal, true)],
        ));
        g.push(c(
            "lightamer-registry",
            &[
                ("lightamer-iop-raw", Normal, true),
                ("lightamer-testkit", Dev, true),
            ],
        ));
        g.push(c(
            "lightamer-engine",
            &[("lightamer-registry", Normal, true)],
        ));
        // `check` dedups identical violations; duplicates of clean edges stay clean.
        assert!(check(&g).is_empty(), "{:?}", check(&g));
    }

    #[test]
    fn upward_dependency_flagged() {
        let g = full_graph();
        let v = check(
            &[
                g,
                vec![c(
                    "lightamer-iop-traits",
                    &[("lightamer-registry", Normal, true)],
                )],
            ]
            .concat(),
        );
        assert!(
            matches!(v[..], [Violation::Upward { from: 0, to: 2, .. }]),
            "{v:?}"
        );
    }

    #[test]
    fn sideways_dependency_flagged() {
        let g = full_graph();
        let v = check(
            &[
                g,
                vec![c(
                    "lightamer-catalog",
                    &[("lightamer-preview", Normal, true)],
                )],
            ]
            .concat(),
        );
        assert!(
            matches!(v[..], [Violation::Upward { from: 3, to: 3, .. }]),
            "{v:?}"
        );
    }

    #[test]
    fn l0_chain_allowed_one_way() {
        let g = full_graph();
        let ok = check(
            &[
                g.clone(),
                vec![c(
                    "lightamer-raster",
                    &[("lightamer-color-math", Normal, true)],
                )],
            ]
            .concat(),
        );
        assert!(ok.is_empty(), "{ok:?}");
        let bad = check(
            &[
                g,
                vec![c(
                    "lightamer-color-math",
                    &[("lightamer-raster", Normal, true)],
                )],
            ]
            .concat(),
        );
        assert!(
            matches!(bad[..], [Violation::Upward { from: 0, to: 0, .. }]),
            "{bad:?}"
        );
    }

    #[test]
    fn l1_chain_meta_decode() {
        let g = full_graph();
        let ok = check(
            &[
                g.clone(),
                vec![c("lightamer-decode", &[("lightamer-meta", Normal, true)])],
            ]
            .concat(),
        );
        assert!(ok.is_empty(), "{ok:?}");
        let bad = check(
            &[
                g,
                vec![c("lightamer-meta", &[("lightamer-decode", Normal, true)])],
            ]
            .concat(),
        );
        assert!(
            matches!(bad[..], [Violation::Upward { from: 1, to: 1, .. }]),
            "{bad:?}"
        );
    }

    #[test]
    fn l2_chain_registry_history_pipeline() {
        let g = full_graph();
        let ok = check(
            &[
                g.clone(),
                vec![
                    c("lightamer-history", &[("lightamer-registry", Normal, true)]),
                    c("lightamer-pipeline", &[("lightamer-history", Normal, true)]),
                ],
            ]
            .concat(),
        );
        assert!(ok.is_empty(), "{ok:?}");
        let bad = check(
            &[
                g,
                vec![c(
                    "lightamer-registry",
                    &[("lightamer-pipeline", Normal, true)],
                )],
            ]
            .concat(),
        );
        assert!(
            matches!(bad[..], [Violation::Upward { from: 2, to: 2, .. }]),
            "{bad:?}"
        );
    }

    #[test]
    fn ui_crates_forbidden_below_l5() {
        for dep in ["gpui", "gpui_component", "gpui-winit"] {
            let g = full_graph();
            let v = check(&[g, vec![c("lightamer-engine", &[(dep, Normal, false)])]].concat());
            assert!(
                matches!(v[..], [Violation::UiBelowL5 { .. }]),
                "{dep}: {v:?}"
            );
        }
        let g = full_graph();
        let ok = check(&[g, vec![c("lightamer-mcp", &[("gpui", Normal, false)])]].concat());
        assert!(ok.is_empty(), "{ok:?}");
    }

    #[test]
    fn unregistered_crate_flagged() {
        let g = full_graph();
        let v = check(&[g, vec![c("dt-mystery", &[])]].concat());
        assert!(
            matches!(&v[..], [Violation::Unregistered { krate }] if krate == "dt-mystery"),
            "{v:?}"
        );
    }

    #[test]
    fn testkit_dev_only() {
        let g = full_graph();
        let bad = check(
            &[
                g.clone(),
                vec![c(
                    "lightamer-pipeline",
                    &[("lightamer-testkit", Normal, true)],
                )],
            ]
            .concat(),
        );
        assert!(
            matches!(bad[..], [Violation::TestkitAsNormalDep { .. }]),
            "{bad:?}"
        );
        let build = check(
            &[
                g.clone(),
                vec![c(
                    "lightamer-pipeline",
                    &[("lightamer-testkit", Build, true)],
                )],
            ]
            .concat(),
        );
        assert!(
            matches!(build[..], [Violation::TestkitAsNormalDep { .. }]),
            "{build:?}"
        );
        let ok = check(
            &[
                g,
                vec![c("lightamer-pipeline", &[("lightamer-testkit", Dev, true)])],
            ]
            .concat(),
        );
        assert!(ok.is_empty(), "{ok:?}");
    }

    #[test]
    fn exempt_crates_skipped() {
        for app in ["lightamer-cli", "xtask"] {
            let g = full_graph();
            let ok = check(
                &[
                    g,
                    vec![c(
                        app,
                        &[("gpui", Normal, false), ("lightamer-gpui", Normal, true)],
                    )],
                ]
                .concat(),
            );
            assert!(ok.is_empty(), "{app}: {ok:?}");
        }
    }

    #[test]
    fn standalone_rule_fires() {
        let table: &[(&str, Class)] = &[
            ("dt-lone", Class::Standalone),
            ("lightamer-geom", Class::Layer(0)),
        ];
        let bad = check_with(
            &[
                c("dt-lone", &[("lightamer-geom", Normal, true)]),
                c("lightamer-geom", &[]),
            ],
            table,
        );
        assert!(
            matches!(bad[..], [Violation::StandaloneHasWorkspaceDep { .. }]),
            "{bad:?}"
        );
        let ok = check_with(
            &[
                c("dt-lone", &[("serde", Normal, false)]),
                c("lightamer-geom", &[]),
            ],
            table,
        );
        assert!(ok.is_empty(), "{ok:?}");
    }

    #[test]
    fn dangling_table_entry_flagged() {
        let table: &[(&str, Class)] = &[
            ("dt-ghost", Class::Layer(3)),
            ("lightamer-geom", Class::Layer(0)),
        ];
        let v = check_with(&[c("lightamer-geom", &[])], table);
        assert!(
            matches!(&v[..], [Violation::Dangling { name }] if name == "dt-ghost"),
            "{v:?}"
        );
    }

    #[test]
    fn planned_crate_may_be_missing() {
        // `lightamer-gpui` is in TABLE but has no crate yet: every other dangling
        // entry would fire, but never the planned one.
        let v = check(&[c("lightamer-geom", &[])]);
        assert!(
            !v.iter()
                .any(|x| matches!(x, Violation::Dangling { name } if name == "lightamer-gpui")),
            "{v:?}"
        );
        assert!(
            v.iter().any(|x| matches!(x, Violation::Dangling { .. })),
            "{v:?}"
        );
    }

    #[test]
    fn metadata_shape_parses() {
        let text = r#"{"packages":[
            {"name":"lightamer-iop-traits","dependencies":[]},
            {"name":"lightamer-iop-raw","dependencies":[
                {"name":"lightamer-iop-traits","kind":null,"path":"crates/lightamer-iop-traits"},
                {"name":"lightamer-testkit","kind":"dev","path":"crates/lightamer-testkit"},
                {"name":"cc","kind":"build"},
                {"name":"serde","kind":null}
            ]},
            {"name":"other","dependencies":[{"name":"lightamer-iop-raw","kind":null}]}
        ]}"#;
        let crates = from_metadata(text).expect("parse");
        assert_eq!(crates.len(), 3);
        let raw = crates
            .iter()
            .find(|c| c.name == "lightamer-iop-raw")
            .expect("raw");
        assert_eq!(raw.deps.len(), 4);
        assert!(matches!(
            raw.deps[0],
            Dep {
                kind: Normal,
                workspace: true,
                ..
            }
        ));
        assert!(matches!(
            raw.deps[1],
            Dep {
                kind: Dev,
                workspace: true,
                ..
            }
        ));
        assert!(matches!(
            raw.deps[2],
            Dep {
                kind: Build,
                workspace: false,
                ..
            }
        ));
        assert!(matches!(
            raw.deps[3],
            Dep {
                kind: Normal,
                workspace: false,
                ..
            }
        ));
        // A member name matches even without `path` (plain `kind: null` edge).
        let other = crates.iter().find(|c| c.name == "other").expect("other");
        assert!(other.deps[0].workspace);
    }

    #[test]
    fn metadata_errors_are_typed() {
        assert!(from_metadata("{}").is_err());
        assert!(from_metadata("{oops").is_err());
        assert!(from_metadata(r#"{"packages":[{"dependencies":[]}]}"#).is_err());
    }

    #[test]
    fn json_reader_handles_escapes_and_unicode() {
        let v = parse_json(r#"{"a":"x\"y\\z\/\n\u00e9😀","b":[1,-2.5e3,true,false,null,{}]}"#)
            .expect("parse");
        let s = v.get("a").and_then(Json::as_str).expect("a");
        assert_eq!(s, "x\"y\\z/\n\u{e9}\u{1F600}");
        assert_eq!(v.get("b").and_then(Json::as_array).map(<[_]>::len), Some(6));
        assert!(parse_json("{\"a\": }").is_err());
        assert!(parse_json("{\"a\": \"\u{1}leak\"}").is_err());
    }
}
