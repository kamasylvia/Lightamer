# M6-1-01 SUMMARY — MCP-09-A 项目级单写者锁 + `--connect` 活实例转发（单 plan 全量批）

> 执行 = ZCode subagent worker（夜间全自动授权「开跑，不要停」在案；2026-10-13）。
> 起点 = `26fd6bf0`（checker 回注后的 plan HEAD）；基线 = **3631/24/0**（planner
> 勘误后真值，M5-3-VALIDATION 亲证）。全程未 push（worker 纪律）。

## 任务序与提交

| 任务 | commit | 内容 | 验证 |
|---|---|---|---|
| T1 | `4d345a6f` | Core `SingleWriterLock` 泛化件（五态 flock + payload v1 冻结拼写 + SingleWriterRole + holderSummary「pid 未知」回落） | SingleWriterLockTests 8 法；**LIB 644/4/0**（636+8） |
| T2 | `61f5d5d0` | `.lalb` 项目锁（create/open role 面 + openReadOnly E2 三岔 + withWriteBatch 断路 + close 释放序）+ LibraryError 两 case + legacy session.lock ride-along | ProjectLockTests 10 法；**LIB 654/4/0**（= AC8 分账精确命中） |
| T3 | `397574bd` | McpEndpointLock 薄封装 delegate Core（签名/头注/五态原样） | **McpHostTests 18/0/0 原样全绿**（行为零 diff 门亲跑） |
| T4 | `f255e8a8` | LibraryProjectController typed 冲突面（pendingConflict）+ openProjectReadOnly + flushForTermination + ProjectConflictDialog（zh verbatim）+ 三路由 + terminate 腿 | ProjectReadOnlyFaceTests 前半 6 法（含 m3a legacy 冲突面并档） |
| T5 | `4326e3c4` | 只读态三 seam（EditorState gate ×7 提交族 / ExportState gate ×2 enqueue / withWriteBatch 已在 T2）+ banner（AX）+ 顶栏禁用投影 + move guard + 装配点接线 | FaceTests 后半 8 法；**App 771/4/0**（757+14 零回归） |
| T6 | `1f981f9b` | 无头 `--project` 仲裁两臂 + connect 指引（JSON schema + 通道分叉 + 降级）+ DEBUG fixture + stdio EOF poll 腿 | McpProjectArbitrationTests 9/0/0（真实双进程） |
| T7 | `1ee26c40` | MCP 写面 probe seam（Seams/CullingContext）+ typed `projectReadOnly` additive 一枚 + 五调用点落位（live 先判序）+ 三宿主装配闭包（自持豁免 + legacy m2 接线） | McpProjectReadOnlyErrorTests 8 法；**App 788/4/0**（= AC8 分账精确命中；快照族/parity 全绿含内） |
| T8 | `5ff6ff48` | o-2 ColormatchResolverBox NSLock 收窄（LutLibraryStore 体例镜像）+ 三写点 replaceShared + 读点局部化 | ColormatchResolverBoxTests 4 法；**IOPParity 460/3/0**（= 456+4） |
| T9 | `81fdb0fc` | 红线机检全绿 + zh-audit PASS（补两 stderr 键 + 表格式崩溃修复）+ 走查 MANIFEST | Arbitration 复跑 9/0/0 |
| T10 | 本 commit | SUMMARY/DECISIONS/ACCEPTANCE 脚手架 + GOAL-STATE 续接点 + TODO/LESSONS 同批 | 定向轮对表（下表） |

## 定向轮对表（AC8 SC 门）

| bundle | 基线 | 预期（E1） | 实测 | 判定 |
|---|---|---|---|---|
| LIB | 636/4/0 | 654/4/0（+18） | **654/4/0** | ✅ 精确 |
| APP | 757/4/0 | 788/4/0（+31） | **788/4/0** | ✅ 精确 |
| IOP | 684/1/0 | 684/1/0（0） | **684/1/0** | ✅ 不变 |
| IOPParity | 456/3/0 | 456/3/0（0）→ 归属勘误后 **460/3/0**（+4） | **460/3/0** | ✅（勘误，见 DECISIONS D-1） |
| 全套 | 3631/24/0 | 3679..3689（中值 3684） | **53 法全数在库**（644+788+460 对账 = 3631+53，IOP 不变） | 收口轮申请全套 `--all` 批准轮对账 |

零 MEMFAIL（IOP 6398MB / IOPParity 5399MB，均 <8G 运行门）；App 峰值 2832MB ≪ 门。

## Golden 五门证据

1. **锁五态 round-trip**：`SingleWriterLockTests`（8 法）——acquire/同进程二 fd heldByOther/unlock 让渡/probe 三态（残留 payload 不影响）/payload round-trip + 缺字段拒解码/pid 缺席回落/ioError/mkdir 腿/双 unlock。
2. **对称只读回退 + 双向确定性**：`McpProjectArbitrationTests`——**序 A**（父持锁→子 HTTP 只读臂：stdout 首行指引 JSON 逐键 + 进程常驻负测 + 存活 endpoint 由测试父进程持 endpoint 锁确定性供给）；**序 A'**（stdio：JSON+人类行全 stderr、stdout 零字节）；**序 B**（子 fixture 持锁→父 typed projectHeldByOther 携 holder 摘要）；**序 A/序 B 各双跑**结论一致（decode 级，D-5）；**五态③窗口**：持有者退出后子重跑获 writer 臂（json 落盘 + 持锁 + 零指引）。GUI 侧对称 = 冲突对话框三选（FaceTests 前半）。
3. **connect 指引机读**：并入门 2 序 A——schema 逐键（event/endpoint{transport,host,port,auth}/holderPid）+ 降级变体（endpoint null）+ 通道分叉（HTTP=stdout / STDIO=stderr 零污染负测）。
4. **GUI 只读面**：`ProjectReadOnlyFaceTests`（14 法）——三 seam 负测（LibraryStore 真消费者拒 / commit 家族 no-op / ExportState enqueue 拒 + legacy face 保留）+ banner AX（实窗 AX 树含 `shell.readonly.banner`，可写态零 chrome）+ 重试臂 + move 拒 + backup 可用 + runModal 零命中。实机走查 = MANIFEST（Manual-Only 行留验收轮）。
5. **MCP typed projectReadOnly**：`McpProjectReadOnlyErrorTests`（8 法）——probe held→typed（code+文案携 pid/指引）、live 先判序负测、probe nil 零行为、serverReadOnly 先序、自持豁免、export 头部 probe、culling write-five + 读类照常、match_color attach 门。20 工具封闭集快照族零 diff（App 全量亲证）。

## 偏差与发现（细则 = DECISIONS）

- **D-1 bundle 归属勘误**：ColormatchResolverBoxTests → IOPParity（在库 Colormatch 单测真实邻居；AC8 的 IOP 688 改 IOP 684 不变 + IOPP 460；总 3684 不变）。
- **D-4 writer 臂单点获锁**（执行期发现）：外部 acquire + store.open(role:) 会同进程双 fd 自锁（flock per open-file-description）——store 即唯一获锁点。
- **L078 表格式崩溃**：键入册后 String(localized:) 走表格式，Int32 过 %@ 崩进程（仲裁 fixture 当场抓到，修复 = 显式 String 化）。
- **L079 单点获锁纪律**：同族教训沉淀 LESSONS。
- 新增键 10 枚（KD-7 九键 + session_lock_held 申报）；快照族 additive 影响实为零（D-M6-1-6 申报义务兑现）。

## 收口状态

- 定向轮三 bundle 全绿 + 双进程 golden 全绿 + 红线机检全绿。
- **全套 `--all` 批准轮**：待 orchestrator 批准（预期 3679..3689/24/0 带，中值 3684）。
- **双重验收**：`M6-1-01-ACCEPTANCE.md` 脚手架在库；zcode 验收 PASS 后串行 omp 二次验收（严禁并发），两路结论回填。
