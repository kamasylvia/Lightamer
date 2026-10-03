# M2-10-02 ACCEPTANCE — 嵌入存储 + 检索 + 搜索 CLIP tab 真腿

> 验收 subagent（零共享上下文，实测核验不轻信）。验收对象 = 五提交
> `882f97a` / `2aa4179` / `4ddb71a` / `a181890` / `ed1880d`（HEAD `ed1880d`，
> 未 push）。正本输入 = PLAN（含 checker 回注 E2/E4/E5/M 级）+ SUMMARY +
> DECISIONS + perf.md。验收日期 2026-10-03。

## 结论

**PASS / 0 error + 1 minor(已修，验收批) + 2 observation** —— AC 10/10 全过；
越界四件**全部追认采纳**；全套独立复跑单轮干净绿
`TOTAL|2759/16/0|926s EXIT=0`（SidecarV5 flake 本轮未复现，隔离口径未启用）；
FTS 双文档缺陷修复与回归揭穿力亲证；M5 真模型 sanity 激活态跑绿亲证。

## 全套独立复跑（对账 2759/16/0）

`caffeinate -dis xcodebuild build-for-testing`（workspace/scheme 标准命令，
DerivedData 容器 `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`，HEAD `ed1880d`）→
`caffeinate -dis Scripts/test-direct.sh --all`：

| bundle | 本轮 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 467/1/0（peak 6492MB） | 467/1/0 | 零漂移 |
| IOPParity | 362/3/0（5999MB） | 362/3/0 | 零漂移 |
| Layers | 298/3/0（1050MB） | 298/3/0 | 零漂移 |
| Library | **503/4/0**（990MB） | 503/4/0（462→503，+41 全落此） | 零漂移 |
| Sessions | 279/4/0（1615MB） | 279/4/0 | 零漂移 |
| Export | 338/1/0（5384MB） | 338/1/0 | 零漂移（红线门） |
| App | 512/0/0（1341MB） | 512/0/0（隔离复跑账） | 零漂移，**一轮过** |
| **TOTAL** | **2759/16/0，926s，EXIT=0** | 2759/16/0 | **精确对账** |

- 对账：2718（M2-10-01 验收基线）+ **41 精确** = schema 测试 19→23（+4）+
  新四文件 37（WordPiece 9 / SemanticStore 10 / EmbeddingScanner 8 /
  SemanticSearch 10）；各类 passed 行数 − Test Suite 行亲点 =
  23/9/10/8/10 与 BUNDLE-MAP 行值逐一相符 ✓。
- **SidecarV5 flake 本轮未复现**（App 512/0/0 单轮干净）——执行批隔离复跑
  口径无需启用，终账 2759/16/0 由本轮直接亲证。
- **M5 真模型 sanity 激活态跑绿亲证**：
  `testRealModelEndToEndZhAndEnQueries` passed（2.373s，非 skip）——zh
  「蓝天白云」+ en 「a clear blue sky」双 query 端到端（tokenize → 文本塔 →
  真扫真库）；skip 16 = 基线零新增。
- 零 MEMFAIL：最大 IOP 6492MB < 8192 门。

## 检索性能独立复测（perf.md 对账）

本轮全套内 `EmbeddingScannerTests` 亲跑读数（测试内 `PERF|` 打印提取）：

| rows × dim | 本轮 median | perf.md 申报 | 判定 |
|---|---|---|---|
| 200,000 × 512 | **32.05ms**（30.47/32.05/33.34） | 31.56ms | 方差内，**≤50ms 硬门 PASS** |
| 100,000 × 512 | **15.98ms**（15.74/15.98/16.42） | 15.98ms | **逐位重合** ✓ |
| 10,000 × 512 | 2.59ms | 2.47ms | 方差内 |
| 10,000 逐行面 | 3.54ms | 3.44ms | 方差内（连续/逐行开销差形态一致） |

两宿主轮次互证：连续/生产面与 sketch 面同源成立（sketch `topK(rows:)`
委托连续面，读码亲证 EmbeddingScanner.swift:134-158）；哨兵测试
`testScanBudget200KRowsWithinP50Of50ms` 超线即 fail + 「禁静默调宽」文案在
断言消息里（读码亲证 :274-277）。

## 逐 commit 边界（纪律 8）

| commit | 文件集 | 判定 |
|---|---|---|
| T1 `882f97a` | LibrarySchema + 3 pin 测试 + SchemaTests + tokenizer_ref.py + golden fixture + Project.swift | == 申报 |
| T2 `2aa4179` | WordPieceTokenizer + SemanticStore + 双测试 + SQLiteHandle（越界①，body 申报）+ Project.swift + BUNDLE-MAP 2 行 | == 申报 |
| T3 `4ddb71a` | EmbeddingScanner + ScannerTests + SemanticStore（loadScanTable 面）+ perf.md + Project.swift + BUNDLE-MAP 1 行 | == 申报 |
| T4 `a181890` | SemanticEngine + AIInferenceService + LibrarySearchModel + GlobalSearchDialog + 三越界文件（②③④，body 申报）+ SemanticSearchTests + Project.swift + BUNDLE-MAP 1 行 | == 申报 |
| T5 `ed1880d` | SUMMARY/DECISIONS/GOAL-STATE/LESSONS + BUNDLE-MAP 勘误 13 行 | == 申报 |

五提交合计 diff = 28 文件 = **front-matter files_modified 23 + 越界申报 4 +
BUNDLE-MAP 账本 1**，零未申报文件（亲跑 `git diff --stat b7b918d..HEAD`
逐行核对）。工作区滞留 = gui-acceptance 截图/.build/ 等既有非本批物，
未触碰。

## 越界四件判定（申报待追认 → 逐件裁定）

| # | 文件 | 判定 | 依据 |
|---|---|---|---|
| ① | SQLiteHandle `bindBlob`/`columnBlob`（+26 行） | **采纳** | KD-1 `embedding BLOB` 是全库首个 BLOB 消费者，包装层确无 blob 面（`git show` 亲证仅两方法 + TRANSIENT 语义与 text 面同构）；无它则 v4 嵌入域完全不可读写——schema 面必要最小，非夹带 |
| ② | LibraryGridModel semantic overlay（+59 行） | **采纳** | KD-6 计划文本自引「`LibraryGridModel.apply(filter:)`（:82 实名）」为折叠点——planner front-matter 漏列本文件属计划书起草缺口，非执行越权；实现零新 SQL（复用 searchPage/searchNullTail 既有 keyset 面 500/页双段 walk → 命中集保序投影），`apply(filter:)/apply(sort:)` 清 overlay 两腿互斥（diff 亲读）；DECISIONS §5.2 申报在案 |
| ③ | LibraryInspectorModel 计数卡（+8 行） | **采纳** | KD-6 AC 字面「命中计数进既有总数卡」——总数卡宿主即 InspectorModel overviewCount；overlay 在场取命中数、缺席走原查询，最小分支（diff 亲读） |
| ④ | WorkspaceHostView 2 hunk（+15 行） | **采纳** | hunk1 = LibrarySearchModel 组装参数（semanticStore + provider——T4 装配必然触点，init 新参数无默认不可免）；hunk2 = dismiss 后 `inspector.refresh()`（EXIF 腿同享，KD-6 计数落卡的呈现侧闭环）；两 hunk 均功能性必需（diff 亲读） |

四件均在对应 commit body 申报 + DECISIONS §5 全量清单，**追认成立，零驳回**。

## 机检亲跑记录

1. **schema v4 三腿真实性**：`migrate(from:to:)` 单 `BEGIN IMMEDIATE` 内三个
   range 条件腿（`from<=1&&to>=2` / `from<=2&&to>=3` / `from<=3&&to>=4`，
   LibrarySchema.swift:756-777 亲读）——v1-born 一次调用逐腿命中 1→2→3→4；
   ProjectFileStore **零 diff**（`git diff b7b918d..HEAD` 空）+ 单 dispatch
   亲证（:120 `dispatchSchema(on:)`）。测试面三出生形态全覆盖：v1-born
   （`testFullChainV1ToV4MigrationRotatesSnapshots` gen1）+ v2-born（同测试
   rewind-to-2 gen2 旋转快照重生）+ v3-born（`testV3ToV4…` 真链 open）；逐腿
   产物断言齐（default_look_pending / version_ref / 语义七表 + 列序 pin）。
   M2-8 E2 死锁教训（快照旋转不 refusal）测试在案亲读。
2. **pin 触点**：`== 3`/futureSchema 全仓 grep——三 pin 文件外源码/测试零
   pin 命中（LibraryError/LibrarySchema/ProjectFileStore 三源文件为机制本体
   非 pin 触点）；`triggerNames` 追加三 understanding 触发器名 + `indexNames`
   四索引齐（亲读 :630-639）；`reservedTableNames` 三名原样（:646-648），
   语义七表非预留成员无翻面负测需求。
3. **FTS 双文档缺陷（L059）**：`replaceUnderstanding` 显式 DELETE+INSERT 同
   事务（SemanticStore.swift:435-467 亲读）+ 机制注释（OR REPLACE 的约束
   删除不触发 AFTER DELETE 触发器，recursive_triggers 默认 OFF）；回归测试
   `testUnderstandingReconcileFlipsActiveAndMirrorsFTS` 的
   `assertMatch("beach", expected: 0)`（:258）正是原缺陷揭穿点——旧实现下
   旧词残留索引必得 1；E5 契约腿 `assertMatch("retriever", expected: 1)`
   （:241，兄弟行 active=0 仍入索引）实测钉住。
4. **E5 MATCH JOIN active=1 契约钉**：三处在案——SemanticStore.swift 文件头
   `CHECKER E5 CONTRACT`（:25-29）+ `replaceUnderstanding` doc（:430-434）+
   LibrarySchema.swift（:570-571 understanding DDL 旁）；测试面
   `assertMatch("retriever", 1)` 留痕。M2-10-04 消费方契约传递完整。
5. **触发器 DDL**：三触发器与 images_fts :311-352 先例同构（external-content
   `'delete'` 命令形，亲读 :584-612）；fresh 直落 + 迁移 slot 双路径同 DDL。
6. **tokenizer**：BERT 全管线逐段亲读（clean/CJK 码位段字切/小写+NFD 去重音/
   标点切分 P* 类/贪心 WordPiece/100 字 [UNK]/CLS-SEP/pad-truncate 52 +
   mask）；golden 12 句 revision 锁定断言对 Catalog 真 pin
   （`chineseClipViTB16Int8.revision`）；缩减词表CI 面论证成立（缩减集 ⊆
   全长词表 ⇒ 贪心等价，归纳可证）；fixture 4,926B ≤10KB；
   `tokenizer_ref.py` 带 `transformers<5` pin 与防呆头注。
7. **M5 sanity 链**：资源门双层 XCTSkip（资产缺席/装载失败，可审计）；激活
   行 upsert 真档 → 两 fixture 图真 `embedAndStore`（图像塔真前向）→ 双
   query 端到端非空 + 降序 + |s|≤1.002 归一带断言；DECISIONS §9 诚实记账
   （合成梯度无语义断言边界）与实现一致。
8. **CLIP tab 半径机检**：GlobalSearchDialog diff minus 逐行核对全部落在
   头注/`case .clip` 分支/`.disabled` 条件（`!= .exif` → `== .fullText`，
   EXIF 行为不变）/`apply()` 路由——EXIF 腿分支与 fulltext marker 零触碰
   ✓；`testExifAndSemanticLegsAreExclusive` 钉 fulltext 恒拒绝。
9. **编译缓存实证**：`~/Library/Caches/Lightamer/compiled-models/` 盘上
   img/txt `.mlmodelc` 在场（Oct 3 16:16 首编译产物）——DECISIONS §4① 跨
   启动复用物理在证；L060 三修复（compileModel/cropping nil→bitmap draw/
   FP16 multiArray→逐元素 doubleValue）代码在位（SemanticEngine.swift
   :154-156/:154-179/:363-379 亲读）。
10. **登记闭环**：四新测试文件 Project.swift :536-544 + golden fixture
    :555 双命中；Core/App 源文件走目录 glob 免单列（:125/:188 面）；M5
    sanity 消费的 `sample-gradient.jpg/png` fixture 既有在bundle。
11. **BUNDLE-MAP 勘误三行**：LibraryStoreTests 14 / XMPExportMatrixTests 6 /
    LibrarySchemaTests 23 亲读在位；LIB 行和 = 503 = Library bundle 执行数
    精确；SUMMARY「func test 全仓 2761」口径亲跑 grep 复算 = **2761 精确** ✓。

## 重点读码抽查

- **SemanticEngine**：查询链与 KD-5 逐条对上（trim 空守卫/activeModel 缺席
  typed `.modelUnavailable`/dim 校验/loadScanTable → topK）；图像链 E4 尺寸
  唯一源 = `ModelAssetManifest.inputSize`（零字面 224——`preScaledJPEG(edge:)`
  参数化，调用点只传 manifest 值）；预缩图 = resize+center-crop 单次 bitmap
  draw（embedding 专用重采样，注释钉「never the thumbnail cache」）。
- **InProcessMLModelRunner**：`.mlpackage` 首用 compileModel + `.mlmodelc`
  缓存命中直载 + 缓存写失败降级可用模型（fail-open 恰当）；文本塔 4D mask
  kv 轴广播图内 `>0.5` 契约（01 §8）逐行实现；int8 塔 FP16 输出逐元素
  `doubleValue` 读取（L060③）；CLIP mean/std 归一化调用侧（图外）与 01
  转换契约一致。
- **AIInferenceService**：装配单点 + 双向 memoize + fail-closed nil 面 +
  M2-10-05 worker 切换行注释 pin（:59）；文本孪生塔名从 `-img.` 派生
  `-txt.`（bundle 命名约定注释在案）。
- **LibrarySearchModel**：mode 三路 submit（exif/clip/fullText 占位恒拒）；
  空输入清腿（EXIF 空计划对称）；typed `.modelUnavailable`/`.semanticQueryFailed`
  两族映射诚实空态；`semanticHitLimit = 256`（D-1 topK 预算同源）。
- **LibraryGridModel overlay**：双段全量 walk 用既有分页面零新 SQL；`rows`
  保序投影 + 选中集过滤 + `isExhausted=true` 有界集语义（分页器后续 walk
  no-op）——有序表保序过滤契约成立。
- **EmbeddingScanner MinHeap**：块级 floor 剪枝用块首快照为保守正确（堆满
  后 `maybeInsert` 自身再校验，无漏判）；`sortedDescending` 契约 = 分数降序。

## FINDING

- **minor M-1（已修，验收批 `fix(M2-10-02)`）**：
  `SemanticSearchTests.swift:335-336` 连续两行完全相同的注释
  （「zh + en queries, each end-to-end…」重复）——纯注释零行为，删一行；
  本轮全套 2759/16/0 对该修复仍然有效（注释不参与执行）。
- **observation O-1**：200k 预算口径 = **median(P50, 3 轮)** 非 plan 字面
  「p95」——plan 文本自相矛盾（「p95 ≤ 50ms（3 次中位）」：3 样本中位即
  P50；checker M1 注记也是把 plan 从 p50 改口 p95，执行方按「3 次中位」
  实现并在 perf.md 如实标注 median 口径）。统计学上 median 较 p95 宽松，
  但本轮 max=33.34ms 亦远低于 50ms 门（余量 1.5×），**两口径判定一致，不改
  变任何结论**；perf.md 口径标注诚实，仅记录在案（后续若贴线再议口径）。
- **observation O-2**：BUNDLE-MAP 分 bundle 行值总和（2744）与 `grep "func
  test"` 全仓计数（2761）为两种既有口径（MAP 行值登记存在历史漂移已勘误
  三行；grep 口径含未执行 helper 形态）——对账正本 = 执行数（2759/16/0，
  本轮亲证），SUMMARY 注记的「−2 基线既有偏移」指 grep 口径，非缺陷。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | v4 迁移：v3→v4 列序对照 + 链式 v1→v4 + fresh 直落 + >4 REFUSE + active 唯一负测 | ✅ LibrarySchemaTests 23/0/0 全套亲证（三出生形态 + 快照旋转 + 迁移重跑幂等） |
| 2 | CASCADE 四域 | ✅ `testImageDeleteCascadesAllFourDomains` + schema 级 `testSemanticTablesCascadeWithImageRow` 绿 |
| 3 | tokenizer golden 12 句逐位 + 截断/[UNK] 边界 | ✅ WordPieceTokenizerTests 9/0/0（revision 锁定 + 缩减词表 CI 面 + >100 字/100 字边界） |
| 4 | scanner 正确性 + fp16 误差带 + top-N 序 + 200k 预算 | ✅ EmbeddingScannerTests 8/0/0；本轮 median 32.05ms ≤ 50ms（手算锚/误差带/朴素参考序对拍亲读） |
| 5 | engine mock 链 + typed error + 诚实空态 | ✅ SemanticSearchTests mock 五法 + `.modelUnavailable` 映射亲证（fail-closed nil provider 亦覆盖） |
| 6 | CLIP tab 真腿 + 半径 | ✅ hunk 机检（EXIF/fulltext 零触碰）+ 提交腿联动/空命中保开/ exclusivity 测试绿 |
| 7 | FTS 触发器同步 | ✅ 写/改（DELETE+INSERT）/删三腿 MATCH 断言 + E5 留痕腿（缺陷揭穿力亲证） |
| 8 | perf.md 三档誊录 | ✅ 三档 + 分解探针 + 方法学在案；100k 档本轮亲跑逐位重合 |
| 9 | 资源门：无模型环境 0 fail + skip 可审计 | ✅ 本机激活态 2759/16/0 零新 skip；双层 XCTSkip 门亲读；M5 激活态跑绿亲证 |
| 10 | 登记闭环 + diff 边界 | ✅ 四测试文件 + fixture 双命中；28 文件 = front-matter 23 + 越界 4 + 账本 1，零未申报 |

## 翻账

- **REQUIREMENTS `M2AI-02`：翻勾 ✅**（本验收批追记 Delivered 注记）——
  ①嵌入存储 = schema v4 七表 + SemanticStore 四域原语（fp16 BLOB/CASCADE/
  单激活不变量 DB 级强制）；②检索 = D-1 裁决兑现（vDSP 暴力精确全扫为基线
  ——「SQLite 向量方案执行时定」条款按 M2-10-CONTEXT D-1 用户裁决闭合，
  ANN/sqlite-vec 为 ≥20 万行或 >50ms 后手；本轮实测 200k×512 median
  32.05ms 硬门 PASS）；③自然语言搜索入全局搜索 = CLIP tab 真腿（EXIF 腿
  同型集合过滤 + typed error 诚实空态 + 真模型 zh/en sanity 绿）。嵌入生产
  写面（`embedAndStore`）亦在本 plan 交付并真模型验证——导入管线接线归
  M2AI-03 波（M2-10-03）；若 03 波发现本条缺口可回退翻账（注记在案）。
- **REQUIREMENTS `M2AI-01`：检索/推理消费半边追记**（维持未勾）——嵌入存储
  +检索+CLIP 搜索消费面已 Delivered（本条），打标/评片/描述/凭据/worker
  消费面仍归 M2AI-03/04/06/07。
- **GOAL-STATE**：本验收续接点追加。**未 push。**
