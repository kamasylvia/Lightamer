---
phase: m2-2
plan: "M2-2-3"
title: "查询面——Album Inspector 数据面（M2LIB-05：总数卡/四分组/Activity 日计数/过滤态投影，API 先于壳）+ EXIF 词法检索解析器（iso800/f2.8/35mm/日期多格式 AND 组合）+ keyset 分页集合查询 + 性能硬门基准（Release p95 < 20ms @ 2 万张，SC#3 方法学，MANUAL-ONLY harness）"
wave: 3
depends_on: ["M2-2-1", "M2-2-2"]
autonomous: true
requirements: [M2LIB-04, M2LIB-05]
files_modified:
  - LightamerCore/Sources/Library/ExifSearchParser.swift         # 新建：自由词 → ExifSearchPlan（结构化谓词 ∪ FTS MATCH 词 AND 组合；iso800/iso 800/f/2.8/f2.8/35mm/35 mm/日期多格式识别）
  - LightamerCore/Sources/Library/LibraryQueries.swift           # 新建：集合查询（keyset 分页 row-value seek + NULL tail 两段式）/ Overview 总数 / 四分组聚合（日期/相机/标签/镜头）/ Activity 按日计数序列 / 过滤态投影（FilterPredicateGroup + 词法 plan 混查 AND）
  - Tests/LightamerTests/ExifSearchParserTests.swift             # 新建（→ tuist generate）：识别矩阵 + AND 组合语义 + 非法词降级
  - Tests/LightamerTests/LibraryQueriesTests.swift               # 新建：分页边界/四分组/Activity/混查命中/词法精确（iso800 不含 iso8000）
  - Tests/LightamerTests/LibraryBenchmarkHarness.swift           # 新建：MANUAL-ONLY（LA_LIBRARY_BENCH=1 门）——≥12 检索形状 × 3 排序 × 2 深度，20k 合成语料，p95 nearest-rank，Release 硬门 < 20ms；观察项（10 万张外推/导入吞吐）
  - .work/gsd/phases/m2-2-library-project/perf.md                # 新建：phase 级性能账本（三轮 Debug+Release 对账 + 硬门终值 + 观察项）
  - .work/gsd/phases/m2-2-library-project/M2-2-3-SUMMARY.md      # 新建（收口任务）
  - .work/gsd/phases/m2-2-library-project/M2-2-3-DECISIONS.md    # 新建（收口任务）
  - .work/GOAL-STATE.md                                          # 续接点追加（收口任务）
  - LESSONS.md                                                   # 如踩坑
---

# Plan M2-2-3 — 查询面（Inspector 数据 API + 词法检索 + 性能硬门）

> **性质**：数据与查询面 plan——M2-3 的壳只做渲染的前提（OQ-11 切分线：本 plan 交付
> 面 = 四分组聚合 SQL / Activity 日计数序列 / Overview 计数 / 过滤态集合投影 API +
> Core 单测；面板/网格/搜索对话框壳 = M2-3）。性能硬门（OQ-9 A 签核）= **EXIF 词法
> 组合检索 Release p95 < 20ms @ 2 万张**，harness 方法学照抄 SC#3 先例
> （CatalogBenchmarkHarness：env 门 MANUAL-ONLY + Release 直启 DYLD 附录 + 三轮对账）。

## 已定裁决（不得重开）

- **OQ-7**：双层检索——结构化物化列走 `FilterSQL.library` 域（范围/排序/聚合）；自由
  词 AND 组合走 `exif_search_words` FTS5 MATCH；两类谓词 AND 混查。折叠物化 =
  M2-2-1 `ExifFold` 正本（正确性承重面），本 plan 只消费。
- **OQ-9**：硬门 **p95 < 20ms @ 2 万张（Release）**；形状矩阵 ≥ 12 检索形状 × 3 排序
  × 2 深度（词法 AND / 结构化范围 / 混查）；观察项（非门）：10 万张外推、首屏缩略图
  时间（M2-3 前无网格，登记为待测挂账）、导入吞吐 ≥100 张/min 软指标。
- **OQ-11**：Inspector 数据面 API 本 plan 定型（`LibraryQueries` 单面），M2-3 壳零
  SQL（只调 API）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 `ExifSearchPlan` = 三段 typed 计划，翻译一次消费一处

`ExifSearchParser.parse(_ raw: String) throws -> ExifSearchPlan`：

```swift
struct ExifSearchPlan: Equatable, Sendable {
  var ftsTerms: [String]            // FTS MATCH 词（折叠变体精确 token；支持尾随 * 前缀透传）
  var structured: [StructuredTerm]  // iso/focal/aperture 的 eq/range（物化列谓词）
  var dateRange: ClosedRange<Date>? // 日期多格式 → capture_date 范围
}
```

识别矩阵（KD 词表对齐 `ExifFold.matchQueryToken`）：`iso800`/`iso 800` → iso==800；
`iso>800`/`iso:800-1600` → 范围；`f/2.8`/`f2.8`/`f 2.8` → aperture≈2.8（±0.05 浮点
容差等值——物化列 REAL 直等易失配，KD：aperture 识别为 **range [v-0.05, v+0.05]**）；
`35mm`/`35 mm` → focal==35；`2024`/`2024-06`/`2024-06-01`/`2024/06/01` → 年/月/日
范围；其余裸词 → 小写折叠后进 `ftsTerms`。多词 AND = plan 内部三段各自 AND 再互
AND。不识别的组合（如 `isoabc`）→ typed error（对话框层 M2-3 呈现）。**parser 纯
函数零 IO**，全矩阵表驱动测试。

### KD-2 混查 SQL 形状 = `WHERE <FilterSQL.library> AND id IN (MATCH)` 单语句

`LibraryQueries.searchPage(filter: ExifSearchFilter, sort:, anchor:, limit:)` 单语句：

```sql
SELECT i.* FROM images i
 WHERE <FilterSQL.translate(.library) whereClause>          -- 结构化/智能相册腿
   AND i.id IN (SELECT rowid FROM images_fts WHERE images_fts MATCH ?)  -- 词法腿
   AND <keyset seek 谓词>                                    -- 排序腿
 ORDER BY <白名单排序> LIMIT ?;
```

无词法词 → MATCH 腿整段省略；无结构化 → FilterSQL 腿 = `(1=1)` baseline。**两腿都
可独立命中是 FTS external-content rowid==images.id 的直接推论**（KD-5 P1 DDL 保证），
测试负例钉（FTS 行与 images 行数恒等）。

### KD-3 keyset 分页 = CatalogIndexStore 先例移植，禁 OFFSET

`(capture_date, id)` row-value seek + NULL tail 两段式（`CatalogIndexStore.queryPage:175`
/ `queryNullTail:236` 同型；`CatalogPageAnchor` 结构对齐）；排序白名单 =
`FilterSortKey` 既有集合（captureDate/rating/filename...`orderBySQL(domain:)` 扩
`.library` 臂）。**禁 OFFSET/LIMIT 跳页**（16-x keyset-only 纪律延续）。

### KD-4 四分组/Activity = 预聚合 SQL 单查询面

- `overviewCount(filter:)` → COUNT。
- `groupCounts(by: GroupKey, filter:)`：`.captureDate`（按日 `%Y-%m-%d` 分组）/
  `.camera`（`camera_make || ' ' || camera_model` 归一，NULL → "Unknown"）/
  `.labels`（rating 星档分组）/ `.lens`——四键各一条 GROUP BY，返回 `[GroupCount]`
  （label + count + 可选 anchor 载荷供点击过滤，M2-3 消费）。
- `activitySeries(range:)` → `[(day: String, count: Int)]` 按日计数序列（Activity
  view 数据正本；点击某天过滤 = 把该日折叠进 `FilterPredicateGroup.captureDate`
  between——投影函数 `dayFilter(day:)` 同面导出）。
- 过滤态投影 = `currentFilterDescription(filter:)` → typed 描述 struct（M2-3 SEARCH
  FILTER 区渲染源；不等价字符串拼接）。

### KD-5 基准 harness = SC#3 方法学逐条移植

`LibraryBenchmarkHarness`（MANUAL-ONLY，`LA_LIBRARY_BENCH=1` 门，无门即 skip——
CatalogBenchmarkHarness 头注同款声明）：

- fixture：20,000 行合成 EXIF 语料（seeded 随机：stem/日期/5 相机/5 镜头/7 档 ISO/
  6 档光圈/7 档焦距——探针 P2 同分布）+ 真实 RAW 交叉腿（`input/RAW/` 存在时读真
  EXIF 物化入 200 行，env `LA_LIBRARY_BENCH_REALRAW=<dir>` 可指；不存在 skip 不算
  违约）。落 `/tmp` throwaway（L009）。
- 矩阵：12 检索形状（词法 4 词 AND / iso 范围 / aperture 档 / focal / 日期窗 /
  相机 / 镜头 / rating / 混查 4 形态）× 3 排序 × 2 深度（页首/页深 50 页）；
  warm-up 一轮 + 计量一轮，p95 nearest-rank，`BENCH|` 行打印。
- **主门 = Release 直启列**（`LA_LIBRARY_BENCH=1` + Release 构建 + ad-hoc re-sign +
  DYLD app-embedded-first——CatalogBenchmarkHarness T1 FINAL-RUN ADDENDUM 附录
  逐条沿用）；Debug 列参考。三轮对账（Debug+Release），门值只认 Release 热 p95。
- 观察项：N=100,000（`LA_LIBRARY_BENCH_N`）外推一组 + 导入吞吐（T1 fixture 复用
  ImportService 计时 ≥100 张/min 软记录）。
- 账本 = `.work/gsd/phases/m2-2-library-project/perf.md`（phase 根，AGENTS §3 布局
  冻结节）。

### KD-6 词法精确性负例进查询面测试

`iso800` 查询不得命中 `iso8000` 值行——探针 P2 正确性抽核在查询面复钉（FTS 词法腿
经 `ExifFold` 词表精确 token 天然不误伤；structured 腿 eq 精确）——P3 基准与单测
双面钉。

## read_first

1. `.work/gsd/phases/m2-2-library-project/M2-2-1-PLAN.md`——KD-5 FTS DDL / ExifFold /
   FilterDomain.library / keyset 索引（消费缝）。
2. `.work/gsd/phases/m2-2-library-project/M2-2-CONTEXT.md`——OQ-7/9/11 裁决 +
   Reusable Assets 表（CatalogIndexStore 行号锚）。
3. `M2-2-RESEARCH-NOTES.md` P2 全节——识别矩阵/分布/17×/前缀串抽核（KD-1/KD-6 正本）。
4. `LightamerCore/Sources/Catalog/CatalogIndexStore.swift:51-330`——keyset 分页/锚
   结构/NULL tail 两段式/count 面正本。
5. `Tests/LightamerTests/CatalogBenchmarkHarness.swift`——SC#3 harness 全文（env 门/
   fixture 分布/矩阵/p95 打印/Release 附录）。
6. `LightamerCore/Sources/Session/FilterSQL.swift`——`.library` 域 + `FilterSortKey.
   orderBySQL(domain:)` 扩展落点。
7. `LightamerCore/Sources/Library/{ExifFold,LibraryStore,ProjectFileStore}.swift`——
   消费缝（withHandle / insertImage 语料灌入）。
8. `research/ALCEDO-FEATURE-MAP.md` §1.2 Album Inspector 段——四分组/Activity/搜索
   过滤态语义锚。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（全英文 Conventional Commits，subject ≤72 祈使句，
   body what+why）；只 add 申报文件；不 push；`.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹；不加 `-derivedDataPath`；新建 .swift 后同
   commit `tuist generate`。
3. **测试纪律**：`Scripts/test-direct.sh '<Class>'` 双读（L028）；基线 = GOAL-STATE
   续接点最新值（1889 + M2-2-1/2 新增）；全套 0 fail；harness 无 env 门时 skip 不计
   违约（SC#3 同语义）。
4. **边界纪律**：每任务边界查 `.work/config.toml [gsd]`。
5. **架构红线**：禁触 `Session/` 域与本 phase 既有 Library 文件的已冻结 API（只增
   不改——`LibraryQueries` 为新文件，`ExifSearchParser` 为新文件）；基准 fixture 落
   `/tmp` throwaway 禁入仓禁外置卷；Release 直启命令照抄附录不自创。

## Tasks

### T1 ExifSearchParser——识别矩阵 + AND 组合

- **read_first**：上列 1/3/6。
- **action**
  1. 新建 `LightamerCore/Sources/Library/ExifSearchParser.swift`（KD-1 全表）。
  2. 新建 `Tests/LightamerTests/ExifSearchParserTests.swift`（→ `tuist generate`）：
     - 识别矩阵逐条：`iso800`/`iso 800`/`ISO-800` → iso==800；`iso>1600` → gt；
       `iso:800-1600` → between；`f/2.8`/`f2.8`/`f 2.8` → aperture 容差 range；
       `35mm`/`35 mm` → focal==35；五种日期拼写 → 正确 `dateRange`（含 `2024` 全年、
       `2024-06` 全月边界）。
     - AND 组合：`sony iso800 f/2.8 2024-06` → structured 2 + fts 1（`sony` 折叠）
       + dateRange 1，四段并存。
     - 降级：`isoabc` → typed error；空串 → 空 plan（恒真）；尾随 `*` 前缀透传。
- **验收标准**
  - [ ] 识别矩阵 + 容差 range + 日期边界 + AND 组合 + typed 降级全绿。
  - [ ] 全套回归 `0 fail`。

### T2 LibraryQueries——分页/四分组/Activity/混查

- **read_first**：上列 4/6/7/8。
- **action**
  1. 新建 `LightamerCore/Sources/Library/LibraryQueries.swift`（KD-2/KD-3/KD-4）；
     `FilterSQL.FilterSortKey.orderBySQL(domain:)` 增 `.library` 臂（唯一既有文件
     触点，模板白名单内）。
  2. 新建 `Tests/LightamerTests/LibraryQueriesTests.swift`：
     - 分页：锚推进逐页不重不漏至尽 + NULL tail 段 + 逆序重走（CatalogIndexStore
       测试形状同款）；OFFSET 禁令无断言面（代码评审项）。
     - 四分组：种子 12 行（跨日期/相机/镜头/星级）各键计数精确 + Unknown 归类。
     - Activity：日序列精确 + `dayFilter(day:)` 投影后查询命中该日子集。
     - 混查：智能相册 Group ∩ `ftsTerms` ∩ structured 三腿 AND；**词法精确负例**：
       `iso800` 不命中 iso==8000 行（KD-6）。
     - 过滤态描述 struct 断言（字段级，非字符串）。
  3. 全套回归 0 fail。
- **验收标准**
  - [ ] keyset 逐页不重不漏 + NULL tail 全绿；四分组/Activity/混查/负例全绿。
  - [ ] `FilterSQL` 改动仅 `.library` 臂（diff 自检）；全套回归 `0 fail`。

### T3 性能硬门——harness + perf.md 落账

- **read_first**：上列 5（全文）+ `Tests/LightamerTests/CatalogBenchmarkHarness.swift`
  头注 Release 直启附录逐条。
- **action**
  1. 新建 `Tests/LightamerTests/LibraryBenchmarkHarness.swift`（KD-5；`LA_LIBRARY_BENCH`
     门 + skip 语义 + `BENCH|` 行 + 观察项组）。
  2. 跑三轮：Debug（test-direct.sh 直启）+ Release（附录命令直启）各计 p95；**Release
     热 p95 < 20ms 硬门判定**；未达标 → 回本 plan 修（索引/SQL 形状）不降门。
  3. 观察项：`LA_LIBRARY_BENCH_N=100000` 外推一组；ImportService 吞吐计时（≥100
     张/min 软记录）。
  4. 落盘 `.work/gsd/phases/m2-2-library-project/perf.md`（三轮数值表 + 门判定 +
     观察项 + 机器口径——`16-4-SUMMARY` perf 账同格式）。
  5. 全套回归 0 fail（harness 无门 skip）。
- **验收标准**
  - [ ] **Release 热 p95 < 20ms @ 20k 行硬门 PASS**（三轮对账在册，门值不降）。
  - [ ] 观察项数值 + perf.md 落账完整；无门常规跑 skip 零扰动。

### T4 收口

- **read_first**：本 plan AC 表。
- **action**：AC 机检 + 全套终跑；落盘 `M2-2-3-SUMMARY.md` + `M2-2-3-DECISIONS.md`
  （M2-3 数据接口面清单——四分组/Activity/搜索过滤态/keyset API 签名摘录，供 M2-3
  plan 直接引用）；`.work/GOAL-STATE.md` 续接点追加；`git diff --stat` 边界核对。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY（含 M2-3 接口摘录）/DECISIONS/GOAL-STATE 同批落盘。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 词法识别矩阵全绿（iso800/f2.8/35mm/日期多格式 → typed plan；AND 组合并存） | ExifSearchParserTests 表驱动 |
| 2 | 混查单语句三腿 AND（FilterSQL.library ∩ FTS MATCH ∩ keyset）；空腿省略 | LibraryQueriesTests |
| 3 | keyset 分页逐页不重不漏 + NULL tail；禁 OFFSET | 分页测试 + 评审 |
| 4 | 四分组计数精确 + Unknown 归类；Activity 日序列 + dayFilter 投影命中 | 分组/Activity 测试 |
| 5 | 词法精确：`iso800` 不命中 `iso8000`（查询面负例） | KD-6 断言 |
| 6 | 过滤态描述 = typed struct 字段断言 | 描述测试 |
| 7 | **Release 热 p95 < 20ms @ 2 万张**（≥12 形状 × 3 排序 × 2 深度，nearest-rank） | perf.md 三轮对账 |
| 8 | 观察项在账：10 万张外推 + 导入吞吐 ≥100 张/min 软记录 + 缩略图首屏挂账 M2-3 | perf.md |
| 9 | harness 常规跑（无 env 门）skip，全套 0 fail | test-direct.sh 双读 |
| 10 | diff 边界 == 申报文件集；既有 Library API 只增不改 | `git diff --stat` |

## 风险与边界

- **Release 直启 DYLD 复杂度**：照抄 CatalogBenchmarkHarness 附录（ad-hoc re-sign +
  app-embedded frameworks first + PackageFrameworks 路径）；自创路径 = 已知坑
  （stale-generation trap），禁。首次跑通耗时入 SUMMARY。
- **门不达标回退路径**：先查 SQL 形状（MATCH 子查询是否被 flatten / keyset 谓词是
  否吃上 `idx_images_capture`）→ `EXPLAIN QUERY PLAN` 归因入 DECISIONS；不降门、
  不加投机索引（加索引 = schema v2 迁移，非本 plan 权限）。
- **aperture 浮点等值**：容差 range 是 KD 裁决非取巧——REAL 物化列直等在 EXIF
  FNumber 舍入下失配（P2 语料同因）；单测含边界值。
- **`input/RAW` 供件不稳定**（gitignore/他机缺失）：交叉腿 skip 不违约；合成语料
  是门的本体。
- **缩略图首屏观察项**：网格壳在 M2-3，本 plan 只挂账不测（perf.md 占位行）。

## 提交约定

- T1 `feat(library): exif lexical search parser with typed plan`
- T2 `feat(library): inspector queries with keyset pages and aggregates`
- T3 `test(library): benchmark harness with release p95 gate`
- T4 `docs(m2-2): close out plan 3 query surface`
- 全英文 Conventional Commits；body 写 what+why + 同批 md 清单；不 push。
