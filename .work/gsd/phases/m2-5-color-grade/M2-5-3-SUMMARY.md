# M2-5-3 SUMMARY — LUT 三件套 + M2-5 phase 收口（2026-09-30/10-01 夜间批）

> plan = M2-5-3-PLAN.md（checker 修正版 87c039d）。执行 = 本 subagent（ZCode），T1-T6
> 逐任务独立提交、每任务边界读 config.toml [gsd]（paused=false/auto=true 全程未变）。
> 签注正本 = 同目录 M2-5-3-DECISIONS.md（八节）。许可门证据正本 =
> `evidence/spectral-film-lut-license.md`。渲染管线零改动（红线四文件零 diff，见边界节）。

## 提交链

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `a31ac15` | 许可门 evidence：clone tag v0.18.2（SHA `42f4f3f…`，API 核对）→ LICENSE = **MIT** → CMake glob 对照 + TITLE 头取证（Alcedo 集即本上游工具产物）→ 三值结论 = **宽松 → 资产分支**；实态更正 44→41（glob 真值）在案 |
| T2 | `6facf60` | registry 键升 relativePath（递归/消歧/可配根三合一）+ enumerator 递归 + 旧行宽容迁移 + 尾段 fallback + shared holder（static var + NSLock + replaceShared）+ validateRoot + seedBuiltIns + LutLibraryRecursionTests 九法（IOPP） |
| T3 | `851a1cc` | LutPanelView 库区升子目录树（LutLibraryTreeView：root 行 + DisclosureGroup 组、BuiltIn 组首、手动刷新、onAppear rescan、撞车前缀、selection 写 key）+ panel_lut_refresh 键 |
| T4 | `93ad30f` | AppPreferences `lut.library.root` 登记/reset 面 + Settings Cache 页「LUT Library」节（根显示/选取/重置/结果行/坏根橙错行）+ Registry 消费点收拢 sharedResolver + KD-3 四法 + SettingsPagesTests +1 |
| T5 | `7d73d1d` | Resources/LUTs/ vendor 40 张（65³，314MB）+ LICENSE（MIT 全文）+ NOTICE（provenance）+ Project.swift folderReference + BuiltInLutSetTests 四法（APP）+ KD-4 两法 |
| T6 | `970485e` | OQ-11 探针两件（env 门控：100MP FULL grade 层对比 LAYERS + 万文件 rescan IOPP） |
| 收口 | （本提交） | SUMMARY/DECISIONS/GOAL-STATE/AGENTS.md 翻账 + zh 对账终态 |

## 许可门终值（T1）

**宽松（MIT，Copyright (c) 2026 Jan Lohse）→ 资产分支执行，无降级、无阻塞登记。**
关键执行期发现：上游仓 = LUT 生成器（不含 .cube），且 Alcedo 打包集本就是该工具产物
（安装目录 TITLE 头逐字取证）→ vendored 集 = 上游 v0.18.2 无头重生成（应用默认导出
参数 + 两处偏差：65³、BW 配 Kodak 2302），零字节来自 GPL 仓。glob 真值 41（plan 预写
44 为清点口径混入）；上游无对应的 2 张 Alcedo 手工变体（Ultramax_500 /
Vision3_500T_5219_3200）以最近上游 stock 收编/不造 → **最终 vendored 40 张**，对照表
41 行逐行在 evidence §四。

## 测试数变化（BUNDLE-MAP 对账）

- **起算基线 = 2305/14skip/0fail**（M2-5-2 收口值）。
- 新增 22 executed 法：LutLibraryRecursionTests 新建 **16**（IOPP 全新文件：T2 九 +
  T4 四 + T5 两 + T6 探针一）+ BuiltInLutSetTests 新建 **4**（APP）+
  SettingsPagesTests +**1**（LUT 根键法）+ GradeEnvelopePerfProbeTests 新建 **1**
  （LAYERS）。
- skip 14→**16**（+2 探针 XCTSkipUnless，环境门控，DECISIONS §六）。
- 预期全套终值 = **2327/16skip/0fail**（2305 + 22 精确；bundle 级：IOPP 326→342、
  Layers 179→180、App 364→369、IOP/Library/Sessions/Export 继承不变）。实测见下节。

## 全套回归终跑（--all，orchestrator 报备后实跑；共两轮）

```
BUNDLE|IOP|467/1/0|peakRSS=7036MB|120s|sampling=time
BUNDLE|IOPParity|342/3/0|peakRSS=5988MB|285s|sampling=time
BUNDLE|Layers|180/3/0|peakRSS=945MB|22s|sampling=time
BUNDLE|Library|430/4/0|peakRSS=294MB|17s|sampling=time
BUNDLE|Sessions|279/4/0|peakRSS=1597MB|70s|sampling=time
BUNDLE|Export|260/1/0|peakRSS=6231MB|190s|sampling=time
BUNDLE|App|369/0/0|peakRSS=1395MB|174s|sampling=time
TOTAL|2327/16/0|878s        （EXIT=0）
```

- **终值 2327/16/0 = 2305 基线 + 22 新增精确**（bundle 分量逐一对账：IOPP +16、
  Layers +1、App +5、三 bundle 零触碰继承一致）；skip 14→16 = 两探针；**MEMFAIL
  零触发**（峰值 IOP 7036MB < 8192 门）。
- **flake 记录**：第一遍 --all = `TOTAL|2327/16/1|871s`，唯一失败 =
  `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile`（.lra 落盘超时，
  9.6s）。归因处置 = 隔离复跑 ×3 全绿（10/10/10）+ 第二遍全套复跑绿（上表）→
  **负载型 flake 定性**（同 bundle 内 BuiltInLutSetTests 多 GB seed I/O 先行 + 首轮
  会话自身 I/O 背景负载；sidecar flush 有界等待被挤压）。测试与产品代码零改动结案，
  机制注记在案供后续 --all 观察对照。

## 观察项三查（OQ-11，KD-6）

| # | 项 | 方法 | 结果 | 判定 |
|---|---|---|---|---|
| ① | ≥4 Grade 层链拖 exposure/HLS 滑杆流畅度 | 走查清单项（plan 自标 **Manual-Only**） | **未执行**（需真机交互：开项目→导图→建 4 层→拖杆目测） | 挂 GUI 验收轮（M2-5-2 面板走查清单同批移交；随 M2GRADE-01/02 面板半边验收一并消核） |
| ② | FULL 100MP 导出 grade 层代价 | 脚本 proxy = 同图含/不含 grade 层两栈 FULL composite 计时（GradeEnvelopePerfProbeTests，L014 fence 后读钟，冷 cache、3 轮取中位） | base（terminal trio，0 grade）= **156.2ms**；4 grade 层 = **1027.0ms**；delta = **+870.8ms**（≈218ms/层） | **超 ±5% 带，但归因含 grade 本体**（plan 方法注记：差值含 exposure 计算 + blend + envelope 对，非纯 envelope 代价）；真实导出 base 还含 RAW 解码 + develop 全链（基线远大于 156ms，占比进一步稀释）；导出为一次性吞吐不涉交互延迟。**立项建议（orchestrator 裁）**：若需纯 envelope 归因，需产品面支持恒等梯度层测量（恒等层被 envelope 跳过，现结构测不到）——建议挂专项而非预优化 |
| ③ | LUT 万文件 rescan 耗时 | 探针（IOPP）：10k 文件 × 3 层树（微型 2³ 表 fixture） | **冷 init 0.77s / 暖重开 0.85s**（ Enumeration+registration 为主；真实 65³ 表 parse = 每新文件一次性成本，自愈只重解析漂移文件；40 张真实 314MB 实库在 BuiltInLutSetTests 50s 全类墙钟内含 3 次全量 seed 拷贝的包络内） | **远低于关注线**（KD-2 软上限 5s @ 500 文件全绿；万文件量级无 O(n²) 迹象），不立项 |

三查总判定：**② 超 5% 带（含 grade 本体归因限制，立项建议在案）；①③ 不立项**。

## AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | 许可门证据闭环（SHA/摘录/对照表/三值结论 + 分支路由一致） | ✅ evidence 四件套齐；结论 = 宽松 → T5 走资产分支（无 GOAL-STATE 阻塞登记需求） |
| 2 | 递归收录（任意深度全收、隐藏目录/registry.json 跳过） | ✅ testDeepTreeIsCollectedRecursively + testHiddenDirectoriesAndNonCubeFilesAreSkipped |
| 3 | 键升级迁移 + 旧引用 fallback/degrade 语义零改动 | ✅ testLegacyRegistryDecodesAndMigratesIdempotently + testLegacyBareNameReferenceResolvesThroughTailFallback + testAmbiguousBareNameDegrades + 既有 Lut3d 族零改动全绿（Golden 5/Kernel 8/Store 10） |
| 4 | 同名消歧（跨子目录双行共存、display 前缀、引用唯一） | ✅ testSameNameRowsCoexistAndGroupFaceLeadsWithBuiltIn（relativePath 天然唯一 + 面板撞车前缀） |
| 5 | 可配根（键缺省=默认根、切根独立重建、坏根 typed 降级、键登记） | ✅ testSwitchingRootBuildsAnIndependentRegistry + testBadRootDegradesWithoutCrashing + testValidateRootAccepts… + testLutLibraryRootDefaultsResetsAndRegistersTheSpelling；默认根零变化 = LutLibraryStoreTests 10 法零改动全绿 |
| 6 | 面板树（分组/折叠/手动刷新/打开 rescan、BuiltIn 组首） | ✅ store 级场景测试钉死（放置/删除/rescan）+ LutPanelView diff 范围核对；目测走查 Manual-Only 移交（观察项①同批） |
| 7 | 内置集：恰清单张数 + LICENSE/NOTICE 在包 + 首启拷贝 + 二次幂等 | ✅ BuiltInLutSetTests 四法（40 张逐名对照 + 42 项夹内容 + LICENSE/NOTICE 内容断言 + seeder 42→0→漂移重拷 1）；「恰 44」按 evidence 实态修正为 40（DECISIONS §二） |
| 8 | 渲染/LUT kernel 红线四文件零 diff | ✅ `git diff --name-only 87c039d..HEAD` grep 零命中（LayerCompositeDriver/PixelPipe/PipeCacheKey/Lut3dModule） |
| 9 | zh 对账 --check 全绿 | ✅ 首查 PASS（1244 source keys / 1458 catalog keys，zh complete，locale={en,zh}）——新键随手随 commit 入账生效 |
| 10 | 观察项三查数据在账，超带有立项建议 | ✅ 本 SUMMARY「观察项」节；② 立项建议在案（纯 envelope 归因需专项），①③ 不立项 |
| 11 | GOAL-STATE M2-5 翻账 + 续接点 + AGENTS.md 键登记补行 | ✅ 收口批同批落盘（GOAL-STATE M2-5 行 + 续接点；AGENTS.md M2-2 键表补 `lut.library.root` + M2-5 架构增量段） |
| 12 | 全套 0 fail + diff 边界 == 申报 + 新测试登记闭环 | ✅ --all 终跑见上节；边界 = 申报集 + Registry.swift（DECISIONS §三预授权申报）+ 探针文件；`git grep` 双命中（BuiltInLutSetTests/LutLibraryRecursionTests/GradeEnvelopePerfProbeTests × Project.swift + BUNDLE-MAP） |

## diff 边界（申报集 + 已声明偏差）

申报内全量落地；**申报外两处（均 DECISIONS 已声明）**：

| 文件 | 依据 |
|---|---|
| `LightamerIOP/Sources/Registry.swift`（lut3d 注册行转发面 + 注释） | KD-3 消费点收拢条款（plan 风险节预授权 + DECISIONS §三） |
| `Tests/LightamerTests/GradeEnvelopePerfProbeTests.swift`（T6 新建探针） | T6 action 3 观察项载体（files_modified 未列执行期产物；DECISIONS §六） |

另：`Tests/LightamerTests/SettingsPagesTests.swift`（T4 +1 法，键登记断言）= plan AC 5
「AppPreferences 断言」的机检载体（同 KD-5 惯例：测试随动申报）。

## 已知限制 / 移交

- **应用内走查双项**（Manual-Only，挂 GUI 验收轮）：LUT 树分组/折叠/刷新目测 +
  ≥4 Grade 层拖杆流畅度（观察项①）。
- **纯 envelope 归因**：需产品面支持恒等梯度层探针（现结构恒等层被 envelope 跳过），
  立项建议挂 orchestrator。
- **vendored 集不与 Alcedo 安装目录逐字节一致**（许可与合规使然，DECISIONS §二.3）；
  「同款」主张 = 同工具同版本同 stock 集（39/41）同尺寸。
- **域盲五件**（M2-5-1 移交）维持：lut3d kernel/params 面零 diff 本批复核维持。
- **seeder 的默认根 init 分支**无自动测试（会写真机用户目录）——static face 测试 +
  code review 承载（DECISIONS §四）。

## flake 记录

- **SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile**：第一遍 --all 唯
  一失败（.lra 落盘超时）。隔离复跑 ×3 全绿 + 第二遍全套 --all 绿 → 负载型 flake 定
  性结案（机制注记见「全套回归终跑」节；SidecarV5Tests 与本批 LUT 改动零接触面，产
  品/测试代码零改动）。
- 执行期两处测试脚手架缺陷当轮即修（validateRoot 探针对未物化目录断言、URL 尾斜杠比
  较）+ 探针首版无 fence 假数（L014 复发即修），非产品代码问题。
