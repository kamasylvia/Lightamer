# M6-1-01 CHECKER — 项目级单写者锁 + `--connect` 活实例转发（plan 从严审查，2026-10-16）

**结论：FAIL / 2 error + 3 minor**（修复批只动 plan 文本，零源码；回注最小集见文末）

- checker：zcode subagent（从严）；亲核 HEAD = `26b07106`（plan 申报锚 `7307f66` 之后仅 docs commit，源锚行号漂移 ≤2 行，见 o4）。
- 输入面：`.work/config.toml [gsd]`（dual_acceptance=true + plan_review_by_omp=true 亲证在册）+ `M6-1-01-PLAN.md` 全文 + `M6-1-CONTEXT.md` 裁决记录（OQ-1..6 全 A，用户回批 2026-10-14）+ `RESEARCH-NOTES.md` + 源码锚逐文件亲读 + LightCraft `docs/mcp.md` 对照 + m5-2 体例对照。
- 实证动作：`cc` 编译运行同进程双 `open()` + `flock(LOCK_EX|NB)` 探针（o1）；`grep -c "func test" Tests/LightamerTests` = 3633 全量复数；bundle 分账七项求和 = 3631 复核；requiresWriter 全集清点。

---

## 一、裁决一致性对账（审查维度 1）——六项生效值全部落位，无违反

| OQ 生效值 | plan 落位 | 亲核结果 |
|---|---|---|
| ①项目锁 `<stem>.lalb.lock` + legacy ride-along | KD-2 + AC1（门 1/门 2 序 B + 红线自证） | ✅ 锁路径拼接 `deletingPathExtension→appendingPathExtension("lalb.lock")` 语义正确；`LibrarySchema.schemaVersion` = 4 现行版零触碰面成立；`backup(to:)` sqlite3_backup 只拷 db（ProjectFileStore.swift:243-287 亲读）→ 锁文件不入备份天然成立；移动 = close→move→reopen（LibraryProjectController:119-166 亲读），move 窗口锁释放注记在 KD-2 |
| ②对称单写者 + 只读回退 | KD-3 + AC2（对话框 zh verbatim 三选 + 双向确定性门） | ✅ 无 GUI 特权；GUI 撞锁三选 / 无头撞锁只读+指引两臂对称 |
| ③无头只读常驻 + connect 指引 | KD-4 + AC3（JSON 逐键 + 通道分叉 + 降级指引 + 存活负测） | ✅ 否决立即退出/转发代理显式在册；HTTP=stdout / STDIO=stderr 与 LightCraft `docs/mcp.md`「Logs go to stderr; stdout carries only protocol messages」同纪律 |
| ④最小只读面 | KD-3 禁用清单表 + AC4（banner/toast/AX/走查 MANIFEST） | ✅ 保持可用集（浏览/检索/查看/soft proof/EDR/备份）与禁用集（含历史写项 undo/redo/jump）显式二分 |
| ⑤启动+每写类调用前 probe + additive 一枚 | KD-5 + AC5（门 5 含 live 先判序负测） | ✅ 见维度 4 详审；`-32002 槽位作废`勘误亲证正确（McpToolError 14 case 全 string code，`McpAdapters.swift:44` wire 面 = `"[\(error.code)] \(error.message)"`，无数字码注册面） |
| ⑥o-2 NSLock 收窄搭车 | KD-6 + AC6 | ✅ 三写点亲证（ColorMatchService.swift:138 configure / :309 solve 腿 + MatchColorToolset.swift:448 `ColormatchResolverBox.shared = service.resolver`）；LutLibraryStore.swift:105-123 shared holder 镜像源亲证（NSLock + sharedInstance + getter 锁内读 + replaceShared）；两读点（loadCube guard :97 / cdfSolution :106 区域）锁内读值落局部的处方可执行 |

AC7（零回归门）/AC8（SC 数字门）落位——但 AC8 数字有算术错，见 **E1**。

## 二、锁机制审计（审查维度 2）

- **五态 round-trip 设计正确**：`SingleWriterLock.acquire/probeLockAvailable/unlock/lockPath` API 形状与 `McpEndpointFile.swift:99-144` 逐条对齐；五态注释继承（acquire / EWOULDBLOCK→只读 / 退出释放 / 崩溃释放 + O_EXCL+pid 舞蹈明确不做 / probe 判残留）、O_RDWR|O_CREAT 0o600、`EWOULDBLOCK || EAGAIN`、L009 目录腿逐条在 KD-1。
- **flock per-open-file-description 语义（OQ-1 依据）——本机实证成立**：见 o1。KD-2「role 缺省 nil = 不锁，否则既有 LIB 双 store 测试成片破坏」的依据与 KD-5「probe 探自己的锁必 EWOULDBLOCK → 自持豁免必要」**双向验证正确**。
- **probe 自持豁免闭包设计正确**：writer 臂/GUI 正常打开 → 直返 writable；read-only 臂 → `probeLockAvailable` 真探；TOCTOU（probe 后新实例乘入）= OQ-5 probe 语义的既接受风险，非缺陷。
- **锁文件路径与零触碰**：sibling 命名正确；崩溃后 stale 语义 = 五态③④无清扫代码、payload 缺席/陈旧不作判据（文案回落「pid 未知」负测在门 1）——与 `mcp-endpoint.lock` 纪律一致。
- **close 释放序正确**：checkpointTruncate → handle close → unlock（WAL 尾安全），ProjectFileStore.swift:167-173 现序上 additive 可行。
- **withWriteBatch 断路单点覆盖面亲证**：LibraryStore 12 处 + ExifSearchIndexer 2 处写全经 withWriteBatch（ExifSearchIndexer.swift:22 头注明文「Every write exits through ProjectFileStore.withWriteBatch」）；LibraryQueries 全 withHandle 读面。计划宣称「一切库面写经此，天然全覆盖」成立。
- **E2（error）：`openReadOnly()` 的 schema 三岔行为未钉死**——dispatchSchema 三腿中 `stored==0`（零字节 stub heal = 全量 DDL 写）与 `0<stored<current`（pre-migrate 快照轮换 + migrate）都是**写腿**（ProjectFileStore.swift:140-160）。openReadOnly 按设计无锁，若照 plan「连接照常建立」字面复用 dispatchSchema：(a) 与持锁 holder 的迁移腿并发（双快照轮换 + 双 migrate = 包损坏窗——第二实例在第一实例迁移中打开只读的真实时序）；(b) 零字节 stub 只读打开会静默建库 = 违背只读语义。T2 只钉了写路「迁移前置锁在锁内」，只读路空缺。
  **处方**：KD-2 补一行钉死——openReadOnly 先读 `PRAGMA user_version`：`stored == schemaVersion` 才直开（连接读面）；`stored == 0 || stored < schemaVersion` → typed 拒（文案「需一次读写打开以完成建库/迁移」）；`stored > schemaVersion` → 既有 `futureSchema` 拒。负测一条（旧版包只读打开 → typed 拒，非半迁移）入门 2 或门 1。

## 三、对称性审计（审查维度 3）

- 门 2 双序设计（序 A 父持锁→子无头 / 序 B 子持锁→父 store.open）+ 各自双跑逐位一致 + 五态③窗口重跑获 writer——对称性可测性成立；`-la_project_hold_lock` fixture 与 `holdLockFixtureIfRequested`（McpServerController.swift:550-571）同型亲证，`syncStdoutBestEffort` 管道纪律（:527-537）与「双进程测试管道纪律」条款一致。
- stdio 零污染负测（stdout 零字节）在门 2 序 A'——通道分叉有负测钉死。
- GUI 只读回退面范围：三 seam（LibraryStore withWriteBatch / EditorState gate / ExportState enqueue）+ banner + toast + `.disabled` 投影 + 重试臂——与 AC4 清单对齐；「无自动升级（只读态持续到关闭重开）」与 AC4「重试臂持锁者退出后可升级」不矛盾（后者 = 对话框重试/重开重仲裁，KD-3 语义自洽）。
- **m1（minor）：无头 writer 臂「serve（读写）」的服务面未钉**。现行两条无头腿 `SessionProvider` 恒 `{ nil }`（runHeadless :94-95 stdio / :108 http——工具面对 session 面 answer `notSessionMember`）；`--project` writer 臂 plan 只写「ProjectFileStore.open → serve（读写）」，未说明打开的 store 如何（或不）接入工具 seams。若 executor 自行接线 = 大面新增（违背 20 工具封闭集精神）；若不接线，「读写」只对锁权有意义。
  **处方**：KD-4 补一句 v1 定位——`--project` = 锁载体 + 指引 + 打开校验（迁移照 KD-2），**工具服务面不变**（不新接项目 session seam，项目级 MCP 工具承载面归 M6-2 后续）；或显式指明接线形态。三行文字，供 AC2/AC3 判读。

## 四、MCP 面审计（审查维度 4）

- **写类全集亲证**：项目写类 = 9 工具——apply_params、export_image（EditingToolset 注册面 :134-155 requiresWriter true×2）+ write-five（CullingToolset :330 frame）+ apply_preset（:516）+ match_color（MatchColorToolset :164-165）。probe 五落位（apply_params body / export_image body / write-five frame / preset-trio frame / match_color body）**恰合全覆盖**；load_image/list_iops/render_preview = read-class（load_image 描述明文「Read … STATELESS … readOnlyHint: true」）probe-free 正确。
- **live 先判序**：apply_params live 判据 :519-523 亲证，probe 落其后 = OQ-5 生效值；match_color 自有 live 判据（:274/:404-407）先判序同理；write-five 无 live 判据的不对称（D-8）显式「保留不动」——正确。
- **writerCheck 旧门零改零移**：McpToolRegistry.call :306-314 endpoint 门 → serverReadOnly 原样；两层锁正交表述与 RESEARCH §3.7 表一致。
- **m2（minor）：legacy 面 MCP 写 probe 未登记**。RESEARCH §3.3 明文「MCP 筛选/修图工具（SessionIndexStore 系）在 legacy 会话上写时同判」；plan 的 probe 闭包只定义项目锁两态（自持/真探），legacy `session.lock` 的 MCP-face probe 既未接线也未显式挂账（KD-2 legacy 边界注记只覆盖只读回退面缺失）。
  **处方**：二选一并登记——(a) KD-5 补 legacy 臂：probe 闭包装配点同读当前 session 的 session.lock 自持态（GUI 内嵌宿主持锁 → writable；语义闭合零边际成本）；(b) 显式挂 M6-5（与 legacy 只读回退面并档），DECISIONS 记录。不允许静默缺位。
- typed `projectReadOnly` additive 一枚落 McpToolError case + code/message 两 switch 补臂——结构面亲证可行；快照族影响见 o2。

## 五、结构面（审查维度 5）

- legacy ride-along 边界显式登记（只落锁 + typed alert，只读回退挂 M6-5）✅；`--project` 参数仲裁 + DEBUG fixture 同型 ✅；golden 五门逐门落位 ✅（门 1-3/门 5 清单完备；门 4 三 seam 负测 + banner AX + 重试臂齐）。
- 封存面清单（NodeGraphCommand/V50Order/Registry/HistoryStack/HistoryHash/PipelineDocument/六格式导出矩阵）零 diff 红线与 T9 机检自证在册 ✅；L057 禁令（sheet 面 + `grep -rn "\.runModal(" App/Sources` 零命中自证）✅。
- **m3（minor）：测试归属与 guard 命名两处拧**。
  (a) T2 把「legacy session.lock acquire+release+**冲突面**」列入 LIB `ProjectLockTests`——SessionCoordinator 在 App target（App/Sources/Lightamer/Session/），LIB（LightamerCore 测试）不可达；冲突面（typed alert 经 lastError）断言只能落 APP。
  (b) guard 家族名单写「commitDrt/commitFilm」——EditorState 层真名 = `recordDrtChange`（:250）/ `recordFilmChange`（:270）（`history.commitDrt/commitFilm` 是其内部调用的 **HistoryStack** 方法，而 HistoryStack 属封存面零 diff 红线——字面执行会指错层）。
  **处方**：(a) legacy 冲突面断言移 APP（并入门 4 ProjectReadOnlyFaceTests 或 T4 前半），LIB 只留锁原语级路径形测试（acquire/release at `<root>/.lightamer/session.lock` 形）；(b) 名单改 `recordDrtChange/recordFilmChange` 并注明 guard 落 EditorState 包装层、HistoryStack 零触。
- read_first 行号清单漏 `recordDrtChange/recordFilmChange` 两入口行号（:250/:270）——随 m3(b) 一并补。

## 六、测试对账（审查维度 6）

- 基线亲证：`grep -c "func test" Tests/LightamerTests` = **3633** ≈ 执行口径 3631（plan 勘误链成立——派发指令 3367/16/0 确与在库不符，M5-3 VALIDATION 3631/24/0 为现行真值；bundle 七项分账求和 = 3631 复核一致）；孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 未跟踪在树亲证（`git status` ??）。
- **E1（error）：SC 数字门算术漏计 T5 后半 8 法**。KD-8 SC 段「六新文件（8+10+6+8+9+4 = 45 法预估）」与「APP 757+23 = 780」中，`ProjectReadOnlyFaceTests` 只计了 T4 前半 6 法；**T5 后半 8 法**（T5 验收明文 + 门 4 清单另一批方法）漏加。真值：六文件 = SingleWriterLockTests 8 + ProjectLockTests 10 + McpProjectArbitrationTests 9 + McpProjectReadOnlyErrorTests 8 + ColormatchResolverBoxTests 4 + ProjectReadOnlyFaceTests **14**（6+8）= **53 法**；分账 LIB +18 / APP **+31** / IOP +4 → **APP 788**、全套预期 **3631+53 = 3684**，估带 3671..3681 需上移（约 3679..3689）。`estimated_tests "+40..50"` 同步失真。
  **处方**：KD-8 SC 段 + AC8 + T10 验收数字三处同步改（53 / 788 / 3684 / 新估带），或显式声明 T5 后半与门 4 某批方法并档——二选一，全文一致；BUNDLE-MAP 增行终态对账惯例不变。
- bundle 分账（六新文件 LIB 18/APP ?/IOP 4）随 E1 修正；双验收编排（dual_acceptance=true：zcode PASS → **串行** omp 二次验收，ACCEPTANCE 载体落 M6-1-01-ACCEPTANCE.md）落位 ✅；plan_review_by_omp=true 的 omp 计划复审与本轮 checker 并行——本轮结论供合并回注。

## 七、goal-backward（审查维度 7）

- ROADMAP M6-1 行验收形态四件（真实双进程仲裁 fixture / 无头 connect 指引输出 / GUI 只读面走查 / 既有 MCP 面零回归）与五门 + AC7 一一覆盖 ✅；MCP-09-A「重开 → M6-1」REQUIREMENTS :405 原位注记在册 ✅。
- M6-2/M6-3 衔接：RESEARCH §5/§6 前瞻两节为后续 plan 输入底稿，本 plan 零越界（M6-3 spike 不在执行面）✅；M6-5 的 o-2 条目随本 plan 搭车后成空项——T10 收口时 GOAL-STATE/TODO 同批注记（提示，非违反）。
- LightCraft 对照亲证：`docs/mcp.md:19-21` catalog.lock 单写者 + "already open in LightCraft (process N …)" + 「use connect mode to work with the running app instead」——plan 的 already-open 文案结构 / connect 指引语义 / stdout 协议面纪律转录忠实；零代码移植声明与 MIT/Apache-2.0 级差声明一致 ✅。

## 八、Observations（不计数）

- **o1（实证）**：Darwin 同进程二独立 `open()` fd 第二次 `flock(LOCK_EX|LOCK_NB)` = **EWOULDBLOCK(35)**（cc 探针本机实测；man 页 NOTES「Locks are on files, not file descriptors」指 dup/fork 共享 description 情形，不豁免独立 open）。KD-2 role 缺省 nil 依据与 KD-5 自持豁免必要性**双向成立**。
- **o2**：快照族影响面亲证——McpRegistrySnapshotTests :280-300 为 writeCallCount 行为断言（catch 面 assert code 字符串），非错误码枚举快照；McpFinalSnapshotTests 钉 count == 20 白名单。plan「据实申报」姿态安全，预计快照族真零 diff。
- **o3**：payload 去 `endpointJson?` 字段（CONTEXT D-M6-1-1 草案含）= RESEARCH §3.1 明示 plan 期定 + 倾向不镜像，KD-1 裁定单源 `McpEndpointDiscovery.discover()`——合规偏差，无需回批。
- **o4（cosmetic）**：锚漂移——SessionCoordinator `close` 实测 :456（plan :454）、LightamerApp EntryPoint 实测 :129（plan :128）、ColormatchModule cdfSolution 读点 :106±2。零实现影响。
- **o5**：`writeCallCount` 语义与 probe 的交互（gated-out 写不计数）已被 :280-300 既有测试钉死——probe 加在 handler 层不影响计数语义（计数在 registry.call 写门内），零回归。
- **o6**：`withWriteBatch` 为 internal（非 public）——openReadOnly 的 typed 拒加在同一函数入口即单点断路，Core 级可测，门 4 负测形态可行。

## 九、修复批回注最小集（全部 plan 文本编辑，零源码）

1. **E1**：KD-8 SC 段 + AC8 + T10 数字改 53/788/3684/新估带（或显式并档声明）。
2. **E2**：KD-2 补 openReadOnly schema 三岔钉死（仅 stored==current 直开；0/旧版 typed 拒；futureSchema 照旧）+ 一条负测。
3. **m1**：KD-4 补 writer 臂 v1 服务面定位一句（锁载体 + 指引，工具面不变）。
4. **m2**：KD-5 或 KD-2 补 legacy MCP probe 臂（接线一句或显式挂 M6-5）。
5. **m3**：T2 legacy 冲突面断言移 APP + guard 名单改 `recordDrtChange/recordFilmChange`（HistoryStack 零触注记）。

修复后 plan 重审范围 = 仅上述五处（无需全文重审）。
