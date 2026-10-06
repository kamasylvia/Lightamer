import re
from collections import Counter

def parse(path):
    data = open(path, encoding="utf-8").read()
    # id map: id="N" -> (kind, value)
    idmap = {}
    for m in re.finditer(r'<(duration|start-time)[^>]*id="(\d+)"[^>]*>(\d+)<', data):
        idmap[m.group(2)] = int(m.group(3))
    rows = []
    for m in re.finditer(r"<row>(.*?)</row>", data, re.S):
        row = m.group(1)
        start = None; dur = None
        sm = re.search(r'<start-time(?:[^>]*id="(\d+)")?(?:[^>]*>(\d+)<|[^>]*/>)', row) or re.search(r'<start-time[^>]*?(?:id="(\d+)"|>(\d+)<)', row)
        dm = re.search(r'<duration[^>]*?(?:id="(\d+)"[^>]*>(\d+)<|ref="(\d+)")', row)
        stm = re.search(r'<start-time[^>]*?(?:id="(\d+)"[^>]*>(\d+)<|ref="(\d+)")', row)
        if stm:
            if stm.group(1): start = idmap.get(stm.group(1))
            elif stm.group(3): start = idmap.get(stm.group(3))
            elif stm.group(2): start = int(stm.group(2))
        if dm:
            if dm.group(2): dur = int(dm.group(2)) / 1e9 * 1000.0
            elif dm.group(3): dur = idmap.get(dm.group(3), 0) / 1e9 * 1000.0
        if dur is not None:
            rows.append((start, dur))
    return rows

rows = parse("/tmp/m2-11-hitches-t2.xml")
durs = [d for _, d in rows if d]
print(f"parsed rows: {len(durs)}")
if durs:
    over50 = [d for d in durs if d > 50.0]
    print(f"sum hitch time: {sum(durs)/1000:.3f} s | max {max(durs):.1f} ms")
    print(f">50ms: {len(over50)} (sum {sum(over50)/1000:.3f} s) | >100ms: {len([d for d in durs if d>100])} | >250ms: {len([d for d in durs if d>250])}")
    buckets = Counter()
    for d in durs:
        if d <= 16.7: buckets["1f<=16.7"] += 1
        elif d <= 33.4: buckets["2f17-33"] += 1
        elif d <= 50: buckets["3f34-50"] += 1
        elif d <= 100: buckets["51-100"] += 1
        elif d <= 250: buckets["101-250"] += 1
        else: buckets[">250"] += 1
    for k in ["1f<=16.7","2f17-33","3f34-50","51-100","101-250",">250"]:
        print(f"  {k}: {buckets.get(k,0)}")
    print("top10:", [round(d,1) for d in sorted(durs, reverse=True)[:10]])
