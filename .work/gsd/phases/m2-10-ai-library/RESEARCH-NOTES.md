# M2-10 RESEARCH-NOTES（AI 图库功能 research 实测）

> 2026-10-02 起草。 companion: `M2-10-CONTEXT.md`（决策草案 + OQ）。
> 参考仓只读：Lumen RAW（MIT，`/Volumes/UNITEK/Documents/Development/lumen-raw`）、
> Alcedo（GPL-3.0 只读，`/Volumes/UNITEK/Documents/Development/AlcedoStudio`）。
> 网络实测 2026-10 时点，链接见 §7 Sources。

## 1. 模型选型实测（web + HF 目录）

### 1.1 MobileCLIP2——许可翻转（本 phase 核心新发现）

- **REQUIREMENTS M2AI-01 预设「MobileCLIP MIT/CoreNet Apache-2.0 待核」→ 实测推翻**：
  HF 权重仓 `apple/MobileCLIP2-S2`（及 MobileCLIP-S2 / S2-OpenCLIP 全族）license =
  **`apple-amlr`**（Apple Machine Learning Research license，自定义研究类许可，
  LICENSE 文件明示覆盖 "trained model weights, parameters"）；MIT 只覆盖 GitHub
  代码仓 `apple-aiml-research/ml-mobileclip`；Apache-2.0 是 CoreNet 训练库。
  → 开源 MIT 项目内置分发该权重 = 许可风险；且 MobileCLIP2 文本塔**仅英文**
  （与「默认模型须中文文本塔」硬约束冲突）。→ OQ-1 重开默认档。
- **体积实数**（HF `plhery/mobileclip2-onnx` 卡片）：S0 vision 43MB / S2 vision
  136MB（fp32 ONNX），embed dim 512，输入 256×256。int8 权重量化约减半至 1/4。

### 1.2 Chinese-CLIP——中文原生、许可全链干净

- 家族：RN50（**77M 参数，最小档**，图塔 ResNet-50 + 文本塔 RBT3）→ ViT-B/16
  （**188M 参数**，图塔 ViT-B/16 + 文本塔 RoBERTa-wwm-base）→ ViT-H/14（958M）。
  HF transformers 文档与官方 README 双源确认。
- embed dim = 512（L2-normalized）；官方 ONNX 导出脚本
  （`OFA-Sys/Chinese-CLIP` `deployment_En.md`：`vit-b-16.img.fp16.onnx` /
  `vit-b-16.txt.fp16.onnx` + tokenizer `.extra_file`）；社区预转换在册
  （`felixdu/chinese-clip-vit-base-patch16-onnx`）。
- 许可：repo 与模型 Apache-2.0。文本序列长度官方导出默认 52 token。
- int8 体积累算（fp32 参数 × 1 byte）：RN50 ≈ 80MB；ViT-B/16 ≈ 190MB。

### 1.3 SigLIP2 家族——多语档体积失控

- `google/siglip2-base-patch16-256`（英文，~203M 总参，768 维）Apache-2.0；
  **多语 `siglip2-base-patch16-256-i18n` ≈ 1.08B 参数**（文本塔扩 XLM 级词表）
  ——int8 仍 >1GB，不入内置候选；多语需求由 Chinese-CLIP（中文）+ Jina（89 语）
  覆盖更经济。
- Alcedo 目录引用的 `immich-app/ViT-B-32-SigLIP2-256__webli` 是 Immich ML server
  的 ONNX 导出（英文 WebLI 训练），非多语。

### 1.4 Jina-CLIP-v2——多语大档实数

- 865M 参数 / 89 语 / 512×512 输入 / 768 维 Matryoshka（可截 512/256）；
  HF 官方 `onnx/model_int8.onnx` = **874,350,932 字节（≈834MB）**——Alcedo
  目录常量同值（`model_asset_catalog.cpp:31` `kJinaClipOnnxSize`，SHA-256 锁定）。
  → 唯一现实的「多语质量进阶」Release 大档（CONTEXT OQ-2 推荐 (A)）。

### 1.5 coremltools 转换路径与 ANE 注意项

- 路径：HF 权重 → 官方 ONNX（fp16/fp32）→ `coremltools.convert`（mlprogram，
  `compute_precision=ct.precision.FLOAT16`）→ int8 权重量化
  （`op_linear_quantization` / 压缩 API）→ `.mlpackage`。
- **ANE 兼容**：int8 权重 + fp16 激活普遍可跑；int8 激活量化需 A17 Pro/M4+
  硬件（Apple 官方量化文档）；**flexible shapes 伤 ANE 兼容**
  （coremltools#1764）→ CLIP/超分导出用静态形状（CLIP 固定 256×256 + 固定
  text seq len；超分按分块固定形状，见 §2.4 Lumen 实测）。
- **MLProgram 逆优化先例**：Real-ESRGAN 转 mlprogram 实测远慢于 neuralnetwork
  格式（coremltools#2545）→ 超分模型转换须两格式 A/B（CONTEXT OQ-3 spike）。
- 术语对齐（任务书「FlexML 组数」）：coremltools 的 flexible-shape 机制会让
  compute plan 产生多组 specialization（Apple「Deploying Transformers on ANE」
  文档）；静态形状 = 单组 = ANE 最优。本仓一律静态形状规避。

### 1.6 Real-ESRGAN / 降噪模型（M2AI-09）

- Real-ESRGAN x4plus：16,697,987 参数（23 RRDB），权重 BSD-3-Clause；
  realesr-general-x4v3（SRVGGNet compact）：BSD-3-Clause——两模型许可与参数数
  均经 Lumen `MODEL.md:33-38` 实核（其 THIRD_PARTY.md 附许可文本）。
- DRUNet color 32,640,960 参数（MIT）/ NAFNet SIDD width32 29,159,715（MIT）/
  FFDNet color（MIT，KAIR）。
- 社区 CoreML fp16 转换先例：`VincentGOURBIN/RealESRGAN-CoreML`（x4plus fp16，
  Mac/iOS 定位）、`mlboydaisuke/Real-ESRGAN-x4-CoreML`；mlx-community 有 MLX
  fp16 档（非 CoreML 路线，仅证可用性）。

## 2. Lumen RAW 源码实测（file:line）

### 2.1 进程隔离骨架 `lumen/ai_worker.py`（310 行）

- **常量**：`OPEN_TIMEOUT = 900`（首用可能编译 CoreML kernel）/ `RUN_TIMEOUT = 600` /
  `MAX_RETRIES = 4`（:29-31）。
- **worker 侧**：`_serve(conn, log_level)`（:40-54）——`compute._IN_WORKER = True`
  标志、SIGTERM→sys.exit(0)（非 NT，daemon 进程优雅退出删临时文件 :46-47）、
  `coreml_housekeeping()`（清理 e5rt 编译缓存 :48）；请求循环 `open`（会话缓存
  per `(path, excluded)` :70-82）/ `run` / `ping` / `stop`（:83-96）；异常回传
  `'error'` 字符串不崩 worker。
- **测试钩子**：`LUMEN_TEST_WORKER_CRASH` env——指定模型名命中即
  `os._exit(9)` 模拟原生崩溃（:58, :73-75）——**我们 plan 需要 crash 注入测试
  钩子的直接先例**。
- **CompatRecord**（:106-142）：`gpu-compat.json`（macOS 落
  `~/Library/Application Support/LUMEN RAW/`，host.py:34-39）；per
  `adapter_key`（机型+驱动）per provider 记 `{models: [...], all: bool, last: {...}}`；
  **两个不同模型在同 provider 崩溃 → `all = True` 全禁**（:132）；`excluded()`
  查询按 `all || model ∈ models`（:119-121）；原子写 tmp+replace（:136-138）；
  CPU 崩溃不记录（:124-125，CPU 是兜底无路可退）。
- **Worker**（:147-214）：`multiprocessing.get_context('spawn')` + `Pipe` +
  `generation` 计数（:159-168）；`request()` 超时 deadline 轮询（1s 粒度 poll），
  超时即 `kill()` + `WorkerCrashed('no response within N s')`（:188-199）；
  进程死亡检测 `not self.process.is_alive()`（:209-210）；管道异常统一折叠成
  `WorkerCrashed`（:211-214）。
- **RemoteSession**（:241-310）：compute.Session 的进程内 drop-in——`_open()`
  带 excluded 列表开会话、元数据缓存 + generation 失效重开（:255-264）；
  **`_call` 重试循环**（:266-282）：crash → culprit = `worker.trying`
  （worker 侧 `on_attempt` 回传的「正在试的 provider」）→ 非 CPU 则
  `record().record(...)` 记账 + 用户提示「已自动改用其他设备重试」→ 元数据置空
  下轮换 provider 重开；MAX_RETRIES 耗尽 → `RuntimeError('AI 推理进程多次异常退出')`。

### 2.2 设备降级链 `lumen/compute.py`

- `coreml_options()`（:148-155）：`MLProgram` 格式 + **默认 `CPUAndGPU`（Metal），
  ANE 需 `LUMEN_COREML_UNITS=ALL` 显式开启**；`RequireStaticInputShapes='0'`、
  `EnableOnSubgraphs='0'`；注释明言：CoreML 编译临时目录 0.1-2s、无持久缓存。
- `provider_plan()`（:282-308）：有序尝试链——macOS = CoreML(GPU) → CPU；
  Windows = TensorRT-RTX → CUDA → DML → CPU；`excluded` 命中的组合直接跳过。
- **固定形状 LRU**（MODEL.md:8 实测结论）：CoreML 动态形状编译 DRUNet
  报 "Error in building plan"、NAFNet 拆 80 段反而更慢 → `ShapedSessions`
  按实际分块尺寸固定 h/w 编译、每模型 LRU 保 4 种尺寸；输入不补边结果一致。
- **CoreML 数值一致性实测**（MODEL.md:9，M1 Pro，vs ONNX CPU 最大绝对误差）：
  x4plus 1.2e-6 / DRUNet 7.5e-7 / NAFNet 8.3e-6 / FFDNet 2.0e-6——CoreML 与
  CPU 路线输出像素级等价，golden-image 测试可行。

### 2.3 可编辑副本 UX `lumen/ai_dialog.py`（185 行 EnhancementDialog）

- **副本命名**：`reserve_copy(folder, stem, kind)`（:17-28）——`{stem}-增强-N.dng`
  / `{stem}-去杂色-N.dng`，`os.O_CREAT|os.O_EXCL` 原子占位 + N 递增（1..9999）。
- **执行编排**（`start`/`wait_for_idle` :83-104）：scheduler Activity `A.AI`
  独占优先级（暂停新预览/缩略图）、等已开始任务结束、**先释放全帧缓存再分配
  4× 放大内存**（:103-104 注释明言）。
- **流程**（work 闭包 :105-147）：读全尺寸原片 → 套当前编辑（`engine.process`）
  → 尺寸校验（4 亿像素上限 `large_image.validate_size`）→ 预览=中央 192×192
  region（:117-118）或全图 → 分块进度回调 `15+78*done/total`（:121）→
  取消检查点贯穿 → **保存阶段失败/取消即删半成品**（:144-147 target.unlink）。
- **落库与回接**（ready :148-165）：`engine.export_image` 带
  `provenance=dict(operation, source, backend, scale, amount)`（:141）→
  `w.add_documents([path])` 新文档入胶片条 → 拷贝水印设置 → `w.open_path`
  直接打开副本继续编辑（:160-164）。
- **取消语义**（reject/closeEvent :177-185）：busy 中关闭 = 设 cancel_event +
  `close_after` 延迟关闭（「当前解码或保存阶段结束后关闭」），不硬杀。
- **导出对话框共用预览**（`enhance_dialog.py` ExportDialog :120-158）：中央
  128×128 原始像素 before/after 对比；自定义 ONNX 模型入口（动态尺寸 NCHW
  float32、倍率一致性校验 :43-46）；Lanczos+反投影非 AI 快速档（:39）。

### 2.4 host.py（52 行，macOS 适配面）

- `data_folder()` = `~/Library/Application Support/LUMEN RAW`（gpu-compat.json）；
  `cache_folder()` = `~/Library/Caches/LUMEN RAW`（可重建编译缓存）；
  `log_folder()` = `~/Library/Logs/LUMEN RAW`（:34-52）——三目录分工可平移。

## 3. Alcedo 源码实测（GPL 只读）

### 3.1 下载断链疑点证实 `rust/puerh_mind/src/service/model_assets.rs`

- **`ensure_present(_revision, _hf_endpoint, _allow_download)`（:494-502）三参数
  全部下划线弃用**——doc comment 明言：「Asset downloading is handled by the
  C++ application layer (via aria2); the `allow_download` and `hf_endpoint`
  parameters are retained for call site compatibility but no longer trigger any
  download.」Rust 侧只剩 `validate()` 验存在。→ REQUIREMENTS M2AI-01
  「疑 `_hf_endpoint` 参数未接线」**证实**：下载职责已迁 C++ 层，HF 端点参数
  在 Rust 路径形同虚设；应用内下载失败痛点 = 双层职责分裂的产物。
  我们的反制（CONTEXT D-7）：内置默认零下载 + Release 单一钦定源 + SHA-256。

### 3.2 模型目录 `alcedo_studio/src/app/model_asset_catalog.cpp`

- 四档：MobileCLIP2 S2 English（:47）/ Jina CLIP v2 INT8 Multilingual
  （`jinaai/jina-clip-v2` @ revision `e10d47f...`，`onnx/model_int8.onnx`，
  **874,350,932 字节 + SHA-256** :24-35）/ SigLIP2 B/32 256 Multilingual
  （repo = `immich-app/ViT-B-32-SigLIP2-256__webli` :35）/ SigLIP2 Base CoreML
  macOS（repo = `zidage/siglip2-base-coreml-macos` 社区转换 :38-40）。
  支持维度 {512, 768}（`semantic_tables.cpp:16-18`）。

### 3.3 语义存储与检索 `storage/store/semantic/`

- **双维表**：`SemanticImageEmbedding`（512）/ `SemanticImageEmbedding768` 同族
  双表 + 对应 LabelPrototype 双表（`semantic_tables.cpp:20-29`）——DuckDB
  `FLOAT[dim]` 定长列的约束产物；SQLite BLOB 我们单表 + dim 列（CONTEXT D-2）。
- **HNSW**：`SET hnsw_enable_experimental_persistence = true` + `CREATE INDEX
  ... USING HNSW`（`semantic_vector_search.cpp:172-174`，DuckDB vss 扩展实验态）。
- **搜索编排**：`kMinCandidatePool = 512`（:23）候选池下限 → HNSW 召回 →
  **score elbow 截断**（`semantic_score_elbow::CutoffScore` 拐点检测 :41-49）
  → offset/limit 分页——「N 硬截断」换成分布拐点，参考价值中（我们精确扫描
  直接全排序，无召回率问题，elbow 可作为结果集「相关/不相关」切分的后手 UX）。
- **打标行**：`SemanticImageLabel(file_id, model_key, label, score, second_label,
  second_score, margin, confident, top_scores JSON)` + `SemanticLabelQuery`
  （出厂中英 label query，`DefaultSemanticPhotographyLabelQueries`）+ 原型表
  （FEATURE-MAP.md:169）——我们 D-2 的 `image_label`/`label_query` 同型来源。

### 3.4 评片与 provider `src/ai/ai_rating.cpp` + `src/app/ai_provider_profile.cpp`

- **rating=0 哨兵**：7a reasons 行 `rating_ = 0`（真星在 metadata Rating 列），
  有效判据 = file key + provider/model identity + reasons 非空（:11-19 注释原文）。
- **协议白名单**：`openai_chat_compatible / anthropic_messages / volcengine_ark_chat
  / openai_responses / openai_codex_oauth / gemini_generate_content / ...`
  （:87-94）；模板表 :173-221（ccswitch / opencode-go / ark / codex-OAuth /
  custom→`http://localhost:11434/v1` Ollama 默认）——模板库体量 = 我们 OQ-7
  选 (A) 双协议的对照面。
- 强制 HTTPS + localhost 例外（Cargo.toml Phase 5c 注 + reqwest rustls，
  FEATURE-MAP.md:205）。

## 4. 本仓锚点（消费面精确位置）

| 锚点 | 位置 | 说明 |
|---|---|---|
| `schemaVersion = 3` | `LightamerCore/Sources/Library/LibrarySchema.swift:90` | v4 additive 起点；:7-9 FREEZE CONTRACT + 迁移 dispatch；:394-407 user_version 读写 |
| images DDL（rating 列已备） | 同文件 :246-276 | `rating INTEGER` 列在（:265）——评片星级直写目标 |
| FTS5 external-content 先例 | 同文件 :311-352 | `images_fts` + 三触发器 + unicode61 + 列名同名纪律——`ai_understanding_fts` 同型 |
| 语义表预留宣言 | `.work/gsd/phases/m2-2-library-project/M2-2-CONTEXT.md:20,145` | 「`Semantic*`/`Ai*` 表族只留 schema 预留位」→ 本 phase 兑现 |
| 搜索三合一占位 | `App/Sources/Lightamer/Library/Views/GlobalSearchDialog.swift`；`M2-3-2-PLAN.md:96`（markers `search.tab.clip.placeholder` / `search.tab.fulltext.placeholder`）；`M2-3-CONTEXT.md:121-123`（OQ-8 边界：数据面归 M2-10） | CLIP/全文 tab 换真腿的接线点；`LibrarySearchModel.family(for:)` 形状分类扩展点 |
| keyset 分页 + 基准方法学 | `LightamerCore/Sources/Library/LibraryQueries.swift`；M2-2-3-ACCEPTANCE（Release 热 p95 15.66ms@2 万行） | 语义结果分页同型；perf.md 方法学沿用 |
| 缩略图双档管线 | `LightamerCore/Sources/Session/SessionThumbnailProvider.swift`（档 A 嵌入预览 10.6ms/张 @86MP） | CLIP 输入预缩图的重采样参照（256×256 嵌入专用，不混缩略图缓存） |
| same-binary 先例 | `.work/gsd/phases/14-mcp-server/14-CONTEXT.md:42`（`--mcp` / `--mcp-stdio` / `--mcp-http` 启动参数分叉，无新 Tuist target） | M2AI-10 `--ai-worker` 同款形态（OQ-5 推荐 A 的依据） |
| 纯 Swift handler 缝 | 14-CONTEXT.md:36-43（D-14-CONTEXT-1 `McpToolRegistry`） | M2AI-08 保留面；OQ-12 defer 的「后手成本低」依据 |
| VersionRef 终态 | `.work/gsd/phases/m2-8-versions/M2-8-3-SUMMARY.md` 交接节 | M2AI-09 不进 version_ref（CONTEXT D-3/OQ-4）的边界依据 |
| 原子写纪律 L009 | AGENTS.md Phase 2 增量 | ai-compat.json / 模型下载 tmp 晋升沿用同目录原子写 |
| StableHash FNV-1a | AGENTS.md Phase 2 增量（L013） | prompt_profile_id 哈希（D-5）；模型 revision 指纹 |
| Lumen 前期调研 | `.work/gsd/research/LUMEN-RAW-NOTES.md`（候选 5/6 = M2AI-09/10 采纳记录） | 本文 §2 为其源码级细化 |

## 5. 成本核算（vDSP 暴力扫描复核）

**设定**：10 万张 × 512 维 fp32 嵌入。

- **存储**：100,000 × 512 × 4B = **204.8MB**（fp16 减半至 102.4MB；SQLite BLOB
  行 ~2KB/行，WAL 正常）。常驻内存可接受；冷启动 mmap 预热一次。
- **算力**：余弦 = 512 FMA/对 = 1024 FLOP；全扫 10 万对 = **102.4 MFLOP**。
  Apple Silicon 单核 vDSP 点积（NEON fp32 ~30-50 GFLOPS，AMX 更高）→
  **计算 2-4ms**。
- **带宽**：205MB 流式读 / 单核可拉 30-60GB/s（M 系 LPDDR 全机 100-800GB/s）
  → **2-7ms**。计算与带宽重叠，**单线程全扫 5-10ms**，十毫秒级先验成立。
- **归一化策略**：图像嵌入入库前 L2 归一化、查询文本嵌入同样归一化 → 余弦退化
  为点积，`vDSP_dotv` 直扫零除法；top-K 用 512 长度小堆或全量 sort（10 万 float
  sort ~10ms 级，可接受；或 partial sort top 256）。
- **fp16 存储**：`vDSP_vconvert` 现场升 fp32 的转换成本 ~1ms 级，存储减半值得；
  plan 实测定夺。
- **扩展阈值**：100 万张 → 50-100ms（超预算）→ sqlite-vec / ANN 后手触发；
  D-1 建议阈值「≥20 万张或 p95>50ms」留 5× 安全余量。
- **查询文本编码**：CLIP 文本塔一次前向（RN50 档文本塔 RBT3 很小）≈ 1-10ms
  （ANE）——总查询延迟目标 **<100ms** 无压力。
- **嵌入吞吐（导入管线）**：CLIP 图塔 256×256 前向，ANE 估 5-20ms/张
  （plan spike 实测）；1 万张导入批 = 1-3 分钟后台——异步管线 + 可取消必要性
  证实（M2AI-07）。

## 6. 体积预算表（内置 vs Release 分界参考）

| 模型 | 参数 | fp32/fp16 | int8 权重 | 语言 | 许可 | 建议档 |
|---|---|---|---|---|---|---|
| Chinese-CLIP RN50 | 77M | 308/154MB | **≈80MB** | 中文 | Apache-2.0 | 内置候选（OQ-1 A） |
| Chinese-CLIP ViT-B/16 | 188M | 752/376MB | **≈190MB** | 中文 | Apache-2.0 | 内置候选（OQ-1 B） |
| MobileCLIP2-S2 | ~80M 级 | vision 136MB | ≈70MB | 英文 | **apple-amlr** | 不推荐内置（OQ-1 C） |
| MobileCLIP2-S0 | ~50M 级 | vision 43MB | ≈45MB | 英文 | **apple-amlr** | 同上 |
| SigLIP2 base i18n | ~1.08B | — | >1GB | 多语 | Apache-2.0 | 不现实 |
| Jina-CLIP-v2 | 865M | 3.4GB | **834MB（HF 实数）** | 89 语 | Apache-2.0 | Release（OQ-2 A） |
| Real-ESRGAN x4plus | 16.7M | fp16 ≈33MB | — | — | BSD-3 | Release（OQ-3 A） |
| realesr-general-x4v3 | ~17M | fp16 ≈34MB | — | — | BSD-3 | 内置候选（OQ-3 B） |
| DRUNet color | 32.6M | fp16 ≈65MB | — | — | MIT | Release（OQ-3 A） |
| NAFNet SIDD w32 | 29.2M | fp16 ≈58MB | — | — | MIT | v1 不上（DRUNet 覆盖） |

> int8 列 = fp32 参数字节 ×1 的权重量化累算（激活仍 fp16）；实际 mlpackage 尺寸
> 会有 ±10-20% 结构开销，plan spike 实测落账。

## 7. Sources（网络实测 2026-10）

- MobileCLIP2 许可/体积：https://huggingface.co/apple/MobileCLIP2-S2 （license =
  apple-amlr）；https://huggingface.co/apple/MobileCLIP-S2/blob/main/LICENSE ；
  https://huggingface.co/plhery/mobileclip2-onnx （S0 43MB / S2 136MB / 512d）；
  https://github.com/apple-aiml-research/ml-mobileclip （代码 MIT）；
  https://arxiv.org/abs/2508.20691 （MobileCLIP2 论文）
- Chinese-CLIP：https://github.com/OFA-Sys/Chinese-CLIP/blob/master/README_En.md
  （RN50/ViT-B/16 家族）；https://huggingface.co/docs/transformers/en/model_doc/chinese_clip
  （77M..958M）；https://github.com/OFA-Sys/Chinese-CLIP/blob/master/deployment_En.md
  （官方 ONNX 导出）；https://huggingface.co/OFA-Sys/chinese-clip-vit-base-patch16
- SigLIP2：https://huggingface.co/blog/siglip2 ；https://arxiv.org/html/2502.14786v1 ；
  https://huggingface.co/google/siglip2-base-patch16-256-i18n （多语 ~1.08B）
- Jina-CLIP-v2：https://huggingface.co/jinaai/jina-clip-v2 ；
  https://huggingface.co/jinaai/jina-clip-v2/blob/main/onnx/model_int8.onnx ；
  https://arxiv.org/html/2412.08802v2
- coremltools：https://apple.github.io/coremltools/docs-guides/source/opt-quantization-overview.html
  （int8 激活需 A17 Pro/M4+）；https://github.com/apple/coremltools/issues/1764
  （flexible shapes × ANE）；https://github.com/apple/coremltools/issues/2545
  （RealESRGAN mlprogram 逆优化）；
  https://machinelearning.apple.com/research/neural-engine-transformers
  （compute plan specialization）
- Real-ESRGAN CoreML：https://huggingface.co/VincentGOURBIN/RealESRGAN-CoreML （x4plus fp16）；
  https://huggingface.co/mlboydaisuke/Real-ESRGAN-x4-CoreML
- 本地参考（非网络）：Lumen `MODEL.md`（模型表/许可/一致性数字）；
  Alcedo `model_asset_catalog.cpp` / `semantic_*.cpp` / `ai_rating.cpp` /
  `ai_provider_profile.cpp` / `model_assets.rs`
