#!/bin/zsh
# test-direct.sh — 运行 LightamerTests 单测，绕开 xcodebuild/testmanagerd。
#
# 背景（LESSONS L019a/L019b）：`xcodebuild test` 每轮重建触发 XCTest automation
# enrollment 密码弹窗（持久化键 = runner cdhash，重建即变）。直启宿主二进制 +
# DYLD 注入 + 旧式 XCTestConfigurationFilePath 完全绕开 testmanagerd——零弹窗。
# 2026-09-22 全套等价性验证：480/3skip/0fail 与 xcodebuild 逐值一致。
#
# 用法：
#   Scripts/test-direct.sh                     # 全套
#   Scripts/test-direct.sh 'StableHashTests'   # 指定类（-XCTest 过滤）
#
# 前提：Debug 产物已由 `xcodebuild build` 生成（构建本身不触发弹窗）。
set -euo pipefail

ROOT="${0:A:h:h}"
# 按 xctest 可执行文件 mtime 选容器——Debug 目录 mtime 不随增量构建更新（实测踩坑）
# (N) = zsh null_glob：无匹配时展开为空而非报错。
# 双重防呆：① glob 空时直接判空（ls -t 无参会列出 CWD——TODO.md 垃圾路径事故）；
# ② xcodebuild build 会移除测试 bundle 产物 → 明确提示 build-for-testing。
DD_DEFAULT=(~/Library/Developer/Xcode/DerivedData/Lightamer-*/Build/Products/Debug/Lightamer.app/Contents/PlugIns/LightamerTests.xctest/Contents/MacOS/LightamerTests(N))
DD=( ${~DD_DEFAULT} )
if [ ${#DD[@]} -eq 0 ]; then
  echo "error: LightamerTests.xctest product missing — the last build pruned test products." >&2
  echo "run: caffeinate -dis xcodebuild build-for-testing -workspace Lightamer.xcworkspace -scheme Lightamer -destination 'platform=macOS'" >&2
  exit 2
fi
# mtime 降序（多容器取最新）
DD="$(ls -t ${DD[@]} | head -1)"
DD="${DD%Lightamer.app/*}"
HOST_BIN="$DD/Lightamer.app/Contents/MacOS/Lightamer"
if [ ! -f "$HOST_BIN" ]; then
  echo "error: host binary missing at $HOST_BIN" >&2
  exit 2
fi

CONFIG=$(mktemp /tmp/la-xctest-config.XXXXXX)
CONFIG="${CONFIG}.plist"
cat > "$CONFIG" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>TestBundlePath</key><string>$DD/Lightamer.app/Contents/PlugIns/LightamerTests.xctest</string>
  <key>productModuleName</key><string>LightamerTests</string>
</dict>
</plist>
EOF

XCODE_DEV="$(xcode-select -p)"
ARGS=()
[ -n "${1:-}" ] && ARGS=(-XCTest "$1")

# 判据 = 测试结果行（Executed 计数 + 失败行），NOT 宿主进程退出态——
# 宿主 shell 的退出路径在**全绿轮也可能非零**（退出态污染，11-04 验收
# 移交）；RC 只作诊断参考打印。RC=0 预置：宿主退出 0 时 `|| RC=$?` 不
# 赋值，`set -u` 下不得引用未定义变量。
RC=0
env \
  DYLD_INSERT_LIBRARIES="$DD/Lightamer.app/Contents/Frameworks/libXCTestBundleInject.dylib" \
  DYLD_LIBRARY_PATH="$DD:$XCODE_DEV/Platforms/MacOSX.platform/Developer/usr/lib" \
  DYLD_FRAMEWORK_PATH="$DD:$XCODE_DEV/Contents/SharedFrameworks:$XCODE_DEV/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
  XCTestConfigurationFilePath="$CONFIG" \
  "$HOST_BIN" \
  "${ARGS[@]}" > /tmp/la-direct-tests.log 2>&1 || RC=$?
rm -f "$CONFIG" /tmp/la-xctest-config.* 2>/dev/null || true

# 判据 = 测试结果行（Executed 计数 + 失败行），NOT 宿主进程退出态——
# 宿主 shell 的退出路径在**全绿轮也可能非零**（退出态污染，11-04 验收
# 移交）；RC 只作诊断参考打印。
grep -E "Executed.*tests" /tmp/la-direct-tests.log | tail -1
FAILED=$(grep -cE "' failed \(|' failed \." /tmp/la-direct-tests.log || true)
SUMMARY_FAIL=$(grep -E "^Executed [0-9]+ tests" /tmp/la-direct-tests.log | tail -1 | grep -oE "with [0-9]+ failures?" | grep -oE "[0-9]+" || echo 0)
EXECUTED=$(grep -oE "Executed [0-9]+ tests" /tmp/la-direct-tests.log | tail -1 | grep -oE "[0-9]+" || echo 0)
if [ "${EXECUTED:-0}" -eq 0 ]; then
  echo "FAILED — Executed 0 tests（-XCTest 过滤名不匹配或旧容器），防空转假绿（host exit=$RC）" >&2
  exit 1
fi
if [ "${FAILED:-0}" -gt 0 ] || [ "${SUMMARY_FAIL:-0}" -gt 0 ]; then
  echo "FAILED — 完整输出: /tmp/la-direct-tests.log（host exit=$RC，仅参考）" >&2
  grep -B2 "' failed" /tmp/la-direct-tests.log | head -20 >&2
  exit 1
fi
echo "OK (direct launch, no testmanagerd; host exit=$RC informational)"
