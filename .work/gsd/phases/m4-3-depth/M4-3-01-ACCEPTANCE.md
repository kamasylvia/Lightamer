# M4-3-01 ACCEPTANCE

> 双重验收编排（config `dual_acceptance = true`）。本文件由验收环节落账。
> **硬约束：两次验收严禁并发（computer-use 单实例会打架），严格串行。**

## 验收输入

- plan = `M4-3-01-PLAN.md`（AC 13 条总表）
- 执行 = `M4-3-01-SUMMARY.md` + `M4-3-01-DECISIONS.md`（§1..§9，含 m1..m7 回勾）
- checker = `M4-3-CHECKER.md`（PASS / 0E+7M+6obs，处方执行批已采纳）
- 批次 = `d2e234a..0355e65` 十提交（T1..T8 + fix(test) + SHA 勘误）+ 验收批小修 `57596d3`

## 第一路：zcode subagent 独立验收

- 结论：**PASS / 0 error + 2 minor（m-a 已修 `57596d3`；m-b 以验收批复跑补证并勘误账面）**
- 日期：2026-10-10/11（夜间独立验收轮）
- 验收方式 = 亲跑 + 独立复算 + 机检，非 SUMMARY 转述。

### 1. 定向亲跑（test-direct.sh 直启，零 MEMFAIL）

| bundle | 申报 | 本验收亲跑 | 判定 |
|---|---|---|---|
| Layers | 411/3/0 | **411/3/0**（167s，peakRSS 1163MB） | 逐位 ✓（3 skip = 基线 AIMaskDeterminism/AIMaskSemantic/GradeEnvelopePerfProbe，零 depth skip） |
| Library | 626/4/0 | **626/4/0**（75s，610MB） | 逐位 ✓（4 skip 全基线） |
| App（模型**缺席**态） | 711/4/0 | **711/4/0**（359s，2832MB） | 逐位 ✓，但 4 skip = 3 golden（"depth package absent"）+ 1 probe → 见 m-b |
| App（模型**在场**净树终值轮） | （申报未单列） | **711/2/0**（372s，2832MB） | golden 3/3 真跑全绿 + skip = probe + absent-assets（与申报注记的 skip 身份逐字吻合） |

- 模型安装 = 按 DECISIONS §5 命令从本地已验 SHA 的 zip 回装（验收机原安装位缺席）。
- golden 三法模型在场实测：`testPrecisionGateAgainstF32Reference` / `testDeterminismDoubleRunByteIdentical`（6.9s 双跑）/ `testWorkerLoopEndToEndDepthRoundTrip` 全 passed。
- perf 探针独立亲跑（`LIGHTAMER_PERF_PROBE=1` 单类）：all **40.8ms**（申报 45.0，同带轮方差）/ cpuAndGPU 55.6 / cpuOnly 67.7 / 端到端 **234.1ms**——与 `perf.md` 一致，`.all` 显著快于 `.cpuOnly` = ANE 在档，无 >10× 超带项。
- **挂账 #6 发作与因果闭环（非本批缺陷）**：模型在场首轮 App 711/2/**1**，唯一 fail = `RasterEditFaceTests.testRestoreWinsOverDerive`（DrtRecord 面失配）——孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（mtime 23:02:40 = 本验收前一轮 Layers 基线族 debounce 写入）在位所致（M4-1 挂账 #6 已知形态，M4-2-01 验收同款）。删孤儿 → 单类重跑 **7/0/0**（8s）因果闭环 → 净树全 bundle 终值轮 **711/2/0**。归 M4-1 所有不阻塞本批。

### 2. 四段管线数学审计（独立复算，灵魂节）

- **Lumen 锚亲核**：`lumen/selection.py:71-74` 逐行命中（`np.percentile([10,95]` / `(r-.48)/.22` / smoothstep `p·p·(3−2p)`）；`:67-68` isfinite 守卫；`auto_masks.py:56,75` document token 比对、`:77` 0.0003 守卫；`selection.py:59` 注释 "larger values are nearer" = 近/远极性正本 → 产线 higher-α=nearer 同向。
- **numpy 12 锚独立复算**（uv/numpy 独立脚本，非转抄测试值）：[1..10] q10=1.9/q95=9.55、[10,20,30,40] q10=13.0/q95=38.5、[5,5,5,5,9,9,9] q10=5.0/q95=9.0、[0,10] q25=2.5/q50=5.0、[7] q10=q95=7.0——**10/10 数值锚逐位命中**测试硬编码值 + empty→nil。
- **两级靶复算**：far 0.2 (89.75%) + near 0.9 (420px=10.25%，m6 ≥10% 门) → low=0.2/high=0.9 → 近 α=1.000000 / 远 α=0.000000 精确命中。
- **守卫 (b) 解析事实复证**：过守卫 (a) 的平面 P(v≥p95)≥5% → 该批像素 α=1 → coverage≥5% ≫ 3e-4 → 默认参数下 (b) = NaN backstop only（DECISIONS §3 的数学主张独立成立）。
- **斜坡 golden 复算**：0…1 ramp n=1000 → low=0.1/high=0.95；带内 (0.48,0.70) 全软、带外饱和 0/1、全程单调——与测试三断言同构。
- **产线源码同构性**：`DepthMaskPipeline.swift` 与 Lumen 公式逐行同构（1e-6 地板保留 = checker o3 死代码注记在案）；测试头注 L048 容差推导（smoothstep 斜率上界 + F32 地板 → 1e-4）在册。

### 3. worker 第三腿审计

- **family 判别式**：`ModelAssetManifest.family` 派生单源（clip 先判优先序 doc comment 在册 = checker o2 兑现）；`testFamilyExhaustiveOverAllProfiles` 六 profile 穷举（clip 2 / enhancement 3 / depth 1）+ 优先序断言 + `==` 新行折叠断言亲读。
- **三腿分派**：`AIWorkerMain` `switch manifest.family` 三臂——clip/enhancement 腿体保留、`.depth` 新 `openDepthLeg`；资产缺席 = 无 culprit profile 级、units 级加载失败 = 带 culprit（降档记账输入）亲读。
- **crash-safe**：crash hook 在资产解析**之前**（`Darwin.exit(9)` DEBUG）→ depth profile 免费生效零改动亲证；`DepthWorkerLegTests` 三法（crash 注入链 CompatRecord+respawn+降档 / envelope PATH 往返零新字段 / 资产缺席 typed 无 culprit）+ 模型在场轮 absent-assets 面 skip 语义正确。
- **协议零破坏**：`git diff d2e234a..HEAD -- AIWorkerProtocol.swift` **零命中**亲跑；inPath/outPath 既有 PATH 通道字段复用（`forwardDepthRun` 只读两字段，run 级错误帧 worker 健康不耗链）。
- **m3 isfinite**：`DepthSession.floatPlane` half/F32 双格式逐行读 + nonFinite 计数 → `nonFiniteOutput` typed（run 级 → inferenceFailed 归因）亲读。
- **HEADLESS**：AIWorkerDepth imports = Foundation/CoreML/ImageIO/LightamerCore 四项白名单（m7），零 SwiftUI/AppKit。
- **AC#3 grep 门亲跑**：App target 产线 `MLModel(` 构造点仅 AIWorkerEnhancement + AIWorkerDepth 两文件（CLIP 腿经 Core InProcessMLModelRunner）——Core SemanticEngine 既有面零新增（本批 Core 零 diff 已证）。

### 4. 资产合规审计（红线节）

- **模型字节不入 git**：`git ls-files` + 全批 diff 双机检零 `.mlpackage`/`.zip`/`weight.bin`/`.mlmodel` 命中；产物位在 `~/Library/Caches/LightamerModels/depth/`（仓外）。
- **digest 亲算**：磁盘 zip `shasum -a 256` = `3824a48c6d17d2c5d76607bd0c0dea8427f062b7b014fa916d54e2aac91d9da9`、45,759,882 B——与在库 `ModelAssetDigests.generated.swift` sentinel 值**逐位一致**。
- **远端 Release 亲下载复证**（§8 走查独立复证）：`gh release download ai-models-v1` → 下载件 SHA-256 与 byteCount 与在库 digest **逐位一致**（45,759,882 B）；`gh release view` 资产在册。
- **MANIFEST.sha256 逐行亲算**：zip 解包后 5 行（LICENSE/NOTICE/model.mlmodel/weight.bin/Manifest.json）全行重算 **5/5 OK**；zip 内容 6 条目与 DECISIONS §1 清单一致。
- **Apache-2.0 全链**：zip 内 LICENSE = Apache 全文；NOTICE 署名三行（Depth Anything authors HKU+TikTok / Apple Inc. / 两 HF URL，均 Apache-2.0）；manifest `licenseName == "Apache-2.0"`。
- **digest fail-closed**：其余 release profile digest 恒 nil（jina/realESRGAN/drunet 三行亲读）+ `ModelAssetStore` 状态机 `.digestUnpublished` 拒下载 + 三新 Store 测试（promotes/fail-closed/checksum-mismatch-deletes-tmp）在册。
- **确定性打包**：build 脚本 fixed mtime + `zip -X` + 排序条目（DECISIONS §1 两次构建逐字节一致申报；本验收以本地 zip == 远端 zip 逐位一致旁证可复现性）。
- **零新 SPM**：Project.swift 依赖面 diff 零 package 行亲跑。

### 5. 红线零 diff 自证（T8 清单亲跑）

`git diff d2e234a..HEAD` 零命中亲证：Sidecar/、Aces2Kernels.metal、MaskEdgeKernels.metal、DrtRecord、HistoryStack、HistoryHash、LayerEditingState、NodeGraphCommand、**AIWorkerProtocol**、V50Order、Registry（LightamerIOP）、Export/（六格式矩阵全目录）——全零；全 `.metal` 零变更；zh-audit `--check` PASS（1855 catalog = 1848+7）；xcstrings diff 实际删除行 = 0（尾块纯插入）。

### 6. m1..m7 抽验（4 项亲核）

| 项 | 抽验结果 |
|---|---|
| m2 | ✓ DepthSession init 从 manifest 取 (inputSize, inputShortEdge)；`DepthMaskService.readDepthPlane` 调用点同源（expectedWidth/Height = manifest 两字段）；392 勘误全链落实 |
| m3 | ✓ floatPlane nonFiniteOutput → typed（上文 §3） |
| m5 | ✓ family 穷举测试 + depth open 无 facts（模型在场轮 absent-assets skip 行亲读） |
| m7 | ✓ HEADLESS 白名单四项 + AC#3 grep 门亲跑（上文 §3） |

### 7. 逐 commit 边界（10 提交）

T1 `814fc97`（6 文件，catalog+digest+脚本+两测试）/ T2 `b7f2598`（管线+AIMaskTypes+8 法）/ T3 `22872ea`（worker 三文件+Leg 测试+LCR 翻面）/ T4 `97e2d67`（service+AIMaskEditing+8 法）/ T5 `98de649`（toolbar+LightamerApp 注入【DECISIONS §4 申报】+xcstrings+visual 折叠）/ T6 `ec4894f`（golden 三件套+fixtures 4,061,160B+3 法）/ T7 `b615636`（探针+perf.md）/ T8 `dda9433`+`bfdeff9`（fix(test) tempFixtureCopy）+`0355e65`（SHA 勘误）——全部 Conventional Commits 全英文、front-matter 为界、无范围外 hunk。偏差申报六条（392 勘误/golden RAW→合成/守卫(b) 不可达/LightamerApp 增补/resolver 勘误/T8 三提交形态）逐条合理有据。

### 8. Minor（2 项）

- **m-a（LESSONS 撞号，已修）**：深度批污染教训误编 L072——与 M3 收官手术批 L072（2026-10-10）撞号，LESSONS.md 双 L072 并存，四处引用（SUMMARY/DECISIONS §7/GOAL-STATE/TODO）指向歧义。**修复 `57596d3`**：重编号 **L074** + 四处引用同批同步（docs-only，零测试影响）。
- **m-b（终验 App 711/4/0 的 skip 态账面精度）**：XCTest `Executed` 计数**含 skip**——模型在场（711/2/0，skip=probe+absent-assets）与缺席（711/4/0，skip=3 golden+1 probe）两态数字同形。执行批终验登记的 711/4/0 实为**模型缺席态**轮，其旁注「2 skip = probe env 门 + absent-assets 门」描述的是装包态身份，与该轮实况不符（skip 身份由本验收日志取证）。交付面无缺陷（golden 门值在 T6 排查期真跑过、本验收装包复跑 3/3 全绿独立复证），仅账面口径需本注记勘误——SUMMARY §3 App 行已由验收批补注。

## 第二路：omp 二次验收（串行，第一路 PASS 后）

- 结论：**PASS / 0 error + 2 minor（o-1 账面口径沿用 m-b 已勘误；o-2 复算余量注记，无代码影响）**
- 证据（正本 = `M4-3-01-ACCEPTANCE-OMP.md`）：定向复跑 Layers **411/3/0**（180s，1090MB）+ Library **626/4/0**（79s，611MB）逐位零 MEMFAIL；numpy 8/8 + **Swift 原文探针独立复算** 8/8 容差内；两级靶精确算术（Fraction）+ 守卫 (b) 严格论证加强；digest 亲算 + MANIFEST.sha256 **5/5 OK** + 远端 Release size 交叉；读码抽查（family 单源/三腿分派/isfinite/可容性/提交边界）+ 红线零 diff + zh-audit `--check` PASS 复证；GUI 走查行（MANIFEST A-G）= Manual-Only，代码面读码代证，实机走查留用户侧
- 日期：2026-10-10
- 分歧：无实质分歧（o-2 = 新增测试口径注记；首验「逐位命中」措辞勘误为「容差内通过」，实质成立）

## FAIL 回注

（两路任一 FAIL → 修复批后重走；回注条目在此登记。两路均无 FAIL 项——m-a 已修 `57596d3`、m-b 勘误注记随本验收落账、omp o-2 注记不阻塞。）
