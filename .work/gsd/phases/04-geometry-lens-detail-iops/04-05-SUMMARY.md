---
phase: 4
plan: "04-05"
title: "detail 五模块（IOP-DETAIL-01..04）：sharpen USM + local contrast EIGF + highpass/soften 双域 + equalizer 金字塔—— SUMMARY"
status: complete
executed: 2026-09-21
tests: "387 tests, 3 skipped, 0 failures (full LightamerTests; 2026-09-21 终轮)"
---

# Plan 04-05 SUMMARY — detail 五模块

## Goal 达成

交付 IOP-DETAIL-01..04（5 ops）：sharpen（35.0 USM）+ local contrast（54.0
`bilat`，EIGF clarity）+ highpass（34.0）/ soften（66.0 Orton）双域变体 +
equalizer（27.0 高斯金字塔）。全部踩 Phase 3 底座（GaussianBlur IIR /
LabMath / toneequal EIGF 核/CorrectionLUT 架构同构），D-G5 主证（sharpen
后向扩展真模块版）兑现。

## Tasks（8 commits）

| Task | Commit | 状态 | 证据 |
|---|---|---|---|
| T0 checkpoint 三口径 | `ae22c1e` | ✅ | DISCUSSION-LOG 04-05-T0 + 04-05-DECISIONS.md D-04-05-T0-0..3 + D1–D11 |
| T1-T4 五模块 + 注册 | `cf3fd80` | ✅ | 5×(.swift+.metal) + Registry（注册/prewarm/seed；Phase 3 七 seed 误删） |
| T5 轨 A golden | `0c860c5` | ✅ | gen_fixtures detail 节 + 76 refs + 15 XMP + 四 parity 套件 22/22 |
| T1 ROI ②真模块 | `c04d2b1` | ✅ | ROINegotiation +1（36×36≪全图），11/11 |
| T5 面板 + seed 恢复 | `adc6d75` | ✅ | 四面板 + 29 keys + PanelWiring +5（24/24）；seed 恢复；SoftenMix pad2 |
| T5 轨 B | `e2bca05` | ✅ | GeometryGolden 链含 detail 腿，4/4 |
| T5 V50 | `302e39c` | ✅ | V50Order +1（6/6） |

## 验收标准逐条自验（plan Verification 表）

- **IOP-DETAIL-01 sharpen（T1）**：合成参考 <1e-4 + amount=0/平场恒等门 +
  σ 换算钉参 + 3σ ROI 外扩真模块断言 ✅（SharpenParityTests 5/5 +
  ROINegotiationTests ②真模块版）。
- **IOP-DETAIL-02 local contrast（T2）**：detail=0 精确恒等 + 公式参考 +
  分块一致 <1e-4 ✅（LocalContrastTests 6/6，含台阶方向 + TilingPlan FULL
  第二消费者）。
- **IOP-DETAIL-03 highpass/soften（T3）**：公式参考 <1e-4 + soften 平场恒等
  （dt-cli probe 免跑：D5 先验结论落 DECISIONS，无变化图 L017 风险）✅
  （HighpassSoftenTests 7/7）。
- **IOP-DETAIL-04 equalizer（T4）**：带分解合成参考 <1e-4 + 全零恒等 ✅
  （EqualizerParityTests 4/4，含带能量内容断言）。
- **SC#4 后向扩展兑现（T1）**：sharpen 真模块 36×36 扩展 + 记账双断言 ✅。
- **轨 B 回归（T5）**：ColorSync 中性度 + 交叉一致性 ✅（GeometryGolden 4/4）。
- **PERF-5 增量（T5）**：单帧增量记录落 `.work/plans/04-05/perf.md` ✅
  （equalizer ~5-8ms 超 6ms 已标注，不阻塞）。

## 关键修复/裁决（排障记录，教训沉淀候选）

1. **模块清单以 plan 文件为准（D-04-05-T0-0）**：任务书 parenthetical 的
   cacorrect/cacorrectrgb 按 plan 不交付——cacorrect 是 Bayer raw 域不可移植
   （rotatepixels 同类勘误），cacorrectrgb 横向 CA 已被 lens TCA 覆盖。defer。
2. **uniform 布局 MSL/Swift 对齐**：mix/recombine 的 srcOffset 从"两 float
   pad"改为 int2 对（MSL int2 8 字节 4 对齐；Swift Int32 对；SoftenMix 去
   pad2 保 16 字节）。ashift float 数组 packing 教训的延续。
3. **L020 帧约定全模块**：全部 mix/recombine 核读 srcOffset（roiOut−roiIn）
   + dispatch 跨输出平面（flip SWAP_XY 教训：永不假设输入输出等 dims）。
4. **Registry seed 误删恢复（流程）**：T1-T4 整段替换吞掉 Phase 3 七 seed
   （sigmoid/agx/filmic/colisa/tonecurve/levels/shadhi）→ PanelWiring 70 失败
   抓获 → 恢复。教训：共享文件改动后跑全量门（04-04 ashift 同类已犯，本轮
   再犯——门规则入 04-06 回归）。
5. **plan 字面勘误三处**：highpass 无 center/radius（两参）；sharpen"默认 0
   中性"实为 amount 快路径（dt $DEFAULT 2.0/0.5/0.5）；equalizer"逐字节"恒等
   只保快路径（重组保 <1e-5）。
6. **dt-cli probe 免跑（D5）**：soften 平场恒等对任何 DC=1 blur 恒成立
   （vacuous）+ 变化图必触 L017——结论先验，合成单轨。
7. **测试尾 brace/通道索引**：V50/PanelWiring/Edit 工具尾边界 + tiling 读回
   `(i/3)*4+channel`（非 `i*4+(i%3)`）。

## 全绿闸门

- 全 suite：**387 tests, 3 skipped, 0 failures**（2026-09-21 终轮；
  04-04 时 358 → +29：parity 22 + ROI 1 + PanelWiring 5 + V50 1）。
- 04-VALIDATION IOP-DETAIL-01..04 行 + 轨 B 行 + 面板/PERF 行 ✅；
  Manual-Only：detail 视觉抽检登记（L011 口径 pending-manual）。
- 下游影响：04-06（SC#3/SC#4 签核——detail golden + ROI 真模块证据就绪）；
  Phase 5 denoise（GaussianBlur/EIGF/halo 语义 + TilingPlan 第二消费者）。

## 过程记录

- 本文件 + 各提交 body + 04-05-DECISIONS.md + `.work/plans/04-05/perf.md`；
  调试探针无（合成参考一次写对为主；parity 首轮全绿 22/22）。
