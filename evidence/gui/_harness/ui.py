#!/usr/bin/env python3
"""Minimal UI driver for the darktable lane (own window only). Reconstructed from the
measurement session; pairs with input.py in this directory."""
import sys, time, os, sqlite3, subprocess, json
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
import input as inp
import Quartz
from AppKit import NSRunningApplication, NSApplicationActivateAllWindows

G = '/Users/Shared/lightamer-gui-test/darktable'
DB = f'{G}/lib.db'
DT = f'{G}/apps/darktable.app/Contents/MacOS/darktable'

def dt_pids():
    return [int(x) for x in subprocess.run(['pgrep','-f',DT],capture_output=True,text=True).stdout.split()]

def win(timeout=30):
    t = time.time() + timeout
    while time.time() < t:
        pids = dt_pids()
        if not pids: return None
        for w in inp.wins(pid=pids[0]):
            if w['layer'] == 0 and w['w'] > 800 and w['h'] > 500:
                return w
        time.sleep(0.3)
    return None

def activate():
    for p in dt_pids():
        app = NSRunningApplication.runningApplicationWithProcessIdentifier_(p)
        if app: app.activateWithOptions_(NSApplicationActivateAllWindows)
    time.sleep(0.4)

def shot(name):
    w = win()
    path = f'{G}/out/{name}.png'
    subprocess.run(['screencapture','-x','-o','-l',str(w['id']),path], check=True)
    return path

def key(name, cmd=False, shift=False, wait=0.1):
    inp.key(name, cmd=cmd, shift=shift, wait=wait)

CODES = {'a':0,'s':1,'d':2,'f':3,'h':4,'g':5,'z':6,'x':7,'c':8,'v':9,'b':11,
         'q':12,'w':13,'e':14,'r':15,'y':16,'t':17,'1':18,'2':19,'3':20,'4':21,
         '6':22,'5':23,'9':25,'7':26,'8':28,'0':29,'o':31,'u':32,'i':34,'p':35,
         'l':37,'j':38,'k':40,'n':45,'m':46,'-':27,'.':47,'_':27,' ':49}

def type_text(s):
    """US keycodes; CGEventKeyboardSetUnicodeString is NOT delivered to GTK entries."""
    for ch in s:
        code = CODES[ch]; shift = ch == '_'
        for down in (True, False):
            ev = Quartz.CGEventCreateKeyboardEvent(None, code, down)
            if shift: Quartz.CGEventSetFlags(ev, Quartz.kCGEventFlagMaskShift)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
            time.sleep(0.015)

def db(q, args=()):
    c = sqlite3.connect(f'file:{DB}?mode=ro', uri=True, timeout=3)
    try: return c.execute(q, args).fetchall()
    finally: c.close()
