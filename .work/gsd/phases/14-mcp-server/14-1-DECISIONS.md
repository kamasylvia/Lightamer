# Plan 14-1 — 执行期决策（DECISIONS）

> 纪律条款：RESEARCH/CONTEXT 未覆盖的细节登记于此，不臆造。

## D-14-1-T1-1 swift-sdk pin 前拉至 T1 提交

Plan 将 Project.swift 的 pin 记在 T2①，但 T1 的无头装配（`Server` + `StdioTransport`）本身依赖
SDK 产品。pin + `.package.resolved` 随 T1 提交落地（commit `44b526a`），T2 提交（`f7d08d3`）在
其声明文件之外额外包含 McpServerController 的 T3 预写代码（该文件跨任务共享，详见
D-14-1-T1-2）。**影响：`f7d08d3` 单独 checkout 不能编译（引用 T3 才落地的
McpEndpointFile.swift 类型）；两提交连续同批，对 push 批次无影响。**

## D-14-1-T1-2 headless 分叉实测结论（R3 关闭）

自定义 `@main enum LightamerEntryPoint`（@MainActor static main）分叉实测成立：
- `--mcp-stdio` 子进程经 stdio 回包 `protocolVersion 2025-11-25` + serverInfo，全程无
  NSApplication/窗口（sample 证实仅 transport 线程 + dispatchMain 驻留）；
- GUI 路径 `LightamerApp.main()` 正常出窗（CGWindowList on-screen + 窗口截图：
  侧栏/工具栏/空态/检查器完整渲染）；
- `@NSApplicationDelegateAdaptor` 与 `@State` 图谱确认为实例属性，仅在 `App.main()` 的
  实例创建时初始化——分叉不构造 App struct 即完全绕开（research §RQ-14-1④ 预期证实）。
**executor target 回退未触发。**

## D-14-1-T2-1 `McpJSON` 类型化 JSON 替代 plan 草图 `[String: Any]`

handler 签名 plan 草图为 `([String: Any]) async throws -> McpToolOutput`；`Any` 在 Swift 6
严格并发下无 Sendable 证明且跨 actor 传递不合法。改为手写 `McpJSON` 值枚举
（null/bool/int/double/string/array/object + 下标便利），适配器层做 `Value ↔ McpJSON`
双向转换。语义等价（含 null 与「键缺失」的区分）。

## D-14-1-T2-2 registry 为 actor + 注册即替换语义

注册发生在宿主装配期（async），dispatch 在请求期——actor 隔离最简且 Sendable 天成。
`register` 允许同名替换（快照测试兜底防误改）；writer 检查以闭包缝注入（T3 flock 接线），
非持锁进程的写面工具在 handler 前置拦截，错误文本携带 `mcp-endpoint.json` 处置指引。

## D-14-1-T2-3 tools/list 的 inputSchema 回显断言为「Value 语义等价」

SDK `Value` 编码不保键序（实测 `{"type":...,"properties":...}` 回显变序），逐字 JSON 断言
只能在 registry 描述符层做（`assertSnapshot` 的 `inputSchemaJSON` 全等）；经 transport 回显的
断言采用解码后 `Value` 相等（语义等价）。两层合起来仍是「改 schema 必须显式改快照」。

## D-14-1-T3-1 两进程 flock 测试用宿主二进制 + DEBUG fixture

XCTest 单进程内无法制造真实双进程；新增 `#if DEBUG` 的 `-la_mcp_hold_lock <dir>` fixture
模式（镜像 `-la_sidecar_probe` 探针先例）：acquire → 打印 `LOCKED <path>` → 读 stdin 驻留。
`McpHostTests` 以 `Process` spawn 本宿主二进制实测互斥/退出释放/SIGKILL 内核自释（<2s 界）。
崩溃残留零处置代码（无 O_EXCL/pid 校验）为「不做」的显式实现。

## D-14-1-T3-2 只读降级测试用合成写面工具

14-1 探针 toolset 无写面工具（写面在 14-2/14-3）；只读降级钩子以 `requiresWriter: true` 的
合成工具（`synthetic_write`/`synthetic_read`）在 registry 层直测，错误文本断言携带
`mcp-endpoint.json` 指引。真实写面工具的 serverReadOnly 负例由 14-2/14-3 消费。

## D-14-1-T4-1 NIO 三产品显式进 App target 依赖

research D1 已定「swift-nio 是主 app 真实编译依赖」；tuist 显式解析下 App target 直接
`import NIOCore/NIOPosix/NIOHTTP1` 需要产品级声明，故 Project.swift App target 增列三产品
（版本仍由 `.package.resolved` 的 swift-nio 2.103.0 钉住）。

## D-14-1-T4-2 HTTP start() 语义改为「bind 后返回」+ 停机排空计数器

conformance 正本 `start()` 阻塞在 `channel.closeFuture`（standalone daemon 形态）；本 plan
HTTP 腿是宿主托管形态（GUI/无头守护自行驻留），start 在 bind 成功后返回，实际端口经
`boundPort` 读回。优雅停机：关监听 → in-flight 计数器有界排空（默认 5s = `McpTimeouts.
shutdownDrain`）→ 关全部 session transport；发现文件删除与 flock 释放在调用侧
（`HttpHostHandle.stop`）按 §RQ-14-14 顺序执行。

## D-14-1-T4-3 conformance 正本的 MainActor 小改 + JSONRPCMessageKind 本地重写

正本 HTTPHandler.channelRead 的 `Task { @MainActor in ... }` 改为普通 `Task`（避免子进程外
对主执行器的无谓耦合）；`JSONRPCMessageKind` 为 SDK package-internal 类型，宿主侧以本地
`isInitializeRequest(_:)`（method == "initialize" 且带 id）等价重写。

## D-14-1-T5-1 非回环分支「不启动」优于「只读启动」

无头 stdio 宿主锁失败 → 只读启动（agent 会话仍有读价值）；HTTP 宿主锁失败 → **不启动**
（exit 4 / GUI 静默跳过 + 日志）：以「被发现」为全部目的的网络宿主若只读启动，会让 launcher
与外部 agent 连到一个拒绝全部写面的端点——错误信号必须前移到启动时。

## D-14-1-T5-2 conformance 测试 stdio 腿的 stdin 走临时文件交付

测试内 Foundation-Pipe 写入在本机稳定复现异常：`write(2)` 返回成功、lsof 证实父子管道端点
匹配、但子进程非阻塞 read 循环持续 EAGAIN（`/bin/cat` 对照正常、**文件-stdin 对照正常**、
shell 管道正常；根因未完全隔离，样本与复现脚本见执行记录）。conformance 的 stdio 腿改用
临时文件作子进程 stdin（fd0 + newline-delimited JSON-RPC 的子进程代码路径与管道完全一致），
结果断言不变。**产品代码不受影响**（真实 agent 场景 stdin 即管道，由 client 侧写入时序决定，
SDK readLoop 的 EAGAIN-10ms 轮询语义不变）；此疑难点留痕待后续环境复验。

## D-14-1-T5-3 stdio 响应按 id 配对（非位置）

实测 stdio 宿主对 5 消息连发的响应顺序为 id1→id3→id4→id2（tools/list 载荷最大最后完成）。
MCP 以 id 配对、不保证顺序——所有子进程断言按 id 匹配，不按行位置。

## D-14-1-T5-4 探针 toolset 不做 String Catalog 本地化

D-14-CONTEXT-3② 的 zh/en 双语描述要求落在 14-2/14-3 的终面工具（19 封闭集）；probe
（ping/count_images）为 14-4 T1 退役的非终面，描述内联英文，DECISIONS 留痕。

## D-14-1-T5-5 McpRenderGate 无取消传播（v1）

`withRenderGate` 等待者以 CheckedContinuation 排队，不响应取消（渲染本身不可安全中断，
QL boundedWait 同语义）。14-2/14-3 消费时若需要取消语义，在 gate 外层用 timeout 包裹
（McpTimeouts.renderAndCrop）。

## D-14-1-T6-1 QuickLook 计时 flake 归因（在案条款兑现）

全套 1776 轮 `testThumbnailRenderTimeoutDegradesBounded` 失败（3.49s > 2.0s bound，负载下
降级路径超时断言）；隔离重跑 ×3 全绿（QuickLookRendererTests 10/0 ×3，该用例 0.6-0.9s）。
归因 = 全套 730s 负载下的计时抖动，非 Phase 14 引入（该测试先于本 plan 存在，且 14 改动
不触碰 QL 路径）。按 plan 纪律 3 单列，不计违约。
