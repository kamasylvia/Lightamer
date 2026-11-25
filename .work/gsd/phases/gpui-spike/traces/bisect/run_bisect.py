#!/usr/bin/env python3
"""Run one bisect case: launch app, drive with the frame probe, analyze.

usage: run_bisect.py <tag> [KEY=VAL ...] --mode timer|wheel_timer|drag|wheel_drag
                        [--x0 90 --x1 340 --y 220] [--rows 80]
All coordinates are window-content local; the probe is invoked with --global and
the coordinates are translated by the window's on-screen origin (titlebar 32).
"""
import os, re, subprocess, sys, time

WS = "/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike"
BIN = WS + "/target/debug/gpui_minimal"
PROBE = os.environ.get("PROBE_BIN", WS + "/measure/frameprobe")
OUT = WS + "/bisect"

args = sys.argv[1:]
tag = args.pop(0)
mode = "timer"
envs = {}
x0, x1, y = 90.0, 340.0, 220.0
while args:
    a = args.pop(0)
    if a == "--mode":
        mode = args.pop(0)
    elif a == "--x0":
        x0 = float(args.pop(0))
    elif a == "--x1":
        x1 = float(args.pop(0))
    elif a == "--y":
        y = float(args.pop(0))
    else:
        k, v = a.split("=", 1)
        envs[k] = v

os.makedirs(OUT, exist_ok=True)
err_path = f"{OUT}/{tag}.err"
out_path = f"{OUT}/{tag}.out"
run_path = f"{OUT}/{tag}.run"
script_path = f"{OUT}/{tag}.script"

env = dict(os.environ)
env.update(envs)
env.pop("http_proxy", None)
env.pop("https_proxy", None)
app = subprocess.Popen([BIN], cwd=WS, env=env,
                       stdout=open(out_path, "w"), stderr=open(err_path, "w"))
wid = None
frame = None
deadline = time.time() + 20
title = f"minimal {envs.get('MINIMAL_CASE', 'M1')}"
while time.time() < deadline:
    if app.poll() is not None:
        print(f"{tag}: app exited rc={app.returncode}", flush=True)
        sys.exit(3)
    lst = subprocess.run([PROBE, "list"], capture_output=True, text=True).stdout
    for line in lst.splitlines():
        p = line.split("\t")
        if len(p) >= 5 and p[4].strip() == title:
            wid = p[0]
            m = re.match(r"(\d+)x(\d+)", p[1])
            fx, fy = [int(x) for x in p[2].split(",")]
            frame = (fx, fy, int(m.group(1)), int(m.group(2)))
            break
    if wid:
        break
    time.sleep(0.05)
if not wid:
    app.kill()
    print(f"{tag}: window not found ({title})", flush=True)
    sys.exit(4)

fx, fy, fw, fh = frame
ox, oy = fx, fy + (fh - 600)  # content origin: titlebar = frame height - content height
lines = []
if mode in ("wheel_timer", "wheel_drag"):
    lines.append(f"move {int(fx + 200)} {int(oy + 300)}")
    lines.append("wait 300")
    for _ in range(43):
        lines.append("scroll -14")
        lines.append("wait 12")
    lines.append("wait 500")
else:
    lines.append("wait 400")
if mode in ("drag", "wheel_drag"):
    lines.append(f"drag {int(fx + x0)} {int(oy + y)} {int(fx + x1)} {int(oy + y)} 40 8")
    lines.append("wait 500")
else:
    lines.append("wait 5200")
open(script_path, "w").write("\n".join(lines) + "\n")

print(f"{tag}: pid={app.pid} wid={wid} frame={frame} oy={oy}", flush=True)
r = subprocess.run([PROBE, "run", "--pid", str(app.pid), "--window-id", wid,
                    "--out", run_path, "--script", script_path, "--activate",
                    "--global"],
                   capture_output=True, text=True)
print(r.stdout.strip(), r.stderr.strip(), flush=True)
app.terminate()
try:
    app.wait(timeout=3)
except subprocess.TimeoutExpired:
    app.kill()

# ---- analyze ------------------------------------------------------------
frames, events = [], []
for line in open(run_path):
    p = line.split()
    if not p:
        continue
    if p[0] == "F" and len(p) >= 7:
        frames.append((int(p[1]), float(p[2]), float(p[5]), int(p[6])))
    elif p[0] == "E" and len(p) >= 3:
        events.append((p[1], float(p[2])))
frames.sort()
changed = [f for f in frames if f[3] >= 1 and f[2] >= 10.0]

err = open(err_path).read()
tick_start = tick_end = None
ticks = []
scroll = None
down = None
for line in err.splitlines():
    m = re.match(r"TICK n=(\d+) t=([0-9.]+)", line)
    if m:
        ticks.append((int(m.group(1)), float(m.group(2))))
    m = re.match(r"TICK_START t=([0-9.]+)", line)
    if m:
        tick_start = float(m.group(1))
    m = re.match(r"TICK_END t=([0-9.]+)", line)
    if m:
        tick_end = float(m.group(1))
    m = re.match(r"SCROLL_SET .*offset=(-?[0-9.]+)", line)
    if m:
        scroll = float(m.group(1))
    m = re.match(r"SLIDER_DOWN .*bounds=\(([-0-9.]+),([-0-9.]+) ([-0-9.]+)x", line)
    if m:
        down = tuple(float(x) for x in m.groups())

if mode in ("drag", "wheel_drag"):
    ev = [(n, t) for (n, t) in events if n == "drag_step"]
    w0 = ev[0][1] if ev else 0.0
    w1 = (ev[-1][1] if ev else 0.0) + 0.25
    label = "drag"
else:
    ev = ticks
    w0, w1 = (tick_start or 0.0), (tick_end or 0.0) + 0.25
    label = "timer"

seg = [f for f in changed if w0 - 0.005 <= f[1] <= w1]
matched = []
for i, (n, t) in enumerate(ev):
    nxt_t = ev[i + 1][1] if i + 1 < len(ev) else w1 + 1.0
    f = next((f for f in changed if f[1] >= t - 0.002 and f[1] < nxt_t), None)
    if f is not None:
        matched.append((f[1] - t) * 1000.0)
lat = sorted(matched)


def med(xs):
    if not xs:
        return float("nan")
    k = len(xs) // 2
    return xs[k] if len(xs) % 2 else (xs[k - 1] + xs[k]) / 2


renders = None
m = re.search(r"TICK_END t=[0-9.]+ renders=(\d+)", err)
m0 = re.search(r"TICK_START t=[0-9.]+ renders=(\d+)", err)
if m and m0:
    renders = int(m.group(1)) - int(m0.group(1))

print(f"{tag}: mode={mode} events={len(ev)} changed={len(seg)} "
      f"matched={len(matched)}/{len(ev)} medlat={med(lat):.1f}ms "
      f"scroll={scroll} trackbounds={down} app_renders={renders}", flush=True)
