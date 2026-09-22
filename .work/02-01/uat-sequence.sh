#!/bin/zsh
# Reusable headless UAT sequence for the issue #1 tracer (Plan 02-01).
# Usage: uat-sequence.sh <run-label>
# Cold launch -> JPEG -> ARW -> JPEG reopen -> 3 stress cycles, screenshot +
# pixel sample at each display point, drawable readback lines from log stream.
set -u
LABEL="$1"
ROOT="/Volumes/UNITEK/Documents/Development/Lightamer"
W="$ROOT/.work/02-01"
PROD="$HOME/Library/Developer/Xcode/DerivedData/Lightamer-glcjhggtbffoiuguwlseyjhxhvew/Build/Products/Debug"
JPG="$ROOT/input/RAW/DSC00012.jpg"
ARW="$ROOT/input/RAW/DSC09991.ARW"
LOG="$W/uat-$LABEL.log"

wait_ready() { # file count-target
  local n=0
  for i in $(seq 1 180); do
    n=$(grep -c "pixelpipe output ready: $1" "$LOG" 2>/dev/null || echo 0)
    [ "$n" -ge "$2" ] && return 0
    sleep 0.5
  done
  echo "  TIMEOUT waiting for $1 (ready=$n want=$2)"; return 1
}
sample() { # png x y w h -> prints verdict line
  caffeinate -dis swift "$W/sample-png.swift" "$1" "$2" "$3" "$4" "$5" 2>/dev/null | tail -1
}
shot() { # name -> screenshot + sample viewport
  local f="$W/shot-$LABEL-$1.png"
  sleep 1
  screencapture -x "$f"
  printf "  step %-8s " "$1"
  sample "$f" 640 200 1560 1300
}

pkill -f "log stream" 2>/dev/null
osascript -e 'quit app "Lightamer"' >/dev/null 2>&1
sleep 2
: > "$LOG"
nohup /usr/bin/log stream --predicate 'subsystem == "com.kamasylvia.lightamer"' --level debug --style compact > "$LOG" 2>&1 &
sleep 1
open -n "$PROD/Lightamer.app"
sleep 8

echo "== (a) cold launch -> JPEG =="
open -a Lightamer "$JPG"
wait_ready DSC00012.jpg 1 && shot a-jpeg

echo "== (b) open ARW =="
open -a Lightamer "$ARW"
wait_ready DSC09991.ARW 1 && shot b-arw

echo "== (c) reopen JPEG =="
open -a Lightamer "$JPG"
wait_ready DSC00012.jpg 2 && shot c-jpeg

echo "== (d) stress: switch cycles =="
for cycle in 2 3 4; do
  open -a Lightamer "$ARW";  wait_ready DSC09991.ARW "$cycle" && shot "d$cycle-arw"
  open -a Lightamer "$JPG";  wait_ready DSC00012.jpg "$cycle" && shot "d$cycle-jpeg"
done

echo "== drawable readback + reuse lines =="
grep -E "DRAWABLE sample|DRAWABLE reuse" "$LOG" | tail -12
echo "== verdict =="
FAILS=$(grep -h "VERDICT: CANVAS" <(for f in "$W"/shot-$LABEL-*.png; do printf "  "; sample "$f" 640 200 1560 1300; done) | wc -l)
echo "canvas-verdicts=$FAILS"
[ "$FAILS" -eq 0 ] && echo "SEQUENCE GREEN" || echo "SEQUENCE FAILED"
