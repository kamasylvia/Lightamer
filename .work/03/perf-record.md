# PERF-5 正式 CI 记录（Plan 03-06-T7）

**日期**: 2026-09-20 · **主机**: M4 (MacBook Air, macOS 27.0) · **管线**: PREVIEW 2560 桶，2048×1536 合成图（native scale 1）

## 测量形状（真实拖拽语义）

- 编辑种子全 11 iop 启用（temperature/exposure/sigmoid/colisa/tonecurve/levels/shadhi/toneequal/filmicrgb/agx + colorin）。
- 稳定 imageID（app 拖拽期间输入平面不重物化）+ 每帧 exposure 微 tick（哈希链全失效 → 全链重渲）。
- PSO 启动预热（`MetalContext.prewarmPipelineStates`，load 后台 Task）先行。
- 4 帧预热后取 12 帧，报告 warm median。

## 正式数字（`PreviewChainPerfTests.testPreviewFullChainFrameTime`）

| 构建 | 逐帧 ms | median | **warm median** |
|---|---|---|---|
| **Release**（正式门） | 68.1, 90.1, 42.9, 29.4, 32.5, 28.4, 34.9, 27.5, 28.1, 41.6, 31.3, 36.2 | 34.87 | **36.23** |
| Debug -Onone（回归对照） | 83.0, 75.2, 42.1, 30.2, 35.7, 31.9, 38.9, 30.4, 27.0, 37.6, 28.2, 33.3 | 35.67 | **37.63** |
| （03-05 预验 Debug 基线，UUID-per-frame 形状） | — | — | 63.4 |

## 预算对账（16.6ms @60fps）

- **实测 Release 稳态 ≈ 36ms（~2.2× 预算）**。RESEARCH §8 的 7-10 趟假设不成立：真实链 ≈ 40 GPU 趟
  （toneequal EIGF 高斯多趟 ~12-15、每 Lab 模块 2 趟往返 ×3、shadhi 模糊 3-4 趟、其余元素级 ~10）。
- 已落地的杠杆：Release 构建（相对 Debug 无显著差——瓶颈是 GPU 趟数与 per-dispatch 开销，非 Swift 侧）、
  PSO 启动预热（首帧冷启动消除）、稳定 imageID 拖拽形状（probe 实证 per-frame UUID 令输入平面每次重物化 ~11ms，
  非 app 真实语义）。
- **剩余杠杆（架构级，已分配）**：①管线级 Lab 往返共享（RESEARCH Open#9 → Phase 5+，~6 趟省出）；
  ②跨模块 dispatch 批合并（同 command buffer 多 encoder，Phase 4+）；③toneequal EIGF 分档降采样。
- **结论**：晚链拖拽（sigmoid/filmic/agx/colisa 等单滑块）实测 2-6ms ✓ 60fps；最坏情形（exposure/WB tick
  全链重渲）为上述 36ms。SC#3 按「晚链交互 60fps 成立 + 全链重渲超预算（杠杆已分配）」注记，
  Manual-Only 的 Instruments 目检待人工。

## 复跑命令

```bash
# Debug 回归对照
xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' \
  -only-testing:LightamerTests/PreviewChainPerfTests
# Release 正式门（本机 Release 需 ENABLE_HARDENED_RUNTIME=NO 覆盖：L011 同族签名验证）
xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' \
  -configuration Release -derivedDataPath /tmp/dd-release ENABLE_HARDENED_RUNTIME=NO \
  -only-testing:LightamerTests/PreviewChainPerfTests
```

## FULL 内存复验

`testFullToneEqualMemoryBudget`：FULL 桶 toneequal 链 Δfootprint 289-337 MB << 3GB（D-C1）✓。
