# M6-1 CONTEXT — MCP-09-A 项目级单写者锁 + `--connect` 活实例转发（discuss/research 起草批，2026-10-16）

> Phase = M6-1（ROADMAP §Milestone 6 M6-1 行：MCP-09-A 项目级单写者锁 + `--connect`
> 活实例转发——LightCraft 裁决①，用户回批 2026-10-11 全按推荐）。本文 = 研究定稿载体 +
> **C 档第 1 停裁决面**（OQ-M6-1-1..6 交用户；全带推荐，用户可随时推翻）。
> 读解正本 = 同目录 `RESEARCH-NOTES.md`（§ 引用见各条）。
> 状态：research 起草完成 → **C 档第 1 停**：OQ 裁决前不进 plan。

## Phase Goal（ROADMAP 原文锚定）

补齐 14-1 只锁 MCP 宿主不锁库面的缺口——14-1 关闭的是**宿主级**单写者
（`McpEndpointFile` flock 五态 + 只读降级 + `imageLiveInEditor` GUI-live 判据，
`App/Sources/Lightamer/MCP/McpEndpointFile.swift` + `McpServerController.swift`）；
未决残面 = **库/项目级**并发——无头 MCP 实例（`--mcp-http` / `--mcp-stdio`）与活
GUI app 同开同一项目时的 `.lalb` 投影 / `.lra` sidecar 双写。M6-1 = LightCraft
`catalog.lock` + connect 范式的项目级兑现：项目打开权单写者锁（复用五态 flock
机制抽 Core 级泛化件）+ 无头实例撞活 GUI 时拒写并按 connect 指引转发至活实例
MCP 端点 + GUI 只读回退面 + MCP 工具写类 typed 拒绝面。
验收形态（ROADMAP M6-1 行）= 真实双进程仲裁 fixture ✓ + 无头 connect 指引输出 ✓
+ GUI 只读面走查 ✓ + 既有 MCP 面（20 工具封闭集/G4 parity）零回归 ✓。

## 决议（D-M6-1-N，均带推荐；最终裁定 = 对应 OQ）

### D-M6-1-1 锁对象与粒度（RESEARCH §3.1/§3.2）

- 推荐**项目级整体锁**：锁文件 = `.lalb` 同目录 sibling `<stem>.lalb.lock`
  （flock EX|NB，五态语义 = `McpEndpointLock` 原样——acquire / heldByOther /
  holder 退出或崩溃 kernel 自释放 / probe 判残留）。锁文件**不入包**
  （`.lalb` 内部零 schema 触碰；`ProjectFileStore.backup(to:)` sqlite3_backup
  不携带——锁是运行态非数据；移动项目随目录走 = 五态③自然失效）。
- 锁文件 payload = `{schemaVersion, role: gui|headless, pid, startedAt,
  endpointJson?}`（诊断与 connect 指引用；**flock 为唯一仲裁**，pid 永不作
  liveness 判据——`McpEndpointFile.swift` 头注既有纪律）。
- legacy Session 根（`LIGHTAMER_LEGACY_LIBRARY=1` 面）ride-along 同件
  （`<sessionRoot>/.lightamer/session.lock`）——同一泛化件零边际成本。
- 被否形态：per-image `.lra` 锁（粒度太细，SidecarStore 2s debounce 写窗难钉，
  与 `imageLiveInEditor` 现有判据重复）；仅 MCP 面锁（= 14-1 现状，不解决
  GUI 自身写腿）。**最终裁定 = OQ-M6-1-1。**

### D-M6-1-2 GUI 与无头的对称性（RESEARCH §3.6）

- 推荐**对称单写者 + 只读回退**（LightCraft 原形——第二打开者无论 GUI/无头
  一律不得写）：GUI 撞锁 → 只读打开对话框（只读打开 / 重试 / 取消）；
  无头撞锁 → 只读 + connect 指引（D-M6-1-3）。
- 被否形态：GUI 特权非对称（需 holder-role 探测 + 抢占协议——flock 无抢占，
  liveness 判定复杂化〔pid 复用教训〕；收益仅覆盖「无头先起、GUI 后开」边角
  场景的顺滑度，与本 phase「一次定清并发语义」目标不成比例）。**最终裁定 =
  OQ-M6-1-2。**

### D-M6-1-3 无头撞锁后行为 = `--connect` 指引形态（RESEARCH §3.4）

- 推荐**只读 server 常驻 + 启动时 emit connect 指引**：无头启动序 probe 项目锁
  → held → ①`McpEndpointDiscovery.discover()` 读活实例端点
  （`.alive(info)` = host/port/auth marker）→ ②stdout 发单行结构化 JSON
  指引（`{"event":"connect-guidance","endpoint":{...},"holderPid":N}`——
  agent 可机读）+ stderr 人类可读行（zh/en）→ ③server 以只读臂继续 serve
  （写类工具 typed 拒绝，D-M6-1-4）；活端点不存在（GUI 未开 MCP host）=
  指引降级为「项目由另一实例持有（pid N），关闭它或在其上开启 MCP server」。
- 被否形态：立即退出带指引（agent 无法继续只读检索/渲染）；无头内嵌转发代理
  （把 MCP 请求 proxy 到活实例——双跳延迟 + 会话语义复制 + 鉴权转发面，成本
  高收益低；connect 语义 = 指引 agent 直连，非本进程代劳）。**最终裁定 =
  OQ-M6-1-3。**

### D-M6-1-4 写面拒绝语义与错误码（RESEARCH §3.5）

- 推荐 MCP 工具写类（`requiresWriter` 集）新增 **typed 错误
  `projectReadOnly`**（错误码表 additive 一枚，建议 -32002 槽位 plan 期定），
  文案双语指引「项目由另一实例持有（pid N）——连接活实例 <endpoint 或指引
  语>」；既有 `imageLiveInEditor` 硬拒保留（更细粒度优先，命中即旧语义）。
- 锁检查时机（RESEARCH §3.7）：**启动 + 每写类调用前 probe**
  （`probeLockAvailable` 语义复用——只探测不持有，无锁文件句柄常驻）。
- 被否形态：仅启动检查（长跑无头实例中途 GUI 出现 = 双写复活窗）；工具面
  新增 `project_status` 查询工具（20 工具封闭集破面，指引信息已随错误文案
  与启动 stdout 承载）。**最终裁定 = OQ-M6-1-5。**

### D-M6-1-5 `.lalb` schema 与备份/移动交互（RESEARCH §3.2）

- 推荐**零 schema 触碰**：`LibrarySchema` v4 不动（锁是文件系统运行态，
  非数据面）；`ProjectFileStore.open` 入口 acquire + close /
  `applicationWillTerminate` 释放；崩溃 = kernel 自释放（五态③④，无残留
  清扫代码——`McpEndpointLock` 同纪律）；备份（sqlite3_backup）与移动
  （整目录搬移）语义零变化。
- 被否形态：`project_meta` 表登记锁态（重启残留需清扫，违背五态「无残留」
  设计）；user_version 升级承载（非数据语义不入 schema）。**最终裁定 =
  OQ-M6-1-1（粒度条的附属裁决，随主 OQ 一并裁）。**

### D-M6-1-6 工具快照族影响与范围搭车（RESEARCH §3.5/§6）

- 推荐**零新工具**（20 封闭集不动）：仲裁在 server 装配与错误面，不在工具面；
  `McpRegistrySnapshotTests` 白名单负测零 diff；新 typed 错误码 additive 面
  的快照影响（descriptionKeys/错误码枚举快照若含）plan 期核对申报。
- 范围搭车候选：M5-1 挂账 **o-2 `ColormatchResolverBox.shared` 裸静态 →
  NSLock holder 收紧**（`LutLibraryStore` shared holder 体例）——与本 phase
  并发/锁面同族，顺手清偿；不同意则转 M6-5 挂账清算批。**最终裁定 =
  OQ-M6-1-6。**

## Open Questions（OQ-M6-1-1..6，全带推荐；C 档第 1 停裁决面）

- **OQ-M6-1-1（锁粒度）**：项目级 `.lalb` 锁 + legacy Session 根同件
  ride-along，锁文件 sibling + 零 schema 触碰？**推荐 = 是**（RESEARCH §3.1/3.2）。
- **OQ-M6-1-2（对称性）**：对称单写者 + 只读回退（GUI 撞锁 = 只读对话框三选；
  无头撞锁 = 只读 + connect 指引），否决 GUI 特权非对称？**推荐 = 是**
  （RESEARCH §3.6）。
- **OQ-M6-1-3（无头撞锁后行为）**：只读 server 常驻 + 启动 emit 机读 connect
  指引（活端点缺席 = 降级指引语），否决立即退出与内嵌转发代理？**推荐 = 是**
  （RESEARCH §3.4）。
- **OQ-M6-1-4（GUI 只读面范围）**：最小只读面 = 浏览/检索可用 + 编辑入点禁用
  （Inspector/节点命令/批量 apply/导出入队）+ 顶部 banner 常驻 + toast 一次性
  告知，而非完整只读重设计或纯拒开？**推荐 = 是**（RESEARCH §3.6）。
- **OQ-M6-1-5（锁检查时机）**：启动 + 每写类调用前 probe（非持有式），错误码
  additive 一枚 + `imageLiveInEditor` 保留？**推荐 = 是**（RESEARCH §3.5/3.7）。
- **OQ-M6-1-6（范围搭车）**：o-2 `ColormatchResolverBox` NSLock 收紧随 M6-1
  搭车清偿（同族锁面卫生），否则转 M6-5？**推荐 = 搭车**（RESEARCH §6）。

## 状态

research 起草完成（2026-10-16，M6 立项合并批）→ **C 档第 1 停**：
OQ-M6-1-1..6 交用户裁决（全带推荐；晨审/用户可随时推翻）→ 裁决回批后进
plan round（执行分工照 Phase 执行模型 = omp 执行 + subagent 验收）。

## 裁决记录（用户回批 2026-10-14）

**OQ-1..6 全部按推荐采纳（全 A）**：①锁粒度 = 项目锁 `<stem>.lalb.lock` + legacy session 根 ride-along ②对称单写者 + GUI 只读回退（否 GUI 特权非对称）③无头撞锁后行为 = 只读 server 常驻 + connect 指引（否立即退出/代理）④GUI 只读面范围 = 最小只读面（浏览可用 + 编辑入点禁用 + banner）⑤锁检查时机 = 启动 + 每写类调用前 probe（错误码 additive 一枚）⑥范围搭车 = o-2 `ColormatchResolverBox` NSLock 收紧随 M6-1（否决转 M6-5）。
