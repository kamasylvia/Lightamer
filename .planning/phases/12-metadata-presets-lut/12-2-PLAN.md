---
phase: 12
plan: "12-2"
title: "过滤/排序/智能相册：FilterPredicateGroup Codable 谓词模型（智能相册持久化面与过滤栏临时面同型）+ FilterSQL 单一翻译层（四联式祖先谓词修正 D-3 / bind-only 注入面关闭 / 排序白名单）+ query 消费面 + grid 工具条 chips/Quick Filter/排序菜单 + SmartAlbums 存储/求值/侧栏"
wave: 2
depends_on: ["12-1"]
autonomous: true
requirements: [META-05, META-06]
files_modified:
  - LightamerCore/Sources/Session/FilterPredicate.swift            # 新建：FilterPredicateGroup/Rule/Field/Op/Value（tagged union Codable）
  - LightamerCore/Sources/Session/FilterSQL.swift                  # 新建：translate(group:) 单一翻译层 + 排序键白名单枚举
  - LightamerCore/Sources/Session/SessionIndexStore.swift          # query 消费面（谓词组 + 排序 → 行集）
  - LightamerCore/Sources/Session/SmartAlbumStore.swift            # 新建：SmartAlbums/*.json 存储 + 启动重扫自愈
  - App/Sources/Lightamer/UI/ContentView.swift                     # grid 工具条过滤栏落位（BrowserMode 三态旁）
  - App/Sources/Lightamer/UI/SessionBrowserView.swift              # chips 行 + Quick Filter 搜索框 + 排序菜单
  - App/Sources/Lightamer/State/SessionState.swift                 # 过滤态/排序态/Quick Filter 态 + 重查询编排
  - App/Sources/Lightamer/UI/InspectorView.swift                   # 侧栏智能相册入口（既有侧栏三段结构内落位）
  - Tests/LightamerTests/FilterPredicateTests.swift                # 新建：模型 round-trip + golden
  - Tests/LightamerTests/FilterSQLTests.swift                      # 新建：翻译层 SQL/binds 快照 + fixture 精确行集（L020）
  - Tests/LightamerTests/SmartAlbumStoreTests.swift                # 新建：存储 round-trip/自愈/求值
  - .planning/phases/12-metadata-presets-lut/12-2-SUMMARY.md
  - .planning/phases/12-metadata-presets-lut/12-2-DECISIONS.md
  - TODO.md                                                        # 12-2 勾选
  - LESSONS.md                                                     # 如踩坑
---

# Plan 12-2 — 过滤/排序/智能相册（W2，与 12-3 并行，零交集）

> 背景：META-05/META-06 一套代码两个消费面（D-12-CONTEXT-7）：谓词模型 + SQL 翻译层是
> **单一实现**——过滤栏（临时谓词组）与智能相册（持久化谓词组）同构，Phase 14 MCP 筛选
> 工具直接消费同一翻译层（GUI/MCP 同源前置）。关键技术修正（F3，**按 RESEARCH 为准，
> 偏离 CONTEXT D-3 原文形态**）：祖先过滤谓词用**四联式**（`=` / `x|%` / `%|x|%` / `%|x`），
> 裸 `LIKE '%T%'` 会误命中 `NatureHolics` 类子串兄弟标签——CONTEXT D-3 的谓词形态建议
> 被 research 修正，本 plan 按 research 落地（10k 行实测 0.95ms，与裸 LIKE 同量级）。
> 求值域 v1 = 当前打开会话的索引 DB（D-12-CONTEXT-4；跨会话聚合 defer v2）。

## read_first

1. `.planning/phases/12-metadata-presets-lut/12-RESEARCH.md` §3（层级关键字 + 四联式 + 性能实测）、§4（谓词组 schema/翻译层/Quick Filter/智能相册）、§7 T4/T5
2. `.planning/phases/12-metadata-presets-lut/12-CONTEXT.md` D-12-CONTEXT-7（过滤 UI 落位）、D-4（智能相册求值域）、验证红线节（L020 内容级断言）
3. `LightamerCore/Sources/Session/SessionIndexSchema.swift`（v2 34 列——Field 枚举的列映射底表；`orphan_sidecar` 基线谓词）
4. `LightamerCore/Sources/Session/SessionIndexStore.swift`（读事务模式——query 面落位；`SQLiteHandle` prepare/bind/step 面）
5. `LightamerCore/Sources/Session/SessionTreeScanner.swift` + `SessionState.swift`（渐进 ingest 与重查询的编排关系——过滤态变更触发 query 重跑的落点）
6. `App/Sources/Lightamer/UI/ContentView.swift:37` 附近（BrowserMode 三态 segmented——过滤栏同行/相邻落位）
7. `LightamerIOP/Sources/Yiyin/YiyinFontStore.swift`（app 级目录存储三拆模式：会话注册/typed 错误/启动重扫自愈——SmartAlbumStore 范本）
8. `dt 对标正本`：`src/common/collection.h:74-136`（属性枚举对齐面）/ `collection.c:1355`（谓词→SQL 同构参考）
9. `LESSONS.md` L009（tmp 原子晋升禁 /tmp 跨卷）/L020（内容级断言）/L025（zh catalog）
10. `AGENTS.md`（Phase 执行模型 + 暂停机制）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建；单测 = `Scripts/test-direct.sh '<Class>'`（**判据 = Executed 行 + failures 行，非宿主退出态**；Executed 0 = 失败防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**；零新 SPM 依赖；无 /tmp 产物入工作区；fixture 禁 UNITEK 盘（L009）。
- **T4/T5 为 GUI 任务：需解锁控制台（Manual-Only 候补）**。
- **SQL 红线**：参数全 bind，**零字符串拼接值**（注入面关闭）；`ORDER BY` 键 = 白名单枚举直译列名（不吃 bind）；基线谓词 `orphan_sidecar = 0` 恒附加。
- **断言红线（L020）**：翻译层与 query 面的验收 = fixture 库**精确行集**，禁「返回非空即过」。
- RESEARCH 未覆盖细节（UI chips 视觉形态/排序持久化键名/Quick Filter 与 chips 叠加顺序）标注**执行期决策**入 `12-2-DECISIONS.md`。

## Tasks

### T1 谓词模型 FilterPredicateGroup（Codable）

- **action**
  1. `FilterPredicate.swift`（新建，Core/Session）：RESEARCH §4.1 schema verbatim——`FilterPredicateGroup { schemaVersion = 1, match: Match = .all（.all=AND/.any=OR，v1 不做嵌套组）, rules: [Rule] }`；`Rule { field: Field, op: Op, value: Value }`。
  2. `Field` 枚举全集（v2 列面对齐）：`rating/colorLabel/keywords/flag/note/cameraMake/cameraModel/lensModel/iso/focalLength/aperture/exposure/captureDate/hasEdits/filename/dir`；`Op`：`eq/neq/gt/gte/lt/lte/between/in/contains/startsWith/empty/notEmpty`；`Value` = tagged union Codable（String|Int|Double|[String]|闭区间——`captureDate` 值 = epoch Double，UI 日期选择器折叠）。
  3. 字段×操作符合法性校验（数值字段禁 contains、文本字段禁 gte 等——typed error）；Codable round-trip + sortedKeys 字节 golden（智能相册文件体与过滤栏 state 同型序列化）。
- **证据**：`FilterPredicateTests`——round-trip/golden/非法字段×操作符组合 typed 拒绝向量表/缺字段降级（未知 field → typed 错误，向前兼容面注记）。

### T2 FilterSQL 单一翻译层（四联式 + bind-only）

- **action**
  1. `FilterSQL.swift`（新建）：`translate(group:) -> (sql: String, binds: [Bind])`——规则 → 括号化条件片段；`.all` = AND 连接 / `.any` = OR；空组 = `1=1`；**参数全 bind 零拼接**。
  2. **关键字祖先匹配 = 四联式**（F3 修正正本，参数绑定形态）：
     `(keywords = ?N OR keywords LIKE ?N||'|%' OR keywords LIKE '%|'||?N||'|%' OR keywords LIKE '%|'||?N)`
     ——语义 = dt「打子隐含父」同义重言；**CONTEXT D-3 原文裸 `LIKE '%T%'` 形态按 research 修正弃用**（`NatureHolics` 误伤对照组进测试）。
  3. 文本字段（filename/dir/note）`contains` = `LIKE '%'||?||'%'`（LIKE 默认 ASCII 不区分大小写，够用；zh 无大小写概念——文档化）；数值区间 = `BETWEEN ? AND ?`；`empty/notEmpty` = `IS NULL / IS NOT NULL` + 空串语义（12-1 EXIF 哨兵 `''` 与 keywords 空串联动语义入 DECISIONS）。
  4. 排序键白名单枚举 `FilterSort { filename/rating/capture_date/iso/focal_length/scan_epoch } × asc/desc` → 列名直译（UserDefaults 持久化键 = 执行期决策）；基线谓词 `orphan_sidecar = 0` 恒附加。
- **证据**：`FilterSQLTests`——每字段×操作符 → SQL 字符串 + binds **快照断言** + fixture 库精确行集：四联式祖先命中集/子标签命中/`NatureHolics` 对照组（裸 substring 命中而四联式不命中）/组合 AND/`.any` OR/空值行排除/含 `|` 与 `%` `_` 通配符转义注入向量（bind 后字面量语义）。

### T3 SessionIndexStore.query 消费面

- **action**
  1. `SessionIndexStore` 新增读面：`query(rootPath:group:sort:limit:) -> [行]`——内部跑 `FilterSQL.translate` 产物（读事务，与增量同步/回填写事务经既有 SQLiteHandle 串行化共存）；返回行类型 = 既有 grid 行模型复用（零新行类型，执行期决策若需扩展列集）。
  2. 关键词四联式在 query 面的绑定参数复用（同 bind 出现多次 = 多占位展开，bind 数组索引对齐）。
  3. 基线回归：query 与 9-2 reconcile/watch/9-4 批量管线的并发共存（读锁语义既有面，零新锁）。
- **证据**：`FilterSQLTests` query 段——fixture 库建行 → query 精确行集（与翻译层 SQL 快照互证）/ 组合排序 asc/desc / limit 分页 / 与写入并发 smoke。

### T4 过滤栏 UI + Quick Filter + 排序菜单（GUI，需解锁控制台（Manual-Only 候补））

- **action**
  1. grid 工具条过滤栏（`ContentView.swift` BrowserMode 三态 segmented 同行/相邻行落位）：chips 型谓词（评分≥N / 色标 / 关键字 / 相机 / 镜头 / 日期区间 / ISO 区间 / 焦距区间 / flag / has_edits），可叠加 AND；chip 单击切换/长按删除（交互形态执行期决策）；激活 chips 从 `FilterPredicateGroup` 双向投影。
  2. Quick Filter：工具条行内搜索框——`filename OR keywords 四联式` 任一命中（单条 contains 组，纯翻译层消费无新 SQL 面）；`/` 聚焦、Esc 清除；快捷 chips「星级≥3」「pick」= 预填谓词组。
  3. 排序菜单：六键 × asc/desc（白名单枚举），选择持久化 UserDefaults。
  4. `SessionState` 过滤态/排序态/Quick Filter 态 + 变更触发重查询编排（防抖执行期决策）；zh catalog 同批（L025）；`|` 关键词录入拒绝 typed error 复用 12-1 校验。
- **证据**：GUI 走查记录（chips 叠加过滤即时生效 / Quick Filter `/`+Esc / 排序持久化重开保持 / 空结果态展示）；Manual-Only 未尽项登记；zh 首屏 smoke。

### T5 SmartAlbums：存储 + 求值 + 侧栏入口（GUI）

- **action**
  1. `SmartAlbumStore.swift`（新建，Core/Session）：存储 = `~/Library/Application Support/Lightamer/SmartAlbums/*.json`（一规则一文件，文件体 = `FilterPredicateGroup` + 名称；sortedKeys + 同目录 tmp 原子晋升——L009 禁 /tmp 跨卷）；启动重扫自愈（YiyinFontStore 三拆模式：会话注册/typed 错误/损坏文件跳过不崩）。
  2. 求值：点入智能相册 → 当前会话 `session.lindex` 上跑翻译层（T3 query 复用）——**规则随 app、结果随会话**（D-12-CONTEXT-4 解耦正本）；空会话/未开会话态展示语义入 DECISIONS。
  3. 侧栏入口（`InspectorView.swift` 侧栏三段结构内）：规则列表 + 新建（谓词编辑复用 T4 chips 组装）/ 重命名 / 删除。
- **证据**：`SmartAlbumStoreTests`——文件 round-trip/损坏文件跳过自愈/求值 = fixture 库精确行集（L020）；GUI 走查（新建规则→点入求值→切会话结果随变）；Manual-Only 登记。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1260/6skip/0fail** + 本 plan 新增，0 fail）；TODO.md 12-2 勾选；`12-2-SUMMARY.md` + `12-2-DECISIONS.md`（UI 形态/持久化键名/空值语义/防抖参数）；新教训候选评估入 LESSONS。
- **证据**：测试计数（0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 谓词模型 | round-trip/golden/非法组合 typed 拒绝 | `Scripts/test-direct.sh 'FilterPredicateTests'` |
| 翻译层 | SQL/binds 快照 + fixture 精确行集 + NatureHolics 对照 | `Scripts/test-direct.sh 'FilterSQLTests'` |
| query 面 | fixture 行集 + 排序/limit + 并发 smoke | `Scripts/test-direct.sh 'FilterSQLTests'`（query 段） |
| SmartAlbums | 存储 round-trip/自愈/求值精确行集 | `Scripts/test-direct.sh 'SmartAlbumStoreTests'` |
| GUI | chips/Quick Filter/排序/侧栏走查 + zh | 手动走查记录 + Manual-Only 登记 |
| 回归 | 全 suite 0 fail（基线 1260+新增） | `Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] 谓词模型：字段/操作符全集对齐 v2 列面 + tagged union Value + 合法性校验 typed 错误 + sortedKeys golden（智能相册文件体与过滤栏同型）
- [ ] 翻译层单实现：**四联式祖先谓词**（research 修正 D-3，`NatureHolics` 对照组测试钉死）+ bind-only 零拼接 + 排序白名单直译 + `orphan_sidecar = 0` 恒附加；每字段×操作符快照断言
- [ ] query 消费面：fixture 精确行集（L020）+ 与既有写事务共存 smoke
- [ ] 过滤栏 chips + Quick Filter（`/` 聚焦/Esc 清除/快捷 chips）+ 排序菜单持久化；zh catalog（L025）
- [ ] SmartAlbums：app 级存储 tmp 原子晋升（L009）+ 启动重扫自愈 + 求值域 = 当前会话（规则随 app/结果随会话）
- [ ] 全 suite 0 fail；每任务独立提交 + 边界查 config 开关；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS 落盘
