#!/usr/bin/env python3
"""10k paste driver (third darktable attempt): T0 = Ctrl+V, completion by UI-window
appearance/disappearance or DB-file mtime quiet; zero DB reads during the job.

Assumes: lighttable, target film roll collected, selection = N, copy state valid
(paste button enabled). Writes one CSV row; prints JSON.
"""
import sys, time, json, csv, os, sqlite3
sys.path.insert(0, '/Users/Shared/lightamer-gui-test/_harness')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui, input as inp

DB = ui.DB

def q(sql, args=()):
    c = sqlite3.connect(f'file:{DB}?mode=ro', uri=True, timeout=10)
    try: return c.execute(sql, args).fetchall()
    finally: c.close()

targets = [r[0] for r in q("select id from images where film_id=1")]
tset = set(targets)
base = dict(q("select imgid,count(*) from history where imgid between 2 and 10001 group by imgid"))
pid = ui.dt_pids()[0]
base_wins = {w['id'] for w in inp.wins(pid=pid)}
ui.activate(); time.sleep(0.3)
t0 = time.time()
inp.key('v', cmd=True)
seen_new = False; dialog_done = None; last_m = None; quiet_since = None; moved = 0
while True:
    time.sleep(0.5)
    el = time.time() - t0
    wins = {w['id'] for w in inp.wins(pid=pid)}
    new = wins - base_wins
    if new: seen_new = True
    if seen_new and not new and dialog_done is None:
        dialog_done = round(el, 2)
    try: m = os.stat(DB).st_mtime_ns
    except OSError: m = 0
    if m != last_m:
        moved += 1; last_m = m; quiet_since = time.time()
    if el > 2 and moved >= 2 and quiet_since and time.time() - quiet_since > 4 and dialog_done is None:
        dialog_done = round(el, 2); break
    if dialog_done is not None and el > 3:
        time.sleep(1.5); break
    if el > 1500: break
t_end = time.time()
ui.shot('post-paste')
cur = dict(q("select imgid,count(*) from history where imgid between 2 and 10001 group by imgid"))
grown = sum(1 for i in tset if cur.get(i, 0) > base.get(i, 0))
out = dict(targets=len(tset), t0=round(t0, 3), wall_s=round(t_end - t0, 2),
           dialog_seen=seen_new, dialog_done_s=dialog_done, mtime_moves=moved, grown_after=grown)
with open(f'{ui.G}/out/paste-tiers.csv', 'a', newline='') as f:
    w = csv.writer(f)
    if f.tell() == 0:
        w.writerow(['tier','targets','t0','wall_s','dialog_seen','dialog_done_s','grown_after'])
    w.writerow(['n10000_final', len(tset), f"{t0:.6f}", out['wall_s'], seen_new, dialog_done, grown])
print(json.dumps(out))
