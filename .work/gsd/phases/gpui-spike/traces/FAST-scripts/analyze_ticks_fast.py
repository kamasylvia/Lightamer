#!/usr/bin/env python3
"""Per-tick latency for timer-driven experiments (E2/E3/E7).

Aligns the app clock to the probe clock via the space key event:
  offset = probe_key_time - app_key_time/1000
Then maps every TICK app timestamp to host time and matches the first changed
frame at or after it.
"""
import re, sys

def pct(xs, p):
    if not xs: return 0.0
    xs = sorted(xs); k = (len(xs)-1)*p; f = int(k); c = min(f+1, len(xs)-1)
    return xs[f] + (xs[c]-xs[f])*(k-f)

tag = sys.argv[1]
base = "/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/runs30/fast"
frames, events = [], []
for line in open(f"{base}/{tag}.run"):
    p = line.split()
    if not p: continue
    if p[0] == "F":
        frames.append(dict(idx=int(p[1]), pts=float(p[2]), cb=float(p[3]),
                           diff=float(p[4]), maxd=float(p[5]), cells=int(p[6])))
    elif p[0] == "E":
        events.append((p[1], float(p[2]), " ".join(p[3:])))
app_key = None
app_move = None
ticks = []
tick_start = tick_end = None
for line in open(f"{base}/{tag}.err"):
    m = re.match(r"MM t=([0-9.]+) n=\d+ NO_DRAG pos=1298\.0,470\.0", line)
    if m and app_move is None:
        app_move = float(m.group(1))
    m = re.match(r"TICK n=(\d+) t=([0-9.]+)", line)
    if m: ticks.append((int(m.group(1)), float(m.group(2))))
    m = re.match(r"TICK_START t=([0-9.]+)", line)
    if m: tick_start = float(m.group(1))
    m = re.match(r"TICK_END t=([0-9.]+)", line)
    if m: tick_end = float(m.group(1))
probe_sync = next((t for n,t,d in events if n == "move" and d.startswith("1330")), None)
if app_move is None or probe_sync is None:
    print(f"{tag}: missing move sync app_move={app_move} probe_move={probe_sync}")
    sys.exit(2)
offset = probe_sync - app_move/1000.0
changed = [f for f in frames if f["cells"] >= 1 and f["maxd"] >= 10.0]
w0 = tick_start/1000.0 + offset
w1 = tick_end/1000.0 + offset
seg = [f for f in changed if w0 - 0.002 <= f["pts"] <= w1 + 0.2]
allseg = [f for f in frames if w0 - 0.002 <= f["pts"] <= w1 + 0.2]
print(f"{tag}: ticks={len(ticks)} offset={offset:.4f} window={w1-w0:.3f}s")
print(f"  changed_in_window={len(seg)} changed_fps={len(seg)/max(1e-6,(w1-w0)):.1f} all_frames={len(allseg)}")
lat = []
for n, at in ticks:
    th = at/1000.0 + offset
    nxt = next((f for f in changed if f["pts"] >= th - 0.002), None)
    if nxt: lat.append(((nxt["pts"] - th)*1000.0, n, at))
if lat:
    vals = [x[0] for x in lat]
    print(f"  per_tick_lat n={len(vals)} med={pct(vals,0.5):.1f}ms p95={pct(vals,0.95):.1f}ms max={max(vals):.1f}ms min={min(vals):.1f}ms")
    print("  first5=" + " ".join(f"#{n}:{v:.0f}ms" for v,n,_ in lat[:5]))
    print("  last5=" + " ".join(f"#{n}:{v:.0f}ms" for v,n,_ in lat[-5:]))
if seg:
    print("  changed_pts=" + " ".join(f"{f['pts']-w0:.3f}" for f in seg[:20]) + (" ..." if len(seg) > 20 else ""))
renders = []
for line in open(f"{base}/{tag}.err"):
    m = re.search(r"TICK_START t=[0-9.]+ renders=(\d+)", line)
    if m: renders.append(int(m.group(1)))
    m = re.search(r"TICK_END t=[0-9.]+ renders=(\d+)", line)
    if m: renders.append(int(m.group(1)))
if len(renders) == 2:
    print(f"  app_renders_in_ticker={renders[1]-renders[0]} (start={renders[0]} end={renders[1]})")
