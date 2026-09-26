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

## 2026-09-26 — 签核终节（11-05；SC#1-5 证据指针 + Phase 12 移交清单 + 遗留对表）

> 正本 = `11-VALIDATION.md` 对照表（三列证据逐条）。本节只留指针 + 移交 + 遗留。

### SC#1-5 证据指针

| SC | 判定 | 一手证据锚 | 测试锚 | GUI 实证锚 |
|---|---|---|---|---|
| SC#1 六格式导出 | ✅ | `Export/` 编码面四件（ExportEncoder/ImageIOEncoders/WebPEncoder/ExportQuantizer） | `ExportEncoderGoldenTests` 17 + `WebPEncoderTests` 5 + `ExportQuantizerTests` 12 + `ExportPhaseE2ETests` ①探针终判（R1/R5） | 11-04 走查 #5/#6c/#11 |
| SC#2 队列后台+不阻塞编辑 | ✅ | `ExportQueue` actor + `exportCommandQueue` + TaskLocal 路由；**priority API 事实修正（checker M3，RESEARCH §4.4）→ 独立队列+并发 1+Utility QoS+yieldsToEditor 位** | `ExportQueueTests` 13（并发=1 探针 ⑦）+ `ExportPipeTests` 队列身份 3 | 11-04 走查 #10/#12/#14(D8) |
| SC#3 多规格同导 | ✅ | `enqueue` N×M + `resolvedOutputTags` + `ExportNamer` | `ExportPhaseE2ETests` ①②（8 变体单动作 + `-1` 不互覆）+ `ExportQueueTests` ⑥ + `ExportNamerTests` 16 | 11-04 走查 #5/#6/#15(D8) |
| SC#4 yiyin 终步 + 五色域 ICC | ✅ | `ExportYiyinInjector` 缝 + 生产注入器 + `ExportColorSpaceMapper` | `ExportRendererE2ETests` yiyin 段 7 + `ExportPhaseE2ETests` ③ + `ExportPipeTests` 色域已知点 | 11-04 走查 #5 + 08-3 T5 ΔR（共享配置） |
| SC#5 post-actions + Output/ 落盘 | ✅ | `PostExportActions` + completion hook + `SessionLayout.outputDirectory` | 注入面自查（$() 逐字进 $1 + 哨兵未创建）+ `ExportQueueTests` settle 语义 | 11-04 走查 #11-13（脚本实跑 + Finder reveal 截图） |

### Phase 12 移交清单（五条）

1. **`ExportRecipe`/`ExportVariant` Codable 直挂预设存储**（PRES 面，D-11-CONTEXT-3
   升级路径）：类型面已 Codable + 零哈希字段（L013）；挂载 = Phase 12 把 recipe 内存态
   接 preset 存储即可，面板内联编辑面不变；`ExportState.defaultVariant` 是预设默认值
   的现成形态。
2. **WebP mux 元数据复审位**（OQ-11-5，Phase 12/14）：v1 = 无内嵌元数据文档化例外 +
   RIFF 结构锚（`WebPEncoderTests`，mux 面露头或宿主获 WebP 写即红触发重审）；Phase 12
   评分/关键词若要求 WebP 载体，需引 WebPMux 或换宿主面——复审输入在 11-02 D8。
3. **XMP rating/flag 字段面 API 位**（Phase 12 META 评分/标签同步消费，D-11-CONTEXT-5
   预留）：宿主 XMP packet 全格式不序列化（11-02 D3 三途径字节级验证）→ rating/flag
   v1 挂空；Phase 12 裁：自写 XMP mux / 第三方 / 放弃内嵌。Editor signature 唯一活载体
   = TIFF Software tag；EXIF 走 properties dict（五格式全通，Phase 12 评分写回同路）。
4. **`yieldsToEditor` 接口位 + perf 清算位**（Phase 15）：契约常量在 `ExportQueueContract`
   （v1 不实现）；Phase 15 若实测导出 GPU 争抢编辑帧率 → 「编辑活跃让位」泵停
   （9-3 可见优先的反向应用）+ 11-04 D15 mask-fence 收编评估一并裁；perf 输入 =
   `.work/11/perf.md`（分段/内存外推 8GB/WebP 瓶颈/blur 腿 164s 杠杆）。
5. **EXIF/IPTC/XMP 读写面与 META-03 汇合点 + 遗留对表**（见下）：导出面 EXIF =
   properties dict 写入（`kCGImagePropertyExifDictionary`，DateTimeOriginal+LensModel
   实测 round-trip）；Phase 12 评分/日期/关键词写回应复用同路并同批定 XMP 裁决（第 3 条）。

### 遗留对表（各 plan SUMMARY 遗留节合并；零静默）

| # | 遗留 | 来源 | 处置 |
|---|---|---|---|
| 1 | ~~11-03 yiyin 4 态 flaky（byte-exact 断言过敏）~~ | 11-04 | **11-05 已闭环**：像素容差 + sanity 错位红断言（`9439b59`），三轮绿 + 终轮 0 fail |
| 2 | ~~F-11-04-1 /tmp symlink targets + canExport 不一致~~ | 11-04 | **11-05 已闭环**：realpath 双拼写匹配 + gate 一致化（`d9dfa9b`，4 tests） |
| 3 | ~~convertTexture L029 镜像（休眠缺陷）~~ | 11-02/11-03 | **11-05 已闭环**：`.downMirrored` + 双腿 parity 测试（`8700b61`，17/17） |
| 4 | AVIF 12-bit 宿主封顶 10-bit | 11-02 D4 | 文档化降级 + conformer 缝；需求出现时经 `AVIFEncoder` 替换位引 libavif |
| 5 | XMP packet/rating/flag 不序列化 | 11-02 D3 | 文档化限制 + 反向锚；Phase 12/14 复审（= 移交第 3 条） |
| 6 | WebP 无 mux 元数据面 | 11-02 D8 | v1 例外 + RIFF 结构锚；Phase 12/14 复审（= 移交第 2 条） |
| 7 | adobeRGB/proPhoto × 32f 无线性 ICC 变体（typed throw） | 11-02 D2 | Phase 13 如需宽域线性 32f 自备 ICC 数据 |
| 8 | mask-fence 未收编导出队列（4 处 seam） | 11-04 D15 | 正确性无碍；Phase 15 与 yieldsToEditor 一并评估 |
| 9 | recipe 不持久化（session 生命周期） | D-11-CONTEXT-3 | Phase 12 PRES 挂载（= 移交第 1 条） |
| 10 | queue journal（重启丢队列） | D-11-CONTEXT-8 | defer v2（幂等重试 + tmp 原子晋升替代） |
| 11 | 导出分段 Release 计量 / 100MP 平面复用 / WebP 吞吐 / 真实 RAW 解码 | 11-05 perf.md | Phase 15 清算（注记七行） |
| 12 | 编辑并发观感 / 真机 100MP 导出观感 | 11-05 | Manual-Only 4 行（VALIDATION 表），verify-work/Phase 15 |
| 13 | blur 腿 21-pass 固有算力（Release 实测 ≈164s@2560） | 11-05 perf.md §5 | 08-3 遗留 #5 关闭（复测在账）；优化杠杆 = pass 数/downsample，Phase 15 |
| 14 | Release 直启计量需 PackageFrameworks 入 DYLD 路径 + Lightamer Dev 重签 | 11-05 | 记录在 perf.md §5/DECISIONS，Phase 15 Release 计量复用 |

### 签核判定

**Phase 11 签核：PASS（SC#1-5 ✅；status: validated + nyquist_compliant: true；
终轮 1258/6skip/0fail；11-04 收尾唯一 fail 已稳定化闭环）。** 终验走 verify-work；
Manual-Only 4 行挂人工不阻塞（自动化腿均已钉数值与语义）。
