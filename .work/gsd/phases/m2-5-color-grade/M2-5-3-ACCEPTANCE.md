# M2-5-3-ACCEPTANCE — LUT 三件套 + M2-5 收口 独立验收报告

> 验收批：2026-10-01（独立验收 subagent）。对象 = plan `M2-5-3-PLAN.md`
> （checker 修正版 `87c039d`）+ 执行批 **8 commits**（T1 `a31ac15` / T2
> `6facf60` / T3 `851a1cc` / T4 `93ad30f` / T5 `7d73d1d` / T6 `970485e` /
> 收口 `3a0ac1a` + `1044641`；派发指令写「9 commits」实为 8——勘误）。
> 验收方式 = 逐 AC 机检核对 + 许可门 evidence 亲核（GitHub API 独立重查）+
> 定向独立复跑（`--bundle IOPParity` / `--bundle App` + 两新测试类定向）+
> 代码抽查（file:line 读码）。全套 `--all` 不重跑（批准门纪律）。

## 结论

**PASS / 0 error + 2 minor（文档勘误，本批已修）+ 2 observation**

- 执行批 8 commits 全部按 plan 交付，AC 12/12 独立复核全绿（AC-6 目测走查
  Manual-Only 移交 GUI 验收轮 = SUMMARY 已申报的移交，非缺口）。
- 复跑与声明 `--all` 终跑逐值一致（IOPParity 342/3/0、App 369/0/0；定向
  LutLibraryRecursionTests 16/1/0、BuiltInLutSetTests 4/0/0；全部 EXIT=0）。
- **许可门核查（最重项）全部亲核属实**——上游 tag/SHA、MIT LICENSE、
  「上游 = 生成器」事实、vendored 40 张零 GPL 特征、NOTICE 在包、
  44→41→40 勘误链，六点独立验证通过（见下节）。
- 两条 minor 均为文档与实态不符（非代码缺陷）：F1 = SUMMARY AC-8 核验区间
  写错；F2 =「默认根 init 分支未执行」声明被测试副作用证伪。均本批勘误。

## 许可门核查（单列，亲核记录）

| # | evidence 主张 | 独立核验方式 | 结论 |
|---|---|---|---|
| 1 | tag v0.18.2 = commit `42f4f3fadfab…ce5f` | GitHub API `git/ref/tags/v0.18.2` 直查（本验收会话） | **逐字一致** ✅ |
| 2 | 上游 LICENSE = MIT (c) 2026 Jan Lohse | GitHub API `contents/LICENSE?ref=v0.18.2` 直查 | **MIT + 版权行一致** ✅；vendored `Resources/LUTs/LICENSE` 同文本 ✅ |
| 3 | 上游仓 = 生成器、不含 .cube | GitHub API `git/trees/v0.18.2`（未截断）全列 | **Python 工程（src/tests/pyproject.toml/PyInstaller .spec），树内零 .cube** ✅ |
| 4 | Alcedo 打包集 = 该工具产物（TITLE 头取证） | 本机 `/Applications/AlcedoStudio.app/.../LUTs/` 只读头注 | `TITLE "D:\Projects\spectral_film_lut\luts\Kodak_Portra_400.cube"` + `LUT_3D_SIZE 65` 逐字复现 ✅ |
| 5 | vendored 40 张零 GPL 字节（重生成非拷贝） | 抽 3 张头注 + 全量尺寸机检 | TITLE = 裸 stock 名（`TITLE "Kodak_Portra_400"`，与 Alcedo 的 Windows 路径形态**字节形态不同**）；40/40 全部 `LUT_3D_SIZE 65`（`grep -L` 零命中）；BW 表 RGB 三列相等（灰度特征）；总 314M ✅ |
| 6 | NOTICE/LICENSE 署名在包 + 44→41→40 勘误链自洽 | 包点数 + 表逐行 | 包 = 恰 42 项（40 .cube + LICENSE + NOTICE）；NOTICE 记上游 URL/版本/SHA/两偏差/零 GPL 声明 ✅。链：安装根层 44 项 − `色彩逆向/` 子目录 = 43 .cube − Hasselblad×2 = **41 glob 真值**；41 − Vision3_500T_5219_3200（不造）+ Ultramax_500→上游名 Ultramax_400（替换非增）= **40**；40 文件名逐行 = evidence §四「生成文件」列 ✅ |

**判定：许可门结论（宽松/MIT → 资产分支）成立，四件套 evidence 真实完整，
「上游 = 生成器」判断证据充分，零 GPL 拷贝主张可信。**

## 复跑 vs 声明

| 轮 | 声明（SUMMARY） | 本验收复跑 | 判 |
|---|---|---|---|
| `--bundle IOPParity` | 342/3/0 | **342/3/0**（288s，peakRSS 5613MB）EXIT=0 | ✅ 逐值一致 |
| `--bundle App` | 369/0/0 | **369/0/0**（158s，peakRSS 1530MB）EXIT=0 | ✅ 逐值一致 |
| LutLibraryRecursionTests 定向 | IOPP 16 法 | **16/1/0**（1 skip = 探针门控）EXIT=0 | ✅ |
| BuiltInLutSetTests 定向 | APP 4 法 | **4/0/0** EXIT=0 | ✅ |
| zh-audit --check | PASS | **PASS**（1244 source / 1458 catalog，exit 0） | ✅ |
| 前置构建 | — | `xcodebuild build-for-testing` @ HEAD `1044641` exit 0 | ✅ |

测试数对账：2305 基线 + 22（Recursion 16 + BuiltIn 4 + SettingsPages 1 +
PerfProbe 1）= 2327 精确；skip 14→16 = 两探针 `XCTSkipUnless`。BUNDLE-MAP
三行（IOPP 16 / APP 4 / LAYERS 1）× Project.swift 三 target 登记 = `git grep`
双命中复核 ✅。

## AC 总表复核（12/12）

| # | AC | 独立核验 |
|---|---|---|
| 1 | 许可门证据闭环 + 分支路由一致 | ✅ 上节六点亲核；结论 = 宽松 → T5 资产分支（无 GOAL-STATE 阻塞登记需求 = 一致） |
| 2 | 递归收录 + 隐藏/registry.json 跳过 | ✅ `testDeepTreeIsCollectedRecursively`（3 层 + BuiltIn/Weddings 深路径断言）+ `testHiddenDirectoriesAndNonCubeFilesAreSkipped`（`.hidden/`、`.buried.cube`、registry.json 手写不采纳）；`rescan()` 用 `enumerator(at:)` + `skipsHiddenFiles`（`LutLibraryStore.swift:232-246`） |
| 3 | 键升级迁移 + fallback/degrade 零改动 | ✅ `testLegacyRegistryDecodesAndMigratesIdempotently`（升级版落盘 + 二次 store 键稳定）+ `testLegacyBareNameReferenceResolvesThroughTailFallback` + `testAmbiguousBareNameDegrades`（双同名 → nil）+ `resolvedKey(for:)` 精确→唯一尾段→歧义 nil（`LutLibraryStore.swift:301-311`）；既有 Lut3d 族（Golden 5/Kernel 8/Store 10）零改动全绿（bundle 复跑内含） |
| 4 | 同名消歧 | ✅ `testSameNameRowsCoexistAndGroupFaceLeadsWithBuiltIn` + 面板 `displayName(for:groups:)` 撞车转 relativePath（`LutPanelView.swift` 树视图段） |
| 5 | 可配根 | ✅ `testSwitchingRootBuildsAnIndependentRegistry`（每根独立 registry + replaceShared 原子 + sharedResolver 转发）+ `testBadRootDegradesWithoutCrashing` + `testValidateRootAccepts…`（真目录收/文件拒/不存在拒）+ SettingsPagesTests `testLutLibraryRootDefaultsResetsAndRegistersTheSpelling`（键缺省 = 默认根 + 拼写单源）；键登记 = `LutLibraryStore.libraryRootKey` 单源 + AGENTS.md:297 |
| 6 | 面板树 | ✅ store 级三场景测试钉死（放置/删除/rescan 自愈）+ `LutLibraryTreeView` diff 核对（root 行 + DisclosureGroup 组、BuiltIn 排序首位 `libraryGroups()`、手动刷新按钮 + onAppear rescan、selection 写 key、`displayKey` 高亮旧引用不改字节）；目测走查 Manual-Only 移交 GUI 验收轮（SUMMARY 申报） |
| 7 | 内置集 | ✅ `BuiltInLutSetTests` 4 法定向 4/0/0（40 张逐名对照 manifest + 42 项夹断言 + LICENSE/NOTICE 内容 + seeder 42→0→漂移重拷 1）；「恰 44」→40 = evidence 实态修正（DECISIONS §二，勘误链自洽） |
| 8 | 渲染红线四文件零 diff | ✅ `git diff --name-only a31ac15^..HEAD` grep 四文件**零命中**（验收机检亲跑）；**F1** = SUMMARY 原记区间 `87c039d..HEAD` 不成立（含 M2-5-1 `1853026` 对 LayerCompositeDriver 的 phase 级合法改动）——SUMMARY 已本批勘误 |
| 9 | zh 对账 --check 全绿 | ✅ 亲跑 exit 0；8 新键（panel_lut_refresh + settings_lut_* 七键，含插值键 `settings_lut_rescan_done %lld`）en+zh 双语在册 |
| 10 | 三查数据在账 + 超带立项建议 | ✅ SUMMARY「观察项」节（详见 OQ-11 重点节） |
| 11 | GOAL-STATE 翻账 + AGENTS.md 键登记 | ✅ GOAL-STATE 续接点 M2-5-3 行在册 + AGENTS.md:297 键行 + :303 M2-5 架构增量段（KD-3/键升级/vendored 规则） |
| 12 | 全套 0 fail + diff 边界 + 登记闭环 | ✅ 声明终跑 2327/16/0 EXIT=0（两 bundle 逐值复跑佐证）；diff 边界 = 申报集 + Registry.swift（DECISIONS §三预授权）+ GradeEnvelopePerfProbeTests（探针载体）+ SettingsPagesTests（AC5 载体）——全部有据；登记双命中复核 |

## 重点抽查

- **registry 迁移真伪**：fixture 用真旧形态（平面键 + 无新字段 JSON，哈希 =
  真文件 StableHash）；断言覆盖 decode 存活 + 字段推导 + persist 落盘升级版 +
  二次 store 幂等。非空转测试。
- **尾段 fallback 边界**：歧义（两目录同名）→ nil degrade；唯一 → 命中且
  `displayKey` 给出 relativePath 供面板高亮；`isMissing` 面（toast 消费点）
  语义与 12-5 一致（`LutPanelView` 消费 `store.isMissing(key)` 原样保留）。
- **Settings 节形态**：`applyLutRoot` = validateRoot 前置（探针失败不持久化 +
  橙色错误行 `settings_lut_root_invalid`）→ persist → `LutLibraryStore()`
  重造 → `replaceShared` 原子换 → 结果行报 rescan 计数。与 KD-3 逐条对应；
  D7 十页钉定面未动（节落 Cache 页，理由 DECISIONS §五）。
- **Registry 消费点收拢**：`Registry.swift:379` 唯一改动行
  `LutLibraryStore.shared` → `sharedResolver`（SharedForwardingResolver 转发
  活实例）；grep 全消费点申报一致（LutPanelView computed 每读免改 + 测试）。
  Lut3dModule 自身零 diff。
- **OQ-11 三查形态与归因**：③万文件 0.77s/0.85s（微型 fixture，枚举开销
  主导）→ 不立项，合理。②探针方法学诚实（L014 fence 后读钟、冷 cache、
  中位取 3、record-only 断言）；**+870.8ms 归因论证成立**——delta 含 4 层
  exposure 本体 + blend + ACEScc envelope 对，非纯 envelope 代价，与 plan
  KD-6 方法注记一致；「真实导出基线含 RAW 解码 + develop 全链 → 占比稀释」
  只影响相对带判定、不影响绝对增量的定性，SUMMARY 表述限定「带内对比 +
  归因限制」无过度主张。**立项建议去向 = orchestrator 合理**（纯 envelope
  归因需恒等梯度层探针——现结构恒等层被 envelope 跳过，属产品面缺口，
  非本 plan 可闭环），挂账随 phase 小结上交。①拖杆流畅度 Manual-Only
  未执行 = plan 自标走查项，移交 GUI 验收轮（与 M2-5-2 面板走查同批）。

## Findings

- **F1（minor，文档，本批已修）**：SUMMARY AC-8 核验区间写 `87c039d..HEAD`
  并称 grep 零命中——该区间实含 M2-5-1 envelope 提交 `1853026` 对
  `LayerCompositeDriver.swift` 的合法改动，原句与事实不符。红线实质（M2-5-3
  自身区间 `a31ac15^..HEAD` 四文件零 diff）成立；SUMMARY 已改正确区间 +
  勘误注记。
- **F2（minor，文档/测试纪律，本批已修注记）**：DECISIONS §四/SUMMARY 称
  「默认根 init 分支 code review 承载、未执行」——实际
  `testSwitchingRootBuildsAnIndependentRegistry` 触 `LutLibraryStore.shared`
  → 静态 `sharedInstance` 初始化 → 默认根 init 全跑（真实根 BuiltIn/ 42 项
  mtime `Sep 30 23:18` = 执行批测试窗口，实证）。无害（= 生产首启幂等语义
  本身），但「测试不触真实用户目录」纪律出现盲区 + 声明不实。SUMMARY 已附
  勘误注记；改善挂账 = store 测试注入式根/defaults（后续 phase）。
- **O1（observation，性能挂账）**：`rescan()` 校验段整读全库字节（40×8.2MB
  = 314MB）+ FNV，面板 onAppear 即触发；seeder 哨兵用 `Data(contentsOf:)`
  读整文件只为比对字节数（`seedBuiltIns`）。40 表规模实测无感（BuiltIn
  4 法 53s 含 3 次全量 seed），但每次开面板/每次启动的 314MB I/O 是结构性
  成本——规模化建议：哨兵改 `attributesOfItem(.size)`、rescan 加 mtime
  短路。非本批修复（改绿不必要）。
- **O2（observation）**：Settings 错误行判色 = `lutStatusLine == rejectedCopy`
  字符串等值（同 computed 双取恒等，现行正确）；将来多态错误行需换判别位。

## 翻账清单（本批 commit）

1. REQUIREMENTS：**M2GRADE-04** 勾选 + Delivered（M2-5-1 ACEScc 域 envelope，
   验收 PASS 在案）；**M2GRADE-05** 勾选 + Delivered（本 plan T2/T3）；**M2GRADE-06**
   勾选 + Delivered（T4）；**M2GRADE-07** 勾选 + Delivered（T1 许可门 MIT 结论 +
   上游 v0.18.2 重生成 40 张 + LICENSE/NOTICE + 44→41→40 勘误）。
2. `M2-5-3-SUMMARY.md`：AC-8 区间勘误（F1）+ seeder init 分支勘误注记（F2）。
3. GOAL-STATE：续接点新行（验收 PASS + M2-5 全 phase 终态 + 签核移交）。
4. TODO.md：M2 节头行推进 + M2-5 行落账。
5. 本报告 `M2-5-3-ACCEPTANCE.md`。

---

# M2-5 Phase 小结（Color Grade 控件——三 plan 全景）

> phase 基线 2240/14/0（M2-4 终态）→ **终态 2327/16/0**（+87 executed/+2 skip）。
> 三 plan 执行+验收全闭环，签核 VALIDATION 移交 verify-work（C 档第 3 停）。

## 三 plan 全景

| plan | 内容 | commits | 测试 | 验收 |
|---|---|---|---|---|
| M2-5-1 | Grade 新件 wave 1：GradeCatalog 18 目录注册表 + 七新件八 op（CAT02 WB/Contrast/White/Black/Saturation/Tint/colorWheels/HLS）+ ACEScc 域 envelope + golden 脚手架 | `ba70717`..`fd13a46`（7+收口） | +47 → 2287/14/0 | **PASS**（`M2-5-1-ACCEPTANCE.md`：0 error + 2 minor 已修 + 1 observation） |
| M2-5-2 | Tone/Look 面板重组 + LGG trackball + HLS 面板 + add 面严格化 + 默认 look 全链（`.lalb` v1→v2） | `d584835`..`36f082b`（7+收口） | +18 → 2305/14/0 | **PASS**（`M2-5-2-ACCEPTANCE.md`：0 error + 1 minor 已修；本批修复 = strength clamp） |
| M2-5-3 | LUT 三件套（05 递归+键升级 / 06 可配根 / 07 内置集）+ phase 收口 | `a31ac15`..`1044641`（8） | +22 → 2327/16/0 | **PASS**（本报告：0 error + 2 minor 已修 + 2 observation） |

## M2GRADE 全族终态（REQUIREMENTS）

- **M2GRADE-01** ✅（M2-5-1 交付 + M2-5-2 面板半边终注）
- **M2GRADE-02** ✅（M2-5-1 params/kernel + M2-5-2 trackball UI + clamp 修复）
- **M2GRADE-03** ✅（M2-5-2 默认 look 全链）
- **M2GRADE-04** ✅（M2-5-1 ACEScc 域 envelope——本批勾选）
- **M2GRADE-05** ✅（M2-5-3 递归扫描 + 树分组——本批勾选）
- **M2GRADE-06** ✅（M2-5-3 可配根——本批勾选）
- **M2GRADE-07** ✅（M2-5-3 内置集 vendor，MIT 合规——本批勾选）

## 挂账（移交 verify-work / 后续 phase）

1. **Manual-Only 走查批**（GUI 验收轮同批）：M2-5-2 新面板走查 + trackball
   手感 + **LGG 拖杆 Manual-Only**（OQ-11 ①：≥4 Grade 层链拖 exposure/HLS
   流畅度）+ M2-5-3 LUT 树分组/折叠/刷新目测 + 缺引用 toast 三场景。
2. **100MP grade 层代价立项（OQ-11 ②）**：4 层 +870.8ms（含 grade 本体归因
   限制）超 ±5% 带——纯 envelope 归因需恒等梯度层探针（产品面缺口），立项
   与否归 orchestrator；不预优化。
3. **seeder/rescan 规模化**（本报告 O1）：哨兵改属性读取、rescan mtime
   短路；测试注入式根改善（F2）。
4. **FSEvents watcher = v2**（plan 预声明不做；刷新 = 面板打开 + 手动按钮）。
5. **域盲五件**（M2-5-1 移交）维持：本批 lut3d kernel/params 面零 diff 复核。

## 签核移交

C 档门控第 3 停：**M2-5 phase 签核（verify-work）**，输入 = 本文件 +
`M2-5-1-ACCEPTANCE.md` + `M2-5-2-ACCEPTANCE.md` + 三 SUMMARY/DECISIONS +
观察项走查清单。签核后 M2-6。
