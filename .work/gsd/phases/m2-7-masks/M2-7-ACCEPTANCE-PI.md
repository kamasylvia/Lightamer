# M2-7 ACCEPTANCE-PI — 蒙版 phase 回溯二次验收（PI 路，双路并发批）

> 验收员：PI（零共享上下文回溯二次验收）。日期 2026-10-10。HEAD = `1c96e639`（远超 phase 收官 commit，后演进口径逐处标注）。方法 = 正本三 ACCEPTANCE + 三 SUMMARY + 两 DECISIONS 亲读 + AGENTS.md M2-7 增量节亲读 + 读码/git/grep/JSON 机检 6 抽查点独立取证（零照抄前报结论）+ 测试零复跑（引用首验已记录终值）。
> **结论头：`PASS / 0 error + 1 minor`**

## 一、逐抽查点证据（均独立取证）

### 1. Follow Edges 熔断态（读码）— ✅

- App 侧默认 `.snap`：`App/Sources/Lightamer/State/LayerEditingState.swift:196` `var followEdgesParams = FollowEdgesParams(mode: .snap)`，上附 OQ-4-C 熔断注记（:185-195）。注记块现含 M4-2 删除段（「walker … deleted after its gate failure (2026-10-10 user ruling)」）——**后演进**（M4-2 立项+终删），熔断语义本体不变，不记账。前报引 :193，行号漂移同为后演进。
- Core 缺省仍 `.streamline`：`LightamerCore/Sources/Layers/Masks/FollowEdges.swift:66` `mode: FollowEdgesMode = .streamline`；双臂分支 `:108-109`（`.streamline`/`.snap`）；全文件 `default:` grep **零命中**。
- V1 walker 参数回归在位：`stepPixels: Float = 1.5`/`maxPoints: Int = 256`（:64-65）——M4-2-03 用户终裁「逐字节回落」亲证。
- **V2 残留 grep 全仓零命中**：`RidgeExtract|RidgeGraph|withRidges|followEdgesRidge` 在 App/Sources + LightamerCore/Sources = 0（`maxLongEdge` 命中仅 `FollowEdges.swift:337` readEdgeMap 缺省 512 + `WorkspaceHostView.swift:897-906` 无关 base64 provider——非 V2 面残留）。
- 模式选择器保留：`MaskToolbarView.swift:213-216` Picker get/set 全绑 `editingState.followEdgesParams.mode`，无字面默认值。

### 2. 蒙版 contentRevision 语义（读码）— ✅

- 单源 bump：`MaskSpec.swift:388-393` `bumpContentRevision()`（`(contentRevision ?? 0) + 1` + overflow precondition，头注「THE single bump primitive」）。
- 乐观并发门单实现：`MaskSpec.swift:409-411` `matchesExpected`——全仓 `?? 0` 生产实现 grep 恰落此处（:389/:411），零第二实现。
- sidecar 载体 additive：`SidecarLayerStack.swift:62-63` `deletionProtected: Bool?`/`contentRevision: Int?` + init 形参（:70-71），decodeIfPresent/encodeIfPresent 零漂移语义（头注 :56-57 申报）。
- 同批亲核 E7 单源：`MaskSpec.swift:148-150` `hasDualFeather = innerFeather != nil || outerFeather != nil`（头注 THE single predicate）+ `:161-162` `resolvedOuterFeather` 单源式逐字在位。

### 3. evidence/m2-7-3 probe 在档（log 亲读）— ✅

- `evidence/m2-7-3/probe/probe.log` 48 行：`FIELD max=0.4941 mean=0.01801 p99=0.1808`（:2）；`COLD median 6.3ms min 6.1 max 7.3`（:3）；`WARM empty=82/100 avgPts=0.2`（:4）；DIAG 四组 `functionalChains=0/3`（:42-45，场 1024/2560 × 步 1.5/0.75）；`FULL 73.7ms`（:47）——全部与 M2-7-3-ACCEPTANCE §二①及 AGENTS.md 判据措辞逐值一致。
- 24 条 SCENE 行逐行亲读：8 景盒 × 2 阈值 + 8 auto-seed，**stream 链全部 n≤3（n=3 仅 A 系三行）、snap 全部 n≤2**——判据②（≤3 点链 + snap 确定性贴边）成立。注：聚合 grep `n=[0-9]*` 会出现 3 处假阳性 `n=4`，系 `len=4px` 子串误匹配，全行亲读排除。
- `all_run_incident.log` 亲读：`TOTAL|2179/16/0|764s`，IOPParity 截断 `16/3/0`，其余六 bundle 467/1、298/3、430/4、279/4、260/1、429/0——与首验 §二③及前报引数逐值一致。evidence 目录 16 文件（ev_A/B/B2/C + field_vis + plane_dump + GUI 两张 + probe/）在档无缺失。

### 4. zh 52 键全族对账（JSON 机检）— ✅

- 从 `M2-7-2-DECISIONS.md` §五键清单独立提取全部键名，逐键查 `Resources/Localizable.xcstrings`：**52/52 存在且 zh 非空**（49 小写键 + 3 camelCase 键 `mask_command_addMaskItem`/`mask_command_removeMaskItem`/`mask_tool_followEdges`——粗则正则 `[a-z_]+` 会漏这 3 键，提取须含大小写）。抽查值：`mask_follow_mode_streamline`→「流线」、`toast_mask_revision_refused`→「蒙版已在他处变更——本次编辑被拒绝，请重画」、`mask_groups_empty_hint`→「还没有调色图层——添加后即可绘制蒙版」。
- catalog 现共 1900 键（前报时点 1822）——M5-x/M6-x 诸批后演进增量，不记账；M2-7 52 键族账不受扰。

### 5. git 机检（commit 存在性 + stat 对照）— ✅（minor 见 §二）

- 熔断 commit 现存为 `d10f6817 chore(m2-7): follow edges default to snap mode`：`--stat` = LayerEditingState.swift 单文件 **6+/2-**——与 P3 SUMMARY「UI 默认值一行 + 注记四行」精确吻合。
- walker commit 现存为 `d84dc2a8 feat(core): follow edges walker with edge map cache key`：`--stat` 六文件（FollowEdges.swift 389+ / MaskEdgeKernels.metal / PipeCacheKey.swift / Project.swift / FollowEdgesTests.swift 234+ / BUNDLE-MAP）——与 P1 T6 SUMMARY 申报交付面精确吻合。
- 同批亲核 `PipeCacheKey.swift:44,90,100` edgeMapPosition -4 + edgeMapNamespaceID additive 在位（首验 §二③勘误落点现态仍成立）。

### 6. 测试宿主 parentage 教训的脚本防护 — ✅（观察：防护为流程面非脚本面）

- `Scripts/test-direct.sh`（321 行）grep：无任何 `ppid`/parentage 机检门——进程处置仅有 `kill -0 "$pid"` 存活轮询（:257）+ ps rss 峰值后备轮询（:258-263）。
- 教训的实际落点 = **AGENTS.md M2-7 增量节流程条款**（「进程清理前先核 parentage（`ps -o ppid`）+ 留证重跑」，亲读在位）——与首验 F2 的修复范围一致（F2 只要求 AGENTS.md 登记），脚本无防护**非缺陷**，登记为观察：若未来要把该纪律机检化（kill 前自动核 ppid），属可选小改。

## 二、与前报（M2-7-ACCEPTANCE-OMP.md）分歧项

- **判定分歧：无。** 熔断态、contentRevision/单源族、probe/incident 数字、zh 族账、commit stat 五面结论经独立取证全部成立。
- **minor × 1（前报 minor 复发，文档时效非交付缺陷）**：前报（2026-10-09）以 `59ac74f`/`8d67b5d` 为「新 SHA 体系」并声明可解析 + stat 吻合；本轮 `git cat-file -t` 亲跑 **六个正本旧短 SHA 与前报两个新 SHA 共八枚现已全部不可解析**——该报告落成后又发生一轮历史重写（现映射 = `d10f6817`/`d84dc2a8`，stat 六文件/6+/2- 逐项吻合，内容面零损）。影响同前报所述：回溯者须按 subject 检索映射。后演进，不记账为交付缺陷；是否补 SHA 映射表入 phase 目齿仍归 orchestrator。
- 次级口径差异（均后演进，不记账）：①LayerEditingState `.snap` 行号 :193→:196（注记块 M4-2 段追加）；②xcstrings catalog 1822→1900 键（M5/M6 诸批增量）；③`probe.log` n 分布聚合 grep 存在 `len=4px`→`n=4` 假阳性，全行亲读方可定论（前报全行读法正确，本条为提取器陷阱注记）。

## 三、会话卫生

- 只读验收遵守：除本报告文件外零写入、零 commit、零 push、零网络动作；测试零复跑（引用首验/前报已记录终值 + 本轮全部抽查点为静态机检，满足 ≥4 项独立机检门）。

PI-VERDICT: PASS
