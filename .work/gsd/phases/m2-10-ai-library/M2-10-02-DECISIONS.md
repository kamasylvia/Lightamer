# M2-10-02 DECISIONS — 执行期裁决与偏离签注

> 状态：执行波 worker 落盘，晨审可推翻。正本 plan = 同目录
> `M2-10-02-PLAN.md`；数字正本 = `perf.md`；spike 承接 = `M2-10-01-SPIKE.md`。

## 1. 检索扫描双面——连续面为生产主 face（KD-4 sketch 形状扩展签注）

KD-4 sketch = `topK(rows: [EmbeddingScanRow], …)`。实现保留该 face（小 N /
测试面），另增 **`topK(rowIDs:contiguousFP16:dim:query:k:)` 连续面** 为生产
主路径：`SemanticStore.loadScanTable` 把整表装进单一平面 fp16 buffer，扫描
块 `vImage_Buffer` 直指 payload（零拷贝）。动机（实测）：逐行 Data 面在
200k 行 Debug 宿主上仅每行 memcpy/桥接即 +25ms 量级（59ms→（换面）31.6ms），
预算哨兵必须量在真实生产形状上。`EmbeddingScanRow` 定义落 `EmbeddingScanner.swift`
（KD-4 sketch 原位；SemanticStore 消费）。

## 2. fp16→fp32 升维 = vImage 块转换（研究稿 vDSP_vconvert 不可行签注）

RESEARCH §5 预估 `vDSP_vconvert` 升维 ~1ms 级——实测该 API **无** UInt16/Float16
→Float 重载（SDK probe：`vDSP.convertElements` 亦无 half 支持）。改用
`vImageConvert_Planar16FtoPlanarF`（256 行多行 buffer 块转换，200k×512 全量
15.4ms，独立 -O 探针）+ `vDSP_dotpr`（vDSP.h 实名，非 sketch 的
`vDSP_dotv`——后者不存在）。分解：转换 15.4ms + 点积 8.0ms ≈ 23.4ms（-O）。

## 3. replaceUnderstanding = 显式 DELETE + INSERT（禁 INSERT OR REPLACE）

外部内容 FTS 的经典陷阱：**INSERT OR REPLACE 的约束解决删除不触发 AFTER
DELETE 触发器**（`recursive_triggers` 默认 OFF）——旧文档词留在索引里、新词
再加进去 = 同一 rowid 双文档静默漂移。语义测试
`testUnderstandingReconcileFlipsActiveAndMirrorsFTS` 首轮实测抓到（MATCH
'beach' 期望 0 实得 1）。修 = 同事务显式 DELETE（普通 DELETE 恒触发）再
INSERT。语义同 KD-2：旧行（同 task）被替换、兄弟 task 行 active=0 留痕。

## 4. 内置 .mlpackage 资产三发现（M5 真模型 sanity 链上实测，全部已修）

1. **`MLModel(contentsOf:)` 拒收未编译 .mlpackage**（"Compile the model
   with Xcode or MLModel.compileModel(at:)"）→ runner 首用
   `MLModel.compileModel(at:)` 编译（img 塔 21.3s），`.mlmodelc` 缓存于
   `~/Library/Caches/Lightamer/compiled-models/`（Caches 类可重建派生物，
   跨启动复用；M2-10-05 worker 接手生命周期）。
2. **`CGImage.cropping(to:)` 对 context-backed CGImage 返 nil**（独立探针
   实证）→ 预缩图改单次 bitmap draw（resize+center-crop 一体，`interpolationQuality = .high`）。
3. **int8 量化塔输出 = FP16 MLMultiArray**：作用域字节接口
   `withUnsafeBytes` 绑定 Float 直接 trap（M5 sanity 运行实测 crash，
   `.ips` 帧 = firstVector 闭包）→ 改逐元素 `doubleValue` 读取（512 元素，
   代价可忽略）。

## 5. 越界增补（四文件，均功能性必需，commit body 已申报）

1. `LightamerCore/Sources/Session/SQLiteHandle.swift`：`bindBlob`/
   `columnBlob`——KD-1 `embedding BLOB` 是库里第一个 BLOB 消费者，包装层
   此前无 blob 面。
2. `App/Sources/Lightamer/Library/LibraryGridModel.swift`：semantic overlay
   （KD-6 引用 :82 但 front-matter 漏列本文件——折叠点只能在 ONE collection
   state 里）。实现 = 既有 keyset 面 500/页全量双段 walk（main + NULL
   tier）→ 命中集内**保序投影**（有序表保序过滤）；`apply(filter:)/apply(sort:)`
   清 overlay（两腿互斥）。
3. `App/Sources/Lightamer/Library/LibraryInspectorModel.swift`：overviewCount
   分支（overlay 在场 = 命中计数进总数卡，KD-6 AC 字面）。
4. `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift` 两 hunk：
   LibrarySearchModel 组装参数（semanticStore + provider）+ 搜索对话框
   dismiss 后 `inspector.refresh()`（EXIF 腿同享，命中计数落卡）。

## 6. golden fixture 的 CI 面 = fixture 内置缩减词表

无模型环境全绿是硬 AC（纪律 6），但 golden id 序列按真实 vocab 索引——
fixture 除 12 句外携带**所用 token 的 [id, token] 清单**，测试以真实 id
重建缩减词表（WordPiece 贪心最长短集⊆全长词表 ⇒ 缩减词表复现同一分词）。
`[PAD]` id 从 mask 尾位反推（不硬编码 0）。fixture 4.9KB（预算 ≤10KB），
revision 与 `ModelAssetCatalog.chineseClipViTB16Int8.revision` 锁定断言。

## 7. label_query 列序：DDL 为准

KD-1 pin 数组初稿把 `lang` 排在 `query_text` 前，与 KD-1 DDL 拼写
（`query_text` 第三列、`lang` 第四列）冲突——列序对照测试当场抓出，**以
DDL 字面为准**修正 pin 数组（`labelQueryColumns`）。

## 8. BUNDLE-MAP 三行陈旧值勘误（本波执行期，对账机检发现）

`func test` 全量对账发现三行行值为更早波次遗留：LibraryStoreTests 11→14、
XMPExportMatrixTests 5→6、LibrarySchemaTests 16→19（本波前实际值；v4 化后
23）。勘误后 LIB 行和 = 503 = 全套实测执行数精确。对账链：2718 + 净 41
（schema +4 + 新四文件 +37）= **2759**（全套 `TOTAL|2759/16/1` 的 1 fail =
在册 SidecarV5 环境型 flake，隔离复跑 11/0/0 → 终账 **2759/16/0**）。

## 9. M5 真模型 sanity 的断言边界（诚实记账）

资源门 ACTIVE（本机有内置资产）：zh「蓝天白云」+ en「a clear blue sky」
双 query 端到端（tokenize → 文本塔 → 全扫）非空、分数字段内（|s| ≤ 1.002）
降序。**不做跨 query 顶位一致断言**——两张 fixture 均为合成梯度（无语义），
两 query 排序不同是正确行为；真图相对序 golden 维持 01 DECISIONS §9 的
open 状态（挂 03 导入管线后有真实照片库时补）。0 新增 skip（模型在场）；
无模型环境该测试 XCTSkip（skip 计数 +1，可审计）。

## 10. jina 768 不截维（planner 钉注兑现位置）

`semantic_model.embedding_dim` 全向量存储（768 原样入列），engine/scanner
全链维度取自模型行——**零截维代码**（Matryoshka 截断策略若未来立项，是
Store 写入侧的新决策点，本 plan 无消费面）。

## 11. Swift 6 编译期签注

MLModel `prediction(from:options:)` 在本 SDK 并发导入为 async——按 `try
await` 消费（语义仍为引擎 actor 内串行前向，M2-10-05 worker 后彻底离线程）；
`MLMultiArray.withUnsafeMutableBytes` 为双参闭包（指针 + strides）。
