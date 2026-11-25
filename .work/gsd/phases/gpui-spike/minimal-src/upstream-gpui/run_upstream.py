#!/usr/bin/env python3
"""Same driver as run_case.py, for the upstream-gpui crate (M1 / C1)."""
import os
import re
import subprocess
import sys
import threading
import time

WS = "/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike"
BIN = WS + "/target/debug/gpui_upstream_minimal"
PROBE = WS + "/measure/frameprobe"
SCRIPT = WS + "/minimal/wait6.run"
OUT = sys.argv[1]
CASE = sys.argv[2]
SHOT_DIR = sys.argv[3] if len(sys.argv) > 3 else None

tag = "U-" + CASE
err_path = f"{OUT}/{tag}.err"
out_path = f"{OUT}/{tag}.out"
run_path = f"{OUT}/{tag}.run"

env = dict(os.environ)
env["UPSTREAM_CASE"] = CASE
env.pop("http_proxy", None)
env.pop("https_proxy", None)

app = subprocess.Popen([BIN], cwd=WS, env=env,
                       stdout=open(out_path, "w"), stderr=open(err_path, "w"))

wid = None
deadline = time.time() + 25
while time.time() < deadline:
    if app.poll() is not None:
        print(f"{tag}: app exited rc={app.returncode}", file=sys.stderr)
        sys.exit(3)
    lst = subprocess.run([PROBE, "list"], capture_output=True, text=True).stdout
    for line in lst.splitlines():
        p = line.split("\t")
        if len(p) >= 5 and p[4].strip() == f"upstream {CASE}":
            wid = p[0]
            break
    if wid:
        break
    time.sleep(0.05)
if not wid:
    app.kill()
    print(f"{tag}: window not found", file=sys.stderr)
    sys.exit(4)

print(f"{tag}: pid={app.pid} wid={wid}", flush=True)

shot_done = threading.Event()
shot_result = {}

def grab():
    seen_mid = False
    t0 = time.time()
    while time.time() - t0 < 12:
        try:
            with open(err_path) as f:
                text = f.read()
        except OSError:
            text = ""
        if re.search(r"TICK n=20 ", text):
            seen_mid = True
            break
        time.sleep(0.005)
    if not seen_mid:
        shot_result["err"] = "tick20 never logged"
        shot_done.set()
        return
    if SHOT_DIR:
        os.makedirs(SHOT_DIR, exist_ok=True)
        path = f"{SHOT_DIR}/{tag}-mid.png"
        r = subprocess.run(["screencapture", "-l", wid, "-o", "-x", path],
                           capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(path):
            shot_result["path"] = path
            shot_result["bytes"] = os.path.getsize(path)
        else:
            shot_result["err"] = (r.stderr or "screencapture failed").strip()
    shot_done.set()

th = threading.Thread(target=grab, daemon=True)
th.start()

r = subprocess.run([PROBE, "run", "--pid", str(app.pid), "--window-id", wid,
                    "--out", run_path, "--script", SCRIPT, "--activate"],
                   capture_output=True, text=True)
print(r.stdout.strip(), r.stderr.strip(), flush=True)
shot_done.wait(timeout=15)
if "path" in shot_result:
    print(f"{tag}: shot={shot_result['path']} bytes={shot_result['bytes']}", flush=True)
elif "err" in shot_result:
    print(f"{tag}: shot failed: {shot_result['err']}", flush=True)
time.sleep(0.3)
app.terminate()
try:
    app.wait(timeout=3)
except subprocess.TimeoutExpired:
    app.kill()
print(f"{tag}: done rc={r.returncode}", flush=True)
