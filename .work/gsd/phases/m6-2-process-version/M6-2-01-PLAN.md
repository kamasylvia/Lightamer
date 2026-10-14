---
phase: m6-2
plan: "M6-2-01"
title: "per-photo process version（单 plan 全量批）——Core 级 RenderProcessVersion/RenderProcess 账本（legacy=0 哨兵 + current=1 + 钳制 resolving + case doc-comment 即账本）+ sidecar v10 additive `process` 键（缺键 = legacy = 恒 ABSENT 不序列化 + LightCraft lenient 宽容 decode + 前向大号保留不降级）+ 管线 run-scoped 读缝（PixelPipe property + IOPiece stamp，零消费零行为）+ App per-url 载体与 mint/preserve 写腿（makeSidecarDocument 唯一编辑缝 + load 腿双分支）+ 出生点盖章五面（merge 两臂 / AI 副本 / Session batch / Metadata pristine 臂）+ hash isolation 与 Copy Adjustments 不携带 + golden 四门 + bump 纪律登记"
wave: 1
depends_on: []
autonomous: true
requirements: ["M6INT-01（REQUIREMENTS :407）"]
estimated_tests: "+32..38"
test_bundles: [LIB, LAYERS, APP, IOP, SESS]
files_modified:
  - LightamerCore/Sources/Pipe/RenderProcess.swift                  # 新建：RenderProcessVersion（Int 值类型 + legacy=0 哨兵 + current=1 + 域门 0...0xFFFF_FFFF 的 init?）+ RenderProcess 枚举（compiler-exhaustive 单 case v1 + ALL oldest-first + current + resolving(_:) 钳制表——raw ≤ 0 → 最老 case / raw > current → current；case doc-comment 即账本，KD-1）+ 分叉点折键契约头注（「非 legacy 才折」，KD-6）
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift            # 修改：schemaVersionCurrent 9→10 + v10 注记段 + `process: RenderProcessVersion?` additive 字段（nil ⇔ 键 ABSENT ⇔ 语义 legacy，KD-2 canonical 形）+ CodingKeys 补 case + decode lenient 表（缺键/0/损坏 → nil 不保留；1..2^32−1 含整值浮点 2.0→2 保留，前向大号原值保全）+ encode 显式 rawValue encodeIfPresent
  - LightamerCore/Sources/Pipe/PixelPipe.swift                      # 修改：`renderProcess: RenderProcessVersion = .legacy` run-scoped 属性（terminalTail :142 同位）+ process(:2036)/processComposite(:2090) 双入口 additive 参数（缺省 .legacy = 全部既有调用点字节零变化）+ 内部派生 sub-run pipe 继承同值（尾段 tailPipe 等，逐构造点审计）
  - LightamerCore/Sources/Pipe/IOPiece.swift                        # 修改：additive `renderProcess: RenderProcessVersion = .legacy`（iscale/pipeType run 常量 stamp 同位，PixelPipe.run 一次性 stamp；不入 paramsHash 折叠——piece 级 run 常量惯例；memberwise 默认参 = 既有构造点零 diff）
  - LightamerCore/Sources/Pipe/LayerCompositeDriver.swift           # 修改：composite additive 参数 renderProcess（缺省 .legacy）+ basePipe/逐层 pipe/terminal pipe 传递（零缺省行为）
  - App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift             # 修改：process 载体三面（rawDecodeOverrides/drtRecords/filmRecords 四件族同形，KD-3）——`processVersions: [String: RenderProcessVersion]` map + `processVersion(for:)` 读面（缺省 .legacy）+ `restoreProcessVersion(_:for:)` 恢复面（无 coordinator 回写——restoreSessionOverrides 同形防写回回声）+ `dropSessionProcessVersions()` 关图丢弃面
  - App/Sources/Lightamer/State/PipeCoordinator.swift               # 修改：load 腿双分支 prime（有档 = document.process ?? .legacy 载体恢复；pristine 无档 = RenderProcessVersion.current mint 盖章——「盘上无 sidecar，imageID mint 同批」判据）+ makeSidecarDocument 写值（carrier legacy → nil 键 ABSENT；非 legacy → 原值含前向大号，KD-4）
  - LightamerCore/Sources/Library/ImportService.swift               # 修改：mintProvenanceSidecar(:675) AI 副本出生档盖章 process = current（§3.7 表行兑现）
  - LightamerCore/Sources/Stack/StackMergeService.swift             # 修改：两出生点（HDR :2220 / Mertens+Pano :2676）产物 sidecar 盖章 process = current
  - LightamerCore/Sources/Session/SessionBatchApplier.swift         # 修改：pristine 臂（无档分支）新档盖章 current；既有档臂非 round-trip（:100-106 字段挑选重建只提 5 字段，:136-144 两臂共汇全新档构造）——+2 行 additive 显式携带 process（局部提升 existingProcess + 构造点分支条件盖章，禁 `?? .current`，KD-7）
  - LightamerCore/Sources/Session/MetadataService.swift             # 修改：pristine 臂同上；既有档臂零改
  - Tests/LightamerTests/SidecarV10Tests.swift                      # 新建（LIB，15 法，FilmSidecarTests 同位同力学）：byte-face 三档 + lenient 全表 + hash isolation + 归一化 + FUTURE-version + 版本/预设不携带负测 + 账本/钳制表（G1 门 + G4 损坏值门）
  - Tests/LightamerTests/RenderProcessSeamTests.swift               # 新建（LAYERS，8 法，DrtTailTests 同位 pipe harness）：IOPiece stamp 贯通 + G2 三式（冻结门/分叉可见门/缺键=legacy 臂）+ G3 零行为门（0/1 逐位恒等）+ 缓存键面零变化 + 前向大号 pipe 面不降级
  - Tests/LightamerTests/ProcessVersionCarrierTests.swift           # 新建（APP，8 法，SidecarV5Tests 同位真 load 链）：mint 门/legacy 保全/前向大号保全/corrupt 档/undo+swap 零触/Copy Adjustments 不携带/关图重开幂等/workspace 缺席面（G4 门）
  - Tests/LightamerTests/StackMergeServiceTests.swift               # 修改：+2 法（HDR 臂 / Mertens-Pano 臂产物 `.lra` 含 "process": 1）
  - Tests/LightamerTests/ImportServiceTests.swift                   # 修改：+1 法（AI 副本出生档 process=1）
  - Tests/LightamerTests/SessionBatchApplierTests.swift             # 修改：+1 法（pristine 臂 =1 + 既有档臂三态一法覆盖：legacy 保 ABSENT / process=1 保全 / 前向 7 保全）
  - Tests/LightamerTests/MetadataServiceTests.swift                 # 修改：+1 法（pristine mint =1 + 既有档保全）
  - Project.swift                                                   # 修改：三新测试文件登记对应 target 数组（显式清单无 glob）+ `tuist generate` 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt      # 修改：三新行登记 + 四既有行 method 数更新（E2 纪律，随各自任务 commit）
  - AGENTS.md                                                       # 修改：M6-2 架构增量节（process 账本开篇 + bump 纪律三层 + 「非 legacy 才折」契约 + M6 批 iop 调参 plan 的 AC 模板行）
  - .work/gsd/ROADMAP.md                                            # 修改：M6-2 行 ✅（T6 收口同批）
  - .work/gsd/REQUIREMENTS.md                                       # 修改：M6INT-01 兑现终态注记（T6）
  - .work/gsd/phases/m6-2-process-version/M6-2-01-SUMMARY.md        # 新建（T6）
  - .work/gsd/phases/m6-2-process-version/M6-2-01-DECISIONS.md      # 新建（T6——含 KD 偏差登记 + 出生点盖章字节面影响申报 + 钳制形式正确性注记 + resolving 无生产消费点申报 + E1 双登记〔pre-M6-2 SessionBatchApplier 既有档臂文档级字段丢弃缺口明确不修出范围 + process 在本臂的携带 = 显式新增面非自动保全〕+ M1 值类型域门/sidecar 存储门双门分离一行注记 + M4 ProcessProbeModule 测试替身可行性确认）
  - .work/gsd/phases/m6-2-process-version/M6-2-01-ACCEPTANCE.md     # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/GOAL-STATE.md                                             # 修改：续接点
  - .work/TODO.md                                                   # 修改：M6-2 条目
  - .work/LESSONS.md                                                # 如踩坑
---

> checker 回注（2026-10-14）：E1 修复批 front-matter 三行同批修订——①
> `SessionBatchApplier.swift` 行：既有档臂**非 round-trip**（:100-106 只从
> decode 出的 document 提取 5 字段；:136-144 pristine/既有两臂共汇
> `LightamerSidecar(` 全新档构造），「decode round-trip 原值自动保全（零改）」
> 原文与源码事实相反，改写为 +2 行 additive 显式携带（分支条件盖章，KD-7）；
> ②`SessionBatchApplierTests.swift` 行：既有档臂测试意图不变、改三态一法
> 覆盖（legacy ABSENT / process=1 保全 / 前向 7 保全），法数仍 +1；③
> DECISIONS 行：追加 E1 双登记 + M1 双门注记 + M4 可行性确认。逐节细则见
> KD-7 / T4 / T6 各节回注。依据 = `M6-2-CHECKER.md`（E1/M1/M2/M4，源码
> file:line 为 2026-10-16 HEAD `c4ff891e` 亲核）。

# Plan M6-2-01 — per-photo process version（单 plan 全量批）

> **性质**：M6-2 单 plan 承载 phase 全部交付面（RESEARCH §3 设计全量 + §4 v10 交互
> 细则 + §5 golden 四门 + §6 迁移挂账）。规格正本 = `RESEARCH-NOTES.md`（file:line
> 均为 2026-10-16 HEAD `d0fa29ad` 亲核）；裁决正本 = `M6-2-CONTEXT.md` 裁决记录
> （**OQ-M6-2-1..6 全按推荐，用户回批 2026-10-14**）。机制底座 = sidecar v5-v9
> additive 族（v7/v8 hash-isolation 与 v6/v9 set-fields-move 两先例形已亲读）+
> `edgeMapAlgorithmVersion` 分叉点折键先例（`PipeCacheKey.swift:92-127`）+
> iscale/pipeType run 常量 IOPiece stamp 先例（`IOPiece.swift`）。
>
> **基线**：**3689/24/0**（M6-1-VALIDATION 2026-10-14 终验 `TOTAL|3689/24/0|2157s`
> 亲证值，exit 0 零 MEMFAIL；对账链 3631+53+4+1 精确闭合，亲核记录 =
> `phases/m6-1-interop/M6-1-VALIDATION.md` §AC8 + 终验节）。本批预期全套
> **3721..3727/24/0**（+32..38；三新文件 31 法 + 既有四文件 additive 5 法），
> 对账留 T6 验收。

## 已定裁决（生效值，硬约束，不得重开）

M6-2 OQ-1..6 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-14 用户回批）。本单 plan 承载全部六项：

1. **OQ-1 = A（键面与 schema 承载）**：文档级 additive 可选 **`process: Int?`**
   （JSON 拼写 `process` 冻结，LightCraft 同名）+ `schemaVersionCurrent` **9→10**
   （一键族一 bump 惯例延续）。三则语义：**缺键 = legacy = 0 = 冻结**（写腿
   `encodeIfPresent`——legacy 档 re-encode 键恒 ABSENT，永不被动升级）；**新档
   mint = `RenderProcessVersion.current`**（Core 常量，起步 = 1，仅首次建档盖章）；
   **语义冻结纪律** = 改观感的 iop 语义变更必须 bump `current` + 旧号冻结分支 +
   golden 三件套，不改观感的重构不 bump。
2. **OQ-2 = A（hash 与缓存纪律）**：**hash isolation**（v3 五元数据/v4 provenance/
   v5 rawOverrides/v7 versions/v8 aiProvenance 先例族）——`process` 不折
   `HistoryHash.hash` / `driftDetected`、零 history item、undo/redo/版本 swap
   零触；缓存键**只在分叉路径折 process 值**（`edgeMapAlgorithmVersion` 折键先例；
   M6-2 零分叉 = 键面零变化；折形 = **非 legacy 才折**——0/缺键不折，legacy 档键
   字节与今日恒等）；**Copy Adjustments / 预设 apply 不携带 process**（文档级键
   不在 `isAdjustmentTransferable` 集，目标照片按自己的 process 解释粘来的参数）。
3. **OQ-3 = A（读腿宽容性与前瞻值，LightCraft lenient 原形）**：合法域 = 整数
   0..2^32−1（整值浮点 `2.0` 记 2）；域外/损坏值（负数/非整浮点/字符串/null/
   数组/2^32）→ **legacy（0）**——不毁档其余字段（tolerant decode 纪律）且
   **损坏值不保留**（存回 = 键 ABSENT）；**比本 build 更大的 process 号 = 保留
   原值**（存回不降级）+ 渲染钳到 `RenderProcess.current`（前向兼容）。
4. **OQ-4 = A（零行为基线与枚举账本）**：M6-2 交付面 = **机制 armed + 渲染零
   行为**——M6-2 时点 process 0 与 process 1 渲染**逐位恒等**（尚无语义分叉，
   首个真实分叉由未来 iop 语义变更引入）；`RenderProcess` 枚举
   compiler-exhaustive + case doc-comment 即账本；bump 纪律登记 =
   AGENTS.md 架构增量节 + 枚举 case 注释 + M6 批 iop 调参 plan AC 模板行；
   **否决演示性 bump**。
5. **OQ-5 = A（迁移 UX）**：v1 = **无显式迁移动作**（老档恒冻结——零漂移承诺
   本体）；「Update to Current Process」挂账至首个真实 iop 语义 bump 落地时裁
   交互形态（LightCraft `develop.updateProcess` 一步 undo 形态为参考底稿）。
6. **OQ-6 = A（golden 四门）**：①additive 零漂移负测 ②冻结语义 golden ③管线
   读缝零行为门 ④mint/传输面——ROADMAP 三件最小面之上**补 mint 门**；范围边界 =
   **零 MCP 工具面、零 UI 面、零格式矩阵触碰、零新 SPM、零 `.metal`、零
   xcstrings/UserDefaults 新键**。

**架构红线（本 plan 全程 + checker 机检面）**：
- **hash 折叠面零 diff**：`HistoryHash.swift` 逐字节零改（折叠公式不含 process——
  legacy 档 historyHash 重算零漂移的机制本体）；`driftDetected` 判定面零改。
- **缓存键面零 diff**：`PipeCacheKey.swift` 零改（M6-2 无分叉；分叉点折键 =
  未来分叉批的登记契约，非本批代码）。
- **history item / 版本链零触**：`HistoryItem` / `SidecarHistoryItemRecord` /
  `SidecarVersionRecord` 零新字段（process 是文档级键；版本 swap = history 链
  换装不触 process——与 LightCraft per-settings 快照形态的有意偏离，登记）。
- **六格式导出矩阵 / MCP 20 工具封闭集 / QuickLook+Spotlight appex / `.lalb`
  schema / LightamerPreset / FilterPredicate 零触碰**。
- **既有 byte-face 测试族零编辑预期**：V 系/Film/Drt/MetadataV3/RoundTrip/
  Phase4-6 全部符号化引用 `schemaVersionCurrent`（亲核 grep 在案）——9→10 bump
  自动传播；新档 init 默认 `process: nil` → encodeIfPresent 保持 ABSENT → 既有
  字节面逐字节不变。若执行期浮出硬编码 `: 9` 字面量断言 → 定向修 + DECISIONS 申报。
- **L057 禁令**（无 UI 面——自然满足）；**L014 GPU fence**（seam 测试读回走既有
  pipe harness fence 形）；**L048 比较空间纪律**（逐位比较 = f32 原样字节比，
  产线常数 `Double(Float(x))` 升维面若涉及）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 Core 账本件形状（T1，RESEARCH §3.5）

- `RenderProcessVersion`（`LightamerCore/Sources/Pipe/RenderProcess.swift`，
  `struct` + `Hashable + Sendable`）：`let rawValue: Int` + 域门构造器
  `init?(rawValue: Int)`（`0...0xFFFF_FFFF` 之外 = nil）+ `static let legacy =
  Self(rawValue: 0)!`（pre-process 哨兵，与任何真实 process 号分离）+ `static
  let current = Self(rawValue: 1)!`（起步 = 1；**唯一可 bump 点**，bump 时同步
  枚举新 case + AGENTS 账本行 + golden 三件套）。非 Codable（sidecar 自持 lenient
  编解码；本类型只作内存载体）。
- `RenderProcess` 枚举（同文件）：**compiler-exhaustive**，M6-2 时点单一 case
  `case v1`（doc-comment 即账本首行：「M6-2 时代基线渲染——与 legacy 0 的区别 =
  v1 是 mint 盖章的『本代』，0 是概念引入前的冻结档；首个语义分叉开 v2 时此处
  追加 case，编译器逐点指向所有分叉处」）+ `static let all: [RenderProcess] =
  [.v1]`（oldest first）+ `static var current: RenderProcess { all.last! }` +
  **`static func resolving(_ raw: RenderProcessVersion) -> RenderProcess`** 钳制
  表：`raw ≤ 0` → 最老 case（legacy 档走最老代际的语义臂 = 冻结本体）；`raw >
  current.rawValue` → current（前向大号钳已知最新——LightCraft
  `ProcessVersion::process()` 同构）；域内 → 对应 case。生产分叉点（未来）在
  match 处调 resolving 后穷举 switch；M6-2 无生产消费点（KD-5）。

### KD-2 sidecar v10 字段 canonical 形（T1，RESEARCH §3.1/§3.4/§4）

- 字段 = `public var process: RenderProcessVersion?`，**canonical 规则一句话：
  nil ⇔ 键 ABSENT ⇔ 语义 legacy**。`init` 默认参 `process: RenderProcessVersion?
  = nil`（rawOverrides/displayTransform/versions/aiProvenance/filmRecord
  additive 族先例形）——既有测试的全部 fresh 构造零 diff。
- **decode**（`init(from:)` 内，自持 lenient 表，不借类型 Codable）：
  键缺席 → nil；键在 → `try?` Int（域门 `1...0xFFFF_FFFF`）→ 命中即
  `RenderProcessVersion(rawValue:)`（**前向大号原值保留**）；Int 失败 →
  `try?` Double 且 `value == value.rounded()` 同域 → 整值浮点（`2.0` → 2）；
  其余一切（0 / 负 / 2.5 / 字符串 / null / 数组 / 2^32）→ **nil（损坏值不
  保留）**。整个 decode 永不 throw——tolerant decode 纪律（其余字段全活）。
- **encode**：`if let process { try container.encode(process.rawValue, forKey:
  .process) }`——nil 保持 ABSENT。**stored-0 归一化**：`"process": 0` decode →
  nil → re-encode ABSENT（0 ≡ legacy 语义恒等，LightCraft
  `skip_serializing_if = "ProcessVersion::is_legacy"` 同构；负测钉死）。
- `schemaVersionCurrent = 10` + v10 注记段（v9 先例文风）：**「入册 ≠ 升级」**
  显式登记——9→10 只是键族入册，无联动迁移语义；无 process 键的 v10 档 = legacy
  （与 v9 无键档同语义）。未编辑的 v9 档不被重写（SidecarStore 只在 commit 后
  scheduleWrite）；被编辑的 legacy 档 re-save 为 v10（schemaVersion 反映 writer，
  既有惯例——memberwise init 恒写 current）但 `process` 键保持 ABSENT——「v9 档
  字节零改」承诺的精确范围 = **键面**（process 恒缺 + 既有键逐字节）。

### KD-3 App 载体三面（T3，rawDecodeOverrides/drtRecords/filmRecords 四件族同形）

- `WorkspaceModel`：`private(set) var processVersions: [String:
  RenderProcessVersion] = [:]`（per-url，session-scoped；**ABSENT 键 = legacy**——
  与 drt/film 载体的「默认不入 map」相反，process 的 legacy 是合法常态值，读面
  缺省 `.legacy`）。读面 `func processVersion(for url: URL) -> RenderProcessVersion`；
  恢复面 `func restoreProcessVersion(_ v: RenderProcessVersion, for url: URL)`
  （**无 coordinator 回写**——`restoreSessionOverrides` 同形：document 即本值
  之源，写回回声会 schedule 冗余 sidecar 写）；丢弃面
  `func dropSessionProcessVersions()`（关图丢弃族同批）。
- **无运行态写面**：M6-2 内 process 只在 load 腿两分支落载体（KD-4），无面板/
  命令/MCP 写路径（OQ-5 挂账）。

### KD-4 load 腿双分支与写腿（T3，RESEARCH §3.1 写腿判据）

- **prime 点** = `PipeCoordinator.load` 的 sidecar 探测双分支（:1153-1215 亲核），
  同一 actor turn 内、任何写可能之前：
  - 有档分支（`store.load()` 命中，restoreFromSidecar 同批）：载体 =
    `document.process ?? .legacy`（tolerant decode 已在 sidecar 层完成——损坏值
    已归 nil = legacy）；
  - pristine 分支（无档）：载体 = **`RenderProcessVersion.current`**（mint 盖章，
    imageID mint 同批语义）。
  - `historyLoadedURL == url` 切回路径零改（载体 map 持值，幂等）。
- **写点** = `makeSidecarDocument()`（:1445，唯一编辑写缝亲核——全部 schedule/
  flush 路径 :1554/:1562/:1597 单一汇入）：`process: carrier.rawValue == 0 ? nil
  : carrier`（legacy → 键 ABSENT 永不被动升级；非 legacy → 原值含前向大号不降级）。
  `workspace` 缺席（detached 测试）→ 读面缺省 `.legacy` → 无键档（G1② 形）。

### KD-5 管线缝 Core 侧 armed，coordinator 传值挂账（T2，RESEARCH §3.5 的最小忠实形）

- M6-2 落：`PixelPipe.renderProcess` run-scoped 属性 + `process`/
  `processComposite` 双入口 additive 参数（缺省 `.legacy` = 全部既有调用点与
  既有测试字节零变化）+ `PixelPipe.run` 将属性 stamp 入每个 `IOPiece.renderProcess`
  （iscale/pipeType「run 级常量 stamp 一次」同位；**不入 paramsHash 折叠**——
  piece 级 run 常量惯例）+ 内部派生 sub-run pipe（DrtTail 尾段 tailPipe :1075
  等）显式 inherit 同值（逐 `PixelPipe(` 内部构造点审计，additive 一行/处）。
- **不落**：PipeCoordinator → pipe 的生产传值（装配点调用点不传 = 缺省 legacy =
  与今日逐字节同）。理由 = 零消费即零行为，传值是无消费者的死接线；文档值 →
  pipe 的贯通由 G2③ 测试以「sidecar decode → 载体 → PixelPipe.process(renderProcess:)」
  显式证明。**首个真实分叉批的接线件**（coordinator 各 render 调用点读载体传值 +
  分叉 iop 消费 `RenderProcess.resolving(piece.renderProcess)`）→ DECISIONS 挂账
  登记（与 OQ-5 迁移 UX 挂账同批触发）。

### KD-6 分叉点折键契约（T1 头注 + DECISIONS，RESEARCH §3.3）

- M6-2 **零分叉 = `PipeCacheKey` 零改**（红线）；未来某 stage 按 process 选语义
  分支时，该 stage 的缓存身份折 process 值，折形 = **非 legacy 才折**
  （`process.rawValue > 0` 折值；0/缺键不折）——legacy 档键字节与今日恒等（
  `edgeMapAlgorithmVersion` :92-127 折键先例形）。契约登记处 =
  `RenderProcess.swift` 头注 + AGENTS.md 架构增量节 + DECISIONS。本批可测面 =
  「process 值不影响缓存键」（seam 测试：同链同参仅 renderProcess 异的两 run 键
  恒等 + 第二 run 命中）。

### KD-7 出生点盖章五面（T4，RESEARCH §3.7 表行兑现）

- 「新档 mint = current」的**全部首次建档点**，非仅 coordinator：
  ①coordinator pristine 载体（KD-4）；②`ImportService.mintProvenanceSidecar`
  （:675-694，AI 副本出生档）；③④`StackMergeService` 两出生点（:2220 HDR /
  :2676 Mertens+Pano——产物档恒新档）；⑤`SessionBatchApplier`（:126-140 pristine
  臂）+ `MetadataService`（:202-215 pristine 臂）——后两处同语义补盖（新建档 =
  本 build 产物，不留「出生即 legacy」的无法溯源类；legacy Session 域语义一致化）。
  **既有档臂分 writer 而论**：`MetadataService` 既有档臂**零改**（`mutate(&document)`
  :186-189 = 真 inout round-trip，既有字段含 process 全保——KD-2 canonical 形自动
  原值保全/legacy 恒 ABSENT）；`SessionBatchApplier` 既有档臂**非 round-trip**——
  :100-106 只从 decode 出的 document 提取 5 字段（`history`/`instances`/
  `decodeParamsHash`/`imageID`/`decoderVersionUsed`），随后与 pristine 臂共汇
  :136-144 同一 `LightamerSidecar(` 构造点重建**全新档**（文档级 additive 字段
  `provenance`/`rawOverrides`/`displayTransform`/`versions`/`activeVersionID`/
  `aiProvenance`/`filmRecord` 在既有档 batch apply 时今日已被静默丢弃——pre-M6-2
  数据保真缺口，M6-2 不修，DECISIONS 出范围登记）——process 须**显式携带**：
  :100-106 臂内把 `document.process` 提升为局部
  `existingProcess: RenderProcessVersion?`，构造点盖章走**分支条件式**（pristine
  臂 → `.current`；既有档臂 → `existingProcess`——nil = legacy = ABSENT，原值含
  前向大号照搬）。**禁用跨臂共享 `document.process ?? .current` 形**（nil 撞上
  `?? .current` = 给 legacy 既有档 mint，违反 OQ-1「永不被动升级」）。
  SessionBatchApplier 因此**不是零改**（+2 行 additive：一局部一参数）。
  字节面影响申报：Session 两 writer 的 mint 臂
  产物新增 `"process": 1` 键（新档，非既有档漂移）——若既有测试钉其全字节 →
  定向修 + DECISIONS 申报（G4 范围内行为变化）。

> checker 回注（2026-10-14）：E1——原文「既有档 read-modify-write 臂零改
> （decode→encode round-trip 经 KD-2 canonical 形自动原值保全）」把
> MetadataService 的真 round-trip 形（`mutate(&document)` :186-189）错误外推到
> SessionBatchApplier（实为 :100-106 字段挑选重建非 round-trip，:136-144 两臂
> 共汇全新档构造），已改写为分 writer 表述 + 分支条件盖章处方（禁
> `?? .current`）+ pre-M6-2 字段丢弃缺口出范围注记。依据 =
> `M6-2-CHECKER.md` E1 节源码亲核。

## read_first

1. `.work/gsd/phases/m6-2-process-version/M6-2-CONTEXT.md`（裁决记录 = 六项生效
   值正本）+ `RESEARCH-NOTES.md` §3（设计全文）/§4（v10 交互细则）/§5（golden
   四门）/§7（范围外）
2. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（v6-v9 注记族文风 +
   memberwise init 默认参惯例 + CodingKeys + decode `decodeIfPresent` 族 + encode
   `encodeIfPresent` 族 + `driftDetected` 面）
3. `App/Sources/Lightamer/State/PipeCoordinator.swift`（`load` :1127-1215 探测
   双分支 / `restoreFromSidecar` :1395+ / `makeSidecarDocument` :1445-1528 /
   restore legs :544/:577/:758/:774 / schedule+flush 汇入 :1554/:1562/:1597）
4. `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift`（:190-330 carrier 族：
   rawDecodeOverrides / drtRecords / filmRecords + restore/drop 面——KD-3 同形源）
5. `LightamerCore/Sources/Pipe/PixelPipe.swift`（:142/:155/:165 run-scoped 属性 +
   :2036-2070 `process` 入口 + :1075 尾段 tailPipe 派生点）+
   `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift`（:190-215 composite
   签名 + 内部 pipe 构造点）+ `LightamerCore/Sources/Pipe/IOPiece.swift`（iscale/
   pipeType run 常量 stamp 先例）
6. `LightamerCore/Sources/Pipe/PipeCacheKey.swift`（:92-127
   `edgeMapAlgorithmVersion` 折键先例）+ `LightamerCore/Sources/Pipe/History/
   HistoryHash.swift`（折叠五元与 modversion 折入点——零 diff 红线正本）+
   `LightamerCore/Sources/Pipe/History/ModuleInstance.swift:64-66`（modversion
   正交澄清）
7. 出生点四面：`LightamerCore/Sources/Stack/StackMergeService.swift` :2200-2245/
   :2655-2700 + `LightamerCore/Sources/Library/ImportService.swift` :660-694 +
   `LightamerCore/Sources/Session/SessionBatchApplier.swift` :100-146 +
   `LightamerCore/Sources/Session/MetadataService.swift` :180-215
8. `App/Sources/Lightamer/State/AdjustmentTransfer.swift`（isAdjustmentTransferable
   单谓词 + 传输面形状——Copy Adjustments 不携带负测的判据源）
9. `Tests/LightamerTests/FilmSidecarTests.swift`（byte-face 三档力学正本：
   digit-rewound 形 + canonicalEncoder + 逐字节断言式）+
   `Tests/LightamerTests/DrtTailTests.swift`（pipe 测试 harness + fence 形）+
   `Tests/LightamerTests/SidecarV5Tests.swift`（APP 真 load 链形）
10. `Scripts/test-direct.sh` + `.work/gsd/phases/m2-4-0-test-bundles/
    M2-4-0-BUNDLE-MAP.txt`（域模式与登记纪律）+ AGENTS.md M3-3/M4-1/M5-2 架构
    增量节（注记体例）+ L014/L041/L048/L070 家族

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter
  `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+
  `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh
  --bundle <域>`（直启宿主）；**全套 `--all` 需 orchestrator 批准，本 plan 收口
  轮才申请**；App bundle 轮前删孤儿
  `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（M4-1 挂账 #6 先例，跑前删
  跑后不复活即净）。
- **资源监控**（AGENTS）：测试宿主与 GUI 实例同名 Lightamer——清理进程前核
  parentage（M2-7-3 事故教训）。
- **L014 GPU fence**：seam 测试 GPU 读回走既有 pipe harness 的 fence 形
  （DrtTailTests 同源）；无 fence 的 GPU 计时/比较是假数。
- **L048 比较空间**：逐位比较 = 原样 f32 字节比（本批无色彩域换算面）。
- **L070**：不 push（推送收敛主会话）；零历史手术。
- 零 diff 红线自证（T5）：`git diff <基线>..HEAD -- LightamerCore/Sources/Pipe/
  History/HistoryHash.swift LightamerCore/Sources/Pipe/PipeCacheKey.swift
  LightamerCore/Sources/Pipe/History/HistoryStack.swift` 零命中 + MCP 快照族
  原样 + xcstrings/UserDefaults 零新键 + dependencies 块零 diff。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。
- 本 plan **无 GUI 走查面**（零 UI 面 = OQ-6 范围边界）——不产
  gui-acceptance MANIFEST；双重验收（config `dual_acceptance = true`，m1）照走。

## Tasks

### T1 Core 账本件 + sidecar v10（KD-1/KD-2）

- read_first 2/6 → `RenderProcess.swift` 新建（RenderProcessVersion + RenderProcess
  + resolving 钳制表 + 分叉点折键契约头注）→ `LightamerSidecar.swift`
  schemaVersionCurrent 9→10 + v10 注记段 + `process` 字段 + CodingKeys + decode
  lenient 表 + encode canonical 形。
- 验收：`SidecarV10Tests.swift`（LIB，15 法）——byte-face 三档
  （①v9 档 digit-rewound decode→re-encode 逐字节〔process ABSENT〕②v10 nil-face
  writer = v9 shape 仅差 schemaVersion 数字③process=1 档 round-trip byte-faithful）
  + hash isolation（同档 ± process → historyHash 逐字节同 + driftDetected 双
  false）+ lenient 合法域边界（1/2/0xFFFFFFFF 保全）+ `2.0`→2 + 损坏集全 nil
  （负/2.5/字符串/null/数组/2^32）+ stored-0 归一化 ABSENT + corrupt 存回 ABSENT
  + FUTURE-version（schemaVersion 11 照读）+ 域门构造/legacy/current 常量
  （current == 1）+ ALL/current 账本面 + resolving 钳制表（0/1/7/2^32−1 → v1）
  + 版本槽不承载（versions 链与 process 并存 round-trip）+ LightamerPreset 无
  process 键（预设不携带）。既有 sidecar 测试族原样绿（零编辑预期亲证）。

### T2 管线读缝 armed（KD-5/KD-6）

- read_first 5 → `PixelPipe` 属性 + 双入口参数 + IOPiece stamp + 派生 pipe 继承
  （逐内部构造点审计）+ `LayerCompositeDriver.composite` additive 参数与传递。
- 验收：`RenderProcessSeamTests.swift`（LAYERS，8 法，测试本地 double 模块
  ProcessProbeModule 读 `piece.renderProcess` 分叉输出——TestGainModule 同位
  test-local 形，独立 registry 实例不触生产 registry）——①IOPiece stamp 贯通
  （0/1 各一）②G3 零行为门：真实链 renderProcess 0 vs 1 渲染**逐位恒等**③G2①
  冻结门：double legacy 臂输出 = passthrough 基线逐位，且「分叉上线后」（同一
  build double 已带 ≥1 臂）legacy 值再渲染仍逐位 = 基线（跨模拟语义变更不变）
  ④G2② 分叉可见门：renderProcess 1 → 输出 ≠ passthrough（缝不是摆设）⑤G2③
  缺键 = legacy 臂：sidecar 无键档 decode → `.legacy` → pipe → double legacy 臂
  （sidecar→pipe 值流贯通）⑥缓存键面零变化：同链同参仅 renderProcess 异两 run
  → 键恒等 + 第二 run 命中 ⑦前向大号 pipe 面不降级：renderProcess = 7 →
  piece = 7 原值（钳制在 resolving 消费点）⑧派生 pipe 继承（尾段 sub-run 同值）。

### T3 App 载体与写腿（KD-3/KD-4）

- read_first 3/4 → `WorkspaceModel` 载体三面 → `PipeCoordinator` load 腿双分支
  prime + `makeSidecarDocument` 写值。
- 验收：`ProcessVersionCarrierTests.swift`（APP，8 法，真 load 链）——①mint 门：
  pristine（无 `.lra`）load → 一次编辑 → 落盘 `"process": 1` ②legacy 保全门：
  带编辑 legacy 档 load → 再编辑 → re-encode process ABSENT + 既有键逐字节
  （schemaVersion 10 = writer 面）③前向大号保全：手写 `process: 7` → load →
  编辑重存 7 保全 ④corrupt 档：手写 `"process": "x"` → load 成功其余字段全活 →
  重存无键 ⑤undo 到顶 + 版本 swap → 重存 process 仍 1（零 history item 面：
  items 无 process 字段 + 文档字段不变）⑥Copy Adjustments 不携带：源档
  process=1 → transfer → 目标 legacy 档重存仍 ABSENT ⑦关图丢弃 → 重开同档 →
  载体幂等恢复 ⑧workspace 缺席（carrier 无值）→ 写腿产出无键 v10 档。

### T4 出生点盖章（KD-7）

- read_first 7 → ImportService + StackMergeService×2 + SessionBatchApplier
  两臂（pristine 臂 `.current` 盖章 + 既有档臂显式携带，KD-7 分支条件式）+
  MetadataService pristine 臂（`.current` 显式盖章，additive 一参/处；Metadata
  既有档臂零改——真 round-trip）。
- 验收：additive 5 法——`StackMergeServiceTests`（IOP）+2（HDR 臂 / Mertens-Pano
  臂产物 `.lra` JSON 含 `"process": 1`）+ `ImportServiceTests`（LIB）+1（AI 副本
  出生档 =1）+ `SessionBatchApplierTests`（SESS）+1（pristine 臂 =1 + 既有档臂
  三态一法覆盖：legacy 保 ABSENT / process=1 保全 / 前向 7 保全——分支条件盖章
  后可测）+ `MetadataServiceTests`（LIB）+1（pristine mint =1 + 既有档保全）。
  既有 mint 臂字节断言若浮出 → 定向修 + 申报（KD-7 预登记）。

> checker 回注（2026-10-14）：E1——原文「既有档臂原值保全（零改前提下）」不可
> 实现（SessionBatchApplier 既有档臂非 round-trip），已改写为分支条件盖章前提
> 下的三态测试意图（pristine =1 / 既有档 legacy 保 ABSENT / process=1 保全 /
> 前向 7 保全），测试意图不变、修订后可测。依据 = `M6-2-CHECKER.md` E1 处方
> 第 2 步。

### T5 红线自证 + 文档同步（KD-6/KD-7 程序面）

- read_first 10 → 零 diff 机检族（HistoryHash/PipeCacheKey/HistoryStack 零命中 +
  MCP 快照族原样 + xcstrings/UserDefaults 零新键 + `Project.swift` dependencies
  块零 diff + 六格式导出面零触）+ AGENTS.md M6-2 架构增量节（process 账本开篇：
  号 0 = legacy 冻结档 / 号 1 = M6-2 基线；bump 纪律三层；「非 legacy 才折」契约；
  **M6 批 iop 调参类 plan 的 AC 模板行**：「若本 plan 改 iop 观感：bump process +
  冻结分支 + 新旧号 golden 三件套随批交付」）+ ROADMAP/REQUIREMENTS 状态注记 +
  GOAL-STATE 续接点 + TODO 同批。
- 验收：机检行全绿截屏入 SUMMARY；AGENTS 账本节与 `RenderProcess` case
  doc-comment 双源一致。

### T6 收口

- SUMMARY（任务序/bundle 分账/对账链）+ DECISIONS（KD 偏差/出生点字节面影响申报/
  钳制形式正确性注记〔M6-2 时点钳制目标 == legacy 行为，无观感差异——诚实申报〕/
  resolving 无生产消费点申报〔KD-5〕/coordinator 传值接线挂账/**E1 双登记**
  〔①pre-M6-2 数据保真缺口：SessionBatchApplier 既有档 batch apply 臂今日已静默
  丢弃文档级 additive 字段（provenance/rawOverrides/displayTransform/versions/
  activeVersionID/aiProvenance/filmRecord）——明确 M6-2 不修（范围纪律），挂观察
  项待未来 fix batch；②process 在本臂的携带 = M6-2 显式新增面（局部提升 + 分支
  条件盖章），非「自动保全」〕/**M1 双门分离注记**〔值类型域门
  `RenderProcessVersion.init?(rawValue:)` = `0...0xFFFF_FFFF`（含 0 = legacy
  哨兵）；sidecar 存储值 decode 域门 = `1...0xFFFF_FFFF`（stored-0/null/损坏 →
  nil 归一 ABSENT）——执行期不得照 OQ-3 散文表「合法域 = 0..2^32−1」把 stored-0
  保留为 0，KD-2 的 stored-0 归一化钉死面优先〕/**M4 ProcessProbeModule 可行性
  确认**〔`IOPModule.process(... piece: inout IOPiece)`（IOPModule.swift
  :125-130）+ `IOPiece` public struct（IOPiece.swift :30）+ `RenderProcessVersion`
  落 `LightamerCore/Sources/Pipe/` 与 IOPiece 同模块——T2 测试替身读
  `piece.renderProcess` 可见性无碍，TestGainModule test-local 先例在案〕）+
  `M6-2-01-ACCEPTANCE.md`（双重验收：zcode subagent 独立验收 PASS 后 → **串行**
  omp 二次验收，严禁并发——computer-use 单实例；FAIL 回注修复批后重走验收）。
- 验收：定向轮 `--bundle Library/Layers/App/IOP/Sessions` 全绿（exit 0 + 零
  MEMFAIL，SC 分账对表；拼写 = `Scripts/test-direct.sh` 注册表
  `BUNDLES=(IOP IOPParity Layers Library Sessions Export App)` :165——散文缩写
  LIB/LAYERS/APP/SESS 不入命令行）；**申请全套 `--all` 批准轮**（预期
  3721..3727/24/0，基线 3689/24/0 亲核在 plan 头）；ROADMAP M6-2 行 ✅ +
  REQUIREMENTS M6INT-01 兑现注记 + TODO 翻账同批。

> checker 回注（2026-10-14）：①M2——T6 定向轮命令原文缩写
> `LIB/LAYERS/APP/IOP/SESS` 改为注册表拼写 `Library/Layers/App/IOP/Sessions`
> （执行命令须过 `test-direct.sh` case 匹配；散文缩写仍是 BUNDLE-MAP/m6-1 既定
> 词汇，AC8/正文分账不改）；②DECISIONS 登记面扩容 = E1 双登记 + M1 双门注记 +
> M4 可行性确认（checker 处置摘要 1/2 步 + M1/M4 处方）。依据 =
> `M6-2-CHECKER.md` E1/M1/M2/M4 节。

## 验收标准（AC 总表）

1. **OQ 生效值①（键面）**：`process` 键拼写冻结 + v10 bump + 三则语义钉死
   （缺键 = legacy 恒 ABSENT 负测 / 新档 mint = 1 / 语义冻结纪律登记）；
   「入册 ≠ 升级」注记在案。【T1/T3/T4】
2. **OQ 生效值②（hash 与缓存纪律）**：hash isolation 负测（historyHash 逐字节
   同 + driftDetected 双 false）+ 零 history item（undo/swap 零触 + items 无
   process 字段）+ Copy Adjustments/预设不携带双负测 + 分叉点折键契约
   （「非 legacy 才折」三处登记：头注/AGENTS/DECISIONS）+ M6-2 缓存键面零变化
   测面。【T1/T2/T3】
3. **OQ 生效值③（lenient 读腿）**：合法域 0..2^32−1（含 `2.0`→2）边界表 +
   损坏集全 nil 不毁档 + 存回 ABSENT + 前向大号保留（存回不降级）+ 渲染钳
   （resolving 钳制表测试 + pipe 面原值贯通）。【T1/T2/T3】
4. **OQ 生效值④（零行为基线）**：process 0 与 1 渲染**逐位恒等**（G3）+
   `RenderProcess` 枚举 compiler-exhaustive + case doc-comment 账本 + AGENTS
   bump 纪律三层在册 + **零演示性 bump**（`git log` 面无 iop 观感改动佐证）。
   【T2/T5】
5. **OQ 生效值⑤（迁移 UX 挂账）**：零迁移 UI/命令/MCP 面（红线自证：无新
   xcstrings 键 + MCP 快照族零 diff + 无新菜单/面板文件）；挂账登记于
   DECISIONS + GOAL-STATE 续接点。【T5/T6】
6. **OQ 生效值⑥（golden 四门）**：G1 additive 零漂移负测（byte-face 三档 +
   hash isolation + 键面零变化）✓ + G2 冻结语义 golden（冻结门/分叉可见门/
   缺键 = legacy 臂三式）✓ + G3 读缝零行为门（0/1 逐位恒等 + parity/snapshot
   族零 diff）✓ + G4 mint/传输面（五出生点盖章 + legacy 编辑重存 ABSENT +
   传输零携带 + corrupt 存回无键）✓。【T1/T2/T3/T4】
7. **零回归门**：HistoryHash/PipeCacheKey/HistoryStack 逐字节零 diff + MCP 20
   工具封闭集快照族零 diff + 六格式导出矩阵零触 + QuickLook/Spotlight appex
   零触 + `.lalb` schema/LightamerPreset/FilterPredicate 零触 + xcstrings/
   UserDefaults 零新键 + `Project.swift` dependencies 块零 diff + 既有
   sidecar/parity 测试族原样绿。【T5】
8. **SC 数字门**：LIB +17 / LAYERS +8 / APP +8 / IOP +2 / SESS +1 定向对表
   （含既有文件 additive 5 法）；全套预期 **3721..3727/24/0**（批准轮对账，
   基线 3689/24/0 亲核记录在 plan 头）。【T6】

## 风险与边界

- **schemaVersion bump 波及面**：全部 byte-face 测试族符号化引用
  `schemaVersionCurrent`（亲核 grep 在案）→ 零编辑预期；隐藏字面量断言浮出 →
  定向修 + DECISIONS 申报。
- **fresh-init 档 v10 无键 vs v9 时代 v9 无键**：唯一 diff = schemaVersion 数字
  ——G1② 钉死并显式申报（「v9 档字节零改」承诺范围 = 键面）。
- **前向大号 + 渲染钳**：M6-2 时点钳制目标（v1）== legacy 行为（无分叉）→
  钳制测试证「形式正确性」非「观感差异」——DECISIONS 诚实申报。
- **IOPiece additive 字段**：memberwise 默认参保全既有构造点；piece 非 Sendable
  契约不破；`renderProcess` 不入 paramsHash（run 常量惯例）——若 checker 揪
  `IOPiece` Equatable/Hashable 合成面 → 该类型无合成 Equatable（逐字段 public
  var，无协议声明，亲核）零影响。
- **出生点盖章改 Session legacy 域 mint 臂字节面**：新产档 +`"process": 1`
  （非既有档漂移）；既有断言定向修 + 申报（KD-7 预登记）。
- **resolving 生产零消费点**：缝 armed 契约 + 账本即文档；unused 观感 →
  DECISIONS 申报（KD-5 挂账同文）。
- **“process 与 modversion 正交”误接线风险**：执行期**禁止**把 process 折入
  `ModuleInstance.version` 或 HistoryHash（两机制各管一域，RESEARCH §3.6）——
  T5 零 diff 机检兜底。
- **APP bundle 贴线**：IOP/IOPParity 本批零触碰（预期零漂移）；新 APP 法均为
  载体/写腿面，无重测族。

## 提交约定

- T1 `feat(core): render process version type and sidecar v10 process key`
- T2 `feat(core): run-scoped render process seam in the pixelpipe`
- T3 `feat(app): per-image process carrier with mint-on-first-document write leg`
- T4 `feat(core): stamp current process on merge, ai-copy and session birth sidecars`
- T5 `docs: register the process version ledger and bump discipline`
- T6 `docs(m6-2): close the process-version batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。
