#!/bin/zsh
# test-direct.sh — 运行 Lightamer 单测，绕开 xcodebuild/testmanagerd。
#
# 背景（LESSONS L019a/L019b）：`xcodebuild test` 每轮重建触发 XCTest automation
# enrollment 密码弹窗（持久化键 = runner cdhash，重建即变）。直启宿主二进制 +
# DYLD 注入 + 旧式 XCTestConfigurationFilePath 完全绕开 testmanagerd——零弹窗。
# 2026-09-22 全套等价性验证：480/3skip/0fail 与 xcodebuild 逐值一致。
#
# M2-4-0 起（2026-09-30）：单 LightamerTests 拆为七个域 bundle（Project.swift
# 显式清单，归属正本 = .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt）。
# 七 bundle 共享同一宿主二进制（D2），串行各起独立进程——进程退出即 Metal/CI/actor
# 状态清零，任一单宿主峰值 RSS <8G 运行门由本脚本机检（MEMFAIL；门修订依据见下）。
#
# 用法：
#   Scripts/test-direct.sh                            # 全套 = --all（七 bundle 串行）
#   Scripts/test-direct.sh --all                      # 同上
#   Scripts/test-direct.sh --bundle IOP               # 单 bundle 全量
#   Scripts/test-direct.sh --bundle Library 'StableHashTests'   # 单 bundle + 类过滤
#   Scripts/test-direct.sh 'StableHashTests'          # 旧式类过滤（向后兼容）：扫描
#                                                     # 全部七 bundle 执行过滤后合计——
#                                                     # 类只活在一个 bundle，其余 bundle
#                                                     # executed=0 属正常（头注释备案，T2）
#   LA_SELFTEST=1 source Scripts/test-direct.sh       # 只取 parse_bundle_log 函数做
#                                                     # fixture 回放自证（不执行主体；
#                                                     # 消费方 = Scripts/test-direct-selftest.sh）
#
# 输出：每 bundle 一行 BUNDLE|<name>|<executed>/<skipped>/<failed>|peakRSS=<MB>|<seconds>|sampling=<time|ps-poll>
#       （MEMFAIL 时行尾追加 " MEMFAIL"；宿主 ANE 编译态劣化签名时行尾追加 " ANE-DEGRADED"
#       注记——只做每轮机检可观测，不判 FAIL，M2-11-01 KD-3：签名 = 行含 ANECCompile 且含
#       FAILED，对应 SidecarV5 ANE flake 五波台账的环境型归因，复绿窗口结束自动消失）
#       末行 TOTAL|<sum>/<sum>/<sum>|<total seconds>
# 退出码：任一 bundle verdict≠ok → 非零。verdict 集（M2-11-01 KD-2 起）：
#         ok / fail（failed>0）/ executed-0（无过滤时 executed==0，L028 防空转）/
#         MEMFAIL（峰值 RSS≥8192MB）/ crash（宿主异常退出签名：`terminated abnormally`
#         或 `Restarting after unexpected exit`，L055）/ no-total-line（末条 Executed 行
#         未挂靠 Test Suite 'All tests' 总计段——类 suite 截断形态即 L055 假绿签名；
#         过滤轮豁免：-XCTest 过滤轮末条 = 'Selected tests' 类 suite 属正常）。
#         crash / no-total-line 两 verdict 下计数不可信，BUNDLE 行报 0/0/0。
#         判据 = 测试结果行（经 parse_bundle_log），NOT 宿主退出态（退出态污染，11-04）。
#
# parse_bundle_log（M2-11-01 KD-1 抽取）：日志解析 + 判定独立成函数，stdout = 五字段一行
#         `<executed>/<skipped>/<failed>|peakRSS=<MB>MB|sampling=<time|ps-poll>|verdict=<v>[ ANE-DEGRADED]`，
#         stderr = ↳ 诊断行；恒返回 0（结果全在行内编码）。Executed 计数 regex 兼容单数
#         `tests?`（L028 家族：单测试轮 `Executed 1 test`，executed/summary_fail 两处外层同修）。
#         自证 = Scripts/test-direct-selftest.sh 对 Scripts/test-direct-fixtures/ 三 fixture
#         回放（crash→FAIL / singular→executed=1 / normal→ok 且逐字段）。
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

# ── 运行门（先于 parse_bundle_log 定义：LA_SELFTEST source 路径下 parse 亦需在册）──
# 门修订（2026-09-30，SPIKE 70e09e5 证伪原 <3G 门槛）：by-design GB 级重测单类自身
# 峰值即 TilingOverlapTests 7865 / HDRPipelineMatrixTests 5913 / QuickLookRendererTests
# 4589 MB（隔离单类 ru_maxrss，独立进程），叠加 ~1.4G 框架分页一次性地板
# （RawCamera/CI/CoreML/Metal __TEXT，与 bundle 划分无关）——<3G 数学不可达，真实
# 跨测残留仅 0.18-2.4MB/test（二阶）。8G 为运行门槛（夜间授权，晨审可推翻；证据正本
# = .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md）。±3% 运行方差注记：IOP
# 峰值 7865 贴线余量 ~4%，连续 MEMFAIL 时先查是否重测顺序漂移（方差注记见 SPIKE）。
RSS_LIMIT_MB=8192

# ── 记账解析 + 判定（KD-1 抽取；可被 LA_SELFTEST source 后喂数 fixture 回放）──
# 入参：$1=日志路径  $2=类过滤（可空）。stdout 五字段一行（格式见头注释），
# stderr = ↳ 诊断行（仅非 ok verdict），恒返回 0。
parse_bundle_log() {
  local log="$1" filter="${2:-}"
  local executed skipped failed summary_fail peak sampling verdict

  # 记账解析（L028 双读：Executed 计数 + 失败行 + summary failures；单数 `tests?` 兼容
  # 「Executed 1 test」单测试轮——executed 判据与 summary_fail 外层两处同修，M2-11-01 m1）
  executed=$(grep -aoE "Executed [0-9]+ tests?" "$log" 2>/dev/null | tail -1 | grep -aoE "[0-9]+" || echo 0)
  skipped=$(grep -acE "' skipped" "$log" 2>/dev/null || true)
  failed=$(grep -acE "' failed \(|' failed \." "$log" 2>/dev/null || true)
  summary_fail=$(grep -aE "^Executed [0-9]+ tests?" "$log" 2>/dev/null | tail -1 | grep -aoE "with [0-9]+ failures?" | grep -aoE "[0-9]+" || echo 0)
  (( summary_fail > failed )) && failed=$summary_fail

  # 崩溃签名（L055 修①）：宿主中途异常退出 / xctest 侧重启 —— 全部计数不可信
  local crashed=0
  if grep -aq "terminated abnormally\|Restarting after unexpected exit" "$log" 2>/dev/null; then
    crashed=1
  fi

  # 末条 Executed 行身份校验（L055 修②）：无过滤轮末条 Executed 必须挂靠
  # `Test Suite 'All tests'` 段（xctest 末尾总计行形态）——来自类 suite = 截断形态，
  # 恰是 L055 假绿签名。过滤轮豁免（-XCTest 轮末条 = 'Selected tests' 类 suite 正常）。
  local total_ok=1
  if [ -z "$filter" ]; then
    local last_exec_ln last_suite
    last_exec_ln=$(grep -anE "Executed [0-9]+ tests?" "$log" 2>/dev/null | tail -1 | cut -d: -f1 || true)
    if [ -n "$last_exec_ln" ]; then
      last_suite=$(head -n "$last_exec_ln" "$log" 2>/dev/null | grep -a "Test Suite '" | tail -1 || true)
      case "$last_suite" in
        *"Test Suite 'All tests'"*) total_ok=1 ;;
        *) total_ok=0 ;;
      esac
    else
      total_ok=0   # 一条 Executed 都没有 = 无总计行
    fi
  fi

  # ANE 编译态签名（KD-3）：行含 ANECCompile 且含 FAILED → 注记（不判 FAIL）
  local ane=0
  if grep -a "ANECCompile" "$log" 2>/dev/null | grep -aq "FAILED"; then
    ane=1
  fi

  # 峰值 RSS：主判据 time 的 ru_maxrss（bytes → MB）；后备 ps 轮询（KB → MB）。
  sampling=time
  peak=$(grep -a "maximum resident set size" "$log" 2>/dev/null | tail -1 | awk '{print $1}' || true)
  if [ -z "$peak" ]; then
    sampling=ps-poll
    local kb
    kb=$(grep -a "sampling=ps-poll peakKB=" "$log" 2>/dev/null | tail -1 | grep -aoE "[0-9]+" || echo 0)
    peak=$(( kb * 1024 ))
  fi
  local peak_mb=$(( peak / 1048576 ))

  # 判定（优先级降序）：crash > no-total-line > MEMFAIL > executed-0 > fail > ok。
  # crash/no-total-line 时计数置零（L055：末条类 suite 行不再被当 bundle 计数）。
  verdict=ok
  if (( crashed )); then
    verdict=crash
    executed=0; skipped=0; failed=0
    print -r -- "  ↳ 宿主异常退出签名（terminated abnormally / Restarting after unexpected exit）——bundle 计数不可信置零（L055）；日志 $log" >&2
  elif (( ! total_ok )); then
    verdict=no-total-line
    executed=0; skipped=0; failed=0
    print -r -- "  ↳ 末条 Executed 行未挂靠 Test Suite 'All tests'（类 suite 截断形态，L055 假绿签名）；日志 $log" >&2
  elif (( peak_mb >= RSS_LIMIT_MB )); then
    verdict=MEMFAIL
    print -r -- "  ↳ MEMFAIL — peakRSS=${peak_mb}MB >= ${RSS_LIMIT_MB}MB 门破线（8G 口径；贴线 bundle 连续破线先查重测顺序漂移，±3% 方差见 SPIKE 70e09e5）；日志 $log" >&2
  elif (( failed > 0 )); then
    verdict=fail
  elif [ -z "$filter" ] && (( executed == 0 )); then
    verdict="executed-0（过滤名不匹配/旧容器/缺席 project，防空转假绿；日志 $log）"
  fi

  local out="${executed}/${skipped}/${failed}|peakRSS=${peak_mb}MB|sampling=${sampling}|verdict=${verdict}"
  (( ane )) && out="$out ANE-DEGRADED"
  print -r -- "$out"
}

# ── LA_SELFTEST 守卫（KD-1）：设该 env 时只暴露上方函数后短路——source 消费取
# parse_bundle_log 做 fixture 回放；被执行消费走 `return` 失败 → `exit 0` 干净退出
# （双形态兜底，m7）。不设 env 的正常调用路径零变化。
if [[ "${LA_SELFTEST:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

# ── bundle 注册表（D4 顺序 = IOP→IOPParity→Layers→Library→Sessions→Export→App）──
# IOPParity = 2026-09-30 D5 预案实拆：IOP 单宿主精确峰值 6.97-8.14G（ru_maxrss，
# /usr/bin/time -l）两轮复现 ≥3G 硬门 → 按 D5 预声明线拆 LightamerTestsIOPParity
# （*Parity*|Golden*|ToneEqual*|Lut3d*，35 文件/242 tests）。夜间授权 + 派发指令
# 授权，晨审可推翻（SUMMARY 登记）。
typeset -a BUNDLES=(IOP IOPParity Layers Library Sessions Export App)
typeset -A TARGET_NAME   # bundle 名 → .xctest target 名（= productModuleName）
for b in "${BUNDLES[@]}"; do TARGET_NAME[$b]="LightamerTests$b"; done

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
# 七 bundle 同批构建 mtime 同源；任取其一即可定位容器。
DD_DEFAULT=(~/Library/Developer/Xcode/DerivedData/Lightamer-*/Build/Products/Debug/Lightamer.app/Contents/PlugIns/LightamerTests(IOP|IOPParity|Layers|Library|Sessions|Export|App).xctest/Contents/MacOS/*(N))
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
# 入参：$1=bundle 名  $2=类过滤（可空）。输出：BUNDLE 行到 stdout（组装面留本函数，
# 解析/判定面在 parse_bundle_log），详细日志 /tmp/la-direct-tests-<bundle>.log。
# 全局累加 TOTAL_E/S/F/SECS，ANY_FAIL 置位即总失败。
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

  # 判据 = 测试结果行（parse_bundle_log 五字段），NOT 宿主进程退出态——
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

  # 解析 + 判定（KD-1 抽取件）：五字段一行 → 拆字段组装 BUNDLE 行
  local parsed
  parsed=$(parse_bundle_log "$log" "$filter")
  local segs_peaks="${parsed%%|*}"        # E/S/F
  local segs_rest="${parsed#*|}"          # peakRSS=<MB>MB|sampling=<mode>|verdict=<v>[ ANE-DEGRADED]
  local executed="${segs_peaks%%/*}"
  local tmp="${segs_peaks#*/}"
  local skipped="${tmp%%/*}"
  local failed="${tmp##*/}"
  local peakseg="${segs_rest%%|*}"; segs_rest="${segs_rest#*|}"
  local samplingseg="${segs_rest%%|*}"; segs_rest="${segs_rest#*|}"
  local verdict="${segs_rest% ANE-DEGRADED}"   # 尾注记剥除（不在场则原样）
  verdict="${verdict#verdict=}"
  local peak_mb="${peakseg#peakRSS=}"
  peak_mb="${peak_mb%MB}"                       # parse 输出已携单位，剥回数字组装 BUNDLE 行
  local ane=0
  [[ "$parsed" == *" ANE-DEGRADED" ]] && ane=1

  local line="BUNDLE|$bundle|${executed}/${skipped}/${failed}|peakRSS=${peak_mb}MB|${t1}s|${samplingseg}"
  [[ "$verdict" == "MEMFAIL" ]] && line="$line MEMFAIL"
  (( ane )) && line="$line ANE-DEGRADED"
  print -r -- "$line"
  if [[ "$verdict" != "ok" ]]; then
    print -r -- "  ↳ $bundle FAILED（$verdict；host exit=$rc 仅参考）— 完整输出: $log" >&2
    [[ "$verdict" == "fail" ]] && { grep -aB2 "' failed" "$log" 2>/dev/null | head -20 >&2 || true }
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
