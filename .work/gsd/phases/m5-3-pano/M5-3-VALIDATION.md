---
phase: M5-3
slug: pano-merge
status: drafted
nyquist_compliant: true
created: 2026-10-16
validated: ""
signed: ""
---

# Phase M5-3 — Validation（IOP-PANO-01 全景合成：自实现特征链 + 单焦 BA + 球面投影 + 分块羽化，100MP+ 输出）

> 体例对齐 `phases/m5-2-mertens/M5-2-VALIDATION.md`（M5-1 同源）。
> **状态 = drafted（C 档第 3 门：签核待 verify-work 结论给用户过目——
> 本文件由 M5-3-03 执行批成文，七门全表 + 对账链已闭合；双重验收
> （config `dual_acceptance`）待派：zcode 独立验收 → PASS 后串行 omp
> 二验，严禁并发；结论落 `M5-3-03-ACCEPTANCE.md` 后翻账签核。）**
> **SC 数字对账基线 = 七 bundle 定向拼表**（M5-1/M5-2 先例口径；
> 本 phase 全套 `--all` 单命令批准轮 = M5-3-03 收口轮——数字见 §
> Test Infrastructure）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / parity / 直启宿主 / 环境门探针 / 仓外 uv 结构对照） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL / ru_maxrss 8G 机检兜底） |
| **Full suite（phase 终轮）** | 全套 `--all` 批准轮 = **TOTAL 3631/24/0 exit 0**（M5-3-03 收口轮 2026-10-16，2102s：IOP 684/1/0〔453s/7731MB〕/ IOPParity 456/3/0〔775s/7803MB〕/ Layers 466/4/0〔1169MB〕/ Library 636/4/0〔617MB〕/ Sessions 279/4/0〔1626MB〕/ Export 353/4/0〔6455MB〕/ App 757/4/0〔366s/2832MB〕——全部 8G 门内零 MEMFAIL 零 crash；原始日志 = phase 根 `all-run-m53-03.log`） |
| **基线演变** | 3539/22/0（M5-2 修复后）→ +43（M5-3-01：Feature 9 / Match 9 / Camera 7 / MergeKind 8 / Golden 5 / Provenance 5）= 3582（01 后拼表）→ +44（M5-3-02 实测净增：Warp 8 / Gain 14 / Crop 10 / Leg 11 / Probe 2 − stub 退役 1，含验收波两枚回归法）= **3626**（enter-03 实测基线，IOP 684 亲证）→ +5（本批：PanoMergeUI 5）= **3631 精确**（skip 22→24：+2 探针 env 门；02-SUMMARY 记账口径 3623 与实测差 3 = 验收波增量，bundle 数字 GOAL-STATE 02 行为证） |
| **skip 24 身份** | 21 = M5-1 终验在册（12 env 探针/基准 + 6 模型资产缺席 + 3 fixture 缺席）+ 1 = `MertensFusionPerfProbeTests`（LIGHTAMER_PERF_PROBE 门）+ 2 = `PanoFusionPerfProbeTests`（同门，主探针 + footprint 诊断）——零静默跳过 |
| **GUI 证据** | `.work/gui-acceptance/m5-3/MANIFEST.md`（G6 Manual-Only 五行配方——三重叠样张合一 + crop 观感 + `_pano` 分账 + typed 失败 toast zh 面 + 重导入编辑链；执行 = 用户/orchestrator 安排，证据回填 ACCEPTANCE——「走查证据待回填」挂账形态，M3-4 先例） |
| **zh 对账** | 03 批 +8 键尾块纯插入（1643/1882 → **1651/1890**）——`zh-audit --check` PASS，删改行 0；历史键字节与顺序零触碰 |
| **在 flake/环境事件** | 03 批零（App 定向轮 + 全套轮一次通过）；01/02 批事件正本 = 各 SUMMARY/perf.md（M5-3-02 探针三连杀 + E-omp-1 修复批重测，均产线侧闭环） |

## REQUIREMENTS 对照（IOP-PANO-01；三列对账）

| SC | 判据 | 终态 |
|---|---|---|
| **IOP-PANO-01** | 全景合成——特征匹配对齐 + 相机参数优化 + 球面投影 + 分块羽化融合，输出 100MP+ 大图入正常编辑管线；v1 合成族之外的新合成模式 | **Delivered**：①自实现特征链（DoG 多尺度 + 128 维定向描述子 + knn Lowe 0.3 + RANSAC 3px/3000 + BFS 连通门，OQ-1；PanoRNG LCG 种子 121 单流确定性全握，OpenCV 零入仓，Lumen MIT 语义移植注记）②单焦 f + N×R LM BA（3N+1）+ 横向 wave correct（OQ-2；typed 收敛门 + N=2 退化守底）③全链 sRGB 编码 float32 + sRGB-tagged 32f TIFF 落盘 → M4-1 raster ingest（OQ-3；REAL 域判别在册）④200MP 画布帽 + 2..32 张 + 8G ru_maxrss 机检（OQ-4；196MP/8 源探针 RSS 5033-5653MB）⑤恒 inner_crop 直方图栈 + alpha 不写 + `_pano` 分账 + provenance details 三字段（OQ-5）⑥v1 全 CPU 零 `.metal`（OQ-6；NO GATE，越门 GPU 另立项）⑦`.pano` additive 第七 case + Session legacy 菜单第三项 + 简形 sheet 零控件（OQ-7；预览画布/参考帧手选/use_edits 挂 V2）——锚 = Pano*Tests 九文件 + PanoMergeKindTests + PanoMergeUITests（01+02+03 合计 88 法 + MergeUI 5 = 93 法） |

## 七门全表（G1..G6 + 预算门；OQ 终验面落位）

| 门 | 判据 | 终态（锚） |
|---|---|---|
| **G1 确定性** | 双跑逐位 | ✅ 两级：数学核心函数级全链（01，`PanoGoldenTests`——keypoints/descriptors/homographies/solution/corrected bitPattern 逐位）+ **腿级闭环含落盘字节**（02，`testDoubleRunProductsBitIdentical`） |
| **G2 合成恢复** | 已知几何恢复带 | ✅ 01 交付（f 误差 0.27% ≤5% / gauge 锚定 R ≤0.095° ≤2° / inlier 率 100% ≥60%；钉门字面 = DECISIONS §2，禁调 golden 凑带程序合规） |
| **G3 分段 golden** | 五靶 | ✅ 02 交付（G3① sphericalMap 闭式解 12288 点 worst 2.44e-4 ≤1e-3 / ②羽化带 12% + 权重归一 + valid=weight>0 行对行 / ③增益合成方程组恢复 ~2.4e-8 ≤1e-6 / ④直方图栈 vs naive 五形状逐位 / ⑤boundedRois 不变式） |
| **G4 结构对照** | 非门值报告在册 | ✅ `evidence/opencv-structural-compare/report.md`（opencv 5.0.0 仓外 uv；七段段序一一对应 + 门值族同源 + 两处有意 Lumen 形分叉零意外缺口；Lumen 腿 OpenCV 段活体实跑 conf 2.9624/inliers 213——**非门值，无数值断言，不入 CI**） |
| **G5 红线机检** | 密封面零 diff + 六 kind 零回归 | ✅ phase 全窗（base 60aad61）十一项电池全绿：LightamerIOP/ + LightamerCore/ + `*.metal` 零 diff、腿体/FloatTIFFWriter/ProvenanceReplay 字节零、dependencies 零 diff、hardened 随机源门（含 `\.random\(`）零、runModal 零、LocalizationValue 插值禁形代码零、schemaVersion 零触、xcstrings 纯插入、UI 前两项 0 deletions——正本 = `g5-redline-checks.txt`（6699da3e） |
| **G6 走查** | MANIFEST 行配方 + 证据 | ⏳ 配方在册（五行 Manual-Only，`.work/gui-acceptance/m5-3/MANIFEST.md`）；执行待排（挂账移交——签核面如实登记；omp 实机取证回填可选，M5-2 G6 行 2/5 先例） |
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
| M5-3-03 | 待派 | 待派（**串行**，严禁并发） | —— |

## 挂账汇编（单一移交清单）

- **移交 M5-4 / 用户侧**：
  - **G6 Manual-Only 五行走查**（`.work/gui-acceptance/m5-3/MANIFEST.md`
    配方；执行 = 用户/orchestrator 安排，证据回填
    `M5-3-03-ACCEPTANCE.md`）。
  - **V2 挂账（OQ 裁决原文）**：预览合成画布 / 参考帧手选 / use_edits /
    per-image 焦距（畸变/tilt）/ multiband 融合；perf 观察项 = 融合段
    freed-but-resident footprint 爬升（+388MB/band @8/8 源，RSS 口径
    健康）与 Release `-O` 复测（M5-4 可选项）——越门 GPU 另立项（OQ-6
    决策面保持关闭）。手动 Y/M 增益微调不设（全自动面，research §3.7）。
  - **M5-4 = M5 VALIDATION 汇总 + 「全史瘦身手术」第二次触发**（SPEC
    正本 = `research/HISTORY-SLIM-SURGERY-SPEC.md`；strip 集按 SPEC 重算
    **非空才动手**，零命中停手上报；filter-repo 后重 add remotes〔L070
    坑〕；push 收敛主会话）——M5-3 证据链（三批 SUMMARY/DECISIONS +
    perf.md + G4 evidence + G6 MANIFEST + g5 transcript）就绪待汇总。
- **签核前置**：M5-3-03 双重验收（zcode → 串行 omp）结论落
  `M5-3-03-ACCEPTANCE.md` → 本文件翻 `status: validated` + `signed`。
