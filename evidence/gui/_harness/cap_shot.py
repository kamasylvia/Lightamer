#!/usr/bin/env python3
"""Window capture at ~5-8 Hz via `screencapture -l` (Metal viewports are black in
CGWindowListCreateImage on this host). Same CLI/summary contract as cap.py.
Usage: cap_shot.py <wid> <outdir> <prefix> --mode startup|onset --timeout SEC
       [--t0 EPOCH] [--stable-n 3] [--stable-thresh 0.35] [--img-thresh 1.0]
       [--change-thresh 1.5] [--crop x,y,w,h] [--min-std 8]
"""
import sys, os, json, time, argparse, subprocess
import numpy as np
from PIL import Image

def grab(wid, maxw=320, crop=None):
    tmp = f'/tmp/cap-shot-{os.getpid()}-{wid}.png'
    r = subprocess.run(['screencapture', '-x', '-o', '-l', str(wid), tmp],
                       capture_output=True)
    if not os.path.exists(tmp) or os.path.getsize(tmp) < 1000:
        return None, None, None
    im = Image.open(tmp).convert('L')
    W0, H0 = im.size
    if crop:
        x, y, w, h = crop
        x = max(0, min(x, W0 - 1)); y = max(0, min(y, H0 - 1))
        w = max(1, min(w, W0 - x)); h = max(1, min(h, H0 - y))
        im = im.crop((x, y, x + w, y + h))
    W = min(maxw, im.width); H = max(1, int(round(im.height * W / im.width)))
    im = im.resize((W, H), Image.LANCZOS)
    return np.asarray(im).astype(np.int16), W0, H0

def shot(wid, path):
    subprocess.run(['screencapture', '-x', '-o', '-l', str(wid), path], capture_output=True)
    return os.path.exists(path) and os.path.getsize(path) > 1000

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('wid', type=int); ap.add_argument('outdir'); ap.add_argument('prefix')
    ap.add_argument('--mode', choices=['startup', 'onset'], required=True)
    ap.add_argument('--timeout', type=float, default=20)
    ap.add_argument('--t0', type=float, default=None)
    ap.add_argument('--stable-n', type=int, default=3)
    ap.add_argument('--stable-thresh', type=float, default=0.35)
    ap.add_argument('--img-thresh', type=float, default=1.0)
    ap.add_argument('--change-thresh', type=float, default=1.5)
    ap.add_argument('--crop', default=None)
    ap.add_argument('--min-std', type=float, default=8.0)
    ap.add_argument('--stop-file', default=None)
    a = ap.parse_args()
    t0 = a.t0 if a.t0 is not None else time.time()
    crop = tuple(int(v) for v in a.crop.split(',')) if a.crop else None
    os.makedirs(a.outdir, exist_ok=True)
    csv = open(os.path.join(a.outdir, a.prefix + '-cap.csv'), 'w', buffering=1)
    csv.write('idx,t_rel,diff_prev,diff_base,mean,std,w,h\n')
    frames = []
    summary = dict(mode=a.mode, wid=a.wid, t0=t0, started=time.time(),
                   ready_epoch=None, ready_rel=None, onset_epoch=None, onset_rel=None,
                   first_epoch=None, first_rel=None, n_frames=0, params=vars(a))
    first_saved = onset_saved = ready_saved = False
    stable_run = 0; onset_seen = False; idx = 0
    t_start = time.time()
    while True:
        now = time.time()
        if now - t_start > a.timeout: break
        if a.stop_file and os.path.exists(a.stop_file): break
        arr, W0, H0 = grab(a.wid, crop=crop)
        t_cap = time.time()
        if arr is None:
            time.sleep(0.05); idx += 1; continue
        prev = frames[-1] if frames else None
        diff_prev = float(np.abs(arr - prev).mean()) if (prev is not None and prev.shape == arr.shape) else (99.0 if prev is not None else 0.0)
        base = frames[0] if frames else arr
        diff_base = float(np.abs(arr - base).mean()) if base.shape == arr.shape else 99.0
        frames.append(arr)
        if not first_saved:
            shot(a.wid, os.path.join(a.outdir, a.prefix + '-first.png'))
            summary['first_epoch'] = t_cap; summary['first_rel'] = t_cap - t0
            first_saved = True
        csv.write(f'{idx},{t_cap-t0:.3f},{diff_prev:.3f},{diff_base:.3f},'
                  f'{arr.mean():.2f},{arr.std():.2f},{arr.shape[1]},{arr.shape[0]}\n')
        idx += 1
        if a.mode == 'onset' and not onset_seen and len(frames) > 2 and diff_base > a.change_thresh:
            onset_seen = True
            summary['onset_epoch'] = t_cap; summary['onset_rel'] = t_cap - t0
            if not onset_saved:
                shot(a.wid, os.path.join(a.outdir, a.prefix + '-onset.png')); onset_saved = True
        if len(frames) > 2 and diff_prev < a.stable_thresh:
            stable_run += 1
        else:
            stable_run = 0
        content_ok = (diff_base > a.img_thresh or arr.std() > a.min_std) if a.mode == 'startup' else onset_seen
        # an image must be present: not a black/blank viewport
        image_ok = arr.std() >= a.min_std
        if stable_run >= a.stable_n and content_ok and image_ok:
            summary['ready_epoch'] = t_cap; summary['ready_rel'] = t_cap - t0
            if not ready_saved:
                shot(a.wid, os.path.join(a.outdir, a.prefix + '-ready.png')); ready_saved = True
            break
    summary['n_frames'] = idx; summary['ended'] = time.time()
    summary['status'] = 'OK' if summary['ready_epoch'] is not None else 'TIMEOUT'
    csv.close()
    with open(os.path.join(a.outdir, a.prefix + '-summary.json'), 'w') as f:
        json.dump(summary, f, indent=1)
    print(json.dumps(summary))

if __name__ == '__main__':
    main()
