# AR-01 SUMMARY — plan A（d6 面大重构）执行摘要

> 执行窗：2026-10-17 夜间批；基线 HEAD `c5570b05`（fixer 后）；B/A/C 三批
> 编排 = CONTEXT D-M7-AR-9（A/B 零交集并行窗口，本批 = A 全程）。
> C 档停位：本 plan 执行+验收闭环后停汇报（大重构批用户过目点），B/C 待确认。

## 逐任务 commit 表（Conventional Commits，全英文，未 push）

| 任务 | commit | 内容 | ΔN 实账 | 机检面 |
|---|---|---|---|---|
| T1 M1 | `1765f0ca` fix(ar01): isolate workspace host invalidation fans (audit M1) | WorkspaceHostView：四 onChange 抽四 modifier（消费逻辑逐行平移）+ ToastBarMount/ReadOnlyBannerMount 叶自读（既有值传递 init 零改）+ WorkspaceTopBar 子 View（窄输入 + 回调）+ rebuildLibrarySurface 移 .task | 0 | 四观察 body 作用域零命中（F-7 分组形）；七 struct 各恰一定义；双 safeAreaInset 原位；onAppear rebuild 零命中；ToastFaceTests/LibraryProjectController 零 diff；构建绿 |
| T2 M4 | `36322b5f` fix(ar01): sink contentview gate-false side effects (audit M4) | ContentView gate-false 臂：ExportQueueRebuildModifier + InspectorPageMount（.inspector/.focusedSceneValue/onChange 整段下沉）；根 body 只剩装配 + Mount | 0 | legacyBody :248-418 byte-frozen（F-6 offset 适配版零输出，D-AR1-2）；-U0 全 hunk 归属臂区；focusedSceneValue 求值内容零改；gate/routing 测试文件零 diff；构建绿 |
| T3 M5 | `17b95f2b` fix(ar01): split panel sections and cache derived reads (audit M5) | Film 三节 + Drt 四节子 View struct；m11 onAppear 惰性建；m2② 值键 memo + m2③ 写点刷新缓存（F-3 成本证据 = DECISIONS D-AR1-5/6）；m9 单格式键 + 并排 Text；o9 会话下沉缓存 | **+2**（m2 memo 两腿回归 → DrtPanelModelTests） | 七节 private var 零命中；State(initialValue:) 零命中；D-H1 绑定面 pre/post 恒等（grep 计数逐文件相等，DrtPanelView +1 为注释提及）；scopes 零 diff；isPristine 分支形保持；xcstrings 恰 +1 键尾块纯插入；zh-audit --check + --self-test 双 PASS；DrtPanelModelTests 11/0/0；构建绿 |
| T4 M3 | `e7a51667` fix(ar01): account filmstrip visibility by row id (audit M3) | FilmstripModel visibleIDs: Set<Int64> + row.id 直传 + firstIndex 消灭 + idToIndex 每 refresh O(n) 重建 + visibleIDs 剪枝；LibraryGridView enumerated 携带 index（pager API 不动） | **+2**（fixup stale-window 两回归 → FilmstripModelTests） | firstIndex 双文件零命中；visibleIndices 全域零命中；visibleIDs 恰一声明；:169 .disabled 逐字节保留；LibraryGridModel 零 diff（fixup 锚）；Project.swift 零 diff；FilmstripModelTests 8/0/0 + Library bundle 738/4/0；构建绿 |
| T5 归因 fixup | `5c072a23` fix(ar01): sync the disable-face manifest token to the topbar refactor | App 定向轮首轮 919/4/1 → 归因 = M7-5 face-⑪ 源码 token manifest 过时（窗内，行为面不变）→ token 同步 + 复测 13/0/0（D-AR1-9） | 0 | AgentControlCoordinatorTests 13/0/0 |

**ΔN 合计 = +4**（T3 +2 / T4 +2；带 +1..7 内，T4 下界 ≥1 兑现）。

## 全套终值（--all，批准制，锁 `/tmp/la-audit-repair-all.lock` 串行）

**净轮 = `TOTAL|3967/35/0|2142s`**（基线 3963 + ΔN 4 = 3967，恰落带
3964..3970；skip 35 口径维持——24 基线 + 11 RAW 供件漂移，零第三种 skip
来源）。逐 bundle：IOP 687/5/0（RSS 7948MB）/ IOPParity 460/3/0（7741MB）/
Layers 494/5/0（809MB）/ Library 738/4/0（622MB）/ Sessions 284/9/0
（1431MB）/ Export 385/5/0（6011MB）/ App 919/4/0（2832MB）。

- **首轮 --all（run1）在 Library bundle FAIL 后中止**（脚本 ANY_FAIL 短路，
  Sessions/Export/App 未跑）：`LibraryThumbnailBridgeTests.
  testPrioritizeReordersQueuedProductions`（`85dbc406` 加固过的时序敏感族）
  ——本批 Δfiles 窗外（桥文件最后触点 M4-1 波 `1b2b5208`；测试直驱桥，无
  FilmstripModel 参与），独立复跑全绿（738/4/0，同日两轮）；M2-7-3 先例
  「留证后干净重跑全套、终值取净轮」行使。留证 = `/tmp/la-audit-repair-
  all-run.log`（local-only）。
- 贴线 RSS 注记：IOP 7948（M2-4-0 记录 7654，+3.8%——略超 ±3% 方差带，
  MEMFAIL 未触发 <8G 门）/ IOPParity 7741（记录 5788——顺序漂移敏感面，
  两轮 8110/7741 波动大；无 MEMFAIL）。挂 AGENTS 资源监控注记域，非本批
  窗口。

## D-6 探针硬门（F-8 形，双构建同协议对测；详录 = DECISIONS D-AR1-10）

**判定：本批零越阈（相对门 PASS）；绝对门 <10% 在基线树形不可达（FIX2
裁定①接受降级的既有持续态）→ 窗外既有缺陷停手上报，C 档头项。**

| 面 | 基线 `c5570b05` | 本批 `5c072a23` |
|---|---|---|
| 编辑器静置（真实 UI：Open Recent 重开 → 进入编辑器） | 193.7% | 194.4%（60s settle 形 192.9%，195→90 衰减） |
| 空载无项目面（60s settle 过 LUT 预热） | 31.4% | 31.9% |

- 三铁条：①spin NOT-PASS（基线同值，既有态）②filmstrip 点击换图出图
  **PASS**（acc5 选中 + 视口渲染 + 直方图跟随；证据 state-editor-after-
  click.png）③截图在案（/tmp 即弃域，验收批按 MANIFEST 重产）。
- 协议勘定五点（seam 自终止 / open stderr 不可捕 / LUT 预热窗 / AI ask
  抑制后已还原 / AX+cliclick 驱动链）= DECISIONS D-AR1-10。
- 门值修订建议（相对门 ≤ 噪声带 vs 绝对门绑 D-6 专项）呈晨审裁定。

## 红线机检电池（全波累计，基线 `c5570b05`..HEAD 亲跑）

| 项 | 判据 | 结果 |
|---|---|---|
| 封存面零 diff | LightamerIOP//*.metal/LightamerSidecar/DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels/DrtEotf/ExportQueueContract/六格式导出矩阵/NodeGraphCommand/HistoryStack/HistoryHash/PipelineDocument/V50Order/GradeCatalog/Registry/ModuleInstance | **零命中 PASS** |
| FIX2③ | LibraryProjectController.swift 零 diff | **PASS** |
| ToastFaceTests 零 diff | — | **PASS** |
| legacyBody byte-frozen | :248-418 段 diff 零输出（offset 适配，D-AR1-2） | **PASS** |
| M2LIB-06 回归通道 | LibraryLegacyGateTests 零 diff 全绿（App bundle 内） | **PASS** |
| xcstrings | 纯插入（deleted lines = 0）+ 恰 +1 键 + zh-audit 双 PASS（m9 同批显式豁免一条，键数终账 = DECISIONS D-AR1-7） | **PASS**（+1 越带下界外，豁免申报在案） |
| UserDefaults 零新键 | InspectorPageMount 的 @AppStorage = 既有 `layout.inspectorWidth` 同键复用 | **PASS** |
| `.runModal(` App/Sources 零命中 | L057 禁令 | **PASS** |
| `String.LocalizationValue("prefix_` 插值禁形零命中 | M2-9 F-2 | **PASS** |
| Project.swift / BUNDLE-MAP 零 diff | 零新测试文件（M3 测试进既有 FilmstripModelTests；m2 测试进既有 DrtPanelModelTests） | **PASS** |
| D-6 禁区面 | menus/focus 挂点零 diff（:183/:228-233/:287-288 求值内容零改）；双 safeAreaInset 挂载形原位；.inspector 形态不动；编辑器三段内容段数不变；AX 深遍历未用 | **PASS** |
| A/B 零交集 | 本波 diff 面 = UI/Shell/ + ContentView + LibraryGridView + Library/Views/ + 两测试文件 + xcstrings；UI/Inspector/ 域零触（唯一新增文件面 = 无） | **PASS** |

## 偏差清单（全部 DECISIONS 在案）

1. D-AR1-2：F-6 命令形 offset 适配（机械，冻结语义恒等）。
2. D-AR1-3：T-M1c 窄值字面形（RESEARCH「只重估 topBar」完全叶隔离未行使——SC 字面为准，罕见事件路径，晨审可翻）。
3. D-AR1-4：Mount 自持 @AppStorage 同键复用（零新键）。
4. D-AR1-5/6：m2②③ 缓存键终形（F-3 成本证据在案；stableHash 形按伪优化条款否决）。
5. D-AR1-7：m9 键数终账 **+1**（带 +2..3 下界外——孤儿键消解优先于带宽，理由链在案）。
6. D-AR1-8：FilmstripModelTests 属 Library bundle（RESEARCH §7 errata）——plan `test_bundles: [APP]` 以 Library 补跑覆盖。
7. D-AR1-9：T5 定向轮 fail 归因 fixup（窗内 token 同步）。
8. D-AR1-11：微偏差七项（task 合并形/init 形态/enumerated Array 包裹/可选链降读/row 壳复制/静态助手原位/剪枝与双面 warmWindow/o9 回落窗）。
9. D-AR1-1：C 路并入条款核对 = 合并 MANIFEST 未落盘，静态基线形态执行，条款活线（review F-9 义务兑现记录）。

## 已知事项移交（非本批窗口）

- `testPrioritizeReordersQueuedProductions`（LibraryThumbnailBridgeTests，`85dbc406` 加固过一次的时序敏感族）：--all 负载顺序下再现一例（本批零触面，独立复跑全绿 ×2）——挂账既有 flake 族，非本批回归；净轮终值为准。
- IOP/IOPParity 贴线 RSS：本轮 IOP 7787MB（M2-4-0 记录 7654，+1.7% 带 ±3% 内）/ IOPParity 8110MB（记录 5788——顺序漂移敏感，MEMFAIL 机检未触发，<8G 运行门维持）；记录值漂移挂 AGENTS 资源监控注记域。
- o6（LutPanelView `.id(libraryRevision)`）+ m10（xcstrings 复数）+ o4（翻译注释）= 挂账不动（CONTEXT 登记）。
- M2 = plan B（39 面板 params codemod），本批零触（UI/Inspector/ 域零 diff = A/B 零交集红线 A 侧义务兑现）。
