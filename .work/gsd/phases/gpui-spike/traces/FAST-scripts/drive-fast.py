#!/usr/bin/env python3
"""Launch the prototype, run one frameprobe script, save trace + stderr.

Same as runs30/matrix/drive.py but writes into runs30/fast and takes the
binary path from env PROTO_BIN (default: the fast-backend build).

usage: drive-fast.py <tag> <script> [ENV=VAL ...]
"""
import os, subprocess, sys, time

WS = "/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike"
BIN = os.environ.get("PROTO_BIN", WS + "/target/debug/lightamer_gpui_proto")
PROBE = WS + "/measure/frameprobe"
OUT = WS + "/runs30/fast"

tag = sys.argv[1]
script = sys.argv[2]
env_extra = dict(kv.split("=", 1) for kv in sys.argv[3:])

env = dict(os.environ)
env.update(env_extra)
env.setdefault("LIGHTAMER_MM_LOG", "1")

err_path = f"{OUT}/{tag}.err"
out_path = f"{OUT}/{tag}.out"
run_path = f"{OUT}/{tag}.run"
app = subprocess.Popen([BIN], cwd=WS, env=env,
                       stdout=open(out_path, "w"), stderr=open(err_path, "w"))
wid = None
deadline = time.time() + 15
while time.time() < deadline:
    if app.poll() is not None:
        print(f"app exited rc={app.returncode}", file=sys.stderr)
        sys.exit(3)
    lst = subprocess.run([PROBE, "list"], capture_output=True, text=True).stdout
    for line in lst.splitlines():
        p = line.split("\t")
        if len(p) >= 5 and p[1].startswith("1440x") and p[2].startswith("32,"):
            wid = p[0]
            break
    if wid:
        break
    time.sleep(0.1)
if not wid:
    app.kill()
    print("window not found", file=sys.stderr)
    sys.exit(4)
print(f"{tag}: pid={app.pid} wid={wid} env={env_extra}", flush=True)
r = subprocess.run([PROBE, "run", "--pid", str(app.pid), "--window-id", wid,
                    "--out", run_path, "--script", script, "--global", "--activate"],
                   capture_output=True, text=True)
print(r.stdout[-2000:], r.stderr[-2000:], flush=True)
time.sleep(0.3)
app.terminate()
try:
    app.wait(timeout=3)
except subprocess.TimeoutExpired:
    app.kill()
print(f"{tag}: done rc={r.returncode}", flush=True)
