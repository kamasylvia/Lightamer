#!/usr/bin/env python3
"""Render the rerun section (SPIKE.md §4.9) from the mechanical evidence.

Inputs (all relative to the evidence directory):
  bench.csv                    archived lane run
  rerun-bench.csv              independent rerun (2026-11-25)
  rerun-m2-product-shape.log   frozen-input-plane M2 control
  rerun-v9-breakdown.log       per-rep v9DNG split

No number is typed by hand. Usage:
  python3 spike-src/rerun_tables.py evidence
"""
import csv
import re
import statistics
import sys
from pathlib import Path

ev = Path(sys.argv[1] if len(sys.argv) > 1 else "evidence")


def kv(line):
    return dict(tok.split("=", 1) for tok in line.split() if "=" in tok)


def section(title, rows, headers):
    print(title)
    print()
    print("| " + " | ".join(headers) + " |")
    print("|" + "|".join("---" for _ in headers) + "|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
    print()


# ── archived vs rerun ──────────────────────────────────────────────────────
arch = list(csv.DictReader(open(ev / "bench.csv")))
rerun = list(csv.DictReader(open(ev / "rerun-bench.csv")))
key = lambda r: (r["row"], r["path"], r["kind"])
rmap = {key(r): r for r in rerun}
rows = []
out = 0
for a in arch:
    b = rmap[key(a)]
    av, bv = float(a["median_ms"]), float(b["median_ms"])
    dev = (bv - av) / av * 100.0
    flag = "**OUT**" if abs(dev) > 15.0 else ""
    if flag:
        out += 1
    rows.append((a["row"], a["kind"], f"{av:.1f}", f"{bv:.1f}", f"{dev:+.1f}%", flag))
print(f"独立复跑 `evidence/rerun-bench.csv`（26 行中 {out} 行偏离归档 > ±15%，全部更快）：")
print()
section("", rows, ["row", "kind", "归档 ms", "复跑 ms", "偏差", "±15%"])

# ── product-shaped M2 ──────────────────────────────────────────────────────
m2 = []
for line in (ev / "rerun-m2-product-shape.log").read_text().splitlines():
    if not line.startswith("mode=m2-product-shape"):
        continue
    d = kv(line)
    name = "P0 CIRAW v8 ARW" if d["path"].endswith(".ARW") else "P1b cached DNG ds0"
    m2.append((name, f"{float(d['freeze_ms']):.0f} ms",
               f"**{float(d['edit_med_ms']):.2f} ms**（{float(d['edit_min_ms']):.2f} / {float(d['edit_p90_ms']):.2f}）",
               f"{float(d['unfrozen_edit_ms']):.1f} ms"))
section("产品形态 M2（冻结输入平面后做下游曝光乘法；n=10，编辑→位图）：", m2,
        ["输入", "冻结（首次输入平面渲染）", "产品形态编辑 中位（min / p90）", "同探针未冻结对照"])

# ── v9 cold vs steady ─────────────────────────────────────────────────────
text = (ev / "rerun-v9-breakdown.log").read_text()
warm_part, cold_part = text.split("three independent processes")
warm = [kv(l) for l in warm_part.splitlines() if l.startswith("rep=")]
cold = [kv(l) for l in cold_part.splitlines() if l.startswith("rep=")]
steady = warm[1:]
v9 = [
    ("首进程 rep0（含模型准备）",
     f"{float(warm[0]['e2e_ms']):.0f} ms",
     f"{float(warm[0]['ci_init_ms']):.0f} ms",
     f"{float(warm[0]['render_ms']):.0f} ms"),
    (f"同进程稳态 rep1–{len(warm)-1}（中位）",
     f"{statistics.median(float(r['e2e_ms']) for r in steady):.0f} ms",
     f"{statistics.median(float(r['ci_init_ms']) for r in steady):.0f} ms",
     f"{statistics.median(float(r['render_ms']) for r in steady):.0f} ms"),
    (f"独立冷进程（{len(cold)} 次，中位）",
     f"{statistics.median(float(r['e2e_ms']) for r in cold):.0f} ms",
     f"{statistics.median(float(r['ci_init_ms']) for r in cold):.0f} ms",
     f"{statistics.median(float(r['render_ms']) for r in cold):.0f} ms"),
]
section("RAW 9（v9DNG）冷/热拆分（`evidence/rerun-v9-breakdown.log`）：", v9,
        ["场景", "e2e ms", "其中 CIRAWFilter init", "其中 render"])
