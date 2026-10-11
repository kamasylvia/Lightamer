---
phase: m5-2
plan: "M5-2-01"
title: "Mertens 融合 Core 底座批（wave 1 = RESEARCH §6 plan-01）——MertensFusion 纯函数族（display 编码/三因子权重/高斯+拉普拉斯金字塔条带核/整帧参考实现/deghost 分位映射+置换 LUT/层数自适应+halo 公式/Float64 孪生）+ MergeKind.hdrMertens additive（provenanceKind/defaultTag/stepTotal/dispatch 臂）+ MergeParams additive 双字段 + ProvenanceReplay 词汇镜像 + 免 EV 预检 + G1/G2/G3/G5 golden"
wave: 1
depends_on: []
autonomous: true
requirements: ["IOP-HDR-06"]
estimated_tests: "+42..52"
test_bundles: [IOP, IOPParity, Library]
files_modified:
  - LightamerCore/Sources/Stack/MertensFusion.swift     # 新建：纯函数族——display 编码（DrtEotf.srgbPiecewise 复用，KD-1）/三因子权重/灰度/分位亮度映射/deghost 掩码与羽化/置换 LUT/金字塔条带核（FocusStackMerge reduce/expand 复用）/fuseStrip/整帧参考融合/adaptiveLevels/haloRows/Float64 孪生；文件头 MIT 归属注记（Lumen 档表+置换语义）
  - LightamerCore/Sources/Stack/StackMergeService.swift # 修改：MergeKind + case hdrMertens = "hdr-merge-mertens"（provenanceKind/defaultTag("mertens")/stepTotal 4N+3 三 switch 补臂）+ MergeParams additive 双 optional（mertensDeghost: String? / mertensLevels: Int?，synthesized encodeIfPresent）+ runProductionMerge dispatch 臂 → runMertensLeg（本 plan = typed stub，生产腿 = M5-2-02，KD-4）
  - LightamerCore/Sources/Stack/ProvenanceReplay.swift  # 修改：SidecarProvenance.Kind + 同名 case（raw 值恒等镜像）+ mertensAlgorithmName = "mertens-exposure-fusion" / mertensImplementationVersion = "1" 常量
  - LightamerCore/Sources/Stack/ExifPrecheck.swift      # 修改：mertensVerdicts 纯函数（免 EV：全 warning 不拒绝 + EV 只组不消费，KD-6）
  - Tests/LightamerTests/MertensFusionTests.swift       # 新建（IOP/Core 级）：编码 round-trip/权重族/分位映射/deghost 掩码/置换 LUT/adaptiveLevels 表/haloRows 表/条带核
  - Tests/LightamerTests/MertensFusionGoldenTests.swift # 新建（IOPP 级，*Golden* 域模式）：G1 双跑 bit-identity + G2 Float64 孪生 parity（实测收窄钉门）+ G3 四靶
  - Tests/LightamerTests/MertensMergeKindTests.swift    # 新建（IOP/Core 级）：kind 词汇/tag/stepTotal/params 语义（nil→medium）/dispatch stub typed 形
  - Tests/LightamerTests/MertensProvenanceTests.swift   # 新建（LIB/Core 级，ProvenanceV4Tests 先例）：Kind 镜像/旧 sidecar 逐字节零漂移/算法名常量
  - Project.swift                                       # 修改：新测试文件登记对应 target 数组（显式清单无 glob）+ tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：四新测试文件增行登记（E2 纪律，随各自任务 commit）
  - .work/gsd/phases/m5-2-mertens/M5-2-01-SUMMARY.md    # 新建（T5）
  - .work/gsd/phases/m5-2-mertens/M5-2-01-DECISIONS.md  # 新建（T5）
  - .work/gsd/phases/m5-2-mertens/M5-2-01-ACCEPTANCE.md # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/GOAL-STATE.md                                 # 修改：续接点
  - .work/TODO.md                                       # 修改：M5-2 条目
  - .work/LESSONS.md                                    # 如踩坑
---

# Plan M5-2-01 — Mertens 融合 Core 底座批（wave 1：纯函数族 → 类型 additive → 免 EV 预检 → golden 四门）

> **性质**：M5-2 两 plan 之首。本批交付 Mertens 曝光融合的**全部数学面与类型
> additive 面**（Core `Stack/` 域），但**不切生产入口**——`.hdrMertens` 的
> dispatch 臂落 typed stub（照 M4-1-01「路由不切」先例：新腿测试直驱，生产腿
> + band-outer halo 流式 + UI = M5-2-02）。本批唯一编译必需的既有面改动 =
> `MergeKind` 穷举 switch 四处补臂（provenanceKind/defaultTag/stepTotal/
> runProductionMerge），全部 additive、既有 kind 行为零变化（G5 钉死）。
> 规格正本 = `RESEARCH-NOTES.md`（merge.py file:line 亲读）；裁决正本 =
> `M5-2-CONTEXT.md` 裁决记录（OQ-1..7 全按推荐，2026-10-11 用户回批）。
>
> **基线**：**3477/21/0**（M5-1-VALIDATION 2026-10-13 终验
> `TOTAL|3477/21/0|` 分割重跑拼表亲证值。派发指令所引 3335/16/0 = M4-1 时代
> 值——M4-3 +31 与 M5-1 +110 已推进，本 plan 记亲核后的现行真值；phase 对账
> 链 = 「3477/21/0 + 各批增量」逐位推算，全套 `--all` 轮照批准制）。IOP 贴线
> 纪律：本批全部新测试小 fixture（≤512² 合成面），零 100MP 单测。

## 已定裁决（生效值，硬约束，不得重开）

M5-2 OQ-1..7 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-11，用户回批）。本 plan 承载其中数学/类型面；UI/流式/预算/走查面 = M5-2-02：

1. **OQ-1 = A**：Mertens 2007 自实现（纯 Swift 纯函数）；**OpenCV 零入仓**（零新 SPM）；Lumen MIT 语义移植带归属注记（deghost 三档表 + 分位亮度映射 + 融合前参考置换）；对齐不借鉴（MTB 已覆盖）。
2. **OQ-3 = A**：deghost 四态 `off/low/medium/high`，默认 medium；v1 无档位面板（advanced 挂账）。
3. **OQ-5 = A**：Mertens 腿**免 EXIF EV**——extent 一致 + N≥2 硬门；aperture/ISO 差异 = warning 不拒绝；EV 有则记 provenance 不消费；曝光比运行时自检豁免（`exposureRatioVerified` 全 true 占位）。
4. **OQ-6 = A（数学面）**：融合工作域 = **sRGB piecewise display 编码**；金字塔层数 = 分辨率自适应（最小边 ≥ 32px 封顶）；band-outer + halo 流式（halo 随层数缩放）；staged 磁盘 N×16B/px。
5. **OQ-7 = A（本 plan 四门）**：G1 双跑 bit-identity / G2 Float32 vs Float64 孪生 parity（实测收窄钉门）/ G3 合成语义靶 / G5 Phase 8 共存零回归。G4（Lumen 结构对照，非门值）与 G6（走查）= M5-2-02。

**架构红线（本 plan 全程 + checker 机检面）**：
- **零新 SPM**：`Project.swift` dependencies 块零 diff；零 OpenCV/第三方融合库符号。
- **零新 `.metal`**：本 phase 全 CPU（Mertens 数学复杂度与 CPU 匹配；GPU 化仅当 M5-2-02 perf 探针证伪 CPU 预算时再议）——收口任务 `git diff <基线>..HEAD` 无 `*.metal` 命中并截屏入 SUMMARY。
- `LightamerIOP/` **零 diff**（DrtEotf 只消费不修改）；`LightamerCore/Sources/Sidecar/`、`Pipe/History/`、`Graph/`（V50Order/Registry/DrtRecord）零 diff；sidecar schemaVersion 不动（MergeParams additive 走 synthesized encodeIfPresent，旧档逐字节零漂移专测钉死）。
- **既有五 kind 行为零变化**：hdrMerge/focusStack/stackAverage/stackMedian/stackSigma 的 enqueue/stepTotal/tag/provenance/腿体逐字节不动（新 case 纯 additive）。
- 既有路由零切换：`enqueue` 无新调用方（App 面 = M5-2-02）；stub 臂 typed 失败形态（KD-4）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 融合工作域曲线接缝 = `DrtEotf.srgbPiecewise`（T1，RESEARCH §3.3 ②的依赖图修正）

- RESEARCH 原文「M3-1 `LutEncodingCatalog` 曲线族现成」**依赖方向不成立**：亲核
  `LutEncodingCatalog` 位于 `LightamerIOP/Sources/Lut3d/`，模块依赖 = IOP →
  Core（`Project.swift` :10/:133 亲核）；`Stack/` 域在 Core，**反向 import
  禁止**。Core 内同语义曲线 = **`DrtEotf.srgbPiecewiseEncode/Decode`**
  （`LightamerCore/Sources/Pipe/Drt/DrtEotf.swift` :172-179，M4-1-01 KD-8
  additive，公开标准参考值 golden 在册；IEC 61966-2-1 分段式，与
  LutEncodingCatalog `transfer: .srgb` 数学恒等）。MertensFusion 经此编码
  linear Rec2020 float32 平面 → display [0,1] 码域。
- **域约定**：编码后 **clamp 到 [0,1]**（display-referred 转换语义——超白
  clip、负值钳 0；Mertens 权重语义定义在 [0,1]，输出凸包性由此保证）。
  DECISIONS 记录该约定（Lumen 输入即 display [0,1]，merge.py:1 头注同前提）。

### KD-2 金字塔核与流式条带形（T1，FocusStackMerge 复用 + RESEARCH §1/§3.3 ⑥）

- **reduce/expand 核对零复制**：`FocusStackMerge` 既有 binomial [1,4,6,4,1]/16
  reduce + linear 2× expand 对（DC-consistent、telescoping exact——08-3 T2 验收
  面）同模块 internal 直调；访问级不足则提升 `internal`（一行改动，行为零变化）。
  权重归一 epsilon 复用 `FocusStackMerge.weightEpsilon`（1e-8）。
- **条带形**：MertensFusion 提供 `fuseStrip(width:height:sources:levels:)`
  级纯函数（输入 = 各源 display 编码后条带 + 权重参数；条带内逐源建权重高斯
  金字塔 × 图像拉普拉斯金字塔、逐层 Σ G(Ŵ)·L、collapse）——**源互不常驻**，
  驱动（band-outer + StagedSet）在 M5-2-02 腿内。
- **整帧参考实现**：`fuse(frames:)` 同文件提供（小面合成，golden 正本位）——
  G3④ halo 不渗钉 = 条带路径带内行 vs 整帧参考逐位对照的锚；亦是 Float64
  孪生的宿主。产线不调用（调用方 = 测试）。
- **层数自适应**：`adaptiveLevels(minEdge:) = clamp(1 + floor(log2(minEdge/32)), 1, 12)`
  （语义 = 顶层面最小边 ≥ 32px；真值表：32→1 / 64→2 / 256→4 / 512→5 /
  1024→6 / 8642〔100MP 短边〕→9；focus-stack `defaultPyramidLevels=5` 为经验
  锚非等式——本公式钉 OQ-6「最小边 ≥ 32px 封顶」原文）。
- **halo 公式**：`haloRows(levels) = max(32, 1 << levels)`（感受野 2^L−2 ≤
  halo；**L=5 → 32 精确命中 `defaultHaloRows` 既有常数**——先例锚自证；L=6→64、
  L=9→512；表测试钉死回归）。

### KD-3 deghost 语义移植面（T1，merge.py:120-169 全链；MIT 归属注记）

- **档表**（MIT，成段移植——文件头注记 `Portions derived from Lumen RAW
  (lumen-raw, MIT)`）：`low (0.20, 2) / medium (0.12, 5) / high (0.065, 9)` =
  （残差阈值，膨胀半径基数）；`off` = 整段跳过（无掩码无置换）。
- **掩码流水**：各帧与参考灰度（Rec709 系数）→ 各自 33 点分位（2..98%，
  抽样步 `ceil(max/1000)`）亮度映射到参考灰阶 → 高斯模糊 σ1.2 → 绝对差 →
  阈值 → **可用门**（两帧灰度均须在 (0.015, 0.985) 开区间——裁切帧非运动
  证据）→ 膨胀半径 `base × max(dim)/1800` → 高斯羽化 → [0,1] 软掩码。
- **置换语义**（merge.py:141-169 原样移植）：静止像素（motion < 0.01 的降采样
  格）上估各帧→参考逐通道 129 点分位 LUT；`prepared = original·(1−α) +
  LUT(ref)·α`——**融合前**把参考内容调到各帧色调域贴进运动区。纯函数面 =
  LUT 构建 + 逐像素应用（流式腿在条带内消费，M5-2-02）。

### KD-4 类型 additive 面（T2，RESEARCH §3.1 扩展点总表落地）

- `MergeKind` + `case hdrMertens = "hdr-merge-mertens"`（Codable raw value
  additive；CaseIterable +1——编译期破四处穷举 switch，逐处补臂：
  `provenanceKind`（镜像同名 case）/ `defaultTag` → `"mertens"`（产物
  `<base>_mertens.tif`，与 `_hdr` 分账）/ `stepTotal` → `sources*4 + 3`
  （KD-8）/ `runProductionMerge` → `runMertensLeg(work)`。
- **`runMertensLeg` 本 plan = typed stub**：`throw AppError.invalidParameter(
  "hdr-merge-mertens production leg lands in M5-2-02")`——M4-1-01「路由不切」
  同形（dispatch 结构两 plan 间零二次编辑，02 只换腿体）；typed 测试钉 stub
  形态防误用。
- `MergeParams` additive 双 optional：`mertensDeghost: String?`（词汇
  `off/low/medium/high`；**nil = 未指定，Mertens 腿语义回落 medium**〔OQ-3
  默认值在腿层消费，UI 恒显式传 "medium"〕）+ `mertensLevels: Int?`（nil =
  自适应；实测解析值照 08-3 `provenanceParams.pyramidLevels` 先例回写快照）。
  权重常数 wc=ws=we=1.0 与 σ=0.2 = 文件常量**不参数化**（RESEARCH §3.1
  「mertensWeights 若裁参数化」按不裁落笔——OpenCV `createMergeMertens(1.,1.,1.)`
  缺省锚，merge.py:167）。

### KD-5 provenance 词汇镜像与算法身份（T2）

- `SidecarProvenance.Kind` + 同名 case（raw 值 `"hdr-merge-mertens"` 恒等
  镜像——两枚举 raw 值逐一对齐的既有纪律）；`ProvenanceReplay.mertensAlgorithmName
  = "mertens-exposure-fusion"`、`mertensImplementationVersion = "1"`（独立于
  hdr 版本——数学演进互不牵连）。
- 消费在 M5-2-02 落地（kind = 域判别器：`hdr-merge-mertens` = display 域产物，
  OQ-2 生效值——本 plan 只钉词汇面）。

### KD-6 免 EV 预检（T3，RESEARCH §3.2 + D-M5-2-5 生效值）

- `ExifPrecheck.mertensVerdicts(captures:) -> [(ev: Double, warnings: [String])]`
  纯函数：**零拒绝面**——body/lens/focal/aperture/ISO 差异全 warning；
  **shutter 无要求**（同曝光合法 = 模式价值本身）；EV = 既有 ΔEV 组成式
  （shutter+ISO 比，参考相对）**只组不消费**（元数据缺 → 0 占位——08-3
  stack 族 flat-zero 先例同形）；消费方 = M5-2-02 腿（记 provenance +
  outcome warnings）。
- extent 一致 + N≥2 硬门 = 既有面（enqueue guard + 腿 extent guard 原样），
  零新代码——本 plan 只钉语义测试。

### KD-7 golden 门定义（T4，RESEARCH §5 + planner 数学修正两处）

- **G1 bit-identity**：同输入双跑 `fuse(frames:)` 与 `fuseStrip` 路径各自
  逐字节相等（全 CPU 顺序归约、零原子零并发归约——M3-3/M5-1
  concurrentPerform 固定索引归并先例）。
- **G2 Float64 孪生 parity**：`MertensFusion` Float32 产线 vs 同文件 Float64
  孪生（M5-1 OklabMath 形态），256² 合成 ramp 集 p99.9 对比。**钉门程序**：
  首轮实测记录带 → DECISIONS 落字面 → 测试钉实测带（向上取整到数量级）；
  **硬上限 1e-5**（拉普拉斯差分放大小数噪声，RESEARCH 预期带 1e-6..1e-5；
  超上限 = 实现缺陷先查 FMA/序，禁调 golden 凑带）。
- **G3 四靶**（③为 planner 修正——research 草案「权重零化」按高斯核数学
  不成立，见下）：
  ①**双帧恒等**：同帧 ×2、deghost off → 输出 == 输入（权重 0.5/0.5 凸性 +
  DC-consistent 金字塔核 telescoping exact；带 ≤1e-6，预期逐位——实测记录）。
  ②**鬼影构造**：帧 B 局部块位移 → medium 档掩码命中位移块 + 置换后该区
  内容 = 参考内容（调到 B 色调域）非鬼影内容。
  ③**权重压制**（修正）：单帧过曝块（1.0 flat）+ 他帧正确曝光同块 → 融合
  输出趋向正确曝光帧（过曝帧权重占比 ≤5% 断言）。**修正依据**：E(1.0) =
  exp(−(0.5)²/(2·0.2²)) = exp(−3.125) ≈ 0.0439 > 0——高斯核无真零点，
  「零化」= 压制语义（占比门），research §5 草案字面修正入 DECISIONS。
  ④**halo 不渗**：`fuseStrip`（带 + halo 条带）带内行（距条带边 ≥ 2^L−2 行）
  vs `fuse(frames:)` 整帧参考**逐位相等**断言（同序浮点；若实测非逐位，
  实测带入 DECISIONS 并钉 ≤1e-7——halo 公式正确性的直接证明）。
- **G5 共存零回归**（T5 收口轮）：既有 Stack/HDR/Provenance 测试零 diff
  全绿（`--bundle IOP` + `--bundle IOPParity` + `--bundle Library` 定向轮）；
  五既有 kind 的 stepTotal/tag/provenance 快照断言原值不变（vocabulary 负测）。

### KD-8 stepTotal 4N+3 推导与 08-3 观察项（T2，亲核发现）

- Mertens 声明式 = `sources*4 + 3`：decode N（`execute` 循环逐源 bump）+
  align N（MTB 参考 1 + 比对 N−1）+ stage/encode N + fuse N（band-paced 补
  足）+ write 1 + sidecar 1 + settle 1。**`done == total` 恒式测试钉死**
  （合成 decode 腿 N=3 全程跑完断言相等）。
- **亲核观察项（不改，登记挂账）**：08-3 既有 stack 族声明
  `sources*3+3`，实际 bump = 4N+3（decode N 未计入声明式）——完成时
  progressDone 可超 progressTotal 约 N 步（观感面小节）。**本 plan 不修**
  （改声明式 = 既有 kind 行为变化，触 G5 红线）；挂账入 DECISIONS +
  GOAL-STATE 挂账节，修复批另案。Mertens 声明式从第一天诚实。

## read_first

1. `.work/gsd/phases/m5-2-mertens/M5-2-CONTEXT.md`（裁决记录 = 七生效值正本）+ `RESEARCH-NOTES.md`（merge.py file:line 读解/算法对比表/落地面设计全锚）
2. `LightamerCore/Sources/Stack/StackMergeService.swift` 全文（MergeKind/MergeParams/runProductionMerge dispatch/stepTotal/defaultTag/landStackProduct/StagedSet——additive 落点）
3. `LightamerCore/Sources/Stack/FocusStackMerge.swift`（reduce/expand 核对 + weightEpsilon + defaultHaloRows/defaultPyramidLevels 锚 + fuseStrip 条带形先例）
4. `LightamerCore/Sources/Stack/ProvenanceReplay.swift`（Kind 词汇/Algorithm 身份/provenanceHash 排除面）
5. `LightamerCore/Sources/Stack/ExifPrecheck.swift`（Verdict 形/ΔEV 组成式/precheckStack 对照——Mertens 免 EV 面的分叉点）
6. `LightamerCore/Sources/Pipe/Drt/DrtEotf.swift` :160-260（srgbPiecewiseEncode/Decode——KD-1 曲线接缝）
7. `/Volumes/UNITEK/Documents/Development/lumen-raw/lumen/merge.py`（MIT 正本：:120-138 档表/可用门、:141-169 置换式、:293-315 入口约束——逐段对照移植）
8. `Project.swift` :1-30/:123-145（模块依赖图——IOP → Core 方向亲核）
9. `Tests/LightamerTests/FocusStackTests.swift` + `HDRMergeMathTests.swift`（Stack 域测试基建：合成面/条带驱动/typed 断言先例）
10. `.work/gsd/phases/m5-1-track/M5-1-VALIDATION.md`（基线 3477/21/0 亲证值 + 对账链）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+ `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh --bundle <域>`（直启宿主；全套 `--all` 需 orchestrator 批准，本 plan 不申请）。
- **L072 跨 bundle 污染**：合成 fixture 与临时产物一律 temp 域（`FileManager.default.temporaryDirectory` 子目录 + `defer` 清理）——StagedSet 既有纪律推广到全部新测试。
- **零 diff 红线自证**（T5 收口）：`git diff <M5-1 终点 SHA>..HEAD -- LightamerIOP/ LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Pipe/History/ LightamerCore/Sources/Graph/ '*.metal'` 零命中 + `Project.swift` dependencies 块零 diff，截屏入 SUMMARY。
- **fixture 域纪律**：测试输入 = 代码内合成平面（零盘上资产、零新 fixture 目录）；复用 FocusStackTests 的合成面驱动形。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 MertensFusion 纯函数族（KD-1/KD-2/KD-3）

- read_first 2/3/6/7 → 新建 `LightamerCore/Sources/Stack/MertensFusion.swift`：文件头 MIT 归属注记 + 算法注记（Mertens-Kaus-Mey-Seidel 2007 + OpenCV `createMergeMertens(1.,1.,1.)` 行为锚）→ display 编码包装（DrtEotf.srgbPiecewise + clamp）/三因子权重（C=|Laplacian(gray)|、S=std(RGB)、E=∏exp(−(I−0.5)²/2σ²)，wc=ws=we=1.0 常量）/归一化/分位亮度映射/deghost 掩码（档表/可用门/膨胀羽化）/置换 LUT（129 点/通道 + 逐像素应用）/`fuseStrip`（金字塔条带融合）/`fuse(frames:)` 整帧参考/`adaptiveLevels`/`haloRows`/Float64 孪生族。
- 验收：`MertensFusionTests`（IOP）——编码 round-trip（linear→encode→decode 带 ≤1e-6 + clamp 边界）+ 权重族四法（几何积分解/w(0.5)=1 σ-参数化恒等/饱和 std/曝光拟合对称性）+ 分位映射单调性 + deghost 档表三行（阈值/半径/可用门负测）+ 置换 LUT 端点与单调 + `adaptiveLevels` 真值表（KD-2 八行）+ `haloRows` 真值表（32@5 精确命中锚）+ `fuseStrip` 单带小面绿。

### T2 MergeKind/MergeParams/Provenance additive（KD-4/KD-5/KD-8）

- read_first 2/4 → `StackMergeService.swift`：`case hdrMertens` + 四 switch 补臂 + `runMertensLeg` typed stub + `MergeParams` 双 optional（init 尾参缺省 nil——既有 init 调用点零改动）→ `ProvenanceReplay.swift`：Kind 镜像 case + 双常量。
- 验收：`MertensMergeKindTests`（IOP）——rawValue `"hdr-merge-mertens"`/`provenanceKind` 镜像/`defaultTag(.hdrMertens) == "mertens"`/`stepTotal(.hdrMertens) == 4N+3` 与 N=3 合成腿 `done == total` 恒式/stub typed 失败形态（enqueue `.hdrMertens` → `.failed(.invalidParameter)` 断言 + 五既有 kind 快照原值不变负测）/params nil→medium 语义纯函数面；`MertensProvenanceTests`（LIB）——Kind 两枚举 raw 值全对齐镜像断言 + **旧 MergeParams（无新字段）Codable JSON 逐字节零漂移**（golden JSON 字面）+ 新字段 encodeIfPresent 往返 + 算法名/版本常量。

### T3 免 EV 预检（KD-6）

- read_first 5 → `ExifPrecheck.mertensVerdicts` 纯函数（零拒绝面 + EV 只组不消费 + metadata 缺 0 占位）。
- 验收：并入 `MertensMergeKindTests`——同曝光包合法（零 warning 零拒绝）/aperture 差异 warning 不拒/ISO 差异 warning 不拒/EV 组成值断言（shutter+ISO 比对表）/metadata 全缺 → EV 0 + warnings 记录/与 `precheck`（严格版）行为对照负测（同输入：precheck 拒、mertensVerdicts 收）。

### T4 golden 批 G1/G2/G3（KD-7）

- read_first 3/9 → `MertensFusionGoldenTests`（IOPP，*Golden* 域模式）：G1 双跑 bit-identity（整帧路径 + 条带路径各一法）/ G2 Float64 孪生 parity（256² 三合成面 ramp 集，p99.9 钉门——**首轮实测 → DECISIONS 落字面 → 测试断言实测带，硬上限 1e-5**）/ G3 四靶（①双帧恒等 deghost off ②鬼影构造 medium 档 ③权重压制占比门 ④halo 不渗条带 vs 整帧逐位）。
- 验收：全绿；G2 实测带与 G3①/④ 实测逐位结论入 DECISIONS（含 KD-7③ 修正的数学依据引用）；失败先查 FMA/求和序，禁调 golden 凑带。

### T5 G5 共存零回归 + 收口（KD-7 G5 + KD-8 观察项落账）

- 收口轮：`--bundle IOP` + `--bundle IOPParity` + `--bundle Library` 定向轮全绿（exit 0 + 零 MEMFAIL——新测试全小 fixture，理论零增量；MEMFAIL 先查重测漂移按 AGENTS 口径）+ 零 diff 红线自证清单（纪律节四路 grep 截屏）+ SUMMARY（任务序/实测带/bundle 分账/`done==total` 恒式证据）+ DECISIONS（KD 偏差/G2 钉门字面/G3 修正记录/08-3 stepTotal 观察项挂账）+ GOAL-STATE 续接点（M5-2-02 待启）+ TODO 同批。
- **双重验收（config `dual_acceptance = true`，m1）**：zcode subagent 独立验收 PASS 后 → **串行** omp 二次验收（computer-use 走查 + 抽测；**严禁并发**——单实例硬约束）；两路结论（PASS/FAIL + 证据）落 `M5-2-01-ACCEPTANCE.md`；FAIL 回注修复批后重走验收。

## 验收标准（AC 总表）

1. **OQ-1 生效值**：MertensFusion 纯 Swift 自实现（文件头 MIT 注记 + 论文/行为锚注记）；`git grep -i "opencv" LightamerCore/ App/` 零命中；`Project.swift` dependencies 零 diff；零新 `.metal`。【T1/T5】
2. **OQ-3 生效值**：deghost 词汇 `off/low/medium/high` 四态在册（档表三行 golden）+ nil→medium 腿层默认语义断言 + 零 UI 面（本 plan 无 App 文件——结构自证）。【T1/T2】
3. **OQ-5 生效值**：`mertensVerdicts` 零拒绝面全表（同曝光合法/aperture/ISO warning/缺 metadata 0 占位/EV 只组不消费）+ 严格版 `precheck` 对照负测。【T3】
4. **OQ-6 生效值（数学面）**：sRGB piecewise 编码经 `DrtEotf`（零新曲线数学）+ `adaptiveLevels` ≥32px 真值表 + `haloRows = max(32, 2^L)` 表（32@5 既有锚精确命中）+ clamp [0,1] 域约定。【T1】
5. **G1**：双跑 bit-identity 两路径绿。【T4】
6. **G2**：Float64 孪生 parity 实测钉门（DECISIONS 字面 + 测试断言一致，≤1e-5 硬上限）。【T4】
7. **G3**：四靶绿（③压制占比门 ≤5%——KD-7 修正语义；④带内行逐位/实测带）。【T4】
8. **G5**：IOP/IOPParity/Library 三 bundle 定向轮零 diff 全绿 + 五既有 kind 行为零变化负测 + 旧 sidecar/params 逐字节零漂移。【T2/T5】
9. **进度恒式**：`.hdrMertens` stepTotal = 4N+3 且合成腿 `done == total` 精确闭合；08-3 观察项挂账在册（不改）。【T2/T5】

## 风险与边界

- **G2 带超 1e-5**：先查 FMA 熔合/求和序 → 再查金字塔核边界 clamp；带写 DECISIONS 不硬凑（禁调 golden 凑带）。
- **G3④ 非逐位**：条带核与整帧核算子序不一致的第一嫌疑 = reduce/expand 边界 clamp 路径；钉 ≤1e-7 带前先对齐实现序。
- **IOP 贴线**：全批合成小面（≤512²）；bundle MEMFAIL 先按 AGENTS 口径查重测漂移。
- **LutEncodingCatalog 依赖图**（KD-1）：若执行中发现 Core 可达的其它 sRGB 曲线源，仍以 `DrtEotf` 为准（golden 在册者胜）——不为此开依赖面。
- **P2 衔接面**：生产腿（band-outer halo 流式 + StagedSet mask + 置换 in-pass）/sRGB-tagged 落盘/域判别钉/UI/预算机检/走查 = M5-2-02；本 plan 交付面以 T5 红证清单为界。

## 提交约定

- T1 `feat(core): mertens exposure fusion pure function family with float64 twin`
- T2 `feat(core): hdr mertens merge kind with additive params and provenance vocabulary`
- T3 `feat(core): ev-free mertens bracket precheck with warning-only verdicts`
- T4 `test(iopp): mertens golden gates bit-identity twin parity and semantic targets`
- T5 `docs(m5-2): close mertens core batch with decisions and ledgers`
- 全英文 Conventional Commits；不 push。
