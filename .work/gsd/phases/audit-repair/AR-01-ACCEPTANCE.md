# AR-01-ACCEPTANCE — plan A（d6 面大重构）第一路独立验收报告

> 验收批：2026-10-18 凌晨（单验收者 ZCode subagent，plan 忠实路线）。
> 对象 = `c5570b05`（fixer 后基线）→ `8e3bd59d`（收口）执行链六 commit；
> 零源码改动；报告落盘即本文件，不 commit。

## 结论头

**PASS / 0 blocking + 0 major + 1 minor + 5 obs**

- **minor-1**：MANIFEST 落盘路径偏差——plan files_modified 与 T5 SC 写的是
  `.work/gui-acceptance/audit-repair/MANIFEST.md`，实际落盘 =
  `.work/gui-acceptance/audit-repair-a/MANIFEST.md`。内容完整（AR-01-01..06
  配方 + 观察行 O-1/O-2，7524 字节），且 `.work/gui-acceptance/` 全目录在
  `.gitignore :79`（local-only 是仓惯例，git ls-files 该目录恒 0）——纯命名
  偏差非缺件，补改名或 plan 侧勘误一条即可消解。
- **obs-1**：SUMMARY 记账措辞「grep 计数逐文件相等，DrtPanelView +1 为注释
  提及」在 plan T3 判据四名（setLiveParams/commitFilmEdit/recordDrtChange/
  setFilmLive）下不可复现——四名在两面板文件 pre/post 恒 0=0，真实绑定面在
  EditorState/PipeCoordinator/EditorAreaView 等八文件 20→20 逐文件恒等（本
  验收亲核）。实质判定（D-H1 零漂移）成立，记账描述的 grep 面与 plan 判据
  面不同（可能按更宽词干计数）。
- **obs-2**：`FilmstripView .disabled(agentControl.holdsControl)` 行号
  `:169`（基线）→ `:206`（现 HEAD）漂移——字节内容逐字保留（亲核），plan
  AC 的 :169 为 pre-diff 行号（T4 在其上方新增 visibleIDs 记账注释块），
  F-6 同型机械偏移，非红线违反。
- **obs-3**：`defaults` 域 `library.ai.labelingMode = never` 现存——与
  D-AR1-10「探针后已 defaults delete 还原用户默认」表述存在张力（无法考证
  还原前的用户值；本验收快照在案，探针轮沿用 never 抑制、轮后维持现状）。
- **obs-4**：执行批 `--all` run1 的 `LibraryThumbnailBridgeTests.
  testPrioritizeReordersQueuedProductions` flake（窗外既有族，执行批独立
  复跑全绿 ×2 后净轮取值）——本验收轮次中该 flake **未再现**（Library
  独立轮 + 两次完整全套轮 738/4/0 三连全绿）。
- **obs-5**：验收编排双事故（均非产线/执行批问题，详录 §8 流程注记）：
  ①首轮 --all 包装任务被外部 SIGKILL（exit 137，锁协议自愈恢复）；
  ②共享主树 01:41:22 被翻至 c5570b05（reflog 钉死，非本路操作）致第二次
  全套轮 App 束唯一 fail = 源码 token 测试读盘假 fail——机理链亲证后还原
  主树、第三次全套轮净轮兑现。两事故处置全程 M2-7-3 先例形（留证 + 净轮
  重跑），AR-01 执行批零扣分。

## 1 对象与执行链核对

| 项 | 申报 | 亲核 | 判定 |
|---|---|---|---|
| HEAD | `8e3bd59d`（收口 docs） | `git log` HEAD 即 8e3bd59d；工作树仅三个既有未跟踪在制品（非本批） | 一致 |
| 执行链 | T1 `1765f0ca` → T2 `36322b5f` → T3 `17b95f2b` → T4 `e7a51667` → T5 fixup `5c072a23` → 收口 `8e3bd59d` | 六 commit 逐一 `git show --stat` | 一致 |
| T1 diff 面 | 恰 1 文件（WorkspaceHostView） | 236+/83-，恰 1 文件 | 一致 |
| T2 diff 面 | 恰 1 文件（ContentView） | 106+/47-，恰 1 文件 | 一致 |
| T3 diff 面 | 恰 7 文件 | 七文件逐一在册（5 产线 + xcstrings + DrtPanelModelTests） | 一致 |
| T4 diff 面 | 恰 4 文件（LibraryGridModel 预期零 diff） | 实触 3 文件 + LibraryGridModel 零 diff（「本体零 diff 预期」兑现） | 一致 |
| fixup diff 面 | 恰 1 文件 | AgentControlCoordinatorTests.swift 恰 2 行 token 替换 | 一致 |
| 收口 diff 面 | SUMMARY + DECISIONS | 恰 2 文件（+MANIFEST 落盘于 gitignore 域，见 minor-1） | 一致（带偏差） |
| config 开关 | paused=false / auto=true | `.work/config.toml [gsd]` 亲读 | 一致 |

## 2 逐任务判定表（机检亲跑）

### T1（M1 WorkspaceHostView 宿主失效隔离）——**PASS**

| 验收标准 | 判据（亲跑命令） | 结果 |
|---|---|---|
| 四观察 body 作用域零命中 | F-7 分组形 grep `\.onChange\(of: (workspace\.pendingAIEnhance\|...)\)` | 4 命中全部落于 :730/:751/:779/:820 四个 ViewModifier struct 体内；宿主 body（:129 起）作用域零命中 |
| 四 modifier 定义各恰一 | `grep -c 'struct X'` × 4 | 各 = 1 |
| 双叶 Mount 自读 + 既有 init 零改 | 读 :700-728 | ToastBarMount `@Environment(EditorState.self)` 自读 → 转发既有 `ToastBarView(toast:)` + `.animation(value:)`；ReadOnlyBannerMount → 转发既有 `ProjectReadOnlyBannerView(isReadOnly:holderPid:)` |
| Mount 定义各恰一 + WorkspaceTopBar 恰一 | grep -c × 3 | 各 = 1 |
| WorkspaceTopBar 窄输入 | 读 :622-694 | `phase/projectName/isReadOnly/holdsControl` + onCloseEditor/onExport/onYiyin 回调；AX identifier `shell.topbar.*` 零改；`.disabled(isReadOnly \|\| holdsControl)` × 2（D-AR1-9 token 同步锚） |
| safeAreaInset 双挂载形不变 | 基线 :166-169/:179-182 vs 现 :178/:192 | 挂载形逐字节同构（`.safeAreaInset(edge: .top/bottom, spacing: 0)`），仅内容表达式换 Mount——D-6 禁区②核过 |
| rebuildLibrarySurface 移 .task | grep onAppear/rebuild | onAppear 内 rebuild 零命中；`.task` 链首行 rebuild + aiEntry.configure 随后（D-AR1-11 合并形，configure-after-rebuild 顺序保持）；URL 观察腿 rebuild 闭包经 ProjectURLChangeModifier 传入 |
| 消费逻辑逐行平移 | 基线 :266-284/:322-352 vs modifier 体 | 四处 onChange 消费体（guard/Task/adapter 生命周期/hoisted locals 注记）逐行恒等 |
| focusedSceneValue :183 零 diff | diff 中 focusedSceneValue 面 | 仅注释行提及（+// swap only...），挂点行原样 |
| ToastFaceTests 零 diff | `git diff c5570b05..HEAD -- '*ToastFaceTests*'` | 空 = PASS |
| WorkspaceRouting/ProjectReadOnlyFace/EditorStackRouting 零 diff | 同法 | 全空 = PASS |
| LibraryProjectController 零 diff（FIX2③） | 同法 | 空 = PASS |
| 构建绿 | HEAD DD 容器 `dgzsvdww…` app 二进制 Oct 18 00:30 > HEAD commit 00:21 | 绿 |

### T2（M4 ContentView gate-false 臂）——**PASS**

| 验收标准 | 判据（亲跑命令） | 结果 |
|---|---|---|
| legacyBody byte-frozen | F-6 offset 适配版亲跑：`diff <(git show c5570b05:ContentView.swift \| sed -n '248,418p') <(sed -n '210,380p' ContentView.swift)` | **零输出 PASS**；段界核对：旧 :418 / 新 :380 同落 alert message 闭包尾（D-AR1-2 申报的 offset=38 与亲测 legacyBody 起点 :248→:210 恰合） |
| -U0 全 hunk 归属 | `git diff -U0` | 4 hunk：:186 注释单行 + :192+6 注释 + :195,46→201,2 臂收窄 + :769+732,97 文件尾 struct——全落 gate-false 臂/文件尾，legacyBody 段零 hunk |
| ExportQueueRebuildModifier 恰一定义 | grep -c | 1 |
| InspectorPageMount 恰一定义 | grep -c | 1 |
| 根 body 只剩装配 + Mount | 读 :170-196 | `WorkspaceHostView(...)` + `.modifier(InspectorPageMount(...))`，exportPageActive/filmPageActive 根级读消灭 |
| onChange 迁 modifier | grep | :824 命中落文件尾 ExportQueueRebuildModifier 体内；根 body 零命中 |
| focusedSceneValue 求值内容零改 | 基线 :228-233 vs Mount 内 | `\.exportPanelRequest` Binding get/set 逐行恒等，仅挂载宿主变化——禁区①核过 |
| binding 腿逐行平移 | 基线 vs Mount | get OR-term / set dismiss 双关（!visible → closeExportPage + closeFilmPage；present no-op）逐行恒等 |
| WorkspaceRouting/LibraryLegacyGate 零 diff | git diff | 全空 = PASS |
| LibraryProjectController 零 diff | git diff | 空 = PASS |

### T3（M5 Film/Drt 面板节级拆分 + m2②③ + m9/m11/o9）——**PASS**

| 验收标准 | 判据（亲跑命令） | 结果 |
|---|---|---|
| 七子 View struct 落位 | grep | SessionControlsView/LatitudeSectionView/PlacementSectionView（FilmPanelView :124/:295/:451）+ DrtMethodCard/DrtEncodingGroup/DrtLimitingGroup/DrtPresetGroup（DrtPanelView :154/:184/:278/:313）各恰一 |
| 六节 private var 零命中 | grep -E 七名 | 零命中 |
| m11 | `State(initialValue: DrtPanelModel` 零命中 + 读 DrtPanelView :27-60 | `@State model?` + 干净 init + body `if let model` 包裹 + onAppear 惰性建（FilmPanelView 定式对齐） |
| m2② 缓存终形 | 读 DrtPanelModel diff | 值键 memo（`@ObservationIgnored (record, isCustom)`）——stableHash 键形按 F-3 否决正确（键计算成本 ≥ 被缓存比较 + KD-3 三级读无写点钩子 = 失效洞）；hit 路径一次 `DrtRecord ==`（≈65 场）严格低于 `isCustomLook` 最坏 7×53 场——D-AR1-5 成本证据成立 |
| m2③ 缓存终形 | 读 FilmPanelModel diff + grep | layer-leg memo + **五写面刷新**（addPlacement :400 / commitPlacement :425 / tickPlacementRecord :476 / resetPlacementSide :524 / stepM :558）+ 每读活真相校验（instanceRecord + adjustmentLayer(id:) 可观察读 = 依赖注册保持）；base-chain 腿不 memo——D-AR1-6 成立 |
| 条件分支形态保持 | 基线 vs 现 body | `if !model.hasImage → if model.isPristine {enableEntry} else {…}` 结构逐位同构，零新增条件卸载 |
| D-H1 绑定链零漂移 | 全 App/Sources 四名 pre/post 逐文件 | setLiveParams 20→20（21 含 API.md 文档面）/ commitFilmEdit 3→3 / recordDrtChange 5→5 / setFilmLive 2→2，逐文件恒等（obs-1 记账措辞见上） |
| m9 :339 拼接消灭 | grep verbatim 拼接形 | 零命中；改为单 `latitude_share_value` 格式键（label 键作参，:384-393） |
| m9 :498-509 并排 Text | 读 :584-600 | 读出行 = 并排独立 Text（label Text + 数值 `Text(_, format:)` + verbatim 分隔），既有 latitude_readout_* 键零触零新键；`String(format:` 仅剩 :530 Stepper 数字标签（基线 :450 既有范围外形态） |
| scopes 面零 diff | git diff '*Scope*' | 空 = PASS |
| xcstrings 恰 +1 键纯插入 | numstat 17+/0- + diff 实形 | `latitude_share_value` 尾块纯插入（en/zh 同 `%@ %lld%%`）；label 三键 zh 值存活（低于/容纳/高于）——**+1 越带下界外，D-AR1-7 理由链成立**（三键形强迫删历史键或改 zh-audit allowlist，均碰更硬红线；单格式键零孤儿 audit PASS） |
| zh-audit 双 PASS | 亲跑 `--check` + `--self-test` | `PASS (1710 source keys, 1958 catalog keys, 38 interp…)` + `SELF-TEST PASS`——与 D-AR1-7 终账逐字一致 |
| o9 会话下沉 | 读 EditorAdjustmentStackView diff | `@State (pageSession, pageSessionScope)` + onChange(of: activeLayerID) 写点重装 + 竞态构造回落——D-AR1-11 形 |
| DrtPanelModelTests +2 法 | git diff \| grep '^\+.*func test' | `testCustomLookMemoHitStaysSemanticallyIdentical` + `testCustomLookMemoRefreshesOnRecordChange`；文件 9→11 法 |
| LibraryProjectController 零 diff | git diff | 空 = PASS |

### T4（M3 Filmstrip id 记账）——**PASS**

| 验收标准 | 判据（亲跑命令） | 结果 |
|---|---|---|
| visibleIDs Set<Int64> 恰一声明 | grep | FilmstripModel（FilmstripView.swift :33 类内）:51 `private var visibleIDs: Set<Int64> = []` |
| visibleIndices 全域零命中 | grep App/Sources Tests | 零命中 |
| firstIndex(where:) 两文件零命中 | grep FilmstripView LibraryGridView | 零命中 |
| id API + warmWindow 终形 | 读 :56-162 | rowAppeared(id:)/rowDisappeared(id:)/listDisappeared/scrollAnchorID/select/requestedIDs 形态保持；refreshWindow 单次 `makeIDToIndex()` 建 map 复用（剪枝 formIntersection + warmWindow 双消费）；`warmWindow(idToIndex:) Range<Int>` 语义零改（D-AR1-11 双面形） |
| View 侧直传 row.id | 读 FilmstripView :194-220 邻域 | 双 firstIndex 反查摘除 |
| pager.cellAppeared(at:) 零改 | pre/post grep | LibraryGridView :57 签名逐字同 |
| enumerated 携带 index | 读 LibraryGridView :139 | `ForEach(Array(grid.rows.enumerated()), id: \.element.id)`（D-AR1-11 Array 包裹形，身份仍 row.id） |
| `.disabled(holdsControl)` 逐字节保留 | pre :169 vs post :206 行内容 | 逐字同（行号漂移 = obs-2） |
| fixup stale-window 新回归 ≥1 | git diff 测试文件 | +2 法：`testMidCollectionInsertKeepsTheWindowCorrectWithoutStaleIDsOrInflation` + `testRowsVanishingFromTheCollectionPruneTheVisibleSet`；文件 6→8 法 |
| LibraryGridModel 零 diff（fixup 锚） | git diff | 空 = PASS |
| Project.swift 零 diff | git diff | 空 = PASS |

### T5（定向轮 + D-6 探针 + 走查配方 + 收口文档）——**PASS**（机检面；测试/探针终值见 §5-§7）

| 验收标准 | 判据 | 结果 |
|---|---|---|
| ΔN 记账 | FilmstripModelTests 6→8（+2）/ DrtPanelModelTests 9→11（+2） | 合计 +4 = 申报值；3963+4 = 3967 落带 3964..3970；T4 下界 ≥1 兑现 |
| SUMMARY ΔN 对账表 | 读 SUMMARY | 与亲核一致 |
| DECISIONS 偏差登记 | 读 DECISIONS D-AR1-1..11 | 11 条全在案，逐条复核见 §8 |
| MANIFEST 落盘 | `.work/gui-acceptance/audit-repair-a/MANIFEST.md` | 在盘内容完整——**路径偏差 minor-1** |
| token fixup 归因 | 读 fixup diff + 测试性质 | 源码 token manifest 测试（读源文本断言 contains）——T1 改 `.disabled(isReadOnly \|\| holdsControl)` 后字面漂移，行为面不变；窗内归因正确，fixup 正当 |
| D-6 禁区八面 | 亲核：menus/focus 挂点零 diff（:183/:228-233/:287-288）/ 双 safeAreaInset 形 / .inspector 形态 / 三段结构（topBar + ZStack switch + BackgroundTaskBar）/ 探针执行记录 / AX 轻用（定点断言形）/ o6 不动（diff 面无 LutPanelView）/ legacy 燃料面零触（legacyBody byte-frozen + LibraryLegacyGateTests 零 diff） | 全 PASS |

## 3 红线机检电池（全量亲跑）

| 项 | 判据 | 结果 |
|---|---|---|
| 封存面零 diff | IOP 全域/*.metal/LightamerSidecar/DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels/DrtEotf/ExportQueueContract/NodeGraphCommand/HistoryStack/HistoryHash/PipelineDocument/V50Order/NodeOwnershipCatalog(GradeCatalog)/Registry/ModuleInstance | **零命中 PASS** |
| FIX2③ | LibraryProjectController.swift 零 diff | **PASS** |
| ToastFaceTests 零 diff | — | **PASS** |
| legacyBody byte-frozen | F-6 offset 适配版零输出（亲测 offset=38 与 D-AR1-2 一致） | **PASS** |
| M2LIB-06 通道 | LibraryLegacyGateTests 零 diff（绿 → §5 App 轮亲跑） | **PASS（diff 面）** |
| xcstrings 纯插入 + 键数 | 17+/0-、恰 +1 键（越带下界外，D-AR1-7 申报在案） | **PASS（带申报）** |
| zh-audit 双 PASS | --check + --self-test | **PASS** |
| UserDefaults 零新键 | diff 全批 @AppStorage/UserDefaults 面 = 仅 `layout.inspectorWidth` 同键复用（D-AR1-4） | **PASS** |
| `.runModal(` App/Sources 零命中 | grep | **PASS** |
| `String.LocalizationValue("prefix_` 零命中 | grep | **PASS** |
| Project.swift / BUNDLE-MAP 零 diff | 全批文件清单 | **PASS** |
| A/B 零交集 | 全链 diff 无 UI/Inspector/ 域文件（含 coordinator 字面命令 `git diff 8e3bd59d^..8e3bd59d -- …/UI/Inspector/`） | **PASS** |
| D-6 禁区面 | §2 T5 行八面 | **PASS** |

## 4 偏差复核（D-AR1-1..11 逐条判「等价终形成立」）

| 偏差 | 复核结论 |
|---|---|
| ①D-AR1-1 C 路并入条款 | **成立**——C 路合并 MANIFEST 未落盘（本验收同法检索 `.work/` 确认），静态基线形态 + 条款活线处理正确 |
| ②D-AR1-2 F-6 offset 适配 | **成立**——内容域零输出 + hunk 归属面核双证；offset=38 亲测吻合；冻结语义严格保持 |
| ③D-AR1-3 topBar 窄值形 | **成立**（SC 字面为准）——isReadOnly/holdsControl 读点留宿主 = 罕见事件路径仍重估宿主 body；D-6 探针（idle CPU）不受扰；晨审可翻面已如实登记 |
| ④D-AR1-4 Mount @AppStorage 同键复用 | **成立**——零新 UserDefaults 键（KD-4 字面满足）；`clamped` 内联 `CGFloat(min(max(w,200),460))` 数学恒等亲核 |
| ⑤D-AR1-5 m2② 值键 memo | **成立**——stableHash 键形确触 F-3 伪优化条款（键计算 ≥ 被缓存比较 + 无失效钩子）；落地形 hit 路径严格更廉；两腿回归在册 |
| ⑥D-AR1-6 m2③ 五写面 + 活真相校验 | **成立**——五写点刷新逐一亲点；校验读同源可观察面 = 依赖注册保持无 stale UI；base-chain 不 memo 判断合理 |
| ⑦D-AR1-7 m9 恰 +1 键越带 | **成立**（申报在案）——+1 在带 +2..3 下界外，但三键形二选一皆碰更硬红线（删历史键违零触碰 / 改 zh-audit allowlist 出 files_modified）；单格式键 + label 作参 = 零孤儿 + audit 双 PASS + zh 语序由格式键承载（三 share 平行结构同形语序，per-key 语序自由收益为零）——理由链闭合 |
| ⑧D-AR1-8 FilmstripModelTests 属 Library bundle | **成立**——Project.swift :584 + BUNDLE-MAP :384 LIB 行亲核；RESEARCH §7 errata 属实；T5 `--bundle App` 不含该件由 Library 补跑覆盖 |
| ⑨D-AR1-9 token fixup | **成立**——测试 = 源码 token manifest 断言（读源文本）；T1 字面漂移窗内归因正确；行为面（disabled 合并语义）不变亲核 |
| ⑩D-AR1-10 探针门值两案 | **成立 + 补强**——门值修订建议（相对门 ≤ 噪声带 / 绝对门绑 D-6 专项）逻辑自洽：FIX2 裁定①接受降级使 <10% 在基线树形永假，绝对门对树形改动行使必 FAIL 在窗外；本验收双构建差分亲测一轮为第二份证据（§7）。裁定权留晨审——验收侧认定：**(a) 相对门是唯一当下可行使语义；(b) 绝对门须与 D-6 专项立项绑定** |
| ⑪D-AR1-11 微偏差七项 | **成立**——task 合并形/init 形/Array 包裹/可选链降读/row 壳复制/静态助手原位/剪枝与双面 warmWindow/o9 回落窗逐一亲核与申报一致（「七项」实为八目，申报文内含 o9——计数口径小差，无实质） |

## 5 定向测试轮（亲跑）

- `--bundle App`：**919/4/0**，peakRSS=2832MB，365s（01:05 净窗轮；HEAD
  build-for-testing 刷新后独立跑）——与申报逐字兑现。
- `--bundle Library`（T4 测试域，D-AR1-8）：**738/4/0**，peakRSS=600MB，
  98s——与申报兑现（738/4/0；RSS 600 vs 执行批 622MB，方差内）。

## 6 全套 --all 独立复跑（亲跑，净轮终值）

**净轮 = `TOTAL|3967/35/0|2095s`（03:25 收官轮）——与申报
`TOTAL|3967/35/0|2142s` 计数逐值兑现**（ΔN 对账 3963+4=3967；skip 35 =
5+3+5+4+9+5+4 逐 bundle 吻合，零第三种 skip 来源；全程 MEMFAIL 零触发，
RSS 全束 <8G 运行门）。

| bundle | 申报 | 本验收净轮 | peakRSS |
|---|---|---|---|
| IOP | 687/5/0 | **687/5/0** | 7125MB（申报 7948） |
| IOPParity | 460/3/0 | **460/3/0** | 7667MB（申报 7741） |
| Layers | 494/5/0 | **494/5/0** | 817MB（申报 809） |
| Library | 738/4/0 | **738/4/0** | 623MB（申报 622） |
| Sessions | 284/9/0 | **284/9/0** | 1631MB（申报 1431） |
| Export | 385/5/0 | **385/5/0** | 6372MB（申报 6011） |
| App | 919/4/0 | **919/4/0** | 2832MB（申报 2832） |

- RSS 面注记：IOP 本轮 7125MB（执行批 7948 / 前一轮 7915）——同族面
  7125..7948MB 波动与贴线注记域一致，<8G 门维持；IOPParity 7667..8110
  跨轮波动（顺序漂移敏感族，SPIKE 注记域）。
- 前两轮残值（非净轮，留 §8 事故链）：第一轮 02:11 被杀（六束中已跑束
  全绿无 fail 记录）；第二轮 3967/35/**1**——唯一 fail =
  `AgentControlCoordinatorTests.testDisableFaceManifestLandsTheMergeForm`
  （编译态 HEAD token 断言被二路翻转的基线源码 → 假 fail，机理亲证：
  树还原后同测试 0.359s passed，第三次全套轮 App 919/4/0 兑现）。

## 7 D-6 探针双构建差分（亲测一轮，同协议）

协议 = MANIFEST AR-01-01 定稿形：AX 驱动 Open Recent（按 `editor-probe`
项目名匹配点击，防 recents 挤位）→ 进入编辑器 → **60s settle**（过 ~50s
LUT 预热）→ 30s 窗 6 采样（间隔 6s）取中位 + `sample 3` 栈旁证 + 截图 +
cliclick 铁条②。双构建 = 基线 `c5570b05`（独立 worktree + 独立
`-derivedDataPath` 构建）vs HEAD `8e3bd59d`（DD 容器 build-for-testing
刷新）。四轮 pid parentage 全 `parent=1`（launchd）。

| 面（60s settle 形） | 基线 `c5570b05` | HEAD `8e3bd59d` | Δ |
|---|---|---|---|
| 编辑器静置（Open Recent 重开 → ⌘E） | **90.1%** | **88.2%** | **−1.9%（HEAD 更低，噪声级）** |
| 空载无项目面 | **31.0%** | **31.9%** | +0.9%（噪声级） |

- **判定：双构建逐面差分 ≤ 噪声带 → 本批零越阈（相对门 PASS，第二份
  独立证据，与执行批 D-AR1-10 双构建等值结论互证）**；绝对门 <10% 维持
  D-AR1-10 判定（基线树形固有永假式，绑 D-6 专项），裁定权留晨审——
  本验收侧支持 **(a) 相对门** 行使语义。
- 铁条②（HEAD 构建亲测）：cliclick 点击左栏第二行 → acc5 选中环 +
  current dot + 视口渲染 + 直方图跟随（截图
  `/tmp/ar01-acc-probe/state-HEAD-after-click.png` 识读 PASS；基线构建
  同形 `state-BASE-after-click.png`）。
- 证据：`/tmp/ar01-acc-probe/`（cpu/parentage/sample/state 四件 × 双构建
  × 两面；local-only 即弃域，路径约定同 MANIFEST）。

## 8 流程注记（M2-7-3 先例留痕，非 AR-01 扣分项）

1. **测试宿主误杀事故**：本验收首轮 `--bundle App` 于 12:38AM 被第二路
   验收 GUI 臂裸 `pkill -x Lightamer` SIGTERM（host exit=143，RSS 2832MB
   未越门，杀前各 suite 逐个全绿）——验收编排事故，已上报 orchestrator
   下发整改（①禁裸 pkill 核 parentage ②旧容器作废换 HEAD 构建 ③GUI 臂持
   `/tmp/la-audit-repair-gui.lock`）。本验收测试轮全部按锁窗口净轮重跑，
   终值取净轮。
2. **基线构建网络坑**：worktree `tuist generate` 两轮失败 = 会话残留代理
   env（`http_proxy=127.0.0.1:10809`，daemon 已停）阻断 libwebp-Xcode 的
   libwebp submodule 克隆；直连 GitHub 可达，`env -u` 清代理后过——后续
   双构建验收直接用独立 `-derivedDataPath` 时注意清代理 env。
3. **锁协议实录**：全套 `--all` 前持 `/tmp/la-audit-repair-all.lock`
   （mkdir 原子占位 + pid 记名 + 死 pid 亲核自愈）；二路 --all
   （01:13-01:42）期间我方按规等待，其释放后我方 01:42:31 拿锁——串行
   无撞车，协议工作正常。
4. **--all 包装任务被杀事故**：第一轮 --all（01:42 起）包装任务 02:11 被
   外部 SIGKILL（exit 137；被杀前宿主 RSS 5590MB 远低于 8G 门，非
   MEMFAIL；凶手无认领）。处置 = M2-7-3 留证（
   `/tmp/ar01-acc-all-kill-evidence.txt`）+ 孤儿锁（死 pid 91478）由带
   pid 亲核的自愈 runner 释放并原子重取 + 复跑改 `nohup + disown` 完全
   脱离会话形态（抗任务级清理）。
5. **共享主树翻转事故（第二轮 App 假 fail 根因）**：git reflog 钉死
   01:41:22 `checkout: moving from main to c5570b05`（非本路操作——本路
   基线构建走 `/tmp/ar01-acc-baseline-wt` worktree，不触主树）——主树被
   翻至基线且滞留，致第二轮全套轮六个无源码断言 bundle 全绿、恰 App 束
   的源码 token manifest 测试（编译态 HEAD token 断言盘上源码）假
   fail。处置 = 树还原 main/8e3bd59d（跟踪面零修改）+ 同测试复跑
   0.359s passed 亲证机理 + 第三次全套轮净轮兑现。**教训（供编排批）**：
   并行验收窗口内共享主树 = 共享可变状态，任何一路的 checkout 翻树都会
   打爆另一路编译态测试对盘上源码的断言——基线/双构建一律 worktree。
6. **净轮口径**：终值取第三轮（03:25 收官，`TOTAL|3967/35/0|2095s`，
   干净窗口 + 树态正确）——前两轮残值留证于 §6/本节，非终值。

## 9 残留清单

1. **minor-1**：MANIFEST 路径偏差（`audit-repair-a` vs plan `audit-repair`）——补改名或 plan 勘误一条即消。
2. **obs-1/2/3/4/5**：见结论头。
3. **执行批已知事项移交面**（维持）：ThumbnailBridge flake 族挂账（本验收三连全绿未再现，族本身维持挂账观察）/ IOP・IOPParity 贴线 RSS 注记 / o6+m10+o4 挂账 / M2 = plan B 零触（A/B 交集红线兑现）。
4. **D-AR1-10 门值修订**：呈晨审裁定——本验收 §7 差分（90.1→88.2 /
   31.0→31.9）为第二份独立证据，支持相对门语义。
5. **C 路并入条款**：活线——C 路 MANIFEST 落盘后 B/C 批开工前重算基线并
   差分申报（D-AR1-1 维持）。
6. **并行验收编排债**：共享主树翻树禁令 + GUI/测试窗口锁协议 + 杀进程
   parentage 纪律——三条已在上报链中向 orchestrator 提出，随本批验收
   闭环移交编排侧沉淀（§8.3/8.4/8.5 先例形）。
