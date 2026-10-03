# M2-10-02 SUMMARY — 嵌入存储 + 检索 + 搜索 CLIP tab 真腿

> 执行 worker 收口（2026-10-03 夜）。四个功能提交 + 本收口提交；
> 裁决与偏离正本 = `M2-10-02-DECISIONS.md`；性能数字正本 =
> `perf.md`（§A 三档实测）。

## 提交账

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `882f97a` | LibrarySchema v4 七表 additive（D-M2-10-CONTEXT-2 兑现）+ v3→v4 幂等迁移 slot + fresh 直落 + 全链 v1→v4 测试 + pin 触点三文件 + tokenizer_ref.py/golden fixture（E2） |
| T2 | `2aa4179` | WordPieceTokenizer（BERT 全管线，KD-3/D-8 零 SPM）+ SemanticStore 四域读写（KD-2）+ blob API 增补 + 19 测试 |
| T3 | `4ddb71a` | EmbeddingScanner（D-1 vDSP 暴力精确扫，双面）+ perf.md 三档账本 |
| T4 | `a181890` | SemanticEngine（KD-5 协议缝 + InProcess runner）+ AIInferenceService 装配单点 + CLIP tab 真腿 + SemanticSearchTests 10 法（M5 真模型 sanity 激活态绿） |
| T5 | 本提交 | AC 机检 + 全套终跑对账 + SUMMARY/DECISIONS/GOAL-STATE/LESSONS + BUNDLE-MAP 勘误 |

## 测试数字（基线 2718/16skip/0fail）

- **全套 --all 终跑：`TOTAL|2759/16/1|954s`** ——执行数 = 2718 + **41 精确
  对账**（LibrarySchemaTests 19→23 净 +4【注：MAP 旧行 16 为更早波次陈旧
  值，本波勘误】+ 新四文件 37 = WordPiece 9 / SemanticStore 10 /
  EmbeddingScanner 8 / SemanticSearch 10）。1 fail =
  `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile` =
  **在册环境型 flake**（.lra 缺席形态，M2-9-04 记录的同族两形态之一）；
  隔离复跑 **11/0/0** → 终账 **2759/16/0**。
- 七 bundle 逐值：IOP 467/1/0、IOPParity 362/3/0、Layers 298/3/0、
  **Library 462→503/4/0**（+41 全落此）、Sessions 279/4/0、Export 338/1/0
  （红线门零漂移）、App 512/1/0（flake 复跑后 512/0/0）；skip 16 = 基线
  （**零新增 skip——M5 真模型 sanity 在本机激活态跑绿**；无模型环境该测试
  XCTSkip 可审计）。
- 定向轮：SemanticSearchTests 10/0/0、LibrarySearchModelTests 5/0/0、
  LibraryGridModelTests 16/1/0（基线 skip）、LibraryInspectorModelTests
  11/0/0、SidecarV5Tests 11/0/0（flake 隔离）。
- func test 全仓总数 2761 对执行数 2759 的 −2 = 基线既有偏移（非本波，
  勘误注记在 BUNDLE-MAP）。

## 检索性能实测（perf.md §A 正本）

| rows × dim | median（3 轮） | 判定 |
|---|---|---|
| 10,000 × 512 | **2.47ms** | 记录档 |
| 100,000 × 512 | **15.98ms** | 记录档 |
| **200,000 × 512** | **31.56ms**（31.30/31.95/31.56） | **D-1 硬门 PASS**（≤50ms，余量 1.58×） |

分解探针（独立 -O）：vImage fp16→fp32 块转换 15.4ms + `vDSP_dotpr` 全扫
8.0ms；外推 ~31.6 万行触后手线。查询链全预算：文本塔 5.59ms（01 spike）
+ 满库扫 31.6ms ≈ 38ms < 100ms 目标。

## pin 触点清单（T1 机检，L050 grep 复核）

- `LibrarySchemaTests.swift`：fresh/reopen/idempotent/future(4→5 探针 5)、
  快照代名 `pre-migrate.N-4.bak`、表集合 extras 前缀。
- `LibraryDocumentTests.swift`：:107/:151 `== 4` 化 + :174-180 future 5 化。
- `DefaultLookTests.swift`：快照名 1-4 + `== 4` 两处 + 注释。
- grep 复核：`pre-migrate.|userVersion|futureSchema` 全仓三文件外**零命中**。

## FTS 触发器同步验证记录（AC #7）

`ai_understanding_fts` external-content 三触发器，Store 级测试三腿：
INSERT 后 MATCH 命中（ai）；兄弟 task 翻 active=0 后旧词**仍在索引**
（E5 契约实测：索引无 active 概念，消费方必须 JOIN active=1——契约注释
钉在 `replaceUnderstanding` 与 DDL 侧）；同 task 重写（显式 DELETE+
INSERT，INSERT OR REPLACE 的约束删除不触发触发器——实测抓到并修复）后旧
词消失新词命中；行删除（CASCADE 腿）后 MATCH 清零（ad）。schema 级 CASCADE
测试四域行数归零 + FTS 清零。

## 交付物

- **Schema v4**：七表 + 四索引（`idx_semantic_model_active` 部分唯一 =
  OQ-9-A DB 级单激活；`idx_image_embedding_model` = M10 扫描前缀）+
  `ai_understanding_fts`（caption+tags，unicode61）+ 三触发器；v1→v2→v3
  迁移分支/列 DDL 零 diff（机检：minus 行仅注释与常量）。
- **WordPieceTokenizer**：BasicTokenizer（clean/CJK 字切/小写/NFD 去重音/
  标点切分）+ 贪心 WordPiece（>100 字词 → [UNK]）+ CLS/SEP + pad/truncate
  52 + attention mask；golden 12 句逐位对拍（transformers 4.x 产 fixture，
  **5.x 加载 vocab_file 静默坏——脚本 pin `<5`**）。
- **SemanticStore**：模型注册（单激活批内翻档）/fp16 BLOB 嵌入/整组标签
  reconcile/label_query 幂等 seed/理解 reconcile/append-only 评分；
  `loadScanTable` 单平面装载。
- **EmbeddingScanner**：连续面（零拷贝块扫，生产）+ rows 面（sketch）；
  k-heap partial sort；手算锚/fp16 误差带/typed 错误。
- **SemanticEngine + InProcessMLModelRunner**：查询链 + 图像链
  （`ModelAssetManifest.inputSize` 唯一尺寸源，E4）；AIInferencing 协议缝
  （05 换 worker = 装配单行）。
- **CLIP tab 真腿**：输入段/提交腿/零命中保开提示/模型缺席 typed 错误；
  EXIF 腿与 fulltext marker 零触碰（hunk 机检：minus 全部落在 CLIP 分支/
  头注/disabled 条件/apply 路由）。
- **装配**：`AIInferenceService`（App，fail-closed nil 面）+ WorkspaceHostView
  注入（semanticStore + provider）。

## 越界增补（DECISIONS §5 全量清单）

SQLiteHandle（bindBlob/columnBlob）、LibraryGridModel（semantic overlay）、
LibraryInspectorModel（计数卡分支）、WorkspaceHostView（2 hunk）。计划
front-matter 外源码文件共此四；BUNDLE-MAP/perf.md/收口三件为账本文件。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | v4 迁移四件套 | ✅ LibrarySchemaTests 23/0/0（v3→v4 列序对照/全链 v1→v4/fresh/>4 REFUSE/active 唯一负测/迁移重跑幂等） |
| 2 | CASCADE 四域 | ✅ SemanticStoreTests 行数归零 + FTS 清零 + schema 级同构测试 |
| 3 | tokenizer golden | ✅ WordPieceTokenizerTests 9/0/0（12 句逐位 + 截断/[UNK] 边界） |
| 4 | scanner 正确性 + 预算 | ✅ EmbeddingScannerTests 8/0/0；200k×512 median **31.56ms ≤ 50ms**（3 轮中位） |
| 5 | engine mock 链 + typed 错误 + 诚实空态 | ✅ SemanticSearchTests mock 五法 + 对话框 note/error 映射 |
| 6 | CLIP tab 真腿 + 半径 | ✅ hunk 机检（EXIF 腿/fulltext marker 零 diff）+ 提交腿联动测试 |
| 7 | FTS 触发器同步 | ✅ 写/改/删三腿 MATCH 断言（含 E5 契约留痕腿） |
| 8 | perf.md 三档 | ✅ perf.md §A.1 三档誊录 + A.3 方法学 |
| 9 | 资源门 0 fail | ✅ 2759/16/0（本机门激活态，零新 skip；无模型环境 M5 测试 skip 可审计） |
| 10 | 登记闭环 + diff 边界 | ✅ 四新测试文件 × Project.swift + BUNDLE-MAP 双命中；diff 边界 = front-matter 全量 + DECISIONS §5 申报四件 + 账本文件 |

## 阻塞节

无 E3 阻塞。环境注记：①SidecarV5 flake 一宗（在册，隔离复跑定案）；
②CoreML 首编译 ~50s（img 21.3s + txt，缓存后跨启动直载——DECISIONS §4）。

## 交接（下游 plan）

- **M2-10-03（打标）**：`label_query` 表 + `seedLabelQueries`/`replaceLabels`
  原语就绪；原型嵌入按 01 §8 随资产包（`prototypes/` 占位）；
  `SemanticEngine.embedAndStore` 图像链即导入管线嵌入腿（E4 尺寸走 manifest）。
- **M2-10-04（全文 + AI 描述/评片写面）**：`ai_understanding` 写 =
  `replaceUnderstanding`（DELETE+INSERT reconcile，兄弟行 active=0 留痕）；
  **MATCH 消费必须 JOIN active=1**（E5 契约，注释钉在 schema 与 Store）；
  `ai_rating` append-only + `latestRating`；rating=0 哨兵语义在 DDL 注释。
- **M2-10-05（worker）**：`AIInferencing` 协议缝就绪；切换点 =
  `AIInferenceService.semanticSearcher()` 的 runner 构造行（注释 pin）；
  编译缓存目录语义见 DECISIONS §4。
- **维护者**：golden fixture 重生成 = `Scripts/ai-models/tokenizer_ref.py`
  （**必须 `transformers<5`**——5.x 静默坏 vocab_file）；词表 revision 变更
  时同步 fixture + Catalog pin。
