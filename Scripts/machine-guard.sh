#!/bin/bash
# machine-guard.sh — 重活（xcodebuild / test-direct 全套 / GUI 走查）起跑前的机器级守门。
# 根因背景（2026-10-20 LESSONS L0xx-e）：三次 watchdog 重启 = 16GB 机器上并行重活致内存/交换饥饿，
#   系统守护（configd 等）被饿到 60s 无响应 → 用户态 watchdog 杀 GUI 会话 / 内核 watchdog 重启。
# 用法：Scripts/machine-guard.sh [--wait <秒>]   通过=exit 0；不满足=exit 1（--wait 则轮询等到满足或超时 exit 2）
#       Scripts/machine-guard.sh --monitor <秒>  运行时看门狗（v1.4）：随重活伴跑，采样 Lightamer
#       进程 RSS，任一实例 > 9GB（测试宿主级）即 kill 并登记——宁可单测失败不可整机重启。
#       用法：nohup Scripts/machine-guard.sh --monitor 21600 & （随全套/验收轮起停）
# 判据（全部满足才放行）：
#   G1 无其它 xcodebuild / test-direct 宿主 / Lightamer 测试宿主在跑（机器级单重活）
#   G2 系统可用内存 ≥ 30%（memory_pressure 口径）
#   G3 = 已撤（v1.3 2026-10-22：静态 swapused 阈值三次校准〔1→4→7G〕仍被地板棘轮〔2.1→6.6→7.5G〕
#      结构性击穿——本机常驻用户进程惰性冷页随使用只增不减，健康态与病态在此指标上不可分。
#      病理判据全权移交：G2〔可用内存≥30%〕+ G4〔Data 卷≥25GB〕+ MEMFAIL 机检 + G1 单重活）
#   G4 Data 卷可用 ≥ 25GB
set -u
WAIT=0; [ "${1:-}" = "--wait" ] && WAIT="${2:-1800}"
check() {
  local fails=()
  local heavy; heavy=$(ps -axo pid=,command= | grep -E "xcodebuild|test-direct\.sh|xctest|Lightamer\.app/Contents/MacOS/Lightamer" | grep -v -E "grep|machine-guard" | wc -l | tr -d ' ')
  [ "$heavy" -gt 0 ] && fails+=("G1 并发重活进程=$heavy")
  local freepct; freepct=$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage/{gsub("%","",$NF); print $NF}')
  [ -n "$freepct" ] && [ "$freepct" -lt 30 ] && fails+=("G2 可用内存=${freepct}%<30%")
  # G3 已撤（v1.3）——静态 swapused 非压力指标（见头注）
  local availmb; availmb=$(df -m /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
  [ -n "$availmb" ] && [ "${availmb}" -lt 25600 ] && fails+=("G4 Data 卷可用=${availmb}MB<25GB")
  if [ ${#fails[@]} -eq 0 ]; then echo "GUARD PASS (heavy=0 free=${freepct:-?}% swap=${swapmb:-?}M disk=${availgb:-?}GB)"; return 0; fi
  echo "GUARD BLOCK: ${fails[*]}"; return 1
}
monitor_loop() {
  local deadline=$(( $(date +%s) + WAIT ))
  echo "RSS-MONITOR start ceiling=9GB ($(date '+%H:%M:%S'))"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    ps -axo pid=,rss=,command= | grep -E "Lightamer\\.app/Contents/MacOS/Lightamer|xctest" | grep -v grep | awk -F'[ ]+' '{print $1":"$2}' | while IFS=: read -r pid kb; do
      mb=$(( kb / 1024 ))
      if [ "$mb" -ge 9216 ]; then
        echo "RSS-KILL: pid=$pid ${mb}MB >=9GB ($(date '+%H:%M:%S'))"
        kill -9 "$pid" 2>/dev/null
      fi
    done
    sleep 60
  done
  echo "RSS-MONITOR exit ($(( WAIT / 60 ))min)"
}

case "${1:-}" in
  --monitor) WAIT="${2:-21600}"; monitor_loop; exit 0 ;;
esac

if [ "$WAIT" -eq 0 ]; then check; exit $?; fi
deadline=$(( $(date +%s) + WAIT ))
while ! check; do
  [ "$(date +%s)" -ge "$deadline" ] && { echo "GUARD TIMEOUT after ${WAIT}s"; exit 2; }
  sleep 30
done
exit 0
