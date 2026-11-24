#!/usr/bin/env python3
"""Synthetic input helpers for #26 GUI timing (Quartz CGEvents)."""
import sys, time
import Quartz
from AppKit import NSRunningApplication, NSApplicationActivateAllWindows

KEY = {'escape': 53, 'return': 36, 'tab': 48, 'space': 49, 'right': 124,
       'left': 123, 'up': 126, 'down': 125, 'delete': 51, 'a': 0, 'c': 8,
       'v': 9, 'd': 2, 'f': 3, 'g': 5, 'n': 45, 'o': 31, 'p': 35}

def post(ev):
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)

def key(name, cmd=False, shift=False, wait=0.0):
    code = KEY[name] if isinstance(name, str) else name
    flags = 0
    if cmd: flags |= Quartz.kCGEventFlagMaskCommand
    if shift: flags |= Quartz.kCGEventFlagMaskShift
    down = Quartz.CGEventCreateKeyboardEvent(None, code, True)
    up = Quartz.CGEventCreateKeyboardEvent(None, code, False)
    for ev in (down, up):
        if flags: Quartz.CGEventSetFlags(ev, flags)
        post(ev)
        time.sleep(0.02)
    if wait: time.sleep(wait)

def move(x, y):
    post(Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, (x, y), 0))

def click(x, y):
    move(x, y); time.sleep(0.06)
    post(Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, (x, y), 0))
    time.sleep(0.05)
    post(Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, (x, y), 0))

def drag(x1, y1, x2, y2, steps=25):
    move(x1, y1); time.sleep(0.06)
    post(Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, (x1, y1), 0))
    time.sleep(0.12)
    for i in range(1, steps + 1):
        x = x1 + (x2 - x1) * i / steps; y = y1 + (y2 - y1) * i / steps
        post(Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDragged, (x, y), 0))
        time.sleep(0.02)
    post(Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, (x2, y2), 0))

def wins(pid=None, owner_sub=None):
    wl = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
    out = []
    for w in wl:
        own = w.get('kCGWindowOwnerName') or ''
        opid = w.get('kCGWindowOwnerPID')
        b = w.get('kCGWindowBounds') or {}
        if pid and opid != pid: continue
        if owner_sub and owner_sub.lower() not in own.lower(): continue
        out.append(dict(id=w.get('kCGWindowNumber'), owner=own, pid=opid,
                        name=w.get('kCGWindowName') or '', layer=w.get('kCGWindowLayer'),
                        x=int(b.get('X', 0)), y=int(b.get('Y', 0)),
                        w=int(b.get('Width', 0)), h=int(b.get('Height', 0))))
    return out

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'key': key(sys.argv[2], cmd='--cmd' in sys.argv)
    elif cmd == 'click': click(int(sys.argv[2]), int(sys.argv[3]))
    elif cmd == 'drag': drag(*map(int, sys.argv[2:6]))
    elif cmd == 'wins': print(wins(int(sys.argv[2]) if sys.argv[2] != '-' else None))

def scroll(x, y, lines, unit='line'):
    ev = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitLine, 1, lines)
    Quartz.CGEventSetLocation(ev, (x, y))
    post(ev); time.sleep(0.05)

KEY.update({'f1':122,'f2':120,'f3':99,'f4':118,'f5':96,'f6':97,'f7':98,'f8':100,'f9':101,'f10':109,'l':37,'r':15,'home':115,'end':119,'pageup':116,'pagedown':121})


def activate(pid):
    app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
    if app:
        app.activateWithOptions_(NSApplicationActivateAllWindows)
        time.sleep(0.3)
        return True
    return False
