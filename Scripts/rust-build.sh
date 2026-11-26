#!/bin/bash
# rust-build.sh — 构建整个 Rust 工作区（并行度 6，机器单重活规定）。
# 用法：Scripts/rust-build.sh [--cold]   --cold 先删 target/ 再全量构建。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "${1:-}" in
  "") COLD=0 ;;
  --cold) COLD=1 ;;
  -h|--help) echo "usage: Scripts/rust-build.sh [--cold]"; exit 0 ;;
  *) echo "rust-build: ERROR: unknown arg: $1" >&2; echo "usage: Scripts/rust-build.sh [--cold]" >&2; exit 2 ;;
esac

if [ "$COLD" -eq 1 ]; then
  echo "rust-build: cold: removing $ROOT/target"
  rm -rf "$ROOT/target"
fi

SECONDS=0
(cd "$ROOT" && cargo build --workspace --locked -j6)
echo "rust-build: done in ${SECONDS}s (cold=$COLD, jobs=6)"
