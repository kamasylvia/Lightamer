#!/usr/bin/env python3
"""zh-audit.py — String Catalog (Localizable.xcstrings) audit for Lightamer.

Plan M2-3-4 T1 / KD-1. Bidirectional key reconciliation between the Swift
source tree and the String Catalog, plus zh completeness and locale-code
discipline assertions.

Scan domain
    Every ``*.swift`` file under the source roots (default: the repository
    root, skipping Tests, build and hidden directories).

Key extraction (assertion 1 — source keys must exist in the catalog)
    Call shapes that produce *static keys*:
      1. ``String(localized: "K"``            — K must match ``^[a-z][a-z0-9_]+$``
      1b. the continuation form ``\n    localized: "K",`` (label on its own
          line, the M2-3 P2/P3 call style)
      1c. the NEXT-LINE continuation form (V15 hardening): ``localized:``
          ends the line and the key literal opens the following scanned
          line — ``String(localized:\n        "K"`` (the per-line regexes
          see neither shape; found live in GlobalSearchDialog /
          LightamerApp toasts)
      2. ``Text("K")``                         — same shape (LocalizableStringKey
                                                literal, not prose)
    Excluded: ``Text(verbatim:`` lines and comment lines (``//``, block
    comments, doc comments). The snake-shape filter is the prose false-positive
    guard (KD-1).

Interpolated localization keys (assertion 5 — V16; V17 extends to Text)
    ``String(localized: "K \\(expr)"`` extracts at build time as a FORMAT
    key (``"K %@"`` / ``"K %lld"`` … — the xcstrings convention). The
    scanner records these as ``interp_sites`` keyed by the static prefix.
    V17 adds the SwiftUI ``Text("K \\(expr)")`` interpolation family (the
    same build-time FORMAT extraction, single-line + the ``Text(``
    end-of-line continuation form) to the same gate. Assertion 5 requires
    every such key K to own a catalog FORMAT-VARIANT key starting with
    ``K + " "``. The bare static key ``K`` never satisfies the gate: a
    catalog entry that only carries ``K`` (its value holding the
    placeholder) means the runtime lookup of the variant key fails and the
    UI falls back to the raw key text (the M2-9 F-2 live defect family).

Specifier deep-checking (assertion 6 — V17)
    For every interpolation key whose interpolated argument expressions are
    statically derivable, the gate compares the DERIVED argument spec
    sequence against the catalog variant's spec sequence IN ORDER (length
    + per-position). Types map: the whole Int family (Int/Int32/Int64/
    UInt…) → ``%lld``; Float and Double share ``%lf``; String → ``%@``.
    The derivation supply side is deliberately narrow (false-MISMATCH
    guard): annotated ``let``/``var`` declarations, function/init
    parameter declarations, integer/float/string literals, ``Int(…)``
    wrapper calls (covers ``.rounded()`` chain tails), and simple depth-0
    arithmetic/ternary/nil-coalescing propagation. Everything else —
    member chains (``progress.completed``), un-annotated closure
    parameters, cross-file inference, generics, protocol types — is
    EXEMPT: reported, never judged (no false positives). MISMATCH is a
    violation: a variant exists but its ordered spec sequence differs
    from the derived one, so the runtime lookup misses (the D-5 live
    defect signature: Float interpolation vs an ``%lld``-only catalog).

Coverage (assertion 2 — catalog keys must be referenced or exempted)
    A catalog key is *covered* when any of the following holds:
      a. it was extracted as a static key (shape 1/2 above);
      b. it appears verbatim as a quoted string literal anywhere in the
         scanned source (covers bare ``LocalizedStringKey`` literals such as
         ``case .grid: "browser_mode_grid"`` or ``labelKey:`` parameters);
      c. it is covered by a *dynamic key family*: the source contains an
         interpolated literal whose static prefix is ``P`` (``"P\\(expr)"``)
         and the key equals ``P`` or starts with ``P + "_"`` or ``P + " "``.
         This covers format-specifier catalog keys such as
         ``"filter_chip_rating %lld"`` produced by
         ``String(localized: "filter_chip_rating \\(v)")``.
      d. it is listed in the allowlist (built-in defaults plus ``--allowlist``).
    Everything else is an orphan key and fails the audit.

Completeness (assertion 3) — every catalog key has a non-empty ``zh`` value.
Locale discipline (assertion 4) — catalog locale codes ⊆ {en, zh}; any
    ``zh-Hans`` (or other second code) fails (D9: no second Chinese code).

Modes
    --report    human-readable report (exit 0 unless IO/format errors)
    --check     machine check: any violation prints key-level detail, exit 1;
                all pass → exit 0
    --self-test run the built-in golden fixtures (violation cases + one
                clean case + the V17 eight-case golden bundle) and verify
                the scanner detects each; exit 0/1

Extra flags
    --allowlist FILE   one catalog key or ``prefix*`` per line, '#' comments;
                       exempts keys from assertion 2 only (KD-1: allowlist is
                       not an escape hatch — every entry needs a DECISIONS
                       attribution)
    --catalog PATH     catalog path (default Resources/Localizable.xcstrings)
    --root PATH        source scan root (default: repository root inferred
                       from this script's location)

Run under uv per the toolchain red line:
    uv run python3 Scripts/zh-audit.py --check
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass, field

# ─────────────────────────────────────────────────────────────────────────────
# Built-in allowlist (assertion-2 exemptions only).
#
# Every entry is a dynamic/dead catalog family with its attribution (also
# mirrored in M2-3-4-DECISIONS.md). Format: one entry per line inside this
# tuple; lines starting with '#' are comments; ``prefix*`` matches every
# catalog key starting with ``prefix``.
#
# Families:
#  * Format-specifier keys produced through interpolated localization
#    literals are NOT listed here — the scanner covers them mechanically
#    through dynamic key families (rule c). Only keys with no surviving
#    static/quoted/dynamic reference are allowlisted.
#  * DEAD-legacy keys: catalog entries from retired M1 UI paths whose call
#    sites no longer exist. Code and catalog stay per the code-preservation
#    ruling (M2LIB-06); catalog pruning is out of scope for M2-3-4.
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_ALLOWLIST: tuple[str, ...] = (
    # Dead catalog keys (M2-3-4-DECISIONS D-allow). None of these has any
    # surviving source reference (static, quoted-literal, or dynamic family);
    # they are retained catalog entries from retired M1 UI paths. Catalog
    # pruning is out of scope for M2-3-4 (code-preservation ruling M2LIB-06;
    # "found translation errors are not fixed in passing" plan risk clause).
    "a11y_inspector_label",          # retired M1 inspector a11y hint
    "inspector_no_modules",          # retired M1 empty-state title
    "inspector_no_modules_body",     # retired M1 empty-state body
    "module_bilateral",              # disabled iop module label (M2-1 收窄)
    "settings_placeholder",          # superseded by settings_placeholder_*
    "smart_album_no_chips_hint",     # retired M1 smart-album hint
    "toast_session_index_failed",    # retired M1 session-index toast
    "panel_lens_apply_match",        # retired LENS-02 T4 (Apply absorbed by the profile browser selection)
    # Retired-in-place keys (M9-4 T2, D-M9SP-7③): the film-era migration
    # copy superseded by the neutral panel_process_migrate_* family — the
    # catalog entries STAY (bytes untouched), the sources reference only
    # the neutral family.
    "panel_film_migrate_title",
    "panel_film_migrate_body",
    "panel_film_migrate_button",
    "panel_film_migrate_cancel",
    "panel_film_migrate_confirm",
)

KEY_SHAPE = re.compile(r"^[a-z][a-z0-9_]+$")
LOCATED_RE = re.compile(r'\bString\(\s*localized:\s*"([A-Za-z0-9_]+)"')
# Continuation form: `String(\n    localized: "K",` — the label sits on its
# own line without the `String(` prefix (M2-3 P2/P3 call style).
LOCATED_CONT_RE = re.compile(r'\blocalized:\s*"([A-Za-z0-9_]+)"')
TEXT_RE = re.compile(r'\bText\(\s*"([A-Za-z0-9_]+)"\s*[,)]')
INTERP_PREFIX_RE = re.compile(r'"([a-z][a-z0-9_]+)\s*\\\(')
LITERAL_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# V15 hardening (form 1c): a line ENDING with `localized:` (optionally as
# `String(localized:`) hands the key to the NEXT scanned line; that line
# must OPEN with the key literal.
PENDING_LOCALIZED_RE = re.compile(r'(?:String\(\s*)?localized:\s*$')
LEAD_LITERAL_RE = re.compile(r'^"([A-Za-z0-9_]+)"')
# V16/V17 (assertions 5+6): interpolated localization literals. Same-line
# `String(localized: "K \(expr)"`, the form-1c continuation line OPENING
# with an interpolated literal, and (V17) the SwiftUI `Text("K \(expr)"`
# family — same-line plus the `Text(` end-of-line continuation. The
# extracted key is the literal's static prefix; the build-time format
# variant is `K <specifier>`.
LOCATED_INTERP_RE = re.compile(r'\bString\(\s*localized:\s*"([A-Za-z0-9_]+)\s*\\\(')
LEAD_INTERP_RE = re.compile(r'^"([A-Za-z0-9_]+)\s*\\\(')
TEXT_INTERP_RE = re.compile(r'\bText\(\s*"([A-Za-z0-9_]+)\s*\\\(')
TEXT_OPEN_RE = re.compile(r'\bText\($')

SKIP_DIR_PARTS = {
    "Tests",
    "DerivedData",
    "Derived",
    ".build",
    ".tuist",
    ".git",
    ".work",
    ".planning",
    ".github",
    ".zcode",
}
SKIP_DIR_SUFFIXES = (".xcodeproj", ".xcworkspace", ".app")

# V17 specifier deep-checking: type → format-specifier mapping. The whole
# Int family shares `%lld` (Int32 pids and Int counts alike); Float and
# Double share `%lf`; String maps to `%@`.
INT_FAMILY = frozenset(
    {"Int", "Int8", "Int16", "Int32", "Int64",
     "UInt", "UInt8", "UInt16", "UInt32", "UInt64"}
)
TYPE_SPEC: dict[str, str] = {t: "%lld" for t in INT_FAMILY}
TYPE_SPEC["Float"] = "%lf"
TYPE_SPEC["Double"] = "%lf"
TYPE_SPEC["String"] = "%@"

# Supply-side declaration shapes (per-file symbol table). Annotated
# let/var only — type inference from the RHS is out of scope (EXEMPT).
LET_DECL_RE = re.compile(
    r'\b(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*'
    r'([A-Za-z_]\w*(?:\?)?)\b'
)
FUNC_HEAD_RE = re.compile(r'\b(?:func|init)\s+[A-Za-z_]\w*\s*\(')


@dataclass
class InterpSite:
    """One interpolated localization literal site (V16/V17)."""

    path: str
    family: str                       # "localized" | "text"
    exprs: tuple[str, ...] | None     # None = literal unterminated on its
                                      # line — deep-check exempt (the V16
                                      # line-based scan cannot see the rest).


@dataclass
class ScanResult:
    static_keys: dict[str, list[str]] = field(default_factory=dict)
    literals: set[str] = field(default_factory=set)
    interp_prefixes: set[str] = field(default_factory=set)
    # V16+V17: interpolated localization sites — key → sites, covering the
    # String(localized:) family (same-line + form-1c continuation) AND the
    # SwiftUI Text family (same-line + Text( continuation).
    interp_sites: dict[str, list[InterpSite]] = field(default_factory=dict)
    # Per-file annotated-declaration symbol tables (V17 derivation supply
    # side): path → name → set of candidate types.
    symbols: dict[str, dict[str, set[str]]] = field(default_factory=dict)

    def interp_paths(self, key: str) -> list[str]:
        seen: list[str] = []
        for site in self.interp_sites.get(key, ()):
            if site.path not in seen:
                seen.append(site.path)
        return seen


@dataclass
class AuditViolations:
    missing: list[str] = field(default_factory=list)       # assertion 1
    orphans: list[str] = field(default_factory=list)       # assertion 2
    zh_missing: list[str] = field(default_factory=list)    # assertion 3
    code_violations: list[str] = field(default_factory=list)  # assertion 4
    interp_missing_variant: list[str] = field(default_factory=list)  # assertion 5
    interp_spec_mismatch: list[str] = field(default_factory=list)    # assertion 6

    @property
    def total(self) -> int:
        return (
            len(self.missing)
            + len(self.orphans)
            + len(self.zh_missing)
            + len(self.code_violations)
            + len(self.interp_missing_variant)
            + len(self.interp_spec_mismatch)
        )

    def ok(self) -> bool:
        return self.total == 0


# ─────────────────────────────────────────────────────────────────────────────
# Paren/interpolation parsing helpers (V17).
# ─────────────────────────────────────────────────────────────────────────────

def match_paren(text: str, open_pos: int) -> int | None:
    """Index of the paren closing ``open_pos``, or None if unbalanced."""
    depth = 0
    for i in range(open_pos, len(text)):
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
    return None


def parse_interp_literal(line: str, open_pos: int) -> tuple[str, ...] | None:
    """Extract the interpolated expressions of a literal.

    ``open_pos`` points at the ``(`` of the FIRST ``\\(``. Walks
    interpolation → plain-text → interpolation … until the literal's
    closing quote. Returns None when the literal does not close on this
    line (the caller then keeps the site deep-check-exempt).
    """
    exprs: list[str] = []
    pos = open_pos
    while True:
        end = match_paren(line, pos)
        if end is None:
            return None
        exprs.append(line[pos + 1:end])
        j = end + 1
        while j < len(line):
            c = line[j]
            if c == "\\" and j + 1 < len(line) and line[j + 1] == "(":
                break
            if c == '"':
                return tuple(exprs)
            j += 1
        else:
            return None
        pos = j + 1


def collect_declarations(source: str) -> dict[str, set[str]]:
    """Per-file symbol table from annotated let/var + func/init parameters."""
    symbols: dict[str, set[str]] = {}
    known = set(TYPE_SPEC)

    def record(name: str, type_name: str) -> None:
        base = type_name.rstrip("?").strip()
        if base in known:
            symbols.setdefault(name, set()).add(base)

    for m in LET_DECL_RE.finditer(source):
        record(m.group(1), m.group(2))

    for m in FUNC_HEAD_RE.finditer(source):
        open_pos = m.end() - 1
        close = match_paren(source, open_pos)
        if close is None:
            continue
        params = source[open_pos + 1:close]
        # Split the parameter list on depth-0 commas.
        depth = 0
        start = 0
        pieces: list[str] = []
        for i, c in enumerate(params):
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == "," and depth == 0:
                pieces.append(params[start:i])
                start = i + 1
        pieces.append(params[start:])
        for piece in pieces:
            piece = piece.strip()
            if not piece or piece.startswith("@"):
                # Best-effort: strip attributes/argument labels; take the
                # trailing `name: Type` pair.
                pass
            pm = re.search(r'([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*(?:\?)?)\s*$',
                           piece)
            if pm:
                record(pm.group(1), pm.group(2))
    return symbols


def derive_type(expr: str, symbols: dict[str, set[str]]) -> str | None:
    """Conservatively derive the static type of one interpolated argument.

    Returns the mapped base type (a TYPE_SPEC key) or None when the
    expression is outside the derivation supply face (EXEMPT — never a
    guess; false MISMATCH is the failure mode this guard exists for).
    """
    e = expr.strip()
    if not e:
        return None
    # Whole-expression parentheses.
    if e.startswith("(") and (close := match_paren(e, 0)) == len(e) - 1:
        return derive_type(e[1:-1], symbols)
    # Typed wrapper calls — `Int(…)`, `Int32(…)`, `Double(…)`, `String(…)`.
    wm = re.match(r'^([A-Za-z_]\w*)\s*\(', e)
    if wm:
        head = wm.group(1)
        if head in TYPE_SPEC and match_paren(e, wm.end() - 1) == len(e) - 1:
            return head
    # Literals: integer → Int, float → Double, string → String.
    if re.match(r'^\d+$', e):
        return "Int"
    if re.match(r'^\d+\.\d*$', e):
        return "Double"
    if len(e) >= 2 and e.startswith('"') and e.endswith('"'):
        return "String"
    # Bare identifier — symbol-table lookup (single candidate type only).
    if re.match(r'^[A-Za-z_]\w*$', e):
        types = symbols.get(e)
        if types and len(types) == 1:
            return next(iter(types))
        return None
    # Depth-0 binary propagation: arithmetic (+ - * / %), nil-coalescing
    # (??), ternary (?:). Both sides must derive and agree.
    for op in ("??", "+", "-", "*", "/", "%"):
        depth = 0
        i = 0
        while i < len(e):
            c = e[i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif depth == 0 and e.startswith(op, i):
                left = derive_type(e[:i], symbols)
                right = derive_type(e[i + len(op):], symbols)
                if left is not None and left == right:
                    return left
                return None
            elif c == "?" and depth == 0:
                # Ternary: `cond ? a : b` — split on the matching ':' at
                # depth 0.
                colon = None
                depth2 = 0
                for j in range(i + 1, len(e)):
                    c2 = e[j]
                    if c2 == "(":
                        depth2 += 1
                    elif c2 == ")":
                        depth2 -= 1
                    elif c2 == ":" and depth2 == 0:
                        colon = j
                        break
                if colon is None:
                    return None
                left = derive_type(e[i + 1:colon], symbols)
                right = derive_type(e[colon + 1:], symbols)
                if left is not None and left == right:
                    return left
                return None
            i += 1
    return None


SPEC_RE = re.compile(r"%(?:@|[a-zA-Z]+)")


def variant_specs(variant_key: str, base: str) -> tuple[str, ...]:
    """Ordered format-specifier sequence of a catalog variant key.

    `%@` counts: the `@` is not a letter, so the character class must
    carry it explicitly (a bare `%[a-zA-Z]+` parses `%@` into an empty
    sequence and phantom-mismatches every String-arg key).
    """
    suffix = variant_key[len(base) + 1:]
    return tuple(SPEC_RE.findall(suffix))


def iter_swift_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d
            for d in dirnames
            if d not in SKIP_DIR_PARTS and not d.endswith(SKIP_DIR_SUFFIXES)
        ]
        for name in filenames:
            if name.endswith(".swift"):
                yield os.path.join(dirpath, name)


def scan_source(root: str) -> ScanResult:
    result = ScanResult()
    for path in iter_swift_files(root):
        try:
            with open(path, encoding="utf-8") as fh:
                lines = fh.readlines()
        except (OSError, UnicodeDecodeError):
            continue
        rel = os.path.relpath(path, root)
        try:
            with open(path, encoding="utf-8") as fh:
                result.symbols[rel] = collect_declarations(fh.read())
        except (OSError, UnicodeDecodeError):
            result.symbols[rel] = {}
        in_block_comment = False
        pending_localized = False
        pending_text = False
        for raw in lines:
            line = raw.strip()
            if in_block_comment:
                if "*/" in line:
                    line = line.split("*/", 1)[1].strip()
                    in_block_comment = False
                else:
                    continue
            if line.startswith("/*"):
                if "*/" in line:
                    line = line.split("*/", 1)[1].strip()
                else:
                    in_block_comment = True
                    continue
            if not line or line.startswith("//") or line.startswith("*"):
                continue
            if "Text(verbatim" in line:
                continue
            # V15 (form 1c): consume a pending next-line continuation — the
            # previous scanned line ended with `localized:` (comments in
            # between keep the pending state alive). The key must OPEN this
            # line; anything else cancels the pending state. Comments and
            # blank lines fall through the filters above without touching
            # the flag.
            if pending_localized:
                pending_localized = False
                lead = LEAD_LITERAL_RE.match(line)
                lead_interp = LEAD_INTERP_RE.match(line)
                if lead and KEY_SHAPE.match(lead.group(1)):
                    result.static_keys.setdefault(lead.group(1), []).append(rel)
                elif lead_interp and KEY_SHAPE.match(lead_interp.group(1)):
                    # V16: the continuation line may also OPEN with an
                    # interpolated literal (`"K \(expr)"`) — the form-1c
                    # interpolation twin joins the interp-key set. V17:
                    # capture the expressions for the deep-check.
                    exprs = parse_interp_literal(line, lead_interp.end() - 1)
                    result.interp_sites.setdefault(
                        lead_interp.group(1), []).append(
                            InterpSite(rel, "localized", exprs))
            elif pending_text:
                # V17 Text-family continuation: the previous scanned line
                # ended with `Text(`; the literal must OPEN this line.
                pending_text = False
                lead_interp = LEAD_INTERP_RE.match(line)
                if lead_interp and KEY_SHAPE.match(lead_interp.group(1)):
                    exprs = parse_interp_literal(line, lead_interp.end() - 1)
                    result.interp_sites.setdefault(
                        lead_interp.group(1), []).append(
                            InterpSite(rel, "text", exprs))
            for match in LOCATED_RE.finditer(line):
                key = match.group(1)
                if KEY_SHAPE.match(key):
                    result.static_keys.setdefault(key, []).append(rel)
            for match in LOCATED_CONT_RE.finditer(line):
                key = match.group(1)
                if KEY_SHAPE.match(key):
                    result.static_keys.setdefault(key, []).append(rel)
            for match in TEXT_RE.finditer(line):
                key = match.group(1)
                if KEY_SHAPE.match(key):
                    result.static_keys.setdefault(key, []).append(rel)
            for match in LOCATED_INTERP_RE.finditer(line):
                key = match.group(1)
                if KEY_SHAPE.match(key):
                    exprs = parse_interp_literal(line, match.end() - 1)
                    result.interp_sites.setdefault(key, []).append(
                        InterpSite(rel, "localized", exprs))
            for match in TEXT_INTERP_RE.finditer(line):
                key = match.group(1)
                if KEY_SHAPE.match(key):
                    exprs = parse_interp_literal(line, match.end() - 1)
                    result.interp_sites.setdefault(key, []).append(
                        InterpSite(rel, "text", exprs))
            for match in LITERAL_RE.finditer(line):
                result.literals.add(match.group(1))
            for match in INTERP_PREFIX_RE.finditer(line):
                result.interp_prefixes.add(match.group(1))
            if PENDING_LOCALIZED_RE.search(line):
                pending_localized = True
            elif TEXT_OPEN_RE.search(line):
                pending_text = True
    return result


def load_catalog(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        catalog = json.load(fh)
    if "strings" not in catalog:
        raise ValueError(f"catalog {path} has no 'strings' object")
    return catalog


def parse_allowlist(path: str | None) -> tuple[list[str], list[str]]:
    """Returns (exact_keys, prefixes-with-star)."""
    exact: list[str] = []
    prefixes: list[str] = []
    entries: list[str] = list(DEFAULT_ALLOWLIST)
    if path:
        with open(path, encoding="utf-8") as fh:
            entries.extend(fh.readlines())
    for raw in entries:
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        if entry.endswith("*"):
            prefixes.append(entry[:-1])
        else:
            exact.append(entry)
    return exact, prefixes


def covered_by_family(key: str, prefixes: set[str]) -> bool:
    for prefix in prefixes:
        if key == prefix:
            return True
        if key.startswith(prefix + "_") or key.startswith(prefix + " "):
            return True
        if prefix.endswith("_") and key.startswith(prefix):
            return True
    return False


def audit(
    scan: ScanResult,
    catalog: dict,
    allow_exact: list[str],
    allow_prefixes: list[str],
) -> AuditViolations:
    violations = AuditViolations()
    catalog_keys = set(catalog["strings"].keys())

    # Assertion 1 — source keys ⊆ catalog keys.
    for key in sorted(scan.static_keys):
        if key not in catalog_keys:
            violations.missing.append(key)

    # Assertion 2 — catalog keys ⊆ source keys ∪ dynamic families ∪ allowlist.
    allowed = set(allow_exact)
    star_prefixes = list(allow_prefixes)
    for key in sorted(catalog_keys):
        if key in scan.static_keys:
            continue
        if key in scan.literals:
            continue
        if covered_by_family(key, scan.interp_prefixes):
            continue
        if key in allowed:
            continue
        if covered_by_family(key, star_prefixes):
            continue
        violations.orphans.append(key)

    # Assertions 3 + 4 — zh completeness and locale-code discipline.
    for key in sorted(catalog_keys):
        localizations = catalog["strings"][key].get("localizations", {})
        zh = localizations.get("zh")
        value = ""
        if isinstance(zh, dict):
            unit = zh.get("stringUnit", {})
            if isinstance(unit, dict):
                value = (unit.get("value") or "").strip()
        if not value:
            violations.zh_missing.append(key)
        for locale in localizations:
            if locale not in ("en", "zh"):
                violations.code_violations.append(f"{key} [{locale}]")

    # Assertion 5 (V16, V17-extended) — every interpolation key (both the
    # String(localized:) and the Text family) must own a catalog
    # FORMAT-VARIANT key (any catalog key starting with `K + " "`). The
    # bare static key K never satisfies the gate.
    for key in sorted(scan.interp_sites):
        if not any(ck.startswith(key + " ") for ck in catalog_keys):
            violations.interp_missing_variant.append(key)

    # Assertion 6 (V17) — specifier deep-checking. For every site whose
    # argument expressions are statically derivable, the derived ordered
    # spec sequence must equal SOME catalog variant's spec sequence
    # (length + per-position). Undecivable sites are EXEMPT (reported,
    # never judged — no false positives).
    exempt_records: list[tuple[str, str, str]] = []
    for key in sorted(scan.interp_sites):
        if key in violations.interp_missing_variant:
            continue  # ABSENT already fails the key; deep-check is moot.
        variants = [ck for ck in catalog_keys if ck.startswith(key + " ")]
        variant_spec_seqs = [variant_specs(ck, key) for ck in variants]
        symbols_by_path: dict[str, dict[str, set[str]]] = {}
        for site in scan.interp_sites[key]:
            if site.path not in symbols_by_path:
                symbols_by_path[site.path] = scan.symbols.get(site.path, {})
        for site in scan.interp_sites[key]:
            if site.exprs is None:
                exempt_records.append((key, site.path, "unterminated literal"))
                continue
            symbols = symbols_by_path[site.path]
            derived = [derive_type(e, symbols) for e in site.exprs]
            if any(d is None for d in derived):
                reason = "undecivable argument type (" + ", ".join(
                    e.strip() if d is None else ""
                    for e, d in zip(site.exprs, derived)
                    if d is None
                ) + ")"
                exempt_records.append((key, site.path, reason))
                continue
            expected = tuple(TYPE_SPEC[d] for d in derived)
            if expected not in variant_spec_seqs:
                shown = " | ".join(
                    f"catalog='{ck}'" for ck in variants)
                violations.interp_spec_mismatch.append(
                    f"{key}  (at {site.path})  "
                    f"expected='{key} {' '.join(expected)}'  vs  {shown}"
                )

    # Stash the exempt records on the violations object for the report
    # (attribute is not part of the violation count).
    violations.exempt_records = exempt_records  # type: ignore[attr-defined]

    return violations


def format_report(violations: AuditViolations, scan: ScanResult, catalog: dict) -> str:
    lines: list[str] = []
    catalog_keys = len(catalog["strings"])
    lines.append("zh-audit report")
    lines.append(f"  source static keys : {len(scan.static_keys)}")
    lines.append(f"  catalog keys       : {catalog_keys}")
    lines.append(f"  dynamic families   : {len(scan.interp_prefixes)}")
    lines.append(f"  interp keys        : {len(scan.interp_sites)}")
    lines.append("")
    lines.append(f"[1] source keys missing from catalog : {len(violations.missing)}")
    for key in violations.missing:
        lines.append(f"    MISSING  {key}  (at {', '.join(scan.static_keys[key])})")
    lines.append(f"[2] orphan catalog keys              : {len(violations.orphans)}")
    for key in violations.orphans:
        lines.append(f"    ORPHAN   {key}")
    lines.append(f"[3] catalog keys missing zh value    : {len(violations.zh_missing)}")
    for key in violations.zh_missing:
        lines.append(f"    NO-ZH    {key}")
    lines.append(f"[4] locale-code violations           : {len(violations.code_violations)}")
    for entry in violations.code_violations:
        lines.append(f"    LOCALE   {entry}")
    lines.append(
        "[5] interpolation keys w/o catalog format variant : "
        f"{len(violations.interp_missing_variant)}")
    for key in sorted(scan.interp_sites):
        absent = key in violations.interp_missing_variant
        status = "ABSENT " if absent else "PRESENT"
        marker = "  ! " if absent else "    "
        families = sorted({site.family for site in scan.interp_sites[key]})
        paths = ", ".join(scan.interp_paths(key))
        lines.append(
            f"{marker}{status}  {key}  [{'+'.join(families)}]  (at {paths})")
    lines.append(
        "[6] specifier deep-check (V17) mismatches : "
        f"{len(violations.interp_spec_mismatch)}")
    for entry in violations.interp_spec_mismatch:
        lines.append(f"  ! MISMATCH  {entry}")
    exempt = getattr(violations, "exempt_records", [])
    lines.append(f"    exempt sites (reported, not judged) : {len(exempt)}")
    for key, path, reason in exempt:
        lines.append(f"      EXEMPT  {key}  (at {path})  {reason}")
    lines.append("")
    lines.append(
        "RESULT: PASS" if violations.ok() else f"RESULT: FAIL ({violations.total} violations)"
    )
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Self-test (golden fixtures). Builds a synthetic source tree + catalog in a
# temp directory and asserts the scanner reports exactly the seeded
# violations, and a clean fixture passes. AC M2-3-4 #2; the V17 golden
# eight-case bundle pins the specifier deep-check (E-2 revised).
# ─────────────────────────────────────────────────────────────────────────────

SELFTEST_SOURCE_BAD = """\
import SwiftUI

struct FixtureView: View {
    var body: some View {
        VStack {
            // Text("selftest_comment_key") stays unscanned (comment line).
            Text(verbatim: "selftest_verbatim_key")
            Text("selftest_good_key")
            Text("selftest_missing_key")
            Button(String(localized: "selftest_orphan_hunter")) {}
            let n = 3
            _ = String(localized: "selftest_family \\(n)")
            // V16 assertion 5 red: an interpolated localization whose
            // catalog has NO format variant (the M2-9 F-2 live family).
            _ = String(localized: "selftest_novariant \\(n)")
            // V15 form 1c: `localized:` ends the line, the key opens the
            // next scanned line — the per-line regexes miss this shape.
            _ = String(
                localized:
                    "selftest_continuation_key")
            // V15 form 1c interpolation twin: the continuation line opens
            // with an interpolated literal (dynamic family coverage).
            _ = String(
                localized:
                    "selftest_family_cont \\(n)")
        }
    }
}
"""

SELFTEST_SOURCE_GOOD = """\
import SwiftUI

struct CleanView: View {
    var body: some View {
        Text("selftest_good_key")
    }
}
"""

# V17 golden eight-case bundle (E-2 revised):
#   1. spec-mismatch red   (Int arg vs a %@-only catalog variant)
#   2. Text-family no-variant red
#   3. cross-line (form-1c continuation) green
#   4. exempt example      (member chain — reported, never judged)
#   5. position-mismatch red ([String, Int] vs `%lld %lld` — the ordered
#      comparison must NOT be fooled by a non-empty type-set intersection)
#   6. Int32 → %lld green  (the all-Int-family mapping anchor)
#   7. Float=Double share %lf green (the D-5 sample's mapping, catalog side)
#   8. comment immunity    (a doc comment containing an interpolation
#      literal stays unscanned — no false ABSENT)
V17_SOURCE = """\
import SwiftUI

struct V17Fixture: View {
    var body: some View {
        VStack {
            let count: Int = fetch()
            // g1: spec mismatch red — Int arg, catalog variant is %@-only.
            _ = String(localized: "g1_spec_mismatch \\(count)")
            // g2: Text family no-variant red.
            Text("g2_text_novar \\(count)")
            // g3: cross-line green (form-1c continuation, variant in
            // catalog).
            _ = String(
                localized:
                    "g3_continuation \\(count)")
            // g4: exempt — a member chain stays unjudged (元组成员豁免).
            Text("g4_exempt_member \\(item.name)")
            // g5: position mismatch red — [String, Int] vs `%lld %lld`.
            let name: String = label()
            _ = String(localized: "g5_position \\(name) \\(count)")
            // g6: Int32 maps to %lld like every Int-family member — green.
            let code: Int32 = 7
            _ = String(localized: "g6_int32 \\(code)")
            // g7: Float and Double share the %lf mapping — green.
            let ratio: Float = 0.5
            let scale: Double = 2.0
            _ = String(localized: "g7_float \\(ratio) \\(scale)")
            // g8 comment immunity: the doc-comment literal below —
            // Text("g8_comment \\(count)") — must stay unscanned.
        }
    }
}
"""


def make_catalog(entries: dict[str, dict]) -> dict:
    return {"sourceLanguage": "en", "strings": entries}


def entry(en: str, zh: str | None = None, locales: dict | None = None) -> dict:
    localizations: dict = {
        "en": {"stringUnit": {"state": "translated", "value": en}}
    }
    if locales is not None:
        localizations = locales
    elif zh is not None:
        localizations["zh"] = {"stringUnit": {"state": "translated", "value": zh}}
    return {"extractionState": "manual", "localizations": localizations}


def write_fixture(tmp: str, source: str, catalog: dict) -> tuple[str, str]:
    src_dir = os.path.join(tmp, "Src")
    os.makedirs(src_dir, exist_ok=True)
    src_path = os.path.join(src_dir, "fixture.swift")
    with open(src_path, "w", encoding="utf-8") as fh:
        fh.write(source)
    cat_path = os.path.join(tmp, "Localizable.xcstrings")
    with open(cat_path, "w", encoding="utf-8") as fh:
        json.dump(catalog, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")
    return src_path, cat_path


def run_selftest() -> int:
    failures: list[str] = []

    def check(label: str, condition: bool) -> None:
        if not condition:
            failures.append(label)

    with tempfile.TemporaryDirectory(prefix="zh-audit-selftest-") as tmp:
        # Case bundle A — seeded violations must all be detected.
        _, cat_path = write_fixture(
            tmp,
            SELFTEST_SOURCE_BAD,
            make_catalog(
                {
                    # covered via quoted literal? no — only via Text pattern.
                    "selftest_good_key": entry("Good", "好"),
                    # orphan: in catalog, referenced nowhere in source.
                    "selftest_orphan_key": entry("Orphan", "孤儿"),
                    # zh missing (assertion 3).
                    "selftest_no_zh_key": entry("No zh"),
                    # locale-code violation (assertion 4, zh-Hans forbidden).
                    "selftest_hans_key": entry(
                        "Hans",
                        locales={
                            "en": {"stringUnit": {"state": "translated", "value": "Hans"}},
                            "zh-Hans": {
                                "stringUnit": {"state": "translated", "value": "简体"}
                            },
                        },
                    ),
                    # V16 assertion 5 green: the format variants for the two
                    # interpolated localization keys (same-line + form-1c
                    # continuation twins).
                    "selftest_family %lld": entry("Family %lld", "家族 %lld"),
                    "selftest_family_cont %lld": entry(
                        "Family cont %lld", "家族续行 %lld"),
                }
            ),
        )
        scan = scan_source(tmp)
        catalog = load_catalog(cat_path)
        violations = audit(scan, catalog, [], [])

        check("A1 missing detects selftest_missing_key", "selftest_missing_key" in violations.missing)
        check("A1 missing does not include cataloged keys", "selftest_good_key" not in violations.missing)
        # V15 form 1c: the next-line continuation key IS extracted (it is
        # catalog-absent here, so it must surface as MISSING).
        check(
            "A1 continuation key extracted (V15 hardening)",
            "selftest_continuation_key" in violations.missing,
        )
        check(
            "A1 continuation key registered as a static source key",
            "selftest_continuation_key" in scan.static_keys,
        )
        # V15 form 1c twin: the continuation interpolation prefix joins the
        # dynamic families (the catalog family keys stay orphan-clean).
        check(
            "interp continuation prefix registered (V15)",
            "selftest_family_cont" in scan.interp_prefixes,
        )
        # V16 assertion 5: interp keys register from BOTH forms; the
        # variant-less one is flagged, the family twins stay green.
        check(
            "A5 interp keys registered (same-line + 1c continuation)",
            "selftest_family" in scan.interp_sites
            and "selftest_novariant" in scan.interp_sites
            and "selftest_family_cont" in scan.interp_sites,
        )
        check(
            "A5 interp key w/o catalog variant flagged",
            "selftest_novariant" in violations.interp_missing_variant,
        )
        check(
            "A5 family keys variant-PRESENT (green)",
            "selftest_family" not in violations.interp_missing_variant
            and "selftest_family_cont" not in violations.interp_missing_variant,
        )
        check(
            "A5 total counts assertion 5",
            violations.total
            == len(violations.missing)
            + len(violations.orphans)
            + len(violations.zh_missing)
            + len(violations.code_violations)
            + len(violations.interp_missing_variant)
            + len(violations.interp_spec_mismatch),
        )
        check("A2 orphan detects selftest_orphan_key", "selftest_orphan_key" in violations.orphans)
        # selftest_family is an interpolation prefix; it must NOT be an orphan.
        check("A2 dynamic family covered", "selftest_family" not in violations.orphans)
        check("A3 zh-missing detects selftest_no_zh_key", "selftest_no_zh_key" in violations.zh_missing)
        check(
            "A4 locale violation detects zh-Hans on selftest_hans_key",
            "selftest_hans_key [zh-Hans]" in violations.code_violations,
        )
        # The verbatim and comment strings must not enter the key set.
        check(
            "scan excludes verbatim/comment keys",
            not any("verbatim" in k or "comment" in k for k in scan.static_keys),
        )
        check("clean keys produce no zh/locale violations",
              "selftest_good_key" not in violations.zh_missing
              and "selftest_good_key" not in violations.code_violations)

        # Case bundle B — clean fixture passes.
        tmp2 = os.path.join(tmp, "clean")
        os.makedirs(tmp2, exist_ok=True)
        _, cat_path2 = write_fixture(
            tmp2,
            SELFTEST_SOURCE_GOOD,
            make_catalog({"selftest_good_key": entry("Good", "好")}),
        )
        scan2 = scan_source(tmp2)
        violations2 = audit(scan2, load_catalog(cat_path2), [], [])
        check("B clean fixture passes", violations2.ok())

        # Case bundle C — allowlist exempts an orphan.
        scan3 = scan_source(tmp)
        violations3 = audit(scan3, catalog, ["selftest_orphan_key"], [])
        check("C allowlist exempts orphan", "selftest_orphan_key" not in violations3.orphans)
        violations4 = audit(scan3, catalog, [], ["selftest_orphan"])
        check("C prefix allowlist exempts orphan", "selftest_orphan_key" not in violations4.orphans)

        # ─────────────────────────────────────────────────────────────────
        # Case bundle D — V17 golden eight cases.
        # ─────────────────────────────────────────────────────────────────
        tmp_d = os.path.join(tmp, "v17")
        os.makedirs(tmp_d, exist_ok=True)
        _, cat_path_d = write_fixture(
            tmp_d,
            V17_SOURCE,
            make_catalog(
                {
                    # g1: variant EXISTS but with the wrong specifier — the
                    # D-5 live-defect signature (golden ①).
                    "g1_spec_mismatch %@": entry("G1 %@", "G1 %@"),
                    # g2: NO variant at all (golden ②) — ABSENT via the
                    # Text-family gate.
                    # g3: continuation form with a matching variant (③).
                    "g3_continuation %lld": entry("G3 %lld", "G3 %lld"),
                    # g4: a variant that WOULD mismatch if the member chain
                    # were judged — its absence from the mismatch list
                    # proves the exemption actually bypasses judgment (④).
                    "g4_exempt_member %@": entry("G4 %@", "G4 %@"),
                    # g5: same type MULTISET, wrong ORDER — the ordered
                    # per-position comparison must flag it (golden ⑤).
                    "g5_position %lld %lld": entry("G5", "G5"),
                    # g6: Int32 → %lld, the all-Int-family anchor (⑥).
                    "g6_int32 %lld": entry("G6 %lld", "G6 %lld"),
                    # g7: Float and Double both derive %lf (⑦).
                    "g7_float %lf %lf": entry("G7 %lf %lf", "G7 %lf %lf"),
                    # g8 exists ONLY in the doc comment — nothing in the
                    # catalog, and the scan must not flag it (⑧).
                }
            ),
        )
        scan_d = scan_source(tmp_d)
        catalog_d = load_catalog(cat_path_d)
        v17 = audit(scan_d, catalog_d, [], [])
        exempt = {k: r for k, _, r in getattr(v17, "exempt_records", [])}

        check("D g1 site registered", "g1_spec_mismatch" in scan_d.interp_sites)
        check("D g1 spec-mismatch red (golden 1)",
              any(e.startswith("g1_spec_mismatch ") for e in v17.interp_spec_mismatch))
        check("D g1 not flagged ABSENT (variant exists)",
              "g1_spec_mismatch" not in v17.interp_missing_variant)
        check("D g2 registered as a TEXT-family site (golden 2)",
              any(s.family == "text" for s in scan_d.interp_sites.get("g2_text_novar", [])))
        check("D g2 Text-family no-variant red (golden 2)",
              "g2_text_novar" in v17.interp_missing_variant)
        check("D g3 continuation site registered (golden 3)",
              any(s.exprs == ("count",) for s in scan_d.interp_sites.get("g3_continuation", [])))
        check("D g3 cross-line green (golden 3)",
              "g3_continuation" not in v17.interp_missing_variant
              and not any(e.startswith("g3_continuation ") for e in v17.interp_spec_mismatch))
        check("D g4 member chain exempt (golden 4)",
              "g4_exempt_member" in exempt
              and not any(e.startswith("g4_exempt_member ") for e in v17.interp_spec_mismatch))
        check("D g5 position-mismatch red (golden 5)",
              any(e.startswith("g5_position ") for e in v17.interp_spec_mismatch))
        check("D g6 Int32→%lld green (golden 6)",
              "g6_int32" not in v17.interp_missing_variant
              and not any(e.startswith("g6_int32 ") for e in v17.interp_spec_mismatch))
        check("D g7 Float=Double share %lf green (golden 7)",
              "g7_float" not in v17.interp_missing_variant
              and not any(e.startswith("g7_float ") for e in v17.interp_spec_mismatch))
        check("D g8 doc-comment literal unscanned (golden 8)",
              "g8_comment" not in scan_d.interp_sites
              and "g8_comment" not in v17.interp_missing_variant)
        check("D g7 exprs parsed from one literal",
              any(s.exprs == ("ratio", "scale")
                  for s in scan_d.interp_sites.get("g7_float", [])))

    if failures:
        print("SELF-TEST FAIL:")
        for item in failures:
            print(f"  - {item}")
        return 1
    print(
        "SELF-TEST PASS (missing / orphan / zh-missing / zh-Hans / interp-no-variant / "
        "spec-mismatch detected; V17 golden eight cases hold; clean passes; allowlist works)"
    )
    return 0


def default_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def default_catalog(root: str) -> str:
    return os.path.join(root, "Resources", "Localizable.xcstrings")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--report", action="store_true", help="human-readable report")
    mode.add_argument("--check", action="store_true", help="machine check (exit 0/1)")
    mode.add_argument("--self-test", dest="self_test", action="store_true", help="golden fixture self-test")
    parser.add_argument("--allowlist", help="extra exemption file for assertion 2")
    parser.add_argument("--catalog", help="catalog path override")
    parser.add_argument("--root", help="source scan root override")
    args = parser.parse_args(argv)

    if args.self_test:
        return run_selftest()

    root = args.root or default_root()
    catalog_path = args.catalog or default_catalog(root)
    try:
        scan = scan_source(root)
        catalog = load_catalog(catalog_path)
        allow_exact, allow_prefixes = parse_allowlist(args.allowlist)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"zh-audit: input error: {exc}", file=sys.stderr)
        return 2

    violations = audit(scan, catalog, allow_exact, allow_prefixes)

    if args.report:
        print(format_report(violations, scan, catalog))
        return 0

    if violations.ok():
        print(
            "zh-audit --check PASS "
            f"({len(scan.static_keys)} source keys, {len(catalog['strings'])} catalog keys, "
            f"{len(scan.interp_sites)} interp keys all variant-PRESENT + spec-matched, "
            "zh complete, locale codes = {en, zh})"
        )
        return 0
    print(format_report(violations, scan, catalog))
    return 1


if __name__ == "__main__":
    sys.exit(main())
