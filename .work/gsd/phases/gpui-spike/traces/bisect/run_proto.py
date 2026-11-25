#!/usr/bin/env python3
"""Run the prototype (dist/proto-pre-clean or an env-named binary) with the probe.

usage: run_proto.py <tag> --mode drag|timer [--off 602] [--binary ...] [--env K=V ...]
"""
import os, re, subprocess, sys, time

WS = "/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike"
OUT = WS + "/bisect"
args = sys.argv[1:]
tag = args.pop(0)
mode = "drag"
off = 602
binary = WS + "/dist/proto-pre-clean"
envs = {"LIGHTAMER_MM_LOG": "1"}
while args:
    a = args.pop(0)
    if a == "--mode":
        mode = args.pop(0)
    elif a == "--off":
        off = int(args.pop(0))
    elif a == "--binary":
        binary = args.pop(0)
    else:
        k, v = a.split("=", 1)
        envs[k] = v
if mode == "timer":
    envs["LIGHTAMER_TIMER"] = "value"
probe = os.environ.get("PROBE_BIN", WS + "/measure/frameprobe")

os.makedirs(OUT, exist_ok=True)
err_path, out_path, run_path, script_path = (f"{OUT}/{tag}.{x}" for x in ("err", "out", "run", "script"))
env = dict(os.environ)
env.update(envs)
env.pop("http_proxy", None)
env.pop("https_proxy", None)
app = subprocess.Popen([binary], cwd=WS, env=env,
                       stdout=open(out_path, "w"), stderr=open(err_path, "w"))
wid = frame = None
deadline = time.time() + 20
while time.time() < deadline:
    if app.poll() is not None:
        print(f"{tag}: app exited rc={app.returncode}"); sys.exit(3)
    lst = subprocess.run([probe, "list"], capture_output=True, text=True).stdout
    for line in lst.splitlines():
        p = line.split("\t")
        if len(p) >= 5 and p[3].strip() == os.path.basename(binary) and "x" in p[1]:
            wid = p[0]
            fx, fy = [int(x) for x in p[2].split(",")]
            frame = (fx, fy)
            break
    if wid:
        break
    time.sleep(0.05)
if not wid:
    app.kill(); print(f"{tag}: window not found"); sys.exit(4)
fx, fy = frame
lines = [f"move {fx + 1330} {fy + 500}", "wait 400"]
if off:
    for _ in range(43):
        lines += ["scroll -14", "wait 12"]
lines.append("wait 500")
if mode == "drag":
    y = (782 if off == 0 else 180)
    lines.append(f"drag {fx + 1267} {fy + y} {fx + 1400} {fy + y} 40 8")
    lines.append("wait 500")
else:
    lines.append("key space")
    lines.append("wait 3200")
open(script_path, "w").write("\n".join(lines) + "\n")
print(f"{tag}: pid={app.pid} wid={wid} origin={frame} mode={mode} off={off}", flush=True)
r = subprocess.run([probe, "run", "--pid", str(app.pid), "--window-id", wid, "--out", run_path,
                    "--script", script_path, "--activate", "--global"],
                   capture_output=True, text=True)
print(r.stdout.strip(), r.stderr.strip(), flush=True)
app.terminate()
try:
    app.wait(timeout=3)
except subprocess.TimeoutExpired:
    app.kill()

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
ticks = [(int(m.group(1)), float(m.group(2)))
         for m in re.finditer(r"TICK n=(\d+) t=([0-9.]+)", err)]
mm = re.findall(r"MM t=([0-9.]+) n=(\d+) APPLY", err)
scroll = re.search(r"SCROLL_OFFSET y=(-?[0-9.]+)", err)
if mode == "drag":
    ev = [(n, t) for (n, t) in events if n == "drag_step"]
    w0 = ev[0][1] if ev else 0.0
    w1 = (ev[-1][1] if ev else 0.0) + 0.25
else:
    ev = ticks
    w0 = ticks[0][1] if ticks else 0.0
    w1 = (ticks[-1][1] if ticks else 0.0) + 0.25
seg = [f for f in changed if w0 - 0.005 <= f[1] <= w1]
matched = []
for i, (n, t) in enumerate(ev):
    nxt = ev[i + 1][1] if i + 1 < len(ev) else w1 + 1.0
    f = next((f for f in changed if f[1] >= t - 0.002 and f[1] < nxt), None)
    if f:
        matched.append((f[1] - t) * 1000)
lat = sorted(matched)
med = lat[len(lat) // 2] if lat else float("nan")
print(f"{tag}: mode={mode} events={len(ev)} changed={len(seg)} matched={len(matched)}/{len(ev)} "
      f"medlat={med:.1f}ms scroll={scroll.group(1) if scroll else None} mm_applied={len(mm)}",
      flush=True)
