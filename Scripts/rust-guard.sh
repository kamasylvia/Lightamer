#!/bin/bash
# rust-guard.sh — Rust 重活起跑前的守门。
# 复用 Scripts/machine-guard.sh，不重写、不改它一个字。
# 用法：Scripts/rust-guard.sh [--wait [秒]]
#   无参数：立刻返回 machine-guard.sh 的结果（0 通过 / 1 挡住）。
#   --wait [秒]：轮询到通过为止（默认上限 1800s，硬上限 7200s），
#     每轮打印带时间的检查结果；超时 exit 2（与 machine-guard 同口径）。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/machine-guard.sh"
INTERVAL=30
DEFAULT_LIMIT=1800
HARD_LIMIT=7200

usage() {
  echo "usage: Scripts/rust-guard.sh [--wait [seconds]]" >&2
  exit 2
}

[ -x "$GUARD" ] || { echo "rust-guard: ERROR: $GUARD missing or not executable" >&2; exit 2; }

case "${1:-}" in
  "") exec "$GUARD" ;;
  -h|--help) usage ;;
  --wait) ;;
  *) echo "rust-guard: ERROR: unknown arg: $1" >&2; usage ;;
esac

LIMIT="${2:-$DEFAULT_LIMIT}"
case "$LIMIT" in
  ''|*[!0-9]*) echo "rust-guard: ERROR: limit must be a non-negative integer: $LIMIT" >&2; exit 2 ;;
esac
if [ "$LIMIT" -gt "$HARD_LIMIT" ]; then
  echo "rust-guard: limit $LIMIT clamped to hard limit $HARD_LIMIT" >&2
  LIMIT="$HARD_LIMIT"
fi

DEADLINE=$(( $(date +%s) + LIMIT ))
while true; do
  if OUT=$("$GUARD" 2>&1); then
    echo "$(date '+%H:%M:%S') rust-guard: $OUT"
    exit 0
  fi
  NOW=$(date +%s)
  if [ "$NOW" -ge "$DEADLINE" ]; then
    echo "$(date '+%H:%M:%S') rust-guard: $OUT"
    echo "rust-guard: TIMEOUT after ${LIMIT}s" >&2
    exit 2
  fi
  echo "$(date '+%H:%M:%S') rust-guard: $OUT (retry in ${INTERVAL}s, $(( DEADLINE - NOW ))s left)"
  sleep "$INTERVAL"
done
