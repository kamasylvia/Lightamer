# Phase 11 Discussion Log

## 2026-09-26 — discuss（夜间自动；用户睡前授权全自动推进）

- **输入**：ROADMAP §Phase 11（EXP-01..08 + SC#1-5）；REQUIREMENTS EXP 节；Phase 9
  移交清单四条（09-DISCUSSION-LOG 终节）；Phase 8 移交义务（EXP-05 消费点 =
  YiyinExportSettings + 生产联合上下文注入，08-3 T3）；PROJECT.md 依赖红线。
- **产出**：`11-CONTEXT.md`（Phase Boundary + D-11-CONTEXT-1..8 全按推荐自动裁决，
  **〔晨审追认〕** 标注 + 追认清单表）。
- **关键裁决摘要**：AVIF native-only（libavif 不进 v1，新 SPM 仅 libwebp）；队列并发 1
  （内存红线）；recipe v1 不持久化（Phase 12 挂载）；输出 stem+tag+递增后缀恒 Output/；
  EXIF round-trip + XMP packet；EXP-08 脚本路径制（防注入）；量化域按格式惯例；
  无 queue journal（tmp 原子晋升 + 幂等重试替代）。
- **晨审注意**：8 项均为推荐项自动裁决，用户晨间任一推翻 → 回注 planner 重开受影响面
  （推翻代价列在 CONTEXT 追认清单表）。

## 2026-09-26 02:2x — research 审阅（orchestrator）+ OQ-11-1..8 裁决〔晨审追认〕

- **RESEARCH 审阅**：`4d41fcd`（455 行）过关——本机 swift 探针实跑 UTI 清单当场钉死
  D-11-CONTEXT-1（AVIF 在、WebP 缺、libavif 不进 v1）；两处 **API 事实修正接受**
  （①`MTLCommandQueue.priority` 无公开 API → 低优先级落地 = 独立队列 + 并发 1 +
  Utility QoS + `yieldsToEditor` 接口位；②XMP packet 须 `kCGImageDestinationMetadata`
  整体替换模式 + WebP 容器元数据需 WebPMux（Swift-WebP 未暴露）→ v1 文档化例外）。
  均为机制层修正，裁决意图不变，晨审一并追认。
- **OQ 裁决（全按 researcher 推荐/orchestrator 惯例，晨审可推翻）**：
  - OQ-11-1 波次 = **采纳 W1 模型+SPM / W2 编码面 / W3 渲染腿 / W4 队列+UI / W5 收口**
  - OQ-11-2 colorout = **保留 + target 覆写（gamma 必剔）**（唯一真分叉，从 researcher 推荐）
  - OQ-11-3 队列作用域 = **session 级**（出片语义属会话；app 级跨会话 v1 不做）
  - OQ-11-4 失败呈现 = **job 级行内错误 + 队列面板汇总计数**
  - OQ-11-5 WebP 元数据 = **v1 文档化例外（不嵌 XMP）**，Phase 12/14 复审
  - OQ-11-6 sizing 归属 = **ExportVariant 持有 sizing；yiyin variant 复用
    YiyinExportSettings**（正主 D-08-CONTEXT-7）
  - OQ-11-7 post-action = **per-job 触发**
  - OQ-11-8 让位开关 = **v1 无 UI 开关**（固定 Utility QoS + 并发 1），接口位预留
