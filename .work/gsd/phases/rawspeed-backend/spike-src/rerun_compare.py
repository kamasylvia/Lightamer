#!/usr/bin/env python3
"""Compare the archived bench.csv with the independent rerun-bench.csv.

Mechanical: no hand-entered numbers. Deviation = (rerun - archive) / archive.
The task's consistency band is +/-15%; rows outside it are flagged OUT.
"""
import csv
import sys

arch_path = sys.argv[1] if len(sys.argv) > 1 else "bench.csv"
rerun_path = sys.argv[2] if len(sys.argv) > 2 else "rerun-bench.csv"

arch = list(csv.DictReader(open(arch_path)))
rerun = list(csv.DictReader(open(rerun_path)))
key = lambda r: (r["row"], r["path"], r["kind"])
rmap = {key(r): r for r in rerun}

print("| row | kind | archive ms | rerun ms | dev | flag |")
print("|---|---|---:|---:|---:|---|")
out = 0
for a in arch:
    b = rmap.get(key(a))
    if not b:
        print(f"| {a['row']} | {a['kind']} | {a['median_ms']} | — | — | MISSING |")
        continue
    av, bv = float(a["median_ms"]), float(b["median_ms"])
    dev = (bv - av) / av * 100.0
    flag = "OUT" if abs(dev) > 15.0 else ""
    if flag:
        out += 1
    print(f"| {a['row']} | {a['kind']} | {av:.1f} | {bv:.1f} | {dev:+.1f}% | {flag} |")
print()
print(f"rows={len(arch)} outside_15pct={out}")
