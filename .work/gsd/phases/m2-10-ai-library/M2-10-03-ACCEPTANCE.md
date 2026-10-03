# M2-10-03 ACCEPTANCE — 自动打标 + 后台任务注册表 + 导入询问接线

> 验收 subagent（零共享上下文，实测核验不轻信）。验收对象 = 三提交
> `f15bb96` / `6a756bd` / `4c07dc6`（HEAD `4c07dc6`，未 push）。正本输入 =
> PLAN（含 checker 回注 E1..E4/M 级）+ SUMMARY + DECISIONS（§1..13）。验收
> 日期 2026-10-03。基线 = M2-10-02 验收终态 2759/16/0（HEAD `321383b`）。

## 结论

**PASS / 0 error + 0 minor + 3 observation** —— AC 8/8 全过；越界三件
**全部追认采纳（零驳回）**；执行期修复三件（解析器模板行 / drain 双 fire /
sheet binding）证据链亲证；全套独立复跑单轮干净绿
`TOTAL|2797/16/0|926s EXIT=0`；真原型链 sanity 激活态跑绿非 skip 亲证；
M2AI-03 / M2AI-07 翻勾。

## 全套独立复跑（对账 2797/16/0）

`caffeinate -dis xcodebuild build-for-testing`（workspace/scheme 标准命令，
HEAD `4c07dc6`）→ `caffeinate -dis Scripts/test-direct.sh --all`：

| bundle | 本轮 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 467/1/0（peak 6584MB） | 467/1/0 | 零漂移 |
| IOPParity | 362/3/0（5999MB） | 362/3/0 | 零漂移 |
| Layers | 298/3/0（1050MB） | 298/3/0 | 零漂移 |
| Library | **515/4/0**（937MB） | 515/4/0（503→515，+12 全落此） | 零漂移 |
| Sessions | 279/4/0（1614MB） | 279/4/0 | 零漂移 |
| Export | 338/1/0（5932MB） | 338/1/0 | 零漂移（红线门） |
| App | **538/0/0**（1318MB） | 538/0/0（512→538，+26 全落此） | 零漂移，**一轮过** |
| **TOTAL** | **2797/16/0，926s，EXIT=0** | 2797/16/0（975s） | **精确对账** |

- 对账：2759（M2-10-02 验收基线）+ **38 精确** = LabelEngineTests 12（全落
  Library）+ AnalysisRegistryTests 13 + LabelingDefaultsTests 13（全落 App）；
  App 日志两新 suite `passed` 行亲点，`grep -c 'func test'` = 12/13/13 与
  BUNDLE-MAP 三行逐位一致 ✓。
- skip 16 = 基线零新增；App bundle 本轮 skip 0。零 MEMFAIL：最大 IOP
  6584MB < 8192 门（执行批申报 7857MB，同为 <8G，±3% 方差注记口径内）。
- **真原型链 sanity 激活态跑绿亲证**：`testRealPrototypesClassifyRealEmbedding`
  passed（2.586s，非 skip）——173 真原型 × 真嵌入链（embedAndStore →
  loadScanRows → classify 全表降序 + 余弦带 ±1.002 → replaceLabels →
  labels 读回 top8）端到端；无模型环境三重 XCTSkip 门在码可审计（AC#7 双读
  口径成立）。

## 逐 commit 边界（纪律 8）

| commit | 文件集 | 判定 |
|---|---|---|
| T1 `f15bb96` | LabelEngine + LabelQueries + generate_label_prototypes.py（越界①，body 申报）+ build_default_bundle.sh（E3）+ LabelEngineTests + Project.swift | == 申报 |
| T2 `6a756bd` | AnalysisTaskTypes + AIAnalysisRegistry + LabelingPromptController + ImportModeDialog + LibraryPreferences + LibraryProjectController + WorkspaceHostView（越界②）+ AIInferenceService（越界③）+ AnalysisRegistryTests + LabelingDefaultsTests + Project.swift | == 申报 |
| T3 `4c07dc6` | SUMMARY/DECISIONS/GOAL-STATE + BUNDLE-MAP 三行 | == 申报 |

三提交合计 diff = 20 文件 = **front-matter files_modified 16 + 越界申报 3 +
BUNDLE-MAP 账本 1**，零未申报文件（亲跑 `git diff --stat 321383b..HEAD`
逐行核对）。工作区滞留 = gui-acceptance 截图/.build/ 等既有非本批物，
未触碰。LESSONS 无增项：T3 body 显式论证两坑（模板行/双 fire）已钉
DECISIONS + 回归测试，非重复犯类，front-matter「如踩坑」条件句不触发——成立。

## 越界三件判定（申报待追认 → 逐件裁定）

| # | 文件 | 判定 | 依据 |
|---|---|---|---|
| ① | `generate_label_prototypes.py`（新，148 行） | **采纳** | E3 只申报了 shell 修改，生成阶段独立成脚本 = `Scripts/ai-models/` 既有先例形态（convert_chinese_clip.py / convert_real_esrgan.py / tokenizer_ref.py 同目录同模式亲证）；可独立运行 → 本机已实跑产真原型（盘上 177,152B 亲验）；front-matter 漏列属起草缺口非执行越权；commit body + DECISIONS §3 双申报在案 |
| ② | `WorkspaceHostView.swift`（65 行） | **采纳** | registry 必须构造在 shell `BackgroundTaskRegistry` @State 所在宿主（M2-3-1 所有权 + 协议零 diff 红线下唯一挂点）；prompt sheet 与既有 5 sheet 同级；`.task` 块 = controller.aiAnalysis/labelingPrompts 唯一注入点（diff 亲读：@State ×2 + 绑定块 + sheet + .task 四 hunk 均功能性必需，零夹带）；commit body + DECISIONS §9 双申报 |
| ③ | `AIInferenceService.swift`（18 行） | **采纳** | 薄代理亲读：`cachedSearcher` → `cachedEngine` concrete 收窄 + `analysisEngine()` 访问器 + `engine()` private 装配体；`semanticSearcher()` 委托同体——同一 memoized 装配双 typed 视图，行为零变（fail-closed nil 面不变）；无它则 registry 拿不到引擎且破坏单向 memoize；commit body + DECISIONS §9 双申报 |

## 机检亲跑记录

1. **原型链三证**：`prototypes.bin` = 177,152 bytes = 173×512×fp16 **精确**；
   `prototypes.json` revision `36e679e6…` 与 `ModelAssetCatalog.swift:98` pin
   **逐字相同**；`git check-ignore` 命中 `.gitignore:53`，`git ls-files
   Resources/AIModels/` 仅 `.keep`（体积红线零跟踪字节）。
2. **单源解析防呆**：`grep -c 'LabelQueryEntry(label:'` = 174 = 173 真条目 +
   1 头注模板行；生成器 ENTRY_RE 强制引号值 + 「…」过滤双保险——模板行
   （值无引号）结构性不可命中；重复 label SystemExit 防呆在码。
3. **E3 字节等价**：shell diff 18 行纯插入（0 删除），flag 块整体
   `WITH_PROTOTYPES -eq 1` 门控；无 flag 行为差 = 源码一处空行（产物零影响）
   ——01 链输出字节等价论断成立（DECISIONS §3 勘误：申报「17 行」实为 18，
   本验收批已更正）。
4. **exactly-once 取消**：`userRequestedCancel` 在队（含运行中，任务执行期
   仍占 queue[0]）→ 出队+finish+fire；drain 尾只在任务**仍在队**时
   finish+fire——双路径互斥由 `firstIndex` 查找结构性保证；回归测试
   `testCancelMidTaskKeepsCompletedRowsOnly` 断言 `finishedIDs == [id]`
   （旧双 fire 实现下必得 `[id, id]`）——揭穿力亲读成立。
5. **串行 utility**：drain 单飞（runner 存在即不重启）+ `Task(priority:
   .utility)` + 每张 `Task.yield()`；mock 引擎 `maxInFlight` 计数器在
   60ms 延迟窗下断言 == 1 + FIFO 序 `[1,2,3,4,5]`——「分析期间可继续工作」
   机制面成立；解码/IO 全在后台腿（imageData → ImageLinker resolve →
   Data，零主线程解码）。
6. **导入接线**：`runImport` 成功尾单块（注入点两个字段 + MAX(id) 高水位 +
   `imported > 0 && !cancelled` 门 + `try?` 静默跳过腿）——ImportService/
   ImportFilter 零触碰亲证；三态真链 ×3 passed 亲点（ask 弹/always 跳/
   never 仅嵌入）；弹询时机 = `importProgress = nil` 后一拍 `Task.yield()`
   且 `intentForNewImages` 不发布（测试钉 `pendingPrompt` 仍 nil）。
7. **键族惯例**：`LabelingPreferences` 与 `ImportDefaults`（ImportFilter.swift
   :126）同构逐项对上——常量键 `library.ai.labelingMode` + 注入 suite +
   全量替换 store + reset + 垃圾值回落 `.ask`（写用户可见态的安全默认）。
8. **3b 保护面零 diff**：BackgroundTaskHosting / Core ImportService /
   Session ImportService / ImportFilter / LibrarySchema / SemanticStore /
   SemanticEngine / EmbeddingScanner / WordPieceTokenizer /
   SemanticStoreTests——`git diff --name-only` **零文件**亲跑（02 产物与导入
   链红线全绿）；`replaceLabels`/`loadScanTable`/`upsertEmbedding`/`activeModel`
   全走 02 公有面，fp16 逐行解码用公有 `FP16Coding`（DECISIONS §12 兑现）。
9. **登记闭环**：三测试文件 Project.swift :537/:698/:701 三命中 + BUNDLE-MAP
   三行（12/13/13）与 `func test` 计数逐位一致；App/Library 日志两新 suite
   passed 亲点。

## 重点读码抽查

- **LabelEngine**：classify = 纯点积（零隐式 norm——非单位输入翻倍由
  `testNonUnitInputTreatedAsNormalizedContract` 钉死）；排序 tie-break 字母序
  确定性；tail 行 confident 恒真（无事反对语义，注释在码）；`labelRows` 裁
  top8 + 主行独占 top_scores JSON + 行级 runner-up 取全表序
  （`rows[7].secondLabel == "rank-8"` 断言钉「裁行不裁链」）；load 后重归一
  保 dot==cosine 精确。
- **LabelPrototypeSet.load typed 家族**：revision mismatch（带 expected/actual
  载荷）/ index corrupt 四形态（JSON 坏/count 不齐/重复 label/payload 尺寸）/
  目录缺席——五路全测试钉死，无静默空表路径。
- **AIAnalysisRegistry**：四缺席路径（store/engine/model/prototypes）typed +
  `lastFailureCopy` 可观测（D8 禁假开关）；labeling 缺者先补两遍扫（pass0
  一次 loadScanTable 探在场 → pass1 补嵌 → pass2 单次重载分类，N 缺张不 N 次
  全表装载）；recomputeAll = manifest `embeddingDim` nil 拒绝（E4 同源）+
  单批翻 active + 旧 key 行保留（取消保 partial + 翻档维持，测试双钉）。
- **WorkspaceHostView prototypesProvider**：revision 按激活模型行逐任务校验
  （同生共死契约的运行时执行点）；bundle 缺席 → nil → registry typed
  `prototypesUnavailable`——链路闭合。
- **LabelingAskDialog**：Alcedo SemanticGenerationDialog 交互形（是/否 +
  Remember my choice + 全本地声明文案）；stateless binding 壳（按钮回掷
  accepted/remember，状态全在 controller/preferences 面）；「不分析」为
  cancelAction、默认按钮 = 「分析」。
- **prompt sheet 形态**：`isPresented: Binding(get/set)` + 内容闭包读
  `pendingPrompt`（private(set) 封装不破）；set 腿只走 `dismissPrompt()`
  （中性关断零偏好写）——DECISIONS §10 兑现。

## FINDING

- **observation O-1**：16 个新 UI 键（`tasks_ai_*` 11 +
  `labeling_ask_*` 5）未入 `Localizable.xcstrings`（本波零 xcstrings diff），
  当前以 `defaultValue:` 英文渲染。判定 = **非违约**：M2-10-07 PLAN :19 明文
  承载「本 phase 全部新键 zh/en（zh-audit 口径）」（M2-7-3/M2-8-3/M2-9-05
  同款阶段收口批先例）；功能零影响。登记挂 M2-10-07，届时 `zh-audit --check`
  必须覆盖此 16 键。
- **observation O-2**：DECISIONS §3「diff 机检 17 行纯插入」实为 **18 行纯
  插入**（`git diff --numstat` = 18+/0- 亲跑）——「纯插入」论断成立，计数差
  一；本验收批已勘误（doc-only）。
- **observation O-3**：front-matter `App/Sources/Lightamer/Library/Views/
  ImportModeDialog.swift` 路径多写 `Views/` 段——实际文件在
  `App/Sources/Lightamer/Library/ImportModeDialog.swift`（`Views/` 下并无此
  文件）。文件本体在申报集内、同名无歧义（T2 修改亲证），属计划书路径笔误；
  diff 边界判定不受影响，登记不改 plan 历史件。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | 手算锚 + margin 双侧 + top8 裁度 + revision typed | ✅ LabelEngineTests 12/0/0（正交/同向/反向 + `nextUp` 双侧 + `rows[7]→rank-8` 全表序边界 + corrupt 五路）全套亲跑 |
| 2 | 出厂集落库幂等 + zh/en 对齐 | ✅ `testFactoryCatalogCompleteness`（≥160/唯一性/非空/seedRows 2× 对）+ `testFactorySeedIsIdempotentIntoRealProject`（真 .lalb 双 seed → 173×2 行逐 label zh+en）——落点改 LabelEngineTests 系 3b 并行波保护，DECISIONS §12 申报在案，追认 |
| 3 | registry 三任务型真链 | ✅ AnalysisRegistryTests 13/0/0（嵌入行落库+进度单调采样/串行 maxInFlight==1+FIFO/取消增量+exactly-once/重算翻档保旧维/取消保 partial/缺者先补 [2,3]） |
| 4 | 导入接线三态 | ✅ 真 ImportService 链 ×3 passed 亲点（ask 弹+分析后 6 行/always 直入 6 行/never 仅嵌入 2 行） |
| 5 | remember 写回 + reset | ✅ LabelingDefaultsTests 13/0/0（是+remember→always/否+remember→never/单次零持久化/reset→ask/垃圾值→ask/suite 隔离） |
| 6 | BackgroundTaskHosting 零 diff + 既有栏呈现 | ✅ `git diff` 0 文件亲跑；AI 任务经 `backgroundRegistry.register` 进既有 bar/dialog（完成后 count 归零断言在测） |
| 7 | 资源门：无模型环境 0 fail + skip 可审计 | ✅ 激活态 2797/16/0 零新 skip；真原型 sanity 2.586s 非 skip 亲证；无模型环境三重 XCTSkip 门（资产/原型树/引擎装载）在码可审计 |
| 8 | 登记闭环 + diff 边界 == 申报集 | ✅ Project.swift ×3 + BUNDLE-MAP 三行逐位；20 文件 = front-matter 16 + 申报 3 + 账本 1，零未申报 |

## 翻账

- **REQUIREMENTS `M2AI-03`：翻勾 ✅**（本验收批追记 Delivered 注记）——
  ①出厂中英 label query = LabelQueries 173 标签 × zh/en 单源 + 幂等 seed 入
  `label_query`（可查可审计，真 .lalb 双 seed 测试钉）；②原型余弦打标 =
  pinned-revision 文本塔原型（173×512 fp16，盘上亲验）+ LabelEngine
  score/second_label/margin/confident/top_scores 全字段 + typed 拒绝族；
  ③导入后询问 Remember-my-choice = LabelingAskDialog + `library.ai.labelingMode`
  三态 + 真 ImportService 链测试 ×3。命中质量走查（threshold 0.05 / 单句
  原型上限）挂 M2-10-07 走查——质量观察项，非交付缺口。
- **REQUIREMENTS `M2AI-07`：翻勾 ✅**（本验收批追记 Delivered 注记）——
  ①任务注册表 = AIAnalysisRegistry 三任务型 conformer 挂既有
  BackgroundTaskRegistry（协议零改、栏/对话框零新增呈现面）；②取消 =
  per-task token + 每张检查点 + 增量终态 exactly-once（回归测试在案）；
  ③分析期间可继续工作 = 串行 utility QoS + Task.yield + 解码离主线程
  （maxInFlight==1 机检）。
- **M2AI-02 回退检查**：前波注记「导入管线接线归 M2AI-03 波，若 03 波发现
  缺口可回退翻账」——本波 runImport 成功尾自动嵌入腿已交付且真链测试 ×3
  过，**无缺口，回退不触发**，M2AI-02 翻账维持。
- **GOAL-STATE**：本验收续接点追加。**未 push。**

## 下游交接注记

- M2-10-04（全文 + AI 描述/评片）：WorkspaceHostView 本波 65 行在先，同文件
  冲突 = 后提交方 rebase（plan 风险节预案）；02 产物共享面零触碰已由本验收
  复证。
- M2-10-05（worker 进程）：`AIAnalysisEngining` 协议缝 + `engineProvider`
  闭包单点换处亲读在位；`AIInferenceService.analysisEngine()` 为装配入口。
- M2-10-07（LCR 页）：`LabelingPreferences.reset()` + labelingMode 三态 UI
  挂点 + threshold/命中质量走查 + **O-1 的 16 键 zh 补录**，四处钥匙就绪。
