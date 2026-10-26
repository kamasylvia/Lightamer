---
phase: M8
slug: fsim-spectral
status: prepared
created: 2026-10-26
---

# Phase M8 — Validation 预备（FSIM 光谱升维：M8-3 收口汇编，2026-10-26）

> **性质**：phase 签核输入汇编（C 档停位交付物——verify-work 结论给用户过目
> 后的独立 VALIDATION 批才执行本体）。本文件只汇编四 plan 终账 + 双臂
> golden 面 + probe 真值 + 走查证据索引，不做任何新验证。

## 一、四 plan 终账（executed 对账链）

| plan | commit 收口 | ΔN | 对账 |
|---|---|---|---|
| M8-1a 数学核-数据面 | `47b28be0` | +19 ∈ [+18, +24] | IOP 增量 3+4+5+6+1（DECISIONS 五） |
| M8-1b 数学核-GPU 面 | `e702be76` | +17 ∈ [+12, +18] | IOPParity 4+3+5+5+0（DECISIONS 四.9；probe 族 5 skip） |
| M8-2 管线集成 | `ff110abd` | +31（越带 +5 申报） | IOPParity +21 / IOP +5 / Layers +5（SUMMARY 定向三 bundle 精确对账，4242+31=4273） |
| M8-3 面板+收口 | `06ac0d41`/`1890febe`/`d6a3c32f`/`0809be19`/`af84ddc1` + 收口 | +13 ∈ [+10, +14] | App +7（FilmPanelSpectralUITests）/ IOPParity +2（DualArm 扩）+4（ExposureSemantics） |
| **合计** | | **+80** ∈ [+60, +82] ✓ | 全套三轮同值 **4286/46/0** ∈ [4283, 4287] ✓（skip 46 = 41 + 1b probe 族 5 申报；M8-3-SUMMARY §T5） |

## 二、双臂 golden 证据链（正本索引）

- **legacy 冻结主门**：`filmRampPlaneHash = 14_365_179_805_968_017_957`
  （FilmDeterminismTests，源级零改跑绿——M8-2 T5 A1/A2 + 缓存键零增量）。
- **光谱生产哨兵**：ramp512 `3613671270926763817` + fixture
  `7557687968680693683` + 中性闭合注册值 0.1300766902548187
  （SpectralDualArmGoldenTests，±0.01 带内）。
- **probe ④ 哨兵**：`10129511468721193651`（登记消费非生产复现——
  M8-2 DECISIONS 十的 probe-only 双 blur 序列注记）。
- **证据正本**：lightamer-evidence 私仓
  `m8-fsim-spectral/evidence-m82/DUAL-ARM-GOLDEN.md` + probe 批
  `probe-m81b/PROBE-RECORD.md`（pack policy B）。
- **M8-3 增面**：迁移 UX 四面（pristine/迁移按钮/确认 sheet/渲染翻面，
  `.work/gui-acceptance/m8/`）+ 曝光语义终账四法
  （SpectralExposureSemanticsTests：solve gain 消费层/ev_scale ≡ 1 双钉/
  descriptor 曝光不变/NOTICE 升格）。

## 三、probe 真值（M8-1b 交付 + M8-3 终态复测零漂移）

| 面 | 终值 | 复测 |
|---|---|---|
| identity 分级 | lograw/print_expose/print_develop **0 ULP 逐位**；expose ≤8e-5（除法翻格缝，声明 2e-4）；develop_corr 1.19e-7；develop 3.58e-7 | —（M8-1b 钉死，源级零改） |
| micro band | 六 stage ≤4.1e-7（门 1e-6）；scan 声明 5e-3（实测 3.1e-7） | — |
| 100MP FULL | 139.2ms ∈ [40,160]ms；A 26.3 / blur 8.8 / B 103.3ms | — |
| corr 裁决 1/4 | ladder 0/1.62e-2/**2.22e-2**/3.23e-2；ds4 corr 95MB / ds8 23MB | M8-3 复测同值（95/23MB）✓ |
| nail 三板斧 | fma 1357/4608 worst 5.96e-8 / 取倒 574/2000 / 多项式 4.77e-7 | M8-3 复测同值 ✓ |
| tc 构建 | -O 13.5-17.5s/次；Debug 28 对 293-318s（gate 600s） | M8-3 复测 298.7s 带内 ✓ |

## 四、走查证据索引

- 正本 = `.work/gui-acceptance/m8/MANIFEST.md`（M8-3 T5 交付——迁移 UX
  走查 + v2 档面板 readout 走查 + 导出递缝走查，逐项截图/证据路径）。
- 面板零新增 = FilmPanelSpectralUITests 机器面（源清单快照 + AX 活树）+
  M8-3-SUMMARY §T1。

## 五、C 档停位声明

本文件落盘 = M8-3 执行批闭环材料齐；**VALIDATION 本体（verify-work +
签核）= 用户过目后的独立批**——本 phase 四 plan 均按 C 档门控逐 plan
停汇报，无越权执行。
