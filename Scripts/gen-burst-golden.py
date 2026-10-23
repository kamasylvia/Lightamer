#!/usr/bin/env python3
"""Generate the LUMEN-A T6 burst-annotation golden constants.

Writes Tests/Fixtures/burst_golden.json — the expected burst grouping, best
frames and hints for a deterministic 10-row dataset, computed by the NumPy
REFERENCE implementation of the Lumen annotate_bursts family (the library_db
code transliterated VERBATIM except the review m-5 ① comparator pin: the
eyes dimension is the relative ratio (nil = 1.0, the Lumen `not None`
analog) instead of the boolean bucket).

The dataset signatures are LCG bytes (the same integer recipe the Swift test
mirrors); the grouping semantics carry the calibration:

    rows 1-3   one camera, 0.5s steps, identical signature -> one burst
    row 4      a DIFFERENT serial, same moment -> never joins
    row 5      a dissimilar signature (MAD > 0.6) -> ends the first burst
    rows 6-9   a copy pair (6/7 stem prefix-containment) excluded at the
               same moment, then the exact 2.0s gap boundary chain
    row 10     no timestamp -> never groups

Regenerate:  uv run --with numpy python3 Scripts/gen-burst-golden.py
"""

import json
from pathlib import Path

import numpy as np

BURST_GAP = 2.0
BURST_DIFFERENCE = 0.6
BLURRY = 22.0
BURST_BLURRY = 14.0


def lcg_bytes(seed: int, count: int = 256) -> bytes:
    state = seed & ((1 << 64) - 1)
    out = bytearray()
    for _ in range(count):
        state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        out.append((state >> 56) & 0xFF)
    return bytes(out)


def signature_difference(a: bytes, b: bytes) -> float:
    x = np.frombuffer(a, np.uint8).astype(np.float64)
    y = np.frombuffer(b, np.uint8).astype(np.float64)
    x = (x - x.mean()) / (x.std() + 4)
    y = (y - y.mean()) / (y.std() + 4)
    return float(np.mean(np.abs(x - y)))


def stem(name: str) -> str:
    return name.rsplit(".", 1)[0].lower() if "." in name else name.lower()


def is_copy(a: dict, b: dict) -> bool:
    if abs((a.get("ts") or 0) - (b.get("ts") or 0)) > 1e-3:
        return False
    x, y = stem(a["name"]), stem(b["name"])
    return bool(x and y) and (x == y or x.startswith(y) or y.startswith(x))


def similar(a, b) -> bool:
    if not a or not b or len(a) != len(b):
        return True
    return signature_difference(a, b) <= BURST_DIFFERENCE


def best_key(row: dict, index: int):
    # review m-5 ①: the eyes dimension = the relative ratio (nil = 1.0),
    # then sharpness desc (nil = -1), then the group index ascending.
    return (row["ratio"] if row["ratio"] is not None else 1.0,
            row["sharpness"] if row["sharpness"] is not None else -1.0,
            -index)


def groups_for(rows: list) -> list:
    timed = sorted(
        (r for r in rows if r["ts"] is not None),
        key=lambda r: ((r["make"] or "", r["model"] or "", r["serial"] or ""),
                       r["ts"], r["name"] or ""))
    groups, current = [], []
    for row in timed:
        if current:
            if any(is_copy(other, row) for other in current[-3:]):
                continue
            last = current[-1]
            same = ((last["make"], last["model"], last["serial"])
                    == (row["make"], row["model"], row["serial"]))
            if same and 0 <= row["ts"] - last["ts"] <= BURST_GAP \
                    and similar(last["sig"], row["sig"]):
                current.append(row)
                continue
            if len(current) > 1:
                groups.append(current)
        current = [row]
    if len(current) > 1:
        groups.append(current)
    groups.sort(key=lambda g: g[0]["ts"])
    return groups


def main() -> None:
    s1 = lcg_bytes(0xA1B2)
    s2 = lcg_bytes(0xC3D4)

    def row(rid, ts, sig, sharpness, ratio, name, serial="S1"):
        return {
            "id": rid, "make": "Canon", "model": "EOS R5", "serial": serial,
            "ts": ts, "sig": sig, "sharpness": sharpness, "ratio": ratio,
            "name": name,
        }

    rows = [
        row(1, 1000.000, s1, 60.0, 0.30, "IMG_0001.ARW"),
        row(2, 1000.500, s1, 80.0, 0.10, "IMG_0002.ARW"),
        row(3, 1001.000, s1, 50.0, 0.35, "IMG_0003.ARW"),
        row(4, 1000.200, s1, 70.0, 0.40, "IMG_0004.ARW", serial="S2"),
        row(5, 1001.500, s2, 65.0, 0.20, "IMG_0005.ARW"),
        row(6, 1002.000, s1, 55.0, 0.25, "IMG_0006.ARW"),
        row(7, 1002.000, s1, 58.0, 0.22, "IMG_0006-Lumen.jpg"),
        row(8, 1004.000, s1, 65.0, None, "IMG_0008.ARW"),
        row(9, 1006.000, s1, 20.0, None, "IMG_0009.ARW"),
        row(10, None, s1, 90.0, None, "IMG_0010.ARW"),
    ]

    groups = groups_for(rows)
    annotations = {}
    best_ids = []
    for number, group in enumerate(groups, 1):
        keys = [best_key(r, i) for i, r in enumerate(group)]
        best_index = max(range(len(group)), key=lambda i: keys[i])
        best = group[best_index]
        best_ids.append(best["id"])
        # Lumen annotate_hints: the group's MAX SHARPNESS (any row), never
        # the best-frame's own sharpness.
        group_best = max(
            (r["sharpness"] for r in group if r["sharpness"] is not None),
            default=0)
        for index, r in enumerate(group):
            value = r["sharpness"]
            blurry = (value is not None and (
                value < BLURRY or group_best - value > BURST_BLURRY))
            annotations[str(r["id"])] = {
                "burst": number, "index": index + 1, "size": len(group),
                "best": r is best, "blurry": blurry,
            }
    for r in rows:
        annotations.setdefault(str(r["id"]), {
            "burst": 0, "index": 0, "size": 1, "best": False,
            "blurry": r["sharpness"] is not None and r["sharpness"] < BLURRY,
        })

    golden = {
        "generator": "Scripts/gen-burst-golden.py (LUMEN-A T6, m-5 comparator pin)",
        "mad_s1_s2": signature_difference(s1, s2),
        "groups": [[r["id"] for r in g] for g in groups],
        "best_ids": best_ids,
        "annotations": annotations,
    }
    out = Path(__file__).resolve().parents[1] / "Tests/Fixtures/burst_golden.json"
    out.write_text(json.dumps(golden, indent=2) + "\n")
    print(json.dumps(golden, indent=2))


if __name__ == "__main__":
    main()
