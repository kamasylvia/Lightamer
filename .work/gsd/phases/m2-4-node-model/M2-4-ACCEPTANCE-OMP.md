# M2-4-ACCEPTANCE-OMP — M2-4「节点模型 + 七 bundle」回溯二次验收（omp 独立二次验收）

> 验收批：2026-10-09 omp 回溯验收员，零共享上下文独立复验。对象 = phase 级 M2-4
> （m2-4-node-model 三 plans M2-4-1..3 + m2-4-0-test-bundles）。正本亲读：
> `M2-4-ACCEPTANCE.md` / `M2-4-1/2/3-ACCEPTANCE.md` / 各 SUMMARY /
> `M2-4-0-ACCEPTANCE.md` / `M2-4-0-SPIKE.md` / `M2-4-0-BUNDLE-MAP.txt` /
> `Scripts/test-direct.sh` 全文。只读验收：除本报告外零写入；定向测试仅 1 类；
> 未跑全套 `--all`；未 push。

## 结论头

**PASS / 0 error + 2 minor**

- 首验四份 ACCEPTANCE 的实质结论（PASS、计数链 2165→2203→2217→2240、8G 门、
  七 bundle 拆分、登记闭环）经独立机检全部复现成立。
- 2 minor = ①现行 `test-direct.sh` 头注 verdict 优先级声明与实现次序一处文字不一致
  （行为正确，注释错，M2-11-01 后续改动引入，非 M2-4 面）；②SPIKE.md E1 一处
  「前 43s ≤764MB」措辞与 timeline 证据逐点值不完全吻合（40.35s 行 1252MB；
  不动摇 E1 结论，属措辞精度问题）。
- 另 3 条 observation（M2-4 后续波次引入的 map 行值滞后、SHA 命名空间说明、
  T2 登记漏改已收口自闭环）不计数。

## 子域判定

| 子域 | 判定 | 依据摘要 |
|---|---|---|
| m2-4-node-model（M2-4-1..3） | PASS | 8 新测试文件归属/计数/登记 commit 逐一复现；716db07 收口快照 2240 精确 |
| m2-4-0-test-bundles | PASS | 2165 基线快照复现；7 target 显式清单零 glob；8G 门机检在册；SPIKE 关键值证据对表成立 |

## 抽查点 1：BUNDLE-MAP 归属 + Project.swift 对账 ✅

### 1a. M2-4 八新测试文件归属（front-matter/内容特征 vs 登记，一致 8/8）

| 文件 | 登记 | EditorState 命中 | 内容特征 | 判定 |
|---|---|---|---|---|
| PipelineDocumentTests.swift | LAYERS 5 | 0（`@testable import LightamerCore` 纯投影） | Core 级 | ✅ 一致 |
| NodeGraphCommandTests.swift | APP 17 | 7（`@testable import Lightamer` + 真 EditorState undo/redo） | App 级 | ✅ 一致 |
| NodeOwnershipCatalogTests.swift | APP 6 | 5（addModuleToLayer 经 EditorState 缝） | App 级 | ✅ 一致 |
| SidecarV5Tests.swift | APP 10 | 10（真 EditorState+PipeCoordinator+WorkspaceModel 装配） | App 级 | ✅ 一致 |
| MaskItemSemanticsTests.swift | APP 9 | 7（lock 拦截经 EditorState/LayerEditingState） | App 级 | ✅ 一致 |
| PipelineLinkageTests.swift | LAYERS 5 | 0（纯 Core 投影） | Core 级 | ✅ 一致 |
| NodeCanvasGeometryTests.swift | APP 9 | 2（:256 真面板 NSHostingView 实装 `EditorState()`，渲染读回面） | App 级 | ✅ 一致 |
| NodesPanelModelTests.swift | APP 14 | 8（front-matter 明示 REAL EditorState 驱动） | App 级 | ✅ 一致 |

method 数以 M2-4 快照为准（`01ed6f8` squash 内容面）：5/17/6/10/9/5/9/14，
与 BUNDLE-MAP 在册行值逐一相等。现 HEAD 下 MaskItemSemanticsTests=14 /
SidecarV5Tests=11 系 M2-7/M2-10 后续波次扩测（见 observation O1），非 M2-4 错账。

### 1b. Project.swift 七 target 显式清单 vs BUNDLE-MAP（现 HEAD 全账，零差）

- 七 target 声明行：`Project.swift:288`（IOPParity）/ `:370`（IOP）/ `:457`（Layers）/
  `:528`（Library）/ `:619`（Sessions）/ `:671`（Export）/ `:733`（App）。
- 域文件 1:1 零差：IOPP 51 / IOP 57 / LAYERS 43 / LIB 57 / SESS 25 / EXPORT 34 /
  APP 71，map↔Project 双向 `only_map=[] only_proj=[]`，无重名。
- SHARED 编列：IOPParity/IOP = Fixtures+ParityGate+ChainBuilderHelpers 三件；
  Layers/Library/Export/App = Fixtures+ChainBuilderHelpers；Sessions = Fixtures。
  与豁免注记一致（ParityGate 仅 IOP 系；SESS 零 ChainBuilder 调用者）。
- 磁盘 `Tests/LightamerTests/*.swift` 341 文件 vs map 数据行 341，`diff` 1:1 零差。

### 1c. M2-4-3 收口快照（`716db07`）终账复现 = 2240 精确 ✅

`git show 716db07:...BUNDLE-MAP.txt` 求和：IOPP 44/308 · IOP 53/457 · APP 28/332 ·
EXPORT 24/260 · LAYERS 22/174 · LIB 43/430 · SESS 25/279 = **2240 精确**，
与首验 `M2-4-3-ACCEPTANCE.md` §计数对账逐格一致。`git ls-tree 716db07 Tests/` = 243 项
= 242 map 数据行 + `.gitkeep` 1（diff 亲核唯一差项），域文件账实 1:1。

## 抽查点 2：Scripts/test-direct.sh 机检 ✅（+ minor M1）

亲读全文（321 行）。机检点逐项在册：

- `RSS_LIMIT_MB=8192`（:70），门修订注释援引 SPIKE 证伪链（:63-69）。
- 主判据 `/usr/bin/time -l` ru_maxrss bytes→MB（:117-126），ps 轮询后备
  （sampling=ps-poll 标注）。
- `parse_bundle_log` 独立函数（:75-151），stdout 五字段一行
  `<E>/<S>/<F>|peakRSS=<MB>MB|sampling=…|verdict=…[ ANE-DEGRADED]`（:148-151），恒返回 0。
- crash（`terminated abnormally|Restarting after unexpected exit`）/
  no-total-line（末条 Executed 未挂靠 `Test Suite 'All tests'`，过滤轮豁免）两 verdict
  计数置零（:131-138）；判据 = 测试结果行非宿主退出态（:237-238，:290-291
  `host exit=$rc 仅参考`）。
- MEMFAIL 行尾追加（:287 `line="$line MEMFAIL"`）+ ANY_FAIL 非零退出（:290-294）。

**M1（minor，行为正确/注释错）**：头注 :32-37 声明 verdict 集并在 :128 注释写
「判定（优先级降序）：crash > no-total-line > MEMFAIL > executed-0 > fail > ok」，
但实际 `if/elif` 链为 crash（:131）→ no-total-line（:135）→ MEMFAIL（:139）→
**fail（:142）→ executed-0（:144）**——fail 与 executed-0 次序与注释相反。
语义影响 = 零（两条件互斥：executed-0 要求 failed==0 且 executed==0，
fail 要求 failed>0，不存在双命中；且该分支形态为 M2-11-01 KD-2 引入，
非 M2-4 交付面）。建议顺手修注释一行，不属 M2-4 缺陷。

## 抽查点 3：定向测试 Layers/PipelineDocumentTests ✅

`caffeinate -dis Scripts/test-direct.sh --bundle Layers PipelineDocumentTests`
（产物 2026-10-09 12:23，晚于被测源最后改动 `6fad2ab`，新鲜）：

- `BUNDLE|Layers|5/0/0|peakRSS=194MB|6s|sampling=time`，`TOTAL|5/0/0|6s`，exit 0。
- 日志三条 `Executed 5 tests, with 0 failures`（类/容器/Selected 三层同值）；
  过滤轮末条挂 `Test Suite 'Selected tests'` = 头注声明的豁免形态，
  no-total-line 假绿签名不在。
- 日志唯一 "failed" 命中为首行 sandbox 噪声
  （`sandbox_extension_issue_file_to_process failed … Operation not permitted`），
  非 `' failed (` 测试失败形态；BUNDLE failed=0。
- ru_maxrss 实测 204275712 bytes = 194MB，与 BUNDLE 行一致。

## 抽查点 4：SPIKE 证据对表 + M2-4-3 登记闭环 ✅（+ minor M2）

### 4a. E2 隔离峰值三关键值

SPIKE.md 声称来源 = `test-direct.sh --bundle` 隔离单类 ru_maxrss（独立进程），
该口径数值本身未落盘为独立文件（`*.run.log` 均不含 `time -l` 段——instrument.sh
外挂轮询架构所致），但时间线证据可交叉印证：

- **TilingOverlap 7865**：`IOP.TilingOverlapOnly.timeline.tsv` 峰值行 rss=7864（×4 行），
  与 7865 差 1MB（轮询采样 vs 内核高水位，口径差正常）。
- **HDR 5913 / QL 4589**：`IOPParity.timeline.tsv` max rss=5969（全 bundle 轮询峰值，
  隔离单类 5913 落在其带内）；`Export.timeline.tsv` max rss=5940（全 bundle 含
  ExportPerfProbe+E2E 叠加工况，隔离 QL 单类 4589 为其次峰——与 E2 表「次峰」定性一致）。
- 隔离轮次真实性：`IOP.TilingOverlapOnly.run.log` = 2 tests / 95.564s 全绿独立进程，
  与 timeline 67.18s 跳变点（1721→7864MB）时间对齐。

### 4b. E1/E3/E4 逐点对表（证据文件行级复核）

- E1 IOP：`testFULLToneEqual100MPMemoryUnder3GB` log 实测 97.417s（SPIKE 写 99.35s，
  另一轮次值，±2% 方差带内）；timeline 110.21s 行 2038→4653→7324MB 跳变，
  「峰值 100% 归因这 1 个测试」成立；其后 5883MB 残留地板行在案。
- E1 IOPP：HDR `testMergeStopwatchProbe24MP` 100.245s / McpParity
  `testParityPlaneByteIdenticalToExportRenderStage` 102.732s，逐字吻合；
  525.8MB 回落行实录（`191.63 06:07:22 2843 525.8M`，footprint 列）；
  McpRenderParity 窗口 footprint 7.6G 行在案；bundle 末行 rss=1557MB 吻合 E4 表。
- E1 Export：QL parity 单测 79.096s 吻合（79.1s）；footprint 10.1G 行 ×2 在案。
- E1 Layers/Library：Layers 采样 max 827MB 吻合；Library boot 195→end 273（+78MB，
  0.18MB/test）逐值吻合；Layers boot 192 / end 580（+388MB，2.37）吻合。
- E3：IOPP `__TEXT` 18.7M→1.4G / Export `__TEXT` 18.8M→1.4G（vmmap 首/末快照），
  两 bundle 同值 1.4G = 「一次性框架分页」定性成立（+1381MB 为 SIZE 列换算值）；
  IOSurface 1.0G/1.3G/1.2G 瞬态三值吻合；Layers `__TEXT` +300MB（1.1G→1.4G）吻合。

**M2（minor，措辞精度）**：E1 写「前 43s 全部测试 RSS ≤764MB」，但
`IOP.timeline.tsv` 显示 23.94s 行 rss=1152（footprint 3.6G 瞬态）与 40.35s 行
rss=1252（footprint 4.5G）两处超 764MB 点。TilingOverlap 类启动于 log 06:25:43
≈ timeline 42s 偏移处，故「重测启动前无 GB 级峰值」的**结论成立**（43s 内 max=2039MB
出现在 43.25s 即重测启动后），仅「≤764MB」字面逐点不成立。属措辞精度问题，
不翻转 E1 归因结论。

### 4c. M2-4-3 交互测试补组登记闭环 ✅

- T1 `e39bd0f`：map 新增 `APP 8 NodeCanvasGeometryTests` + `APP 12 NodesPanelModelTests`，
  与该 commit 文件实数（8/12）逐一相符，同 commit 登记。
- T3 `dc5f832`：`NodesPanelModelTests` 行 12→14 同批修订（T3 补组 +2 法闭环）。
- T2 `f7687ae`：几何文件 +1 法（8→9）**未随动 map**（该 commit map 零 diff），
  收口 `716db07` 以「终值勘误 8→9 + 三行注记」补正——首验已披露此漏改，
  本批独立复现实证链完整，闭环成立。

## 抽查点 5：git 机检 commit 对账 ✅

### 5a. SHA 命名空间说明（首验 SHA 在本仓不可直解属正常）

首验 ACCEPTANCE 引用的 7 位短 SHA（`22e3b32`/`02a2835`/`52cf75e`/`b7d7acd`/
`48e2b7d`/`70e09e5` 等）在本仓均 unknown revision。经查：M2-4-1/2/3 的 per-task
commits 以**全值不同的 SHA** 存于 main 祖先链（`ab629d5`/`606ad15`/`9fb90a0`/
`8d6f7af`/`e68efe9`/`e6ee87f`/`6fad2ab`/`e39bd0f`/`f7687ae`/`dc5f832`/`716db07`），
subject 与首验申报逐一对应；公开侧另有 squash `01ed6f8`（M2-4 整包）。
首验 SHA 系执行机本地压缩前命名空间（全局 AGENTS §2.2 公开仓压缩规则），
内容面逐 commit 可考——不判分歧。

### 5b. 执行 commit --stat vs ACCEPTANCE 申报文件集（抽查 3 个，超出要求的 2 个）

- `ab629d5`（T1）：4 文件 = map + PipelineDocument.swift + Project.swift(+1 行) +
  PipelineDocumentTests——与 SUMMARY 申报一致。
- `8d6f7af`（T4）：8 文件 = map + MaskSpec + LightamerSidecar + NodeOwnershipCatalog
  （D-5 改列）+ Project.swift + NodeOwnershipCatalogTests（pin 随动）+
  SidecarMetadataV3Tests（D-4 pin 4→5）+ SidecarV5Tests——与首验 ①节「22 文件
  边界 = 申报 + 两处备案随动」口径一致。
- `e39bd0f`（M2-4-3 T1）：8 文件 = map(+7 行：5 注记 + 2 数据）+ Rail + 3 新 Nodes/
  文件 + Project.swift(+2 行）+ 2 测试——与 SUMMARY 申报一致。

### 5c. M2-4-0 执行链与 L041 落域规则 ✅

- M2-4-0 链：`ec83ced`（六域拆分）→ `cc9075d`（D5 第 7 bundle）→ `b698cf9`
  （test-direct.sh 多 bundle）→ `f3201bf`（收口）→ `28978d0`（SPIKE 证据 42 文件，
  产品/测试源零 diff 红线亲核零命中）→ `47e64b8`（`RSS_LIMIT_MB=3072→8192` 一行 +
  注释，门修订机检成立）→ `2f2bf45`（验收）。
- `f3201bf` 时刻 map 求和 = **2165 精确**（IOPP 44 / IOP 53 / LAYERS 20 / APP 22 /
  LIB 43 / SESS 25 / EXPORT 24 / SHARED 3），与首验基线逐格一致。
- L041（同批 Project.swift + 同 commit 登记）：8 个新测试文件引入 commit 中，
  7 个 commit body 含 "tuist generate"（ab629d5/606ad15/9fb90a0/8d6f7af/e6ee87f/
  6fad2ab/e39bd0f）；`e68efe9`（T5）body 无该字样——但该 commit 未引入新文件
  （SidecarV5Tests 系 8d6f7af 已登记，T5 仅 +3 法扩测 + map 行 7→10 修订），
  L041 触发条件（新文件落域）不适用，无违规。`f7687ae`（T2 既有文件 +1 法）
  未跑 generate 同理不触发（零新文件）。

## 与首验分歧点

实质分歧：无。首验四份 PASS 结论、计数链、门修订、登记闭环经独立机检全部成立。

文字/精度层差异（均已计入 minor，不翻转结论）：

1. M1：`test-direct.sh` 头注 verdict 优先级「fail/executed-0」次序与实现相反
   （M2-11-01 后续引入，非 M2-4 面；首验期脚本无此分支，首验无责）。
2. M2：SPIKE.md E1「前 43s ≤764MB」字面与 timeline 两采样点不合（结论成立，
   措辞精度问题；首验未逐点核 timeline，属验收粒度差异）。
3. 首验 SHA 短码与本仓 main 祖先链 SHA 全值不同（压缩/变基命名空间差，
   内容面逐一对应；首验按执行机本地 SHA 行文，符合当时语境）。

## Observation（不计数）

- O1：现 HEAD 下 map 行值与文件 `func test` 实数有 11 处差（net +21：3153 vs 3174），
  其中 2 处为 M2-4 文件（MaskItemSemantics 9→14 系 M2-7 `744b1c3` +5 法；
  SidecarV5 10→11 系 M2-7/M2-10 扩测）。均为 M2-4 之后波次扩测未随动行值，
  M2-4 快照时刻账实相符——属后世台账滞后，非 M2-4 缺陷。建议后续全套轮对账时
  以运行期 Executed 为准（BUNDLE-MAP 头注已有此口径）。
- O2：T2 `f7687ae` 登记漏改（map 行 8 未随 +1 法）系 M2-4 期唯一登记纪律执行瑕疵，
  已由收口 `716db07` 终值勘误自闭环，首验已披露——本批独立复现实证链，
  无需追加动作。
- O3：M2-4-3-ACCEPTANCE F1（test-direct.sh 头注「六个域」陈旧）修复 commit
  `fafaf63` 在 main 祖先链可考，现行头注 :9 已为「七个域 bundle」——首验修复
  落地确认。

## 会话卫生

- 读取：正本 md/txt/sh 全文亲读 + 8 测试文件 front-matter + spike 证据 40 文件抽核
  + git show/log 约 30 次。写入：仅本报告文件。
- 定向测试：`--bundle Layers PipelineDocumentTests` 1 类（6s，194MB，无 MEMFAIL 风险）。
- 未运行 `--all`；未修改源码/既有文档；未 push；工作区预存改动（M2-3-OMP 报告等）
  未触碰。

OMP-VERDICT: PASS
