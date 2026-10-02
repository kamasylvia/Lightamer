# M2-10: AI 图库功能 — Context（起草稿）

> 起草：discuss/research subagent（2026-10-02）。**C 档第 1 停**：本文为草案，
> Open Questions 交用户裁决后才进 plan。两参考仓（Lumen RAW MIT / Alcedo GPL-3.0）
> 全程只读，代码不复制入库。源码实测与成本核算细节见同目录 `RESEARCH-NOTES.md`。

## Phase Boundary

**做**（REQUIREMENTS AI2 全族 M2AI-01..10）：

1. **M2AI-01 本地 CLIP 嵌入**——CoreML 档模型可选、本地不上云；混合获取策略
   （默认模型内置 / 大档走本仓 GitHub Release 版本锁死 / HF-hf-mirror 兜底）。
   **本 phase research 的核心翻转点：MobileCLIP2 权重许可 = `apple-amlr`（非 MIT）**，
   默认内置模型选型重开——见 OQ-1。
2. **M2AI-02 嵌入存储 + 检索**——`LibrarySchema` v4 additive 迁移（嵌入表 + 打标表 +
   AI 注记表），自然语言搜索接 M2-3 `GlobalSearchDialog` CLIP tab（占位 marker 已在册）。
3. **M2AI-03 自动打标**——出厂中英 label query 原型余弦（score/second_label/margin/confident）
   + 导入询问 Remember-my-choice。
4. **M2AI-04 AI 评片**——OpenAI/Anthropic 兼容 endpoint、1-5 星+理由（clamp；
   rating=0 reasons-only 哨兵）、星级写库、严格度+输出语言设置。
5. **M2AI-05 AI 描述**——caption+tags+scene+confidence + FTS5 全文检索文档。
6. **M2AI-06 凭据与安全**——Keychain 存 key（读出缓冲 zeroize）+ 强制 HTTPS
   （localhost dev 例外）+ prompt profile 护栏（prompt_profile_id 哈希随结果落库，rubric 变更可检）。
7. **M2AI-07 后台执行**——任务注册表 + 取消；分析期间可继续工作。
8. **M2AI-08 MCP server 保留互补**——Phase 14 资产照旧（launcher + 外部 client 双入口）；
   本 phase **不加**新语义工具（defer 记录，见 OQ-12）。
9. **M2AI-09 AI 出片入工作流**——超分/降噪在独立预览对话框执行，结果作为新可编辑副本
   插入项目（胶片条/网格可见、可继续调整），原图零触碰（Lumen「editable copy」UX）。
10. **M2AI-10 推理进程隔离 crash-safe**——本地推理（01..05/09 共用）跑独立 worker 进程；
    推理崩溃编辑器不死、任务重试/设备降级（ANE↔GPU↔CPU）、记住失败设备组合（Lumen crash-safe 范式）。

**不做**（本 phase 边界外）：

- AI 蒙版数据面（MiDaS 深度 → IOP-MASK-07 解锁）——LUMEN-RAW-NOTES 候选 1 已采纳但归 M2-7 后续，不入本 phase。
- Mertens HDR / 全景合成——IOP-HDR-06 / IOP-PANO-01，v2 合成族，不入本 phase。
- 16-bit linear DNG 导出——用户已裁不采纳（LUMEN-RAW-NOTES 裁决节）。
- M2-9 导出选项任何改动（两 phase 零裁决交集，交汇记录见下）。
- darktable 侧 AI（dt 无此面，无对标）；Alcedo 的 codex-OAuth / gemini / ark 等
  provider 模板全家桶（抽象度收窄见 OQ-7）。

**既有裁决延续（不重开）**：

- 检索基线 = **嵌入独立表 + vDSP 暴力精确扫描 + sqlite-vec 后手**（M2-2/M2-10 D3 裁决，
  本 phase research 复核数字成立，见 RESEARCH-NOTES §5）。
- 模型获取混合策略五件套（2026-09-27 用户批准）；默认模型须中文文本塔可用。
- macOS 27 地板（ANE/MLComputeUnits API 无版本分叉负担）；依赖最小化（MCP swift-sdk
  与 Swift-WebP 之外本 phase 零新增 SPM 依赖——CLIP 推理走 CoreML + MLModel 原生，
  tokenization 自实现或随模型资产携带，不引 swift-transformers，见 D-8）。

## 与 M2-9 的交汇记录（只记录，不互相裁决）

- M2-9-CONTEXT OQ-3「默认导出落点」若裁 Sessions 常量退役 → M2AI-09 副本落点
  （项目 `Media/`）不受影响（副本走项目导入链，非 Export 管线）；M2-9 裁决若引入
  项目域导出默认面，M2AI-09 复用其常数不重复定义。
- M2AI-09 副本文件 = 原格式随行 + sidecar（M2AI-09 字面），不经 M2-9 的导出
  队列/尺寸/元数据策略面——增强对话框自带固定语义（16-bit 随原格式、EXIF 继承原图、
  provenance 入 sidecar），不挂 M2EXP 系选项。

## 资产盘点（Phase 承接面）

| 资产 | 位置 | 复用方式 |
|---|---|---|
| 全局搜索三合一壳（EXIF 真腿 + CLIP/全文诚实空态） | `App/Sources/Lightamer/Library/Views/GlobalSearchDialog.swift`；marker `search.tab.clip.placeholder`（M2-3-2-PLAN.md:96） | CLIP tab 换真腿：文本嵌入 → vDSP 扫描 → 集合态过滤（EXIF 腿同型） |
| EXIF FTS5 external-content 先例（KD-5） | `LightamerCore/Sources/Library/LibrarySchema.swift:311-352` | AI 描述全文表同型（external content + 三触发器 + unicode61） |
| `LibrarySchema` 版本化纪律 | 同文件 :90（`schemaVersion = 3`）+:394-407（user_version 双写） | v4 additive：新表 + 迁移分支，>4 REFUSE 照旧 |
| keyset 分页 + 性能基准方法学 | `LightamerCore/Sources/Library/LibraryQueries.swift`；M2-2-3 先例（15.66ms p95 @ 2 万行） | 语义结果集分页照此；嵌入扫描基准入 perf.md |
| 后台任务注册表（M2AI-07 消费面） | M2-2 导入管线 + `SessionThumbnailProvider` 双档管线（App 层注入 render leg 先例） | 嵌入/打标任务入同一注册表 + 取消；AI 任务优先级低于交互 |
| VersionRef 面收口（M2-8 终态） | `.work/gsd/phases/m2-8-versions/M2-8-3-SUMMARY.md` 交接节 | M2AI-09 副本不进 version_ref（D-4）；sidecar v7 零改动 |
| MCP server + launcher 双入口 | Phase 14 资产（14-CONTEXT.md:42 same-binary 先例） | M2AI-08 保留不动；same-binary 启动参数形态 = M2AI-10 worker 先例 |
| 缩略图管线 | `SessionThumbnailProvider` 档 A（10.6ms/张 @86MP 实测） | CLIP 输入 = 256×256 预缩图（嵌入专用低分辨率重采样，不劫持缩略图缓存） |
| Settings 壳 | M2-3 现有 Settings 页族 | 新增 LCR / ACA 两设置页（Alcedo IA 对齐，见 OQ-8） |

## 直接裁决项（低分叉 / 既有裁决延续；随 OQ 一并过目，可逐条推翻）

### D-M2-10-CONTEXT-1: 检索基线 = 独立嵌入表 + vDSP 暴力精确扫描（D3 延续，sqlite-vec 后手）

- **裁决**：v1 不引 ANN 索引与 sqlite-vec 依赖。查询 = 查询文本嵌入（CoreML 一次前向）
  → 全表 vDSP 余弦点积 → 内存排序 → keyset 分页。**后手触发阈值**：≥20 万张或
  查询 p95 > 50ms 时再议 sqlite-vec/ANN（届时嵌入表 schema 不变，只换执行器）。
- **理由**：10 万张×512d fp32 = 205MB 常驻可接受；单线程 vDSP 全扫 <10ms
  （RESEARCH-NOTES §5 复核成立），精确扫描还免去 ANN 召回率语义负担；
  Alcedo 用 DuckDB HNSW 实验扩展（`semantic_vector_search.cpp:172-174`）是其
  DuckDB 栈的约束，非我们所需。

### D-M2-10-CONTEXT-2: `LibrarySchema` v4 additive——`semantic_model` / `image_embedding` / `image_label` / `label_query` / `ai_understanding` / `ai_understanding_fts` / `ai_rating` 七表

- **裁决**：user_version 3→4，纯 additive（新表 + 索引，零列改动，>4 REFUSE）。
  - `semantic_model(model_key PK, model_id, revision, embedding_dim, image_size, prompt_config_hash, active)`——单激活模型（OQ-9）。
  - `image_embedding(image_id REFERENCES images ON DELETE CASCADE, model_key, dim, embedding BLOB, computed_time, PRIMARY KEY(image_id, model_key))`——BLOB 存 fp16/fp32 字节（**不**学 Alcedo 双维表：那是 DuckDB `FLOAT[dim]` 列约束的产物，`semantic_tables.cpp:16-29`；SQLite BLOB 一表通吃）。
  - `image_label(image_id, model_key, label, score, second_label, second_score, margin, confident, top_scores TEXT/*JSON*/, PRIMARY KEY(image_id, model_key, label))`——Alcedo `SemanticImageLabel` 语义同型。
  - `label_query(model_key, label, query_text, lang)`——出厂中英 label query 落库可查；
    **原型嵌入不入库**——随模型资产包分发（原型与模型版本强耦合，见 D-7）。
  - `ai_understanding(image_id, task_id, provider_id, model_id, prompt_profile_id, rendition_kind, caption, tags TEXT, scene, confidence, active, computed_time)`。
  - `ai_understanding_fts`——FTS5 external content 于 `ai_understanding`（caption+tags 文档列），KD-5 同型三触发器。
  - `ai_rating(image_id, task_id, provider_id, model_id, prompt_profile_id, rating, reasons TEXT, computed_time)`——rating=0 = reasons-only 哨兵（Alcedo `ai_rating.cpp:11-19` 同型）；实星级写 `images.rating`（写入目标裁度见 OQ-11）。
- **理由**：M2-2-CONTEXT:20「`Semantic*`/`Ai*` 表族只留 schema 预留位」的兑现面；
  additive 迁移是 v1→v3 既有纪律；CASCADE 跟 images 行走（KD-4 语义）。

### D-M2-10-CONTEXT-3: AI 出片 = 新 images 行（新文件入 `Media/` + 自己的 `.lra`），不进 version_ref 版本链

- **裁决**：增强副本 = 完整新图片条目：文件落 `Media/`（命名 `{stem}-增强-N` / `{stem}-去杂色-N`，
  Lumen `reserve_copy` 同型 O_EXCL 递增，`ai_dialog.py:17-28`）→ 走既有导入链（EXIF backfill +
  副本自身 `.lra` sidecar + 自己的编辑历史）→ 落当前相册（可选）。
  溯源以 sidecar provenance 字段承载：`operation/scale/amount/source_file/source_image_id/backend`
  （Lumen `enhance` provenance 同型，`ai_dialog.py:141`）。**version_ref 不动**——
  版本链 = 同一源像素的不同参数链（M2-8 语义），AI 出片 = 新源像素，硬塞版本链
  需要「版本携带源替换」新语义 = schema 与心智双重重负。
- **理由**：Lumen 同型（`w.add_documents([path])` 新文档进胶片条，`ai_dialog.py:160-164`）；
  M2AI-09 字面「版本链/胶片条可见」的「可见」由项目网格/胶片条自然满足；
  「可继续调整」= 副本自己的编辑历史（零新机制）。原图零触碰 = 新文件天然保证。
  （形态对比详录 OQ-4，推荐已内置本条，用户可推翻。）

### D-M2-10-CONTEXT-4: rating=0 哨兵 + 星级写 `images.rating` + reasons 随 `ai_rating` 行

- **裁决**：评片输出 clamp 到 1-5；模型拒绝评级（只给理由）= rating 0 落 `ai_rating`
  哨兵行（星级列 0、reasons 非空即有效）；1-5 时同时更新 `images.rating`。
- **理由**：Alcedo 同型（`ai_rating.cpp:15-17`：7a reasons 行 rating=0 哨兵，
  真星在 metadata Rating 列）；「写库」字面 = images.rating 可被图库排序/过滤器消费。
  覆盖用户手评的防护见 OQ-11。

### D-M2-10-CONTEXT-5: 凭据 = Keychain（Security.framework）+ 读出 zeroize + 强制 HTTPS + localhost 例外 + prompt_profile_id 哈希随行

- **裁决**：key 存 Keychain（kSecClassGenericPassword，service = 本 app bundle id）；
  读出后的 `Data` 用完即 `resetBytes`（zeroize，不引第三方）；请求层 scheme 检查——
  非 `https://` 拒发（`http://127.0.0.1`/`http://localhost` 显式 dev 例外，设置页开关或
  输入即放行的 host 白名单，plan 定）；每次远程结果行落 `prompt_profile_id`
  （rubric 文本 FNV-1a 哈希，StableHash 纪律）——rubric 变更后旧行可检、可选择性重跑。
- **理由**：M2AI-06 字面；Alcedo 同面（`ai_credential_store.cpp` + reqwest rustls
  强制 HTTPS + prompt profile 护栏）；零新依赖。

### D-M2-10-CONTEXT-6: crash 记录 = App Support 目录 `ai-compat.json`（Lumen gpu-compat.json 同型）

- **裁决**：worker 崩溃后把 `(model, computeUnits)` 组合落
  `~/Library/Application Support/Lightamer/ai-compat.json`：per-machine-key
  （机型 + OS build）per-model 记录崩溃 computeUnits 与明细（截断 300 字符）；
  **两个不同模型在同 computeUnits 崩溃 → 该 units 全禁**（Lumen `CompatRecord.record`
  `info['all'] = len(info['models']) >= 2` 同型，`ai_worker.py:132`）。后续加载自动
  排除已禁组合；提供设置页「重置 AI 兼容性记录」按钮（设备/驱动更新后自救）。
- **理由**：M2AI-10「记住失败设备组合」字面；JSON 原子写（tmp+rename，L009 同目录
  原子晋升纪律）；Lumen 实测范式直接移植（`ai_worker.py:106-142`）。

### D-M2-10-CONTEXT-7: 模型资产 = 目录清单 + SHA-256 锁定；原型嵌入随资产包分发

- **裁决**：每模型档一份 manifest（profile_id / model_id / revision / 文件清单 /
  字节尺寸 / SHA-256 / 嵌入维 / 输入尺寸 / 文本塔语言 / 许可名）内置编译期常量
  （Alcedo `model_asset_catalog.cpp` 同型）；下载走本仓 GitHub Release 资产
  （版本锁死 URL），HF/hf-mirror 兜底；落盘 `~/Library/Application Support/Lightamer/models/<profile_id>/`，
  校验 SHA-256 后启用。自动打标的 label 原型嵌入 = 资产包随行文件（与模型 revision
  同生共死，不进用户库）；label query 文本（中英）= 出厂常量落 `label_query` 表可查。
- **理由**：Alcedo 断链教训反向吸收——其 HF 下载链实测全报错
  （`model_assets.rs:489-502` `ensure_present` 的 `_hf_endpoint` 参数下划线弃用未接线，
  下载移交 C++ aria2 层后 Rust 侧只验存在）；**内置默认模型零下载** + Release
  单一钦定源 + SHA-256 锁定 = 三重反制（REQUIREMENTS M2AI-01②③）。

### D-M2-10-CONTEXT-8: tokenization 自实现（BERT/中文 WordPiece 或随包 SentencePiece runtime），不引 swift-transformers

- **裁决**：默认模型（Chinese-CLIP 族，OQ-1）文本塔 = BERT 类 → WordPiece tokenizer
  自实现（词表随资产包，~200KB JSON）；SentencePiece 类（Jina 档）若引入则评估
  随包 token 资产 + 最小 BPE 实现，仍不引 SPM 依赖。嵌入维度归一化输出由
  CoreML 图内完成（导出时把 L2-normalize 收进图）。
- **理由**：依赖最小化红线（PROJECT.md：原生框架优先）；swift-transformers 是
  新 SPM 依赖且功能面（生成/分词全家族）远超需求；tokenizer 是纯函数、golden-test 友好。

### D-M2-10-CONTEXT-9: 远程调用 = URLProtocol 原生 URLSession + 两协议编解码手写（openai chat completions / anthropic messages），不引 SDK

- **裁决**：请求体/响应体 Codable 手写两套（POST /chat/completions 与 /v1/messages）；
  超时/重试/取消走 URLSession 原生；流式不用（同步阻塞语义 + 后台任务取消即可，
  Phase 14 MCP 同款「同步 req/resp」先例）。
- **理由**：依赖最小化；评片/描述请求都是一次性短 JSON，流式无 UX 增益；
  两协议已覆盖 OpenAI 兼容生态（含 ollama/LM Studio/vLLM 本地端点）与 Anthropic 直连。

## Open Questions（用户裁决点；每条：问题 / 选项 / 推荐 / 理由）

### OQ-1: 默认内置模型档位——MobileCLIP2 许可翻转后的重开

- **问题**：REQUIREMENTS M2AI-01 预设「MobileCLIP2-S2 int8 ≈40-80MB 内置 +
  MobileCLIP MIT 待核」。research 实测：**权重在 HF 上 = `apple-amlr`（Apple ML
  Research 许可，研究用途类自定义许可），MIT 只覆盖 GitHub 代码仓，CoreNet 训练库
  才是 Apache-2.0**（HF `apple/MobileCLIP2-S2` LICENSE 文件）——开源项目（MIT）
  分发内置权重有许可风险，且 MobileCLIP2 文本塔**仅英文**，与「默认模型须中文
  文本塔」硬约束直接冲突。默认档需重选。
- **选项**：
  - **(A) Chinese-CLIP RN50 int8 内置（≈80MB）**——Apache-2.0 全链干净；中文原生
    （RoBERTa-wwm/RBT3 中文塔）；512 维；RN50 图塔质量弱于 ViT 但 CLIP 零样本
    检索场景可接受；贴 40-80MB 原预算上限。
  - **(B) Chinese-CLIP ViT-B/16 int8 内置（≈190MB）**——质量显著更好（188M 参数
    官方主力档），但 DMG 体积预算翻倍。
  - **(C) 维持 MobileCLIP2-S2 int8 内置**——尊重原字面，接受 apple-amlr 许可风险
    （非商业自用勉强可辩，GitHub 公开分发含第三方下载 = 灰色）+ 中文查询不可用
    （须英文 query），两伤。
  - **(D) 不内置任何 CLIP，首启引导下载**——体积归零，但复刻 Alcedo 下载断链痛点，
    违背 M2AI-01①「零下载」立项初衷。
- **推荐**：**(A)**（预算贴线）或 **(B)**（质量优先）二选一，取决于用户对 app
  体积的容忍度；**C/D 均不推荐**（许可风险 / 痛点复刻）。
- **理由**：许可干净是开源分发硬约束；中文文本塔是用户批准的硬约束；int8 体积
  核算见 RESEARCH-NOTES §6（RN50 77M 参数 → int8 ≈80MB；ViT-B/16 188M → ≈190MB）；
  plan 阶段 spike（ONNX→coremltools 转换 + 实测延迟/质量抽查）对 A/B 通吃。

### OQ-2: GitHub Release 大档首发清单与分界

- **问题**：Release 资产首发带哪些档位？内置/分界线画在哪？
- **选项**：(A) 首发只带 Jina-CLIP-v2 int8（834MB，89 语含中文，768 维 Matryoshka）
  一个语义大档；(B) (A) + SigLIP2 系（英文/多语，质量基线）；(C) 首发只带默认档
  之外的空集，Release 通道建好即止。
- **推荐**：**(A)**——多语大档是「中文质量进阶」唯一真需求；SigLIP2 系与 Chinese-CLIP
  覆盖面重叠，等有真实需求再上架（Release 资产追加无成本）。
- **理由**：Jina-CLIP-v2 int8 是 Alcedo 目录实测存在的现成资产
  （`model_asset_catalog.cpp:31` 874,350,932 字节）；Release 分发后手可追加，首发从简。

### OQ-3: M2AI-09 增强模型档位与分发

- **问题**：超分/降噪模型选哪些、内置还是 Release 下载？
- **选项**：
  - **(A) 双模型 Release 下载（推荐）**：Real-ESRGAN x4plus fp16（16.7M 参数 ≈33MB，
    权重 BSD-3-Clause）+ DRUNet color fp16（32.6M ≈65MB，MIT）——质量主力档；
  - **(B) (A) + compact 内置**：realesr-general-x4v3（SRVGGNet compact ≈17M，fp16
    ≈34MB）内置给「快速增强」档——内置体积 +34MB；
  - **(C) 全内置**（A+B 合计 ≈130MB）——离线开箱即用，体积最重。
- **推荐**：**(B)**——「快速档内置、高画质下载」分层与 OQ-1 的内置/Release 双轨
  心智一致；NAFNet（29M，真实噪声）/FFDNet（旧）v1 不上（DRUNet 覆盖通用降噪）。
- **理由**：Lumen MODEL.md:33-38 已核三模型许可（BSD-3/MIT）；fp16 CoreML 社区
  转换先例在册（VincentGOURBIN/RealESRGAN-CoreML）；⚠️ 转换格式注意
  coremltools#2545（RealESRGAN 的 MLProgram 形态实测慢于 neuralnetwork）——
  plan spike 时两格式实测择优；分块推理 + 固定形状 LRU（Lumen `ShapedSessions`
  范式，MODEL.md:8）防 CoreML 动态形状编译失败（DRUNet 实测动态形状无法出计划）。

### OQ-4: 可编辑副本形态签核——新 images 行（D-3）vs version_ref 扩展

- **问题**：D-M2-10-CONTEXT-3 已按「新 images 行」起草；此 OQ 给用户显式推翻口。
- **选项**：(A) 新 images 行 + provenance（D-3 草案）；(B) version_ref 加
  「源替换版本」语义（版本链内可见、切换版本即切原图/增强图）；(C) 两者都做
  （新行 + 在原图 sidecar 记派生指针）。
- **推荐**：**(A)**；若用户重视「原图/增强图在版本面板一键切换」则 **(C)**
  （派生指针 = 单向元数据，无 schema 新语义）。
- **理由**：见 D-3；（B）需要 version_ref 承载异源像素 = 破坏 M2-8 已签核的
  「同源参数链」不变量，返工面大；（C）的派生指针是纯增量，胶片条视觉分组
  （「衍生自」徽标）可后加。

### OQ-5: M2AI-10 进程隔离形态——同 binary 子进程 vs XPC Service

- **问题**：worker 进程的 macOS 载体选哪种？
- **选项**：
  - **(A) 同 binary 子进程（`Lightamer --ai-worker`）+ stdin/stdout 帧协议**
    ——Phase 14 无头宿主同款形态（14-CONTEXT.md:42 `--mcp` 先例）；Process +
    帧化 JSON/二进制管道；崩溃 = 进程退出检测 + generation 计数重启（Lumen
    `Worker.generation` 同型，`ai_worker.py:159-168`）。
  - **(B) XPC Service（独立 .xpc target）**——launchd 托管按需重启、崩溃上报
    规整；代价 = 新 Tuist target + NSXPCConnection 协议版本化 + 无 GUI 环境调试成本。
  - **(C) in-process 兜底**——worker 起不来时回退主进程推理（崩溃风险回归编辑器）。
- **推荐**：**(A)**，且 **不含 (C)**——M2AI-10 字面是「推理崩溃编辑器不死」，
  in-process 兜底直接违背立项本意；worker 启动失败 = 功能降级不可用 + 错误呈现，
  不是回退。App sandbox 未启用（unsigned 分发）下 (A) 无任何权限障碍。
- **理由**：同 binary 免新 target、免 launchd、与 Phase 14 心智复用；Lumen 范式
  （长驻 worker + 请求超时 kill + generation 重启）直接平移；XPC 的托管重启收益
  被我们自管 generation 重启覆盖。

### OQ-6: 嵌入/打标后台时序——导入自动 vs 询问 vs 空闲批

- **问题**：M2AI-03 字面「导入后询问 Remember-my-choice」（打标询问），M2AI-07
  要求后台任务化——嵌入计算与打标询问的时序关系要定。
- **选项**：
  - **(A) 嵌入自动后台跑 + 打标走询问**（推荐）：导入完成 → 嵌入任务自动入队
    （缩略图之后、可取消）；打标 = Alcedo `SemanticGenerationDialog` 式弹询
    （「用 AI 分析图片内容？」+ Remember my choice 记住选择），选「是」则嵌入完成后
    就地余弦打标。
  - **(B) 全自动**：嵌入 + 打标都自动，无询问（Remember-choice 字面落空）。
  - **(C) 全询问**：嵌入也询问（弹窗疲劳，违背「分析期间可继续工作」）。
- **推荐**：**(A)**——询问面是 M2AI-03 字面（打标写标签 = 产生用户可见状态，
  值得一次授权）；嵌入是纯派生数据（可重建、无用户可见副作用），自动跑合理。
- **理由**：Alcedo 询问的正是「semantic generation」整包，我们拆成
  「派生数据自动 / 用户可见打标询问」两层，弹窗次数最少且字面保全。

### OQ-7: 远程评片 provider 抽象度

- **问题**：M2AI-04「OpenAI/Anthropic 兼容」的 UI/抽象深度。
- **选项**：
  - **(A) 双协议 + 单连接配置**（推荐）：协议二选一（chat completions / messages）
    + base URL + API key（Keychain）+ 模型名 + 严格度 + 输出语言——无 profile 模板库。
  - **(B) Alcedo 式模板库**：预置 openrouter/ark/codex-OAuth/gemini 等 10+ 模板
    （`ai_provider_profile.cpp:173-221`）。
  - **(C) 仅 OpenAI 兼容协议**（Anthropic 经兼容网关用）。
- **推荐**：**(A)**——C 砍掉 Anthropic 直连违背 M2AI-04 字面；B 的模板库是
  Alcedo 的 ccswitch 生态特化，Lightamer v1 无此用户面；A 零依赖覆盖两协议。
- **理由**：D-9 已定两协议手写；模板库 = 纯 UI 增量，后补无返工。

### OQ-8: UI 入口布局——设置两页 + 增强对话框入口 + 搜索接线

- **问题**：M2-3 壳上 M2-10 的 UI 落位。
- **选项**：
  - **(A) Alcedo IA 对齐**（推荐）：Settings 增两页——**Local Content Recognition**
    （模型档选择 / 下载状态 / 兼容性记录重置）+ **Advanced Content Analysis**
    （provider/key/严格度/语言/数据政策说明）；增强对话框入口 = 图库右键 + 编辑器
    Image 菜单（「AI 超分辨率…」「AI 去杂色…」）；搜索 = `GlobalSearchDialog` CLIP
    tab 换真腿 + 全文 tab 换 `ai_understanding_fts` 腿。
  - **(B) 单设置页收纳 + 仅图库入口**——页面少一级，但与 Alcedo 对照走查（M2-3
    computer-use 方法学）口径不一致。
- **推荐**：**(A)**。
- **理由**：本项目 UI 对标 = Alcedo（PROJECT.md 重定义），IA 一致性优先；
  增强对话框双入口（库网格右键 = 批量潜力、编辑器菜单 = 当前图）对齐 Lumen
  （「照片」菜单）+ Alcedo 习惯。

### OQ-9: 嵌入多模型共存——单激活 vs 多模型并存

- **问题**：`image_embedding` 主键含 `model_key`（D-2）天然支持多模型并存；
  检索/打标用哪个？
- **选项**：
  - **(A) 单激活模型**（推荐）：`semantic_model.active` 唯一；换档 = 后台批重算
    全库嵌入（旧维行保留可回切）；搜索/打标恒用激活档。
  - **(B) 多模型并存检索**：任意档查询合并——存储 ×N、评分不可比（不同模型余弦
    分布不同）、UI 复杂。
- **推荐**：**(A)**。
- **理由**：Alcedo 同型（`SemanticModel.active`）；成本核算（RESEARCH-NOTES §5）
  按单模型维度成立，并存直接翻倍；`model_key` 列保留 = 换档重算期间新旧行共存
  的工程空间，不是产品语义。

### OQ-10: worker IPC 数据通道——路径传递 vs 字节块

- **问题**：主进程 → worker 的图像数据怎么传（CLIP 小图 / 超分大图两场景）？
- **选项**：
  - **(A) 路径传递**（推荐）：主进程写 tmp（JPEG 预缩图 / TIFF 中间帧），worker
    自行解码、结果写回 tmp 路径回传——大图零 IPC 拷贝，崩溃断点天然落盘。
  - **(B) 帧化字节块**：数组直接过管道（Lumen 同型）——省两次盘写，100MP 级
    中间帧（RGBA fp32 ≈1.6GB）过管道拷贝代价高。
  - **(C) 混合**：CLIP 小图字节块、超分大图路径。
- **推荐**：**(C)** 或 **(A)**——按数据量分流；plan 实测定稿（此项允许 plan 阶段
  以 spike 数字裁决，不阻塞签核）。
- **理由**：IOSurface 跨进程共享 MTLTexture 复杂度高不合算；Lumen 字节块方案
  在其 numpy 管线成立，我们的 100MP 场景体量差一个量级。

### OQ-11: 评片星级写入防护——直写 images.rating vs 独立列并显

- **问题**：AI 星级写 `images.rating`（D-4）会覆盖用户手评/既有效率工具星级。
- **选项**：
  - **(A) 直写 + 前置确认**（推荐）：对话框呈现星级 + 理由，用户点「应用」才写
    `images.rating`（可勾「不再询问」）；批量评片 = 预览表逐行确认或全应用。
  - **(B) 独立 `ai_rating.rating` 列 + UI 并显**——零覆盖风险，但图库排序/过滤器
    要区分双星源，M2AI-04「星级写库」的消费面复杂化。
  - **(C) 直写无确认**——批量场景顺手，误覆盖不可逆（无星级 undo）。
- **推荐**：**(A)**——「写库」字面保全（最终落在 images.rating 可被现有
  排序/过滤消费），覆盖风险由确认步挡住。
- **理由**：Alcedo 也写 metadata Rating 列（FEATURE-MAP §8.2），其覆盖语义
  未见防护面——我们加确认步是改进项；星级无 undo 基建（rating 不在编辑历史内），
  事前防护 > 事后恢复。

### OQ-12: MCP 语义工具 defer 签认

- **问题**：M2AI-08 字面「保留互补照旧」；M2-10 建成的语义库是否顺手暴露
  `semantic_search` MCP 工具给外部 agent？
- **选项**：(A) defer（推荐）——M2AI-08 按字面零新增，语义工具等外部需求出现
  再立项；(B) 顺手加一个只读 `semantic_search` 工具（registry 缝现成，
  D-14-CONTEXT-1 纯 Swift handler）。
- **推荐**：**(A)**——phase 边界纪律（字面最小面）；B 的边际成本虽低，
  但工具 schema/文档/安全走查都是新增验收面。
- **理由**：Phase 14 的「app 零 AI 代码」裁决（MCP-10）历史语境已变（M2-10 本身
  就是 AI 面），但「需要才加」的依赖最小化逻辑不变。

## 裁决后影响面速览（给 plan 阶段的输入）

- **Core 新目录**：`LightamerCore/Sources/AI/`（SemanticIndex / LabelEngine /
  CompatRecord / AIWorkerClient 协议缝——Core 级可单测，worker 进程 App 层装配，
  沿「sidecar 读写器放 Core」推广原则）。
- **schema v4 迁移**：七新表 additive（D-2）；`user_version` 3→4；迁移测试随 M2-4
  测试 bundle 纪律。
- **plan 期 spike 清单**：①OQ-1 模型 ONNX→CoreML 转换（int8 权重量化 + 静态形状，
  ANE 实测延迟）；②Real-ESRGAN 转换格式 A/B（MLProgram vs neuralnetwork，
  coremltools#2545）；③OQ-10 IPC 两通道微基准。
- **性能基准挂账**：嵌入扫描 p95（1 万 / 10 万 / 20 万张三档）入 `.work/gsd/phases/m2-10-ai-library/perf.md`
  （M2-2-3 方法学）。
- **依赖登记**：预期零新增 SPM 依赖（D-8/D-9）；sqlite-vec 仍为后手（D-1）。

## 裁决记录（用户回批）

- **OQ-1（2026-10-02）**：用户裁决「采用偏质量」= **选项 B（Chinese-CLIP ViT-B/16 质量档，int8 ≈190MB）**。已同步 REQUIREMENTS M2AI-01。
- OQ-2..12 及 D-M2-10-CONTEXT-1..9：**仍待裁决**。
