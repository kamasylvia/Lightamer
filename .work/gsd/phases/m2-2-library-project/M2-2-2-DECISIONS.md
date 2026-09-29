# M2-2-2 DECISIONS — 执行决策记录

> Plan M2-2-2 执行期决策（2026-09-29）。KD-1..6 = planner 裁决，逐条执行确认；
> D1..D12 = 执行偏差/细化，均实测归因，不重开任何 CONTEXT 裁决。

## KD 执行确认（planner 裁决 → 落地状态）

- **KD-1（过滤单一纯函数面）✅**：`ImportFilter.select` 判定序 ①hidden（`.` 前缀 + 真实
  isHidden flag，唯一 IO 点）②硬编码排除表（最后后缀）③白名单（最后后缀精确、case-insensitive、
  空后缀拒）。`photo.ARW.xmp` 天然落 ②；`raw.xmp.arw` 双后缀伪装按需求字面收（testLastExtension
  SemanticsDocumented 钉文档）。排除表永读配置（配置含 xmp 仍拒，testConfigurationCannotRe_admit）。
- **KD-2（plan→executor→commit 骨架）✅**：DB 行只在文件落位成功后写（writeRow 在 rename/copy/
  link 成功腿尾部）；批尾一次 rebuildFTS（有行才跑）；崩溃最坏「已拷未行」由重复检测兜（等价字节
  → skip）。EXIF 走 M2-2-1 Indexer 缝（fillMetadata per row），零新键位代码（KD-6）。
- **KD-3（Media/<folder>/<rel> 落位 + resolve 规则）✅**：kind0 = `Media/...` 项目相对；kind1 =
  卷根相对 + volumeUUID（statfs 挂载点 + URLResourceKey.volumeIdentifierKey）；kind2 = 绝对 +
  UUID（UUID 不可得 typed 降级 nil）。stale 两形态按 OQ-5 字面。relink = record 复用（M2-3 挂 UI）。
- **KD-4（对话框/进度无副作用薄壳 + Core 状态面）✅**：ImportModeChoice/ImportDefaults Core 定义
  测试直构；对话框初始值由命令路由在 body 外 seed（D-EXEC-1 纪律）；storeChoice 在 ACTION 落盘
  （remember=false 全清，单次覆盖不落盘 testSingleShotOverride 钉）。进度快照 immutable struct +
  setProgressHandler 缝（CatalogRebuilder 同型）；取消 = per-file 检查点（handler 内直接
  `await service.cancel()`，actor 重入点确定 → cancel 测试确定性 2/5）。
- **KD-5（Controller 命令族 + welcome 最小化）✅**：recent 去重移前/上限 10/失效清扫/跨实例持久
  （SessionState.promoteRecent 同型）；backupProject 唯一消费 backup API；moveProject = 整目录
  （close 先行 checkpoint；同卷 rename；跨卷 copy→verify→remove 红线复用；verify 失败原位
  reopen + typed 抛）；`.lathumbs` copy 腿跳过、rename 腿自然随行（派生物无数据危害，D11）；
  backup API 消费者仍唯一。App 接线 = File 菜单命令 + 无项目且无 recent 时欢迎 sheet（OQ-1 A
  字面）；Sidebar/ContentView 零改动（diff 自检）。
- **KD-6（EXIF 零重发明）✅**：fillMetadata + rebuildFTS 全走 M2-2-1 缝；EXIF 测试用合成
  JPEG-with-EXIF 字节存 .ARW 名（ImageIO 按 CONTENT 读、白名单按 EXTENSION 收——两面同时 exercised，
  零真片）。

## 执行决策（D1..D12）

- **D1 FIRMLINK 拼写差 → 相对分量扫描（本 plan 最大实现发现）**：temp 目录实测三重事实——
  ①`FileManager.enumerator`/`contentsOfDirectory` 产出的子路径一律解析到 `/private/var/...`，
  与调用方 URL 的 `/var/...` 拼写不一致；②`resolvingSymlinksInPath()` 不解析 firmlink（/var
  原样返回）；③`/System/Volumes/Data/var/...`（挂载点内拼写）不可达。推论：对 enumerator 绝对
  路径做前缀裁剪**构造性不可靠**（T3 首轮 6/9 测试失败的根因）。修复 = 扫描器逐层
  `lastPathComponent` 积累相对分量（拼写无关），link 测试断言改 fileIdentifier 同文件比较。
  教训落 L039。
- **D2 `setUUIDProbe` 测试缝**：plan 红钉只列 `verifyStrategy` 缝，但跨卷腿在单卷测试机
  结构性不可达——补 `setUUIDProbe`（默认 `ImageLinker.volumeUUID`）强制跨卷；Controller 侧
  moveProject 镜像同缝（verifyStrategy + uuidProbe 双注入）。生产零影响。
- **D3 ImportMode/ImportModeChoice/ImportDefaults 落 ImportFilter.swift**：plan 未单列文件；
  三键宿主与 select 同文件 = 最小文件面（Library/ 目录惯例内聚）。
- **D4 App 侧 ImportService 撞名**：`App/Sources/Lightamer/Session/ImportService.swift`
  （M1 session-import enum）与 Core 新 actor 同名——控制器以 `LightamerCore.ImportService`
  模块限定消歧（Core 内无歧义；M1 面不动画 P4 一起收）。
- **D5 projectURL 控制器自持**：`ProjectFileStore.fileURL` 是 actor-isolated 属性，视图/命令
  需同步读——控制器自存 URL（create/open/move 维护、close 清空），**不**给 M2-2-1 文件加
  `nonisolated`（diff 边界保洁净：plan 未申报 ProjectFileStore.swift）。
- **D6 moveProject containment 守卫**：T4 首轮测试把 `.lalb` 直放 temp root（项目目录=root），
  目的地 root/Moved 在源内 → `moveItem` 自嵌套递归（Moved/Moved/... 千层）。生产加固两 typed
  守卫（目的地在源内 / 源在目的地内均拒）+ 测试 fixture 改每项目独立目录（真实包形态）。
- **D7 skippedDuplicates 计数修复**：executor 首版返回 Bool——「重复跳过」与「无行可写」共用
  false，outcome.skippedDuplicates 恒 0（测试捕获）。改 `StepResult` enum（imported /
  duplicateSkipped），进度快照同步该计数。
- **D8 欢迎视图 + LibraryPanels 落 LibraryProjectController.swift**：files_modified 未单列
  welcome/panel 文件；三按钮最小入口（OQ-1 A 字面：无项目**且**无 recent 时启动展示、可「稍后」
  关闭与 Session 面并存）与 NSSavePanel/NSOpenPanel 包装同文件内聚。verbatim 字符串（D-EXEC 同源：
  新键不入 String Catalog，zh 随 M2-3 壳批）——构建后 git status 证实 catalog 零 churn。
- **D9 新命令快捷键冲突核查**：⌘N（New Project）/ ⌥⌘O（Open Project）/ ⇧⌘I（Import Folder）
  对全表既有项零冲突（D-8 冲突表口径复核：bare i 未占、⌘⇧E/O/N、⌥⌘S/I/P 不撞）。
- **D10 tuist generate 分任务补跑 ×3**（T1/T2/T3-T4 各一次）——每任务独立提交纪律下新文件
  各自 generate（M2-2-1 D2 同判）。
- **D11 `.lathumbs` rename 腿随行**：KD-5「可丢弃不搬」——copy 腿逐文件复制可跳过已跳；
  rename 腿整目录移动天然携带派生缓存，删除重建成本为零、无数据危害，不做 rename 后清理
  （避免多余的二段删除窗）。
- **D12 提交序列事故与修复（透明记录）**：AC⑦ 回滚测试补入时 `git commit --amend` 误叠 T4
  HEAD；soft-reset 修复时裸 `git commit` 把 T3+T4 混提一笔（0ecdf11，作废）。终态 =
  `git reset`（unstage 全部）→ 按 pathspec 分批 add → `-C` 复用原 message 重提（T3 `c6eee61` /
  T4 `b30d8e5`），边界核对干净。教训候选：soft-reset 后多提交序列必须 pathspec-scoped add
  + 裸 `git commit` 禁用。

## 风险与边界（兑现情况）

- fixture 版权：全合成字节（确定性 pseudo-random + ImageIO 合成 JPEG），ARW 命名 + 真实目录
  形态——AC③ 缺陷形态（文件数翻倍）完整复现；真目录复跑 = Manual-Only。
- USB 卷相对链接（L009）：kind1 逻辑全 temp 测试（fileIdentifier 断言拼写免疫）；真实卷
  UUID 稳定性 = Manual-Only 观察项 3。
- 大目录扫描：actor 内同步递归 + scanning phase 进度（v1 无分批流式）；吞吐观察项入 SUMMARY。
- M1 并存：Session 面零改动（diff 空）；项目入口为并列路径；收窄归 M2-2-4。
