#!/usr/bin/env python3
"""RawLab timing helpers: window capture, AX lookup, launch/quit, M1/M2 measurement."""
import os, sys, time, json, subprocess, ctypes, argparse
import Quartz, ApplicationServices as AS
import numpy as np

G = '/Users/Shared/lightamer-gui-test'
APP = f'{G}/rawlab/apps/RawLab Mac.app'
HOME = f'{G}/rawlab/home'
SAMPLES = f'{G}/rawlab/samples'

def attr(el, name):
    err, v = AS.AXUIElementCopyAttributeValue(el, name, None)
    return v if err == 0 else None

def app_el():
    out = subprocess.run(['pgrep','-f','RawLab Mac.app/Contents/MacOS/RawLabMac'],
                         capture_output=True, text=True).stdout.split()
    if not out: return None, None
    pid = int(out[0])
    return pid, AS.AXUIElementCreateApplication(pid)

def find(el, ident, depth=0, maxd=12):
    if depth > maxd: return None
    if attr(el, AS.kAXIdentifierAttribute) == ident: return el
    for k in (attr(el, AS.kAXChildrenAttribute) or []):
        r = find(k, ident, depth+1, maxd)
        if r is not None: return r
    return None

def find_all(el, pred, depth=0, maxd=12, out=None):
    if out is None: out = []
    if depth > maxd: return out
    if pred(el): out.append(el)
    for k in (attr(el, AS.kAXChildrenAttribute) or []):
        find_all(k, pred, depth+1, maxd, out)
    return out

def main_window(pid):
    wl = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
    cands = []
    for w in wl:
        if w.get('kCGWindowOwnerPID') != pid: continue
        if w.get('kCGWindowLayer') != 0: continue
        b = w.get('kCGWindowBounds') or {}
        wd, ht = b.get('Width',0), b.get('Height',0)
        if wd < 800 or ht < 500: continue
        cands.append((w['kCGWindowNumber'], wd, ht, b))
    return cands[0] if cands else None

def cap_gray(wid, maxw=320):
    img = Quartz.CGWindowListCreateImage(Quartz.CGRectMake(0,0,0,0),
        Quartz.kCGWindowListOptionIncludingWindow, wid, Quartz.kCGWindowImageBoundsIgnoreFraming)
    if img is None: return None, None
    w = Quartz.CGImageGetWidth(img); h = Quartz.CGImageGetHeight(img)
    if w <= 0 or h <= 0: return None, None
    W = min(maxw, w); H = max(1, int(round(h*W/w)))
    buf = (ctypes.c_ubyte * (W*H))()
    cs = Quartz.CGColorSpaceCreateDeviceGray()
    ctx = Quartz.CGBitmapContextCreate(buf, W, H, 8, W, cs, Quartz.kCGImageAlphaNone)
    if ctx is None: return None, None
    Quartz.CGContextSetInterpolationQuality(ctx, 1)
    Quartz.CGContextDrawImage(ctx, Quartz.CGRectMake(0,0,W,H), img)
    arr = np.frombuffer(bytes(buf), dtype=np.uint8).reshape(H, W).astype(np.int16)
    return arr, (w, h)

def shot(wid, path):
    subprocess.run(['screencapture','-x','-o','-l',str(wid),path], check=False, capture_output=True)

def measure(wid, t0, mode='onset', timeout=25, stable_n=3, stable_thresh=0.35,
            img_thresh=1.0, change_thresh=1.5, base_frames=2, outdir=None, prefix='run',
            verbose=False):
    frames = []; first = None; onset = None; ready = None
    rows = []; stable = 0; saved_first = saved_onset = saved_ready = False
    tstart = time.time(); idx = 0
    while True:
        now = time.time()
        arr, dims = cap_gray(wid)
        if arr is None:
            time.sleep(0.1); continue
        if first is None:
            first = arr
            if outdir and not saved_first:
                shot(wid, os.path.join(outdir, prefix+'-first.png')); saved_first = True
        diff_prev = float(np.abs(arr - frames[-1]).mean()) if frames else 0.0
        diff_base = float(np.abs(arr - first).mean())
        rows.append((idx, round(now-t0,3), round(diff_prev,3), round(diff_base,3),
                     int(arr.mean()), int(arr.std())))
        frames.append(arr)
        if len(frames) > 4: frames.pop(0)
        if mode == 'startup':
            if diff_base > img_thresh: stable = stable + 1 if diff_prev < stable_thresh else 0
        else:
            if onset is None and len(rows) > base_frames and diff_base > change_thresh:
                onset = now
                if outdir and not saved_onset:
                    shot(wid, os.path.join(outdir, prefix+'-onset.png')); saved_onset = True
            if onset is not None:
                stable = stable + 1 if diff_prev < stable_thresh else 0
        if verbose and idx % 5 == 0:
            print(f"  {now-t0:.2f}s dprev={diff_prev:.2f} dbase={diff_base:.2f} mean={arr.mean():.0f}", flush=True)
        if stable >= stable_n and (time.time()-tstart) > 0.3:
            ready = now
            if outdir and not saved_ready:
                shot(wid, os.path.join(outdir, prefix+'-ready.png')); saved_ready = True
            break
        if now - tstart > timeout: break
        idx += 1
        time.sleep(0.1)
    return dict(t0=t0, mode=mode, window=wid, onset_rel=(onset-t0) if onset else None,
                ready_rel=(ready-t0) if ready else None, n=len(rows),
                rows=rows, first_dim=dims)

def quit_app():
    pid, _ = app_el()
    if pid is None: return True
    subprocess.run(['osascript','-e','tell application "RawLab Mac" to quit'], capture_output=True)
    for _ in range(100):
        if app_el()[0] is None: return True
        time.sleep(0.1)
    subprocess.run(['kill', str(pid)], capture_output=True)
    time.sleep(0.5)
    return app_el()[0] is None

def launch(file, new_instance=True):
    args = ['open']
    if new_instance: args.append('-n')
    args += ['--env', f'HOME={HOME}', '--env', f'CFFIXED_USER_HOME={HOME}', '-a', APP]
    if file: args.append(file)
    return subprocess.run(args, capture_output=True, text=True)

def wait_window(timeout=30):
    t0 = time.time()
    while time.time()-t0 < timeout:
        pid, _ = app_el()
        if pid:
            m = main_window(pid)
            if m: return pid, m[0], time.time()-t0
        time.sleep(0.05)
    return None, None, None

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'wins':
        pid, ae = app_el(); print(pid, main_window(pid) if pid else None)
    elif cmd == 'quit':
        print(quit_app())
