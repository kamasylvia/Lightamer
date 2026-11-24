#!/usr/bin/env python3
import sys, os, time, json, subprocess, csv
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import alcedo as A, input as inp
from AppKit import NSRunningApplication, NSApplicationActivateAllWindows
A.CAP = '/Users/Shared/lightamer-gui-test/_harness/cap_shot.py'
NAMES = {1: '7RM5-ARW', 2: 'GFX100S-RAF', 3: 'Z8-NEF'}
CROP = ','.join(map(str, A.VIEW_CROP))
rows = []
def activate(pid):
    app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
    if app: app.activateWithOptions_(NSApplicationActivateAllWindows)
    time.sleep(0.35)
def cap_start(wid, prefix, t0, stable=3, timeout=120):
    return subprocess.Popen([A.PY_VENV, A.CAP, str(wid), f'{A.G}/frames', prefix,
        '--mode', 'onset', '--timeout', str(timeout), '--t0', str(t0), '--stable-n', str(stable),
        '--crop', CROP], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
def cap_wait(p, timeout=150):
    out, err = p.communicate(timeout=timeout)
    try: return json.loads(out)
    except Exception: return {'status': 'BAD', 'raw': out, 'err': err}
A.kill_app()
p = A.launch('hotmain2'); w = A.wait_win(p.pid); A.wait_session(); A.acquire(); activate(p.pid)
A.call('project.open', {'path': A.PROJECT})
A.call('editor.open', {'element_id': 1}); time.sleep(1.0); activate(p.pid)
for rep in range(1, 11):
    sample = (2, 3, 1)[(rep - 1) % 3]
    cap = cap_start(w['id'], f'hot-{sample}-{rep}', time.time())
    time.sleep(0.25)
    t = time.time(); r = A.call('editor.open', {'element_id': sample}, timeout=120); dt = time.time() - t
    s = cap_wait(cap)
    row = dict(kind='hot', sample=NAMES[sample], rep=rep, t_editor_open=dt,
               onset=s.get('onset_rel'), ready=s.get('ready_rel'), status=s.get('status'), n_frames=s.get('n_frames'))
    rows.append(row); print(row, flush=True)
# reset image + exposure
A.call('editor.open', {'element_id': 1}); time.sleep(0.6)
A.call('editor.set', {'field': 'exposure', 'value': 1.5}); time.sleep(0.6)
for rep in range(1, 6):
    activate(p.pid)
    inp.key(29); time.sleep(1.2)      # 0 = FIT
    inp.click(575, 375); time.sleep(0.2)
    cap = cap_start(w['id'], f'zoom-{rep}', time.time(), stable=8, timeout=40)
    time.sleep(0.25)
    inp.key(18)                        # 1 = 100%
    s = cap_wait(cap, 60)
    time.sleep(0.4)
    A.shoot(w['id'], f'zoom-{rep}-after')
    row = dict(kind='zoom', sample='7RM5-ARW', rep=rep, onset=s.get('onset_rel'),
               ready=s.get('ready_rel'), status=s.get('status'), n_frames=s.get('n_frames'))
    rows.append(row); print(row, flush=True)
A.kill_app()
with open(f'{A.G}/logs/m1b.csv', 'w', newline='') as f:
    keys = sorted({k for r in rows for k in r}); wr = csv.DictWriter(f, fieldnames=keys); wr.writeheader()
    for r in rows: wr.writerow(r)
print('WROTE', len(rows))
