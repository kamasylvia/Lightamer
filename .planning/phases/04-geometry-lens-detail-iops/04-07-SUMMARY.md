---
phase: 4
plan: "04-07"
title: "Phase 4 签核（VALIDATION sign-off）—— SUMMARY"
status: complete
executed: 2026-09-21
tests: "398 tests, 3 skipped, 0 failures (full LightamerTests)"
---

# Plan 04-07 SUMMARY — Phase 4 签核

## Goal 达成

执行 Phase 4 VALIDATION 签核：ROADMAP §Phase 4 SC#1-4 逐条核对（证据指针落
`04-DISCUSSION-LOG.md` 04-07 节）+ golden 完整性总账 9/9（manifest 追加 Phase 4
核对节）+ PERF-5 链长增量记录（只记录不设门）+ 轨 B 全链回归 + sidecar 9 新 op
round-trip + 未知 op 降级回归 + 内存记账复核 → `04-VALIDATION.md`
`status: validated` + `nyquist_compliant: true`。本 plan 不写新功能——唯一新增测试是
签核缺口回补（T2 sidecar 机制覆盖），其余全是核对与记录落账。

## Tasks

| Task | 内容 | 状态 | 证据 |
|---|---|---|---|
| T1 SC#1-4 逐条核对 | SC#1-4 每条证据指针落 DISCUSSION-LOG 04-07 节；manifest 追加 Phase 4 golden 总账节 | ✅ | DISCUSSION-LOG 04-07 两节 + manifest `## Phase 4 golden 完整性总账` |
| T2 全链回归 | 轨 B（GeometryGolden track B 2/2，全启用链）+ sidecar 9 op（新 Phase4SidecarTests 9/9）+ 未知 op 降级（既有）+ 内存记账复核 | ✅ | 终轮全量 398 绿内含全部 |
| T3 PERF-5 链长增量 | Release 36.23→33.42ms（+9 中性模块≈零增量），只记录不设门 | ✅ | `.work/04-07/perf-phase4.md` + Release/Debug 双实测 |
| T4 VALIDATION 签核 | 全行 ✅ + Wave 0 勾销 + frontmatter validated/compliant + TODO/文档收口 + 全量回归 | ✅ | VALIDATION Sign-Off 15 项全勾 + TODO Phase 4 完成态 |

## 缺口回补（T2 唯一代码改动）

- **发现**：sidecar 对 9 个 Phase-4 新 op 无直接 round-trip 测试——既有
  `SidecarRoundTripTests` 只覆盖 trio + testgain + 未知 op 降级（机制通用但无逐 op 点名）。
- **回补**：新建 `Tests/LightamerTests/Phase4SidecarTests.swift` 9 用例——每 op 非默认 Params
  → `ModuleInstance` → JSON  verbatim round-trip → params 解回原值 → 真 registry
  `makeBox(op)+apply(record)` 物化（含 identity UUID 恢复）。9/9 首跑即绿（机制本就 op-agnostic）。
- **修测试 infra**：新文件进套需 `tuist generate`（Project.swift glob 制；pbxproj gitignored 不提交）；
  `XCTUnwrap(await ...)` 写成同步上下文 actor 隔离错一次，拆两行修复。

## 验收标准逐条自验（plan Verification 表）

- **SC#4 ROI 端到端**：`ROINegotiationTests` 11/11（crop 前向 32×32 + sharpen 真模块后向 36×36
  + 禁用穿越 + 回拖命中），终轮全量内绿 ✅。
- **全 8 REQ-ID parity 完整性**：manifest 总账 9/9 有账（crop/flip/ashift/lens/sharpen/bilat/
  highpass/soften/equalizer：轨 A 来源 + 容差 + probe/采纳记录）✅。
- **轨 B 全链回归**：`GeometryGoldenTests` track B 2/2（crop+flip+lens+五 detail 中性插链，
  ColorSync 双判据不回归）✅。
- **内存记账**：`testCropHalvesMemoryAccounting`（1/4）+ `testHaloExpansionStaysBelowFullFrame`
  （30×30≪128）probe 腿绿；ashift 有界/sharpen 外扩由 ROI 真模块断言覆盖 ✅。
- **PERF-5**：`PreviewChainPerfTests` 2/2（Debug warm 32.83ms + Release warm 33.42ms）✅；
  FULL toneequal Δfootprint 336-337MB << 3GB ✅。
- **sidecar 兼容**：Phase4SidecarTests 9/9 + 未知 op 降级既有测试绿 ✅。
- **签核**：`nyquist_compliant: true` + 全行 ✅ + 全 suite 398 绿 ✅。

## 新增签核内容（任务书 §3）

- **GUI 验收轮**：GUI-1（视口 <16 30.6%→13.7%，饱和 0→75480）+ GUI-2/3（无对角线，包络边距 ≤11px）
  + GUI-4（三列 13.9%/54.1%/32.0%，视口 ≥50%；990pt 窗复验 pending-manual）——FINDINGS.md 为准。
- **L021 + L019/L020**：L021（04-06 已入 LESSONS）+ L019/L020（Phase 4 期间已落账）确认复用，无新增。
- **Phase 5 移交清单 5 项**：toneequal/flip double-scale 审计、shadhi bilateral 腿、PERF-5 杠杆、
  cacorrect/cacorrectrgb Bayer 方案、Lab 往返共享——逐条 TODO/DECISIONS 引用存在性已核对
  （见 DISCUSSION-LOG 04-07 节）。

## 全绿闸门

- 全 suite：**398 tests, 3 skipped, 0 failures**（2026-09-21 终轮全量实测；
  389 基线 + Phase4SidecarTests 9；Release PERF 链同日绿）。
- `04-VALIDATION.md`：status validated + nyquist_compliant true + wave_0_complete true +
  Sign-Off 15 项全勾；Manual-Only 6 行 pending-manual（L011 口径挂账，不阻塞）。
- 下游影响：Phase 5（Color & Denoise）——ROI 协商、warp/blur 惯例、TilingPlan 第二消费者、
  PERF 增量基线（33.42ms Release）全部就绪；IOP-GEO-05/06 与 4 角透视手柄 defer Phase 6。

## 过程记录

- 本文件 + DISCUSSION-LOG 04-07 节 + `.work/04-07/perf-phase4.md` + 各提交 body。
