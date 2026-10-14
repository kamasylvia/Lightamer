#!/usr/bin/env python3
"""parity-audit.py - Alcedo-parity checklist gate for Lightamer.

Plan M6-6-01 T2 (charter ruling 6). Machine gate over
docs/parity-checklist.md: row structure, id uniqueness, vocabulary and
status-evidence rules, evidence-path existence, cross-file FEAT reference
linkage, and generated-block freshness. Method credit: LightCraft
(MIT OR Apache-2.0) parity gate - form and behavior semantics only, zero
code ported.

Scan domain
    docs/parity-checklist.md (the reconciliation master; the internal
    survey never mints ids). Rows are table lines whose first cell is a
    ``FEAT-<DOM>-NN`` id; the 12 domain sections (``## SHELL`` .. ``## OWN``)
    must be present.

Assertions
    A1 row structure - every FEAT row parses into exactly 6 cells, the id
       matches ``FEAT-(SHELL|LIB|EDT|ADJ|DEV|GEO|NODE|MASK|DRT|EXP|AI|OWN)-NN``,
       and all 12 domain section headers exist.
    A2 id uniqueness - FEAT ids are globally unique (the id cell only;
       prose mentions in Notes are not counted).
    A3 vocabulary + status-evidence rules - Source in {Alcedo, LightCraft,
       Lightamer} and Status in {Delivered, Partial, Missing, V2, Parked,
       OOS} (exact match; the vocabulary is case-sensitive). Per the
       CONTEXT D2 machine-checkable half: a Delivered row carries at least
       one backticked ``src:``/``doc:`` pointer; Missing carries a note;
       V2/Parked/OOS carry at least one ``doc:`` anchor (anchor CONTENT
       stays a manual-walk item).
    A4 evidence existence - ``src:`` pointers must exist under the tree
       root (always checked; a ``:<line>`` suffix is additionally checked
       against the file's line count); ``doc:`` pointers are checked only
       when a ``.work/`` root exists in the tree (public checkouts skip
       them with an explicit report note - never a silent skip); pointers
       under ``.work/gui-acceptance/`` or ``.work/gsd/phases/*/evidence/``
       are format-only everywhere (gitignored evidence domains).
    A5 reference linkage - every ``FEAT-...`` token cited in the ledgers
       (``.work/gsd/REQUIREMENTS.md``, ``.work/gsd/ROADMAP.md`` and the
       repo-root ``AGENTS.md``) must exist in the checklist; an absent
       scanned file (public tree: the ``.work/`` ledgers) is skipped with
       an explicit note.
    A6 generated-block freshness - two states: while the summary/gaps
       blocks are still empty placeholders (whitespace only), A6 requires
       the four block markers to be present; once a block is filled its
       on-disk content must equal the in-memory recomputation byte for
       byte (drift = "stale - run --write").

Modes
    --check      machine check: any violation prints id/line detail, exit 1;
                 all pass -> exit 0
    --report     human-readable report (domain x status matrix + gaps
                 preview + skip notes); exit 0 unless IO/format errors
    --write      re-render the summary/gaps blocks in place
    --self-test  golden red/green fixtures: bad id shape / duplicate id /
                 illegal status / illegal source / missing src path / stale
                 generated block (each detected), one clean fixture passes
                 (empty placeholder blocks are the tolerated pre-fill
                 state), and a public-tree fixture without ``.work/``
                 exercises the A4 skip branch through the --tree-root seam

Extra flags
    --checklist PATH   checklist path override (default
                       <tree-root>/docs/parity-checklist.md; self-test uses
                       embedded fixtures and never touches the real file)
    --tree-root PATH   tree root override (default: repository root inferred
                       from this script's location). Feeds A4's ``.work/``
                       presence probe, ``src:`` path resolution and A5's
                       scanned files - the injection seam that makes the
                       public-tree branch deterministically testable (the
                       zh-audit ``--root`` flag is the same shape).

Run under uv per the toolchain red line:
    uv run python3 Scripts/parity-audit.py --check
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from dataclasses import dataclass, field

DOMAINS = (
    "SHELL", "LIB", "EDT", "ADJ", "DEV", "GEO",
    "NODE", "MASK", "DRT", "EXP", "AI", "OWN",
)
STATUSES = ("Delivered", "Partial", "Missing", "V2", "Parked", "OOS")
SOURCES = ("Alcedo", "LightCraft", "Lightamer")
# Gaps-block ordering: severity first, then domain code alphabetical
# (LightCraft ranks by measured user impact; we have no such calibration,
# so status severity is the standing proxy - refinement is a V2 note).
GAPS_STATUS_ORDER = ("Missing", "V2", "Parked", "OOS", "Partial")

SECTION_RE = re.compile(r"^## ([A-Z]+)\b")
ROW_RE = re.compile(r"^FEAT-(%s)-(\d{2})$" % "|".join(DOMAINS))
EVIDENCE_PTR_RE = re.compile(r"`((?:src|doc):[^`]+)`")
LINE_SUFFIX_RE = re.compile(r"^(.*):(\d+)$")
FORMAT_ONLY_RE = re.compile(r"^\.work/(gui-acceptance/|gsd/phases/[^/]+/evidence/)")
SCANNED_FILES = (".work/gsd/REQUIREMENTS.md", ".work/gsd/ROADMAP.md", "AGENTS.md")
A5_FEAT_TOKEN_RE = re.compile(r"FEAT-[A-Z]{3,5}-\d{2}")

SUMMARY_OPEN = "<!-- parity:summary -->"
SUMMARY_CLOSE = "<!-- /parity:summary -->"
GAPS_OPEN = "<!-- parity:gaps -->"
GAPS_CLOSE = "<!-- /parity:gaps -->"


@dataclass
class Row:
    row_id: str
    domain: str
    feature: str
    source: str
    status: str
    evidence: str
    notes: str
    line_no: int


@dataclass
class ParseResult:
    rows: list = field(default_factory=list)
    structure: list = field(default_factory=list)   # A1
    sections: set = field(default_factory=set)


@dataclass
class Violations:
    structure: list = field(default_factory=list)   # A1
    duplicates: list = field(default_factory=list)  # A2
    vocab: list = field(default_factory=list)       # A3
    evidence: list = field(default_factory=list)    # A4
    linkage: list = field(default_factory=list)     # A5
    stale: list = field(default_factory=list)       # A6
    notes: list = field(default_factory=list)       # explicit skip notes

    @property
    def total(self) -> int:
        return (
            len(self.structure)
            + len(self.duplicates)
            + len(self.vocab)
            + len(self.evidence)
            + len(self.linkage)
            + len(self.stale)
        )

    def ok(self) -> bool:
        return self.total == 0


def parse_checklist(text: str) -> ParseResult:
    result = ParseResult()
    # Generated blocks (summary/gaps) hold rendered rows that also start
    # with "| FEAT-" - they are gate OUTPUT, not hand-maintained rows, so
    # the parser skips everything inside the four markers.
    block_markers = (SUMMARY_OPEN, SUMMARY_CLOSE, GAPS_OPEN, GAPS_CLOSE)
    in_block = False
    for line_no, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if line in block_markers:
            if line in (SUMMARY_OPEN, GAPS_OPEN):
                in_block = True
            else:
                in_block = False
            continue
        if in_block:
            continue
        section = SECTION_RE.match(line)
        if section and section.group(1) in DOMAINS:
            result.sections.add(section.group(1))
            continue
        if not line.startswith("| FEAT-"):
            continue
        cells = [c.strip() for c in line.split("|")]
        # "| a | b | c | d | e | f |" splits into 8 pieces with empty ends.
        cells = cells[1:-1] if len(cells) >= 2 else []
        if len(cells) != 6:
            result.structure.append(
                "line %d: row does not parse into 6 cells (%d)" % (line_no, len(cells)))
            continue
        row_id, feature, source, status, evidence, notes = cells
        if not ROW_RE.match(row_id):
            result.structure.append(
                "line %d: bad id shape %r (expected FEAT-<DOM>-NN)" % (line_no, row_id))
            continue
        result.rows.append(Row(
            row_id=row_id,
            domain=row_id.split("-")[1],
            feature=feature,
            source=source,
            status=status,
            evidence=evidence,
            notes=notes,
            line_no=line_no,
        ))
    for domain in DOMAINS:
        if domain not in result.sections:
            result.structure.append("missing domain section: %s" % domain)
    return result


def pointers_in(evidence: str) -> list:
    return EVIDENCE_PTR_RE.findall(evidence)


def check_pointer(ptr: str, tree_root: str, work_present: bool):
    """Returns (violation_or_None, note_or_None)."""
    if ptr.startswith("src:"):
        rel = ptr[len("src:"):]
        # A trailing :N is a line pointer only when the stem (without it)
        # also resolves - a path that legitimately ends in digits is not
        # misread as a line reference.
        full = os.path.join(tree_root, rel)
        line_no = None
        m = LINE_SUFFIX_RE.match(rel)
        if m and not os.path.exists(full):
            stem_full = os.path.join(tree_root, m.group(1))
            if os.path.isfile(stem_full):
                line_no = int(m.group(2))
                full = stem_full
        if not os.path.exists(full):
            return ("A4 missing src path: %s" % ptr), None
        if line_no is not None:
            with open(full, encoding="utf-8", errors="replace") as fh:
                line_count = sum(1 for _ in fh)
            if line_no < 1 or line_no > line_count:
                return (
                    "A4 src line out of range: %s (file has %d lines)"
                    % (ptr, line_count)), None
        return None, None
    if ptr.startswith("doc:"):
        rel = ptr[len("doc:"):]
        if FORMAT_ONLY_RE.match(rel):
            return None, "format-only evidence domain (not checked): %s" % ptr
        if not work_present:
            return None, "local-only evidence (public tree, not checked): %s" % ptr
        if not os.path.exists(os.path.join(tree_root, rel)):
            return ("A4 missing doc path: %s" % ptr), None
        return None, None
    return ("A4 unknown pointer scheme: %s" % ptr), None


def audit(parsed: ParseResult, text: str, tree_root: str) -> Violations:
    violations = Violations()
    rows = parsed.rows
    violations.structure.extend(parsed.structure)

    # A2 - id uniqueness (id cell only).
    seen = {}
    for row in rows:
        seen.setdefault(row.row_id, []).append(row.line_no)
    for row_id, line_nos in sorted(seen.items()):
        if len(line_nos) > 1:
            violations.duplicates.append(
                "duplicate id %s at lines %s" % (row_id, line_nos))

    # A3 - vocabulary + status-evidence rules.
    known_ids = set(seen)
    for row in rows:
        if row.source not in SOURCES:
            violations.vocab.append(
                "line %d: illegal Source %r (%s)" % (row.line_no, row.source, row.row_id))
        if row.status not in STATUSES:
            violations.vocab.append(
                "line %d: illegal Status %r (%s)" % (row.line_no, row.status, row.row_id))
        ptrs = pointers_in(row.evidence)
        if row.status == "Delivered" and not ptrs:
            violations.vocab.append(
                "A3 Delivered row without an evidence pointer: %s" % row.row_id)
        if row.status == "Missing" and not row.notes.strip():
            violations.vocab.append(
                "A3 Missing row without a note: %s" % row.row_id)
        if row.status in ("V2", "Parked", "OOS"):
            if not any(p.startswith("doc:") for p in ptrs):
                violations.vocab.append(
                    "A3 %s row without a doc: anchor: %s" % (row.status, row.row_id))

    # A4 - evidence existence.
    work_present = os.path.isdir(os.path.join(tree_root, ".work"))
    for row in rows:
        for ptr in pointers_in(row.evidence):
            violation, note = check_pointer(ptr, tree_root, work_present)
            if violation:
                violations.evidence.append(violation)
            if note:
                violations.notes.append(note)

    # A5 - cross-file FEAT reference linkage (absent file = explicit skip).
    for name in SCANNED_FILES:
        path = os.path.join(tree_root, name)
        if not os.path.isfile(path):
            violations.notes.append("A5 scanned file absent (skipped): %s" % name)
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            body = fh.read()
        for token in sorted(set(A5_FEAT_TOKEN_RE.findall(body))):
            if token not in known_ids:
                violations.linkage.append(
                    "A5 %s cites %s which is not in the checklist" % (name, token))

    # A6 - generated-block freshness (two states, see module docstring).
    for open_m, close_m, render in (
        (SUMMARY_OPEN, SUMMARY_CLOSE, render_summary),
        (GAPS_OPEN, GAPS_CLOSE, render_gaps),
    ):
        if open_m not in text or close_m not in text:
            violations.stale.append(
                "A6 generated-block markers missing: %s" % open_m)
            continue
        inner = text.split(open_m, 1)[1].split(close_m, 1)[0].strip()
        if inner == "":
            continue  # placeholder state: markers present is enough
        if inner != render(rows).strip():
            violations.stale.append(
                "A6 generated block is stale - run --write (%s)" % open_m)
    return violations


def status_counts(rows: list) -> dict:
    counts = {status: 0 for status in STATUSES}
    for row in rows:
        if row.status in counts:
            counts[row.status] += 1
    return counts


def render_summary(rows: list) -> str:
    lines = [
        "| Domain | Delivered | Partial | Missing | V2 | Parked | OOS | Rows |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    totals = {status: 0 for status in STATUSES}
    grand = 0
    for domain in DOMAINS:
        dom_rows = [r for r in rows if r.domain == domain]
        counts = status_counts(dom_rows)
        total = len(dom_rows)
        for status in STATUSES:
            totals[status] += counts[status]
        grand += total
        lines.append(
            "| %s | %d | %d | %d | %d | %d | %d | %d |"
            % (domain, counts["Delivered"], counts["Partial"], counts["Missing"],
               counts["V2"], counts["Parked"], counts["OOS"], total))
    lines.append(
        "| **Total** | %d | %d | %d | %d | %d | %d | %d |"
        % (totals["Delivered"], totals["Partial"], totals["Missing"],
           totals["V2"], totals["Parked"], totals["OOS"], grand))
    return "\n".join(lines)


def render_gaps(rows: list) -> str:
    lines = [
        "| Id | Domain | Status | Feature |",
        "|---|---|---|---|",
    ]
    for status in GAPS_STATUS_ORDER:
        subset = [r for r in rows if r.status == status]
        subset.sort(key=lambda r: (r.domain, r.row_id))
        for row in subset:
            lines.append("| %s | %s | %s | %s |" % (
                row.row_id, row.domain, row.status, row.feature))
    return "\n".join(lines)


def write_blocks(text: str, rows: list) -> str:
    text = replace_block(text, SUMMARY_OPEN, SUMMARY_CLOSE, render_summary(rows))
    text = replace_block(text, GAPS_OPEN, GAPS_CLOSE, render_gaps(rows))
    return text


def replace_block(text: str, open_m: str, close_m: str, content: str) -> str:
    before, rest = text.split(open_m, 1)
    _, after = rest.split(close_m, 1)
    return "%s%s\n%s\n%s%s" % (before, open_m, content, close_m, after)


def load_checklist(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def default_tree_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def format_report(parsed: ParseResult, violations: Violations) -> str:
    lines = []
    counts = status_counts(parsed.rows)
    lines.append("parity-audit report")
    lines.append("  checklist rows    : %d" % len(parsed.rows))
    lines.append(
        "  Delivered/Partial/Missing/V2/Parked/OOS : %d/%d/%d/%d/%d/%d"
        % (counts["Delivered"], counts["Partial"], counts["Missing"],
           counts["V2"], counts["Parked"], counts["OOS"]))
    lines.append("")
    lines.append("[A1] row structure violations        : %d" % len(violations.structure))
    for item in violations.structure:
        lines.append("    STRUCT  %s" % item)
    lines.append("[A2] duplicate ids                   : %d" % len(violations.duplicates))
    for item in violations.duplicates:
        lines.append("    DUP     %s" % item)
    lines.append("[A3] vocabulary/status-rule violations: %d" % len(violations.vocab))
    for item in violations.vocab:
        lines.append("    VOCAB   %s" % item)
    lines.append("[A4] evidence-path violations        : %d" % len(violations.evidence))
    for item in violations.evidence:
        lines.append("    PATH    %s" % item)
    lines.append("[A5] dangling FEAT references        : %d" % len(violations.linkage))
    for item in violations.linkage:
        lines.append("    LINK    %s" % item)
    lines.append("[A6] stale generated blocks          : %d" % len(violations.stale))
    for item in violations.stale:
        lines.append("    STALE   %s" % item)
    if violations.notes:
        lines.append("notes (explicit skips, not violations):")
        for item in violations.notes:
            lines.append("    NOTE    %s" % item)
    lines.append("")
    lines.append(
        "RESULT: PASS" if violations.ok()
        else "RESULT: FAIL (%d violations)" % violations.total)
    return "\n".join(lines)


def run_check(parsed: ParseResult, text: str, tree_root: str) -> int:
    violations = audit(parsed, text, tree_root)
    if violations.ok():
        notes = ""
        if violations.notes:
            notes = " [%d skip notes]" % len(violations.notes)
        print(
            "parity-audit --check PASS (%d rows, id-unique, vocab clean, "
            "evidence paths verified%s)" % (len(parsed.rows), notes))
        for note in violations.notes:
            print("  note: %s" % note)
        return 0
    print(format_report(parsed, violations))
    return 1


def run_report(parsed: ParseResult, text: str, tree_root: str) -> int:
    violations = audit(parsed, text, tree_root)
    print(format_report(parsed, violations))
    print()
    print("gaps preview (%s order):" % " -> ".join(GAPS_STATUS_ORDER))
    print(render_gaps(parsed.rows))
    return 0


def run_write(path: str, parsed: ParseResult) -> int:
    text = load_checklist(path)
    updated = write_blocks(text, parsed.rows)
    if updated == text:
        print("parity-audit --write: blocks already fresh (%s)" % path)
        return 0
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(updated)
    print("parity-audit --write: refreshed summary/gaps blocks in %s" % path)
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# Self-test (golden fixtures). Synthetic checklist texts in a temp tree;
# asserts each seeded violation family is detected, the clean fixture passes
# (empty placeholder blocks = tolerated pre-fill state), and the public-tree
# fixture exercises the A4 skip branch via the --tree-root seam. AC SC2.
# ─────────────────────────────────────────────────────────────────────────────

def fixture_sections() -> str:
    return "".join("## %s - %s\n\n" % (d, d.lower()) for d in DOMAINS)


FIXTURE_BLOCKS_EMPTY = (
    "## Summary\n\n<!-- parity:summary -->\n<!-- /parity:summary -->\n\n"
    "## Gaps\n\n<!-- parity:gaps -->\n<!-- /parity:gaps -->\n\n"
)


def red_fixture() -> str:
    rows = "\n".join([
        "| FEAT-SHELL-1 | Bad id shape | Alcedo | Delivered | `src:Docs/real.txt` | |",
        "| FEAT-SHELL-02 | First copy | Alcedo | Delivered | `src:Docs/real.txt` | |",
        "| FEAT-SHELL-02 | Second copy | Alcedo | Delivered | `src:Docs/real.txt` | |",
        "| FEAT-SHELL-03 | Bad status | Alcedo | done | `src:Docs/real.txt` | |",
        "| FEAT-SHELL-04 | Bad source | Someone | Delivered | `src:Docs/real.txt` | |",
        "| FEAT-SHELL-05 | Missing src | Alcedo | Delivered | `src:LightamerCore/Nothing.swift` | |",
        "| FEAT-SHELL-06 | Delivered without evidence | Alcedo | Delivered | | |",
        "| FEAT-SHELL-07 | Missing without note | Alcedo | Missing | | |",
        "| FEAT-SHELL-08 | V2 without anchor | Alcedo | V2 | `src:Docs/real.txt` | |",
    ])
    return fixture_sections() + rows + "\n\n" + FIXTURE_BLOCKS_EMPTY


def clean_fixture() -> str:
    rows = "\n".join([
        "| FEAT-SHELL-01 | Clean row | Alcedo | Delivered | `src:Docs/real.txt` | |",
        "| FEAT-LIB-01 | Missing with note | Alcedo | Missing | | not built yet |",
        "| FEAT-EXP-01 | Deferred with anchor | Alcedo | V2 | `doc:.work/gsd/phases/v2-station/V2-PROPOSAL.md` | |",
    ])
    return fixture_sections() + rows + "\n\n" + FIXTURE_BLOCKS_EMPTY


def public_tree_fixture() -> str:
    # Same content, but the tree root will NOT contain .work/ - the doc:
    # pointer must take the A4 skip branch (explicit note, no violation).
    return clean_fixture()


def stale_fixture() -> str:
    base = clean_fixture()
    return base.replace(
        "<!-- parity:summary -->\n<!-- /parity:summary -->",
        "<!-- parity:summary -->\n| Domain | Delivered |\n|---|---:|\n| wrong | 0 |\n<!-- /parity:summary -->",
    )


def make_tree(tmp: str, name: str, fixture: str, with_work: bool) -> tuple:
    root = os.path.join(tmp, name)
    docs = os.path.join(root, "docs")
    os.makedirs(docs, exist_ok=True)
    os.makedirs(os.path.join(root, "Docs"), exist_ok=True)
    with open(os.path.join(root, "Docs", "real.txt"), "w", encoding="utf-8") as fh:
        fh.write("evidence\n")
    if with_work:
        anchor = os.path.join(root, ".work", "gsd", "phases", "v2-station")
        os.makedirs(anchor, exist_ok=True)
        with open(os.path.join(anchor, "V2-PROPOSAL.md"), "w", encoding="utf-8") as fh:
            fh.write("anchor\n")
    path = os.path.join(docs, "parity-checklist.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(fixture)
    return root, path


def run_selftest() -> int:
    failures = []

    def check(label: str, condition: bool) -> None:
        if not condition:
            failures.append(label)

    with tempfile.TemporaryDirectory(prefix="parity-audit-selftest-") as tmp:
        # Case A - red fixture: every seeded family must be detected.
        root_a, path_a = make_tree(tmp, "red", red_fixture(), with_work=False)
        text_a = load_checklist(path_a)
        parsed_a = parse_checklist(text_a)
        v_a = audit(parsed_a, text_a, root_a)

        check("A1 bad id shape detected",
              any("FEAT-SHELL-1" in item for item in v_a.structure))
        check("A2 duplicate id detected",
              any("FEAT-SHELL-02" in item for item in v_a.duplicates))
        check("A3 illegal status detected",
              any("'done'" in item for item in v_a.vocab))
        check("A3 illegal source detected",
              any("'Someone'" in item for item in v_a.vocab))
        check("A4 missing src path detected",
              any("Nothing.swift" in item for item in v_a.evidence))
        check("A3 Delivered-without-evidence detected",
              any("FEAT-SHELL-06" in item for item in v_a.vocab))
        check("A3 Missing-without-note detected",
              any("FEAT-SHELL-07" in item for item in v_a.vocab))
        check("A3 V2-without-doc-anchor detected",
              any("FEAT-SHELL-08" in item for item in v_a.vocab))
        check("red fixture not ok", not v_a.ok())

        # Case B - clean fixture with empty placeholder blocks passes.
        root_b, path_b = make_tree(tmp, "clean", clean_fixture(), with_work=True)
        text_b = load_checklist(path_b)
        parsed_b = parse_checklist(text_b)
        v_b = audit(parsed_b, text_b, root_b)
        check("B clean fixture passes (placeholder tolerance)", v_b.ok())

        # Case C - stale generated block detected.
        root_c, path_c = make_tree(tmp, "stale", stale_fixture(), with_work=True)
        text_c = load_checklist(path_c)
        parsed_c = parse_checklist(text_c)
        v_c = audit(parsed_c, text_c, root_c)
        check("C stale summary block detected",
              any("stale" in item for item in v_c.stale))
        # And --write heals it.
        run_write(path_c, parsed_c)
        text_c2 = load_checklist(path_c)
        v_c2 = audit(parse_checklist(text_c2), text_c2, root_c)
        check("C --write heals the stale block", v_c2.ok())

        # Case D - public-tree branch: no .work/ root, doc: pointer skipped
        # with an explicit note (never a violation, never a silent skip).
        root_d, path_d = make_tree(tmp, "public", public_tree_fixture(), with_work=False)
        text_d = load_checklist(path_d)
        parsed_d = parse_checklist(text_d)
        v_d = audit(parsed_d, text_d, root_d)
        check("D public tree passes", v_d.ok())
        check("D local-only skip note present",
              any("local-only evidence" in item for item in v_d.notes))

    if failures:
        print("SELF-TEST FAIL:")
        for item in failures:
            print("  - %s" % item)
        return 1
    print(
        "SELF-TEST PASS (bad id shape / duplicate id / illegal status / illegal "
        "source / missing src path / ruleless Delivered-Missing-V2 rows / stale "
        "block all detected; clean + placeholder passes; --write heals; "
        "public-tree branch skips with explicit notes)"
    )
    return 0


def main(argv: list = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--report", action="store_true", help="human-readable report")
    mode.add_argument("--check", action="store_true", help="machine check (exit 0/1)")
    mode.add_argument("--write", action="store_true", help="refresh summary/gaps blocks")
    mode.add_argument("--self-test", dest="self_test", action="store_true",
                      help="golden fixture self-test")
    parser.add_argument("--checklist", help="checklist path override")
    parser.add_argument("--tree-root", dest="tree_root",
                        help="tree root override (A4 .work probe, src resolution, A5 files)")
    args = parser.parse_args(argv)

    if args.self_test:
        return run_selftest()

    tree_root = args.tree_root or default_tree_root()
    checklist_path = args.checklist or os.path.join(
        tree_root, "docs", "parity-checklist.md")
    try:
        text = load_checklist(checklist_path)
    except OSError as exc:
        print("parity-audit: input error: %s" % exc, file=sys.stderr)
        return 2
    parsed = parse_checklist(text)

    if args.write:
        return run_write(checklist_path, parsed)
    if args.report:
        return run_report(parsed, text, tree_root)
    return run_check(parsed, text, tree_root)


if __name__ == "__main__":
    sys.exit(main())
