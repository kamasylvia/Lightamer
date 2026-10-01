---
phase: m2-7
plan: "M2-7-2"
title: "面板与交互——MaskThumbnailRenderer GPU 缩略 pass（缓存键 = stableHash，OQ-3 A）+ Mask Groups 面板（PipelineDocument.maskGroups 投影 + item 编辑 + add/remove 命令 + 锁删标记/Locate 提示，OQ-7 A）+ radial 双羽化手柄 overlay 扩展 + Default Behavior 消费接线（复用 M2-3 既有面，完成时点，OQ-8 A + checker E1 勘误）+ Follow Edges 工具接线（MaskTool case + coordinator 取面 seam + 交互腿，checker E6）+ Luminance/Color Range 快捷面板（parametric 预设化 UI 皮，OQ-6 A）+ AI Subject 入口（subject+invert sugar，OQ-5 A）+ 乐观并发接线（expectedRevision 提交，OQ-9 收尾）"
wave: 2
depends_on: ["M2-7-1"]
autonomous: true
requirements: [M2MASK-04, M2MASK-05, M2MASK-06, M2MASK-07]
files_modified:
  - LightamerCore/Sources/Layers/Masks/MaskThumbnailRenderer.swift  # 新建：缩略 GPU pass——assembleUnmasked 复用（below/top = ramp 输入，KD-1）→ r32Float → 8-bit CGImage（L014 fence 读回）；签名含 GeometryPointMapper（checker M4 纵横比钉）；进程内 LRU 缓存键 = spec.stableHash() ⊕ 尺寸档
  - LightamerCore/Sources/Layers/Masks/ParametricMask.swift         # 修改（checker E4 显式落点）：吸管换算 extension（linear Rec2020 → JzCzhz，Core 单源——T5）
  - App/Sources/Lightamer/UI/Inspector/MaskGroupsPanelView.swift    # 新建：Mask Groups 面板——组 = PipelineDocument.maskGroups（grade 序）；行 = maskItems 投影 + 缩略图格 + enabled/invert/opacity/feather/displayName 编辑 + add/remove + 锁形标记 + Locate
  - App/Sources/Lightamer/UI/Inspector/LayersPanelView.swift        # 修改（checker E4）：层行 chip 切 renderer 输出（MaskChipView 退役，T2）+ MaskCommand 层菜单改 panelMenuCases 白名单（checker M5）
  - App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift          # 修改：radial 双羽化手柄（rim 内带/外带双 grips）+ 导引线 token 化 + expectedRevision 快照/校验接线（KD-6，checker E5 时点钉）+ Follow Edges 交互腿（T6）
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift          # 修改：Default Behavior 完成时消费接线（KD-4）+ Follow Edges 工具位/labelKey（T6）+ AI Subject「主体以外」入口
  - App/Sources/Lightamer/State/LayerEditingState.swift             # 修改：MaskTool 增 .followEdges case（T6）+ MaskCommand 增 addMaskItem/removeMaskItem 两 payload-free case（checker M5：执行缝带目标参数）+ Default Behavior 完成时分流面（注入式，body 零 UserDefaults）
  - App/Sources/Lightamer/State/PipeCoordinator.swift               # 修改（checker E6 seam 申报）：Follow Edges 只读取面一条——below 复合平面 texture handle + 前缀身份哈希；零 walk 逻辑触碰
  - App/Sources/Lightamer/State/EditorState.swift                   # 修改：面板 item 属性写统一缝（commitLayerEdit，history_mask_item_* 键族）+ Locate 选中联动（层选中 + 页签路由既有面）
  - App/Sources/Lightamer/Settings/SettingsPages.swift              # 修改（checker E1）：仅 SettingsDefaultBehaviorPage hint 文案一行（去「Takes effect with the mask editor (M2-7)」前瞻括注）——零新节零新键
  - App/Sources/Lightamer/UI/Inspector/LuminanceColorRangePanelView.swift # 新建：Luminance Range（luma 4 点梯形快捷面）+ Color Range（JzCzhz 吸管取色 + 范围/羽化）——数据全写既有 ParametricMask
  - Project.swift                                                   # 修改：新建测试文件登记对应 bundle sources 显式清单（bundle 无 glob；checker E2）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt      # 修改（checker E4）：四新测试文件登记行（纪律 6 实路径申报）
  - Tests/LightamerTests/MaskThumbnailRendererTests.swift           # 新建（**LightamerTestsLayers**，Core 级）：drawn/parametric/raster 三腿缩略 + 键失效 + 空载荷降级
  - Tests/LightamerTests/MaskGroupsPanelTests.swift                 # 新建（**LightamerTestsApp**，App 级）：面板投影/add-remove 命令/undo round-trip/锁删拦截/Locate 联动
  - Tests/LightamerTests/MaskDefaultBehaviorTests.swift             # 新建（**LightamerTestsApp**，App 级）：MaskDrawBehavior 完成时消费矩阵（checker E1：复用 M2-3 既有枚举）+ 注入式（body 零 UserDefaults 机检）
  - Tests/LightamerTests/RangePanelMappingTests.swift               # 新建（**LightamerTestsLayers**，Core 级换算）：吸管采样 → 梯形点换算 + boost 档
  - Tests/LightamerTests/MaskRevisionTests.swift                    # 扩展：overlay expectedRevision 提交/失配分派（append 重放/mutate 拒绝）+ Follow Edges 交互腿贴边断言（T6）
  - .work/gsd/phases/m2-7-masks/M2-7-2-SUMMARY.md                   # 新建（收口任务）
  - .work/gsd/phases/m2-7-masks/M2-7-2-DECISIONS.md                 # 新建（收口任务）
  - .work/GOAL-STATE.md                                             # 续接点追加（收口任务）
  - .work/LESSONS.md                                                # 如踩坑
---

# Plan M2-7-2 — 面板与交互（缩略图 GPU pass + Mask Groups 面板 + 手柄/设置/Range/AI 入口 + 并发接线）

> **性质**：UI plan——Core 只新增 `MaskThumbnailRenderer` 一个可单测小类型，其余
> 全部 App 面消费 M2-7-1 落定的数据/内核缝。规格锚点 = D-M2-7-CONTEXT-3/5/6/7/8
> （推荐 A 生效）+ REQUIREMENTS M2MASK-04/05/06/07。**纪律前提**：面板是
> `PipelineDocument.maskGroups` 与 `maskItems` facade 的**纯消费者**（单一事实源，
> OQ-7 B 已否决面板自持副本）；渲染管线红线（`PipeCacheKey`/`PixelPipe`/
> `LayerCompositeDriver` 零 diff）延续 P1。
>
> **本 plan 与 L031 的关系**：缩略 pass 与 PREVIEW 管线并发是本 plan 头号风险
> （KD-2 答复 = GPU 提交全部走 MetalContext 唯一路由获取点，禁止硬编第二条
> queue——L031 教训原文）。

## 已定裁决（不得重开）

- **D-M2-7-CONTEXT-3（OQ-3 A）**：缩略图 = GPU 缩略尺寸平面渲染 pass——小窗口
  跑既有 `DrawnMaskRasterizer`+`MaskCombiner` 出小 r32Float → 显示腿 → 位图缓存，
  键 = `MaskSpec.stableHash()`；`MaskChipView` CPU 示意被替代。
- **D-M2-7-CONTEXT-5（OQ-5 A）**：AI Subject 入口 = 零新内核 sugar——复用
  `AIMaskSource.subject` 生成 + invert 位装配一步成「主体以外」；生成参数不持久
  红线不触碰。
- **D-M2-7-CONTEXT-6（OQ-6 A）**：Luminance/Color Range = UI 按 Nitro 语义呈现、
  数据落既有 `ParametricMask`——Luminance = luma 域快捷面板（取亮部暗部 → 4 点
  梯形）；Color Range = JzCzhz 吸管取色 + 范围/羽化 → Cz/hz 通道曲线；**不暴露
  dt 14 通道全量 blendif 面**；吸管采样 = 显示平面像素 → domain 值换算（换算
  本 plan 钉，KD-5）。
- **D-M2-7-CONTEXT-7（OQ-7 A）**：面板 = 投影 + 既有命令面全复用——组序投影只读、
  拖组排序 = `NodeGraphCommand.reconnectGrade`（M2-4 OQ-9「一 mutation 两 UI 面」）、
  增删 item = `MaskCommand` 扩两 case、锁删 = deletionProtected toast 既有 +
  锁形标记、Locate = 层选中 + 页签联动既有路由。
- **D-M2-7-CONTEXT-8（OQ-8 A + checker E1 勘误，勘误注记见 CONTEXT）**：
  Default Behavior = **消费 M2-3 既有面** + 注入式求值——枚举 = 既有
  `MaskDrawBehavior`（`App/Sources/Lightamer/Settings/AppPreferences.swift:25`，
  ask/newLayer/currentNode）、键 = 既有 `mask.behavior.default`
  （`AppPreferences.maskBehaviorKey:38`）、Settings = 既有
  `SettingsDefaultBehaviorPage`（`SettingsPages.swift:146`，仅 hint 文案一行）；
  **消费点勘误 = 蒙版绘制完成时**（对表 M2-3 页面语义三处文字见证；OQ-8 原文
  「arm 时」作废——Alcedo 字面「Create a new layer, then draw」为 arm 时，
  以 M2-3 既有面为准，偏差入 DECISIONS）；视图 body 零 `UserDefaults` 直读
  （M2-1 D-EXEC-1 同款）。
- **D-M2-7-CONTEXT-9（OQ-9 收尾）**：overlay 提交腿带 expectedRevision（P1 已落
  数据面、bump 提交腿重挂与分派表（checker E5），本 plan 接线——快照时点 =
  press 段写毕后现值，校验次序 = 先校验后 bump）。
- **D-M2-7-CONTEXT-11（OQ-11 A）**：缩略 pass 增量成本 = O(缩略像素)/格；观察项
  （拖动实时性）挂 P3。
- **D-M2-7-CONTEXT-12（OQ-12 A）**：新 UI 键随手 `String(localized:)`，zh 滞后
  P3 对账（本 plan 预估 30-50 键：面板 + Range 面板 + Follow Edges 参数/工具
  + 入口/toast 族——**Default Behavior 设置节键已在 M2-3 在册**（checker E1
  复用既有面，本 plan 零新设置键，仅 hint 文案值更新一键）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 MaskThumbnailRenderer = assembleUnmasked 单入口复用 + ramp 输入

```swift
public struct MaskThumbnailRenderer {
    public static let thumbLongEdge = 112          // 尺寸档（KD 悬决回填：96-128 级取中）
    public static let cacheLimit = 64              // LRU 条目预算
    /// spec + 缩略窗映射器 → 8-bit 灰度 CGImage；缓存键 = spec.stableHash() ⊕ 尺寸档。
    /// mapper 由 caller 以缩略窗构建（checker M4：纵横比语义见下）。
    public static func render(
        spec: MaskSpec, size: Int, metal: MetalContext,
        mapper: GeometryPointMapper,
        maskDirectory: URL?, cache: inout ThumbnailCache
    ) async throws -> CGImage?
}
```

- **缩略窗纵横比语义（checker M4 KD 补钉）**：缩略窗 = **层窗口等比缩放**
  （短边 = `size`/`thumbLongEdge` 档，长边按层窗 aspect 派生——**非方形**）；
  mask 归一化坐标是内容窗口相对坐标，假方形窗 = 形状畸变（禁）。mapper 由
  caller 构建（`GeometryPointMapper` compose 恒等链同款：frameSize = 层窗口、
  outputSize = 缩略尺寸——`LayerCompositeDriver` 既有构建先例）传入，Core
  renderer 不自建管线态（可单测纪律）；drawn/raster 腿几何经 mapper 映射，
  parametric 腿在 ramp 上求值不受 mapper 影响（ramp 同值输入）。缓存键含
  尺寸档即含 aspect 档（同 stableHash 不同窗 = 不同键，正确失效）。

- **单入口 = `MaskCombiner.assembleUnmasked` 原样复用**：below/top 双输入平面 =
  **横向线性 ramp（x∈[0,1]）同值写入**（thumb 尺寸 r32Float，一次构建进程内
  复用）——drawn 腿不受输入影响；parametric 腿在 ramp 上求值即得「选择窗口
  可视化」（禁自绘曲线——内核单源纪律）；raster 腿走既有 `RasterMaskStore.load`
  + 窗口失配重采样腿（06-04 既有）。三 payload 混合层 = 同一入口自然合成。
  `layerOpacity: 1`（缩略图显示形状不折层透明度）。
- **缓存键 = stableHash（KD 必答）**：`spec.stableHash() ⊕ thumbLongEdge` ——
  编辑即换键（旧条目 LRU 逐出），失效零新代码（沿 `maskPosition` 缓存键族既有
  失效设计，CONTEXT OQ-3 原文）。缓存 = 进程内 dict + 简单 LRU（`cacheLimit`
  封顶），**不落盘**（缩略图可 O(缩略像素) 重算，持久化负收益）；栅格 ref 的
  PNG 完整性由既有 `maskHash` 把守，缩略不重复校验。
- **读回 = L014 fence 纪律**：r32Float → getBytes 前 fence（既有测试探针
  `drain()` 模式同款）→ 线性值 ×255 → 8-bit gray CGImage（alpha 平面 = 灰度
  显示，与 chip 既有黄线视觉语言解耦——像素真实优先）。nil spec/空载荷 = 返回
  nil，面板显示占位框（不崩不静默空白帧）。
- **面板 dumb**：面板只持 `(layerID, maskHash)` → `CGImage` 的行状态，渲染
  请求 `.task` 按需发；renderer 无 UI 依赖（Core 可单测，CONTEXT Specific
  Ideas 原文）。

### KD-2 并发纪律 = 唯一路由获取点（L031 教训正面回答）

- 缩略 pass 的全部 GPU 提交（ramp 构建/assembleUnmasked 内核链/读回）经
  `MetalContext` **既有唯一路由获取点**获取 encoder/queue——**禁止**新设
  专用 queue/硬编 editor queue（L031：identity blit 硬编 queue 在导出链上
  跨队列竞速产「两形态交替」假非确定）。
- 触发模型 = 面板可见行的按需 `.task`（一行一格，格完成即显示）——**不进
  pipe、不与 PREVIEW 帧竞争 command buffer 预算**（小平面 112px 级，单格
  提交微秒量级）；PREVIEW 渲染中到达的缩略请求自然排队（同路由 FIFO），
  不做节流新机制（D-M2-7-CONTEXT-11：不引入新节流）。
- 拖动实时性观察项挂 P3（超标 fallback = 拖动中缩略窗口平面预览、松手全精，
  OQ-11 预案）。

### KD-3 Mask Groups 面板 = 投影只读 + 命令面全复用（零第二存储）

- **数据源**：组 = `PipelineDocument.maskGroups`（grade 序投影，只读展示）；
  组内行 = `layer.mask.maskItems`（M2-7-1 扩展后含嵌套可达 setter；树的展示
  = top-level 行 + child 折叠节，P2 面板投影按 formID 平铺深度展开，**派生
  显示名消费 Core `nextLayerName` 单源**——M2-4-2 纪律）。
- **操作面分派表**（每操作恰一条 history item）：
  | 操作 | 执行面 |
  |---|---|
  | 拖组排序 | `EditorState.apply(.reconnectGrade(...))`（M2-4 OQ-9 既有） |
  | enabled/invert/opacity/feather/displayName | 三 setter → `commitLayerEdit`（`history_mask_item_*` 键族，EditorState 统一缝） |
  | 增 item | `MaskCommand.addMaskItem`（新 case：按当前工具缺省形建 form + item，一命令一 history item） |
  | 删 item | `MaskCommand.removeMaskItem`（删 item + 无他引用时连带删 form；deletionProtected 拦截沿用双腿 toast 既有） |
  | 锁删标记 | spec.deletionProtected → 锁形 modifier（M2-4 Specific Ideas 预制）+ clear/fill 既有拦截 |
  | Locate unfinished node | 选中蒙版 → 层选中 + 右栏页签路由到 Mask 页（EditorState 选中联动既有路由面）；unfinished（未启用 grade 上有蒙版）= 行角标 + 提示文案 |
- **add/remove 与 `MaskCommand: CaseIterable` 冲突裁决（checker M5，二选一之
  选 A = 执行缝带目标参数 + 菜单白名单过滤）**：`MaskCommand` 为
  `String, CaseIterable`（LayerEditingState.swift:80）且 `LayersPanelView.swift:387`
  层菜单裸消费 `ForEach(MaskCommand.allCases)`——增两 case 若带关联值会破坏
  CaseIterable 自动合成并泄漏进层菜单。裁决 = 两 case 保持 **payload-free**
  （护 CaseIterable 合成与 `labelKey` 族），**删除目标 itemID 作执行缝参数**
  传入（`applyMaskCommand(.removeMaskItem, itemID:)` 式）；层菜单消费点改
  **显式白名单** `MaskCommand.panelMenuCases`（duplicate/duplicateAndInvert/
  fill/clear/resetEdits 五项），add/remove 由面板蒙版行级按钮直呼、不进层菜单。
  选 B（另立 `MaskItemCommand` 独立命令面）否决理由 = 第二命令面复制
  labelKey/拦截/undo 语义族，违单一事实源纪律。
- **缩略图格** = KD-1 renderer 输出；`MaskChipView` CPU 示意从层行退役（层行
  chip 改渲染同一 renderer 输出——一处视觉语言，两处消费）。
- **联动选中**：面板行选中 = `editingState.selectLayer + setTool(nil)`；
  overlay 手柄跟随既有 `showsMaskOverlay` 门（零新机制）。

### KD-4 Default Behavior = 消费 M2-3 既有面 + 完成时分流（checker E1 重裁）

> **checker E1 勘误**：原 KD-4 自起枚举/自起键/新 Settings 节作废——M2-3-3 T5
> 已交付全部载体，本 plan 是**纯消费者**；消费时点经对表 M2-3 页面语义裁决为
> **完成时**（勘误注记见 CONTEXT）。

- **复用载体三件（零新造）**：
  | 载体 | 位置 | 本 plan 动作 |
  |---|---|---|
  | 枚举 `MaskDrawBehavior`（ask/newLayer/currentNode，CaseIterable Sendable） | `AppPreferences.swift:25` | 直接消费，零新枚举 |
  | 键 `mask.behavior.default`（`AppPreferences.maskBehaviorKey`） | `AppPreferences.swift:38` | 直接消费，零新键 |
  | 设置页 `SettingsDefaultBehaviorPage` | `SettingsPages.swift:146` | **仅改 hint 文案一行**——`settings_behavior_mask_hint` 的 defaultValue 去掉「Takes effect with the mask editor (M2-7)」前瞻括注（M2-7 生效后失实），保留「Applies when a drawn mask is completed.」语义句 |
- **消费时点裁决 = 完成时**（对表 M2-3 页面语义三处文字见证：`AppPreferences.swift:23-24` 头注「the M2-7 mask toolbar consumes it when the user **finishes** a drawn mask」/ Picker 标签「**After drawing** a mask」/ hint「Applies when a drawn mask is **completed**」）：一笔 drawn mask 交互完成（`endInteraction` 提交后）求值三分流——
  - `currentNode` = 原层保留，零动作；
  - `newLayer` = 新建 adjustment layer 并把该 drawn mask 移挂新层（层创建走既有命令面，蒙版移植 = mask 随建随迁，原层无残留——MaskDefaultBehaviorTests 断言钉）；
  - `ask` = 一次性 sheet（「保留当前层 / 移入新层」二选，选择**不持久**——M2-3 语义即每次完成时 ask，不引入「不再询问」）。
  Alcedo 原文「Create a new layer, **then draw**」字面为 arm 时——**以 M2-3 既有面为准**（消费面复用优先于字面复刻），偏差理由入 DECISIONS。
- **求值注入（M2-1 D-EXEC-1 同款）**：resolver 闭包（内读 `AppPreferences.maskDrawBehavior`，注入 suite 可测）经 environment 注入消费点；视图 body 零 `UserDefaults` 直读。测试注入常量枚举直测矩阵（三值完成时臂 + ask sheet 选择不持久 = 4 格）。
- 完成时语义的边界（KD 必答）：完成时必然存在当前层（刚画完），原「无选中回落 ask」防空指条款随 arm 时语义一并作废；ask sheet 的移动动作落一次 history item（移挂 = 层结构变更命令），`currentNode`/「保留当前层」零 item。

### KD-5 Luminance/Color Range = parametric 预设化皮，换算单源

- **数据落点**：全部写既有 `ParametricMask`（domain `luma` / `jzczhz`，
  `ChannelEntry.curve` 4 点梯形 + boost）——**零新 MaskType**（OQ-6 C 已否决）。
  面板持有目标层的 parametric payload 编辑会话，提交 = `commitLayerEdit`
  （`history_mask_range_*` 键族）。
- **Luminance Range**：直方图条 + 亮部/暗部双滑杆（+羽化）→ 写 luma 梯形 4 点
  （shadows: [p0,p1] / highlights: [p2,p3] 区间映射，换算式 = UI 域 [0,1] →
  curve UI 域直通，`packedParameters()` 消费既有）。
- **Color Range**：吸管（显示平面像素采样）→ JzCzhz（JzAzBz 链既有 Core 换算
  单源复用，**禁止第二 Jz 实现**）→ 写 Cz（色度范围 ±羽化）与 hz（色相中心
  ±范围）两通道曲线；boost 档 = Jz/Cz 默认 −6.64385619 既有（`ParametricMask`
  头注既有值，不新造）。
- **吸管换算钉（OQ-6 悬决回填）**：采样源 = 当前显示平面（PREVIEW 输出）中心
  1px；linear Rec2020 → JzAzBz → JzCzhz 换算走 Core 既有色彩链（05 系 Color
  模块同款）；换算函数 Core 单源 + `RangePanelMappingTests` golden（已知
  sRGB 值 → 期望 Cz/hz 采样 ≤1e-4）。UI 默认面 = 单通道快捷（Nitro 语义），
  dt 全量通道面不暴露（OQ-6 边界原文）。
- **Follow Edges 参数面**：工具参数节（宽度/对比阈值/跟随强度/单侧方向 + mode
  指示）绑 `FollowEdgesParams`（P1 落定）；walker 空链降级 = 状态条提示（KD-P1
  KD-6 消费面）。

### KD-6 乐观并发接线 = press 段写毕后快照 + 先校验后 bump（分派表消费，checker E5 同口径）

- overlay 交互开始快照 `expectedRevision`——**时点钉 = press 段写毕之后**
  （P1 KD-5 快照钉消费）：常规笔画 press 段 `appendForm` 走 live 腿零 bump
  （快照 = 现值 N）；press 即「append+commit」型交互（Follow Edges tap-commit、
  path 节点 tap-add 既有先例）其 bump 随 press 段提交先落，快照取 **post-bump**
  值——防自致失配误走重放。
- `endInteraction` 提交前 `MaskSpec.matchesExpected` 校验（P1 原语单源），
  **次序 = 先校验后 bump**：
  - 相等 → bump 恰一次（P1 落的提交腿 bump 在此发生）→ `commitLayerEdit` 照旧
    （恰 1 commit 契约不动）——**正常笔画 = 相等路径恰 +1、不走重放**
    （MaskRevisionTests 断言钉）；
  - 失配 → **追加型 = 重放**（重读 live spec 重装 drawn payload 后 bump 提交）、
    **改写型 = 拒绝**（丢弃本次变更 + toast + live 重读）——P1 KD-5 分派表
    原文执行。
- live 腿（`applyLiveLayer`/`appendForm`/`mutateForm` tick）不校验不 bump
  （单写者同步，视觉预览允许覆盖显示；revision 数值 live 腿恒不变——P1 钉）；
  校验只在**落 history 的提交点**——与「笔画结束恰 1 commit」契约正交（既有
  dirty 门零改动）。
- AI bake 侧 P1 已拒装；本 plan 补 toast 文案键 + 面板行刷新（bake 失败后
  缩略图不换键，自然一致）。

### KD-7 AI Subject 入口 = invert sugar 装配（零生成面改动）

- 入口 = MaskToolbar AI 组新「主体以外」项：复用 `AIMaskSource.subject` 现档
  生成/重烤语义**零改动**；生成落格后装配 invert——raster ref 已有 per-ref
  invert 位（`RasterMaskRef` inverted，06-04 语义）优先，group item `inverted`
  为辅（按目标层形态二选一，DECISIONS 记录选择）；一步成「主体以外」蒙版。
- 生成参数不持久红线：入口不改 AIMaskService/AIMaskEditing 参数面（P1 只在其
  install 腿加了 bump/校验，本 plan 零触碰该文件为红线）。

## read_first

1. `.work/gsd/phases/m2-7-masks/M2-7-CONTEXT.md`——裁决正本（OQ-3/5/6/7/8）+
   Specific Ideas（缩略 renderer 形态/边缘图派生缓存/提示面样式）。
2. `LightamerCore/Sources/Layers/Masks/MaskCombiner.swift`——`assembleUnmasked`
   签名与三腿装配（缩略 pass 复用入口）+ `RasterMaskStore.load` 窗口重采样腿。
3. `App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift`——手柄命中/Grab 枚举/
   endInteraction 契约（`:352-366`）+ P1 改后的 append/mutate 构造。
4. `App/Sources/Lightamer/State/LayerEditingState.swift`——MaskCommand 五命令 +
   deletionProtected 双腿拦截 + 工具 radio 语义（`:196-202`）。
5. `App/Sources/Lightamer/UI/Shell/`节点图面板/栈路由实态——`NodeGraphCommand`
   消费点（拖组复用面）+ 页签路由（Locate 联动面）；`EditorState.apply` 统一入口。
6. `App/Sources/Lightamer/UI/Inspector/LayersPanelView.swift:444-521`——
   MaskChipView（被替代物）+ 层行 chip 消费点。
7. `LightamerCore/Sources/Layers/Masks/ParametricMask.swift`——ChannelEntry/curve/
   packedParameters/boost 默认（Range 面板数据落点）。
8. `App/Sources/Lightamer/State/AIMaskEditing.swift` + `MaskToolbarView.swift`——
   AI 组入口现状（07-3 交付面，sugar 装配点）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符
   祈使句、body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；
   git add 用 `.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；新建 .swift 文件的任务同 commit
   `tuist generate`（T1/T2/T4/T5 建文件批各自 generate；T3/T6/T7 零新文件免）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；Executed +
   failures 双读（L028）。**回归基线 = 2464 + P1 新增（P1 SUMMARY 终数为基线），
   0 fail**；`--all` **报备制**（跑前 SendMessage 报备 orchestrator）；MEMFAIL
   RSS ≥8G 机检；flake ×3 归因。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`PipelineDocument`/`maskGroups` 投影零 diff（面板纯消费）；
   `PipeCacheKey`/`PixelPipe`/`LayerCompositeDriver` 零 diff；`AIMaskEditing.swift`
   本 plan **零 diff**（P1 已封，红线项）；AI 生成参数不持久；视图 body 零
   `UserDefaults`/`ProcessInfo` 直读（M2-1 D-EXEC-1 口径）；Core 不 import App。
6. **测试登记纪律（checker E2）**：四新测试文件同 commit 登记 Project.swift
   对应 bundle + BUNDLE-MAP 行；归属：MaskThumbnailRendererTests/
   RangePanelMappingTests = **Layers**；MaskGroupsPanelTests/
   MaskDefaultBehaviorTests = **App**。
7. **checker 四条（M2-4 教训移植，逐条对表）**：①真链验收禁绕路造假（E1）——
   面板/命令 AC 走真实 EditorState 实例链，禁测试后门直捅存储；②登记闭环（E2）
   ——纪律 6；③语义断言落可观测级（E4）——undo round-trip/锁拦截/缩略失效
   断言到键与字节级；④收口边界核对（M 级）——T9 `git diff --stat` 逐文件对表 +
   grep 口径精确（模式限 `default:`、文件限触点文件——checker E6 触点清单口径）
   + 消费点单源核验。
8. **收口核对**：T9 diff 边界 == front-matter files_modified，越界 = 违约。

## Tasks

### T1 MaskThumbnailRenderer（Core，缩略 GPU pass）

- **read_first**：上列 1/2。
- **action**
  1. 新建 `LightamerCore/Sources/Layers/Masks/MaskThumbnailRenderer.swift`
     （KD-1 全量：ramp 输入复用构建、assembleUnmasked 调用、L014 fence 读回、
     8-bit gray CGImage、进程内 LRU 键 = stableHash ⊕ 尺寸档、nil/空载荷返回
     nil）。
  2. 新建 `Tests/LightamerTests/MaskThumbnailRendererTests.swift`：drawn
     （ellipse 实体）/parametric（luma 梯形在 ramp 上的窗口可视化）/raster
     （fixture PNG ref）三腿 + 混合层 + **键失效**（改 spec 一字段 → 键变 →
     重渲内容差）+ 空载荷 nil + LRU 封顶逐出。
  3. `tuist generate` + 登记两处（纪律 6）。
- **验收标准**
  - [ ] 三腿 + 混合 + 键失效 + 空载荷/LRU 断言全绿。
  - [ ] renderer 无 App 依赖、无 UI 类型（Core 编译证）；读回前 fence 在册
        （代码评审 m7）。
  - [ ] 全套回归 `0 fail`。

### T2 Mask Groups 面板（投影 + 操作面 + 缩略图格）

- **read_first**：上列 1/4/5/6。
- **action**
  1. 新建 `App/Sources/Lightamer/UI/Inspector/MaskGroupsPanelView.swift`
     （KD-3 全量：组投影行/蒙版行/缩略图格/属性编辑/add-remove/锁标记/Locate
     角标；`String(localized:)` 随手键）。
  2. `LayerEditingState.swift`：`MaskCommand` 增 `addMaskItem`/`removeMaskItem`
     （KD-3 分派表 + **checker M5 裁决**：两 case payload-free、删除目标 itemID
     作执行缝参数；remove 连带 form 清扫 + deletionProtected 拦截沿用）。
  3. `EditorState.swift`：面板 item 属性写统一缝（setter → commitLayerEdit，
     `history_mask_item_*` 键族）+ Locate 选中联动。
  4. `LayersPanelView.swift`：层行 chip 切换 renderer 输出（MaskChipView 退役
     删除，视觉语言统一）+ 层菜单 `ForEach` 改 `MaskCommand.panelMenuCases`
     白名单（checker M5：add/remove 不进层菜单）。
  5. 新建 `Tests/LightamerTests/MaskGroupsPanelTests.swift`（**真实
     EditorState 链**，checker ①）：投影行序 = grade 序 + 属性编辑恰 1 item +
     undo/redo round-trip + add/remove 命令 undo 保 UUID + 删锁 item 拦截
     （零 history item + toast）+ Locate 选中联动断言。
  6. `tuist generate` + 登记两处。
- **验收标准**
  - [ ] 面板投影/命令/undo/锁拦截/Locate 断言全绿（真链口径）。
  - [ ] `PipelineDocument.swift` 零 diff（`git diff --stat` 核）；面板无第二
        状态存储（代码评审 m7：行状态仅 (layerID, maskHash, image) 缓存）。
  - [ ] 全套回归 `0 fail`。

### T3 手柄 overlay 扩展 + 乐观并发接线（expectedRevision）

- **read_first**：上列 3 + `M2-7-1-PLAN.md` KD-5（分派表）。
- **action**
  1. `MaskOverlayHost.swift`：radial 双羽化手柄——rim 内带/外带双 grips
     （命中半径沿用 screen-space 16px 既有常量）+ 拖写
     `innerFeather/outerFeather`（P1 字段）+ 导引线 token 化（Alcedo overlay
     导引线视觉语言：中心十字/radius 主轴/羽化带边界三 token 类）。
  2. 同文件：grab 快照 `expectedRevision`（**时点 = press 段写毕后**，KD-6/
     checker E5）+ `endInteraction` 提交校验（**先校验后 bump**：append 重放/
     mutate 拒绝 + toast）。
  3. `MaskRevisionTests` 扩展：快照→中途改 spec（模拟 AI install）→提交 →
     append 重放成功断言 / mutate 拒绝 + toast 断言；**正常笔画 = 相等路径恰
     +1、不走重放**（checker E5 断言钉）+ 恰 1 commit 契约回归不破。
- **验收标准**
  - [ ] 双 grips 命中/拖动/写值断言绿；并发分派（重放/拒绝）绿；恰 1 commit
        契约回归绿。
  - [ ] `AIMaskEditing.swift` 零 diff（红线核）。
  - [ ] 全套回归 `0 fail`。

### T4 Default Behavior 消费接线（复用 M2-3 既有面 + 完成时分流，checker E1）

- **read_first**：上列 4/8 + `App/Sources/Lightamer/Settings/AppPreferences.swift`
  （`MaskDrawBehavior`/`maskBehaviorKey` 实态，:23-38）+
  `App/Sources/Lightamer/Settings/SettingsPages.swift:142-188`
  （`SettingsDefaultBehaviorPage` 既有节 + hint 文案行）。
- **action**
  1. `SettingsPages.swift`：**仅 hint 文案一行**——`settings_behavior_mask_hint`
     defaultValue 去「Takes effect with the mask editor (M2-7)」前瞻括注（KD-4；
     零新节零新键——`git diff` 评审核：该文件仅此一行）。
  2. `LayerEditingState.swift`：完成时消费分流面——`endInteraction` 提交回调
     后按 `MaskDrawBehavior` 分流（KD-4：`newLayer` = 建新层 + mask 移挂（一
     history item）/ `currentNode` = 零动作 / `ask` = 一次性 sheet「保留当前层/
     移入新层」不持久）；resolver 闭包注入式（读 `AppPreferences.maskDrawBehavior`，
     environment 承载，body 零 UserDefaults 直读）。
  3. `MaskToolbarView.swift`：消费接线挂点（完成时回调链——**非** arm 分流，
     checker E1 时点勘误）。
  4. 新建 `Tests/LightamerTests/MaskDefaultBehaviorTests.swift`：完成时三分流
     矩阵（`newLayer` = 蒙版移挂新层且原层无残留且恰 1 history item /
     `currentNode` = 原位零 item / `ask` = sheet 出现且选择不持久）+ 注入常量
     直测 + **body 零直读机检**（`git grep -n "UserDefaults" App/Sources/
     Lightamer/UI/Overlay/MaskToolbarView.swift` 零命中——文件限 grep 口径）+
     既有 `SettingsPagesTests` 零改动全绿复核。
  5. `tuist generate` + 登记两处。
- **验收标准**
  - [ ] 完成时三分流矩阵全绿；注入式机检绿（grep 零命中）；unset/不可解析 =
        `ask` 既有缺省断言绿（AppPreferences 既有语义）。
  - [ ] `SettingsPages.swift` diff 仅 hint 一行（`git diff` 评审核）；既有设置
        页键在册复核（M2-3 SUMMARY 键清单——本 plan 零新设置键）。
  - [ ] 全套回归 `0 fail`。

### T5 Luminance/Color Range 快捷面板 + Follow Edges 参数节

- **read_first**：上列 7 + `M2-7-1-PLAN.md` KD-6（walker 产出/降级面）。
- **action**
  1. 新建 `App/Sources/Lightamer/UI/Inspector/LuminanceColorRangePanelView.swift`
     （KD-5：Luminance 直方图 + 双滑杆 → luma 梯形；Color Range 吸管 + 范围/
     羽化 → Cz/hz 曲线；提交 = commitLayerEdit `history_mask_range_*`）。
  2. 吸管换算 Core 单源函数（linear Rec2020 → JzCzhz，复用既有色彩链）落
     `LightamerCore`（文件 = Range 换算就近 `ParametricMask.swift` extension，
     禁新 Jz 实现）。
  3. `MaskToolbarView.swift`：Follow Edges 参数节（KD-5 末段：四参数 + mode
     指示 + 空链状态条提示）。
  4. 新建 `Tests/LightamerTests/RangePanelMappingTests.swift`：吸管 golden
     （已知输入 → Cz/hz ≤1e-4）+ 梯形写穿 round-trip（UI 值 → ParametricMask →
     packedParameters 读回一致）+ boost 默认档断言。
  5. `tuist generate` + 登记两处。
- **验收标准**
  - [ ] 换算 golden + 写穿 round-trip + boost 档断言全绿。
  - [ ] 数据落点 = 既有 `ParametricMask`（零新 MaskType——`git diff` 证
        MaskSpec.swift 零 diff）。
  - [ ] 全套回归 `0 fail`。

### T6 Follow Edges 工具接线（MaskTool case + coordinator 取面 seam + 交互腿，checker E6）

- **read_first**：上列 3 + `App/Sources/Lightamer/State/PipeCoordinator.swift`
  （取面落点——cache/MetalContext/decoded 实态）+
  `M2-7-1-PLAN.md` KD-6（walker/edge map/缓存键语义）+
  `App/Sources/Lightamer/State/LayerEditingState.swift:31`（MaskTool）。
- **seam 裁决（checker E6 二选一，申报文件 = `PipeCoordinator.swift`）**：
  **选 App 经 coordinator 取面**——`PipeCoordinator` 增只读取面一条：给定目标层
  位置返回（below 复合平面 texture handle + 前缀身份哈希）；edge map 生产 =
  P1 键函数缓存命中或 `mask_edge_map` 经 MetalContext 唯一路由（L031 纪律）。
  **否决 acesccEnvelope 式 driver seam**：该先例需 driver diff（M2-5-1 实录
  「driver diff = 腿部 2 行 + 缝持有器」），违 P1/P2 `LayerCompositeDriver`
  零 diff 红线；coordinator 取面是纯 App 只读消费，渲染 walk 零触碰。形态差异
  （何时该用哪种 seam）入 DECISIONS。
- **action**
  1. `LayerEditingState.swift`：`MaskTool` 增 `.followEdges` case（CaseIterable
     合成自动纳入 radio/`MaskToolbarView` ForEach）。
  2. `PipeCoordinator.swift`：只读取面（上表 seam 裁决；零 walk 逻辑触碰）。
  3. `MaskOverlayHost.swift`：**交互腿**——dragGesture `.followEdges` 臂：press
     = seed 采集 → coordinator 取面 → edge map（缓存或算）→ walker →
     `BrushStroke` → `appendForm`（live 腿）→ 拖动微调走 mutate 臂 →
     `endInteraction` 提交（E5 语义：提交腿恰一次 bump）；空链降级 = 不
     appendForm + 状态条提示（P1 KD-6 降级语义消费）。
  4. `MaskOverlayHost.swift`：`commitLabelKey` 加 `.followEdges` 臂
     （`history_mask_follow_edges`）。
  5. `MaskToolbarView.swift`：工具位（ForEach 自动纳入）+ 新 labelKey
     `mask_tool_follow_edges`（工具提示/AX——OQ-12 键族）。
  6. **穷举触点清单（switch 穷举纪律，checker E6）**：新 case 落地时逐点核——
     ① `MaskOverlayHost` dragGesture tool switch（:188-201 邻域）②
     `commitLabelKey` switch（:362-373 邻域）③ overlay display/命中腿的 tool
     分派（`git grep -n "case .path\b" App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift`
     口径列全）④ `MaskToolbarView` ForEach（allCases 自动，核无手写白名单遗漏）；
     全部 switch 穷举**零 default**（纪律 7 口径：模式限 `default:`、文件限触点
     文件）。已知不受影响触点：`AIMaskEditing.swift:127` `activateTool` 缺省
     `.brush`（零改动）。
  7. `MaskRevisionTests` 扩展：**合成边缘场一笔出贴边 stroke**——stub coordinator
     取面返回合成边缘场平面 → 模拟 press seed → 断言 spec.drawn 增一笔且点链
     贴边（距边缘 ≤ 容差带）+ 提交恰 1 revision bump（E5 语义）+ 空链降级
     （零 appendForm + 状态条）。
- **验收标准**
  - [ ] 合成边缘场贴边 stroke 断言绿；空链降级断言绿。
  - [ ] 触点 switch 穷举零 default（grep 机检）；`LayerCompositeDriver`/
        `PixelPipe` 零 diff（`git diff --name-only` 核）。
  - [ ] 全套回归 `0 fail`。

### T7 AI Subject 入口（sugar）

- **read_first**：上列 8。
- **action**
  1. `MaskToolbarView.swift`：AI 组「主体以外」项（KD-7：subject 生成复用 +
     invert 装配；raster ref inverted 位优先）。
  2. `MaskGroupsPanelTests` 扩展：sugar 装配 round-trip（生成 stub → 装配 →
     invert 位 + spec 内容断言）+ 重烤语义不变断言（同 maskID 覆盖 D-07-CONTEXT-5
     既有测试族零改动全绿复核）。
- **验收标准**
  - [ ] sugar 装配断言绿；`AIMaskEditing.swift`/`AIMaskService` 零 diff（红线核）。
  - [ ] 全套回归 `0 fail`。

### T8 面板键入账 + 面板走查冒烟

- **action**
  1. 本 plan 全部新 UI 键清单落 `M2-7-2-SUMMARY.md` 键清单节（**Default
     Behavior 设置节零新键**——checker E1 复用 M2-3 在册键，清单只含消费接线/
     sheet/Follow Edges 工具/toast 族新键），zh 翻译滞后允许（P3 对账）。
  2. GUI 冒烟走查（Debug 构建 + 真样张）：面板展开/缩略显示/属性编辑/锁删/
     Locate/双羽化手柄/ask sheet——证据截图落
     `.work/gsd/phases/m2-7-masks/evidence/m2-7-2/`（§3.2 视口截图纪律：关键区
     裁剪，不全页长图）。
- **验收标准**
  - [ ] 键清单在册；走查六点全过 + 截图在册；发现缺陷当场修或记 E3。

### T9 收口——SUMMARY/DECISIONS + 续接点

- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 报备制；计数/秒数/峰值入 SUMMARY）。
  2. 落盘 `M2-7-2-SUMMARY.md` + `M2-7-2-DECISIONS.md`（KD-1..7 执行确认 +
     invert 装配位选择 + **Default Behavior 完成时点对表偏差理由（checker E1）**
     + **add/remove 裁决选 A 落地确认（checker M5）** + **Follow Edges seam
     选 coordinator 确认（checker E6）** + 偏差归因）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-7-2 完成 + 下一步 = M2-7-3）。
  4. `git diff --stat` 核对边界（纪律 8）。
- **验收标准**
  - [ ] AC 表全绿；三件 md 同批落盘；diff 边界无越界。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 缩略三腿 + 混合 + 键失效（stableHash ⊕ 尺寸档）+ 空载荷 nil + LRU 封顶 + 缩略窗纵横比保形（mapper 传入，checker M4） | MaskThumbnailRendererTests |
| 2 | 面板投影序 = grade 序；属性编辑恰 1 item + undo round-trip；add/remove undo 保 UUID；层菜单 = panelMenuCases 白名单五项（checker M5） | MaskGroupsPanelTests（真 EditorState 链） |
| 3 | 删锁 item 拦截（零 history item + toast）；锁形标记在册 | MaskGroupsPanelTests + 既有拦截测试族全绿 |
| 4 | 双羽化双 grips + 导引线 token + expectedRevision 分派（append 重放/mutate 拒绝）+ **正常笔画 = 相等路径恰 +1 不走重放**（checker E5）+ 恰 1 commit 契约不破 | MaskRevisionTests 扩展 |
| 5 | Default Behavior 完成时三分流矩阵（newLayer 移挂/currentNode 零动作/ask 不持久，checker E1）+ 注入式（工具文件 grep UserDefaults 零命中）+ `SettingsPages.swift` diff 仅 hint 一行 | MaskDefaultBehaviorTests + `git grep` + `git diff` |
| 6 | Range 吸管换算 golden ≤1e-4 + 梯形写穿 round-trip + boost 默认档；零新 MaskType | RangePanelMappingTests + `git diff` |
| 7 | **Follow Edges 接线**（checker E6）：合成边缘场一笔出贴边 stroke + 空链降级 + 触点 switch 穷举零 default + driver 零 diff | MaskRevisionTests 扩展 + `git grep`/`git diff --name-only` |
| 8 | AI Subject sugar 装配 + 重烤语义零改动（`AIMaskEditing.swift`/`AIMaskService` 零 diff） | MaskGroupsPanelTests 扩展 + `git diff --name-only` |
| 9 | GPU 提交唯一路由（renderer 无新 queue 创建——`git grep -n "MTLCreateSystemDefaultDevice\|makeCommandQueue" MaskThumbnailRenderer.swift` 零命中） | `git grep` |
| 10 | 全套回归 0 fail（基线 = P1 终数 + 本 plan 新增 30..38） | test-direct.sh --all BUNDLE 行双读 |
| 11 | diff 边界 == 申报文件集；四新测试登记闭环（Project.swift + BUNDLE-MAP） | `git diff --stat` + `git grep` 双命中 |

## 风险与边界

- **缩略 pass 与 PREVIEW 并发**（任务书风险条目②，L031）：正面回答 = KD-2——
  全部提交走既有唯一路由获取点（grep 机检 AC8），无新 queue；按需 `.task` 小
  平面不与 pipe 抢 command buffer 预算。残余风险 = 大量行同时入屏的请求风暴
  ——LRU + 面板只对可见行请求（`LazyVStack` 可见面）自然限流；若走查实测
  仍抖，fallback = 面板级串行队列消费（单 Task actor），挂 P3 裁决不预做。
- **parametric 缩略的 ramp 语义**：ramp 输入是「窗口可视化」非内容真值——缩略
  语义 = 显示选择域形状（与 Alcedo 缩略图目的一致），DECISIONS 明示该解释；
  若走查裁决要内容真值（真实复合采样），属增强挂账（需 below 平面入参，成本
  数量级上升），本 plan 不预做。
- **拖组排序与蒙版行拖动误触**：面板两组拖动手势域（组重排 = Reconnect；蒙版
  行不拖排序——item 序即 forms 序，Alcedo 无蒙版行重排面）——手势域隔离在
  面板内静态分离，不引入新手势仲裁。
- **expectedRevision 快照时点（checker E5 钉后残余）**：快照在 press 段写毕后
  取值（KD-6）——若 press 与 commit 间用户经面板改了属性（同一 MainActor
  线程物理上不同帧），失配走分派表而非崩溃/静默覆盖；面板写在笔画中途不可达
  （模态互斥既有），真实窗口仅 AI bake（KD-6 注记）。
- **MaskChipView 退役回退**：renderer 在无 GPU 上下文（测试宿主外）失败 →
  层行 chip 回退占位框（nil 分支既有），不崩；`MaskChipView` 删除后如走查
  需回退，git revert 单文件可逆。
- **Default Behavior 消费时点与 M2-3 的关系（checker E1 残余）**：完成时消费
  复用 M2-3 既有枚举/键/设置页——语义分歧（Alcedo 字面 arm 时 vs M2-3 面语义
  完成时）已裁决以 M2-3 为准并记 DECISIONS；若走查裁决要 arm 时（先建层再画
  的 Alcedo 字面），属交互增强挂账非本 plan 重开（完成时 = M2-3 页面文案对
  用户的既成承诺）。
- **设置键族命名**：键 `mask.behavior.default` 为 M2-3 既有在册键（checker E1
  消费），与既有 `library.import.*` 族同层（UserDefaults 直键），无冲突域；
  本 plan 新键清单 SUMMARY 申报防漂移。

## 提交约定

- T1 `feat(core): mask thumbnail renderer with stable hash cache key`
- T2 `feat(app): mask groups panel over document projection`
- T3 `feat(app): dual feather handles with optimistic revision gate`
- T4 `feat(app): consume stored mask draw behavior on stroke completion`
- T5 `feat(app): luminance and color range quick panels`
- T6 `feat(app): follow edges tool wiring over coordinator seam`
- T7 `feat(app): ai subject inverted sugar entry`
- T8 `chore(m2-7): panel key ledger and smoke walkthrough evidence`
- T9 `docs(m2-7): close out plan 2 mask panels and interaction`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-10-01）

checker 判 FAIL（7E+9M）后本 plan 修订项（hint 逐条落实；勘误正本 = CONTEXT
勘误注记节）：

- **E1**：Default Behavior 改**消费 M2-3 既有面**——KD-4 全节重写（复用
  `MaskDrawBehavior` AppPreferences.swift:25 + 键 `mask.behavior.default` :38 +
  既有 `SettingsDefaultBehaviorPage`，设置侧仅 hint 文案一行）；删自起枚举
  `MaskDefaultBehavior`/自起键 `mask.defaultBehavior`/新 Settings 节；消费时点
  裁决 = **完成时**（M2-3 页面语义三处文字见证对表；arm 时条款作废）——T4 重写
  + D-8/D-12 裁决引用勘误 + AC5/风险节同步；CONTEXT 勘误-1 同步。
- **E4**：front-matter 补申报 `LayersPanelView.swift`、`ParametricMask.swift`、
  `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（实路径）、
  `PipeCoordinator.swift`（E6 seam 申报）。
- **E5**：KD-6 重写与 P1 KD-5 同口径——快照时点 = press 段写毕后（press 即
  append+commit 型交互取 post-bump 值）+ 校验次序 = 先校验后 bump + 「正常
  笔画 = 相等路径恰 +1、不走重放」断言（T3 action/AC4/风险节同步）。
- **E6**：**新增 T6 Follow Edges 工具接线**（原 T6/T7/T8 重编号 T7/T8/T9）——
  `MaskTool` 增 `.followEdges` case + 穷举触点清单（dragGesture/commitLabelKey/
  display 腿 grep 口径；`AIMaskEditing:127` 不受影响实证）+ **seam 裁决 = App 经
  coordinator 取面**（申报 `PipeCoordinator.swift`；否决 acesccEnvelope 式
  driver seam——需 driver diff 违零 diff 红线）+ press→seed→walker→BrushStroke→
  appendForm 交互腿 + commitLabelKey/工具 labelKey 臂 + AC7（合成边缘场贴边
  stroke + 空链降级 + 穷举零 default + driver 零 diff）。
- **M4**：缩略 renderer 签名补 `GeometryPointMapper` 入参 + 缩略窗纵横比语义
  KD 补钉（层窗等比缩放非方形；mapper caller 构建；AC1 同步）。
- **M5**：add/remove 与 `MaskCommand: CaseIterable` 冲突裁决 = **选 A：两 case
  payload-free + 删除目标 itemID 作执行缝参数 + 层菜单 `panelMenuCases` 白名单
  过滤**（KD-3 + T2 + AC2 同步；选 B 独立命令面否决理由在案）。
- **M2/M3/M6-M9**：留执行期 DECISIONS（checker 口径）。
