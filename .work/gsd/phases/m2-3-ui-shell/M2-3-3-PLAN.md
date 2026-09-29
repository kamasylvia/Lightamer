---
phase: m2-3
plan: "M2-3-3"
title: "编辑器面——三段布局（左工具轨 History/Versions/Nodes + 中视口包装 + 右示波器/调整栈 + 左竖胶片条挂载，D2/D3 活体壳）；七页签调整栈路由表 33 面板归页（D4 映射表代码化 + TAB-MATRIX 落盘）；示波器 GPU kernel（直方图 256-bin×RGB+luma + 波形，D6）；RAW Decode 新面板（CIRAW NR 参数族 + decoder version + boost，D2 解码层承担）；Settings 七页（D7 + Import Defaults/Displays/MCP 迁移）。唯一 Core 例外 = RAWDecoder.swift 增量参数缝"
wave: 3
depends_on: ["M2-3-1", "M2-3-2"]
autonomous: true
requirements: [M2UIW-02, M2UIW-03, M2UIW-04, M2UIW-05, M2DIS-03, M2DIS-04, M2LIB-07]
files_modified:
  - App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift        # 新建（→ tuist generate）：左工具轨图标列（History 真挂现行 history stack / Versions 空态 M2-8 / Nodes 空态 M2-4）+ 展开推挤动画（共享折叠语义）
  - App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift            # 新建：七页签枚举（Alcedo 页序）+ EditorTabRoutingTable 静态映射表 = D4 OQ-4 表代码化单一正本
  - App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift # 新建：页签切换 + 面板宿主（复用 IOPPanelProvider 注册面 + InspectorRowView 宿主形态；面板本体零改动）
  - App/Sources/Lightamer/UI/Shell/EditorNodeHeaderView.swift      # 新建：节点头（节点名 + 焦距/光圈/快门/ISO——LibraryImageRow EXIF 列读出）
  - App/Sources/Lightamer/UI/Shell/ScopePanelView.swift            # 新建：右栏示波器面板（直方图/波形二选一 + 节流宿主 + 小纹理/小 buffer 直显）
  - App/Sources/Lightamer/UI/Shell/RawDecodePanelView.swift        # 新建：RAW Decode 页签面板（NR amount/luminance/chroma/sharpness + decoder version + boost）
  - App/Sources/Lightamer/UI/Settings/SettingsPages.swift          # 新建：设置页内容件（Language/Theme、Default Behavior、Cache、LCR/ACA 诚实空态、Keyboard、About、Import Defaults、Displays/MCP 迁移宿主）
  - App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift  # 修改：P1 骨架 slot 填充三段布局（工具轨/视口/左胶片条/右栏）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift         # 修改：TopBar yiyin 独立入口按钮（YiyinPanelView + TextOverlayPanelView sheet，D4 独有面板入口）
  - App/Sources/Lightamer/UI/EditorAreaView.swift                  # 修改（仅增量缝）：外壳适配——视口/手势/overlay 底座零行为改动；legacy gate 快照核对前置
  - App/Sources/Lightamer/State/PipeCoordinator.swift              # 修改（仅增量缝）：PREVIEW 输出纹理示波器采样 tap（节流 + L031 唯一队列路由点）
  - App/Sources/Lightamer/UI/SettingsView.swift                    # 修改：Settings scene 重组为 Alcedo 式左列表右内容导航（visibleCatalogSectionMarkers 门控逻辑零改动）
  - App/Sources/Lightamer/Settings/AppPreferences.swift            # 新建：Default Behavior（蒙版三选）/Cache/Keyboard 偏好键宿主（UserDefaults 惯例，ImportDefaults 先例同型）
  - LightamerCore/Sources/Decode/RAWDecoder.swift                  # 修改（**显式红线例外，唯一 Core 文件，仅增量**）：decode 增量 technicalOverrides 参数（默认值 = 零行为变化）——overrides 先于 rawTech readback 写入 filter
  - LightamerIOP/Sources/Common/ScopeReduce.swift                  # 新建：示波器归约宿主（HistogramReduce 同族扩展——bin/波形两 pass + 节流策略）
  - LightamerIOP/Sources/Common/ScopeReduceKernels.metal           # 新建：直方图 bin kernel（256-bin × RGB + luma）+ 波形 kernel（逐列下采样散点写小纹理）
  - .work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md              # 新建：OQ-4 七页签归页映射表落盘（与 EditorTabRoutingTable 同批互校，M2-1 MATRIX 同格式）
  - Tests/LightamerTests/ScopeReduceTests.swift                    # 新建（→ tuist generate）：合成纹理 bin 计数 vs CPU 参考逐 bin parity + 波形列统计 parity + 确定性
  - Tests/LightamerTests/EditorStackRoutingTests.swift             # 新建：路由表完备性（启用面板恰一次归页/页序 == Alcedo/禁用 6 名零命中）+ 空态页 + 工具轨三态
  - Tests/LightamerTests/RawDecodeOverridesTests.swift             # 新建：overrides 应用断言（filter 键位读回）+ 默认参数逐字节不变 + cache key 漂移断言 + 越界钳制
  - Tests/LightamerTests/SettingsPagesTests.swift                  # 新建：页 id 集精确断言 + Default Behavior 三选 round-trip + Keyboard 冲突检测 + Catalogs 门控页 gate 两态
  - .work/gsd/phases/m2-3-ui-shell/M2-3-3-SUMMARY.md               # 新建（收口任务）
  - .work/gsd/phases/m2-3-ui-shell/M2-3-3-DECISIONS.md             # 新建（收口任务）
  - .work/GOAL-STATE.md                                            # 续接点追加（收口任务）
  - .work/LESSONS.md                                               # 如踩坑
---

# Plan M2-3-3 — 编辑器面（三段布局 + 七页签归页 + 示波器 GPU + RAW Decode 面板 + Settings 七页）

> **性质**：App 层为主 + **两处申报例外**（`RAWDecoder.swift` 增量参数缝——唯一 Core
> 生产文件触点；`LightamerIOP/Sources/Common/` 示波器 kernel 新文件——D6 推荐归属）。
> 活体壳策略（D3 A）：既有功能真接、缺失功能诚实空态。规格锚点 =
> `research/ALCEDO-FEATURE-MAP.md` §1.3（EditorWorkspace 布局注释正本：tool rail left /
> viewport center / scopes + adjustment stack right——**胶片条按用户修订移左轨竖向**）+
> §1.4（设置九页）+ `M2-3-CONTEXT.md` OQ-4 映射表（本 plan T2 落盘正本）。
>
> P1/P2 缝消费：`EditorWorkspaceShellView`（P1 骨架）、`FilmstripView` +
> `LibraryGridModel`（左轨数据源）、`WorkspaceModel`（EditorPhaseState）。

## 已定裁决（不得重开）

- **D2（OQ-2 A）**：编辑器顶栏回退按钮/⌘W 关图回图库（⌘W 命令 P1 已挂，本 plan 接线
  确认）。
- **D3（OQ-3 A）活体壳**：Tone/Look/LUT/Geometry/Mask 五页签挂现行平铺管线既有面板
  （参数直调现行 history stack，行为与 M1 一致）；Display Transform 页签 = 暂驻 AgX 现
  面板 + 「DRT arrives with M2-6」占位节；RAW Decode 页签 = 新建 CIRAW 参数面板
  （NR amount/luminance/chroma/sharpness + decoder version + boost；Neural Engine 细节
  M2-5+ 校准）；左工具轨 History = 挂现行 history stack，Versions = 占位空态（M2-8），
  Nodes = 占位空态（M2-4）；示波器/胶片条/FIT 读出/双级 busy = 真数据真交互；空态文案
  统一「<Feature> arrives in M2-x」家族。
- **D4（OQ-4 A）**：七页签归页映射表照 CONTEXT OQ-4 表生效（details = 表 verbatim；plan
  期微调仅限「明确偏差 + DECISIONS 归因」）；独有面板入口：YiyinPanelView + TextOverlay
  = 顶栏独立按钮（sheet）；McpLauncherPanelView = 现状保持（菜单/窗口入口）；PresetPanelView
  = 七页签头部全局入口（沿 M1 Inspector 底部 + 管理器窗口现状）。
- **D5（OQ-5 A）**：禁用 6 面板（FilmicRGB/Sigmoid/AgX/DenoiseProfile/NLMeans/Bilateral）
  零额外删除——路由表不含 → 文件自然失挂；收尾审计（P4）加「禁用 op 名路由表 grep 零
  命中」；`LIGHTAMER_FULL_IOP_FACE=1` 全量回切不受影响（七页签外 legacy 平铺挂接路径
  不动，PanelWiringTests 依赖面零改动）。
- **D6（OQ-6 A）**：示波器 = GPU compute（LightamerIOP Common 扩 HistogramReduce 先例，
  可单测）；直方图 256-bin × RGB + luma 对 PREVIEW 输出纹理直采；波形逐列下采样散点写
  小纹理（≤1080 宽预览上限）；节流 = 拖动中 ≤15Hz + 帧稳定后单次计算。
- **D7（OQ-7 A）**：设置 = M2UIW-05 明文七页 + Import Defaults 节（M2LIB-07④）+ 既有
  Displays/MCP 节保留迁移；**砍** Acceleration 与 Updates；LCR/ACA = 结构 + 「arrives
  with M2-10」空态；LUT 根目录选择器留 M2-5 不预埋。
- **D12（OQ-12 A）**：legacyBody 树资产零 diff；`EditorAreaView.swift` 改动仅限增量缝
  （见 KD-1 前置核对步）；`InspectorView.swift`/`InspectorRowView` 之外不新增对 legacy
  面板文件的修改——33 面板本体文件**全部零 diff**（挂接 = 新栈实例化既有 PanelView，
  面板文件不动）。
- **用户修订**：胶片条 = 编辑器**左侧竖向**（P1 组件直挂左轨，非 Alcedo 底部）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 三段布局 = EditorAreaView 包装不重写，legacy gate 快照核对前置

`EditorWorkspaceShellView` 三段填充：左 = `EditorToolRailView`（图标列 + 文字标签，展开
推挤中央视口——共享折叠动画常量）；中 = **既有 `EditorAreaView` 原样作为 child 挂入**
（视口/手势/overlay/双级 busy/FIT 读出/ZoomHUD 全保留，零行为迁移）；左轨与胶片条并列
（工具轨窄列 + 胶片条竖列，互不重叠——Alcedo 左轨推挤语义映射为「推挤视口，不推挤
胶片条」，与用户修订布局自洽）；右 = `EditorRightPane`（ScopePanelView + 七页签栈纵向
排列，Alcedo 同方位）。
**前置核对步（T1 第一步，禁跳）**：`Tests/LightamerTests` 内 legacy gate 冻结快照
（M2-2-4 建立的 identifier `Set<String>` 快照断言）的覆盖面逐一核对——若快照含编辑器域
identifier，则 `EditorAreaView.swift` **零 diff**、全部挂接走外层包装文件；仅当快照
不含编辑器域才允许 EditorAreaView 增量缝。核对结论入 DECISIONS。
`EditorAreaView.swift` 允许的改动上限 = 增量 init 注入/可选修饰（不改任何既有语句；
`git diff` 逐 hunk 评审项核对）。

### KD-2 EditorTabRoute = D4 映射表代码化单一正本

```swift
enum EditorTabRoute: CaseIterable { case tone, look, lut, displayTransform,
                                    geometry, rawDecode, mask }   // Alcedo 页序（§1.3）
enum EditorTabRoutingTable {
  static func panels(for tab: EditorTabRoute) -> [PanelDescriptor]
}
```

- 路由表 = CONTEXT OQ-4 表逐行代码化（页签 → 挂接面板清单 + 组语义）；`PanelDescriptor`
  承载面板构造闭包引用（复用 `IOPPanelProvider` 注册面实例化既有 PanelView，**面板文件
  零改动**）+ Advanced 折叠组标记（Geometry 页 D6 独有项组）。
- 归页总数断言：启用面板全集（`ModuleRegistry` 默认面 33 − Lut/Yiyin/TextOverlay/Preset
  四个特例入口）**恰一次**出现在路由表；禁用 6 名（filmicrgb/sigmoid/agx/
  denoiseprofile/nlmeans/bilateral op 名小写比对）**零命中**；页序 == `allCases` 序。
- 同批落盘 `.work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md`（M2-1 MATRIX 同格式：
  页签 × 面板 × 组语义 × Alcedo 对应物列）；**表与 md 同批互校**（md 由表人工誊写，
  T2 验收含逐行对账步）。
- Display Transform 页签 = AgX 面板 + 占位节（「OpenDRT / ACES 2.0 arrive with M2-6」）；
  RAW Decode 页签 = RawDecodePanelView（T4）；Mask 页签 = LayersPanelView + MaskToolbar
  联动入口（M2-7 替换前的归位）。

### KD-3 ScopeReduce = HistogramReduce 同族 GPU 归约，L031 队列纪律直承

- `LightamerIOP/Sources/Common/ScopeReduce.swift` + `ScopeReduceKernels.metal`：
  - 直方图 pass：threadgroup 归约写 `atomic_uint` bin（256 × RGBA 四通道 = R/G/B/luma），
    输出 ≤4KB buffer；
  - 波形 pass：每列下采样散点加亮写小纹理（`r16Uint`，宽 = 预览宽 ≤1080、高 = 256 亮度
    级），零 CPU 读回（MTKView/layer 直显小纹理）；
  - 直方图小 buffer 读回 = fence 后单次（L014 纪律；复用 `HistogramReduce.rgbMinMax`
    的 fence 先例，`PipeCoordinator.swift:1369-1373` 同型）。
- 队列路由：**一切 GPU 提交走 PipeCoordinator 既有唯一队列获取点**（L031 正本：
  `LESSONS.md:261`——identity blit 硬编 editor queue 曾致跨队列竞速假非确定）；示波器
  tap 挂 PREVIEW 渲染完成回调之后（渲染同一 command buffer 串行语义内 enqueue compute
  ——不另起并行 render pass 抢占 PREVIEW）；**禁新建第二 MTLCommandQueue**。
- 节流宿主（`ScopePanelView`）：参数变化/拖动中 ≤15Hz 合并请求；帧稳定（渲染 idle
  ≥250ms）后单次补算；scopes 不可见 = 零 tap（P1 View 可见性 toggle 命令点亮）。
- **AC 机检**：合成纹理（CPU 构造已知分布 MTLTexture）→ bin 计数 vs CPU 参考逐 bin
  精确 parity + 波形列最大值/计数 parity + 同输入两次调用结果逐字节一致（确定性）。

### KD-4 RAW Decode overrides = filter 先写后读，cache key 自然漂移（Core 唯一例外）

- `RAWDecoder.decode(_ url:)` 增量第二参数
  `technicalOverrides: RAWTechnicalParams = .init()`（默认值 = 零行为变化——既有调用
  点零改动，编译级保证）；override 值**先写入 CIRAWFilter 对应键
  （`noiseReductionAmount`/`luminanceNoiseReductionAmount`/`colorNoiseReductionAmount`/
  sharpness 族/`boost`），后走既有 `rawTechnicalParams(from:)` readback
  （`RAWDecoder.swift:284`）**——readback JSON 已含 NR 三字段（`RAWTechnicalParams:30-37`
  实态），`PixelPipe` cache key = `(decoderVersionUsed, RAWTechnicalParams JSON)`
  （`PixelPipe.swift:67` 实态）因此**自动漂移**：参数变 → key 变 → 解码缓存正确失效；
  默认 overrides = identity → JSON 逐字节不变 → key 逐字节不变（单测断言）。
- decoder version override：既有 `supportedDecoderVersions` 探针面收窄为「用户指定 v8/v9
  与探针结果交集」（用户强选 v9 但相机不支持 → typed 降级 v8 + 面板行内提示）。
- **膨胀字段规则**：boost/sharpness 若 `rawTechnicalParams(from:)` readback 无承载字段
  （cache key 漏漂移），按 `HistoryHash.swift:145-146` 契约**扩 `RAWTechnicalParams`
  字段 + HistoryHash 侧同批**——此时 files_modified 追加 `RAWTechnicalParams.swift` 与
  HistoryHash 相关文件（执行期实测后定，DECISIONS 记录；预估不需扩——readback 已含
  boost 腿待核）。
- 持久化边界（明确非目标）：v1 overrides = **会话级**（切图保持该图会话值；关图丢弃）；
  入 sidecar/项目包的 decode 参数持久化 = M2-4 节点模型 schema 扩展承载（D3 活体壳
  边界内，DECISIONS 挂账 M2-4）。

### KD-5 Settings 七页 = Settings scene 内左列表右内容导航，门控逻辑零改动

- `SettingsView.swift` 重组：`NavigationSplitView`（List selection = 页 id）+ 右内容
  区按页切换（Alcedo `SettingDialog` 形态）；**`visibleCatalogSectionMarkers` 及
  Catalogs 双节门控逻辑零改动**（Catalogs 页仅 gate=true 可见，消费既有静态函数）。
- 页集（D7 全量，id 精确断言 10 项）：
  `languageTheme` / `defaultBehavior` / `cache` / `localContentRecognition`（空态）/
  `advancedContentAnalysis`（空态） / `keyboard` / `about` / `importDefaults`
  （M2LIB-07④：三选 + remember，消费 `ImportDefaults` 三键） / `displays`（既有节迁移）/
  `mcp`（既有节迁移）。Acceleration/Updates 不在册（D7 砍）。
- Default Behavior = 蒙版绘制三选（`ask`/`newLayer`/`currentNode`）→ `AppPreferences`
  UserDefaults 键（`mask.behavior.default`，M2-7 消费；本 plan 只存不接线——D3 边界）；
  Cache 页 = 缩略图缓存目录展示 + 清空按钮（桥缓存清空缝）；Keyboard 页 = 命令 × 当前
  键位表（MenuCommandSet id 全集）+ 冲突检测高亮 + 恢复默认（v1 展示/检测/恢复三面，
  **不活绑重映射**——CONTEXT Deferred Ideas 口径）；About = 版本/MIT 许可/致谢。
- LCR/ACA 空态文案 = 「arrives with M2-10」家族 + 页面结构骨架（分段卡/说明行），
  **零假开关**。

## read_first

1. `.work/gsd/phases/m2-3-ui-shell/M2-3-CONTEXT.md`——D2/D3/D4/D5/D6/D7 + OQ-4 映射表
   全文（T2 正本）。
2. `research/ALCEDO-FEATURE-MAP.md` §1.3/§1.4——布局注释正本 + 设置九页。
3. `App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift` + `FilmstripView.swift`
   + `WorkspaceModel.swift`（P1 缝正本）。
4. `App/Sources/Lightamer/UI/EditorAreaView.swift`——全文（KD-1 包装边界；ZoomHUD/
   busy/手势面零改动清单）。
5. `App/Sources/Lightamer/UI/InspectorView.swift` + `Inspector/IOPPanelProvider.swift`
   ——面板宿主形态 + 注册面（新栈复用形态正本；两文件本身禁改）。
6. `App/Sources/Lightamer/State/PipeCoordinator.swift:1355-1385`——PREVIEW 渲染回调 +
   `HistogramReduce.rgbMinMax` fence 先例（示波器 tap 落点）。
7. `LightamerIOP/Sources/Common/HistogramReduce.swift` + `HistogramReduceKernels.metal`
   ——GPU reduce 先例（D6 归属与 kernel 风格正本）。
8. `LightamerCore/Sources/Decode/RAWDecoder.swift`——decode（`:37/:68`）+
   readback（`:284`）+ 探针（`:132`）三面（KD-4 例外缝实态）。
9. `LightamerCore/Sources/Pipe/PixelPipe.swift:60-75` + `HistoryHash.swift:140-150`
   ——cache key 组成 + HistoryHash 契约原文。
10. `App/Sources/Lightamer/UI/SettingsView.swift`——既有三节 + `visibleCatalogSectionMarkers`
    （`:52`）门控面（重组保真正本）。
11. `Tests/LightamerTests/LayerUIWiringTests.swift` 等 PanelWiring 族——面板接线测试
    形态（零改动全绿为基线对账项）。

## 纪律（强制）

1. 提交纪律：每任务独立提交（全英文 Conventional、≤72 字符祈使句、body what+why）；只
   add 本任务申报文件；不 push；`.work/gsd/...` 真路径。
2. 构建纪律：`caffeinate -dis` 包裹；不加 `-derivedDataPath`；新文件同 commit
   `tuist generate`（T2/T3 各有新 .metal/.swift → 各自 generate）。
3. 测试纪律：`Scripts/test-direct.sh '<Class>'` 双读（L028）；**基线 = 2049 +
   M2-3-1/M2-3-2 终值**；全套 0 fail；在案 flake 归因惯例。
4. 边界纪律：每任务检查 `.work/config.toml [gsd]`。
5. 架构红线（本 plan 申报例外全表）：`LightamerCore/` 仅 `RAWDecoder.swift` 一个文件
   且仅增量（默认参数零行为变化）；若 KD-4 膨胀字段规则触发，`RAWTechnicalParams.swift`
   + HistoryHash 侧同批追加并**当场更新本 front-matter 与纪律 5**（DECISIONS 记录）；
   `Inspector/` 33 面板文件 + `InspectorView.swift` + `InspectorRowView.swift` +
   `LightamerIOP` 既有文件（HistogramReduce 例外为**只读参照**，禁改）零 diff；新增
   Metal 文件仅 `ScopeReduceKernels.metal`；legacyBody 树资产零 diff；新 UI 全量
   `String(localized:)`。

## Tasks

### T1 三段布局填充（工具轨 + 视口包装 + 右栏容器 + 胶片条挂载）

- **read_first**：上列 1/3/4。
- **action**
  1. **前置核对步**：legacy gate 冻结快照覆盖面核对（KD-1）——结论（编辑器域在/不在
     快照内）写 DECISIONS，定 EditorAreaView 触碰策略（增量缝 vs 零 diff 包装）。
  2. 新建 `EditorToolRailView.swift`：History/Versions/Nodes 三按钮（图标 + 文字标签，
     Alcedo 0.3.0 形态）+ 展开面板容器（History = 现行 history stack 行列表挂接：操作名
     + 时间，undo/redo 头部按钮；Versions/Nodes = 空态「arrives in M2-8/M2-4」）+ 推挤
     动画（视口宽度过渡，共享常量）+ `editor.rail.<name>` marker。
  3. `EditorWorkspaceShellView.swift` 填充：HStack{工具轨 | 胶片条竖列(FilmstripView) |
     中视口(EditorAreaView child) | 右栏(ScopePanelView 槽 + EditorAdjustmentStackView
     槽)}；顶栏回退按钮接线 `closeEditor()`；当前图 EXIF 经 `WorkspaceModel` ←
     `LibraryGridModel` 行读出。
  4. 胶片条挂载：消费同一 `LibraryGridModel`（同集合过滤语义，P1 KD-3）；点选 → 当前图
     切换（与网格选中同源）。
  5. 工具轨三态 + 推挤状态断言**归 T2 的 `EditorStackRoutingTests` 同批补**（该测试
     文件 T2 新建，T1 不建测试文件——时序约束：T1 只交 marker 与视图件）。
- **验收标准**
  - [ ] 三段方位 == Alcedo 布局注释语义（tool rail left / viewport center / scopes +
        stack right）+ 左胶片条竖列（用户修订）；marker 断言在册。
  - [ ] EditorAreaView 既有行为零迁移（手势/overlay/busy 断言面 = 既有测试零改动全绿）；
        legacy gate 快照测试零改动全绿。
  - [ ] 全套回归 `0 fail`。

### T2 七页签路由表 + 33 面板归页 + 节点头 + TAB-MATRIX 落盘

- **read_first**：上列 1（OQ-4 表全文）/5/11。
- **action**
  1. 新建 `EditorTabRoute.swift`（KD-2 全量：枚举 Alcedo 页序 + RoutingTable 静态映射
     + PanelDescriptor/Advanced 组标记 + 特例入口注释 yiyin/MCP/Preset）。
  2. 新建 `EditorAdjustmentStackView.swift`：页签条（七页签横排，Alcedo
     `EditorAdjustmentStack` 形态）+ 页内容 = 路由表面板实例化宿主（复用
     InspectorRowView 宿主形态 + editingState 层上下文，与 M1 行为一致）+ 头部全局
     Preset 入口 + `editor.stack.tab.<name>` marker。
  3. 新建 `EditorNodeHeaderView.swift`：节点名（v1 = 「Color Grade」常量，M2-4 真节点）
     + 焦距/光圈/快门/ISO（LibraryImageRow EXIF 列读出，Empty 态「—」）。
  4. Display Transform 页 = AgX 面板 + DRT 占位节；RAW Decode 页槽位（T4 填充前先挂
     空态）；Mask 页 = LayersPanelView 实例 + MaskToolbar 联动入口。
  5. 独有入口：TopBar 加 yiyin 按钮（YiyinPanelView + TextOverlayPanelView sheet）；
     MCP/Preset 现状入口确认不变。
  6. 新建 `.work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md`（与 RoutingTable 逐行
     对账：页签 × 面板 × 组语义 × Alcedo 对应物 × Alcedo 无对应标注）。
  7. 新建 `Tests/LightamerTests/EditorStackRoutingTests.swift`：路由表完备性四断言
     （启用面板恰一次/页序/禁用 6 零命中/特例四件不在表内）+ md 与表行数一致断言
     （读 md 文件逐行对账）。
- **验收标准**
  - [ ] 路由表四断言全绿；TAB-MATRIX md 逐行与表一致。
  - [ ] 33 面板文件 + InspectorView/InspectorRowView 零 diff（`git diff --stat` 核）；
        PanelWiring 族既有测试零改动全绿。
  - [ ] 全套回归 `0 fail`。

### T3 示波器 GPU kernel + ScopePanelView

- **read_first**：上列 6/7 + `.work/LESSONS.md` L031（`:261`）/L014 原文。
- **action**
  1. 新建 `LightamerIOP/Sources/Common/ScopeReduceKernels.metal`：bin kernel（atomic
     归约，256×4 通道）+ 波形 kernel（列下采样散点）。
  2. 新建 `LightamerIOP/Sources/Common/ScopeReduce.swift`：两 pass 宿主（`histogram(of:
     texture, metal:)` → 4KB buffer；`waveform(of:texture,metal:)` → 小纹理；fence 纪律
     同 HistogramReduce 先例；Sendable 结果值类型）。
  3. 修改 `PipeCoordinator.swift`（增量缝）：PREVIEW 渲染完成回调后 + scopes 可见 +
     节流窗允许 → enqueue ScopeReduce（唯一队列路由点，禁第二 command queue）；结果
     经 `@MainActor` 状态发布。
  4. 新建 `ScopePanelView.swift`：直方图/波形二选一（分段卡，Alcedo
     `EditorScopePanel` 形态：Show histogram / Show waveform）+ 直方图 4 通道叠加绘制 +
     波形小纹理直显 + 节流宿主（≤15Hz + idle ≥250ms 补算）+ P1 View toggle 命令点亮。
  5. 新建 `Tests/LightamerTests/ScopeReduceTests.swift`：合成纹理（已知分布：纯色/双峰/
     渐变三 case）bin 计数逐 bin parity（总和不丢像素）+ 波形列统计 parity + 确定性
     （同输入双跑逐字节）+ 空纹理零崩。
- **验收标准**
  - [ ] 三 case bin parity + 波形 parity + 确定性断言全绿。
  - [ ] 队列路由：新增代码零 `makeCommandQueue()`（grep 断言）；L031 复审项过。
  - [ ] 全套回归 `0 fail`。

### T4 RAW Decode 面板 + decode overrides 增量缝

- **read_first**：上列 8/9 + `App/Sources/Lightamer/UI/Inspector/ExposurePanelView.swift`
  （滑杆面板形态参照）。
- **action**
  1. 修改 `LightamerCore/Sources/Decode/RAWDecoder.swift`（KD-4 增量缝：overrides
     参数默认 identity + filter 键位先写后读 + decoder version 用户强选与探针交集 +
     typed 降级）；readback 字段覆盖核对（boost/sharpness 腿），膨胀字段规则触发时按
     纪律 5 处理。
  2. 新建 `RawDecodePanelView.swift`：NR 四滑杆（amount/luminance/chroma/sharpness）
     + decoder version 三选（default/v8/v9——`demosaic` 语义对齐 Alcedo 入口命名，
     CIRAW 实际 = decoder version 档）+ boost 滑杆 + 相机不支持 v9 的行内降级提示 +
     「Reset」identity 按钮 + `editor.rawdecode` marker；写 `WorkspaceModel` 会话级
     overrides → 解码请求链 → 缓存失效即时重渲。
  3. Display Transform 页空态槽位换挂本面板（T2 槽位点亮）。
  4. 新建 `Tests/LightamerTests/RawDecodeOverridesTests.swift`：overrides 应用断言
     （decode 后 rawTech 字段 == overrides 值）+ 默认参数 decode 输出与既有路径逐字节
     一致 + cache key 漂移断言（NR 变 → key 变；identity → key 不变）+ 越界钳制
     （amount>1 钳 1 等）+ v9 不支持相机 typed 降级。
- **验收标准**
  - [ ] overrides 应用/identity 逐字节不变/cache key 漂移三断言全绿。
  - [ ] `RAWDecoder.swift` diff 仅增量（逐 hunk 评审：无既有语句改动）；既有 Decode
        域测试零改动全绿。
  - [ ] 全套回归 `0 fail`。

### T5 Settings 七页 + Import Defaults + Displays/MCP 迁移

- **read_first**：上列 10 + `LightamerCore/Sources/Library/ImportFilter.swift`
  （`ImportDefaults` 三键面）+ `App/Sources/Lightamer/Library/LibraryPreferences.swift`
  （键惯例参照）。
- **action**
  1. 修改 `SettingsView.swift`：NavigationSplitView 左列表右内容重组（KD-5）；三既有节
     内容原样迁入 displays/mcp 页容器（语句零语义改动，逐 hunk 评审）；Catalogs 门控
     逻辑零改动。
  2. 新建 `App/Sources/Lightamer/Settings/AppPreferences.swift`：`mask.behavior.default`
     三选 + cache 页偏好 + keyboard 表数据宿主（UserDefaults 惯例，typed 包装）。
  3. 新建 `Settings/SettingsPages.swift`：十页内容件（KD-5 页集全量——LCR/ACA 空态
     骨架、Keyboard 冲突检测 + 恢复默认、About 版本/许可、Import Defaults 三选 +
     remember 消费 `ImportDefaults`）。
  4. 新建 `Tests/LightamerTests/SettingsPagesTests.swift`：页 id 集精确 == 十项（
     Acceleration/Updates 负例在册）+ Default Behavior 三选 round-trip + Keyboard 冲突
     检测器单测（撞键对检出/无撞零报）+ Catalogs 页 gate 两态可见性 + Import Defaults
     键绑定断言（写读一致 + reset）。
- **验收标准**
  - [ ] 页 id 集断言 + 三选 round-trip + 冲突检测断言全绿；Catalogs 门控既有测试
        零改动全绿。
  - [ ] Displays/MCP 节语义零迁移（既有 Settings 相关测试零改动全绿）。
  - [ ] 全套回归 `0 fail`。

### T6 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（计数/秒数入 SUMMARY）。
  2. 落盘 `M2-3-3-SUMMARY.md`（测试数/KD 确认/例外缝 diff 证据/禁用 6 名 grep 证据）+
     `M2-3-3-DECISIONS.md`（KD-1..5 执行确认 + 前置核对结论 + 偏差归因 + M2-4 挂账项）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-3-3 完成 + 下一步 = M2-3-4 收口）；LESSONS
     如踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 5 例外全表核对）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 三段方位语义（rail left/viewport center/scopes+stack right）+ 左竖胶片条挂载同集合态；工具轨 History 真挂/Versions+Nodes 空态 marker | EditorStackRoutingTests + marker 断言 |
| 2 | EditorAreaView 行为零迁移：既有视口/手势/overlay 测试零改动全绿；legacy gate 快照零改动全绿；EditorAreaView diff 仅增量（前置核对结论在 DECISIONS） | 既有测试零 diff 全绿 + 逐 hunk 评审项 |
| 3 | 路由表完备性：启用面板全集恰一次归页；页序 == Alcedo 七页序；禁用 6 op 名 grep 零命中；TAB-MATRIX md 与表逐行一致 | EditorStackRoutingTests + `git grep -i` 禁用名 |
| 4 | 33 面板文件 + InspectorView/InspectorRowView/IOPPanelProvider 零 diff；PanelWiring 族零改动全绿 | `git diff --name-only` |
| 5 | ScopeReduce：三 case bin 逐 bin parity + 波形 parity + 确定性；零第二 command queue（grep）；直方图读回 fence 在册 | ScopeReduceTests + grep 断言 |
| 6 | 示波器节流：拖动 ≤15Hz + idle 补算 + 不可见零 tap（状态机单测） | ScopePanelView 宿主状态断言 |
| 7 | RAW Decode overrides：应用断言 + identity 逐字节不变 + cache key 漂移/不漂移双断言 + v9 降级 typed | RawDecodeOverridesTests |
| 8 | `RAWDecoder.swift` 唯一 Core 触点且仅增量（默认参数既有调用零改动）；Decode 域既有测试零改动全绿 | 逐 hunk 评审 + 既有测试零 diff 全绿 |
| 9 | Settings 页 id 集 == 十项精确（Acceleration/Updates 负例）；Default Behavior 三选 round-trip；Keyboard 冲突检测；Catalogs 门控/Displays/MCP 零迁移 | SettingsPagesTests + 既有 Settings 测试零 diff 全绿 |
| 10 | 新 UI 全量 `String(localized:)`；legacyBody 树资产零 diff | grep + `git diff --name-only` |
| 11 | 全套回归 0 fail，计数 ≈ 基线 + 25..35 | test-direct.sh Executed/failures 双读 |
| 12 | diff 边界 == 申报文件集（含纪律 5 例外全表）；越界 = 违约 | `git diff --stat` 逐文件核对 |

## 风险与边界

- **GPU 示波器与 PREVIEW 管线并发（L031 域）**：示波器 compute 与 PREVIEW 渲染共用
  command buffer 串行语义 + 唯一队列路由点，杜绝跨队列竞速；残余风险 = 节流宿主状态
  竞争——节流纯 MainActor 状态机（单测覆盖）；若实测示波器拖累 PREVIEW 帧率（P4
  computer-use 走查），后备 = 采样半分辨率 ROI（方案记 DECISIONS，不砍波形）。
- **atomic bin kernel 正确性**：Metal atomic_float 不可用——bin 用 `atomic_uint` 计数
  （整型直方图），像素非负浮点 → bin index 取整后计数，语义 = 计数直方图（与 CPU 参考
  逐 bin 精确可比）；归一化在绘制层。测试三 case 钉语义。
- **legacy gate 快照覆盖编辑器域的可能性**：KD-1 前置核对步是硬闸——若快照含编辑器
  identifier，EditorAreaView 走零 diff 包装（新增外层文件承载三段壳），计划内的增量缝
  放弃；不影响其余任务。
- **RAWTechnicalParams 膨胀字段**：KD-4 规则触发面小（预估不需扩），一旦触发 = front-
  matter/纪律 5/DECISIONS 同批更新，禁静默扩字段。
- **Settings 重组回归面**：SettingsView 承载 M2-2-4 Catalogs 门控 marker 与 13-2 显示
  覆盖行——重组保持节容器原语（Section/Picker 语句零语义改动），两族既有测试零改动
  全绿为硬判据。
- **胶片条与工具轨并存的左轨宽度**：竖向胶片条（用户修订）+ Alcedo 左工具轨同侧并存
  ——布局 = 工具轨窄列（40pt 级）+ 胶片条列（160pt 级）串联，互推挤视口；P4 computer-use
  走查为观感裁决点（偏差-接受/偏差-修判定）。
- **空态文案与 zh**：空态家族键（`editor.versions.placeholder` 等 6 键）随手写 en，
  zh 随 P4 补录。

## 提交约定

- T1 `feat(ui): editor three-section layout with tool rail and filmstrip`
- T2 `feat(ui): seven-tab adjustment routing table with panel rehoming`
- T3 `feat(iop): gpu histogram and waveform scope kernels`
- T4 `feat(decode): raw decode panel over ciraw technical overrides`
- T5 `feat(ui): settings pages with ten entry navigation`
- T6 `docs(m2-3): close out plan 3 editor face`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。
