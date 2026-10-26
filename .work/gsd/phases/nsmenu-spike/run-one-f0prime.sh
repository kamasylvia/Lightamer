#!/bin/zsh
# run-one.sh — one AR-01-protocol churn measurement run (NSMenu spike F0).
# Protocol per D-AR1-10 F-8 + L082 discipline:
#   bare direct launch (child of this shell = my PID) + editor probe stay-alive
#   + probe stderr markers as the phase=editor machine check + 60s settle
#   (covers the ~50s LUT preheat) + System Events frontmost gate BEFORE any
#   reading (occluded readings invalid; visible-window CPU ~0% = sentinel)
#   + 30s window 6 samples @6s median + sample 6s stack corroboration with
#   SYMBOL TOTALS (sum across lines, never max single branch).
# Usage: run-one.sh <label> <binary-path> [extra-launch-args...]
set -u
em() { print -u2 "run-one: $*" }
label="$1"; shift
bin="$1"; shift
runlog="/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/nsmenu-spike/f0prime-logs/$label"
mkdir -p "$runlog"
FIXTURES=/tmp/nsmenu-spike-fixtures

# ── launch (my PID only) ────────────────────────────────────────────────
"$bin" -la_editor_probe "$FIXTURES" -la_probe_stay "$@" \
    >"$runlog/stdout.log" 2>"$runlog/stderr.log" &
pid=$!
print "pid=$pid bin=$bin args=$*" >> "$runlog/meta.txt"
em "launched pid=$pid label=$label"

# ── wait for the probe stay-alive marker (phase=editor machine check) ──
ok=0
for i in {1..300}; do
    sleep 1
    if grep -q "staying alive for measurement" "$runlog/stderr.log" 2>/dev/null; then ok=1; break; fi
    if ! kill -0 $pid 2>/dev/null; then em "EARLY-EXIT pid=$pid"; break; fi
done
if [[ $ok != 1 ]]; then
    print "VERDICT=ABORT reason=probe-marker-missing" >> "$runlog/meta.txt"
    kill $pid 2>/dev/null
    exit 3
fi
grep -q "rendered=yes" "$runlog/stderr.log" \
    || print "WARN=rendered-yes-absent" >> "$runlog/meta.txt"
print "editor-face=confirmed" >> "$runlog/meta.txt"

# ── settle 60s (LUT preheat ~50s, AR-01 F-8 §3) ─────────────────────────
sleep 60

# ── frontmost gate FIRST (L082: occluded readings invalid) ──────────────
osascript -e 'tell application "System Events" to set frontmost of process "Lightamer" to true' 2>>"$runlog/meta.txt"
sleep 1
fm=$(osascript -e 'tell application "System Events" to get frontmost of process "Lightamer"' 2>/dev/null)
print "frontmost=$fm t=$(date +%H:%M:%S)" >> "$runlog/meta.txt"
if [[ "$fm" != "true" ]]; then
    print "VERDICT=ABORT reason=occluded" >> "$runlog/meta.txt"
    kill $pid 2>/dev/null
    exit 4
fi
screencapture -x "$runlog/screen.png" 2>/dev/null

# ── 30s window, 6 samples @6s (AR-01 F-8 §5 shape) ──────────────────────
vals=()
t=0
for i in {1..6}; do
    v=$(ps -o %cpu= -p $pid 2>/dev/null | tr -d ' ')
    vals+=("$v")
    print "cpu[${t}]s=$v" >> "$runlog/cpu.txt"
    t=$((t+6))
    sleep 6
done
median=$(printf '%s\n' "${vals[@]}" | sort -g | awk 'NR==3{a=$1} NR==4{b=$1} END{printf "%.1f", (a+b)/2}')
print "median=$median" >> "$runlog/cpu.txt"

# ── sample 6s stack corroboration + symbol TOTALS ───────────────────────
sample $pid 6 -file "$runlog/sample.txt" >/dev/null 2>&1
for sym in makeMainMenu updateMainMenu appGraphDidChange prependValue beginTransaction UpdateStack sizeThatFits; do
    total=$(awk -v s="$sym" 'index($0, s) > 0 && $1 ~ /^[0-9]+$/ { t += $1 } END { print t+0 }' "$runlog/sample.txt")
    print "sym_$sym=$total" >> "$runlog/symbols.txt"
done
print "symbols=done" >> "$runlog/meta.txt"

# ── verdict line ────────────────────────────────────────────────────────
print "VERDICT=OK median=$median" >> "$runlog/meta.txt"

# ── kill MY pid only ────────────────────────────────────────────────────
kill $pid 2>/dev/null
sleep 3
kill -9 $pid 2>/dev/null
sleep 1
em "done label=$label median=$median"
