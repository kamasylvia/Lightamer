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

Interpolated localization keys (assertion 5 — V16)
    ``String(localized: "K \\(expr)"`` extracts at build time as a FORMAT
    key (``"K %@"`` / ``"K %lld"`` … — the xcstrings convention). The
    scanner records these separately (same-line form + the form-1c
    continuation line opening with an interpolated literal) as
    ``localized_interp_keys``, and assertion 5 requires every such key K
    to own a catalog FORMAT-VARIANT key starting with ``K + " "``. The
    bare static key ``K`` never satisfies the gate: a catalog entry that
    only carries ``K`` (its value holding the placeholder) means the
    runtime lookup of the variant key fails and the UI falls back to the
    raw key text (the M2-9 F-2 live defect family). Specifier-shape
    deep-checking (``%lld`` vs ``%@`` mismatches while a variant exists)
    stays a manual-walk item — the gate is the PRESENT/ABSENT triage.

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
                clean case) and verify the scanner detects each; exit 0/1

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
# V16 (assertion 5): interpolated localization literals — the same-line
# `String(localized: "K \(expr)"` form, and the form-1c continuation line
# OPENING with an interpolated literal. The extracted key is the literal's
# static prefix; the build-time format variant is `K <specifier>`.
LOCATED_INTERP_RE = re.compile(r'\bString\(\s*localized:\s*"([A-Za-z0-9_]+)\s*\\\(')
LEAD_INTERP_RE = re.compile(r'^"([A-Za-z0-9_]+)\s*\\\(')

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


@dataclass
class ScanResult:
    static_keys: dict[str, list[str]] = field(default_factory=dict)
    literals: set[str] = field(default_factory=set)
    interp_prefixes: set[str] = field(default_factory=set)
    # V16 (assertion 5): interpolated localization keys — the static prefix
    # of a `String(localized: "K \(…)"` literal (same-line + form-1c
    # continuation), with the reference paths for the report.
    localized_interp_keys: dict[str, list[str]] = field(default_factory=dict)


@dataclass
class AuditViolations:
    missing: list[str] = field(default_factory=list)       # assertion 1
    orphans: list[str] = field(default_factory=list)       # assertion 2
    zh_missing: list[str] = field(default_factory=list)    # assertion 3
    code_violations: list[str] = field(default_factory=list)  # assertion 4
    interp_missing_variant: list[str] = field(default_factory=list)  # assertion 5

    @property
    def total(self) -> int:
        return (
            len(self.missing)
            + len(self.orphans)
            + len(self.zh_missing)
            + len(self.code_violations)
            + len(self.interp_missing_variant)
        )

    def ok(self) -> bool:
        return self.total == 0


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
        in_block_comment = False
        pending_localized = False
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
                    # interpolation twin joins the interp-key set.
                    result.localized_interp_keys.setdefault(
                        lead_interp.group(1), []).append(rel)
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
                    result.localized_interp_keys.setdefault(key, []).append(rel)
            for match in LITERAL_RE.finditer(line):
                result.literals.add(match.group(1))
            for match in INTERP_PREFIX_RE.finditer(line):
                result.interp_prefixes.add(match.group(1))
            if PENDING_LOCALIZED_RE.search(line):
                pending_localized = True
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

    # Assertion 5 (V16) — every localized interpolation key must own a
    # catalog FORMAT-VARIANT key (any catalog key starting with `K + " "`:
    # the build-time extraction of `String(localized: "K \(…)")` spells the
    # key `K %@` / `K %lld` …). The bare static key K never satisfies the
    # gate — a catalog that only carries K sends the runtime lookup of the
    # variant to the raw-key fallback (the M2-9 F-2 family). Specifier
    # deep-checking stays manual (the PRESENT/ABSENT triage is the gate).
    for key in sorted(scan.localized_interp_keys):
        if not any(ck.startswith(key + " ") for ck in catalog_keys):
            violations.interp_missing_variant.append(key)

    return violations


def format_report(violations: AuditViolations, scan: ScanResult, catalog: dict) -> str:
    lines: list[str] = []
    catalog_keys = len(catalog["strings"])
    lines.append("zh-audit report")
    lines.append(f"  source static keys : {len(scan.static_keys)}")
    lines.append(f"  catalog keys       : {catalog_keys}")
    lines.append(f"  dynamic families   : {len(scan.interp_prefixes)}")
    lines.append(f"  interp format keys : {len(scan.localized_interp_keys)}")
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
    for key in sorted(scan.localized_interp_keys):
        absent = key in violations.interp_missing_variant
        status = "ABSENT " if absent else "PRESENT"
        marker = "  ! " if absent else "    "
        paths = ", ".join(scan.localized_interp_keys[key])
        lines.append(f"{marker}{status}  {key}  (at {paths})")
    lines.append("")
    lines.append(
        "RESULT: PASS" if violations.ok() else f"RESULT: FAIL ({violations.total} violations)"
    )
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Self-test (golden fixtures). Builds a synthetic source tree + catalog in a
# temp directory and asserts the scanner reports exactly the four seeded
# violations, and a clean fixture passes. AC M2-3-4 #2.
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
        # Case bundle A — four seeded violations must all be detected.
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
            "selftest_family" in scan.localized_interp_keys
            and "selftest_novariant" in scan.localized_interp_keys
            and "selftest_family_cont" in scan.localized_interp_keys,
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
            + len(violations.interp_missing_variant),
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

    if failures:
        print("SELF-TEST FAIL:")
        for item in failures:
            print(f"  - {item}")
        return 1
    print(
        "SELF-TEST PASS (missing / orphan / zh-missing / zh-Hans / interp-no-variant "
        "detected; clean passes; allowlist works)"
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
            f"{len(scan.localized_interp_keys)} interp keys all variant-PRESENT, "
            "zh complete, locale codes = {en, zh})"
        )
        return 0
    print(format_report(violations, scan, catalog))
    return 1


if __name__ == "__main__":
    sys.exit(main())
