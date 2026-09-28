# Phase 14: MCP Server — Research（14-RESEARCH）

**Written:** 2026-09-28
**Status:** Draft for planning — RQ-14-1..15 全部作答；★探针四项实测完成（swift-sdk 双传输 + headless / flock 锁原语 / base64 预算表 / Vision 吞吐），探针数字在案
**输入:** `14-CONTEXT.md`（D-14-CONTEXT-1..12）+ `14-RESEARCH-QUESTIONS.md` + ROADMAP §Phase 14（:258-269）+ REQUIREMENTS MCP-01..10（:477-488）+ 复用底座源码走查（SessionIndexStore / FilterSQL / MetadataService / ExportRenderer / QuickLookRenderer / SidecarStore / PipeCoordinator / LightamerApp / ModuleInstance / HistoryStack / PresetsStore / PresetApplier / SessionIndexSchema / FilterPredicate）

---

## §0 探针执行摘要

探针环境：macOS 27.0（arm64）、Xcode 27.0 / Swift 6.4（swiftlang-6.4.0.34.1）。探针工程 `/tmp` 即弃（一次性 SPM 工程，非仓内分支）；数字与代码形状记录于下，探针要点代码内嵌各节。

| 探针 | RQ | 结果 | 关键数字 |
|---|---|---|---|
| ★1 swift-sdk 0.12.1 集成 + 双传输 + headless | 14-1 | **全通** | 干净全量构建 78.5s（含 swift-nio 全家）；stdio 三步握手+调用 ✓；Streamable HTTP 端到端（SDK 自带 client 对打）✓；Origin 非法→403 ✓；纯 Swift 无 UI 进程 libsqlite3 建/开 v2 `.lindex` + WAL + 34 列读写 ✓ |
| 锁原语两进程 | 14-3 | **全过** | flock 互斥 ✓；持有者退出即释放 ✓；持锁进程 `exit(9)` 崩溃→内核自释、后继立即获锁（零残留处置代码）✓ |
| ★3 base64 预算表 | 14-8 | **出炉** | render_preview 默认候选 1024px/q80 = 106KB JPEG → 141KB base64 ≈ 1400 视觉 token；4096px/q90 = 4.13MB / 5.5MB / 22.4K token（上限表必要性证实）；20 格联系表 @256/q80 = 319KB ≈ 2000 token；100 缩略 @360 = 3.65MB base64（需分页） |
| ★4 Vision faceLandmarks 吞吐 | 14-10 | **出炉**（无脸 fixture） | warm 单图 3.9ms @1024²；串行 100 张 389ms；8 路并发 152ms（2.56×）；万张串行外推 ~39s → 按需 per-request 裁决成立 |

**探针局限（诚实标注）**：①Vision fixture 无真实人脸——检测主干成本有效，landmark 精化增量待 14-3 用真实人像样张补测；②MCP-03 像素级 parity 初测未跑（需完整 app 构建 + 真实 RAW + Export golden 族）——形状钉板已完成（§RQ-14-4），初测钉为 14-2 首任务；③「同 binary SwiftUI `@main` 分叉」未在主 app 实测（探针只证了「无 SwiftUI lifecycle 的纯 Swift 进程」腿）——钉为 14-1 首任务，executor target 回退方案在案。

---

## §RQ-14-1 swift-sdk 0.12.1 集成 + 双传输 + headless 进程（P0 ★探针）

### ① SPM 依赖图与编译实况

- **SDK 结构**：0.12.1 单产品 `MCP`（`mcp-swift-sdk`，platforms macOS 13+ 满足 27 地板）；传递依赖 4 个：swift-system / swift-log / eventsource（mattt）/ **swift-nio**（≥2.65）。swift-docc-plugin 是根依赖但在库 target 之外（可被消费方忽略）。
- **编译**：探针工程（MCP + NIOCore/NIOPosix/NIOHTTP1）干净全量 **78.5s**（依赖一次编译后，探针增量 1.2-12s）。Swift 6 严格并发全开（`StrictConcurrency` upcoming feature）——主 app Swift 6 模式兼容。
- **⚠️ 依赖面新发现（planner 必读）**：**SDK 的 HTTP server transport 不自带 HTTP listener**。`StatefulHTTPServerTransport` 是框架无关的 `handleRequest(HTTPRequest) -> HTTPResponse` 纯函数面——绑 127.0.0.1 需要**调用方自搭 NIO 适配腿**（`ServerBootstrap` + `configureHTTPServerPipeline` + SSE 泵，形状正本 = SDK 自带 conformance server `Sources/MCPConformance/Server/HTTPApp.swift`，约 250 行）。因此 swift-nio 不是「SDK 内部实现细节」而是**主 app 的真实编译依赖**（App 层适配器 import NIOCore/NIOPosix/NIOHTTP1）。PROJECT.md 依赖漂移修正（CONTEXT 事实 5）把 swift-nio 一并登记。

### ② stdio hello-world 端到端（实测）

`StdioTransport` = newline-delimited JSON-RPC 2.0 on stdin/stdout。管道灌入四条消息实测回包：

```
→ initialize  (protocolVersion "2025-11-25")
← {"capabilities":{"tools":{"listChanged":false}},"protocolVersion":"2025-11-25","serverInfo":{...}}
→ notifications/initialized
→ tools/list
← 两个工具（name/description/inputSchema/annotations 完整回显）
→ tools/call count_images
← {"content":[{"text":"rows=2","type":"text"}]}
```

server 起法：`try await server.start(transport: StdioTransport())` 后挂常驻 Task（探针 sleep loop）。**协议版本常量**：SDK 支持 2025-11-25 / 2025-06-18 / 2025-03-26（`Versioning.swift:10-13`），latest = 2025-11-25 = CONTEXT 钉的 spec 修订，吻合。

### ③ Streamable HTTP 端到端 + Origin 行为（实测）

- **端到端**：`StatefulHTTPServerTransport` + 自搭 NIO 腿 + SDK 自带 `HTTPClientTransport`（URLSession）对打：`connect()` → initialize（proto 2025-11-25 回显）→ tools/list → tools/call `rows=2` → disconnect，exit 0。每个 JSON-RPC 请求的响应走 **request-scoped SSE 流**（`handleJSONRPCRequest` 返回 `.stream`）——适配器必须把 `AsyncThrowingStream<Data, Error>` 泵进 HTTP chunked body（探针首版漏泵 → client 挂死；conformance server 的 `writeResponse` stream 分支是正确姿势）。
- **Origin/Host 校验（SDK 内置，探针实测）**：默认 pipeline = `OriginValidator.localhost()` + `AcceptHeaderValidator(.sseRequired)` + `ContentTypeValidator` + `ProtocolVersionValidator` + `SessionValidator`。
  - `Origin: http://evil.example.com` → **403** ✓（MCP-04 spec 条款兑现，无需自写）。
  - 无 Origin（非浏览器 agent client）→ 放行（Origin 仅存在时校验）——agent CLI 场景的主形态。
  - ⚠️ **匹配规则**：`localhost(port: nil)` 的模式是 `http://localhost:*`——`*` 匹配**任意端口但要求端口存在**；`Origin: http://localhost`（无端口）被拒。工具文档/示例须写带端口 origin。
  - Host 头校验：`127.0.0.1:*`/`localhost:*`/`[::1]:*`，不匹配 → 421（DNS rebinding 防护）。
- **⚠️ 单 transport = 单 session（实测踩到）**：`StatefulHTTPServerTransport` 实例在首个 initialize 后进入已初始化态，第二个 initialize → 400 "Session already initialized"。**多 client 并发 = HTTPApp 层 per-session transport 字典**（每 client 一次 initialize → 新建一个 transport 实例 + SessionContext；conformance server `HTTPApp` 的 sessions 字典就是该模式）→ 14-1 的装配面照此设计。
- **Bearer token**：SDK 内置 `BearerTokenValidator` 面向 OAuth 2.0 Protected Resource（JWT + `aud` 校验）。**静态共享 token 场景 SDK 无现成 valve**——自写一个轻量 `HTTPRequestValidator`（查 `Authorization: Bearer <共享串>`，SecRandom 生成、常量时间比较）进 `validationPipeline` 即可，约 30 行。设计结论见 §RQ-14-13。
- **测试基建红利**：SDK 自带 `InMemoryTransport`（client/server 进程内对连）——「双宿主行为一致性」验证红线可以第三形态兑现：同一 registry 内核 × InMemory × 单测进程内全断言，比拉两个真宿主便宜得多。

### ④ headless 进程可行性（实测 + 边界）

- **已实测腿**：探针 = 纯 Swift 可执行（无 SwiftUI/AppKit lifecycle）+ libsqlite3（`import SQLite3` + linker `sqlite3`）：按 `SessionIndexSchema.swift:114-151` 冻结 DDL 建 `.lindex` → WAL 开启（`-shm`/`-wal` 伴生出现，与主 app 形态一致）→ 事务插 2 行 → 34 列 SELECT 读回 `SQLITE-OK rows=2`。同一进程内 MCP server（stdio 与 HTTP 两形态）调 `count_images` 工具读同一文件成功。**结论：无 GUI 进程跑 server + 读索引，技术上无阻塞。**
- **未实测腿（14-1 首任务）**：主 binary 是 SwiftUI `@main struct LightamerApp: App`（`LightamerApp.swift:119-120`）。headless 分叉的推荐做法 = 把 `@main` 从 struct App 上摘下，换成自定义入口 enum 的 `static func main()`：检测 `CommandLine.arguments` 含 `--mcp-stdio`/`--mcp-http` → 不构造 `LightamerApp`、不进 `NSApplication.run`，直接装配 server 内核 + `dispatchMain()` 式常驻；否则 `LightamerApp.main()` 走 GUI。风险点（executor 回退判据）：`@NSApplicationDelegateAdaptor` 与 `@Observable @State` 的初始化是否被完全绕开（静态 main 分叉不构造 App struct 即不触碰它们——预期可行，需实机构建验证）；Settings/偏好读取不依赖 App scene（UserDefaults 直读）✓。**回退方案**：新增轻量 executor target（同 13-1 appex 先例）——代价 = Tuist target + 装配代码共享层抽取，执行期裁决入 14-1 DECISIONS。

### ⑤ 0.x API churn 实证（pin 升级成本基线）

探针踩到的 0.12.1 行为变更（升级 0.10→0.12 谱系的真实样本）：
1. `client.connect(transport:)` **自动执行 initialize 握手并返回 `Initialize.Result`**（`Client.swift`："Automatically initialize after connecting"）——connect 后再显式 `initialize()` = 二次 initialize，stateful transport 直接 400（探针实测）。
2. `Tool.Content.text(_:)` deprecated → `.text(text:_meta:)` 形态（编译警告踩到）。
3. `HTTPClientTransport` init 带 `authorizer`（OAuth flow）/ `requestModifier` / `sseInitializationTimeout`。
4. `Server` 是 actor；handler 注册 = `withMethodHandler(ListTools.self/CallTool.self)` 泛型闭包；`Tool.annotations`（readOnlyHint/destructiveHint/idempotentHint）原生支持——MCP 安全审计显式化的 SDK 级载体（写面工具标 destructiveHint，读面标 readOnlyHint）。

**结论**：API 面足够且双传输齐备，pin 0.12.1 可行；registry 纯 Swift 缝（D-14-CONTEXT-1④）使适配器薄——14-1 可交付。

---

## §RQ-14-2 端点发现文件协议（P0）

**文件布局**：`<AppSupport>/Lightamer/mcp/mcp-endpoint.json`（App 支持目录**全局一份**，非 per-session——会话切换不换端点；与 SmartAlbumStore/YiyinFontStore 的 app 级资产三拆模式对齐）。schema（additive 起点）：

```json
{
  "schemaVersion": 1,
  "transport": "streamable-http",
  "host": "127.0.0.1",
  "port": 51234,
  "pid": 4242,
  "startedAt": "2026-09-28T09:00:00Z",
  "serverName": "lightamer",
  "serverVersion": "1.0.0",
  "auth": "none"
}
```

- `auth`: `"none"`（回环默认）| `"bearer"`（非回环；token 真身不入文件——见 §RQ-14-13）。
- **锁与发现文件是两个工件**（对 CONTEXT D-14-CONTEXT-2② 的细化）：`mcp-endpoint.lock`（flock，**写者权**原语——GUI 内嵌宿主与无头宿主都持）+ `mcp-endpoint.json`（**发现**载荷——只有带网络端点的宿主才写）。
- **写删时序**：启动 = flock(`endpoint.lock`, EX|NB) 成功 → 绑端口 → 写 json（原子写，L009 同目录 tmp）→ 服务；优雅停机（偏好关 / `applicationWillTerminate` `LightamerApp.swift:65`）= 删 json → unlock → 退出；**崩溃残留**：json 残留但 flock 内核已自释（探针 T5）——发现方协议 = 读 json 后先 `flock(NB)` 试锁，**试锁成功 = 残留文件（持有者已死）→ 清理并按无服务处理；失败 = 活服务在**。pid 字段仅作诊断展示，不作存活判据（pid 复用风险）。
- **stdio 宿主：不写 endpoint.json（修正 RQ 原推荐）**。stdio 的「端点」就是自身 stdin/stdout，生命周期归 agent 父进程，发现文件无消费方；但它**必须持 flock**（写者权与传输形态无关）。launcher 只路由 HTTP 端点（D-14-CONTEXT-2③ 不变）。
- **server info / capabilities 两宿主同一份**（单内核）：name=lightamer、capabilities 只声明 `tools`（v1 无 resources/prompts/logging）；`tools.listChanged=false`（封闭集，无变更通知）。

---

## §RQ-14-3 研究项 A 终判——单写者机制与 GUI-live 判据（P0，锁探针在案）

1. **GUI-live 判据精确来源**：`PipeCoordinator`（`@MainActor final class`，`PipeCoordinator.swift:78-79`）的 `currentImageURL`（:175，当前编辑器加载图 URL）与 `currentImageID`（:107）。**判据 = 目标图 URL == `currentImageURL` → 拒**（「打开中」一级，不区分脏/拖动中——与 RQ 推荐一致；`isEditingContinuous`（:149）只影响 GUI 自身 history 折叠，不进判据）。MCP 适配器在 App 层可 MainActor-hop 读该字段（与 `terminateHandler` 同款 `MainActor.assumeIsolated` 姿势，`LightamerApp.swift:49-52`）。无头宿主无 PipeCoordinator = 无此约束，全图可写。
2. **锁原语终判 = flock**（探针五态全过）：两进程 EX 互斥 ✓；持有者正常退出即释放 ✓；**持锁进程崩溃（exit 9）→ 内核自释、后继立即获锁** ✓——RQ 倾向「flock 无残留」实测证实，O_EXCL + pid 校验自愈舞步整段不需要。
3. **后开者只读降级**：无头（或第二实例）flock 失败 → 只读模式启动。`tools/list` **不变**（快照断言跨模式恒定；错误在 call 时给）；五个写工具 + apply_params/apply_preset/export_image 返回 typed error `serverReadOnly`，错误文本携带端点文件路径（agent 改连 GUI HTTP 端点或请用户关 GUI）。
4. **SidecarStore 汇合确认**：MCP 写走 `MetadataService`（`MetadataService.swift:47`）三段（段1 disk compose :174-215 / 段2 `claimMetadataApply` `SessionIndexStore.swift:1177` / 段3 `BatchSidecarWriter` 串行队列 :239-241）与 `SessionBatchApplier`（params 面）——**两条既有汇合点，不经 SidecarStore 直写，无第三写路径**。SidecarStore 的 2s debounce（`SidecarStore.swift:41-42`）只服务 GUI 单图编辑流，与 MCP 面正交。GUI-live 拒写保证「GUI 内存 doc 与盘 doc」永不双双存活于同一张图。
5. **MCP render 读一致性**：sidecar 读 = `ExportRenderer.readDocument`（`ExportRenderer.swift:435-439`）单次 `Data(contentsOf:)` + decode——SidecarStore 写是同目录 tmp 原子晋升（`SidecarStore.swift:146-180`），读到的是**完整旧版或完整新版，无半新半旧**。2s debounce 窗口内 MCP 读到「最近一次落盘态」——工具描述明示「render_preview 反映已保存的编辑态」（诚实条款，非 bug）。
6. **GUI 可见性联动（14-3 走查项）**：MCP 元数据写 → lindex 行即时更新（claim 事务）→ 浏览器网格 badge/过滤面经既有刷新缝同步；**编辑器当前打开图的 inspector 行是否跟随**需走查（claim 面不推 GUI 状态对象）——走查入 14-3，不阻塞划界。

---

## §RQ-14-4 render_preview 形状与 MCP-03 parity 测试形态（P0 ★探针-形状钉板）

1. **形状正本已存在——render_preview ≈ 零新渲染代码**：`QuickLookRenderer.renderedPlane(imageURL:targetLongEdge:metal:registry:decodeLeg:)`（`QuickLookRenderer.swift:211-307`）正是「ExportRenderer 减法孪生」的参数化形态：disk sidecar（`readDocument`）→ `ExportChainBuilder.exportChain(from:target:.sRGB, linearVariant:false)`（gamma 剥离 + sRGB 显示终端 override）→ routed pipe render @ `targetLongEdge`（`$routesToExportQueue`，L031）→ fresh `CIContextPool` exit leg（R8/L014 fence 固化在源）→ `packedRGBA8`。MCP 工具腿 = `renderedPlane` → `image(from:)`（:311-314，`ImageIOEncodeCore.makeCGImage`）→ **JPEG 编码为 Data（ImageIO）→ base64**。与 `preview()` 的差异点：**不走 embedded-preview fallback**（:129-137 的降级是 QL 永不崩条款；MCP 要 typed error `renderFailed`）——直接消费 `renderedPlane` 而非 `preview()`。
2. **尺寸参数插位**：`targetLongEdge` 即 render 目标（管内 long-edge，渲染即目标尺寸——非渲染后 CGImage 缩放），与 QL「caller's long edge IS the render target」一致（:265-266 注释）。**parity 门钉在「同尺寸同参」域**（targetLongEdge = golden 尺寸时逐像素/容差对照），缩放域只做内容断言——RQ 推荐维持。
3. **超时**：`boundedWait(seconds:)`（:438-454）现成；`renderTimeout = 30s`（:69，QL 5.44s worst ×5.5）——MCP render 类超时表取同一常数（§RQ-14-14）。超时 = typed error（不降级 embedded preview）。
4. **MCP-03 parity 测试形态**（沿 13-1 QL parity 模板）：同 sidecar 同参下 `renderedPlane` 输出 vs Export golden 族同尺寸成员对照（字节面/容差口径随 11 期 golden 先例）。**像素级初测本环未跑**（需完整 app 构建 + 真实 RAW + golden 基建在测程内）——钉为 14-2 首任务 T1，通过即 SC#3 的自动化腿。

---

## §RQ-14-5 apply_params / 工具面 schema 设计（P0，最难 schema 面）

1. **入参形状终判（模块级 upsert，非整栈替换）**：

```json
{
  "relPath": "DSC00012.ARW",
  "ops": [
    { "opName": "exposure", "multiPriority": 0,
      "params": { "stops": 0.3 }, "enabled": true }
  ]
}
```

   - 每 op 按 `(opName, multiPriority)` 寻址（`ModuleInstance.swift:51-58`——multiPriority 序数 + multiName 人读辅助；`id` UUID **不暴露**，跨进程无意义）。upsert = 同键替换 `params`（不存在则新增实例）；`enabled` 可选翻转；`"remove": true` 可选删实例。整栈替换走 `apply_preset` 通道（PresetApplier = paste 语义），reset 单模块 = `ops` 带该 op 默认 params——**三动词合一工具，不拆**。
   - `params` JSON → 模块 `Params` Codable 直映（`ParamsCoding` 既有编码域）；未知 opName → typed error `unknownOp`（unknown-op degrade 管线已兜底降级，写面拒绝更早）；类型不匹配/越界 → `invalidParams`（decode 失败即拒）。
2. **活动上下文裁决：推荐无状态化（与 CONTEXT D-14-CONTEXT-7④ 的「活动上下文」提法有出入，planner 裁决）**：`apply_params` **必带 relPath**（server 侧无会话级活动句柄）；`load_image` 退化为**读面工具**（校验会话成员 rel_path + 返回该图 sidecar 当前 instances/图层摘要视图）。理由：①RQ-14-14 的「两 client 轮流 load_image 上下文互踩」难题**整段消解**（无状态 = 无归属问题）；②apply 即写（三段管线）下上下文句柄无落盘时机问题（RQ-14-5③ 的 apply 即写 vs commit 工具二选一直接消失）；③幂等重试安全（agent 超时重放同参数无害）。代价：每次调用带 relPath 的微小冗余。若 planner 保留有状态上下文：上下文全局单份 + 后 load 覆盖前 + 错误面提示（CONTEXT 语义），超时不回收。
3. **GUI-live 拒写**：目标 relPath ∈ PipeCoordinator 活动集（§RQ-14-3 判据）→ typed error `imageLiveInEditor`，描述文本给处置指引（「图像在 Lightamer 编辑器中打开；请让用户关闭后重试」zh/en 双语键，L025 面）。未打开 → `SessionBatchApplier.apply`（disk truth compose + claim + 串行写，`PresetApplier.swift:105-117` 同构直复）。
4. **错误码表**（apply_params/list_iops 共用骨架）：`unknownOp` / `invalidParams`（含 op 名+键名定位）/ `imageLiveInEditor` / `notSessionMember`（rel_path 越界）/ `serverReadOnly` / `renderFailed` / `renderTimeout` / `exportFailed`。

---

## §RQ-14-6 list_iops（P0）

- 返回面 = `ModuleRegistry` 遍历：`opName` / display 名 / `iopOrder`（v50 序）/ **`version`**（`ModuleInstance.swift:66` 既有字段，agent 缓存失效键——RQ 推荐暴露，采纳）/ 适用域（raw / non-raw / both）/ **params 键集与类型**（`{key: type}` 扁平表，type ∈ string|number|integer|boolean|enum:…|range:[min,max]）。
- **schema 生成裁决：手写 per-op 轻表，不做 Codable 反射生成**。探针性走查结论：Mirror/CodingKeys 反射拿键集可行，但 Optional 包裹、enum rawValue 域、range 语义（slider min/max）需要人工语义标注——反射产物会是一份「键全对、语义全无」的表，仍需手写注解层；而 18 个 iop 面参数键量级（每 op 3-10 键）手写表 + 单测断言「手写表键集 == Params CodingKeys 反射键集」（反射只做**守卫**不做生成）= 两全。该守卫测试同时 pin `version` 漂移。
- `apply_params` 的 `params` 自由 JSON + 服务端 decode 校验（§RQ-14-5），inputSchema 不逐 op 展开（展开 = schema 爆炸）；`list_iops` 是 agent 获知参数键的运行时通道——两者配合即 MCP-01「iop 参数 schema 元数据」字面。

---

## §RQ-14-7 list_photos 入参与轻量列终表（P0）

1. **入参**：`filter` = `FilterPredicateGroup` JSON 直作（`FilterPredicate.swift:212-266`——`{schemaVersion:1, match: all|any, rules:[{field,op,value}]}`；16 字段白名单 `FilterField`（:54-71）**全暴露**（字段集即 FilterSQL 支撑面，子集化无收益）；12 op 白名单 `FilterOp`（:76-89）；合法性矩阵 `legalOps`/`legalValueKinds`（:274-314）服务端校验 → typed error `invalidFilter`（FilterPredicateError 映射））；`sort` = `{key: filename|rating|captureDate|iso|focalLength|scanEpoch, ascending}`（`FilterSortKey` 六键直映，`FilterSQL.swift:58-86`）；`limit`（默认 200，上限 1000）+ `cursor`。
2. **分页 keyset 游标**（16 期 RQ-16-6 同源形状）：cursor = base64(`{captureDate, path}` 或按 sort 键 + path 终值)；SQL 形状 = 追加 `(key, path) > (?, ?)` 谓词进 `SessionIndexStore.query` 的 WHERE（现 face `SessionIndexStore.swift:561-584` 消费 `FilterSQL.translateConjoining` 产物 + 追加项——**零新翻译层**，追加谓词拼在 query 调用点的 SQL 组装层，不触碰 FilterSQL）。返回 `{rows, nextCursor}`——**不返回总数**（COUNT 需第二趟全扫，16 期 COUNT 语义对照后裁决：agent 用游标耗尽感知终页即可，省一次万张级扫描）。
3. **轻量列终表**（34 列逐列裁决；frozen spelling `SessionIndexSchema.swift:66-102` 零改动）：

| 组 | 列 | 处置 |
|---|---|---|
| 路径身 | path, dir, filename | **暴露**（path = 工具间 relPath 通用键） |
| 文件 | file_size, file_mtime | **暴露** |
| 索引内部 | scan_epoch | **不暴露**（内部账目，无 agent 语义） |
| 身份 | imageID | **不暴露**（UUID 内部身份；L013 哈希面 agent 无需） |
| sidecar 态 | sidecar_present, sidecar_mtime, has_edits | **暴露** has_edits（MCP-05 黑体）；sidecar_present/mtime **不暴露**（内部一致性账目） |
| 参数态 | params_hash, layer_count, layer_summary | layer_count/summary **暴露**（有编辑内容语义）；params_hash **不暴露**（内部哈希） |
| 几何 | orientation, width, height | **暴露**（ROI 坐标系换算必需——get_detail_crop 依赖） |
| 时间 | capture_date | **暴露**（burst/游标/筛选键） |
| 缩略 | thumb_state, thumb_path, thumb_params_hash | thumb_state **暴露**（stale 语义 §RQ-14-8）；thumb_path/thumb_params_hash **不暴露**（内部路径/哈希） |
| 元数据 | rating, color_label, keywords, flag, note | **全暴露**（MCP-05/06 黑体面） |
| 分类 | orphan_sidecar, dirty | **不暴露**（基线谓词已滤 orphan；dirty 是崩溃窗口内部态） |
| EXIF | camera_make, camera_model, lens_model, iso, focal_length, aperture, exposure | **全暴露**（筛选键 + 筛片语义） |

   **终数：暴露 25 列 / 不暴露 9 列**（内部账目/哈希/路径类剔除，其余全给）。返回行按此投影（`SessionIndexRow` → MCP dict 的显式映射表，一处拼装）。
4. **谓词往返测试**：同一 FilterPredicateGroup GUI chips 与 MCP 入参同 SQL 同结果（12-2 翻译层 fixture 复用）入 14-3 测试单。

---

## §RQ-14-8 图像三件套参数与 base64 预算表（P0 ★探针出炉）

**预算表（实测：36MP 照片级源图；JPEG bytes → base64 bytes；vision-token ≈ (w×h)/750 的 client 端粗估系数，真实 token 由各 client 视觉编码器决定）**

| longEdge | q70 | q80 | q90 | token≈ |
|---|---|---|---|---|
| 512 | 32KB/43KB | 36KB/48KB | 47KB/63KB | 349 |
| 768 | 58KB/78KB | 65KB/87KB | 89KB/118KB | 786 |
| **1024** | **92KB/123KB** | **106KB/141KB** | 149KB/199KB | **1398** |
| 1536 | 197KB/263KB | 241KB/321KB | 348KB/464KB | 3145 |
| 2048 | 370KB/493KB | 478KB/637KB | 690KB/920KB | 5592 |
| 4096 | 2.17MB/2.89MB | 2.97MB/3.96MB | 4.13MB/5.50MB | 22369 |

小尺寸档（q85）：256px=16KB/22KB、360px=27KB/36KB、512px=44KB/59KB、720px=75KB/100KB。HEIF 同质小 3-4×（720px: 17KB vs 75KB）但 MCP client 渲染支持面窄——**JPEG 为主的 D-14-CONTEXT-4① 裁决被实测支持**；PNG inline 永不（lossless 5-8×）。

**默认值由预算表钉死（非拍脑袋）**：

| 工具 | 默认 | 上限 | 单请求预算 |
|---|---|---|---|
| render_preview | longEdge **1024**, q**85**, JPEG | longEdge **2048**, q90（**4096 上限砍至 2048**——4096/q90=5.5MB base64/22K token 一次调用即污染上下文，超 2048 需走 export_image 落盘） | ~1.5MB |
| get_thumbnails | 双档直读（档A embedded / 档B `ThumbnailDiskStore.read`，沿用 09 期 appointment 语义 `SessionThumbnailProvider.swift:43-50`）；thumb_state=3 → 返回 `stale: true` 标记 + 可选 `regenerate: false` 参数（默认只标记不阻塞批量；regenerate=true 触发 tier B 单图重渲后返回） | **每请求 ≤20 张**（分页由调用方循环） | ~730KB |
| get_contact_sheet | cell **256**, q**80**；布局 cols×rows 上限 6×5=30 格 + 每格 24px 标注条（文件名短标 + rating 星符 + flag 色条，CoreGraphics 绘制纯 CG 无管线） | 单图总量 ≤ 2MB base64 | 20 格实测 319KB/426KB ≈ 2000 token |
| get_detail_crop | ROI 原图像素坐标 `{x,y,w,h}`；输出 longEdge **1024**, q**85** | ROI 面积上限 = 全图；输出上限 1536 | ~200KB |

- **100 张全尺寸原图不可行**的量化注脚：4096/q90 档 100 张 = 550MB base64——CONTEXT 红线成立且量级在案。
- get_detail_crop 多 ROI：v1 单 ROI 单请求（批量循环；多 ROI 数组 = additive 参数位）。

---

## §RQ-14-9 burst 分组算法（P1）

- **聚类键**：`capture_date` 间隔阈值（默认 **2.0s**，参数化 `gapSeconds`）+ `camera_model` 参与分组（换机不并组——RQ 推荐采纳）。跨日自然切断（间隔阈值隐式覆盖，无特殊边界逻辑）。
- **查询形状**：`SELECT capture_date, camera_model, path, filename ... FROM images WHERE <baseline> ORDER BY capture_date ASC` 单扫 + 内存聚类（万张级 <1ms 扫描 + O(n) 分组——12-RESEARCH §3.4 已量过万张全扫 <1ms，SQL 窗口函数无收益）。复用 `SessionIndexStore` 查询面直拼（不用 FilterSQL 谓词——burst 是专用查询不是过滤面；但仍走同一 actor handle，零新锁面）。
- **返回形态**：`{bursts: [{id: "burst-<首图path-hash8>", count, members: [{relPath, filename, captureDate}]}], singles: [relPath...]}`——单张不成组进 singles。`list_photos` 组合查询 = burst id 不是索引键，agent 以 members 的 relPath 集合自组 `filename in` 或时间窗谓词二次过滤（文档给 recipe，不加专用参数）。

---

## §RQ-14-10 get_face_regions 复用面（P1 ★探针出炉）

- **轻请求直用，SkinRegionLocator 不硬套**（RQ 推荐采纳）：get_face_regions = `VNDetectFaceLandmarksRequest` 直发（Vision framework 直调），只取 `boundingBox`（归一化坐标 × 图像 width/height → 原图像素框）+ landmarks 点集可选返回。SkinRegionLocator 的 hull/保护区逻辑是磨皮域孪生（`SkinRegionLocator.swift:12` 编排含 person segmentation），脸框工具不复用其编排。
- **成本实测（无脸 fixture，1024²）**：warm 单图 **3.9ms**；串行 100 张 **389ms**；8 路并发 **152ms**（2.56× 加速——Vision 内部并发度有限，线性外推无效）；负例 = faces 0 空数组（**无脸是空数组非错误**，语义钉死）。检测主干成本与是否有脸无关（全图跑），landmark 精化增量待 14-3 真人像样张补测（探针局限）。
- **策略**：**per-request 不缓存**（RQ 推荐采纳）——3.9ms/图的量级下缓存是过度设计；文档标注成本模型「~4ms/图 + 请求内串行」。万张全量跑 (~39s 串行) 不是用例（culling 流 = 联系表选出可疑组 → 挑 3-5 张取脸框 → get_detail_crop 脸部 ROI），不需要批量入口；`relPaths` 数组上限 20（与 get_thumbnails 同批上限）。

---

## §RQ-14-11 export_image 复用面（P0）

1. **落盘通道终判：直渲，不入 ExportQueue**（RQ 推荐采纳）：`ExportRenderer.render(request:metal:registry:yiyinInjector:)`（`ExportRenderer.swift:164-184` = renderStage + encodeStage 一体）全复用——decode → sizing（ExportVariant）→ disk sidecar → export chain → （yiyin 可选注入）→ routed render → exit leg → quantize → **encode + L009 原子晋升（encodeStage :381-428 内建）**。ExportQueue 的进度/取消/队列语义对单图 MCP 导出过重；并发控制 = 渲染信号量（§RQ-14-14，与 render_preview 共用）。
2. **yiyin 参数位**：`variant.yiyin` 默认 false，schema 可选布尔 + 可选预设 id；true 时注入器 = App 层 `ExportYiyinInjector` 生产缝（`ExportRenderer.swift:46-65`，11-04 wiring 复用）——yiyin 工具参数只透传「用当前 yiyin 面板配置」一个语义，不暴露边框细节参数（EXP-05 共享配置语义）。
3. **输出位置与命名**：destinationDirectory 限 `Session/Output/`（服务端钉死，入参不含路径）；命名 = `ExportNamer.destinationURL`（`ExportRenderer.swift:357-362` 消费点）——`<stem>_<tag>` 派生 + `-1` 递增碰撞先例照抄。XMP mount 腿（encodeStage :416-423）随 encodeStage 自动发生（导出产物带元数据，与 GUI 导出一致——注：11 期 WebP 降级注记沿用，不新增工作）。
4. **路径返回**：绝对路径文本 + `note` 字段明示「远程 client 无法直接读取本机路径；如需查看请用 render_preview 取 inline 预览或经 GUI/文件共享」。variant 尺寸/格式/colorSpace 参数 = ExportVariant 既有面直映（六格式 registry + ICC）。

---

## §RQ-14-12 launcher 细节（P1）

- **默认模板示例**（设置占位文本，真实可跑形）：
  - omp：`omp -p --auto-approve "请用 lightamer MCP 工具筛选 {{LIGHTAMER_MCP}} 所在会话中 rating IS NULL 的照片，{{PROMPT}}"`
  - pi：`pi -p "对当前 Lightamer 会话（MCP 端点配置见 {{LIGHTAMER_MCP}}）执行筛图任务：{{PROMPT}}"`
  - agent 侧消费方式示例文本：「mcp-endpoint.json 内含 host/port；将 `"http://<host>:<port>/mcp"` 配置为 Streamable HTTP server」。
- **`{{PROMPT}}` 转义规则**：模板先做占位符替换，`{{PROMPT}}` 内容经 **shell 单引号包裹法**（`'` → `'\''`）内联后整体交 `/bin/zsh -c`。文档明示注入面 = 用户自注入（D-14-CONTEXT-10③ 与 EXP-08 的差异留痕：EXP-08 `Process` 直 exec 不经 shell（`PostExportActions.swift:123-132`），launcher 走 shell 是模板表达力的自觉选择，纪律不同源不混引）。
- **日志面板**：Pipe 读行 → SwiftUI TextEditor 环形缓冲 **2000 行**；暂停滚动开关（滚动跟随 toggle）；导出 = 复制全文到剪贴板（v1 不做文件导出）。
- **终止 UX**：进行中显示「停止」按钮 → SIGTERM → **5s** 超时 SIGKILL（§8.5 自家子进程：只对自持 pid 下手）；launch 失败（executable 不存在）= toast + 日志行；非零退出 = 日志尾部红色标注退出码；写回零结果 = 任务完成 toast 显示「本次会话无写回」（agent 是否听话不作断言）。
- **串行**：进行中再点 = 按钮置灰 + 「已有一个 agent 会话进行中」提示。

---

## §RQ-14-13 安全细节（P1）

- **token**：生成 = `SecRandomCopyBytes` 32 字节 → base64url（~43 字符）；存储 = **keychain 真身 + 发现文件只放 `auth: "bearer"` 标记**（非回环才有 token 面，回环零 token——攻击面最小）；fallback（keychain 不可用，非沙盒 app 罕见）= `~/.lightamer/mcp-token` 0600。校验 = 自写轻 validator（§RQ-14-1②）进 `validationPipeline`，**常量时间比较**（`constantTimeComparison` 手写，防时序侧信道——公开仓审计注意项）。安全走查口径：绑定常量走查（127.0.0.1 无设置项）、token 比较、Origin pipeline 未被禁用、工具白名单 = tools/list 快照负例。
- **非回环绑定**：设置中显式开启后监听接口选择 = **0.0.0.0**（+ Bearer 必须 + 文档明示局域网暴露风险）——具体网卡选择 UI 是 v2 精细化；revisit 于安全走查。
- **速率限制**：渲染类工具（render_preview/export_image/get_detail_crop/get_contact_sheet）**串行信号量（并发 1）**即够（GPU 渲染本身串行化更稳）；元数据/查询工具不限流（SQLite WAL 读并发已有）。

---

## §RQ-14-14 生命周期/超时/多 client（P1）

- **请求级超时表**（对齐 QL 有界超时数值族）：元数据写 5s / list_photos·list_bursts 10s / get_thumbnails·get_contact_sheet 20s / render_preview·get_detail_crop **30s**（= `QuickLookRenderer.renderTimeout` :69 同源常数）/ apply_params 10s（万张批量除外——批量上限 relPaths ≤ 1000 时 60s）/ export_image **120s**。超时 = JSON-RPC error（typed 码），server 不崩。
- **停机处置**：偏好关 / applicationWillTerminate = 停止接受新请求 + in-flight **有界排空 5s**（running 渲染 finishes into the void 姿态同 QL boundedWait 取消语义）→ 删发现文件 → 释放 flock → 退出。即断兜底：排空超时后强制。
- **HTTP 多 client**：per-session transport 字典（§RQ-14-1③ 模式）+ 上限 **4 并发 session**（超出 503 + 文档；本机单用户工具，4 已宽裕）；写面（元数据/params/preset/export）全局 actor 串行——请求级排队非拒绝（D-14-CONTEXT-5⑤）。
- **活动上下文归属**：无状态化后**问题消解**（§RQ-14-5②）——若 planner 保留有状态设计则取「全局单份 + 后 load 覆盖前 + call 时 typed 提示」。

---

## §RQ-14-15 研究项 B/C 终判登记 + 复审位处置（登记型）

1. **研究项 B（v1 = history append 既有语义）复核通过**：`HistoryStack` 的 `jump(to:)` 语义已交付（`HistoryStack.swift:12`——"undo/redo/jump(to:) move ONLY the pointer"），GUI 可回退任意历史点；MCP 不暴露 history 遍历工具**无功能洞**（agent 的「反悔」= 重新 apply 上一参数集或请用户 GUI undo）。版本面 defer v2 登记（CONTEXT deferred 节维持）。
2. **研究项 C（match_color）零占用确认**：19 工具封闭枚举不含 match_color；tools/list 快照断言天然排除；V2 TRACK colormatch iop 落地时的入集流程 = additive + 快照显式改 + 工具描述补齐（留痕即此条）。
3. **XMP 三格式内嵌元数据复审位：关闭留痕**（12 移交②经 13 转记）——v1 元数据真身 = sidecar/lindex，读写全程不经文件内嵌 XMP；复审条件「MCP 需三格式内嵌元数据载体」不成立。
4. **WebP mux 复审位**：export_image 沿用 11 期 WebP 元数据降级注记（Swift-WebP 零 mux 面），不新增工作。

---

## §A 工具清单终表（19 个，D-14-CONTEXT-3 封闭集；快照断言的正本）

CONTEXT 写「~18」，逐项清点 = **19**（微修正：4 修图 + 4 筛选读 + 2 culling 辅助 + 5 筛选写 + 3 预设 + 1 导出）。

| # | 工具 | 关键入参 | 返回 | 错误码 | annotations |
|---|---|---|---|---|---|
| 1 | `load_image` | relPath | 该图 sidecar 视图（instances 摘要/图层摘要/尺寸）§RQ-14-5② | notSessionMember, serverReadOnly | readOnlyHint |
| 2 | `apply_params` | relPath, ops[] | 落盘结果（appliedRelPaths） | unknownOp, invalidParams, imageLiveInEditor, serverReadOnly, notSessionMember | destructiveHint |
| 3 | `render_preview` | relPath, longEdge≤2048, quality≤90, format | image content (JPEG b64) | renderFailed, renderTimeout, notSessionMember, serverReadOnly | readOnlyHint |
| 4 | `list_iops` | （无） | op 清单 + params 键集 + version §RQ-14-6 | — | readOnlyHint |
| 5 | `list_photos` | filter(FilterPredicateGroup), sort, limit, cursor | rows(22 列投影) + nextCursor | invalidFilter, serverReadOnly | readOnlyHint |
| 6 | `get_thumbnails` | relPaths≤20, regenerate=false | 每图 image content + stale 标记 | notSessionMember, serverReadOnly | readOnlyHint |
| 7 | `get_contact_sheet` | cols×rows≤30, cellSize=256, relPaths 或 filter | 单拼图 image content | notSessionMember, serverReadOnly | readOnlyHint |
| 8 | `get_detail_crop` | relPath, roi{x,y,w,h}, longEdge=1024 | image content | roiOutOfBounds, notSessionMember, serverReadOnly | readOnlyHint |
| 9 | `list_bursts` | gapSeconds=2.0 | bursts + singles §RQ-14-9 | serverReadOnly | readOnlyHint |
| 10 | `get_face_regions` | relPaths≤20 | 每图脸框数组（空数组=无脸） | notSessionMember, serverReadOnly | readOnlyHint |
| 11 | `set_rating` | relPaths[], rating 0..5\|null | MetadataEditOutcome 映射 | serverReadOnly, notSessionMember | destructiveHint |
| 12 | `set_flag` | relPaths[], flag 0/1/2\|null | 同上 | 同上 | destructiveHint |
| 13 | `set_color_label` | relPaths[], color 0..6\|null | 同上 | 同上 | destructiveHint |
| 14 | `append_note` | relPaths[], note | 同上 | 同上 | destructiveHint |
| 15 | `set_keywords` | relPaths[], keywords[]\|null | 同上（`MetadataService.setKeywords` :117-124 整组替换语义；不含 `\|` 校验 typed error） | keywordContainsSeparator, 同上 | destructiveHint |
| 16 | `list_presets` | kind=develop\|export | 预设清单（PresetsStore 面 :73/:200） | serverReadOnly | readOnlyHint |
| 17 | `apply_preset` | presetID, relPaths[], mode, selection? | BatchApplyOutcome 映射（PresetApplier.apply 直复） | exportPresetNotApplicable, imageLiveInEditor(live skip 语义→报告面), serverReadOnly | destructiveHint |
| 18 | `diff_presets` | presetIDA, presetIDB | 实例差异面（op 键集 diff） | unknownPreset, serverReadOnly | readOnlyHint |
| 19 | `export_image` | relPath, format, sizing, quality, yiyin=false | 绝对路径文本 + note | exportFailed, serverReadOnly, notSessionMember | destructiveHint |

- 全部读面含隐式错误 `internalError`（SDK MCPError 映射）；错误码表随各 plan 测试单逐行断言。
- apply_preset 的 live 语义细化：GUI-live 图由 `PresetApplier.apply` 的 `liveRelPaths` 跳过机制处理（:92 live targets skip + interactive 层 paste）——MCP 场景无 GUI 交互层，live 图进 `skippedRelPaths` 报告（不报错不阻塞批量）——与 apply_params 的硬拒不同（单图硬拒给 agent 明确信号；批量软跳给结果面）。**该差异入 14-3 plan 钉板**。

---

## §B 波次验证与 plan 草案（D-14-CONTEXT-12 验证 = **维持 4 plans / 3 waves**）

- **正交性验证成立**：14-2（ExportRenderer/renderedPlane 域）与 14-3（Session 域）Core 面零交集；共享件只有 14-1 的 registry 缝与渲染信号量（后者在 14-1 落，两 plan 消费）。14-2∥14-3 并行推荐执行（双 worker）。
- **14-1 新增任务**（相对 CONTEXT 草案的增量）：NIO HTTP 适配腿（conformance HTTPApp 模板移植 + SSE 泵 + per-session transport 字典 + 轻量 Bearer validator）——这是 14-1 最大的新代码面，任务单独立。
- **刚性**：14-1 先行（hello-world 探针收口 = SC 级）；14-4 收口含签核。

### 14-1 server 底座（wave 1）
任务：T1 `@main` headless 分叉实测（本 research §RQ-14-1④ 方案；不过 → executor target 裁决入 DECISIONS）；T2 swift-sdk 0.12.1 集成 + `McpToolRegistry` 纯 Swift 缝 + tools/list 快照框架（InMemoryTransport 测试形态）；T3 stdio 宿主 + 无头 flock 写者权 + endpoint.lock；T4 NIO 适配腿 + Streamable HTTP 绑 127.0.0.1 + 端点发现文件 + 只读降级；T5 安全面（Bearer validator + Origin/Host 实测 + 127.0.0.1 常量断言）+ hello 工具双宿主端到端。
AC：stdio + HTTP 两宿主 hello 工具对打绿；flock 互斥/降级断言绿；tools/list 快照落位；全套 suite 绿（基线 1768/11skip/0fail）。

### 14-2 修图面（wave 2，与 14-3 并行）
任务：T1 MCP-03 parity 初测（renderedPlane vs Export golden，同尺寸同参域）+ render_preview 工具（超时/信号量）；T2 apply_params + load_image（无状态化按 §RQ-14-5② planner 裁决）+ GUI-live 拒写 + 错误码表；T3 list_iops + per-op 手写 schema 表 + 反射守卫测试；T4 export_image（直渲 + ExportNamer + yiyin 缝 + 路径返回）；T5 修图面 SC#3 端到端（载入 DSC00012.ARW → ≥3 iop → 预览与本地渲染对照）。
AC：parity 初测数字在案；golden 往返（apply→读盘 sidecar 字节面）；全套 suite 绿。

### 14-3 筛选面（wave 2，与 14-2 并行）
任务：T1 list_photos（FilterSQL 直连 + 22 列投影 + keyset 游标 + 谓词往返测试）；T2 写五件 + GUI 联动走查（含 inspector 行跟随走查 §RQ-14-3⑥）+ apply_preset/diff_presets/list_presets；T3 图像三件套（双档直读/stale 语义/联系表 CG 拼图/ROI 裁剪）+ base64 上限表落码；T4 list_bursts + get_face_regions（真人像 landmark 补测入本 plan 首任务）；T5 筛选端到端（SC#5/6：列 → 缩略/联系表 → 细节 → 写回 → sidecar+lindex+GUI 同步可见）。
AC：写回联动 parity（12 期测试形态跨入口）；批量三段回归 + live-target 负例；全套 suite 绿。

### 14-4 launcher + 收口（wave 3）
任务：T1 偏好 UI（模板/prompt/开关）+ launcher 动作（Process zsh -c + 占位符 + 串行 + SIGTERM/SIGKILL）；T2 日志面板（环形缓冲/暂停/复制）+ 哨兵测试（注入逐字/串行/终止只及自家）；T3 SC 端到端全链 + 安全走查清单（绑定/token 比较/Origin/白名单负例）+ PROJECT.md 依赖漂移修正挂收口批；T4 签核准备（VALIDATION）。
AC：SC#7 launcher 端到端；安全断言全绿；L025 zh 键 smoke。

---

## §C 风险表

| # | 风险 | 等级 | 对策/落点 |
|---|---|---|---|
| R1 | swift-sdk 0.x churn（connect 自动握手等行为变更实证） | 中 | 精确 pin 0.12.1；registry 纯 Swift 缝；适配器层单点替换 |
| R2 | NIO 适配腿 = 新增自维护 ~250 行（SSE 泵/session 字典/keep-alive 细节） | 中 | conformance server HTTPApp.swift 正本移植 + 探针已踩平 SSE 泵坑；14-1 T4 独立任务 |
| R3 | 同 binary headless 分叉未实测（NSApplication 生命周期副作用） | 中 | 14-1 T1 首任务实测；executor target 回退（13-1 appex 先例）|
| R4 | 静态 token 校验自写（SDK 面向 OAuth JWT） | 低 | ~30 行 validator + 常量时间比较；14-4 安全走查 |
| R5 | Vision landmark 真人脸成本未测 | 低 | 14-3 首任务补探针（真实人像样张 10 张）；架构不受影响（per-request 已裁） |
| R6 | MCP-03 像素 parity 未初测 | 中 | 14-2 T1 首任务（QL parity 模板 + golden 基建现成）；不过 → 划界重谈（CONTEXT 预案） |
| R7 | MCP 元数据写后 GUI 编辑器 inspector 不自动刷新 | 低 | 14-3 T2 走查；若属实 → 通知缝或刷新钩子小改 |
| R8 | 多 client session 字典 + InMemory 测试双形态的行为差异 | 低 | registry 缝单实现 + 双宿主（+InMemory）同套 handler 测试（验证红线） |
| R9 | get_contact_sheet CG 拼图中文字体渲染（文件名含中文） | 低 | CoreText/NSAttributedString 标注条；14-3 用中文 fixture 测 |

---

## §D 与 CONTEXT 的冲突/修正发现（planner 裁决清单）

| # | 发现 | 性质 | 建议 |
|---|---|---|---|
| D1 | HTTP server transport 无 listener，swift-nio 成为主 app 真实编译依赖 | **新事实**（CONTEXT 未提） | 14-1 增 NIO 适配腿任务；PROJECT.md 依赖漂移修正把 swift-nio 一并登记 |
| D2 | stdio 宿主写 endpoint.json 无消费方 | 对 CONTEXT D-14-CONTEXT-2②/RQ-14-2 推荐的修正 | stdio 只持 flock 不写发现文件（§RQ-14-2） |
| D3 | 工具数 19 非 ~18 | 终数钉死 | 快照断言以 §A 表为正本 |
| D4 | `connect()` 自动 initialize（0.12.1 行为变更） | 新事实 | 适配器集成注意；churn 基线入 RESEARCH |
| D5 | load_image「活动上下文」→ 无状态化推荐 | **设计建议**（非推翻；RQ-14-14 互踩难题消解） | planner 二选一：无状态（推荐）vs 全局单份上下文 |
| D6 | Origin 匹配要求带端口（`http://localhost` 无端口被拒） | 新事实 | 工具文档/client 示例写带端口 origin |
| D7 | render_preview 上限 4096 → 建议砍至 2048（4096/q90 = 5.5MB b64/22K token 实测） | 参数修正 | 上限表数值常量一处（D-14-CONTEXT-4 reversibility 预案内） |
| D8 | apply_preset 的 GUI-live 处理 = skippedRelPaths 软跳（批量语义）vs apply_params 硬拒（单图语义） | 语义细化 | 14-3 plan 钉板；两语义各有测试负例 |

---

## Sources

- swift-sdk 0.12.1：https://github.com/modelcontextprotocol/swift-sdk（tag 0.12.1；Package.swift / Server.swift / Tools.swift / HTTPServerTransport / HTTPClientTransport / HTTPApp.swift conformance 模板 / README BearerTokens 节）
- MCP spec 2025-11-25：https://modelcontextprotocol.io/specification/2025-11-25/（Streamable HTTP 传输 / Origin 校验条款 / tools 注解）
- 本仓源码走查行号见各节 inline 引用（复用底座 14 文件 + App 层 4 文件）

---

*Phase: 14-MCP Server — Research*
*探针工程 /tmp 即弃（mcp-probe / lock-probe / budget-probe / vision-probe 四工程）；本文件为唯一交付物*
