# Phase 14: MCP Server - Context

**Gathered:** 2026-09-28
**Status:** Draft for planning — 12 项 OQ 全按推荐自动裁决〔晨审追认〕（D-14-CONTEXT-1..12，追认清单表见 decisions 末）；研究问题清单另见 `14-RESEARCH-QUESTIONS.md`（P0/P1 分级 + research 首探针项）

<domain>
## Phase Boundary

本 Phase 交付内嵌 MCP（Model Context Protocol）server：远程 AI 经 MCP 协议对本机照片执行 RAW 修图取回预览（MCP-01..04），并支撑外部 AI 自动筛选（culling）——读面（索引查询/缩略图/联系表/ROI 细裁）+ 写面（星级/旗标/色标/备注/关键词写回 sidecar），照片留在 Lightamer 工作流内（MCP-05..09）；GUI launcher 一键拉起 agent（MCP-10）。核心架构事实：

1. **消费面全部已就位，本 Phase 是「接线 phase」不是「算法 phase」**——修图渲染 = `ExportRenderer` 无头链（`LightamerCore/Sources/Export/ExportRenderer.swift:8-27` 编排注释：disk sidecar → instances → ExportChainBuilder → render → encode）第三消费面（QL 先例 `QuickLookRenderer.swift`，13-VALIDATION SC#1「QL parity 逐字节一致」）；筛选读面 = `SessionIndexStore.query`（`SessionIndexStore.swift:561-584`）+ `FilterSQL.translateConjoining`（`FilterSQL.swift:160`）零新翻译层（12 移交③字面兑现）；缩略图 = `SessionThumbnailProvider` 双档（`SessionThumbnailProvider.swift:43-50` tier appointment + has_edits 裁决红线）；写面 = `MetadataService` 六 API（`MetadataService.swift:81/:91/:100/:117/:128/:141`）+ `PresetApplier` 三段同构（`PresetApplier.swift:10-32`）。**零新 iop、零新管线、零新持久化格式。**
2. **MCP-03「渲染一致性」的口径必须诚实钉死**——量化一致的定义域 = **同 sidecar 同参 → 同像素（sRGB 终态编码域）**；GUI 视口是 EDR/显示变换域（08-4 EDR 三 PSO 分叉），不作为 MCP 对齐对象。QL 预览语义先例（13 期「预览=编辑态非导出成品态，无印框」）跨域延续：MCP render_preview 默认同样不带 yiyin 终端印框（export_image 才可选带，EXP-05 共享配置）。文档与工具描述必须写明，防「远程看到的和 GUI 不一样」预期差。
3. **研究项 A（GUI/无头同会话并发 sidecar 双写）是本 Phase 唯一的真架构风险**——SidecarStore 的 per-image actor + 2s debounce（`SidecarStore.swift:32/:41-42`）只保护单进程内单写者；GUI 进程内嵌 server 与无头 server 进程并存 = 两进程两写者。主对策已预裁（D-14-CONTEXT-5）：写面全部走既有单源服务 + GUI-live 图 params 写 typed error + server 单实例端点锁；机制细节 research 终判（RQ-14-3）。**WAL 不解决 sidecar 文件双写**（12-RESEARCH 已证 WAL 只覆盖索引层）。
4. **Catalogs 联动 defer 是 16 期字面裁决，不是本环新裁决**——16-CONTEXT Boundary 不做节原文「MCP 筛选工具的 catalog 求值——MCP-05/06 求值域 = 当前会话（Phase 14 面）；catalog 联动 defer」（`16-CONTEXT.md:23`）+ deferred 节「catalog 求值面就绪后是工具壳增量」（`16-CONTEXT.md:177`）。本 Phase 的纪律 = 不预接、但 FilterDomain 分派缝（`FilterSQL.swift:135-137`）是天然扩展点（D-14-CONTEXT-9）。
5. **依赖面首次扩军是约束修订事件**——官方 swift-sdk（pin 0.12.1）+ 传递依赖（swift-nio/swift-log/swift-system/eventsource）= 全项目**第二个新 SPM 依赖**（第一个 = Swift-WebP，EXP-02）。PROJECT.md 依赖最小化约束「预期仅 libwebp、libavif 两个 SPM 依赖」已因 libavif 砍除 + 本项实际漂移，orchestrator 收口同批修订（同 16 期 PROJECT.md:65 漂移修正先例）。SDK 类型收口在 App 层，**Core 零 import MCP**（工具 handler 经纯 Swift registry 缝，D-14-CONTEXT-1）。
6. **分发形态红利于本 Phase**——DIST-02 Removed（2026-09-27 用户终裁砍 Apple 渠道）意味着 MCP server 无公证/hardened runtime 负担；GitHub 公开仓已立（13-4），**swift-sdk 依赖入公开树 + 端口/token 安全面代码公开 = 安全审计注意项**（token 存储、绑定逻辑走查入验证红线），非阻塞。

**Phase 14 不做**：

- **文件写/删/移动、像素修改写回**——MCP-08 黑体：写回限元数据字段（rating/flag/color/note/keywords）；export_image 是唯一落盘通道且只写 Session/Output 域
- **shell 执行暴露**——EXP-08 post-export actions（脚本/Finder）**不经 MCP 暴露**（server 工具白名单封闭集，D-14-CONTEXT-6）
- **文件上传/下载通道**——无第二网络面；图片只经 base64 inline 与 export_image 落盘两形态（D-14-CONTEXT-4）
- **Catalogs 求值域**——16 期字面 defer（事实 4）；v1 工具求值域恒当前会话
- **match_color 实装**——V2 TRACK colormatch iop 依赖，v1 零实装零 schema 占用（D-14-CONTEXT-11）
- **多版本参数组/历史快照工具面**——研究项 B 判 v2（v1 = history stack append 语义既有，D-14-CONTEXT-11）
- **非回环无鉴权暴露 / 流式进度通知 / 多 catalog / 任意路径写**——安全与范围红线（D-14-CONTEXT-6）；MCP progress notification 机制 v1 不用（同步 req/resp，长渲染超时错误）
- **XMP 三格式（HEIF/AVIF/WebP）内嵌元数据复审**——复审位**关闭**（v1 MCP 元数据真身 = sidecar/lindex，不经文件内嵌 XMP；12 移交②经 13 转记的处置，晨审知悉，见 deferred 留痕）
- **GUI 内嵌 AI 面（B 路）**——MCP-10 裁决原文「app 零 AI 代码；B 路 v2 再议」（ROADMAP §Phase 14 Notes）
</domain>

<decisions>
## Implementation Decisions

> 12 项 = discuss 起草识别的 OQ，全部按推荐项自动裁决〔晨审追认〕。晨间任一推翻 → 回注 planner 重开受影响面（推翻代价见追认清单表）。

### D-14-CONTEXT-1: 协议 = MCP spec 2025-11-25（JSON-RPC 2.0）；SDK = 官方 `modelcontextprotocol/swift-sdk` pin 0.12.1；SDK 类型收口 App 层、Core 零 import
- **裁决**：①协议底座 = MCP 官方规范 2025-11-25 修订（当前 stable latest；JSON-RPC 2.0 报文层）；②SDK = 官方 Swift SDK（`github.com/modelcontextprotocol/swift-sdk`，0.12.1 @ 2026-05-07，**精确 pin**——0.x API churn 期不做范围版本）；③依赖登记 = 全项目第二个新 SPM 依赖（传递：swift-nio/swift-log/swift-system/eventsource；macOS 13+ 满足 27 地板）；④**分层铁律：LightamerCore 零 import MCP/SDK 模块**——工具 handler 定义为纯 Swift 值类型缝（`McpToolRegistry`：工具名 + JSON 输入 schema + `@Sendable` handler → JSON 输出），SDK 类型只在 App 层 `App/Sources/Lightamer/MCP/` 适配器出现；⑤不预写 2026-07-28 RC（stateless core + extensions）适配——spec 升级 = pin 升 + 适配器层修正，registry 缝不动。
- **理由**：官方 SDK 是唯一同时实现 stdio + Streamable HTTP 双传输、随 spec 演进的 Swift 实现；hand-rolled JSON-RPC = 握手/capabilities/tools schema 全自担且 client 兼容性风险自负（违背「能用原生不引第三方」的精神边界——此处原生生态位就是官方 SDK）；registry 缝使 SDK 更换/升级 = 单适配器层替换（D-16-CONTEXT-8「纪律缝非 trait 全家桶」同款反 YAGNI）。
- **Reversibility**: pin 升级 additive；registry 纯 Swift 缝 = 换 SDK 只改 App 适配器；依赖移除路径 = 适配器删除。

### D-14-CONTEXT-2: 一份 server 内核 × 两种宿主 × 两种传输——GUI 内嵌（Streamable HTTP @ 127.0.0.1）+ CLI 无头（stdio 子进程形态为主、HTTP daemon 形态为辅）；端点发现文件协议
- **裁决**：①server 内核（tool registry + 会话状态机）**单实现**，宿主差异只在 App 层装配：a. **GUI 内嵌宿主**（MCP-02 前半）——偏好开关开即启动/关即停，Streamable HTTP 绑 `127.0.0.1`（端口默认随机，绑定成功后写端点发现文件）；b. **CLI 无头宿主**（MCP-02 后半「无 GUI 进程」）——同 binary 启动参数形态（`Lightamer .../Lightamer --mcp` 进程内不进 UI 主循环）：**stdio 传输为主**（agent 把 `.../Lightamer --mcp-stdio` 配成自家 child server，经典 MCP 形态零网络面）、HTTP daemon 为辅（`--mcp-http`，与 GUI 同款绑定纪律）；②**端点发现文件** = `<sessionRoot 外的 app 支持目录>/.lightamer/mcp-endpoint.json`（port/token 指纹/pid/host/health 字段——schema research 定，RQ-14-2），GUI 与 daemon 启动写、退出删，launcher 与外部 client 经它发现端点；③**launcher（MCP-10）路由 = agent 连 GUI 内嵌 HTTP 端点**（发现文件注入模板占位符）——app 进程恒单写者（D-14-CONTEXT-5③锁的持有者）；④多 client 允许（HTTP 并发连接），写工具经 actor 串行（D-14-CONTEXT-5）；⑤无头宿主不加新 Tuist target（同 binary 启动参数分叉；若 headless NSApplication 剥离不可行，回退方案 = 新增轻量 executor target——执行期裁决入 plan DECISIONS）。
- **理由**：stdio = MCP 客户端生态（Claude Code/pi/omp 类 agent CLI）的默认配置形态，覆盖「agent 自管 server 生命周期」场景；GUI 内嵌 HTTP = launcher 单写者前提 + 远程/外部 client 直连入口（MCP-02「外部任意 MCP client 直连与 launcher 双入口并存」字面）；单内核双宿主 = 行为一致性可断言（验证红线）。
- **Reversibility**: 传输形态增删 = 适配器级；端点文件 schema additive；executor target 拆分随时可做。

### D-14-CONTEXT-3: 工具粒度 = 一动词一工具（MCP-01..10 展开 ~18 个）；tools/list 快照断言钉死工具面
- **裁决**：①不合并 mega-tool——工具集封闭枚举：修图面 `load_image`/`apply_params`/`render_preview`/`list_iops`（MCP-01）+ `export_image`（MCP-09）；筛选读面 `list_photos`/`get_thumbnails`/`get_contact_sheet`/`get_detail_crop`（MCP-05）+ `list_bursts`/`get_face_regions`（MCP-07）；筛选写面 `set_rating`/`set_flag`/`set_color_label`/`append_note`（MCP-06）+ `set_keywords`（MCP-09）；预设面 `list_presets`/`apply_preset`/`diff_presets`（MCP-09）；②每个工具独立 inputSchema + 错误码 + 描述文本（zh/en 双语描述进 String Catalog——L025 面）；③**tools/list 快照测试**：工具名集 + inputSchema 键集逐字断言——工具面即安全面，新增/删减工具必须显式改快照（安全审计显式化，验证红线）；④工具描述文本写明语义边界（如 render_preview「编辑态预览，无印框」）。
- **理由**：MCP 客户端（LLM 侧）的选型效率瓶颈在**工具描述质量**不在数量，~18 个恰命名动词工具的 union-free schema 对 LLM 校验/错误归因均优；mega-tool（参数面 union）= schema 膨胀 + 描述失焦 + 错误码混叠；lightroom-mcp 先例（vault 文章筛片流）同为细粒度动词工具。
- **Reversibility**: 工具 additive（快照显式改）；改名 = 破坏 client 配置，v1 起名审慎（`lightamer_` 前缀与否 research 定）。

### D-14-CONTEXT-4: 图片传输 = base64 inline（MCP image content 标准形态）单通道；原图永不 inline；export_image 唯一落盘例外
- **裁决**：①所有图片返回（render_preview/get_thumbnails/get_contact_sheet/get_detail_crop）= base64 inline image content（MCP 标准 `image` content block，JPEG 编码为主）；②**分辨率/格式参数化 + 默认上限表**（research 定数值，RQ-14-8）：render_preview 默认 long edge 1024 上限 4096、get_thumbnails 直读双档既有尺寸、get_contact_sheet cell 默认 256、get_detail_crop ROI 原尺寸上限（超限下采样）——100MP 原图与未下采样 FULL 渲染**永不 inline**（token 效率红线：100 张全尺寸原图不可行，vault 文章方法论同款）；③`export_image`（MCP-09）例外 = 落盘 Session/Output 域（复用 Phase 11 编码 registry + L009 tmp 同目录原子晋升），返回**路径文本**（不 inline 不回传字节）；④不做 URL/预签名形态——无第二 HTTP 文件服务面，远程 client 对本机路径无读取力，inline 是唯一普适通道。
- **理由**：MCP image content = 全 client 通吃形态；token 效率由「服务端先降采样再编码」保证（联系表拼图 = lightroom-mcp 同款 token 策略）；路径引用形态只在落盘场景有意义（export_image 语义本来就是产出文件）。
- **Reversibility**: 上限表数值常量一处；URL 形态可后补（additive 工具参数）。

### D-14-CONTEXT-5: 并发与单写者（研究项 A 主形态预裁）——元数据写走 MetadataService 单源汇合；params 写对 GUI-live 图 typed error；server 单实例端点锁
- **裁决**：①**元数据写**（set_rating/set_flag/set_color_label/append_note/set_keywords）= MCP 与 GUI **同一 MetadataService 单源**（`MetadataService.swift:47`）→ claim 面（`claimMetadataApply` `SessionIndexStore.swift:1177`，live-target 既有保护）→ 天然汇合无分叉；②**params 写**（apply_params/apply_preset）：目标图在 GUI 编辑器打开（PipeCoordinator 活动集判据——research 走查定精确来源，RQ-14-3）→ **typed error**（如 `imageLiveInEditor`，工具描述写明处置：GUI 侧关闭后重试）；未打开 → disk truth compose（`SessionBatchApplier` 段1 读盘）+ 段2 claim + 段3 writer（`PresetApplier.swift:10-32` 同构，apply = paste 语义）；③**server 单实例锁** = 端点发现文件独占创建（O_EXCL/flock 语义 research 定）：GUI 内嵌 server 持锁时，无头实例降级**只读模式**（写工具一律 typed error 指向端点文件里的 GUI 端点——提示 agent 改连 HTTP）；锁空闲时无头实例为写者；④无 GUI 场景（纯无头工作流）= 无头实例即唯一写者，全图可写；⑤server 内部多 client 写 = actor 串行队列（请求级排队，非拒绝）。
- **理由**：双写风险的根 = GUI 内存 doc 与盘 doc 分叉后互相无声覆盖；MetadataService 单源让元数据面**结构性无险**（两入口同汇点）；params 面 GUI-live 拒写把「编辑中图」的所有权钉在 GUI（用户正在拖滑块时 agent 改参数 = 必坏体验）；端点锁把进程级互斥收敛到一个文件原语，WAL/文件监视等复杂方案全不需要。
- **Reversibility**: GUI-live 判据可从「拒绝」放宽为「协商接管」（v2 交互面）；锁机制替换 = 单点。

### D-14-CONTEXT-6: 安全边界（MCP-04/08 字面）——默认 127.0.0.1 硬编码；非回环 = 显式开启 + Bearer token 必须；工具白名单封闭集；load_image 限会话成员
- **裁决**：①**默认绑定 127.0.0.1 硬编码常量**（非「默认值」是「无设置项的底线」）；非回环暴露 = 设置中显式开启 + **Bearer token 必须**（首启自动生成，存储位 keychain 或 0600 文件 research 定，RQ-14-13）+ 文档明示风险（MCP-04「文档明示」字面）；②工具白名单 = D-14-CONTEXT-3 封闭枚举——无 shell 执行（EXP-08 动作不暴露）、无文件删除/移动、无任意路径写、无上传；③**load_image 作用域 = 已打开会话成员**（rel_path 校验；MCP-01「打开 Session/RAW 路径」的收敛解释——v1 不开任意绝对路径读写，用户要修别的图先在 app 开会话）；list_photos/get_thumbnails 等读面天然限当前会话域；④Origin 头校验按 spec 2025-11-25 条款（无效 Origin → 403——SDK 2025-11-25 版已实现该要求）；⑤速率限制 v1 = 渲染类工具并发信号量（串行）即够，令牌桶类不做。
- **理由**：威胁模型 = 本机单用户工具，最大风险是「非回环暴露 + 无鉴权」与「工具面越权到文件系统」；封闭枚举 + 会话域收敛把爆炸半径钉在「当前会话的元数据 + Output 落盘」；token 泄露的最坏后果 = 元数据写 + 会话内读，不含删除/执行。
- **Reversibility**: 非回环开关/token 机制 additive；作用域放宽 = 显式裁决事件（晨审级）。

### D-14-CONTEXT-7: 修图管线落位——render_preview/export_image = ExportRenderer 减法孪生消费面；MCP-03 口径 = 同 sidecar 同参 → 同像素（sRGB 终态编码域）
- **裁决**：①`render_preview` = `ExportRenderer` 无头链（`ExportRenderer.swift:8-27`）的参数化变体：disk sidecar → instances + layer record → ExportChainBuilder（gamma 剥离 + colorout target override）→ 渲染 → **编码为 inline JPEG（尺寸/格式参数化）不落盘**；QL 先例（`QuickLookRenderer.swift`——ExportRenderer 减法孪生 + 有界超时）是形状正本；②`export_image` = Phase 11 编码 registry 全量复用（六格式/ICC/yiyin 可选——**yiyin 默认关，参数显式开**，EXP-05 共享配置语义）；③**MCP-03 一致性口径**：同 sidecar 同参 → MCP render_preview 输出与本地渲染管线（Export golden 族）**量化一致**（像素级/容差口径随 11 期 golden 先例）；GUI 视口（EDR/显示域）不对齐（Boundary 事实 2 诚实条款）；④`load_image` 语义 = 建立 server 侧活动编辑上下文（指向某会话成员 + 载入其 sidecar 视图），`apply_params` = 对该上下文的 history append（非破坏，⌘Z 链自然回退——研究项 B 的 v1 答案）；上下文落盘时机 = apply 即写（经 D-14-CONTEXT-5② 路径）还是显式 commit 工具——research 定（RQ-14-5，推荐 apply 即写 = 与 GUI 语义同构）。
- **理由**：headless 链已被 QL/Export 两个消费面验证过 parity 与隔离性（不触碰 GUI 状态）；一致性口径钉在编码域 = 测试可自动化（QL parity 同款）；render_preview 走 PipeCoordinator/GUI 渲染域会把 EDR 状态、soft proof 状态全部卷进对齐面（不可钉）。
- **Reversibility**: preview 编码参数 additive；上下文落盘时机换制 = 一处状态机。

### D-14-CONTEXT-8: 筛选面落位——list_photos = FilterSQL 直连零新翻译层（12 移交③兑现）；缩略图双档直读；burst = 查询层聚类；脸部 = SkinRegionLocator 复用
- **裁决**：①`list_photos` 入参 = **FilterPredicateGroup JSON 直作 MCP inputSchema**（`FilterPredicate` Codable 已持久化就绪——12 移交③「结构化谓词 JSON 可直作 MCP 工具入参 schema」字面）+ `FilterSQL.translateConjoining`（`FilterSQL.swift:160`）+ `SessionIndexStore.query`（`SessionIndexStore.swift:561-584`）；返回轻量列 = 34 列子集终表（EXIF 轻量列/rating/flag/has_edits/has_thumb 等——MCP-05 黑体字段，逐列终表 RQ-14-7）；分页 = limit + capture_date/path 游标（keyset 形状与 16 期 RQ-16-6 同源）；②`get_thumbnails` = `ThumbnailDiskStore.read` 直读（`ThumbnailDiskStore.swift:75`）+ tier A embedded 腿——**stale 语义**：thumb_state=3（stale）行返回 stale 标记 + 可选触发 tier B 重渲（SessionThumbnailRenderer 注入腿，语义 RQ-14-8 定，推荐默认返回标记不阻塞批量）；③`get_contact_sheet` = 服务端拼图（N×M cell + 可选标注行——评级/文件名短标）单图 base64 返回；④`get_detail_crop` = RAWDecoder 原尺寸解码 + ROI 裁剪（原图像素坐标系入参），下采样上限内联；⑤`list_bursts` = capture_date 间隔阈值 + camera_model 聚类（纯 lindex 查询层 + 内存聚类，阈值参数化默认 2s——research 定，RQ-14-9）；⑥`get_face_regions` = `SkinRegionLocator` 的 Vision 基建复用（`SkinRegionLocator.swift:12`——VNFaceLandmarks2D + person segmentation；**返回脸框坐标**供 get_detail_crop 取脸部细节，批量成本与缓存 RQ-14-10 探针）。
- **理由**：零新翻译层/零新缩略档/零新 Vision 基建——四个「复用黑体」全部有具名落点；burst 聚类是纯查询变换（lightroom-mcp 方法论的 burst 组语义）；脸框 = 联系表 → 脸部细节筛片流的最后一环。
- **Reversibility**: 列终表 additive；burst 阈值参数化；脸框缓存位 additive。

### D-14-CONTEXT-9: Catalogs 集成 = v1 求值域恒当前会话（16 期字面 defer 承接）；FilterDomain 缝保留不预接
- **裁决**：①v1 全部筛选工具求值域 = **当前会话**（`FilterDomain.session`）——16-CONTEXT Boundary 不做节 + deferred 节原文承接（`16-CONTEXT.md:23/:177`），不因 Phase 16 已交付而扩大；②`FilterDomain` 分派缝（`FilterSQL.swift:135-137`）已由 16-1 落地 = catalog 求值的天然扩展点，v1 **不接**（工具 inputSchema 不暴露 domain 参数——暴露即承诺双域行为矩阵）；③catalog 联动 = Phase 14 后的独立增量批（工具壳级——`CatalogIndexStore` 消费 + domain 参数放开 + 16 期查询面联调），届时按增量流程走；④launcher/修图工具与 Catalogs 模式无交互（修图域 = 会话成员，Catalogs 网格打开图 = 路由回会话域——16 期 D-16-CONTEXT-7 既有语义）。
- **理由**：16 期刚闭环（2026-09-27），其查询面/路由面缺真实负载检验；MCP v1 先钉会话域 = 工具行为矩阵减半；分派缝在 = defer 零架构代价。
- **Reversibility**: domain 参数放开 = schema additive + 快照显式改（D-14-CONTEXT-3 机制内）。

### D-14-CONTEXT-10: MCP-10 launcher = 用户自担 shell 命令模板 + 占位符替换 + 端点注入 + 日志面板；动作 app 侧串行
- **裁决**：①偏好存储 = agent CLI 启动命令**模板字符串**（用户自配自担 shell 语义——ROADMAP §Phase 14 Notes「执行用户配置命令的 shell 注入面需文档明示」字面）+ 可选任务 prompt 模板（筛图口径/修图审美方向）；②占位符集最小化：`{{LIGHTAMER_MCP}}`（端点发现文件路径——agent 侧配置经它取 port/token）+ `{{PROMPT}}`（任务模板转义后内联）；默认模板示例（pi/omp）入设置占位文本；③执行 = `/bin/zsh -c "<模板>"` + 环境变量注入发现文件路径（与 EXP-08「Process 直 exec 不经 shell」的差异**显式留痕**：EXP-08 是 app 内置动作故收窄路径制；launcher 命令作者是用户本人，注入面 = 自注入，文档明示即合规——两处纪律不同源不混引）；④日志面板 = agent 进程 stdout/stderr 流式显示（Pipe 读行 → SwiftUI 面板，环形缓冲上限）；⑤**launcher 动作 app 侧串行**（同时至多 1 个 agent 进程；进行中再点 = 拒绝 + 提示）；终止 = SIGTERM 到自家拉起的子进程（§8.5 自家子进程纪律，超时后 SIGKILL 兜底）。
- **理由**：模板 = agent CLI 命令天然含引号/管道/重定向，参数数组化表达力崩；串行 = 研究项 A 对策的前置（两 agent 并发写回无对策）；「零 AI 代码」裁决 = app 只做拉起/注入/显示三件事。
- **Reversibility**: 占位符 additive；模板语法升级向后兼容（旧模板无占位符照跑）。

### D-14-CONTEXT-11: 研究项 B/C 预裁——B（多版本参数组）v1 = history append 既有语义、工具面 defer v2；C（match_color）零实装零占用
- **裁决**：①**研究项 B**：v1 apply_params = 对活动上下文 history stack 的一次 append（非破坏主语义既有——HIST-01/02），「保存/切换/对比参数组」的版本工具面 **defer v2**（needs: 快照存储位 + 命名管理 + 对比渲染三面，非工具壳增量）；MCP 面不暴露 history 遍历工具（undo/redo 语义归 GUI）；②**研究项 C**：`match_color` v1 **零实装、schema 零占用**（工具集封闭枚举不含它——比「预留签名」更干净；V2 TRACK colormatch iop 落地后按 additive 流程进）；登记于 deferred 不进 tools/list 快照；③export_image 的 yiyin 参数位（D-14-CONTEXT-7②）是本预裁的唯一例外形态（可选参数进 schema——因上游 EXP-05 配置面已存在）。
- **理由**：封闭枚举 + 快照断言体系下，「预留未实现工具」= 快照断言自打脸；B 的三面成本是 plan 级非任务级；C 依赖的 iop 不存在，签名预留 = 假 API。
- **Reversibility**: B/C 均为 additive 工具面（快照显式改）；无存量 client 锁定。

### D-14-CONTEXT-12: 波次分解建议 = 4 plans / 3 waves（14-1 底座依赖根先行；14-2∥14-3 可选并行经 planner 裁决；14-4 launcher+收口签核）
- **裁决**（给 planner 的依赖序基线）：**14-1**（server 底座：swift-sdk 集成 + 双宿主双传输 + 端点发现文件 + 单实例锁 + 安全面（绑定/token/Origin）+ `McpToolRegistry` 缝 + tools/list 快照框架 + **stdio hello-world 端到端探针落定**——RQ-14-1 头号探针在此收口）→ **14-2**（修图面：load_image/apply_params/render_preview/list_iops/export_image + MCP-03 parity 专项 + GUI-live 拒写语义）∥ **14-3**（筛选面：list_photos + 图像三件套 + 写五件 + list_bursts/get_face_regions + GUI 缩略图联动走查）——14-2/14-3 Core 面天然正交（渲染域 vs 索引/元数据域），共享 14-1 registry；UI 耦合点仅 launcher 偏好（14-4）——planner 裁决并行度 → **14-4**（收口：MCP-10 launcher + 偏好 UI + 日志面板 + SC 端到端全链（载入 → ≥3 iop → 预览一致 + 筛选读写回环）+ 签核）。
- **理由**：14-1 是全部工具面的依赖根（传输/安全/registry/快照框架），hello-world 探针早落定 = SDK 风险（0.x churn/macOS 27 编译）在工具面前暴露；14-2/14-3 消费面互不触碰（ExportRenderer 域 vs Session 域）；14-4 的 launcher 是唯一新 UI 面 + 端到端是 SC 字面。
- **Reversibility**: plan 边界可并/拆；刚性 = 14-1 先行、14-4 收口含签核。

### 继承定案（非 OQ，上游已论证、下游不得重开）

- **sidecar 恒真身**——MCP 一切写回经既有单源服务面（MetadataService/batch pipeline），server 永不直写 sidecar 文件字节；「照片留在 Lightamer 工作流内」= 写回落 sidecar + lindex + GUI 缩略图联动（MCP-06 黑体）。
- **FilterSQL 单一翻译面**（12 移交③原文）——MCP list_photos 禁止第二翻译层；谓词 JSON = FilterPredicateGroup 直作。
- **批量/事务纪律**——one bulk change = one transaction；批量写回走三段管线语义（段1 内存变换/段2 索引单事务/段3 串行写队列）；万张级操作零像素渲染（PERF-07 语义）。
- **L013 哈希纪律**——跨进程身份一律 StableHash（FNV-1a 64）decimal String；禁 Swift `Hasher`。
- **L009 同目录 tmp 原子晋升**——export_image 落盘腿；禁止 /tmp 跨卷 rename。
- **L014 GPU 读回 fence**——render_preview 读纹理前必须 fence（QL/Export 先例固化）。
- **app 零 AI 代码**（MCP-10 用户裁决）——provider 配置归 agent 自身体系；app 不含任何模型调用/提示词工程。
- **预览语义诚实口径**（13 期 QL 先例跨域）——「编辑态非成品态」：render_preview 无印框；与 GUI 的差异（EDR/soft proof 显示域）在工具描述与文档明示。
- **失败语义**——MCP 错误 = typed error 映射 JSON-RPC error（工具描述列错误码）；永不静默降级（L020 同源）；server 崩溃 = 连接断（client 重连），不吞异常。
- **执行纪律**——`.work/config.toml [gsd]`（auto/paused）每任务边界检查；C 档门控三点停（research 定稿后停 / 每 plan 闭环停 / 签核前停）。

### 验证红线（全 plan 写死，执行期不得放宽）

- **MCP-03 parity 专项**：同 sidecar 同参 → MCP render_preview 与本地渲染（Export golden 族）量化一致；**SC#3 端到端**：载入 DSC00012.ARW → apply ≥3 iop → 取回预览与本地渲染对照（字面 SC）；测试形态沿 QL parity 先例（13-1）。
- **tools/list 快照断言**：工具名集 + inputSchema 键集逐字钉死；新增/删减工具必须显式改快照（安全面变更显式化）。
- **安全断言**：默认绑定 127.0.0.1 实测（无设置可改到底线常量）；非回环未带 token 请求拒绝；Origin 无效 → 403；写面白名单外工具不存在（负例 = 构造越权请求）。
- **写回联动 parity**：MCP set_rating/flag/color/note/keywords → sidecar 真身 + lindex 行 + GUI 缩略图/过滤面同步可见（12 期 MetadataService 测试形态跨入口复用）；批量管线三段语义回归 + live-target 保护负例（GUI-live 图 params 写 typed error；元数据写 claim 面行为不变）。
- **双宿主行为一致性**：stdio 与 HTTP 两宿主跑同一套 handler 测试（registry 缝的单实现证明）；无头实例与 GUI 实例锁互斥断言（后开者只读降级 + 错误指向端点文件）。
- **launcher 注入面**：模板执行哨兵测试（环境变量/占位符替换逐字）；串行断言（第二动作拒绝）；终止只及自家子进程。
- **防空转/L014/L010/L025**：同 09/12/16-CONTEXT 全套；新 UI（偏好/日志面板）zh 键同步（L025 smoke 数字随 suite 报）。
- **回归纪律**：每任务全套 suite 绿（现基线 **1768/11skip/0fail**，08-5 收口批后）；每任务边界查 `.work/config.toml [gsd]`。

### Open Questions 晨审追认清单（12 项全按推荐自动裁决）

| OQ | 裁决一句 | 关键理由 | 推翻代价 | Reversibility |
|---|---|---|---|---|
| 1 SDK/协议 | 官方 swift-sdk 0.12.1 pin + spec 2025-11-25；Core 零 import，registry 纯 Swift 缝 | 唯一双传输官方实现；hand-rolled = spec 漂移自担 | 换 SDK = 适配器 + 握手全重写；SPM 依赖面约束修订需登记 | pin 升级 additive |
| 2 宿主/传输 | 单内核 × GUI 内嵌 HTTP + 无头 stdio 为主；端点发现文件；无头不加新 target | stdio = agent 生态默认；launcher 单写者前提 | 独立 daemon = 第二写者进程，研究项 A 复杂化 | 传输增删 = 适配器级 |
| 3 工具粒度 | 一动词一工具 ~18 个；tools/list 快照断言 | LLM 效率在描述质量；mega-tool schema 膨胀 | 合并后回拆 = client 配置破坏 | 工具 additive |
| 4 图片传输 | base64 inline 单通道；默认上限表；export_image 唯一落盘例外 | client 通吃；token 效率靠服务端降采样 | URL/文件引用 = 远程 client 不可达或第二网络面 | 上限表常量一处 |
| 5 并发/单写者 | 元数据写单源汇合；params 写 GUI-live typed error；端点文件单实例锁 | 双写根因 = 内存/盘 doc 分叉；锁收敛到一个原语 | 直写 GUI-live 图 = 无声覆盖必坏 | 拒绝→协商接管可后补 |
| 6 安全边界 | 127.0.0.1 硬编码；非回环 token 必须；工具封闭集；load_image 限会话成员 | 爆炸半径钉在会话元数据 + Output | 任意路径 = token 泄露即全盘暴露 | 放宽 = 晨审级显式裁决 |
| 7 修图管线 | ExportRenderer 减法孪生；MCP-03 = sRGB 编码域同像素口径 | QL 双消费面已验 parity；EDR 域不可钉 | 走 GUI 渲染域 = 状态耦合 + 口径失钉 | 编码参数 additive |
| 8 筛选面 | FilterSQL 直连零新层；双档直读；burst 查询层聚类；SkinRegionLocator 复用 | 四个复用黑体全有具名落点 | 第二翻译层违 12 移交③ | 列终表/阈值 additive |
| 9 Catalogs | v1 恒会话域；FilterDomain 缝留而不接 | 16 期字面 defer；行为矩阵减半 | v1 接 catalog = 双域矩阵 + 刚交付面缺检验 | domain 放开 = additive |
| 10 launcher | 用户自担 shell 模板 + 占位符 + 日志面板 + 串行 | 用户 = 命令作者（自注入）；串行 = 研究项 A 前置 | 参数数组化 = 模板表达力崩 | 占位符 additive |
| 11 研究项 B/C | B = history append 语义、版本面 defer v2；C = 零实装零占用 | 封闭枚举下预留未实现 = 假 API | B 提前 = 三面 plan 级成本 | B/C 均 additive |
| 12 波次 | 4 plans / 3 waves；14-1 底座含 hello-world 探针；14-2∥14-3 可选；14-4 收口 | SDK 风险最早暴露；两消费面正交 | 串行拉长日历 | plan 边界可调 |

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.work/gsd/ROADMAP.md` §Phase 14（:258-269——Goal/SC#1-7 + Notes：MCP-09 组三研究项 A/B/C / MCP-10 launcher V1 裁决 / 筛选图像 token 效率 / lightroom-mcp 方法论来源）；`.work/gsd/REQUIREMENTS.md` MCP-01..10（:477-488）+ Traceability（:422-431）
- `.work/gsd/phases/12-metadata-presets-lut/12-DISCUSSION-LOG.md`:61-79（**Phase 13 移交清单五条**——③FilterSQL 消费面与 ④`.lightamer-preset` 上游是本 Phase 直接正主；②XMP 例外集复审位经 13 转记，本环处置 = 关闭，见 deferred）
- `.work/gsd/phases/13-system-integration-distribution/13-CONTEXT.md`（:16 移交承接面 / :48 XMP 复审位登记 / :89 34 列 frozen-spelling 契约 / :199 转记 Phase 14 原文）+ `13-VALIDATION.md`（SC#1 QL parity/Spotlight lindex 投影先例 + 分发形态：unsigned/unhardened + CI 零 secrets）——注：13-DISCUSSION-LOG 无终节，13 期移交面以上述两文件为正本（discuss 环重构五条见 14-DISCUSSION-LOG）
- `.work/gsd/phases/16-catalogs-mode/16-CONTEXT.md`（:23 Boundary「MCP catalog 求值 defer」原文 / :177 deferred「工具壳增量」/ D-16-CONTEXT-8 三道缝体例）+ `16-RESEARCH-QUESTIONS.md`（F1-F5 探针事实——keyset 分页形状与 16 期同源）
- `LightamerCore/Sources/Session/SessionIndexStore.swift`（:8-12 真身纪律 / :561-584 query 消费面 / :1074 claimBatchApply / :1177 claimMetadataApply）；`FilterSQL.swift`（:56 排序白名单 / :135-150 FilterDomain + translate 域形态 / :160 translateConjoining）；`FilterPredicate.swift`（Codable 谓词模型——MCP 入参直作）
- `LightamerCore/Sources/Session/MetadataService.swift`（:47 struct / :81-:141 六 API——MCP 写五件 + set_keywords 单源）；`SessionBatchApplier.swift` + `BatchSidecarWriter.swift`（三段管线）；`LightamerCore/Sources/Presets/PresetApplier.swift`（:10-32 apply=paste 同构）+ `PresetsStore.swift`（:73/:109）
- `LightamerCore/Sources/Export/ExportRenderer.swift`（:8-27 headless 编排 + 注入器缝）/ `QuickLookRenderer.swift`（减法孪生 + 有界超时正本）；`SessionThumbnailProvider.swift`（:43-50 tier appointment）/ `ThumbnailDiskStore.swift`（:75 read）；`LightamerIOP/Sources/SkinSmooth/SkinRegionLocator.swift`（:12 Vision 基建）；`SidecarStore.swift`（:32/:41-42 actor + debounce）
- `App/Sources/Lightamer/UI/LightamerApp.swift`（:39-65 AppDelegate flush / :1087 Settings 挂点）+ `SettingsView.swift`（偏好 UI 载体）+ `State/PipeCoordinator.swift`（GUI-live 活动集判据源，RQ-14-3 走查）
- `AGENTS.md`（Phase 执行模型 + 暂停机制 + Conventions）+ `LESSONS.md` L009/L010/L013/L014/L020/L025/L031
- `.work/GOAL-STATE.md`（:89 Phase 14 开环指令 + Phase 12/13 续接上下文）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **渲染域**：`ExportRenderer` headless 全链（disk truth → ExportChainBuilder → renderToEncodedBitmap → encode）——render_preview 主体只差「不落盘改 inline」与「尺寸参数化」；`QuickLookRenderer` 证明减法孪生 + 有界超时形态；Export golden 测试族 = MCP-03 parity 的直接基建。
- **查询域**：`SessionIndexStore.query(groups:sort:limit:)` + `FilterSQL.translateConjoining` + `FilterPredicateGroup`（Codable）——list_photos 三件套现成；`FilterSortKey` 白名单枚举 = ORDER BY 注入面既有守卫（`FilterSQL.swift:56`）。
- **写域**：`MetadataService` 六 API（GUI/MCP 同源汇合）+ `claimBatchApply`/`claimMetadataApply`（live-target 保护）+ `BatchSidecarWriter` 串行队列——写回面零新代码。
- **图像资产域**：双档缩略图（`ThumbnailDiskStore.read` 直读 + tier A embedded 腿）+ `RAWDecoder`（detail crop 解码腿）+ contact sheet 拼图（CoreGraphics 绘制，新代码但纯 CG 无管线风险）。
- **Vision 域**：`SkinRegionLocator`（landmarks + person seg）——get_face_regions 复用其请求编排，只取脸框输出。
- **进程域**：`Process` 直 exec 先例（EXP-08 `PostExportActions.swift`）+ Pipe 读行形态——launcher 执行腿模板；`AppDelegate.applicationWillTerminate`（`LightamerApp.swift:65`）= server 优雅停机钩子位。

### Integration Points

| 上游面 | Phase 14 落位 |
|---|---|
| FilterSQL/SessionIndexStore（Phase 12/16） | D-14-CONTEXT-8：list_photos 直连；domain 缝留而不接（D-14-CONTEXT-9） |
| MetadataService + 批量管线三段（Phase 9/12） | D-14-CONTEXT-5：写五件单源汇合；GUI-live 拒写语义 |
| PresetApplier/PresetsStore（Phase 12） | D-14-CONTEXT-5②/7：apply_preset 三段同构；list_presets/diff_presets 读 PresetsStore |
| ExportRenderer/QuickLookRenderer（Phase 11/13） | D-14-CONTEXT-7：render_preview/export_image 消费面；MCP-03 parity 基建 |
| SessionThumbnailProvider 双档（Phase 9） | D-14-CONTEXT-8：get_thumbnails 直读 + stale 标记语义 |
| SkinRegionLocator（Phase 7） | D-14-CONTEXT-8⑥：get_face_regions 脸框输出 |
| ExportQueue/编码 registry（Phase 11） | D-14-CONTEXT-7②：export_image 编码/L009 晋升复用 |
| 16 期 Catalogs 面 | 不动——defer（D-14-CONTEXT-9）；v2 工具壳增量入口 |

</code_context>

<specifics>
## Specific Ideas

- **执行顺序刚性**：14-1（底座+探针）→ 14-2（修图）∥ 14-3（筛选）→ 14-4（launcher+收口）。RQ-14-1 的 stdio hello-world 探针是全 Phase 第一任务——SDK 在 macOS 27/Tuist 工程的编译与并发语义不过关，一切工具面划界重谈。
- **research 头项三探针**（详见 RQ 文件）：①swift-sdk 集成探针（SPM 依赖图/双传输 hello-world/headless 进程可行性）；②MCP-03 parity 初测（ExportRenderer 参数化变体 vs golden）；③base64 尺寸预算表（四档图像工具的默认分辨率 × JPEG 质量 → 字节/token 估算表）。
- **C 档门控**：research 定稿后停（用户过目 Open Questions 裁决点）→ 每 plan 执行+验收闭环后停 → 签核（VALIDATION）前停。worker 每任务边界查 `.work/config.toml [gsd]`。
- **server 代码落位**：`App/Sources/Lightamer/MCP/`（适配器 + registry 装配 + 宿主形态）——server 需要 GUI 状态（PipeCoordinator 活动集）与 Settings；Core 零 import SDK（D-14-CONTEXT-1 铁律）；无宿主 target 新增（同 binary 启动参数；executor target = 回退方案，执行期裁决）。
- **「GUI-live 拒写」的用户体验条款**：typed error 文本必须给 agent 可执行的处置指引（「图像在 Lightamer 编辑器中打开；请让用户关闭后重试，或改用 GUI 操作」）——错误文本也是工具描述的一部分（zh/en 键）。
- **执行期决策边界**：端点发现文件精确 schema 与存储位、token 存储位（keychain vs 0600 文件）、contact sheet 标注渲染细节、日志面板 UI 形态、stdio/HTTP 宿主的 server info/capabilities 声明、工具命名前缀——标注执行期决策入各 plan DECISIONS，不臆造。
- **PROJECT.md 依赖最小化约束漂移修正**（事实 5）挂 orchestrator 收口批，不进 worker plan；swift-sdk 入公开仓的安全审计注意（绑定/token 代码走查）入 14-4 走查批。

</specifics>

<deferred>
## Deferred Ideas

- **Catalogs 求值域**（list_photos domain 参数 + CatalogIndexStore 消费 + 组织树/集合谓词）——16 期字面 defer；工具壳级增量批
- **match_color 工具**（研究项 C）——V2 TRACK colormatch iop 依赖；落地后 additive 进封闭集
- **多版本参数组/历史快照工具面**（研究项 B）——快照存储/命名管理/对比渲染三面，v2 plan 级
- **GUI 协商接管 GUI-live 图**（D-14-CONTEXT-5 拒写 → 协商/排队/接管交互）——v2 交互面
- **流式进度通知**（MCP progress notification——长渲染/批量进度推送给 client）——spec 机制现成，v1 同步 req/resp 先行
- **非回环 TLS / 令牌桶限流 / 多 server 实例管理面**——安全增强 additive 位
- **history 遍历工具（undo/redo/get_history）**——语义归 GUI；v2 与研究项 B 同批议
- **WebP 内嵌 XMP mux**（11 期 EXP-02 注记复审位）——MCP export_image 沿用 11 期 WebP 元数据降级注记（Swift-WebP 零 mux 面），不新增工作；真实需求出现时随 11 期位复审
- **XMP 三格式内嵌元数据复审（12 移交②经 13 转记）**——**本环关闭**：v1 MCP 元数据真身 = sidecar/lindex，读写全程不经文件内嵌 XMP；复审条件（MCP 需三格式内嵌元数据载体）不成立，留痕备查

</deferred>

---

*Phase: 14-MCP Server*
*Context gathered: 2026-09-28（discuss 起草；12 项 OQ 全按推荐自动裁决〔晨审追认〕——用户晨间任一推翻即回注 planner 重开受影响面；RQ 清单与 research 探针项见 14-RESEARCH-QUESTIONS.md）*
