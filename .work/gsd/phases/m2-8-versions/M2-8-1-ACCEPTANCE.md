# M2-8-1 ACCEPTANCE — 版本模型核（sidecar v7 + 链 swap + version_ref 投影激活）独立验收

> 验收：ZCode 验收 subagent，2026-10-01。对象 = 执行方 4 commits + 收口（`2afeb3a` T1
> sidecar v7 / `788e1a7` T2 VersionCoordinator / `69a30ec` T3 version_ref / `0578da1` T4
> 收口；plan 正本 = checker 修正版 `527d4ba`）。方式 = AC 12 条逐条核对 + 六重点定向核查
> （diff 逐文件复核 + 测试代码真伪审读 + 三域独立复跑 + grep/git 机检）。
> **结论头：PASS / 0 error + 1 minor（已修，同批）+ 2 observation。**

## 一、复跑 vs 声明

| 项 | 声明 | 本轮独立实测 | 判定 |
|---|---|---|---|
| App 域 | 448/0/0 | **448/0/0**（176s，peakRSS 1329MB——HEAD 增量 build-for-testing 后 `Scripts/test-direct.sh --bundle App` 亲跑） | ✅ 逐值一致 |
| Library 域 | 436/4/0 | **436/4/0**（21s，peakRSS 305MB，亲跑） | ✅ 逐值一致 |
| Layers 域 | 298/3/0 | **298/3/0**（21s，peakRSS 1093MB，亲跑——零改动域复归） | ✅ 逐值一致 |
| 全套 | TOTAL\|2550/16/0\|897s EXIT=0 | 采用执行方声明对账（--all 批准门不重跑，per dispatch）+ 三域定向亲跑平值 + 增量算术亲核：2525 基线 + 25 = 2550（新增 26 法 − 1 改名 = 净 +25，见 §三⑥） | ✅ 对账一致 |

三域复跑命令：`caffeinate -dis xcodebuild build-for-testing`（EXIT=0，增量）→
`Scripts/test-direct.sh --bundle {App,Library,Layers}`。二进制 mtime（Oct 1 18:23-27）晚于
最后源码提交 T3，T4 为纯 docs——产物与 HEAD 源同源。

## 二、AC 12 条逐条判定

| # | AC | 判定 | 证据 |
|---|---|---|---|
| 1 | v7 三字节面 + 既有 pin 测试除显式触点外零改动 | ✅ | SidecarV7Tests 三法逐一审读（①v6 形 decode→re-encode 逐字节相等；②全 nil 版本面 = v6 形仅 schemaVersion 位差——字符串替换后全等断言 + 回拨字节 decode `schemaVersion==6` 零版本键；③带版本 round-trip 字节忠实 + re-encode 同字节）。DrtSidecarTests 仅 `:71` pin + 头注释（diff 复核）；SidecarV5Tests 全程零触（不在 diff 文件集）；SidecarMetadataV3Tests = 申报增补③ |
| 2 | historyHash 零折叠 + HistoryHash/HistoryStack 零 diff | ✅ | 篡改 `versions[].name` → `driftDetected == false` 负测在场；`git diff 527d4ba..HEAD --name-only` 机检两文件零命中；hash 函数签名零改动（结构性保证）|
| 3 | swap 真链五面 | ✅ | VersionSwapTests 11 法全真链（makeAssembly = 真 EditorState+PipeCoordinator+VersionCoordinator+MetalContext，零存储后门）：materialize 双槽/branch 快照时点（源版本保 jump 点 position=1 + 3 items 完整）/switch 往返 items+position 精确相等/remove active 切首/remove 唯一回隐式保链/dangling typed degrade 保 history |
| 4 | 切换即时 | ✅ | EditorState diff 仅 +26 行（attach + installVersionChain——`rebuildInstances()/rebuildLayerStack()` 本体零 diff 机检过）；`versionActionDidChange` = syncDrtCarrierWithHistory + historyDidChange（param 重放路径）+ scheduleSidecarWrite；零重解码 = 结构性保证（EditorState 半径无 decode 面，AC 机检栏只要求 VersionSwapTests + diff 半径，均满足）；DRT carrier 跨 swap 重同步测试亲读（redo 腿重放 + 双向切换 carrier 跟随 + drtTailActive 翻转断言）|
| 5 | pristine 收窄 | ✅ | KD-6①：零编辑 createFromScratch → flushUntilPersisted → `.lra` 在盘 + `history.position == -1` + versions 2 槽；KD-6②：空 active 链 + 非空 versions → `effectiveInstances().isEmpty` 仍真 |
| 6 | items 不双写 | ✅ | 全文档 `"items"` 出现次数 == 1 计数断言 + active 记录（按 activeVersionID 匹配）无 `chain` 键双断言（SidecarV7Tests）+ post-swap 落盘文件态断言（VersionSwapTests 法 9：active 槽 chainStack 为 nil + branch 链停在 versions[]）|
| 7 | version_ref 激活 | ✅ | 翻面负测（version_ref 存在 + `PRAGMA table_info` 列序对照 `versionRefColumns` + CASCADE DDL + 无 head_commit_hash + 余三名仍负）；v2→v3 迁移（手造 29 列 v2 包 → 真 `ProjectFileStore.open` → user_version==3 + `pre-migrate.2-3.bak` 诞生 + 旧行完好）；链式两代见 §三②；fresh v3 直落；close 后 detached 读（L051 形态）|
| 8 | replaceVersionRefs 四面 + 命令投影 reconcile | ✅ | round-trip 行集相等/reconcile 删除/幂等/FK CASCADE/typed unknown-image（LibraryStoreTests 3 新法）+ VersionSwapTests 法 11（真 `.lalb`：create+rename → 行集镜像；remove 逐级 → 行清空面；bounded settle 轮询）|
| 9 | 注入式投影 | ✅ | sink 装配在 `loadCurrentImage()`（private async func，非 body）——`grep LibraryStore App/Sources/Lightamer/UI/` 仅命中该函数 + 既有 defaultLookPending 同位读（LutLibraryStore 为异名旧类）；Sessions 模式 projectStore nil → sink=nil 零引用；App bundle 全绿即 Sessions 零回归 |
| 10 | 全套 0 fail ≈ 2525+30..38 | ✅ | 2550/16/0（声明对账 + 三域亲跑平值）；+25 在 30..38 预估带下方但为 BUNDLE 行精确对账值（预估非承诺）|
| 11 | diff 边界 | ✅ | 集合差机检：actual(23) − front-matter(20) = 恰好 3 处已申报增补（LightamerApp/DrtPersistenceTests/SidecarMetadataV3Tests），反向差空；红线五文件（HistoryStack/HistoryHash/PixelPipe/PipeCacheKey/LayerCompositeDriver）零 diff；ProjectFileStore 触碰 = 轮换单点 + backup 签名收窄 + 头注释（E2 申报面，dispatch 形状零改亲读）|
| 12 | 登记闭环 | ✅（带勘误） | Project.swift 两文件 + BUNDLE-MAP 两行双命中；**per-file 计数过时 = 本轮唯一 minor，已修**（§三⑥）|

## 三、六重点核查结论

### ① E1 public 面三件——**实现与申报逐行一致**

- `SidecarVersionRecord.public init(id:name:createdAt:updatedAt:chain: HistoryStack?)`：
  在场，`chain.map { SidecarHistoryRecord(stack: $0) }` 单点铸造（App 永不见 internal
  record）；`public var chainStack: HistoryStack? { chain?.stack }` 读取面在场——
  SidecarLayerRecord/Snapshot 双先例同款。
- `public extension HistoryStack { static func copyingPrefixOf(_:upTo:) }`：落
  LightamerSidecar.swift（落位注释钉明红线理由），index 双向 clamp（-1 → 空栈；
  超 count-1 → 全量），position = 拷贝尾；**HistoryStack.swift 本体零 diff 机检过**。
- 两 record private→internal：diff 纯 access-level 关键字替换，拼写零改动亲核；
  internal 化理由（版本链嵌同一份编码器，复制键集 = 双格式迁移债）入 commit body +
  DECISIONS 签注。
- 消费面闭环：PipeCoordinator 写腿经 public init 投影、hydrate 经 chainStack 读回、
  branchFromCurrent 经 copyingPrefixOf——三缝各有真实调用者（grep 亲核）。

### ② E2 链式迁移测试真伪——**真实模拟，死锁钉死成立**

- 手法审读：程序化造 v2 包 → `ALTER TABLE images DROP COLUMN default_look_pending` +
  `writeUserVersion(1)` 回拨成 v1 形态 → **真 `ProjectFileStore.open`** 迁 1→3（断言
  `pre-migrate.1-3.bak` 诞生）→ close → **独立 SQLiteHandle 回拨 user_version=2**
  （模拟上一代在线产物）→ 二代 open 迁 2→3 → 断言 `pre-migrate.2-3.bak` 与 `1-3.bak`
  **共存**（代际轮换非覆盖）→ close 后读 user_version==3。回拨是真实写库操作而非
  mock，迁移走生产 dispatch 路径——手法真实。
- 轮换实现亲读：快照名 `<stem>.pre-migrate.<stored>-<to>.bak` 代际命名 + 同名旧件
  `removeItem` 后重照；`backup(from:to:allowExisting:)` 死参收窄为 `backup(from:to:)`
  （refusal 上移 public `backup(to:)` 一帧行为不变——「allowExisting 从无 true 调用者」
  亲核属实）；dispatchSchema 三路 dispatch 形状零改。
- 定向复跑：Library 域 436/4/0 含该测试全绿。

### ③ E4 跨图污染用例——**真链往返，断言充分**

A 图（branch+create → 3 槽，flush 落盘）→ 切 B（无 `.lra`）→ 断言 slots 清空 +
activeVersionID nil（A 不泄漏）→ B 首创建 = **「Version 1」起算**（slots[0].name 断言，
非「Version 4」）→ 切回 A → 断言 3 槽从 A 的 `.lra` 重水合 + 首槽链 items `["a1"]`。
覆盖 plan 要求的起算断言且超出（往返重水合腿）；hydrate nil 臂与 pristine seed 臂
（load 无 `.lra` 路径）双清空口都在 PipeCoordinator diff 落实。

### ④ v7 字节 pin 与不双写——**三面 + 计数断言全部成立**

见 §二 AC1/AC2/AC6。补一点：v6 形测试先断言两新键缺席再回拨版本位做 round-trip——
「v6 字节由这些字节构造」的前置自洽断言在，排除假阳性。

### ⑤ 三处越界增补定性——**全部合理且申报闭环**

1. **LightamerApp 装配三角（T2）**：无此件生产写腿读 nil coordinator（版本键永不落盘）、
   T3 sink 无注入目标——功能性必需非顺手改；最小半径亲读 = @State 一行 + attach 三行 +
   environment 一行，零既有行为改动。定性：front-matter 漏列，SUMMARY 偏差 § 申报，合规。
2. **DrtPersistenceTests:325（T1）**：`== 6` 字面第五触点，checker E3 名单漏计的同类机械
   修复——不修则全套 0 fail 不可达。定性：E3 同类，申报合规。
3. **SidecarMetadataV3Tests golden 家族（T3）**：LIB bundle 字节 golden（当前版本位 +
   v2→v3 diff 期望集字面 `"schemaVersion" : 6`）——同款改引 `schemaVersionCurrent`，
   golden 家族断言语义不变（diff 面仍 = 五元数据键 + 版本位）。定性：E3 同类，申报合规。

三处均在对应 commit body + SUMMARY §偏差 + DECISIONS E3 实况节三重申报；L050 教训
（grep 机检穷举替代人工枚举）已入账。

### ⑥ 测试计数对账与 minor 修复

- 实测新增 26 法：SidecarV7Tests **8** + VersionSwapTests **11**（T2 落 10 + T3 投影面
  +1）+ LIB 净 **+6**（新 7 法 − `testFreshCreateStampsUserVersionTwo...` 改名
  `...VersionThree...`）。净 +25 = 2550 − 2525 精确吻合。
- **minor（已修）**：BUNDLE-MAP 两 per-file 行过时——SidecarV7Tests 登 9 实 8（登记
  预写）、VersionSwapTests 登 10 实 11（T3 增投影面未回更）；APP 两行合计 19 不变，
  总增量对账不受影响。按本文件「行内 method 数以终态对账为准」+ M2-7-2 终值勘误先例，
  随验收 commit 修正（两行 + 增行记录注第二批勘误）。
- **observation①**：SUMMARY/GOAL-STATE 行文「SidecarV7Tests 9 法」同源偏差（实 8）——
  执行方记录不改写，本报告对账为准；总量与 bundle 行（修正后）均自洽。
- **observation②**：AC4「零重新解码」无专用断言——结构性行（installVersionChain 不触
  decode 面 + historyDidChange 走 param 重放路径）+ AC 机检栏原文只要求 VersionSwapTests
  + diff 半径，判定满足；如晨审要行为面可补 decode 请求计数探针（不阻塞）。

### 附：L051 事故处置核查

WAL checkpoint busy 根因（测试侧第二读连接 statement 停在 SQLITE_ROW 持隐式读锁 →
zombie 连接不放锁 → 强制 TRUNCATE 必败）定性准确——修复 = 迁移断言改「store.close()
后 detached 句柄读」（DefaultLookTests 形态），两处新测试（v2→v3 / 链式）注释均钉明
reader rule 亲读确认；非产品 checkpoint 纪律问题，处置合规。

## 四、判定与移交

- **判定：PASS**——AC 12 条全过（AC12 带已修 minor）；checker 四条（E1 public 缝/E2
  死锁/E3 触点/E4 泄漏）逐一实证；三处越界增补全部申报合理；红线零违例。
- 翻账（本批同 commit）：REQUIREMENTS **M2VER-01 勾选 + Delivered**（sidecar v7 + .lalb
  version_ref 双载体，commit 图面收窄注记）+ **M2VER-02/03/04 注记**（02 命令面
  Delivered/面板归 M2-8-2；03 内存态兑现注记；04 部分交付/历史行 UI 与崩溃恢复条归
  M2-8-2/P2）+ BUNDLE-MAP 第二批终值勘误 + GOAL-STATE 验收续接点。
- 下一步：M2-8-2（Versions 面板 UI + 历史行升级 + Copy Adjustments）消费本 plan 的
  coordinator/v7 面；M2VER-02/04 面板落地后翻勾。
- 未 push。验收批 commit = BUNDLE-MAP 勘误 + REQUIREMENTS 翻账 + 本报告 + GOAL-STATE。
