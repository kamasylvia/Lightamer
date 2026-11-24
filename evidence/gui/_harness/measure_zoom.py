#!/usr/bin/env python3
"""100% zoom by viewport double-click, 5 reps (Alcedo lane)."""
import sys, time, json, subprocess, csv
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import alcedo as A, input as inp
from AppKit import NSRunningApplication, NSApplicationActivateAllWindows
A.CAP='/Users/Shared/lightamer-gui-test/_harness/cap_shot.py'
CROP=','.join(map(str,A.VIEW_CROP)); rows=[]
A.kill_app(); p=A.launch('zoom5'); w=A.wait_win(p.pid); A.wait_session(); A.acquire()
NSRunningApplication.runningApplicationWithProcessIdentifier_(p.pid).activateWithOptions_(NSApplicationActivateAllWindows)
A.call('project.open',{'path':A.PROJECT}); A.call('editor.open',{'element_id':1}); time.sleep(2.5)
for rep in range(1,6):
    cap=subprocess.Popen([A.PY_VENV,A.CAP,str(w['id']),f'{A.G}/frames',f'zoomx-{rep}','--mode','onset',
        '--timeout','30','--t0',str(time.time()),'--stable-n','8','--crop',CROP],
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    time.sleep(0.3)
    inp.click(575,375); time.sleep(0.1); inp.click(575,375)   # double-click = 1:1
    out,err=cap.communicate(timeout=40); s=json.loads(out)
    time.sleep(0.5); A.shoot(w['id'],f'zoomx-{rep}-after')
    rows.append(dict(rep=rep,onset=s.get('onset_rel'),ready=s.get('ready_rel'),status=s.get('status'),n=s.get('n_frames')))
    inp.click(575,375); time.sleep(0.1); inp.click(575,375); time.sleep(1.2)  # back to FIT
with open(f'{A.G}/logs/zoomx.csv','w',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=['rep','onset','ready','status','n']); wr.writeheader(); [wr.writerow(r) for r in rows]
A.kill_app()
