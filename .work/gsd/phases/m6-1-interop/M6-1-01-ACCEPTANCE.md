# M6-1-01 ACCEPTANCE — 双重验收记录（config `dual_acceptance = true`）

> 编排纪律：**zcode 独立验收 PASS → 串行 omp 二次验收（严禁并发——computer-use
> 单实例）**；两路结论落本文件（PASS/FAIL + 证据指针）；FAIL 回注修复批后重走。
> 本批（worker 执行 2026-10-13）交付面与证据正本：
> - 任务序/commit 表/定向轮对表 = `M6-1-01-SUMMARY.md`
> - 执行偏差与机检清单 = `M6-1-01-DECISIONS.md`
> - 走查配方（Manual-Only 行）= `.work/gui-acceptance/m6-1/MANIFEST.md`
> - 五门 golden 证据 = SUMMARY「Golden 五门」节（测试文件在库可复跑）

## 第一路：zcode 独立验收

- status: **PASS**（2026-10-13 夜间独立验收批；验收树 = a18cfb82（worker 十提交）
  + 并发线 omp 回注批（e2a493c0/f42dc13c/ed6ca3e7/cf36190a/f8e0671c）+ 本路修复
  `5d814958`；全程亲测不轻信报告）
- 结论：**AC1..AC8 逐条兑现 + 一项 error 级回归发现并当场修复**（session.lock
  ride-along 同进程二次 openAndSync 自撞 flock per-fd——worker 定向轮未覆盖
  Sessions bundle 漏出，全套复跑第一轮抓到；修复 = SessionIndexController 进程内
  seat registry 同进程共享活锁，跨进程仲裁不变；Sessions 279/4/0 双轮回基线）。
  锁机制/对称性/GUI 面/MCP typed/红线七域审计全过（分节见下）。
- 亲跑数字：
  - 全套 `--all` 第二轮（修复后）：`TOTAL|3688/24/1|2165s`——3688 = 已提交面
    **3684**（= 基线 3631 + 53，AC8 精确）+ 并行线**当时未提交**的 +4 法
    （f8e0671c in-flight）；唯一失败 = 该未提交 in-flight 测试自身缺陷
    （`testVersionCoordinatorGateRejectsWriteCommands` 断言取错槽名），**已提交面
    788 全绿**（算术闭合：3688 − 4 = 3684 零失败）；f8e0671c 落库后 HEAD
    `0f6bdcd7` 单类复跑 **FaceTests 18/0/0** 闭合。bundle 分账：IOP 684/1/0
    （5360MB）/ IOPParity 460/3/0（7311MB）/ Layers 466/4/0 / Library 654/4/0 /
    **Sessions 279/4/0**（修复生效）/ Export 353/4/0（6095MB）/ App 792/4/1；
    峰值全部 <8G 门、零 MEMFAIL、零 crash、零 no-total-line（L055 双保险全过）。
  - 定向：修复后 Sessions bundle **279/4/0**（基线精确）；HEAD FaceTests
    **18/0/0**；worker 批 MCPHostTests 18/0/0 零 diff 门经全套轮含内亲证。
  - zh-audit `--check` **PASS**（source 1661 / catalog 1900，10 新键全入册与
    MANIFEST D7 一致；xcstrings diff 零删除行 = 纯插入亲核）。
- 证据：全套两轮日志 = `acceptance-logs/full-all-zcode.log`（第一轮
  2543/16/2——fail-fast 止于 Sessions，导出修复现场）与
  `acceptance-logs/full-all-zcode-round2.log`（第二轮全七 bundle）；修复提交 =
  `5d814958`（含根因 + 回归证据说明）。

### 锁机制审计（灵魂项）

- `SingleWriterLock`（`LightamerCore/Sources/Foundation/SingleWriterLock.swift`
  全文读码）：五态语义与 `McpEndpointFile.swift` 正本逐条一致——flock
  EX|NB 唯一仲裁、`EWOULDBLOCK||EAGAIN` → heldByOther、无 O_EXCL+pid 清扫代码
  （五态③④）、payload 骑锁 fd truncate+write（诊断面，缺席/陈旧不作判据）、
  probe = try-flock 即释（非持有式）。payload v1 冻结拼写（schemaVersion/role/
  pid/startedAt）+ 缺字段拒解码负测（`XCTJSONDropKey` 构造）+ pid 缺席
  「pid 未知 / pid unknown」回落，8 法亲跑全绿。
- flock per-fd 同进程实证：`testAcquireSuccessThenSecondAcquireHeldByOther`
  同进程第二独立 open() fd EWOULDBLOCK（Darwin per-open-file-description，
  checker o1 依据）——测试亲跑绿 + LightCraft `crates/catalog/src/lock.rs`
  头注同语义对照（「flock belongs to the open file description」）成立。
- `ProjectFileStore` 落地（读码）：`acquireProjectLockIfRoled` role-nil 零触碰 +
  锁 nil 幂等守卫；open（role）严格先于一切写腿（heldByOther 在 pre-migrate
  快照轮换之前 typed 抛——`testAcquirePrecedesMigrationSnapshotLeg` 钉死）；
  `openReadOnly` E2 三岔（stored==current 直开 / 0 与 0<stored<current typed 拒
  「需一次读写打开」/ >current futureSchema 照旧）；`withWriteBatch` 只读 typed
  断路；close = checkpoint → handle close → unlock（WAL 尾安全序）；
  backup 只读可用且产物零锁文件。10 法亲跑全绿。

### 双进程对称性审计

- `McpProjectArbitrationTests`（9 法，真实 spawn 宿主二进制 + poll 门控管道
  读写）亲跑全绿：序 A（父持项目锁 → 子 `--mcp-http --project`）stdout 首行
  指引 JSON decode 级逐键（event=connect-guidance / holderPid / endpoint
  {transport,host,port,auth}）+ 800ms 后进程存活（只读常驻负测）；降级变体
  （无端点文件 → `endpoint:null` + holderPid）；序 A'（stdio）JSON + 人类行全
  stderr 且 **stdout 零字节**（协议面零污染）；序 B（子 `-la_project_hold_lock`
  持锁 → 父 typed `projectHeldByOther` 携 holder 摘要）；序 A/序 B 各双跑
  decode 级结论一致（D-5 口径）；五态③窗口（持有者退出 → 子重跑获 writer 臂：
  endpoint json 落盘 + 项目锁被持 + stdout 零指引）；旗标校验两腿 exit 1；
  无 `--project` 冒烟零回归。
- writer 臂单点获锁（D-3/L079）读码确认：`store.open(role:.headless)` 是唯一
  获锁点，held 分支即只读臂触发器——外部 acquire + open 双 fd 自锁缺陷不存在。
- 只读 HTTP serve 面（D-4）读码确认：`startReadOnlyHTTPHost` 不取 endpoint
  writer 锁、不写 discovery json、`writerCheck { false }`——与 OQ-3「只读常驻」
  相容（GUI 持 endpoint 锁时子进程不 exit(4)）。

### GUI 只读面 / MCP typed 审计

- FaceTests 14 法（committed）亲跑全绿：三 seam 负测（LibraryStore 真消费者
  typed 拒 / EditorState gate 关 → commit 家族 no-op 不崩 / ExportState 两
  enqueue 拒）+ **banner AX 实窗断言**（真 NSWindow + AX 树遍历，
  `shell.readonly.banner` 只读在树/可写零 chrome 双向）+ 重试臂 + move typed 拒
  + backup 可用 + `testL057RunModalZeroHits` 常驻钉死。
- 禁用投影读码：顶栏 export/yiyin `.disabled(isReadOnly)` 同源布尔 +
  `ProjectConflictDialog` 三选 zh verbatim（sheet 面、无 @Environment 跨界——
  M2-8-3 FINDING-A 规则遵守）+ EditorState gate 七提交族入口 guard 逐条 +
  ExportState 两 enqueue guard + moveProject typed backstop + 装配点三闭包接线
  （EditorState/ExportState gate + MCP probe 自持豁免/只读真探/legacy
  session.lock 判据源 m2 接线）。
- MCP typed 面（`McpProjectReadOnlyErrorTests` 8 法亲跑全绿）：probe held →
  typed `projectReadOnly`（code + 文案携 `role=gui pid=4321` + connect 指引）、
  live 先判序负测（live 图 + 锁 held → `imageLiveInEditor`）、probe nil 零行为
  （legacy 写落盘）、serverReadOnly 先序（endpoint 门 → probe 正交）、自持豁免
  放行、export 头部 probe（先于参数校验）、culling write-five frame 内 probe +
  读类 `list_presets` 照常、match_color attach 门。五调用点落位读码核对
  （apply_params live 判据后 / export 头部 / write-five requireMembers 后 /
  preset-trio / match_color attach 门）。20 工具封闭集快照族 + G4 parity 全套
  轮含内亲证零 diff（D-8 申报兑现）。
- omp 回注三提交（f42dc13c/ed6ca3e7/cf36190a，验收期内落库）读码审计通过：
  guard 家族 7→13（undo/redo 拒 false、jump no-op + PipeCoordinator 尾跳、
  install 三件 no-op——补齐 D-9 表「undo/redo/jump 靠 commit 族 guard」的实缺）、
  VersionCoordinator 六写命令 gate（同缝注入式）、Edit 菜单 disabled 投影；
  零测试面变化（+4 法随 f8e0671c 另行落地，见「并发批注记」）。

### 红线机检（全部亲跑）

- `grep -rn "\.runModal(" App/Sources` = **0**；`LibrarySchema.swift`
  26fd6bf0..HEAD diff = **0**；`Project.swift` diff = 6 行纯测试数组增行
  （dependencies 块零触，零新 SPM）；封存面逐真路径 diff 全零
  （HistoryStack/HistoryHash/V50Order/DrtRecord/Registry[Core+IOP]/PipelineDocument/
  NodeGraphCommand/AIWorkerProtocol/六格式矩阵/YiyinExportSettings/LibrarySchema）；
  QuickLook/Spotlight appex 零触碰；生产码随机源门零命中；zh-audit PASS。
- LightCraft `catalog.lock` 范式对照成立：flock 唯一仲裁 + owner/payload 仅
  hint（missing/stale 不作判据）+ typed InUse 冲突携 holder 描述——M6-1 目标
  「LightCraft 范式项目级兑现」达成（payload 骑锁 fd vs 独立 owner 文件为合理
  简化；锁外降级臂我方不采纳 = 本地卷边界，DECISIONS 在案）。

### 发现与处置

1. **E1（error，发现并当场修复）**：legacy `session.lock` ride-along 使同进程
   二次 `openAndSync`（同 controller 再同步 / 第二 controller 实例）自撞
   flock per-fd → `failed:true`（两既有 Sessions 测试红：`CatalogProjectorTests.
   testOpenAndSyncHookRespectsGuard` / `CatalogModeIsolationTests.
   testSessionsModeFullFlowCreatesNoCatalogFile`；基线 279/4/0 → 279/4/2）。
   根因 = ride-along 无同进程重开语义（KD-2 的 ProjectFileStore 有
   `guard lock == nil` 幂等 + role-nil 缝，SessionIndexController 无对应物；
   worker 定向轮 test_bundles [LIB,APP,IOP] 未覆盖 Sessions 面漏出）。修复 =
   `5d814958`（进程内 seat registry：同 root 共享活锁对象、末座起立才 unlock、
   跨进程仲裁/typed 冲突/ioError 降级逐字节不变）；验证 = Sessions 定向
   279/4/0 + 全套二轮 279/4/0 双轮。教训（worker 定向轮盲区：触碰
   SessionCoordinator 却未跑 Sessions bundle）已具文本提交内。
2. **M1（minor，被并发批覆盖，不重复处置）**：BUNDLE-MAP `ProjectReadOnlyFaceTests`
   行计数 6 ≠ 文件实有 14（T10 终态对账漏项）——本路独立发现的同时，omp
   计划复审批以 6→18（+4 法）随 f8e0671c 落库覆盖同点；本路不重复改行。
3. **并发批注记（非缺陷）**：验收执行期间并行线（omp E-OMP-1 执行批）在同一
   工作区落库 5 commits（e2a493c0/f42dc13c/ed6ca3e7/cf36190a/f8e0671c，编排层
   知情并裁决「二轮优先 + 串行」）；二轮 App bundle 二进制含其当时未提交的
   +4 法（792 = 3684 + 4），唯一失败属该 in-flight 测试自身（f8e0671c 已修），
   已提交 3684 面全绿由算术闭合 + HEAD 复跑 FaceTests 18/0/0 双证。DerivedData
   竞争不存在（双线各用 -workspace / -project 两容器）。
4. **Manual-Only 走查行未执行**（MANIFEST A/B/C 三节——`open -n` 双实例对话框
   三选 / 只读面逐项 / 无头 connect 指引终端目测）：本路无 computer-use，
   按编排留**omp 二次验收**执行并回填截图；机检行 D1..D8 本路全部亲证闭合。

## 第二路：omp 二次验收（串行，第一路 PASS 后）

- status: **pending**（待 orchestrator 派遣；注意验收树已前移至
  0f6bdcd7——含 omp 回注批与 zcode 修复 `5d814958`，全套对账值 = **3688**；
  Manual-Only 行 = 本文件第一路第 4 条移交清单）
- 结论：
- 证据：

## 处置记录

（FAIL 回注修复批的 commit 与重走记录逐行追加于此）
- 2026-10-13 zcode 第一路：E1 修复 `5d814958`（详见上），无其余回注项。
