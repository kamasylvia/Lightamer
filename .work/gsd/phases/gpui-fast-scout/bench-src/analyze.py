#!/usr/bin/env python3
"""Read a frameprobe .run file and report frame/event statistics.

changed frame = the probe's own rule: cells >= 1 and maxd >= 10 (both grids).

usage: analyze.py <run> [drag|scroll|all] [--json]
"""
import json
import statistics
import sys

CELL_MIN = 1
MAXD_MIN = 10.0


def load(path):
    frames, events = [], []
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "F" and len(p) >= 7:
                frames.append(
                    dict(
                        idx=int(p[1]),
                        pts=float(p[2]),
                        cb=float(p[3]),
                        diff=float(p[4]),
                        maxd=float(p[5]),
                        cells=int(p[6]),
                        # dual-grid files carry the sparse grid after the dense one
                        maxs=float(p[7]) if len(p) >= 9 else None,
                        cellss=int(p[8]) if len(p) >= 9 else None,
                    )
                )
            elif p[0] == "E" and len(p) >= 3:
                events.append(dict(name=p[1], t=float(p[2]), detail=" ".join(p[3:])))
    frames.sort(key=lambda f: f["idx"])
    return frames, events


def changed(frames, sparse=False):
    if sparse:
        return [f for f in frames if f["cellss"] is not None and f["cellss"] >= CELL_MIN and f["maxs"] >= MAXD_MIN]
    return [f for f in frames if f["cells"] >= CELL_MIN and f["maxd"] >= MAXD_MIN]


def pct(xs, p):
    if not xs:
        return None
    s = sorted(xs)
    i = min(len(s) - 1, max(0, round(p * (len(s) - 1))))
    return s[i]


def intervals(frames):
    out = []
    for a, b in zip(frames, frames[1:]):
        out.append((b["pts"] - a["pts"]) * 1000.0)
    return out


def window_stats(frames, t0, t1, sparse=False, label=""):
    allf = [f for f in frames if t0 <= f["pts"] <= t1]
    ch = changed(allf, sparse)
    iv = intervals(ch)
    res = dict(
        label=label,
        all_frames=len(allf),
        changed=len(ch),
        span_s=round(t1 - t0, 3),
        changed_fps=round(len(ch) / max(0.001, t1 - t0), 1),
        changed_med_ms=round(pct(iv, 0.5), 2) if iv else None,
        changed_p95_ms=round(pct(iv, 0.95), 2) if iv else None,
        changed_gt167=sum(1 for x in iv if x > 16.7),
        changed_gt333=sum(1 for x in iv if x > 33.3),
        all_med_ms=round(pct(intervals(allf), 0.5), 2) if len(allf) > 1 else None,
        all_p95_ms=round(pct(intervals(allf), 0.95), 2) if len(allf) > 1 else None,
    )
    return res


def event_latencies(frames, events, names, tol=0.002, horizon=1.0, sparse=False):
    ch = changed(frames, sparse)
    out = []
    for e in events:
        if e["name"] not in names:
            continue
        first = None
        for f in ch:
            if f["pts"] >= e["t"] - tol:
                first = f
                break
        if first is None or first["pts"] - e["t"] > horizon:
            out.append(dict(name=e["name"], t=e["t"], lat=None))
        else:
            out.append(dict(name=e["name"], t=e["t"], lat=(first["pts"] - e["t"]) * 1000.0))
    return out


def summarize_events(lats):
    matched = [x["lat"] for x in lats if x["lat"] is not None and x["lat"] >= -1.0]
    return dict(
        events=len(lats),
        matched=len(matched),
        match_ratio=round(len(matched) / len(lats), 3) if lats else None,
        med_ms=round(pct(matched, 0.5), 1) if matched else None,
        p95_ms=round(pct(matched, 0.95), 1) if matched else None,
        max_ms=round(max(matched), 1) if matched else None,
    )


def main():
    path = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "all"
    frames, events = load(path)
    begin = next((e["t"] for e in events if e["name"] == "begin"), frames[0]["pts"] if frames else 0)
    end = next((e["t"] for e in events if e["name"] == "end"), frames[-1]["pts"] if frames else 0)
    result = dict(file=path, mode=mode)
    result["whole"] = window_stats(frames, begin, end, label="begin..end")
    result["whole_sparse"] = window_stats(frames, begin, end, sparse=True, label="begin..end sparse")

    if mode in ("drag", "all"):
        downs = [e for e in events if e["name"] == "drag_down"]
        ups = [e for e in events if e["name"] == "drag_up"]
        drags = []
        for i, d in enumerate(downs):
            if i >= len(ups):
                break
            u = ups[i]
            seg = window_stats(frames, d["t"], u["t"] + 0.05, label=f"drag{i}")
            steps = [e for e in events if e["name"] == "drag_step" and d["t"] <= e["t"] <= u["t"]]
            step_lat = event_latencies(frames, steps, {"drag_step"})
            seg["steps"] = summarize_events(step_lat)
            seg["steps_sparse"] = summarize_events(
                event_latencies(frames, steps, {"drag_step"}, sparse=True)
            )
            # per-step values in order, for a lag-vs-time view
            seg["step_lat_series"] = [None if x["lat"] is None else round(x["lat"], 1) for x in step_lat]
            drags.append(seg)
        result["drags"] = drags

    if mode in ("scroll", "all"):
        scrolls = [e for e in events if e["name"] == "scroll"]
        if scrolls:
            seg = window_stats(frames, scrolls[0]["t"], scrolls[-1]["t"] + 0.05, label="scroll")
            seg["events"] = summarize_events(event_latencies(frames, scrolls, {"scroll"}))
            seg["events_sparse"] = summarize_events(
                event_latencies(frames, scrolls, {"scroll"}, sparse=True)
            )
            result["scroll"] = seg

    print(json.dumps(result, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
