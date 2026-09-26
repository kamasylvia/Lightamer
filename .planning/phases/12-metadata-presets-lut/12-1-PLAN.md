---
phase: 12
plan: "12-1"
title: "元数据依赖根：sidecar v3 五字段（rating/flag/colorLabel/keywords/note，哈希隔离）+ DB v2 首次真迁移（25→34 列，幂等 ALTER + v99 拒开保留）+ MetadataService 三段写面（claimMetadataApply 新缝，thumb_state 不变）+ EXIF 轻量七列回填 + grid overlay/全域快捷键接线"
wave: 1
depends_on: []
autonomous: true
requirements: [META-01, META-02, META-03]
files_modified:
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift          # schemaVersionCurrent 2→3 + 五字段 additive（decodeIfPresent / encode 恒写）
  - LightamerCore/Sources/Session/SessionIndexSchema.swift        # schemaVersion 1→2 + imagesColumns 25→34 + migrate 函数 + apply(to:) dispatch
  - LightamerCore/Sources/Session/SessionIndexStore.swift         # claimMetadataApply 新方法 + healDirtyRows/backfillSidecarSummaries UPDATE additive 扩五列 + backfillExifMetadata 扩七列
  - LightamerCore/Sources/Session/MetadataService.swift           # 新建：三段写面唯一入口（GUI/未来 MCP-06 同源）
  - App/Sources/Lightamer/UI/SessionBrowserView.swift             # rating overlay 接数据（:139-149 壳）+ flag/色标 badge
  - App/Sources/Lightamer/UI/ContentView.swift                    # 快捷键命令宿主（0-5/X/P/⌘0-6；具体命令面按既有 commands 结构落位）
  - App/Sources/Lightamer/UI/InspectorView.swift                  # note 编辑行（最小录入位）
  - Tests/LightamerTests/SidecarMetadataV3Tests.swift             # 新建：v3 降级读/恒写 golden/哈希隔离
  - Tests/LightamerTests/SessionIndexMigrationTests.swift         # 新建：v1 fixture→v2 全套（幂等/拒开/parity）
  - Tests/LightamerTests/MetadataServiceTests.swift               # 新建：三段/万张门/crash 注入/thumb 不变
  - Tests/LightamerTests/SessionIndexStoreTests.swift             # PRAGMA VERBATIM 冻结断言 25→34 列
  - .work/12/perf.md                                              # 万张批量打分计量门数字
  - .planning/phases/12-metadata-presets-lut/12-1-SUMMARY.md
  - .planning/phases/12-metadata-presets-lut/12-1-DECISIONS.md
  - TODO.md                                                       # Phase 12 节开账 + 12-1 勾选
  - LESSONS.md                                                    # 如踩坑
---

# Plan 12-1 — 元数据依赖根（W1，全 Phase 依赖根）

> 背景：把 Phase 9 的「预留三列 + 25 列 DB」升级为元数据真身面。三条主线（RESEARCH §2 正本）：
> ① sidecar v3 additive 五字段——**五字段不进 `driftDetected` 哈希**（元数据非管线参数，改评分
> 不得触发 drift false-positive / 缩略图 stale）；② DB v2 首次真迁移——D-12-CONTEXT-1 裁决的
> Phase 9「never migrate」显式例外条款，34 列冻结（F5 全下游扫描收口）；③ `MetadataService`
> 三段写面 = GUI 与 Phase 14 MCP-06 的同源单实现，**新写 `claimMetadataApply`**（F6：复用
> `claimBatchApply` 会 stale 缩略图且 UPDATE 列集全不适用）。内部任务序刚性：sidecar v3 →
> DB v2 迁移 → Store additive → MetadataService → EXIF 回填 → UI 接线（迁移先于服务，服务
> 测试建在 v2 上）。

## read_first

1. `.planning/phases/12-metadata-presets-lut/12-RESEARCH.md` §2（sidecar v3 + DB v2 迁移规格 + F6 crash 一致性 + F7 additive 扩列）、§3.1（keywords 模型）、§7 T2/T3/T6、§8.1（任务序）
2. `.planning/phases/12-metadata-presets-lut/12-CONTEXT.md` D-12-CONTEXT-1（真身落位/列集）、D-8（服务单源/不翻 paramsHash）、验证与 GUI 红线节
3. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`：`schemaVersionCurrent = 2`（:102）、reader 容忍 >current（:94-97）、v2 layerStack additive 先例（:99-101/:219-228）、`decodeIfPresent` 模式（:334 起）、`SidecarInstanceRecord`（:252）、`@UInt64String historyHash`（:139）
4. `LightamerCore/Sources/Session/SessionIndexSchema.swift`：`schemaVersion = 1`（:31）、`imagesColumns` 25 列（:48-75）、预留三列（:69-71 注释即回填义务）、`apply(to:)` version dispatch（:145-167）、v99 拒开（:153-157）
5. `LightamerCore/Sources/Session/SessionIndexStore.swift`：`backfillSidecarSummaries`（:625，UPDATE 列集扩列位）、`backfillExifMetadata`（:755，pending 谓词 + properties dict 取值模式）、`claimBatchApply`（:916——**只读参照，不复用**：PK-seek 逐行 + 单事务形态是蓝本）、`clearBatchDirty`（:948，原样不动）、`healDirtyRows`（:970，UPDATE :1013-1022 扩列位）
6. `LightamerCore/Sources/Session/BatchSidecarWriter.swift`（段3 串行写队列复用 + `armCrashInjectionForTesting` :136 crash 注入缝）
7. `Tests/LightamerTests/Perf07MassApplyTests.swift`（万张 fixture + 计量门模式复用）
8. `App/Sources/Lightamer/UI/SessionBrowserView.swift:139-149`（rating overlay 壳 + `.rating` identifier）
9. `LESSONS.md` L009（fixture 禁 UNITEK）/L013（哈希 decimal String）/L019b（test-direct）/L020（内容级断言）
10. `AGENTS.md`（Phase 执行模型 + 暂停机制）+ `.work/GOAL-STATE.md`（Phase 12 续接点）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建（`xcodebuild build-for-testing` 先行——test-direct 前提）。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行（脚本内置），NOT 宿主进程退出态**（11-05 修好的判据，宿主退出码只作诊断打印）。Executed 0 = 判据失败（防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停（在制品已 commit、报告断点）；`auto=false` 完成当前任务后停等用户「继续」。
- **不 push**（本 Phase 全部 plan 同此）。
- **零新 SPM 依赖**（继承定案）；无 /tmp 产物入工作区；fixture 禁 UNITEK 盘（L009）。
- **T6 为 GUI 任务：需解锁控制台（Manual-Only 候补）**——无法自动化走查的部分按既有 Manual-Only 台账格式登记。
- **迁移破坏性红线**：迁移失败 = 拒开并保留原库文件（不破坏性改写）；`v99 → REFUSE` 语义保留；幂等列检查二次迁移零害。
- RESEARCH/CONTEXT 未覆盖细节（五字段 encode 字节形态已钉死除外、数值哨兵、快捷键冲突表）标注**执行期决策**入 `12-1-DECISIONS.md`，不臆造。

## Tasks

### T1 sidecar v3 五字段（哈希隔离）

- **action**
  1. `LightamerSidecar.swift`：`schemaVersionCurrent = 2 → 3`；新增顶层五字段（D-12-CONTEXT-1 拼写 verbatim）：`public var rating: Int?`（0...5，nil=未评分）、`public var flag: Int?`（0=none/1=pick/2=reject）、`public var colorLabel: Int?`（0...6 C1 七色）、`public var keywords: [String]?`（完整层级 path 数组，`|` 分隔）、`public var note: String?`。
  2. 编解码纪律（**plan 期定死，golden 锁**）：decode = `decodeIfPresent`（v2 文件降级读，缺键→nil；reader 容忍 `> 3` 契约 :94-97 **不动**）；encode = **恒写**（nil 写 `encodeNil`，不省键——与 CONTEXT「encode 恒写」裁决一致，杜绝「absent vs null」歧义）。
  3. init 签名追加带默认值参数（`rating: Int? = nil, …`）——既有调用点零改动。
  4. **哈希隔离断言**：`HistoryHash.hash(stack:decodeParamsHash:layerSnapshot:)` 不变；对既有 v2 文档升级路径写「五字段 set 前→后 historyHash/paramsHash 逐字节不变」+ sortedKeys 稳定 diff（v2→v3 升版只加键）测试。
- **证据**：`SidecarMetadataV3Tests`——v2 文件降级读五字段全 nil / v3 被 reader 容忍路径（>current 语义回归）/ encode 恒写字节 golden（含 null 形态）/ **五字段写后 historyHash+paramsHash 逐字节不变** / sortedKeys 稳定 diff。

### T2 DB v2 迁移（25→34 列，首次真迁移）

- **action**
  1. `SessionIndexSchema.swift`：`schemaVersion = 1 → 2`；`imagesColumns` 尾追加 9 条（顺序钉死）：`flag INTEGER`、`note TEXT`、`camera_make TEXT`、`camera_model TEXT`、`lens_model TEXT`、`iso INTEGER`、`focal_length REAL`、`aperture REAL`、`exposure REAL`；`createImagesTableSQL` DDL 同步 34 列（新建库直建 v2，不走 ALTER）。
  2. 迁移函数 `SessionIndexSchema.migrate(from:to:on:)`（表驱动，RESEARCH §2.2 序列 verbatim）：`BEGIN IMMEDIATE` → 读 `PRAGMA table_info(images)` 已有列集**逐列幂等防御**（已存在则跳过）→ `ALTER TABLE images ADD COLUMN …` × 9 → `UPDATE meta SET value='2' WHERE key='schemaVersion'` → `COMMIT`。
  3. `apply(to:)` dispatch 改造（:145-167 模式上扩展）：absent → 建 v2 DDL + stamp 2；`1` → migrate to 2；`2` → ok；`>2` → REFUSE（:153-157 语义保留）。
  4. **不建新索引**（RESEARCH §2.2 实测 LIKE 全扫 <1ms，写放大不值）——文档化决策入 DECISIONS。
  5. `SessionIndexStoreTests` 的 `PRAGMA table_info` VERBATIM 冻结断言更新 25→34（frozen-spelling 既有资产改期望值，与迁移同批）。
- **证据**：`SessionIndexMigrationTests`——手写 v1 fixture 库（25 列 DDL + 边界值行）→ open → 34 列/meta=2/旧行逐列字节不变/新列 NULL/二次打开幂等（列已存在跳过路径）/v99 REFUSE 保留/迁移失败拒开原库文件未改写/删库重建 parity 扩 v2 全列。

### T3 SessionIndexStore additive（claimMetadataApply + heal/summary 扩列）

- **action**
  1. 新方法 `claimMetadataApply(claims:)`（RESEARCH §2.4 SQL verbatim，形态照 `claimBatchApply` :916 的 PK-seek + 单事务蓝本但**列集全新**）：
     ```sql
     UPDATE images SET rating=?, color_label=?, keywords=?, flag=?, note=?,
                        sidecar_mtime=?, dirty=1
     WHERE path=? AND orphan_sidecar=0
     ```
     **不动 thumb_state / params_hash / has_edits / layer 列**。mtime 值来源（段2 预测 vs 段3 写后实测回写）= 执行期决策入 DECISIONS；不变量由 T4 crash 注入测试钉死（crash 窗口 reopen 后 `healDirtyRows` 旧值回填 + dirty=0 + 状态一致）。
  2. `healDirtyRows`（:970）UPDATE（:1013-1022）additive 扩五列：rating/color_label/keywords/flag/note 从磁盘 sidecar 文档回填（F7——函数签名不变；metadata 值直接读 `document.rating` 等五字段，`keywords` 存 `joined(separator: "|")`）。
  3. `backfillSidecarSummaries`（:625）UPDATE 同批 additive 扩五列（同一 F7 义务；drift 重读路径不丢评分列）。
  4. `clearBatchDirty`（:948）原样不动；`BatchApplyClaim` 类型不动（`claimMetadataApply` 自带 claim 结构）。
- **证据**：`MetadataServiceTests` 前置段——heal 回填五列值精确断言（sidecar 文档 → 行逐值）/ backfillSidecarSummaries 扩列后 drift 重读保评分 / claim SQL 列集断言（thumb_state 不在 SET 内——查表比对）。

### T4 MetadataService 三段写面（万张门 + crash 注入）

- **action**
  1. `MetadataService.swift`（新建，Core/Session——Core 级可单测红线；GUI 与 Phase 14 MCP-06 同源唯一入口）：API = `setRating(_:relPaths:)` / `setFlag(_:relPaths:)`（X toggle 语义在调用方）/ `setColorLabel(_:relPaths:)` / `setKeywords(_:relPaths:)`（整组替换，MCP-09 set_keywords 上游语义）/ `appendKeywords(_:relPaths:)`（去重追加，META-03 批量编辑）/ `appendNote(_:relPaths:)`；关键词录入校验禁 `|`（typed error，RESEARCH §3.1）。
  2. 三段（9-4 同构 + F6 精细语义）：段1 = 读磁盘 sidecar → 内存改五字段（**非 history 项，不进栈**）→ 段2 = `claimMetadataApply` 单事务（万张 PK-seek 形态）→ 段3 = `BatchSidecarWriter` 串行队列落盘 + 逐图 `clearBatchDirty`。
  3. `keywords` 列物化 = `keywords.joined(separator: "|")`（既有预留列，零 ALTER）；`keywords == nil` → 列 NULL；空数组 → 空串（过滤面语义区分「未打标」vs「已清空」，入 DECISIONS）。
  4. 万张计量门：PERF-07 fixture 复用（`Perf07MassApplyTests` 模式），10k `setRating` 段1+段2 ≤5s；断言批量后 `thumb_state`/`params_hash` **逐行不变**（D-8 性能陷阱红线：评分不触发缩略图再生）。
  5. crash 注入：段3 前中断（`armCrashInjectionForTesting` 模式）→ reopen → `healDirtyRows` → 旧值回填 + dirty=0（状态一致、真身诚实）。
- **证据**：`MetadataServiceTests` 全绿 + 万张门数字（段1/段2 分列）入 `.work/12/perf.md` + `thumb_state` 逐行不变断言 + crash 注入三态漂移零发生。

### T5 EXIF 轻量七列回填

- **action**
  1. `backfillExifMetadata`（:755）additive：properties dict 取值扩七列——`kCGImagePropertyTIFFDictionary`（`Make`→camera_make / `Model`→camera_model）+ `kCGImagePropertyExifDictionary`（`LensModel`→lens_model / `ISOSpeedRatings`→iso / `FocalLength`→focal_length / `FNumber`→aperture / `ExposureTime`→exposure）。
  2. **pending 谓词 plan 期定死**（RESEARCH §2.5 三案择一落地）：谓词 = `camera_make IS NULL`（单锚）；处理时七列**同批 UPDATE**；无值文本列写空串哨兵 `''`（已尝试标记），无值数值列保持 NULL（SQLite 三值逻辑下过滤谓词自然排除，文档化）——既有 v1 行（orientation 已填）被新锚一次性收编，无 EXIF 图不反复重扫。
  3. QoS：后台、不阻塞首帧（既有调用时序不动）。
- **证据**：`SessionIndexMigrationTests` 扩段——v1 行（orientation 已填）升级后单轮收编 / 无 EXIF 图恰被扫一次（哨兵后不再入 pending）/ 有 EXIF 图七列值精确断言（L020 内容级）。

### T6 UI 接线：overlay 数据 + 全域快捷键 + note 行（GUI，需解锁控制台（Manual-Only 候补））

- **action**
  1. `SessionBrowserView.swift` rating overlay（:139-149 壳）接 `MetadataService` 数据面：实星填充 + colorLabel 色点 + flag badge（pick/reject 徽标）；identifier `.rating` 既有锚不动（AX 四件套）。
  2. 全域快捷键（D-8 三态：grid 焦点行 / culling 双格选中格 / 单图编辑器当前图）：`0-5` 星级、`X` flag-reject toggle、`P` flag-pick toggle、`⌘0-6` 色标（0=清除）——命令宿主按 `LightamerApp.swift`/`ContentView.swift` 既有 commands/keyboardShortcut 结构落位；与既有快捷键冲突表核对后入 DECISIONS。全部路由 `MetadataService`（多选批量走同一入口）。
  3. note 最小录入位：`InspectorView.swift` 既有信息面板新增 note 行（单图编辑）+ 多选「追加备注」菜单项（`appendNote`）。
  4. zh catalog 同批（L025：新键语言标签跟全库 zh 约定）。
- **证据**：GUI 走查记录（三态快捷键打分/flag/色标即时可见 + overlay 实星 + note 持久化重开保持）；无法自动化项登记 Manual-Only 台账行；zh 首屏 smoke。

### T7 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1260/6skip/0fail** + 新增，0 fail）；TODO.md 开 Phase 12 节 + 12-1 勾选；`12-1-SUMMARY.md`（任务表/commit 表/证据/万张门数字）；`12-1-DECISIONS.md`（mtime 来源、keywords 空数组语义、EXIF 谓词锚定、快捷键冲突表、encode 恒写字节形态复核）；新教训候选评估入 LESSONS。
- **证据**：测试计数（1260 → N，0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| sidecar v3 | 降级读/恒写 golden/哈希隔离全绿 | `Scripts/test-direct.sh 'SidecarMetadataV3Tests'` |
| DB 迁移 | v1 fixture→v2 全套 + 冻结断言 34 列 | `Scripts/test-direct.sh 'SessionIndexMigrationTests'` + `Scripts/test-direct.sh 'SessionIndexStoreTests'` |
| 服务三段 | 万张 ≤5s + thumb/params 逐行不变 + crash 注入 | `Scripts/test-direct.sh 'MetadataServiceTests'` |
| EXIF 回填 | 七列精确值 + 单次收编 | `Scripts/test-direct.sh 'SessionIndexMigrationTests'`（EXIF 段） |
| GUI 接线 | 三态快捷键 + overlay 实星 + note 走查 | 手动走查记录 + Manual-Only 登记 |
| 回归 | 全 suite 0 fail（基线 1260+新增） | `Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] sidecar v3：五字段 additive（decodeIfPresent + encode 恒写含 null，golden 锁）；init 默认参数零调用点改动；**五字段写后 historyHash/paramsHash 逐字节不变**；v2 降级读 + `>3` 容忍
- [ ] DB v2：34 列冻结（列序钉死）+ 幂等迁移 + v99 拒开保留 + 迁移失败不破坏原库 + 删库重建 parity 扩 v2 全列 + `PRAGMA table_info` VERBATIM 断言更新；不建新索引（文档化）
- [ ] `claimMetadataApply` 新缝（不复用 `claimBatchApply`）：不动 thumb_state/params_hash；`healDirtyRows`/`backfillSidecarSummaries` additive 扩五列（签名不变）；crash 窗口三态漂移零发生（注入测试）
- [ ] `MetadataService` 唯一写入口（GUI/未来 MCP 同源）；`|` 录入 typed 拒绝；万张 setRating 段1+段2 ≤5s 入 perf.md + `thumb_state`/`params_hash` 逐行不变断言
- [ ] EXIF 七列回填：单锚谓词防重扫（plan 定死形态）+ 无 EXIF 单次哨兵 + 值精确断言
- [ ] GUI：overlay 实星/色点/flag badge + 三态快捷键（0-5/X/P/⌘0-6）+ note 录入位 + zh catalog；Manual-Only 未尽项登记
- [ ] 全 suite 0 fail；每任务独立提交 + 边界查 config 开关；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS 落盘
