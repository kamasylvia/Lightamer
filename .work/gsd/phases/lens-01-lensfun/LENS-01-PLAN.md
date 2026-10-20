---
phase: lens-01-lensfun
plan: "LENS-01"
title: "plan L1 — 双重校正互斥三态探测 + 匹配硬化 + 匹配移出 process 期（T1 EXIF 字段接线核验〔勘误③复用既有字段〕+ decodeParamsHash 覆盖核验 / T2 DNG opcode 探针 + DecodedImage 四构造点三态 / T3 crop gate 修复 + 阈值分档 ≥60 + 歧义拒绝 / T4 匹配结果 memo / T5 面板 §1 状态机 readout + 匹配预览 stub 修复 / T6 收口）"
wave: 1
depends_on: []
autonomous: true
requirements: ["charter = UQ-R4 拉正（8bd94370）——FEAT-DEV-07 验收锚 enable+scale+projection+profile database+auto-detection 的互斥与匹配地基波", "research 正本 = phases/lens-01-lensfun/RESEARCH.md（b2b31909）§Baseline/§Mutex/§Auto-Detection/§Plan Split L1 行", "OQ 裁决正本 = 同目录 CONTEXT.md（D-LENS-1..8 全按推荐 + X1..X8 设计承接 + hazards 三条 + 红线 15 条 + 转写勘误三条〔③ = review B1〕）", "基线 3991/37/0（f0prime 终态——CONTEXT §转写勘误②）；本 plan 分账 +13..18（含 B1 下修）", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 LENS-02 起跑"]
success_criteria: "SC 全可机检——T1：复用既有 focalLength35mm/lensMake（勘误③——零新声明零产线 diff）+ 接线断言测试（合成 EXIF fixture decode → 两字段非 nil）+ 旧档 decode 零漂移负测 + decodeParamsHash 对 RAWTechnicalOverrides 覆盖面核验结论落 DECISIONS（未覆盖 = 停手上报，禁顺手扩缝——X2 v1.x 域）；T2：DNGOpcodeProbe 纯函数（51008/51009/51010 存在性 + seek 式有界读纪律 (review m10)）+ DecodedImage.embeddedGeometry additive + 四构造点赋值（RAW:236 内 DNG/非 DNG 分支/退役 raster:358/RasterDecoder:121:138——DNG=probe/RAW 非 DNG=unknown/raster 全部=notApplicable (review M6)）+ 表驱动测试（合成 TIFF 字节正负例）；T3：resolveCommitted 全参化（maker/model/imageCrop 实值 + imageCrop 优先序 35mm 推导 > camera 唯一命中 > 1.0 + resolve crop 实参 = 相机 imageCrop 修正回归 (review m5)）+ 阈值 ≥60 分档 + 歧义拒绝 + Params additive 记录 resolve 输入 + crop gate 生效回归（全幅/APS-C 误配拒绝例）；T4：LensfunStore 进程内 memo（缓存匹配结果 entry+score+失败状态——尺寸无关，键 = 匹配输入 stableHash + DB 实例身份，reinstall 失效 (review M4)）+ 命中/失效/跨尺寸测试；T5：面板 §1 = 互斥三态 readout（params.embeddedGeometry 携带）+ 匹配预览真跑（maker+model+score 档位 + miss 状态机 readout，替换 matchName=key stub）+ 新键尾块纯插入 + zh-audit 双 PASS"
estimated_tests: "+13..18（T1 +1..2 / T2 +4..6 / T3 +4..6 / T4 +2..3 / T5 +2..4〔App bundle〕；越带申报理由；T1 下修 = B1 勘误③）"
test_bundles: [IOP, APP]
baseline: "3991/37/0（f0prime 批终态 F0P-02-SUMMARY:12,:99——CONTEXT §转写勘误②；HEAD b2b31909 = research docs-only 产线零漂移）"
expected_all: "3991 + ΔN（LENS-01 分账 +13..18 → 本 plan 终态带 4004..4009；--all 归 orchestrator 批准制——本 plan 验收 = 构建 + 定向 bundle〔IOP/App〕，全套归 LENS-04 收口轮统一对账）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 15 条（FIX2③ / 封存面 / xcstrings 尾块 / LocalizationValue 禁形 / L041 tuist 末位 / machine-guard 机器级单重活 / GPL 归属 / probe fence / --all 批准制 / C 档门控 / UserDefaults 恰一键本 plan 零触〔autoApply 归 LENS-02〕/ 默认中性零行为 / L057 缝 / 测试落域 / commit 纪律）。"
  - "X2 边界 = 解码侧 vendorLensCorrection override 本 plan 零执行（v1.x parked——T1 只做 hash 覆盖面核验与结论登记，发现未覆盖 = 停手上报不扩缝）。"
  - "既有行为零回归底线：manual 滑杆路径 / 默认 .off / pointMapSegment 蒙版缝 / fallbackEntry 40 档（browser 排序提示语义保留，仅摘除自动入选资格）——定向 bundle 全绿。"
  - "anti-double-correction 默认语义零改：本 plan 不动 auto-apply（LENS-02 域）；detected/unknown/notApplicable 判定只进 readout 与 params 记录，不改变默认 source。"
files_modified:
  - LightamerCore/Sources/Decode/RAWDecoder.swift             # T2：DecodedImage 构造点 embeddedGeometry 赋值（RAW :236 腿 + 退役 decodeRaster :358 腿；T1 零产线 diff——勘误③ (review B1)）
  - LightamerCore/Sources/Decode/RasterDecoder.swift          # T2：TIFF 两腿构造点 embeddedGeometry 赋值（:121/:138 (review M6)）
  - LightamerCore/Sources/Decode/DecodedImage.swift           # T2：embeddedGeometry additive optional
  - LightamerCore/Sources/Decode/DNGOpcodeProbe.swift         # T2：新建——TIFF 字节探针纯函数（51008/51009/51010）
  - LightamerIOP/Sources/Lens/LensModule.swift                # T3：Params additive（cameraMaker/cameraModel/imageCrop/embeddedGeometry）+ reloadDefaults 折入 + T4 消费 memo
  - LightamerIOP/Sources/Lens/LensfunMatch.swift              # T3：resolveCommitted 全参化 + 阈值分档 + 歧义拒绝 + T4 memo（LensfunStore 域）
  - App/Sources/Lightamer/UI/Inspector/LensPanelView.swift    # T5：§1 readout 三态 + 匹配预览真跑（stub 摘除）
  - Resources/Localizable.xcstrings                           # T5：panel_lens 状态机/readout 新键尾块纯插入
  - Tests/LightamerTests/ExifLensFieldsTests.swift            # T1：新建（IOP bundle）
  - Tests/LightamerTests/DNGOpcodeProbeTests.swift            # T2：新建（IOP bundle）
  - Tests/LightamerTests/LensMatchHardeningTests.swift        # T3：新建（IOP bundle）
  - Tests/LightamerTests/LensfunMemoTests.swift               # T4：新建（IOP bundle）
  - Tests/LightamerTests/LensPanelReadoutTests.swift          # T5：新建（App bundle）
  - Project.swift                                             # T6：四个新测试文件入对应 bundle 显式数组（IOP ×4 / App ×1——五文件）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # T6：五个新测试文件落域登记行 (review m4)
  - .work/gsd/phases/lens-01-lensfun/LENS-01-SUMMARY.md       # T6：执行摘要（逐任务记账 + ΔN 终账）
  - .work/gsd/phases/lens-01-lensfun/LENS-01-DECISIONS.md     # T6：裁定记录（hash 覆盖面核验结论 + 各偏差）
---

# Plan LENS-01 — plan L1：互斥三态探测 + 匹配硬化 + 匹配移出 process 期

> **裁决正本** = `CONTEXT.md`（D-LENS-1..8 + X1..X8；晨审可推翻）；规格
> 正本 = `RESEARCH.md`（§Baseline / §Mutex / §Auto-Detection / §Plan
> Split L1 行；planner 抽核吻合 + 勘误三条见 CONTEXT，③ = review B1
> EXIF 字段勘误）。本 plan = 纯现
> 基座接线 + Core 探针新件，**零 kernel 改动**（LensKernels.metal 本
> plan 零 diff——kernel 面归 LENS-02/03）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T6 形态 = CONTEXT D-LENS
> 落定值）。执行中如触「必须扩面」（解码侧 override / auto-apply 开关 /
> kernel 扩参 / 封存面触碰）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6。每任务独立 commit
> （Conventional Commits 全英文，只 add 相关文件，不 push）；重活
> （xcodebuild）起跑前过 `Scripts/machine-guard.sh`。
>
> **C 档停**：T6 闭环后**停汇报**；确认后 LENS-02 起跑。
>
> **基线**：**3991/37/0**（CONTEXT 勘误②）。全套预期 3991 + ΔN（本
> plan 分账 +13..18，B1 下修后；全套对账归 LENS-04 收口轮）。

## ΔN 预算表（逐任务，LENS-01 分账带 +13..18；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 EXIF 字段接线核验 | **+1..2** | 接线断言（既有字段取值正例）+ 旧档零漂移负测 (review B1) | IOP（ExifLensFieldsTests） |
| T2 DNG 探针 | **+4..6** | 探针表驱动（合成 TIFF 正负例）+ 四构造点赋值 (review M6) | IOP（DNGOpcodeProbeTests） |
| T3 匹配硬化 | **+4..6** | crop gate 生效/阈值分档/歧义拒绝/resolve 输入折入 + resolve crop 实参回归 (review m5) | IOP（LensMatchHardeningTests） |
| T4 memo | **+2..3** | 命中/miss/reinstall 失效/跨尺寸同参 (review M4) | IOP（LensfunMemoTests） |
| T5 面板 readout | **+2..4** | readout 状态映射 + 预览真跑 | App（LensPanelReadoutTests） |
| T6 收口 | **0** | docs + Project.swift 数组 + BUNDLE-MAP + tuist generate | — |
| **合计** | **+13..18** | 3991 → 本 plan 终态带 4004..4009 | 五新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **auto 生效域 = raster 链**（D-LENS-1）——本 plan 不落地开关（归
   LENS-02），只落判定携带面。
2. **v1 只 Lensfun 侧覆盖**（D-LENS-2）——解码侧 override 零执行（X2）。
3. **阈值 ≥60 + 歧义拒绝 + imageCrop 优先序**（D-LENS-4）。
4. **探测挂载位 = DecodedImage additive + params 自描述携带**（X1）。
5. **匹配移出 process 期 = L1 memo / L4 快照两段制**（D-LENS-3）——本
   plan 只做 memo 段。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/lens-01-lensfun/CONTEXT.md`（D-LENS-1..8 + X1..X4 +
  hazards + 红线 15 条 + 勘误三条〔③ = CaptureMetadata EXIF 字段——
  review B1〕+ 晨审索引）
- `.work/gsd/phases/lens-01-lensfun/RESEARCH.md` §Baseline/§Mutex/
  §Auto-Detection/§Test Strategy
- `.work/gsd/phases/04-geometry-lens-detail-iops/04-04-DECISIONS.md`
  （D-04-04-T0-1 数据不入 git / D1-D9 既有裁定）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位——本 plan 五个新测试文
  件必触发）+ L014（fence——本 plan 无计时面，备忘）+ AGENTS.md M2-4-0
  E2（测试落域 + BUNDLE-MAP）

---

## T1 — EXIF 字段接线核验 + decodeParamsHash 覆盖面核验（X4 前置；勘误③ (review B1)）

> `CaptureMetadata` 两字段**既有**：`focalLength35mm`（:58，08-2 声明）
> / `lensMake`（:78），且 decode 腿已接线（`RAWDecoder.swift:550/:563-577`
> ，08-3 yiyin 批；LensMake = 主 EXIF dict `kCGImagePropertyExifLensMake`
> + aux 回落——D-08-3-T2-1 纠正注记在源）。「补两字段」前提作废（勘误
> ③）：本任务**零产线 diff**（或仅测试暴露接线缺口时的最小防御补线）
> ——重名新声明 `focalLengthIn35mm` / 重复 `lensMake` = 编译错误 +
> 双字段双真相违单源，禁。

**read_first**：CONTEXT §X4（勘误③）+ §转写勘误③；`CaptureMetadata.swift` 全文（:49-84 追加尾段——08-2/08-3 yiyin 批）；`RAWDecoder.swift:545-580`（接线现形 + D-08-3-T2-1 注记）；RawLab `raw_processor.cpp:45-46`（35mm 推导式）；CONTEXT §X2（核验边界）。

- **action**：
  1. 复用既有 `focalLength35mm`/`lensMake`——核接线覆盖面（RAW decode
     腿 :550/:563-577 在位）；如测试暴露某容器/腿漏读 = 最小防御补线
     + DECISIONS 申报；**禁新增字段声明**。
  2. **decodeParamsHash 覆盖面核验（X2 边界核验，零改动）**：核 RAW
     decode 缓存键是否折叠 `RAWTechnicalOverrides` 全字段——结论（覆盖/
     未覆盖）落 DECISIONS；未覆盖 = **停手上报**（v1.x 域，禁顺手补折
     叠）。
  3. 测试（IOP bundle）：接线断言——合成 EXIF fixture（或既有 fixture
     补拍）decode → `meta.focalLength35mm`/`meta.lensMake` 非 nil 取值
     正例（**断言既有接线，非新声明**）+ 旧 metadata JSON decode 零漂
     移负测（tolerant additive 断言）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 产线文件**预期零 diff**（防御补线暴露时
    = 恰最小接线文件 + DECISIONS 申报）+ 一新测试文件。
  - grep：`focalLength35mm`/`lensMake` 在 CaptureMetadata **恰一既有声
    明**（零新增声明；`focalLengthIn35mm` 零命中——重名禁，勘误③）。
  - 接线断言正例 + 旧档零漂移负测在册（缺新键 JSON decode == 旧结构）。
  - decodeParamsHash 核验结论在 DECISIONS（覆盖/未覆盖二值 + 证据行号）。
- **commit**: `test(lens01): pin capture metadata exif lens fields wiring`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（测试-only 零行为
  差；防御补线态 = 回既有接线）；偏差（接线缺口/防御补线落点）=
  DECISIONS 申报；**禁触 RAWTechnicalOverrides 结构**（X2 v1.x 域）；
  **禁改 CaptureMetadata 既有字段语义**。

## T2 — DNG opcode 探针 + DecodedImage 三态（互斥探测地基，X1）

> CIRAW 无「是否已应用」查询 API（架构性事实）——分层判定：DNG tag 探
> 针 / 厂商 RAW unknown / raster notApplicable。

**read_first**：`RESEARCH.md` §Mutex 事实基座 + 探测缝三步；CONTEXT §X1；RawLab `lens-dng.md`（Stage3 探测设计正本——语义对照，非移植体）；`DecodedImage.swift`（additive 落点）；`RAWDecoder.swift` 腿分派面（RAW/退役 decodeRaster——构造点 :236/:358 (review M6)）；`RasterIccParser.swift:320-360`（TIFF IFD0 有界字节 walk 先例——seek 式读法 (review m10)）。

- **action**：
  1. 新建 `LightamerCore/Sources/Decode/DNGOpcodeProbe.swift`：纯函数
     `(data: Data) -> Bool`——TIFF 结构字节探针（II/MM 头识别 + IFD0 +
     SubIFD walk，entries 查 tags 51008/51009/51010 存在性）；零 ImageIO
     依赖；越界/畸形容错（探针失败 = false = 未检出，不 throw）。读法
     = **seek 式有界读**（只读 IFD0/SubIFD 所需字节——
     `RasterIccParser.tiffEmbeddedICCData` :320-360 先例；opcode tags 可
     在 IFD0 或 SubIFD〔ProRAW 多帧〕），禁全文件 Data 读入（DNG 可达
     10^8 字节级）；`(data: Data)` 语义注明可分片 (review m10)。
  2. 新枚举 `EmbeddedGeometryState`（detected/unknown/notApplicable，
     Core 域 Sendable）；`DecodedImage` += `embeddedGeometry:
     EmbeddedGeometryState?`（additive optional）。
  3. 构造点赋值（**4 处** (review M6)）：`RAWDecoder.swift:236` RAW 腿
     内 = 条件分支（DNG → 探针，任一 tag = detected；非 DNG →
     unknown）；`:358` 退役 decodeRaster 腿 = **notApplicable 同步赋值**
     （一处改动；不赋 = nil「未判定」与 raster 语义矛盾；退役腿处置入
     DECISIONS）；`RasterDecoder.swift:121/:138` TIFF 两腿 =
     notApplicable。
  4. 测试（IOP bundle）：探针表驱动——手织最小 TIFF 字节（含/不含
     51008-51010、SubIFD 深层、畸形头）正负例 + 四构造点赋值断言（合成
     fixture 或既有 decode 测试扩臂）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰四产线文件（DNGOpcodeProbe 新建 +
    DecodedImage + RAWDecoder〔:236/:358〕+ RasterDecoder〔:121/:138〕
    ——(review M6)）。
  - grep：`EmbeddedGeometryState` 恰一文件定义；`DecodedImage(` 构造点
    4 处均带 `embeddedGeometry:` 实参（DNG/非 DNG 在 RAW 腿内条件分支
    ——「各腿恰一处」按实际拓扑改写 (review M6)）。
  - 探针测试含畸形输入容错例（不 throw 断言）。
  - 既有 decode 测试零回归（`--bundle IOP` 定向）。
- **commit**: `feat(lens01): probe dng opcode lists for embedded geometry state`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（additive optional，
  零消费方行为差）；偏差（探针 walk 深度/枚举命名/退役 decodeRaster 腿
  处置）= DECISIONS 申报；**禁做 opcode 内容解析**（存在性判定 = X1 保守
  语义）；**禁在 IOP 侧重复定义枚举**（Core 单源）。

## T3 — crop gate 修复 + 阈值分档 + 歧义拒绝（D-LENS-4，X4）

> 现役 `resolveCommitted` 传 maker:nil/model:nil/imageCrop:1.0——crop
> gate 0.96 实际未生效；40 分 fallback 档自动入选偏松。

**read_first**：`RESEARCH.md` §Auto-Detection 匹配硬化节；`LensfunMatch.swift:100-160`（modelScore/match 全参本体——已实现，纯接线）+:405-446（resolveCommitted/fallbackEntry 现状）；CONTEXT §X3/X4（Params additive 纪律）；M3-1-01 hash 零漂移先例（AGENTS.md M3-1 节）。

- **action**：
  1. `LensModule.Params` additive：`cameraMaker: String?`/
     `cameraModel: String?`/`imageCrop: Double?`/`embeddedGeometry:
     EmbeddedGeometryState?`（默认 nil，encodeIfPresent——默认 params
     JSON 逐字节零漂移专测随批）；`reloadDefaults` 从 capture + probe
     折入（imageCrop 终式按 X4 优先序：35mm 推导〔focal > 0 守卫〕>
     camera 唯一命中 cropfactor > 1.0）。
  2. camera 唯一命中查找（`db.cameras` maker+model 归一匹配；多命中 =
     弃 = RawLab 语义；单命中 = cropfactor 采纳）——`LensfunMatch` 新
     纯函数。
  3. `resolveCommitted` 全参化：maker/model/imageCrop 从 params 读
     （nil = 现状兜底）；auto 通道阈值 ≥60（word-overlap 40 档摘除自动
     入选资格——`fallbackEntry` 保留但仅 browser 排序语义，标注注释）；
     同分多候选 = Ambiguous 拒绝（返回 miss + 状态，供 T5 readout）；
     **resolve crop 实参 = 相机 imageCrop**——现役
     `LensfunMatch.swift:422` 传 `crop: entry.cropfactor`（镜头校准
     crop）与 `resolve` 语义（:193 注释自述需相机 cropfactor）相悖，随
     本任务修正 + 回归钉死 (review m5)。
  4. resolve 失败状态结构化（Matched/Ambiguous/NoLens/NoDatabase/
     MissingFocal——T5 消费；进程内返回值形态，非持久面）。
  5. 测试：crop gate 生效例（全幅镜头串 vs APS-C 校正集拒绝/通过双臂）
     + 35mm 推导例（`focalLength35mm` 既有字段——勘误③）+ camera 唯
     一/多命中例 + 阈值分档例（40 分拒/60 分收）+ 歧义拒绝例 + resolve
     crop 实参回归例（相机 crop 腿——(review m5)）+ params additive 零
     漂移负测。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两产线文件（LensModule + LensfunMatch）。
  - grep：`imageCrop: 1.0` 字面兜底仅在「前序皆缺」分支恰一处；
    `>= 60` 阈值常量恰一处声明；`fallbackEntry` 调用点带
    「browser-ordering only」注释；`crop: entry.cropfactor` 相悖实参零
    残留（resolve crop 实参 = 相机 imageCrop 回归在册 (review m5)）。
  - 默认 params（无新键）encode 输出与旧 JSON 逐字节相等（零漂移专测
    在册）。
  - 既有 LensfunDBTests/LensParityTests 零回归（`--bundle IOP` 定向）。
- **commit**: `fix(lens01): harden lensfun matching with crop gate and score tiers`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 crop gate 失效态
  ——既有行为恢复，无新增回归）；偏差（状态结构形态/阈值常量落点）=
  DECISIONS 申报；**禁改 modelScore 既有分值语义**（100/60/40 +5 亲核
  基线）；**禁把 Ambiguous 猜成最高分**（D-LENS-4）；**禁动 40 档打分
  本体**（只动入选资格）。

## T4 — LensfunStore 进程内 memo（H-L1 消解第一段）

> `process` 每次 run 全库线性打分（拖滑杆每帧数千条目）——L1 段 = 进程
> 内 memo；持久快照归 LENS-04（两段独立可回退）。memo 缓**匹配结果**
> （entry + score + 失败状态）非解析系数——resolve 多项式求值廉价且尺
> 寸无关 (review M4)。

**read_first**：`RESEARCH.md` §Geometry Pipeline Seam per-render 解析开
销节；`LensfunMatch.swift:204-207/:258-262`（normScale/center 分辨率强
相关面——memo 键避尺寸项的依据）；`:380-446`（LensfunStore NSLock 域 +
install/uninstall 语义）；CONTEXT §X3 L1/L4 分工。

- **action**：
  1. `LensfunStore` NSLock 域内 memo：键 = **匹配输入** stableHash
     （params 折新 additive 字段——resolve 输入面：lensKey/maker/model/
     imageCrop/focal 等）+ DB 实例身份（install 时换戳）；值 = **匹配
     结果**（entry 身份 + score + 失败状态，非解析系数——resolve 求值
     尺寸无关天然免 width/height 键，center 分辨率强相关跨尺寸串值缝一
     并消解 (review M4)）；`install/uninstall` 失效全表。
  2. 匹配段（`LensfunMatch.match` 层）改走 memo（miss 才全库打分；
     `resolve` 多项式求值保持每 run——(review M4)）；容量上限（如
     LRU 32，LutLibraryStore LRU 先例）防膨胀。
  3. 测试：命中（二次同参零打分——打分计数器或时间断言）/ 参数变化
     miss / reinstall 失效 / 容量淘汰 / **跨尺寸同参命中**（full/
     preview/thumbnail 同匹配结果——尺寸无关断言 (review M4)）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一产线文件（LensfunMatch.swift）。
  - memo 键 = 匹配输入 stableHash（新 additive 字段变化必 miss——测试
    在册）+ DB 实例身份，**无 width/height 项**（值 = 匹配结果天然尺
    寸无关 (review M4)）；reinstall 失效 + 跨尺寸命中测试在册。
  - 既有 LensfunDBTests 零回归。
- **commit**: `perf(lens01): memoize lensfun match results in store`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 per-render 打分
  态——功能等价，性能回落）；偏差（容量值/键形态）= DECISIONS 申报；
  **禁把 memo 结果写进 params**（持久化 = LENS-04 快照域）；**禁在锁内
  做重活**（打分在锁外、写表在锁内——NSLock 纪律）。

## T5 — 面板 §1 状态机 readout + 匹配预览 stub 修复（X6 §1 段）

> 现役 `refreshMatchState` 只回显 EXIF 串（`matchName = key`，:226-237
> 亲核）——落地 = 真跑硬化匹配 + RawLab 状态机 readout 形态。

**read_first**：`RESEARCH.md` §Auto-Detection 匹配预览 stub 修复节 + §UI/UX §1 段；`LensPanelView.swift` 全文（三段现状 + applyDiscrete 缝）；CONTEXT §X1/X6；T3 失败状态结构。

- **action**：
  1. §1 段改造：静态 `panel_lens_embedded_note` 升级为带判定 readout
     （params.embeddedGeometry：detected/unknown/notApplicable/nil 未判
     定四态；nil = 中性文案不冒充结论）。
  2. `refreshMatchState` 真跑：用 params resolve 输入（cameraMaker/
     cameraModel/imageCrop/lensKey/focal）跑 `LensfunMatch` + 阈值/歧
     义逻辑 → readout = Matched(maker+model+score 档)/Ambiguous/NoLens/
     NoDatabase/MissingFocal；hasData=false → NoDatabase。
  3. readout 提取 App 侧可测纯模型（`LensPanelReadout`——输入 params +
     store 状态 → 状态 + 文案键；View 只消费）。
  4. xcstrings 新键尾块纯插入（状态机 5 键 + 三态 3 键 + 未判定 1 键量
     级，实际键清单随 implementation 申报）；`zh-audit --check` +
     `--self-test` 双 PASS。
  5. 测试（App bundle）：readout 状态映射表驱动（含 nil 未判定态）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两产线文件（LensPanelView + xcstrings）。
  - grep：`matchName = key` 回显 stub 零命中；`panel_lens_embedded_note`
    键退役或改值面（历史键零触碰——尾块纯插入 + 旧键可留作未判定文案，
    终形 DECISIONS 申报）。
  - 新键全部静态字面量（LocalizationValue 插值禁形零命中）；zh-audit
    双 PASS 输出留档。
  - `--bundle App` 定向零回归。
- **commit**: `feat(lens01): show mutex state and real match readout in lens panel`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 stub 回显态）；
  偏差（键清单/readout 分段）= DECISIONS 申报；**禁动 §2-§3 手动滑杆段
  与 Apply/Clear 按钮**（browser 改造 = LENS-02 T4 域）；**禁跑真匹配于
  body 求值路径**（readout 缓存于状态，仅在参数/图切换时刷新——body 纯
  函数纪律）。

## T6 — 收口（Project.swift 数组 + tuist generate + docs）

- **action**：
  1. `Project.swift` 五个新测试文件入对应 bundle 显式数组（IOP ×4：
     ExifLensFields/DNGOpcodeProbe/LensMatchHardening/LensfunMemo；
     App ×1：LensPanelReadout）+ BUNDLE-MAP 五行登记
     （`M2-4-0-BUNDLE-MAP.txt`——(review m4)）。
  2. `tuist generate` = 本批最后一个动作（L041）。
  3. `--bundle IOP` + `--bundle App` 定向全绿；ΔN 实数对账（预算
     +13..18）。
  4. SUMMARY（逐任务记账 + ΔN 终账 + 探针/证据指针）+ DECISIONS
     （decodeParamsHash 核验结论 + 各偏差 + 键清单）落盘。
  5. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿零回归；Project.swift diff =
  恰五行数组插入；BUNDLE-MAP 登记行在库 (review m4)；tuist generate 后
  无生成物入 git（`.gitignore` 面）；SUMMARY/DECISIONS 在库。
- **commit**: `test(lens01): register lens match hardening suites and close out l1`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY
  申报理由；禁漏 tuist generate（数组改后不生成 = 编译面漂移）。

---

## 风险与回退

- **探针假阳性**：opcode tag 存在 ≠ CIRAW 实际应用（如第三方 DNG 无内
  嵌校正却带空 opcode list）——保守方向无害（detected = Lensfun auto
  不开，用户可显式强制启用）；表驱动测试覆盖空 list 例。
- **阈值收紧的匹配率回落**：≥60 收紧可能让部分原本 40 分命中的镜头失
  配——方向正确（误配 > 失配）；miss 台账（readout NoLens）+ profile
  browser 手动回落（LENS-02）是既定 UX 闭环；回落率观察项挂 LENS-04
  收口走查。**legacy `.lensfun` 档叙事 (review M3)**：既有
  `source == .lensfun` 文档（snapshot nil）恒走 live resolve——硬化后
  命中→miss = 校正静默消失（blit identity）、系数变 = 观感变；处置归
  LENS-04 T2 裁决表第七项（预期按缺陷修复原位收 + 面板 Re-match 提示
  ；判 look-change 则按 bump 纪律全套）。
- **memo 键漂移**：params additive 字段变化必 miss（stableHash 折入自
  然覆盖）——测试钉死；DB reinstall 戳失效防跨库串值。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH 缺口表「auto-detection/双重校正互斥」两
   行 ↔ T2/T3/T5 逐项闭合；H-L1 memo 段 ↔ T4。
2. **OQ 兑现核**：D-LENS-4（T3 阈值/歧义/crop gate 三件 + 40 档摘除自
   动资格）/ X1（T2 四构造点 + params 携带 (review M6)）/ X2（T1 只核
   验不扩缝）/ 勘误③（T1 复用既有字段零新声明 (review B1)）。
3. **红线核**：LensKernels.metal 零 diff；Registry/V50Order/LightamerSidecar
   零 diff；xcstrings 尾块纯插入 + 双 PASS；LocalizationValue 禁形零命
   中；Project.swift 数组段 diff + tuist generate 末位。
4. **SC 可机检性**：每条 SC 有命令级判据（grep / git diff --stat / 定
   向 bundle）；ΔN 对账式非死数。
