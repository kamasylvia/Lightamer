#!/usr/bin/env python3
import sys, time, json, subprocess
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import dt, input as inp
G = dt.G
p, t0, log = dt.launch([f'{G}/samples/{dt.SAMPLES[k]}' for k in dt.SAMPLE_ORDER], 'libprobe')
w = dt.main_window(p.pid)
if not w:
    print('NO_WINDOW'); dt.quit_app(p, log); sys.exit(1)
time.sleep(1.5); print('dialogs', len(dt.dismiss_dialogs(p.pid, log)))
inp.key('d'); time.sleep(0.5)
s = dt.cap(w['id'], 'probe2', 'startup', time.time(), 20)
print('ready', s.get('ready_rel'), s.get('status'))
inp.scroll(w['x'] + w['w'] - 100, w['y'] + 300, 25)
time.sleep(0.8)
subprocess.run(['screencapture','-x','-o','-l',str(w['id']), f'{G}/frames/probe-top2.png'])
print('PID', p.pid, 'WID', w['id'], 'BOUNDS', w)
open(f'{G}/probe.json','w').write(json.dumps(dict(pid=p.pid,wid=w['id'],bounds=w)))
time.sleep(900)
