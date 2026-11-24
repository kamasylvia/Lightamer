#!/usr/bin/env python3
import sys, os, time, json, subprocess, csv, statistics
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import alcedo as A
import input as inp
from AppKit import NSRunningApplication, NSApplicationActivateAllWindows
A.CAP = '/Users/Shared/lightamer-gui-test/_harness/cap_shot.py'
OUT = f'{A.G}/logs/m1m2.csv'
CROP = ','.join(map(str, A.VIEW_CROP))
NAMES = {1: '7RM5-ARW', 2: 'GFX100S-RAF', 3: 'Z8-NEF'}

def activate(pid):
    app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
    if app: app.activateWithOptions_(NSApplicationActivateAllWindows)
    time.sleep(0.35)

def cap_start(wid, prefix, t0):
    return subprocess.Popen([A.PY_VENV, A.CAP, str(wid), f'{A.G}/frames', prefix,
                             '--mode', 'onset', '--timeout', '90', '--t0', str(t0),
                             '--crop', CROP], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def cap_wait(p, timeout=120):
    out, err = p.communicate(timeout=timeout)
    try: return json.loads(out)
    except Exception: return {'status': 'BAD', 'raw': out, 'err': err}

def cold(sample, rep):
    A.kill_app()
    t0 = time.time(); p = A.launch(f'cold-{sample}-{rep}')
    w = A.wait_win(p.pid, 20); t_win = time.time() - t0
    ts, _ = A.wait_session(25); t_sess = (ts - t0) if ts else None
    A.acquire(); activate(p.pid)
    t = time.time(); rp = A.call('project.open', {'path': A.PROJECT}); t_proj = time.time() - t
    cap = cap_start(w['id'], f'cold-{sample}-{rep}', t0)
    time.sleep(0.2)
    t = time.time(); re = A.call('editor.open', {'element_id': sample}, timeout=90); t_open = time.time() - t
    s = cap_wait(cap, 100)
    return dict(kind='cold', sample=NAMES[sample], rep=rep, t_win=t_win, t_sess=t_sess,
                t_project=t_proj, t_editor_open=t_open, onset=s.get('onset_rel'),
                ready=s.get('ready_rel'), status=s.get('status'), n_frames=s.get('n_frames'))

def hot(sample, rep, wid):
    cap = cap_start(wid, f'hot-{sample}-{rep}', time.time())
    time.sleep(0.25)
    t = time.time(); r = A.call('editor.open', {'element_id': sample}, timeout=90); t_open = time.time() - t
    off = t - cap.args and 0  # unused
    s = cap_wait(cap, 100)
    return dict(kind='hot', sample=NAMES[sample], rep=rep, t_editor_open=t_open,
                onset=s.get('onset_rel'), ready=s.get('ready_rel'), status=s.get('status'),
                n_frames=s.get('n_frames'))

def edit(val, rep, wid):
    cap = cap_start(wid, f'edit-{rep}', time.time())
    time.sleep(0.2)
    t = time.time(); r = A.call('editor.set', {'field': 'exposure', 'value': val}, timeout=60); dt = time.time() - t
    s = cap_wait(cap, 60)
    return dict(kind='edit', sample='7RM5-ARW', rep=rep, value=val, t_editor_set=dt,
                onset=s.get('onset_rel'), ready=s.get('ready_rel'), status=s.get('status'),
                n_frames=s.get('n_frames'))

def ax_zoom_text():
    r = subprocess.run(['osascript', '-e',
        'tell application "System Events" to tell process "AlcedoStudio" to get value of every static text of group 1 of group 1 of window 1'],
        capture_output=True, text=True)
    return r.stdout.strip()

def zoom(rep, pid, wid):
    app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
    if app: app.activateWithOptions_(NSApplicationActivateAllWindows)
    time.sleep(0.3)
    inp.key('0')            # reset to FIT
    time.sleep(1.0)
    inp.click(575, 375)     # focus viewport
    time.sleep(0.2)
    cap = cap_start(wid, f'zoom-{rep}', time.time())
    time.sleep(0.25)
    t = time.time(); inp.key('1'); s = cap_wait(cap, 60)
    time.sleep(0.5)
    label = ax_zoom_text()
    return dict(kind='zoom', sample='7RM5-ARW', rep=rep, onset=s.get('onset_rel'),
                ready=s.get('ready_rel'), status=s.get('status'), label=label,
                n_frames=s.get('n_frames'))

rows = []
# --- M1 cold: 5 reps per sample, interleaved ---
for rep in range(1, 6):
    for sample in (1, 2, 3):
        try:
            r = cold(sample, rep); rows.append(r)
            print('COLD', r, flush=True)
        except Exception as e:
            rows.append(dict(kind='cold', sample=NAMES[sample], rep=rep, error=str(e)))
            print('COLD ERR', sample, rep, e, flush=True)
A.kill_app()
# --- one session for hot / edit / zoom ---
p = A.launch('hotmain'); w = A.wait_win(p.pid); A.wait_session(); A.acquire(); activate(p.pid)
A.call('project.open', {'path': A.PROJECT})
A.call('editor.open', {'element_id': 1}); time.sleep(1.0); activate(p.pid)
for rep in range(1, 11):
    sample = (2, 3, 1)[(rep - 1) % 3]
    try:
        r = hot(sample, rep, w['id']); rows.append(r); print('HOT', r, flush=True)
    except Exception as e:
        rows.append(dict(kind='hot', sample=NAMES[sample], rep=rep, error=str(e))); print('HOT ERR', e, flush=True)
# ensure image1 open
A.call('editor.open', {'element_id': 1}); time.sleep(0.6)
cur = A.call('editor.get', {'fields': ['exposure']})['values']['exposure']
for rep in range(1, 11):
    val = round(cur + 0.5 * rep, 2)
    try:
        r = edit(val, rep, w['id']); rows.append(r); print('EDIT', r, flush=True)
    except Exception as e:
        rows.append(dict(kind='edit', rep=rep, error=str(e))); print('EDIT ERR', e, flush=True)
A.call('editor.set', {'field': 'exposure', 'value': 1.5}); time.sleep(0.5)
for rep in range(1, 6):
    try:
        r = zoom(rep, p.pid, w['id']); rows.append(r); print('ZOOM', r, flush=True)
    except Exception as e:
        rows.append(dict(kind='zoom', rep=rep, error=str(e))); print('ZOOM ERR', e, flush=True)
A.kill_app()
with open(OUT, 'w', newline='') as f:
    keys = sorted({k for r in rows for k in r})
    wr = csv.DictWriter(f, fieldnames=keys); wr.writeheader()
    for r in rows: wr.writerow(r)
print('WROTE', OUT, len(rows))
