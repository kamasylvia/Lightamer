---
phase: M5-3
slug: pano-merge
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-13
signed: 2026-10-13
milestone_closeout: M5
---

# Phase M5-3 — Validation（IOP-PANO-01 全景合成：自实现特征链 + 单焦 BA + 球面投影 + 分块羽化，100MP+ 输出；**兼 Milestone 5 收口正本**）

> 体例对齐 `phases/m5-2-mertens/M5-2-VALIDATION.md`（M5-1 同源）。
> **状态 = validated**（2026-10-13 签核批翻账；夜间全自动授权在案，
> 晨审可推翻；**兼 Milestone 5 收口正本**，`milestone_closeout: M5`，
> M2-11/M4-3 单文档收口先例）——C 档第 3 停已过：双重验收（config
> `dual_acceptance`）双路全 PASS——zcode 首验 **PASS / 0E+1M+3obs**
> （m-1 = SC 行法数锚 88/93→85/90，验收批当场更正）+ omp 串行二验
> **PASS / 0E+1M+3obs**（与首验零实质分歧；唯一 minor = FAIL toast
> 屏上像素未取证，映射语义三方闭合）。结论正本 =
> `M5-3-03-ACCEPTANCE.md` + `M5-3-03-ACCEPTANCE-OMP.md`。
> **SC 数字对账基线 = 全套 `--all` 单命令批准轮 `TOTAL 3631/24/0`**（
> M5-3-03 收口轮 2102s + zcode 验收独立复跑 2104s 双轮逐位互证；对账链
> **3539 + 43 + 44 + 5 = 3631 精确**——数字见 § Test Infrastructure）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / parity / 直启宿主 / 环境门探针 / 仓外 uv 结构对照） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL / ru_maxrss 8G 机检兜底） |
| **Full suite（phase 终轮）** | 全套 `--all` 批准轮 = **TOTAL 3631/24/0 exit 0**（M5-3-03 收口轮 2026-10-16，2102s：IOP 684/1/0〔453s/7731MB〕/ IOPParity 456/3/0〔775s/7803MB〕/ Layers 466/4/0〔1169MB〕/ Library 636/4/0〔617MB〕/ Sessions 279/4/0〔1626MB〕/ Export 353/4/0〔6455MB〕/ App 757/4/0〔366s/2832MB〕——全部 8G 门内零 MEMFAIL 零 crash；原始日志 = phase 根 `all-run-m53-03.log`） |
| **基线演变** | 3539/22/0（M5-2 修复后）→ +43（M5-3-01：Feature 9 / Match 9 / Camera 7 / MergeKind 8 / Golden 5 / Provenance 5）= 3582（01 后拼表）→ +44（M5-3-02 实测净增：Warp 8 / Gain 14 / Crop 10 / Leg 11 / Probe 2 − stub 退役 1，含验收波两枚回归法）= **3626**（enter-03 实测基线，IOP 684 亲证）→ +5（本批：PanoMergeUI 5）= **3631 精确**（skip 22→24：+2 探针 env 门；02-SUMMARY 记账口径 3623 与实测差 3 = 验收波增量，bundle 数字 GOAL-STATE 02 行为证） |
| **skip 24 身份** | 21 = M5-1 终验在册（12 env 探针/基准 + 6 模型资产缺席 + 3 fixture 缺席）+ 1 = `MertensFusionPerfProbeTests`（LIGHTAMER_PERF_PROBE 门）+ 2 = `PanoFusionPerfProbeTests`（同门，主探针 + footprint 诊断）——零静默跳过 |
| **GUI 证据** | `.work/gui-acceptance/m5-3/MANIFEST.md`（G6 Manual-Only 五行配方——三重叠样张合一 + crop 观感 + `_pano` 分账 + typed 失败 toast zh 面 + 重导入编辑链）；**行 1 前段（右键菜单第三项/sheet 四生效值/queued toast）+ 行 4 log 面（typed canonical 前缀）= omp 实机取证已回填**（`.work/gui-acceptance/m5-3/omp-g6/`）；余行待执行（需同视点扫幅样张）——「走查证据待回填」挂账形态，M3-4 先例 |
| **zh 对账** | 03 批 +8 键尾块纯插入（1643/1882 → **1651/1890**）——`zh-audit --check` PASS，删改行 0；历史键字节与顺序零触碰 |
| **在 flake/环境事件** | 03 批零（App 定向轮 + 全套轮一次通过）；01/02 批事件正本 = 各 SUMMARY/perf.md（M5-3-02 探针三连杀 + E-omp-1 修复批重测，均产线侧闭环） |

## REQUIREMENTS 对照（IOP-PANO-01；三列对账）

| SC | 判据 | 终态 |
|---|---|---|
| **IOP-PANO-01** | 全景合成——特征匹配对齐 + 相机参数优化 + 球面投影 + 分块羽化融合，输出 100MP+ 大图入正常编辑管线；v1 合成族之外的新合成模式 | **Delivered**：①自实现特征链（DoG 多尺度 + 128 维定向描述子 + knn Lowe 0.3 + RANSAC 3px/3000 + BFS 连通门，OQ-1；PanoRNG LCG 种子 121 单流确定性全握，OpenCV 零入仓，Lumen MIT 语义移植注记）②单焦 f + N×R LM BA（3N+1）+ 横向 wave correct（OQ-2；typed 收敛门 + N=2 退化守底）③全链 sRGB 编码 float32 + sRGB-tagged 32f TIFF 落盘 → M4-1 raster ingest（OQ-3；REAL 域判别在册）④200MP 画布帽 + 2..32 张 + 8G ru_maxrss 机检（OQ-4；196MP/8 源探针 RSS 5033-5653MB）⑤恒 inner_crop 直方图栈 + alpha 不写 + `_pano` 分账 + provenance details 三字段（OQ-5）⑥v1 全 CPU 零 `.metal`（OQ-6；NO GATE，越门 GPU 另立项）⑦`.pano` additive 第七 case + Session legacy 菜单第三项 + 简形 sheet 零控件（OQ-7；预览画布/参考帧手选/use_edits 挂 V2）——锚 = Pano*Tests 九文件 + PanoMergeKindTests + PanoMergeUITests（01+02+03 合计 85 法 + MergeUI 5 = 90 法；zcode 验收批 grep 复核更正——原 88/93 系 BUNDLE-MAP Gain/Leg 错记口径的陈旧算术，Gain 13/Leg 12 实数见 02-ACCEPTANCE m-a） |

## 七门全表（G1..G6 + 预算门；OQ 终验面落位）

| 门 | 判据 | 终态（锚） |
|---|---|---|
| **G1 确定性** | 双跑逐位 | ✅ 两级：数学核心函数级全链（01，`PanoGoldenTests`——keypoints/descriptors/homographies/solution/corrected bitPattern 逐位）+ **腿级闭环含落盘字节**（02，`testDoubleRunProductsBitIdentical`） |
| **G2 合成恢复** | 已知几何恢复带 | ✅ 01 交付（f 误差 0.27% ≤5% / gauge 锚定 R ≤0.095° ≤2° / inlier 率 100% ≥60%；钉门字面 = DECISIONS §2，禁调 golden 凑带程序合规） |
| **G3 分段 golden** | 五靶 | ✅ 02 交付（G3① sphericalMap 闭式解 12288 点 worst 2.44e-4 ≤1e-3 / ②羽化带 12% + 权重归一 + valid=weight>0 行对行 / ③增益合成方程组恢复 ~2.4e-8 ≤1e-6 / ④直方图栈 vs naive 五形状逐位 / ⑤boundedRois 不变式） |
| **G4 结构对照** | 非门值报告在册 | ✅ `evidence/opencv-structural-compare/report.md`（opencv 5.0.0 仓外 uv；七段段序一一对应 + 门值族同源 + 两处有意 Lumen 形分叉零意外缺口；Lumen 腿 OpenCV 段活体实跑 conf 2.9624/inliers 213——**非门值，无数值断言，不入 CI**） |
| **G5 红线机检** | 密封面零 diff + 六 kind 零回归 | ✅ phase 全窗（base 60aad61）十一项电池全绿：LightamerIOP/ + LightamerCore/ + `*.metal` 零 diff、腿体/FloatTIFFWriter/ProvenanceReplay 字节零、dependencies 零 diff、hardened 随机源门（含 `\.random\(`）零、runModal 零、LocalizationValue 插值禁形代码零、schemaVersion 零触、xcstrings 纯插入、UI 前两项 0 deletions——正本 = `g5-redline-checks.txt`（6699da3e） |
| **G6 走查** | MANIFEST 行配方 + 证据 | ⏳ 配方在册（五行 Manual-Only，`.work/gui-acceptance/m5-3/MANIFEST.md`）；**omp 实机部分回填**：行 1 前段（右键菜单 13 项亲见〔第三项落位与代码一致〕+ sheet AX 逐字〔零档位控件〕+ queued toast zh 逐字）+ 行 4 log 面（typed canonical 前缀三 instance 亲证）——`.work/gui-acceptance/m5-3/omp-g6/`（M5-2 G6 行 2/5 先例同形）；行 2/3/5 + 行 4 屏面（omp minor-1：FAIL toast 4s auto-clear 未取证，映射语义测试三臂 + AX 锚 + log 三方闭合）**挂账移交**——签核面如实登记 |
| **预算门** | ru_maxrss < 8G 机检 | ✅ 02 交付（196MP 画布 × 8 源：几何 184s / 融合+流写 1630.9/1634.1s（8/8 源修复批双跑 ±0.2%）/ 产物 3.1GB / **ru_maxrss 5033/5653MB**——零 MEMFAIL；正本 = `perf.md`「修复批重测轮」全源基线） |

## 三 Plan Per-Plan Map

| Plan | 交付 | 终态 commits | 测试增量 |
|---|---|---|---|
| M5-3-01 | 数学核心（特征/匹配/相机 typed stub + G1/G2 golden + 32 门 + provenance 镜像） | `3fa930a`/`96056d7`/`c6f020b`/`8ec142e`/`e591c89` + 收口 + 双验 `f5b56b7` | +43 |
| M5-3-02 | 生产腿（投影/增益/裁切/换腿 + FloatTIFFWriter + rowProvider 臂 + G3 五靶 + 预算探针 + E-omp-1 修复） | `ba2b2cc`/`1daad17`/`b6332ba`/`fa10355`/`613c8ad`/`940a658`/收口 + 双验修复批 `7ece3d3`/`60aad61` | +41 |
| M5-3-03 | UI 第三项/sheet/seam/enqueue + typed 三态 zh 面 + zh 8 键 + G4/G5/G6 + phase 收口 | `fe3fc5f`/`2d57bc37`/`6699da3e` + 本批 | +5 |

零红线域终态（phase 全窗 `git diff 43fe66d..HEAD` 两批机检互证 + 03 批
base 60aad61 终验）：`V50Order`/`Registry`/`HistoryStack`/`HistoryHash`/
`PipelineDocument`/sidecar schema/`LightamerIOP/` 全程零 diff；`*.metal`
新增 = 0（phase 全程纯 CPU，OQ-6）；零新 SPM（dependencies 0 diff）；
`runModal` 0 命中；`String.LocalizationValue("prefix_…")` 禁形代码 0 命中；
darktable GPL 零复制；OpenCV 零入仓（26 命中全为头注归属注记）；Lumen
MIT 语义移植带归属注记（Pano 文件头注）。

## 双重验收记录

| 波 | zcode 首验 | omp 二验 | 分歧 |
|---|---|---|---|
| M5-3-01 | **PASS / 0E+0M+3minor**（`M5-3-01-ACCEPTANCE.md`，2026-10-13 凌晨） | **PASS / 0E+0M**（`M5-3-01-ACCEPTANCE-OMP.md`） | 零实质分歧（置信度公式勘误两路独立复算同向） |
| M5-3-02 | **PASS / 1E+0M+5minor**（`M5-3-02-ACCEPTANCE.md`，2026-10-13 凌晨；1E = HEAD Export 编译破，当场修复 `7ece3d3`） | **FAIL / 1E + 4 minor → 修复批闭环 → OMP-REVERDICT: PASS**（`M5-3-02-ACCEPTANCE-OMP.md`；E-omp-1 band-span X 守卫漏 originX → `60aad61` 一行修复 + 非对称几何回归法 + 8/8 参与门双跑） | error 族闭环（对称 fixture 结构性盲区教训：几何守卫回归法必须非对称） |
| M5-3-03 | **PASS / 0E+1M+3obs**（`M5-3-03-ACCEPTANCE.md`，2026-10-13 晨；全套 `--all` 独立复跑 TOTAL 3631/24/0 exit 0 逐位闭合、零 MEMFAIL 零 crash；m-1 = SC 行法数锚 88/93→85/90 验收批当场更正；UI/typed 映射/zh 键族/G4〔probe 独立复跑逐位〕/G5 十一项/G6/commit 边界七面审计全绿） | **PASS / 0E+1M+3obs**（`M5-3-03-ACCEPTANCE-OMP.md`，串行二验；App 定向复跑 757/4/0 逐位〔含 peakRSS 2832MB〕+ 实机端到端取证〔菜单 13 项/sheet AX 逐字/queued toast/生产腿热栈/typed canonical log〕+ G4 探针仓外独立复跑 diff 空；minor-1 = FAIL toast 屏上像素未取证〔4s auto-clear，语义三方闭合，不阻断〕） | 零实质分歧（首验 m-1 + 三观察全复核同意；omp 新记 minor/obs 均批外或环境面） |

## 挂账汇编（单一移交清单）

- **移交用户侧 / 后续站**：
  - **G6 Manual-Only 余行走查（行 2/3/5 + 行 4 屏面）**——行 1 前段 +
    行 4 log 面 = omp 实机取证已回填（`.work/gui-acceptance/m5-3/omp-g6/`）；
    余行配方 = `.work/gui-acceptance/m5-3/MANIFEST.md`（执行 =
    用户/orchestrator 安排，需同视点扫幅样张，证据回填
    `M5-3-03-ACCEPTANCE.md`）。
  - **V2 挂账（OQ 裁决原文）**：预览合成画布 / 参考帧手选 / use_edits /
    per-image 焦距（畸变/tilt）/ multiband 融合；perf 观察项 = 融合段
    freed-but-resident footprint 爬升（+388MB/band @8/8 源，RSS 口径
    健康）与 Release `-O` 复测——越门 GPU 另立项（OQ-6
    决策面保持关闭）。手动 Y/M 增益微调不设（全自动面，research §3.7）。
  - **「全史瘦身手术」第二次触发 → 主会话**（SPEC 正本 =
    `research/HISTORY-SLIM-SURGERY-SPEC.md`；strip 集按 SPEC 重算
    **非空才动手**，零命中停手上报；filter-repo 后重 add remotes〔L070
    坑〕；push 收敛主会话）——原 M5-4 载荷其一；M5-3 证据链（三批
    SUMMARY/DECISIONS + perf.md + G4 evidence + G6 MANIFEST + g5
    transcript）已随本 VALIDATION 汇总落账。
- ~~**签核前置**：M5-3-03 双重验收（zcode → 串行 omp）结论落
  `M5-3-03-ACCEPTANCE.md` → 本文件翻 `status: validated` + `signed`~~
  ——**已闭环（2026-10-13 签核批：双路全 PASS，本件落签 + M5 milestone
  收口同批）**。

## M5 milestone 收口（本件兼收口正本，`milestone_closeout: M5`）

- **M5「追色与合成」closed（2026-10-13）**：M5-0..M5-4 全 5 phase
  闭环——M5-0 charter（2026-10-11）/ M5-1 TRACK（VALIDATION signed
  2026-10-13，终态 3477/21skip/0fail）/ M5-2 Mertens（signed 2026-10-15，
  拼表 3538/22/0 修复后基线 3539/22/0）/ M5-3 PANO（本件，全套批准轮
  3631/24/0）/ M5-4 收口（**由本件承载**——VALIDATION 汇总 = 三 phase
  VALIDATION + SC 三列对账已随各件落账，单文档收口 M2-11/M4-3 先例；
  手术第二次触发确认移交主会话，见下）。M5 Ledger 5/5；计划计数
  154/154（M5-3 三 plan 入账）。
- **M5 族 SC 终态**：TRACK-01..05 + MCP-09 研究项 C + IOP-HDR-06 +
  IOP-PANO-01 全 **Delivered**（REQUIREMENTS 翻账随各 phase VALIDATION
  批 + 本批收口注记）。
- **手术第二次触发（主会话执行）**：SPEC 正本 =
  `research/HISTORY-SLIM-SURGERY-SPEC.md`；执行前必须重算 strip 集
  （M3 收官预检曾证伪为 0；M4-0 证据分仓迁 ~2.2GB + M4/M5 批新增大对象
  历史版本后局面已变）——**非空才动手，零命中停手上报**；红线 =
  源码/Tests/Scripts 历史 blob 不剥 + filter-repo 后重 add remotes
  （L070 家族坑）+ push 收敛主会话。
- **挂账单一清单移交**（三 VALIDATION 汇编）：M5-1（Manual-Only 目测行
  + bake 生产耗时 + G2 交越界机制面 / o-2 收紧候选 / omp-03 面板追色
  观察项 / Tooltip SIGBUS 归 L057-B / MCP 多参考 V1 缺口 + preset 化）
  + M5-2（G6 余行 1/3/4 / Release 直启注入链环境债另案 / IOP·IOPParity
  贴线族观察项 / o-1..o-5 + o-omp1..omp4）+ M5-3（本件挂账汇编——G6
  余行 + V2 挂账 + perf 观察项）。

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权
  （M2-8/9/10/11、M4-3、M5-1/M5-2 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权**：夜间全自动批在案（合并批 = M5-3 签核 + M5 milestone
  收口一体；「开跑，不要停」先例链延续）。依授权，本 VALIDATION 由
  夜间批落盘签核（`[gsd] paused=false / auto=true` 全程未动）；用户
  晨审可推翻（推翻 = M5-3 签核与 M5 milestone closed 名分作废回退，
  已交付面与三波执行/验收证据不受影响；翻账批同 commit，推翻时随
  revert）。
- 签核 executor：ZCode 合并批 subagent（doc-only）——零源码 diff
  （本批 commit 全 docs/`.work` 路径亲核）。
- **呈报裁决点（禁静默）**：①G6 余行走查归属（用户/orchestrator 安排，
  不阻断签核——M3-4「走查证据待回填」先例）；②手术第二次 strip 集重算
  结果裁决（非空才动手，主会话执行）；③M5 milestone closed 名分
  （夜间授权链，晨审可推翻）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：IOP-PANO-01 翻 **Delivered** 终态注记 + TRACK 节头
  M5 收口追签注记。
- ROADMAP：M5-3 行 ✅ 闭环（全套 3631/24/0）+ §Milestone 5 块收口头 +
  文档头注更新。
- STATE：M5-3 complete + **M5 milestone closed**（M5 Ledger 5/5，计划
  154/154）+ current_phase = M5 closed → 手术第二次触发（主会话）。
- TODO：M5-3 条目落账 [x] + M5-4 收口形态注记 + M5 收官行。
- GOAL-STATE：置顶续接点 = **M5 closed → 「全史瘦身手术」第二次触发
  （主会话执行，strip 集重算非空才动手）**。
- 未 push；零源码 diff。

## 签核

- IOP-PANO-01 全项 Delivered（三列证据齐；数字对账 = 全套批准轮双轮
  亲证基线 3631/24/0）。
- `status: validated` + `nyquist_compliant: true` + `milestone_closeout: M5`。
- **M5 milestone（追色与合成）closed**：M5-0..M5-4 全 complete；M5 族
  SC 全 Delivered；挂账单一清单移交（M5-1 + M5-2 + M5-3 三件汇编）。
- 晨审裁决项：G6 余行归属 + 手术 strip 集裁决 + 签核推翻窗
  （夜间授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**
