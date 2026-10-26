# LightCraft 调研速记（2026-10-09）

> 来源：github.com/storytold/lightcraft（本地克隆 `/Volumes/UNITEK/Documents/Development/lightcraft`，HEAD `25ef65c` Release 0.7.0，2026-10-11 docs）。

## 〇、历史重写通告（2026-10-13 对表批，先读本节）

**上游 2026-09-30 起重写全部历史**（force-push 重构），本地仓已按「纯参考仓无本地修改」裁决
`git reset --hard` 到新 HEAD。后果与结论：

- **旧 SHA 全部作废**：本文正文引用的 `25ef65c`（旧 Release 0.7.0 HEAD）及一切旧 commit/PR 锚
  在新历史中不存在；v0.7.0 tag 不存在于新历史。**新 HEAD 锚 = `a82a001d`**
  （0.8.0 主干，"Merge pull request #1857 integrate-batch-38"）；新历史带 tag
  v0.5.0 / v0.6.0 / v0.7.1 / v0.8.0。本文正文 SHA 仅作历史阅读用，重查一律以新 HEAD `a82a001d`
  树为准（正文引用的 docs/*.md 路径与主题均已核在新树中仍在）。
- **本次对表结论（gainmap.rs 比对）**：M6-3/ALCE-03 兜底臂引用的
  `crates/codecs/src/gainmap.rs`（ISO 21496-1 gain map writer：MPF 索引 + ISO marker +
  Adobe `hdrgm` XMP + Apple 描述 + `read_jpeg` 读回）**旧（834 行）↔ 新（834 行）逐字节相同**
  （`diff` 空，工作区版本 0.8.0；许可仍 = 工作区级 MIT OR Apache-2.0，文件内无独立许可头）。
  **ALCE-03 兜底参考实现不受重写影响。**
- **已落袋借鉴（M6INT 家族五件：M6-1 单写者锁/M6-2 process version/M6-4 stacks+AI 蒙版 spike/
  M6-6 parity 清单 CI 门）不受影响**——借鉴的是思想与范式（单写者锁语义、process 冻结规则、
  auto-stack 间隔聚类、parity 对账纪律），均非绑定旧 SHA 的代码；新 HEAD 面上这些范式仍在
  （`catalog.lock` / `docs/process-versions.md` / `docs/gaps.md` 路径已核在新树）。
- 重写体量：旧 0.7.0 快照 ↔ 新 0.8.0 HEAD = 564 files changed，+92k/−4.8k 行（上游批量
  integrate-batch PR 涌入所致）；对借鉴判定无增量主题（gainmap 之外的 delta 属上游功能面扩张，
  M6 charter 已裁定的借鉴清单不因此扩项）。

> 许可：**MIT OR Apache-2.0 双许可**（可选其一；代码级移植合法，需 NOTICE 归属）。~10.7k 星。
> 定位：Adobe Lightroom 的 **clean-room 纯 Rust 复刻**——照片图库 + RAW 显影 + 非破坏编辑；macOS/Windows/Linux/FreeBSD/WASM 多端；MCP server 内置；纯 Rust ~202k 行 / 505 文件 / 24 库 crate + 3 app。状态 alpha，自评 Lightroom 功能广度 81.1%、实做就绪 ~61%（按受众分：主力摄影师 ~49%）。

## 一、架构一句话

Engine-first 分层 Cargo workspace（`cargo xtask layers` CI 强制分层）：L0 `geom/color/raster/tiff` → L1 `raw(22.3k 行自研解码)/codecs/meta/develop(编辑模型)` → L2 `pipeline`（**CPU 参考实现 = oracle**）→ L3 `catalog(append-only journal)/gpu(WGSL 计算孪生)/preview/merge/segment(SAM 3)` → L4 `engine`（**命令注册表：一切皆命令** + history + 渲染/导出作业）→ L5 `ui-egui`（可换皮）+ `mcp` → L6 三 app。UI/键盘/CLI/JSON-lines 控制通道/MCP 五个前端经**同一命令分发缝**（id + JSON 参数）；下层永不知 UI 存在。

## 二、逐面对照

### 面 1：图库模型

- **LightCraft 做法**：持久化 = **append-only op log（`catalog.log` JSON lines，每行 CRC-32、fsync 后返回）+ 周期快照 `catalog.snap`（temp+fsync+rename 原子）+ 后台 compaction**；崩溃规则成文并有注入测试（torn 尾记录回切、写失败重试同 seq、坏记录后保留 `catalog.log.damaged-<seq>`、快照/日志交错崩溃全覆盖）；`catalog.lock` 单写者。功能面：albums 嵌套 folders、**smart albums（规则树）**、**stacks（含 auto-stack）**、virtual copies、versions、keywords、faces、watched folders 自动导入、逐字节重复检测、字段搜索语法（`rating:>3 flag:pick iso:>800 camera:x2 date:2026-04 keyword:mountains`）、日期/重命名模板导入、justified+square 双虚拟化网格、**Compare/Survey 挑片视图（同步缩放）**、contact sheet PDF（A4/Letter，150dpi，撤销安全）。
- **我方现状**：`.lalb` SQLite 单文件包（WAL + NORMAL + 写批节流 checkpoint + close TRUNCATE；备份唯一钦定路径 `ProjectFileStore.backup(to:)` sqlite3_backup）；Library 目录（LibrarySchema/ProjectFileStore/LibraryStore/ImportFilter/ImageLinker/ImportService/ExifFold/ExifSearchIndexer/ExifSearchParser/LibraryQueries）；真身边界 = `.lra` 恒编辑态真相，项目库 = 组织 + 检索投影 + 引用（PathKind 0/1/2）；ImportService 已有 size+FNV-1a 内容哈希重复检测；ExifSearchParser 已有结构化 term（iso/focal/aperture eq·range + fts + 日期，typed 错误）；versions = M2-8 版本链。
- **差距/可借鉴**：① smart albums（保存式规则树）——我方检索是即时投影，无保存式智能相册；② **stacks + auto-stack**（burst/bracket 按时间间隔堆叠）——我方无；③ Compare/Survey 挑片视图——我方 culling 只走 MCP 外部 AI 筛选，无人工挑片视图；④ watched folders 自动导入——我方导入一次性；⑤ LightCraft journal 崩溃规则文档化——我方 SQLite WAL 已有等价保证，不需借鉴机制本身。
- **我方已超集**：事务性持久化（SQLite 对 op-log 是代差优势——无需自证崩溃安全）、内容哈希去重、结构化搜索（含中文 FTS）、版本链（LightCraft versions 弱于我方 M2-8）。

### 面 2：RAW 解码

- **LightCraft 做法**：**自研纯 Rust 解码器**（`raw` crate 22.3k 行）：DNG / CR2 / CR3(CRX 无损+C-RAW) / ARW(含压缩) / NEF(无损+有损 split 后) / RAF(Bayer+X-Trans，无损+有损) / RW2·RWL(全格式) / PEF / ORF(未压缩) / SRW；**culling 先显嵌入相机预览（~0.1s）**；预览/缩略从 mosaic 直接 binning（`develop_binned` 2×）不全解；相机色彩 = 拟合估计（从相机 JPEG 拟合，ΔE 2.9–10，52 组 spectral 矩阵 + 4 内置 profile，实测标定库缺失 = 头号 gap）；lens profiles 只有文件内嵌（DNG opcode / RW2 数据），无数据库；`docs/raw/coverage.tsv` **逐机型验证纪律**（1446 Adobe 机型中 81% 可解码、16% 逐台验证）；compressed ORF / HE NEF / 部分 CR3 变体 = 预览兜底；`lightcraft-cli calibrate` 从相机 JPEG 拟合矩阵。
- **我方现状**：CIRAWFilter（RAW 8/9，macOS 27 起 Neural Engine demosaic+denoise 一趟融合）；相机覆盖 = Apple 名单（~600+ 机型，新机滞后数月）；色彩 = Apple 内嵌 profile；无自研解码（约束明文禁止 libraw/自研）。
- **差距/可借鉴**：两条路线互斥不可移植（LightCraft 用 2.2 万行换「不被 Apple 名单/内部算法卡脖子」，我方用 ANE 换解码+降噪质量）。可借鉴的只有**方法论**：①逐机型验证 corpus 纪律（SHA256 清单 + 解码 smoke + 亮度统计抽查）——我方 CIRAW 解码对 Apple OS 更新导致的输出漂移**无证据链**，可建轻量 corpus 防 silently-changed output；②嵌入预览 stand-in 先行显示（我方缩略图有缓存，loupe 打开是否先显嵌入 JPEG 需核，候选验证项）。
- **我方已超集**：RAW 9 ANE demosaic+denoise 融合质量（LightCraft AI denoise 是可选后处理、Bayer only、无 X-Trans 权重）、解码速度（ANE vs CPU）、相机名义覆盖面、色彩 profile 质量（Apple 实测 vs LightCraft 拟合估计 ΔE 2.9–10）。

### 面 3：非破坏性编辑模型

- **LightCraft 做法**：`DevelopSettings` 值对象（serde `#[serde(default)]` 宽容演进，未知字段忽略/缺省补默认）；catalog 为真相 + 可选 XMP sidecar（`lc:` 命名空间 JSON 精确回环；**只读** `crs:` 60+ 字段近似映射；owned-properties 合并写——只替换自己拥有的属性、外来的逐字节保留）；**process version per photo**（V1 冻结 / V2 现行——凡改观感的变更必须开新 process 号，老照片渲染零漂移直至手动 Update to Current Process；缺字段=V1；legacy 值不序列化故 preview cache key `hash64` 逐字节不变；copy/paste/sync/preset 永不携带 process）；**控制规格单表**（每 slider 一行：id/range/default/section/track 样式）→ UI 面板构建 + MCP schema + get/set by id 三消费方同源；indexed controls（`pointColor.<i>.hueShift` 模板寻址列表项）；预设导入矩阵（.lcpreset/XMP preset/.lrtemplate/Luminar/.zip/.cube LUT）。
- **我方现状**：`.lra` JSON sidecar 恒真相（schemaVersion 9，additive + typed degrade 纪律），history stack（items/position）+ versions 链 + DRT record + FilmRecord document 级载体；实例身份 UUID；StableHash（FNV-1a）跨进程身份；HistoryHash 折叠（含 drt/film 尾位）；MCP IopCatalog 已有参数 schema 元数据。
- **差距/可借鉴**：① **per-photo process version 是我方真缺口**——我方 iop 调观感（nlmeans 重调、tone model 变更、M5 TRACK 落地后调参概率升高）会让全部老 `.lra` 渲染漂移，目前只能靠 schemaVersion 整体迁移语义兜底；LightCraft 的「改观感=新 process 号 + 冻结旧号 + hash 不变技巧」是零成本移植（`.lra` 加可选 `process` 键，缺=legacy）；② 控制规格单表三消费方同源——我方 UI slider 表与 MCP schema 是否单源需审计（MCP IopCatalog 与 iop params 定义疑似双源）；③ owned-properties XMP 写——被「`.xmp` 永不读写删」红线挡死（Alcedo 同样不写 XMP），不借鉴；④ 预设导入矩阵（lrtemplate/Luminar）——无用户需求，不借鉴。
- **我方已超集**：版本树（分支/粘贴/swap 单路径）、DRT + Film document 级 record（LightCraft 无 DRT 概念、HDR 只有 headroom 开关）、sidecar schema 演进纪律（typed degrade 有负测钉死）。

### 面 4：处理管线（GPU 与健壮性）

- **LightCraft 做法**：**CPU 参考管线（oracle）+ WGSL GPU 孪生**，等价性门 mean<0.5 LSB / max≤3 LSB（实测 Metal max 1 LSB，26 组设置用例）；GPU 健壮性五件套：**短提交**（每 stage + 每 16M invocation flush，防 Windows TDR/i915 watchdog）、error scopes 全包 + device-lost 回调、**读回 sanity**（输出先清零 + per-pixel stage 写 alpha 255 canary，未写 = 本 render 降 CPU；全黑结果 ≥4096px = 本 render 重渲 CPU）、**两级 fallback 阶梯**（buffer 超限/显存不足/黑帧 = 本 render 降、验证错误/device lost = 整进程降，且 `perf.gpuReason`/`gpuFallback` 诊断字段直出 UI）、**缓冲池**（≤2GB 按精确尺寸复用，释放后 3s 回收）；stage cache 与 CPU 同 key 共存（UI 零改动）；**GPU init 崩溃哨兵**（`gpu-init.marker` 编译前后摘除，残留 = 下次启动关 GPU）；**内存单预算闸**（25% RAM：1/2 引擎缓存跨类 LRU + **1/4 解码工作门 work_gate**——网格缩略/邻居预取/导入探针等房间才跑，loupe/导出永不等待 + 1/8 GPU 池）；`malloc_zone_pressure_relief` 每次 decode 后调（macOS 大块释放滞留对策）；dhat-heap 堆剖面 feature。
- **我方现状**：Metal 3 直渲 float32 RGBA linear Rec2020；per-module per-ROI tile 缓存 + GAC；IOPParity 七域 bundle + golden 对照（对 darktable 参考输出）；test-direct 七域 + ru_maxrss 机检 MEMFAIL 8G 门；PipeCache 预算 + clearCaches 三层。
- **差距/可借鉴**：① **work_gate 分类配额 admission control**（「关键路径永不等待，后台解码等房间」）比我方全局限流的粒度细——候选（中）；② **读回完整性哨兵**（canary 字节 + 异常本 render 降级）——我方 Metal 单腿无 CPU 全管线兜底，但导出链可加「结果完整性核验」（候选，低）；③ 进程级降级诊断面（reason 字段直出 UI/日志）——我方诊断面弱，候选（低）；④ 短提交——我方 tile 化天然切短命令（已覆盖）；⑤ CPU oracle 全管线——我方架构性不可行，等价性职责已由 IOPParity golden 承担（已超集：对第三方参考对照比自比自更强）。
- **我方已超集**：零拷贝 unified memory 直渲、per-ROI 缓存粒度、100MP 线性行带流式。

### 面 5：色彩管线

- **LightCraft 做法**：working = **linear Rec2020 D65 float32（与我方同构）**；Bradford 色适应白平衡（CCT↔chromaticity 模型，Kelvin/relative 双标尺显式进 schema）；**OkLab/OkLCh 承载 mixer/HSL/grading**（感知均匀，皮肤保护 vibrance 好写）；**单调样条（monotone by construction——曲线永不意外反转）**；**gamut mapping 替代 clipping**（出界映射不裁剪）；display profile 转换体系；HDR 编辑（headroom 上限 + 派生 SDR rendition）+ 导出 **ISO 21496-1 gain map JPEG / PQ AVIF / 32f TIFF**。
- **我方现状**：linear Rec2020 scene-referred float32；grade ACEScc envelope；DRT（ACES20/OpenDRT）尾段 + EDR 四态视口（PQ/HLG/P3-PQ）；LutEncodingCatalog 17 传递曲线 Float64 双向；Film sub-run + FilmSolveCache；导出 ICC 解析器（自建 ICC v4 + HDR 臂系统 PQ/HLG）+ peak 闸门。
- **差距/可借鉴**：① **ISO 21496-1 gain map（UltraHDR）JPEG 导出**——正是 ALCE-03 挂账正主；LightCraft 纯 Rust 实现了 metadata writer，算法可参考移植 Swift（或先 spike AVFoundation/CGImage auxiliary data 原生路）——候选（高，前置 = 用户解冻 ALCE-03）；② **导出 gamut mapping**（软映射替代硬裁剪）——我方 ColorSync 转换默认 intent，质量升级候选（中）；③ **单调样条构造**——我方 rgbcurve/tone curve 单调性保证需核，缺则候选移植（小而美）；④ OkLCh 承载 hue/sat 类算子——我方 GradeCatalog hls/colorWheels 色彩空间需核，LightCraft 经验 = OkLCh 数值稳、皮肤保护好写（候选，低-中）；⑤ HDR headroom 编辑——我方 DRT-HDR 全链已有（已超集）。
- **我方已超集**：DRT 显示变换（ACES20/OpenDRT——LightCraft 无）、胶片物理模拟、LUT 编码维、EDR 视口四态。

### 面 6：MCP / agent 工具面

- **LightCraft 做法**：**命令注册表单源**（每命令 id/label/menu path/shortcut/params/enabled/run）→ 五前端同缝分发；MCP（手写 stdio JSON-RPC，零 async runtime）：**自动派生每命令一工具（`cmd_*`）** + 精选 helper（import/query_photos/select_photos/list_controls/get_develop/set_develop/apply_preset/crop/render_photo→图像内容/export）+ **resources**（`lightcraft://library` 等 5 个 JSON 快照）；**双模式 = headless（内嵌 Session + `--library` 持久库）/ connect（连活 app 控制通道，可截图/点击/手势）**；**库锁**（`catalog.lock`，第二写者拒并报「already open in process N」+ 指引走 connect）；command_batch 逐步 undo；export **progress notification（≤10/s 严格递增）+ cancellation（requestId 停下一张前）**；严格参数校验（-32602 回报键名与合法参数）；一条龙 CLI `run`（JSONL 输入输出）；写盘失败「内存已应用 + 持续重试 + UI 云图标告警」语义。
- **我方现状**：Phase 14 已交付——McpToolRegistry（HTTP transport + Bearer 鉴权 + endpoint file + McpLauncher 一键拉 agent），Culling/Editing/MatchColor 三 toolset + IopCatalog + PhotoProjection；MCP-09（preset/export/keywords + 三研究项）；端到端 byte-identical parity 门（M5-1 G4）。**MCP-09 研究项 A（无头/会话并发 sidecar 双写对策）未决**。
- **差距/可借鉴**：① **「单写者锁 + connect 转发」是 MCP-09-A 的现成答案**——无头实例持锁时活 app 拒开、agent 改摸活实例控制通道——候选（高，直接回应未决项；我方 MCP 已常驻 HTTP，缺的是与会话的仲裁语义）；② **注册表自动派生工具**——我方工具手写集合，命令面膨胀后维护成本升；但需先有统一命令注册表（我方命令分散于 MenuCommandID/NodeGraphCommand/DrtPanel 键族），改造成本大——列观察项；③ progress notification + cancellation——候选（低）；④ resources JSON 快照——低成本加（低）。
- **我方已超集**：HTTP transport + Bearer 鉴权（LightCraft 明示 loopback 无鉴权）、byte-identical parity 门、launcher 模式（agent provider 配置归 agent 侧）。

### 面 7：平台与分发

- **LightCraft 做法**：macOS/Win/Linux/FreeBSD/WASM 五端；wgpu 跨后端卫生（Windows 默认 DX12-only 不加载 Vulkan 驱动——驱动崩溃不可捕获；GPU init 哨兵；窗口渲染器探针轮换 + 失败记忆重试 ≤4 次）；12+ 分发形态（MSI/AppImage/Flatpak/deb/rpm/Nix/静态 web）；CJK 字体独立仓 craft-fonts（构建期可选输入）。
- **我方现状**：macOS 27+ 专属、Metal 3 单后端、unsigned DMG/zip（2026-09-27 终裁）。
- **对比**：方向相反无借鉴面；LightCraft 代码量大头之一就是跨平台健壮性工程，我方不需要。**我方已超集**：EDR 原生、ANE、签名成本为零、SwiftUI 原生无障碍。

### 面 8：AI 面

- **LightCraft 做法**：SAM 3 分割（candle 纯 Rust 推理，Metal/CPU；Object 点击精修 + Describe 文本选择 + **延迟高分辨率 patch 精修**（~1s 后放大重析，≤4 patch/selection，边缘细 5–10×）+ Edge 羽化参数）；AI denoise（**不捆绑权重**：用户自装 ONNX + manifest + SHA256 + 合成自检（有限输出/可重复/尺度/降噪量四检）+ 条款确认 + RawNIND GPL 权重 opt-in 政策显式记录）；faces（纯 Rust 检测+识别 + MWG region 只读互操作）。
- **我方现状**：M2-10 CLIP 本地语义 + ANN + 自动打标 + 远程评片；M2AI-09/10（AI 出片入工作流 + 推理 worker 进程隔离 crash-safe，Lumen 借鉴）；M2-7 蒙版（brush/gradient/luminance/color-range/Follow Edges/depth 候选）。
- **差距/可借鉴**：① **可选模型安装器纪律**（SHA256 验证 + 合成自检 + 条款确认 + 断点续传 + 取消）——我方 MiDaS depth（已采纳）与 M2AI 后续模型分发直接复用（候选，中）；② **SAM 3 级语义分割蒙版**——我方蒙版族缺 AI 语义分割；macOS 路径优先 spike Apple 原生 `VNGenerateForegroundInstanceMaskRequest`（零模型成本），不够再上 SAM CoreML（大件，OQ）；③ 边缘精修 patch 思路（点击后延迟放大重析）可用于我方任何 AI 蒙版质量升级（记录）。
- **我方已超集**：远程评片（OpenAI/Anthropic 兼容打分——LightCraft 无）、CLIP 语义检索、worker 进程隔离。

### 面 9：工程方法论（非代码）

- **LightCraft 做法**：① `docs/gaps.md` **排名清单**（每 gap 一条：证据/用户影响/工时/beta 阻塞标记，agent 按 top 领活）+ `parity-checklist.md` 517 行逐条 ID + **CI 门「checklist 引用的 id 必须存在」**（`cargo xtask parity`）+ ROADMAP 头条数字（breadth/readiness 分受众/剩余工时，按 PR 历史标定）；② **never-crash 纪律**：非测试代码禁 unwrap/expect/panic/unsafe + clippy lint 强制 + 每崩溃修复带回归测试；③ 资产 ATTRIBUTION.md 同 commit 登记 + CI `assets` 门（禁 Adobe 资产）；④ procedural demo library（`scenes` crate 程序化生成演示照片，不捆绑图片资产）；⑤ clean-room 声明 + 「读公共 spec 与黑盒观察，禁读 Adobe 二进制与 GPL 源」。
- **我方现状**：ALCEDO-FEATURE-MAP.md（301 行，功能对标正本但无 ID 化对账）；GSD 流程有 golden/parity/gui-acceptance 门；无 never-crash 等价 lint；spectral LUT 许可证据已有先例（未 CI 化）。
- **可借鉴**：① **ALCEDO-FEATURE-MAP → ID 化 parity 清单 + CI 对账门**（每天级成本，M6+ Alcedo 对标批的前置基建）（候选，中-高）；② never-crash lint 的 Swift 对应（禁 force unwrap/`try!`，swiftlint/编译器设置）（候选，低-中）；③ ATTRIBUTION CI 门固化（低）；④ demo library 程序化生成（GUI 首启演示可选）（低）。

## 三、借鉴候选清单（按价值排序）

| # | 候选 | 价值 | 风险/成本 | 许可 |
|---|---|---|---|---|
| 1 | **MCP 单写者锁 + connect 转发**（回应 MCP-09-A 未决项） | 高——并发双写语义一次定清 | 低-中（McpServerController + Session 仲裁） | 无碍 |
| 2 | **ISO 21496-1 gain map（UltraHDR）JPEG 导出** | 高——ALCE-03 挂账正主，参考实现在手 | 中（先 spike AVFoundation auxiliary 原生路，Rust 版兜底） | Apache-2.0/MIT，记 NOTICE |
| 3 | **per-photo process version**（`.lra` 可选 `process` 键 + 冻结规则 + hash 跳过 legacy） | 高——iop 调参漂移老档的根治纪律 | 小（sidecar additive + HistoryHash 旁路） | 无碍（思想移植） |
| 4 | **量化对标方法论**（ALCEDO-FEATURE-MAP → ID 化 parity 清单 + CI 对账 + 分受众 readiness 数字） | 中-高——M6 对标批基建 | 一天级 | 无碍 |
| 5 | **AI 模型可选安装器**（SHA256 + 合成自检 + 条款 + 断点续传） | 中——MiDaS depth/M2AI 分发直接复用 | 低 | 无碍 |
| 6 | **SAM 3 级语义分割蒙版**（先 spike VNGenerateForegroundInstanceMask） | 中-高（蒙版族补 AI 语义分割） | 大（模型/许可/性能三裁） | SAM 权重许可需查 |
| 7 | **work_gate 分类配额内存闸** | 中——大图连跑内存峰值治理 | 低-中 | 无碍 |
| 8 | 图库功能包（stacks/auto-stack/smart albums/Compare-Survey 挑片/watched folders） | 视用户图库强度 | 中-大（四个独立小特性） | 无碍 |
| 9 | 色彩三小件（导出 gamut mapping/单调样条/OkLCh 审计） | 中（质量升级） | 各小 | 无碍 |
| 10 | 工程纪律小件（never-crash lint/ATTRIBUTION CI/progress notification/resources 快照） | 低-中 | 小 | 无碍 |

**明确不借鉴**：自研 RAW 解码器（路线互斥，我方 CIRAW 锁定）；op-log 持久化（SQLite 代差）；XMP owned-properties 写（`.xmp` 红线）；CPU 全管线 oracle（架构性不可行）；跨平台层（macOS 专属）；egui/headless softpaint（SwiftUI 不同栈）；Lightroom catalog 导入（不互通已裁决）；智能体 UI 遥测（egui widget 寻址——SwiftUI AX 体系已有）。

## 四、OQ / 裁决点（给用户，带推荐）

- **OQ-LC-1（MCP 并发语义）**：MCP-09-A 是否按「单写者锁 + 活实例转发」立专项？**推荐 = 是**（LightCraft 范式现成，改动集中，解锁 agent 与 GUI 同库协作）。
- **OQ-LC-2（UltraHDR）**：ALCE-03 是否解冻立项（gain map JPEG 导出）？**推荐 = 是**（先 spike 原生 auxiliary 路，LightCraft 实现兜底；EXR/ALCE-02 仍独立挂账）。
- **OQ-LC-3（process version）**：是否引入 per-photo 渲染过程版本纪律？**推荐 = 是**（M5 TRACK/Mertens 落地后 iop 调参概率升高，越早越省）。
- **OQ-LC-4（AI 分割蒙版）**：语义分割蒙版是否入 V2 蒙版族？**推荐 = 先零成本 spike Apple VNGenerateForegroundInstanceMask，达标即收，不达标再裁 SAM CoreML**。
- **OQ-LC-5（图库功能包）**：stacks/auto-stack/smart albums/挑片视图/watched folders 哪些立项？**推荐 = stacks + auto-stack 优先**（拍摄强度用户的真需求，SQLite 落地便宜），smart albums 次之，挑片视图/watched folders 挂账。
- **OQ-LC-6（量化对标）**：ALCEDO-FEATURE-MAP 是否升维 ID 化 parity 清单 + CI 对账？**推荐 = 是**（成本一天级，建议作为 M6 对标里程碑的第一个 plan）。

## 五、许可边界

MIT OR Apache-2.0（任选其一）——**代码级移植合法**（与 darktable GPL-3.0「只读参考不复制」红线不同），仍须 NOTICE 归属；仓内自有 clean-room 纪律（禁读 Adobe 二进制/GPL 源、资产 ATTRIBUTION 同 commit 登记）与我方方法论同向。展示照片公有领域；UI 字体 Inter OFL；CJK 字体独立仓 OFL。

## Sources

- 本地克隆：`/Volumes/UNITEK/Documents/Development/lightcraft`（HEAD `25ef65c`，0.7.0）
- `README.md` / `ROADMAP.md` / `AGENTS.md`（clean-room 与 never-crash 纪律）
- `docs/architecture.md`（分层与规模）、`docs/gpu-pipeline.md`（oracle/健壮性/内存）、`docs/process-versions.md`（process 版本规则）、`docs/mcp.md` + `docs/control-protocol.md`（命令注册表/MCP/库锁/进度取消）、`docs/xmp-interop.md`（sidecar owned-properties 合并）、`docs/denoise.md` + `docs/ai-masks.md`（模型安装器/SAM 3）、`docs/merge.md`（HDR/全景）、`docs/gaps.md`（排名 gap 方法论）、`docs/raw/coverage.tsv`（逐机型验证）
- 对照内部正本：本仓 AGENTS.md（M2-2/.lalb、M2-6 DRT、M2-7 蒙版、M2-8 versions、M2-9 导出、M2-10 AI、M5 MCP-09/ALCE 挂账）、`.work/gsd/research/LUMEN-RAW-NOTES.md`（格式先例）

## 六、裁决记录（用户回批 2026-10-11）

**OQ-LC-1..6 全部按推荐采纳**：①MCP-09-A 按「单写者锁 + 活实例转发」立项 ②ALCE-03 解冻（先 spike AVFoundation auxiliary 原生路，LightCraft 实现兜底）③引入 per-photo process version（M5 TRACK/Mertens 落地后 iop 调参概率升高，越早越省）④AI 分割蒙版先零成本 spike Apple VNGenerateForegroundInstanceMask，达标即收 ⑤图库功能包 stacks + auto-stack 优先（smart albums 次之，挑片视图/watched folders 挂账）⑥ALCEDO-FEATURE-MAP 升维 ID 化 parity 清单 + CI 对账（作为 M6 对标里程碑第一个 plan）。立项站点随 M5 后续站/M6 charter 排布。

## 七、2026-10-16 增量登记（`a82a001d..0da998f2`，+43）

> 夜间同步批：fetch 经 SSH 显式 URL（origin HTTPS 走本机死代理 127.0.0.1:10809，绕开）；
> 上游历史重写仓惯例 `reset --hard 0da998f2`。主体 = batch 39/40 整合 + 四个功能面：

- `c78b457c` **LR-VIEW-ZOOM 软打样 1:1 zoom window**：软打样 1:1 渲染放大窗，1:1 像素与导出做等值测试。借鉴候选：**是**——软打样我方未立项；立项时「1:1 像素 == 导出」验收形态直接取用（UQ-L2）。
- `cb8b797c` **KEY-SLIDER-RESET 滑杆双击重置**（#1436）：名称/滑块双击回默认值。借鉴候选：**是**——SwiftUI Slider 无原生支持需自实现；yiyin 面板与我方 iop 面板通用 UX。
- `ab64e9a5` **KEY-SLIDER-SCRUB 滑杆值横扫**：拖值左右扫动调参。借鉴候选：**是**——与上件合为一个滑杆 UX 小件（UQ-L1）。
- `0242a75b` + `f625c74c` **Faces 网络整体 GPU 化（wgpu）**：整网卷积 GPU + 批处理 + CPU-only 开关 + 限速 GPU 使用。借鉴候选：方法论级——人脸检测不在范围；「GPU 批处理 + CPU 回退 + pacing」模式对 M2AI 推理 worker 一次参考即弃。
- 其余 ~35：batch 39/40 整合（brush Shift-click 直线笔画 `e5c6e17b`、PERF-SYNC 目录清单直读 `540a281c`、格鲁吉亚语 i18n、parity 清单文档维护、CI font pin `fd9d045c`、clippy 1.99 修复 `76f12dca`）——无独立借鉴面；brush Shift-click 直线登记为蒙版笔刷 UX 小注记（我方笔刷若建，Shift-click 直线是 Lightroom 惯例）。

---

## 增量节（2026-10-25 M9 charter 输入批；+1031，churn 为主 + Upright 主料）

> churn 主体（~900 commits）：docking 移植（craft-libs repin 连环）、egui 0.37 迁移、
> title-bar movable、HEIF/RAW 安全加固（`d00df631`/`b88f72b9` 等 hostile 输入内存
> 预算）、相机 profile 补录（ILCE-7RM5）、依赖刷新。**真主料 = Guided Upright 落地**。
> 正本判定 = `M9-CHARTER-INPUT.md` §2.3。

### Guided Upright（M9 站 3 主料）

- **`crates/pipeline/src/upright.rs`（611 行，MIT OR Apache-2.0）**：①线段检测——梯度
  level-line 方向一致区域（最强梯度种子）+ 加权主轴拟合；②消失点——近垂直/近水平分组
  + RANSAC 线对 + 加权最小二乘（`Σ w·l·lᵀ` 最小特征向量）精化（含无穷远点）；③校正
  ——虚拟相机旋转 `K·R·K⁻¹`（Level 纯旋转；Full 双消失点 + 正交性估焦距）；坐标居中
  归一（lens 校正后，长边/2），分析分辨率无关。
- **Guided 形态**（`fbc927f0`/`7635b38c`）：≤4 条用户导线解同问题；press 画线 + 端点
  拖拽编辑 + 选中删除；G 键开网格、⇧G 开 guided（tests_masking.rs:843）。
- **auto straighten 防呆**（`693c3593` LR-CROP-AUTO）：仅 ≤10° 且 ≥3 一致线才转、
  找不到明说——实测 300 原样片误转 79→19。**判定：站 3 全量候选**——我方几何面 =
  Crop 纯裁切框（CropModule.swift:63-70 无 rotation）+ Flip + Liquify，旋转/拉直/
  透视全缺；`PanoCamera.swift:95 focalFromHomography` homography 基建可复用；
  CPU Float64 构建期一次解 + GPU warp dispatch（Lens warp 同形态）。
- **XMP Upright 警告模式跨导入路径保留**（`7d3cd8af`）：sidecar 互操作细节，注记。

### 其余判定

- **自更新**（craft-update + startup prompt modal `2b931751`）：OQ-M9-6 不入，挂
  UPSTREAM-QUEUE（与 lumen 同判）。
- **安全加固批**（HEIF iloc/重建预算、RAW 解码敌意内存路径、denoise/tiff/merge 有界
  化）：我方 ImageIO/CIRAW 官方解码面攻击模型不同，注记观察；「reconstruction 前预算」
  纪律入未来面。
- **docking/egui/title-bar/craft-libs repin**：UI 框架演进 churn，与我方 SwiftUI 无关。
- **Info 面板多选元数据/关键词/Add Keywords**（`31ec62cd`）：我方 Inspector 元数据面
  已有同域，注记。
