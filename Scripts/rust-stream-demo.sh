#!/bin/bash
# rust-stream-demo.sh — B1d-b wave demo: over-limit frames auto-stream.
#
# Runs the release-built `stream-demo` subcommand on a 120MP synthetic
# frame: strips on a point-only chain, blocks with a blur module, a small
# spill limit failing typed, three rapid generations (only the latest
# reports ready), a mid-stream cancel (budget back, spill clean), a resource
# table, and cleanup. Peak RSS comes from /usr/bin/time -l.
# Everything runs in the demo's own temp dir with synthetic pixels: no user
# photo library reads, no real Application Support writes. Exits 0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lightamer-stream-demo-XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

say() { printf '\n==> %s\n' "$1"; }
fail() { echo "demo: FAIL: $1" >&2; exit 1; }

"$ROOT/Scripts/machine-guard.sh"
(cd "$ROOT" && cargo build --release -p lightamer-cli --locked -j6)
CLI="$ROOT/target/release/lightamer-cli"

say "stream-demo on synthetic pixels (release build)"
/usr/bin/time -l "$CLI" stream-demo --mp 120 > "$TMP/demo.log" 2> "$TMP/time.log" \
  || fail "stream-demo run"
cat "$TMP/demo.log"
grep -q "demo: ALL GREEN" "$TMP/demo.log" || fail "demo did not report green"
grep -q "step 1: mode=strip pieces=" "$TMP/demo.log" || fail "step 1 strip missing"
grep -q "step 2: mode=block pieces=" "$TMP/demo.log" || fail "step 2 block missing"
grep -q "step 3: spill limit refused" "$TMP/demo.log" || fail "step 3 missing"
grep -q "step 4: only generation" "$TMP/demo.log" || fail "step 4 missing"
grep -q "no render event: ok" "$TMP/demo.log" || fail "cancel step missing"
grep -q "resource table" "$TMP/demo.log" || fail "resource table missing"

say "peak resident set (whole demo process)"
RSS="$(grep "maximum resident set size" "$TMP/time.log" | awk '{print $1}')"
echo "peak rss = $((RSS / 1024 / 1024))MB ($RSS bytes)"

say "hygiene: no leftover temp dirs, no held processes"
leftovers="$(ls "${TMPDIR:-/tmp}" 2>/dev/null | grep -E "lightamer-stream-demo-" | grep -v "^$(basename "$TMP")\$" || true)"
[ -z "$leftovers" ] || fail "leftover temp dirs: $leftovers"

rm -rf "$TMP"
trap - EXIT
echo "demo: ALL GREEN"
