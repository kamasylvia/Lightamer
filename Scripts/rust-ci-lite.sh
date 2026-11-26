#!/bin/bash
# rust-ci-lite.sh — 守卫（不等待）→许可证→分层→不崩溃 lint→文档→构建→测试→预算，一条命令串起来。
# 用法：Scripts/rust-ci-lite.sh   任一步失败即停（set -e）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
  "") ;;
  -h|--help) echo "usage: Scripts/rust-ci-lite.sh"; exit 0 ;;
  *) echo "rust-ci-lite: ERROR: unknown arg: $1" >&2; echo "usage: Scripts/rust-ci-lite.sh" >&2; exit 2 ;;
esac

"$SCRIPT_DIR/rust-guard.sh"
"$SCRIPT_DIR/check-licenses.sh"
(cd "$SCRIPT_DIR/.." && cargo xtask layers)
(cd "$SCRIPT_DIR/.." && cargo clippy --workspace --all-targets --locked -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented)
(cd "$SCRIPT_DIR/.." && RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked)
(cd "$SCRIPT_DIR/.." && cargo xtask check-apple-boundary)
"$SCRIPT_DIR/rust-build.sh"
"$SCRIPT_DIR/rust-test.sh"
"$SCRIPT_DIR/rust-budget.sh"
echo "rust-ci-lite: ALL GREEN"
