#!/bin/bash
# runone.sh <tag> <binary> <script> [ENV=VAL ...]
# Launches one app instance, runs one frameprobe script against its window,
# takes one window-only screenshot, kills the instance. Writes into bench/out/.
set -u
TAG=$1; BIN=$2; SCRIPT=$3; shift 3
OUT="$(cd "$(dirname "$0")" && pwd)/out"
mkdir -p "$OUT"
BASE=$(basename "$BIN")

# only ever touch an instance of this exact binary path
pkill -f "${BIN}" 2>/dev/null
sleep 0.4
# wait until no stale window of this app is listed any more
for _ in $(seq 1 40); do
  N=$(./measure/frameprobe-dense list 2>/dev/null | awk -F'\t' -v b="$BASE" '$4==b && $5==""' | wc -l | tr -d ' ')
  [ "$N" = "0" ] && break
  sleep 0.1
done
BEFORE=$(./measure/frameprobe-dense list 2>/dev/null | awk -F'\t' -v b="$BASE" '$4==b {print $1}' | tr '\n' ' ')

env "$@" "$BIN" > "$OUT/$TAG.app.log" 2> "$OUT/$TAG.app.err" &
APP=$!

WID=""
for _ in $(seq 1 80); do
  WID=""
  for cand in $(./measure/frameprobe-dense list 2>/dev/null | awk -F'\t' -v b="$BASE" '$4==b && $5=="" {print $1}'); do
    case " $BEFORE " in *" $cand "*) ;; *) WID=$cand; break;; esac
  done
  [ -n "$WID" ] && break
  sleep 0.1
done
if [ -z "$WID" ]; then
  echo "RUNONE FAIL no window for $BASE ($TAG)"
  kill $APP 2>/dev/null
  exit 1
fi
echo "$TAG pid=$APP wid=$WID bin=$BASE"

./measure/frameprobe-dense run --pid "$APP" --window-id "$WID" \
  --out "$OUT/$TAG.run" --script "$SCRIPT" --activate --global --tail 0.7 \
  > "$OUT/$TAG.probe.out" 2> "$OUT/$TAG.probe.err"
RC=$?

screencapture -x -o -l "$WID" "$OUT/$TAG.png" 2>/dev/null
sleep 0.2
kill $APP 2>/dev/null
wait $APP 2>/dev/null
echo "RUNONE done $TAG rc=$RC"
