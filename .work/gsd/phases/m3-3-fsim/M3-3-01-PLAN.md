---
phase: m3-3
plan: "M3-3-01"
title: "FSIM 数据模型与资产批——FilmRecord document 级 record（DrtRecord 同构）+ CC BY-SA 资产原样引入五件套（28 profile + neutral_print_filters.json，隔离目录零改动）+ FilmProfile schema/加载器 + FilmMaterialStore + bake 期中性包闭式求解器 + sidecar v9 / HistoryItem.filmRecord / HistoryHash 尾位折叠持久化面"
wave: 1
depends_on: []
autonomous: true
requirements: ["FSIM-01d", "FSIM-01a（数据模型半面——record/persistence；管线面 = M3-3-02）", "FSIM-01c（数据基座半面——染料近似数据通路；golden 门 = M3-3-03）"]
estimated_tests: "+34..40"
test_bundles: [Layers, Library]
files_modified:
  - LightamerCore/Sources/Graph/FilmRecord.swift          # 新建：FilmRecord + 四枚举 + stableHash + isFilmRecordDefault（DrtRecord.swift 同构）
  - LightamerCore/Sources/Film/FilmProfile.swift           # 新建：profile schema Codable（density_curves/log_exposure 消费面；光谱字段不消费随文件保留）+ 加载器 + typed 错误
  - LightamerCore/Sources/Film/FilmMaterialStore.swift     # 新建：目录注入式 store（film/paper 索引 + 材料对身份 stableHash）
  - LightamerCore/Sources/Film/FilmFilterPackSolver.swift  # 新建：bake 期中性滤色包闭式解 (M0,Y0)（有界二分，确定性）
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift   # 修改：v9 additive filmRecord 文档字段（schemaVersionCurrent 8→9）
  - LightamerCore/Sources/Pipe/History/HistoryStack.swift  # 修改：HistoryItem.filmRecord additive + commitFilm + effectiveFilmRecord（drtDocumentScope 同构忽略面）
  - LightamerCore/Sources/Pipe/History/HistoryHash.swift   # 修改：hash(...) 尾位 filmRecord 折叠参数（默认 nil = 既有档逐位不变）
  - Resources/FilmProfiles/                                # 新建（隔离目录）：28 profile JSON + neutral_print_filters.json 原样字节 + LICENSE（CC BY-SA 4.0 全文）+ NOTICE（署名/citation）+ MANIFEST.sha256 + CHANGELOG.md
  - Project.swift                                          # 修改：Resources/FilmProfiles folderReference（App target）+ 新测试文件登记
  - Tests/LightamerTests/FilmRecordTests.swift             # 新建（LAYERS/Core 级）：record/枚举/hash/pristine/round-trip
  - Tests/LightamerTests/FilmProfileTests.swift            # 新建（LAYERS/Core 级）：schema 解码/typed 容错/资产完整性（MANIFEST 对账）
  - Tests/LightamerTests/FilmFilterPackSolverTests.swift   # 新建（LAYERS/Core 级）：闭式解收敛/确定性/sanity 带（neutral_print_filters 实测值域）
  - Tests/LightamerTests/FilmSidecarTests.swift            # 新建（LIB/Core 级）：v9 字段 additive round-trip + v8 文档零漂移
  - Tests/LightamerTests/FilmHistoryTests.swift            # 新建（LAYERS/Core 级）：commitFilm/effectiveFilmRecord/hash 折叠尾位（无 film item 档逐位不变）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：增行登记（E2 纪律）
  - .work/gsd/phases/m3-3-fsim/M3-3-01-SUMMARY.md          # 新建
  - .work/gsd/phases/m3-3-fsim/M3-3-01-DECISIONS.md        # 新建
  - .work/GOAL-STATE.md                                    # 修改：续接点
  - .work/TODO.md                                          # 修改：M3-3 条目
  - .work/LESSONS.md                                       # 如踩坑
---

# Plan M3-3-01 — FSIM 数据模型与资产批（wave 1）

> **性质**：M3-3 三 plan 之首。本 plan 交付**零渲染面**的全部数据底座：FilmRecord
> （DrtRecord 逐位同构的 document 级 record）、CC BY-SA 资产引入（OQ-2-③ 混合态，
> 五件套合规）、profile 加载器与材料库、bake 期中性包闭式求解器、持久化三件
> （sidecar v9 字段 / history item / hash 折叠）。渲染管线（film sub-run / 
> filmPlacement op / coordinator 接线）= M3-3-02；golden/确定性门/UI = M3-3-03。
> **光谱不可达边界（FSIM-01c 架构注记，全 phase 生效）**：解码链 CIRAW = RGB 域起步，
> 81 波长光谱重放架构性不可达（光谱信息在 demosaic 即折叠）；本批消费
> `density_curves`/`log_exposure`（256×3，status M 打印密度域，与 RGB 域染料近似
> **直接同构**，RESEARCH §1.5）；光谱字段**不消费、随文件原样保留**（避免「修改版
> CC BY-SA 文件」归属混乱）。用户可见措辞 =「物理流程建模，非光谱重放」。

## 已定裁决（生效值，硬约束，不得重开）

M3-2 OQ-1..7 **全部按推荐裁**（M3-2-CONTEXT 裁决记录 2026-10-08）。本 plan 承载：

1. **③ 资产 c 混合态**：引擎/schema/加载器**自建**；`engine/resources/profiles/`
   28 配置 JSON + `resources/neutral_print_filters.json`（TH-KG3 头 × 8 相纸 × 
   film stock，值域 C=0 / M≈49-79 / Y≈48-79 点，planner 2026-10-08 亲核实值）
   **整文件原样字节**入库；**五件套** = ①隔离目录 `Resources/FilmProfiles/`（与
   `Resources/LUTs/`（MIT）物理隔离）②`LICENSE`（CC BY-SA 4.0 全文）③`NOTICE`
   （Andrea Volpato / spektrafilm 署名 + citation 全文 + 来源版本）④`CHANGELOG`
   行记录引入版本 ⑤**资产内容零改动**（MANIFEST.sha256 对账 + fixture 只引用）。
   SpektraLab 渲染产物不入仓不 push（OQ-2-⑤）；GPL 代码零复制。
2. **① 阶段承载（数据面）**：胶片段 = **document 级 FilmRecord 单例**（一台放大机
   一副底片一种相纸 = 每文档一份）；材料/配光字段归 record，**置位参数不进
   FilmRecord**（= M3-3-02 的 filmPlacement grade op）。
3. **② 配光语义（bake 期半面）**：中性滤色包 (M0,Y0) = **bake 期闭式解**（mid-gray
   经负片段得密度三元组，解 M0/Y0 使印相输出通道相等——2 元 2 方程、各通道对 M/Y
   单调 → 有界二分必收敛）；SpektraLab `neutral_print_filters.json` = 自研解的
   **sanity 带参考**（非逐值复刻——其头/相纸/工艺域与我们不同，只断言合理区间）。
4. **确定性门（FSIM-01b，本 plan 先钉数学面）**：同材料对 + 同输入 → 同解
   （求解器无随机性、无并行数据竞争写入、Float64 通道数学）；运行期统计分量
   （缓存键 `fnv(材料对Hash ⊕ 统计Hash ⊕ 模式tag)`）= M3-3-02。
5. **④ 宽容度面板 = M3-4**：本批不做任何教导/直方图 UI。
6. **pristine 纪律（DRT 同款门）**：缺 `filmRecord` 键 = 逐位现状——sidecar v8 文档
   解码/编码字节零漂移（负测钉死）、`HistoryHash` 无 film item 档逐位不变（负测
   钉死）、默认 FilmRecord 不入 carrier 不写 sidecar。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 FilmRecord 形状（T1，DrtRecord.swift 逐位同构）

- 位置 `LightamerCore/Sources/Graph/FilmRecord.swift`；`Codable + Hashable + Sendable`；
  `stableHash()` = FNV-1a over `.sortedKeys` canonical JSON（L013，DrtRecord 同式）。
- 字段（snake_case CodingKeys，tolerant decode `decodeIfPresent` + init 默认）：
  - `filmStock: String` / `paperStock: String` —— profile `info.stock` id
    （默认档 = 空串 = pristine 语义的一部分，见 KD-6）；
  - `yFilterShift: Float`（Yellow 手动偏移，CC 点域 0-100，默认 0）
  - `mFilterShift: Float`（Magenta 手动偏移，CC 点域 0-100，默认 0）
    —— **Y/M 手动恒在**（生效值②，FSIM-01b 钦定，不可裁掉）；
  - `contentAdaptiveShift: Bool`（内容自适应通道偏移可选档，**默认 false** = 
    SpektraLab 行为对齐，生效值②）；
  - `strength: Float`（RFC-025 语义 `out = in + k·(film − in)` 密度域混入，默认
    1.0 = as-modelled；Producer 域 [0,1]，Core 纯函数**不钳**，面板/消费端 owns
    validation——DrtRecord.peakLuminance 同款分工）；
  - `exposureEv: Float`（印相曝光手动微调 EV，默认 0——曝光归一自动分量之外的
    手动臂；SpektraLab Post-Dev exposure 对应物的材料域席位）。
- `isFilmRecordDefault(_:)` 纯函数（`isDrtRecordDefault` 同构）= pristine 判定单源。
- 枚举不设：film/paper stock 是**开放字符串 id**（资产集可扩），非法 id 的 typed
  降级在 store/loader 层（KD-3），不进枚举穷举面。

### KD-2 资产引入（T2，五件套任务面）

- **来源**：本地 SpektraLab 仓 `/Volumes/UNITEK/Documents/Development/SpektraLab/
  engine/resources/`（profiles/ 28 文件 + `neutral_print_filters.json`）。
  **copy 字节原样**（`cp` + `shasum -a 256` 双机对账），禁止任何重排/重编码/
  字段删改（含光谱字段）。
- **布局**：`Resources/FilmProfiles/profiles/*.json`（28）+
  `Resources/FilmProfiles/neutral_print_filters.json` + 四件文书同目录：
  `LICENSE`（CC BY-SA 4.0 法律全文，creativecommons.org 官方文本）、`NOTICE`
  （署名 + `metadata.citation` 全文转录 + 来源 repo 与版本 + 「本目录资产为原样
  未修改副本」声明 + 光谱字段未消费注记）、`MANIFEST.sha256`（逐文件哈希，
  测试对账正本）、`CHANGELOG.md`（引入版本 v0.3.2——profile `metadata.version`
  亲核值——与引入日期）。
- `Project.swift` App target `resources:` 加 `.folderReference(path:
  "Resources/FilmProfiles")`（`Resources/LUTs` 同款——Tuist 4.208 裸目录字符串
  静默忽略的坑，M2-5-3 在案）。**`tuist generate` 恒为该任务批尾动作（L041）**。
- 测试（FilmProfileTests 内）：MANIFEST 全量对账（`#filePath` 走仓根定位——Core
  测试不依赖 App bundle）；`metadata.license` 含 "CC BY-SA 4.0" 断言；28 文件
  计数断言；film/paper 按 `info.support`/`info.stage` 分型计数（film 型 20 +
  paper 型 8 量级，执行期以实盘为准写死）。

### KD-3 FilmProfile schema 与加载器（T3）

- 位置 `LightamerCore/Sources/Film/FilmProfile.swift`；**只解码消费键**（JSONDecoder
  对未知键天然忽略——光谱字段零触碰的机制保证）：`metadata.{version,license,
  copyright,citation}` + `info.{stock,name,type,support,stage,target_print,
  channel_model,densitometer,reference_illuminant}` + `data.{log_exposure,
  density_curves,base_density}`。
  - `log_exposure: [Float]`（256 点，log10 域 −3.0…+4.0）；`density_curves:
    [[Float]]`（256×3，per-channel status M 密度）；`base_density: [Float?]` 
    （film 侧橙罩常数半；paper 侧 Dmin 对应物——执行期以 28 文件实盘核对 nullable
    形态，tolerant 解码兜底）。
- typed 加载错误族：`FilmProfileError { fileUnreadable, schemaMismatch(String),
  curveShapeMismatch(expected:actual) }`——fail-closed（坏文件不静默降级）。
- **形状校验**：`density_curves.count == log_exposure.count`（256）+ 每行 3 通道
  ——染料近似的域约定进文档注释（RESEARCH §4.1 模型域）。

### KD-4 FilmMaterialStore（T4）

- 位置 `LightamerCore/Sources/Film/FilmMaterialStore.swift`；`final class ... 
  @unchecked Sendable`（LutLibraryStore 同款形态）；**目录注入式 init**
  （`init(profilesDirectory: URL)`——Core 不读 App bundle；App 侧装配 = M3-3-02
  coordinator 接线时从 `Bundle.main.resourceURL/FilmProfiles` 注入；测试注入仓内
  `Resources/FilmProfiles/profiles` 真路径）。
- 面：`filmStocks() -> [FilmProfile]`（`info.support == "film"`）/
  `paperStocks() -> [FilmProfile]` / `profile(id:) -> FilmProfile?` /
  `materialPairHash(film:paper:) -> UInt64`（= FNV over 两 profile 消费数据域
  canonical 字节——`density_curves + log_exposure + base_density` bit pattern，
  L013；**不含**光谱字段——未消费数据不进身份）。
- 加载即索引（一次性读目录 + 按 stock id 去重；重名/缺 `info.stock` = typed 错误
  上抛）。**不 bake 不缓存求解结果**（solve 缓存 = M3-3-02 运行期腿的键控面，
  本 plan 只交确定性求解函数本体）。

### KD-5 bake 期中性包闭式求解器（T6）

- 位置 `LightamerCore/Sources/Film/FilmFilterPackSolver.swift`；纯 CPU、Float64、
  无状态（所有输入显式传参——bake 期/运行期解耦的第一半）。
- 输入：film profile + paper profile + 负片段密度变换的**同构 CPU 参考**
  （mid-gray 场景 → 负片段得密度三元组；本 plan 交付参考函数
  `midGrayDensities(film:)`——log10(0.184) 查 `density_curves`（线性插值）+
  `base_density` 偏移；串扰矩阵 M3-3-02 kernel 定形时回填本参考——本 plan 先以
  恒等串扰解 (M0,Y0)，**02 落串扰后 sanity 断言不翻**（解随模型走是设计内））。
- 求解：滤色增益 RGB 域简化 `gain = k_y·[0,0,1] + k_m·[0,1,1] + k_c·[1,0,0]`
  （C 恒中性 0——SpektraLab `c_filter_neutral=0` 同构）；2 元 2 方程（印相输出
  R=G、G=B 两等式）各通道对 M/Y 单调 → **有界二分**（固定迭代数 + 固定收敛
  epsilon 常量——确定性硬约束，无自适应步长无随机性）。
- sanity 带（测试）：对 `neutral_print_filters.json` 在册 (film×paper) 组合，
  自解 (M0,Y0) 落该表实测域的**宽容区间**（M∈[40,90] / Y∈[40,90] 点级——不逐值
  复刻：其头/光源/工艺域不同，区间断言即「解在物理合理域」）；至少覆盖
  portra_400×portra_endura、ektar_100×ultra_endura 两组合。
- **确定性门先钉**：`solve(...) 两次调用 bit-identical`（Float 位型断言）+
  收敛解不依赖初值（无初值——纯二分）。

### KD-6 持久化三件（T7，M2-6 DRT 四件套的 Core 半面）

- **sidecar v9**：`schemaVersionCurrent = 8 → 9`（LightamerSidecar.swift:192）；
  文档级 `filmRecord: FilmRecord?` additive 字段（`displayTransform` 同位形态：
  `decodeIfPresent/encodeIfPresent`、nil 双向缺席）；**v8 负测钉死**——无 film
  键文档 decode→encode 字节零漂移（SidecarV7/V8 同款字节形 pin 先例）。
  `makeSidecarDocument`/恢复读点接 filmRecord（`drtRecord` :952 旁镜像位）。
- **HistoryItem.filmRecord**（HistoryStack.swift:114 `drtRecord` 旁 additive）+
  `commitFilm(record:placeholder:label:)`（commitDrt :249-270 同构——document 
  级单 item、键族 `history_film_param/preset/stock/strength`、撤销恢复语义同款）
  + `effectiveFilmRecord() -> FilmRecord?`（effectiveDrtRecord :466-471 同构——
  指针之下最新 film item wins）。
- **HistoryHash 尾位折叠**：`hash(stack:decodeParamsHash:layerSnapshot:drtRecord:
  filmRecord:)` additive 参数（**默认 nil**——全部既有调用点零改动编译；无 film
  item 的档折入字节逐位不变，负测钉死——与 drtRecord「末位含 film 的 item 的
  stableHash 折入」同序，film 排 drt 之后）。
- **carrier/写腿/恢复腿（App 面）= M3-3-02**（需渲染腿同批闭环验收）。

## read_first

1. `.work/gsd/phases/m3-2-fsim-research/M3-2-CONTEXT.md`——文末裁决记录（七项生效值）
   + D-M3-2-1/3/5/8；`RESEARCH-NOTES.md` §1.5（资产 schema 实测）/§4.1-4.2（模型域
   与求解草案）/§5（许可操作面清单）/§6（golden 策略）。
2. `LightamerCore/Sources/Graph/DrtRecord.swift`——KD-1 的逐位同构模板（枚举
   CodingKeys 终式纪律、tolerant decode、stableHash、isDrtRecordDefault、
   「LICENSING: schema facts only」头注形态）。
3. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`——:192
   `schemaVersionCurrent`、:665-735 drtRecord 字段 additive 形态（decodeIfPresent
   纪律）、:952 makeSidecarDocument 读点。
4. `LightamerCore/Sources/Pipe/History/HistoryStack.swift`——:114-167
   HistoryItem.drtRecord、:249-270 commitDrt、:466-471 effectiveDrtRecord；
   `HistoryHash.swift`——三个 hash 重载与 drtRecord 折叠位。
5. 资产正本：`/Volumes/UNITEK/Documents/Development/SpektraLab/engine/resources/
   profiles/kodak_portra_400.json`（film 形）+ `kodak_portra_endura.json`（paper
   形，`edr_tone_map` 存在但**不消费**）+ `neutral_print_filters.json`（sanity 带
   实值）。`Tests/LightamerTests/Phase6SidecarTests.swift`（LIB 侧car additive
   负测先例）+ `Tests/LightamerTests/StableHashTests.swift`（FNV 纪律）。
6. `Project.swift`——:122/:142 resources 段、:177-185 folderReference 先例
   （`Resources/LUTs`）、测试 target 登记（:531 LightamerTestsLibrary 一带）。
7. `.work/gsd/phases/m3-1-w1/M3-1-01-PLAN.md`（PLAN 体例与 KD/E7 登记纪律参照）
   + `.work/LESSONS.md` L041（generate 批尾）/L013。

## 纪律（强制）

1. **光谱字段零消费**（机制 = 只解码消费键）；**资产字节零改动**（MANIFEST.sha256
   为对账正本；任何确需改动的发现 = 停下上报，不得改资产适配代码）。
2. **GPL 零复制**：SpektraLab 代码/脚本（bake_all_print_luts.py 等）零参考复制；
   本仓只引 CC BY-SA 数据文件。
3. **密封面（本 plan 范围零 diff 清单）**：`TerminalTailPolicy` / 
   `DrtTailAssembly` / `PixelPipe.swift` / `DrtEotf.swift` / `Lut3dKernels.metal` /
   `LutEncodingCatalog` / 六格式导出矩阵 / `V50Order` / `ModuleRegistry` /
   `defaultFaceDisabledOpNames`——本 plan 一律不触碰（git diff --name-only 机检
   零命中）。`LightamerSidecar.swift` 仅限 KD-6 additive 面。
4. **测试登记**（E2）：新测试文件同 commit 登记 Project.swift + BUNDLE-MAP 增行
   （归属按 front-matter：FilmRecord/FilmProfile/Solver/History = LAYERS；
   FilmSidecar = LIB）；`tuist generate` 恒批尾（**L041**）。
5. **确定性**：求解器 Float64、固定迭代/epsilon 常量、无随机无初值依赖；hash 走
   StableHash（L013），禁 Swift `Hasher`。
6. **checker 四条**：①资产完整性真链（MANIFEST 实对账非抽样）；②登记闭环
   （Project.swift × BUNDLE-MAP × 源文件 `func test` 三方对表）；③语义断言
   （pristine 负测钉死；hash 不变性负测钉死）；④边界核对（密封面 diff 零命中 +
   sidecar v8 零漂移专测在案）。

## Tasks

### T1 FilmRecord（KD-1）

- **action**：`FilmRecord.swift` 新建（record + tolerant decode + stableHash +
  `isFilmRecordDefault` + PresetNames 占位常量族，DrtRecord 头注形态带
  SCHEMA PROVENANCE/LICENSING 注记）；`FilmRecordTests`（round-trip / 默认值 /
  tolerant decode（部分键/未知键）/ stableHash 稳定性与差异面 / pristine 判定）。
- **验收标准**
  - [ ] LAYERS 定向轮绿；`FilmRecord` 落 `Sources/Graph/`；密封面零命中。

### T2 资产引入五件套（KD-2）

- **action**：28 profile + neutral_print_filters.json 原样 copy + shasum 双对账；
  LICENSE/NOTICE/MANIFEST.sha256/CHANGELOG.md 四件；Project.swift
  folderReference + generate 批尾；FilmProfileTests 资产完整性法（MANIFEST 全量
  对账 + license 字段 + 计数）。
- **验收标准**
  - [ ] `shasum -a 256` 仓内文件 vs MANIFEST 全量一致；来源仓 vs 仓内 diff 零
        输出；`Resources/LUTs/`（MIT）零触碰；CC BY-SA 目录物理隔离在位。

### T3 FilmProfile schema/加载器（KD-3）

- **action**：`FilmProfile.swift` 新建（消费键 Codable + 形状校验 + typed 错误）；
  测试（film/paper 两形真文件解码、坏形状 typed 拒、target_print 关联读取）。
- **验收标准**
  - [ ] LAYERS 定向轮绿；解码只触消费键（光谱字段不在类型面）；坏文件 fail-closed。

### T4 FilmMaterialStore（KD-4）

- **action**：store 新建（目录注入、分型索引、materialPairHash）；测试（真资产
  目录索引、分型计数、pair hash 稳定性/差异面、重复 id typed 拒）。
- **验收标准**
  - [ ] LAYERS 定向轮绿；store 零 bundle 依赖（注入式）。

### T5 bake 期求解器（KD-5）

- **action**：`FilmFilterPackSolver.swift` 新建（midGrayDensities 参考 + 有界
  二分 (M0,Y0) + 常量族）；测试（两组合 sanity 带、bit-identical 双调用、单调
  前提自检、epsilon/迭代数常量在册）。
- **验收标准**
  - [ ] LAYERS 定向轮绿；确定性断言在案；sanity 带非逐值复刻（区间断言 +
        DECISIONS 注记口径）。

### T6 持久化三件（KD-6）

- **action**：sidecar v9 字段 + schemaVersionCurrent 9；HistoryItem.filmRecord +
  commitFilm + effectiveFilmRecord + HistoryHash filmRecord 参数；测试：
  FilmSidecarTests（LIB——v9 round-trip + **v8 零漂移负测**）、FilmHistoryTests
  （LAYERS——commit/undo/jump 投影、**无 film item 档 hash 逐位不变负测**、
  film 在 drt 之后的折叠序）。
- **验收标准**
  - [ ] LIB + LAYERS 定向轮绿；v8 文档字节零漂移专测在案；HistoryHash 既有调用
        点零改动（默认参数）。

### T7 收口

- **action**：SUMMARY（含「光谱不可达边界」架构注记转述 + 测试增量对账链）/
  DECISIONS（KD-1..6 + sanity 带口径 + 资产版本）/ GOAL-STATE 续接点 / TODO；
  `git diff --stat` 对表 + 密封面机检。
- **验收标准**
  - [ ] 三方对表（登记 vs 文件 vs BUNDLE-MAP）；密封面 `git diff --name-only`
        零命中；docs 完整。

## 验收标准（AC 总表）

| # | AC | 机检方式 |
|---|---|---|
| 1 | FilmRecord 落位（字段/KD-1 域/pristine 判定/stableHash），round-trip 与 tolerant decode 全绿 | T1 测试 |
| 2 | 资产五件套完整：28+1 文件字节原样（MANIFEST 全量对账）+ LICENSE/NOTICE/CHANGELOG + 隔离目录；MIT LUT 目录零触碰 | T2 shasum + diff + 走查 |
| 3 | 加载器只解码消费键（光谱字段不进类型面）；坏文件 typed fail-closed | T3 测试 |
| 4 | 求解器确定性（bit-identical 双调用）+ sanity 带两组合 + 常量族在册 | T5 测试 |
| 5 | sidecar v9 additive（v8 零漂移负测钉死）+ HistoryItem.filmRecord/commitFilm/effectiveFilmRecord + HistoryHash 默认参数零改动（无 film 档逐位不变负测钉死） | T6 测试 |
| 6 | 登记闭环（E2/L041）+ 密封面零命中 | 三方对表 + diff 机检 |

## 风险与边界

- **base_density/相纸 Dmin 的 nullable 形态**：28 文件实盘可能不一（film 侧
  `[None,...]` 前导实测在案）——tolerant 解码兜底 + 执行期若发现成片缺键 =
  DECISIONS 注记消费策略（缺省 0），**不改资产**。
- **sanity 带宽严**：SpektraLab 表 = TH-KG3 头工艺域，我方闭式解域更宽——区间
  断言取宽容带（KD-5），过紧 = 假失败风险；宽严标定写 DECISIONS，M3-3-03 golden
  门不依赖本带（主门 = 数学复算）。
- **串扰矩阵未定**（M3-3-02 kernel 定形）：本 plan 求解参考以恒等串扰起步，
  02 落串扰后 sanity 断言不翻（解随模型走是设计内）；02 有回填义务（DECISIONS
  双向登记）。
- **v9 bump 的下游面**：`PRAGMA user_version`（.lalb）与 sidecar schemaVersion
  是两条版本线（M2-8 在案）——本 plan 只动 sidecar 线；.lalb 零触碰。

## 提交约定

- T1 `feat(core): film record data model with stable hash and pristine gate`
- T2 `feat(assets): import spektrafilm CC BY-SA profiles with compliance set`
- T3 `feat(core): film profile schema and typed loader`
- T4 `feat(core): film material store with pair identity hashing`
- T5 `feat(core): bake-time neutral filter-pack closed-form solver`
- T6 `feat(core): sidecar v9 film record and history additive plane`
- T7 `docs(m3-3): close film data model batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。
