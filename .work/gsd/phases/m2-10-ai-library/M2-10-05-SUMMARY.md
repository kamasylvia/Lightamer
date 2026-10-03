# M2-10-05 SUMMARY — 推理进程隔离 crash-safe（worker 进程 + 帧协议 + 降级链）

> 执行 worker 收口（2026-10-03/04 夜）。三个功能提交 + 本收口提交；
> 裁决与偏离正本 = `M2-10-05-DECISIONS.md`（§1..15）。
> 提交顺序 = T1→T3→T2（依赖序倒置，§1）。

## 提交账

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `f1cc3a3` | AIWorkerProtocol（Core：UInt32 BE 长度前缀 + JSON envelope + 8MB 构造期分界 + 坏帧容忍 + 管道帧 reader）+ AIWorkerMain（App：actor 帧循环 open/run/ping/stop + `(profile,units)` InProcessMLModelRunner 会话缓存 + SIGTERM exit 0 + LIGHTAMER_TEST_AI_WORKER_CRASH 钩子 + DEBUG spike op）+ LightamerEntryPoint `--ai-worker` 分叉臂（--mcp 臂后，永不构造 SwiftUI App）+ AIWorkerProtocolTests 10 |
| T3 | `3afc5d4` | CompatRecord（Core：ai-compat.json 读写——machineKey=hw.model/kern.osversion per 模型 per units 记账、两模型同 units 崩→全禁、CPU 崩不记、同目录 tmp+replaceItemAt 原子写、坏 JSON 容忍、resetAll、路径+machineKey 双注入）+ CompatRecordTests 8 |
| T2 | `65da2d1` | AIWorkerClient（App：真子进程 spawn/generation 计数/deadline 轮询/超时 SIGKILL+收尸/管道死亡折叠 typed/降级链编排/AIInferencing conformer/降级不可用不回退）+ AIInferenceService 装配单点换 WorkerClient（InProcess 保留为 fixture+worker 会话对象）+ AIWorkerClientTests 9（真子进程生命周期 + IPC spike）+ worker 侧两修复（spike 路由 / 内联 await） |
| T4 | 本提交 | AC 机检 + 全套对账 + SUMMARY/DECISIONS/GOAL-STATE/LESSONS + BUNDLE-MAP 三行 |

## 测试数字（基线 2863/16/0）

- **终账：`TOTAL|2890/16/0`** = 2863 + **27 精确对账**
  （AIWorkerProtocolTests 10 + CompatRecordTests 8 + AIWorkerClientTests 9，
  全落 App；App 551→578）。
- 七 bundle 逐值（本轮实测）：IOP 467/1/0（peakRSS 6456MB）、IOPParity
  362/3/0（5982MB）、Layers 298/3/0（1056MB）、Library 568/4/0（613MB）、
  Sessions 279/4/0（1323MB）、Export 338/1/0（5846MB，红线门零漂移）、
  **App 578/0/0**（2831MB）；peakRSS 最大 IOP 6456MB < 8192 门，零
  MEMFAIL；skip 16 = 基线**零新增**。
- **首轮全套（夜间 --all）注记**：Library 一例
  `LibraryThumbnailBridgeTests.testPrioritizeReordersQueuedProductions`
  并发时序 flake（缩略图产出队列顺序竞争——本波零接触域，改动文件机检
  无缩略图代码）；脚本「前红即停」在 Library 后截断（Sessions/Export/App
  未跑）。**隔离复跑**：该类 10/0/0 + Library 全量 568/4/0 + 三补跑
  bundle 全绿 → 终账成立。与 M2-10-04 三崩家族同属环境型归因口径。

## IPC spike（OQ-10-C 定稿，数字正本 DECISIONS §2）

真 worker 子进程实测（50 次中位；TIFF 10 次）：ping RTT 0.025ms /
256² JPEG 字节通道 0.041ms / 路径通道 0.094ms / 50MP TIFF（196MB）
路径通道 19.4ms。**8MB 分界维持**：小图双通道均亚毫秒；大图字节通道
假想 ~260MB base64 过管道对 19.4ms 的路径通道量级碾压。探针 = DEBUG
spike op（RELEASE 无此 op）；JSON 落 `/tmp/lightamer-ipc-spike.json`。

## crash 注入测试证据（E1 真链）

- **真子进程**：全部生命周期测试 spawn `Bundle.main.executableURL
  --ai-worker`（直启宿主即 app 二进制，DECISIONS §7）；零 mock Process。
- **真崩溃**：钩子命中 open → 子进程 `Darwin.exit(9)` 实测（手动探针
  独立验证 exit code = 9）；客户端断言死亡 detail 含 `exit code 9`。
- **链证据**：`testCrashInjectionRestartsGenerationAndRecordsNonCPUUnits`
  ——三档全崩 → `.workerExhausted`，CompatRecord 有 .all/.cpuAndGPU、
  **无 .cpuOnly**，generation 3；
  `testCrashSequenceTerminatesOnCPUWithTheProfileFailureSurfaced`——
  钩子限 `@all,cpuAndGPU` → cpuOnly 档活（资产缺席 error 帧直通
  `.requestFailed`），记账恰 {.all, .cpuAndGPU}；
  `testPreseededExclusionSkipsTheCrashedRungEntirely`——预记账 .all →
  链首跳 cpuAndGPU，.all 条目字节未动。
- **超时 kill**：注入零预算 deadline → SIGKILL + `waitUntilExit` 收尸
  （`childProcessIdentifier` 归 nil）→ typed `.workerCrashed("no
  response within 0 s")` → 次请求 generation+1 复活。
- **管道断裂**：外部 `kill(pid, SIGKILL)` 真杀 → pump EOF → 折叠
  typed（detail 含 exit code 9）→ 编辑器侧复活续用。
- **不可用不回退**：不存在可执行 → `.workerUnavailable`，InProcess
  兜底代码在装配面**不存在**（OQ-5-A 字面）。
- **真模型探针**（资源门）：bundled CLIP 在场 → 224² JPEG 经 worker
  真 open+run → 512 维有限向量（缓存热 0.685s；首跑冷编译 ~400s 后
  暴露 run 挂 bug——LESSONS L064）；缺席环境 XCTSkip 可审计。

## 交付面形态（KD 对照）

- **帧协议（KD-1）**：4 字节 BE 长度 + JSON UTF-8；请求
  `{id,op,profile,units,payload}`；响应 `{id,ok,result|error,culpritUnits?}`
  ——culprit 回传 = 降级记账输入（DECISIONS §10 二分语义）；8MB 构造期
  typed 拒（字节通道只给小图）；坏帧两形可存活（坏 JSON 回 error 帧保活 /
  越界前缀 skip 精确字节数重对齐），仅 EOF/管道断裂折叠进程级。
- **worker 体（KD-2）**：`LightamerEntryPoint` 臂序 flock(DEBUG) →
  `--mcp` → **`--ai-worker`** → GUI；分叉臂 8 行级半径（机检 hunk 在案），
  永不构造 SwiftUI App；无头纪律（AIWorkerMain 零 SwiftUI/AppKit import）；
  SIGTERM→exit 0；MLModel 会话按 `(profileID, units)` 缓存；worker 自己
  的编译缓存树（DECISIONS §6）；路径通道协议形状就绪、推理腿归 M2-10-06
  （typed error 帧，DECISIONS §10 同口径）。
- **WorkerClient（KD-3）**：串行请求队列单飞 + pump 线程邮箱 +
  deadline 1s 切片轮询；超时 SIGKILL+收尸（terminationStatus 可读=无
  僵尸）；降级链 = 尝试序 − 预剔除，增量剔除（DECISIONS §13——record
  重算复活 CPU 档的实现 bug 被测试抓出后弃用）；open 900s/run 600s/
  MAX_RETRIES=4 常量平移；SIGPIPE 全局忽略（§11）。
- **CompatRecord（KD-4）**：`{machineKey:{units:{models,all,last}}}`；
  两模型同 units 崩→`all=true` 全禁；CPU 崩恒不记；坏 JSON=空记录重建；
  resetAll 删文件（M2-10-07 按钮消费）；路径+machineKey 注入，默认路径
  仅装配点解析。
- **装配切换（AC#7）**：`AIInferenceService.engine()` 单点换
  AIWorkerClient——消费面（02 引擎/03 registry/搜索/全文）**零 diff 机检
  在案** + AnalysisRegistryTests 13/0/0 + SemanticSearchTests 10/0/0；
  bundled 资产探针保留为 nil 门（「语义模型未就绪」面不变）；worker 失败
  typed 直通，InProcess 兜底不存在。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | 帧协议 round-trip/8MB typed/坏帧保活 | ✅ AIWorkerProtocolTests 10/0/0（BE golden/管道 round-trip/越界 skip 重对齐/坏 JSON 对齐/EOF typed/双通道形状/宽容字段） |
| 2 | 分叉臂永不构造 SwiftUI App | ✅ 臂序在 flock/--mcp 后、`return` 先于 `LightamerApp.main()`；真子进程 ping/open/stop 全程无 GUI（宿主启动即臂内停驻）+ App suite 578/0/0 零回归 |
| 3 | crash 注入：open 崩→generation 重启→换 units 续试 | ✅ 真 exit(9)；generation 3；两档记账 + CPU 不记 |
| 4 | 超时 kill + 管道断裂折叠 + MAX_RETRIES exhausted | ✅ 零预算 deadline kill 收尸复活；外杀 EOF 折叠 typed；三档烧尽 exhausted |
| 5 | 降级链 excluded 剔除/CPU 不记/两模型全禁 | ✅ 预剔除跳档 + 记账断言 + CompatRecordTests 8（全禁翻转/同模型不翻） |
| 6 | CompatRecord 原子写/坏 JSON/reset/machineKey 注入 | ✅ 终态文件 + 无 .tmp 残留 + 坏 JSON 重建 + reset 幂等 + 纯函数注入 |
| 7 | 装配切换零涟漪 + workerUnavailable 不回退 | ✅ 消费面零 diff + 双 suite 绿 + `.workerUnavailable` 断言 |
| 8 | 资源门 0 fail | ✅ 2890/16/0（真模型探针激活态真跑；无模型环境 XCTSkip 登记） |
| 9 | 登记闭环 + diff 边界 | ✅ 三测试文件 Project.swift × BUNDLE-MAP 双命中；源码 diff = front-matter 全量（12 文件含账本；外部并行 commit 5fbda86 剔除，DECISIONS §15）；LightamerApp hunk = 分叉臂 8 行 |

## 偏差与申报（全量清单）

front-matter 外源码文件：**零**。计划文本外执行裁决 15 项全录
DECISIONS（§1 提交序倒置 / §9 钩子扩展形 / §10 culprit 二分 /
§13 链增量维护 / §14 生成计数语义为实质新增口径，晨审可推翻，
改动半径各一处函数/常量）。

## 首轮测试抓出的真缺陷（防线自证）

- **UInt8 原位移位截断**（L063）：BE 长度装载 `UInt8 << 24` 结果仍
  UInt8——5359 字节帧读成 239；小帧 golden 假绿掩蔽，512 维 float 帧当
  场抓红。逐字节先宽化再移位 + >255 字节 round-trip 钉死。
- **actor 执行器饿死死锁**（L064）：`serve()` 同步阻塞读占用 actor
  执行器，`run` 派生的 async 推理子任务永不到度（ping/open 正常、仅
  run 挂的高度误导症状）；真模型探针 482s exhausted 暴露。改内联
  await（挂起即让位）。
- **链重算复活 CPU 档**（DECISIONS §13）：从 CompatRecord 重算降级链
  把 CPU 崩剔除的 rung 加回（CPU 不入账 → 重算恒复活）→ .cpuOnly 双
  崩 generation 4 ≠ 3 当场抓红。改增量剔除。
- **spike op 路由**：`"spike"` 非枚举值 → opKind=nil 先命中 unknown-op
  臂；unknown-op 臂内前置拦截修复。

## 交接（下游 plan）

- **M2-10-06（AI 出片/增强）**：worker 路径通道协议形状已就绪
  （`{inPath,outPath,tile}` 帧形状测试钉死）；worker `open` 对增强族
  （embeddingDim==nil）回 typed「opens via the M2-10-06 leg」error 帧
  ——06 落地 = AIWorkerMain 增强腿 + InProcessMLModelRunner 单资产形态
  扩展；会话缓存/降级链/CompatRecord 记账面即取即用。
- **M2-10-07（LCR/ACA 设置页）**：「重置 AI 兼容性记录」按钮 =
  `CompatRecord.resetAll()`（默认路径解析在 AIInferenceService——
  `CompatRecord.defaultPath()`）；worker 崩溃的呈现面 = typed
  `.workerExhausted/.workerUnavailable` 文案（设置页指引重置）。
- **验收轮抽查点**：crash 注入三测试（真 exit(9) + 记账面）；
  `testPreseeded…` 的预剔除语义；分叉臂 hunk 半径；MCP 零 diff。

## 阻塞节

无 E3 阻塞。环境注记：①首轮 --all 的 Library 缩略图时序 flake
（隔离全绿，非本波域）+ 脚本「前红即停」语义使后续 bundle 未跑——
验收轮全套复跑注意该截断形态；②worker 编译缓存首轮冷（~400s），
与 02 波 in-process 首编译同水位。
