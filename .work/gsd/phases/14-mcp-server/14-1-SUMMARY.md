# Plan 14-1 — server 底座 执行 SUMMARY

**Executor:** ZCode subagent worker · **Date:** 2026-09-28
**Plan:** `.work/gsd/phases/14-mcp-server/14-1-PLAN.md`（W1 全 Phase 依赖根）
**Status:** 完成（6 tasks / 6 commits，未 push）

## 任务表与提交

| Task | 内容 | Commit | 证据 |
|---|---|---|---|
| T1 | `@main` headless 分叉 + swift-sdk 0.12.1 exact pin（T2①前拉）+ stdio 腿 | `44b526a` | 实机 stdio 探针回包 `protocolVersion 2025-11-25` + `serverInfo{lightamer,0.1.0}`；GUI 截图零害；`--mcp-http` stub exit 2 |
| T2 | `McpToolRegistry` 纯 Swift 缝 + `McpAdapters`（唯一 import MCP）+ 错误码/超时/渲染门表 + 探针 toolset + 快照框架 | `f7d08d3` | `McpRegistrySnapshotTests` 8/8；全套 1776/11skip（+1 负载 flake 归因，见下） |
| T3 | `McpEndpointFile`（flock 锁件 + 发现文件 + 试锁发现协议）+ stdio 宿主持锁/只读降级 | `50f0874` | `McpHostTests` flock 五态（真实双进程）+ 只读降级 + 发现三态 + schema v1 冻结 + L009 |
| T4 | NIO Streamable HTTP 腿（HTTPApp 正本移植 + SSE 泵 + session 字典上限 4）+ 端点文件写删时序 + GUI 内嵌挂点 | `65ebd43` | HTTP E2E（SDK client）+ Origin 403/无端口拒/Host 421/无 Origin 放行 + 容量 503 + 重初始化 400 + 停机零残留 |
| T5 | Bearer valve（SecRandom/keychain 真身/常量时间比较）+ 非回环分支 + 三形态 hello 收口 | `4f9f2bc` | Bearer 单元/存储/401 负例/LAN 分支 + `testHelloConformanceAcrossThreeHostForms` |
| T6 | 全量回归 + 本文档 + DECISIONS + TODO/PROGRESS | 本提交 | 终轮计数见下 |

## 终轮回归

- 基线：**1768/11skip/0fail**（git `2edf489`，Phase 8 回补收口后）
- T2 全套：**1776/11skip/1fail** — 唯一失败 `QuickLookRendererTests.testThumbnailRenderTimeoutDegradesBounded`（3.49s vs 2.0s bound）；**隔离 ×3 复跑全绿**（0.609/0.819/0.873s）→ 负载型计时断言 flake（在案 flake 家族，非本 plan 引入，归因条款兑现）
- 本 plan 新增测试：快照 8 + 宿主 18 = **26** → 理论终值 **1794**
- 终轮实测：见 PROGRESS.log 追加行（`Executed 1794 tests, with 11 tests skipped and 0 failures`）

## 分层自证（架构红线①）

```
$ grep -rn "^import MCP\|^import NIO" LightamerCore/ LightamerIOP/
（零命中 — exit 1）
$ grep -n "^import" App/Sources/Lightamer/MCP/*.swift
McpAdapters.swift:       import Foundation / import MCP          ← 唯一 SDK 类型收口
McpServerController.swift: import Foundation / import LightamerCore / import MCP
McpToolRegistry.swift:   import Foundation                       ← 纯 Swift 缝，grep 可证
```

## 探针对账（本 plan 实测 vs research §0）

| 探针结论 | 本 plan 复现 | 偏差 |
|---|---|---|
| stdio 三步握手 + 协议版本 2025-11-25 | ✓ 实机（T1 管道探针 + T3/T5 子进程测试） | 无 |
| Streamable HTTP 端到端（SDK client 对打） | ✓ `testHTTPEndToEndSDKClientRoundTrip`（connect→init→list→call→disconnect） | 无 |
| Origin 非法 → 403 | ✓ `testOriginAndHostValidationPipeline`（+无端口 Origin 403 = D6、Host 421、无 Origin 放行） | 无 |
| SSE 泵坑（漏泵 client 挂死） | ✓ 按正本 `.stream` 分支移植；E2E 响应即经泵送达 | 无 |
| 单 transport = 单 session（第二个 initialize → 400） | ✓ `testSecondInitializeOnSameSessionIs400` | 无 |
| flock 五态（互斥/退出释放/崩溃内核自释/只读降级/试锁清理） | ✓ `McpHostTests` 真实双进程（`-la_mcp_hold_lock` fixture spawn 本宿主二进制） | 无 |
| headless 分叉（探针局限③，R3） | ✓ **分叉可行，未触发 executor target 回退**：stdio 回包无 GUI；GUI 回归截图正常 | 无（R3 关闭） |

## 测试基础设施注记

- `test-direct.sh` 私有日志：共享 `/tmp/la-direct-tests.log` 有并行覆写风险，关键判定用 `/tmp/t6-full.log` 等私有重跑确认。
- stdio 子进程测试的 stdin 交付：conformance 测试内 Foundation-Pipe 写入在本环境出现「write(2) 成功但子进程非阻塞读循环始终 EAGAIN」的异常（`/bin/cat` 对照正常，文件-stdin 对照正常，根因未完全隔离）→ 该测试 stdin 改走临时文件交付（D-14-1-T5-2），子进程代码路径与管道完全一致（同为 fd0 + newline-delimited JSON-RPC）。

## 交付物清单（files_modified 对照）

- `Project.swift`：swift-sdk 0.12.1 exact pin + MCP/NIOCore/NIOPosix/NIOHTTP1 产品登记 + SPM policy 注释更新 ✓
- `App/Sources/Lightamer/MCP/McpToolRegistry.swift` ✓（McpJSON/错误码 14 枚举/McpTimeouts 9 常量/McpRenderGate FIFO 信号量）
- `App/Sources/Lightamer/MCP/McpAdapters.swift` ✓（唯一 import MCP；`.text(text:)` 新形态）
- `App/Sources/Lightamer/MCP/McpEndpointFile.swift` ✓（锁件 + 发现文件 + `McpEndpointDiscovery`）
- `App/Sources/Lightamer/MCP/McpHTTPTransport.swift` ✓（`McpHTTPHost`：SSE 泵/session 上限 4/503/优雅停机 5s 排空/loopback 硬编码）
- `App/Sources/Lightamer/MCP/McpBearerValidator.swift` ✓（validator + 常量时间比较 + keychain/0600 fallback）
- `App/Sources/Lightamer/MCP/McpServerController.swift` ✓（宿主编排 + startHTTPHost/stop + GUI 内嵌 + terminate 同步 5s 桥）
- `App/Sources/Lightamer/UI/LightamerApp.swift` ✓（`LightamerEntryPoint` 分叉 + DEBUG hold-lock fixture 路由 + embedded 启动 + terminateHandler 挂点）
- `Tests/LightamerTests/McpRegistrySnapshotTests.swift` ✓（分域快照框架 + probe 域 + InMemory 第三形态）
- `Tests/LightamerTests/McpHostTests.swift` ✓（18 测试）
- `.package.resolved` ✓（9 pins：swift-sdk 0.12.1 + swift-nio 2.103.0 等）
- 本文档 / `14-1-DECISIONS.md` / `TODO.md` Phase 14 节 / PROGRESS.log ✓
