# M5-1-03 DECISIONS — TRACK P3：match_color MCP 最小面 + G4 + 五门收口

> 执行批 2026-10-12（续班 worker；基线 = M5-1-02 修复批后 HEAD `3be69ee`；
> 前任实例 ~10 分钟 API 瞬态亡，零产出——本批全新开跑）。任务序 T1..T4 与
> PLAN 一致；本文只记**偏离、机制发现与申报面**。

## 1. 工具宿主形态（T1）——两枚 host seam box + GUI 装配两行（申报偏离）

- **`EditingToolset.Seams` 零扩**（register 一行红线的必然）：match_color 的
  两个宿主依赖以 `MatchColorToolset` 自持 box 承载——①`installLibraryProvider`
  （id 形 reference 的 `(LibraryStore, projectDirectory)` 源）；②
  `installColorMatchService`（进程内唯一 ColorMatchService——GUI 装配注入 app 的
  `@State colorMatchService`，会话曲线共享；headless 惰性建 standalone 并
  `configure` 进 `ColormatchResolverBox.shared`）。
- **申报偏离（files_modified 未列）**：`LightamerApp.swift` 装配点 +2 行 install
  （机制必需——不装则 id 形 reference 生产恒 typed 死面；不共享 service 则双
  resolver 互踢 `ColormatchResolverBox.shared`）。`colorMatchService` 的
  M5-1-02 注释已预告该共享（「the panel and (M5-1-03) the MCP match_color tool
  share this ONE instance」）。
- `EditingToolset.swift` diff = **register 内一行**（行尾注释同线，红线字面达标）。

## 2. solve 腿 = Core 纯函数同形，非 `solveAndAttach`（T1）

`ColorMatchService.solveAndAttach` 绑 `editorState`/`coordinator`（GUI 面）；
MCP 腿 = 同一批 Core 纯函数（`ColorMatchSolver.solve` / `ColorMatchCDFSolver
.solve` / `ColorMatchBake.bake` / `ColormatchCubeAsset.write·cleanupSameSolution`
——与 service attach 逐式同形），落位走 **store 级投影缝**（`projectColormatch`
+ `SessionBatchApplier` 一次写 + `flushForTeardown`——E6 checker 注记的
「store 级实例投影缝同面复用」）。**零新提取路径红线保持**：统计唯一来自
`ColorMatchService.extractStats`（源 512 预览桶 / 参考 THUMBNAIL pristine 同
API，instances `[]` 即 pristine 语义）。
- **N=1 免池化**：v1 单 reference/调用，`ColorMatchPooling.pool([e])` N=1 恒等
  返回 verbatim——直接用参考统计（等值），池化面留 GUI 多参考（M5-1-02）。

## 3. 「targets 缺省 = 当前图」的 stateless 实现（T1，KD-1）

D5 无服务端活动句柄——「当前图」= `liveImageURL`（GUI-live judge）映射到 open
session relPath（root 前缀剥离，liveRelPaths 同形）。live 缺席或不属 session →
`invalidParams`（targets 必填的 typed 面）。**GUI-live 目标 + attach=true →
`imageLiveInEditor` 硬拒**（apply_params 同缝；attach=false 只读不拒——拒写不
拒读，两测钉死）。

## 4. attach=false 也提交 `.cube` 资产（T1，申报）

CDF 解的产物 = 资产本身（params 只存 `{assetRef, assetHash}`）——不写资产则
attach=false 参数组落位后必然 typed degrade。故资产在 solve 时提交（两模式
同），同解前缀清理照走；agent 放弃 apply 时留下的是派生资产（无害，与
`.lra.masks/` 同族派生物）。响应 note 已写明 assetRef 仅在目标图上有效。

## 5. requiresWriter + destructiveHint（T1）

`requiresWriter: true`（attach 缺省写盘）+ `destructiveHint: true`（§A 破坏列
8→9，快照同步）。**caveat（记录）**：writer gate 是注册面级——只读宿主上连
attach=false 的读式求解也 `serverReadOnly`（保守拒绝，与 apply_preset 同形）；
只读宿主的追色需求 = GUI 面板。

## 6. m4 回灌面的机制发现：apply_params 无法 CREATE colormatch（T1 测试批）

首轮 e2e 实测抓到：`apply_params` 对 colormatch 报 `invalidParams("no derivable
default params")`——**M5-1-01「Registry seed ABSENT」密封决策的必然**（
`defaultRecord` 种子源无 colormatch，E-omp1 鸡生蛋族）。终形 = **两段 agent
流**：①attach=true 建实例（或 GUI add 行）→ ②attach=false 参数组经 apply_params
重参数化（upsert replace 路径，m4 e2e 实测绿：sourceStatsHash/referenceStatsHash
逐位回灌）。工具 description 已写明该用法；非缺陷、非 seed 翻案（密封面零触碰）。

## 7. 快照族 19→20——实际改动面 > plan 行号清单（T1，独立验收面照办）

- `McpFinalSnapshotTests`：plan 列 :165/:193——实际五处：frozen 表入 verbatim
  descriptor + `all19→all20` 属性更名 + `testFinalSnapshotUnion19Verbatim→20`
  + **白名单负测重形**（`testTwentiethToolIsWhitelistNegative→
  testPostUnionToolIsWhitelistNegative`：match_color 移出 not-a-tool 名单——
  它现在是工具了，负测名单剩 delete_file/run_shell）+ **descriptionKeys 必增
  match_color**（key-map-cover-exactly 断言强制）+ destructive 集 8→9 + :220/
  :362 计数。
- `McpRegistrySnapshotTests`：plan 列 :186——**editing 域快照表**（
  `testEditingDomainSnapshot` 的 expected 数组）也要入 verbatim descriptor
  （首跑红：TOOL SET CHANGED 即该表）。:186 计数 + 三处注释照改。
- `McpHostTests`：:242/:694 计数 + 三处注释；:720-726 的「19 ops」是 IOP 目录
  计数非工具数——不动（亲核）。
- 快照域全程显式申报（security face 非 executor 顺手改数——checker E3 字面）。

## 8. solver 拼写二态（T1）

MCP 入参面 = plan 字面 kebab（`gaussian-ot|reinhard|cdf`）；**返回 params 用
模块 rawValue（`gaussianOT`）**——apply_params 回灌字节诚实（ColorMatchSolverKind
rawValue 解码）。`IopCatalog` colormatch 行零改（`enum:gaussianOT=0,reinhard=1`
是 params wire 面，与 MCP 入参拼写分域）。

## 9. 必要 glue 两枚（T1，申报）

- `layerStack(from: SidecarLayerStackRecord?)` 8 行——QuickLookRenderer/
  ExportRenderer 重建形 verbatim（`record.snapshot.makeLayers()` → addAdjustment；
  空栈 nil）。服务 live 腿拿 editorState 的活 LayerStack，headless 必须从盘
  重建——无既有公共 helper。
- 批量帽 = **30**（get_contact_sheet 先例；每目标全 decode+extract+solve+
  write）。超帽 `invalidParams` 在 gate/service 之前（GPU 前置 fail-fast，
  L050）——负测以无 metal seams 钉「参数层先行」。

## 10. G4 判据（T2）——byte-identical 成立，零容差带

共享 decode memo + 同 gate 串行下：match_color→apply_params(0.7)→render_preview
== 本地 renderedPlane+JPEG q85 **逐字节**（三法全绿）。SC#3 先例判据未放宽，
无实测带收窄项（plan 风险节的「GPU 采样非确定性」在 colormatch 线性臂实测
不显——同 PSO 同 uniforms 确定性）。fixture = 合成渐变 TIFF（KD-2 禁真 RAW；
M4-1 raster 解码族，测试内生成零外部依赖）。

## 11. 批量账目与对账

- 新测试 2 文件 **24 法**（ToolsetTests 21 + ParityTests 3；plan 估 +10..16，
  超估申报——typed 面六法 + 快照域表/负测重形 + 两 reference 形态全覆盖所需）；
  BUNDLE-MAP 增行 2；App 对账 725→749 逐位。
- **快照族四文件方法数零增**（重命名/改表/改计数，不增法——BUNDLE-MAP 既有行
  不动）。
- xcstrings **+1 键**（`mcp_tool_desc_match_color` 尾块纯插入；zh-audit PASS
  1638/1877）。
- 收口轮（定向四 bundle）：Layers 466/4/0（1153MB）/ IOPParity 444/3/0
  （5836MB）/ App 749/4/0（2832MB）/ IOP 563/1/0（7740MB<8G）——零 MEMFAIL，
  三 bundle 与 M5-1-02 收口值逐位相等（零漂移抽验通过）。全套 `--all` 终验数字
  = GATE-LEDGER §6（批准在案轮）。
- M4-1 挂账 #6 孤儿第五度预防：全套轮前预删
  `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（配方照 M5-1-02）。

## 12. 红线自证（`git diff 3be69ee..HEAD` 亲证）

- [x] `LightamerCore`/`LightamerIOP` **零 diff**（本 plan 零 Core/IOP 触碰铁证）
- [x] `.metal` 零 diff 零新文件；V50Order/Registry/GradeCatalog 零触碰
- [x] `grep -rn "\"match_" App/Sources/Lightamer/MCP/Tools/` = MatchColorToolset
      一文件（零新工具面）
- [x] EditingToolset.swift diff = register 一行
- [x] 零新 SPM（Project.swift diff 仅测试编列 2 行）
- [x] `runModal` 机检 0 命中；`String.LocalizationValue("prefix_…")` 禁形 0 命中
- [x] LumaRescue 文本零搬（工具 doc 全英文自写——许可红线）
- [x] zh-audit `--check` PASS（1638 source / 1877 catalog）
- [x] McpRenderParityTests.swift:564 注释未动（plan 预授权核对点，checker 亲核）
- [x] McpServerController.swift 头注「frozen 19-tool set」陈旧未改（files_modified
      纪律；历史注记不误导行为，SUMMARY 登记待后续 plan 顺手面）
