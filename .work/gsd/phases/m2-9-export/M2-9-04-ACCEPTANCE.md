# M2-9-04 ACCEPTANCE — 检查器 Export 页 + App 装配点（wave 3）

**验收:** M2-9-04 独立验收 subagent（零共享上下文，实测核验不轻信）
**Date:** 2026-10-03 晨（夜间全自动授权在案；`[gsd]` auto=true/paused=false 全程未动）
**输入:** PLAN（checker E5 回注版）× SUMMARY × DECISIONS（§1..§12）× M2-9-03-ACCEPTANCE（基线 2662/16/0 + O-2 方向留意项）× GOAL-STATE 续接点 × 全仓源码/测试实读 + 机检亲跑
**对象提交链:** `ec69483`(T1 页挂载+Destination/Naming) → `572df73`(T2 Metadata&Color/SDR+质量四键) → `c97924e`(T3 Queue+装配+Core 载体) → `8cbcfbb`(T4 收口)

## 结论

# PASS / 0 error + 1 minor(已修) + 3 observation

Plan 九条 AC 全部独立复核通过；全套独立复跑**单轮干净绿 `TOTAL|2693/16/0|927s EXIT=0`**（2662+31 精确对账，skip 16 保全，七 bundle 逐值零漂移——Export 338/1/0 红线门实证 Core 载体默认 nil 字节稳定）。越界三处**全部追认**（§四逐一判定，均有钦定/真因/最小性证据）。1 minor = 复跑首轮撞出 SidecarV5Tests 环境型瞬态（已知在案 flake 复发：验收机 Data 卷 96% 满反噬 ANE/decode 腿）——验收批清 6GB 测试残留后终跑绿，根因归属与盘况证据在案（§六）。

## 一、全套独立复跑（三轮全记录）

独立 `xcodebuild build-for-testing`（专设 DerivedData 容器，产物七 .xctest 齐）→ `caffeinate -dis Scripts/test-direct.sh --all`：

**终跑（清盘后，正本数字）：**

| Bundle | M2-9-03 终态 | 终跑 | Δ | peakRSS | 判定 |
|---|---|---|---|---|---|
| IOP | 467/1/0 | 467/1/0 | 0 | 7854MB | 零漂移 ✓ |
| IOPParity | 362/3/0 | 362/3/0 | 0 | 5986MB | ✓ |
| Layers | 298/3/0 | 298/3/0 | 0 | 1058MB | ✓ |
| Library | 437/4/0 | 437/4/0 | 0 | 321MB | ✓ |
| Sessions | 279/4/0 | 279/4/0 | 0 | 1653MB | ✓ |
| Export（红线门） | 338/1/0 | **338/1/0** | **0** | 6970MB | **Core 载体零漂移实证** ✓ |
| App | 481/0/0 | **512/0/0** | **+31** | 1346MB | = 9+11+11 ✓ |
| **TOTAL** | **2662/16/0** | **2693/16/0** | **+31** | — | **精确对账** ✓ |

- 927s；peakRSS 全 bundle < 8192MB 门（最大 IOP 7854），零 MEMFAIL。
- 新测试类逐类点名（BUNDLE-MAP 行值 vs 文件 `func test` 终态）：ExportInspectorFaceTests **9**、ExportMemoryKeysTests **11**、ExportAssemblyTests **11**——登记 = 实测，03 波 M-1 同族缺陷本波未复发（验收亲数 `func test` 逐文件核对）。

**执行记录（前两轮，瞬态定性证据链）：**

| 轮 | 命令 | 结果 | 盘况 |
|---|---|---|---|
| 1 | `--all` 全套 | `2693/16/1`——App 唯一 fail = `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile`（decode readback 103s 轮询超时；log 紧邻 ANE `MILCompilerForANE` 编译失败行） | Data 卷 **96%**（余 8.2G） |
| 2 | `--bundle App` | `512/0/1`——**同用例**再红，异形态（flush 后 `.lra` 文件缺席，:396 throw） | 仍 96% |
| — | 隔离 `--bundle App 'SidecarV5Tests'` | **11/0/0（33s）** | — |
| — | 清理 sidecarv5 残留 ×84（≈6G，失败路径恒漏的已知卫生缺陷） | 盘 96%→93%（余 14G） | — |
| 3 | `--bundle App` | **512/0/0（258s）** | 93% |
| 4 | `--all` 全套（终跑） | **`2693/16/0`（927s）** | 93% |

## 二、逐 commit 边界审计

| commit | 申报 | 实测 `--stat` | 判定 |
|---|---|---|---|
| `ec69483` T1 | front-matter 8 源文件 + Project.swift + BUNDLE-MAP | 恰 10 文件（+1328/−5） | ✓ |
| `572df73` T2 | ExportInspectorView/ExportState/xcstrings/keys 测试 + Project.swift + BUNDLE-MAP | 恰 6 文件（+1125/−12） | ✓ |
| `c97924e` T3 | front-matter 6 + 越界 4（WorkspaceHostView/ExportQueue/ExportRenderer/ToastFaceTests，全部申报） | 恰 11 文件（+985/−8） | ✓（越界见 §四） |
| `8cbcfbb` T4 | SUMMARY/DECISIONS/GOAL-STATE | 恰 3 文档（+243） | ✓ |

波内 `fb821f3..8cbcfbb` = 20 文件 = **front-matter 13（含 checker-E5 补登记的 InspectorState + .xcstrings）+ 越界 4（申报）+ docs 3**，精确闭合无第五处。

## 三、红线零 diff 机检（亲跑）

| 红线 | 机检 | 判定 |
|---|---|---|
| `ExportPanelView.swift` | `git diff fb821f3..8cbcfbb` = **0 行**（比申报「连编译性补臂都不需要」更强） | ✓ |
| `ContentView.swift` | 恰 **1 hunk**、**0 minus 行**（numstat 42/0），全落 gate=false M2 分支（`.inspector` 挂载 + `\.exportPanelRequest` 复用发布 + 项目打开 rebuild）；legacyBody + legacy sheet 臂字节冻结 | ✓ |
| `LightamerApp.swift` | 0 行（菜单命令 + gate 求值点未动；根 environment 注入 :444-445 既有面） | ✓ |
| `InspectorView.swift` | numstat 24/5——旧 body 原文搬入 `standardBody`（内树逐行 context 无改），`.frame/.background/.a11y` 修饰上提一层到分支外壳（分支点结构性必需，inactive 渲染面等价；`Inspector` AX id 与 L010 注释保留） | ✓（实质逐字节成立） |
| Core 本波（`fb821f3..c97924e`） | 恰 2 文件：`ExportQueue.swift` 6 hunk（实测 hunk 数；SUMMARY 写 5 = 记账偏差，见 O-1）+ `ExportRenderer.swift` 恰 1 additive hunk；diff 内 `func pump/cancel/retry/markTerminal/finish/finishCancelled` **零命中**——引擎体零 hunk 亲验 | ✓ |
| legacy 三测试族 + `ExportQueueTests`/`ExportNamingTemplateStoreTests`/`LibraryLegacyGateTests`/`SidecarV5Tests` | 各 0 行 | ✓ |
| 剥离门双向 | `openExportPage` 全仓恰 3 调用点：ContentView M2 分支 ×2 + WorkspaceHostView topbar ×1（`workspace.phase == .editor` 门）；`legacyBody` 零武装点（source fact）+ LibraryLegacyGateTests 全绿 | ✓ |

## 四、越界三处审计（晨审裁决点，逐处判定）

### ① Core 载体两面（ExportQueue + ExportRenderer）——**追认（成立且钦定）**

- **缺口真实性**：M2-9-03-SUMMARY 交接节原文「queue 路径暂无 App→encoder 的 Software 载体（Contract 冻结 + variant 无字段——**本 plan front-matter 不许加**）→ 04 需 enqueue 增参 + carrier 递缝（jobDrtTail 同款）」；M2-9-03-DECISIONS :205 同文。04 plan front-matter 确实漏列 Core 文件（E5 同族遗漏——front-matter 只有 App 文件）。**03 钦定 04 接缝属实。**
- **引擎体零 hunk 亲验**：diff 仅 Job 增字段/enqueue 双增参（默认 nil）/precondition/Job init 折叠/`$jobExifSoftware.withValue` 包装/encodeLeg 消费行；pump/cancel/retry/generation/markState/markTerminal/finish/finishCancelled 零命中。
- **legacy 字节稳定**：`instancesOverrides?[i] ?? instancesOverride` 折叠 + 双参默认 nil；**Export bundle 338/1/0 两轮亲跑零漂移**为直接实证。
- **per-image instancesOverrides（DECISIONS §2）**：KD-4 明文「逐图构造」，queue 批级单值装不下；备选「逐图单次 enqueue」会破坏 queue 盖章批序（每次调用 imageIndex 归零 → sequence 恒 1）——索引载体是保序唯一干净路径，drtTails 先例同形。typed 拒绝先行（count 失配 App 层 typed throw，O-2 前车之鉴兑现）。

### ② WorkspaceHostView——**追认（KD-1/KD-4 的正主落点，最小面）**

- M2 面无 window toolbar，topBar = 「toolbar 导出按钮」等位物（KD-1 措辞的物理落点）；32 行 = 2 env 声明 + topbar 按钮（editor phase 门 + `shell.topbar.export` AX id）+ `m2SelectionProvider` 臂（KD-4 目标推导，L036 注入纪律：shell 拥有选择态、装配点只读——provider 是 KD-4 的必要腿，非可选装饰）。
- weak 捕获 + 空选择回落当前图，与装配测试 `testM2SelectionProviderFace` 双向钉。

### ③ ToastFaceTests 环境随动——**追认（真因修复，非断言偷懒）**

- diff = HostRoot 补 `ExportState`/`InspectorState` 两 `.environment()` 注入 + 构造点随动；**生产码零改动、断言零改动**——修的是「最小宿主少注入新 env 依赖 = 挂载即 trap」（L056 候选教训），与「改断言绕开挂载」的偷懒路径正相反。
- trap 实测在案（DECISIONS §1.3 `No Observable object of type ExportState found`）；InspectorView 同类 AX 测试的宿主注入清单（7 面）为对照正本。

## 五、重点抽查（读码 + 断言体亲读）

1. **OQ 生效值逐条落点**：OQ-1 检查器新页（页开关 + Inspector 列 swap + legacy sheet 冻结）；OQ-3 跨会话记忆（`export.lastDirectory` path 串 + picker 即时写回 + run 写回 + 首用回落首图目录，`testDestinationMemoryRoundTripAndFirstUseFallback`）；OQ-10 四格式各一键（登记拼写常量 + kind→key 映射 + `testQualityKeySpellingsMatchRegistration`）；OQ-11 子文件夹默认关 + 默认文案 **en "Processed" / zh「导出」**（xcstrings 亲查）；OQ-12 高级折叠区（DisclosureGroup + allowUpscale=false/maxEdge=0 + 测试钉）；OQ-6 UI 单开关（`metadataOn → .standard/.none`，模型 6 bool 不触）。全部与 M2-9-CONTEXT :230 裁决清单逐条对上。
2. **质量四键 typed 读 + 生命周期**：`defaults.object(forKey:) as? Double` + isFinite + `qualityRange`(=0...1, ExportRecipe.swift:342 亲核) 域校验；mount/切格式载入（`formatSelection` set 臂先写回旧格式再载新格式）+ run/离页写回（`writeBackQualityMemory` 双调用点）；**0.0 假记忆修正回归在案**（`testQualityZeroIsARealMemoryNotAnUnsetKey`——presence-check 会把「未存」与「存了 0.0」混淆，typed 读修正被自家测试钉住）。
3. **enqueueExportM2 装配逐字段**（真链捕获，非 stub——注入腿在 actor 的 withValue scope **内**读载体）：per-image override（open 图=活投影 `editorState.instances`〔= baseInstances ∪ history.effectiveInstances()，EditorState.swift:95 注释亲核〕/其余 nil 盘真相）；`drtOutput = drtRecord`（OQ-7 强制联动）+ 每图 `DrtTailParams(record:postOpNames: NodeOwnershipCatalog.drtPostOpNames)`（PipeCoordinator:660 同法 verbatim 亲核）；模板批序 sequence 1/2 FIFO 断言；policy/subfolder/collision(.fail) 透传；exifSoftware encode 腿逐 job；relPath=展示名（快照显示面断言钉）。count 失配 typed 拒绝先行（queue precondition 前）。
4. **ExportNamingEditor**：预设 CRUD（存 sheet/改名 inline/删，内置不可删——`selectedUserTemplate` 只在 store.loadTemplates() 中命中，内置构造性不入存储）；11 token（拼写逐枚断言 = OQ-4 语法）；typed 反馈（`ExportFileNameTemplate.parse` 五错误族，红字 + raw message）；live 预览（样本 stem + sequence=1 + 空 capture 缺省渲染，`testLivePreviewRendersTheSampleContext` 四断言含 fallback "image"）；手改 pattern → Custom 掉锚。store 注入式（`NamingTemplateStore` 默认 `.standard`、测试隔离 suite；视图 body 零 defaults 直读——grep 亲验）。
5. **队列节**：四态映射穷举 switch（含 `.done(URL)`/.failed(.cancelled)/.cancelled 三形态断言）；36 帽纯函数 + `…(N more)`；进度条 + 失败红字摘要 + retry（failed 档）/cancel（非终态档）双按钮；空态 ContentUnavailableView；add/clear 门（canRun = naming+sizing+targets+destination 四腿合取）。
6. **层语义边界（晨审重点）**：`layerRecord = nil` 起源 blame = fb5b044（11-03 ExportRenderer 创建）——**现行语义非本波引入实证**；本波该分支仅 03 加过 `if naming != nil` 行。DECISIONS §3 如实登记「带层图 M2 面 override 腿 = base 链像素」+ 立项选项留给晨审/M2-9-05 走查 #4。**判定：诚实申报的既有边界，非本波缺陷、非掩盖；晨审裁决点维持**（plan KD-4 原文「instances + layerSnapshot 随 active 链走」只兑现 instances 半边——Core layer 座位属「纯 App 波」红线外，正确定性）。
7. **O-2 方向留意项消解核验**：enqueueExportM2 只走 queue 面命名参（`ExportNamingRequest` 经 enqueue），从不设 Request 命名族——03 验收 O-2 的「双设方向不对称」在 M2 腿无触发面。
8. **键面/审计**：`zh-audit --check` PASS 亲跑（**1633 catalog keys**，locale {en,zh}，source 1398）；插值键 `%lld` 拼写亲查（`export_face_add_selected %lld`/`export_face_more %lld`/`export_face_failed_summary %lld` 全在册）；M2 页相关键抽查 zh/en 双语完备。

## 六、minor 与 observation

- **M-1（minor，验收批已处置）**：验收首轮全套撞出 `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile` 环境型瞬态（两轮两种形态：decode readback 超时 103s〔log 紧邻 ANE MILCompilerForANE 编译失败〕/ flush 后 `.lra` 缺席；隔离 11/0/0）。定性 = **已知在案 flake 复发，非产品回归**——同用例同失败族在 M2-5-3（「负载型 flake 结案」）与 M2-8-2（「受害用例轮换 + ANE 推理面错误 + 非产品回归」）两度登记；根因条件复现 = 验收机 Data 卷 96% 满（M2-8-2 查明的「temp 累积顶盘反噬 ANE/decode 腿」，其卫生缺陷 observation③ 恒漏未除）。处置：验收批清 sidecarv5 残留 ×84（≈6G，盘 96%→93%）→ App 单 bundle 绿 → **全套终跑 `2693/16/0` 单轮干净**。受害文件本波 0 字节触碰（git diff 亲验）+ 该测试主subject（sidecar 写腿/decode）本波零 hunk。**卫生缺陷本体（测试失败路径不清工作拷贝）仍开放**——M2-8-2 observation③ 维持，建议独立小修 plan（test teardown 加 residue sweep 或 setUp 清同名前缀）。
- **O-1（observation）**：SUMMARY「ExportQueue.swift 5 hunk」实为 **6 hunk**（Job 字段/enqueue 签名/precondition/Job init 折叠/execute 包装/encodeLeg 消费）——03 波 O-1 同族 hunk 记账文字错位，实质主张（全载体 + 引擎体零 hunk）亲验成立，以本报告为勘误正本。
- **O-2（observation）**：`testQualityDegradesOnOutOfRangeNonFiniteAndForeignTypes` 测试名含 non-finite 但 body 未实测 NaN/±inf（越域/异型/Data 三态有）——实际不可达面（plist 无法存储非有限 Double，UserDefaults 会拒/串型），`isFinite` 守卫在代码层在位；测试名与覆盖面的措辞差，不改行为。
- **O-3（observation，正向）**：`ExportPanelView.swift` 全波 **0 行 diff**——比 plan 纪律 2 允许的「编译性补臂」更干净（01 波已备的 sizing 补臂最终未需要），legacy 冻结红线以最强形态兑现。

## 七、AC 逐条（9/9）

| # | AC | 独立核验 | 判定 |
|---|---|---|---|
| 1 | M2 面 Export 页可达 + legacy sheet 冻结（gate 双向） | AX 双向测试亲读 + `openExportPage` 调用点机检（legacy 零武装点）+ ExportPanelView/ContentView 0 minus 亲跑 | ✓ |
| 2 | 五节齐备 + 默认值对表 Alcedo | 五节读码 + `testPanelModelDefaultsMatchAlcedo`（0.95/2048/210×297@300/OQ-11/12/6/7 默认逐项） | ✓ |
| 3 | 落点记忆 + 首用回落 | round-trip + fallback + 降级三测试亲读；picker 即时写回 + run 写回双点 | ✓ |
| 4 | 质量四键 round-trip + 键名=登记值 | 拼写测试 + 源码 grep 双锚；typed 读/0.0 真记忆/异型降解 | ✓ |
| 5 | 装配逐字段断言 | ExportAssemblyTests 真链捕获 11 法亲读（§五.3 逐字段） | ✓ |
| 6 | 模板无效禁用 + 错误展示 + live 预览 | parse 五错误 + canRun 门 + 预览四断言 | ✓ |
| 7 | 四态 + 36 帽 + 进度 + retry | 穷举映射 + previewSlice 边界（36/40→4 more/≤36 无汇总） | ✓ |
| 8 | zh-audit PASS + locale 纪律 | 亲跑 PASS（1633 键，{en,zh}） | ✓ |
| 9 | App 0 fail + 双登记闭环 + 全套精确对账 | 终跑 512/0/0 + Project.swift 3 行 + BUNDLE-MAP 9/11/11=实测 + 2662+31 精确 | ✓ |

## 八、翻账与提交

- **REQUIREMENTS**：**M2EXP-01/02/03/04 翻勾 Delivered**（各追「Delivered 终注」：01 面板 UI 半边〔四模式字段+折叠区+模型域禁入〕/ 02 App 传值载体〔$jobExifSoftware 递缝〕/ 03 面板 UI+模板选择器〔EditorEditor 全功能面〕/ 04 面板装配〔OQ-7 强制联动+peak 兜底〕）——模型/消费/UI 三半边跨 01-04 波闭环，验收报告齐备。**M2EXP-05 追「队列 UI 半边 Delivered」注记不翻勾**（真机观感/走查归 M2-9-05，yiyin 适配 = 注入器保留 + topbar sheet 入口不变，翻勾留走查批）。
- **GOAL-STATE**：验收续接点入账（含越界三追认 + 层语义晨审项 + 盘压瞬态处置记录）。
- **本验收批提交**：单 docs commit（本报告 + REQUIREMENTS 五处 + GOAL-STATE）。**不 push。**

## 九、下一步（交接 orchestrator）

C 档第 2 停 = M2-9-04 plan 闭环汇报（本报告为输入）→ 用户确认 → **M2-9-05**（GUI 走查批：五节观感/topbar 入口/legacy 回切双向 #10/层语义差异暴露 #4〔晨审 §12.2 同点〕/尾追 token 手感/add-start 塌缩形态；AGENTS.md 键册补六键：`export.lastDirectory` + 质量四键 + `export.namingTemplates`）。晨审待裁项汇总（DECISIONS §12 + 本报告）：①越界三追认 ②层语义 base 链行为是否立项 Core layer 座位 ③目标集=编辑面网格选择 ④add/start 塌缩形态。SidecarV5 卫生缺陷独立小修另案。
