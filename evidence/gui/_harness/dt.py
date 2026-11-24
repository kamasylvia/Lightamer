#!/usr/bin/env python3
"""darktable #26 GUI timing orchestrator (isolated, own processes only)."""
import os, sys, time, json, signal, subprocess, sqlite3, argparse, threading, csv

G = '/Users/Shared/lightamer-gui-test/darktable'
HARNESS = '/Users/Shared/lightamer-gui-test/_harness'
PY = f'{HARNESS}/venv/bin/python'
DT = f'{G}/apps/darktable.app/Contents/MacOS/darktable'
HOME = f'{G}/home'
CONFIG = f'{HOME}/dt-config'
sys.path.insert(0, HARNESS)
import input as inp
from AppKit import NSRunningApplication

SAMPLES = {
    'A': '7RM5-LosslessCompressedLarge.ARW',
    'F': 'Fujifilm-GFX100S-14bits-uncompress-4_3.RAF',
    'N': 'Nikon_Z8_raw_14_bit_lossless_compression.NEF',
}
SAMPLE_ORDER = ['A', 'F', 'N']

def env():
    e = dict(os.environ)
    for k in ('http_proxy','https_proxy','HTTP_PROXY','HTTPS_PROXY','all_proxy','ALL_PROXY'):
        e.pop(k, None)
    e['HOME'] = HOME
    e['CFFIXED_USER_HOME'] = HOME
    return e

def kill_stale():
    out = subprocess.run(['pgrep', '-f', DT], capture_output=True, text=True).stdout.split()
    for pid in out:
        try: os.kill(int(pid), signal.SIGKILL)
        except OSError: pass
    time.sleep(0.5)
    for f in ('data.db.lock', 'library.db.lock'):
        try: os.remove(f'{CONFIG}/{f}')
        except OSError: pass

def launch(args, logname):
    kill_stale()
    os.makedirs(f'{G}/logs', exist_ok=True)
    log = open(f'{G}/logs/{logname}-{int(time.time())}.log', 'w')
    t0 = time.time()
    p = subprocess.Popen([DT, '--configdir', CONFIG, '--library', f'{G}/{logname}.db',
                          '--luacmd', f'dofile("{G}/dt_probe.lua")'] + args,
                         env=env(), stdout=log, stderr=subprocess.STDOUT,
                         start_new_session=True)
    return p, t0, log

def alive(pid):
    try:
        os.kill(pid, 0); return True
    except OSError:
        return False

def wins(pid):
    try:
        return inp.wins(pid=pid)
    except Exception:
        return []

def main_window(pid, timeout=40):
    t_end = time.time() + timeout
    while time.time() < t_end:
        for w in wins(pid):
            if w['w'] >= 1000 and w['h'] >= 600 and w['layer'] == 0:
                return w
        if not alive(pid):
            return None
        time.sleep(0.1)
    return None

def dialog_windows(pid):
    return [w for w in wins(pid) if 420 <= w['w'] <= 620 and 360 <= w['h'] <= 560 and w['layer'] == 0]

def dismiss_dialogs(pid, log):
    """Escape-first dismissal for the welcome wizard; returns list of handled windows."""
    handled = []
    t_end = time.time() + 10
    while time.time() < t_end:
        ds = dialog_windows(pid)
        if not ds:
            return handled
        d = ds[0]
        handled.append(d)
        inp.key('escape'); time.sleep(0.7)
        if not dialog_windows(pid):
            log.write(f'DIALOG escaped {d}\n'); log.flush(); continue
        inp.click(d['x'] + d['w'] - 34, d['y'] + d['h'] - 22); time.sleep(0.7)
        if not dialog_windows(pid):
            log.write(f'DIALOG clicked-rel {d}\n'); log.flush(); continue
        inp.click(970, 656); time.sleep(0.8)
        log.write(f'DIALOG clicked-known {d} still={bool(dialog_windows(pid))}\n'); log.flush()
        return handled
    return handled

def cap(wid, prefix, mode, t0, timeout, outdir=None):
    outdir = outdir or f'{G}/frames'
    os.makedirs(outdir, exist_ok=True)
    cmd = [PY, f'{HARNESS}/cap.py', str(wid), outdir, prefix,
           '--mode', mode, '--timeout', str(timeout), '--t0', str(t0)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        return {'status': 'CAPFAIL', 'stdout': r.stdout[-500:], 'stderr': r.stderr[-500:]}

def quit_app(p, log, timeout=6):
    if p.poll() is not None:
        return True
    app = NSRunningApplication.runningApplicationWithProcessIdentifier_(p.pid)
    if app:
        app.terminate()
    t_end = time.time() + timeout
    while time.time() < t_end:
        if p.poll() is not None:
            return True
        time.sleep(0.2)
    try: os.kill(p.pid, signal.SIGKILL)
    except OSError: pass
    log.write(f'FORCE-KILLED {p.pid}\n'); log.flush()
    return False

def db_count_images(db):
    try:
        c = sqlite3.connect(f'file:{db}?mode=ro', uri=True, timeout=2)
        n = c.execute('select count(*) from images').fetchone()[0]; c.close(); return n
    except Exception: return -1

def db_history_counts(db):
    try:
        c = sqlite3.connect(f'file:{db}?mode=ro', uri=True, timeout=2)
        n_img = c.execute('select count(distinct imgid) from history').fetchone()[0]
        n_rows = c.execute('select count(*) from history').fetchone()[0]
        c.close(); return n_img, n_rows
    except Exception: return -1, -1

def db_thumb_counts(db):
    """(images, thumbs_current): history_hash rows whose mipmap_hash == current_hash."""
    try:
        c = sqlite3.connect(f'file:{db}?mode=ro', uri=True, timeout=2)
        n = c.execute('select count(*) from images').fetchone()[0]
        m = c.execute('select count(*) from history_hash where mipmap_hash is not null '
                      'and mipmap_hash = current_hash').fetchone()[0]
        c.close(); return n, m
    except Exception:
        return -1, -1

def wait_db_images(db, n, timeout):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if db_count_images(db) >= n: return time.time() - t0
        time.sleep(0.25)
    return None

def write_rows(path, rows, fieldnames=None):
    if not rows: return
    new = not os.path.exists(path) or os.path.getsize(path) == 0
    with open(path, 'a', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames or list(rows[0].keys()))
        if new: w.writeheader()
        for r in rows: w.writerow(r)

def wait_ready_startup(pid, wid, t0, timeout=30, prefix='ready'):
    return cap(wid, prefix, 'startup', t0, timeout)

def scroll_panel_top(x, y, times=12):
    for _ in range(times):
        inp.scroll(x, y, 10)

def m2_edit(coords, direction):
    """Drag the exposure slider by ~0.5 EV. coords: bar_left, bar_right, y, ev_range."""
    left = coords['bar_left']; right = coords['bar_right']; y = coords['y']
    value = coords.get('current', 0.0)
    span = right - left
    ev_range = coords.get('ev_range', 6.0)
    dx = int(round(span / ev_range * 0.5))
    kx = int(round(left + span * (value + ev_range/2) / ev_range))
    x2 = kx + (dx if direction > 0 else -dx)
    x2 = max(left + 2, min(right - 2, x2))
    t0 = time.time()
    inp.drag(kx, y, x2, y, steps=12)
    t1 = time.time()
    coords['current'] = value + (0.5 if direction > 0 else -0.5)
    return t0, t1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['probe', 'cold', 'hot', 'm2', 'prep', 'batch', 'probe2'])
    ap.add_argument('--sample', default='A')
    ap.add_argument('--runs', type=int, default=5)
    ap.add_argument('--n', type=int, default=100)
    ap.add_argument('--out', default=f'{G}/results.csv')
    ap.add_argument('--coords', default=f'{G}/m2_coords.json')
    a = ap.parse_args()

    if a.cmd == 'probe':
        p, t0, log = launch([f'{G}/samples/{SAMPLES[k]}' for k in SAMPLE_ORDER], 'libprobe')
        w = main_window(p.pid)
        if not w:
            print('NO_WINDOW'); quit_app(p, log); return
        time.sleep(1.5)
        handled = dismiss_dialogs(p.pid, log); inp.activate(p.pid)
        inp.key('home'); time.sleep(0.3)
        inp.key('d'); time.sleep(0.5)
        s = wait_ready_startup(p.pid, w['id'], time.time(), 20, 'probe-ready')
        print('window', w, 'wizard', len(handled), 'ready', s.get('ready_rel'))
        time.sleep(0.5)
        subprocess.run(['screencapture','-x','-o','-l',str(w['id']), f'{G}/frames/probe-darkroom.png'])
        scroll_panel_top(w['x'] + w['w'] - 120, w['y'] + 300)
        time.sleep(0.7)
        subprocess.run(['screencapture','-x','-o','-l',str(w['id']), f'{G}/frames/probe-top.png'])
        print('shots saved')
        inp.key('f7'); time.sleep(1.2)
        try:
            print('LUALOG', open(f'{G}/lua-log.txt').read()[-400:])
        except Exception as e:
            print('LUALOG_ERR', e)
        quit_app(p, log)
    elif a.cmd == 'cold':
        key = a.sample; sample = SAMPLES[key]
        logname = f'libcold-{key}'; db = f'{G}/{logname}.db'
        rows = []
        for run in range(1, a.runs + 1):
            p, t0, log = launch([f'{G}/samples/{sample}'], logname)
            w = main_window(p.pid)
            if not w:
                print('NO_WINDOW', run); quit_app(p, log); continue
            t_win = time.time()
            handle = dismiss_dialogs(p.pid, log); inp.activate(p.pid)
            inp.key('d'); time.sleep(0.25)
            s = cap(w['id'], f'cold-{key}-{run}', 'startup', t0, 30)
            row = dict(sample=key, run=run, t_window=round(t_win-t0,3),
                       m1=s.get('ready_rel'), status=s.get('status'),
                       dialogs=len(handle), frames=s.get('n_frames'), wid=w['id'])
            rows.append(row); print(json.dumps(row), flush=True)
            log.write(f'M1 {row}\n'); log.flush()
            quit_app(p, log); log.close()
        write_rows(a.out, rows)
    elif a.cmd == 'hot':
        p, t0, log = launch([f'{G}/samples/{SAMPLES[k]}' for k in SAMPLE_ORDER], 'libhot')
        w = main_window(p.pid)
        if not w:
            print('NO_WINDOW'); quit_app(p, log); return
        time.sleep(1.0)
        dismiss_dialogs(p.pid, log); inp.activate(p.pid)
        inp.key('home'); time.sleep(0.3)
        inp.key('d'); time.sleep(0.4)
        s0 = cap(w['id'], 'hot-first', 'startup', t0, 30)
        print('first ready', s0.get('ready_rel'), s0.get('status'))
        rows = []
        for i in range(a.runs):
            pre = time.time()
            cmd = [PY, f'{HARNESS}/cap.py', str(w['id']), f'{G}/frames',
                   f'hot-{i:02d}', '--mode', 'onset', '--timeout', '15', '--t0', str(pre)]
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
            time.sleep(0.35)
            t_key = time.time()
            inp.key('right')
            out = proc.communicate(timeout=20)[0]
            try: s = json.loads(out.strip().splitlines()[-1])
            except Exception: s = {'status': 'CAPFAIL'}
            row = dict(idx=i, m1=s.get('ready_rel'), status=s.get('status'),
                       onset=s.get('onset_rel'), wid=w['id'])
            rows.append(row); print(json.dumps(row), flush=True)
        write_rows(a.out, rows)
        quit_app(p, log)
    elif a.cmd == 'm2':
        p, t0, log = launch([f'{G}/samples/{SAMPLES[k]}' for k in SAMPLE_ORDER], 'libhot')
        w = main_window(p.pid)
        if not w:
            print('NO_WINDOW'); quit_app(p, log); return
        time.sleep(1.0); dismiss_dialogs(p.pid, log); inp.activate(p.pid)
        inp.key('home'); time.sleep(0.3)
        inp.key('d'); time.sleep(0.4)
        s0 = cap(w['id'], 'm2-first', 'startup', t0, 30)
        print('open ready', s0.get('ready_rel'))
        time.sleep(0.4)
        rows = []
        for i in range(a.runs):
            direction = 1 if i % 2 == 0 else -1
            prep = time.time()
            cmd = [PY, f'{HARNESS}/cap.py', str(w['id']), f'{G}/frames',
                   f'm2-{i:02d}', '--mode', 'onset', '--timeout', '15', '--t0', str(prep)]
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
            time.sleep(0.35)
            t_drag0 = time.time(); inp.key('f7'); t_drag1 = time.time()
            out = proc.communicate(timeout=25)[0]
            try: s = json.loads(out.strip().splitlines()[-1])
            except Exception: s = {'status': 'CAPFAIL'}
            m2 = None
            if s.get('ready_rel') is not None:
                m2 = s['ready_rel'] - (t_drag1 - prep)
            row = dict(idx=i, dir=direction, m2=m2, status=s.get('status'),
                       drag_ms=round((t_drag1-t_drag0)*1000), onset=s.get('onset_rel'))
            rows.append(row); print(json.dumps(row), flush=True)
        write_rows(a.out, rows)
        quit_app(p, log)
    elif a.cmd == 'prep':
        folder = f'{G}/batch/n{a.n}'; logname = f'libbatch-{a.n}'; db = f'{G}/{logname}.db'
        p, t0, log = launch([folder], logname)
        w = main_window(p.pid)
        if not w:
            print('NO_WINDOW'); quit_app(p, log); sys.exit(2)
        time.sleep(1.0); dismiss_dialogs(p.pid, log); inp.activate(p.pid)
        inp.key('l')
        waited = wait_db_images(db, a.n, 900)
        print(json.dumps(dict(cmd='prep', n=a.n, imported=db_count_images(db),
                              waited=waited, wizard=True)))
        quit_app(p, log); log.close()
    elif a.cmd == 'batch':
        n = a.n; logname = f'libbatch-{n}'; db = f'{G}/{logname}.db'
        p, t0, log = launch([f'{G}/batch/n{n}'], logname)
        w = main_window(p.pid)
        if not w:
            print('NO_WINDOW'); quit_app(p, log); return
        time.sleep(1.0); dismiss_dialogs(p.pid, log); inp.activate(p.pid)
        wimp = wait_db_images(db, n, 900)
        print(f'import n={n} waited={wimp} images={db_count_images(db)}', flush=True)
        inp.key('l'); time.sleep(1.5)
        inp.key('home'); time.sleep(0.4)          # first image selected
        inp.key('d'); time.sleep(0.4)             # open in darkroom
        s_open = cap(w['id'], f'batch{n}-open', 'startup', t0, 40)
        print('batch open ready', s_open.get('ready_rel'), s_open.get('status'), flush=True)
        # M2 edit on the source image (+0.5 EV)
        prep = time.time()
        proc = subprocess.Popen([PY, f'{HARNESS}/cap.py', str(w['id']), f'{G}/frames',
                                 f'batch{n}-edit', '--mode', 'onset', '--timeout', '20',
                                 '--t0', str(prep)], stdout=subprocess.PIPE, text=True)
        time.sleep(0.35)
        t_d0 = time.time(); inp.key('f7'); t_d1 = time.time()
        edit_out = proc.communicate(timeout=30)[0]
        try: s_edit = json.loads(edit_out.strip().splitlines()[-1])
        except Exception: s_edit = {'status': 'CAPFAIL'}
        print('source edit', s_edit.get('status'), s_edit.get('ready_rel'), flush=True)
        # back to lighttable, copy history, select all, paste
        inp.key('l'); time.sleep(2.0)
        time.sleep(0.3)
        inp.key('f9'); time.sleep(0.4)
        inp.key('a', cmd=True); time.sleep(0.5)
        before = db_history_counts(db)
        t_key = time.time()
        poll = {'first': None, 'done': None, 'counts': []}
        def poller():
            while time.time() - t_key < 600:
                ni, nr = db_history_counts(db)
                rec = (round(time.time() - t_key, 3), ni, nr)
                poll['counts'].append(rec)
                if poll['first'] is None and nr > before[1] and ni >= 1:
                    poll['first'] = round(time.time() - t_key, 3)
                if poll['done'] is None and ni >= n:
                    poll['done'] = round(time.time() - t_key, 3)
                    return
                time.sleep(0.05)
        th = threading.Thread(target=poller, daemon=True); th.start()
        capcmd = [PY, f'{HARNESS}/cap.py', str(w['id']), f'{G}/frames',
                  f'batch{n}-paste', '--mode', 'onset', '--timeout', '240',
                  '--t0', str(t_key)]
        capproc = subprocess.Popen(capcmd, stdout=subprocess.PIPE, text=True)
        time.sleep(0.4)
        t_v = time.time()
        inp.key('f8')
        paste_out = capproc.communicate(timeout=260)[0]
        try: s_paste = json.loads(paste_out.strip().splitlines()[-1])
        except Exception: s_paste = {'status': 'CAPFAIL'}
        th.join(timeout=610)
        print('paste frame', s_paste.get('status'), s_paste.get('onset_rel'),
              s_paste.get('ready_rel'), 'db', poll['first'], poll['done'], flush=True)
        # M3b: thumbnail currency via history_hash (crawler + visible thumbs)
        thumb = []
        t_poll0 = time.time()
        while time.time() - t_poll0 < 30:
            ni, tm = db_thumb_counts(db)
            thumb.append((round(time.time() - t_key, 1), ni, tm))
            if tm >= n: break
            time.sleep(3)
        print('thumbs', thumb[-5:], flush=True)
        # M3c: open an image while thumbnail backlog remains
        capproc2 = subprocess.Popen([PY, f'{HARNESS}/cap.py', str(w['id']), f'{G}/frames',
                                     f'batch{n}-m3c', '--mode', 'onset', '--timeout', '30',
                                     '--t0', str(time.time()) + 0.0], stdout=subprocess.PIPE, text=True)
        time.sleep(0.3); t_open = time.time()
        inp.key('d')
        out2 = capproc2.communicate(timeout=40)[0]
        try: s_c = json.loads(out2.strip().splitlines()[-1])
        except Exception: s_c = {'status': 'CAPFAIL'}
        print('M3c', s_c.get('status'), s_c.get('ready_rel'), flush=True)
        row = dict(n=n, key=t_key, v_epoch=t_v,
                   ui_onset=s_paste.get('onset_rel'), ui_idle=s_paste.get('ready_rel'),
                   db_first=poll['first'], db_done=poll['done'],
                   thumbs_at_60=thumb[-1][2] if thumb else None,
                   thumb_series=json.dumps(thumb),
                   m3c_ready=s_c.get('ready_rel'), m3c_status=s_c.get('status'),
                   open_ready=s_open.get('ready_rel'), edit_ready=s_edit.get('ready_rel'),
                   images=db_count_images(db))
        write_rows(f'{G}/batch-results.csv', [row])
        quit_app(p, log)
    elif a.cmd == 'probe2':
        logname = f'libbatch-{a.n}'; db = f'{G}/{logname}.db'
        p, t0, log = launch([f'{G}/batch/n{a.n}'], logname)
        w = main_window(p.pid)
        if not w: print('NO_WINDOW'); quit_app(p, log); return
        time.sleep(1.0); dismiss_dialogs(p.pid, log); inp.activate(p.pid)
        inp.key('l'); time.sleep(1.5)
        subprocess.run(['screencapture','-x','-o','-l',str(w['id']), f'{G}/frames/probe2-lighttable-n{a.n}.png'])
        print('lighttable shot saved', w)
        quit_app(p, log)

if __name__ == '__main__':
    main()
