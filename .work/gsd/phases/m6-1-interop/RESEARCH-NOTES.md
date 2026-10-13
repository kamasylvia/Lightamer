# M6-1 RESEARCH NOTES — MCP-09-A 项目级单写者锁 + `--connect` 活实例转发

> Phase = M6-1（ROADMAP §Milestone 6）。裁决面 = 同目录 `M6-1-CONTEXT.md`
> （D-M6-1-1..6 + OQ-M6-1-1..6，全带推荐）。本文 = 设计全文 + 两个姊妹前瞻
> （§5 = M6-3 UltraHDR spike 对照面；§6 = M6-2 process version 设计前瞻）。
> 状态：research 起草完成 → C 档第 1 停待 OQ 裁决。

## 1. 背景与缺口定位

### 1.1 已关闭面（14-1 宿主级，不重做）

14-1 已交付 MCP **宿主级**单写者机制（`App/Sources/Lightamer/MCP/McpEndpointFile.swift`，
14-VALIDATION「研究项 A 关闭」注记）：

- **`mcp-endpoint.lock`** = 写者权原语（flock EX|NB）。五态语义成文并测过：
  ①acquire 成功 = 本进程是写者 ②`EWOULDBLOCK` = 存活持有者 → 只读模式
  （不退出）③持有者退出 → kernel 释放（无清扫代码）④持有者崩溃 → kernel
  释放（O_EXCL+pid 舞蹈**明确不做**——flock 无残留）⑤discovery probe =
  读 json → 试锁；锁成功 = 残留（持有者已死）→ 删 json 视为无服务。
- **`mcp-endpoint.json`** = 发现载荷（schema v1 冻结：transport/host/port/
  pid/startedAt/serverName/serverVersion/auth marker——bearer 真身永不入此
  文件）；同目录 tmp + rename 原子晋升（L009）。
- **`McpEndpointDiscovery.discover()`** 三态：`noEndpointFile` /
  `staleResidueRemoved` / `.alive(info)`。
- 工具面：`requiresWriter` 门 + `imageLiveInEditor` 硬拒（GUI 活图写保护）
  + 20 工具封闭集快照族（19→20，M5-1-03 match_color）。

### 1.2 未决残面（本 phase 正主）

宿主锁只仲裁「**MCP server 实例**」之间；**GUI app 不参与该锁**（GUI 内嵌
宿主持锁，但 GUI 自身的编辑写腿不经它）。残面场景：

| 场景 | 现状行为 | 缺口 |
|---|---|---|
| 无头 `--mcp-http` + 活 GUI 同开同一 `.lalb` 项目 | 无头获宿主锁成功（GUI 若未开 MCP host）；GUI 编辑写 `.lra`（SidecarStore 2s debounce）+ `.lalb` 投影；无头经 `SessionBatchApplier`/MetadataService 写**别的图**的 `.lra` + 投影 | **双写**：两进程各自事务，`.lalb` WAL 能扛进程级但语义面（索引 vs sidecar 真身仲裁、编辑互相覆盖、live 图 stale）无主人 |
| 无头撞 GUI 活图 | `imageLiveInEditor` 硬拒 | 仅覆盖 GUI 当前打开的单图；项目级语义（批量写、关键词批量、preset 批量）不在判据内 |
| 两个无头实例 | 宿主锁仲裁：第二实例只读 | **已覆盖**（14-1），但只读面无项目级指引 |
| GUI 先开 + 无头后起 | 无头不探项目，直接 serve 写 | **双写**同上 |

MCP-09 研究项 A 原文（Phase 14 登记）＝「GUI 与无头 MCP 同会话并发 sidecar
双写对策（WAL 仅覆盖索引层；单写者锁/后开者只读/移交）」——14-1 兑现的是
其中宿主级半边；本 phase 兑现**库/项目级**半边（裁决①立项）。

## 2. LightCraft 范式对照（思想转录，零代码移植预期）

LightCraft（`research/LIGHTCRAFT-NOTES.md` 面 6，MIT OR Apache-2.0 双许可）：

- **库锁**：`catalog.lock` 单写者——第二写者拒并报「already open in process
  N」+ **指引走 connect**。
- **双模式**：headless（内嵌 Session + `--library` 持久库）/ connect（连活 app
  控制通道）。
- 对照转译：LightCraft 的 catalog = 单文件库 = 我们 `.lalb`；它的 connect =
  五前端同缝命令分发，我们无统一命令缝但有 **MCP HTTP 端点发现文件**
  （`McpEndpointDiscovery`）——「connect 指引」在我方的最小忠实形态 =
  指向活实例 MCP 端点，让 agent 直连，而非本进程代理（D-M6-1-3 否决代理臂
  的依据：我方命令面分散于 20 MCP 工具，无 LightCraft 式单缝可代理）。
- **许可级差声明**：LightCraft = MIT OR Apache-2.0——**代码级移植合法**
  （与 darktable GPL-3.0「只读参考不复制」红线不同级），成段移植须 NOTICE
  归属同 commit 登记。本 phase 预期**零移植**：五态 flock 机制我方已有
  （14-1），转译的是范式（项目级锁 + connect 指引语义 + already-open 文案
  结构），实现全部自写。

## 3. 设计

### 3.1 Core 级 `SingleWriterLock` 泛化件（新，`LightamerCore/Sources/Foundation/`）

- 从 `McpEndpointLock` 抽取语义原样泛化：`acquire(paths:) -> Result<Lock,
  AcquireError>` / `probeLockAvailable(paths:)` / `unlock()`；API 形状、
  五态注释、L009 目录纪律逐条继承。App 侧 `McpEndpointLock` 改为薄封装或
  直接换用泛化件（**行为零 diff 门**：McpHostTests 双进程 fixture 全绿原样
  ——plan 期定封装策略，倾向 App 侧 typealias/包装保快照族面零触）。
- 锁文件 payload 载体 `SingleWriterInfo`（Codable，schema v1 冻结拼写）：
  `{schemaVersion, role, pid, startedAt, endpoint?}`；role = `gui|headless`；
  endpoint = 可选 `{transport, host, port, auth}` 镜像（connect 指引直读，
  免二次读 json——两读皆可，plan 期定，倾向复用 `McpEndpointFile.read` 单源
  不镜像）。

### 3.2 项目锁面（`.lalb`）

- 锁文件 = `<stem>.lalb.lock`（`.lalb` 同目录 sibling；项目目录搬移随行，
  五态③自然失效）。**`.lalb` 包内零触碰**（`LibrarySchema` v4 不动；
  `project_meta` 零新行——D-M6-1-5）。
- 接线点：
  - GUI：`ProjectFileStore.open`（或其调用层 `LibraryProjectController`——
    plan 期定注入缝，倾向 store 层持锁对象生命周期）acquire；held →
    `open` 返回 typed 冲突态（带 holder 诊断），UI 层转对话框（§3.6）；
    close / `applicationWillTerminate` 释放（SidecarStore flush 同窗，
    AppDelegate 5s 有界等待先例）。
  - 无头：`McpServerController` headless 分叉（`LightamerEntryPoint`）在
    SessionProvider/Library 装配前 probe；装配参数带项目路径时 acquire。
- 崩溃语义：kernel 自释放，无残留清扫（锁文件本体是 fixture 非证据——与
  `mcp-endpoint.lock` 同）。

### 3.3 legacy Session 锁面（ride-along）

- `LIGHTAMER_LEGACY_LIBRARY=1` 面的 Session 根：`<root>/.lightamer/
  session.lock` 同件。默认面（项目工作区）不可达；MCP 筛选/修图工具
  （SessionIndexStore 系）在 legacy 会话上写时同判。成本 ≈0（同一泛化件
  第二个调用点），语义一致性收益 = 研究项 A 原文「同会话并发」完整闭合。
- 默认项目面与 legacy 面互斥（gate 决定），不叠加。

### 3.4 无头启动仲裁与 `--connect` 指引（D-M6-1-3）

启动序（`--mcp-http` / `--mcp-stdio` 共用）：

```
headless 分叉
  └─ 装配参数含项目/会话路径？
       ├─ 否（无目标面）→ 现行为不变（零回归面）
       └─ 是 → acquire 项目锁
            ├─ 成功 → 现行为（读写 server）——锁对象随装配生命周期释放
            └─ heldByOther →
                 ①读锁 payload + McpEndpointDiscovery.discover()
                 ②stdout 单行 JSON：
                   {"event":"connect-guidance","holderPid":N,
                    "endpoint":{"transport":"streamable-http",
                                "host":"127.0.0.1","port":P,
                                "auth":"bearer|none"} | null}
                 ③stderr 人类可读（zh/en 双语择一，plan 期定——倾向随
                   locale）：「项目已由另一实例打开（pid N）——请连接其
                   MCP 端点 127.0.0.1:P（发现文件 <path>），或关闭该实例
                   后重试。」
                 ④以只读臂继续 serve（OQ-M6-1-3 推荐）；端点缺席 = 指引
                   降级（无 connect 目标，仅告知持有者 pid + 关闭指引）
```

- exit code 约定：只读常驻臂 = 正常 serve 退出码；若 OQ-M6-1-3 裁「立即
  退出」臂 = 专用退出码（plan 期定，如 3）+ 同款 stdout/stderr 指引。
- stdio 宿主注意：stdout 是 MCP 通道（JSON-RPC），指引 JSON 若走 stdout
  会污染 stdio 协议——**stdio 宿主指引走 stderr**（结构化 JSON 同样落
  stderr），HTTP 宿主走 stdout。plan 期把此分叉写死为常量面。

### 3.5 只读 server 臂与错误面（D-M6-1-4）

- `McpToolRegistry` 写类工具（`requiresWriter == true` 集）调用前 probe
  项目锁（非持有式 `probeLockAvailable`）；held → typed 错误
  `projectReadOnly(detail)`（错误码表 additive 一枚；MCP JSON-RPC 错误码
  槽位 plan 期定，建议 -32002 与 `imageLiveInEditor` 同段）。
- 文案双语：「项目由另一实例持有（pid N）——连接活实例 <host:port> 或关闭
  它后重试」；键族 `mcp_error_project_read_only`（xcstrings 尾块纯插入惯例）
  + 工具描述键如有快照影响同批申报。
- `imageLiveInEditor` 硬拒**保留且优先**（更细粒度判据先命中）——两判据
  顺序 = live 图判据 → 项目锁 probe。
- 读类工具零影响（render_preview/list_photos/get_thumbnails 照常——只读
  server 的存在意义）。

### 3.6 GUI 只读回退面（D-M6-1-2/D-M6-1-4，OQ-M6-1-4）

最小只读面（推荐）：

- 撞锁打开 → 对话框三选：**只读打开 / 重试 / 取消**（zh verbatim plan 期
  定稿）；只读打开 = store 装配为只读态（写腿断路）。
- 只读态 UI 面：
  - 顶部（WorkspaceHostView 顶栏位）常驻 banner：「只读——项目已由另一
    实例（pid N）打开」；
  - 编辑入点禁用：Inspector 调整栈、节点图命令（NodeGraphCommand）、
    蒙版编辑、批量 apply、Copy/Paste Adjustments、导出入队、yiyin、
    DRT/Film/LUT 面板写入、版本三命令、历史写项——**禁用清单以
    `EditorState`/`LibraryStore` 写 API 集为准机检**（plan 期出清单表，
    禁用实现倾向单一 seam：只读态 = 写 API 前置 guard，UI 控件
    `.disabled` 投影同源布尔）；
  - 浏览/检索/查看/soft proof/EDR 查看**可用**（只读语义 = 像素与元数据
    零写入）。
- 重试臂：对话框「重试」= 重新 acquire（持有者可能已退出——五态③窗口）。
- 被否形态：纯拒开（用户被迫人肉找另一实例关闭——体验断裂）；完整只读
  工作区重设计（超 M6-1 规模）。

### 3.7 交互矩阵（零回归面盘点）

| 既有面 | 交互 | 处置 |
|---|---|---|
| MCP 宿主锁（`mcp-endpoint.lock`） | 与项目锁**正交两层**：宿主锁仲裁 server 实例，项目锁仲裁库面写权 | 零改动 |
| `imageLiveInEditor` | 更细粒度写拒 | 保留且先判 |
| QuickLook/Spotlight appex | 只读连接（immutable=1 URI 先例，13-1） | **不持锁不 probe**（只读旁路，零触碰） |
| `ProjectFileStore.backup(to:)` | sqlite3_backup 在线拷 | 零变化（锁文件不入包不随备份） |
| 项目移动（整目录搬移） | `.lalb` + Media/ 随行 | 锁文件随行但持有者已死时五态③失效；移动动作本身要求本进程持锁（打开态禁移动——现状语义不变） |
| 崩溃/强杀 | kernel 释放 | 无残留清扫（五态③④） |
| 20 工具封闭集快照族 | 零新工具 | 白名单负测零 diff；错误码 additive 申报 |
| G4 MCP e2e parity | match_color→render 链 | 零影响（单实例正常路径） |
| McpLauncher 一键拉 agent | GUI 持锁 + agent 无头连 GUI 端点 = 正道 | launcher 面若 agent 模板含项目路径，agent 无头实例会撞 GUI 锁 → connect 指引正是其归宿（行为改善非回归）；launcher 文档面顺带注记 |

## 4. 测试与验收设计（对齐 ROADMAP M6-1 验收形态）

1. **真实双进程仲裁 fixture**（`McpHostTests` 双进程先例同型）：父进程
   acquire 项目锁 → 子进程无头启动 → 断言 ①stdout/stderr 指引 JSON 可解析
   ②写类工具 typed `projectReadOnly` ③读类工具照常。反向：子进程持锁 →
   GUI open API typed 冲突态。
2. **只读臂 e2e**：只读 server 全读类工具冒烟 + 写类全拒（错误码/文案断言）。
3. **GUI 只读面走查**：banner 常驻 / 编辑入点禁用清单逐项（AX 断言 + 实机
   截图归 `gui-acceptance/m6-1/`）/ 浏览检索可用 / 重试臂持锁者退出后可
   升级为读写。
4. **零回归门**：McpHostTests 双进程 fixture 原样全绿（宿主锁零 diff）/
   20 工具快照族零 diff / G4 parity 零触 / `Project.swift` dependencies
   零 diff（零新 SPM）/ zh-audit 新键块纯插入。
5. **SC 数字门** = plan 期定（惯例：新增测试法数 + 对账链，预期 Layers/
   Library/App 三 bundle 增量）。

## 5. 前瞻 A：M6-3 UltraHDR spike 对照面（ALCE-03，裁决②）

> 本节 = M6-3 plan 的输入底稿；spike 本体随 M6-3 立，不在 M6-1 执行面。

### 5.1 SDK 实测事实（本批亲验，macOS 27 SDK headers）

- `CGImageDestinationAddAuxiliaryDataInfo(dst, type, dict)` — macOS 10.13+
  （`CGImageDestination.h:399`）；aux dict 三键 = data / dataDescription /
  metadata。
- `kCGImageAuxiliaryDataTypeHDRGainMap` — macOS 11.0/14.1+；
  `kCGImageAuxiliaryDataTypeISOGainMap` — **macOS 15.0+**
  （`CGImageProperties.h:2373-2374`；ISO = ISO 21496-1 语义档）。
- `kCGImageDestinationEncodeGenerateGainMapWithBaseImage` /
  `kCGImageDestinationEncodeGainMapPixelFormatRequest` /
  `kCGImageDestinationEncodeGainMapSubsampleFactor` /
  `kCGImageDestinationEncodeAlternateColorSpace` — **macOS 16+**
  （`CGImageDestination.h:420-423`；可用性宏四参实测解出 = macos(16)）。
- `kCGImageDestinationPreserveGainMap`（AddImageFromSource 透传）— macOS
  11.0/14.1+。

**结论：原生路两臂（auxiliary 自算 gain map / destination 生成 gain map）
均在 macOS 27 底线内，无 OS 门槛障碍。** spike 争的是**容器字节有效性与
语义正确性**（Apple 是否真把 ISO gain map 序列化进 JPEG 容器、第三方可读
性），非可用性。

### 5.2 三路对照（spike 设计骨架）

| 路 | 内容 | 预期 |
|---|---|---|
| A 原生 auxiliary | 我方 DRT-HDR/EDR 链产 HDR 面 + SDR 基面 → 自算 gain = HDR/SDR 比 → `CGImageDestinationAddAuxiliaryDataInfo` + `kCGImageAuxiliaryDataTypeISOGainMap` 挂到 JPEG destination | 容器字节读回验证（同 key 读回 + exiftool + Photos/Preview HDR 渲染目检）；语义全在我方手（ISO 21496-1 字段自控） |
| B 原生 generate | `kCGImageDestinationEncodeGenerateGainMapWithBaseImage`（+ alternate colorspace 键族）让 ImageIO 自生成 | 语义黑盒（基图/替代表示怎么给、gain 从哪算）——spike 探明即定；若可控且容器有效 = 最省 |
| C LightCraft 移植 | 其纯 Rust ISO 21496-1 metadata writer 逐字段转 Swift（MIT/Apache-2.0，NOTICE） | 容器字节完全可控的兜底；A/B 达标则不落 |

### 5.3 判据（M6-3 plan 细化）

- 容器有效性：`CGImageSource` 读回 `kCGImageAuxiliaryDataTypeISOGainMap`
  非 nil + 外部校验（exiftool gain map 字段 / macOS Preview・Photos 对同
  文件 HDR 渲染生效 / 与 LightCraft 参考输出对读）。
- 集成面：`ImageIOEncoders.swift` JPEG 腿 additive（六格式矩阵零改动红线
  ——gain map = JPEG 专属档，其余五格式 typed 不可达说明沿用 ExportICCStrip
  先例文案形）；DRT-HDR 源图（`isHdrEncoding` 单源）端到端。
- 达标即收（裁决④同款纪律）：A 或 B 容器字节达标 → C 不移植（NOTICE 免）。

## 6. 前瞻 B：M6-2 process version 设计前瞻（裁决③）

> 本节 = M6-2 plan 的输入底稿；落点随 M6-2 立。

### 6.1 键面

- `.lra` 文档级 additive 可选键 `process`（Int，拼写 plan 期冻结；命名对齐
  LightCraft `process version` 思想）：
  - **缺键 = legacy = process 0 = 冻结语义**（写腿 `encodeIfPresent`——
    缺键档 re-encode 字节零漂移，LightCraft「legacy 值不序列化故 hash
    逐字节不变」技巧同构；SidecarV9 byte-face 负测钉）。
  - 新档写腿 = 当前 `RenderProcessVersion.current`（Core 常量，起步 = 1）。
- 纪律：**改观感的 iop 语义变更必须 bump `current` 并为旧号保留冻结分支**
  （管线读缝按 process 选代码路径——旧号走旧语义分支）；不改观感的重构
  （性能/内部结构）不 bump。

### 6.2 hash 与缓存纪律（三选，OQ 供 M6-2）

- 推荐**hash 隔离**（`aiProvenance` 先例）：`process` 不折入
  `HistoryHash.hash` / `driftDetected`——它是渲染语义标签非用户像素编辑；
  同理不产生 history item（commit 面零触）。缓存键（`PipeCacheKey`）在
  process 分支真分叉时折 process 值（缺键 = 0 恒，legacy 档键面零变化）。
- 备选 set-fields-move（`drtRecord`/`filmRecord` 先例）被否理由：process
  非「用户改了它」的编辑面，折 hash 会让语义升级误报 drift。
- **schemaVersion 裁点**：升 v10（语义标记键入册）vs additive-in-v9（宽容
  decode 已允许未知键?）——推荐升 v10：v6/v7/v8/v9 每 bump 各承载其键的
  惯例延续；tolerant decode 保 v9 档可读（typed degrade 纪律原样）。

### 6.3 迁移 UX（v1 = 无）

- 老档恒冻结（零漂移承诺本体）；「Update to Current Process」显式迁移动作
  = OQ 挂账（LightCraft 有此动作；我方首个真实消费场景出现〔某 iop 语义
  bump〕时再裁交互形态——面板按钮 vs 预设应用时询问）。
- 首个消费纪律落点：M6 批内任何 iop 调参/语义变更（含 M5 TRACK/Mertens
  后续调优）落地时**必须**同时 bump `current` + 冻结分支 + 负测（同档跨
  bump 渲染逐位不变）。

## 7. 许可与归属

- LightCraft = MIT OR Apache-2.0 双许可（任选其一）：本 phase/前瞻两节均为
  思想与命名转录 + 我方既有机制复用，**零代码移植**；若 M6-3 走 C 路移植其
  ISO 21496-1 writer，须 NOTICE 署名同 commit 登记（`spectral_film_lut`
  NOTICE 先例形）。
- 我方五态 flock / 端点发现 / L009 原子晋升 = 14-1 自有交付，无外部归属面。

## 8. Sources

- 内部：`App/Sources/Lightamer/MCP/McpEndpointFile.swift`（五态正本）/
  `McpServerController.swift`（headless 分叉 + writerLockHeld）/
  `McpToolRegistry.swift`（requiresWriter + imageLiveInEditor + 20 工具面）/
  `McpLauncherPanelView.swift`（`endpointDiscoveryState` 消费面）/
  `LightamerCore/Sources/Library/LibrarySchema.swift`（v4）/
  `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（v9 additive 纪律 +
  hash 隔离/set-fields-move 两先例）/ `LightamerCore/Sources/Export/
  ImageIOEncoders.swift` + `DrtOutputColorSpace.swift`（M6-3 集成面）/
  `phases/m5-1-track/M5-1-VALIDATION.md`（挂账汇编 = M6-5 输入）
- 外部：`/Volumes/UNITEK/Documents/Development/lightcraft`（HEAD `25ef65c`，
  0.7.0；`docs/mcp.md` / `docs/control-protocol.md` / `docs/process-versions.md`）
  ——调研转录正本 = `research/LIGHTCRAFT-NOTES.md` §六
- SDK（macOS 27，本批亲验）：ImageIO `CGImageDestination.h:399/:420-423` +
  `CGImageProperties.h:2373-2374`（§5.1 三键 + auxiliary API 可用性）
