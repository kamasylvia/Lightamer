#!/bin/zsh
# test-direct.sh — 运行 Lightamer 单测，绕开 xcodebuild/testmanagerd。
#
# 背景（LESSONS L019a/L019b）：`xcodebuild test` 每轮重建触发 XCTest automation
# enrollment 密码弹窗（持久化键 = runner cdhash，重建即变）。直启宿主二进制 +
# DYLD 注入 + 旧式 XCTestConfigurationFilePath 完全绕开 testmanagerd——零弹窗。
# 2026-09-22 全套等价性验证：480/3skip/0fail 与 xcodebuild 逐值一致。
#
# M2-4-0 起（2026-09-30）：单 LightamerTests 拆为六个域 bundle（Project.swift
# 显式清单，归属正本 = .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt）。
# 六 bundle 共享同一宿主二进制（D2），串行各起独立进程——进程退出即 Metal/CI/actor
# 状态清零，任一单宿主峰值 RSS <3G 硬门由本脚本机检（MEMFAIL）。
#
# 用法：
#   Scripts/test-direct.sh                            # 全套 = --all（六 bundle 串行）
#   Scripts/test-direct.sh --all                      # 同上
#   Scripts/test-direct.sh --bundle IOP               # 单 bundle 全量
#   Scripts/test-direct.sh --bundle Library 'StableHashTests'   # 单 bundle + 类过滤
#   Scripts/test-direct.sh 'StableHashTests'          # 旧式类过滤（向后兼容）：扫描
#                                                     # 全部六 bundle 执行过滤后合计——
#                                                     # 类只活在一个 bundle，其余 bundle
#                                                     # executed=0 属正常（头注释备案，T2）
#
# 输出：每 bundle 一行 BUNDLE|<name>|<executed>/<skipped>/<failed>|peakRSS=<MB>|<seconds>|sampling=<time|ps-poll>
#       （MEMFAIL 时行尾追加 " MEMFAIL"）末行 TOTAL|<sum>/<sum>/<sum>|<total seconds>
# 退出码：任一 bundle fail>0 / executed=0（无过滤时，L028 防空转）/ 峰值 RSS≥3072MB
#         （MEMFAIL）→ 非零。判据 = 测试结果行，NOT 宿主退出态（退出态污染，11-04）。
#
# RSS 采样（M2-4-0 D4/M1）：主判据 = /usr/bin/time -l 包宿主进程，解析 ru_maxrss
# （macOS 单位 bytes，÷1048576 得 MB）——内核记账精确峰值，无采样间隙；ps 1s 轮询
# 仅作 time 不可用时的后备（sampling=ps-poll 标注）。
#
# bundle 选择（M2-4-0 实测修正 L019b 配方）：XCTestBundlePath=<.xctest> 是唯一被尊重
# 的选 bundle 旋钮——XCTestConfigurationFilePath 配置 plist 的 TestBundlePath 在本栈
# （Xcode 26 直启）被无视，宿主实际行为 = 扫 PlugIns 取首个 .xctest（旧单 bundle 时代
# 两种机制巧合等价，多 bundle 拆分才暴露）。
#
# 前提：Debug 产物已由 `xcodebuild build-for-testing` 生成（build 不触发弹窗）。
set -euo pipefail

ROOT="${0:A:h:h}"

# ── bundle 注册表（D4 顺序 = IOP→IOPParity→Layers→Library→Sessions→Export→App）──
# IOPParity = 2026-09-30 D5 预案实拆：IOP 单宿主精确峰值 6.97-8.14G（ru_maxrss，
# /usr/bin/time -l）两轮复现 ≥3G 硬门 → 按 D5 预声明线拆 LightamerTestsIOPParity
# （*Parity*|Golden*|ToneEqual*|Lut3d*，35 文件/242 tests）。夜间授权 + 派发指令
# 授权，晨审可推翻（SUMMARY 登记）。
typeset -a BUNDLES=(IOP IOPParity Layers Library Sessions Export App)
typeset -A TARGET_NAME   # bundle 名 → .xctest target 名（= productModuleName）
for b in "${BUNDLES[@]}"; do TARGET_NAME[$b]="LightamerTests$b"; done

RSS_LIMIT_MB=3072  # M2-4-0 硬门：任一 bundle 单宿主峰值 <3G

# ── 参数解析 ─────────────────────────────────────────────────────────
MODE=all; SELECTED=""; CLASS_FILTER=""
args=("$@")
i=1
while (( i <= ${#args[@]} )); do
  case "${args[$i]}" in
    --all) MODE=all ;;
    --bundle)
      (( i+1 <= ${#args[@]} )) || { echo "error: --bundle needs a name (${(j:/:)BUNDLES})" >&2; exit 2; }
      MODE=bundle; SELECTED="${args[$((i+1))]}"; (( i+=1 )) ;;
    *)
      if [ -n "$CLASS_FILTER" ]; then
        echo "error: multiple filter args ('${args[$i]}')" >&2; exit 2
      fi
      CLASS_FILTER="${args[$i]}"
      ;;
  esac
  (( i+=1 ))
done

if [ "$MODE" = "bundle" ]; then
  if (( ! ${BUNDLES[(Ie)$SELECTED]} )); then
    echo "error: unknown bundle '$SELECTED' — valid: ${(j:/:)BUNDLES}" >&2; exit 2
  fi
fi

# ── DerivedData 定位（按 xctest 可执行 mtime 取最新容器，L041 双重防呆保留）──
# 六 bundle 同批构建 mtime 同源；任取其一即可定位容器。
DD_DEFAULT=(~/Library/Developer/Xcode/DerivedData/Lightamer-*/Build/Products/Debug/Lightamer.app/Contents/PlugIns/LightamerTests(IOP|Layers|Library|Sessions|Export|App).xctest/Contents/MacOS/*(N))
DD=( ${~DD_DEFAULT} )
if [ ${#DD[@]} -eq 0 ]; then
  echo "error: LightamerTests*.xctest products missing — the last build pruned test products." >&2
  echo "run: caffeinate -dis xcodebuild build-for-testing -workspace Lightamer.xcworkspace -scheme Lightamer -destination 'platform=macOS'" >&2
  exit 2
fi
DD="$(ls -t ${DD[@]} | head -1)"
DD="${DD%Lightamer.app/*}"
HOST_BIN="$DD/Lightamer.app/Contents/MacOS/Lightamer"
if [ ! -f "$HOST_BIN" ]; then
  echo "error: host binary missing at $HOST_BIN" >&2
  exit 2
fi
PLUGINS="$DD/Lightamer.app/Contents/PlugIns"

XCODE_DEV="$(xcode-select -p)"
HAVE_TIME=0
[[ -x /usr/bin/time ]] && HAVE_TIME=1

# ── 单 bundle 执行 + 记账 ────────────────────────────────────────────
# 入参：$1=bundle 名  $2=类过滤（可空）。输出：BUNDLE 行到 stdout，
# 详细日志 /tmp/la-direct-tests-<bundle>.log。全局累加 TOTAL_E/S/F/SECS，
# ANY_FAIL 置位即总失败。
TOTAL_E=0; TOTAL_S=0; TOTAL_F=0; TOTAL_SECS=0
ANY_FAIL=0

run_bundle() {
  local bundle="$1" filter="${2:-}"
  local target="${TARGET_NAME[$bundle]}"
  local xctest="$PLUGINS/${target}.xctest"
  local log="/tmp/la-direct-tests-${bundle}.log"
  if [ ! -d "$xctest" ]; then
    print -r -- "BUNDLE|$bundle|0/0/0|peakRSS=N/A|0s|sampling=none MISSING-PRODUCT $xctest"
    ANY_FAIL=1; return
  fi

  local xargs=()
  [ -n "$filter" ] && xargs=(-XCTest "$filter")

  # 判据 = 测试结果行（Executed 计数 + 失败行），NOT 宿主进程退出态——
  # 宿主 shell 的退出路径在全绿轮也可能非零（退出态污染，11-04 验收移交）。
  local rc=0 t0 t1
  t0=$SECONDS
  if (( HAVE_TIME )); then
    /usr/bin/time -l env \
      DYLD_INSERT_LIBRARIES="$DD/Lightamer.app/Contents/Frameworks/libXCTestBundleInject.dylib" \
      DYLD_LIBRARY_PATH="$DD:$XCODE_DEV/Platforms/MacOSX.platform/Developer/usr/lib" \
      DYLD_FRAMEWORK_PATH="$DD:$XCODE_DEV/Contents/SharedFrameworks:$XCODE_DEV/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
      XCTestBundlePath="$xctest" \
      "$HOST_BIN" "${xargs[@]}" > "$log" 2>&1 || rc=$?
  else
    # 后备：ps -o rss= 1s 轮询取 max（macOS ps rss 单位 KB）。
    env \
      DYLD_INSERT_LIBRARIES="$DD/Lightamer.app/Contents/Frameworks/libXCTestBundleInject.dylib" \
      DYLD_LIBRARY_PATH="$DD:$XCODE_DEV/Platforms/MacOSX.platform/Developer/usr/lib" \
      DYLD_FRAMEWORK_PATH="$DD:$XCODE_DEV/Contents/SharedFrameworks:$XCODE_DEV/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
      XCTestBundlePath="$xctest" \
      "$HOST_BIN" "${xargs[@]}" > "$log" 2>&1 &
    local pid=$! peak_kb=0 cur
    while kill -0 "$pid" 2>/dev/null; do
      cur=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
      [ -n "$cur" ] && (( cur > peak_kb )) && peak_kb=$cur
      sleep 1
    done
    wait "$pid" || rc=$?
    print -r -- "sampling=ps-poll peakKB=$peak_kb" >> "$log"
  fi
  # $(( )) 赋值形态：(( expr )) 形态在结果为 0 时状态码 1，set -e 会杀脚本（实测踩坑）
  t1=$(( SECONDS - t0 ))

  # 记账解析（L028 双读：Executed 计数 + 失败行 + summary failures）
  local executed skipped failed summary_fail peak
  executed=$(grep -aoE "Executed [0-9]+ tests" "$log" | tail -1 | grep -aoE "[0-9]+" || echo 0)
  skipped=$(grep -acE "' skipped" "$log" || true)
  failed=$(grep -acE "' failed \(|' failed \." "$log" || true)
  summary_fail=$(grep -aE "^Executed [0-9]+ tests" "$log" | tail -1 | grep -aoE "with [0-9]+ failures?" | grep -aoE "[0-9]+" || echo 0)
  (( summary_fail > failed )) && failed=$summary_fail

  # 峰值 RSS：主判据 time 的 ru_maxrss（bytes → MB）；后备 ps 轮询（KB → MB）。
  local sampling=time
  peak=$(grep -a "maximum resident set size" "$log" | tail -1 | awk '{print $1}')
  if [ -z "$peak" ]; then
    sampling=ps-poll
    local kb
    kb=$(grep -a "sampling=ps-poll peakKB=" "$log" | tail -1 | grep -aoE "[0-9]+" || echo 0)
    peak=$(( kb * 1024 ))
  fi
  local peak_mb=$(( peak / 1048576 ))

  # 失败判定：fail>0 / executed=0（无过滤时，L028）/ RSS≥硬门（MEMFAIL，硬门机检）
  local verdict=ok
  if (( failed > 0 )); then verdict=fail; fi
  if [ -z "$filter" ] && (( executed == 0 )); then
    verdict="executed-0（过滤名不匹配/旧容器/缺席 project，防空转假绿；日志 $log）"
  fi
  if (( peak_mb >= RSS_LIMIT_MB )); then
    verdict=MEMFAIL
  fi

  local line="BUNDLE|$bundle|${executed}/${skipped}/${failed}|peakRSS=${peak_mb}MB|${t1}s|sampling=${sampling}"
  [[ "$verdict" == "MEMFAIL" ]] && line="$line MEMFAIL"
  print -r -- "$line"
  if [[ "$verdict" == "MEMFAIL" ]]; then
    print -r -- "  ↳ $bundle MEMFAIL — peakRSS=${peak_mb}MB >= ${RSS_LIMIT_MB}MB 硬门破线（IOP 破线 = plan D5 拆分预案触发点）；日志 $log" >&2
    ANY_FAIL=1
  elif [[ "$verdict" != "ok" ]]; then
    print -r -- "  ↳ $bundle FAILED（$verdict；host exit=$rc 仅参考）— 完整输出: $log" >&2
    grep -aB2 "' failed" "$log" | head -20 >&2 || true
    ANY_FAIL=1
  fi
  TOTAL_E=$(( TOTAL_E + executed )); TOTAL_S=$(( TOTAL_S + skipped )); TOTAL_F=$(( TOTAL_F + failed ))
  TOTAL_SECS=$(( TOTAL_SECS + t1 ))
}

# ── 执行 ─────────────────────────────────────────────────────────────
if [ "$MODE" = "bundle" ]; then
  run_bundle "$SELECTED" "$CLASS_FILTER"
elif [ -n "$CLASS_FILTER" ]; then
  # 旧式兼容：类过滤扫全部 bundle（类只活在一个 bundle，其余 executed=0 正常）；
  # L028 防空转按 TOTAL 合计判定（见尾部）。
  for b in "${BUNDLES[@]}"; do run_bundle "$b" "$CLASS_FILTER"; done
else
  for b in "${BUNDLES[@]}"; do
    run_bundle "$b" ""
    (( ANY_FAIL )) && break  # 前序 bundle 红即停，后续照跑只添噪音
  done
fi

print -r -- "TOTAL|${TOTAL_E}/${TOTAL_S}/${TOTAL_F}|${TOTAL_SECS}s"

# 总判定
if (( ANY_FAIL )); then exit 1; fi
if [ "$MODE" = "all" ] && [ -n "$CLASS_FILTER" ] && (( TOTAL_E == 0 )); then
  echo "FAILED — 旧式类过滤合计 Executed 0 tests（类名不匹配或产物缺席，防空转假绿）" >&2
  exit 1
fi
echo "OK (direct launch, no testmanagerd)"
