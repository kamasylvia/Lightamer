# M2-2-3 DECISIONS — 查询面执行决策

> Plan M2-2-3（2026-09-29）。已定裁决（OQ-7/9/11、KD-1..KD-6）未重开；本文件只记
> 执行中的自由裁量与归因。

## D1 — aperture 容差带边界做 4 位小数规整

KD-1 裁的 ±0.05 容差带在 IEEE 下有表示噪声（`2.8 + 0.05 = 2.8499999999999996`）。
parser 把带边界规整到 4 位小数（`(v*10000).rounded()/10000`），使绑定值就是字面量
`2.85`/`2.75`——SQL 端谓词可复现、可读，Equatable 测试精确匹配。规整只作用于容差
带边界，不触碰用户值本身。

## D2 — StructuredTerm 约束面带 gte/lte 完整族

plan 识别矩阵只点名 `iso>800`（gt）与 `iso:800-1600`（between）；实现补全
`>=`/`<=` → `greaterThanOrEqual`/`lessThanOrEqual`（翻译面直映 FilterOp `.gte`/
`.lte`），拒绝用 ±inf between 伪装——`FilterValue.doubleRange` 语义诚实，后续
M2-3 对话框可直接把范围选择器映射到 typed 约束。识别矩阵本身未扩（`iso:800` 冒号
等值仍按 plan 拒绝）。

## D3 — `iso…` 前缀 token 的严格错误面（含真实词的取舍）

KD-1 钉 `isoabc` → typed error。执行把「以 `iso` 开头但语法不匹配」的**一切**
token 都按同规则处理（含 `isolation` 这类真实词——它会被当作失败的 iso 查询报
typed error，而非静默降级 FTS）。理由：静默降级必然零命中（折叠词表里 iso 家族
是结构化变体），错误呈现是更有用的反馈；代价是词形巧合的 FTS 词不可查——
M2-3 对话框呈现错误后用户改写即可。同逻辑覆盖 `f`/`f/2.8.5`（数字续接的失败
aperture）；字母续接（`fstop`）不算 aperture 前缀，照常降 FTS。

## D4 — 10 万张观察项的排序腿触顶归因（挂账，非门）

`isoRange|dateDESC|deep` 在 20k = 15.66ms（门内），100k 外推 = 138ms（超线性）。
EXPLAIN QUERY PLAN（冻结 DDL 复现）：`ORDER BY (capture_date IS NULL), capture_date
DESC, image_path ASC` 的 image_path tiebreaker 与 `idx_images_capture(capture_date,
id)` 不匹配（索引第二列是 id）→ TEMP B-TREE 全排序；DESC 的 OR 展开 seek 进一步
放弃索引范围扫。**这是 schema 形状问题，不是查询面问题**：catalog 域同题的解是
表达式索引 `(k IS NULL, k DESC, rel_path)`（16-1 F6），library 域镜像修法 =
`images(capture_date IS NULL, capture_date DESC, image_path)`（或改 tiebreaker 为
id 的变体）——**加索引 = schema v2 迁移，本 plan 无权限**（OQ-9/纪律 5 红线）。
词法/FTS 腿 100k 仍 5-6ms，无触顶。若 10 万张级成为常态需求，裁项随 schema v2
一并走（plan 红线「不降门、不加投机索引」已守）。

## D5 — SmartAlbumEvaluation 追加 `.library` case + evaluate 默认参数

`.library` 臂真实现需要 (a) 返回载体 (b) 查询面注入。(a) = 枚举追加
`case library(imageIDs: [Int64])`（库域稳定身份 = rowid PK，与 session 的 rel-path、
catalog 的复合身份同级诚实；纯增量，无既有 switch 消费者——grep 证实）；(b) =
`libraryQueries: LibraryQueries? = nil` 默认参数（三个既有调用点零改动；
`.session`/`.catalog` 分支字节不变）。`LibraryFilterDomainTests` 的
`testEvaluateLibraryIsTheTypedPlaceholder` **零改动仍绿**——它断言的 nil-注入
typed 拒绝面在新实现下语义不变（该测试名的历史「placeholder」措辞由本文件的缝
闭环记录解释）。

## D6 — evaluate 全集走 id-keyset walk（非 captureDate 排序键）

智能相册成员集收集用 `WHERE <filter> AND i.id > ? ORDER BY i.id LIMIT n` 步进而
非 KD-3 的排序键分页：全集收集要求「不重不漏且无序敏感」，rowid PK 恒非 NULL、
无 tie tier、无 NULL 尾段——是唯一对所有谓词形状都无洞的 sweep 键。与 catalog 臂
（filename 排序分页，其列恒非 NULL）同构的「能一次走完」语义；测试钉
evaluate ≡ memberIDs ≡ 直查同集合。

## D7 — dayFilter 的整日界 = UTC 整秒闭合

Activity 点击折叠：`[day 00:00:00Z, day 23:59:59Z]`（start+86399）。与
ExifSearchParser 日期族同一闭合约定——EXIF DateTimeOriginal 秒级精度下精确；
`strftime('%Y-%m-%d', …, 'unixepoch')` 的 UTC 分桶与 dayFilter 的 UTC 日界一致
（跨时区显示转换归 M2-3 渲染层）。

## D8 — 100k 外推与吞吐跑在 Release 列

观察项（非门）只跑 Release 单轮（100k）与两列吞吐（Debug/Release 各一次以内嵌于
三轮 harness 类运行）；Debug 100k 不跑——观察项不承担判据职责，省一轮 ~5 分钟
fixture+矩阵。三轮主门（Debug+Release 各三）全跑齐。

## D9 — `appendFilterLeg` 尾随空格归一

SELECT 头拼接点归一（`if !sql.hasSuffix(" ") { sql += " " }`）而非逐模板补空格：
多行字符串字面量的闭引号缩进剥除会让裸 `FROM images i` 丢尾随空白（实测
`images iWHERE` 语法错一次）；归一在唯一拼接点收口，后续聚合模板不会再踩。
