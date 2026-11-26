#!/bin/bash
# rust-apple-boundary.sh — Apple 边界链接门（A6 §6，A7b 加第 7 步）。
#
# 按序跑七步，任一步失败即退出非零：
#   1. cargo xtask check-apple-boundary（四条规则）
#   2. linux 目标的 dt-apple 依赖树只有它自己一行（无需安装该目标）
#   3. macOS 目标的 dt-apple 依赖树里有 objc2 族
#   4. --no-default-features 的 dt-cli：无框架链接、无 Apple 未定义符号
#   5. 该二进制 capabilities 打印空后端
#   6. 默认 feature 重建，capabilities 打印 macOS 真值
#   7. 非 macOS 真编译（A7b；目标装了就查 dt-apple，没装就打印跳过）
#
# 用法：Scripts/rust-apple-boundary.sh
# 不安装任何编译目标。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT/target/debug/dt-cli"

case "${1:-}" in
  "") ;;
  -h|--help) echo "usage: Scripts/rust-apple-boundary.sh"; exit 0 ;;
  *) echo "rust-apple-boundary: ERROR: unknown arg: $1" >&2; echo "usage: Scripts/rust-apple-boundary.sh" >&2; exit 2 ;;
esac

"$SCRIPT_DIR/machine-guard.sh"

fail() { echo "rust-apple-boundary: FAIL: $1" >&2; exit 1; }

echo "rust-apple-boundary: STEP 1/7 cargo xtask check-apple-boundary"
(cd "$ROOT" && cargo xtask check-apple-boundary) || fail "xtask check-apple-boundary"

echo "rust-apple-boundary: STEP 2/7 dt-apple tree on x86_64-unknown-linux-gnu"
LINUX_TREE=$(cd "$ROOT" && cargo tree --locked -e normal --target x86_64-unknown-linux-gnu -p dt-apple --prefix none) || fail "cargo tree (linux)"
echo "$LINUX_TREE"
LINUX_LINES=$(printf '%s\n' "$LINUX_TREE" | wc -l | tr -d ' ')
[ "$LINUX_LINES" = "1" ] || fail "linux tree wants 1 line, got $LINUX_LINES"
case "$LINUX_TREE" in
  "dt-apple v"*) ;;
  *) fail "linux tree line is not dt-apple: $LINUX_TREE" ;;
esac
echo "rust-apple-boundary: STEP 2/7 PASS (1 line, dt-apple only)"

echo "rust-apple-boundary: STEP 3/7 dt-apple tree on aarch64-apple-darwin"
MAC_TREE=$(cd "$ROOT" && cargo tree --locked -e normal --target aarch64-apple-darwin -p dt-apple --prefix none) || fail "cargo tree (mac)"
printf '%s\n' "$MAC_TREE"
printf '%s\n' "$MAC_TREE" | grep -q "objc2 v" || fail "mac tree lacks objc2"
printf '%s\n' "$MAC_TREE" | grep -q "objc2-metal v" || fail "mac tree lacks objc2-metal"
printf '%s\n' "$MAC_TREE" | grep -q "objc2-vision v" || fail "mac tree lacks objc2-vision"
printf '%s\n' "$MAC_TREE" | grep -q "objc2-core-image v" || fail "mac tree lacks objc2-core-image"
echo "rust-apple-boundary: STEP 3/7 PASS (objc2 family present)"

echo "rust-apple-boundary: STEP 4/7 no-default-features link check"
(cd "$ROOT" && cargo build -p dt-cli --no-default-features --locked -j6) || fail "no-default build"
echo "rust-apple-boundary: otool -L:"
otool -L "$BIN"
FW_COUNT=$(otool -L "$BIN" | grep -c "/System/Library/Frameworks/" || true)
[ "$FW_COUNT" = "0" ] || fail "framework links: $FW_COUNT"
SYM_COUNT=$(nm -u "$BIN" | grep -cE 'OBJC\$|_objc_|CIRAW|CGColor|_VN[A-Z]' || true)
[ "$SYM_COUNT" = "0" ] || fail "apple undefined symbols: $SYM_COUNT"
LEGACY_COUNT=$(nm -u "$BIN" | grep -ciE 'objc|CoreImage|ColorSync|Vision' || true)
echo "rust-apple-boundary: framework lines = $FW_COUNT, apple symbols = $SYM_COUNT (gate 0/0) PASS"
echo "rust-apple-boundary: legacy-pattern count (reference only) = $LEGACY_COUNT"

echo "rust-apple-boundary: STEP 5/7 no-default capabilities prints empty backend"
NO_DEFAULT_OUT=$("$BIN" capabilities) || fail "no-default capabilities run"
printf '%s\n' "$NO_DEFAULT_OUT"
printf '%s\n' "$NO_DEFAULT_OUT" | grep -q "^backend=empty$" || fail "want backend=empty"
echo "rust-apple-boundary: STEP 5/7 PASS"

echo "rust-apple-boundary: STEP 6/7 rebuild default, capabilities prints macOS values"
(cd "$ROOT" && cargo build -p dt-cli --locked -j6) || fail "default rebuild"
DEFAULT_OUT=$("$BIN" capabilities) || fail "default capabilities run"
printf '%s\n' "$DEFAULT_OUT"
printf '%s\n' "$DEFAULT_OUT" | grep -q "^backend=macos$" || fail "want backend=macos"
echo "rust-apple-boundary: STEP 6/7 PASS"

echo "rust-apple-boundary: STEP 7/7 real non-macOS compile of dt-apple"
if rustup target list --installed 2>/dev/null | grep -q "^x86_64-unknown-linux-gnu$"; then
  (cd "$ROOT" && cargo check -p dt-apple --target x86_64-unknown-linux-gnu --locked -j6) || fail "linux-target check"
  echo "rust-apple-boundary: STEP 7/7 PASS (dt-apple checks on x86_64-unknown-linux-gnu)"
else
  echo "rust-apple-boundary: STEP 7/7 SKIP (target not installed; would run: cargo check -p dt-apple --target x86_64-unknown-linux-gnu --locked)"
fi

echo "rust-apple-boundary: ALL GREEN"
