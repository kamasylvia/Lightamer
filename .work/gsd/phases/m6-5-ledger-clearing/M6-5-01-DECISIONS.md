# M6-5-01 DECISIONS（挂账清算批执行批裁定记录，2026-10-16）

> 执行批 = ZCode executor（夜间全自动授权链，先例 D-07-3-T5-1）。
> plan 正本 = `M6-5-01-PLAN.md`（修订版，HEAD `2f88907a`+`62a7ca30` 起跑）。
> 本文件只记裁定与执行期发现；逐任务记账与挂账终局表见 SUMMARY。

## 1. 批内 commit 链

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `c749ee00` | RasterEditFaceTests restore+undo 双写腿 tempFixtureCopy 化 + `loadRaster(at:)` 孪生 + 头注 M4-1 #6 终局注记（含 E-1 归因勘误） |
| T2 | `bd81f859` | SessionBatchApplier 既有档臂 12 字段捕获（CarriedDocumentState）+ 构造点 12 参 + 4 回归法 + M6-2 VALIDATION 挂账 #2 对表补记 |
| T3 | `71dbd371` | McpServerController 两处 19→20 + 伴文算术 5→6 editing + 两测试文件同族注释顺带 |
| T4 | `76729922` | ExportGainMapTests +1 行序方向性断言法 |
| T5 | `c651bb51` | ExportRecipe 门③ + ExportRenderer capture 装配点 API-consumer 契约注记（纯注释） |
| T6 | `0ebdd3c1` | zh-audit V16 断言 5 + 三活体键尾块纯插入 + AGENTS M6-5 节登记 |
| T7 | （不入 git） | `.work/gui-acceptance/m6-5/MANIFEST.md` 汇编 18 GUI 行 + 1 perf 行 |
| T8 | `9bdeb467` | V2-PROPOSAL「七、」九项登记 |
| T9 | （收口 commit） | SUMMARY/DECISIONS/AGENTS 终值/TODO/GOAL-STATE |

## 2. 执行期裁定

### D-1（T1）E-1 归因勘误落位

- undo 法写腿链 = `recordDrtChange`(:209) + `undo()`(:213) 双调度面，undo 的
  persistence 重调度（EditorState → PipeCoordinator `drtRecordDidChange`）的
  2s debounce 写在测试返回后落地 → 测试级 defer 确定性输给迟到 write-behind。
- M5-1「restore 法 defer 输给迟到 write-behind」归因错位已照 plan E-1 修正
  （头注 + 本节）；M6-2 VALIDATION :60 排除项（undo 到顶仍写 carrier）为
  独立引证。
- 修法 = 双法同 `tempFixtureCopy`（DepthMaskEditingTests verbatim 同款 helper
  + UUID tempDirectory）；restore 法入口前清/defer 改指 tmp sidecarURL + repo
  侧一行防御性 `removeItem`（存量孤儿不毒轮）；undo 法断言全在 carrier 面，
  换 tmp 副本零语义影响（:216-222 亲读符合 CHECKER 2.1 判定）。

### D-2（T2）「nil 档不落键」断言形态按线格式事实订正

- plan 原文「rating…nil 档不落键」按 wire 字面不可达：`LightamerSidecar`
  encode 面对五元数据字段是**恒写形态**（nil = 写 `null`，byte golden 锁定
  的 plan-pinned constant-write form）——「键缺席」断言会假红。
- 裁定 = 保真断言落在 **typed 层**（`composed.document.rating == nil`），
  注记申报线格式事实；正测臂（rating=3 逐值保真 + keywords 全路径逐元素
  保真）不受影响。

### D-3（T4）断言形式 = 单向方向断言（预案一），取向经实测定格

- 非对称构造：base 上半场中灰(sRGB 128)/下半场高光(sRGB 250) × HDR 纹理
  （**记忆行 0 = 图顶**，管线 producer 约定）k=1/k=2 两档增益。
- 方向断言四重：①GainMapMin/Max ≈ 1.0/2.0（取向无关锚，±0.4 带）②top-down
  读回帧位图带均值 top<64 / bottom>192 ③带均值差 >128 ④经 min/max 锚映射
  的语义增益逐带 ≈ kTop/kBottom（±0.45）。掉 down-mirror 的反置面
  （≈4.15/-1.15）全数触红。
- aux 读回帧取向假定 = **top-down**（读回行 0 = 图顶）——首跑即绿，取向
  假定与实现一致（如实现变向，②③④反触红，门语义不损）。
- M-2 计数对账：HEAD 实测 25 法（`func test` grep 亲点）+1 = 26，与 plan
  订正一致；CONTEXT D2「24 法」= 计数漂移，不另立案。

### D-4（T6）三活体键实况 = 裸键值承载格式串

- 目录现状：三个裸静态键（`edr_headroom_label` 等）**值内含 `%@` 占位串**
  （en/zh 双语已在）——运行时查 `K %@` 变体键不命中 → 回退裸键观感
  （M2-9 F-2 家族活体）；bare 键此前经 interp 前缀族（rule c `== P`）覆盖
  故四断言全绿，V16 断言 5 才暴露。
- 清偿 = 变体键（`K %@`）尾块纯插入，en+zh 值与既有裸键**同文**（措辞对齐
  相邻键族义务的最稳满足形）；裸键留目录（仍被 rule c 覆盖，非孤儿）。
- 分诊 transcript：V16 首跑 30 调用点/30 键 = 27 PRESENT + 3 ABSENT
  （与 fixer 预扫逐键一致：`toast_import_partial`/`toast_hdr_merge_failed`/
  `toast_hdr_merge_done` 三枚 1c 续行键全 PRESENT）；清偿后 30 全 PRESENT。
  存档 = `evidence/t6-v16-postclearing-report.txt`。

### D-5（T8）触发条款换行断裂 → amend 修复

- 首版 heredoc 将「首个真实 iop 语义分叉/bump 批触发时四件同批」断行
  （「语义/分叉」跨行），M-4 同文机检 grep 零命中——修正为整句单行后
  `--amend`（终 commit = `9bdeb467`）；同文机检 = 与
  `M6-2-VALIDATION.md` :104 grep 双侧命中 1:1。

## 3. 执行期事故登记（流程缺陷，LESSONS 候选）

### I-1 陈旧二进制假绿——test-direct.sh 前置构建步漏执行

- **经过**：T1/T2 首轮定向跑（App 7/0/0、Sessions 13/0/0）在**未重建的
  DerivedData 产物**上执行——Sessions 13 = 旧 13 法（新 +4 未入二进制）；
  T4 方法级过滤 `ExportGainMapTests/testGainMapRowOrder…` 返 0/0/0 才暴露。
- **根因**：`test-direct.sh` 头注「前提：Debug 产物已由
  `xcodebuild build-for-testing` 生成」是**前置条件非内置步**；执行批照
  plan 的单测标准命令直跑，漏了构建前置。
- **处置**：`caffeinate -dis xcodebuild build-for-testing`（exit 0）后三
  bundle 全部复跑——App 7/0/0（改后双法真跑）+ Sessions 17/0/0（9 旧+4 新）
  + Export 26/0/0（25 旧+1 新）+ RasterRoundTripTests 3/0/0 复验；孤儿复扫
  零命中在**新二进制**轮后补做（sleep 3s 过 debounce 窗）。
- **LESSONS 候选**（翻账批落）：「test-direct.sh 不含构建；执行批的测试
  命令序列 = build-for-testing → test-direct.sh，漏前者 = 陈旧二进制假绿
  （类计数/方法过滤 0/0/0 是暴露信号）」。
- **污染面评估**：首轮假绿未入任何 commit/申报数字（定向轮数字以复跑轮为
  准）；T9 全套轮在本 I-1 处置后的二进制上执行。

## 4. plan 偏差清单（对 plan 正本）

| # | 偏差 | 定性 | 处置 |
|---|---|---|---|
| 1 | T2 「nil 档不落键」→ typed-nil 断言（线格式恒写 null） | 小偏差 | D-2，就地处理 |
| 2 | T4 aux 读回帧取向需执行期定格（plan 已授权「断言形式执行时择稳」） | plan 内授权 | D-3 |
| 3 | T6 三活体键裸键值即格式串（plan 未记载此实况；清偿路线 = plan 指定路线不变） | 小偏差 | D-4 |
| 4 | T8 触发条款首版换行断裂（M-4 机检红）→ amend | 执行失误自纠 | D-5 |
| 5 | I-1 陈旧二进制（流程缺陷，非 plan 缺陷） | 事故 | §3，复跑消除 |
| 6 | T7 汇编行数 18+1（plan「~17 行」约数；逐行可对 CONTEXT §6 明细） | 约数内 | SUMMARY 对表 |

结构性偏差：零（无停手上报项）。
