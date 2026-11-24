#!/usr/bin/env python3
"""Render the SPIKE.md §4.1-§4.4 tables from bench.csv (single source of truth).

Usage: tables.py evidence/bench.csv > evidence/tables-4.md
Pasted into SPIKE.md §4 by the lane (keeps prose around the tables hand-written).
"""
import csv
import sys

rows = list(csv.DictReader(open(sys.argv[1])))
# row names repeat across metric groups (M1-cold / M1-hot / M2) — key on both.
by = {}
for r in rows:
    by[(r["row"], r["path"])] = r


def get(name, col="median_ms", kind="M1-cold"):
    r = by.get((name, kind))
    return f"{float(r[col]):.0f}" if r and r.get(col) else "—"


def tri(name, kind="M1-cold"):
    r = by.get((name, kind))
    if not r:
        return "—"
    return f"**{float(r['median_ms']):.0f} ms**（{float(r['min_ms']):.0f} / {float(r['p90_ms']):.0f}）"


def tri_plain(name, kind="M1-cold"):
    r = by.get((name, kind))
    if not r:
        return "—"
    return f"{float(r['median_ms']):.0f} ms（{float(r['min_ms']):.0f} / {float(r['p90_ms']):.0f}）"


print("### 4.1 M1 打开等待（冷启动，每测量独立进程，n=10；括号 = min / p90）\n")
print("| 路径 | 适配屏 2560 | 全分辨率 |")
print("|---|---|---|")
print(f"| **P0 CIRAW v8（现状）** | {tri('P0 CIRAW v8 A7R5 fit')} | {tri('P0 CIRAW v8 A7R5 full')} |")
print(f"| **P1a 首开（rawspeed→内存 DNG→CIRAW v8DNG）** | {tri('P1a live ds0 fit (decode+DNG+CI)')} | {tri('P1a live ds0 full')} |")
print(f"| P1a，马赛克先降 1/4 面积（ds1） | {tri_plain('P1a live ds1 fit')} | — |")
print(f"| P1a，马赛克先降 1/16 面积（ds2） | {tri_plain('P1a live ds2 fit')} | — |")
print(f"| P1a + **RAW 9**（v9DNG，n=5） | {tri('P1a live ds0 v9DNG fit (RAW9)')} | — |")
print(f"| P1b 已缓存 DNG（122 MB 在盘） | {tri_plain('P1b cached-DNG ds0 fit')} | {tri_plain('P1b cached-DNG ds0 full')} |")
print()
print("### 4.2 M1 热（同进程重开 + clearCaches，n=10）\n")
print("| 路径 | 适配屏 2560 | 全分辨率 |")
print("|---|---|---|")
print(f"| P0 CIRAW v8 | {get('P0 CIRAW v8 A7R5 fit', kind='M1-hot')} ms | {get('P0 CIRAW v8 A7R5 full', kind='M1-hot')} ms |")
print(f"| P1b 已缓存 DNG ds0 | {get('P1b cached-DNG ds0 fit', kind='M1-hot')} ms | {get('P1b cached-DNG ds0 full', kind='M1-hot')} ms |")
print(f"| P1b 已缓存 DNG ds1 | {get('P1b cached-DNG ds1 fit', kind='M1-hot')} ms | — |")
print()
print("### 4.3 M2 编辑等待（每次一个**新**曝光值 → 位图更新；缓存按自然设计保留）\n")
print("| 路径 | 适配屏 2560 | 100% ROI 1024×768 |")
print("|---|---|---|")
print(f"| P0 CIRAW | {tri_plain('P0 CIRAW v8 fit', kind='M2')} | {tri_plain('P0 CIRAW v8 100% ROI', kind='M2')} |")
print(f"| P1b 已缓存 DNG | {tri_plain('P1 cached-DNG ds0 fit', kind='M2')} | {tri_plain('P1 cached-DNG ds0 100% ROI', kind='M2')} |")
print()
print("### 4.4 规模阶梯（P0 vs P1a/P1b）\n")
print("| 输出/解码规模 | P0 冷 | P1 冷 |")
print("|---|---|---|")
print(f"| 长边 2560 | {get('P0 CIRAW v8 A7R5 fit')} ms | P1a {get('P1a live ds0 fit (decode+DNG+CI)')} / P1b {get('P1b cached-DNG ds0 fit')} ms |")
print(f"| 长边 1280 | {get('P0 CIRAW v8 1280 long edge')} ms | —（ds2 2392 长边 ≈ 此档）|")
print(f"| 长边 640 | {get('P0 CIRAW v8 640 long edge')} ms | — |")
print(f"| 马赛克 ds1（4784 长边） | — | P1a {get('P1a live ds1 fit')} / P1b {get('P1b cached-DNG ds1 fit')} ms |")
print(f"| 马赛克 ds2（2392 长边） | — | P1a {get('P1a live ds2 fit')} / P1b {get('P1b cached-DNG ds2 fit')} ms |")
print()
print("### 4.7 P2 替身（LibRaw 解码 + CPU 去马赛克；**无渲染腿**，n=10）\n")
print("| 配置 | 冷 e2e（解码+去马赛克） | 其中 open+unpack | 其中 process |")
print("|---|---|---|---|")
for label in ("P2 LibRaw full linear", "P2 LibRaw full AMaZE", "P2 LibRaw half linear", "P2 LibRaw half AMaZE"):
    r = next((v for (k, _), v in by.items() if k == label), None)
    if r:
        print(f"| {label[3:]} | **{float(r['median_ms']):.0f} ms** | {r['open_ms']} ms | {r['render_ms']} ms |")
