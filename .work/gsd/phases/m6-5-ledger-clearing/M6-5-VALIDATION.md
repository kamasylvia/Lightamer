---
phase: M6-5
slug: ledger-clearing
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-16
---

# Phase M6-5 — Validation（挂账清算批：40 项盘点逐项闭合 + 六清偿任务机检在案的闭环签核）

> 体例对齐 `phases/m6-4-gallery-stacks/M6-4-VALIDATION.md`（正本链上溯
> `phases/m2-11-performance/M2-11-VALIDATION.md`）。**双重验收
> （`dual_acceptance = true`）单 plan 双路全部落终态后成文**：M6-5-01 双路
> zcode 独立验收 **PASS / 0 error + 1 minor open（同源 I-1 假绿数字残留，
> 本批落勘误正本）零实质分歧**（第一路 3 观察项 + 第二路位点订正 + N-1/N-2
> 两新观察，正本 = `M6-5-01-ACCEPTANCE.md` / `M6-5-01-ACCEPTANCE-2ND.md`，
> 两份随本批入库）。omp 制度路**配额阻塞**由**第二支零共享上下文 zcode
> 独立验收眼替代**（M6-2/M6-3/M6-4 同款登记，晨审可裁）。执行方 T9 +
> 第一路 + 第二路**三路亲跑全套同值 3848/24/0**（2099s/2087s/2096s，exit 0
> + 0 MEMFAIL + 七 bundle 全 8G 门内）。charter 验收形态（ROADMAP M6-5 行）
> = **挂账单一清单逐项闭合或转 V2 挂账留痕 ✓**——40 项 + rider 终局对表
> （SUMMARY §五）全闭合：**清偿 6 任务（全部亲测机检在案）/ 转 V2 9 项
> （`9bdeb467` §七登记）/ Manual-Only 11 分类项 → 19 汇编行 /
> 销账 7（证据链维持）/ 留置 5（归他站在案）**；孤儿复扫三路独立零命中
> （T1 根治终证，M4-1 挂账 #6 延续三代就此终局）。**SC 数字对账基线 =
> 全套 `--all` 终验 `TOTAL|3848/24/0|` 三路独立亲跑同值**；对账链
> **3841（M6-4 实测）+ 2（M6-4 修批）+ 5（本批 T2 +4 / T4 +1）= 3848
> 精确**，即 **M6-4 修批后推算 3843 + 本批 5 = 3848 实测核销**（M6-4
> VALIDATION 在册的「下一 phase 验收全套轮以 3843 为预期中心确认」义务
> 就此履行，对账链闭合）；段级 skip 和 1+3+4+4+4+4+4 = 24 = TOTAL 24
> 机械一致；增量分账 Sessions 280→284（T2）/ Export 378→379（T4），其余
> 五 bundle 逐值零漂移。执行链 `c749ee00..7c0d2bbb`（8 commits，T1-T9）；
> 执行期事故 I-1（陈旧二进制假绿——build-for-testing 前置漏步）实质处置
> 成立，申报残留由本 VALIDATION §minor-1 落勘误正本收口。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest。**本批 +5 法全 additive**（T2 SessionBatchApplierTests 13→17〔12 字段正测 / pristine 负测 / rating=3 逐值保真 + typed-null / 层级 keywords 逐元素〕+ T4 ExportGainMapTests 25→26〔非均匀增益 k=1/k=2 × 非对称 base 128/250 四重方向断言——①GainMapMin/Max ≈1.0/2.0 取向无关锚 ±0.4 ②top-down 带均值 <64/>192 ③带差 >128 ④锚映射语义增益 ±0.45；down-mirror 反置面 ①..④ 全数触红〕）；T1 改法不增数（RasterEditFaceTests restore+undo 双写腿 `tempFixtureCopy` 化 + `loadRaster(at:)` 孪生）；`tuist generate` 未需（零新测试文件，Project.swift 全零 diff） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/crash 签名/no-total-line 机检全挂靠；**I-1 教训入册：脚本不含构建步，命令序列 = `xcodebuild build-for-testing` → `test-direct.sh`**） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3848 tests / 24 skip / 0 fail（实测，三路独立亲跑同值：执行方 T9 2099s / 第一路 2087s / 第二路 2096s，exit 0）**；七 bundle 逐行（第一路）：IOP **686/1/0**〔peak 7676MB〕/ IOPParity **460/3/0**〔7004MB〕/ Layers **494/4/0**〔1161MB〕/ Library **729/4/0**〔621MB〕/ Sessions **284/4/0**〔1628MB〕/ Export **379/4/0**〔6432MB〕/ App **816/4/0**〔2832MB〕——peakRSS 全 <8G 运行门（最高 94% 贴线族在 ±3% 方差带），零 MEMFAIL 零 crash；L055 双保险三路亲证 |
| **基线演变** | 3841（M6-4 实测）→ 修批 +2 = 3843（M6-4 推算，带 3840..3844）→ 本批 +5（T2 +4 / T4 +1）= **3848 实测**；对账链 3841+2+5 = 3848 精确（**3843 推算由本批实测核销**）；异常形态（ΔN=0）未出现 |
| **SC 数字面** | Sessions 280→**284**（T2 +4）/ Export 378→**379**（T4 +1）；IOP/IOPParity/Layers/Library/App 五段逐值零漂移（三路互证）；BUNDLE-MAP 零新行（零新测试文件） |
| **在案发现（本 phase 事件）** | **零 error 级发现**（双路全 0E）；**minor-1（两路同源）** = I-1 事故实质处置成立但「假绿未入任何 commit」申报被 `bd81f859` commit message Verified 行证伪（13/0/0 = 陈旧首轮数字）+ DECISIONS :89「9 旧」arithmetic 残留（真旧集 13；**位点订正：全仓仅 :89 一处**——第一路「两处」为计数滑差，:82「Sessions 13/0/0」是事故经过的诚实记录应保留）——**勘误正本 = 本 VALIDATION §minor-1 节，本批落账**；观察项分账 = 挂账单一清单六项（§挂账单一清单）+ 登记级（§特殊事项 §5） |
| **GUI 证据** | 本批零新 GUI 面（清算批）；**Manual-Only 19 行汇编交付** = `.work/gui-acceptance/m6-5/MANIFEST.md`（18 GUI 行 + 1 perf 行 P1 bake，逐行来源指针 + 前置供件 + 预期观测；「本批不执行」头注 + L057-B 纪律注记在册；gitignored 本地证据，L073 口径）——移交下一 GUI 批（挂账 ④），不阻断收口 |
| **zh 对账** | T6 三活体键变体尾块纯插入（xcstrings 51+/0-，en+zh 值与既有裸键同文）；zh-audit `--self-test` PASS（红绿双例非永真）+ `--check` PASS 三路独立复跑（**1682 source / 1926 catalog / 30 interp 键全 variant-PRESENT**）；fresh `--report` 与 evidence transcript 逐字节一致；UserDefaults **全 phase 零新增** |

---

## 六清偿任务 SC 生效值对照（`M6-5-CONTEXT.md` §1 分类裁定 → `M6-5-01-PLAN.md` T1-T9 → 落点终态）

| # | 生效值（CONTEXT §1/§3 裁定） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **T1 孤儿 fixture 根治**（A1+B2+C3 三源同条；M4-1 挂账 #6 终局）：真写腿 = `RasterEditFaceTests.testRestoreWinsOverDerive` repo 路径驱动 + undo 法 post-test debounce 迟到写（E-1 归因勘误：M5-1「defer 输给 write-behind」错位）；修法 = 双法 `tempFixtureCopy`（UUID tempDirectory，DepthMaskEditingTests verbatim 同款）+ `loadRaster(at:)` 孪生 + repo 侧防御清扫 | T1 `c749ee00` | **Delivered**：源读全文件亲核（helper + 生命周期 + 头注 #6 终局注记含 E-1 归因勘误）；全 Tests 域写腿原语扫 = 仅此两法持写腿；**孤儿复扫三路独立零命中**（执行方 T9 + 双路验收轮毕 `find Tests/Fixtures -name "*.lra"` 零命中 + Tests/Fixtures 零 untracked——「跑前删跑后复活」形态根治终证）；M5-1 误宣告「收口」被本件双证证伪后真正终局 |
| 2 | **T2 12 字段携带**（C2 终局；E-2 扩面）：既有档臂七 additive（`provenance`/`rawOverrides`/`displayTransform`/`versions`/`activeVersionID`/`aiProvenance`/`filmRecord`）+ 五元数据（`rating`/`flag`/`colorLabel`/`keywords`/`note`——原挂账清单漏列，MetadataService 五写点）全捕获 + 构造点 12 参；process 分支条件盖章纪律零触（禁 `?? .current` 维持）；pristine 臂缺省 nil 零漂移 | T2 `bd81f859` | **Delivered**：`CarriedDocumentState` 12 字段捕获 + 构造点 12 参亲核；**独立对表 `LightamerSidecar` 全字段面 = 9 结构性 + 12 optional + process，无第十三字段**（两路独立复证 CHECKER 2.2）；四新法亲读（正测走盘上 decode 真路径）；字节面 = pristine 臂逐字段同旧形 + Sidecar 字节 golden 族（13 文件）运行时全绿；D-2 typed-nil 断言 = 线格式事实诚实形（五元数据 encode 恒写 null 源码亲证）；M6-2 VALIDATION 挂账 #2 对表补记纯追加；Sessions 280→284 亲证 |
| 3 | **T3 头注 19→20**（A13；M-3 扩面）：`McpServerController` 两处「19-tool」→ 20 + 伴文 5→6 editing 算术；零行为面 | T3 `71dbd371` | **Delivered**：`grep -rn "19-tool"` 全仓零命中、`20-tool` 计 2、`5 editing` 零命中、`6 editing` 在位（两路独立亲跑）；diff 纯注释；两测试文件同族注释顺带 = red_lines 明文豁免形 |
| 4 | **T4 行序方向性断言**（D2 终局）：`.oriented(.downMirrored)` 垂直 flip 现有测试面零覆盖 → 补非均匀 HDR 面 × 非对称 base 方向性断言（断言形式 plan 明文授权执行期择稳） | T4 `76729922` | **Delivered**：单向方向断言四重（D-3）——aux 读回 top-down 取向首跑即绿实测定格，反置面全数触红证**单向性真单向**；M-2 计数订正亲核（25→26 = CONTEXT「24 法」漂移属实）；Export 378→379 亲证 |
| 5 | **T5 门③载体分叉 API 注记**（D4 终局）：validate 门③查 `variant.drtOutput.peakLuminance` vs render 侧读 `drtTail.record.peakLuminance`——直接构造 Request 可组出超纲产物（全 UI 路不可达）；API-consumer 契约注记 | T5 `c651bb51` | **Delivered**：diff = 20 行纯注释（ExportRecipe 门③ + ExportRenderer headroom 取值点），两载体分叉契约 + enqueueExportM2 联动引证在文；零行为 |
| 6 | **T6 格式键插值目录分诊门**（F1/E-3 = zh-audit V16 断言 5 + 三活体键清偿）：`String(localized: "K \(…)"` 合法惯例定性（禁形作废）→ 门语义 = 目录占位符变体 PRESENT/ABSENT 分诊；三活体键（`edr_headroom_label`/`settings_displays_overridden`/`softproof_active_label`，裸键值承载 `%@` 格式串）补变体 | T6 `0ebdd3c1` | **Delivered**：V16 提取器（同行 regex + form-1c 续行延拓）+ 断言 5（`K %`-前缀变体必在）+ self-test 红绿双例非永真（BAD fixture 真实驱动红例，两路独立读码证伪「永真」疑点）；分诊 = 30 键 3 ABSENT → 30 全 PRESENT；`--check` PASS 三路复跑（1682/1926/30）；xcstrings 51+/0- 尾块纯插入；调用点零改；**门覆盖限定见挂账 ③（N-2）** |
| — | **T7/T8 清算面** | T7（不入 git，L073）/ T8 `9bdeb467` | **Delivered**：T7 Manual-Only 19 行汇编逐行可对 CONTEXT §6 明细（plan「~17 行」约数内，偏差 #6 ACCEPT）；T8 V2 九项各带一级标题 + 来源锚 + 触发条件 + 规模 + 一句话（C1 触发条款与 M6-2 VALIDATION :104 同文 grep 双侧 1:1 + 四件套镜像含②完整形；「登记 ≠ 立项」头注在册） |
| — | **零回归门** | 双路机检 | **Delivered**：`LightamerIOP/` 全域 / 全部 `*.metal` / `LightamerSidecar.swift` / `Pipe/History/` + `PipeCacheKey.swift` / V50Order / MCP 快照族 / Export 六格式矩阵三文件 / `Project.swift` 全零 diff（零新 SPM + 零新测试文件）；runModal = 0；`String.LocalizationValue("` 插值禁形 = 0；UserDefaults 零新键；xcstrings 仅 T6 三键 51+/0-；五 bundle 逐值零漂移 |
| — | **数字门** | 三路终验批 | **Delivered**：**3848/24/0** 三路独立亲跑同值 = 3841+2+5 精确；skip 段和 = TOTAL 机械一致；M6-4 推算 3843 核销声明见挂账 ⑥ |

## 40 项终局对表（charter 验收形态「挂账单一清单逐项闭合或转 V2 挂账留痕」）

> 正本 = `M6-5-01-SUMMARY.md` §五逐项表（40 项 + rider，逐项证据指针在册）；
> 两路独立对账闭合（第一路全核 + 第二路错开抽样：V2 九项全抽 + Manual-Only
> 19 行全对）。分类合计 = **清偿 6 任务（8 条：A1+B2+C3 同条 → T1）+
> 转 V2 9 + Manual-Only 11 分类项 → 19 汇编行 + 销账 7 + 留置 5 = 40 逐项
> 闭合，无孤儿**。销账 7 项证据链全核（A2 `7bc6365f` + 五轮全套绿 / A5 五轮
> + 本批第六轮 / A7 `5ff6ff48` NSLock holder / B4 `908526fe` + M6-1 原裁 /
> C4 M6-2-VALIDATION :127 留痕 / D3 M6-3-VALIDATION「DPI 登记零动作」/
> E6 核查义务已履行）；留置 5 项零动作申报与现状一致（A9 L057-B / A12
> 维持原判 / A16 AGENTS ±3% 口径 / A19 perf.md / A20 范围外指针）。

## 验收记录（dual_acceptance 链：执行方 + 双路独立验收）

| 路 | 结论 | 证据要点 | 分歧与处置 |
|---|---|---|---|
| **执行方 T9 收口轮**（2026-10-16 夜，夜间授权链） | 九任务全交付；全套 **3848/24/0**（2099s）exit 0 + 0 MEMFAIL | T9 全套确认轮（批准制 + 8G 门监视 7 次采样）+ 逐任务定向轮 + 轮毕孤儿复扫零命中；transcript = `evidence/t9-all-run.log`；对账 = 3841+2+5 精确 | I-1 事故自曝 + 复跑消除（DECISIONS §3）；「假绿未入任何 commit」申报含 minor-1 残留（下两路证伪） |
| **第一路 zcode 独立验收**（2026-10-15/16，零共享上下文） | **PASS / 0 error + 1 minor（I-1 残留）+ 3 观察项** | 全套自建亲跑 **3848/24/0**（2087s）与执行方逐值一致 + 六清偿项亲测全过 + 40 项终局表全核 + 八 commit 逐 hunk 亲核（边界零越界）+ 红线机检亲跑 + zh-audit 独立复跑 + I-1 链条亲证（`bd81f859` message 13/0/0 出自陈旧首轮——commit 时刻 03:56:42 早于重建 04:04） | **minor-1 发现路**：修复建议 = DECISIONS 订正 + 勘误正本落 VALIDATION（「两处 9 旧」计数滑差由第二路订正）；O-1 TODO 妆饰滑差旧计数并存 / O-2 `c749ee00` message 数字 provenance 注记 / O-3 资源时效（T9 轮 Localizable.strings 为 T6 插键前产物，零影响——无测试消费编译目录） |
| **第二路 zcode 独立眼**（零共享上下文；omp 制度位替代） | **PASS / 0 error + 1 minor（minor-1 维持 + 位点订正）+ N-1/N-2 两新观察** | 全套自跑 **3848/24/0**（2096s）逐位一致 + 五面独立审计（T1/T2 修法面数据保真视角 + T6 V16 提取器状态机独立读码〔两形态盲区定性〕+ 40 项错开抽样 + I-1 链条位点全数 + 偏差六项独立复核全 ACCEPT）+ D-2/D-3 源码级亲证 + 字节面抽验 | **位点订正**：DECISIONS「9 旧」残留**仅 :89 一处**（第一路「两处」为其引文同行的计数滑差）；**:82「Sessions 13/0/0」= 事故经过诚实记录应保留**；无第三处。**N-1**：`McpLauncherPanelView.swift` :225/:242/:246 三处 `Text("…\(pid/writes/code)")` 插值裸键 zh 回退活体（`mcp_launcher_status_running/done_writes/exit_code`——14-4 时代 `3578a415` 既有，非本批引入非 40 项盘点范围）→ 挂账 ②；**N-2**：V16 门只覆盖 `String(localized:` 同行 + 1c 续行两形态，Text 族 + `String(` 跨行族不设防（LCR 三跨行键变体恰在册 = 潜伏非活体）→ 挂账 ③；**与第一路零实质分歧**（位点计数差一档非分歧） |
| **omp 制度路** | **配额阻塞登记（非 FAIL），未执行** | 制度位由第二支零共享上下文 zcode 独立眼替代（M6-2/M6-3/M6-4 同款；登记晨审可裁） | 不重试（lane_retry 语义）；双 zcode 独立眼意图已满足 |

三路终态：**零 error、零实质分歧**；minor-1 同源残留由本闭环批落勘误正本
收口（见下节）；三路独立全套复跑同值互证（3848/24/0 逐值一致）。

## Per-Plan Map

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M6-5-01（挂账清算批：40 项盘点 → 六清偿 + 四态分流） | T1 孤儿 fixture 根治（A1/B2/C3 三源同条终局）；T2 batch apply 12 字段携带（C2 终局 + M6-2 对表补记）；T3 头注 19→20（A13）；T4 行序方向断言（D2 终局）；T5 门③载体分叉注记（D4 终局）；T6 zh-audit V16 断言 5 + 三活体键清偿（F1 终局）；T7 Manual-Only 19 行汇编（local-only）；T8 V2 九项登记；T9 全套确认轮 + 收口 | 执行链 `c749ee00..7c0d2bbb`（8 commits：T1-T6 + T8 + T9）；T7 不入 git（L073 口径）；未 push | 双路 zcode 独立验收 PASS / 0 error + 1 minor open（同源 I-1 残留——勘误正本本批落账）+ 执行方三路全套同值 3848/24/0；零实质分歧 |

零红线域终态（`c749ee00..7c0d2bbb` 全程，双路亲跑）：`LightamerIOP/` 全域 =
**0 diff** / 全部 `*.metal` = **0 diff**（零新 kernel 传承兑现）/
`LightamerSidecar.swift` = **0 diff**（`.lra` 格式零字节变更）/ `Pipe/History/`
+ `PipeCacheKey.swift` + V50Order = **0 diff** / MCP 快照族 = 0 diff（T3 触两
测试文件注释 = red_lines 明文豁免形）/ Export 六格式矩阵三文件 = 0 diff /
`Project.swift` 全零 diff（零新 SPM + 零新测试文件）/ UserDefaults = **0 新增**
/ runModal = 0 / LocalizationValue 插值禁形 = 0 / xcstrings = 51+/0- 恰 T6
三键尾块纯插入。M6-5 零源码生产行为变更（六清偿 = test-only ×3 + 纯注释 ×2
+ 机检/键目录 ×1 + 测试修法 ×1——清算批性质决定零生产面）。

---

## 挂账单一清单（M6-5 单一移交清单，六项）

1. **minor-1 勘误正本（本批落账，闭环项非移交项）**：I-1 事故「首轮假绿
   未入任何 commit」申报被证伪——`bd81f859`（T2）commit message Verified
   行残留陈旧首轮数字 `13/0/0 (9 existing … + 4 new)`（真旧集 13、fresh
   总数 17，拆解两头皆错）；DECISIONS :89「Sessions 17/0/0（9 旧+4 新）」
   同源 arithmetic 残留。**位点终局（第二路全数）= 残留仅 :89 一处**
   （:82「Sessions 13/0/0」为事故经过诚实记录保留；AGENTS/TODO/GOAL-STATE/
   evidence 零残留）。**处置 = 本批 DECISIONS :89 原位订正「13 旧」+ 污染
   面评估句勘误；`bd81f859` message 不可变不回写**（8-commit 链 rebase
   重写代价与收益倒挂；账面订正是对衡——**先例引 M6-3**：minor-1 账面
   滑差由闭环批原位改数清偿、commit 历史零重写），**以本节为勘误正本**。
   实质影响面 = 零（假绿未污染任何申报终值；三路 3848 亲跑同值；定向轮
   数字以复跑轮为准）。
2. **N-1 McpLauncherPanelView 三处插值裸键 → 下一清算批候选**：
   `McpLauncherPanelView.swift:225/:242/:246` 三处 `Text("mcp_launcher_
   status_running \(pid)")` / `Text("mcp_launcher_done_writes \(writes)")` /
   `Text("mcp_launcher_exit_code \(code)")`——LocalizedStringKey 插值运行时
   查表键 = `K %lld` 变体，目录与编译产物只有裸键（值即格式串）→ zh 运行
   时回退裸键观感（M2-9 F-2 家族活体）；同族正面样本 `settings_catalogs_
   rebuild_progress %lld %lld` 在册恰证惯例是登变体。**批前既有溯源 =
   14-4 时代 `3578a415` 调用点、键在 `0ebdd3c1^` 已在册**——非本批引入、
   非 40 项盘点范围。清偿路线 = 三键补 `%lld` 变体（S，T6 同款尾块纯插入）。
3. **N-2 zh-audit V16 门覆盖限定（限定语本批落）+ 门扩展列 V17 候选**：
   V16 断言 5 只覆盖 `String(localized:` 同行 + form-1c 续行两形态；
   **SwiftUI `Text("K \(x)")` 族（树内 11 处，3 处真 ABSENT 活体 = 挂账 ②）
   与 `String(` 跨行族（树内 3 处，变体恰在册 = 潜伏非活体）不设防**。
   红线引用句已加限定语（AGENTS「M6-5 架构增量」节同步）；门扩展（Text 族
   + `String(` 跨行族提取）= **V17 候选**（机检硬化批顺带评估；KEY_SHAPE
   小写偏置维持观察口径）。
4. **Manual-Only 19 行汇编 → 下一 GUI 批**：`.work/gui-acceptance/m6-5/
   MANIFEST.md`（18 GUI 行 + 1 perf 行 P1 bake）——M5-1..M6-4 六份既有
   MANIFEST human rows 并集 + A6/A8/A10 观察行 + E3 补录义务行 + M4-3
   rider；前置供件含自然样张 / 真无人像照片（素场幻觉实证在册）/ 同视点
   扫幅样张 / layer B 资产引导下载 / HDR 屏与跨生态设备；执行 = 用户/
   orchestrator 安排的 GUI 批（omp computer-use 或人工走查），证据回填
   各来源目录。
5. **V2 九项（V2-PROPOSAL §七，`9bdeb467`）+ 留置 5 项指针**：V2 = #1
   TRACK-MULTIREF / #2 RELEASE-DIRECT-INJECT / #3 PANO-V2（五件）/
   #4 SESSION-LEGACY-READONLY / #5 PROCESS-WIRING（触发条件档，首个真实
   iop 语义 bump 批四件同批）/ #6 ULTRAHDR-EXIF / #7 STACKS-SEMANTICS /
   #8 SAM-COREML（用户裁立项另开独立 phase）/ #9 PATCH-LIVEPLANE——
   **登记 ≠ 立项，终裁在用户**。留置 5 项 = A9（L057-B 专项行）/ A12
   （lut3d add 行维持 M5-1 原判）/ A16（贴线族 RSS ±3% 口径，AGENTS 在案）/
   A19（pano perf freed-but-resident 爬升，perf.md 在案）/ A20（全史瘦身
   手术第二次触发 = 主会话专属，范围外指针）。
6. **M6-4 推算值核销声明（对账链闭合）**：M6-4 VALIDATION 在册「修批后
   推算 3843/24/0（带 3840..3844），下一 phase 验收全套轮以 3843 为预期
   中心确认」——本批全套实测 **3848 = 3843（推算）+ 5（T2 +4 / T4 +1）=
   3841（实测）+ 2（M6-4 修批）+ 5（本批）双式精确命中**，3843 推算值
   就此核销；M6-4 修批 `b49215bb` 后未复跑的悬置义务履行完毕，对账链
   **3759+56+2+24+2〔→3843〕+5 = 3848 全程闭合**。后续 phase 对账基线 =
   **3848 实测**（推算/实测并行申报期结束）。

另有**登记级观察**不占挂账（双路在案）：O-1 TODO 规划批段 R-2 妆饰滑差旧
计数（「销账 6/留置 6」）与终局口径（7/5）并存——逐项表为正本，带日期历史
行不改写（本条即登记）；O-2 `c749ee00` message Verified 行数字出自陈旧首轮
（值恰同 fresh，provenance 注记级）；O-3 执行方 T9 轮 app-bundle
Localizable.strings 为 T6 插键前构建产物（零影响——无测试消费编译目录，
双路新鲜构建已消除该缝）。

**批内已清偿**不占移交：40 项盘点的清偿 6 任务 + I-1 实质处置 + E-1 归因
勘误落位 + M-2 计数订正 + D-5 amend 自纠 + LESSONS 候选 I-1 条目（文本在
DECISIONS §3，随本批入 LESSONS 义务移交 maintenance 面）。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。charter 验收形态（挂账单一清单逐项
  闭合或转 V2 挂账留痕）+ 六清偿任务每条均有 ≥1 机器锚（T1 全套轮毕孤儿
  复扫零命中三路独立亲跑 / T2 四新法 + Sidecar 全字段面对表 + 字节 golden
  族 / T3 grep 零命中 / T4 四重方向断言反置触红 / T5 纯注释 diff 零行为 /
  T6 `--self-test` + `--check` 三路复跑 30 键全 PRESENT）+ ≥1 实证背书
  （**三路独立全套亲跑同值 3848/24/0** + 对账链 3841+2+5 双式精确 + 段级
  skip 和机械一致 + 增量分账 Sessions/Export 亲数一致 + 八 commit 逐 hunk
  双路亲核边界零越界 + zh-audit fresh report 与 transcript 逐字节一致）。
- 采样密度：40 项终局对表双路独立闭合（第一路全核 + 第二路错开抽样 V2
  全抽 + Manual-Only 全对）+ 偏差六项双路独立复核全 ACCEPT + I-1 链条
  位点全数（「有无第三处」任务书级拷问 = 无）+ 红线机检族双路亲跑。「无
  证据 ✅」零项。
- 数字对账：三路同值互证（执行方 2099s / 第一路 2087s / 第二路 2096s，
  逐 bundle 计数逐值一致 + peakRSS 全门内）+ 对账链五段精确 + M6-4 推算
  3843 核销双式命中——**实测与推算并行申报期就此结束，单一基线 3848**。

## 特殊事项入册（phase 级事件台账）

1. **I-1 陈旧二进制假绿事故（执行批，LESSONS 候选正本 = DECISIONS §3）**：
   `test-direct.sh` 前置条件（`xcodebuild build-for-testing`）非内置步——
   执行批漏步致首轮定向跑在陈旧 DerivedData 产物上假绿（Sessions 13 = 旧集；
   T4 方法过滤 0/0/0 为暴露信号）。实质处置成立（重建 + 三 bundle 复跑 +
   T9 全套在新二进制执行），申报残留由 minor-1 勘误正本收口。**流程教训
   入册：测试命令序列 = build-for-testing → test-direct.sh，漏前者 = 假绿
   （类计数差 / 方法过滤 0/0/0 是暴露信号）**——LESSONS 落账义务移交
   maintenance 面（本批 doc-only 不触 LESSONS 正文）。
2. **omp 制度路配额阻塞 → 双 zcode 独立眼替代**：M6-2/M6-3/M6-4 同款
   429 家族登记；第二路意图由第二支零共享上下文 zcode 独立验收眼兑现
   （PASS，全套独立亲跑同值）——dual_acceptance 意图满足、制度字面偏离，
   登记晨审可裁。
3. **minor-1 收口形态（先例沉淀）**：执行批 commit message 数字残留 →
   **账面勘误正本落 VALIDATION + 原位订正 DECISIONS、commit 历史零重写**
   （M6-3 原位改数先例延伸至「message 不可变」变体）；后续验收批同形沿用。
4. **清算批性质注记**：M6-5 = M 站首个零生产行为变更 phase（六清偿 =
   test-only ×3 + 纯注释 ×2 + 机检门/键目录 ×1）；charter「挂账单一清单
   逐项闭合或转 V2 挂账留痕」以 SUMMARY §五逐项表为正本兑现，40 项无孤儿。
5. **登记级观察聚拢**（O-1..O-3 见挂账节末）：O-1 妆饰滑差为带日期历史行
   并存形态（不改写，逐项表正本）；O-2/O-3 provenance / 资源时效注记级。
6. **M 站挂账面收敛**：M5 三汇编 + M6-1 四项 + M6-2 三项 + M6-3 五项 +
   M6-4 六项全量入本批盘点 → 终态 = 清偿 6 / V2 9 / Manual-Only 19 行 /
   销账 7 / 留置 5——**M2..M6 历史挂账面首次全量清零入册**（历史批零星
   挂账不再有未盘点项）；残面 = 本挂账清单六项 + M6-6 收口批。

## 授权记录（C 档第 3 停 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 +
  M3/M4/M5/M6-1..M6-4 全系 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」（research/plan/
  执行 + 双重验收编排 + 本 VALIDATION 同一授权链）。
- 依授权，本 VALIDATION 由 VALIDATION 成文 executor 落盘签核（`.work/
  config.toml [gsd] paused=false / auto=true` 全程未动，dual_acceptance=true
  在册）；用户晨审可推翻本签核（推翻 = M6-5 签核作废回退，已交付面与三路
  执行/验收证据不受影响；翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode VALIDATION 成文 executor（2026-10-16 闭环批）；
  **doc-only——零源码 diff**（六清偿面 test-only/纯注释/键目录已随执行链
  入库；本批 = VALIDATION 成文 + 双 ACCEPTANCE 入库 + DECISIONS :89 勘误 +
  五正本翻账 + AGENTS 红线句限定语；工作树既有 untracked 兄弟批/孤儿参考件
  〔M3-1-ACCEPTANCE-PI / retro-dual / dt-clone-archive〕本批零触碰）。
- **呈报裁决点（禁静默）**：①Manual-Only 19 行 GUI 批安排（挂账 ④，默认 =
  下一 GUI 批）；②N-1 三键 + V17 门扩展随下一清算批或机检硬化批（默认 =
  候选登记不立即执行）；③SAM-COREML 立项时机（V2 #8，charter「大件另裁」
  ——用户专属）；④瘦身手术第二次触发确认（A20 留置，主会话专属）。

## 翻账与移交（本批同 commit）

- ROADMAP：M6-5 行 ✅ 闭环（三路同值 3848 + 40 项终局 + 挂账六项指针）；
  头部 Milestone 6 段追加 M6-5 closed。
- STATE：current_phase 翻新 = M6-5 closed → next M6-6；m6_phases_complete
  6/7；M6 Ledger M6-5 行 complete + terminal 3848/24/0。
- TODO：M6 头部 M6-5 ✅ 闭环追加 + 下一步 = M6-6；M6-5 条目追加 VALIDATION
  签核注记（带日期历史行只追加）。
- GOAL-STATE：顶部新续接点 = M6-5 closed → M6-6（FEATURE-MAP ID 化 + CI
  对账门 + M6 milestone VALIDATION 收口）；charter 剩余 = 裁决⑥一件。
- DECISIONS :89 原位订正（「9 旧」→「13 旧」+ 污染面评估句勘误，勘误
  标记指回本 VALIDATION §挂账 ①）。
- AGENTS「M6-5 架构增量」节红线句加限定语（`String(localized:` 两形态覆盖
  口径 + Text 族 / `String(` 跨行族不设防申报 + V17 候选指针）。
- 双 ACCEPTANCE（`M6-5-01-ACCEPTANCE.md` / `-2ND.md`）随本批入库；未 push；
  测试宿主/GUI 进程零残留（三路验收批各自清场申报在案）。

## 签核

- charter 验收形态（挂账单一清单逐项闭合或转 V2 挂账留痕）+ 六清偿任务
  + 零回归门 + 数字门全项 **Delivered**（三列证据齐；数字对账 = 三路独立
  亲跑同值 `TOTAL|3848/24/0|`〔2099s/2087s/2096s〕，对账链 3841+2+5 = 3848
  精确、M6-4 推算 3843 核销双式命中；双重验收零实质分歧，minor-1 同源残留
  勘误正本本批落账）。
- `status: validated` + `nyquist_compliant: true`。
- **M6-5（挂账清算批）closed**：40 项 + rider 全闭合（清偿 6 / V2 9 /
  Manual-Only 19 行 / 销账 7 / 留置 5）；执行链 `c749ee00..7c0d2bbb`
  （8 commits）；终验全套实测 `TOTAL|3848/24/0|`（三路独立亲跑同值）；
  挂账单一清单六项（minor-1 勘误正本〔本批落〕/ N-1 三键 → 下一清算批 /
  N-2 限定语本批落 + V17 候选 / Manual-Only 19 行 → 下一 GUI 批 / V2 九项
  + 留置五项指针 / M6-4 推算 3843 核销声明），移交 M6-6 收口批、GUI 批
  与晨审。
- 晨审裁决项：四项呈报裁决点（见授权记录）+ 签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**
