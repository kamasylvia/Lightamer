#!/bin/bash
# rust-budget.sh — 量六项并对照门；任一项越门 exit 1。
# 用法：Scripts/rust-budget.sh [--cold]   --cold 时删 target 后全量量。
# 六项：①核心冷构建（≤360s，仅 --cold，排除 lightamer-gpui）
#   ②界面冷构建（≤900s，仅 --cold；在核心冷构建之后量，共享依赖已暖，诚实标注）
#   ③界面重新构建（≤180s：touch 一个 lightamer-gpui 源文件后的增量构建）
#   ④界面发行版二进制体积（≤80MB；--cold 时现编现量，平时有就量、无则 N/A）
#   ⑤cargo check -p lightamer-iop-color（≤40s）
#   ⑥target/ 体积（≤20GB，超则触发清理）。
# A7b 修订：gpui 进来后全工作区冷构建必超 360s，而这条门保的是核心各波的
# 迭代速度，故核心与界面分门（核心门与命令不变，只排除 lightamer-gpui）。
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

# ① 核心冷构建（date +%s 起止戳；删后验 target/ 确已消失，否则判 FAIL。
# A2 注：计时器经 cargo 内置计时 + Compiling 行 + 删除验证三方互证诚实。）
if [ "$COLD" -eq 1 ]; then
  rm -rf "$ROOT/target"
  if [ -e "$ROOT/target" ]; then
    echo "rust-budget: core cold-build = TARGET-NOT-REMOVED FAIL"
    FAIL=1
  else
    T0=$(date +%s)
    if (cd "$ROOT" && cargo build --workspace --exclude lightamer-gpui --locked -j6); then
      gate "core cold-build (workspace minus lightamer-gpui)" "$(( $(date +%s) - T0 ))" 360 s
    else
      echo "rust-budget: core cold-build = BUILD-FAILED FAIL"
      FAIL=1
    fi
  fi
else
  echo "rust-budget: core cold-build = SKIP (pass --cold to measure)"
fi

# ② 界面冷构建（仅 --cold；紧随核心冷构建，界面独有依赖是冷的，与核心
# 共享的已暖——行名如实标注，不冒充全冷）。
if [ "$COLD" -eq 1 ]; then
  T0=$(date +%s)
  if (cd "$ROOT" && cargo build -p lightamer-gpui --locked -j6); then
    gate "ui cold-build (shared deps warm)" "$(( $(date +%s) - T0 ))" 900 s
  else
    echo "rust-budget: ui cold-build = BUILD-FAILED FAIL"
    FAIL=1
  fi
else
  echo "rust-budget: ui cold-build = SKIP (pass --cold to measure)"
fi

# ③ 界面重新构建（touch 一个源文件后的增量时间；spike 实测 37–102s）。
touch "$ROOT/crates/lightamer-gpui/src/lib.rs"
T0=$(date +%s)
if (cd "$ROOT" && cargo build -p lightamer-gpui --locked -j6); then
  gate "ui rebuild (one file touched)" "$(( $(date +%s) - T0 ))" 180 s
else
  echo "rust-budget: ui rebuild = BUILD-FAILED FAIL"
  FAIL=1
fi

# ④ 界面发行版二进制体积（--cold 现编现量；平时只量现成的）。
UI_BIN="$ROOT/target/release/lightamer-gpui"
if [ "$COLD" -eq 1 ]; then
  if (cd "$ROOT" && cargo build -p lightamer-gpui --release --locked -j6); then
    BYTES=$(stat -f%z "$UI_BIN")
    gate "release lightamer-gpui bytes" "$BYTES" 83886080 B
  else
    echo "rust-budget: release lightamer-gpui = BUILD-FAILED FAIL"
    FAIL=1
  fi
elif [ -f "$UI_BIN" ]; then
  BYTES=$(stat -f%z "$UI_BIN")
  gate "release lightamer-gpui bytes" "$BYTES" 83886080 B
else
  echo "rust-budget: release lightamer-gpui = N/A (no release binary; pass --cold to build) PASS"
fi

# ⑤ 增量检查
T0=$(date +%s)
if (cd "$ROOT" && cargo check -p lightamer-iop-color --locked -j6); then
  gate "check lightamer-iop-color" "$(( $(date +%s) - T0 ))" 40 s
else
  echo "rust-budget: check lightamer-iop-color = CHECK-FAILED FAIL"
  FAIL=1
fi

# ⑥ target/ 体积
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
