---
phase: 14
plan: "14-1"
title: "server 底座（全 Phase 依赖根）：swift-sdk 0.12.1 精确 pin + McpToolRegistry 纯 Swift 缝 + tools/list 快照框架 + @main headless 分叉（--mcp-stdio/--mcp-http）+ stdio 宿主 + NIO Streamable HTTP 适配腿（127.0.0.1 + SSE 泵 + per-session transport 字典）+ 端点发现文件协议（flock 写者权 + 只读降级）+ 安全面（轻量 Bearer validator / Origin-Host 内置管线 / 回环绑定常量）+ 渲染串行信号量基建 + hello 双宿主端到端探针收口"
wave: 1
depends_on: []
autonomous: true
requirements: [MCP-02, MCP-04]
files_modified:
  - Project.swift                                                   # packages 加 swift-sdk 0.12.1 exact pin（第二个 SPM 依赖，D-14-CONTEXT-1③）；App target 依赖 MCP 产品；注释更新 SPM policy
  - App/Sources/Lightamer/MCP/McpToolRegistry.swift                 # 新建：纯 Swift 值类型缝——ToolDescriptor（name/description/inputSchema/annotations）+ @Sendable handler + typed McpToolError 错误码 + McpTimeouts 常量表 + McpImageBudget 预算常量表（render_preview 上限 2048 等三 plan 消费共享——checker M-3 上移）+ 渲染串行信号量 McpRenderGate
  - App/Sources/Lightamer/MCP/McpAdapters.swift                     # 新建：SDK 类型适配层（唯一 import MCP 处）——withMethodHandler(ListTools/CallTool) ↔ registry 映射 / Tool.Content / InMemoryTransport 测试腿
  - App/Sources/Lightamer/MCP/McpEndpointFile.swift                 # 新建：mcp-endpoint.json 读写（L009 同目录 tmp 原子晋升）+ McpEndpointLock（flock EX|NB 写者权 + 崩溃内核自释语义）
  - App/Sources/Lightamer/MCP/McpHTTPTransport.swift                # 新建：NIO 适配腿 ~250 行（conformance HTTPApp.swift 正本移植）——ServerBootstrap + configureHTTPServerPipeline + SSE 泵 + per-session transport 字典（上限 4，超出 503）
  - App/Sources/Lightamer/MCP/McpBearerValidator.swift              # 新建：轻量 HTTPRequestValidator（Authorization: Bearer 共享串 + SecRandom 32B base64url 生成 + keychain 真身/0600 fallback + 常量时间比较）
  - App/Sources/Lightamer/MCP/McpServerController.swift             # 新建：宿主编排——单内核 × 双宿主装配（GUI 内嵌 start/stop + 无头分叉路由）+ 优雅停机（停止接受 → 5s 有界排空 → 删 json → unlock）+ 探针 toolset（ping/count_images）
  - App/Sources/Lightamer/UI/LightamerApp.swift                     # @main 改造：自定义 main 入口分叉（--mcp-stdio/--mcp-http 不构造 App struct 不进 NSApplication.run）+ applicationWillTerminate 挂 server 停机（:65 挂点）
  - Tests/LightamerTests/McpRegistrySnapshotTests.swift             # 新建：快照框架 + 分域快照基建 + 探针面快照（ping/count_images）+ InMemory 全断言
  - Tests/LightamerTests/McpHostTests.swift                         # 新建：flock 互斥/持有者退出释放/崩溃自释/只读降级 + 端点文件写删/残留试锁清理 + Origin 403（带端口匹配规则）/Host 421 + Bearer 拒绝 + 127.0.0.1 常量断言 + stdio 管道三步握手 + HTTP 端到端（SDK client 对打）
  - .work/gsd/phases/14-mcp-server/14-1-SUMMARY.md
  - .work/gsd/phases/14-mcp-server/14-1-DECISIONS.md
  - TODO.md                                                         # Phase 14 节开账 + 14-1 勾选
  - LESSONS.md                                                      # 如踩坑
---

# Plan 14-1 — server 底座（W1，全 Phase 依赖根）

> 背景：Phase 14 一切工具面的依赖根（D-14-CONTEXT-12）。四条主线（14-RESEARCH 正本）：
> ① **swift-sdk 0.12.1 精确 pin + registry 纯 Swift 缝**——SDK 类型收口 App 层适配器，
> `LightamerCore` 零 import MCP（D-14-CONTEXT-1④ 铁律）；探针已证 SDK 双传输 API 面足够
> （§RQ-14-1：stdio 三步握手 + Streamable HTTP 端到端全通，78.5s 干净构建）；② **headless
> 进程**——探针只证了「无 SwiftUI lifecycle 纯 Swift 进程」腿，**同 binary SwiftUI `@main`
> 分叉未实测**（探针局限③），钉为本 plan T1 首任务，executor target 回退在案；③ **NIO 适配
> 腿**——SDK 的 `StatefulHTTPServerTransport` 是框架无关纯函数面，**不自带 HTTP listener**
> （D1 新事实），绑 127.0.0.1 需自搭 ~250 行 NIO 腿（conformance server `HTTPApp.swift` 正本
> 移植 + SSE 泵——探针首版漏泵 client 挂死的坑已踩平）+ **per-session transport 字典**（单
> transport = 单 session 实测，第二个 initialize → 400）；④ **单写者锁与端点发现**——flock
> 终判（锁探针五态全过：互斥/退出释放/崩溃内核自释，O_EXCL+pid 自愈舞步整段不需要）+
> 端点发现文件协议（research §RQ-14-2 终版：**stdio 宿主只持锁不写 json**[D2 修正]、
> 发现方「读 json 后试锁」判残留）。
> 内部任务序刚性：T1（分叉实测）→ T2（registry+快照框架）→ T3（stdio+锁）→ T4（HTTP 腿）
> → T5（安全面+端到端）——T3/T4 共享 T2 缝，T5 是 T3/T4 的断言收口。

## read_first

1. `.work/gsd/phases/14-mcp-server/14-RESEARCH.md` 全文——§0（探针执行摘要 + 局限③）、
   §RQ-14-1（**本 plan 正本**：SDK 依赖图/编译实况、stdio 管道报文形状、HTTP 端到端与
   Origin/Host 匹配规则、**SSE 泵坑**、**单 transport = 单 session**、Bearer 无现成 valve、
   0.x churn 四条[D4]、headless 方案与回退判据）、§RQ-14-2（端点文件 schema/锁件两分/写删
   时序/**stdio 不写 json**[D2]/试锁判残留）、§RQ-14-3②③（flock 终判五态/只读降级
   serverReadOnly）、§RQ-14-13（token 生成存储校验/常量时间比较）、§RQ-14-14（超时表/停机
   排空/session 上限）、§B（本 plan 任务/AC 草案）、§C 风险 R1-R4
2. `.work/gsd/phases/14-mcp-server/14-CONTEXT.md`——D-14-CONTEXT-1（SDK pin/Core 零 import/
   registry 缝形状）、D-14-CONTEXT-2（单内核双宿主/发现文件/无头不加新 target[executor 回退
   例外]）、D-14-CONTEXT-5③（端点锁/后开者只读降级）、D-14-CONTEXT-6（安全边界：127.0.0.1
   硬编码常量/非回环 token 必须）+ 继承定案（失败语义/预览诚实口径）+ 验证红线（双宿主行为
   一致性/安全断言）
3. swift-sdk 0.12.1 源码（SPM checkout `checkouts/mcp-swift-sdk/`）——
   `Sources/MCPConformance/Server/HTTPApp.swift`（**NIO 腿正本**，~250 行：ServerBootstrap +
   configureHTTPServerPipeline + writeResponse 的 `.stream` 分支即 SSE 泵 + sessions 字典）、
   `Sources/MCP/Server/Versioning.swift:10-13`（协议版本常量 2025-11-25）、
   `Sources/MCP/Server/Server.swift`（actor + withMethodHandler）、
   `Sources/MCP/Transport/HTTPClientTransport.swift`（测试对打 client；connect 自动握手[D4]）
4. `App/Sources/Lightamer/UI/LightamerApp.swift`：`@main struct LightamerApp`（:119-120——T1
   改造位）、`MainActor.assumeIsolated` 先例（:49-52）、`applicationWillTerminate`（:65——
   停机钩子挂点，与既有 flush 同批）
5. `LightamerCore/Sources/Session/SessionIndexStore.swift`：query 消费面（:561-584——探针
   `count_images` 的正式替代消费点；本 plan 只读腿）
6. `Project.swift`：packages 节（:86-87 Swift-WebP 先例——from: range 写法（exact: 为本 phase 精确钉要求） + SPM policy 注释
   更新位）+ App target dependencies（:107-113 .package(product:) 消费形态）
7. `LESSONS.md` L009（fixture 禁 UNITEK/同目录 tmp 晋升）/ L013（跨进程身份 StableHash
   decimal String）/ L025（String Catalog 语言标签 zh）+ `AGENTS.md`（Phase 执行模型 + 暂停
   机制）+ `.work/GOAL-STATE.md`（Phase 14 续接点）

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits，英文 message，≤72 字符祈使句 + body
   写 what+why；只 add 本任务申报文件）；**不 push**（本 Phase 全部 plan 同此）。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建（`xcodebuild build-for-testing` 先行——
   test-direct 前提）；**构建勿加 `-derivedDataPath`**（SPM submodule 坑，L034 家族）；
   **新建文件后跑 `tuist generate`**（11-03 教训；本 plan 新建 `App/Sources/Lightamer/MCP/`
   目录与 2 个测试文件——T1 提交前 generate 一次，后续任务每新建文件同）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`（L019b 直启宿主绕
   testmanagerd）；判据 = **Executed 计数行 + failures 行**，Executed 0 = 判据失败（防空转
   假绿）。**回归基线 = 1768/11skip/0fail**（Phase 8 回补收口批后终值，git `2edf489`；执行
   期若基线再漂移，读 `.work/GOAL-STATE.md` 续接点取最新）；每任务全套 suite 绿，收尾轮 =
   1768 + 新增，**0 fail 目标**；**在案 flake 归因条款**：`LayerE2E`/`ToneEqual` 类负载型
   flake 若现，隔离 ×3 归因单列入 SUMMARY，不计本 plan 违约。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）——commit
   后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
5. **架构红线**：①`LightamerCore` **零 import MCP/NIO**——SDK 与 NIO 类型只在
   `App/Sources/Lightamer/MCP/` 适配器出现（D-14-CONTEXT-1④；Core 缝零触碰，grep 自证入
   SUMMARY）；②**MCP 永禁直写 sidecar 文件字节**（继承定案；本 plan 无写面工具，探针面只读）；
   ③L009：端点文件/测试临时文件同目录 tmp 原子晋升，fixture 禁 UNITEK 盘；④L013：一切跨
   进程身份哈希 StableHash decimal String；⑤server 崩溃 = 连接断（client 重连），不吞异常
   （失败语义继承定案）。
6. **执行期决策登记**：RESEARCH/CONTEXT 未覆盖细节（端口随机范围、session 字典淘汰策略、
   探针工具退役时点、keychain service/account 拼写等）标注**执行期决策**入
   `14-1-DECISIONS.md`，不臆造。

## Tasks

### T1 `@main` headless 分叉实测（探针局限③收口，R3 消解位）

- **action**
  1. `LightamerApp.swift` `@main` 从 struct App 摘下，换自定义入口 enum `static func
     main()`（research §RQ-14-1④ 方案）：`CommandLine.arguments` 含 `--mcp-stdio` 或
     `--mcp-http` → **不构造 `LightamerApp`、不进 `NSApplication.run`**，直接装配 server
     内核常驻（stdio：`dispatchMain()` 式挂起等 stdin；http：NIO 腿跑起后挂常驻）；否则
     `LightamerApp.main()` 走 GUI 全流程。
  2. **风险点实测**（回退判据）：`@NSApplicationDelegateAdaptor` 与 `@Observable @State`
     初始化是否被完全绕开（静态 main 分叉不构造 App struct 即不触碰它们——预期可行，实机
     构建验证）；GUI 路径回归（开关/窗口/设置全绿）。
  3. **不过 → 回退**：新增轻量 executor target（13-1 appex 先例）——代价 = Tuist target +
     装配代码共享层抽取；裁决与证据入 `14-1-DECISIONS.md`（D-14-CONTEXT-2⑤ 预案）。
  4. 无头进程最小验证：`--mcp-stdio` 管道灌 initialize → 回包 serverInfo（协议版本
     2025-11-25）即收（完整 hello 工具面在 T5）。
- **证据**：实机构建 + 两形态启动日志/回包记录；GUI 回归点清单；回退未触发（或触发时
  DECISIONS 裁决记录）。

### T2 swift-sdk pin + `McpToolRegistry` 纯 Swift 缝 + tools/list 快照框架

- **action**
  1. `Project.swift`：packages 加
     `.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact:
     "0.12.1")`（**exact pin**——0.x churn 期不做范围版本，R1）；App target 加
     `.package(product: "MCP")`；SPM policy 注释更新（第二个依赖 + 传递 swift-nio/swift-log/
     swift-system/eventsource 登记，D1）；`.package.resolved` 入库（11-01 先例：钉传递依赖
     版本）；`tuist generate`。
  2. 新建 `McpToolRegistry.swift`（**纯 Swift，零 SDK/NIO import**，编译期可证）：
     `ToolDescriptor`（name/description/inputSchema JSON 字符串/annotations
     readOnlyHint/destructiveHint/idempotentHint——SDK annotations 面 §RQ-14-1⑤④ 直映）、
     `@Sendable handler ([String: Any]) async throws -> McpToolOutput`（text/image content
     两形态）、typed `McpToolError` 错误码枚举（unknownOp/invalidParams/imageLiveInEditor/
     notSessionMember/serverReadOnly/renderFailed/renderTimeout/exportFailed/invalidFilter/
     roiOutOfBounds/keywordContainsSeparator/exportPresetNotApplicable/unknownPreset/
     internalError——§RQ-14-5④ + §A 全表错误码列，一次落齐，各工具 plan 消费）、registry
     注册/查询面。
  3. **超时常量表 `McpTimeouts`**（§RQ-14-14 一处落齐）：metadata 5s / list 10s /
     thumbnails+contact 20s / render+crop 30s / apply 10s（批量 ≤1000 时 60s）/ export
     120s——后续 plan 引用，禁各处裸数字。
  4. **渲染串行信号量 `McpRenderGate`**（§RQ-14-13；两 plan 消费的共享件）：并发 1
     actor/信号量，render 类工具包装器（`withRenderGate`）——14-1 落基建，消费在 14-2/14-3。
  5. 新建 `McpAdapters.swift`（**唯一 import MCP 处**）：`Server` actor 装配（name=lightamer
     + capabilities 只声明 tools，`tools.listChanged=false`）+ `withMethodHandler(ListTools/
     CallTool)` 泛型闭包 ↔ registry 双向映射 + `Tool.Content`（`.text(text:_meta:)` 新形态，
     旧 API deprecated 警告禁踩[D4②]）+ **InMemoryTransport 测试腿**（§RQ-14-1③ 测试基建
     红利：双宿主行为一致性的第三形态）。
  6. 探针 toolset 注册：`ping`（回声）/ `count_images`（已打开会话 lindex 行数，只读——
     SessionIndexStore query 面 :561-584 只读消费）。**探针面非终面成员**（D-14-CONTEXT-3
     封闭集 19 工具不含它）——退役时点 = 14-4 T1（DECISIONS 登记）。
  7. 快照框架（`McpRegistrySnapshotTests.swift`）：工具名集 + inputSchema 键集逐字断言，
     **分域分组**——`probe` 域（本 plan 探针面）/ `editing` 域（14-2 填）/ `culling` 域
     （culling 域快照在 14-3 自有测试文件 McpCullingToolsetTests；editing 域由 14-2 填共享 McpRegistrySnapshotTests；并集终快照 14-4 冻结——checker M-1 分域落点更正）；跨域并集终快照（19 封闭集
     冻结）在 14-4 T3。
- **证据**：`McpRegistrySnapshotTests` 绿（探针面快照 + InMemoryTransport 上 tools/list 回显
  name/description/inputSchema/annotations 完整）；Core 零 import grep 自证（
  `grep -rn "import MCP\|import NIO" LightamerCore/` 零命中，输出入 SUMMARY）。

### T3 stdio 宿主 + flock 写者权 + 端点锁件

- **action**
  1. 新建 `McpEndpointFile.swift`：**锁与发现文件两分**（research §RQ-14-2）——
     `McpEndpointLock`（`<AppSupport>/Lightamer/mcp/mcp-endpoint.lock`，flock EX|NB 写者权
     原语）+ `McpEndpointFile`（`mcp-endpoint.json` 载荷：schemaVersion/transport/host/port/
     pid/startedAt/serverName/serverVersion/auth——schema verbatim §RQ-14-2；L009 同目录 tmp
     原子晋升）。
  2. **锁语义**（探针五态终判 §RQ-14-3②）：获取成功 = 写者；`EWOULDBLOCK` = 已有持有者 →
     **只读模式启动**（flock 失败不退出，写面工具调用时 typed error `serverReadOnly`，
     错误文本携带端点文件路径指引 agent 改连 GUI HTTP 端点）；持有者退出/崩溃 = 内核自释，
     **零残留处置代码**（O_EXCL + pid 校验舞步明确不做）。
  3. **发现方协议**：读 json 成功后 `flock(NB)` 试锁——试锁成功 = 残留文件（持有者已死）→
     清理并按无服务处理；失败 = 活服务在。pid 字段仅诊断展示不作存活判据。
  4. stdio 宿主（`McpServerController` 分支）：`StdioTransport` + registry 装配 + flock
     持有；**stdio 不写 endpoint.json**（D2 修正——「端点」即自身 stdin/stdout，发现文件无
     消费方；但锁必持，写者权与传输形态无关）。
  5. 写者权只读降级断言钩子：registry handler 执行前查「本进程持锁？」，非持锁 →
     `serverReadOnly`（基建落此，写面负例测试 14-2/14-3 消费）。
- **证据**：`McpHostTests`——flock 两进程互斥 / 持有者正常退出即释放 / 持锁进程 `exit(9)`
  崩溃后继立即获锁（零残留）/ 只读降级 serverReadOnly / stdio 宿主不产生 json 文件 /
  发现方试锁清理残留。

### T4 NIO Streamable HTTP 适配腿 + 端点发现文件 + 只读降级

- **action**
  1. 新建 `McpHTTPTransport.swift`（conformance server `HTTPApp.swift` 正本移植，~250 行，
     R2）：`ServerBootstrap` + `configureHTTPServerPipeline` + **SSE 泵**（
     `handleJSONRPCRequest` 返回 `.stream` → `AsyncThrowingStream<Data>` 泵进 HTTP chunked
     body——探针首版漏泵 client 挂死的坑，正本 writeResponse stream 分支照抄）+ POST
     JSON-RPC 与 GET SSE 端点。
  2. **per-session transport 字典**（§RQ-14-1③）：每 client 一次 initialize → 新建
     `StatefulHTTPServerTransport` 实例 + SessionContext 入字典（单 transport = 单 session
     实测：第二个 initialize → 400）；**上限 4 并发 session**（超出 503 + 文本）。
  3. 绑定 `127.0.0.1` **硬编码常量**（D-14-CONTEXT-6①——「无设置项的底线」；端口默认随机，
     绑定成功回读实际端口）；非回环绑定代码路径（设置显式开启后 0.0.0.0 + Bearer 必须）本
     plan 落常量与分支，UI 开关在 14-4。
  4. `Origin/Host` 校验 = SDK 内置 validationPipeline 默认开（`OriginValidator.localhost()`
     等——探针实测 403/421 行为）；**匹配规则注意**：`localhost(port: nil)` 模式 =
     `http://localhost:*`，**要求端口存在**，无端口 Origin 被拒（D6——工具文档/示例带端口）。
  5. GUI 内嵌宿主启动/停机（`McpServerController`）：偏好键读面（UserDefaults 键 + 常量，
     UI 开关控件在 14-4）开 → flock → 绑端口 → 写 json → 服务；**优雅停机**（偏好关 /
     `applicationWillTerminate` 挂点）：停止接受新请求 → in-flight **有界排空 5s** → 删
     json → unlock → 退出（§RQ-14-14 停机处置）。无头 `--mcp-http` 同款绑定纪律（写 json）。
- **证据**：`McpHostTests`——HTTP 端到端（SDK `HTTPClientTransport` 对打：connect →
  initialize[2025-11-25 回显] → tools/list → tools/call → disconnect，exit 0）；`Origin:
  http://evil.example.com` → 403 / 无 Origin 放行 / 无端口 localhost Origin 被拒 / Host 不
  匹配 → 421；127.0.0.1 绑定常量断言（源码级 + 运行时 socket 实测）；第二实例 flock 失败 →
  只读 + serverReadOnly；端点文件写删时序（启停循环后 json 不残留）+ 崩溃残留 → 试锁清理。

### T5 安全面（Bearer validator）+ hello 双宿主端到端收口

- **action**
  1. 新建 `McpBearerValidator.swift`（R4；~30 行 `HTTPRequestValidator`）：查
     `Authorization: Bearer <共享串>`；生成 = `SecRandomCopyBytes` 32 字节 → base64url
     （~43 字符）；存储 = **keychain 真身 + 发现文件只放 `auth: "bearer"` 标记**（token 真身
     不入文件）；fallback = `~/.lightamer/mcp-token` 0600；校验 = **常量时间比较**（手写
     `constantTimeComparison`，公开仓审计注意项）；回环默认 `auth: "none"` 零 token
     （攻击面最小——非回环才启用 Bearer 分支）。
  2. validator 进 `validationPipeline`（Bearer 启用时）；断言顺序 = Origin/Accept/Content/
     Protocol/Session 既有 pipeline + Bearer 追加。
  3. **hello 双宿主端到端**（RQ-14-1 头号探针收口 = 本 plan SC 级判据）：同一 registry
     内核 × 三形态——stdio 管道四条消息（initialize → notifications/initialized →
     tools/list → tools/call ping + count_images）§RQ-14-1② 报文形状逐条断言；HTTP
     client 对打（T4）；InMemory 进程内（T2）——三形态同一 handler 结果一致（双宿主行为
     一致性验证红线 + InMemory 第三形态）。
  4. 非回环负例（自动化可测部分）：模拟非回环配置无 token → 请求拒绝；带错 token → 401。
- **证据**：`McpHostTests` 端到端三形态绿 + Bearer 负例绿；`McpRegistrySnapshotTests` 绿；
  token 不落盘断言（json 无 token 字段 + keychain 写入成功）。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1768/11skip/0fail** + 新增，0 fail；收尾轮 = 当前 HEAD
  + 新增）；Core 零 import grep 自证输出贴 SUMMARY；TODO.md 开 Phase 14 节 + 14-1 勾选；
  `14-1-SUMMARY.md`（任务表/commit 表/证据/探针对账：本 plan 实测 vs research §0 探针数字
  偏差注记）；`14-1-DECISIONS.md`（headless 分叉实测结论或回退裁决、探针工具退役时点、
  端口随机范围、session 字典策略、keychain 拼写、其余执行期决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（1768 → N，0 fail）；grep 自证输出；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| headless 分叉 | `--mcp-stdio`/`--mcp-http` 两形态回包 + GUI 回归零害（或 DECISIONS 回退裁决） | `xcodebuild build` + 实机启动记录 |
| registry 缝 | 探针面快照（name/inputSchema/annotations 逐字）+ InMemory tools/list | `Scripts/test-direct.sh 'McpRegistrySnapshotTests'` |
| 锁与降级 | flock 互斥/退出释放/崩溃自释/只读降级/试锁清理/stdio 零 json | `Scripts/test-direct.sh 'McpHostTests'` |
| HTTP 腿 | 端到端对打 + Origin 403/无端口拒/Host 421 + 127.0.0.1 常量 + 停机排空零残留 | `Scripts/test-direct.sh 'McpHostTests'` |
| 安全面 | Bearer 拒绝/常量时间比较/token 不落 json | `Scripts/test-direct.sh 'McpHostTests'` |
| 回归 | 全 suite 0 fail（基线 1768+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |
| 分层 | Core 零 import MCP/NIO | `grep -rn "import MCP\|import NIO" LightamerCore/`（零命中，输出入 SUMMARY） |

## 验收标准（Acceptance）

- [ ] swift-sdk 0.12.1 **exact pin** 入 Project.swift + `.package.resolved` 入库 + SPM
      policy 注释登记（第二依赖 + 传递 swift-nio 等，D1）；`tuist generate` 后构建绿
- [ ] `McpToolRegistry` 纯 Swift 缝（Core 零 import MCP/NIO grep 自证）+ 错误码枚举全表
      一次落齐 + `McpTimeouts` 常量表 + `McpRenderGate` 渲染串行基建
- [ ] `@main` headless 分叉实测收口（两形态回包；GUI 回归零害；不过 → executor target
      回退裁决入 DECISIONS——R3 关闭）
- [ ] flock 写者权五态（互斥/退出释放/崩溃自释/只读降级 serverReadOnly/试锁清理残留）+
      stdio 宿主只持锁不写 json（D2）+ 端点文件 schema verbatim §RQ-14-2 + L009 原子写
- [ ] NIO 适配腿（HTTPApp 正本移植）：SSE 泵 + per-session 字典（上限 4，503）+
      127.0.0.1 硬编码常量 + Origin/Host 内置管线实测（403/421/无端口拒）+ 优雅停机 5s
      排空 + `applicationWillTerminate` 挂点
- [ ] Bearer validator（SecRandom 生成/keychain 真身 + json 只放标记/0600 fallback/
      常量时间比较/非回环才启用）+ hello 双宿主端到端三形态（stdio/HTTP/InMemory）一致
- [ ] tools/list 快照框架落位（分域分组：probe/editing/culling）+ 探针面快照绿
- [ ] 全 suite 0 fail（1768+新增）；每任务独立提交 + 边界查 config 开关；不 push；
      SUMMARY + DECISIONS 落盘
