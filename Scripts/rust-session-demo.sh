#!/bin/bash
# rust-session-demo.sh — B12' wave-one demo: new/verify/backup/restore/dual-open/adopt.
#
# Everything runs in the script's own temp dir with empty placeholder files:
# no user photo library reads, no real Application Support writes (the
# templates override points at the temp dir too). Exits 0 on success.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lightamer-session-demo-XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
export LIGHTAMER_APP_SUPPORT_DIR="$TMP/app-support"

"$ROOT/Scripts/machine-guard.sh"
(cd "$ROOT" && cargo build -p lightamer-cli --locked -j6)
CLI="$ROOT/target/debug/lightamer-cli"

say() { printf '\n==> %s\n' "$1"; }
fail() { echo "demo: FAIL: $1" >&2; exit 1; }
line() { printf '{"id": "%s", "params": %s}\n' "$1" "$2"; }

say "1. create a session"
{
  line "session.new" "{\"name\": \"Demo\", \"parent\": \"$TMP\"}"
  line "session.close" "{}"
} > "$TMP/new.jsonl"
"$CLI" run --file "$TMP/new.jsonl" || fail "session.new"
find "$TMP/Demo" -mindepth 1 | sort
[ -f "$TMP/Demo/Demo.lmsessiondb" ] || fail "database missing"

say "2. verify it: no findings"
{
  line "session.open" "{\"path\": \"$TMP/Demo\"}"
  line "session.verify" "{}"
  line "session.close" "{}"
} > "$TMP/verify.jsonl"
"$CLI" run --file "$TMP/verify.jsonl" | tee "$TMP/verify.log" || fail "verify run"
grep -q '"count":0' "$TMP/verify.log" || fail "expected zero findings"

say "3. drop an empty placeholder in Capture/"
touch "$TMP/Demo/Capture/placeholder.txt"
[ ! -s "$TMP/Demo/Capture/placeholder.txt" ] || fail "placeholder not empty"

say "4. back up, list it, check the database"
{
  line "session.open" "{\"path\": \"$TMP/Demo\"}"
  line "session.backup" "{\"dest\": \"$TMP/Demo-backup\"}"
  line "session.close" "{}"
} > "$TMP/backup.jsonl"
"$CLI" run --file "$TMP/backup.jsonl" || fail "backup run"
find "$TMP/Demo-backup" -mindepth 1 | sort
[ -f "$TMP/Demo-backup/Capture/placeholder.txt" ] || fail "placeholder did not travel"
[ "$(sqlite3 "$TMP/Demo-backup/Demo-backup.lmsessiondb" 'PRAGMA integrity_check;')" = "ok" ] \
  || fail "backup database corrupt"

say "5. restore elsewhere, open it, verify"
{
  line "session.restore" "{\"backup\": \"$TMP/Demo-backup\", \"dest\": \"$TMP/Demo-restored\"}"
  line "session.verify" "{}"
  line "session.close" "{}"
} > "$TMP/restore.jsonl"
"$CLI" run --file "$TMP/restore.jsonl" | tee "$TMP/restore.log" || fail "restore run"
grep -q '"count":0' "$TMP/restore.log" || fail "restored session has findings"
[ -f "$TMP/Demo-restored/Capture/placeholder.txt" ] || fail "placeholder lost in restore"

say "6. double open refused; kill the holder; open again"
line "session.open" "{\"path\": \"$TMP/Demo\"}" > "$TMP/hold.jsonl"
"$CLI" run --file "$TMP/hold.jsonl" --hold 20 > "$TMP/hold.log" 2>&1 &
HOLDER=$!
for _ in $(seq 1 300); do
  grep -q "hold: keeping" "$TMP/hold.log" 2>/dev/null && break
  sleep 0.2
done
grep -q "hold: keeping" "$TMP/hold.log" || {
  kill -9 "$HOLDER" 2>/dev/null || true
  wait "$HOLDER" 2>/dev/null || true
  fail "holder never opened"
}
if "$CLI" run --file "$TMP/hold.jsonl" > "$TMP/double.log" 2>&1; then
  kill -9 "$HOLDER" 2>/dev/null || true
  wait "$HOLDER" 2>/dev/null || true
  fail "second open was accepted"
fi
cat "$TMP/double.log"
grep -q "already open" "$TMP/double.log" || fail "refusal names no holder"
grep -q "process" "$TMP/double.log" || fail "refusal names no process"
kill -9 "$HOLDER" 2>/dev/null || true
wait "$HOLDER" 2>/dev/null || true
"$CLI" run --file "$TMP/hold.jsonl" --hold 1 > "$TMP/reopen.log" 2>&1 || fail "reopen after kill"
grep -q "session.open ok" "$TMP/reopen.log" || fail "reopen did not succeed"
echo "reopen after kill: ok"

say "7. adopt an existing folder; originals untouched"
mkdir -p "$TMP/Adopt/sub"
echo "keep me" > "$TMP/Adopt/keep.txt"
echo "data" > "$TMP/Adopt/sub/blob.bin"
sha_before=$(shasum -a 256 "$TMP/Adopt/keep.txt" "$TMP/Adopt/sub/blob.bin")
{
  line "session.open" "{\"path\": \"$TMP/Adopt\"}"
  line "session.close" "{}"
} > "$TMP/adopt.jsonl"
"$CLI" run --file "$TMP/adopt.jsonl" || fail "adopt run"
sha_after=$(shasum -a 256 "$TMP/Adopt/keep.txt" "$TMP/Adopt/sub/blob.bin")
[ "$sha_before" = "$sha_after" ] || fail "adopt moved original files"
echo "originals unchanged"

say "8. clean up"
rm -rf "$TMP"
trap - EXIT
echo "demo: ALL GREEN"
