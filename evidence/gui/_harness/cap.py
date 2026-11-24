#!/usr/bin/env python3
"""Window capture at ~10Hz with stability detection (Lightamer #26 harness).

Usage:
  cap.py <wid> <outdir> <prefix> --mode startup|onset --timeout SEC
         [--t0 EPOCH] [--stable-n 3] [--stable-thresh 0.35]
         [--img-thresh 1.0] [--change-thresh 1.5] [--stop-file PATH]

Outputs:
  <outdir>/<prefix>-cap.csv      per-frame stats
  <outdir>/<prefix>-summary.json ready/onset epochs + window size
  <outdir>/<prefix>-{first,onset,ready}.png  full-res proof frames (screencapture)

Mode startup: frame0 = baseline; ready when content differs from frame0 by
  > img-thresh AND last stable-n inter-frame diffs < stable-thresh.
Mode onset: first 2 frames = baseline; onset when diff-base > change-thresh,
  then ready when stable-n inter-frame diffs < stable-thresh.
"""
import sys, os, json, time, argparse, subprocess, ctypes
import Quartz
import numpy as np

def cg_capture_gray(wid, maxw=320):
    img = Quartz.CGWindowListCreateImage(
        Quartz.CGRectMake(0, 0, 0, 0),
        Quartz.kCGWindowListOptionIncludingWindow, wid,
        Quartz.kCGWindowImageBoundsIgnoreFraming)
    if img is None:
        return None, None, None
    w = Quartz.CGImageGetWidth(img); h = Quartz.CGImageGetHeight(img)
    if w <= 0 or h <= 0:
        return None, None, None
    W = min(maxw, w); H = max(1, int(round(h * W / w)))
    nbytes = W * H
    buf = (ctypes.c_ubyte * nbytes)()
    cs = Quartz.CGColorSpaceCreateDeviceGray()
    ctx = Quartz.CGBitmapContextCreate(buf, W, H, 8, W, cs, Quartz.kCGImageAlphaNone)
    if ctx is None:
        return None, None, None
    Quartz.CGContextSetInterpolationQuality(ctx, 1)
    Quartz.CGContextDrawImage(ctx, Quartz.CGRectMake(0, 0, W, H), img)
    arr = np.frombuffer(bytes(buf), dtype=np.uint8).reshape(H, W).astype(np.int16)
    return arr, w, h

def shot(wid, path):
    subprocess.run(['screencapture', '-x', '-o', '-l', str(wid), path],
                   check=False, capture_output=True)
    return os.path.exists(path) and os.path.getsize(path) > 1000

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('wid', type=int)
    ap.add_argument('outdir'); ap.add_argument('prefix')
    ap.add_argument('--mode', choices=['startup', 'onset'], required=True)
    ap.add_argument('--timeout', type=float, default=20)
    ap.add_argument('--t0', type=float, default=None)
    ap.add_argument('--stable-n', type=int, default=3)
    ap.add_argument('--stable-thresh', type=float, default=0.35)
    ap.add_argument('--img-thresh', type=float, default=1.0)
    ap.add_argument('--change-thresh', type=float, default=1.5)
    ap.add_argument('--stop-file', default=None)
    a = ap.parse_args()
    t0 = a.t0 if a.t0 is not None else time.time()
    os.makedirs(a.outdir, exist_ok=True)
    csv = open(os.path.join(a.outdir, a.prefix + '-cap.csv'), 'w', buffering=1)
    csv.write('idx,t_rel,diff_prev,diff_base,mean,std,w,h\n')
    frames = []          # downsampled int16 arrays
    summary = dict(mode=a.mode, wid=a.wid, t0=t0, started=time.time(),
                   ready_epoch=None, ready_rel=None, onset_epoch=None,
                   onset_rel=None, first_epoch=None, first_rel=None,
                   n_frames=0, params=vars(a))
    first_saved = False
    onset_saved = False
    ready_saved = False
    stable_run = 0
    onset_seen = False
    t_start = time.time()
    idx = 0
    while True:
        now = time.time()
        if now - t_start > a.timeout:
            break
        if a.stop_file and os.path.exists(a.stop_file):
            break
        arr, w, h = cg_capture_gray(a.wid)
        t_cap = time.time()
        if arr is None:
            time.sleep(0.05); idx += 1
            csv.write(f'{idx},{t_cap-t0:.3f},,,, ,,\n')
            continue
        prev = frames[-1] if frames else None
        if prev is not None and prev.shape == arr.shape:
            diff_prev = float(np.abs(arr - prev).mean())
        else:
            diff_prev = 99.0 if prev is not None else 0.0
        base = frames[0] if frames else arr
        if base.shape == arr.shape:
            diff_base = float(np.abs(arr - base).mean())
        else:
            diff_base = 99.0
        frames.append(arr)
        if not first_saved:
            shot(a.wid, os.path.join(a.outdir, a.prefix + '-first.png'))
            summary['first_epoch'] = t_cap; summary['first_rel'] = t_cap - t0
            first_saved = True
        csv.write(f'{idx},{t_cap-t0:.3f},{diff_prev:.3f},{diff_base:.3f},'
                  f'{arr.mean():.2f},{arr.std():.2f},{w},{h}\n')
        idx += 1
        if a.mode == 'onset' and not onset_seen and len(frames) > 3 and diff_base > a.change_thresh:
            onset_seen = True
            summary['onset_epoch'] = t_cap; summary['onset_rel'] = t_cap - t0
            if not onset_saved:
                shot(a.wid, os.path.join(a.outdir, a.prefix + '-onset.png'))
                onset_saved = True
        if len(frames) > 2 and diff_prev < a.stable_thresh:
            stable_run += 1
        else:
            stable_run = 0
        content_ok = ((diff_base > a.img_thresh) or (arr.std() > 8)) if a.mode == 'startup' else onset_seen
        if stable_run >= a.stable_n and content_ok:
            summary['ready_epoch'] = t_cap; summary['ready_rel'] = t_cap - t0
            if not ready_saved:
                shot(a.wid, os.path.join(a.outdir, a.prefix + '-ready.png'))
                ready_saved = True
            break
        # adapt pacing to ~10Hz
        dt = time.time() - t_cap
        if dt < 0.1:
            time.sleep(0.1 - dt)
    summary['n_frames'] = idx
    summary['ended'] = time.time()
    if summary['ready_epoch'] is None:
        summary['status'] = 'TIMEOUT'
    else:
        summary['status'] = 'OK'
    csv.close()
    with open(os.path.join(a.outdir, a.prefix + '-summary.json'), 'w') as f:
        json.dump(summary, f, indent=1)
    print(json.dumps(summary))

if __name__ == '__main__':
    main()
