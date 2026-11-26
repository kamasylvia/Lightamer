// SPDX-License-Identifier: GPL-3.0-or-later
//! `check-apple-boundary`: Apple bindings live only in `lightamer-apple`.
//!
//! Four rules (see `docs/APPLE-BOUNDARY.md`):
//! 1. No workspace crate except `lightamer-apple` names an Apple binding crate in
//!    its direct dependencies ([`APPLE_EXACT`] + the [`OBJC2_PREFIX`] family).
//! 2. Inside `lightamer-apple`, every Apple binding dependency sits under the macOS
//!    target table.
//! 3. Rust sources, build scripts, and tests under `crates/` and `apps/`
//!    (except `crates/lightamer-apple/`) name no Apple token ([`NEEDLES`]).
//! 4. Unreadable `cargo metadata` output fails the check, never passes it.
//!
//! The rule engine works on a small model ([`Crate`]/[`Dep`]) built by
//! [`from_metadata`] from `cargo metadata --format-version 1 --no-deps`, the
//! same input shape `layers.rs` uses. Only direct edges are visible.
//!
//! Self-hosting note: this file is itself scanned by rule 3 and by the raw
//! `rg` gate in the A6 report, so the forbidden tokens never appear here as
//! literals; they are assembled with `concat!` (compile time, no cost).
//! Behavioral proof that the assembled needles match real code is the live
//! negative test in `Scripts/rust-apple-boundary.sh` (§8 of the wave brief),
//! not a literal in a unit test.
use std::path::{Path, PathBuf};

/// Manifest-name prefix of the bridge-crate family (the `objc` stem plus
/// `2`, and everything starting with it). Assembled so this file stays clean
/// under its own rule 3.
pub const OBJC2_PREFIX: &str = concat!("objc", "2");

/// Apple binding crates by exact manifest name. Dash form (as in manifests);
/// underscore form is a separate rule-3 needle. To add or drop a crate, edit
/// this list only.
pub const APPLE_EXACT: &[&str] = &[
    "objc",
    "block2",
    "dispatch2",
    "core-foundation",
    "core-graphics",
    "core-graphics-types",
    "metal",
    "cocoa",
    "cocoa-foundation",
    "io-surface",
    "foreign-types",
    "core-text",
    "core-video",
    "core-image",
];

/// True when `name` is an Apple binding crate (prefix family or exact list).
pub fn is_apple_binding(name: &str) -> bool {
    name.starts_with(OBJC2_PREFIX) || APPLE_EXACT.contains(&name)
}

/// The expected macOS target gate, whitespace-stripped form.
const MACOS_TARGET: &str = concat!("cfg", "(target_os=", "\"macos\")");

/// True when a `cargo metadata` dependency `target` is the macOS gate.
fn is_macos_target(target: &str) -> bool {
    target.split_whitespace().collect::<String>() == MACOS_TARGET
}

/// Bridge-crate token in Rust code.
const NEEDLE_BRIDGE: &str = concat!("objc", "2");
/// Core Foundation token in Rust code.
const NEEDLE_CF: &str = concat!("core", "_foundation");
/// Core Graphics token in Rust code.
const NEEDLE_CG: &str = concat!("core", "_graphics");
/// Target-OS `cfg` attribute token.
const NEEDLE_CFG: &str = concat!("cfg", "(target_os");
/// Target-OS `cfg!` macro token.
const NEEDLE_CFG_MACRO: &str = concat!("cfg!", "(target_os");

/// Rule-3 tokens: none may appear outside `crates/lightamer-apple/`.
pub const NEEDLES: &[&str] = &[
    NEEDLE_BRIDGE,
    NEEDLE_CF,
    NEEDLE_CG,
    NEEDLE_CFG,
    NEEDLE_CFG_MACRO,
];

/// Source roots scanned by rule 3, relative to the workspace root.
const SCAN_ROOTS: &[&str] = &["crates", "apps"];
/// Subtree exempt from rule 3, relative to the workspace root.
const SKIP_PREFIX: &str = "crates/lightamer-apple";

/// One direct dependency edge: manifest name plus optional target gate.
#[derive(Debug, Clone)]
pub struct Dep {
    /// Dependency name as in the manifest.
    pub name: String,
    /// `target` field of `cargo metadata` (`None` = unqualified table).
    pub target: Option<String>,
}

/// One workspace crate and its direct edges.
#[derive(Debug, Clone)]
pub struct Crate {
    /// Package name.
    pub name: String,
    /// Direct dependencies.
    pub deps: Vec<Dep>,
}

/// One Apple-boundary violation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Violation {
    /// Rule 1: an Apple binding outside `lightamer-apple`.
    AppleDepOutsideApple {
        /// Offending crate.
        krate: String,
        /// Apple binding dependency.
        dep: String,
    },
    /// Rule 2: an Apple binding in `lightamer-apple` outside the macOS target table.
    AppleDepNotTargetGated {
        /// Offending crate (always `lightamer-apple`).
        krate: String,
        /// Apple binding dependency.
        dep: String,
        /// Actual target gate (`None` = plain `[dependencies]`).
        target: Option<String>,
    },
    /// Rule 3: a forbidden Apple token in scanned sources.
    ForbiddenSourceToken {
        /// File relative to the workspace root.
        file: String,
        /// 1-based line number.
        line: usize,
        /// Token found.
        token: String,
    },
}

impl std::fmt::Display for Violation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Violation::AppleDepOutsideApple { krate, dep } => {
                write!(
                    f,
                    "{krate}: direct dependency `{dep}` is an Apple binding; only lightamer-apple may depend on it"
                )
            }
            Violation::AppleDepNotTargetGated { krate, dep, target } => {
                let gate = target.as_deref().unwrap_or("plain [dependencies]");
                write!(
                    f,
                    "{krate}: Apple binding `{dep}` must sit under the macOS target table (found: {gate})"
                )
            }
            Violation::ForbiddenSourceToken { file, line, token } => {
                write!(f, "{file}:{line}: forbidden Apple token `{token}`")
            }
        }
    }
}

/// Rules 1–2 over the dependency model. Violations sorted for stable output.
pub fn check(crates: &[Crate]) -> Vec<Violation> {
    let mut out = Vec::new();
    for c in crates {
        for d in &c.deps {
            if !is_apple_binding(&d.name) {
                continue;
            }
            if c.name == "lightamer-apple" {
                let gated = d.target.as_deref().is_some_and(is_macos_target);
                if !gated {
                    out.push(Violation::AppleDepNotTargetGated {
                        krate: c.name.clone(),
                        dep: d.name.clone(),
                        target: d.target.clone(),
                    });
                }
            } else {
                out.push(Violation::AppleDepOutsideApple {
                    krate: c.name.clone(),
                    dep: d.name.clone(),
                });
            }
        }
    }
    out.sort_by_key(std::string::ToString::to_string);
    out.dedup();
    out
}

/// Build the model from `cargo metadata --format-version 1 --no-deps`.
/// Only `packages[].name` and each `dependencies[]` (`name`, `target`) are
/// read; the rest is skipped. Rule 4: malformed input is an error, never a
/// pass.
pub fn from_metadata(text: &str) -> Result<Vec<Crate>, String> {
    let root = Reader::new(text).parse()?;
    let pkgs = root
        .get("packages")
        .and_then(Json::as_array)
        .ok_or_else(|| "metadata: no packages array".to_owned())?;
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
                let dname = d.get("name").and_then(Json::as_str).unwrap_or_default();
                let target = match d.get("target") {
                    None | Some(Json::Null) => None,
                    Some(Json::Str(s)) => Some(s.clone()),
                    Some(_) => {
                        return Err(format!(
                            "metadata: dependency target of `{dname}` is not a string"
                        ));
                    }
                };
                deps.push(Dep {
                    name: dname.to_owned(),
                    target,
                });
            }
        }
        out.push(Crate { name, deps });
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}

/// Rule 3 over the working tree. Returns violations plus the scanned `.rs`
/// file count. Unreadable files fail the check (rule-4 spirit: never pass on
/// what could not be read).
pub fn scan_sources(root: &Path) -> Result<(Vec<Violation>, usize), String> {
    let skip = root.join(SKIP_PREFIX);
    let mut violations = Vec::new();
    let mut files = 0;
    for scan in SCAN_ROOTS {
        collect_dir(&root.join(scan), &skip, root, &mut violations, &mut files)?;
    }
    violations.sort_by_key(std::string::ToString::to_string);
    violations.dedup();
    Ok((violations, files))
}

fn collect_dir(
    dir: &Path,
    skip: &Path,
    root: &Path,
    violations: &mut Vec<Violation>,
    files: &mut usize,
) -> Result<(), String> {
    if dir == skip {
        return Ok(());
    }
    let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)
        .map_err(|e| format!("scan {}: {e}", dir.display()))?
        .map(|entry| entry.map(|item| item.path()))
        .collect::<Result<_, _>>()
        .map_err(|e| format!("scan {}: {e}", dir.display()))?;
    entries.sort();
    for path in entries {
        if path == *skip {
            continue;
        }
        let kind = std::fs::symlink_metadata(&path)
            .map_err(|e| format!("scan {}: {e}", path.display()))?;
        if kind.is_dir() {
            collect_dir(&path, skip, root, violations, files)?;
        } else if kind.is_file() && path.extension().is_some_and(|ext| ext == "rs") {
            *files += 1;
            scan_file(&path, root, violations)?;
        }
    }
    Ok(())
}

fn scan_file(path: &Path, root: &Path, violations: &mut Vec<Violation>) -> Result<(), String> {
    let text =
        std::fs::read_to_string(path).map_err(|e| format!("scan {}: {e}", path.display()))?;
    let shown = path
        .strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .into_owned();
    for (index, line) in text.lines().enumerate() {
        for needle in NEEDLES {
            if line.contains(needle) {
                violations.push(Violation::ForbiddenSourceToken {
                    file: shown.clone(),
                    line: index + 1,
                    token: (*needle).to_owned(),
                });
            }
        }
    }
    Ok(())
}

/// Runs all four rules: metadata rules plus the source scan.
pub(crate) fn run() -> Result<(), String> {
    let crates = from_metadata(&super::metadata_text()?)?;
    let root = super::iop_order::workspace_root();
    let (mut violations, files) = scan_sources(&root)?;
    violations.extend(check(&crates));
    violations.sort_by_key(std::string::ToString::to_string);
    violations.dedup();
    if violations.is_empty() {
        println!(
            "OK: {} crates, {files} rust files, no Apple-boundary violations.",
            crates.len()
        );
        Ok(())
    } else {
        println!("{} violation(s):", violations.len());
        for v in &violations {
            println!("  - {v}");
        }
        Err(format!("{} Apple-boundary violation(s)", violations.len()))
    }
}

// --- Minimal JSON reader: exactly what `from_metadata` needs. ---
//
// Numbers, booleans, and null all decode to `Json::Null`: only strings and
// structure are observable, which is all the model reads.

#[derive(Debug, Clone, PartialEq)]
enum Json {
    Null,
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
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

    fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
            _ => None,
        }
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

    fn parse(&mut self) -> Result<Json, String> {
        let value = self.value()?;
        self.ws();
        if self.pos != self.bytes.len() {
            return Err(format!("metadata: trailing bytes at {}", self.pos));
        }
        Ok(value)
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn ws(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.pos += 1;
        }
    }

    fn expect(&mut self, byte: u8, what: &str) -> Result<(), String> {
        if self.peek() == Some(byte) {
            self.pos += 1;
            Ok(())
        } else {
            Err(format!("metadata: want {what} at {}", self.pos))
        }
    }

    fn value(&mut self) -> Result<Json, String> {
        self.ws();
        match self.peek() {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => Ok(Json::Str(self.string()?)),
            Some(b't') => self.word("true"),
            Some(b'f') => self.word("false"),
            Some(b'n') => self.word("null"),
            Some(b'-' | b'0'..=b'9') => self.number(),
            _ => Err(format!("metadata: unexpected value at {}", self.pos)),
        }
    }

    fn word(&mut self, word: &str) -> Result<Json, String> {
        if self.bytes.get(self.pos..self.pos + word.len()) == Some(word.as_bytes()) {
            self.pos += word.len();
            Ok(Json::Null)
        } else {
            Err(format!("metadata: bad literal at {}", self.pos))
        }
    }

    fn number(&mut self) -> Result<Json, String> {
        let start = self.pos;
        while matches!(
            self.peek(),
            Some(b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9')
        ) {
            self.pos += 1;
        }
        if self.pos == start {
            return Err(format!("metadata: bad number at {}", self.pos));
        }
        Ok(Json::Null)
    }

    fn array(&mut self) -> Result<Json, String> {
        self.expect(b'[', "'['")?;
        let mut items = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(Json::Arr(items));
        }
        loop {
            items.push(self.value()?);
            self.ws();
            match self.peek() {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b']') => {
                    self.pos += 1;
                    return Ok(Json::Arr(items));
                }
                _ => return Err(format!("metadata: want ',' or ']' at {}", self.pos)),
            }
        }
    }

    fn object(&mut self) -> Result<Json, String> {
        self.expect(b'{', "'{'")?;
        let mut fields = Vec::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(Json::Obj(fields));
        }
        loop {
            if self.peek() != Some(b'"') {
                return Err(format!("metadata: want string key at {}", self.pos));
            }
            let key = self.string()?;
            self.ws();
            self.expect(b':', "':'")?;
            let value = self.value()?;
            fields.push((key, value));
            self.ws();
            match self.peek() {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(Json::Obj(fields));
                }
                _ => return Err(format!("metadata: want ',' or '}}' at {}", self.pos)),
            }
        }
    }

    fn string(&mut self) -> Result<String, String> {
        self.expect(b'"', "'\"'")?;
        let mut buf: Vec<u8> = Vec::new();
        loop {
            match self.peek() {
                None => return Err(format!("metadata: unterminated string at {}", self.pos)),
                Some(b'"') => {
                    self.pos += 1;
                    return String::from_utf8(buf)
                        .map_err(|_| format!("metadata: bad UTF-8 at {}", self.pos));
                }
                Some(b'\\') => {
                    self.pos += 1;
                    match self.peek() {
                        Some(byte @ (b'"' | b'\\' | b'/')) => {
                            buf.push(byte);
                            self.pos += 1;
                        }
                        Some(b'b') => {
                            buf.push(0x08);
                            self.pos += 1;
                        }
                        Some(b'f') => {
                            buf.push(0x0C);
                            self.pos += 1;
                        }
                        Some(b'n') => {
                            buf.push(b'\n');
                            self.pos += 1;
                        }
                        Some(b'r') => {
                            buf.push(b'\r');
                            self.pos += 1;
                        }
                        Some(b't') => {
                            buf.push(b'\t');
                            self.pos += 1;
                        }
                        Some(b'u') => {
                            self.pos += 1;
                            let high = self.hex4()?;
                            let scalar = if (0xD800..0xDC00).contains(&high) {
                                if self.bytes.get(self.pos..self.pos + 2) == Some(b"\\u") {
                                    self.pos += 2;
                                    let low = self.hex4()?;
                                    if !(0xDC00..0xE000).contains(&low) {
                                        return Err(format!(
                                            "metadata: bad low surrogate at {}",
                                            self.pos
                                        ));
                                    }
                                    0x1_0000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                                } else {
                                    return Err(format!(
                                        "metadata: lone high surrogate at {}",
                                        self.pos
                                    ));
                                }
                            } else {
                                high
                            };
                            let ch = char::from_u32(scalar)
                                .ok_or_else(|| format!("metadata: bad scalar at {}", self.pos))?;
                            let mut tmp = [0u8; 4];
                            buf.extend_from_slice(ch.encode_utf8(&mut tmp).as_bytes());
                        }
                        _ => return Err(format!("metadata: bad escape at {}", self.pos)),
                    }
                }
                Some(byte) if byte < 0x20 => {
                    return Err(format!("metadata: control byte at {}", self.pos));
                }
                Some(byte) => {
                    buf.push(byte);
                    self.pos += 1;
                }
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let digits = self
            .bytes
            .get(self.pos..self.pos + 4)
            .ok_or_else(|| format!("metadata: truncated unicode escape at {}", self.pos))?;
        let mut value: u32 = 0;
        for digit in digits {
            value = value * 16
                + u32::from(match digit {
                    b'0'..=b'9' => digit - b'0',
                    b'a'..=b'f' => digit - b'a' + 10,
                    b'A'..=b'F' => digit - b'A' + 10,
                    _ => return Err(format!("metadata: bad hex digit at {}", self.pos)),
                });
        }
        self.pos += 4;
        Ok(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn apple_dep_name() -> String {
        format!("{OBJC2_PREFIX}-metal")
    }

    fn macos_gate() -> String {
        format!("{NEEDLE_CFG} = \"macos\")")
    }

    fn one_crate(name: &str, deps: &[(&str, Option<&str>)]) -> Crate {
        Crate {
            name: name.to_owned(),
            deps: deps
                .iter()
                .map(|(dep, target)| Dep {
                    name: (*dep).to_owned(),
                    target: target.map(str::to_owned),
                })
                .collect(),
        }
    }

    #[test]
    fn rule1_flags_apple_dep_outside_apple() {
        let metal = apple_dep_name();
        let graphs = [
            vec![one_crate("lightamer-engine", &[(metal.as_str(), None)])],
            vec![one_crate(
                "lightamer-cli",
                &[(metal.as_str(), Some("cfg(unix)"))],
            )],
            vec![one_crate("lightamer-history", &[("metal", None)])],
        ];
        for graph in &graphs {
            let found = check(graph);
            assert_eq!(found.len(), 1, "{found:?}");
            assert!(
                matches!(
                    &found[0],
                    Violation::AppleDepOutsideApple { krate, dep }
                    if graph[0].name == *krate && graph[0].deps[0].name == *dep
                ),
                "{found:?}"
            );
            let message = found[0].to_string();
            assert!(message.contains(&graph[0].name), "{message}");
            assert!(message.contains(&graph[0].deps[0].name), "{message}");
        }
    }

    #[test]
    fn rule1_ignores_plain_deps() {
        let graph = vec![
            one_crate(
                "lightamer-engine",
                &[("serde", None), ("lightamer-apple", None)],
            ),
            one_crate("lightamer-cli", &[("png", None)]),
        ];
        assert_eq!(check(&graph), Vec::new());
    }

    #[test]
    fn rule2_requires_macos_gate_inside_apple() {
        let metal = apple_dep_name();
        let gate = macos_gate();
        let ok = vec![one_crate(
            "lightamer-apple",
            &[(metal.as_str(), Some(gate.as_str()))],
        )];
        assert!(check(&ok).is_empty(), "{:?}", check(&ok));
        for target in [None, Some("cfg(unix)"), Some("cfg(windows)")] {
            let graph = vec![one_crate("lightamer-apple", &[(metal.as_str(), target)])];
            let found = check(&graph);
            assert_eq!(found.len(), 1, "{found:?}");
            assert!(
                matches!(
                    &found[0],
                    Violation::AppleDepNotTargetGated { krate, dep, .. }
                    if krate == "lightamer-apple" && dep == &metal
                ),
                "{found:?}"
            );
            let message = found[0].to_string();
            assert!(message.contains("lightamer-apple"), "{message}");
            assert!(message.contains(&metal), "{message}");
        }
    }

    #[test]
    fn rule3_scan_finds_tokens_outside_exempt_dir() {
        let root = std::env::temp_dir().join(format!("ab-scan-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let victim = root.join("crates/victim/src/lib.rs");
        let tool = root.join("apps/tool/main.rs");
        let skipped = root.join("crates/lightamer-apple/src/macos.rs");
        let notes = root.join("crates/victim/NOTES.md");
        for path in [&victim, &tool, &skipped, &notes] {
            std::fs::create_dir_all(path.parent().expect("parent")).expect("mkdir");
        }
        // Victim lines are built from the needles (which are themselves
        // assembled without literals); the live negative test proves they
        // match real-world spellings.
        std::fs::write(
            &victim,
            format!("use {NEEDLE_BRIDGE}::rc::Retained;\nfn f() {{}}\n"),
        )
        .expect("write");
        std::fs::write(
            &tool,
            format!("#[{NEEDLE_CFG} = \"macos\")]\nfn g() {{}}\n"),
        )
        .expect("write");
        std::fs::write(&skipped, format!("use {NEEDLE_BRIDGE}::rc::Retained;\n")).expect("write");
        std::fs::write(&notes, format!("mentions {NEEDLE_BRIDGE}\n")).expect("write");
        let (found, files) = scan_sources(&root).expect("scan");
        std::fs::remove_dir_all(&root).expect("cleanup");
        assert_eq!(files, 2);
        assert_eq!(found.len(), 2, "{found:?}");
        for hit in &found {
            let message = hit.to_string();
            assert!(message.contains(".rs:1:"), "{message}");
            assert!(
                message.contains(NEEDLE_BRIDGE) || message.contains(NEEDLE_CFG),
                "{message}"
            );
        }
        assert!(found.iter().any(|hit| hit.to_string().contains("victim")));
        assert!(
            found
                .iter()
                .any(|hit| hit.to_string().contains("apps/tool"))
        );
    }

    #[test]
    fn rule4_metadata_failures_are_errors() {
        assert!(from_metadata("{}").is_err());
        assert!(from_metadata("{oops").is_err());
        assert!(from_metadata("{\"packages\":[{\"dependencies\":[]}]}").is_err());
        assert!(
            from_metadata("{\"packages\":[]}")
                .expect("empty")
                .is_empty()
        );
    }

    #[test]
    fn metadata_shape_parses_names_and_gates() {
        let metal = apple_dep_name();
        let gate = macos_gate();
        let gate_json = gate.replace('"', "\\\"");
        let text = format!(
            "{{\"packages\":[{{\"name\":\"lightamer-apple\",\"dependencies\":[{{\"name\":\"{metal}\",\"kind\":null,\"target\":\"{gate_json}\"}},{{\"name\":\"serde\",\"kind\":null,\"target\":null}}]}},{{\"name\":\"lightamer-cli\",\"dependencies\":[]}}]}}"
        );
        let crates = from_metadata(&text).expect("parse");
        assert_eq!(crates.len(), 2);
        let apple = crates
            .iter()
            .find(|c| c.name == "lightamer-apple")
            .expect("apple");
        assert_eq!(apple.deps.len(), 2);
        assert_eq!(apple.deps[0].name, metal);
        assert_eq!(apple.deps[0].target.as_deref(), Some(gate.as_str()));
        assert_eq!(apple.deps[1].target, None);
    }

    #[test]
    fn binding_names_match_intent() {
        assert!(is_apple_binding(&apple_dep_name()));
        assert!(is_apple_binding(OBJC2_PREFIX));
        for exact in APPLE_EXACT {
            assert!(is_apple_binding(exact), "{exact}");
        }
        assert!(is_apple_binding(&format!("{OBJC2_PREFIX}ness")));
        assert!(!is_apple_binding("serde"));
        assert!(!is_apple_binding("png"));
        assert!(!is_apple_binding("lightamer-apple"));
        // "objc" without the trailing digit is its own legacy crate, still listed.
        assert!(is_apple_binding("objc"));
        assert!(!is_apple_binding("obj"));
    }

    #[test]
    fn needles_assemble_without_typos() {
        // Component checks that never spell a full token literally.
        assert_eq!(NEEDLES.len(), 5);
        assert_eq!(OBJC2_PREFIX.chars().count(), 5);
        assert!(NEEDLE_BRIDGE.starts_with("objc"));
        assert!(NEEDLE_BRIDGE.ends_with('2'));
        assert!(NEEDLE_CF.starts_with("core"));
        assert!(NEEDLE_CF.ends_with("foundation"));
        assert!(NEEDLE_CG.starts_with("core"));
        assert!(NEEDLE_CG.ends_with("graphics"));
        assert!(NEEDLE_CFG.starts_with("cfg"));
        assert!(NEEDLE_CFG.ends_with("target_os"));
        assert!(NEEDLE_CFG_MACRO.starts_with("cfg!"));
        assert!(MACOS_TARGET.starts_with("cfg"));
        assert!(MACOS_TARGET.ends_with("macos\")"));
        assert!(is_macos_target(&macos_gate()));
        assert!(!is_macos_target("cfg(unix)"));
        assert!(!is_macos_target("cfg(windows)"));
    }

    #[test]
    fn json_reader_handles_escapes_and_shapes() {
        let parsed = Reader::new(
            "{\"a\":\"x\\\"y\\\\z\\/\\n\\u00e9\",\"b\":[1,-2.5e3,true,false,null,{}],\"c\":{}}",
        )
        .parse()
        .expect("parse");
        assert_eq!(
            parsed.get("a").and_then(Json::as_str),
            Some("x\"y\\z/\n\u{e9}")
        );
        assert_eq!(
            parsed.get("b").and_then(Json::as_array).map(<[_]>::len),
            Some(6)
        );
        assert!(Reader::new("{\"a\": }").parse().is_err());
        assert!(Reader::new("{\"a\": \"\u{1}leak\"}").parse().is_err());
        assert!(Reader::new("[1,]").parse().is_err());
    }
}
