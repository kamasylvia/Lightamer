#!/bin/bash
# machine-guard.sh — 重活（xcodebuild / test-direct 全套 / GUI 走查）起跑前的机器级守门。
# 根因背景（2026-10-20 LESSONS L0xx-e）：三次 watchdog 重启 = 16GB 机器上并行重活致内存/交换饥饿，
#   系统守护（configd 等）被饿到 60s 无响应 → 用户态 watchdog 杀 GUI 会话 / 内核 watchdog 重启。
# 用法：Scripts/machine-guard.sh [--wait <秒>]   通过=exit 0；不满足=exit 1（--wait 则轮询等到满足或超时 exit 2）
# 判据（全部满足才放行）：
#   G1 无其它 xcodebuild / test-direct 宿主 / Lightamer 测试宿主在跑（机器级单重活）
#   G2 系统可用内存 ≥ 30%（memory_pressure 口径）
#   G3 交换已用 < 1GB
#   G4 Data 卷可用 ≥ 25GB
set -u
WAIT=0; [ "${1:-}" = "--wait" ] && WAIT="${2:-1800}"
check() {
  local fails=()
  local heavy; heavy=$(ps -axo pid=,command= | grep -E "xcodebuild|test-direct\.sh|xctest|Lightamer\.app/Contents/MacOS/Lightamer" | grep -v -E "grep|machine-guard" | wc -l | tr -d ' ')
  [ "$heavy" -gt 0 ] && fails+=("G1 并发重活进程=$heavy")
  local freepct; freepct=$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage/{gsub("%","",$NF); print $NF}')
  [ -n "$freepct" ] && [ "$freepct" -lt 30 ] && fails+=("G2 可用内存=${freepct}%<30%")
  local swapmb; swapmb=$(sysctl -n vm.swapusage 2>/dev/null | sed -E 's/.*used = ([0-9.]+)M.*/\1/')
  [ -n "$swapmb" ] && [ "${swapmb%.*}" -ge 1024 ] && fails+=("G3 交换已用=${swapmb}M≥1GB")
  local availgb; availgb=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
  [ -n "$availgb" ] && [ "$availgb" -lt 25 ] && fails+=("G4 Data 卷可用=${availgb}GB<25GB")
  if [ ${#fails[@]} -eq 0 ]; then echo "GUARD PASS (heavy=0 free=${freepct:-?}% swap=${swapmb:-?}M disk=${availgb:-?}GB)"; return 0; fi
  echo "GUARD BLOCK: ${fails[*]}"; return 1
}
if [ "$WAIT" -eq 0 ]; then check; exit $?; fi
deadline=$(( $(date +%s) + WAIT ))
while ! check; do
  [ "$(date +%s)" -ge "$deadline" ] && { echo "GUARD TIMEOUT after ${WAIT}s"; exit 2; }
  sleep 30
done
exit 0
