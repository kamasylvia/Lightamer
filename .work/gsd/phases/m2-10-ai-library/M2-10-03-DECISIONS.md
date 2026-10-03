# M2-10-03 DECISIONS — 执行期裁决与偏离签注

> 状态：执行波 worker 落盘，晨审可推翻。正本 plan = 同目录
> `M2-10-03-PLAN.md`；数字正本 = SUMMARY。

## 1. 出厂集 = 173 标签（plan「~160」的落地值）

KD-1 骨架四类展开后实收 **173**（场景 51 / 人物 14 / 动物 9 / 植物+食物 16 /
车辆+结构 18 / 光线天气时间 22 / 技术氛围 43）。`testFactoryCatalogCompleteness`
钉 ≥160 下限 + 唯一性 + zh/en 非空。zh query = 「一张…的照片」自然句式（中文塔
原生语义），en query = 「a photo of …」句式——原型只嵌 en（KD-1 字面），zh 行
落 `label_query` 可查（D-2 审计面）。

## 2. 目录解析契约：LabelQueries.swift 是唯一真相源，脚本解析不复制

原型生成器（`generate_label_prototypes.py`）**正则解析 Swift 源文件**取
`(label, queryEN)`——零复制清单。防呆两件：①头注模板行故意**不加引号**
（`label: <label>`），解析器永不吃到模板；②解析端过滤含「…」的行（双保险，
首轮实跑抓到模板行混入 label "…" 后修复重生成）。每个 Swift 侧改清单必须重跑
生成器（prototype revision 与模型 revision 同生共死，D-7）。

## 3. 新脚本文件 `generate_label_prototypes.py`（front-matter 外，申报）

E3 只申报了 `build_default_bundle.sh` 的修改。生成阶段实现为**独立脚本**而非
shell 内联 heredoc——mirror `convert_chinese_clip.py` 先例（可独立运行、可维护、
本机可直接重跑产真原型）。shell 侧 = 纯 opt-in 调用（无 flag 时 01 链字节等价，
`zsh -n` + diff 机检 18 行纯插入——2026-10-03 验收批勘误，原记 17）。**已在本机实跑**：173 原型 × 512 维 fp16 =
177,152 bytes 落
`Resources/AIModels/chinese-clip-vitb16-int8/label-prototypes/`（gitignore 覆盖
机检过；revision = Catalog pin `36e679e6…`）。

## 4. 原型目录名 = `label-prototypes/`（KD-1 字面），01 的 `prototypes/` 占位
   目录由 flag 阶段移除

01 占位目录名（`prototypes/`）与 plan KD-1 契约名（`label-prototypes/`）不一致
——**以 plan 字面为准**（加载器唯一认 `label-prototypes/`）。`--with-label-
prototypes` 阶段完成后 `rm -rf` 占位目录（README 自述「M2-10-03 ships the real
prototypes here」，语义即被真实产物取代）；无 flag 链不触碰它。本机现状：真
`label-prototypes/` 已生成，占位 `prototypes/` 暂留（未跑全 flag 链，只直跑了
生成器）——下次全链跑时移除。

## 5. top_scores JSON = 主行独占（入库裁度的 payload 半边）

KD-2 只钉「行 = top 8、top_scores 同源同 8」。执行裁决：JSON **只写主行**
（rows[0].topScoresJSON），rows[1..7] 该列 nil——每行重复同一份 8 条 JSON 是
8× payload 膨胀，无消费面（显示读主行）。行级 runner-up 语义 = **全表序**
（第 8 行的 second_label 指向全表第 9 名——裁度只裁「存储行」，不裁排序链；
`testLabelRowsClampToTopEightWithMainRowJSON` 钉该边界）。晨审若裁「每行都带」
或「runner-up 截断在 8 内」，改 `labelRows` 一处。

## 6. threshold = 0.05 初值维持（KD-2 planner 值）+ 走查观察项

`confidentThreshold = 0.05` 原样落地；inclusive（`margin ≥ threshold`，恰等
计 confident——`testConfidentBoundaryIsInclusiveAtThreshold` 用 `nextUp` 双侧
钉死）。真图命中质量走查挂 M2-10-07（plan 风险节原注）。

## 7. labeling 的 top_scores/confident 依赖 embedding 的「缺者先补」实现为
   两遍扫

KD-3「前置 = 该集 embedding 已在（缺者先补一段嵌入子任务）」实现：pass 0 =
一次 `loadScanTable` 探在场集；pass 1 = 逐缺张过 engine（与导入自动腿同
`embedAndStore`）；pass 2 = **重载一次** scan table 后逐张余弦。不做逐张
reload（N 缺张 = N 次全表装载）。`testLabelingEmbedsMissingFirstThenWrites-
CosineRows` 钉 engine 只吃缺张（[2,3]）。

## 8. 导入接线的边界裁决（runImport 成功尾）

- **new-row 捕获** = 导入前 `MAX(id)` 高水位 + 成功后 `id > 水位`（importOutcome
  不携带 id，ImportService 零触碰——导入链红线）。
- **腿的触发条件** = `imported > 0 && !cancelled`：取消的半截导入不触发 AI 腿
  （plan 字面「成功尾」）；半截行留给重导入/重算幂等覆盖。
- **捕获失败 = 腿静默跳过**（`try?`）：AI 是机会性派生数据，绝不倒灌导入失败
  面；与「typed 不静默」不冲突——那是模型缺席路径（registry 内 typed）。
- **弹询时机** = `importProgress = nil` 发布之后 + 一次 `Task.yield()` 才
  `presentPrompt`（plan 风险节的竞争钉）；ask 意图判定与发布分离
  （`intentForNewImages` 不发布，tail 控制时机）。

## 9. AI 任务进既有聚合面 = WorkspaceHostView 持有的 taskRegistry（申报增量
   文件两件）

BackgroundTaskRegistry 实例是 WorkspaceHostView `@State`（M2-3-1 交付）。本波
**未动所有权**：registry 与 prompt 面在 host 内构造（`.task` 一次性绑定注入
controller），sheet 挂 host（与既有 5 sheet 同级）。**申报增量**：
- `WorkspaceHostView.swift`（65 行：@State ×2 + 绑定块 + prompt sheet）——
  M2-10-02 已有同文件增量先例；与 M2-10-04 并行波若同文件冲突，后提交方 rebase
  （plan 风险节预案）。
- `AIInferenceService.swift`（18 行：缓存改 concrete `SemanticEngine?` +
  `analysisEngine()` 访问器——同一 memoized 装配的两个 typed 视图；行为零变，
  `semanticSearcher()` 字节语义等价）。
`generate_label_prototypes.py` 申报见 §3。其余 diff 边界 == front-matter 全量
（机检：`git diff 321383b..HEAD --stat` 16 文件全列）。

## 10. prompt sheet 用 isPresented + 内容读，不用 sheet(item:)

`pendingPrompt` 是 `private(set)`（状态只经 controller 面变更）→
`sheet(item:)` 的可写 Binding 不可得。改 `isPresented: Binding(get/set)` +
内容闭包读 `pendingPrompt`——set 腿只走 `dismissPrompt()`（中性关断，不写
偏好）。语义等价且封装不破。

## 11. 取消终态的 exactly-once（首轮测试抓到并修复）

`userRequestedCancel` 对**在队（含运行中）任务**直接出队+finish+fire；drain 执
行完若发现任务已不在队 → 跳过 fire（否则双 fire，首轮
`testCancelMidTaskKeepsCompletedRowsOnly` 抓到）。终态语义：cancelled=true 恰
一次；行集增量保留。

## 12. 02 产物共享面零触碰（3a/3b 并行波保护）

`git diff 321383b..HEAD` 机检：SemanticStore / SemanticEngine / EmbeddingScanner /
WordPieceTokenizer / LibrarySchema / SemanticStoreTests **零文件**。Registry 的
存储消费全走 02 公有面（`loadScanTable` / `replaceLabels` / `upsertEmbedding` /
`activeModel`）；逐行 fp16 解码在 App 侧用 `FP16Coding`（public）切片——**未给
SemanticStore 加 per-row 读 face**（front-matter 外文件零增长）。AC#2 的
「SemanticStoreTests 增补」改落 `LabelEngineTests.testFactorySeedIsIdempotent-
IntoRealProject`（真 .lalb 幂等 seed + zh/en 对齐同覆盖面；02 测试文件不动，
3b 波安全）。

## 13. 测试数字账

LabelEngineTests 12（LIB 实跑 12/0/0，资源门 ACTIVE——真原型 sanity 非 skip）；
AnalysisRegistryTests 13 + LabelingDefaultsTests 13（APP 实跑 13/0/0 ×2）。
基线 2759 + 38 = **2797 预期**（全套 --all 终账见 SUMMARY）。BUNDLE-MAP 三行
12/13/13 与文件 `func test` 计数逐位一致。
