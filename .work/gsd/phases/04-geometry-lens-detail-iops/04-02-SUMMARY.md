---
phase: 4
plan: "04-02"
title: "crop（IOP-GEO-01，窗口变换/比例锁）+ flip/orientation（IOP-GEO-04，索引映射 kernel）+ EditorMTKView overlay 手柄（D-G6，D-H1 三件套）——ROI 前向收缩首批真模块 + dt-cli 直接 golden"
status: complete
executed: 2026-09-20
tests: "311 tests, 3 skipped, 0 failures (full LightamerTests)"
---

# Plan 04-02 SUMMARY — crop + flip + overlay 手柄（ROI 协商首批消费者）

## Goal 达成

交付 IOP-GEO-01（crop，含比例锁）与 IOP-GEO-04（flip/orientation），作为
04-01 ROI 协商的首批真模块：crop 的 `modifyROIOut` 前向收缩让下游平面按
裁切窗口原生分配；flip 是纯索引映射（parity <1e-6 全绿）。UI 侧交付 D-G6
的 overlay 手柄（角落拖拽 + 网格线 + 比例锁）与面板，交互走 D-H1 三件套，
live 语义用「crop 临时 disabled + 暗膜」（T0 决策 a）。

**v50 硬约束**：flip(16.0) 先于 crop(24.5) ——默认链自然满足，V50OrderTests
钉死（iop_order.c:810-812 机制化）。

## Tasks（6 commits）

| Task | Commit | 状态 | 证据 |
|---|---|---|---|
| T0 live 语义决策 | `1f56b21` | ✅ | DISCUSSION-LOG 04-02-T0（采纳 a）+ plan 注记 |
| T1 CropModule + T2 FlipModule | `8ae634f` | ✅ | Crop/Flip 模块 + Registry + Crop/FlipParity 16/16 + ROI ①③④真模块回归 + V50 顺序断言 |
| T3 golden | `73270e0` | ✅ | XMP 7 cases + synth refs + GeometryGolden 4/4（track A <1e-6 + track B 2/2） |
| T4 overlay + fit | `ca9e068` | ✅ | ViewportFit 抽取 + overlay/handles/scrim + host + EditorAreaView 挂载 + CropOverlay 6/6 |
| T5 panel + sign-off | （本批） | ✅ | CropPanelView + catalog 20 keys + PanelWiring +3 + VALIDATION ✅ + 全 suite 311 绿 |

## 关键修复（排障记录）

- **裸模块腿读未提交默认**：`modifyROIOut` 读 box 的 `committed`（TestGain
  同构）——直接 `Module()` 构造的腿读全幅默认。golden 腿改走 registry box
  后 crop 全绿（flip 同腿同修）。Gotcha 注记落 CropModule。
- **flip backward 基准三易其稿**：input-dims → output-dims → buf_out（dt
  `:338-339` 原文：`buf_out×scale`）。CPU round-trip + GPU 8 态 + ROI
  AABB 三方互锁后定稿。
- **crop e2e 的 CI 腿漂移**：gradient-window 跨 render 对比漂移达 1.0
  （CI 行序/内容敏感）；e2e 改直接 blit + 同缓存窗口平面双重定位，
  RGB 门 <1e-6。
- **合成 hook 链复现不了 pipe 状态**：手卷两 box 的 hook 链读到另一 box
  的 committed（4×4 vs 3×3 之谜）；退为 order-only 断言 + pipe 内覆盖。
- **track B 窗口语义**：50% 窗口把中性 patches 推入 letterbox → 全幅
  crop + NONE flip（window 路径由 track A 覆盖）。
- **Edit 工具 `+` 前缀陷阱**：body 行 `+TEXT` 里的 `+` 被当作字面（flip
  process / overlay drag 两次 syntax break）—— Ancestors 式重写改走
  `write` 整文件。

## D-X1 回归保护

- overlay/panel 只产 instance records（coordinator 单渲染路径未动）；
  EyedropperTests + PanelWiringTests 全绿为证。
- AppLaunchTests 属 UITests（需解锁控制台）；本 plan 以 headless
  PanelWiring + CropOverlay + 全套 LightamerTests（311 绿）为验收。

## 全绿闸门

- 全 suite：**311 tests, 3 skipped, 0 failures**（2026-09-20 终轮，
  04-01 时 282 → +29：Crop/Flip 16 + Golden 4 + Overlay 6 + Panel 3
  + V50 1 − 退役 1）。
- 04-VALIDATION IOP-GEO-01/04 行 + 轨 B 行 ✅；Manual-Only overlay
  3 行登记（L011 口径）。
- 下游影响：04-03（ashift 黑角由 crop 收——组合语义就绪）、04-06
  （SC#1/SC#4 签核数据源就绪）。

## 手动验收（Manual-Only，未执行）

- overlay 拖角 → viewport 纹理尺寸变化 + 暗膜 + history +1。
- 三分/phi 网格视觉（0.3819/0.6181）。
- 比例锁手感（3:2/16:9/original 短边贴合）。
