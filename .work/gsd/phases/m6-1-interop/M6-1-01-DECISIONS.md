# M6-1-01 DECISIONS — 执行期裁决与偏差登记（2026-10-13 执行批）

> 正本 = plan KD-1..KD-8（执行中未重开任何 KD）；本文件只登记执行期偏差、
> 机检清单与申报义务。六 OQ 生效值逐条兑现路径见 SUMMARY「Golden 五门」。

## D-1 bundle 归属勘误（AC8 数字面）

Plan SC 段「IOP 684/1/0 + 4 = 688/1/0」为 planner 近似：在库 Colormatch 单测
真实邻居 = **IOPParity**（BUNDLE-MAP 行 101-103：ColormatchIdentityGolden /
KernelParity / ModuleTests 三行均 IOPP）。ColormatchResolverBoxTests 按邻域
落位 IOPParity。**AC8 修正 = IOP 684/1/0 不变 + IOPParity 456→460/3/0；全套
预期 3684 不变**。BUNDLE-MAP 勘误注记同批（终值勘误惯例照 M2-8 批）。

## D-2 新增键 10 枚（KD-7 九键 + 申报一枚）

KD-7 九键全数入册 + **`session_lock_held`**（T2 legacy ride-along 的冲突文案——
KD-7 清单未含，执行 T2 时引入、T9 随批入册；10 枚 = 申报偏差，非静默）。
xcstrings 尾块纯插入两批（T4 块 + T9 两键补块），`git diff` = 纯插入行。

## D-3 writer 臂单点获锁（执行期设计修正，KD-4 实现细节）

初版 writer 臂 = 外部 `SingleWriterLock.acquire` + `store.open(role:)`——
**同进程第二 fd 对自己的锁 EWOULDBLOCK**（flock 按 open file description 仲裁，
checker o1 同源依据）→ 子进程打字错误 `projectHeldByOther(pid=self)` 自拒。
修正 = **store 是唯一获锁点**：`open(role: .headless)` 的 held 分支即只读臂
触发器，成功分支 store 内部持锁、close 释放。纪律沉淀 = **L079**。

## D-4 只读 HTTP serve 面（KD-4 的补充形状）

只读臂的 HTTP serve 不能走 `startHTTPHost`（其契约 = endpoint writer 锁 +
discovery json；GUI 持 endpoint 锁时子进程会 exit(4)，违背 OQ-3「只读常驻」）。
新增 `startReadOnlyHTTPHost`：不取 endpoint writer 锁、不写 discovery json
（该文件属 writer；指引已指向 holder 真端点）、`writerCheck { false }` 全写面
call-time 拒。stdio 只读臂照旧走 legacy stdio 体（endpoint 键与 json 面正交）。

## D-5 指引 JSON 确定性口径

JSONEncoder 的键序不构成契约（双跑实测键序漂移）——确定性门 = **decode 级
相等**（Codable struct Equatable），非字节级。序 A'（stdio 变体）单跑 +
序 A/序 B 各双跑；A' 的确定性由 A 双跑承载（同仲裁树、仅通道不同），申报
不计缺口。

## D-6 测试密闭性注入（DEBUG-only）

子进程无法收构造参数 → `LIGHTAMER_MCP_ENDPOINT_DIR` 环境变量在
`McpServerController.headlessEndpointPaths`（组装根读一次，L036 纪律；
`#if DEBUG` 分支，release 二进制不可达）。全部子进程测试经此重定向 discovery
面，零触碰用户 Application Support。

## D-7 legacy 冲突面接线（m2/m3a 兑现）

- legacy 冲突报告 = `SessionIndexController.sessionLockConflictHandler` →
  app 根接线 `editorState.presentToast`（既有 session 错误面即 toast——plan
  「alert 经 lastError」措辞按实际面落位，语义等价：typed 冲突经既有面）。
- legacy MCP probe（m2）= `holdsSessionLock` 自持豁免 + 真探回落
  （LightamerApp 装配闭包 `legacyLibraryEnabled` 分支）。
- legacy **无**只读回退面（KD-2 显式边界；M6-5 挂账）。

## D-8 快照族 additive 影响申报（D-M6-1-6 义务）

`McpToolError.projectReadOnly` additive 一枚：McpRegistrySnapshotTests（
writeCallCount 行为断言）与 McpFinalSnapshotTests（20 工具白名单）**零 diff
亲证**——错误码枚举无快照面（checker o2 预判兑现）。App 788/4/0 全量轮含内。

## D-9 只读面禁用清单机检表（KD-3 义务；走查配方 = MANIFEST B 行）

| 入口 | 覆盖缝 |
|---|---|
| Inspector 调整栈 | EditorState gate（recordChange/commitLayerEdit） |
| 节点图命令 | EditorState gate（recordChange/commitLayerStructure）+ UI 投影；NodeGraphCommand 零 diff |
| 蒙版编辑 | commitMaskEdit guard |
| 批量 apply | recordChange guard + LibraryStore withWriteBatch |
| Copy-Paste Adjustments | recordChange/commitLayerEdit guard |
| 导出入队（两代面） | ExportState gate（enqueueExport/enqueueExportM2 typed 拒） |
| yiyin sheet | 顶栏按钮 disabled 投影 + ExportState gate（队列腿同缝） |
| DRT/Film/LUT 面板 | recordDrtChange/recordFilmChange/recordChange guard |
| ~~版本三命令~~（omp 复审更正） | **VersionCoordinator coordinator 级 gate（六写命令全集）+ EditorState installVersionChain guard + VersionsPanelView 全控件 .disabled**——原「withWriteBatch + commit 族 guard 断路」宣称不成立（版本命令不经 commit 族），omp E-OMP-1 (b) 证伪后本批落地 |
| ~~历史写项（undo/redo/jump）~~（omp 复审更正） | **EditorState performUndo/performRedo（拒 false → PipeCoordinator 早退）+ performJump（no-op）+ PipeCoordinator.jumpToHistory 门读（堵 sidecar 尾 touchActive 写）+ Edit 菜单 .disabled**——原「跳转后任何落项均写 sidecar = 被断」宣称不成立（undo/redo/jump 本身直翻栈），omp E-OMP-1 (a) 证伪后本批落地 |
| 单图 paste（⌘V live 腿） | EditorState installMergePaste/installOverwritePaste guard（omp E-OMP-1 (a)） |
| batch paste（⌘⇧V 选择集） | pasteToSelection 入口门 + toast 拒（omp E-OMP-1 (c)；legacy 会话面不受项目锁门） |
| 导入 | LibraryStore withWriteBatch typed 拒 |
| Move Project | controller typed guard（moveProject isReadOnly 拒） |
| 顶栏导出/yiyin 按钮 | `.disabled(isReadOnly)` 投影（同源布尔） |

保持可用：浏览/检索/查看/soft proof/EDR/缩略图/Backup（只读拷贝）。第一防线
= UI 禁用投影；guard 兜底不 throw 不崩（EditorState 面）；写类 typed 拒
（ExportState/LibraryStore 面）。

## D-10 其余执行注记

- **T6 stdio EOF 腿** = `poll(2)` 零事件掩码盯 HUP（不与 transport 抢 stdin
  字节）；仅 `--project` 臂挂（无 project 路径零触碰）。
- **T9 表格式崩溃**（L078）与**单点获锁**（L079）沉淀 LESSONS。
- **McLauncher 文档面注记**（KD-4 末段）：agent 模板携项目路径撞 GUI 锁 →
  connect 指引即归宿（行为改善非回归）；v1 零 launcher 新键（范围裁定照
  plan 申报）。
- **backup/move 语义零变化**（KD-2）：backup 只读可走（T5 测试钉）；
  move = close→move→reopen 窗口锁短暂释放（五态③；第二实例可乘入 → typed
  冲突面，可接受，本注记即 plan 风险条登记）。
- **headless `--project` 打开即迁移** = 与 GUI 打开同语义（写权属持锁者；
  pre-migrate 快照在锁内），plan 风险条照登。
- **孤儿 fixture** `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 已删
  （M4-1 挂账 #6；untracked；后续轮未复活）。

## D-11 omp 计划复审批落地（2026-10-16 执行批，E-OMP-1 四 commits + 测试一批）

omp plan-review（`M6-1-01-PLAN-REVIEW-OMP.md` FAIL / 1E+5M）回注 plan 后的本批
执行记录（commits `f42dc13c` / `ed6ca3e7` / `cf36190a` / `f8e0671c` + docs）：

- **guard 家族 7→13**（E-OMP-1 (a)）：performUndo/performRedo 拒 `false`
  （PipeCoordinator :1827/:1836 既有 guard 早退零副作用）；performJump no-op；
  installVersionChain/installMergePaste/installOverwritePaste no-op。
  **执行期追加 `PipeCoordinator.jumpToHistory` 门读**（plan 处方外的一行）：
  makeSidecarDocument 对带版本结构的文档恒 `touchActive()`——blocked jump 若不
  堵尾仍会调度 sidecar 写 = 真 `.lra` updatedAt 突变；故 jump 腿在
  scheduleSidecarWrite 前读同一 EditorState gate（nil = 可写，零行为差）。
  installVersionChain 门安全性 = omp 亲证（全仓调用点仅 VersionCoordinator
  命令路径，hydrate 恢复流不走它）。
- **coordinator 级门拒时面 = typed no-op + logger（静默）**（E-OMP-1 (b) 处方
  「toast/typed 拒」取 typed 拒臂）：零新文案键（KD-7 十键清单不动），
  EditorState guard 同形；第一防线 = VersionsPanelView `.disabled` 投影
  （header/emptyState 四按钮 + 行 tap=switch + rename/remove 菜单项 + remove
  确认钮，同源布尔 = `versions.isReadOnly` → 装配点闭包读
  `libraryProjects.isReadOnly`——body 求值内闭包同步执行，Observable 追踪传递
  命中）。行 `.disabled` 落在 `.onTapGesture` 之后（gesture 在 disabled 子树内
  才权威失效）。
- **batch paste 门**（E-OMP-1 (c)）：`pasteToSelection` 入口 guard + toast 拒
  （复用 `project_read_only_banner` 键——holder pid 插值，只读打开 toast 同族，
  零新键）；谓词抽 `LightamerApp.batchPasteBlocked(gate:)` internal 纯函数 +
  `readOnlyPasteToast(holderPid:)` = golden 法④的可测缝（App struct 不可在测试
  构造）；legacy 会话面不受项目锁门（无项目打开 = gate 读 false，m2 二分天然
  满足）。
- **Edit 菜单四处 `.disabled` 追加 `|| libraryProjects.isReadOnly`**（E-OMP-1
  (d)）：undo/redo/paste-adjustments/paste-partial；jump 面板无 `.disabled`
  要求（performJump guard 兜底已足，plan 钉死）。
- **门 4 补 4 法**（E-OMP-1 (e)）：undo no-op / 版本命令六连拒（representative
  升级为全集）/ 单图 paste 拒 / batch 入口拒+toast——14→18 法；断言锚
  setup 后状态（gate 开的 createFromScratch 合法装空链，非 gate 泄漏）；
  rename 断言锚改名前捕获值（隐式槽名 locale 相关，不可字面比对）。
- **BUNDLE-MAP 6→18**：o-OMP-1 的 T10 终态对账（6→14）漏做，本批直落 18；
  六文件合计 57 法，全套预期 **3688**（估带 3683..3693）。
- **计数实测**：App **792/4/0**（= 788+4 精确命中）/ Library 654/4/0 不变 /
  App 峰值 2832MB；Schema/dependencies 零 diff 复验（`git diff a18cfb82..HEAD`
  两文件零命中）。
- **并发注记**：本批执行中途 sibling 验收修复批在同仓落 `5d814958`（session
  lock 同进程同根重开 seat 共享——M6-1-01 验收发现，非本批范围）；工作区无
  交叠文件冲突，commit 序 cf36190a → 5d814958 → f8e0671c 交错在案。
