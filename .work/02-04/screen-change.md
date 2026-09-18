# Plan 02-04-05 — Display-profile follow(D-COL2)手动验证记录

**Date:** 2026-09-19 · 环境:macOS 27.0 / Apple M4 / BenQ PD2705U(外接,自定义 ICC,唯一显示器)

## 已验证(app 内,log stream 实证)

启动 app(`open Lightamer.app`)+ `open -a` 打开 `input/RAW/DSC09991.ARW`,log stream
(`subsystem == com.kamasylvia.lightamer`,info 级)捕获:

```
[color]      display profile → ColorSync fallback (custom ICC)     ← configure(window:) → 初始 resolve
[error]      registered default.metallib from LightamerIOP.framework
[decode]     decoded DSC09991.ARW vv9
[coordinator] pixelpipe output ready: PREVIEW bucket 1120px (0 hits / 4 misses, 4 planes)
```

- **D-COL2 跟随链路已接线**:`WindowCapture`(viewDidMoveToWindow)→
  `PipeCoordinator.configure(window:)` → `startScreenFollow()`
  (`NSWindow.didChangeScreenNotification` + `NSApplication.didChangeScreenParametersNotification`)
  → 初始 resolve 成功,profile 标签正确(本机 = 自定义 ICC → ColorSync fallback)。
- **默认链在 app 内生效**:4 planes = input + colorin + colorout + gamma(02-03 时代为 2);
  gamma 尾平面 `.bgra8Unorm`,blit 走 display-ready passthrough regime(新 PSO),屏幕显示正确
  (截图 `/tmp/la-with-image.png`,内容 = 绿调夜 shop,与 headless CI 基线逐通道一致,见
  `smoke-run.md` §B)。
- **幂等**:screen 事件重复触发时 `displayStableID` guard 命中即返回("idempotent no-op",
  debug 级);仅 stableID 真变才 re-commit + 重渲。
- 双 log 行(同 profile 两次)为 configure 双触发(Window 两次 placement)与初始 resolve 的
  良性竞态——stableID guard 保证只有第一次生效,无重复渲染;已知可接受。

## 跳过项(skip-with-reason)

- **双屏拖拽换 profile 实测**:本机仅一台显示器(BenQ,无第二显示源),无法触发
  `didChangeScreenNotification` 的真实跨屏场景 → **skip-with-reason**(计划允许)。补偿性验证:
  ① 缓存失效语义由 `GoldenColorTests.testFullChainCacheAssertions` 以 coordinator 同款操作序列
  (override + re-commit)在单测内完整断言(colorin hit / colorout+gamma miss / 回切全 hit);
  ② resolve 逻辑对 P3/sRGB/自定义 ICC 三类输入由 `TerminalTrioTests.testDisplayProfileKnownSpaces`
  覆盖。Phase 13(COLOR-03 多显示器/软打样)补真机双屏实测。
