# M6-5-01 ACCEPTANCE（第一路独立验收，2026-10-15）

> 验收身份 = zcode 独立 subagent（零共享推理链，不轻信执行方报告，逐条实测）。
> 输入 = 修订版 PLAN + CONTEXT + CHECKER + SUMMARY + DECISIONS + 执行链
> `c749ee00..7c0d2bbb`（8 commits）。夜间全自动授权链（D-07-3-T5-1），晨审可推翻。
> **结论头：PASS / 0 error + 1 minor（报告完整性；两观察项随附）**。
> 全套独立复跑 **TOTAL 3848/24/0**（exit 0 + 0 MEMFAIL + 七 bundle 全 8G 门内）
> 与执行方申报逐值一致；六清偿项亲测全过；40 项终局表对账闭合；I-1 实质处置
> 成立但「假绿未入任何 commit」申报被 commit message 证据证伪（minor-1）。

---

## 一、全套独立复跑（亲跑，非转抄）

前置：`caffeinate -dis xcodebuild build-for-testing`（exit 0 / TEST BUILD
SUCCEEDED；I-1 教训先确认新鲜度——发现执行方 T9 轮的 app-bundle
Localizable.strings 为 T6 插键前产物，见 §六观察项 O-3）。

```
BUNDLE|IOP|686/1/0|peakRSS=7676MB|421s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=7004MB|763s|sampling=time
BUNDLE|Layers|494/4/0|peakRSS=1161MB|161s|sampling=time
BUNDLE|Library|729/4/0|peakRSS=621MB|78s|sampling=time
BUNDLE|Sessions|284/4/0|peakRSS=1628MB|70s|sampling=time
BUNDLE|Export|379/4/0|peakRSS=6432MB|205s|sampling=time
BUNDLE|App|816/4/0|peakRSS=2832MB|389s|sampling=time
TOTAL|3848/24/0|2087s   OK (direct launch, no testmanagerd)
```

- **对账**：3848 = 3841（M6-4 实测）+ 2（修批）+ 5（本批 T2 +4 / T4 +1）
  **精确**；和式手核 686+460+494+729+284+379+816 = 3848、skip 1+3+4+4+4+4+4 = 24。
  异常形态（ΔN=0）未出现。
- 七 bundle 计数与执行方 T9 轮（`evidence/t9-all-run.log`）**逐值一致**；
  峰值 RSS 全 <8192MB（贴线族 IOP 7676 / IOPParity 7004，±3% 方差带内；
  Export 6432 vs 执行方 5340 = 非贴线 bundle 时序方差，门内无 MEMFAIL）。
- L055 双保险亲跑：七 bundle 末条 Executed 行全挂靠 `Test Suite 'All tests'`
  + 崩溃签名七段零命中。
- **轮毕孤儿复扫（我方轮后 sleep 4s）**：`find Tests/Fixtures -name "*.lra"`
  零命中 + `git status` Tests/Fixtures 零 untracked（untracked 仅三件批前既有
  `.work` 面）——**T1 根治在我方独立轮上终证**。
- 新测试真跑亲证（我方轮日志）：T2 四新法 4/4 passed、T1 双写腿法 2/2
  passed、T4 新法 1/1 passed；`SessionBatchApplierTests` 类 17 法在轮。

## 二、六清偿项逐项亲测

| 任务 | 亲测证据 | 判定 |
|---|---|---|
| **T1** 孤儿 fixture 根治 `c749ee00` | 源读全文件：`tempFixtureCopy` helper + UUID tempDirectory 生命周期（DepthMaskEditingTests verbatim 同款）+ restore 法（:225-262 入口前清 + defer 改指 tmp + repo 侧防御 removeItem）+ undo 法（:264-291 tempFixtureCopy + `loadRaster(at:)` 孪生）+ 头注 #6 终局注记含 E-1 归因勘误；全 Tests 域写腿原语扫 = 仅此两法持 recordDrtChange/flush 写腿，其余 12 引 Tests/Fixtures 文件全 temp/合成/只读；我方全套轮后孤儿复扫零命中 | ✅ |
| **T2** 12 字段携带 `bd81f859` | `CarriedDocumentState` 12 字段捕获 + 构造点 12 参（pristine 臂 `carried?` 铸 nil）+ process 盖章纪律零触（`?? .current` 禁形零命中）；**独立对表 `LightamerSidecar` 全字段面 = 恰 12 optional + process + 9 结构性，无第十三字段**（CHECKER 2.2 独立复证）；四新法亲读（12 字段正测 / pristine 负测 / rating=3 逐值保真 + typed-nil / 层级 keywords 逐元素）；M6-2-VALIDATION 补记 = 纯追加（diff 亲见原行零改）；我方轮 4 法全 passed | ✅ |
| **T3** 头注 19→20 `71dbd371` | `grep -rn "19-tool"` 全仓（App/Tests/Core/IOP）零命中；`20-tool` 计 2；`5 editing` 零命中；`6 editing` :15/:448 在位；两测试文件顺带亲见；diff 纯注释 | ✅ |
| **T4** 行序方向断言 `76729922` | 新法本体亲读：非均匀增益（top k=1 / bottom k=2）× 非对称 base（128/250）+ 四重断言（①GainMapMin/Max ≈1.0/2.0 取向无关锚 ±0.4 ②top-down 带均值 <64/>192 ③带差 >128 ④锚映射语义增益 ±0.45）——down-mirror 反置全数触红，**单向性真单向**；M-2 计数亲核 = T4 前 25 法（`71dbd371` 时点 grep）+1 = 26，CONTEXT「24 法」漂移订正属实 | ✅ |
| **T5** 门③注记 `c651bb51` | diff = 20 行纯注释（ExportRecipe 门③ + ExportRenderer headroom 取值点），两载体分叉契约 + enqueueExportM2 联动引证在文；零行为 | ✅ |
| **T6** V16 + 三键 `0ebdd3c1` | `--self-test` PASS（interp-no-variant 检测在册）+ `--check` PASS（**1682/1926/30 interp 键全 variant-PRESENT**）；fresh `--report` 与 evidence transcript **逐字节一致**（30 PRESENT / 0 ABSENT）；xcstrings diff = 51+/0- 三键尾块纯插入（en+zh 值与裸键同文）+ 调用点零改；AGENTS M6-5 节登记行落盘 | ✅ |

## 三、40 项终局表对账（SUMMARY §五 vs CONTEXT §1 vs 各源 VALIDATION）

结构亲数：§五表 = 40 项 + rider；分类合计 = 清偿 6 任务（8 条：A1+B2+C3 同条
→T1）+ 转 V2 9 + Manual-Only 11→19 行 + 销账 7 + 留置 5 = **40 逐项闭合**。

- **清偿 6 任务**：全部亲测（§二）。
- **销账 7 项证据链全核**：A2 `7bc6365f` 在库 ✓ / A5 五轮全套绿逐轮亲见
  （M5-3 3631、M6-1 3689〔ACCEPTANCE-FINAL〕、M6-2 3725、M6-3 3759、
  M6-4 3841 各 ACCEPTANCE 正本）+ 本批第六轮 ✓ / A7 `5ff6ff48` +
  `ColormatchModule.swift:91-104` NSLock holder 亲读 ✓ / B4 `908526fe` +
  M6-1 原裁在案 ✓ / C4 M6-2-VALIDATION :127 销账留痕 + 第二路证伪原文 ✓ /
  D3 M6-3-VALIDATION :117-118 + :235「DPI 登记零动作」 ✓ / E6
  M6-4-VALIDATION :153 核查条目 ✓。
- **转 V2 9 项**：V2-PROPOSAL §七九个一级标题逐项在册；C1 触发条款
  「首个真实 iop 语义分叉/bump 批触发时四件同批」grep 双侧 1:1（M6-2
  VALIDATION :104 vs V2 §七 #5）+ 四件套镜像含②完整形
  `RenderProcess.resolving(piece.renderProcess)`；#2/#8 抽验来源锚与规模
  字段在位；「登记 ≠ 立项」头注在册。
- **Manual-Only 19 行**：`.work/gui-acceptance/m6-5/MANIFEST.md` 亲读 =
  18 GUI 行 + 1 perf 行（P1 bake）；逐行来源指针 + 前置供件 + 预期观测齐备；
  SUMMARY §五行号映射（A3→#1 … rider→#18、A4→P1）逐行可对；「本批不执行」
  头注在册。
- **留置 5 项**：A9（AGENTS L057-B queue 行）/ A12（CONTEXT §7 边界）/
  A16（AGENTS ±3% 口径行亲见）/ A19（m5-3 perf.md +388MB/band 行亲见）/
  A20（范围外指针）——零动作申报与现状一致。

## 四、I-1 事故处置复核

**实质处置成立**：根因定位正确（`test-direct.sh` 头注亲证 build-for-testing
为前置条件非内置步）；T4 方法过滤 0/0/0 暴露路径可信；重建后三 bundle 复跑 +
T9 全套轮在新二进制上执行（我方产物 mtime 考古：七测试 bundle 04:04 批含
T1/T2/T4 测试码、framework 04:05:37 含 T5）——执行方 T9 日志中四新法/双写腿
法/T4 新法逐条 `passed` 亲见，**假绿未污染任何申报终值**。

**但「假绿数字未入任何 commit」申报被证伪（minor-1）**：

- `bd81f859`（T2）commit message Verified 行：`"targeted Sessions
  SessionBatchApplierTests 13/0/0 (9 existing incl. the three-state process
  test + 4 new)"`——13/0/0 正是**陈旧二进制首轮数字**（真旧集 = 13 法、fresh
  总数 = 17；「9 existing + 4 new」= 13 的拆解两头皆错）。commit 时刻
  03:56:42 早于重建（04:04 批），该数只可能出自陈旧轮。
- DECISIONS §3 I-1 处置行「Sessions 17/0/0（**9 旧**+4 新）」同源 arithmetic
  error（应为 13 旧；SUMMARY §二「13 旧 + 4 新」为正确形——三处两种拼法并存
  即内部矛盾）。
- 附：`c749ee00`（T1）Verified 行的 7/0/0 + 孤儿零命中亦出自陈旧首轮，但
  7/0/0 与 fresh 同值（T1 零新增）故无假绿差异；孤儿零命中已被重建后补做 +
  我方两轮独立复扫坐实——**申报数字层面无影响，仅 provenance 注记**。

**处置建议（翻账批）**：DECISIONS §3 两处「9 旧」订正为「13 旧」+ I-1 污染面
评估句改为「假绿未入 SUMMARY/申报终值；bd81f859 commit message Verified 行
残留首轮数字（不可变历史），以 VALIDATION 本节为勘误正本」。

## 五、偏差清单裁决（I-1 外六项，DECISIONS §4）

| # | 偏差 | 裁决 |
|---|---|---|
| 1 | T2 typed-nil 断言（wire 恒写 null） | **ACCEPT**——线格式事实亲核（LightamerSidecar 五元数据 encodeIfPresent 恒写形）；typed 层断言是诚实形，D-2 已申报 |
| 2 | T4 取向执行期定格 | **ACCEPT**——plan 明文授权「断言形式执行时择稳」；top-down 实测 + 反置触红证明门语义不损 |
| 3 | T6 裸键值即格式串 | **ACCEPT**——现状亲核（三裸键值内含 %@）；清偿路线 = plan 指定路线未变 |
| 4 | T8 换行断裂 amend | **ACCEPT**——终 commit `9bdeb467` 同文机检双侧 1:1 亲跑证实自纠闭环 |
| 5 | I-1 | 实质 ACCEPT + minor-1（§四） |
| 6 | T7 18+1 行 vs ~17 约数 | **ACCEPT**——19 行逐行可对 CONTEXT §6 明细，约数内 |

结构性偏差：零（执行链 18 文件与 plan files_modified 逐一对照零越界亲证）。

## 六、红线族亲跑 + 独立观察项

**红线全绿**：`LightamerIOP/` / 全部 `*.metal` / `LightamerSidecar.swift` /
`Pipe/History/` + `PipeCacheKey.swift` / V50Order 面零 diff（git diff 空输出
亲跑）；MCP 快照族（McpRegistrySnapshotTests）零 diff（T3 触两测试文件注释 =
red_lines 明文豁免形）；Export 六格式矩阵三文件零 diff；`Project.swift` 全零
diff（零新 SPM + 零新测试文件）；`xcstrings` 全链仅 T6 三键 51+/0-；UserDefaults
零新键（diff 中 UserDefaults 字样仅 md 文档行）；`\.runModal(` App/Sources 零
命中；`String.LocalizationValue("` 插值禁形代码零命中；zh-audit `--check` PASS
（断言 5 ABSENT 零命中）。

**独立观察项（不阻塞）**：

- **O-1**（妆饰）：TODO.md M6-5 条目规划批段保留 CONTEXT §2 的 R-2 妆饰滑差
  旧计数（「销账 6 / 留置 6」），与 SUMMARY §五终局口径（销账 7 / 留置 5）
  并存——逐项表为正本，翻账批顺带统一措辞即可。
- **O-2**（provenance）：c749ee00 Verified 行数字出自陈旧首轮（值恰同 fresh，
  见 §四附注）。
- **O-3**（资源时效，零影响）：执行方 T9 全套轮的 app-bundle
  Localizable.strings 为 T6 插键前构建产物（资源在我方 05:04 build 才刷新）——
  全仓无任何测试消费编译目录（zh-audit 直读 repo xcstrings），3848 数字不受
  扰；我方轮已在新鲜资源上复跑消除该缝。

## 七、commit 清单（8 commits，逐一 diff 审过）

| commit | 任务 | 边界判定 |
|---|---|---|
| `c749ee00` | T1 双写腿 temp 化 | ✅ 测试文件单文件 additive+改法 |
| `bd81f859` | T2 12 字段 + 4 法 + M6-2 补记 | ✅ 三文件；commit message 含 minor-1（§四） |
| `71dbd371` | T3 头注 20-tool | ✅ 三文件纯注释 |
| `76729922` | T4 行序断言 | ✅ 测试单文件 +1 法 |
| `c651bb51` | T5 门③注记 | ✅ 两文件纯注释 20 行 |
| `0ebdd3c1` | T6 V16 + 三键 + AGENTS | ✅ 三文件；xcstrings 51+/0- |
| `9bdeb467` | T8 V2 九项 | ✅ 单文件纯追加节（D-5 amend 终形） |
| `7c0d2bbb` | T9 收口 | ✅ SUMMARY/DECISIONS/AGENTS/TODO/GOAL-STATE |

T7 MANIFEST local-only 正确不入 git（L073 口径）。

## 八、结论

**PASS / 0 error + 1 minor（minor-1 = I-1「假绿未入任何 commit」申报不实 +
DECISIONS「9 旧」arithmetic 残留；修复建议见 §四，不影响任何测试终值与 3848
对账）+ 观察三项（O-1..O-3，不阻塞）。**

九任务全交付 / 全套独立复跑 3848/24/0 逐值一致 / 六清偿亲测全过 / 40 项终局
闭合 / 红线族全绿 / commit 边界零越界。**建议闭环批：按 §四建议订正 DECISIONS
后进 omp 二次验收（串行）→ M6-5-VALIDATION 签核。**
