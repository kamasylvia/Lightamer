---
phase: 4
plan: "04-01"
title: "ROI 协商协议改造 — SUMMARY"
status: complete
executed: 2026-09-20
tests: "282 tests, 3 skipped, 0 failures (full LightamerTests)"
---

# Plan 04-01 SUMMARY — ROI 协商协议改造（Phase 4 硬前置）

## Goal 达成

`PixelPipe.processRec` 从「恒等 ROI assert」改造成 Darktable 式两趟真协商：
前向 `run()` 预计算（dt `get_dimensions :3368-3405`）+ 后向 miss-closure 协商
（dt `:2085-2096`）+ 输入平面子域渲染 + `roiHint` 探针缝。`PipeCacheKey.roi`
首次实际生效；`levelHash` 与 ROI 正交语义不破坏。

## Tasks（7 commits）

| Task | Commit | 状态 | 证据 |
|---|---|---|---|
| T0 decision 定稿 | `e07e137` | ✅ | 04-DISCUSSION-LOG 三口径（D-G2 读法 / roiHint 形状 / SC#4 闸门） |
| T2 erased 转发 + ROI 辅助 | `34f94b6` | ✅ | ModuleBoxing 2 转发 + IOPModule 默认恒等 + clamped/AABB；IOPModuleTests 6/6 |
| T1 测试先行 + harness | `f8b4019` | ✅ | ROINegotiationTests 新建（① RED 8 fails ↔ T3 改造点）；PipeCache ROI 轴绿 |
| T3 前向预计算 + 真协商 | `3370399` | ✅ | bufInROI/levelROI + 协商递归 + processedROI 盖章 + TestGain 窗口采样；①③④绿 |
| T4 子域渲染 + roiHint | `ca1c70e` | ✅ | renderRegion（源锚定 bounds）+ process(roiHint:) + frameROI clamp；② e2e 绿；279 0 fail |
| T5 内存记账 | `e74ff90` | ✅ | MemoryBudgetTests 9/9（crop 1/4 bytes；halo 30×30+24×24≪128） |
| T5 D-X1  guard + 签核 | `ad5bd16` | ✅ | JPEG open→reopen smoke；API.md；04-VALIDATION Wave 1 签核 |

## SC#4 四断言（all-green 闸门）

1. **Crop 前向收缩**：`[crop50, gain]` → 终帧 32×32；gain 见窗口；crop roiIn =
   下游窗口 + 原点（dt crop.c:576-592）；记账 3×窗口。
2. **Sharpen 后向外扩**：`[gain → halo]` + roiHint 24×24 → halo roiIn =
   30×30（+2·halo 数值精确）；输入平面按扩展窗口记账 ≪ 全图。
3. **禁用穿越**：crop disabled → 全链恒等、零 process、miss=2。
4. **缓存回归**：crop 拖动 A→B→A → 新键做功、旧键保留、回拖全命中零功耗。

## 关键修复（排障记录）

- **CropStub 对齐 dt 原文**：forward 相对偏移（不加 input 原点）；
  backward 保留下游窗口 + 原点（初版误删导致双重收缩 → assert 炸）。
- **TestGain 窗口采样**：协商后输入/输出平面偏移不同，逐点 kernel 必须按
  `(roiIn−roiOut)` 采样；零偏移快路径保留 legacy kernel（恒等默认逐字节不变）。
- **Clamp  bound = frameROI**：halo 翼合法超出 hint/forward 窗口（初版 clamp
  到 bufInROI 切掉 30×30→24×24）；dt 本无此 clamp，以解码帧为界。
- **Scaled 腿经 region 渲染**：入口像素坐标 ÷scale 回解码坐标（PREVIEW/THUMBNAIL
  全绿的关键修复）。
- **Negotiation-order 语义**：TOP-DOWN probe 顺序下 gain 键定在 hint 窗口、
  halo 消费扩展——各模块见各自协商对（e2e 注释钉死）。
- **GoldenColor 单发 flake**：T3 树上 1 次 `crossLinear 1.0 @512,0`，即时重跑绿 +
  3× 连绿 + clean 树绿 → 环境 flake（CIContextPool 文档化已知 flake 家族）。

## D-X1 回归保护

- `testJPEGOpenReopenSmoke`（RAW03Tests）：JPEG 解码 → 管线 → 同 cache/imageID
  重跑全命中零功耗、同尺寸非空平面。单一渲染显示路径不受 ROI 改造影响。
- AppLaunchTests 属 UITests（需解锁控制台）；本 plan 以 headless JPEG 烟囱 +
  全套 LightamerTests（282 绿）为验收。

## 全绿闸门

- 全 suite：**282 tests, 3 skipped, 0 failures**（2026-09-20 终轮）。
- 04-VALIDATION Wave 1 两行 ✅；04-02..04-05 `depends_on: ["04-01"]` 可开工。
- 过程记录：本文件 + 各提交 body；无 `.work/plans/04-01/` 调试日志留存（排障全在提交说明）。

## 下游影响

- 04-02（crop/flip）：换真 crop 模块回归断言①（stub→真模块）；overlay 用
  「live disabled + 暗膜」规避拖动全链 miss。
- 04-05（sharpen/detail）：换真 sharpen（`ceil(3σ)` 外扩）回归断言②。
- 恒等默认不变量：所有既有模块 modifyROI 默认恒等 → 现链零语义变化（全回归绿为证）。
