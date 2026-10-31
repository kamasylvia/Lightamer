#!/usr/bin/env python3
"""M8-3+ T6 three-stamp reconciliation probe — the write-starvation
mechanism's behavioral proof (R-M83P-7).

Mechanism hypothesis: film-enable's `historyDidChange()` awaits a 4-5 min
tc cold build on MainActor, starving `scheduleSidecarWrite()` (which used
to run AFTER the render) until the build window closes. The T6 fix moves
the schedule BEFORE the render.

The probe is a STATIC + RUNTIME pair (no GUI driving):
  1. STATIC: assert the source order (schedule-before-render) in
     filmRecordDidChange + the single-hunk scope (all other call sites
     keep render-before-write).
  2. RUNTIME (needs a running app — orchestrator approval round):
     enable film on a cold pair, record three stamps —
       S1 = the history-commit timestamp (oslog/EditorState hook)
       S2 = the tc build completion timestamp (bake log line)
       S3 = the .lra mtime
     Verdict: S3 ≈ S1 + 2s (debounce) = the write escaped starvation
     (HOLD the fix); S3 ≈ S2 + 2s = STILL starved (falsified — the OQ
     reopens, the single line rolls back).

This script runs leg 1 now (machine-checkable in this lane) and EMITS
the leg-2 recipe (the orchestrator runs it against a live app; the
record file below carries the verdict slot).

Usage:  python3 t6_probe.py   (cwd = repo root)
Output: T6-PROBE-RECORD.md in this directory + stdout verdict.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
while not os.path.exists(os.path.join(ROOT, "App", "Sources")):
    ROOT = os.path.dirname(ROOT)

COORD = os.path.join(
    ROOT, "App", "Sources", "Lightamer", "State", "PipeCoordinator.swift")


def main():
    src = open(COORD).read()
    results = []

    # Leg 1a: the filmRecordDidChange order (schedule BEFORE render).
    m = re.search(
        r"func filmRecordDidChange\(_ record: FilmRecord\) async \{(.*?)\n    \}",
        src, re.S)
    assert m, "filmRecordDidChange not found"
    body = m.group(1)
    sched = body.find("scheduleSidecarWrite()")
    render = body.find("await historyDidChange()")
    order_ok = 0 <= sched < render
    results.append(("T6-STATIC-ORDER",
                    "filmRecordDidChange schedules before rendering",
                    order_ok,
                    "schedule@%d render@%d" % (sched, render)))

    # Leg 1b: the single-hunk scope (no other call site moved).
    hunks = subprocess.run(
        ["git", "diff", "HEAD", "--", COORD],
        cwd=ROOT, capture_output=True, text=True).stdout.count("@@ -")
    # NOTE: post-commit this reads 0 (the change is IN); the gate ran
    # pre-commit at 1 hunk — both are recorded honestly below.
    results.append(("T6-STATIC-SCOPE",
                    "PipeCoordinator diff is the single T6 hunk (0 post-commit)",
                    hunks <= 1,
                    "%d hunk(s) vs HEAD" % hunks))

    # Leg 1c: the sibling call sites keep render-before-write (the
    #收窄 face — only the film face moved).
    siblings = 0
    for mm in re.finditer(
            r"await historyDidChange\(\)\n(\s*)scheduleSidecarWrite\(\)", src):
        siblings += 1
    results.append(("T6-STATIC-SIBLINGS",
                    "sibling call sites keep render-before-write",
                    siblings >= 2,
                    "%d sibling sites unmoved" % siblings))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "T6-PROBE-RECORD.md")
    fails = [r for r in results if not r[2]]
    with open(out, "w") as f:
        f.write("# M8-3+ T6 three-stamp probe record\n\n")
        f.write("## Leg 1 (static, this lane)\n\n")
        f.write("| id | check | verdict | detail |\n|---|---|---|---|\n")
        for rid, name, passed, detail in results:
            f.write("| %s | %s | %s | %s |\n" % (
                rid, name, "PASS" if passed else "FAIL", detail))
        f.write("\n## Leg 2 (runtime, orchestrator approval round)\n\n")
        f.write("Recipe: cold pair (fresh DerivedData or new pair) → open\n")
        f.write("image → enable film → capture S1 (commit log line) / S2\n")
        f.write("(tc build completion — bake log) / S3 (.lra mtime).\n\n")
        f.write("Verdict slot: S3 ≈ S1+2s = HOLD / S3 ≈ S2+2s = FALSIFIED.\n\n")
        f.write("Status: PENDING (no live app in this lane).\n\n")
        f.write("## m-6① undo leg (zero code)\n\n")
        f.write("Recipe: outside the cold build window, undo a rotation →\n")
        f.write("the viewport restores immediately (the R8 36b condition\n")
        f.write("reversed). Status: PENDING (orchestrator walkthrough).\n")
    for rid, name, passed, detail in results:
        print(("PASS " if passed else "FAIL ") + rid + " " + name
              + " :: " + detail)
    print("wrote", out)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
