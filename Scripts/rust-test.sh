#!/bin/bash
# rust-test.sh — 格式检查 + clippy（-D warnings + 六条不崩溃 lint，自 rust-ci-lite.sh 并入，B12′-a）+ 全工作区测试，并打印测试总数。
# 用法：Scripts/rust-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "${1:-}" in
  "") ;;
  -h|--help) echo "usage: Scripts/rust-test.sh"; exit 0 ;;
  *) echo "rust-test: ERROR: unknown arg: $1" >&2; echo "usage: Scripts/rust-test.sh" >&2; exit 2 ;;
esac

(cd "$ROOT" && cargo fmt --all --check)
echo "rust-test: fmt OK"
(cd "$ROOT" && cargo clippy --workspace --all-targets --locked -j6 -- -D warnings -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented)
echo "rust-test: clippy OK"

OUT="$(mktemp -t rust-test.XXXXXX)"
trap 'rm -f "$OUT"' EXIT
(cd "$ROOT" && cargo test --workspace --locked -j6 2>&1 | tee "$OUT")
TOTAL=$(grep -oE '[0-9]+ passed' "$OUT" | awk '{s+=$1} END {print s+0}')
echo "rust-test: tests total passed=$TOTAL"
