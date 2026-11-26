#!/bin/bash
# oracle.sh — darktable 官方对照工具的薄入口（A5）。
# 一切逻辑在 apps/lightamer-cli（Rust）；本脚本只 cd 到仓库根并转发。
# 用法：Scripts/oracle.sh {fetch|render|cmp|emit-xmp|selftest} [args...]
#   自检要联网取包 + 8 次全分辨率渲染，不进 Scripts/rust-ci-lite.sh。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "${1:-}" in
  ""|-h|--help|help)
    echo "usage: Scripts/oracle.sh {fetch|render|cmp|emit-xmp|selftest} [args...]"
    echo "  selftest runs 8 full-res renders; keep one heavy job at a time (see AGENTS.md)."
    exit 0
    ;;
esac

command -v cargo >/dev/null 2>&1 || { echo "oracle.sh: ERROR: cargo not found in PATH" >&2; exit 2; }

cd "$ROOT" || exit 2
exec cargo run --locked -p lightamer-cli -- "$@"
