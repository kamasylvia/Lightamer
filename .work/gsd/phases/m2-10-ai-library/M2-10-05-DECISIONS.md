# M2-10-05 DECISIONS — 裁决与偏离正本

> 执行 worker（2026-10-03/04 夜）。正本对照 `M2-10-05-PLAN.md`；
> 晨审可推翻项各注改动半径。

## §1 提交顺序 T1→T3→T2（依赖序，偏离 plan 文本序）

plan 任务序为 T1→T2→T3，但 T2（AIWorkerClient）代码 import T3 产物
（CompatRecord）——按依赖序提交：T1 `f1cc3a3`（协议+worker+分叉臂）→
T3 `3afc5d4`（CompatRecord）→ T2 `65da2d1`（client+切换）。每 commit
自洽可构建（E2 登记随各自 commit 闭环）。晨审可推翻：改动半径 = 零
（纯历史顺序，代码无差）。

## §2 OQ-10-C 8MB 分界定稿——spike 数字（语义恒定）

IPC 微基准经真实 worker 子进程（DEBUG spike op，50 次中位 + TIFF 10 次
中位；JSON 正本 `/tmp/lightamer-ipc-spike.json`，测试输出行 `IPC-SPIKE`）：

| 通道 | 中位 |
|---|---|
| ping RTT（控制面常量） | 0.025 ms |
| 256² JPEG 字节通道（base64 过管道） | 0.041 ms |
| 256² JPEG 路径通道（tmp 写+worker 读） | 0.094 ms |
| 50MP TIFF（7000² RGBA8 ≈ 196MB）路径通道 | 19.4 ms |

注：spike 样图为纯色 JPEG（压到 1.9KB/2564 base64 字节）——真实照片
20-50KB 时字节通道延迟线性放大 ~10×（仍亚毫秒）。结论：**小图双通道均
亚毫秒、无分界压力；大图路径通道 19.4ms vs 假想 196MB 字节通道
（~260MB base64 过管道 + 2.6× 内存驻留）量级碾压**。8MB 分界保守合理，
维持 KD-1 常量；语义（字节通道只给小图）恒定。

## §3 embedding JSON 帧不做二进制优化（KD-1 签注）

响应 embedding = JSON float 数组：512 维 ≈ 11KB、834MB 档 jina 768 维
≈ 15KB——管道 0.025ms RTT 常量下无优化收益。v1 恒 JSON；后手 = 二进制
帧（仅在维度/批量出现量级变化时重开）。

## §4 无 MCP 复用（D-M2-10-CONTEXT-6 落地面）

帧协议独立最小实现（长度前缀 + JSON envelope，单向请求-响应）；MCP
stdio 传输（JSON-RPC/capabilities/工具面）零复用零触碰——`git diff
App/Sources/Lightamer/MCP/` 空（机检在案）。

## §5 InProcessMLModelRunner 保留语义 = 双角色

①测试 fixture（AIInferencing 第二 conformer，Core 单测/registry mock
链继续用）；②**worker 会话对象**——AIWorkerMain 按 `(profileID, units)`
缓存 InProcessMLModelRunner 实例，复用其编译缓存逻辑（`loadCompiled`），
worker 侧零重复加载代码。plan 原「保留为测试 fixture」扩为双角色，
DECISIONS 签注。

## §6 worker 编译缓存目录

`~/Library/Caches/Lightamer/compiled-models-worker/<profileID>/`——与
fixture 时代的 `compiled-models/` 分离（worker 进程独占树；.mlmodelc
编译产物与 units 无关，per-profile 即可）。生命周期 = Caches 派生物，
系统可回收，无清理代码（与 InProcess 同策）。

## §7 测试宿主落点（plan 风险节预判项的定稿）

`Bundle.main.executableURL` 在 test-direct 直启宿主内即 Lightamer.app
二进制——`--ai-worker` 臂在宿主内可用，spawn 真链测试直接命中，**无需
xcrun 回落**（McpHostTests 同款先例）。生产 GUI 与测试宿主同落点。

## §8 spike op = DEBUG-only 原始字符串 op

`"spike"` 不入 `AIWorkerOp` 枚举；DEBUG 构建在 unknown-op 臂前拦截，
RELEASE 无此代码路径（unknown-op error 帧）。语义 = 传输探针
（字节数回显/文件读取），非推理——不构成协议面扩展。

## §9 crash 钩子扩展形 `<profileID>@units,units`

Lumen `LUMEN_TEST_WORKER_CRASH` 单值形之上的超集：`@all,cpuAndGPU`
后缀把崩溃限定到列出 units，测试可注入「崩两档、第三档活」的降级序
列。默认（无 @）= 每次该 profile 的 open 都崩。DEBUG + env 双门，
RELEASE 零路径。

## §10 错误帧 culprit 二分语义（KD-2 的落地细化）

`ok:false` 响应：**有 culpritUnits** = units 级失败（MLModel 在该设备
编译/加载失败——记账 + 剔该档 + 同进程续试下档）；**无 culprit** =
profile 级失败（资产缺席/增强族未接线——直通 `.requestFailed`，不烧
链不记账：换 units 无助）。run 级错误帧恒无 culprit（worker 健康）→
直通呈现。

## §11 SIGPIPE 全局 SIG_IGN（spawn 时一次性）

子进程死亡后的管道写入必须折叠为 typed `.workerCrashed`，不能以默认
SIGPIPE 杀宿主。GUI app 无「靠 SIGPIPE 死」的依赖，进程级忽略安全；
EPIPE 错误走 write 抛错 → foldDeath 路径。

## §12 降级链耗尽与 03 registry 交互

`.workerExhausted` / `.workerUnavailable` 经 SemanticEngine 上抛 →
registry 任务 typed failed（既有失败面）→ 任务标失败 + 错误呈现，
**不自动重排队**（防风暴）。registry 零改动机检在案
（AnalysisRegistryTests 13/0/0 + 文件零 diff）。

## §13 链维护 = 增量剔除（record 重算被弃）

首轮实现从 CompatRecord 重算链——把 CPU 崩剔除的 rung 复活（CPU 崩
不入账，重算永远加回）。改为：链 = 尝试序 − 初始 excluded（预剔除），
每次消化按 culprit 增量 remove；不重算。测试钉死
（testPreseededExclusionSkipsTheCrashedRungEntirely）。

## §14 生成计数语义 = spawn 计数

generation 每 spawn +1（teardown 不计）。每降级档一次 spawn；终态
rung 若以响应型失败收尾（profile 级 error 帧）也需一次 spawn（前档崩
溃已 teardown）——testCrashSequence 断言 3 = [.all 崩, .cpuAndGPU 崩,
.cpuOnly 响应]，非直觉的「2 spawn」。

## §15 外部并行 commit

`5fbda86`（docs(research): RAWmakase survey）为并行落库的 research
提交，落在本波 T3 与 T2 之间——非本 plan 边界，独立成提交无文件交集
（对账时从 81ae393..HEAD 全量 diff 中剔除）。
