# M6-2 RESEARCH NOTES — per-photo process version

> Phase = M6-2（Roadmap §Milestone 6 M6-2 行 / REQUIREMENTS M6INT-01）。本文 =
> 设计全文正本；裁决面 = 同目录 `M6-2-CONTEXT.md`（OQ-M6-2-1..6 全带推荐）。
> 设计底稿 = `phases/m6-1-interop/RESEARCH-NOTES.md` §6（前瞻 B，本批展开细化）；
> LightCraft 调研正本 = `research/LIGHTCRAFT-NOTES.md`（裁决③）。
> 日期：2026-10-13（M6-1 VALIDATION 签核后接棒批）。

## 1. 缺口定位：iop 调参漂移真缺口

### 1.1 现状

`.lra` sidecar 承载非破坏编辑真相（`instances[]` + `history` + 文档级记录族）。
iop 渲染语义（kernel 公式、tone model、slider 响应曲线、默认曲线）在**代码里**，
不在档里——同一段 params 在不同 build 下可以渲染出不同观感。目前改 iop 观感
（nlmeans 重调、tone model 变更、M5 TRACK/Mertens 后续调优）会让**全部老
`.lra` 静默漂移**：重算的渲染与用户存档时的观感脱节，且无任何机制察觉。

### 1.2 现有兜底与其不足

| 既有机制 | 覆盖面 | 对「语义变更」的不足 |
|---|---|---|
| `schemaVersion`（现 = 9） | **容器形状**迁移（键族入册、tolerant decode、typed degrade） | 只管 JSON 结构，不管像素语义；无 per-档语义选择 |
| `ModuleInstance.version`（modversion 类比，`ModuleInstance.swift:64-66`） | **params 形状**迁移（Params 结构变更） | ①语义变更通常不改 params 形状，触发不了；②该字段折入 `HistoryHash.hash`（`HistoryHash.swift:54-57`）——bump 即全量老档假阳 external-edit drift，**不可用作语义变更载体**（§3.6 澄清） |
| `decoderVersionUsed` 盖章（`LightamerSidecar.swift:221-230`） | decode 侧半例：记录产档时的 decoder，drift 重算用档内自有 `decodeParamsHash`（decoder 升级不假阳） | 只记录不门控；渲染侧无对应物 |
| `driftDetected`（HIST-04/SC#5） | 外部编辑检测（重算 historyHash 比对） | 检测的是「档被外部改过」，不是「代码语义变了」 |

结论：**per-photo process version 是该缺口的根治纪律**——把「渲染语义代际」
变成档内一等数据，语义变更开新号、旧号冻结，老档渲染零漂移直至显式迁移。
LightCraft 实测该机制零成本移植（sidecar additive + hash 旁路），M5 落地后
调参概率升高，越早越省（`LIGHTCRAFT-NOTES.md` §3 表第 3 行 + OQ-LC-3）。

## 2. LightCraft 参考面（转录正本）

来源：`/Volumes/UNITEK/Documents/Development/lightcraft`（HEAD `25ef65c`，0.7.0）
`docs/process-versions.md` + `crates/develop/src/settings.rs` +
`crates/develop/src/tests_process.rs` + `crates/pipeline/src/local.rs`。
MIT OR Apache-2.0 双许可——**思想/命名/机制转录合法；本批零代码移植**
（Swift 实现为独立写作；若未来成段移植须 NOTICE 同 commit 登记，
`spectral_film_lut` 先例形）。

### 2.1 核心机制（settings.rs）

- **`ProcessVersion(pub u32)`** transparent newtype = 档内存储形态（纯数字）。
- **`Process` 枚举**（V1/V2）= 本 build 实现的渲染过程集；`ALL`（oldest first）+
  `LATEST` 常量；**对 `Process` 的 match 全部穷举**——加新 process = 编译器逐点
  指向所有语义分叉处（`docs/process-versions.md` "Adding a process" 第 2 步）。
- **`process()` 钳制**：存的号比本 build 新 → 渲染钳到已知最新；比 V1 小 → V1。
  前向兼容：新版本写的档在旧 build 可读可渲染。
- **宽容反序列化**：整数 0..2^32−1 合法（`2.0` 记 2）；其余一切（负数/小数/
  文本/null/数组）→ `legacy()`（= V1），**损坏值不毁档其余字段、不保留**
  （存回即 V1）。
- **缺键 = V1（字段级 default），新档 = LATEST（struct 级 Default）**——两级
  default 分离是「老档冻结 / 新档现行」的机制本体。
- **`skip_serializing_if = "ProcessVersion::is_legacy"`**：V1 不序列化——
  process 版本化之前存的档 re-save **逐字节不变**，preview cache key
  （`hash64`）逐字节不变。**这是 legacy 零漂移的序列化面技巧**。
- **Copy/paste/sync/presets 永不携带 process**（不在任何 settings group 内）；
  目标照片按自己的 process 解释粘来的参数。部分 settings JSON 显式点名
  `process` 才会设置它。
- **Update to Current Process**（`develop.updateProcess`）：显式迁移，一步
  undo；Reset 也落到 LATEST；版本/历史恢复回到「它当时的 process」。
- **缓存按 process 键控**：分叉阶段的中间面缓存键含 process
  （`local.rs` `BaseKey`——`sigma.to_bits(), s.process.process(), detail`）。
- **语义分类纪律**（docs "The rule"）：改观感（tone model/slider 响应/默认
  曲线/阶段解释方式）→ 新 process；**修 bug 让坏输出变正确**（crash/NaN/
  黑图/decoder 错/CPU-GPU 不一致）→ 不是 look，原地修；decode/相机色域变更
  改的是源，process 管不着。

### 2.2 golden 先例（tests_process.rs）

`settings_saved_before_process_versions_load_as_v1`：内嵌「process 版本化之前
的完整 settings JSON」fixture（无 `process` 键）——断言 ①载入 = V1 数字
（非 LATEST：新号上线后它仍钉住全部既有 catalog/sidecar/preset 的渲染）；
②最小档 `{}` 也 = V1（含嵌套在 history/versions 里的 settings）；③re-save
不添键（文件与 cache key 原样）。另有双 process 渲染对比（程序化场景）+
`docs/parity-checklist.md` 更新步骤。

## 3. 我方设计

### 3.1 键面（OQ-1）

`.lra` 文档级 additive 可选键：

```json
{ "schemaVersion" : 10, ..., "process" : 1 }   // 新档（mint 盖章 current）
{ "schemaVersion" : 10, ... }                  // legacy 档（键恒 ABSENT）
```

- **拼写**：`process`（LightCraft 同名；单词无 camelCase/蛇形歧义）。plan 期冻结。
- **类型**：`Int?`（Swift 面）；合法域 0..2^32−1（§3.4）。
- **缺键语义** = legacy = `0` = **冻结**（M6-1 前瞻 §6.1 定式：0 = pre-process
  哨兵，与任何真实 process 号分离；LightCraft 用 V1=1 是因其 V1 本就是命名过
  的历史渲染，我方 M6-2 引入概念前的渲染记 0 更诚实）。
- **写腿**（唯一缝 = `PipeCoordinator.makeSidecarDocument()`，
  `App/Sources/Lightamer/State/PipeCoordinator.swift:1445`）：
  - 档来自磁盘且无键（legacy）→ 恒写 ABSENT（`encodeIfPresent`）——
    **永不被动升级**（零漂移承诺本体）；
  - 首次建档（盘上无 sidecar，imageID mint 同批）→ 盖章
    `RenderProcessVersion.current`（起步 = 1）；
  - 档来自磁盘且带键 → 原值回写（含前向大号——不降级用户数据，§3.4）。
  - 写腿判据 = restore 腿记载的「载入值 + 文件在否」二态（plan 期落具体
    carrier 形态；语义钉死 = 上三行）。
- **schema 承载**：`schemaVersionCurrent` 9→10（v6/v7/v8/v9 每 bump 各承载
  其键族的惯例延续；tolerant decode 保 v9 档可读）。注意面：未编辑的 v9 档
  **不会**被重写（SidecarStore 只在 commit 后 scheduleWrite——盘上保持 v9
  原样）；被编辑的 legacy 档 re-save 为 v10（schemaVersion 反映 writer，
  既有惯例）但 `process` 键保持 ABSENT——「v9 档字节零改」承诺的精确范围 =
  **键面**（process 恒缺 + 既有键逐字节），负测按此钉（§5 G1）。
- 被否形态：additive-in-v9 不 bump（破惯例、v9 语义膨胀）；独立文件；
  per-instance / per-history-item 粒度（process 是文档级渲染语义）。

### 3.2 hash 纪律：hash isolation（OQ-2）

- **`process` 不折入 `HistoryHash.hash` / `driftDetected`**（v3 五元数据 D-8 /
  v4 provenance / v5 rawOverrides / v7 versions / v8 aiProvenance 先例族）：
  它是渲染语义标签非用户像素编辑。`makeSidecarDocument` 的 historyHash 实参
  五项（`stack / decodeParamsHash / layerSnapshot / drtRecord / filmRecord`）
  **零变化**——折叠公式与既存档逐字节稳定。
- 被否 = set-fields-move（v6 drtRecord / v9 filmRecord 先例形）：那条路的
  前提是「用户改了它 → 缓存/漂移面该动」；process 恰恰相反——**未来语义
  升级（bump current）绝不能让老档误报 external-edit drift**，也不能让
  老档缩略图失效。折 hash = 每次语义升级全量假阳，与本 phase 目标正面对撞。
- **零 history item**：process 变更（mint 盖章/未来显式迁移）不走
  `recordChange`——undo/redo/jump 面零触；文档级常量跨编辑历史恒定
  （LightCraft「Restoring a version or history step: the one it had」在我方
  文档级模型下的对应物 = undo/版本 swap 永不触碰 process）。
- 面向 M2-8 版本体系：process 是**文档级**，跨 versions 槽共享（版本 swap =
  history 链换装，不触 process）。与 LightCraft 的 per-settings 快照形态
  显式偏离，登记为有意决策（我方版本槽不承载渲染代际——代际是整档属性）。

### 3.3 缓存纪律：分叉点折键（OQ-2 附则）

- `PipeCacheKey.upstreamHash` 链（`decodeParamsHash` 种子 + 逐 instance
  `paramsHash`）**零结构性变化**。
- process 折键**只发生在真分叉的代码路径**：未来某 iop stage 按 process
  选语义分支时，该 stage 的缓存身份折 process 值——精确先例 =
  `edgeMapAlgorithmVersion`（`PipeCacheKey.swift:92-94`：算法版本折入
  edge-map 键，kernel 变更作废缓存）。DRT 尾平面（`DrtTailAssembly.seed`）
  与 film sub-run seed 若分叉同理折入。
- **M6-2 时点零分叉 = 键面零变化**；legacy 档（缺键 = 0 恒）在任何分叉
  上线后键面也只受「0 折入」影响——为保持 legacy 档键面**逐字节不变**，
  折键形态 = **非 legacy 才折**（`process > 0` 时折值；0/缺键 = 不折，
  与今日键字节恒等）。plan 期以负测钉死。

### 3.4 读腿宽容性与前向兼容（OQ-3）

LightCraft lenient 原形移植（`settings.rs:25-40`）：

| 输入 | 判定 |
|---|---|
| 整数 0..2^32−1 | 该 process 值 |
| `2.0` 形整数值浮点 | 2 |
| 负数 / 非整浮点 / 字符串 / null / 数组 / 域外大数 | **legacy（0）**——不毁档其余字段（tolerant decode 纪律），损坏值不保留（存回 = 键 ABSENT） |
| 比本 build 已知更大的整数 | **保留原值**（存回不降级）+ 渲染钳到 `RenderProcess.current`（前向兼容：新 build 写的档旧 build 可读可渲染） |

### 3.5 Core 面与管线读缝（OQ-4）

- **`RenderProcessVersion`**（Core，`LightamerCore/Sources/` 落位 plan 期定，
  建议 `Pipe/` 或 `Foundation/`）：Int 值类型 + `legacy = 0` 哨兵 +
  `current` 常量（起步 = 1）+ 宽容 decode 构造器（§3.4 表）。
- **`RenderProcess` 枚举**：compiler-exhaustive；`ALL`（oldest first）+
  `current`；**case doc-comment 即账本**（LightCraft `Process` 枚举先例——
  每 case 注明「该代际改了什么」；M6-2 时点单一 case = M6-2 时代渲染）。
  未来加 case = 编译器逐点指向所有需分叉的 match。
- **管线读缝**：`PixelPipe` 装配点 run-scoped 属性（缺省 = legacy）——
  `terminalTail` / `filmTail` 同位先例（`PixelPipe.swift:2045-2114` 装配
  factory）。文档值流向：sidecar decode → restore 腿记载 → pipe 装配只读
  消费。M6-2 无任何消费点（零分叉）——缝在位、armed、零行为。
- **运行态不设写路径**：M6-2 内 process 只在 mint 盖章与原值回写两处落笔；
  无面板/命令/MCP 写面（迁移 UX 挂账，OQ-5）。

### 3.6 与 `ModuleInstance.version`（modversion）的正交澄清

- `ModuleInstance.version` = **params 形状**代际（Params 结构迁移，decode 域）。
- 折叠面不同：modversion 折 `HistoryHash`（bump = 全量老档假阳 drift——
  形状迁移必须让缓存/漂移面动，合理）；process **不折**（语义升级必须让
  老档纹丝不动，反向需求）。
- 纪律登记：**语义变更 ≠ modversion bump**（除非 params 形状恰好也变）；
  语义变更的唯一载体 = process bump。两机制并存、各管一域。

### 3.7 交互面清单（M6-2 全部零触或负测钉死）

| 面 | 行为 | 机制 |
|---|---|---|
| Copy Adjustments（M2-8） | **不携带 process** | 文档级键不在 `isAdjustmentTransferable` 集；负测钉死（LightCraft「copy/paste/sync/presets never carry」同构） |
| 预设 apply / apply_params | 不触 process | params 面与文档键正交 |
| undo / redo / jump / 版本 swap | 零触 | 无 history item（§3.2） |
| merge 产物（Pano/Mertens/HDR）/ AI 副本 | **新档 mint = current** | 首次建档盖章（§3.1 写腿） |
| 缩略图 / preview 缓存 | legacy 档零失效 | hash isolation + 分叉点折键（§3.3） |
| MCP 20 工具封闭集 | 零新工具、零参数变化 | 范围边界（D-M6-2-6）；快照族零 diff |
| 六格式导出矩阵 | 零触 | 导出按档自有 process 渲染（M6-2 无分叉 = 现行为） |
| Lightroom 式外部语义（未来 `crs:` 类） | 不适用 | 我方无外部渲染器导入面 |

### 3.8 bump 纪律的程序面（OQ-4 附则）

无 CI 可机检「语义变更」（观感判定是人的裁决），纪律 = 三层：

1. **枚举账本**：`RenderProcess` case doc-comment + `docs` 级登记（AGENTS.md
   架构增量节追加「process 账本」小节——每号一行：号 / 落地 batch / 改了
   什么观感 / 冻结分支位置）。
2. **冻结 golden 常青**：每 bump 必须为新旧号各钉渲染 golden（§5 G2 扩展）
   ——变更者被迫直面料间差异。
3. **phase gate 措辞**：ROADMAP M6 批内 iop 调参类 plan 的 AC 模板加一条
   「若本 plan 改 iop 观感：bump process + 冻结分支 + golden 三件套随批交付」
   （plan 期由 planner 落实；M6-2 自身不改任何 iop 观感）。

## 4. schema v10 交互细则（OQ-1 附则）

- **tolerant decode 链**：v10 reader 读 v9 档 = `process == nil`（legacy）；
  读 v11+ 档（未来）= FUTURE-version 分支 degrade 语义原样（`LightamerSidecar
  .swift:98-100` 既有纪律）。
- **byte-face 负测三档**（沿用 SidecarV7/V8/V9Tests 三 byte-face 惯例）：
  ①v9 档（无键）decode→re-encode（schemaVersion 面 bump 为 10）——
  `process` 键 ABSENT + 其余键逐字节；②v10 无 process 档 re-encode 逐字节
  （含 schemaVersion 10 原样）；③v10 带 process=1 档 re-encode 逐字节。
- **升级不迁移**：schemaVersion 10 与 process 键**无联动迁移语义**——
  9→10 只是键族入册；无 process 键的 v10 档 = legacy（与 v9 无键档同语义）。
  「入册 ≠ 升级」显式登记，防误读。

## 5. golden 门集（OQ-6）

| 门 | 内容 | 对应 ROADMAP 验收形态 |
|---|---|---|
| **G1 additive 零漂移负测** | §4 三 byte-face + legacy 档 historyHash 重算零漂移 + `PipeCacheKey` legacy 键面零变化（分叉点折键的「非 legacy 才折」负测） | 「sidecar additive 零漂移负测（v9 档字节零改）」 |
| **G2 冻结语义 golden** | 测试替身模块按 process 分叉输出（test registry 注册，legacy 臂 = 现渲染 / 新 process 臂 = 可见差异）：①legacy 档跨「模拟语义变更」渲染**逐位不变**；②新 process 臂分叉**真可见**（缝不是摆设）；③缺键档 = legacy 臂（LightCraft `settings_saved_before_process_versions_load_as_v1` 同构 + 双 process 渲染对比） | 「冻结语义 golden（同档跨 process 语义变更渲染逐位不变）」 |
| **G3 读缝零行为门** | process 0 与 1 渲染逐位恒等（M6-2 无分叉）+ 既有 parity/snapshot 族零 diff + 全套对账按 BUNDLE-MAP 预期申报 | 「管线 process 读缝零行为门」 |
| **G4 mint/传输面** | 新档首写 = `process: 1` 入档；legacy 档编辑重存键恒 ABSENT；Copy Adjustments / 预设 apply / 版本 swap 零携带；损坏值档 → legacy 且存回无键（§3.4） | mint 面补强（ROADMAP 三件之外，D-M6-2-6） |

测试落域：按 `M2-4-0-BUNDLE-MAP.txt` 域模式归入唯一 target（sidecar 面归
既有 sidecar 域 bundle；管线替身面按域登记），同批更新 `Project.swift` 显式
清单 + `tuist generate` 恒末位（L041）；跑法 `Scripts/test-direct.sh --bundle <域>`。

## 6. 迁移 UX（OQ-5）

- **v1 = 无显式迁移动作**。老档恒冻结（零漂移承诺本体）；首渲染差异在用户
  侧不可见（这正是卖点）。
- **「Update to Current Process」挂账**：首个真实 iop 语义 bump 落地时裁交互
  形态（面板按钮 vs 菜单项 vs MCP 工具；LightCraft `develop.updateProcess`
  一步 undo 形态为参考底稿——我方对应物 = 文档级离散 commit）。挂账登记 =
  本文档 + GOAL-STATE 续接点。
- 前瞻面（首个 bump 时需一并裁）：迁移是否产生 history item（推测：产生
  一枚离散 commit，使迁移可 undo——与 §3.2「零 history item」不冲突，那条
  说的是**语义升级不产生** item；**显式迁移是用户编辑动作，应当产生**）。

## 7. 范围外与挂账

- 零 MCP 工具面、零 UI 面、零格式矩阵触碰、零新 SPM、零 `.metal` 触碰。
- 不做：自动迁移、批量迁移、per-version process、per-instance process。
- 挂账：①「Update to Current Process」交互（首个真实 bump 时裁，§6）；
  ②首个真实 bump 的落地批（未来 iop 调参 plan 顺带）；③`RenderProcess`
  case 账本随首个 bump 开篇（M6-2 时点账本 = AGENTS 架构增量节本文）。

## 8. Sources

- 内部：`LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（schemaVersion
  9 / additive 纪律 / hash-isolation vs set-fields-move 两先例族 /
  `decoderVersionUsed` 盖章）/ `LightamerCore/Sources/Pipe/History/HistoryHash.swift`
  （折叠公式与 modversion 折入点）/ `LightamerCore/Sources/Pipe/History/
  ModuleInstance.swift:64-66`（modversion 类比）/ `LightamerCore/Sources/Pipe/
  PipeCacheKey.swift`（upstreamHash 链 + `edgeMapAlgorithmVersion` 折键先例）/
  `LightamerCore/Sources/Pipe/PixelPipe.swift:2045-2114`（装配点 run-scoped
  属性先例）/ `App/Sources/Lightamer/State/PipeCoordinator.swift:1445`
  （`makeSidecarDocument` 唯一写缝）
- 项目：`.work/gsd/ROADMAP.md` §Milestone 6 M6-2 行 / `.work/gsd/REQUIREMENTS.md`
  M6INT-01 / `.work/gsd/phases/m6-1-interop/RESEARCH-NOTES.md` §6（前瞻 B 底稿）/
  `.work/gsd/research/LIGHTCRAFT-NOTES.md`（§2 develop 面 + §六裁决③）
- 外部（只读，MIT OR Apache-2.0）：`/Volumes/UNITEK/Documents/Development/
  lightcraft`（HEAD `25ef65c`，0.7.0）——`docs/process-versions.md`（规则正本）/
  `crates/develop/src/settings.rs`（ProcessVersion/Process/宽容 decode/
  skip-serializing）/ `crates/develop/src/tests_process.rs`（golden 先例）/
  `crates/pipeline/src/local.rs`（BaseKey 按 process 键控）
