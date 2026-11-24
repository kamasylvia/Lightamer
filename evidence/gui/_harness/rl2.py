import time, os, numpy as np, rl

def canvas_stats(arr):
    h, w = arr.shape
    c = arr[int(h*0.14):int(h*0.94), int(w*0.22):int(w*0.82)]
    return float(c.mean()), float(c.std())

def measure2(wid, t0, mode='startup', timeout=40, stable_n=3, stable_thresh=0.4,
             img_mean=20.0, change_thresh=1.5, outdir=None, prefix='run', verbose=False):
    frames = []; first = None; onset = None; ready = None
    rows = []; stable = 0; saved = set()
    tstart = time.time(); idx = 0
    while True:
        now = time.time()
        arr, dims = rl.cap_gray(wid)
        if arr is None:
            time.sleep(0.08); continue
        m, s = canvas_stats(arr)
        if first is None:
            first = arr
            if outdir: rl.shot(wid, os.path.join(outdir, prefix+'-first.png')); saved.add('first')
        diff_prev = float(np.abs(arr - frames[-1]).mean()) if frames else 0.0
        diff_base = float(np.abs(arr - first).mean())
        rows.append((idx, round(now-t0,3), round(diff_prev,3), round(diff_base,3), round(m,1), round(s,1)))
        frames.append(arr)
        if len(frames) > 3: frames.pop(0)
        content = m > img_mean and s > 8
        if mode == 'startup':
            if onset is None and content:
                onset = now
                if outdir and 'onset' not in saved:
                    rl.shot(wid, os.path.join(outdir, prefix+'-onset.png')); saved.add('onset')
        else:
            if onset is None and len(rows) > 1 and diff_base > change_thresh:
                onset = now
            if onset is None and content and m > 40:
                onset = now
        if onset is not None:
            stable = stable + 1 if (diff_prev < stable_thresh and content) else 0
        if verbose and idx % 3 == 0:
            print(f"  {now-t0:.2f} m={m:.1f} s={s:.1f} dp={diff_prev:.2f} db={diff_base:.2f}", flush=True)
        if stable >= stable_n:
            ready = now
            if outdir and 'ready' not in saved:
                rl.shot(wid, os.path.join(outdir, prefix+'-ready.png')); saved.add('ready')
            break
        if now - tstart > timeout: break
        idx += 1
        time.sleep(0.08)
    return dict(onset_rel=(onset-t0) if onset else None, ready_rel=(ready-t0) if ready else None,
                n=len(rows), rows=rows)
