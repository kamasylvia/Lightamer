---
phase: M5-2
slug: mertens-exposure-fusion
status: validated
nyquist_compliant: true
created: 2026-10-14
validated: 2026-10-14
signed: 2026-10-15
---

# Phase M5-2 — Validation（Mertens 曝光融合：免 CRF 快速 HDR 合并第二模式 + 多档 deghosting）

> 体例对齐 `phases/m5-1-track/M5-1-VALIDATION.md`（M2-11 同源）。**状态 =
> validated**（2026-10-15 签核批翻账；夜间全自动授权在案，晨审可推翻）——
> C 档第 3 停已过：双重验收（config `dual_acceptance`）双路全 PASS——
> zcode 首验 **PASS / 1E+0M+5obs**（E-1 已随验收批 `358abd8` 修复闭环）+
> omp 串行二验 **PASS / 0E+2M+4obs**（与首验零实质分歧；两 minor 均
> 批外已知域，不阻断）。结论正本 = `M5-2-02-ACCEPTANCE.md` +
> `M5-2-02-ACCEPTANCE-OMP.md`。
> **SC 数字对账基线 = 七 bundle 定向拼表 `TOTAL 3538/22/0`**（分割重跑
> 口径，M5-1 先例；单命令 `--all` 批准制未申请）。对账链
> **3477 + 39 + 22 = 3538 逐位闭合**；修复后基线 = **3539/22/0**。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / parity / 直启宿主 / 环境门探针 / `swiftc -O` 脚手架预算面 / uv 仓外结构对照） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL / ru_maxrss 8G 机检兜底） |
| **Full suite（phase 终轮）** | 七 bundle 定向拼表 = **3538 tests / 22 skip / 0 fail**（2026-10-14 收口轮逐 bundle：IOP 608/1/0〔7657MB〕/ IOPParity 451/3/0〔7738MB〕/ Layers 466/4/0 / Library 631/4/0 / Sessions 279/4/0 / Export 351/2/0〔6443MB〕/ App 752/4/0；全部 8G 门内零 MEMFAIL） |
| **基线演变** | 3477（M5-1 终验）→ +39（M5-2-01：Fusion 13 / MergeKind 14 / Golden 7 / Provenance 5）→ +22（本批：Leg 13 / RasterDomain 5 / MergeUI 3 / PerfProbe 1）= **3538 精确**（skip 21→22：+probe env 门） |
| **skip 22 身份** | 21 = M5-1 终验在册（12 env 探针/基准 + 6 模型资产缺席 + 3 fixture 缺席）+ 1 = `MertensFusionPerfProbeTests`（LIGHTAMER_PERF_PROBE 门，M2-5 惯例默认 skip；缺省面 `Export 1/1/0` 亲证）——零静默跳过 |
| **GUI 证据** | `.work/gui-acceptance/m5-2/MANIFEST.md`（G6 Manual-Only 五行配方——双算法各合一张 + deghost 三档对比 + `_mertens` 分账核 + 重导入观感；执行 = 用户/orchestrator 安排，证据回填 ACCEPTANCE——VALIDATION 允许「走查证据待回填」挂账形态，M3-4 先例） |
| **zh 对账** | 01 批 xcstrings 零改动（1638/1877）→ 本批 +5 键尾块纯插入（1643/1882）——`zh-audit --check` PASS，删改行 0 |
| **在 flake/环境事件** | 执行批三起全环境/探针侧（perf.md §事故）：staged 脏页 phys_footprint 压力（sync 回写修复）/ 被杀进程 defer 不跑残留 ENOSPC（L049 同族变体，runbook 化）/ Release 直启 WebP 动态链接不对称（工具链债，登记）——**零产线缺陷**；IOP 7657MB / IOPParity 7738MB 贴线族（±3% 方差注记口径）零 MEMFAIL |

## REQUIREMENTS 对照（IOP-HDR-06；三列对账）

| SC | 判据 | 终态 |
|---|---|---|
| **IOP-HDR-06** | Mertens 曝光融合——无 CRF 估计的快速 HDR 合并第二模式（含多档 deghosting），与 Robertson02（IOP-HDR-01）互为合并选项；输出 32f HDR 进 IOP-HDR-04 管线 | **Delivered**：①自实现 Mertens 2007 纯函数族（OQ-1，零 OpenCV 入仓，Lumen MIT 语义移植注记）+ 免 EV 预检（OQ-5：零拒绝面 + EV 只记不消费）②deghost 四态 off/low/medium/high 默认 medium（OQ-3；union 掩码 + 129 点置换 LUT 流式 in-pass）③生产腿 = band-outer halo 流式（网格对齐 + 共享掩码单通道 + 常驻 N 无关，OQ-6）④产物 = sRGB-tagged 32f 经 M4-1 raster ingest（OQ-2；两域判别钉）⑤UI 两菜单项并存 + `_mertens` 分账（OQ-4）⑥预算 = ru_maxrss 6248MB<8G 门 + 融合核 ~2.9min@100MP×5（预算内零 GPU 化触发）——锚 = `MertensFusionTests`/`MertensMergeKindTests`/`MertensFusionGoldenTests`/`MertensProvenanceTests`/`MertensLegTests`/`MertensRasterDomainTests`/`MertensMergeUITests`（47 法两批合计） |

## 六门全表（G1..G6；OQ-7 生效值落位）

| 门 | 判据 | 终态（锚） |
|---|---|---|
| **G1 bit-identity** | 双跑逐字节相等 | ✅ 两级：函数级双路径（01，`MertensFusionGoldenTests`）+ **腿级**双 enqueue 产物 TIFF 逐位（本批 `testDoubleRunProductBitIdentity`，medium 档全链含掩码） |
| **G2 Float64 孪生 parity** | p99.9 钉门 | ✅ 01 交付实测钉门 1e-6（6.954681e-07；硬上限 1e-5 在册） |
| **G3 合成语义靶** | 四靶 | ✅ 01 交付（双帧恒等 8.94e-08 / 连贯暗物体 mask≈1.0+置换 1.8e-7 / 过曝占比 0.0 / halo 带内逐位+负门）——本批驱动级多 band 逐位测试（`testBandOuterFuseMatchesWholeFrameGolden`）为 G3④ 的生产驱动面延伸 |
| **G4 Lumen 结构对照** | 非门值报告在册 | ✅ `evidence/lumen-structural-compare/report.md`（ρ=0.990 RGB/luma、max 0.105、mean 0.038、凸包 0.960/0.927；四节形态一致；偏差归因 = gray 系数/归一化层/层数未对齐——**非门值，无数值断言**，测试不入 CI） |
| **G5 共存零回归** | 既有路径零 diff | ✅ 红线机检（密封面/.metal/SPM/runHDRLeg 体全零 diff）+ 七 bundle 拼表零失败 + 既有 kind 快照/字节零漂移负测（01 vocabulary 钉 + 本批 additive-default 臂负测） |
| **G6 走查** | MANIFEST 行配方 + 证据 | ✅ 配方在册（五行 Manual-Only）/ 行 2（Mertens sheet + `_mertens` 分账）与行 5（重导入编辑链）**omp 实机取证已回填**（`.work/gui-acceptance/m5-2/omp-g6/` 五截图：menu/sheet/product/edit/wb + 产物 32f sRGB 三重机检）/ 行 1/3/4 待执行（挂账移交，见下） |

## 双重验收记录

| 波 | zcode 首验 | omp 二验 | 分歧 |
|---|---|---|---|
| M5-2-01 | **PASS / 0E+0M+4obs**（`M5-2-01-ACCEPTANCE.md`，2026-10-14） | **PASS / 0E+0M**（`M5-2-01-ACCEPTANCE-OMP.md`，2026-10-13——先于首验成文，零实质分歧） | 零实质分歧（首验批勘误「opencv 零代码符号命中」措辞 = plan 措辞矛盾非执行虚报） |
| M5-2-02 | **PASS / 1E+0M+5obs**（`M5-2-02-ACCEPTANCE.md`，2026-10-14/15；E-1 生产腿 LUT 缺 merge.py:145 全格兜底 → `358abd8` 单源化修复 + 回归法 + 定向 IOP 609/1/0 绿） | **PASS / 0E+2M+4obs**（`M5-2-02-ACCEPTANCE-OMP.md`，2026-10-12 串行；定向三 bundle 逐位闭合 + 实机端到端取证；两 minor 均**批外**：Library Import 收尾疑似卡住 → Library 另案 / L057-B 同族崩溃 → 专项行在案） | 零实质分歧（omp §5 五项逐项复核同意） |

## Per-Plan Map

| Plan | 交付 | 终态 commits | 测试增量 |
|---|---|---|---|
| M5-2-01 | 纯函数族 + MergeKind/params/provenance additive + 免 EV 预检 + G1/G2/G3 golden + G5 三 bundle 复验 | `075114a`/`fc66033`/`288467a`/`a141814`/`06a3b9c` + 验收 `7d9708f` | +39 |
| M5-2-02 | 生产腿（流式/置换/域判别）+ sRGB 落盘 + UI 两菜单项 + 预算机检 + G4/G6 收口 | `826fa5b`/`5afa952`/`45bcfe4`/`e52bd6f`/本批 + 验收 `358abd8`（E-1 LUT 兜底修复，zcode 验收批） | +22（验收批 +1 回归法 = 后续基线 3539） |

零红线域终态（phase 全窗 `git diff 0f7e10b..HEAD` 两批机检互证）：`V50Order`/
`Registry`/`HistoryStack`/`HistoryHash`/`PipelineDocument`/sidecar schema/
`LightamerIOP/` 全程零 diff；`*.metal` 新增 = 0（phase 全程纯 CPU，OQ-6）；
零新 SPM（dependencies 0 diff）；`runModal` 0 命中；
`String.LocalizationValue("prefix_…")` 禁形 0 命中；darktable/Lumen/Alcedo
GPL 零复制（Lumen MIT 语义移植带归属注记，`MertensFusion.swift` 头注）。

## 挂账汇编（单一移交清单）

- **移交 M5-4 / 用户侧**：
  - **G6 Manual-Only 余下走查行（1/3/4）**——行 2/5 已由 omp 实机取证回填
    （`.work/gui-acceptance/m5-2/omp-g6/`）；行 1（Robertson02 对照合并）/
    行 3（deghost 三档对比，需 enqueue 参数通道 v1 无面板）/ 行 4（`_hdr`
    并存分账）证据回填 ACCEPTANCE——配方
    `.work/gui-acceptance/m5-2/MANIFEST.md`。
  - **M5-4 = VALIDATION 汇总 + 瘦身手术第二次触发**（SPEC 正本：strip 集
    按 SPEC 重算非空才动手）——M5-2 证据链（两批 SUMMARY/DECISIONS +
    perf.md + G4 evidence + G6 MANIFEST）就绪待汇总。
- **环境债（非产线）**：Release 直启注入链（WebP 包 framework 动态链接
  不对称 + 未 embed；D-09-04-D9 配方不达——framework 未产出为根因）——
  perf.md §事故 4 登记，另案。
- **观察项**：IOP/IOPParity 贴线族 RSS（7657/7738MB，±3% 方差口径）——
  连续 MEMFAIL 先查重测顺序漂移（AGENTS 在案口径，本批零 MEMFAIL）。
