# M2-10-05 ACCEPTANCE — 推理进程隔离 crash-safe（worker 进程 + 帧协议 + 降级链）

> 验收 subagent（零共享上下文，实测核验不轻信）。验收对象 = 四提交
> `f1cc3a3`（T1）/ `3afc5d4`（T3）/ `65da2d1`（T2）/ `1491f8f`（T4 收口，
> HEAD，未 push）。正本输入 = PLAN（含 checker 回注 M6）+ SUMMARY +
> DECISIONS（§1..15）+ LESSONS L063/L064。验收日期 2026-10-04。
> 基线 = M2-10-04 验收终态 2863/16/0（HEAD `9114c48`）。

## 结论

**PASS / 0 error + 0 minor + 3 observation** —— AC 9/9 全过；提交序倒置
（T1→T3→T2，DECISIONS §1）**追认采纳**；全套独立复跑**对账精确成立**
`2890/16/0`（七 bundle 逐值零漂移；首轮 --all 在 Library 复现执行批申报的
同一缩略图时序 flake——本波零接触域，隔离复绿 + 三补跑口径与执行批逐值
一致）；**crash 链 E1 真链亲证升级**：除全套测试外，验收方以独立 python
探针亲手驱动 worker 子进程——ping 往返 pid 一致、坏 JSON 帧→error 帧且
worker 存活（同 pid 续 ping）、stop→exit 0、钩子 open→**真 exit 9**；
L055 对策机检亲跑：七日志 `terminated abnormally` 全零 + crash 信号零
命中 + Executed 行与 BUNDLE 行逐值一致；**M2AI-10 翻勾**。

## 全套独立复跑（对账 2890/16/0）

`caffeinate -dis xcodebuild -project Lightamer.xcodeproj -scheme Lightamer
-configuration Debug build-for-testing`（TEST BUILD SUCCEEDED 亲验，退出码
不进管道——L034 对策）→ `caffeinate -dis Scripts/test-direct.sh --all`：

| bundle | 本轮 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 467/1/0（peak 6601MB） | 467/1/0（6456MB） | 零漂移 |
| IOPParity | 362/3/0（6001MB） | 362/3/0（5982MB） | 零漂移 |
| Layers | 298/3/0（1093MB） | 298/3/0（1056MB） | 零漂移 |
| Library | 首跑 568/4/**1** → 隔离复跑 **568/4/0**（616MB） | 568/4/0（613MB） | 零漂移（flake 见下） |
| Sessions | 279/4/0 | 279/4/0 | 零漂移（补跑） |
| Export | 338/1/0 | 338/1/0 | 零漂移（红线门，补跑） |
| App | **578/0/0**（2831MB） | 578/0/0（2831MB） | 零漂移，一轮过 |
| **TOTAL** | **2890/16/0** | 2890/16/0 | **精确对账** |

- 对账：2863（04 验收基线）+ **27 精确** = AIWorkerProtocolTests 10 +
  CompatRecordTests 8 + AIWorkerClientTests 9（全落 App 551→578）；
  `grep -c "func test"` = 10/8/9 与 BUNDLE-MAP 三行逐位一致。
- skip 16 = 基线**零新增**（1+3+3+4+4+1+0 亲点）；peakRSS 最大 IOP
  6601MB < 8192 门，零 MEMFAIL。
- **Library flake 复现记账**：首轮 `--all` 在
  `LibraryThumbnailBridgeTests.testPrioritizeReordersQueuedProductions`
  红（`("Optional(2)") is not equal to ("Optional(1)")`——产出队列顺序
  竞争，4.362s），脚本「前红即停」（`ANY_FAIL && break` 亲读）截断
  Sessions/Export/App。**按执行批同口径恢复**：该类隔离
  `--bundle Library 'LibraryThumbnailBridgeTests'` = **10/0/0** →
  Library 全量 = **568/4/0** → Sessions/Export/App 三补跑全绿（上表）。
  本波 diff 零缩略图代码（域外既有时序 flake；连续两轮复现，见 O-1）。
- **L055 对策机检亲跑**：七日志 `terminated abnormally` 计数**全零**；
  `Fatal error|EXC_BAD|Segmentation|crashed` 信号零命中；七 bundle 末行
  Executed（467/362/298/568/279/338/578 + skip 1/3/3/4/4/1/0）与 BUNDLE
  行逐值一致——本轮无假绿形态。
- **新 suite passed 行亲点**（App log）：AIWorkerClientTests /
  AIWorkerProtocolTests / CompatRecordTests / AnalysisRegistryTests 四
  suite `passed`；Library log SemanticSearchTests 10/0/0——02/03 消费面
  零涟漪数字亲证（13/0/0 + 10/0/0）。
- **真模型探针激活态亲证**：`testRealModelEmbedImageThroughWorkerProcess`
  **passed 2.409s 非 skip**——bundled CLIP 在场，224² JPEG 经 worker 真
  open+run 出 512 维有限向量（L064 揭穿测试本轮激活态绿）；资源门 skip
  逻辑在读码面核验（`XCTSkip("bundled CLIP assets absent…")`）。
- **IPC spike 复跑同量级**：验收轮 JSON（测试落盘
  `/tmp/lightamer-ipc-spike.json`）= ping 0.026ms / 256² JPEG 字节通道
  0.045ms / 路径通道 0.101ms / 50MP TIFF 15.57ms——与执行批（0.025/
  0.041/0.094/19.4）同量级（中位数轮次方差，申报带宽 15.5-19.4 内）；
  **8MB 分界维持**判定不变（小图双通道亚毫秒、大图路径通道量级碾压）。

## 逐 commit 边界（front-matter 对照）

| commit | 文件集 | 判定 |
|---|---|---|
| T1 `f1cc3a3` | AIWorkerProtocol.swift（Core 343 行）+ AIWorkerMain.swift（App 387 行）+ LightamerApp.swift（+8）+ AIWorkerProtocolTests.swift（208 行）+ Project.swift（+1） | == 申报 |
| T3 `3afc5d4` | CompatRecord.swift（Core 199 行）+ CompatRecordTests.swift（167 行）+ Project.swift（+1） | == 申报 |
| T2 `65da2d1` | AIWorkerClient.swift（567 行）+ AIInferenceService.swift（62 行换刀）+ AIWorkerClientTests.swift（397 行）+ Project.swift（+1）+ **AIWorkerMain.swift（+28/-19）** | == 申报 + 申报内触碰①（见下） |
| T4 `1491f8f` | SUMMARY + DECISIONS + GOAL-STATE（+1 行）+ LESSONS（+38 = L063/L064）+ BUNDLE-MAP 三行 | == 申报 |

- **T2 对 AIWorkerMain 的触碰 = 申报内**：SUMMARY 提交账 T2 行明文
  「worker 侧两修复（spike 路由 / 内联 await）」——①spike op 原始串在
  unknown-op 臂前拦截（`case nil` + `#if DEBUG`，DECISIONS §8）；②L064
  修复（`await run(request)` 内联，:189/:305）。两处均功能性必需且各有
  申报落点，非夹带。
- **全范围 diff 对表**：`git diff --name-only 81ae393..HEAD` = 16 文件 =
  front-matter 13（含 LESSONS「如踩坑」触发）+ BUNDLE-MAP（T4 申报）+
  RAWMAKASE-NOTES（外部并行提交，零交集）——**front-matter 外源码零**。
- **分叉臂 hunk 半径亲验**：LightamerApp.swift 全波 diff = **纯 8 行插入**
  （注释 5 + `if AIWorkerMain.runIfRequested() { return }` 3），位于
  `--mcp` 臂后、`LightamerApp.main()` 前；臂序 = flock(DEBUG) → `--mcp`
  → `--ai-worker` → GUI（亲读 :70-95）——worker 臂 `return` 先于
  `LightamerApp.main()`，永不构造 SwiftUI App（AC#2）。
- **MCP/Library/Sessions 零 diff 亲跑**：`git diff --name-only -- App/
  Sources/Lightamer/MCP/ App/Sources/Lightamer/Library/ LightamerCore/
  Sources/Library/ LightamerCore/Sources/MCP/ App/Sources/Lightamer/
  Sessions` = **零文件**（DECISIONS §4 机检复证）；Tests/ 仅三个新建
  文件——SemanticSearchTests / LabelEngineTests / AnalysisRegistryTests
  零修改（02/03 消费面零改亲证，AC#7）。

## crash 链抽查（读码 + 全套测试 + 独立探针三重）

### 1. crash 钩子双门（DEBUG + env）

- **读码**：钩子声明与消费全部圈在 `#if DEBUG`（AIWorkerMain :78-95 声明
  `crashHookEnvironment`/`crashHookShouldFire`、:240-244 消费
  `Darwin.exit(9)`）；全仓 grep 钩子符号 = 声明 + 消费 + 测试三处，零
  RELEASE 可达路径。`@units,units` 扩展形（DECISIONS §9）解析在读码面
  核验（`@` split + units rawValue 包含判断）。
- **钩子先于资产解析**（:238-244 注释 + 码序）：玩具 profile 无真资产
  亦崩——测试注入面成立。
- **独立探针亲证**：验收方 python 探针 spawn 宿主二进制 `--ai-worker`，
  env 设 `LIGHTAMER_TEST_AI_WORKER_CRASH=compat-probe-profile` → 发
  open 帧 → 子进程 **exit code = 9**（`HOOK-EXIT: 9`）。

### 2. 三档全崩 → exhausted + 记账面（AC#3/#5）

`testCrashInjectionRestartsGenerationAndRecordsNonCPUUnits` 断言亲读：
`.workerExhausted` + generation 3（每 rung 一 spawn，DECISIONS §14）+
`excluded` 含 .all/.cpuAndGPU、**不含 .cpuOnly**（CPU 崩不入账）+ 单模型
不翻转全禁。passed 0.119s（真 exit(9) 三连）。

### 3. 序列注入 → cpuOnly 档活（AC#5）

`testCrashSequenceTerminatesOnCPUWithTheProfileFailureSurfaced`：钩子限
`@all,cpuAndGPU` → 终态 cpuOnly rung 收资产缺席 error 帧（无 culprit →
`.requestFailed` 直通，DECISIONS §10 二分）+ generation 3 + 记账恰
`[.all, .cpuAndGPU]`。passed 0.116s。

### 4. 预记账跳档 = 增量剔除语义（DECISIONS §13）

`testPreseededExclusionSkipsTheCrashedRungEntirely`：预记账 .all → 链首
即 .cpuAndGPU（generation 2 = 一次崩溃 spawn + 一次响应 spawn）；**.all
条目字节未动**（`last?.detail` 逐字 = 预种子行）+ .cpuAndGPU 新条 +
.cpuOnly nil。该测试揭穿力 = 钉死「链从 CompatRecord 重算」旧实现
（重算必复活 CPU 档/扰动预种子）——与 Client 源码互证：链 = 尝试序 −
初始 excluded（:249-251）+ 逐次 `chain.removeAll`（:288/:294），无重算
路径。passed 0.106s。

### 5. 超时 kill + 管道断裂 + 复活（AC#4）

- `testTimeoutKillFoldsToWorkerCrashedAndRespawns`：零预算 deadline →
  `.workerCrashed("no response within 0 s")` + `childProcessIdentifier`
  归 nil（SIGKILL + `waitUntilExit` 收尸 = 无僵尸，Client :466-476 亲
  读）→ 次 ping generation 2 复活。
- `testExternalPipeBreakageFoldsIntoWorkerCrashed`：外部真
  `kill(pid, SIGKILL)` → detail 含 `exit code 9` → 编辑器存活续用（新
  pid ≠ 旧 pid）。passed 亲点。

### 6. 协议面（AC#1）

- 8MB **构造期** typed 拒：`AIWorkerFrameCodec.encode` 超限抛
  `.payloadTooLarge`（注入小 bound 负测，不移 8MB 过 JSON）。
- **L063 对策在码**：BE 装载逐字节 `UInt32(byte)` 宽化再移位
  （AIWorkerProtocol :285-293，注释亲读）+ `>255 字节` BE golden 测试
  在案（`testFramePrefixIsFourByteBigEndianLength` 双段断言）+ 512 维
  float 精度 round-trip（当年抓红用例）。
- 坏帧两形可存活：坏 JSON → typed `.badFrame`（流对齐保持）+ 越界前缀
  → skip 精确字节数重对齐（`testOversizeFrameIsSkippedAndStreamStays
  Aligned`）；仅 EOF 中帧 → `.connectionClosed` 折叠。
- **独立探针复证坏帧容忍**：裸字节 `not-a-json!!` 帧 → error 帧（匿名
  id 0）→ 同 worker 续 ping **同 pid 应答**（存活亲证）。
- SIGTERM → exit 0：`signal(SIGTERM) { _ in exit(0) }`（AIWorkerMain
  :67，读码核验；stop op 路径经探针 `STOP-EXIT: 0` 亲证）。

### 7. CompatRecord（AC#5/#6）

machineKey = `hw.model/kern.osversion` 纯函数注入（sysctl 只在
`currentMachineKey()` 组装点）；`record` CPU 恒不记（:126 guard，负测以
**盘上无文件**钉死）；两模型同 units 崩 → `all=true`（count≥2）+ 同模型
重复不翻转（负测在案）；detail 截断 300；同目录 tmp + `replaceItemAt`
原子晋升 + 无 .tmp 残留终态断言；坏 JSON = 空记录重建；`resetAll` 删
文件幂等；路径 + machineKey 双注入（测试零触碰真 App Support）。

### 8. 红线与装配（AC#2/#7）

- worker 五文件 grep `Sidecar|import SwiftUI|import AppKit` = **零命中**
  （无头纪律 + 零 sidecar 直写）；盘面写仅 stdout 帧 + 自有编译缓存树
  （`compiled-models-worker/<profile>/`，DECISIONS §6）。
- **InProcess 兜底不存在**（OQ-5-A 字面）：全仓 `InProcessMLModelRunner(`
  生产构造仅剩 AIWorkerMain:272（worker 会话对象，DECISIONS §5 双角色）
  ——AIInferenceService 零 InProcess 构造；`AIWorkerClient(record:)` =
  唯一换刀行，`CompatRecord.defaultPath()` 仅装配点解析。
- 降级不可用面：spawn 失败/可执行缺席 → `.workerUnavailable` +
  generation 0（`testMissingExecutableIsWorkerUnavailable`），**无回退**。

## 机检亲跑记录

1. **登记闭环**：Project.swift 三命中（:701/:702/:705，全落
   LightamerTestsApp target）+ BUNDLE-MAP 三行（APP 10/8/9）与
   `grep -c "func test"` 逐位一致；27 = 2890−2863 精确。
2. **diff 边界**：16 文件 = front-matter 13 + BUNDLE-MAP + 外部
   RAWMAKASE-NOTES；Project.swift 三次提交各 +1 = 全波 +3。
3. **spike DEBUG-only**：`spikeOp` 圈 `#if DEBUG`（AIWorkerMain :99-105
   声明 + :195-200 unknown-op 臂前拦截）；RELEASE 无此 op（unknown-op
   error 帧）——DECISIONS §8 成立。
4. **SIGPIPE 全局忽略**：spawn 内 `signal(SIGPIPE, SIG_IGN)`（Client
   :414）——死子进程管道写走 EPIPE → foldDeath typed，不杀宿主
   （DECISIONS §11 成立；GUI 无靠 SIGPIPE 死的依赖）。
5. **open/run 预算与重试常量**：900/600/ping 10/MAX_RETRIES 4（Client
   :61-66 缺省值亲读）；测试全毫秒级注入 deadline（纪律 3）。
6. **culprit 归因**：`lastOpenedUnits` 在 open 前置位（:315）——无响应
   型死亡按「崩溃前最后 open 的 units」记账（KD-3 字面）。

## 重点读码抽查

- **AIWorkerClient 线程形状**：串行 queue 单飞（spawn/write/deadline/
  chain 全 confined）+ pump 线程阻塞读 → size-1 mailbox + 信号量 →
  deadline 1s 切片轮询（死亡被及时察觉）；`runOnQueue` checked
  continuation 桥 async——与头注 THREADING 契约一致。
- **`ping` 刻意链外**（liveness 探针崩溃直通调用方，:193-195 注释）——
  `stop()` 有界 5s + 兜底 kill，幂等 teardown。
- **AIWorkerMain actor 形状（L064 修复形态核验）**：`serve()` 内 run 腿
  `await run(request)` → `await forwardRun(...)` **内联**（:189/:305），
  零 `Task { }` 派生；注释明示「a child Task would deadlock here」。该
  缺陷揭穿测试 = `testRealModelEmbedImageThroughWorkerProcess`（run 腿
  唯一激活路径；旧代码下 run 永不到度 → 120s 注入超时 kill → 链烧尽 →
  断言失败）——本轮**激活态 2.409s 绿**即修复有效性实证；无模型环境该
  测试 skip（skip 16 恒定证明无隐藏激活）。
- **AIWorkerProtocol 纯函数性**：Core 级零进程依赖（Pipe 对象即可测）；
  envelope 宽容未知字段（forward-compat 注释）；`AITileParameters` 空
  容器 = 路径通道帧形状占位（M2-10-06 消费，SUMMARY 交接一致）。
- **增强族 typed 门**：`embeddingDim == nil` →「opens via the M2-10-06
  leg」error 帧（AIWorkerMain :256-262）——06 交接面与 SUMMARY 一致。

## observation 三件（零 error / 零 minor）

- **O-1（挂账建议）**：`LibraryThumbnailBridgeTests.
  testPrioritizeReordersQueuedProductions` 时序 flake **连续两轮复现**
  （执行批首轮 + 本验收首轮，同断言同测试）。隔离/全量复绿口径两批逐值
  一致，本波零接触域（diff 零缩略图代码）——不构成本 plan 缺口；但
  「环境型」归因在两连击下趋弱，建议另案挂账硬化该测试的队列顺序竞争
  断言（非本验收范围，不动）。
- **O-2（文档缺口，登记即闭）**：DECISIONS §15 只申报外部并行 commit
  `5fbda86`（RAWmakase survey）；范围内实际还有第二个 `64a120b`（drop
  RAWmakase reference）。两文件（RAWMAKASE-NOTES.md + AGENTS.md）与本
  plan 边界零交集、同 docs/research 性质——漏报属 §15 表述不全，非边界
  违反；本条即补录。
- **O-3（申报带宽内注记）**：DECISIONS §2 spike TIFF 值 19.4ms 为执行批
  单轮中位；执行批后跑与验收轮复跑均 ~15.5ms（申报带 15.5-19.4 内），
  字节/路径小图通道两轮 0.041-0.045 / 0.094-0.101——量级结论与 8MB 分
  界判定不受影响（语义恒定口径，§2 自述「数字可修」）。

## 判定汇总（AC 9/9）

| # | AC | 结果 |
|---|---|---|
| 1 | 帧协议 round-trip/8MB typed/坏帧保活 | ✅ 10/0/0 + L063 对策在码 + 探针坏帧存活亲证 |
| 2 | 分叉臂永不构造 SwiftUI App | ✅ hunk = 8 行纯插入亲验 + 臂序亲读 + App 578/0/0 零回归 |
| 3 | crash 注入真 exit(9) 重启链 | ✅ 三测试 passed + 探针 HOOK-EXIT: 9 亲证 + generation/记账断言逐条 |
| 4 | 超时 kill + 断裂折叠 + exhausted | ✅ 零预算 kill 收尸复活 + 外杀 exit code 9 + 三档烧尽 |
| 5 | 降级链剔除/CPU 不记/两模型全禁 | ✅ 预剔除跳档（字节未动）+ 记账恰集 + CompatRecordTests 8 |
| 6 | CompatRecord 原子写/坏 JSON/reset/machineKey | ✅ 终态无残留 + 重建 + 幂等 + 纯函数注入 |
| 7 | 消费面零涟漪 + 不回退 InProcess | ✅ 双 suite 13/0/0 + 10/0/0 + 文件零 diff + `.workerUnavailable` gen 0 |
| 8 | 资源门 0 fail | ✅ 2890/16/0（真模型探针激活态 2.409s 非 skip 亲点） |
| 9 | 登记闭环 + diff 边界 | ✅ 三双命中逐位 + 16 文件对表零未申报源码 |

## 翻账

- REQUIREMENTS **M2AI-10 翻勾**（Delivered 注记：worker 进程 + 帧协议 +
  generation 降级链 + CompatRecord + 装配切换四合一，E1 真链 + 独立探针
  双证；M2AI-09 增强推理腿 = worker 路径通道形状已就绪、推理落 M2-10-06）。
- **M2AI-01 残留半边追记**：本地推理消费面 02/03 已交付且经本波 worker 化
  （04/05/07 远程腿不经 worker）——剩余消费半边 = M2AI-09 增强出片
  （M2-10-06）+ 设置 UI 面（M2-10-07），本条维持未勾至 09 交付。
- M2AI-02..09 无本波触发的回退/追记（registry/搜索/sidecar 面零 diff 亲证；
  M2AI-08 MCP 面零 diff，维持 Phase 14 语义）。

## 交接确认

- SUMMARY「验收轮抽查点」四项全查：crash 注入三测试（§crash 链 2/3）、
  `testPreseeded…` 预剔除语义（§4）、分叉臂 hunk 半径（§逐 commit）、
  MCP 零 diff（§机检 2）。
- 下游交接面核对：M2-10-06 路径通道推理腿（帧形状已测 + 增强族 typed 门
  在码）；M2-10-07 `resetAll()` 按钮 + typed 崩溃呈现面（API 在位，
  `defaultPath()` 装配点解析）。

**未 push。验收批零代码改动（0 error + 0 minor → 无 fix 提交）；本文件 +
翻账 + GOAL-STATE 增量 = 单 docs 提交。**
