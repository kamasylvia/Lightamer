#!/bin/bash
# rust-render-demo.sh — B1-c wave demo: render jobs on a synthetic session.
#
# Runs the release-built `render-demo` subcommand: five private gain modules
# on one photo's chain, seven printed steps (first render, selective
# recompute, three rapid generations, cancel, idle timing, cleanup).
# Everything runs in the demo's own temp dir with synthetic pixels: no user
# photo library reads, no real Application Support writes. Exits 0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lightamer-render-demo-XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

say() { printf '\n==> %s\n' "$1"; }
fail() { echo "demo: FAIL: $1" >&2; exit 1; }

"$ROOT/Scripts/machine-guard.sh"
(cd "$ROOT" && cargo build --release -p lightamer-cli --locked -j6)
CLI="$ROOT/target/release/lightamer-cli"

say "render-demo on synthetic pixels (release build)"
"$CLI" render-demo --size 256 | tee "$TMP/demo.log" || fail "render-demo run"
grep -q "demo: ALL GREEN" "$TMP/demo.log" || fail "demo did not report green"
grep -q "step 3: change the middle gain" "$TMP/demo.log" || fail "step 3 missing"
grep -q "step 4: fire three generations" "$TMP/demo.log" || fail "step 4 missing"
grep -q "no render event: ok" "$TMP/demo.log" || fail "cancel step missing"

say "hygiene: no leftover temp dirs, no held processes"
leftovers="$(ls "${TMPDIR:-/tmp}" 2>/dev/null | grep -E "lightamer-render-demo-" | grep -v "^$(basename "$TMP")\$" || true)"
[ -z "$leftovers" ] || fail "leftover temp dirs: $leftovers"

rm -rf "$TMP"
trap - EXIT
echo "demo: ALL GREEN"
