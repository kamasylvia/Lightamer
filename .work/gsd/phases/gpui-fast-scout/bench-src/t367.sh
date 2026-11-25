#!/bin/bash
# t367.sh <pre|fast> — T3 (100k list), T6 (text), T7 (surface + renderimage)
set -u
B=$1
BIN=dist/lab-$B
OUT=bench/out

echo "== T3 list $B =="
pkill -f "$BIN"; sleep 0.4
./bench/runone.sh t3-$B "$BIN" bench/scripts/t3-list-scroll.scr LAB_MODE=list >/dev/null 2>&1
echo "-- $B app log:"; head -3 "$OUT/t3-$B.app.log"
grep -E "LAB_LAYOUT|TICK" "$OUT/t3-$B.app.err" | head -2
./bench/analyze.py "$OUT/t3-$B.run" scroll | python3 -c 'import json,sys;d=json.load(sys.stdin);s=d["scroll"];print("T3 '$B'",{k:s[k] for k in ("all_frames","changed","span_s","changed_fps","changed_med_ms","changed_p95_ms","changed_gt167","changed_gt333")}),print("events",s["events"])'
ps -o rss= -p "$(pgrep -f "$BIN" | head -1)" 2>/dev/null | awk '{printf "T3 '$B' rss(after)=%.0f MB\n", $1/1024}'

echo "== T6 text $B =="
pkill -f "$BIN"; sleep 0.4
LAB_MODE=text "$BIN" > "$OUT/t6-$B.app.log" 2> "$OUT/t6-$B.app.err" &
APP=$!
sleep 3
WID=$(./measure/frameprobe-dense list 2>/dev/null | awk -F'\t' -v b="lab-$B" '$4==b && $5==""{print $1;exit}')
screencapture -x -o -l "$WID" "$OUT/t6-$B.png"
echo "shot t6-$B.png wid=$WID"
grep LAB_LAYOUT "$OUT/t6-$B.app.err" | head -1
kill $APP 2>/dev/null; sleep 0.3

echo "== T7 surface $B =="
./bench/runone.sh t7s-$B "$BIN" bench/scripts/t7-watch.scr LAB_MODE=surface LAB_TICK_MS=16
grep -E "SURFACE_BUFFER|TICK_START|TICK n=0 |TICK n=270|TICK_END" "$OUT/t7s-$B.app.err" | head -5
./bench/analyze.py "$OUT/t7s-$B.run" all | python3 -c 'import json,sys;d=json.load(sys.stdin);w=d["whole"];print("T7s '$B'",{k:w[k] for k in ("all_frames","changed","span_s","changed_fps","changed_med_ms","changed_p95_ms")})'

echo "== T7 renderimage $B =="
./bench/runone.sh t7r-$B "$BIN" bench/scripts/t7-watch.scr LAB_MODE=renderimage LAB_TICK_MS=16
grep -E "TICK_START|TICK n=0 |TICK n=270|TICK_END" "$OUT/t7r-$B.app.err" | head -5
./bench/analyze.py "$OUT/t7r-$B.run" all | python3 -c 'import json,sys;d=json.load(sys.stdin);w=d["whole"];print("T7r '$B'",{k:w[k] for k in ("all_frames","changed","span_s","changed_fps","changed_med_ms","changed_p95_ms")})'
pkill -f "$BIN"; sleep 0.3
