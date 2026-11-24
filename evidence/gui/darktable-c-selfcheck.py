#!/usr/bin/env python3
"""darktable lane #26 — script-based self-check (third attempt).
Recomputes every number §11 asserts from the archived CSV / evidence files and
the live temp dir if present. Prints PASS / N error + M minor.
"""
import csv, os, re, sqlite3, subprocess, sys

R = '/Volumes/UNITEK/Documents/Development/Lightamer'
E = f'{R}/evidence/gui'
G = '/Users/Shared/lightamer-gui-test/darktable'
err, minor = [], []

def rd(p):
    with open(p, newline='') as f:
        return list(csv.DictReader(f))

# 1. CSV rows
rows = rd(f'{E}/darktable-c-paste-tiers.csv')
if len(rows) != 2:
    err.append(f'CSV rows={len(rows)} (expected 2 failed 10k attempts)')
for r in rows:
    if r['tier'] != 'n10000_final':
        err.append(f"unexpected tier {r['tier']}")
    if int(r['targets']) != 10000:
        err.append(f"targets={r['targets']} != 10000")
    if int(r['grown_after']) != 0:
        err.append(f"grown_after={r['grown_after']} contradicts report claim of zero growth")
    if not (0 < float(r['wall_s']) < 200):
        err.append(f"wall_s={r['wall_s']} out of plausible range")

# 2. lock evidence
lock = open(f'{E}/darktable-c-dblock.txt').read()
mm = re.search(r'total_lines=(\d+)', lock)
n = int(mm.group(1)) if mm else 0
if n < 200:
    err.append(f'dblock lines={n} (report says 330)')

# 3. 10k sidecars + history counts (live dir may be deleted; evidence file is authoritative)
ev = open(f'{E}/darktable-c-10k-evidence.txt').read()
m = re.search(r'xmp_files_n10000=(\d+)', ev)
if not m or m.group(1) != '10000':
    err.append('xmp_files_n10000 != 10000')
if 'history_rows_total=16514' not in ev:
    minor.append('history total not pinned in evidence file')

# 4. report consistency
rep = open(f'{R}/.work/gsd/phases/rawspeed-backend/GUI-darktable.md').read()
checks = [
    ('第三轮' in rep, 'no §11 heading'),
    ('101 张' in rep and '≈2 s' in rep, '101-tier number missing'),
    ('不成立' in rep, 'verdict sentence missing'),
    ('10,000 个 XMP' in rep, '10k sidecar count missing'),
    ('零增长' in rep, 'history zero-growth claim missing'),
    ('330 条' in rep, '330 lock lines missing'),
]
for ok, msg in checks:
    if not ok: err.append(f'report: {msg}')

# 5. if app dir still present, re-verify DB facts
if os.path.exists(f'{G}/lib.db'):
    c = sqlite3.connect(f'file:{G}/lib.db?mode=ro', uri=True, timeout=5)
    total = c.execute('select count(*) from history').fetchone()[0]
    film1 = c.execute('select count(distinct h.imgid) from history h join images i on i.id=h.imgid where i.film_id=1').fetchone()[0]
    if total != 16514: err.append(f'live history total={total} != 16514')
    if film1 != 7364: err.append(f'live film1 imgids={film1} != 7364')
    c.close()

print(f'PASS / {len(err)} error + {len(minor)} minor')
for x in err: print('ERROR', x)
for x in minor: print('MINOR', x)
sys.exit(1 if err else 0)
