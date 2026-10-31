---
phase: M9
slug: aimask-bwspectral-upright-smallpool
status: prepared
created: 2026-10-30
updated: 2026-10-31
note: 2026-10-30 首次落盘因复合命令缺陷为空文件（cat 短路截断），2026-10-31 本体补全并含站后修复链（R7/R8/R9）终账
---

# Phase M9 — Validation 预备（AI Mask 交互 + 光谱延展 + 几何 Upright + 小件池，2026-10-29/31）

> **性质**：站签核输入汇编（C 档停位交付物——用户过目后的独立 VALIDATION 批才执行签核本体）。本文件汇编四站终账 + 三眼验收链 + 深度缺陷闭环记录 + 站后修复链终账 + 路由池，不做新验证。

## 一、四站终账

| 站 | commits | ΔN | 全套锚 | 三眼 |
|---|---|---|---|---|
| M9-1 AI Mask 交互 parity | 5（refs #11） | +33（越带 +4） | 4328/33/0 | 路 1 `d78a539d` + 路 2 `aeaff367` + omp 全 PASS〔两实机面降级源读+直驱 7.17s 冷解/refine 0.02s 门内〕 |
| M9-2 黑白族+滤色镜 | 2+1 快修（refs #12） | +35（越带 +15） | 4363/34/0 | 双 PASS + omp PASS/0B+0M〔**w11 转录错**抓修——路 2 独立复算抓出〕 |
| M9-3 Upright 系 | 5+10 修复轮（refs #13） | +23→+5 | 4391/34/0 | 双 PASS〔**E-1 基准平面域错**抓修〕+ omp 四修复实机全验 |
| M9-4 小件池 | 9+4 修复轮（refs #14） | +35（越带 +20） | 4428/34/0 | 双 PASS〔**B-1 gamma 倒数语义错配**抓修〕+ omp PASS〔M-1′→快修 `d2dca6e7`〕 |
| **合计** | | **+126** | **4428/34/0**（站收口锚） | **omp 五场全 PASS** |

## 二、双路制度价值三连实证（本站特色战果）

三个深度缺陷全部由**独立第二眼**在路 1 全绿后翻出：
1. **M9-2 w11 转录错**——路 2 numpy 独立复算 vs 发表 factor 离群 0.89 stop（B-3 源页 dash 格臆读；W2-11 PDF 退役致原转录无第二源）；
2. **M9-3 E-1 基准平面域错**——路 2 行为级深审抓出旋转漏斗 displayTexture 尺寸误用（首拖 −8.6% 逐代累积，单测手值盲区）；
3. **M9-4 B-1 gamma 倒数语义错配**——路 2 迁移语义推演实锤升号观感反转 2.34 stops（测试锚同病：golden 验的是上游语义非我方冻结语义）。

## 三、结构演进登记

- **sidecar v12**（首例封存面豁免，bump 章程 + v8-v11 先例链）：paperGrade String verbatim + cameraFilter 双键 additive；
- **process v3**（双臂 + offset additive 判别子 + PipeCache run 级 fork resolved-arm discriminator + 折键负测三件硬门）+ **thumbnail guard M8-3 设计决定修订**（DECISIONS 单独申报非补漏）+ 9 未穿点全穿 + 豁免两件（SessionThumbnailRenderer/CullingView pristine）；
- 零新 SPM / 零 AI 模型引入 / bake-to-raster 合法偏离声明（charter）。

## 四、走查证据索引

- M9-1: `.work/gui-acceptance/m9-1/MANIFEST.md`（六项）+ `m9-1-aimask/omp-evidence/` 11 张
- M9-2: `m9-2-bwspectral/omp-evidence/` 19 张
- M9-3: `m9-3-upright/omp-evidence/` 12 张 + fix-acceptance/
- M9-4: `m9-4-smallpool/omp-evidence/` + MANIFEST

## 五、路由池（站后尾项，全部 minor/obs 级）

M9-3 N-1（导线端点 release 不提交——**已 R7 清偿**）/ N-2（flip 态 crop 重拟未换轴——**已 R7 清偿**）；M9-2 四 obs（grade 视口地板/HP5 note——**已 R7 清偿**/纸切残留键——**已 R7 清偿**/旧档 hash 伪影）；M9-1 三尾项（孤儿 png——**R7 裁定活引用不删已登记**/bootstrap 补走查/注释谓词名）；M9-4 判别子设防单点化建议；vpError 死代码；M2-6 纵深（DRT 峰值写死/方法切换不联动——R7 T3 裁定产品零 diff 以回归钉死）；时长维 obs（R9 RO-1）。

## 六、晨审可翻项汇总

M9-3 ashift charter 勘误（站点瘦身）/ sidecar v12 首例封存面 bump / thumbnail guard M8-3 设计修订 / XPan 三值自主增强 / 四站 OQ 采纳值族（31 条）/ 四站 ΔN 越带申报（+4/+15/+4/+20）/ Float 门 1e-3px 重定 / 病态第四防线。

## 七、站后修复链终账（收口后三批，2026-10-28/31）

| 批 | 内容 | 终值 | 三眼 |
|---|---|---|---|
| R7 | 导线端点 release 提交（比原建议加严：零 tick 防幻影）/ flip 态重拟换轴（镜像半边代数抵消证明独立验成立）/ M2-6 两项裁决产品零 diff（双向钉死回归代修）/ 卫生包（paste 活引用不删裁决等） | **4435/34/0** | 综合验收 PASS/0B+0M+1m + omp CONDITIONAL PASS（R7 本体签核） |
| R8 | **E-1′ 几何编辑即崩**（omp 实机抓出，`PixelPipe.swift:1676` negotiated ROI）——根因 = 09-23 `9d1f4fa9` composite 骨架 T4 潜伏（勘误：非 06-01），M9-3 crop 工具条首次用户可达 | **4438/34/0** | omp 复审 PASS〔原崩矩阵实机全存活〕；#16 CLOSED |
| R9 | **R8 M-1 表型推翻**（黑/NaN/持久三要素证伪——真凶 = L014 读回竞态第二次，fence 内移 18/0/0）+ **C200 Newton 梯 Y 撞墙真定罪**（路由 M8-3+，非产线改动）+ 5 契约测试 | **4443/34/0** | zcode review PASS/0B+0M+1m+2obs〔时长维缺口 RO-1 如实登记〕 |

**终态全套锚 = 4443/34/0**（本文件签核时的全套真值）。

## 八、C 档停位声明

四站三眼闭环 + 站后修复链三批闭环 + 本汇编（含真实终账）落盘 = M9 执行材料齐；**VALIDATION 签核本体 = 用户过目后的独立批**。本文件曾于 2026-10-30 以空文件误入库（复合命令缺陷，commit f783f1c3），2026-10-31 本体补全——勘误如实登记。
