#!/usr/bin/env python3
"""Batch paste tier measurement for Alcedo Studio. Usage: measure3.py <tier> <folder>"""
import sys, os, time, json, subprocess, csv
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import alcedo as A
from AppKit import NSRunningApplication, NSApplicationActivateAllWindows

tier = sys.argv[1] if len(sys.argv) > 1 else '100'
folder = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else f'{A.G}/batch/n100'
projdir = f'{A.G}/batchproj{tier}'
os.makedirs(projdir, exist_ok=True)
os.makedirs(f'{A.G}/thumbs{tier}', exist_ok=True)
outcsv = f'{A.G}/logs/m3-{tier}.csv'
rows = []

def activate(pid):
    app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
    if app: app.activateWithOptions_(NSApplicationActivateAllWindows)
    time.sleep(0.3)

def rec(**kw):
    rows.append(kw); print(kw, flush=True)

A.kill_app()
t0 = time.time(); p = A.launch(f'batch{tier}'); w = A.wait_win(p.pid, 20); ts, _ = A.wait_session(25)
A.acquire(); activate(p.pid)
rec(kind='launch', tier=tier, t_win=time.time()-t0, t_session=(ts-t0) if ts else None)

t = time.time(); r = A.call('project.create', {'folder': projdir, 'name': f'batch{tier}'}, timeout=120); rec(kind='project_create', tier=tier, sec=time.time()-t, ret=r)
t = time.time(); r = A.call('library.import', {'folder': folder, 'recursive': True}, timeout=60); imp_cmd = time.time()-t
tid = r.get('task_id'); t = time.time(); st = A.call('tasks.wait', {'task_id': tid}, timeout=1800); imp_wait = time.time()-t
rec(kind='import', tier=tier, cmd=imp_cmd, wait=imp_wait, state=st.get('state'), counts=st.get('counts'), ret_raw=st if not st.get('state') else None)

# enumerate ids
ids = []
off = 0
while True:
    r = A.call('library.list', {'limit': 1000, 'offset': off, 'sort': 'import_time'}, timeout=120)
    items = r.get('items', [])
    ids += [it['element_id'] for it in items]
    off += len(items)
    if not items or off >= r.get('total', 0): break
rec(kind='list', tier=tier, ids=len(ids), total=(r.get('total') if isinstance(r, dict) else None))
if len(ids) != int(tier):
    rec(kind='count_mismatch', tier=tier, got=len(ids))

# source edit + copy
t = time.time(); r = A.call('editor.open', {'element_id': ids[0]}, timeout=120); rec(kind='open_source', tier=tier, sec=time.time()-t, ret=r)
cur = A.call('editor.get', {'fields': ['exposure']})['values']['exposure']
t = time.time(); r = A.call('editor.set', {'field': 'exposure', 'value': round(cur + 0.5, 2)}, timeout=60); rec(kind='edit_source', tier=tier, sec=time.time()-t, ret=r.get('value'))
t = time.time(); cp = A.call('adjustments.copy', {'element_id': ids[0]}, timeout=60); rec(kind='copy', tier=tier, sec=time.time()-t, package=cp.get('package_id'), items=len(cp.get('items', [])))
A.call('editor.close', {'persist': True}, timeout=120)

# paste to the rest
targets = ids[1:]
t = time.time(); rp = A.call('adjustments.paste', {'package_id': cp.get('package_id'), 'element_ids': targets, 'version_name': 'GUI paste', 'note': 'gui timing'}, timeout=1800); paste_cmd = time.time()-t
rec(kind='paste', tier=tier, cmd=paste_cmd, ret={k: rp.get(k) for k in ('task_id','target_count')})
if rp.get('task_id'):
    t = time.time(); st = A.call('tasks.wait', {'task_id': rp['task_id']}, timeout=3600); wait = time.time()-t
    res = st.get('result') or {}
    rec(kind='paste_task', tier=tier, wait=wait, state=st.get('state'), result_count=len(res) if isinstance(res, list) else res)

# forced thumbnail refresh (all targets) in background; measure interactivity by opening a photo meanwhile
sample_n = 100 if int(tier) <= 100 else 40
thumb_targets = targets[:sample_n]
thumb_proc = subprocess.Popen([A.CLI, '--session-dir', A.SD, '--session', 'gui', '--json', 'call',
                               'library.thumbnails', json.dumps({'element_ids': thumb_targets, 'out_dir': f'{A.G}/thumbs{tier}', 'long_edge': 256, 'timeout_ms': 900000})],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(1.0)
# M3c: open another image during the forced refresh
activate(p.pid)
cap = subprocess.Popen([A.PY_VENV, A.CAP, str(w['id']), f'{A.G}/frames', f'm3c-{tier}', '--mode', 'onset', '--timeout', '120', '--t0', str(time.time()), '--crop', ','.join(map(str, A.VIEW_CROP))], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(0.2)
t = time.time(); ro = A.call('editor.open', {'element_id': targets[-1]}, timeout=300); open_during = time.time()-t
capout, _ = cap.communicate(timeout=180)
try: cs = json.loads(capout)
except Exception: cs = {}
rec(kind='m3c_open', tier=tier, sec=open_during, ready=cs.get('ready_rel'), status=cs.get('status'))
# thumbnail job result
th0 = time.time(); tout, terr = thumb_proc.communicate(timeout=1800); thumb_wait = time.time()-th0
try: tr = json.loads(tout)
except Exception: tr = {'raw': tout, 'err': terr}
ok = len(tr.get('files', [])) if isinstance(tr, dict) and isinstance(tr.get('files'), list) else None
rec(kind='thumbnails', tier=tier, wait=thumb_wait, files=ok, sample_n=sample_n, ret_keys=list(tr.keys()) if isinstance(tr, dict) else None)
A.kill_app()
with open(outcsv, 'w', newline='') as f:
    keys = sorted({k for r in rows for k in r})
    wr = csv.DictWriter(f, fieldnames=keys); wr.writeheader(); [wr.writerow(r) for r in rows]
print('WROTE', outcsv)
