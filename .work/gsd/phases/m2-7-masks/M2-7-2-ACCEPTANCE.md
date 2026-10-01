# M2-7-2 ACCEPTANCE — 面板与交互（缩略 GPU pass + Mask Groups 面板 + 手柄/Default Behavior/Range/AI 入口 + Follow Edges 接线 + 乐观并发）独立验收

> 验收：ZCode 验收 subagent，2026-10-01。对象 = 执行方 9 commits（`4e8299c`..`24f711f`，
> 正本 = checker 修正版 `7b88bbb`：E1 Default Behavior 消费 M2-3 面 / E5 校验先于 bump /
> E6 Follow Edges 接线 + coordinator seam / M4 mapper 入参 / M5 panelMenuCases 白名单，
> 全部落地）。方式 = AC 11 条逐条核对 + 六重点定向抽查（实现亲验 + 测试真伪判读 +
> grep/git 机检 + 修复前后截图并读）+ 两域独立复跑。
> **结论头：PASS / 0 error + 1 minor（已修 `1ce8e8e`）。**

## 一、复跑 vs 声明

两域定向独立复跑（`caffeinate -dis Scripts/test-direct.sh` 直启，L028 双读）：

| 域 | 声明 | 本轮独立复跑 | 判定 |
|---|---|---|---|
| App | 429/0/0 | **429/0/0**（173s，peakRSS 1210MB） | ✅ 逐值一致 |
| Layers | 298/3/0 | **298/3/0**（23s，peakRSS 1041MB） | ✅ 逐值一致 |
| 全套 | TOTAL\|2525/16/0\|882s EXIT=0（基线 2493+32） | 两域实测含全部 32 新增测试（+19 App / +13 Layers 精确对账：9+8+3+5+4+2+1）；其余五域源文件零 diff（`git diff --name-only 93ca9e7..HEAD` 亲核） | ✅ 覆盖变更面，与声明对账一致 |

skip 持平（App 0 / Layers 3 既有）；MEMFAIL 未触发（峰值 <8G）。+32 对账：T1 +9、
T2 +8、T3 +3、T4 +5、T5 +4、T6 +2、T7 +1 = 32，与 SUMMARY 精确一致。

## 二、六重点核查结论

### ① E1 Default Behavior 消费面（checker 勘误落地亲验）

**判定：纯消费者兑现，零自起载体。**

- 双键残留 grep：自起枚举 `MaskDefaultBehavior` 代码零命中（仅 plan/CONTEXT 历史文档
  在案）；自起键 `mask.defaultBehavior` 代码零命中（同前）。
- 复用载体三件全对表：枚举 `MaskDrawBehavior`（AppPreferences.swift:25 零 diff）、键
  `mask.behavior.default`（:67-71 零 diff）、`SettingsDefaultBehaviorPage` diff 仅
  hint 一行（去「Takes effect with the mask editor (M2-7)」前瞻括注，git diff 亲核
  唯一 hunk）。
- 完成时三分流实现亲验（LayerEditingState `maskDrawInteractionDidComplete`）：
  `guard didCommit` 门（no-op tap 永不触发）→ exhaustive switch 零 default——
  `currentNode` = break 零动作；`newLayer` = `migrateMaskToNewLayer`（EditorState:541
  亲读：源层 `stripped.mask = nil` + 新层载 mask 同一 stack snapshot，恰 1 次
  `commitLayerStructure`，`hasDrawnForms` 前置 guard）；`ask` = `pendingMaskBehaviorAsk`
  一次性 sheet（confirm 走同一 migration，选择不持久）。resolver 注入式
  （:321 默认读 AppPreferences，测试注常量）；五触点视图文件
  `UserDefaults|ProcessInfo` grep 零命中。SettingsPagesTests 零改动（diff 空亲核）。

### ② E5 校验次序（先校验后 bump 实现亲验 + 分派测试真伪）

**判定：时点/次序/分派三钉全中。**

- 快照时点亲验（MaskOverlayRecord.appendForm）：`layer.mask = spec` →
  `applyLiveLayer`（live 腿零 bump）**之后** `expectedRevision = layer.mask?.contentRevision`
  ——press 段写毕后现值 N；mutateForm 首改兜底 `if expectedRevision == nil`。
- 校验次序亲验（endInteraction）：先 `MaskSpec.matchesExpected(expectedRevision, live)`
  门，相等路径**才** `live.mask?.bumpContentRevision()` → `commitLayerEdit`——先校验后
  bump，正常笔画恰 +1 不走重放；失配 + append 型 = 重放（重读 live spec → id dedup
  重装 appendedForms → bump merged 值 → 恰 1 item → toast）；失配 + mutate-only =
  拒绝（零 history 零 bump + toast）；defer 恒清理。
- 测试真伪：快照时点 pin（第二次交互 snapshot == post-bump 值 1）＋ 重放测试用**真
  AI 提交通道**（`AIMaskEditing.commitRasterMask` 真实 mid-stroke 穿插，非手工改
  spec）断言 history 恰 AI+replay 两 item / merged revision 2 / 同 form id / raster
  存活 / toast——能揭穿「先 bump 后校验」或「快照时点错误」实现；拒绝测试断言零
  bump 零额外 item。三测试与实现逐段对表通过。
- in-flight form 存活语义（live 对象共享使 AI sibling 快照携带在途 form，重放 dedup
  保单一 form）——测试 NOTE 注记与实际断言一致，诚实申报非掩饰。

### ③ E6 Follow Edges 接线（READ seam + 交互腿 + 测试真伪 + 穷举）

**判定：seam 裁决落地，交互腿真，测试真。**

- READ seam 亲验（PipeCoordinator diff additive-only）：`followEdgesSurface` =
  截断栈（base + 严格在下层）经**既有** `RenderPipeline.processComposite`（preview 后
  缓存暖；零 walk 逻辑、零 driver/pipe diff——`LayerCompositeDriver`/`PixelPipe`/
  `PipeCacheKey` 零 diff 机检亲跑）；prefixHash = Hasher 折叠（imageID⊕base⊕下层
  id+chain records，PipeCacheKey Hashable 先例，进程内不持久）；`edgeMapField` =
  cache-or-compute 经 `FollowEdges.edgeMap`（MetalContext 唯一路由）+ L014 fence
  `readEdgeMap`。缓存位置偏差（coordinator 自持 8 条 dict vs P1 `PipeCacheKey.edgeMapKey`）
  DECISIONS §三-4 有据（Core internal 键类型 + PipeCache.swift 申报集外）。
- 交互腿亲验（MaskOverlayHost `followEdgesInteraction`）：press（grab == nil）= seed →
  seam → edge map → walker → `BrushStroke` → appendForm live 腿 → grab 上臂；drag =
  chain 重走经 mutateForm 替换 points（newest-wins generation guard 防过期异步写）；
  空链 = **零 append** + `followEdgesDegraded` 状态条——降级语义真。
- 合成边缘场测试真伪：fieldReader 注入的只是 surface——edge map 生产 = **真 kernel**
  （`FollowEdges.edgeMap` Sobel pass）+ 真 fenced readback；column-32 luma 阶跃场 →
  点链逐点 `x*63 == 32 ± 2` 贴边断言 ≥8 点 + 恰 1 bump + 恰 1 item。能揭穿假接线
  （walker 不吃真边缘场则贴边断言必红）。
- 穷举机检：五触点文件 `default:` grep 零命中（唯一命中为
  LuminanceColorRangePanelView:350 **注释文字**提及——非代码 arm，亲核）；dragGesture/
  commitLabelKey/`.followEdges` 臂显式在案；`MaskToolbarView` ForEach 走
  `MaskTool.allCases` 自动纳入（`mask.tool.followEdges` AX pin 更新同步）；
  `AIMaskEditing:127` 缺省参数值非 switch，实证不受影响。
- 观察项（非缺陷）：空链降级测试的 flat field 分支实际经 surfaceProvider nil 短路
  （flat field 未被消费）——walker 阈值内空链路径由 P1 FollowEdgesTests 覆盖，chain()
  guard 极简，可接受。

### ④ panelMenuCases 白名单（checker M5 防复发）

**判定：白名单唯一消费，CaseIterable 裸消费已绝迹。**

- 定义（LayerEditingState:109 五项显式表）+ 唯一菜单消费点（LayersPanelView:396
  `ForEach(MaskCommand.panelMenuCases)`）+ 测试钉（panelMenuCases 不含 add/remove、
  allCases == 7）。
- `MaskCommand.allCases` 全仓 grep 零消费点（唯一 `allCases` 裸消费 =
  `MaskTool.allCases` 工具 radio——语义即「全 case 自动纳入」，正确行为）；未来新
  MaskCommand case 不经白名单不可能泄漏进层菜单——防复发结构成立。
- 两 case payload-free 亲验（enum 声明无关联值，CaseIterable 合成存活）+ 删除目标
  itemID 走 `performMaskCommand(_:itemID:)` 执行缝，nil 缝静默 no-op。

### ⑤ 申报外三文件定性（逐个核）

**判定：三处全部必要且定性诚实，无一越权。**

1. `EditorAdjustmentStackView.swift`（+19 行）：面板挂载（`.layersPanel` 槽
   MaskGroupsPanelView + LuminanceColorRangePanelView + 层面板 + toolbar link）+
   `pendingTabRoute` 消费端（onChange 设 selectedTab + 清位）——**无此文件则两个新
   面板不可达、Locate 联动无消费端**，必要性成立；diff 亲读零越界逻辑。
2. `LayerUIWiringTests.swift`（5 行）：五工具 AX pin → 六工具——`.followEdges` 入
   radio 集的出货面后果，pin 与交付面一致是 E4「断言与交付面一致」的正确方向。
3. `evidence/m2-7-2/*.png` 三张：T8 走查证据，plan 申报落点（evidence 节），归属
   正当。

### ⑥ T8 LazyVStack 观察域缺陷修复真伪（修复前红）

**判定：缺陷真、修复真。**

- 修复前截图（panel-before-fix-empty-hint.png 亲读）：面板显示 `mask_groups_empty_hint`
  空态，同帧下方层面板存在「调整 1」adjustment layer——层在而面板空 = 缺陷实拍。
- 缺陷机理成立：`document?.maskGroups` 读在 LazyVStack 延迟内容闭包内，@Observable
  读取未注册进 body 观察事务，stack 变更不触发面板重渲。
- 修复 diff（db8a211）：`let groups = document?.maskGroups ?? []` 提到 body 作用域 +
  `return`——读取回到观察事务内；9 行最小修，回归双绿（App 429/0/0 本轮复跑为证）。

## 三、11 条 AC 逐条判定

| # | AC | 判定 | 证据 |
|---|---|---|---|
| 1 | 缩略三腿 + 混合 + 键失效（stableHash⊕尺寸档）+ 空载荷 nil + LRU 封顶 + 纵横比保形（checker M4） | ✅ | MaskThumbnailRendererTests 9/0/0（aspect 窗规则/键失效重渲内容差/LRU touch 存活/空载荷零缓存入账断言亲读）；renderer fence :241-243 亲验 |
| 2 | 面板投影 grade 序 + 属性恰 1 item + undo round-trip + add/remove 保 UUID + 层菜单白名单五项 | ✅ | MaskGroupsPanelTests 真链 9 法全绿（白名单钉 :236-243 亲读） |
| 3 | 删锁拦截（零 history + toast）+ 锁标记 | ✅ | 拦截测试断言 toast+零 item+form/items 计数不变+锁位存活；既有拦截族全绿（双域复跑） |
| 4 | 双 grips + expectedRevision 分派 + 相等路径恰 +1 不重放 + 恰 1 commit | ✅ | §二②；MaskRevisionTests +3 真伪判读通过 |
| 5 | Default Behavior 完成时三分流 + 注入式 grep + SettingsPages 单行 diff | ✅ | §二①；grep/diff 机检亲跑 |
| 6 | Range golden ≤1e-4 + 写穿 round-trip + boost 档 + 零新 MaskType | ✅ | RangePanelMappingTests 4/0/0（gray Cz<1e-4/round-trip 1e-9/写穿 packed 回读/boost pin 亲读）；MaskSpec 零 diff 机检 |
| 7 | Follow Edges 贴边 stroke + 空链降级 + 穷举零 default + driver 零 diff | ✅ | §二③；`git diff --name-only` 红线文件零命中亲跑 |
| 8 | AI sugar 装配 + 重烤语义不变 + AIMaskEditing/AIMaskService 零 diff | ✅ | sugar round-trip 测试（真提交通道 invert 位 + 同 fileName 覆盖 + 恰 1 bump 1 item）；AIMaskEditing 零 diff 机检（AIMaskService 文件本 plan 零 touch） |
| 9 | GPU 唯一路由 grep 零命中 | ✅ | `MTLCreateSystemDefaultDevice\|makeCommandQueue` 于 renderer 零命中亲跑 |
| 10 | 全套 0 fail（2493+32=2525） | ✅ | 两域独立复跑逐值一致 + 五域零 diff 文件面；--all TOTAL 采用执行方声明对账（+32 精确对账无差） |
| 11 | diff 边界 == 申报集 + 四新测试登记闭环 | ✅ | 变更文件集 = 申报集 + 申报外三处（§二⑤ 全部定性成立）；Project.swift 四命中 + BUNDLE-MAP 四行双登记（数字列漂移 = 本轮 minor，已修 `1ce8e8e`） |

## 四、Findings

- **0 error。**
- **1 minor（已修）**：BUNDLE-MAP method-count 列三行漂移——RangePanelMappingTests
  5→4、MaskGroupsPanelTests 10→9（登记时预写数与文件实况差 1）、MaskRevisionTests
  6→11（M2-7-1 基数未随 T3/T6 扩测更新）；「行内 method 数以终态对账为准」口径下
  随验收 commit 修正 + 勘误注记（M2-4-3 先例），`1ce8e8e`。
- 观察项（非缺陷，留档）：①空链降级测试 flat-field 分支经 nil-surface 短路（P1
  walker 测试覆盖阈值内空链）；②吸管 golden 为性质级断言（同链推导 + round-trip
  1e-9 + BlendOpParity 族先钉 IOP 链）非独立绝对数值——单源守护意图成立；③
  edgeMapFieldCache 逐出 = dict first-key（非严格 LRU；DECISIONS 只声明 bounded，
  语义正确）；④E3 挂账五 GUI 交互点实操证据未取得（DECISIONS §四在案）——修复后
  「组卡片显示」实拍亦无（同 E3 性质，逻辑面 MaskGroupsPanelTests 钉）。

## 五、翻账清单

`.work/gsd/REQUIREMENTS.md`（本批同 commit）：

- M2MASK-04 ✅ 载体兑现注记追加（五属性面板消费面 commitMaskEdit 统一缝 + 锁删行级
  拦截 + nextLayerName 单源；M2-7-1 Delivered 行不动）
- M2MASK-05 ✅ [ ]→[x] Delivered（Follow Edges 接线 + Luminance/Color Range +
  AI Subject sugar 三件全清；锚 `f9601c2`/`35ea75c`/`b95f033`，验收本文件）
- M2MASK-06 ✅ [ ]→[x] Delivered（缩略 GPU 管线 + Mask Groups 面板 + 双羽化手柄 +
  Default Behavior 完成时消费 + 乐观并发接线；锚 `4e8299c`..`db8a211`，验收本文件）
- M2MASK-07 不动（M2-7-1 已翻）

## 六、验收方式与范围声明

- 复跑命令：`caffeinate -dis Scripts/test-direct.sh --bundle App|--bundle Layers`
  （直启宿主，L028 Executed+failures 双读）。
- 实现亲验文件：`MaskOverlayHost.swift`（MaskOverlayRecord/FollowEdgesInteraction/
  交互腿/commitLabelKey）/ `LayerEditingState.swift`（MaskCommand/panelMenuCases/
  分流面）/ `EditorState.swift`（migrateMaskToNewLayer/applyLiveMaskEdit/
  commitMaskEdit）/ `PipeCoordinator.swift`（READ seam diff）/ `MaskGroupsPanelView.swift`
  （db8a211 diff）/ `SettingsPages.swift`（diff）/ `AppPreferences.swift`（零 diff 复核）。
- 测试真伪判读文件：`MaskRevisionTests.swift`（diff 级 +3+2）/ `MaskGroupsPanelTests.swift`
  / `MaskThumbnailRendererTests.swift` / `RangePanelMappingTests.swift`（断言级抽读）。
- 截图证据并读：panel-before-fix-empty-hint.png / mask-page-mounted.png。
- 未覆盖声明：IOP/IOPParity/Library/Sessions/Export 五域未独立复跑（本 plan 九
  commits 零触该五域源文件，`git diff --name-only 93ca9e7..HEAD` 为证）；全套 --all
  数字采用执行方声明对账（+32 精确对账成立）。GUI 交互实操五点依 E3 挂账留人工/
  M2-7-3。
