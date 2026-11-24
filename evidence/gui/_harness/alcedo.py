#!/usr/bin/env python3
"""Alcedo Studio GUI-timing lane driver (issue #26). Own window only."""
import os, sys, time, json, subprocess, signal
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import input as inp

G = '/Users/Shared/lightamer-gui-test/alcedo'
APP = f'{G}/apps/AlcedoStudio.app'
EXE = f'{APP}/Contents/MacOS/AlcedoStudio'
CLI = f'{APP}/Contents/MacOS/alcedo-cli'
SD  = f'{G}/home/Library/Application Support/Alcedo/Alcedo/automation/sessions'
PROJECT = f'{G}/project/gui-test.alcd'
ENV = dict(os.environ, HOME=f'{G}/home', CFFIXED_USER_HOME=f'{G}/home')
PY_VENV = '/Users/Shared/lightamer-gui-test/_harness/venv/bin/python3'
CAP = '/Users/Shared/lightamer-gui-test/_harness/cap.py'
VIEW_CROP = (215, 125, 1870, 1130)   # captured px (2x logical): image viewport only

def pids():
    r = subprocess.run(['pgrep', '-x', 'AlcedoStudio'], capture_output=True, text=True)
    return [int(x) for x in r.stdout.split()]

def kill_app():
    for p in pids():
        try: os.kill(p, signal.SIGTERM)
        except ProcessLookupError: pass
    t = time.time() + 6
    while pids() and time.time() < t:
        time.sleep(0.05)
    for p in pids():
        try: os.kill(p, signal.SIGKILL)
        except ProcessLookupError: pass
    t = time.time() + 3
    while pids() and time.time() < t:
        time.sleep(0.05)

def launch(tag='run'):
    log = open(f'{G}/logs/{tag}.log', 'w')
    p = subprocess.Popen([EXE], env=ENV, cwd=G, stdout=log, stderr=subprocess.STDOUT)
    return p

def wait_win(pid, timeout=20):
    t = time.time() + timeout
    while time.time() < t:
        for w in inp.wins(pid=pid):
            if w['layer'] == 0 and w['w'] > 900 and w['h'] > 500:
                return w
        time.sleep(0.05)
    return None

def call(method, params=None, timeout=60):
    args = [CLI, '--session-dir', SD, '--session', 'gui', '--json', 'call', method]
    if params is not None:
        args.append(json.dumps(params))
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    out = r.stdout.strip()
    try:
        return json.loads(out)
    except Exception:
        return {'_raw': out, '_err': r.stderr.strip(), '_rc': r.returncode}

def wait_session(timeout=25):
    t = time.time() + timeout
    last = None
    while time.time() < t:
        r = call('control.get', timeout=5)
        if '_raw' not in r:
            return time.time(), r
        last = r
        time.sleep(0.1)
    return None, last

def acquire(holder='gui-timing'):
    r = call('control.acquire', {'holder_name': holder})
    return r

def editor_state():
    r = call('editor.get', {'fields': []})
    return r.get('state') if isinstance(r, dict) else None

def shoot(wid, name):
    path = f'{G}/frames/{name}.png'
    subprocess.run(['screencapture', '-x', '-o', '-l', str(wid), path], check=False)
    return path
