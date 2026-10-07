#!/bin/zsh
# test-direct-selftest.sh — test-direct.sh parse_bundle_log 的 fixture 回放自证
# （M2-11-01 KD-1 / D-M2-11-CONTEXT-4 自证纪律）。
#
# 零依赖、零宿主：只对 Scripts/test-direct-fixtures/ 三 fixture + 两构造段回放
# parse_bundle_log，断言五字段输出。不跑测试宿主、不碰 DerivedData。
#
# 用法：Scripts/test-direct-selftest.sh   （全绿输出 ok 行 + SELFTEST OK，退出码 0）
set -euo pipefail

ROOT="${0:A:h:h}"
FIXTURES="$ROOT/Scripts/test-direct-fixtures"
TMPD="${TMPDIR:-/tmp}"
ane_log="${TMPD%/}/test-direct-selftest-ane-$$.log"
trunc_log="${TMPD%/}/test-direct-selftest-trunc-$$.log"
trap 'rm -f "$ane_log" "$trunc_log"' EXIT

# KD-1 守卫消费：source 只暴露 parse_bundle_log，不执行 bundle 主体
export LA_SELFTEST=1
source "$ROOT/Scripts/test-direct.sh"

(( $+functions[parse_bundle_log] )) || { print -r -- "FAIL guard: parse_bundle_log not defined after source"; exit 1 }

typeset -i fails=0
check() {  # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    print -r -- "ok   $1"
  else
    print -r -- "FAIL $1: expected [$2] got [$3]"
    fails=$(( fails + 1 ))
  fi
}

# ① crash.log（L055 现场形态：末条 Executed = 类 suite 15 tests + terminated abnormally）
# → verdict=crash（FAIL），计数置零——末条类 suite 行不再被当 bundle 计数（AC1/AC2）
out=$(parse_bundle_log "$FIXTURES/crash.log" "")
check "crash counts zeroed (AC1)"  "0/0/0"        "${out%%|*}"
check "crash verdict (AC1)"        "crash"         "${out##*verdict=}"
check "crash no ANE note"          "${out% ANE-DEGRADED}" "$out"
diag=$(parse_bundle_log "$FIXTURES/crash.log" "" 2>&1 >/dev/null)
[[ -n "$diag" ]] && print -r -- "ok   crash stderr diagnostic present" || { print -r -- "FAIL crash stderr diagnostic missing"; fails=$(( fails + 1 )) }

# ② singular.log（L028 家族第 5 件：`Executed 1 test` 单数形态，All tests 总计在）
# → executed=1、verdict=ok——单数 regex 两处同修、L028 不误报（AC3）
out=$(parse_bundle_log "$FIXTURES/singular.log" "")
check "singular counts (AC3)"  "1/0/0"       "${out%%|*}"
check "singular verdict (AC3)" "ok"          "${out##*verdict=}"

# ③ normal.log（正向对照：All tests 总计行 + 1 skip）→ 五字段一行逐字节一致（AC4）
out=$(parse_bundle_log "$FIXTURES/normal.log" "")
check "normal full five-field line (AC4)"  "3/1/0|peakRSS=200MB|sampling=time|verdict=ok" "$out"

# ④ ANE 构造段：normal.log + ANECCompile() FAILED 行 → 注记 ANE-DEGRADED 且不 FAIL（AC5）
{ cat "$FIXTURES/normal.log"; printf "ANECompilerService: ANECCompile() FAILED for model /abc/CoreML (worker pid 123)\n"; } > "$ane_log"
out=$(parse_bundle_log "$ane_log" "")
check "ANE note + verdict ok (AC5)"  "3/1/0|peakRSS=200MB|sampling=time|verdict=ok ANE-DEGRADED" "$out"

# ⑤ 过滤轮豁免负证（KD-2 实现细节）：crash 签名剥除后的截断形态——
#    带过滤 → 不做 no-total-line 判定（类 suite 计数照报）；无过滤 → no-total-line FAIL
{ grep -v "terminated abnormally" "$FIXTURES/crash.log"; } > "$trunc_log"
out=$(parse_bundle_log "$trunc_log" "GradeCatalogTests")
check "filtered truncation exempt (KD-2)"  "15/0/0"      "${out%%|*}"
check "filtered truncation verdict"        "ok"          "${out##*verdict=}"
out=$(parse_bundle_log "$trunc_log" "")
check "unfiltered truncation FAILs (AC2)"  "0/0/0"              "${out%%|*}"
check "unfiltered truncation verdict"      "no-total-line"      "${out##*verdict=}"

if (( fails == 0 )); then
  print -r -- "SELFTEST OK (test-direct.sh parse_bundle_log — 3 fixtures + 2 constructed)"
else
  print -r -- "SELFTEST FAILED: ${fails} assertion(s)"
  exit 1
fi
