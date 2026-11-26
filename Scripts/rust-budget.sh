#!/bin/bash
# rust-budget.sh — 量四项并对照 PLAN-TABLES.md T2 的门；任一项越门 exit 1。
# 用法：Scripts/rust-budget.sh [--cold]   --cold 时含冷构建计时（删 target 后全量构建）。
# 四项：①冷构建时间（≤360s，仅 --cold）②cargo check -p dt-iop-color（≤40s）
#   ③UI release 二进制体积（≤80MB；A2 无此二进制，记 N/A 通过）
#   ④target/ 体积（≤20GB，超则触发清理）。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COLD=0
case "${1:-}" in
  "") ;;
  --cold) COLD=1 ;;
  -h|--help) echo "usage: Scripts/rust-budget.sh [--cold]"; exit 0 ;;
  *) echo "rust-budget: ERROR: unknown arg: $1" >&2; echo "usage: Scripts/rust-budget.sh [--cold]" >&2; exit 2 ;;
esac

FAIL=0
gate() { # gate <name> <value> <limit> <unit>
  if [ "$2" -le "$3" ]; then
    echo "rust-budget: $1 = $2$4 (gate <=$3$4) PASS"
  else
    echo "rust-budget: $1 = $2$4 (gate <=$3$4) FAIL"
    FAIL=1
  fi
}

# ① 冷构建时间（date +%s 起止戳；删后验 target/ 确已消失，否则判 FAIL，不量假数。
# 2026-11-26 注：曾疑计时器读出 0–1s 异常值；后经 cargo 内置计时（Finished 0.25s）
# + 19 Compiling 行 + 删除验证三方互证，证实计时诚实——暖机真值约 0.25s，
# 全程观测 0.25s–15s（机器负载波动），门 360s 余量巨大。）
if [ "$COLD" -eq 1 ]; then
  rm -rf "$ROOT/target"
  if [ -e "$ROOT/target" ]; then
    echo "rust-budget: cold-build = TARGET-NOT-REMOVED FAIL"
    FAIL=1
  else
    T0=$(date +%s)
    if (cd "$ROOT" && cargo build --workspace --locked -j6); then
      gate "cold-build" "$(( $(date +%s) - T0 ))" 360 s
    else
      echo "rust-budget: cold-build = BUILD-FAILED FAIL"
      FAIL=1
    fi
  fi
else
  echo "rust-budget: cold-build = SKIP (pass --cold to measure)"
fi

# ② 增量检查
T0=$(date +%s)
if (cd "$ROOT" && cargo check -p dt-iop-color --locked -j6); then
  gate "check dt-iop-color" "$(( $(date +%s) - T0 ))" 40 s
else
  echo "rust-budget: check dt-iop-color = CHECK-FAILED FAIL"
  FAIL=1
fi

# ③ UI release 二进制
UI_BIN="$ROOT/target/release/dt-gpui"
if [ -f "$UI_BIN" ]; then
  BYTES=$(stat -f%z "$UI_BIN")
  gate "release dt-gpui" "$BYTES" 83886080 B
else
  echo "rust-budget: release dt-gpui = N/A (no UI binary at A2) PASS"
fi

# ④ target/ 体积
if [ -d "$ROOT/target" ]; then
  KB=$(du -sk "$ROOT/target" | awk '{print $1}')
else
  KB=0
fi
MB=$(( KB / 1024 ))
echo "rust-budget: target/ = ${MB}MB (${KB}KB, gate <=20GB)"
if [ "$KB" -gt 20971520 ]; then
  echo "rust-budget: target/ exceeds 20GB: run cleanup FAIL"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then echo "rust-budget: overall PASS"; else echo "rust-budget: overall FAIL"; fi
exit "$FAIL"
