#!/bin/bash
# rust-gui-viewport-probe.sh — A7b viewport/input probe (opens OUR window only).
#
# One command end to end; any gate failure exits non-zero:
#   0. preconditions: machine-guard, no other lightamer-gpui, user idle >= 5 min, no
#      foreign heavy work. Re-checked every 60s for up to 90 min, then give up
#      with the numbers (the window never opens).
#   1. compile the probe tools (no window yet).
#   2. per input path (a = framework callback, b = native subclass):
#      launch -> new window -> GEOM wait -> frame-probe self-check ->
#      synthetic input -> cropped shots -> 11s panel-vs-viewport run ->
#      self-exit wait -> parse the three gates.
#   3. memory fuse + user-activity abort during the window phase.
#
# usage: Scripts/rust-gui-viewport-probe.sh [--evidence-dir DIR]
# evidence default: .work/gsd/phases/rust-core/waves/A7b-evidence/
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT/target/debug/lightamer-gpui"
PROBES="$ROOT/crates/lightamer-gpui/probes"
EVIDENCE="$ROOT/.work/gsd/phases/rust-core/waves/A7b-evidence"

case "${1:-}" in
  "") ;;
  --evidence-dir) EVIDENCE="${2:-}"; [ -n "$EVIDENCE" ] || { echo "probe: --evidence-dir needs DIR" >&2; exit 2; };;
  -h|--help) echo "usage: Scripts/rust-gui-viewport-probe.sh [--evidence-dir DIR]"; exit 0 ;;
  *) echo "probe: ERROR: unknown arg: $1" >&2; echo "usage: Scripts/rust-gui-viewport-probe.sh [--evidence-dir DIR]" >&2; exit 2 ;;
esac

[ -x "$BIN" ] || { echo "probe: ERROR: missing binary: $BIN (build first)" >&2; exit 2; }
mkdir -p "$EVIDENCE" || { echo "probe: ERROR: cannot make $EVIDENCE" >&2; exit 2; }

TMP="$(mktemp -d -t lightamer-gpui-probe.XXXXXX)"
FULLSHOTS="$(mktemp -d -t lightamer-gpui-fullshots.XXXXXX)"
APID=""
FPID=""
MONPID=""
SUMMARY="$EVIDENCE/SUMMARY.txt"
: > "$SUMMARY"
cleanup() {
  [ -n "$FPID" ] && kill "$FPID" 2>/dev/null
  [ -n "$APID" ] && kill -9 "$APID" 2>/dev/null
  [ -n "$MONPID" ] && kill "$MONPID" 2>/dev/null
  rm -rf "$TMP"
  echo "probe: full-window originals kept outside the repo: $FULLSHOTS"
}
trap cleanup EXIT

idle_secs() {
  local ns
  ns=$(ioreg -n IOHIDSystem -r 2>/dev/null | awk '/HIDIdleTime/ {print $NF; exit}')
  case "$ns" in ''|*[!0-9]*) echo -1 ;; *) echo $(( ns / 1000000000 )) ;; esac
}
swap_used_mb() {
  sysctl -n vm.swapusage 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); sub(/M/,"",v); print int(v); exit}}'
}
free_pct() {
  memory_pressure 2>/dev/null | awk '/free percentage/ {gsub(/%/,"",$NF); print $NF}'
}
foreign_heavy() {
  # Anything building/rendering that is not us (this probe runs no cargo).
  pgrep -x cargo >/dev/null 2>&1 && return 0
  pgrep -x rustc >/dev/null 2>&1 && return 0
  pgrep -x xcodebuild >/dev/null 2>&1 && return 0
  pgrep -f "darktable-cli" >/dev/null 2>&1 && return 0
  return 1
}

echo "probe: step 0/4 preconditions (idle>=300s, no lightamer-gpui, guard, no heavy)"
DEADLINE=$(( $(date +%s) + 5400 ))
BASE_SWAP=""
while true; do
  IDLE=$(idle_secs)
  GUARD_OUT=$("$SCRIPT_DIR/machine-guard.sh" 2>&1); GUARD_RC=$?
  DTPROC=$(pgrep -x lightamer-gpui 2>/dev/null | tr '\n' ' ')
  HEAVY="no"; foreign_heavy && HEAVY="yes"
  echo "probe: wait idle=${IDLE}s guard_rc=$GUARD_RC lightamer-gpui=[$DTPROC] heavy=$HEAVY :: $GUARD_OUT"
  if [ "$GUARD_RC" -eq 0 ] && [ -z "$DTPROC" ] && [ "$IDLE" -ge 300 ] 2>/dev/null && [ "$HEAVY" = "no" ]; then
    break
  fi
  NOW=$(date +%s)
  if [ "$NOW" -ge "$DEADLINE" ]; then
    echo "probe: TIMEOUT 90min without an idle machine (window never opened)" >&2
    echo "probe: last idle=${IDLE}s guard=[$GUARD_OUT] lightamer-gpui=[$DTPROC] heavy=$HEAVY" >&2
    exit 3
  fi
  sleep 60
done
echo "probe: preconditions green"

echo "probe: step 1/4 compile probe tools (no window)"
swiftc -O -o "$TMP/frameprobe" "$PROBES/FrameProbeRegions.swift" || { echo "probe: frameprobe compile failed" >&2; exit 2; }
swiftc -O -o "$TMP/crop" "$PROBES/crop.swift" || { echo "probe: crop compile failed" >&2; exit 2; }
"$TMP/frameprobe" list >/dev/null || { echo "probe: frameprobe list failed" >&2; exit 2; }
echo "probe: tools ok"

# Memory fuse monitor (started after the compile warmup so the swap baseline
# is post-warmup): trips on free<20% or swap growth >4GB.
BASE_SWAP=$(swap_used_mb)
echo "probe: fuse baseline swap_used=${BASE_SWAP}MB"
(
  while sleep 5; do
    F=$(free_pct); S=$(swap_used_mb)
    if [ -n "$F" ] && [ "$F" -lt 20 ] 2>/dev/null; then
      echo "FUSE free=${F}%<20% swap=${S}MB" > "$TMP/FUSE"; break
    fi
    if [ -n "$S" ] && [ -n "$BASE_SWAP" ] && [ $(( S - BASE_SWAP )) -gt 4096 ] 2>/dev/null; then
      echo "FUSE swap growth $(( S - BASE_SWAP ))MB>4096MB (now=${S}MB base=${BASE_SWAP}MB)" > "$TMP/FUSE"; break
    fi
  done
) &
MONPID=$!
fuse_check() {
  if [ -f "$TMP/FUSE" ]; then
    echo "probe: $(cat "$TMP/FUSE") -- killing app, aborting" | tee -a "$SUMMARY" >&2
    [ -n "$APID" ] && kill -9 "$APID" 2>/dev/null
    exit 4
  fi
}

fp_list() { "$TMP/frameprobe" list 2>/dev/null; }

# Count F rows whose pts falls between the auto E begin/end timestamps and
# whose region column $COL exceeds 0. (The trace lists all F rows first, then
# all E rows, so the window must be taken by timestamp, not file order.)
# Regions columns: F idx pts cb diff maxd cells r0 r1 ... (r0 = $8, r1 = $9).
count_region() { # <trace> <col>
  awk -v col="$2" '
    /^F / { n++; pts[n]=$3; val[n]=$col }
    /^E begin / { t0=$3 }
    /^E end/ { t1=$3 }
    END { c=0; for (i=1;i<=n;i++) if (pts[i]>=t0 && pts[i]<=t1 && val[i]>0) c++; print c+0 }' "$1"
}

run_path() { # <a|b>
  local path="$1" tag="path-$path"
  echo "probe: step 2/4 $tag launch"
  fuse_check
  local before
  before=$(fp_list | awk -F'\t' '$4=="lightamer-gpui" {print $1}' | tr '\n' ' ')
  "$BIN" --input-path "$path" --quit-after-secs 100 --panel-tick-ms 200 \
    > "$EVIDENCE/app-$tag.log" 2>&1 &
  APID=$!
  local t0; t0=$(date +%s)
  local wid=""
  for _ in $(seq 1 200); do
    for cand in $(fp_list | awk -F'\t' '$4=="lightamer-gpui" {print $1}'); do
      case " $before " in *" $cand "*) ;; *) wid="$cand"; break 2;; esac
    done
    kill -0 "$APID" 2>/dev/null || { echo "probe: $tag app died before windowing" >&2; tail -20 "$EVIDENCE/app-$tag.log" >&2; return 1; }
    fuse_check
    sleep 0.1
  done
  [ -n "$wid" ] || { echo "probe: $tag no window in 20s" >&2; kill -9 "$APID" 2>/dev/null; APID=""; return 1; }
  local appear=$(( $(date +%s) - t0 ))
  echo "probe: $tag pid=$APID wid=$wid appear=${appear}s (informational, no gate)"
  # Window position for input coordinates + crops.
  local pos
  pos=$(fp_list | awk -F'\t' -v w="$wid" '$1==w {print $3}')
  local wx=${pos%%,*} wy=${pos##*,}
  echo "probe: $tag window at $wx,$wy"

  # GEOM wait: viewport proven alive before the probe self-check.
  echo "probe: $tag waiting for GEOM (viewport alive)"
  for _ in $(seq 1 200); do
    grep -q "^GEOM " "$EVIDENCE/app-$tag.log" 2>/dev/null && break
    kill -0 "$APID" 2>/dev/null || { echo "probe: $tag app died waiting GEOM" >&2; tail -20 "$EVIDENCE/app-$tag.log" >&2; return 1; }
    fuse_check
    sleep 0.1
  done
  grep -q "^GEOM " "$EVIDENCE/app-$tag.log" || { echo "probe: $tag no GEOM in 20s" >&2; kill -9 "$APID" 2>/dev/null; APID=""; return 1; }
  if grep -q "FAIL" "$EVIDENCE/app-$tag.log"; then
    echo "probe: $tag app log already has FAIL" >&2; grep "FAIL" "$EVIDENCE/app-$tag.log" >&2
    kill -9 "$APID" 2>/dev/null; APID=""; return 1
  fi

  # Self-check: the probe must see the sweeping marker (app proven alive
  # above, so zero here means the probe is broken, not the viewport).
  echo "probe: $tag self-check (probe must see the marker)"
  fuse_check
  printf 'mark begin\nwait 2000\nmark end\n' > "$TMP/self.scr"
  "$TMP/frameprobe" run --pid "$APID" --window-id "$wid" \
    --out "$EVIDENCE/self-$tag.run" --script "$TMP/self.scr" \
    --activate --global --tail 0.5 --regions "0,0,0.6667,1;0,0.965,0.6667,1" \
    > "$EVIDENCE/self-$tag.out" 2>&1 || { echo "probe: $tag self-check run failed" >&2; return 1; }
  local self_view self_mark
  self_view=$(count_region "$EVIDENCE/self-$tag.run" 8)
  self_mark=$(count_region "$EVIDENCE/self-$tag.run" 9)
  echo "probe: $tag self-check viewport_changed=$self_view marker_changed=$self_mark (gate >=5/>=1)"
  if [ "$self_view" -lt 5 ] || [ "$self_mark" -lt 1 ]; then
    echo "probe: $tag SELF-CHECK FAILED (probe broken, viewport was alive)" >&2
    kill -9 "$APID" 2>/dev/null; APID=""; return 1
  fi

  # Input: 20 synthetic moves + down/up; count INPUT lines.
  echo "probe: $tag input (20 moves + down/up)"
  fuse_check
  local idle_before; idle_before=$(idle_secs)
  if [ "$idle_before" -lt 60 ] 2>/dev/null; then
    echo "probe: $tag user back (idle=${idle_before}s), aborting synthesis" >&2
    kill -9 "$APID" 2>/dev/null; APID=""; return 1
  fi
  {
    echo "mark begin"
    i=0
    while [ "$i" -lt 20 ]; do
      echo "move $(( wx + 150 + i * 25 )) $(( wy + 400 ))"
      echo "wait 60"
      i=$(( i + 1 ))
    done
    echo "down $(( wx + 400 )) $(( wy + 400 ))"
    echo "wait 120"
    echo "up $(( wx + 400 )) $(( wy + 400 ))"
    echo "wait 300"
    echo "mark end"
  } > "$TMP/input.scr"
  "$TMP/frameprobe" run --pid "$APID" --window-id "$wid" \
    --out "$EVIDENCE/input-$tag.run" --script "$TMP/input.scr" \
    --activate --global --tail 0.5 \
    > "$EVIDENCE/input-$tag.out" 2>&1 || { echo "probe: $tag input run failed" >&2; return 1; }
  local inputs moves
  inputs=$(grep -c "^INPUT seq=.* path=$path " "$EVIDENCE/app-$tag.log" || true)
  moves=$(grep -c "^INPUT seq=.* path=$path kind=move " "$EVIDENCE/app-$tag.log" || true)
  echo "probe: $tag input lines=$inputs moves=$moves (gate lines>=19)"
  if [ "$inputs" -lt 19 ]; then
    echo "probe: $tag INPUT GATE FAILED" >&2
    kill -9 "$APID" 2>/dev/null; APID=""; return 1
  fi

  # Cropped shots (full window stays outside the repo).
  echo "probe: $tag shots"
  fuse_check
  screencapture -x -o -l "$wid" "$FULLSHOTS/full-$tag.png" 2>/dev/null || { echo "probe: $tag shot failed" >&2; return 1; }
  "$TMP/crop" "$FULLSHOTS/full-$tag.png" 300 200 200 200 "$EVIDENCE/band-edge-$tag.png" || return 1
  "$TMP/crop" "$FULLSHOTS/full-$tag.png" 1620 100 500 300 "$EVIDENCE/panel-$tag.png" || return 1
  # V3: panel repaints at 200ms for 11s; viewport must keep changing.
  # No synthetic events in this window, so the idle timer is ours to read:
  # user activity aborts the run.
  echo "probe: $tag v3 (11s panel repaint vs viewport)"
  fuse_check
  printf 'mark begin\nwait 11000\nmark end\n' > "$TMP/v3.scr"
  "$TMP/frameprobe" run --pid "$APID" --window-id "$wid" \
    --out "$EVIDENCE/v3-$tag.run" --script "$TMP/v3.scr" \
    --activate --global --tail 0.5 --regions "0,0,0.6667,1;0.6667,0,1,1" \
    > "$EVIDENCE/v3-$tag.out" 2>&1 &
  FPID=$!
  sleep 3
  while kill -0 "$FPID" 2>/dev/null; do
    sleep 2
    kill -0 "$FPID" 2>/dev/null || break
    fuse_check
    gap_idle=$(idle_secs)
    if [ "$gap_idle" -lt 2 ] 2>/dev/null; then
      echo "probe: $tag user active during v3 gap (idle=${gap_idle}s), aborting" >&2
      kill "$FPID" 2>/dev/null; FPID=""
      kill -9 "$APID" 2>/dev/null; APID=""
      return 1
    fi
  done
  wait "$FPID" 2>/dev/null; FPID=""
  v3_view=$(count_region "$EVIDENCE/v3-$tag.run" 8)
  v3_panel=$(count_region "$EVIDENCE/v3-$tag.run" 9)
  echo "probe: $tag v3 viewport_changed=$v3_view panel_changed=$v3_panel (gate viewport>=450)"
  if [ "$v3_view" -lt 450 ]; then
    echo "probe: $tag V3 GATE FAILED" >&2
    kill -9 "$APID" 2>/dev/null; APID=""; return 1
  fi

  # Self-exit wait.
  echo "probe: $tag waiting for self-exit"
  for _ in $(seq 1 600); do
    kill -0 "$APID" 2>/dev/null || break
    fuse_check
    sleep 0.5
  done
  if kill -0 "$APID" 2>/dev/null; then
    echo "probe: $tag app did not self-exit" >&2
    kill -9 "$APID" 2>/dev/null; APID=""; return 1
  fi
  APID=""

  return 0
}

geom_gate() { # <tag> -> 0/1, prints the four numbers
  local tag="$1"
  local line
  line=$(grep "^GEOM " "$EVIDENCE/app-$tag.log" | tail -1)
  # GEOM frame=N canvas=[a b c d] view=(x,y wxh) layer=(wxh) drawable=WxH scale=S ...
  local canvas view layer drawable scale
  canvas=$(printf '%s' "$line" | sed -n 's/.*canvas=\[\([^]]*\)\].*/\1/p')
  view=$(printf '%s' "$line" | sed -n 's/.*view=(\([^)]*\)).*/\1/p')
  layer=$(printf '%s' "$line" | sed -n 's/.*layer=(\([^)]*\)).*/\1/p')
  drawable=$(printf '%s' "$line" | sed -n 's/.*drawable=\([^ ]*\).*/\1/p')
  scale=$(printf '%s' "$line" | sed -n 's/.*scale=\([^ ]*\).*/\1/p')
  echo "probe: $tag geom canvas=[$canvas] view=($view) layer=($layer) drawable=$drawable scale=$scale"
  python3 - "$canvas" "$view" "$layer" "$drawable" "$scale" <<'PYEOF'
import sys
canvas, view, layer, drawable, scale = sys.argv[1:6]
_, _, cw, ch = [float(x) for x in canvas.split()]
vxy, vwh = view.split()
vw, vh = [float(x) for x in vwh.split("x")]
lw, lh = [float(x) for x in layer.split("x")]
dw, dh = [float(x) for x in drawable.split("x")]
s = float(scale)
checks = [
    ("canvas-vs-view", abs(cw - vw) <= 0.5 and abs(ch - vh) <= 0.5),
    ("layer-vs-view", abs(lw - vw) <= 0.5 and abs(lh - vh) <= 0.5),
    ("drawable-vs-view-scale", abs(dw - vw * s) <= 1.0 and abs(dh - vh * s) <= 1.0),
]
for name, ok in checks:
    print(f"probe: geom {name} {'PASS' if ok else 'FAIL'}")
sys.exit(0 if all(ok for _, ok in checks) else 1)
PYEOF
}

overall=0
for path in a b; do
  if run_path "$path"; then
    if geom_gate "path-$path" | tee -a "$SUMMARY"; then
      echo "probe: path-$path ALL GATES PASS" | tee -a "$SUMMARY"
    else
      echo "probe: path-$path GEOMETRY GATE FAILED" | tee -a "$SUMMARY"
      overall=1
    fi
  else
    echo "probe: path-$path FAILED" | tee -a "$SUMMARY"
    overall=1
  fi
done

kill "$MONPID" 2>/dev/null

echo "probe: step 3/4 residuals"
if pgrep -x lightamer-gpui >/dev/null 2>&1; then
  echo "probe: residual lightamer-gpui processes:" >&2; pgrep -fl lightamer-gpui >&2; overall=1
else
  echo "probe: no residual lightamer-gpui processes"
fi

echo "probe: step 4/4 evidence: $EVIDENCE"
ls -la "$EVIDENCE"
if [ "$overall" -eq 0 ]; then echo "probe: ALL GREEN (paths a+b)"; else echo "probe: FAILED"; fi
exit "$overall"
