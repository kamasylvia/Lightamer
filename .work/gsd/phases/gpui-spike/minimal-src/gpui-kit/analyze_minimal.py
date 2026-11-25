#!/usr/bin/env python3
"""Join FrameProbe frames with the app's host-clock TICK log.

Both sides use CMClockGetHostTimeClock seconds (verified: mach_absolute_time *
timebase equals CMClockGetSeconds(CMClockGetTime(hostClock)) within 4 us), so
no synthetic input is needed to align them.

Changed frame = cells >= 1 and max grid delta >= 10 grey levels (probe rule).
"""
import re
import sys


def pct(xs, p):
    if not xs:
        return 0.0
    xs = sorted(xs)
    k = (len(xs) - 1) * p
    f = int(k)
    c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


out = sys.argv[1]
case = sys.argv[2]
run_path = f"{out}/{case}.run"
err_path = f"{out}/{case}.err"

frames = []
events = []
for line in open(run_path):
    p = line.split()
    if not p:
        continue
    if p[0] == "F" and len(p) >= 7:
        frames.append(dict(idx=int(p[1]), pts=float(p[2]), cb=float(p[3]),
                           diff=float(p[4]), maxd=float(p[5]), cells=int(p[6])))
    elif p[0] == "E" and len(p) >= 3:
        events.append((p[1], float(p[2]), " ".join(p[3:])))
frames.sort(key=lambda f: f["idx"])

ticks = []
tick_start = tick_end = None
renders_start = renders_end = None
scroll = None
for line in open(err_path):
    m = re.match(r"TICK n=(\d+) t=([0-9.]+) renders=(\d+)", line)
    if m:
        ticks.append((int(m.group(1)), float(m.group(2)), int(m.group(3))))
    m = re.match(r"TICK_START t=([0-9.]+) renders=(\d+)", line)
    if m:
        tick_start, renders_start = float(m.group(1)), int(m.group(2))
    m = re.match(r"TICK_END t=([0-9.]+) renders=(\d+)", line)
    if m:
        tick_end, renders_end = float(m.group(1)), int(m.group(2))
    m = re.match(r"SCROLL_SET .*offset=(-?[0-9.]+) max=(-?[0-9.]+)", line)
    if m:
        scroll = (float(m.group(1)), float(m.group(2)))

if tick_start is None or tick_end is None:
    print(f"{case}: missing TICK_START/TICK_END")
    sys.exit(2)

changed = [f for f in frames if f["cells"] >= 1 and f["maxd"] >= 10.0]
w0 = tick_start
w1 = tick_end + 0.25
seg = [f for f in changed if w0 - 0.005 <= f["pts"] <= w1]
allseg = [f for f in frames if w0 - 0.005 <= f["pts"] <= w1]
span = tick_end - tick_start

print(f"{case}: ticks={len(ticks)} window={span:.3f}s scroll={scroll}")
print(f"  changed={len(seg)} changed_fps={len(seg)/max(1e-6, span):.1f} "
      f"candidate_frames={len(allseg)}")
lat = []
for n, t, _ in ticks:
    nxt = next((f for f in changed if f["pts"] >= t - 0.002), None)
    if nxt and nxt["pts"] <= w1:
        lat.append(((nxt["pts"] - t) * 1000.0, n))
vals = [x[0] for x in lat]
if vals:
    print(f"  per_tick_lat n={len(vals)} med={pct(vals,0.5):.1f}ms "
          f"p95={pct(vals,0.95):.1f}ms max={max(vals):.1f}ms")
else:
    print("  per_tick_lat n=0 (no changed frame in the tick window)")
print(f"  ticks_without_change={len(ticks)-len(vals)}")
if renders_start is not None and renders_end is not None:
    print(f"  app_renders_in_ticker={renders_end - renders_start} "
          f"(start={renders_start} end={renders_end})")
print(f"  changed_pts_rel=" + " ".join(f"{f['pts']-w0:.3f}" for f in seg[:24])
      + (" ..." if len(seg) > 24 else ""))
