#!/bin/zsh
# instrument.sh — M2-4-0 spike: run one test bundle with an external memory
# poller (ps RSS + vmmap summary timeline). Zero source changes.
# Usage: instrument.sh <Bundle> [class_filter] [interval_sec] [full_every]
# Artifacts → spike dir: <Bundle>.run.log / <Bundle>.timeline.tsv / vmmap-*.txt
set -euo pipefail

BUNDLE="${1:?bundle}"
FILTER="${2:-}"
INTERVAL="${3:-1}"
FULL_EVERY="${4:-10}"

ROOT="${0:A:h:h:h:h}"   # spike/ → m2-4-0-test-bundles → phases → gsd → repo root
SPIKE="${0:A:h}"
DD_DEFAULT=(~/Library/Developer/Xcode/DerivedData/Lightamer-*/Build/Products/Debug/Lightamer.app/Contents/PlugIns/LightamerTests(IOP|IOPParity|Layers|Library|Sessions|Export|App).xctest/Contents/MacOS/*(N))
DD=( ${~DD_DEFAULT} )
if [ ${#DD[@]} -eq 0 ]; then echo "error: test products missing" >&2; exit 2; fi
DD="$(ls -t ${DD[@]} | head -1)"
DD="${DD%Lightamer.app/*}"
HOST_BIN="$DD/Lightamer.app/Contents/MacOS/Lightamer"
PLUGINS="$DD/Lightamer.app/Contents/PlugIns"
TARGET="LightamerTests$BUNDLE"
XCTEST="$PLUGINS/${TARGET}.xctest"
XCODE_DEV="$(xcode-select -p)"

hostargs=()
[ -n "$FILTER" ] && hostargs=(-XCTest "$FILTER")

RUNLOG="$SPIKE/$BUNDLE.run.log"
TIMELINE="$SPIKE/$BUNDLE.timeline.tsv"
echo "epoch_sec	timestamp	rss_mb	footprint_mb	regions" > "$TIMELINE"

env \
  DYLD_INSERT_LIBRARIES="$DD/Lightamer.app/Contents/Frameworks/libXCTestBundleInject.dylib" \
  DYLD_LIBRARY_PATH="$DD:$XCODE_DEV/Platforms/MacOSX.platform/Developer/usr/lib" \
  DYLD_FRAMEWORK_PATH="$DD:$XCODE_DEV/Contents/SharedFrameworks:$XCODE_DEV/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
  XCTestBundlePath="$XCTEST" \
  "$HOST_BIN" "${hostargs[@]}" > "$RUNLOG" 2>&1 &
PID=$!
echo "host pid=$PID log=$RUNLOG"

T0=$(python3 -c 'import time; print(time.time())')
N=0
while kill -0 "$PID" 2>/dev/null; do
  NOW=$(python3 -c "import time; print(f'{time.time()-$T0:.2f}')")
  RSS_KB=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ' || echo 0)
  RSS_MB=$(( ${RSS_KB:-0} / 1024 ))
  # physical footprint via vmmap summary last line region count + footprint
  VMMAP_OUT=$(vmmap --summary "$PID" 2>/dev/null || true)
  FOOT_MB=$(print -r -- "$VMMAP_OUT" | grep -a "^Physical footprint" | awk '{print $3}' | head -1)
  NREG=$(print -r -- "$VMMAP_OUT" | grep -ac "^[A-Z_]" || true)
  print -r -- "$NOW	$(date +%H:%M:%S)	$RSS_MB	${FOOT_MB:-?}	$NREG" >> "$TIMELINE"
  (( N % FULL_EVERY == 0 )) && print -r -- "$VMMAP_OUT" > "$SPIKE/${BUNDLE}.vmmap-$(printf %03d $N).txt"
  (( N+=1 ))
  sleep "$INTERVAL"
done
wait "$PID" || true
echo "done. timeline: $TIMELINE"
tail -5 "$TIMELINE"
