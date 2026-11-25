#!/bin/bash
# T9: 10 minutes of scrolling + dragging on one backend, RSS sampled every 10 s.
set -u
B=${1:-fast}
BIN=dist/proto-$B-clean
OUT=bench/out
pkill -f "proto-$B-clean"; sleep 0.5
LIGHTAMER_FIXED=1 "$BIN" > "$OUT/t9-$B.app.log" 2> "$OUT/t9-$B.app.err" &
APP=$!
WID=""
for _ in $(seq 1 200); do
  WID=$(./measure/frameprobe-dense list 2>/dev/null | awk -F'\t' -v b="proto-$B-clean" '$4==b && $5==""{print $1;exit}')
  [ -n "$WID" ] && break
  sleep 0.1
done
echo "T9 $B pid=$APP wid=$WID start=$(date +%H:%M:%S)"
if [ -z "$WID" ]; then echo "T9 $B NO_WINDOW"; kill $APP 2>/dev/null; exit 1; fi
( for i in $(seq 1 62); do
    if kill -0 $APP 2>/dev/null; then
      echo "$(date +%s) $(ps -o rss= -p $APP | tr -d ' ')"
    else
      echo "$(date +%s) DEAD"; break
    fi
    sleep 10
  done ) > "$OUT/t9-$B.rss" &
MON=$!
./measure/frameprobe-dense run --pid $APP --window-id $WID --out "$OUT/t9-$B.run" \
  --script bench/scripts/t9-stability.scr --activate --global --tail 1.0 \
  > "$OUT/t9-$B.probe.out" 2> "$OUT/t9-$B.probe.err"
kill $MON 2>/dev/null
ALIVE=$(kill -0 $APP 2>/dev/null && echo yes || echo no)
echo "T9 $B end=$(date +%H:%M:%S) alive=$ALIVE frames=$(grep -c '^F ' "$OUT/t9-$B.run")"
kill $APP 2>/dev/null
