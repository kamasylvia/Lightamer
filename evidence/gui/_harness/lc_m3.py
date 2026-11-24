#!/usr/bin/env python3
"""LightCraft M3 batch paste measurement.

Usage: lc_m3.py <N> [--open-during-refresh]
Assumes the app is running and the N target photos are already imported.
"""
import json, os, sys, time
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import lc, cap
import numpy as np

A = lc.A
OUT = A + '/logs'


def photos():
    return lc.ctl({'id': 1, 'method': 'engine.execute',
                   'params': {'command': 'catalog.query', 'params': {'limit': 200000}}}, timeout=120)['result']['photos']


def perf():
    return lc.inspect(timeout=30)['result']['perf']


def grid_frame(wid):
    arr, w, h = cap.cg_capture_gray(wid, maxw=500)
    return arr


def main():
    N = int(sys.argv[1])
    open_during = '--open-during-refresh' in sys.argv
    ph = photos()
    targets = [p['id'] for p in ph if p['fileName'].startswith('img')]
    raws = [p['id'] for p in ph if p['fileName'].endswith(('.ARW', '.RAF', '.NEF'))]
    if len(targets) < N:
        print(json.dumps({'error': f'only {len(targets)} targets imported'}))
        return
    targets = targets[:N]
    source = raws[0]
    lc.exec_cmd('view.photoGrid', timeout=30)
    time.sleep(0.4)
    # source edit: +0.5 EV, copy
    lc.exec_cmd('library.select', {'ids': [source], 'active': source}, timeout=30)
    lc.exec_cmd('develop.set', {'control': 'light.exposure', 'value': 0.5}, timeout=30)
    c = lc.exec_cmd('develop.copy', {}, timeout=30)
    # select the targets
    t_sel = time.time()
    for i in range(0, len(targets), 2000):
        lc.exec_cmd('library.select', {'ids': targets[i:i + 2000], 'mode': 'add'}, timeout=60)
    sel_s = round(time.time() - t_sel, 2)
    ins = lc.inspect(timeout=30)['result']
    pid = lc.pgrep_app()[0]
    wid = lc.main_window(pid)['id']
    before = grid_frame(wid)
    p0 = perf()
    t0 = time.time()
    res = lc.exec_cmd('develop.paste', {}, timeout=300)
    t1 = time.time()
    paste_s = round(t1 - t0, 3)
    p1 = perf()
    # watch the grid repaint: diff vs the pre-paste frame, then frame-to-frame stability
    frames = []
    prev = None
    changed_frac = None
    stable = 0
    t_stable = None
    t_end = time.time() + (45 if open_during else 30)
    while time.time() < t_end:
        arr = grid_frame(wid)
        t = time.time()
        if arr is None:
            time.sleep(0.05); continue
        if changed_frac is None and before is not None and arr.shape == before.shape:
            changed_frac = float((np.abs(arr.astype(np.int16) - before.astype(np.int16)) > 8).mean())
        d = None
        if prev is not None and prev.shape == arr.shape:
            d = float(np.abs(arr.astype(np.int16) - prev.astype(np.int16)).mean())
        stable = stable + 1 if (d is not None and d < 0.5) else 0
        frames.append(dict(t=t, diff=d))
        prev = arr
        if stable >= 3:
            t_stable = t
            break
        time.sleep(0.05)
    p2 = perf()
    out = dict(N=N, paste_s=paste_s, paste_ok=res.get('ok'), paste_result=res.get('result'),
               select_s=sel_s, selection=len(ins['selection']),
               refresh_stable_s=None if t_stable is None else round(t_stable - t1, 2),
               grid_changed_frac=None if changed_frac is None else round(changed_frac, 4),
               thumbs_before=p0['thumbsMade'], thumbs_after=p2['thumbsMade'],
               renders_before=p0['rendersDone'], renders_after=p2['rendersDone'],
               queue_after=p2['renderQueue'], in_flight=p2['rendersInFlight'],
               frame_count=len(frames))
    if open_during:
        # while the refresh runs: open one pasted photo in Detail and time it
        target = targets[len(targets) // 2]
        ins = lc.inspect()['result']
        tt = time.time()
        lc.exec_cmd('library.select', {'ids': [target], 'active': target}, timeout=30)
        lc.exec_cmd('view.detail', timeout=30)
        tw = lc.main_window(pid)['id']
        import lc_measure as lm
        r = lm.wait_ready(tw, ins, time.time(), timeout=60, want_view='detail', want_target=target)
        out['open_during_refresh_s'] = round(r['ready_epoch'] - tt, 3)
        out['open_cache'] = (r.get('state') or {}).get('loupe', {}).get('source')
    print(json.dumps(out, ensure_ascii=False))
    with open(OUT + f'/m3-{N}.json', 'w') as f:
        json.dump(out, f, indent=1)


if __name__ == '__main__':
    main()
