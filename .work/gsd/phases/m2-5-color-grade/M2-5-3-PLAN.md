---
phase: m2-5
plan: "M2-5-3"
title: "LUT 目录三件套（wave 3）——05 递归扫描 + registry 键升根相对路径（InstalledLut additive relativePath/subdirectory，旧行宽容迁移）+ 面板子目录树分组/折叠 + 手动刷新；06 LUT 根目录用户可配（UserDefaults lut.library.root + Settings 节 + 切根重建索引）；07 内置 Alcedo 同款胶片 LUT 集（许可门第一任务：上游 JanLohse/spectral_film_lut clone 核许 → bundle Resources vendor BuiltIn/ 首启拷贝 + LICENSE/NOTICE；非宽松 → 导入指南降级）+ phase 收口（zh-audit 对账补齐 + OQ-11 观察项三查 + GOAL-STATE 翻账）"
wave: 3
depends_on: ["M2-5-2"]
autonomous: true
requirements: [M2GRADE-05, M2GRADE-06, M2GRADE-07]
files_modified:
  - LightamerIOP/Sources/Lut3d/LutLibraryStore.swift            # 修改：rescan() 攂 enumerator(at:) 递归枚举 + registry 键升根相对路径（旧行 = 根下文件名，decode 宽容迁移）+ InstalledLut additive 字段（relativePath/subdirectory）+ 同名冲突 display 消歧（子目录前缀）+ root 配置注入（init(directory:) 既有缝消费 UserDefaults）+ 内置集首启拷贝 seeder（07）
  - App/Sources/Lightamer/UI/Inspector/LutPanelView.swift       # 修改：库 Picker 升子目录树分组/折叠 + 手动刷新按钮 + 面板打开触发 rescan；缺引用 blit identity + toast 既有语义零改动消费
  - App/Sources/Lightamer/Settings/SettingsPages.swift          # 修改：Settings 新节「LUT Library」——根目录选择器（NSOpenPanel 目录选择 + 当前根显示 + 重置默认）+ 切根重扫进度/结果反馈
  - App/Sources/Lightamer/Library/AppPreferences.swift          # 修改：UserDefaults 键宿主（lut.library.root，ImportDefaults 同款登记惯例 + reset 面）
  - Resources/Localizable.xcstrings                             # 修改：LUT 树分组/Settings「LUT Library」节/导入指南新键随手键入账（zh 值 T6 收口批补——D12；checker E8 补申报）
  - AGENTS.md                                                   # 修改：UserDefaults 键登记补 `lut.library.root` 行 + M2-5 架构增量段（T6 action 5 翻账的申报落点——checker E8 补申报）
  - Project.swift                                               # 修改：Resources 登记（44 张 .cube + LICENSE/NOTICE，T1 许可门通过才入）+ 新测试文件登记（bundle 无 glob——checker E2 纪律）
  - Resources/LUTs/                                             # 新建（T1 许可门通过才 vendor）：Agfa_*/Fuji_*/Kodak_*.cube 44 张 + LICENSE + NOTICE（CMake glob 清单对照，Hasselblad/「色彩逆向」不入——M2GRADE-07 字面）
  - Tests/LightamerTests/LutLibraryRecursionTests.swift         # 新建（LightamerTestsIOPParity——Lut3d* glob 惯例，IOP 级）：fixture 树 3 层深递归收录 / 同名冲突消歧 / 旧 registry.json 宽容 decode / 键迁移幂等 / 切根重建 / 坏根降级 / 引用缺名 degrade / seeder 幂等
  - Tests/LightamerTests/BuiltInLutSetTests.swift               # 新建（LightamerTestsApp，App 级——读 app bundle Resources）：内置集恰 44 张（CMake 清单对照常量）+ LICENSE/NOTICE 在包 + 首启拷贝到默认根 BuiltIn/ 子目录 + 二次启动零重复拷贝
  - .work/gsd/phases/m2-5-color-grade/M2-5-3-SUMMARY.md         # 新建（收口任务）
  - .work/gsd/phases/m2-5-color-grade/M2-5-3-DECISIONS.md       # 新建（收口任务）
  - .work/gsd/phases/m2-5-color-grade/evidence/spectral-film-lut-license.md  # 新建（T1 许可门证据：clone tag/SHA、LICENSE 原文摘录、CMake 清单对照表、许可结论）
  - .work/GOAL-STATE.md                                         # 修改：M2-5 翻账（收口任务）+ 阻塞（需人工）登记如 T1 非宽松
  - .work/LESSONS.md                                            # 如踩坑
---

# Plan M2-5-3 — LUT 三件套（05/06/07）+ phase 收口

> **性质**：资产/存储 plan——渲染管线零改动（`LayerCompositeDriver`/`PixelPipe`/
> `PipeCacheKey`/`Lut3dModule` kernel 面零 diff；`lut3d` params 的 `lutName` 语义 =
> 库键，本 plan 升级键的**编码**而非引用语义）。三件套执行序 = **05 → 06 → 07，07 许
> 可门前置为第一任务**（D-M2-5-CONTEXT-7 A：许可未过前内置集打包路径悬空）。
> 收口 = phase 级：zh-audit 对账补齐（D12 预估 100–140 键）+ OQ-11 观察项三查 +
> GOAL-STATE 翻账。规格锚点 = D-M2-5-CONTEXT-6/7/11/12 + REQUIREMENTS M2GRADE-05/06/07。

## 已定裁决（不得重开）

- **D-M2-5-CONTEXT-6（OQ-7 A）**：执行序 05→06→07 且 07 许可门前置；05 = `enumerator
  (at:)` 递归 + registry 键升根相对路径（旧行 decode 宽容 = 根下文件）+ `InstalledLut`
  additive `relativePath`；06 = UserDefaults `lut.library.root` + registry.json 跟根
  走（每根一份自洽库）+ 切根整库重扫 + 坏根 degrade 兜底；07 = 上游原生获取 + 宽松
  许可才入包（BuiltIn/ 首启拷贝 + LICENSE/NOTICE 署名）+ 非宽松降级设置页导入指南 +
  登记阻塞（需人工）；FSEvents watcher = v2 不做（刷新 = 面板打开 rescan + 手动按钮）。
- **M2GRADE-07 字面**：目标集 = CMake 打包 glob 的 `Agfa_*/Fuji_*/Kodak_*.cube`（44
  张）；Hasselblad 两张 33³ 与「色彩逆向」子目录 = 用户自放，不入目标；**禁从
  AlcedoStudio GPL 仓拷任何数据文件**（其公开仓 config/LUTs 已查不存在）。
- **D-M2-5-CONTEXT-11（OQ-11 A）**：性能观察项挂账不设优化门——本 plan 收口执行三查
  走查（≥4 Grade 层拖滑杆 / FULL 100MP 导出 ±5% 带内 / LUT 万文件 rescan 耗时）。
- **D-M2-5-CONTEXT-12（OQ-12 A）**：zh 键随手键 + 本 plan 收口 `Scripts/zh-audit.py
  --check` 对账补齐；语言 code 沿 `zh`。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 registry 键升级 = 根相对路径一处升级承载三件事（CONTEXT 事实基线③）

- **键空间**：`installed`/`parsed` 字典键从 `InstalledLut.name`（文件名）升级为
  `relativePath`（相对库根，POSIX 分隔，如 `"BuiltIn/Fuji_XXXX.cube"`）；库根直下
  文件的 relativePath == 文件名（退化情形 = 旧行语义）。
- **旧行宽容迁移（KD 必答）**：decode `InstalledLut` 时 `relativePath` 缺失 →
  推导 = 键本身（旧行键即文件名，等价根下文件）→ 迁移后写回（首次 rescan
  persistRegistry 自然落盘升级版）——**registry.json decode 对缺字段宽容（合成
  decodeIfPresent additive），对键形态零校验**；同名冲突不可能出现在旧行（平面键空
  间本就唯一）。
- **引用兼容**：`lut3d` params `lutName` 存的库名引用——**引用键与 registry 键同步
  升级**。旧档（引用 = 文件名）加载：resolution 顺序 = 精确 relativePath 命中 →
  失败则「文件名尾段匹配」fallback（`installed.values.first { $0.relativePath
  .hasSuffix("/" + name) || $0.relativePath == name }`，唯一命中才解析，多命中 =
  degrade）——**旧档零改写**（引用字节不动，resolution 层兼容），新写入恒存
  relativePath（面板选择时写 relativePath）。跨子目录同名消歧 = relativePath 天然
  唯一；display 名撞车加子目录前缀（面板层呈现）。
- **自愈/degrade 语义零改动**：rescan 三段式（失效行删除 / 内容漂移重解析 / 未注册
  采纳）与 blit identity + toast（`isMissing` 路径）原样保留——只换枚举广度与键
  编码，不换行为。

### KD-2 递归扫描 = FileManager.enumerator(at:) + 跳隐藏目录 + 规模上限 sanity

- `rescan()` 采纳段改 `enumerator(at:includingPropertiesForKeys:[.isDirectoryKey])`：
  递归收录 `.cube`（`supportedExtensions` 既有集合）；跳过 `.` 前缀目录
  （`.lathumbs` 式派生物/隐藏目录不入库）+ 跳 `registry.json`；`BuiltIn/` 子目录与
  用户 LUT 天然分组隔离（07 seeder 落点，普通递归成员——无特判，分组即目录）。
- **万文件 sanity（OQ-11 三查之一）**：测试含 500 文件 × 3 层 fixture 树 rescan 耗时
  断言（软上限 5s @ DEBUG——非硬性能门，防意外 O(n²)）；真实万文件走查留收口三查。

### KD-3 可配根 = store 实例按根重造，bookmark 仅重验不新建

- UserDefaults `lut.library.root`（String path，空/缺 = 默认根
  `~/Library/Application Support/Lightamer/LUTs/`）；`LutLibraryStore` 消费点 =
  `init(directory:)` 既有注入缝——Settings 切根后**重造 store 实例**
  （`AppPreferences` 提供 `lutLibraryRoot() -> URL`）；registry.json 跟根走（每根
  自洽，KD-1 迁移按根独立发生）。
- **shared holder 机制（checker m6）**：`LutLibraryStore.shared` 既有 `static let`
  升级为可替换 holder——`private static var _shared` + `NSLock`（`shared` getter
  锁内读、`replaceShared(_:)` 锁内原子换；切根 = Settings 主线程调 `replaceShared`
  后既有消费点经 getter 恒取新实例）；机制**内联于 `LutLibraryStore.swift`**（不新
  建 holder 文件——front-matter 零新增；`ModuleRegistry` 等 registry 面零触碰、
  **不入 front-matter**）。
- **外置卷/可达性（L009 教训）**：仅做存在性重验（`isDirectory` + 可写探测）；失败 =
  typed 降级回默认根 + Settings 节错误文案（**不新建 bookmark**——12-4 D10 例外不扩
  展，路径存 String 的脆弱性以降级兜底，v2 再议 security-scoped bookmark）。
- **引用缺名 degrade 零改动**：切根后被引用 LUT 缺失 → 既有 blit identity + toast
  （KD-1 resolution fallback 在新根内跑，跨根不追）。

### KD-4 内置集 seeder = 首启一次性拷贝 + 版本哨兵，幂等零重复

- bundle Resources `LUTs/`（44 张 + LICENSE + NOTICE）→ 默认根 `BuiltIn/` 子目录：
  seeder 在 `LutLibraryStore` 初始化路径（默认根分支才跑——可配根下不自动拷贝，用户
  根的用户数据主权）；哨兵 = 目标文件存在且字节数一致即跳过（内容 hash 比对太贵，
  count+size 足够幂等判定；单文件漂移 = 重拷该文件——与 rescan 自愈「内容漂移重解
  析」语义兼容）。
- **许可门联动的降级形态（T1 非宽松分支）**：Resources 不入 LUT 资产；Settings 节
  改渲染「内置胶片 LUT 导入指南」块（上游 URL + 下载放置说明 + 「打开根目录」按钮）；
  `BuiltInLutSetTests` 改断言「指南文案键在册 + Resources 零 .cube」；GOAL-STATE
  「阻塞（需人工）」登记许可结论待人工复核。**两条分支共享同一 T2/T3/T4 成果**（递归
  /可配根/树面板与内置集无关）。

### KD-5 许可门 = clone 原生获取 + 结论落 evidence（第一任务，硬门）

- 步骤：`git clone https://github.com/JanLohse/spectral_film_lut`（**网络异常走代理
  `px --up`…`px --stop` 一条龙**，全程记录）→ 检出最新 release tag（记录 tag/SHA）→
  读 LICENSE/COPYING/README 许可声明 → 逐字对照 CMake 打包 glob 清单（提取构建脚本
  的 glob 规则，列出 44 张文件名入 evidence 表）→ 结论三值：宽松（MIT/BSD/CC0 类
  允许再分发）/ 署名要求（CC-BY 类——可入包但 NOTICE 补作者与链接）/ 非宽松或无声明
  （= 默认无许可，**视为非宽松**，走降级）。
- evidence 落 `.work/gsd/phases/m2-5-color-grade/evidence/spectral-film-lut-license
  .md`：clone SHA、LICENSE 原文关键段摘录、44 张清单对照表、结论与依据。**clone 目录
  放 `/tmp/`（即弃），不入仓不入家目录**（executor 禁家目录纪律）。

### KD-6 phase 收口 = zh 对账 + 观察项三查 + 翻账（本 plan 承载 phase 级收尾）

- **zh-audit**：`Scripts/zh-audit.py --check` 全仓对账——M2-5 三 plan 新键
  （P1 零 UI 键 + P2 SUMMARY 键清单 + 本 plan LUT 树/Settings/指南键）zh 值补齐；
  缺口批量补翻一批 commit。
- **观察项三查（OQ-11，脚本 proxy + 走查清单双轨）**：
  1. ≥4 Grade 层链拖 exposure/HLS 滑杆流畅度——走查清单项（人工，Manual-Only）；
  2. FULL pipe 100MP 导出时间往返开/关对比 ±5%——脚本 proxy（导出计时两轮，envelope
     开 = 现状 / 关 = 临时 env 或 debug 开关断言……**不允许为测量改产品代码**——
     proxy = 同图含/不含 grade 层两栈导出计时对比归因，方法入 evidence）；
  3. LUT 树面板 rescan 耗时（KD-2 测试 + 真库走查）。
  结果入 SUMMARY「观察项」节；超带才立项专项（不预优化）。
- **翻账**：GOAL-STATE M2-5 行翻账 + 续接点更新（M2-5 完成 → 下一 phase）；AGENTS.md
  M2-2 节 UserDefaults 键登记表补 `lut.library.root` 行 + M2-5 架构增量段（若执行
  期形成新惯例）；三 plan SUMMARY/DECISIONS 交叉引用闭环。

## read_first

1. `.work/gsd/phases/m2-5-color-grade/M2-5-CONTEXT.md`——D6/7/11/12 + 事实基线③。
2. `LightamerIOP/Sources/Lut3d/LutLibraryStore.swift:60-220`——registry 三段式自愈/
   adopt/persistRegistry/查询面/importLut 正本（键升级的改造基底）。
3. `App/Sources/Lightamer/UI/Inspector/LutPanelView.swift`——库 Picker/导入/missing
   toast 既有面（树分组改造落点）。
4. `App/Sources/Lightamer/Settings/SettingsPages.swift` + `App/Sources/Lightamer/
   Library/AppPreferences.swift`——Settings 节形态 + ImportDefaults 键宿主惯例。
5. `LightamerCore/Sources/Pipe/ModuleRegistry.swift` + `LightamerIOP/Sources/Lut3d/
   Lut3dModule.swift:40-70`——`lutName` 引用消费链（resolution fallback 插入位）。
6. `.work/gsd/phases/m2-5-color-grade/M2-5-2-SUMMARY.md`——P2 新 UI 键清单（zh 对账
   输入）+ M2-5-1 SUMMARY（观察项①的层链基线形态）。
7. REQUIREMENTS M2GRADE-05/06/07 + `.work/gsd/phases/m2-4-0-test-bundles/
   M2-4-0-BUNDLE-MAP.txt`（Lut3d* 测试在 IOPP 的登记惯例）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使
   句、body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；git add
   用 `.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；不加 `-derivedDataPath`；Resources/
   测试文件登记后同 commit `tuist generate`。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数
   行 + failures 行双读（L028）。**回归基线 = M2-5-2 收口后的运行期总数**（M2-5-2
   SUMMARY 记载；phase 起算基线 2240/14skip/0fail）；每任务全套 suite 绿。**全套跑法
   = `Scripts/test-direct.sh --all`**；跑前必须向 orchestrator SendMessage 报备；
   RSS ≥8G = MEMFAIL 机检内置，触发即记 E3 不自行重试超两次。在案 flake 隔离复跑 ×3
   归因入 SUMMARY。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`LayerCompositeDriver.swift`/`PixelPipe.swift`/`PipeCacheKey.swift`
   /`Lut3dModule.swift` kernel 面零 diff（`lutName` params 字段与 kernel 不动——键
   升级只发生在 store/resolution 层）；`LutLibraryStore` 自愈/degrade 行为语义零改
   动（只换枚举广度与键编码）；旧档引用字节零改写（resolution 层兼容，KD-1）；
   GPL 数据禁令（Alcedo 仓零拷贝，上游许可门是唯一数据来源）。
6. **测试登记纪律（checker E2）**：新建测试文件**同 commit** 登记 `Project.swift` +
   BUNDLE-MAP 增行。LutLibraryRecursionTests = **IOPP**（Lut3d* 惯例）；
   BuiltInLutSetTests = **APP**（读 app bundle Resources）。运行期总数基线相应上移。
7. **收口核对（checker 教训②）**：T6 `git diff --stat` 与 front-matter 逐文件核对，
   越界 = 违约；Resources 目录按 T1 许可结论二选一（资产 or 无资产）与申报一致。
8. **家目录/临时产物纪律**：clone 目录一律 `/tmp/`（即弃），禁入家目录与仓内
   （executor 全局约束）。

## Tasks

### T1 许可门（07 前置，硬门）

- **read_first**：上列 1/7（M2GRADE-07 字面）。
- **action**
  1. KD-5 全流程（clone → tag/SHA → LICENSE 核读 → CMake glob 清单对照 44 张 →
     三值结论）。
  2. evidence 落盘 `evidence/spectral-film-lut-license.md`。
  3. **宽松（含署名要求，NOTICE 承接）** → T5 按资产分支执行；**非宽松/无声明** →
     GOAL-STATE「阻塞（需人工）」登记 + 通报 orchestrator（SendMessage），T5 切指南
     分支——**本任务不因许可结论停摆后续 T2/T3/T4**。
- **验收标准**
  - [ ] evidence 文件含 SHA/许可摘录/44 张对照表/结论四件套；结论与后续任务分支
        一致。
  - [ ] 非宽松分支：GOAL-STATE 阻塞登记在册 + orchestrator 已通报。

### T2 05 递归扫描 + registry 键升级

- **read_first**：上列 2/5。
- **action**
  1. `LutLibraryStore.swift`：KD-1 全量（enumerator 递归 + 键升 relativePath +
     InstalledLut additive 字段 + 旧行宽容迁移 + display 消歧）+ KD-2（跳隐藏目录
     + 规模 sanity）+ resolution fallback（文件名尾段匹配，`LutResolving` face
     内实现——消费方零改动）。
  2. 新建 `Tests/LightamerTests/LutLibraryRecursionTests.swift`：3 层深 fixture 树
     全收录；同名文件不同子目录双行共存 + display 前缀断言；旧 registry.json fixture
     （文件名键、无新字段）decode 迁移幂等（二次 rescan 键稳定）；键迁移后 `lutName`
     旧引用 resolution 命中（尾段 fallback）+ 歧义多命中 degrade；缺引用 degrade
     语义零改动（既有 Lut3d 测试全绿 = 活体回归）；500 文件 rescan <5s（DEBUG 软
     上限）。测试登记两处（IOPP）。
- **验收标准**
  - [ ] 递归/迁移/消歧/fallback/degrade 断言全绿；既有 Lut3d 族测试零改动全绿。
  - [ ] `Lut3dModule` kernel/params 面零 diff。
  - [ ] 全套回归 `0 fail`。

### T3 面板树分组 + 刷新

- **read_first**：上列 3。
- **action**
  1. `LutPanelView.swift`：库 Picker 升子目录树分组/折叠（组头 = 子目录相对路径段，
     内置 `BuiltIn/` 组首）+ display 撞车前缀 + 手动刷新按钮 + 面板打开触发 rescan
     （既有 `libraryRevision` 触发面扩展）。
  2. missing toast / blit identity 消费面零改动确认（既有 toast 文案键复用）。
  3. 走查（checker m4）：**手动放置子目录**（Finder 拷 `.cube` 入库根下子目录）→
     rescan 收录 / 删除子目录后刷新 / 缺引用 toast 三场景。
- **验收标准**
  - [ ] 树分组/折叠/刷新走查绿；缺引用降级走查绿（typed degrade 非 crash）。
  - [ ] 全套回归 `0 fail`。

### T4 06 可配根 + Settings 节

- **read_first**：上列 2/4。
- **action**
  1. `AppPreferences.swift`：`lut.library.root` 键（登记 + reset 默认面）。
  2. `SettingsPages.swift`：新节「LUT Library」（当前根显示 + NSOpenPanel 选择 +
     重置默认 + 切根重扫反馈 + 坏根错误文案）。
  3. `LutLibraryStore` 消费侧：切根经 shared holder 原子替换（KD-3——
     `replaceShared(_:)`，static var + lock，checker m6）；`LutPanelView` 等
     `LutLibraryStore.shared` 消费点经统一获取面读取（getter 恒取当前实例；若既有
     直引捕获存储实例，收拢 accessor——改动半径限 Lut3d 相关消费点，逐点 grep
     申报）。
  4. `LutLibraryRecursionTests` 追加：切根重建（新根独立 registry）/ 坏根降级回默认
     + 错误态 / 新根下旧引用缺名 degrade。
- **验收标准**
  - [ ] 切根/坏根/缺名三断言绿；Settings 节走查绿；默认根行为零变化（键缺省 = 既有
        路径，既有 LUT 测试零改动全绿证）。
  - [ ] 全套回归 `0 fail`。

### T5 07 内置集（按 T1 结论分支）

- **read_first**：上列 2 + evidence 文件。
- **action**
  1. **资产分支**：44 张 + LICENSE + NOTICE 入 `Resources/LUTs/` → Project.swift
     Resources 登记 → seeder（KD-4：默认根 `BuiltIn/` 首启拷贝 + count/size 哨兵
     幂等）→ `BuiltInLutSetTests`（恰 44 张清单常量对照 / LICENSE 在包 / 首启拷贝 /
     二次启动零重复）。测试登记两处（APP）。
  2. **指南分支**：Settings LUT 节渲染导入指南块（KD-4 降级形态）+ 指南文案键 +
     `BuiltInLutSetTests` 改断言指南在册 + Resources 零 .cube；GOAL-STATE 阻塞项
     补执行注记。
  3. `tuist generate`（Resources 变更批）。
- **验收标准**
  - [ ] 资产分支：44 张断言 + 幂等断言 + LICENSE/NOTICE 署名断言全绿；清单与
        evidence 表逐行一致。
  - [ ] 指南分支：指南块 + 键登记 + 零资产断言全绿。
  - [ ] 全套回归 `0 fail`。

### T6 phase 收口——zh 对账 + 观察项三查 + 翻账

- **read_first**：上列 6 + 三 plan AC 表 + `.work/GOAL-STATE.md`。
- **action**
  1. 本 plan AC 机检 + 全套回归终跑（`--all` 前报备；计数入 SUMMARY）。
  2. zh-audit：`Scripts/zh-audit.py --check` → 缺口补齐（三 plan 全部新键，P2
     SUMMARY 键清单为输入）→ 复跑 --check 绿。
  3. 观察项三查（KD-6）：走查清单执行 + 脚本 proxy 计时 → 结果入 SUMMARY「观察项」
     节（超带立项建议，不自行优化）。
  4. 落盘 `M2-5-3-SUMMARY.md`（键升级迁移实态/许可结论终值/三查数据/测试数变化）+
     `M2-5-3-DECISIONS.md`（KD 执行确认 + 偏差归因）。
  5. `.work/GOAL-STATE.md` M2-5 翻账 + 续接点（下一 phase 入口）；AGENTS.md 键登记
     补行 + M2-5 架构增量段（如有新惯例）；LESSONS 如踩坑。
  6. `git diff --stat` 核对三 plan 累计边界（纪律 7）。
- **验收标准**
  - [ ] AC 表全绿；zh-audit --check 绿；三查数据在账；GOAL-STATE/AGENTS/SUMMARY/
        DECISIONS 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 许可门证据闭环：clone SHA + LICENSE 摘录 + 44 张对照表 + 三值结论；分支路由与结论一致 | evidence 文件 + T5 分支产物核对 |
| 2 | 递归收录：任意深度子目录 `.cube` 全收录；隐藏目录/registry.json 跳过 | LutLibraryRecursionTests |
| 3 | 键升级：旧行（文件名键、无新字段）宽容 decode → relativePath 推导迁移幂等；新写入恒 relativePath；`lutName` 旧引用尾段 fallback 命中 / 歧义 degrade / 缺名 blit identity + toast 语义零改动 | LutLibraryRecursionTests + 既有 Lut3d 族全绿 |
| 4 | 同名消歧：跨子目录同名双行共存、display 前缀、引用唯一 | LutLibraryRecursionTests |
| 5 | 可配根：键缺省 = 默认根（既有测试零改动证）；切根独立 registry 重建；坏根 typed 降级 + 错误文案；`lut.library.root` 键登记 | LutLibraryRecursionTests + AppPreferences 断言 |
| 6 | 面板树：分组/折叠/手动刷新/打开触发 rescan；BuiltIn 组首 | 走查 + LutPanelView diff 范围核对 |
| 7 | 内置集（资产分支）：恰 44 张（evidence 清单逐行）+ LICENSE/NOTICE 在包 + 首启拷贝 BuiltIn/ + 二次启动幂等；（指南分支）：指南块 + 零资产 + GOAL-STATE 阻塞登记 | BuiltInLutSetTests（两形态） |
| 8 | 渲染/LUT kernel 红线：LayerCompositeDriver/PixelPipe/PipeCacheKey/Lut3dModule kernel 面零 diff | `git diff --name-only` 断言 |
| 9 | zh 对账：`Scripts/zh-audit.py --check` 全绿（M2-5 三 plan 新键全补） | zh-audit --check 退出码 |
| 10 | 观察项三查数据在账（层链拖滑杆走查 / 导出计时对比 / rescan 耗时），超带有立项建议 | M2-5-3-SUMMARY「观察项」节 |
| 11 | GOAL-STATE M2-5 翻账 + 续接点 + AGENTS.md 键登记补行 | 文件核对 |
| 12 | 全套回归 0 fail（基线 = M2-5-2 收口总数 + 本批新增）；diff 边界 == 申报；新测试登记闭环（两文件 × Project.swift + BUNDLE-MAP） | test-direct.sh --all 双读 + `git diff --stat` + `git grep` 双命中 |

## 风险与边界

- **许可结论不可预判**：T1 是硬门但**不阻塞 T2/T3/T4**（递归/可配根/树面板与内置集
  独立）；非宽松路径已预声明（指南 + 阻塞登记），无返工面。风险残留 = 宽松但为
  「署名要求」级——NOTICE 承接即可，不算降级。
- **键升级对 12-5 既有 LUT 用户的迁移面**：旧 registry.json/旧引用的兼容矩阵
  （KD-1）测试钉死；残余风险 = 用户手工编辑过的 registry（在野概率≈0，decode 宽容
  兜底）。
- **`LutLibraryStore.shared` 单例重造的引用面**：消费点若散落直引（`LutPanelView`/
  `Lut3dModule` resolution 链），切根后旧实例悬挂——KD-3 shared holder（static var
  + lock，checker m6）原子替换 + 收拢 accessor 是既定改法，改动半径 = grep
  `LutLibraryStore.shared` 全消费点（执行期逐点申报入 files_modified 附录，越界先
  申报后动）。
- **seeder 与可配根的组合**：内置集只落默认根（KD-4）——用户切根后 BuiltIn 消失属
  预期（每根自洽库语义）；Settings 文案明示，避免「内置集丢了」误会。
- **观察项三查的导出对比方法学**：含/不含 grade 层两栈计时归因（非 A/B 开关）——
  差值含 grade 计算本身，非纯 envelope 代价；结论表述限定为「带内对比」，立项判断
  留 orchestrator（KD-6 字面）。
- **基线上移**：2240 → P1/P2 收口值逐级上移；本 plan 预计 +15..25（两测试文件），
  BUNDLE-MAP 行对账。

## 提交约定

- T1 `docs(m2-5): spectral film lut license gate evidence`
- T2 `feat(iop): recursive lut library scan with root-relative registry keys`
- T3 `feat(app): lut panel subdirectory tree grouping and refresh`
- T4 `feat(app): user configurable lut library root`
- T5 `feat(app): vendor builtin film lut set with license attribution`（指南分支 =
  `feat(app): built-in lut import guide fallback`）
- T6 `docs(m2-5): close out phase color grade controls`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-09-30）

checker 判 FAIL（8E+6M）后本 plan 落地项：

- **E8（front-matter 补申报）**：增 `Resources/Localizable.xcstrings`（LUT 树/
  Settings 节/导入指南新键随手键入账）+ `AGENTS.md`（UserDefaults 键登记补
  `lut.library.root` 行 + M2-5 架构增量段——T6 action 5 翻账的申报落点）。
- **m4（走查场景修正）**：T3 action 3 走查场景改「**手动放置子目录**（Finder 拷
  `.cube` 入库根下子目录）→ rescan 收录」——原「导入到子目录」与导入能力面不符。
- **m6（shared holder 机制）**：KD-3 增补 `LutLibraryStore.shared` 可替换 holder
  机制——`private static var _shared` + `NSLock`（getter 锁内读 + `replaceShared`
  锁内原子换），机制**内联于 `LutLibraryStore.swift`**（不新建文件、front-matter
  零新增；`ModuleRegistry` 等 registry 面零触碰、不入 front-matter）；T4 action 3
  与风险节同步。
