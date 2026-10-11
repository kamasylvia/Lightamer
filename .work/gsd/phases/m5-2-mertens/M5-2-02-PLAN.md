---
phase: m5-2
plan: "M5-2-02"
title: "Mertens 生产腿与 UI 收口批（wave 2 = RESEARCH §6 plan-02）——runMertensLeg 生产腿（MTB 对齐复用 refactor 抽取 + display 编码/deghost + StagedSet staged 掩码 + band-outer halo 流式 + 置换 in-pass）+ sRGB-tagged 32f 落盘（writeFloatTIFF additive colorSpace）+ landStackProduct additive 双参 + 两域判别回归钉 + UI 两菜单项/_mertens 分账/zh 键族 + perf 探针与 ru_maxrss 机检 + G4 Lumen 结构对照 evidence + G6 走查 + phase 收口"
wave: 2
depends_on: ["M5-2-01"]
autonomous: true
requirements: ["IOP-HDR-06"]
estimated_tests: "+22..30"
test_bundles: [IOP, Library, Export, App]
files_modified:
  - LightamerCore/Sources/Stack/StackMergeService.swift   # 修改：runMertensLeg 生产腿本体（KD-1 流水）+ runStackPrecheckAndAlignment 的 MTB 段抽取为 private helper（KD-3 refactor——precheckStack 严格 aperture 不适用 Mertens）+ landStackProduct additive 双参（exposureEVs/ghostUnion，缺省 nil = 既有 08-3 行为字节零漂移，KD-4）+ StagedSet 增 mask 字节通道（UInt8 staged 读/写 + readShiftedMask）
  - LightamerCore/Sources/Stack/BandStreamer.swift        # 修改：writeFloatTIFF additive colorSpace 参数（缺省 WorkingSpace.colorSpace = 既有调用零漂移；Mertens 传 sRGB——KD-2）
  - App/Sources/Lightamer/UI/SessionBrowserView.swift     # 修改：HDR 合并入口扩第二菜单项（browser_menu_hdr_mertens）+ Mertens 确认 sheet（简形：标题/正文/开始——零档位控件，OQ-3）+ onHDRMertens seam（nil = 隐藏，既有 gate 形）
  - App/Sources/Lightamer/Session/SessionCoordinator.swift # 修改：mertensMergeHandler seam（focusStackHandler 同形）
  - App/Sources/Lightamer/UI/LightamerApp.swift           # 修改：app root 接线——enqueue kind: .hdrMertens + MergeParams(deGhost: false, tag: nil, mertensDeghost: "medium") + toast_hdr_mertens_queued
  - Resources/Localizable.xcstrings                       # 修改：5 键尾块纯插入（browser_menu_hdr_mertens / hdr_mertens_dialog_title / hdr_mertens_dialog_body / hdr_mertens_dialog_start / toast_hdr_mertens_queued）
  - Tests/LightamerTests/MertensLegTests.swift            # 新建（IOP/Core 级，合成 decode 腿小 fixture）：happy path/进度恒式/落地字段/deghost off/cancel/extent typed 败/对齐标签/EV 记录/双跑产物 bit-identity
  - Tests/LightamerTests/MertensRasterDomainTests.swift   # 新建（IOP/Core 级，decode 家族先例）：两域判别回归钉（KD-2）——Mertens 产物重导入描述断言 + Robertson02 产物对照 + Primé 不触发
  - Tests/LightamerTests/MertensMergeUITests.swift        # 新建（APP/App 级）：seam 存在性/enqueue 参数映射（medium 显式）/菜单可见性 gate
  - Tests/LightamerTests/MertensFusionPerfProbeTests.swift # 新建（EXPORT/Core 级，env 门 LIGHTAMER_PERF_PROBE=1 + XCTSkipUnless——默认套件 skip）：100MP×N=5 合成面融合预算探针（KD-6）
  - Project.swift                                         # 修改：四新测试文件登记对应 target 数组 + tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：四新测试文件增行登记（E2；probe 落 EXPORT rationale 注记随行）
  - .work/gsd/phases/m5-2-mertens/perf.md                 # 新建：probe 出数正本（100MP×5 时延/常驻面/ru_maxrss；M2-11 perf.md 惯例）
  - .work/gsd/phases/m5-2-mertens/evidence/lumen-structural-compare/  # 新建：G4 仓外一次性对照（脚本 + 报告——非门值，KD-7）
  - .work/gui-acceptance/m5-2/MANIFEST.md                 # 新建：G6 走查 Manual-Only 行配方（真 RAW bracket 双算法各合一张 + deghost 三档对比截图）
  - .work/gsd/phases/m5-2-mertens/M5-2-02-SUMMARY.md      # 新建（T5）
  - .work/gsd/phases/m5-2-mertens/M5-2-02-DECISIONS.md    # 新建（T5）
  - .work/gsd/phases/m5-2-mertens/M5-2-02-ACCEPTANCE.md   # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/gsd/phases/m5-2-mertens/M5-2-VALIDATION.md      # 新建（T5——phase 签核面，SC 三列对表 + 基线对账链 + 六门全表）
  - AGENTS.md                                             # 修改：M5-2 架构增量节（流式腿形/域判别器/键族登记/封存面零解封申报）
  - .work/GOAL-STATE.md                                   # 修改：续接点
  - .work/TODO.md                                         # 修改：M5-2 条目
  - .work/LESSONS.md                                      # 如踩坑
---

# Plan M5-2-02 — Mertens 生产腿与 UI 收口批（wave 2：生产腿 → 域判别 → UI → 预算/走查 → phase 收口）

> **性质**：M5-2 后继 plan（依赖 M5-2-01 全绿）。本批执行**生产行为落地**：
> ①`runMertensLeg` 生产腿（band-outer halo 流式 + StagedSet staged 掩码 +
> 置换 in-pass——常驻与 N 解耦）；②sRGB-tagged 32f 落盘与两域判别回归钉
> （OQ-2 生效值的生产落点）；③UI 两菜单项 + `_mertens` 分账（OQ-4）；④预算
> 机检（ru_maxrss 8G 门）+ perf 探针 + G4/G6 收尾 + phase VALIDATION。
> **既有五 kind 与 Robertson02 路径字节零回退**为本批第一红线（G5 复验）。
>
> **基线**：M5-2-01 验收后的实测全套值（对账链 = 3477/21/0 + M5-2-01 增量；
> 01-SUMMARY 记账后起算——M4-1-02 同款衔接措辞）。定向轮 bundle 分账见 T5；
> 全套 `--all` 轮照批准制（本 plan 收口轮申请）。

## 已定裁决（生效值，硬约束，不得重开）

承 M5-2-01 已列四值（OQ-1/3/5/6 数学面 + OQ-7 前四门）；本 plan 承载其余生效值：

1. **OQ-2 = A**：产物 = **display-referred [0,1] 的 32f TIFF**，下游走 M4-1 已交付 raster ingest 链——零新机制；provenance kind = 域判别器（`hdr-merge-mertens` = display 域产物）。**落地形态修正见 KD-2**（sRGB tag——research「无 ICC」草案与 M4-1 解析规则冲突，亲核修正）。
2. **OQ-4 = A**：互为合并选项——「HDR 合并（Robertson02）」现行为原样默认一键位不动 +「HDR 合并（Mertens 快速）」新菜单项 → `.hdrMertens` enqueue；tag `_mertens` 分账；不做自动择优。
3. **OQ-6 = A（落地面）**：band-outer + halo 流式（`haloRows(L) = max(32, 2^L)`，M5-2-01 KD-2 钉）+ staged 磁盘 N×16B/px + **ru_maxrss 8G 运行门机检**（预算式不移植 Lumen 全帧式）。
4. **OQ-7 = A（本 plan 二门 + 收口）**：G4 Lumen 跨实现结构对照（**非门值**，仓外一次性，证据入 evidence/，测试不入 CI）/ G6 走查 Manual-Only；六门全表入 VALIDATION。

**架构红线（本 plan 全程 + checker 机检面）**：
- Robertson02 路径**逐字节不动**：`runHDRLeg`/`ExifPrecheck.precheck`/HDR 预检语义零 diff；既有四 stack kind 行为零变化（`landStackProduct` additive 双参缺省路径字节零漂移专测钉死）。
- 队列/取消/进度/落地**骨架零改**：actor 泵/generation epoch/hooks/ExportNamer 碰撞面零 diff——唯一例外 = `runStackPrecheckAndAlignment` 内部 refactor 抽取（KD-3，行为保持，既有测试零 diff 为证）。
- 零新 SPM / 零新 `.metal`（继承 01）；`V50Order`/`Registry`/`HistoryStack`/`HistoryHash`/`PipelineDocument`/sidecar schema 零触碰（M3-3 封存面**零解封**——本 phase 全程不入 iop 链，合并服务面非 op 面）。
- **IOP 贴线**：腿测试小 fixture（≤512²）；100MP 只进 env 门控 probe（EXPORT bundle，KD-6）——IOP bundle 零大面增量。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 runMertensLeg 生产流水（T1，RESEARCH §3.3 ①..⑦落地）

```
①decode N 帧（renderFullFloatRGBA，线性 Rec2020 float32——execute 循环既有面）
②②+③每帧：display 编码（DrtEotf.srgbPiecewise + clamp [0,1]，01 KD-1 约定）
  → deghost（tier ≠ off）：灰度 + vs 参考灰度的分位映射残差掩码
    （33 点/σ1.2/可用门/膨胀 base×max(dim)/1800/羽化——01 KD-3 纯函数消费）
  → staged 落盘：pixels UInt8 掩码双通道（StagedSet 增 mask 通道——
    掩码 [0,1] float 量化 UInt8 落盘，100MP ≈ 0.1GB/张；全分辨率掩码不常驻）
  （参考帧先行——其灰度面在 stage 循环内常驻 0.4GB@100MP 单面，逐源释放）
④对齐：MTB shifts（KD-3 helper 复用，withNCC: false）——stage 与对齐次序
  可交换，移位采样统一在 band 读取缝做（readShifted* 既有惯例）
⑤band-outer 融合：逐 band 读 N 源 shifted 条带（halo = haloRows(L)）：
  条带内逐源 ⑥deghost 置换 in-pass（tier ≠ off：α = mask 条带；
  prepared = strip·(1−α) + LUT(refStrip)·α——refStrip = 源 0 参考条带已在手，
  LUT = 01 KD-3 的 129 点/通道，静止像素预计算）→ 权重金字塔 × 拉普拉斯
  金字塔（01 fuseStrip 消费）→ collapse → 带行写输出平面
⑦落地：landStackProduct（KD-4 additive 面）——float32 RGBA + alpha 1
  → writeFloatTIFF(colorSpace: sRGB)（KD-2）+ provenance sidecar
  （kind hdr-merge-mertens + mertensAlgorithmName/Version + EV 记录 +
  ghost 掩码落盘 GhostMaskWriter 复用 = 置换掩码语义）+ 进度恒式 4N+3
```

- **常驻面**：输出平面 16B/px（1.6GB@100MP）+ 单 band N 源条带 + 金字塔条带组 + stage 期参考灰度单面——与 N 全帧解耦（staged 磁盘 N×(16+1)B/px，`defer` 清理——StagedSet 现行）。decode 次数 = 每源 1 次（比 Robertson02 的 2+1 少一档——「快速第二模式」定位的量化表达，probe 出数）。
- **deghost off** = 跳过掩码/置换/LUT 整段（零额外 IO 零额外遍）——与 Robertson02 `deGhost: false` 对偶（OQ-3 生效值）。

### KD-2 产物域 = sRGB-tagged 32f（T2，RESEARCH §3.4「无 ICC」草案的亲核修正）

- **修正依据（RasterColorDescription.resolve 亲核，M4-1-01 正本）**：无 ICC
  float32 → **scene-linear Rec.2020**（②规则 `tiffNoIccFloatLinear`）——
  research §3.4 草案「无 ICC → sRGB 判定」对 float32 存储**不成立**（sRGB
  默认仅非 float 存储生效）。按草案落盘 = [0,1] display 值被判 scene-linear
  = 域误判。
- **落地**：`writeFloatTIFF` additive `colorSpace` 参数（缺省
  `WorkingSpace.colorSpace`——既有三调用点零漂移）；Mertens 传
  `CGColorSpace(name: .sRGB)` → 产物 = sRGB-tagged 32f → 重导入
  `RasterColorDescription.resolve` = transfer `.srgbPiecewise` + referral
  `.displayReferred`（Primé 规则只对 linear 触发，不命中）→ M4-1 display 腿
  （linearize + outputTransform_inv）→ sceneLinear——**OQ-2「零新机制 + kind
  域判别器」生效值全保持**，仅 tag 承载域声明（诚实域语义不变形）。
- **两域判别回归钉**（T2，research §3.4 plan-01 校验任务在本 plan 兑现）：
  Mertens 产物 write → `RAWDecoder().decode` → `rasterColor` 逐字段断言
  （.srgbPiecewise/.displayReferred/origin 非 defaultSrgb 缺省面）+
  Robertson02 产物（linear-Rec2020 tagged 32f）对照断言（Primé →
  sceneLinear）——**两域两门互证**。

### KD-3 对齐复用 refactor（T1，行为保持抽取）

- `runStackPrecheckAndAlignment`（:1106-1162）= `ExifPrecheck.precheckStack`
  （**aperture 严格**——与 Mertens 免 EV 相抵，OQ-5 生效值禁止复用其预检段）
  + MTB 对齐段 + NCC 段。**抽取**：MTB 对齐段（含进度 bump 与标签词汇）提为
  `runMTBAlignment(work:width:height:withNCC:)` private helper——
  `runStackPrecheckAndAlignment` 保留预检后委托；Mertens 腿直调 helper
  （`withNCC: false`，NCC 对 Mertens 无意义面弱——research §3.2）。
- **行为保持红线**：refactor 后既有 focus/stack/HDR 测试零 diff 为证
  （G5 复验）；helper 不改 bump 序（进度恒式两族全保）。

### KD-4 landStackProduct additive 双参（T1/T2，单一落地路径纪律）

- `landStackProduct` additive：`exposureEVs: [Double]? = nil`（nil = 既有
  flat-zero 路径字节零漂移；Mertens 传 `mertensVerdicts` 的 EV 记录值——
  OQ-5「EV 有则记 provenance 不消费」）+ `ghostUnion: [UInt8]? = nil`
  （nil = 既有 layerStack nil 路径；非 nil 且含 1 → `GhostMaskWriter.dilate +
  land` + `ghostSuppressionLayerStack` 进 sidecar——runHDRLeg 尾段同形，
  掩码语义 = 置换掩码）。
- `exposureRatioVerified` 全 true 占位 = 既有 08-3 形（曝光比自检豁免——
  OQ-5 生效值，零新代码，语义测试钉死）。

### KD-5 UI 面（T3，RESEARCH §3.5 + OQ-4 生效值）

- **两菜单项**：既有 `browser_menu_hdr_merge`（Robertson02）原样保留 =
  默认一键位不动；新增 `browser_menu_hdr_mertens` 并排项（≥2 多选 gate 同形）
  → Mertens 确认 sheet（**简形**：标题/body/开始——**零档位控件**，OQ-3「v1
  无面板」；body 文案注明默认中档去鬼影）→ `onHDRMertens` seam。
- 接线链：`SessionBrowserView.onHDRMertens` → `SessionCoordinator.mertensMergeHandler`
  → LightamerApp root `enqueue(kind: .hdrMertens, params: MergeParams(deGhost:
  false, tag: nil, mertensDeghost: "medium"), sessionRoot:)` + toast
  `toast_hdr_mertens_queued`——hdrMergeHandler/focusStackHandler 同构三段形。
- **zh 键族**（V14 静态键纪律——新代码禁 `String.LocalizationValue("prefix_\(x)")`
  形态）：`browser_menu_hdr_mertens` / `hdr_mertens_dialog_title` / 
  `hdr_mertens_dialog_body` / `hdr_mertens_dialog_start` /
  `toast_hdr_mertens_queued` 五键，xcstrings **尾块纯插入**（历史键字节与
  顺序零触碰）；`MergeKind` 新 case 不进任何 Picker/文案（零动态键）。
- zh-audit `--check`：本批 +5 键全绿（MISSING 对账以 SUMMARY 键清单并集）。

### KD-6 预算机检与 perf 探针（T4，AGENTS 资源监控节 + M2-11 perf.md 惯例）

- **ru_maxrss 机检**：`test-direct.sh` 每 bundle 轮自带 ru_maxrss（内核精确
  口径）+ MEMFAIL 8G 门机检——Mertens 腿测试随 IOP 定向轮自动受检（小 fixture
  理论零增量）；**100MP 级预算证据 = env 门控 probe**：
  `MertensFusionPerfProbeTests`（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless，
  默认套件 skip——M2-5 惯例）：合成 100MP×N=5 float 平面走 `fuseStrip`
  band-outer 全路径（staged 掩码通道含入），探针读钟前 queue fence（L014——
  无 fence 计时是假数），出数 = 时延/常驻面/staged IO 量 → `perf.md` 正本。
- **probe 落 EXPORT bundle rationale**：IOP 为贴线 bundle（7654MB，AGENTS
  在案）——probe 运行态 +2..3GB 会破 8G 门；EXPORT 有余量且融合产物落地面
  （float-TIFF writer）与 Export 域同族；BUNDLE-MAP 增行注记随 commit。
  定向跑法 = `LIGHTAMER_PERF_PROBE=1 Scripts/test-direct.sh --bundle Export
  MertensFusionPerfProbeTests`（批准制：probe 轮 = orchestrator 批准的定向轮，
  运行中监视 + MEMFAIL 即 kill 纪律照 AGENTS）。
- **CPU 预算判据**：100MP×5 融合在探测机可接受时延内（出数记录，无硬门——
  GPU 化仅当探针证伪 CPU 预算时 plan 期再议，OQ-6 生效值原文）。

### KD-7 G4 Lumen 跨实现结构对照（T4，非门值）

- 仓外一次性脚本（Python/uv，`lumen-raw` 环境 or 独立 venv）：同一组合成小图
  （≤256²）分别喂 Lumen `fuse_hdr`（cv2.createMergeMertens 路径）与我方
  `MertensFusion`（经 Swift 脚手架或测试宿主导出融合片）→ 结构对照报告
  （权重积形态/金字塔层数/输出域凸包性/相关性 + 最大偏差量级）。
- **非门值**：OpenCV 内部常数未公开冻结，逐位不可达（RESEARCH §5 OQ-7 备选
  A 否决理由）——报告入 `evidence/lumen-structural-compare/`，测试不入 CI，
  不作任何 AC 门。

### KD-8 G6 走查（T5，gui-acceptance Manual-Only）

- `.work/gui-acceptance/m5-2/MANIFEST.md`：行配方 = 真 RAW bracket 双算法
  各合一张（Robertson02 默认项 + Mertens 项各一）+ deghost 三档对比截图
  （off/medium/high 同素材）+ 产物落格与 `_mertens` 分账核 + 重导入编辑链
  观感（sRGB 域产物正常进管线）。**Manual-Only**（M3-4 先例：GUI 走查合成
  激活环境级全惰，人工行配方）——执行 = 用户/orchestrator 安排，ACCEPTANCE
  记录证据回填。

## read_first

1. `.work/gsd/phases/m5-2-mertens/M5-2-01-PLAN.md` 全文（KD-1..8 = 本 plan 消费的纯函数/类型/常量面契约）+ `M5-2-01-SUMMARY.md`/`DECISIONS.md`（实测带与钉门字面）
2. `LightamerCore/Sources/Stack/StackMergeService.swift`（runFocusStackLeg/runStackAggregateLeg = 流式腿范式；runStackPrecheckAndAlignment :1106-1162 = KD-3 refactor 面；landStackProduct :1382-1454 = KD-4 additive 面；StagedSet :1459-1586 = mask 通道扩展面）
3. `LightamerCore/Sources/Stack/MertensFusion.swift`（01 交付：fuseStrip/adaptivelLevels/haloRows/deghost 纯函数/LUT）
4. `LightamerCore/Sources/Stack/BandStreamer.swift`（writeFloatTIFF :149-200 + bands 几何）
5. `LightamerCore/Sources/Decode/RasterColorDescription.swift` :195-260（resolve ②/③/Primé 规则——KD-2 修正依据正本）
6. `App/Sources/Lightamer/UI/SessionBrowserView.swift` :147-328（HDR 菜单/三 dialog 形/seam gate）+ `SessionCoordinator.swift` :123-137（handler seams）+ `LightamerApp.swift` :877-950（接线三段形）
7. `.work/gsd/phases/m4-1-tiff-raster/M4-1-02-PLAN.md`（wave-2 收口批体例与切换批红线先例）
8. `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（落域正本 + probe 落域先例 GradeEnvelopePerfProbeTests/DepthPerfProbeTests）+ `Tests/LightamerTests/DepthPerfProbeTests.swift`（env 门 probe 形）
9. `Tests/LightamerTests/HDRPipelineMatrixTests.swift`（合成 decode 腿端到端先例）+ `Scripts/test-direct.sh`（MEMFAIL/ru_maxrss 机检口径）
10. `/Volumes/UNITEK/Documents/Development/lumen-raw/lumen/merge.py`（G4 对照正本 + fuse_hdr 调用形 :167）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+ `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh --bundle <域>`；全套 `--all` 收口轮才申请（批准制 + 运行中监视 + MEMFAIL 即 kill）。
- **L072 跨 bundle 污染**：腿测试的合成源文件与产物一律 temp 域 + `defer` 清理；probe 轮独立执行（不与其它 bundle 轮混跑）。
- **L014**：probe/任何 GPU 相邻计时读钟前 queue fence。
- **零 diff 红线自证**（T5 收口）：`git diff <01 终点>..HEAD -- LightamerCore/Sources/Stack/HDRMergeMath.swift LightamerCore/Sources/Stack/ExifPrecheck.swift 'LightamerCore/Sources/Sidecar/' LightamerCore/Sources/Pipe/History/ '*.metal'` 零命中（ExifPrecheck 若 01 已动则对 01 基线）+ `runHDRLeg` 函数体零 diff 截屏 + `runStackPrecheckAndAlignment` refactor 行为保持证据（既有测试零 diff）。
- 双重验收串行纪律（m1）：zcode PASS → omp 二次验收，严禁并发。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 runMertensLeg 生产腿（KD-1/KD-3/KD-4）

- read_first 2/3 → `StackMergeService.swift`：KD-3 helper 抽取（行为保持）→ `runMertensLeg` 本体（KD-1 流水①..⑦全落：stage 期编码+deghost+掩码 staged / band-outer halo 融合 / 置换 in-pass / 落地）+ StagedSet mask 通道 + landStackProduct additive 双参（KD-4）→ stub 臂换真腿（01 KD-4 的 dispatch 结构零二次编辑）。
- 验收：`MertensLegTests`（IOP，合成 decode 腿小 fixture ≤512²）——happy path（N=3 tier medium：产物在盘 + `_mertens` 名 + provenance kind/算法名/EV 记录/`exposureRatioVerified` 全 true + ghost 掩码 PNG 落盘 + layer stack 含 Ghost Suppression）/deghost off（零掩码零置换 + 零额外 staged IO 形断言）/进度恒式（`done == total == 4N+3` 精确）/cancel 中途（generation epoch 既有语义）/extent 不一致 typed 败/对齐标签词汇透传/**双跑产物 bit-identity**（G1 腿级扩展——合成腿两次 enqueue 产物 TIFF 字节逐位相等）/既有 kind 落地路径字节零漂移负测（additive 双参缺省）。

### T2 域判别回归钉（KD-2）

- read_first 4/5 → `BandStreamer.writeFloatTIFF` additive colorSpace 参数 + Mertens 落地消费 + `MertensRasterDomainTests`。
- 验收：`MertensRasterDomainTests`（IOP，decode 家族先例）——sRGB-tagged 32f write→decode→`rasterColor` 逐字段断言（transfer `.srgbPiecewise` + referral `.displayReferred` + Primé 不触发）+ Robertson02 产物对照（linear-ICC float32 → Primé → sceneLinear）+ `writeFloatTIFF` 缺省参数既有调用零漂移负测 + `resolve` 无 ICC float32 → scene-linear 既有规则不回归负测（KD-2 修正依据的回归钉）。

### T3 UI 两菜单项 + zh 键族（KD-5）

- read_first 6 → `SessionBrowserView`（第二菜单项 + Mertens sheet + seam）+ `SessionCoordinator`（handler）+ `LightamerApp`（接线 + toast）+ `Localizable.xcstrings` 尾块五键。
- 验收：`MertensMergeUITests`（APP）——seam 存在性/handler 参数映射（`.hdrMertens` + `mertensDeghost: "medium"` 显式 + `deGhost: false` + tag nil）/菜单可见性 gate（handler nil → 项隐藏既有形）/既有 HDR 菜单项文案与行为零变化断言；zh-audit `--check` 对五新键绿（尾块纯插入——diff = 纯插入验证）；**L057 判别式自证**：sheet 呈现走 SwiftUI `.sheet` 既有形（非 runModal 族——`grep -rn "\.runModal(" App/Sources` 零命中红线维持）。

### T4 perf 探针 + 预算机检 + G4 对照（KD-6/KD-7）

- read_first 8/9/10 → `MertensFusionPerfProbeTests`（EXPORT，env 门）+ `perf.md` 正本 + G4 仓外脚本与报告入 `evidence/lumen-structural-compare/`。
- 验收：probe 默认套件 skip 断言（无 env 时 XCTSkip）；批准制定向 probe 轮出数（100MP×5：时延/ru_maxrss/staged IO——**ru_maxrss < 8G 运行门**，MEMFAIL = 立即 kill + 回归流式形审查）→ `perf.md` 三行账；G4 报告落 evidence（相关性/偏差量级/结构形态四节——**无门值断言**，报告尾注「非门值」）；BUNDLE-MAP probe 增行 rationale 注记。

### T5 G6 走查 MANIFEST + phase 收口（KD-8）

- read_first 1/7 → `.work/gui-acceptance/m5-2/MANIFEST.md`（Manual-Only 行配方）→ SUMMARY/DECISIONS → **全套 `--all` 终验申请**（orchestrator 批准；分割重跑拼表口径照 M5-1 先例）→ GOAL-STATE/TODO/AGENTS（M5-2 架构增量节）翻账 → `M5-2-VALIDATION.md`（六门全表 G1..G6 落位 + SC 对账链 + 基线对账 + 挂账汇编）。
- **双重验收（config `dual_acceptance = true`，m1）**：zcode subagent 独立验收 PASS 后 → 串行 omp 二次验收（computer-use 走查 UI 面 + 抽测）；两路结论落 `M5-2-02-ACCEPTANCE.md`；FAIL 回注修复批后重走验收。VALIDATION = C 档第 3 停（phase 签核前停——结论给用户过目）。

## 验收标准（AC 总表）

1. **OQ-2 生效值**：Mertens 产物 = sRGB-tagged 32f TIFF（KD-2 修正形）→ 重导入 `.srgbPiecewise`/`.displayReferred` 两域判别钉绿 + Robertson02 产物对照钉绿 + 落地走 `landStackProduct` 单一路径（additive 零漂移）。【T1/T2】
2. **OQ-4 生效值**：两菜单项并存（Robertson02 项零变化断言 + Mertens 项新键）+ `_mertens` 分账产物名 + 零自动择优（无任何择优代码路径——结构自证）。【T3】
3. **OQ-5 生效值（消费面）**：EV 记录进 provenance（mertensVerdicts 消费）+ `exposureRatioVerified` 全 true + 同曝光包端到端可合（合成腿 happy path 内嵌断言）。【T1】
4. **OQ-6 生效值（落地面）**：band-outer halo 流式（`haloRows(L)` 消费）+ staged 磁盘 N×(16+1)B/px + probe 100MP×5 ru_maxrss < 8G（`perf.md` 出数）。【T1/T4】
5. **G1（腿级）**：合成腿双跑产物 TIFF 字节逐位相等。【T1】
6. **G4**：Lumen 结构对照报告入 evidence（非门值——报告在册即满足，无数值门）。【T4】
7. **G5（复验）**：既有五 kind + Robertson02 全路径零 diff 全绿；`runHDRLeg` 函数体零 diff 红证。【T1/T5】
8. **G6**：MANIFEST 行配方在册 + 双重验收走查证据回填。【T5】
9. **键族**：五 zh 键尾块纯插入 + zh-audit 绿 + 零动态键形态。【T3】
10. **进度恒式（生产腿）**：`done == total == 4N+3`（tier off 同值——off 减掉的置换不在步数账内，KD-1 步序钉）。【T1】

## 风险与边界

- **流式腿内存超预算**（probe MEMFAIL）：先查条带/金字塔组常驻（KD-1 常驻面清单逐项核对）→ 再查掩码通道泄漏（全分辨率掩码误常驻）→ staged IO 顺序；禁 GPU 化救火（OQ-6：GPU 化仅 plan 期再议）。
- **置换 in-pass 色调失配**：LUT 静止像素采样过疏（motion<0.01 降采样格过宽）→ medium/high 档构造靶（01 G3②）腿级复验；失配 = 采样格收紧（常数面调整入 DECISIONS）。
- **refactor 回归**（KD-3）：helper 抽取后既有三腿对齐行为任何漂移 = 立即回退抽取、Mertens 腿改持私有副本（重复 30 行换零回归——备选路径预declared）。
- **IOP 贴线**：腿测试全小 fixture；bundle MEMFAIL 先查重测漂移（±3% 方差注记）再查本批。
- **probe 轮批准**：100MP probe 轮未获批不跑（env 门双保险）；获批轮运行中监视 + MEMFAIL 即 kill（AGENTS 资源监控节）。
- **VALIDATION 前置**：G6 Manual-Only 行需人工执行——VALIDATION 允许「走查证据待回填」挂账形态收口（M3-4 先例），签核面如实登记。

## 提交约定

- T1 `feat(core): mertens production merge leg with staged band-outer halo streaming`
- T2 `feat(core): srgb-tagged mertens product landing with domain discriminator pin`
- T3 `feat(app): mertens quick hdr merge menu entry with zh keys`
- T4 `test(export): mertens perf probe and budget evidence with lumen structural compare`
- T5 `docs(m5-2): close mertens phase with walkthrough manifest and validation`
- 全英文 Conventional Commits；不 push。
