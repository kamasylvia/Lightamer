# M6-1-01 PLAN-REVIEW-OMP — 独立第二遍（与 zcode checker 零共享上下文，2026-10-13）

**结论头：`FAIL / 1 error + 5 minor`**

- 复审员：omp（独立第二遍）；亲核 HEAD = `1ee26c40`（T1–T7 已 commit，T8 脏树未提交，T9/T10 未执行）。
- 输入面：`M6-1-01-PLAN.md` 全文 + `M6-1-CONTEXT.md`（OQ-1..6 全 A）+ `M6-1-CHECKER.md`（zcode FAIL 2E+3M）+ `RESEARCH-NOTES.md` + 源码锚逐文件亲读 + LightCraft 只读对照（`crates/catalog/src/lock.rs` + `docs/mcp.md`）。
- zcode 修复批 `26fd6bf0` 亲证 = plan 文本-only（E1/E2/m1/m2/m3 全部落位，见 §10）。
- 本报告新发现（zcode 未抓）：**E-OMP-1 + M-OMP-1..5**，见 §11；修复批回注最小集见 §12（全部 plan 文本编辑，零源码）。

---

## §1 六项裁决 → AC 完备性：✅（E-OMP-1 除外，见 §4/§11）

| OQ 生效值 | plan 落位 | 独立亲核 |
|---|---|---|
| ①锁粒度 `<stem>.lalb.lock` + legacy ride-along | KD-2 + AC1（门 1/序 B + 红线自证） | ✅ 路径拼接语义正确；`LibrarySchema` v4 零 diff 亲证（`git diff` 零命中）；`backup(to:)` sqlite3_backup 不携锁亲证；移动 close→move→reopen 窗口注记在册 |
| ②对称只读回退 | KD-3 + AC2（三选 verbatim + 双向确定性门） | ✅ 无角色特权；GUI 三选 / 无头只读+指引两臂对称；门 2 双序双跑设计可测 |
| ③无头只读常驻 + connect 指引 | KD-4 + AC3（JSON 逐键 + 通道分叉 + 降级 + 存活负测） | ✅ 否决项显式在册；通道分叉与 LightCraft `docs/mcp.md:26`「stdout carries only protocol messages」同纪律 |
| ④最小只读面 | KD-3 禁用清单 + AC4 | ⚠️ 清单列出 11 项，但 undo/redo/jump + 版本三命令 + Copy-Paste/batch 在 plan 内无确定落位（guard 名单封闭 7 函数不含，`.disabled` 接线点未指明，门 4 无对应法）→ **E-OMP-1** |
| ⑤启动 + 每写类 probe + additive 一枚 | KD-5 + AC5（门 5 含 live 先判序负测） | ✅ `-32002 作废`勘误正确（`McpToolError` 15 case 全 string code，wire 面 `McpAdapters.swift:44` 既有映射）；五落位恰合写类全集（§5 详核） |
| ⑥o-2 NSLock 搭车 | KD-6 + AC6 | ✅ 三写点亲证（`ColorMatchService:138/:309` + `MatchColorToolset:448`→现 `:454` 行号漂移）；`LutLibraryStore:105-123` 镜像源成立；T8 脏树改动与 KD-6 逐行一致 |

## §2 锁机制正确性：✅

- 五态语义逐条继承 `McpEndpointFile.swift` 头注（acquire / EWOULDBLOCK→只读 / 退出释放 / 崩溃释放 + O_EXCL+pid 明确不做 / probe 判残留）；O_RDWR|O_CREAT 0o600、`EWOULDBLOCK \|\| EAGAIN`、L009 目录腿逐条在 KD-1 与 `SingleWriterLock.swift` 对齐亲证。
- flock per-open-file-description 语义：KD-2 role-nil 依据与 KD-5 自持豁免**双向成立**（zcode o1 实证 + 门 1 `testAcquireSuccessThenSecondAcquireHeldByOther` 同进程二 fd 负测 + 门 2 真实跨进程序 A/B）。
- probe 自持豁免闭包三装配点亲证：无头两臂 `makeProjectWriteProbe(selfHeld:isWriter:)`（`McpServerController:150-160`）+ GUI 内嵌（`LightamerApp:1300-1330`，`isReadOnly` 门 + legacy `holdsSessionLock` 分支）——m2 接线真实在位。
- stale 语义 = 无清扫代码（kernel 释放），payload 缺席/陈旧不作判据（`holderSummary`「pid 未知」回落 + 门 1 负测）。与 `mcp-endpoint.lock` 纪律一致。
- close 释放序 checkpoint→handle close→unlock（`ProjectFileStore:303-312`）WAL 尾安全 ✅。
- `withWriteBatch` 断路单点覆盖面亲证：`LibraryStore` 12 写处 + `ExifSearchIndexer` 2 处全经 `withWriteBatch`；`LibraryQueries` 全 `withHandle` 读面；`ImportService.writeRow→insertRow→libraryStore.insertImage` 经断路 ✅（孤儿文件副作用见 E-OMP-1 处方注记）。

## §3 对称性 / connect 指引 / stdio 防污染：✅（+ M-OMP-3）

- 门 2 双序（序 A 父持锁→子无头 HTTP/stdio 双变体 / 序 B 子 fixture 持锁→父 `open(role:)`）+ 各自双跑逐位一致 + 五态③窗口重跑获 writer——对称性可测性成立。
- `connectGuidanceChannel(for:)`（`:109-114`）HTTP=stdout / STDIO=stderr；`log()` 走 unified log（`:817-820`）不污染 stdout；序 A' stdout 零字节负测（`testSequenceAStdioStdoutZeroPollution`）钉死。
- 只读 HTTP 臂不写 discovery json（`:368-399`「writer owns it」诚实面）✅；`--project` 校验（缺参/非 `.lalb` → stderr + exit 1）+ 无 `--project` 冒烟（`testNoProjectStdioSmoke`）零回归面 ✅。
- 缺口：指引 JSON 的 `holderPid` 缺席值未钉（执行用 `-1`，`McpServerController:334`，plan KD-4 schema 无定义，门 3 无 `-1` 变体）→ **M-OMP-3**。

## §4 GUI 只读面范围：❌ → E-OMP-1（error，§11）

- 已落位亲证：banner（`WorkspaceHostView` top safeAreaInset + `shell.readonly.banner` AX 标识）+ 只读打开一次性 toast（复用 banner 键）+ 三 seam（`withWriteBatch` typed 拒 / `EditorState.projectReadOnlyGate` 7 函数 backstop / `ExportState` 双 enqueue guard）+ export/yiyin 双 `.disabled` + 冲突对话框三选（sheet 面，M2-8-3 FINDING-A 边界遵守）+ terminate 腿（`:1216-1230` 窗内）。
- 缺口：KD-3 禁用清单 11 项中，**undo/redo/jump + 版本三命令（+switch/rename/remove）+ Copy-Paste 全路径（含 batch）+ 批量 apply** 在 plan 内无落位——guard 家族封闭 7 函数（`recordChange/commitMaskEdit/commitLayerEdit/commitRetouchEdit/commitLayerStructure/recordDrtChange/recordFilmChange`）不含任何 history 导航/安装入口；`.disabled` 接线点（Edit 菜单 undo/redo/paste、版本面板）未指明；门 4/T5 14 法无对应覆盖。只读第二实例 ⌘Z/切版本/粘贴 → `scheduleSidecarWrite` 改写 `.lra` = 单写者语义泄漏（亲证链见 §11 E-OMP-1）。

## §5 MCP typed projectReadOnly additive：✅

- `McpToolError.projectReadOnly(String)` additive 一枚 + code/message 两 switch 补臂亲证（`McpToolRegistry:75/:94/:107`）；wire 面经 `:44` 既有映射零新面。
- 写类全集 9 工具五落位亲证：apply_params body（live 判据 `:544-552` 之后 `:557`）/ export_image body 头（`:314`，D8 无 live 判据不对称保留）/ write-five frame（`requireMembers` 后 `:354`）/ apply_preset 成员（`:575`，list 读类无 probe 正确）/ match_color attach 门内（live `:404-407` 之后 `:416`）。
- `writerCheck` 旧门零改（`registry.call:333-340`，`serverReadOnly` 先于 probe，门 5 `testServerReadOnlyFiresBeforeProjectProbe` 钉序）；probe nil 档零行为（`rejectIfProjectReadOnly:178` guard）；自持豁免负测（`testSelfHeldExemptionLetsWritesThrough`）钉 writer 臂不自拒。
- 20 工具封闭集：零新 `register` 调用，零工具描述改动（Errors 列不列新码 = 红线合规，o-OMP-5）。

## §6 legacy ride-along 边界：✅（+ M-OMP-2）

- KD-2 边界显式（只落锁 + 冲突告警，只读回退挂 M6-5）+ m2 probe 接线（`LightamerApp:1302-1316` + `holdsSessionLock`）+ T10 DECISIONS 登记义务 ✅。
- plan 文本事实错误两处写「typed 冲突经既有 **lastError** alert 面」（KD-2 + T4 m3a 回注）——`SessionCoordinator` 无 `lastError` 成员（基线/HEAD 双亲证 0 命中）；实际执行 = `sessionLockConflictHandler` → toast（`LightamerApp:820-824`）→ **M-OMP-2**。

## §7 o-2 NSLock 收窄：✅

- KD-6 与脏树 T8 改动逐行一致：holder 三件（`sharedLock/sharedInstance/getter/replaceShared`）+ 三写点 `replaceShared`（含 `:448`→`:454` 漂移点）+ forward 读局部化；零裸 `shared =` 残留（全仓 grep 亲证）；`ColormatchResolverBoxTests` 4 法语义全对。
- 行号锚漂（`:97/:106`）属 cosmetic（zcode o4 同类）；并发压测为「可选项」故 4 法无并发法合规。

## §8 golden 五门：✅（门 4 缺 E-OMP-1 四组）

- 门 1：`SingleWriterLockTests` 8 法 = acquire 互斥 / unlock 让渡 / probe 三态 / payload 冻结拼写负测 / pid 缺席回落 / ioError / 父目录创建 / unlock 幂等+path ✅。
- 门 2/3：`McpProjectArbitrationTests` 9 法 = 序 A alive + 降级 + 序 A' stdio 零污染 + 序 B typed 冲突 + 双确定性双跑 + ③窗口 writer 臂 + flag 校验 + 无 project 冒烟 ✅（真双进程 + hermetic env 重定向）。
- 门 4：`ProjectReadOnlyFaceTests` 14 法（6+8）= 冲突投影（含 m3a legacy 并档）/ 三选三腿 / flush / L057 / store 拒 / gate 双测 / export 双测 / banner AX / move 拒 / backup 允 ✅——但清单中 undo/版本/paste/batch 四组无法规测试位 → E-OMP-1。
- 门 5：`McpProjectReadOnlyErrorTests` 8 法 = held typed / live 先判 / nil 档 / serverReadOnly 先序 / 自持豁免 / export_image / culling 五写+读类无扰 / match_color attach 门 ✅。

## §9 测试对账：✅

- 基线：`grep -c "func test" Tests/LightamerTests` = **3686** = 3633（zcode 亲证静态值）+ 53（六新文件 8+10+9+8+14+4 逐文件亲数）——与执行口径 3631→3684（-2 恒定差）自洽；派发指令 3367/16/0 失真勘误链成立。
- 分账：LIB +18（654）/ APP +31（788）/ IOP +4（688）；`estimated_tests` "+48..58" ∋ 53；估带 3679..3689 ✅。
- BUNDLE-MAP 中间态：`APP 6 ProjectReadOnlyFaceTests.swift` 为 T4 登记值，T5 后半 8 法未同步行内数 → T10 终态对账 6→14（o-OMP-1，不计数）。

## §10 修复批后 plan 自洽性：✅（五处全闭合）

- **E1**：五同步点（front-matter `:9` / 头基线注 `:53-61` / KD-8 `:359-373` / T10 `:522-523` / AC8 `:555-557`）= 53 / APP 788 / 全套 3684 / 估带 3679..3689 全一致 ✅。
- **E2**：KD-2 schema 三岔钉死（`:145-165`）+ T2 负测并入「计数不变」✅；执行拆两法（old-version + zero-stub）但以 detail/backup 两概念项并档消化，总数仍 10 ✅。
- **m1**：KD-4 writer 臂 v1 定位回注（`:233-239`，SessionProvider 恒 `{nil}` + 工具面不变 + M6-2 承接）✅。
- **m2**：KD-5 legacy 判据源接线（`:282-291`）+ T7（`:497-498`）+ T10 DECISIONS 登记（`:520`）✅。
- **m3a/m3b**：T2 原语级 + T4 并档（`:453-456/:470-472`）✅；guard 真名 `recordDrtChange:250/recordFilmChange:273`（基线亲证 `:273`，checker `:270` 确为锚漂）+ HistoryStack 零触注记 + read_first 行号 ✅。
- `26fd6bf0` 零源码亲证（`--stat` 仅 PLAN.md；CHECKER.md 在 `abd7b389`）✅。

## §11 独立发现（zcode 未抓）

### E-OMP-1（error）：只读态 history-mutating 入口无落位——⌘Z/切版本/粘贴改写 `.lra`

**事实链（全亲证）：**

1. plan KD-3 禁用清单含「历史写项含 undo/redo/jump（均产生新 sidecar 字节 = 写项）」「版本三命令」「Copy-Paste Adjustments」「批量 apply」，机检形 = 「每个 UI 写入口要么被 `.disabled` 投影覆盖、要么被三 seam 之一兜底」。
2. 三 seam 实际覆盖（`EditorState.swift` 全文 grep）：
   - guard 家族 = 7 函数（`recordChange:200/commitMaskEdit:723/commitLayerEdit:812/commitLayerStructure:1088/commitRetouchEdit:1211/recordDrtChange:275/recordFilmChange:299`），全部 `projectWriteSuppressed()` backstop ✅；
   - **无 guard**：`performUndo:370/performRedo:379/performJump:388`（直改 `history` 栈）+ `installMergePaste:330/installOverwritePaste:341/installVersionChain:132`（直装新栈）；
   - `VersionCoordinator` 七命令（`createFromScratch:155/branchFromCurrent:178/pasteChain:214/switchTo:257/rename:271/remove:288`）经 `installVersionChain` + `finishVersionAction→versionActionDidChange→scheduleSidecarWrite` 落盘——**零门**；
   - `LightamerApp.pasteToSelection:2239` batch 路经 `SessionBatchApplier + batchSidecarWriter` 直写 `.lra`——**零门**（legacy/项目面未二分）。
3. `.disabled` 第一防线：全仓 `isReadOnly` 残疾投影仅 export/yiyin 两处（`WorkspaceHostView:610/:623`）；Edit 菜单 undo/redo（`LightamerApp:1669/:1674`，仅 `canUndo/canRedo`）/ paste（`:1689/:1694`，仅 `hasPayload`）/ 版本面板 / jump 面板**零接线**。
4. 后果：只读第二实例 ⌘Z → `PipeCoordinator.undo:1826-1831`（`performUndo + scheduleSidecarWrite`）改写 `.lra` position；切版本/粘贴同理 → 与持锁实例互覆盖 = **单写者语义泄漏**，直违 phase goal「补齐双写缺口」与 OQ-4 生效值。
5. plan 测试缺口：门 4/T5 14 法无 undo/版本/paste 任一对应法；DECISIONS 机检表是登记义务非落位设计——plan 未告诉 executor 这些清单项走哪条路（guard 名单封闭，`.disabled` 接线点未指明）。

**处方（plan 文本编辑，零源码）：** KD-3 补「历史导航/版本/paste 落位」段——
  (a) guard 家族增 `performUndo/performRedo/performJump/installMergePaste/installOverwritePaste/installVersionChain`（no-op + logger 同形；HistoryStack 零触维持，m3b 纪律）；
  (b) `VersionCoordinator` 七命令 coordinator 级 `isReadOnly` 门（`ExportState` 缝形，装配点接 `libraryProjects.isReadOnly`）；
  (c) `pasteToSelection` batch 路项目面门（入口 guard + toast/typed 拒；legacy 会话面 paste 不受项目锁门——m2 二分明确）；
  (d) Edit 菜单 undo/redo/paste + 版本面板 `.disabled` 接 `isReadOnly`（第一防线，接线点逐个指明）；
  (e) 门 4/T5 增 3–4 法（undo no-op / 版本命令拒 / paste 拒 ± batch 拒），计数按 E1 惯例同步五点（53→56/57，SC/AC8/T10/front-matter/BUNDLE-MAP 终态）。
  附注：导入兜底（`withWriteBatch` typed 拒）在 placement 之后触发会留 Media/ 孤儿文件——导入以 UI 禁用为主、typed 拒为兜底，孤儿副作用 DECISIONS 登记。

### M-OMP-1（minor）：KD-7 键清单漏 legacy `session_lock_held`

- plan KD-7 申报 9 枚；执行在册 8 枚 = 7（`project_read_only_*` 六 + `mcp_error_project_read_only`）+ **`session_lock_held`（plan 未登记的第 10 键）**；`mcp_connect_guidance_stderr` 双键引用在码（`McpServerController:354/:359`）但 catalog 缺席（运行时回落中文 defaultValue——en 用户见中文）。
- 处方：KD-7 补 `session_lock_held` 登记（9→10 枚，或明确 legacy 键归属）；T9 收口补插 guidance 双键（执行侧，T9 未跑故可补）。

### M-OMP-2（minor）：「lastError alert 面」锚虚构

- plan KD-2（`:174-175`）与 T4 m3a 回注（`:471-472`）写 legacy 冲突「经既有 lastError alert 面」——`SessionCoordinator.lastError` 基线/HEAD 双亲证 0 命中；实际执行 = `sessionLockConflictHandler` → toast。
- 处方：两处改「经 `sessionLockConflictHandler` → toast 面」。

### M-OMP-3（minor）：指引 JSON `holderPid` 缺席值未钉

- plan KD-4 ② schema 只钉 event/endpoint/holderPid 三键；payload 缺席时执行用 `-1`（`:334`），plan 无定义，门 3 无 `-1` 变体。
- 处方：KD-4 补「payload 缺席 → `holderPid: -1`」+ 门 3（或门 1）增一断言。

### M-OMP-4（minor）：create/move 生产路径 role 缺位——KD-2「语义闭合」宣称不成立

- plan KD-2 宣称「生产强制点 = 装配层两点，一切生产打开路径经此两点，语义闭合」；实际生产路径五处中三处未传 role：`createProject→store.create(name:)`（`:115`）、move 失败回开 `store.open()`（`:266`）、move 新位重开 `moved.open()`（`:273`）。
- 后果：新建/移动后项目无锁常驻 → 另一实例 `open(role:)` 获写成功 → 双写（第一实例无锁读写，第二实例持锁读写，互不知晓）；KD-2 移动窗口注记（`:170-171`「乘入落 typed 冲突面」）以重开持锁为前提，前提不成立。
- 处方：KD-2 补 create/move 角色要求（create 传 `.gui`；move 两重开腿传 `.gui`；或 store 级 role 记忆跨重开——三选一钉死）。

### M-OMP-5（minor）：网络卷 flock 不可用策略未钉

- LightCraft 对照（`lock.rs:22-24` + issue #171 测试）：锁文件不可锁 → 开但警告。plan KD-2/T2 只覆盖坏路径 ioError（open 失败形）；flock 本身 `ENOTSUP`（网络卷）→ `ioError` → 项目锁面 `openFailed` 拒绝 = 项目打不开。macOS 独占本地盘为主故 minor，但行为应钉死。
- 处方：KD-2 补一句（拒绝并文案说明 / LightCraft 式警告开锁——二选一）。

### Observations（不计数）

- o-OMP-1：BUNDLE-MAP `APP 6 ProjectReadOnlyFaceTests.swift` 为 T4 中间态 → T10 终态对账 6→14。
- o-OMP-2：T8 脏树未提交（o-2 三文件 + BUNDLE-MAP + Project.swift + `ColormatchResolverBoxTests.swift` 未跟踪）+ 孤儿 `.lra` 未删 + T9/T10 产物（SUMMARY/DECISIONS/ACCEPTANCE/MANIFEST）不在盘——验收前闭合。
- o-OMP-3：`readPayload` 非原子读（对 `writePayload` truncate+write 半截 JSON → decode 失败 → nil 回落）= 安全方向，无需改。
- o-OMP-4：`unlock()` 双调 fd 重用窗理论存在；生产路径 `releaseProjectLock` 置 nil 幂等 + 测试双调覆盖，同线程顺序安全，无需改。
- o-OMP-5：工具描述 Errors 列不列 `projectReadOnly` = 红线「零工具描述改动」合规，MCP 客户端自解释性小损，plan 已裁定。
- o-OMP-6：KD-5「preset-trio frame」实际仅 apply_preset 成员有 probe（list 读类无）——执行正确，plan 表述可精化。
- o-OMP-7：`role: role ?? .headless`（`ProjectFileStore:246`）右臂不可达（前有 `guard role != nil`）——死码一行，cosmetic。
- o-OMP-8：LightCraft `LOCK_UN`-before-close（issue #680：spawn 窗子进程继承 fd 致重开被拒）——我方 `unlock()` 同为 flock-then-close 同形 ✅；且 `SingleWriterLock` 无 deinit（fd 随进程死 kernel 收，store close 显式释）——与 `McpEndpointLock` 原形一致 ✅。

## §12 修复批回注最小集（全部 plan 文本编辑，零源码）

1. **E-OMP-1**：KD-3 补历史导航/版本/paste 落位段（§11 处方 a–d）+ 门 4/T5 增 3–4 法 + 计数五点同步（E1 惯例）。
2. **M-OMP-1**：KD-7 补 `session_lock_held` 登记（9→10 枚）。
3. **M-OMP-2**：KD-2/T4 两处「lastError」改 `sessionLockConflictHandler` → toast。
4. **M-OMP-3**：KD-4 补 `holderPid: -1` 缺席值 + 门 3（或门 1）一断言。
5. **M-OMP-4**：KD-2 补 create/move 角色要求（三选一钉死）。
6. **M-OMP-5**：KD-2 补网络卷 flock 不可用策略句（二选一）。

修复后 plan 重审范围 = 仅上述六处（无需全文重审）。

PLAN-REVIEW: FAIL
