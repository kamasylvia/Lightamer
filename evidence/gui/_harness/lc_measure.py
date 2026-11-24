#!/usr/bin/env python3
"""LightCraft GUI timing measurements (Lightamer #26).

Modes:
  cold  <target_id>        quit, launch, select+detail, time to stable viewport
  hot   <target_id>        click filmstrip thumb of target, time to stable
  edit  <delta_px>         drag exposure slider, time to stable
Every mode writes one CSV row to $G/lightcraft/logs/measure.csv.
"""
import json, os, signal, sys, time
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import lc, cap, input as inp
import numpy as np

A = lc.A
CSV = A + '/logs/measure.csv'
FR = A + '/frames'
WARM_CAP = 0.05   # sleep between frame grabs (~10 Hz + capture cost)

def bright_frac(arr):
    return float((arr > 85).mean())

def frame(wid):
    arr, w, h = cap.cg_capture_gray(wid, maxw=400)
    return arr, w, h

def canvas_crop(arr, ins, win):
    """Crop the downsampled frame to the canvas rect (points -> frame pixels)."""
    x, y, w, h = ins['canvasRect']
    W, H = w, h
    # frame is window content; engine points == window points here
    fx = arr.shape[1] / win['w']; fy = arr.shape[0] / win['h']
    x0 = max(0, int(x * fx)); y0 = max(0, int(y * fy))
    x1 = min(arr.shape[1], int((x + W) * fx)); y1 = min(arr.shape[0], int((y + H) * fy))
    return arr[y0:y1, x0:x1]

def stable_ready(prev, cur, stable_n=3, thresh=0.5):
    if prev is None:
        return None, 0.0
    d = float(np.abs(cur.astype(np.int16) - prev.astype(np.int16)).mean())
    return d, d

def wait_ready(wid, ins, t_action=None, timeout=40.0, stable_thresh=0.5, stable_n=3,
               min_bright=0.02, poll_state=True, want_view=None, want_target=None):
    """Capture ~10 Hz until the canvas has content and 3 consecutive frame diffs < thresh.
    Returns dict with t_rel ready epoch, frame stats, ready frame, and app state."""
    frames = []
    prev = None
    stable = 0
    onset = None
    t_start = time.time()
    last_state = None
    last_state_t = 0.0
    ready_frame = None
    state_ready = None
    none_since = None
    while time.time() - t_start < timeout:
        arr, w, h = frame(wid)
        t = time.time()
        if arr is None:
            none_since = none_since or t
            if t - none_since > 4.0:
                break
            time.sleep(WARM_CAP)
            continue
        none_since = None
        ca = canvas_crop(arr, ins, {'w': w, 'h': h})
        bf = bright_frac(ca)
        d = None
        if prev is not None and prev.shape == ca.shape:
            d = float(np.abs(ca.astype(np.int16) - prev.astype(np.int16)).mean())
        if d is not None:
            stable = stable + 1 if (d < stable_thresh and bf > min_bright) else 0
        else:
            stable = 0
        if onset is None and bf > min_bright and d is not None and d > 1.0:
            onset = t
        frames.append(dict(t=t, diff=d, bf=bf, mean=float(ca.mean()), std=float(ca.std())))
        prev = ca
        # app-side state check every ~0.5 s
        if poll_state and t - last_state_t > 0.5:
            last_state_t = t
            try:
                last_state = lc.inspect(timeout=5)['result']
                lv = last_state['loupe']
                state_ready = (lv['pending'] is False and
                               lv['source'] in ('render', 'cached') and
                               (want_view is None or last_state['ui'].get('view') == want_view) and
                               (want_target is None or lv.get('photo') == want_target))
            except Exception:
                pass
        if stable >= stable_n and state_ready:
            ready_frame = ca
            break
    t_ready = frames[-1]['t'] if frames else time.time()
    return dict(frames=frames, ready_epoch=t_ready, ready_frac=ready_frame,
                onset_epoch=onset, state=last_state)


def row(mode, target, t0, t_action, res, note=''):
    f = res['frames']
    d = dict(mode=mode, target=target, t0=t0, t_action=t_action,
             t_ready=res['ready_epoch'],
             spawn_to_action=None if not t_action else round(t_action - t0, 3),
             action_to_ready=None if not t_action else round(res['ready_epoch'] - t_action, 3),
             total=round(res['ready_epoch'] - t0, 3),
             onset_rel=None if not res['onset_epoch'] else round(res['onset_epoch'] - t_action, 3) if t_action else None,
             n_frames=len(f),
             ready_bf=round(f[-1]['bf'], 4) if f else None,
             ready_std=round(f[-1]['std'], 2) if f else None,
             cache=(res.get('state') or {}).get('loupe', {}).get('source'),
             step=json.dumps(((res.get('state') or {}).get('perf', {}).get('loupeSteps') or {}).get('current') or {}, separators=(',', ':')),
             render_ms=round((res.get('state') or {}).get('perf', {}).get('lastRenderMs') or 0, 1),
             note=note)
    new = not os.path.exists(CSV)
    with open(CSV, 'a') as fh:
        if new:
            fh.write(','.join(d.keys()) + '\n')
        fh.write(','.join('' if v is None else str(v) for v in d.values()) + '\n')
    return d


def ensure_quit():
    for p in lc.pgrep_app():
        try:
            os.kill(p, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _ in range(200):
        if not lc.pgrep_app():
            return True
        time.sleep(0.05)
    return not lc.pgrep_app()


def launch_timed():
    t0 = time.time()
    p, _ = lc.launch(wait=25)
    # first window epoch (loop already saw it); approximate by the moment launch returned
    t_win = time.time()
    # wait for the control channel
    for _ in range(400):
        try:
            lc.inspect(timeout=2)
            break
        except Exception:
            time.sleep(0.05)
    return p, t0, t_win


def select_detail(pid, target):
    lc.exec_cmd('library.select', {'ids': [target], 'active': target})
    lc.exec_cmd('view.detail')
    return time.time()


def click_film(pid, target, tries=3):
    """OS-level click on the filmstrip thumbnail of `target`; verified by the active photo.
    Returns the epoch of the click that took effect (a swallowed first click is retried)."""
    inp.activate(pid)
    time.sleep(0.12)
    last = None
    for _ in range(tries):
        w = next((x for x in lc.widgets()['result'] if x['id'] == f'film:{target}'), None)
        if w is None:
            raise RuntimeError(f'film:{target} not on screen')
        x, y, ww, hh = w['rect']
        win = lc.main_window(pid)
        # film cells carry the caption above the thumbnail: click the image, ~62% down the cell
        last = time.time()
        inp.click(win['x'] + x + ww / 2, win['y'] + y + hh * 0.62)
        for _ in range(30):
            time.sleep(0.02)
            if lc.inspect(timeout=3)['result']['active'] == target:
                return last
    return last


def main():
    mode = sys.argv[1]
    target = int(sys.argv[2]) if len(sys.argv) > 2 else None
    if mode == 'cold':
        fresh = '--fresh' in sys.argv
        if lc.pgrep_app():
            try:
                lc.exec_cmd('view.photoGrid')
                time.sleep(0.6)
            except Exception:
                pass
        assert ensure_quit(), 'app still running'
        if fresh:
            import shutil
            shutil.rmtree(lc.LIB + '/thumbs', ignore_errors=True)
        p, t0, t_win = launch_timed()
        ins = lc.inspect()['result']
        t_action = select_detail(p.pid, target)
        wid = lc.main_window(p.pid)['id']
        res = wait_ready(wid, ins, t_action, timeout=40, want_view='detail', want_target=target)
        if res['ready_frac'] is not None:
            cap.shot(wid, f'{FR}/cold-{target}-{int(time.time())}.png')
        print(json.dumps(row('cold', target, t0, t_action, res,
                             note='win@%.2f' % (t_win - t0)), ensure_ascii=False))
    elif mode == 'hot':
        pid = lc.pgrep_app()[0]
        ins = lc.inspect()['result']
        wid = lc.main_window(pid)['id']
        t_l = time.time()
        t_click = click_film(pid, target)
        res = wait_ready(wid, ins, t_click, timeout=20, want_view='detail', want_target=target)
        print(json.dumps(row('hot', target, t_l, t_click, res), ensure_ascii=False))
    elif mode == 'edit':
        pid = lc.pgrep_app()[0]
        ins = lc.inspect()['result']
        wid = lc.main_window(pid)['id']
        x, y, ww, hh = next(w['rect'] for w in lc.widgets()['result'] if w['id'] == 'slider:light.exposure')
        ctrls = lc.ctl({'id': 1, 'method': 'engine.execute',
                        'params': {'command': 'develop.controls', 'params': {}}}, timeout=30)['result']
        exp = next(c for c in ctrls if c['id'] == 'light.exposure')
        dx = int(sys.argv[2])
        win = lc.main_window(pid)
        inp.activate(pid)
        time.sleep(0.15)
        for attempt in range(3):
            v0 = exp['value']
            # the centred linear track: handle x for the current value
            hx = x + (v0 - exp['min']) / (exp['max'] - exp['min']) * ww
            cy = y + hh / 2
            t_l = time.time()
            inp.drag(win['x'] + hx, win['y'] + cy, win['x'] + hx + dx, win['y'] + cy, steps=8)
            t_up = time.time()
            exp = next(c for c in lc.ctl({'id': 1, 'method': 'engine.execute',
                                          'params': {'command': 'develop.controls', 'params': {}}}, timeout=30)['result']
                       if c['id'] == 'light.exposure')
            if abs(exp['value'] - v0) > 0.02:
                break
        res = wait_ready(wid, ins, t_up, timeout=20, want_view='detail', want_target=ins['active'])
        row_d = row('edit', dx, t_l, t_up, res, note='ev %.2f->%.2f' % (v0, exp['value']))
        print(json.dumps(row_d, ensure_ascii=False))
    else:
        raise SystemExit('mode?')

if __name__ == '__main__':
    main()
