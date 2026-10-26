---
phase: M8
slug: fsim-spectral
status: validated
nyquist_compliant: true
milestone_closeout: M8
created: 2026-10-26
validated: 2026-10-26
---

# Phase M8 — VALIDATION（FSIM 光谱升维签核，2026-10-26；晨审已过目 + 三眼验收 + 修正批三眼全闭环）

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


## 六、验收与修正批终账（签核时点补录，2026-10-26 深夜）

- **四 plan 三眼验收**：路 1 `45f88435`（0B+0M+0m+4obs）+ 路 2 `f5bbe17c`
  （0B+0M+0m+5obs，盲评 + 反自取消金样——改 CMF 波长点双哨兵真红）+
  omp 终审 `7b53e95d`（PASS/0B+1M+0m+6obs）。全套三轮 `4286/46/0` 同值。
- **M8-FIX 修正批**（omp M-1 → 真根因 `WorkspaceModel.closeEditor` 丢弃
  process 载体——omp 两候选证伪，第三机制定罪；正常用户路径同病）：修复
  `7422401a` + 契约登记 `73421ef9` + 收口 `3f24584c`；综合验收 `54a86ae4`
  PASS/0B+0M+0m+3obs（GUI 两轮独立反转 + v1 判别腿）+ **omp 复核
  `f1a6367d` PASS/0B+0M+0m+4obs（三项物证逐项反转 + 磁盘腿实机直证 +
  D-6 翻账独立 40 采样加强）**。全套 `4287/39/0`（skip 46−7 = RAW 供件
  恢复 U=7 首跑全过）。
- **R5 波随件裁决**：D-6 重开项目态复验绿核销（408 行翻账——壳交接消解
  H2 载体，CPU 0.0%×40 两轮独立）；导入零行确诊（grid 刷新链，R6 真修
  首项）；Vision 漂移维持登记（CPU 仍未入 supported 集，下轮挂 27.1）。
- **随批运维件**：RAW 供件恢复（TestRAW 六样本齐）+ ColorChecker 网寻
  落位标定（首启双真发现——中性 +7/255 AWB 表型 + 暗区 pipe vs ColorSync
  255 分歧 → CC-ARW 调查批；坐标表回退空、门维持 skip）+ noiseprofiles
  许可发布门解除（NOTICE 条目 R + LICENSE-NOTES 翻账）+ AGENTS「样张与
  测试供件」节（用户实拍库 3.7TB 登记）。
- **挂账移交**：M8-3+ 姐妹载体缺口（film/DRT/raw 载体同款 close 丢弃）/
  obs-1 白场幅度真图并排（omp 复核场已消 obs 记账——readout 语义边界
  登记）/ omp obs-3 迁移按钮 AXPress 配方建议并入 R6。

## 七、签核声明

SPEC-01..06 全部 Delivered 且验收形态逐项兑现（§一至§五 + 本节）；SC 门
= 全套三轮同值 + 修正批净轮零失败；红线族（封存面 15 项 / 哨兵四件 /
CC BY-SA 独立归属 / GPL 零拷贝 clean-room）三眼逐项核验在案。M8
milestone 正式 closed。签核时点 = 用户晨审过目（2026-10-26「晨审文件已
过目」）+ 全链验收闭环后；晨审可推翻惯例维持。
