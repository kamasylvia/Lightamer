# M3-1-03 ACCEPTANCE — 小件族合并批 + zh 清算 + M3-1 phase 收口

> 验收 2026-10-08，独立验收 subagent（零共享上下文，实测核验不轻信）。
> 被验批次 = T1 `7a800a5` + T2 `158a468` + T3 `c5afe0d` + T4 `d4ae750` + T5 `184d1aa`
>（五 commit 未 push，基线 `0241a1c`）。

## 结论

**PASS / 0 error + 1 minor + 1 observation**（minor 已修于本验收 commit）

- minor-1：SUMMARY §四 对账表「M3-1 前」列 Layers/Export 两格陈旧值（268/337）——
  基线 2962 逐 bundle 分解（471+363+300+581+279+338+630 = 2962 精确）证明两格基线
  即 300/338；系旧 era 表抄手陈值，对账式本身以 2962 总锚 + BUNDLE-MAP 登记增量
  计不受扰——**验收批已修**（两格改正 + 表下勘误注记）。
- obs-1：plan front-matter `files_modified` 漏列三文件——T3 路由腿
  `PipeCoordinator.swift` + `IOPPanelProvider.swift`（session→coordinator→EditorState
  纯转发 9+10 行，KD-3「面板只认 InspectorEditSession」的结构必经）+ T4 F1 落点
  `ContentView.swift`（KD-4 F1 sweep 的承载面）。三文件均在 SUMMARY §七 diff 边界
  节如实申报（非静默扩面），红线域零涉——front-matter 不完整记 observation，
  不构成范围违反；后续 plan front-matter 编制时对「路由缝/F1 类扫批」类任务应把
  结构必经的转发文件列入申报集。

## 一、亲跑数字（全套独立复跑 + 定向）

| 项 | 结果 | 判定 |
|---|---|---|
| 产物新鲜度 | xctest 七件 mtime 12:12 > T4 提交 11:22:55；`find -newer` 产线源零命中 | ✓ 零陈旧构建疑虑 |
| **全套 `caffeinate -dis Scripts/test-direct.sh --all`** | **`TOTAL\|3024/16/0\|1113s` exit 0 零 MEMFAIL**（1119s 申报 1077s = 时长差，计数逐位同） | ✓ = 申报值逐位命中 |
| — IOP | 471/1/0，peak 7594MB | ✓ `08dd061` 逐位基线；<8192 门 |
| — IOPParity | 389/3/0，peak 5984MB | ✓ 01 终态逐位 |
| — Layers | 300/3/0，peak 1128MB | ✓ 登记面 |
| — Library | 587/4/0，peak 606MB | ✓ 01 终态逐位 |
| — Sessions | 279/4/0，peak 1616MB | ✓ 登记面 |
| — Export | 338/1/0，peak 5890MB | ✓ 引擎钉死族零改全绿 |
| — App | 660/0/0，peak 2831MB | ✓ 649 + 本 plan 11 |
| L055 双保险亲核 | 七 bundle 末条 Executed 全挂 `Test Suite 'All tests' passed`（IOP/App 两份亲读 + 余五份脚本 verdict=ok 机检同构）；`terminated abnormally`/`Restarting after unexpected exit` 全日志零命中 | ✓ |
| 定向 `--bundle App ExportCollisionPickerTests` | **5/0/0**（7s） | ✓ |
| 定向 `--bundle App NLMeansDragDowngradeTests` | **6/0/0**（瞬时） | ✓ |
| `zh-audit.py --self-test` | SELF-TEST PASS（exit 0） | ✓ D5 形态亲验 |
| `zh-audit.py --check` | **PASS（1534 source / 1772 catalog，zh complete）** | ✓ 与申报逐位同 |

对账式亲核：2962（M2-11-05 终验实测 2961，perf.md §PERF-07 + `08dd061` +1）
+ 37（01）+ 14（02）+ 11（本 plan：Picker 5 + Bypass 6，BUNDLE-MAP 增行
`APP 5`/`APP 6` × Project.swift :770-771 × `grep -c "func test"` 5/6 三方对表）
= **3024**；登记面起算 3013（2999+14）+ 11 = 3024 两式互证；全套实测逐位命中。

## 二、逐 commit 边界（对照 front-matter + 红线机检）

- 五 commit 文件清单与申报集一致（§四表）；`ExportPanelView.swift` 预期零 diff
  层面兑现（全程零触）。obs-1 三文件为 front-matter 漏列（已在 SUMMARY §七申报）。
- **红线域 `git diff --name-only 0241a1c..HEAD` 零命中亲跑**：ExportNamer /
  NLMeansModule / PixelPipe.swift / DrtOutputColorSpace / ExportState.swift /
  DrtEotf / 六格式编码器 / WebPEncoder / PipeCacheKey / V50Order / ModuleRegistry /
  ExportICCStrip / Lut3dKernels.metal——grep 零命中。
- `Localizable.xcstrings` = 193 插入 / 0 删除（`^---` 头除外）纯增量亲验；JSON
  parse 有效；catalog 恰 1772 键；新增键块居文件尾部。M2-9-VALIDATION 历史
  文件 range log 零命中（挂账#4 关闭 = SUMMARY 声明，历史行未改写）。
- T5 `184d1aa` = 纯 docs（SUMMARY/DECISIONS/AGENTS/GOAL-STATE/TODO/MANIFEST +
  五证据图），零产线文件。

## 三、小件族抽查（实机证据 + 读码）

### T1 冲突档（挂账#4 关闭）——证据充分性成立

- **透传链闭合亲核**：Picker（`export.page.collision`，三 tag 绑
  `ExportNamer.ExportCollisionPolicy`）→ `ExportM2PanelModel.collisionPolicy`
  （`@State private var model` :33 = 页视图寿命，D1 会话态裁定与代码面一致）→
  `makeRunAssembly` 纯缝（RunAssembly 值类型，nil = run-gate miss，overrides
  快照读取顺序与重构前逐位等价亲读）→ `enqueueExportM2(collisionPolicy:)`（:472
  既有形参零 diff）→ `queue.enqueue(collisionPolicy:)`（:507）→ NamingCarrier →
  `ExportNamer.resolve`（:121/:133 既有引擎消费）。
- **挂账#4 关闭三判据**：①Picker 在场（代码 + 装配 AX 挂载测试 + MANIFEST #2
  截图）；②选择值达队列（逐档装配测试亲跑绿 + 既有 `ExportAssemblyTests`
  真队列捕获面 `collisionPolicy` 断言在册 + 引擎 `testFailPolicyFailsQueueJobWithoutWriting`
  族既有）；③三档行为走查（MANIFEST #3 三档菜单截图 + Fail 选择 AX 翻转）。
  历史文件零改写，关闭 = SUMMARY §三声明合规。
- 证据截图目检：三档菜单全 zh 尾注（✓ Increment / Fail / Replace）同帧含 SDR
  readout 无说明行（T2 SDR 零变化同帧旁证）。

### T2 peak-ICC 说明行

- `isHdrEncoding` = **Core 单源亲核**（`LightamerCore/Sources/Graph/DrtRecord.swift:456`
  自由函数，与 `legalEOTFs` :445 同族；视图零重推导）；SDR 臂仅加 VStack 父容器、
  可见面零变化（读码 + 截图同帧旁证）；HDR 档截图目检 = `rec2020 · st2084 · 100 nits`
  + 说明行全文与 catalog zh 值逐字一致；`export_drt_peak_note` 键 zh/en 在册。
- `DrtOutputColorSpace.swift` / `ExportICCStrip` 零 diff（红线机检）；签名面零触碰
  （M2-9-02 边界正本不动）。

### T3 denoise 拖动旁路——六测逐条读码 + Manual-Only 判定成立

- **六测逐条核**（6/0/0 亲跑）：①身份键控 + 姊妹 nlmeans（异 UUID + multiPriority 1
  layer-embedded 形态）零连带 + tick 窗内强制不复活 + 窗零 history；②先验 disabled
  复原 + 双 arm 幂等 + 无 arm disarm no-op；③三件套（窗零 items → 松手恰一 commit
  → committed enabled 未触 + ticked params + `effectiveInstances` 真相同步）；④零
  tick 不伪造 commit；⑤load 重建清扫 + commit 自愈；⑥session 路由。
- **三防线代码面亲读**：`previewDenoiseBypass: [UUID: Bool]`（值 = arm 时先验
  enabled）+ `recordChange` removeValue 自愈（commit 即真相）+ `resetHistoryForNewImage`/
  `rebuildInstances` 双清扫 + upsert 强制（armed 时 incoming.enabled 压 false）。
  旁路永不进 `liveEdited`（D4 FULL 判定面语义与代码一致）。D9 顺序（disarm 先于
  endEditing）在面板 dragEnd 落实。四滑杆挂点全接线（编译期）。
  重建清扫测试覆盖 load 腿（rebuildInstances 腿同 helper 调用，代码亲读在案，
  测试未单列——observation 级，不构成缺口）。
- **Manual-Only 登记合理性判定：成立**。不可达论证双腿亲核：①
  `NLMeansModule.opName` ∈ `LightamerIOPRegistry.defaultFaceDisabledOpNames`
  （`LightamerIOP/Sources/Registry.swift:48`）；②tab shell 描述符表
  （`App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift`）全页枚举
  （tone/look/lut/displayTransform/geometry/rawDecode/mask）**零 nlmeans 席位**
  （文件 grep 计数 = 0）；③`NLMeansPanelView` 唯一实例化点 = 面板文件内 :128
  工厂（registry 门控provider）。默认 Alcedo IA 结构不可达论证成立；plan 纪律 4
  明文「GUI 不可达 = Manual-Only 登记不阻塞翻账」；补偿覆盖（状态层六测 + 挂点
  编译期 + D-H1 既有语义）充分；补走查配方在 MANIFEST。**接受登记**。

### T4 zh 清算

- V14：两处动态键位 → `ratingMenuLabel`/`colorMenuLabel` 显式 switch 静态键
  （读码亲核；13 键 = 11 在册 + 2 clear 既有键全含 zh 值——catalog 逐键
  python 亲验）；标记菜单 13 键 zh 截图目检（清除评分/1..5 星/精选/拒绝/清除
  旗标/清除色标/红..紫全 zh + 快捷键）。
- V15：form 1c 行对状态机（`PENDING_LOCALIZED_RE` + `LEAD_LITERAL_RE`，注释行
  保持 pending）读码核；`--self-test` 亲跑 PASS（含 1c 静态键提取 + 插值前缀
  两条新负测 + 既有四 violation case）。
- D6 真缺口核验：`GlobalSearchDialog.swift:113/:138` 实为 `String(localized:`
  行尾 + 键次行开头形态（1c 命中面真实）；两键 en 值逐字转录代码 defaultValue
  （"e.g. sony iso800 f/2.8 35mm 2024-06" 等）+ zh 值同批入册亲验。
- F1：`project_face_*` 四键替换四处 verbatim（ContentView diff 亲读）+ "Lightamer"
  品牌词 verbatim 保持；D7 两处 verbatim「Import Folder…」:1301/:1635 亲核在位
  （登记不修 = M2-3-4 先例合规）。
- 键族登记节（AGENTS.md）与 catalog 实际一致（12 新键逐键 zh 亲验 + UserDefaults
  零新增）。

## 四、phase 收口审计（M3-1 终态意见）

- **对账链**：2962 → 2999（+37）→ 3013（+14）→ **3024**（+11）四点全对表
  （BUNDLE-MAP 增行记录 + 各波 SUMMARY/ACCEPTANCE + 本批全套实测）。
- **翻账面**：AGENTS.md「M3-1 架构增量」节 = 三 plan 约定正本（编码维/sheet
  拖拽/旁路三防线/冲突档会话态/peak-ICC 面/1c 硬化/键族登记）——声明与代码
  实况逐条相符（本验收读码逐项印证）；GOAL-STATE 续接点 + L057 队列行 +
  M3-2 交接节完整（交付物就绪面 + 阻塞余量五项）；TODO M3-1 行改写与实际一致。
- **收口意见**：M3-1 W1 三 plan 全闭环成立——主线交付（M2GRADE-08 编码建模 /
  YIYIN-09 拖拽语义 / 小件族四件 + zh 清算）+ 两波验收 PASS + 本波验收 PASS；
  挂账面（L057 专项 / M4 coordinator 串行化 / T3 补走查配方 / D7 verbatim ×2 /
  冲突档跨会话记忆）全部有主、有指针、有触发条件。**同意进入 phase VALIDATION
  签核（C 档第 3 停）**。

## 五、AC 总表对账

| AC | 判定 |
|---|---|
| 1 三档 Picker 在场（Increment 默认）+ 选择值达队列；引擎/ExportState 零 diff；钉死测试零改全绿 | ✓（透传链读码 + 装配测试亲跑 + 红线机检 + Export 338/1/0） |
| 2 peak-ICC HDR 说明行 + SDR 零变化 + DrtOutputColorSpace 零触碰 | ✓（单源亲核 + 双态截图目检 + 红线机检） |
| 3 拖动态旁路零 params/history/pipe 触碰 + 松手恰一 commit + FULL 判定面不变 + 实例键控 + 状态条 | ✓ 状态层（六测亲跑 + 读码）；实机观感 = Manual-Only **判定成立**（双腿亲核 + plan 纪律 4 条款） |
| 4 V14 显式化 + V15 负测 + F1 清账 | ✓（读码 + self-test 亲跑 + 四键/catalog 亲验） |
| 5 `--check` PASS + 标记菜单实机 zh | ✓（1534/1772 亲跑复现 + 13 键截图目检） |
| 6 全套终轮绿 + 终值对账 + 七条锚状态落 SUMMARY | ✓（3024/16/0 亲跑逐位 + §三锚表核） |
| 7 登记闭环（E2/L041）+ 红线域零命中 | ✓（三方对表 + range grep 零命中） |

## 六、验收批增量

- 本文件 + SUMMARY §四 两格勘误（Layers/Export 基线值 + 勘误注记）+ GOAL-STATE
  验收续接点——单 commit `fix(m3-1-03)`，未 push。
- 零代码变更（minor-1 为台账表格勘误；产线码零触碰，无需回归——全套 3024/16/0
  即当前树实测）。
- 验收过程副作用：无（全程读码/跑测/目检截图，未启动 GUI 实例、未触碰
  defaults/临时项目；测试宿主进程随脚本自然退出）。
