#!/bin/bash
# rust-history-demo.sh — B13'-b2 wave demo: persisted history, kill -9, sync/merge, 10k gate.
#
# Everything runs in the script's own temp dir with empty placeholder files:
# no user photo library reads, no real Application Support writes. Exits 0 on
# success; 3 when the 10k gate stays UNRELIABLE after retries (machine busy:
# neither pass nor fail).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lightamer-history-demo-XXXXXX")"
echo $$ > "$TMP/.owner-pid"
HOLDER=""
cleanup() {
  if [ -n "$HOLDER" ] && ps -p "$HOLDER" -o comm= 2>/dev/null | grep -q "lightamer-cli"; then
    kill -9 "$HOLDER" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

# A run killed untrappable (-9, power) leaves its $TMP: no trap runs. Sweep
# siblings whose owner is dead; pid-less (pre-tag) dirs only past 60 minutes,
# so a live run (minutes, always tagged) is never touched.
for stale in "${TMPDIR:-/tmp}"/lightamer-history-demo-*; do
  [ -d "$stale" ] || continue
  [ "$stale" = "$TMP" ] && continue
  owner="$(cat "$stale/.owner-pid" 2>/dev/null || true)"
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    continue
  fi
  if [ -z "$owner" ] && [ -z "$(find "$stale" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
    continue
  fi
  echo "sweep: removing stale $stale"
  rm -rf "$stale" || true
done

# Step 5 sizes: the gate procedure itself (3 fresh-slice rounds, median vs
# 1000ms); setup holds exactly runs * photos.
BIG_PHOTOS=10000
BIG_RUNS=3
"$ROOT/Scripts/machine-guard.sh"
(cd "$ROOT" && cargo build -p lightamer-cli --locked -j6)
CLI="$ROOT/target/debug/lightamer-cli"

say() { printf '\n==> %s\n' "$1"; }
fail() { echo "demo: FAIL: $1" >&2; exit 1; }
line() { printf '{"id": "%s", "params": %s}\n' "$1" "$2"; }
short() { printf '%s' "$1" | cut -c1-8; }

say "1. plant a session with three empty photos"
"$CLI" bench setup --parent "$TMP" --name Shoot --photos 3
DB="$TMP/Shoot/Shoot.lmsessiondb"
A="$(sqlite3 "$DB" "SELECT uuid FROM photos ORDER BY id LIMIT 1;")"
B="$(sqlite3 "$DB" "SELECT uuid FROM photos ORDER BY id LIMIT 1 OFFSET 1;")"
C="$(sqlite3 "$DB" "SELECT uuid FROM photos ORDER BY id LIMIT 1 OFFSET 2;")"
[ -n "$A" ] && [ -n "$B" ] && [ -n "$C" ] || fail "uuids missing"
SA="$(short "$A")"; SB="$(short "$B")"; SC="$(short "$C")"
echo "a=$SA b=$SB c=$SC (8-char shorts)"
[ "$(find "$TMP/Shoot/Capture" -type f | wc -l)" -eq 3 ] || fail "want 3 placeholders"
[ -z "$(find "$TMP/Shoot/Capture" -type f ! -empty)" ] || fail "placeholders not empty"

say "2. edit A twice, undo, redo; close; reopen and compare"
{
  line "session.open" "{\"path\": \"$TMP/Shoot\"}"
  line "develop.set" "{\"ids\": [\"$A\"], \"module\": \"rawprepare\", \"patch\": {\"white\": {\"type\": \"int\", \"value\": 1}}}"
  line "develop.set" "{\"ids\": [\"$A\"], \"module\": \"rawprepare\", \"patch\": {\"white\": {\"type\": \"int\", \"value\": 2}}}"
  line "history.undo" "{\"id\": \"$A\"}"
  line "history.redo" "{\"id\": \"$A\"}"
  line "session.close" "{}"
} > "$TMP/edit.jsonl"
"$CLI" run --file "$TMP/edit.jsonl" | tee "$TMP/edit.log" || fail "edit run"
grep -q "line 3: develop.set ok.*photos=\[[^]]*$SA:3:2" "$TMP/edit.log" || fail "A not 3:2 after two sets"
grep -q "line 5: history.redo ok.*photos=\[[^]]*$SA:3:2" "$TMP/edit.log" || fail "redo did not return to 3:2"
{
  line "session.open" "{\"path\": \"$TMP/Shoot\"}"
  line "develop.copy" "{\"id\": \"$A\"}"
  line "develop.copy" "{\"id\": \"$B\"}"
  line "develop.copy" "{\"id\": \"$C\"}"
  line "session.close" "{}"
} > "$TMP/reopen.jsonl"
"$CLI" run --file "$TMP/reopen.jsonl" | tee "$TMP/reopen.log" || fail "reopen run"
REOPEN2="$(grep "line 2: develop.copy ok" "$TMP/reopen.log")"
echo "$REOPEN2" | grep -q "$SA:3:2" || fail "reopened A differs: $REOPEN2"
echo "$REOPEN2" | grep -q "$SB:1:0" || fail "reopened B differs: $REOPEN2"
echo "$REOPEN2" | grep -q "$SC:1:0" || fail "reopened C differs: $REOPEN2"
echo "reopened states match: $SA:3:2 $SB:1:0 $SC:1:0"

say "3. kill -9 mid-drag: committed stays, live dies"
{
  line "session.open" "{\"path\": \"$TMP/Shoot\"}"
  line "develop.set" "{\"ids\": [\"$B\"], \"module\": \"rawprepare\", \"patch\": {\"white\": {\"type\": \"int\", \"value\": 1}}}"
  line "develop.set" "{\"ids\": [\"$B\"], \"module\": \"rawprepare\", \"patch\": {\"white\": {\"type\": \"int\", \"value\": 2}}}"
  line "develop.set" "{\"ids\": [\"$B\"], \"module\": \"rawprepare\", \"patch\": {\"white\": {\"type\": \"int\", \"value\": 3}}}"
  line "develop.beginInteraction" "{\"id\": \"$B\"}"
  line "develop.updateInteraction" "{\"id\": \"$B\", \"module\": \"rawprepare\", \"patch\": {\"white\": {\"type\": \"int\", \"value\": 99}}}"
} > "$TMP/hold.jsonl"
"$CLI" run --file "$TMP/hold.jsonl" --hold 30 > "$TMP/hold.log" 2>&1 &
HOLDER=$!
for _ in $(seq 1 300); do
  grep -q "hold: keeping" "$TMP/hold.log" 2>/dev/null && break
  sleep 0.1
done
grep -q "hold: keeping" "$TMP/hold.log" || { HOLDER=""; fail "holder never held"; }
grep -q "develop.updateInteraction ok" "$TMP/hold.log" || { HOLDER=""; fail "drag never started"; }
line "session.open" "{\"path\": \"$TMP/Shoot\"}" > "$TMP/double.jsonl"
if "$CLI" run --file "$TMP/double.jsonl" > "$TMP/double.log" 2>&1; then
  HOLDER=""; fail "second open succeeded while held"
fi
grep -q "already open" "$TMP/double.log" || { HOLDER=""; fail "refusal names no holder"; }
echo "held confirmed; killing the holder (pid $HOLDER, our own child)"
kill -9 "$HOLDER" 2>/dev/null || true
wait "$HOLDER" 2>/dev/null || true
HOLDER=""
{
  line "session.open" "{\"path\": \"$TMP/Shoot\"}"
  line "develop.copy" "{\"id\": \"$B\"}"
  line "session.close" "{}"
} > "$TMP/afterkill.jsonl"
"$CLI" run --file "$TMP/afterkill.jsonl" | tee "$TMP/afterkill.log" || fail "reopen after kill"
grep -q "line 2: develop.copy ok.*photos=\[[^]]*$SB:4:3" "$TMP/afterkill.log" \
  || fail "B is not 4 steps at cursor 3 after kill"
LABELS="$(sqlite3 "$DB" "SELECT history_steps.label FROM history_steps JOIN photos ON photos.id = photo_id WHERE uuid = '$B' ORDER BY idx;" | paste -sd, -)"
[ "$LABELS" = "import,develop.set,develop.set,develop.set" ] || fail "labels: $LABELS"
HASH="$(sqlite3 "$DB" "SELECT current_hash FROM photos WHERE uuid = '$B';")"
JSON="$(sqlite3 "$DB" "SELECT json FROM snapshots WHERE hash = '$HASH';")"
echo "$JSON" | grep -q '"value":3' || fail "current value is not 3: $JSON"
echo "$JSON" | grep -q '99' && fail "drag value 99 survived the kill" || true
echo "after kill: 4 steps, cursor 3, committed 3 kept, live 99 gone"

say "4. sync one module A->B; merge clipboard selection ->C"
{
  line "session.open" "{\"path\": \"$TMP/Shoot\"}"
  line "develop.copy" "{\"id\": \"$A\"}"
  line "develop.sync" "{\"id\": \"$A\", \"ids\": [\"$B\"], \"selection\": [\"rawprepare\"]}"
  line "develop.merge" "{\"ids\": [\"$C\"], \"selection\": [\"rawprepare.white\"]}"
  line "session.close" "{}"
} > "$TMP/sync.jsonl"
"$CLI" run --file "$TMP/sync.jsonl" | tee "$TMP/sync.log" || fail "sync run"
grep -q "line 3: develop.sync ok.*photos=\[[^]]*$SB:5:4" "$TMP/sync.log" || fail "B not 5:4 after sync"
grep -q "line 4: develop.merge ok.*photos=\[[^]]*$SC:2:1" "$TMP/sync.log" || fail "C not 2:1 after merge"
BLAST="$(sqlite3 "$DB" "SELECT history_steps.label FROM history_steps JOIN photos ON photos.id = photo_id WHERE uuid = '$B' ORDER BY idx DESC LIMIT 1;")"
CLAST="$(sqlite3 "$DB" "SELECT history_steps.label FROM history_steps JOIN photos ON photos.id = photo_id WHERE uuid = '$C' ORDER BY idx DESC LIMIT 1;")"
[ "$BLAST" = "develop.sync" ] || fail "B last label: $BLAST"
[ "$CLAST" = "develop.merge" ] || fail "C last label: $CLAST"
BHASH="$(sqlite3 "$DB" "SELECT current_hash FROM photos WHERE uuid = '$B';")"
BJSON="$(sqlite3 "$DB" "SELECT json FROM snapshots WHERE hash = '$BHASH';")"
echo "$BJSON" | grep -q '"value":2' || fail "B did not sync 2: $BJSON"
echo "sync: B 5:4 develop.sync value 2; merge: C 2:1 develop.merge"

say "5. ten thousand pastes on the release build"
(cd "$ROOT" && cargo build --release -p lightamer-cli --locked -j6)
RCLI="$ROOT/target/release/lightamer-cli"
"$RCLI" bench setup --parent "$TMP" --name Big --photos $((BIG_PHOTOS * BIG_RUNS))
attempt=1
while :; do
  "$RCLI" bench paste --session "$TMP/Big" --photos "$BIG_PHOTOS" --runs "$BIG_RUNS" \
    | tee "$TMP/bench.log"
  if grep -q " PASS$" "$TMP/bench.log"; then
    break
  elif grep -q "UNRELIABLE" "$TMP/bench.log"; then
    if [ "$attempt" -ge 3 ]; then
      echo "demo: UNRELIABLE (machine busy after 3 tries), gate skipped, neither pass nor fail"
      exit 3
    fi
    echo "bench paste: UNRELIABLE, waiting 60s and retrying ($attempt/3)"
    sleep 60
    attempt=$((attempt + 1))
  else
    fail "10k paste did not pass (see bench.log)"
  fi
done

say "6. clean up"
rm -rf "$TMP"
trap - EXIT
HOLDER=""
echo "demo: ALL GREEN"
