# M2-2-ACCEPTANCE-OMP-R2 — 图库与项目模型双路终验报告（OMP 路）

> 验收员 = OMP 独立回溯二次验收（2026-10-10，双路并发批，零共享上下文）；首验 = ZCode subagent（2026-09-29）；上一轮单路回溯 = M2-2-ACCEPTANCE-OMP.md（2026-10-09）。
> HEAD = `a18cfb82`（main）。方法 = 亲读 4×ACCEPTANCE + SUMMARY×4 + AGENTS.md M2-2 增量节，上一轮 5 抽查点提炼 6 可机检项独立重验（现状差异凡后演进致均标「后演进，不记账」）。只读验收：除本报告零写入，未跑测试（引用已记录终值），未 push。

## 结论头

**PASS / 0 error + 0 minor**（与首验、上一轮零实质分歧；分歧项仅活谱系 SHA 表述勘误，不改判定）

## 逐抽查点证据

### R2-1 — `.library` 5 触点：当时刻行号逐行一致 ✅

- `git grep -n "case .library" 15c6784b` = 恰 5 处：FilterSQL `:121/:217/:246/:290` + SmartAlbumStore `:300`，与 M2-2-1 首验重点②逐行相同（上一轮抽查 5 加深项复述成立）。
- HEAD 同 grep = 5 处同在（FilterSQL `:121/:217/:246/:290` 不动；SmartAlbumStore `:300`→`:306`，+6 行 = M2-2-3 T2 真实现臂展开，「后演进，不记账」）。

### R2-2 — F-1 事务修复态现存 + 回归测试可寻 ✅

- `ProjectFileStore.swift:444-477`：`withWriteBatch` 包 `BEGIN IMMEDIATE`/:467 → `COMMIT`/:470 → `checkpointIfNeeded`/:471，抛错 `ROLLBACK`/:474；头注 :449-450 明确标注 "M2-2-1 acceptance fix"。修复语义现存（M6-1 只读门 :457-465 为 additive 前置，「后演进，不记账」）。
- `git show af8453f7 --stat` = ProjectFileStore（27+-/6-）+ LibraryStoreTests（+42），与上一轮申报逐数一致；回归测试 `testRefcountMoveIsAtomicUnderMidStatementFailure` 在 `Tests/LightamerTests/LibraryStoreTests.swift:269` 可寻。

### R2-3 — env 唯一读点 + 默认面（现状）✅

- 全仓 `LIGHTAMER_LEGACY_LIBRARY` 命中 = 2 文件：`Library/LibraryPreferences.swift:11`（注释）+`:31`（键定义）；`UI/LightamerApp.swift:428`（注释）。Core/Tests 零命中，与上一轮一致。
- 唯一读点 `LibraryPreferences.swift:36-40`（`environment[key] == "1"` 纯函数）现存；组装点 `LightamerApp.swift` 单次求值（行号已漂移——M2-3+ 演进改行，「后演进，不记账」）。
- view body 零直读成立：ContentView/SettingsView/SidebarView 的 ProcessInfo 命中全为注释；WorkspaceHostView 4 处 = `-la_editor_probe`/`-la_film_probe` DEBUG 探针 `.arguments`（M3 演进新增，与 env 无关，「后演进，不记账」）。

### R2-4 — L013 DECIMAL TEXT + PathKind + 迁移链 ✅

- `params_hash TEXT` 冻结列（`LibrarySchema.swift:166` + DDL `:289`）+ `:27-29` "NEVER INTEGER" 纪律注释现存；`updateProjection(imageID:hasEdits:paramsHash: String?)`（`LibraryStore.swift:420-421`）String 入参面现存。
- PathKind 三态（`:209-218`，0 项目相对/1 卷相对+uuid/2 绝对+uuid）逐字节在位，与 AGENTS.md OQ-3 注记一致。
- 迁移链「未破坏 M2-2 语义」口径成立：`schemaVersion = 4`（:102；v1 M2-2 冻结）；`migrate(from:to:)` 单事务走全腿（:762-783，1→2→3→4 幂等槽）；`39c53470` diff 亲证 v1→v2 = images 尾部 append `default_look_pending` 列 + slot 首填，既有列/DDL 逐 hunk 零改动；冻结索引 `idx_images_capture(capture_date,id)`（:361）零漂移；`m2-2-era → HEAD` M2-2 收官 `c72f86da` 为 HEAD 祖先。

### R2-5 — ImportFilter 键族 + sidecar 排除 ✅

- 三键拼写现存：`library.import.mode/rememberMode/rawExtensions`（`ImportFilter.swift:233-235`）；`resolvedWhitelist` 全量替换语义（:255-264）现存；判定序 ② sidecar 硬表先于白名单（:105-109）现存；`hardcodedSidecarExclusions` 5 项拼写（`LibrarySchema.swift:250-252`）逐字在位。
- 「后演进，不记账」：`ImportCategory` 掩码 + `tiffRasterExtensions` + `library.import.categories` 一键（M4-1 批）为 additive，RAW 臂语义逐字节不变。

### R2-6 — 测试终值引用 + 文件集机检 ✅

- 出生时刻计数：`git grep -c "func test"` = 21（`ce9f49fa` ExifSearchParserTests）/ 11（`c6cd1d5f` LibraryDocumentTests）= HEAD 同值——后序 phase 未碰此二类；终值引用上一轮复跑 21/0/0 + 11/0/0（本轮未复跑，指令口径）。
- M2-2-1 活谱系 --stat：`f601e5b8`(3) / `c6cd1d5f`(2，ProjectFileStore 305 行) / `45c6c0bf`(3) / `15c6784b`(5，SmartAlbumStore +8 行) = 13 代码/测试；M2-2-3：`ce9f49fa`(Parser 416+Tests 247) / `c648ce43`(Queries 676 + SmartAlbumStore 27 行 + Tests 489) / `d03461cb`(perf.md 92 + Harness 431) = 1092/27/1167 三方精确——与上一轮申报逐数一致。

## 分歧项

1. **活谱系等价 SHA 表述勘误（不改判定）**：上一轮抽查 5 所列 `2845c1f`/`8a93cbf`/`1c803e9`/`0a7d24a`/`c07f412`/`ea648ac`/`c66484a`/`11d161b`/`3ec23b3`/`c8f585a` 在当前仓库已不可达（`git cat-file -t` 双抽亲证 fatal；再次 history-surgery 所致）。等价内容经 `f601e5b8..c72f86da` 逐 --stat 对照逐项一致（见 R2-2/R2-6），后来者按本报告 SHA 定位。
2. **上一轮 O-2 数字已过期**：schemaVersion 现 HEAD = 4（上一轮写作时 = 4，现仍 4——无变化，注：上一轮 O-2 称 "M2-5/M2-8/M2-10 各加一" 成立，现状无新增腿）。
3. 其余判定（逐 plan PASS、文件边界、性能门可信性）与上一轮完全一致，无分歧。

## 会话卫生

- 只读：除本报告外零写入；测试零复跑（引用上一轮 32 tests / 0 fail 定向终值 + 首验全套 2049/13skip/0fail）；未跑 `--all`；未 push。

OMP-VERDICT: PASS
