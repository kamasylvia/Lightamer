# Plan 16-1 DECISIONS — 执行期决策清单

> 纪律：RESEARCH/CONTEXT 未覆盖细节标注执行期决策，不臆造。编号 D1 起（D 前缀避免与
> checker 归并编号混淆）。

## D1 CatalogPreferences 以 suite 名传递（UserDefaults 非 Sendable）

plan 拟「偏好读面落 UserDefaults 键 + 常量」。实现期 Swift 6 严格并发拒绝
`UserDefaults` 实例跨 actor 边界（sending data race）。定案：`CatalogPreferences`
与 `CatalogProjector` 的注入面全部改 **suite 名（String?，Sendable）**，UserDefaults
实例在消费点就地构建（actor 内部计算属性）。App 层从此零 UserDefaults 触碰（见 D2）。

## D2 App 钩子守卫下沉 projector 入口（双守卫改单守卫 + provider 分派）

plan T2⑦「守卫 false 时 project 直接返回」+ 验收「openAndSync 全流程零 `.lcat` 句柄」。
首版把守卫放 App 钩子读 `.standard` defaults——与测试注入 suite 冲突（读面不一致）。
定案：守卫**只**存在于 `CatalogProjector.project` 内部、且位于 `ensureOpen()` 之前
（「零句柄」的字面保持：守卫假时连文件都不创建）；App 侧 `catalogProjectorProvider`
闭包只负责 projector 分派（默认 = `SessionIndexController.sharedCatalogProjector`，
测试注入临时目录 factory）。disabled 路径的 detached Task 空跑成本 = 一次 bool 读，可忽略。

## D3 lindex 只读连接在 projector 内开合（签名偏离）

plan T2 拟 `project(sessionRoot:lindexHandle:)`——调用方传 handle。`SQLiteHandle` 非
Sendable，跨 actor 传参在 Swift 6 下非法。定案：签名改 `project(sessionRoot:)`，
只读连接（`SQLiteHandle.readOnlyFlags`——flags 常量入 SQLiteHandle，缝 c 的归属面，
避免 Catalog 侧 `import SQLite3` 破坏缝 c 审计）在 projector actor 内开合。plan 纪律
「投影不写 lindex」由只读 flags 强制。

## D4 DESC keyset seek 语义修正（research 形状缺陷，keyset suite 抓住）

research §1.1/plan T4 的 seek 形状 = row-value `(k, rel_path) < (?, ?)`（DESC 用 `<`）。
10k keyset suite 实证：**DESC 主键 + ASC tiebreak 下该形状同层回卷**——
`(k, a) < (k, c)` 为 true 而 `(k, a)` 已读，第二页重复第一页（probe F6 只验证了
plan 形状零 TEMP B-TREE，未验证混合方向页序语义）。定案：
- ASC（全 ASC 字典序）：保留 row-value `(k, rel_path) > (?, ?)`（NULL 排除语义不变）；
- DESC：展开式 `(k < ?) OR (k = ? AND rel_path > ?)`（NULL 在两臂均 NULL-false，尾段
  分工不变；`rel_path > ?` 与 tiebreak 的 ASC 方向一致）。
EXPLAIN 实证（新增常驻断言）：展开式仍走 `idx_cat_rt_desc`、零 TEMP B-TREE。
回注 planner：16-4 T1 终测沿用展开式形状。

## D5 idx_tags_image 新索引（首跑真缺陷修复，research F11 盲点）

harness 1M 首跑投影 148s/10 万行（Debug 与 Release **同值**→ 排除编译口径）。
根因 = 投影 R6 的 `DELETE FROM image_tags WHERE catalog_image_id = ?`：
tags 表聚簇 PK `(tag, catalog_image_id)` 只服务查询方向，删除方向全表扫，
N² 随 tags 增长劣化（F11 探针只测了等值查询方向 + 批量 GROUP BY，未测删除方向）。
定案：DDL 增加 `idx_tags_image ON image_tags(catalog_image_id)`
（`CREATE INDEX IF NOT EXISTS`，幂等）。裁定要点：
- 它**不属于**「catalog_images 7 索引」纪律面（那是镜像终表的排序/身份索引集）；
  属关联表辅助索引，与「不加过滤列索引」的 F10 裁决无冲突（F10 针对低选择性过滤
  列引诱 planner 的场景；此处是删除热路径 seek 必需）。
- 写放大代价：tags 行 INSERT ×2 索引（首跑数据 1.6M tags 行 fixture 生成仍 16s 量级）。
- EXISTS 查询方向仍走 PK（EXPLAIN 未变）。
- schema 测试冻结断言同步（image_tags 索引列表含 idx_tags_image）。
修复实证：Release full100k 148.3s → **1.926s**（预算 30s，余量 ~15×）；增量 10k
32.9s → **292ms**。回注 planner：16-4 T1 终测沿用本 DDL。

## D6 COUNT memo 键 = 翻译产物 whereClause 字符串

plan 拟「`[FilterPredicateGroup.hash: Int]` NSCache 形态」。hashValue 有碰撞面且
不可解释。定案：memo 键 = `FilterSQL.translateConjoining(groups, domain: .catalog)`
产出的 **whereClause 字符串**（NSString）——同一谓词组 → 同 SQL → 同计数，按构造
零碰撞；失效语义不变（invalidateCounts 清空）。「简单谓词」判定 =
`groups.count<=1 && (空 || 单 rule && .all && field != .keywords)`——简单类**每次
现算不进 memo**（§1.4「请求时现算」字面；1M 实测 64-76ms Debug / Release 更低，
亚 100ms 角标预算内），组合/标签类走 memo（首跑实测命中 0.04ms）。

## D7 page size = 60（`CatalogIndexStore.defaultPageSize`）

research §1.5 口径「每形状 30 页 × 60 行」的 60 直接钉为 API 缺省；UI 数据源
（16-2）可覆写。

## D8 catalog v1 排序键白名单 = captureDate / rating / filename；不支持键 typed throw

`iso`/`focal_length` 有镜像列但无表达式索引；`scan_epoch` 连列都不镜像。排序键缺
索引 = TEMP B-TREE 慢路径。定案：`catalogOrderColumn` 对三种 v1 支持键返回列名，
其余 **typed error**（`SessionIndexError.execFailed`，message 说明「no catalog
ordering index (v1 pin)」）——拒绝静默慢路径。`queryNullTail` 同理仅
captureDate/rating（filename 恒非 NULL，无尾段）。若 v1.x 要放开 iso/focal：DDL
加对应表达式索引 + 白名单扩项（additive）。

## D9 mmap_size 不入基线（plan 预注）

F13 <2% 增益，可选旋钮不入 `CatalogIndexSchema.apply`；harness 若未来要测，经
独立 pragma 语句（不进 DDL 冻结面）。

## D10 keywords catalog 域 `in`/`eq` 的形状（plan 说 contains/eq 两 op）

plan T3 落点 a 写「contains/eq 两 op」。`in` 若留在 session 四条款形状会破坏
「catalog 域 tags 恒走物化表」的分派完整性。定案：`in` = 每 tag 一个 EXISTS OR
（bind 顺序 = tags 数组序）；`eq` = 同 contains 的单 EXISTS（物化后完整路径本身
是一行 tag；与 session eq「整列精确」的语义差是 research §6 超集裁决的既有口径，
非新偏差）。`empty`/`notEmpty` 两域同形状（消费镜像 keywords 列的 NULL/'' 两态）。
测试快照钉死全部四 op。

## D11 filename/dir 之外的 text contains 保持 contains（慢路径注记）

plan 降级清单只点名 filename/dir（RQ-16-16①）。note/cameraMake/cameraModel/
lensModel 的 contains 在 catalog 域保持 session 形状（`+i.` 前缀版）——EXIF 文本
列的 contains 是低频 MCP/面板路径；若 SC#3 终测超门再议 FTS5（deferred 已留档）。

## D12 scopeClause 保留 domain 参数（未消费）

plan 签名 `scopeClause(domain:sessionID:categoryID:collectionID:)`。v1 内锚点谓词
只对 catalog 库有意义，domain 参数当前无分支价值——按 plan 签名保留（缺省
`.catalog`，未消费），作为 v2「域随模式」扩展位的形态占位，文档注明。

## D13 空 token 防御（标签前缀展开的唯一细化）

plan §6 伪码 `materialized.split("|")` 未指明空子串策略。实现取
`omittingEmptySubsequences: true`（`"A||B"` 不产出空 tag 行——XMP 导入的空段
防御）。其余逐字忠实（见 D14 复核）。

## D14 标签物化前缀展开对 research §6 原文的忠实性复核（checker R1 点名）

research §6 裁决原文（16-RESEARCH.md:214）：

> 「投影按串域前缀展开定义（split `|` → 全部前缀行）——对平铺标签（绝大多数）
> 语义精确；对层级导入标签 = 与 session 域四条款同源的超集语义……」
> 「用例集须覆盖：平铺多标签、层级标签、混合、空串/NULL 两态」

plan T2④ 伪码：

> `nil -> ∅` / `"" -> ∅` / `tokens = materialized.split("|")` /
> `rows = Set(tokens)` / `rows += { tokens[0..<i].joined("|") for i in
> 1...tokens.count }`

实现（`CatalogProjector.tagRows(fromMaterialized:)`）逐条对照：

| 伪码行 | 实现 | 忠实性 |
|---|---|---|
| `nil -> ∅` | `guard let … else { return [] }` | ✓ |
| `"" -> ∅` | `!materialized.isEmpty` 早退 | ✓（两态区分留在镜像 keywords 列——注释明示） |
| `tokens = split("|")` | `split(separator:"|", omittingEmptySubsequences: true)` | ✓（唯一细化 = 空 token 防御，D13） |
| `rows = Set(tokens)` | `var rows = Set(tokens)` | ✓ |
| `rows += {tokens[0..<i].joined for i in 1...count}` | `for i in 1...tokens.count { rows.insert(tokens[0..<i].joined(separator:"\|")) }` | ✓（区间含 1…count 与伪码一致：单 token 串退化为自身） |

**golden 对照**：`"A|B|C"` → `{A, B, C, A|B, A|B|C}`（research §6 原例；实现输出
一致）；五形态测试（NULL/''/`X|Y`/`A|B|C`/`A|B|C|X`）覆盖 research 要求的用例集；
跨域方向性断言（catalog ⊆ session，`B|C` 中段路径 session 命中而 catalog 无行为
by-design）按 research §6「同源超集」裁决替代 CONTEXT D-3 的等值对照——即 checker
M2 的登记口径。**结论：实现忠实于 research §6 原文；对 CONTEXT D-3 的 3 行 golden
构成声明中的超集（{Nature, Nature\|Flower, Nature\|Flower\|Rose} ⊂ 实现行集），无
私自解读。**

## D15 Debug/Release 分栏的达成方式

SC#3 口径要求 Debug/Release 分栏。Debug = test-direct.sh 常规路径。Release =
`xcodebuild build-for-testing -configuration Release` + ad-hoc 重签 Release 容器
（Team ID 校验挡 DYLD 注入）+ 同款直启命令（PackageFrameworks 补 DYLD 路径）。
重签只作用于 DerivedData 即弃产物，源码/正式签名零影响。Release 分栏数字入
perf.md（矩阵最差 p95 0.17ms 级、投影 1.926s/292ms/5.5ms）。SC#3 终测（16-4 T1）
复用本流程。
