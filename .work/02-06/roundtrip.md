# 02-06 Headless Sidecar Round-Trip — SC#3 acceptance artifact

**Date:** 2026-09-19 · **Machine:** macOS 27.0 / Apple M4 · **Result: PASS**

## Method

DEBUG launch argument `-la_sidecar_probe`（真实 app 进程内驱动，LaunchServices
`open -a` 启动以保窗口创建确定性；`-la_sidecar_dump` 额外 dump 显示平面字节）：

1. **run1 = edit**：sidecar 不存在 → 探针经真实 D-H1 三件套
   （`beginContinuousEdit` → `setLiveParams(testgain 1.5×)` →
   `commitContinuousEdit`）提交一条 history item → 等待 2s 节流写入
   `IMG_PROBE.jpg.lra` → 打印渲染平面 hash → `NSApp.terminate`（触发
   `applicationWillTerminate` → `flushForTermination` 同步 flush）。
2. **run2 = verify**：sidecar 已存在 → app 正常 odoc open → coordinator 从
   `.lra` 恢复 history/instances/imageID（drift 检查 + 未知 op 降级全跑）→
   pixelpipe 重渲 → 打印恢复态 + 渲染平面 hash → 退出。

判定：run1/run2 的 displayHash 一致 + dump 字节 `cmp` 一致 + 恢复日志的
history/position/paramsHash 符合。

## Evidence

```
run1 (edit):
  probe edit committed — waiting for the 2s throttled flush
  probe mode=edit sidecar flushed, displayHash=1dbb380e2153fea0
run2 (verify):
  coordinator] sidecar restored: IMG_PROBE.jpg (history 1/1, imageID 38B3AA6C-…)
  coordinator] pixelpipe output ready: PREVIEW bucket 1120px (0 hits / 5 misses, 5 planes)
  probe mode=verify history=1/1 position=0 topParamsHash=59f189fbe560e1ee
             displayHash=1dbb380e2153fea0 instances=4
byte compare:
  cmp /tmp/lra-display-edit.bin /tmp/lra-display-verify.bin → IDENTICAL
sidecar 内容（python 抽查）: schemaVersion=1, gain 1.5 base64 byte-exact,
  UInt64 hash 全部 decimal-string, driftDetected=false, .xmp 未触碰（无此文件）
kill -9 窗口期检查：写后 0 tmp 残留（store 单测 testAtomicWrite* 双腿覆盖）
```

## 执行过程中抓出的真实缺陷（已修）

**ColorSync 腿跨队列读竞态**（`CIContextPool.convertTexture`）：CI 在自己的
内部队列渲染纹理背书的 CIImage，而输入平面在我们的串行队列上可能还有
in-flight kernel 写入（dispatch2DTexture 只 commit 不等完成）。restore 渲染
5 个 dispatch 连发时 CI 稳定读到刚分配的全零平面（4/4 复现黑图）；live-edit
短渲染时序不同则侥幸通过（2/2）。修复 = CI 读取前先在本队列 commit 空
command buffer 并 `waitUntilCompleted`（fence）。该竞态是 pre-existing
（02-04 引入 fallback 腿起即存在），由 02-06 的 round-trip 验收逼出。
Core 级 `SidecarRoundTripTests.testRoundTripRestoresIdenticalRenderedOutput`
同时固化该回归防线（readback 前 drain；教训同步 LESSONS L014）。

## 人工可选复核

真机交互路径（菜单/滑块）Phase 3 才有 UI；本轮以进程内真实 trio + 真实
sidecar I/O + 真实渲染链等价覆盖。
