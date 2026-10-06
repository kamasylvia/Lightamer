#!/bin/zsh
# M2-11-04 T1 GUI steady-state memory profile — one round, reproducible.
# usage: memprof-round.sh <N>
set -e
N="$1"
D=/tmp/m2-11-memprof
APP=~/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Build/Products/Debug/Lightamer.app/Contents/MacOS/Lightamer
PROJ=editor-probe-UNKNOWN

echo "[r$N] 1. probe: fresh project + import + open"
if [[ "${MEMPROF_REUSE_PROBE:-0}" == "1" ]]; then
  pkill -TERM -x Lightamer 2>/dev/null || true; sleep 3
  PROJ=$(defaults read com.kamasylvia.lightamer library.recentProjects 2>/dev/null | head -2 | tail -1 | tr -d ' ",')
else
  caffeinate -dis "$APP" -la_editor_probe /tmp/m2-11-memprof/raw > "$D/probe-r$N.log" 2>&1 &
  PROBE_PID=$!
  for i in {1..90}; do
    grep -q "rendered=yes" "$D/probe-r$N.log" 2>/dev/null && break
    grep -q "FAIL" "$D/probe-r$N.log" 2>/dev/null && break
    sleep 2
  done
  if ! grep -q "rendered=yes" "$D/probe-r$N.log" 2>/dev/null; then
    echo "[r$N] probe attempt failed — one retry"
    pkill -TERM -x Lightamer 2>/dev/null || true; sleep 3
    caffeinate -dis "$APP" -la_editor_probe /tmp/m2-11-memprof/raw > "$D/probe-r$N.log" 2>&1 &
    for i in {1..90}; do
      grep -q "rendered=yes" "$D/probe-r$N.log" 2>/dev/null && break
      grep -q "FAIL" "$D/probe-r$N.log" 2>/dev/null && break
      sleep 2
    done
  fi
  grep -q "rendered=yes" "$D/probe-r$N.log" || { echo "[r$N] PROBE FAILED"; exit 1; }
  sleep 2
  kill -TERM $PROBE_PID 2>/dev/null || true
  pkill -TERM -x Lightamer 2>/dev/null || true
  sleep 3
  PROJ=$(defaults read com.kamasylvia.lightamer library.recentProjects 2>/dev/null | head -2 | tail -1 | tr -d ' ",')
fi
echo "[r$N] project: $PROJ"

echo "[r$N] 2. launch app (normal GUI session)"
caffeinate -dis "$APP" > "$D/session-r$N.log" 2>&1 &
sleep 12
PID=$(pgrep -x Lightamer | head -1)
echo "[r$N] pid=$PID"

echo "[r$N] 3. open recent project via File menu"
osascript -e 'tell application "System Events" to tell process "Lightamer" to set frontmost to true' -e "delay 0.5" -e "tell application \"System Events\" to tell process \"Lightamer\" to click menu item \"$(basename "$PROJ")\" of menu 1 of menu item \"Open Recent Project\" of menu 1 of menu bar item \"文件\" of menu bar 1"
sleep 6

echo "[r$N] 4. double-click grid cell -> editor"
$D/cgdrive dclick 94 191
sleep 12

echo "[r$N] 5. zoom x2 + pan"
osascript -e 'tell application "System Events" to keystroke "z"'; sleep 4
$D/cgdrive scroll 713 469 -3 12; sleep 3
osascript -e 'tell application "System Events" to keystroke "f"'; sleep 4

echo "[r$N] 6. slider drag sequence x10"
$D/cgdrive drag 1345 736 1350 736; sleep 1.6
$D/cgdrive drag 1352 773 1370 773; sleep 1.6
$D/cgdrive drag 1350 736 1338 736; sleep 1.6
$D/cgdrive drag 1370 773 1345 773; sleep 1.6
$D/cgdrive drag 1338 736 1380 736; sleep 1.6
$D/cgdrive drag 1345 773 1338 773; sleep 1.6
$D/cgdrive drag 1380 736 1355 736; sleep 1.6
$D/cgdrive drag 1338 773 1378 773; sleep 1.6
$D/cgdrive drag 1355 736 1342 736; sleep 1.6
$D/cgdrive drag 1378 773 1360 773; sleep 1.6
$D/cgdrive scroll 713 469 3 12; sleep 2
screencapture -x "$D/r$N-after-edits.png"

echo "[r$N] 7. footprint T0"
footprint $PID --noCategories 2>/dev/null | head -8 > "$D/r$N-footprint-t0.txt"
ps -o rss= -p $PID | awk '{print "rss_kb: "$1}' >> "$D/r$N-footprint-t0.txt"
cat "$D/r$N-footprint-t0.txt"

echo "[r$N] 8. rest 60s (clearCaches sweep)"
sleep 60

echo "[r$N] 9. footprint T60 (steady state)"
footprint $PID --noCategories 2>/dev/null | head -8 > "$D/r$N-footprint-t60.txt"
ps -o rss= -p $PID | awk '{print "rss_kb: "$1}' >> "$D/r$N-footprint-t60.txt"
cat "$D/r$N-footprint-t60.txt"
screencapture -x "$D/r$N-steady.png"

echo "[r$N] 10. mechanism log capture"
/usr/bin/log show --last 15m --predicate "process == \"Lightamer\" AND (eventMessage CONTAINS[c] \"enforceBudget\" OR eventMessage CONTAINS[c] \"evict\")" --info > "$D/r$N-mech.log" 2>&1
echo "[r$N] mech lines: $(wc -l < "$D/r$N-mech.log")"

echo "[r$N] 11. quit"
osascript -e 'tell application "Lightamer" to quit' 2>/dev/null || true
sleep 4
pgrep -x Lightamer >/dev/null && { pkill -TERM -x Lightamer; sleep 3; }
pgrep -x Lightamer >/dev/null && { pkill -9 -x Lightamer; sleep 2; }
echo "[r$N] done"
