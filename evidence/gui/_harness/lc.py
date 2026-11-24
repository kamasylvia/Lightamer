#!/usr/bin/env python3
"""LightCraft GUI-timing harness (Lightamer #26).

Helpers: control-channel client, window lookup, launch/quit, frame capture.
"""
import json, os, socket, subprocess, sys, time, signal

G = '/Users/Shared/lightamer-gui-test'
A = G + '/lightcraft'
APPDIR = A + '/apps/LightCraft.app'
BIN = APPDIR + '/Contents/MacOS/LightCraft'
HOME = A + '/home'
LIB = A + '/library'
CFG = A + '/config'
FR = A + '/frames'
PORT = 7980


def ctl(req, timeout=90.0, port=PORT):
    """One request on the control channel (one connection per call)."""
    s = socket.create_connection(('127.0.0.1', port), timeout=5)
    s.settimeout(timeout)
    s.sendall((json.dumps(req) + '\n').encode())
    buf = b''
    while b'\n' not in buf:
        chunk = s.recv(1 << 20)
        if not chunk:
            break
        buf += chunk
    s.close()
    if not buf.strip():
        raise RuntimeError('empty reply')
    return json.loads(buf.split(b'\n', 1)[0])


def exec_cmd(command, params=None, timeout=90.0):
    return ctl({'id': 1, 'method': 'engine.execute',
                'params': {'command': command, 'params': params or {}}}, timeout)


def inspect(timeout=90.0):
    return ctl({'id': 1, 'method': 'ui.inspect'}, timeout)


def widgets(flt=None, timeout=90.0):
    p = {} if flt is None else {'filter': flt}
    return ctl({'id': 1, 'method': 'ui.widgets', 'params': p}, timeout)


def windows(pid=None):
    import Quartz
    out = []
    for w in Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
            Quartz.kCGNullWindowID):
        if pid is not None and w.get('kCGWindowOwnerPID') != pid:
            continue
        out.append(dict(id=w.get('kCGWindowNumber'), owner=w.get('kCGWindowOwnerName'),
                        pid=w.get('kCGWindowOwnerPID'), name=w.get('kCGWindowName'),
                        x=w.get('kCGWindowBounds', {}).get('X', 0),
                        y=w.get('kCGWindowBounds', {}).get('Y', 0),
                        w=w.get('kCGWindowBounds', {}).get('Width', 0),
                        h=w.get('kCGWindowBounds', {}).get('Height', 0),
                        layer=w.get('kCGWindowLayer', 0)))
    return out


def main_window(pid):
    ws = [w for w in windows(pid) if w['layer'] == 0 and w['w'] >= 600 and w['h'] >= 400]
    return max(ws, key=lambda w: w['w'] * w['h']) if ws else None


def launch(extra_args=None, wait=8.0):
    """Start the app with isolated HOME/config/library and the control channel."""
    for d in (HOME, CFG, LIB, FR):
        os.makedirs(d, exist_ok=True)
    args = [BIN, '--library', LIB, '--control', str(PORT)] + (extra_args or [])
    env = dict(os.environ)
    for k in ('http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'all_proxy', 'ALL_PROXY'):
        env.pop(k, None)
    env.update(HOME=HOME, CFFIXED_USER_HOME=HOME, LIGHTCRAFT_CONFIG_DIR=CFG,
               NO_COLOR='1')
    log = open(A + '/logs/app.log', 'ab')
    p = subprocess.Popen(args, env=env, stdout=log, stderr=log, start_new_session=True)
    t0 = time.time()
    while time.time() - t0 < wait:
        if main_window(p.pid):
            return p, time.time()
        if p.poll() is not None:
            raise RuntimeError('app exited rc=%s' % p.returncode)
        time.sleep(0.02)
    raise RuntimeError('no window after %.1fs' % wait)


def quit_app(p, sig=signal.SIGTERM):
    try:
        p.send_signal(sig)
    except ProcessLookupError:
        pass
    t0 = time.time()
    while time.time() - t0 < 20:
        if p.poll() is not None:
            return p.returncode
        time.sleep(0.05)
    try:
        p.kill()
    except ProcessLookupError:
        pass
    return 'killed'


def pgrep_app():
    out = subprocess.run(['pgrep', '-f', 'lightcraft/apps/LightCraft.app'],
                         capture_output=True, text=True).stdout.split()
    return [int(x) for x in out]


if __name__ == '__main__':
    print(json.dumps({'windows': windows(), 'app_pgrep': pgrep_app()}, indent=1))
