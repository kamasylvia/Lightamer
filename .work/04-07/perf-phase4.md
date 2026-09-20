# PERF-5 Phase 4 链长增量记录（Plan 04-07-T3）

> 方法：PreviewChainPerfTests 同口径（2048×1536 synthetic，PREVIEW longEdge 2560，
> PSO prewarm + 稳定 imageID + exposure tick 全链失效，4 帧预热后 12 帧 warm median）。
> Phase 3 基线 = Release warm median **36.23ms**（03-06，11 模块链：colorin + 10 tone iop）。
> Phase 4 种子 = 基线 11 + 9 新模块（lens/ashift/flip/crop/sharpen/bilat/equalizer + highpass/soften disabled）。
> 注意：`testPreviewFullChainFrameTime` 的正式链 = `editingDefaultInstances()` 快照（随种子增长），
> 因此本次 Release/Debug 实测即 Phase 4 全链（20 模块）数字——只记录，不设门。

## 实测（2026-09-21，本机 Apple M4，macOS 27）

| 构建 | 逐帧 ms | median | **warm median** |
|---|---|---|---|
| **Release**（正式） | 36.8, 33.6, 30.4, 33.7, 30.4, 33.4, 33.4, 32.4, 34.1, 30.3, 33.4, 33.3 | 33.41 | **33.42** |
| Debug（回归对照） | 33.3, 32.5, 30.3, 33.2, 31.4, 33.1, 32.1, 30.3, 33.2, 30.2, 32.8, 32.5 | 32.49 | **32.83** |

复跑命令（与 `.work/03/perf-record.md` 同）：

```bash
# Debug 回归对照
caffeinate -dis xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer \
  -destination 'platform=macOS' -only-testing:LightamerTests/PreviewChainPerfTests
# Release 正式
caffeinate -dis xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer \
  -destination 'platform=macOS' -configuration Release -derivedDataPath /tmp/dd-release \
  ENABLE_HARDENED_RUNTIME=NO -only-testing:LightamerTests/PreviewChainPerfTests
```

## 链长增量分析（+9 模块）

- Phase 3 基线 Release warm median 36.23ms → Phase 4 全链 Release **33.42ms**：
  增量 ≈ **−2.8ms**（噪声带内， machines 同机先后跑；Debug 37.63→32.83 同方向）。
- 方向解释（非优化功劳）：9 新模块在种子中 = 中性恒等位——crop 全帧 window blit、
  flip NONE、lens OFF、sharpen amount=0、bilat detail=0、equalizer 全零增益全走 **blit 快路径**、
  highpass/soften **disabled 跳过**。中性模块≈每模块 1 趟 blit（~0.3-0.5ms），但 exposure-tick
  全链失效形状下缓存行仍全 miss——实测持平/微降说明新增 blit 趟被 GPU 并行吸收，
  未引入 Lab 往返/IIR 重型趟（04-05 单模块增量见 `.work/04-05/perf.md`：active 参数下
  sharpen ~2-4ms / bilat ~4-6ms / equalizer ~5-8ms——那些是 ACTIVE 态，本链是 NEUTRAL 态）。
- 结论：**只记录，不设门**（plan T3 acceptance 字面）。预算状态 = 与 Phase 3 同注记：
  Release 33ms vs 16.6ms 预算未达；晚链单滑块 2-6ms ✓；杠杆分配不变——
  ①管线级 Lab 往返共享（Phase 5+）②跨模块 dispatch 批合并（Phase 4+，本 Phase 未做——
  Phase 4 只加了模块，未做批合并；杠杆仍 open，见 TODO Phase 3 遗留行）。
- FULL 内存复验：`testFullToneEqualMemoryBudget` Δfootprint Debug 337MB / Release 336MB
  << 3GB（D-C1）✓（基线 289-337MB 同带）。

## 门

- 记录即合规（plan T3 acceptance）。`PreviewChainPerfTests` 2/2 本轮绿（Debug + Release）。
