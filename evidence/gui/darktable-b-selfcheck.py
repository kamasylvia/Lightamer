import csv, re, subprocess, sys
repo='/Volumes/UNITEK/Documents/Development/Lightamer'
rep=open(f'{repo}/.work/gsd/phases/rawspeed-backend/GUI-darktable.md').read()
errs=[]
# 1. CSV arithmetic
rows=list(csv.DictReader(open(f'{repo}/evidence/gui/darktable-b-thumbs.csv')))
r=rows[0]; n=int(r['n_thumbs']); el=float(r['elapsed_s'])
rate=n/el; ms=el/n*1000
if abs(rate-float(r['rate_per_s']))>0.02: errs.append(f'rate mismatch {rate:.2f} vs {r["rate_per_s"]}')
if abs(ms-float(r['ms_per_thumb']))>0.2: errs.append(f'ms mismatch {ms:.2f} vs {r["ms_per_thumb"]}')
ext=10000*ms/1000
if '13.3 min' not in rep: errs.append('report lacks the 13.3 min extrapolation')
if f'{ext:.0f}' not in rep and '800 s' not in rep: errs.append(f'extrapolation {ext:.0f}s not in report')
# 2. import numbers
ir=list(csv.DictReader(open(f'{repo}/evidence/gui/darktable-b-import.csv')))[0]
if ir['window_s'] not in rep: errs.append('window_s 4.736 not in report')
# 3. block claims vs source tag
def sh(c):
    return subprocess.run(c, shell=True, capture_output=True, text=True).stdout
dt='/Volumes/UNITEK/Documents/Development/darktable'
out=sh(f'cd {dt} && git grep -n "paste_history" release-5.6.2 -- src/lua | wc -l')
if out.strip()!='0': errs.append('paste_history unexpectedly present in release-5.6.2 lua')
out=sh(f'cd {dt} && sed -n "660,670p" release-5.6.2:src/lua/events.c 2>/dev/null | grep -c "dt_action_register"')
out=sh(f'cd {dt} && git show release-5.6.2:src/lua/events.c | sed -n "650,670p" | grep -c "dt_action_register(.*,  0, 0)"')
if out.strip()=='0': errs.append('events.c no-default-key claim not confirmed')
out=sh(f'cd {dt} && git show release-5.6.2:src/gui/accelerators.c | grep -c "_find_views(ac)"')
if out.strip()=='0': errs.append('accelerators.c view-check claim not confirmed')
# 4. paste CSV has 6 attempts all non-success
pr=list(csv.DictReader(open(f'{repo}/evidence/gui/darktable-b-paste.csv')))
if len(pr)!=6: errs.append(f'paste csv attempts {len(pr)}')
for row in pr:
    if 'no' not in row['result'] and 'nan' not in row['result'] and 'exist' not in row['result'] and 'never' not in row['result'] and 'marker' not in row['result']:
        errs.append('unexpected success row: '+row['result'])
print('FAIL' if errs else 'PASS', len(errs), 'error')
for e in errs: print(' -', e)
print(f'recomputed rate={rate:.2f}/s ms={ms:.2f} extrapolated_10k={ext:.1f}s ({ext/60:.2f} min)')
