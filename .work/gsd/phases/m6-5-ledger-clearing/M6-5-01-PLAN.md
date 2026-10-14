---
phase: m6-5
plan: "M6-5-01"
title: "M6-5 挂账清算批（单 plan）——清偿六件（T1 孤儿 fixture 根治〔RasterEditFaceTests restore + undo 双写腿 temp 化〕/ T2 SessionBatchApplier 文档级 12 字段（七 additive + 五元数据）携带补齐 / T3 McpServerController 头注 19→20 + 伴文算术 / T4 gain-map HDR-base 行序方向性断言 / T5 门③载体分叉 API 消费者注记 / T6 格式键插值目录分诊门（zh-audit V16 断言 5）+ 三活体键清偿）+ Manual-Only 走查汇编（纯 doc）+ 转 V2 九项登记（纯 doc）+ 全套 --all 确认轮（预期 3848/24/0 = 3843 核销基线 + 5，8G 门红线）"
wave: 1
depends_on: []
autonomous: true
requirements: ["M6-5（ROADMAP §M6-5 行 + TODO M6-5 条——挂账单一清单逐项闭合或转 V2 挂账留痕）"]
estimated_tests: "+5（T2 +4 / T4 +1；执行时逐任务如实记账）"
test_bundles: [APP, Sessions, Export]
baseline: "3843/24/0（M6-4 修批后推算，带 3840..3844；本批 --all 确认轮核销）"
expected_all: "3848/24/0（= 3841 实测 + 2 修批 + 5 本批；对账式精确，执行时按 ΔN 实记账）"
files_modified:
  - Tests/LightamerTests/RasterEditFaceTests.swift                  # T1：restore + undo 双法改 tempFixtureCopy（DepthMaskEditingTests.swift:22-32/:273 verbatim 同款 helper + tempDirectory 生命周期）+ loadRaster(at:) URL 孪生；写腿（recordDrtChange/undo 的 scheduleSidecarWrite + flushUntilPersisted）全落 tmp 副本；repo 路径仅读 + 存量孤儿防御清扫；:173-222
  - Tests/LightamerTests/SessionBatchApplierTests.swift             # T2：+4 法（既有档臂 12 字段全带 + pristine 臂 additive 面零变化 + rating/keywords 数据保真各一）
  - LightamerCore/Sources/Session/SessionBatchApplier.swift         # T2：composeSegment 既有档臂显式捕获 12 字段（七 additive：provenance/rawOverrides/displayTransform/versions/activeVersionID/aiProvenance/filmRecord + 五元数据：rating/flag/colorLabel/keywords/note）+ 构造点传入；process 分支条件盖章纪律零触（:158-163 E1 注记原样）；pristine 臂缺省 nil 不变
  - .work/gsd/phases/m6-2-process-version/M6-2-VALIDATION.md        # T2（doc 配套）：挂账 #2 行后追加带日期对表补记（原文漏列五元数据字段；纯追加不改写）
  - App/Sources/Lightamer/MCP/McpServerController.swift             # T3：:15 + :448-449 两处 19-tool → 20-tool 且伴文算术 5 editing → 6 editing（match_color 在册）；零行为
  - Tests/LightamerTests/McpRenderParityTests.swift                 # T3：:564 同族 19-tool 注释顺带（纯注释零行为）
  - Tests/LightamerTests/DefaultFaceTests.swift                     # T3：:361 同族 19-tool 注释顺带（纯注释零行为）
  - Tests/LightamerTests/ExportGainMapTests.swift                   # T4：+1 法——非 uniform 增益面（上下半场异增益）× 非对称 base 的行序方向性断言（锚 = ExportGainMapEncoder.swift:137 .oriented(.downMirrored)）
  - LightamerCore/Sources/Export/ExportRecipe.swift                 # T5：validate 门③（:158-191）加 API-consumer 契约注记（载体分叉残余；全 UI 路不可达）；零行为
  - LightamerCore/Sources/Export/ExportRenderer.swift               # T5：:519 headroom 取值点同款注记（两载体同源自证义务）；零行为
  - Scripts/zh-audit.py                                             # T6：V16 扩展——localized 插值键提取（同行 + form 1c 续行面）+ 断言 5（目录格式变体 PRESENT 判定）+ 报告 [5] 节 + self-test golden 负测
  - Resources/Localizable.xcstrings                                 # T6：三占位符变体键尾块纯插入（settings_displays_overridden %@ / edr_headroom_label %@ / softproof_active_label %@；en+zh）
  - AGENTS.md                                                       # T6/T9：M6-5 架构增量节（V16 断言 5 门形态 + 三键登记 + --all 确认轮终值 + 清算台账指针）
  - .work/gui-acceptance/m6-5/MANIFEST.md                           # T7（gitignored 证据域，不 commit——落盘即可）：Manual-Only 走查汇编 ~17 行
  - .work/gsd/phases/v2-station/V2-PROPOSAL.md                      # T8：挂账区追加九项（触发条款对表基准 = M6-2 VALIDATION 挂账 #1 原文）
  - .work/gsd/phases/m6-5-ledger-clearing/M6-5-01-SUMMARY.md        # T9：执行摘要（逐任务 ΔN 记账 + 挂账闭合对表 + T6 分诊 transcript）
  - .work/gsd/phases/m6-5-ledger-clearing/M6-5-01-DECISIONS.md      # T9：裁定记录（分类偏差 + 执行期发现 + E-1 归因勘误）
  - .work/TODO.md                                                   # T9：M6-5 条目落账
  - .work/GOAL-STATE.md                                             # T9：续接点
---

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。清查正本 =
> `M6-5-CONTEXT.md`（盘点表 40 项 + 分类裁定 + file:line 量级评估）。
> 派遣形态 = research+plan 合批 worker 产物，执行批（omp 或 ZCode
> executor）接手本 plan。**零新 SPM / 零新 UserDefaults 键 / 零
> `.metal` / xcstrings 仅 T6 三占位符变体键尾块纯插入**（T3/T5 注记
> 不引入键；T4 断言复用既有 fixture 域）。
>
> **评审修订版**（2026-10-16 fixer 批）：`M6-5-01-PLAN-REVIEW.md`
> E-1/E-2/E-3 + M-1..M-4 全数落入本版（逐 finding 落点见文尾
> 「评审修订记录」节）；修订依据的代码锚点均 HEAD 亲核。

# Plan M6-5-01 — 挂账清算批（单 plan）

> **性质**：清偿 + 汇编 + 登记 + 确认轮四合一。每个清偿任务独立 commit
> （Conventional Commits，只 add 相关文件）；doc 任务（T7/T8）与收口
> （T9）各一 commit。构建用 `caffeinate -dis` 包裹；单测标准命令 =
> `Scripts/test-direct.sh`（直启宿主，绕开 testmanagerd）。
> **bundle token 纪律（M-1）**：`test-direct.sh` 的 bundle 注册表 =
> `(IOP IOPParity Layers Library Sessions Export App)`，**大小写敏感
> 无归一**——命令一律用注册表原样 token（`App`/`Sessions`/`Export`），
> 禁 `APP`/`LIB`/`EXPORT` 大写变体。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m6-5-ledger-clearing/M6-5-CONTEXT.md`（本批正本）
- `.work/config.toml [gsd]` paused/auto 开关（暂停机制）
- `.work/LESSONS.md` L041（tuist generate 恒末位）/ L074（直驱 commit
  类测试图片锚必须 temp 化）/ L014（GPU 读回 fence）
- `AGENTS.md` 资源监控节（--all 批准制 + 8G 门 + MEMFAIL 机检）

---

## T1 — 孤儿 fixture 根治（A1/B2/C3 三源同条；M4-1 挂账 #6 终局）

> **E-1 修订**：App bundle 的 repo 路径写腿全集 = **restore + undo
> 两法**，只 temp 化 restore 法则 undo 法继续产孤儿。归因勘误（写入
> DECISIONS）：M5-1「defer 清扫输给迟到 write-behind」的归因错位——
> 真残写源 = undo 法 `testUndoToTopKeepsRasterDrtCarrier` 的 post-test
> debounce 写：`loadRaster("srgb-matrix-8.tif")`（:205，repo fixture
> 路径）后 :209 `recordDrtChange` + :213 `undo()` 各自
> `scheduleSidecarWrite()`（EditorState → `drtRecordDidChange`
> PipeCoordinator.swift:622 / undo :1855「position moved — persist it
> too」），2s debounce 写在测试返回后落地；M6-2 VALIDATION :60 在册
> 排除项「undo 到顶后写腿仍写 carrier 值」直证 undo 到顶照写。
> restore 法 flush 后无再调度写、其 defer 确定性胜出——孤儿五度再生
> 与 restore 法 defer 无关。

- **action**：
  1. `RasterEditFaceTests.swift` 增加 `tempFixtureCopy(_:)` helper +
     `tempDirectory` UUID 生命周期（setUp 建 / tearDown 清——
     `DepthMaskEditingTests.swift:22-32` + `:273-283` verbatim 同款）。
  2. **restore 法** `testRestoreWinsOverDerive`（:173-200）：
     `let url = try tempFixtureCopy("srgb-matrix-8.tif")` 替换 repo
     fixture 取用——:187-190 的真实写腿（load → recordDrtChange →
     flushUntilPersisted）全部落 tmp 副本；入口前清/defer 语义保留
     （改指 tmp sidecarURL）；repo 侧保留一行防御性 `removeItem`
     （存量孤儿不毒轮）。
  3. **undo 法** `testUndoToTopKeepsRasterDrtCarrier`（:202-222）：
     url 换 `tempFixtureCopy("srgb-matrix-8.tif")`；`loadRaster` 加
     `loadRaster(at:)` URL 孪生（原 name 形保留；孪生 = decode + load
     直通 3 行）。断言全在 carrier 面（`drtRecord`/`hasDrtRecord`），
     与文件路径无关，换 tmp 副本零语义影响；方法体其余零改。
  4. 文件头注释补 M4-1 #6 终局注记（**双**写腿 temp 化 = L074 纪律
     兑现；含 E-1 归因勘误一行）。
  5. 测试运行前置清扫：删除现存孤儿
     `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（untracked，
     直接 rm）。
- **验收标准（机检）**：
  - 定向 `--bundle App RasterEditFaceTests` 全绿（7 法含改后双法）。
  - 定向 `--bundle Export RasterRoundTripTests` 全绿（读同 fixture 的
    跨 bundle 面不受扰）。
  - 轮毕 `find Tests/Fixtures -name "*.lra"` 零命中（transcript 记
    SUMMARY）。
  - `git status` 确认 Tests/Fixtures 无新增 untracked。
- **commit**: `fix(m6-5): move both raster sidecar write legs onto tmp fixture copies`

## T2 — SessionBatchApplier 文档级 12 字段携带补齐（C2；E-2 扩面）

> **E-2 修订**：七字段清单 = M6-2 挂账 #2 原文照抄，而挂账原文本身
> 漏列——`LightamerSidecar` 文档字段面（:250-377）逐字段对表后，除七
> additive 外 `rating`(:293) / `flag`(:297) / `colorLabel`(:300) /
> `keywords`(:306) / `note`(:309) 五个 optional 元数据字段同样被既有
> 档臂丢弃（构造点不传 = decode 出 nil）。产线确有写腿持久化它们：
> `LightamerCore/Sources/Session/MetadataService.swift`
> :85/:95/:104/:122/:145（setRating/setFlag/setColorLabel/setKeywords/
> appendNote 全部 decode → mutate → write `.lra`）——带 rating/
> keywords/note 的目标图过 batch apply（Copy Adjustments）= 库内组织
> 元数据静默清除，与七字段同族数据保真缺陷。裁定 = 携带面扩 **12
> 字段**（七 additive + 五元数据；语义同为「携带目标档自有文档级状态，
> paste 只动调整结构」），一次清干净避免第三批再开同族挂账。

- **action**：
  1. `SessionBatchApplier.swift` 既有档臂（:111-118 decode 成功分支）：
     捕获 **12 字段** = `provenance` / `rawOverrides` /
     `displayTransform` / `versions` / `activeVersionID` /
     `aiProvenance` / `filmRecord` 七 additive（命名 =
     `LightamerSidecar.swift:317-365` 原文）+ `rating` / `flag` /
     `colorLabel` / `keywords` / `note` 五元数据（:293-309 原文）。
  2. :149-163 `LightamerSidecar(` 构造点：12 参显式传入（additive、
     缺省 nil 语义不变）；**`process: processStamp` 分支条件盖章纪律
     零触碰**（:158-163 注记原样保留；禁 `?? .current`）。
  3. pristine 臂（:119-133 else 分支）零改（新档 additive 字段缺省 nil
     = 既有字节面零漂移）。
  4. `SessionBatchApplierTests.swift` +4 法（ΔN 记账 +4）：
     - `testBatchApplyCarriesDocumentLevelAdditiveFields`——构造含 12
       字段的目标档（decode document 直写盘），composeSegment 后断言
       composed 文档 12 字段全带（+ process 走既有档臂 verbatim）。
     - `testBatchApplyPristineArmKeepsAdditiveFaceEmpty`——无档目标
       compose 后 12 字段全 nil（既有面负测）。
     - `testBatchApplyPreservesRatingFidelity`——rating 非零值（如 3）
       过 batch apply 逐值保真（非 nil 化、非钳制；nil 档不落键）。
     - `testBatchApplyPreservesKeywordsFidelity`——层级关键词
       （`"Nature|Flower|Rose"` 全路径形）过 batch apply 逐元素保真。
  5. **M6-2 挂账对表补记（doc，E-2 配套）**：`M6-2-VALIDATION.md` 挂账
     #2 行后追加带日期补记行（**不改写原行**）：原文七字段清单漏列五
     元数据字段（锚 `LightamerSidecar.swift:293-309`），M6-5 T2 修批
     按 12 字段全带清偿。
- **验收标准（机检）**：定向 `--bundle Sessions
  SessionBatchApplierTests` 全绿（既有法含三态 process 法不红）；
  `git diff LightamerCore/Sources/Session/SessionBatchApplier.swift`
  仅 :100-163 窗内 additive 行；sidecar schema 文件零 diff；
  M6-2-VALIDATION diff = 纯追加补记行。
- **commit**: `fix(m6-5): carry all 12 document-level fields through batch apply`

## T3 — McpServerController 头注 19→20 + 伴文算术（A13；M-3 扩面）

- **action**：
  1. `McpServerController.swift` :15 与 :448-449 两处注释：19-tool →
     20-tool **且伴文算术同步**「(5 editing + 14 culling)」→
     「(6 editing + 14 culling)」（match_color 属 editing 族——只改
     19→20 会产出「20-tool (5 editing + 14 culling)」内部矛盾句）；
     补一句「+ match_color（M5-1-03）」；不加新注释块，原位改词。
  2. 全仓同族陈旧注释两处顺带（仍纯注释零行为，禁留新陈旧账）：
     `McpRenderParityTests.swift:564` + `DefaultFaceTests.swift:361`
     的 19-tool 字样同步改 20。
- **验收标准（机检）**：`grep -rn "19-tool" App/Sources Tests
  LightamerCore/Sources LightamerIOP/Sources` 零命中；
  `grep -c "20-tool" App/Sources/Lightamer/MCP/McpServerController.swift`
  ≥2；`grep -n "5 editing"
  App/Sources/Lightamer/MCP/McpServerController.swift` 零命中；
  `git diff` 仅注释行（零代码行变更）。
- **commit**: `docs(m6-5): update the MCP tool-face headers to the 20-tool set`

## T4 — gain-map HDR/base 行序方向性断言（D2）

- **action**：
  1. `ExportGainMapTests.swift` +1 法
     `testGainMapRowOrderIsTheDownMirroredAlignment`——构造非 uniform
     增益面（上半场 gain ≈1.0 / 下半场 gain ≈2.0，单通道）× 非对称
     base（上半场中灰 / 下半场高光），走 `ExportGainMapEncoder.encode`
     产文件 → ImageIO 重读 aux 增益面：断言下半场采样点增益语义显著
     高于上半场（行序方向单向断言；如单向断言带不稳，改 flip 反置
     负测——手工翻转增益面重编码，两产物逐位不同 + 方向互换）。
  2. 断言形式执行时择稳（CONTEXT §3.4 预案二选一），DECISIONS 记选择
     理由。
- **验收标准（机检）**：定向 `--bundle Export ExportGainMapTests`
  全绿（**26 法 = 25+1**；M-2 订正——HEAD 实测 25 法，CONTEXT D2 记
  「24 法亲点」= 计数漂移〔`c077784a` 容器批后未复核〕，本批以账面
  精确为纲按 26 对账，防 T9 对账自扰）；新法在无 gain-map 负测族之外
  独立；`git diff` 仅测试文件 additive。
- **commit**: `test(m6-5): pin the gain-map row order with a directional assertion`

## T5 — 门③载体分叉 API 消费者注记（D4）

- **action**：`ExportRecipe.swift` validate 门③（:158-191）与
  `ExportRenderer.swift:519` headroom 取值点各加一段注释：直接构造
  `ExportQueue.Request` 的 API 消费者可组出「`drtOutput.peakLuminance`
  ≥203 合格 + `drtTail.record.peakLuminance` 偏低」→ 产物
  headroom<1（gain 语义弱化非崩溃）；两载体须消费方自证同源（生产 UI
  路经 `enqueueExportM2` 强制联动不可达——M6-3 双路验收在案）。零行为。
- **验收标准（机检）**：`git diff` 仅两文件注释行；Export 定向轮编译
  绿（`--bundle Export` 抽一轮或 build 证编译）；无断言/行为变化。
- **commit**: `docs(m6-5): note the gate-3 carrier-fork contract on the public export API`

## T6 — 格式键插值目录分诊门（F1；E-3 重刻 = zh-audit V16 断言 5 + 三活体键清偿）

> **E-3 修订**：原「`String(localized: "…\(` 禁形 + 零命中基线」被现树
> 证伪——该形态是 xcstrings **格式键合法惯例**（构建期提取为占位符键，
> zh-audit V15 form 1c 已在册），单行 grep 实测 27 命中且抽验键目录
> 变体全 PRESENT；「禁形」定性滑步作废。门语义重刻为「目录占位符变体
> PRESENT/ABSENT 分诊」：PRESENT = 合法格式键（绿）；ABSENT = 运行时
> 回退裸键的真缺陷（红，M2-9 F-2 家族活体）。现树实测 ABSENT **3 键**
>（非评审抽验的 1 键）：`settings_displays_overridden`
>（SettingsPages.swift:1191）/ `edr_headroom_label`
>（EDRControlView.swift:46）/ `softproof_active_label`
>（SoftProofControlView.swift:82）。

- **action**：
  1. `Scripts/zh-audit.py` **V16 扩展**（V15 提取器硬化同族）：
     - 新提取：`String(localized: "K \(…)"` 同行面（新 regex，键形同
       `KEY_SHAPE`）+ form 1c 续行面（PENDING 机制延拓：次行以插值
       字面量开头也登记）→ `localized_interp_keys`（key → 路径表）。
     - 断言 5：每个 localized 插值键 K，目录必须存在 `K %`-前缀格式
       变体键（**裸静态键 K 不计**——插值调用的提取键恒为格式键；
       %lld/%@ 具体 spec 不作深检，spec 错配〔变体在册但形态不符〕
       留人工走查，不属本门）。计入 `AuditViolations` total。
     - 报告 [5] 节（逐键 PRESENT/ABSENT + 路径）。
     - self-test golden 负测：BAD fixture 增「插值键无目录变体」用例
       （断言 5 红）+ 既有 `selftest_family` / `selftest_family_cont`
       补目录格式变体（断言 5 绿）+ 1c 续行插值 twin——
       `--self-test` PASS 为 AC。
  2. 现树分诊 transcript（fixer 预扫定格，2026-10-16 HEAD）：**30
     调用点 / 30 独立键** = 单行面 27 命中 27 键（24 PRESENT + 3
     ABSENT）+ 1c 续行面 3 调用点 3 键全 PRESENT
     （`toast_import_partial` / `toast_hdr_merge_failed` /
     `toast_hdr_merge_done`，LightamerApp.swift:943/:1103/:2019）。
     V16 首跑重建逐键分诊表记 SUMMARY（清偿前 3 红 → 清偿后 0 红）。
  3. 三活体键清偿：`Resources/Localizable.xcstrings` 补
     `settings_displays_overridden %@` / `edr_headroom_label %@` /
     `softproof_active_label %@` 三键（**尾块纯插入**，en+zh 值；调用
     点代码零改）；键值措辞对齐既有相邻键族（settings_displays_* /
     edr_* / softproof_*）。
  4. AGENTS「M6-5 架构增量」节登记：V16 断言 5 门形态一行 + 三键
     登记（后续批红线电池引用 = `zh-audit --check` ABSENT 零命中）。
- **验收标准（机检）**：`python3 Scripts/zh-audit.py --self-test`
  PASS；`--check` PASS（目录 1923+3 = 1926 键，断言 5 ABSENT 零命中）；
  `git diff Resources/Localizable.xcstrings` = 恰 3 键尾块纯插入；
  triage transcript 在案（30 键逐键绿/红 → 清偿后全绿）；AGENTS
  「M6-5 架构增量」节登记行落盘（V16 门形态 + 三键）。
- **commit**: `fix(m6-5): gate localized interpolation keys on catalog format variants`

## T7 — Manual-Only 走查汇编（纯 doc，不执行）

- **action**：落盘 `.work/gui-acceptance/m6-5/MANIFEST.md`——汇编
  CONTEXT §6 行集（M5-1 human rows + G2/A8/A10 观察行；M5-2 行 1/3/4；
  M5-3 行 2/3/5 + 行 4 屏面；M6-1 C 行；M6-3 跨生态可选行；M6-4
  M-1..M-4 + plan01 五行 + D-06/D-07 补录义务行；rider = M4-3 guided
  filter 深边界糊）。每行 = 配方指针（来源 MANIFEST 锚）+ 前置供件 +
  预期观测。**bake 生产耗时（A4）单列 perf 观察行**（非 GUI 行）。
- **验收标准**：MANIFEST 行数 = CONTEXT §6 明细逐条可对；每行有来源
  指针；零执行声明（「本批不执行」头注）。
- **commit**：**不入 git**（`.work/gui-acceptance/` 证据域 gitignored，
  L073 口径）——落盘即可，SUMMARY 记路径。

## T8 — 转 V2 九项登记（纯 doc）

- **action**：`V2-PROPOSAL.md` 末尾追加「七、M6 清算批转 V2 挂账
  （2026-10-16 M6-5 批登记）」节——CONTEXT §5 九项措辞落盘（每项：
  名称 / 来源 phase + 锚 / 触发条件 / 规模 / 一句话）；登记头注声明
  「登记 ≠ 立项，终裁在用户」。C1（PROCESS-WIRING）落触发条件档形态，
  **触发条款与 M6-2 VALIDATION 挂账 #1 原文同文**（「首个真实 iop
  语义分叉/bump 批」——非 CONTEXT §5 的转述形「首个真实 iop 语义
  bump 批」），四件套与 `M6-2-01-DECISIONS.md` §6 ①..④ 语义逐条
  镜像（含②「分叉 iop 在 `process` 内消费
  `RenderProcess.resolving(piece.renderProcess)`」完整形）。
- **验收标准（机检）**：九项各有一级标题行 + 触发条件字段；C1 触发
  条款文本与 `M6-2-VALIDATION.md` :104 句式同文、四件套可对 DECISIONS
  §6 逐条镜像；来源锚可 grep（各 VALIDATION 挂账节原文在位）；零删除
  既有内容（纯追加节）。
- **commit**: `docs(m6-5): register nine V2 candidates from the M6-5 ledger sweep`

## T9 — 全套 `--all` 确认轮 + 收口（批准制 + 8G 门红线）

- **action**：
  1. `tuist generate`（如 Project.swift 有登记变更——本批 files_modified
     无新测试文件，一般不需要；有则 generate 恒末位，L041）。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （夜间授权链覆盖 = 批准在案；运行中保持监视，>8G 或内存压力转红
     立即 kill）。
  3. 轮毕孤儿复扫：`find Tests/Fixtures -name "*.lra"` 零命中
     （T1 终验 transcript）。
  4. SUMMARY（逐任务 ΔN 记账 + 挂账闭合对表 40 项逐行状态 + T6 分诊
     transcript）+ DECISIONS；AGENTS「M6-5 架构增量」节（终值 + V16
     门形态 + 台账指针）；TODO M6-5 条目 [x]；GOAL-STATE 续接点翻新
     = M6-5 closed → M6-6。
- **验收标准（机检）**：
  - exit 0 + 0 fail + 0 MEMFAIL + 七 bundle 全 8G 门内；
  - **TOTAL == 3843 + ΔN（预期 3848/24/0；ΔN = T2 +4 + T4 +1 = +5，
    执行时如实记账）**；对账式 = 3841（M6-4 实测）+ 2（M6-4 修批）+
    5（本批）= 3848 精确；异常形态（ΔN=0）回退核销带 3840..3844 判定
    并停手上报；
  - 孤儿复扫零命中 transcript；
  - 五正本翻账同批（TODO/GOAL-STATE/AGENTS/ROADMAP M6-5 行 ✅ 由
    VALIDATION 批执行——本 plan 只翻 TODO/GOAL-STATE/AGENTS，ROADMAP
    M6-5 行翻账留 M6-6 VALIDATION 或本批 VALIDATION 面，执行时按
    orchestrator 指令）。
- **commit**: `docs(m6-5): close the ledger-clearing batch (full-suite confirmation)`

---

## red_lines（零 diff 机检族，T9 收口核对）

- `LightamerIOP/` 全域零 diff；全部 `*.metal` 零 diff。
- `LightamerSidecar.swift` 零 diff（schema 零字节变更；T2 只消费
  既有字段）。
- `Pipe/History/` + `PipeCacheKey.swift` 零 diff；V50Order 零触。
- MCP 快照族（McpRegistrySnapshotTests 等）零 diff（T3 纯注释不触
  descriptor 面；T3 触 `McpRenderParityTests`/`DefaultFaceTests` 两
  文件注释行——非快照族成员，不违本条）。
- Export 六格式矩阵面（`ExportFormatSpec`/`ImageIOEncoders`/
  `WebPEncoder`）零 diff（T5 纯注释）。
- `Project.swift` dependencies 块零 diff（零新 SPM）；无新测试文件则
  Project.swift 全零 diff。
- `*.xcstrings` **除 T6 三占位符变体键尾块纯插入外零 diff**；
  UserDefaults 零新键；`\.runModal(` App/Sources 零命中；
  `String.LocalizationValue("` 插值禁形零命中；**zh-audit V16 断言 5
  ABSENT 零命中**（`--check` PASS——替代原「T6 新门零命中基线」表述，
  E-3）。
- 工作树零新增 untracked 源文件（孤儿 fixture 复扫零命中是唯一允许的
  「无残留」态）。

## 风险与回退

- T1 双法 temp 化后若 tmp 域 `flushUntilPersisted` 轮询时序差（同构
  语义，风险低）——回退预案 = tmp 副本域内延长有界等待窗，
  DECISIONS 记录。**原「保持 repo 路径写」预案作废**（与根治目标
  矛盾，E-1）。
- T4 断言形式二选一预案在 action 内置（单向断言不稳 → flip 反置负测）。
- T6 断言 5 不作 %lld/%@ spec 深检——spec 错配（变体在册但形态不符）
  留人工走查；门语义 = PRESENT/ABSENT 分诊（E-3 边界申报）。
- --all 轮贴线 bundle（IOP/IOPParity）连续 MEMFAIL → 先查重测顺序漂移
  （AGENTS 在案口径），非本批引入面（零 IOP 触碰）。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——本批批内窗 =
  SessionBatchApplier.swift + 4 测试文件 + zh-audit.py + xcstrings +
  3 注释文件；窗外 fail = 既有缺陷，停手上报不静默修。

---

## 评审修订记录（2026-10-16 fixer 批；依据 = `M6-5-01-PLAN-REVIEW.md`）

| finding | 落点 |
|---|---|
| E-1 | T1 重刻：restore + undo 双法同改 tempFixtureCopy（undo 法 :205/:209/:213 写腿链 + `loadRaster(at:)` 孪生 + helper/tempDirectory verbatim 搬入）；M5-1 归因勘误写入 T1 头注 + DECISIONS 义务；M6-2 VALIDATION :60 排除项引证；风险节「保持 repo 路径写」预案作废；T9 复扫断言保持；bundle token `App` |
| E-2 | T2 扩 12 字段（七 additive + 五元数据 rating/flag/colorLabel/keywords/note；`LightamerSidecar.swift`:293-309 + `MetadataService.swift` 五写点引证）；回归法 +2→+4（12 字段携带正测 + pristine 负测 + rating/keywords 保真各一，ΔN +4）；M6-2 挂账 #2 对表补记任务追加（doc，纯追加行）；`--bundle Sessions` token 订正 |
| E-3 | T6 重刻为「目录占位符变体 PRESENT/ABSENT 分诊」：zh-audit V16 扩展（同行 + 1c 续行提取 + 断言 5 + 报告 [5] 节 + self-test golden 负测）；三活体键清偿（xcstrings 尾块纯插入 ×3，调用点零改）；现树分诊定格 30 调用点/30 键 = 27 PRESENT + 3 ABSENT；red_lines「零命中」→「断言 5 ABSENT 零命中」+ xcstrings 零 diff 加 T6 例外 |
| M-1 | bundle token 全订正（`LIB`/`APP`/`EXPORT` → `Sessions`/`App`/`Export`——注册表大小写敏感亲验）；SessionBatchApplierTests 归 Sessions；front-matter test_bundles = [APP, Sessions, Export]（T4 归 Export） |
| M-2 | T4 法数订正 26 = 25+1（HEAD 实测 25 法；CONTEXT D2 记 24 = 计数漂移勘误注记入 AC） |
| M-3 | T3 扩全：伴文算术 5 editing → 6 editing + 全仓另两处 19-tool（McpRenderParityTests:564 / DefaultFaceTests:361）+ 验收补「5 editing 零命中」grep |
| M-4 | T8 AC 对表基准改 M6-2 VALIDATION 挂账 #1 原文（「首个真实 iop 语义分叉/bump 批」）+ DECISIONS §6 四件套语义逐条镜像；:104 句式同文机检 |
| 算术 | ΔN +3 → **+5**（T2 +4 / T4 +1）；expected_all 3846 → **3848**（= 3841 + 2 + 5）；baseline/T9 对账式同步 |

> fixer 亲测增量（评审证据之外）：①ABSENT 活体实为 3 键（评审抽验 1）；
> ②真树另有 3 处 form-1c 续行插值面（全 PRESENT，单行 grep 不可见）；
> ③`test-direct.sh` bundle token 大小写敏感无归一——plan 原文
> `--bundle APP/EXPORT` 同为非法 token，随 M-1 一并订正。
