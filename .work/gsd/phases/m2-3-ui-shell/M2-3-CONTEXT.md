# Phase M2-3: UI 壳重设计（Alcedo 克隆）— Context

> discuss/research 起草稿（2026-09-28）。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` §1（UI 结构总览逐屏）/ §1.4（设置页）/ §8（AI 功能——LCR/ACA 设置页语境）；需求 = REQUIREMENTS **M2UIW-01..06** + **M2LIB-05 壳半边**（Inspector 面板/网格/搜索对话框壳与视觉验收，OQ-11 切分线）+ **M2DIS-03 后半**（七页签 IA 收纳）+ M2LIB-07③④ 挂账（Inspector 批量 relink UI / ImportDefaults 设置页 UI）。**视觉验收 = computer-use 开 `/Applications/AlcedoStudio.app` 真机对照截图（2026-09-27 用户授权，UAT 自答先例同款；实机在位已复核 2026-09-28）**。

## Phase Boundary

**范围**（ROADMAP M2-3 行）：

1. **双工作区路由**（M2UIW-01）——Library/Editor 两态 + 顶栏 + 暗色玻璃主题 tokens。
2. **图库**（M2LIB-05 壳半边）——缩略图网格（消费 M2-2-3 `LibraryQueries.searchPage/searchNullTail` keyset 分页）+ Album Inspector 面板（四分组/Activity view/Overview 总数卡/SEARCH FILTER 过滤态区，数据 API 已交付、壳零 SQL）+ 全局搜索三合一对话框（EXIF 词法腿真接已交付 Parser；CLIP/全文腿壳占位，见 OQ-8）+ Inspector 批量 relink UI（M2LIB-07③ 挂账）+ 缩略图首屏（M2-2-3 观察项挂账）。
3. **编辑器三段布局**（M2UIW-02）——左工具轨（History/Versions/Nodes 图标列 + 展开推挤）+ 中视口（FIT/百分比读出/裁剪角度徽标/双级 busy/手势缩放平移）+ 底部胶片条（与图库同集合过滤）+ 右示波器（M2UIW-04）+ 七页签调整栈（M2UIW-03）。
4. **七页签 IA 收纳**（M2DIS-03 后半 + D6）——33 个 M1 IOP 面板 + yiyin/MCP 独有项按映射表归页（见 OQ-4）。
5. **设置页族**（M2UIW-05 + M2LIB-07④ 挂账）——见 OQ-7。
6. **后台任务系统 UI**（M2UIW-06）——对话框 + 底部栏 + 取消（导入/AI/导出共用；导入腿接 M2-2-2 `ImportService` 进度快照，AI 腿数据面 M2-10）。
7. **zh/en 文案补录 + 菜单 IA 收纳**——新 UI 全量 `String(localized:)` 键 + zh 补录审计（OQ-9）；Menu 命令面收纳（Session 死路由清理，M2LIB-06 登记）+ 快捷键策略（OQ-11）。
8. **视觉验收**——computer-use Alcedo 真机逐屏对照（判定方法见 OQ-1，执行方式见 OQ-10）。

**非目标（本 phase 明确不做）**：

- **节点编辑模型**（M2-4）——PipelineDocument/图命令/所有权校验；Nodes 工具轨 = 壳占位空态。
- **Color Grade 18 项目录 / LGG trackball / ACEScc 域**（M2-5）——Grade 面板只挂既有 M1 模块参数。
- **DRT 功能体**（M2-6）——Display Transform 页签壳先立（暂驻 AgX 现面板），DRT 面板 M2-6 替换。
- **蒙版体系**（M2-7）——图上绘制/手柄 overlay 交互；Mask 页签挂现有 adjustment layers 面板，Default Behavior 设置 UI 落 M2-3（设置项存 UserDefaults，行为接线 M2-7 消费）。
- **版本/历史 mini-git**（M2-8）——Versions 工具轨 = 占位空态；History 工具轨挂现有 history stack。
- **导出 Alcedo 化**（M2-9）——既有 ExportPanelView 保留挂接。
- **AI 图库功能**（M2-10）——CLIP 嵌入/自动打标/AI 评片功能体；LCR/ACA 设置页功能体。
- **删除 Session/Catalog 代码**——M2LIB-06 裁决延续；legacyBody 冻结策略见 OQ-12。

## Existing Code Insights

### Reusable Assets（M1/M2-2 资产盘点，2026-09-28 Grep 实测）

| 资产 | 位置 | M2-3 复用判定 |
|---|---|---|
| `ContentView`（699 行）gate 分叉：`legacyBody`（既有树 verbatim 迁入，M2-2-4 T2 字节同构机检）↔ `ProjectWorkspaceFace`（:655，gate=false 默认启动面 = 项目工作区最小容器，无项目 → P2 Welcome sheet 占位） | `App/Sources/Lightamer/UI/ContentView.swift` | **新壳挂接点**——M2-3 把 ProjectWorkspaceFace 内层演进为 Library workspace + 新增 Editor workspace 路由；`legacyBody` 按 OQ-12 处置 |
| `ProjectWorkspaceFace` / `ImportModeDialog` / `ImportProgressView`（M2-2 交付 UI 面） | 同上 + `App/Sources/Lightamer/Library/` | **直接演进**——Welcome 面升格 P1、导入对话框/进度接入 M2UIW-06 后台任务栏 |
| `LibraryQueries`（searchPage/searchNullTail/overviewCount/groupCounts 四键/activitySeries/dayFilter/currentFilterDescription）+ `ExifSearchParser.parse` + `SmartAlbumStore.evaluate(.library)` | `LightamerCore/Sources/Library/`；接口面清单 = `phases/m2-2-library-project/M2-2-3-SUMMARY.md`「M2-3 数据接口面清单」节 | **壳零 SQL 直接引用**——网格分页/Inspector 四分组+Activity/搜索过滤态/智能相册成员集全部现成 |
| `SessionThumbnailProvider` 双档缩略图管线（档 A ImageIO 720 超采样 **10.6ms/张 @86MP**；档 B 真管线渲；`has_edits`+stale 裁决）+ `ThumbnailDiskStore` | `LightamerCore/Sources/Session/` | **图库/胶片条缩略图源**——首屏挂账 M2-2-3 观察项，本 phase 交付消费面 |
| `InspectorView`（400 行）+ `InspectorRowView` + **33 个 IOP PanelView**（`App/Sources/Lightamer/UI/Inspector/`：Exposure/Temperature/ToneCurve/Levels/Colisa/Shadhi/Gamma/ColorContrast/Vibrance/Velvia/Monochrome/ColorBalanceRGB/ColorZones/SkinSmooth/Sharpen/HighpassSoften/LocalContrast/Equalizer/Crop/Flip/Ashift/Lens/Liquify/Retouch/ChannelMixer×2/Grain/Bloom/Vignette/Dehaze/TextOverlay/Lut/AgX/FilmicRGB/Sigmoid/DenoiseProfile/NLMeans/Bilateral 等） | `App/Sources/Lightamer/UI/Inspector/` | **七页签收纳的分派对象**——面板本体不动，按 OQ-4 映射表重新挂接到页签路由 |
| 禁用模块 6 个 PanelView 文件仍在库（FilmicRGB/Sigmoid/AgX/DenoiseProfile/NLMeans/Bilateral） | 同上 | M2-1 注册面收窄已保证不出现；处置见 OQ-5 |
| `EditorAreaView`（613 行，视口挂 `EditorMTKView` NSViewRepresentable）+ `ViewportFit` + 双级 busy 雏形 + `Overlay/` 族（Crop/Mask/Liquify/Retouch OverlayHost + `MaskToolbarView` + `InstancePickerOverlay`） | `App/Sources/Lightamer/UI/` | **三段布局重组对象**——视口/手势/overlay 底座全保留，外壳换 Alcedo 三段式 |
| `LayersPanelView` / `LutPanelView` / `YiyinPanelView` / `PresetPanelView` / `McpLauncherPanelView` / `ExportPanelView` / `PresetManagerWindow` | `App/Sources/Lightamer/UI/` | **一等公民面板**——按 OQ-4 归页；yiyin 面板入口形态单独裁决（OQ-4 内） |
| `HistogramReduce.rgbMinMax`（GPU reduce，Phase 3 交付；`PipeCoordinator.swift:1371` 消费） | `LightamerIOP/Sources/Common/HistogramReduce.swift` | **示波器底座**——min/max 归约 ≠ 直方图 bin；bin/波形 kernel 为本 phase 新增（OQ-6） |
| `LightamerApp.swift`（1905 行）：9 个 CommandMenu/CommandGroup、**25 个 keyboardShortcut**；Session 项未门控（M2LIB-06 登记 inert 死路由，菜单 IA 收纳归本 phase）；Settings scene 挂 `SettingsView`（406 行 = Displays/Catalogs(gated)/MCP 三节） | `App/Sources/Lightamer/UI/LightamerApp.swift` + `SettingsView.swift` | **菜单 IA 收纳对象 + 设置页族起点**——Alcedo 九页 vs 现三节，范围见 OQ-7 |
| `SidebarView`（999 行）/ `SessionBrowserView`（540）/ `CullingView`（277）/ `FilterBarView` / `CatalogBrowser*` | `App/Sources/Lightamer/UI/` | legacyBody 树资产——冻结（OQ-12） |
| zh String Catalog：`Resources/Localizable.xcstrings` **1146 键（language code = `zh`，非 zh-Hans）**，en 1131；M2-2 新 UI verbatim 英文键未入 catalog | `Resources/Localizable.xcstrings` | **zh 补录审计对象**（OQ-9）；新键沿用 `zh` code 不引入 zh-Hans 第二码 |
| Alcedo 实机：`/Applications/AlcedoStudio.app`（2026-09-28 复核在位）+ computer-use 授权（GOAL-STATE 环境备忘） | — | 视觉验收参照物；GPL-3.0——只截图对照布局语义，tokens/图形资产/代码禁拷 |

### Integration Points

- 双工作区路由落在 App 层（`ContentView` gate=false 分支），Core 零改动预期（壳消费既有 API）。
- 图库/胶片条共用同一 `FilterPredicateGroup` 集合态（Alcedo「与图库同集合过滤」语义）——过滤态模型需从 legacyBody 的 Session 域视图状态迁到 Library 域 `ExifSearchFilter`。
- 设置页新增键走 UserDefaults 惯例（`ImportDefaults` 先例：`library.import.rawExtensions` / mode / rememberMode）。
- 后台任务栏三腿共用一个注册表协议（导入 = `ImportProgress` 快照；导出 = `ExportQueue` 既有四态；AI = M2-10 预留）。

## Open Questions（待用户裁决；每条含推荐）

### OQ-1 视觉验收的「像」标准与判定方法（必裁——决定整 phase AC 语义）
QML→SwiftUI 无法逐像素（渲染栈/字体/图形 API 全不同），且 Alcedo 是 GPL——像素级复刻在法律与工程上都不成立。「像」的可行定义：
- **A（推荐）**：**信息架构/布局语义级对齐**——逐屏判定「元件逐一存在 + 方位布局一致（Alcedo `EditorWorkspace.qml` 不可协商注释：tool rail left / viewport center / scopes + adjustment stack right）+ 交互语义一致（FIT 切换/双击/推挤动画/页签切换）」；**判定方法 = 逐屏差异清单**：computer-use 每屏对 Alcedo 与 Lightamer 各截一张 → 表格化逐行标注「一致 / 偏差-接受 / 偏差-修」，不要求叠图。
- B：像素级近似（等比布局 + 近似配色 tokens）——成本高收益低；tokens 只能「视觉参考后自写」（GPL DESIGN.md 数值禁逐值拷），像素级验收不可判。
- C：分屏叠对（50% 叠加）——两 app 内容/窗口尺寸/内容密度不同，叠对大量误报，仅作个别屏（顶栏/工具轨）的辅助手段。
**推荐 A**；tokens 语义 = 暗色玻璃卡片家族（colCardSurface/colCardBorder 的视觉意图），数值自写自测。

### OQ-2 双工作区切换形态与入口（M2UIW-01）
Alcedo = 单窗口两态路由（LibraryWorkspace/EditorWorkspace + WorkspaceHost），无 tab 无双窗：
- **A（推荐）**：**同款两态路由**——项目面（ProjectWorkspaceFace 演进 = Library workspace）↔ 编辑器 workspace；入口 = 图库网格双击图 → 编辑器；编辑器顶栏回退按钮/⌘W 关图回图库；切换保留集合态与选中态（往返无损）。
- B：单窗口 Library/Editor segmented tab——偏离 Alcedo 视觉验收基线。
- C：双窗口——更 macOS 但偏离「完全模仿 Alcedo」重定义。
**推荐 A**；Welcome 面保持 P2 语义（无项目时启动落 Library 空态 + 新建/打开入口）。

### OQ-3 编辑器「活体」边界：M2-3 时点节点模型（M2-4）未落地，七页签/工具轨显示什么（必裁）
- **A（推荐）**：**活体壳策略**——既有功能真接、缺失功能明确空态：
  - Tone/Look/LUT/Geometry/Mask 五页签挂**现行平铺管线**既有 33 面板（无节点概念，参数直调现行 history stack，行为与 M1 一致）；
  - Display Transform 页签 = 暂驻 AgX 现面板 + 「DRT arrives with M2-6」占位节；
  - RAW Decode 页签 = 新建 CIRAW 参数面板（M2DIS-04 明文「CIRAW NR 参数族在 RAW Decode 页签暴露」——本 phase 交付基础参数族：NR amount/luminance/chroma + decoder version + boost，Neural Engine demosaic 细节 M2-5+ 校准）；
  - 左工具轨 History = 挂现有 history stack；Versions = 占位空态（M2-8）；Nodes = 占位空态（M2-4）；
  - 示波器/胶片条/FIT 读出/双级 busy = 真数据真交互。
- B：纯静态壳（面板不接数据）——视觉验收能过，但交互验收空白 + M2-4 二次接线浪费。
- C：本 phase 先做最小节点模型——范围爆炸，违 ROADMAP 依赖序（M2-4 依赖 M2-3 而非反向）。
**推荐 A**；空态文案统一「<Feature> arrives in M2-x」家族。

### OQ-4 七页签收纳映射表（M2DIS-03 后半 + D6；逐面板归页草案——必裁）
33 面板 + 独有项 → Tone / Look / LUT / Display Transform / Geometry / RAW Decode / Mask（Alcedo `EditorAdjustmentStack.qml:10-16` 页序）：

| 页签 | 挂接（M1 面板） | 说明 |
|---|---|---|
| **Tone** | Exposure / Temperature / ToneCurve / Levels / Colisa / Shadhi / Gamma / ColorContrast | Alcedo Tone = WB/Exposure/Contrast/White/Black/Shadows/Highlights/Curve；temperature 面板 M2-5 前 = 现 M1 语义，M2-5 换 CAT02 |
| **Look** | Vibrance / Velvia / Monochrome / ColorBalanceRGB / ColorZones / SkinSmooth / Sharpen / HighpassSoften / LocalContrast / Equalizer / Grain / Bloom | Alcedo Look = Saturation/Vibrance/Selective Color/LGG/Detail/Texture；Velvia/Monochrome/SkinSmooth = D6 独有增强归 Look 子组；LGG 色轮 M2-5 落（ColorBalanceRGB 暂驻） |
| **LUT** | LutPanelView（+ TextOverlay? 见下） | 递归扫描/根目录配置 = M2GRADE-05/06 在 M2-5 落，页签先挂现面板 |
| **Display Transform** | AgX 现面板 + Vignette | DRT 面板 M2-6 替换；grain/bloom 按 Alcedo 语义属 DRT 后 Post——M2-6 前暂驻 Look 页，M2-6 迁 DRT 后段（草案：本 phase 暂驻 Look，避免 M2-6 二次搬家） |
| **Geometry** | Crop / Flip / Ashift / Lens / Liquify / Retouch / Dehaze / ChannelMixer×2 / Hazeremoval | Alcedo Geometry = crop/rotate/aspect（全图）；D6 独有项（liquify/retouch/ashift/CA 系/haze/channelmixer 系）归本页「Advanced」折叠组，不破坏 Alcedo IA |
| **RAW Decode** | 新建 CIRAW 参数面板（NR amount/luminanceNR/chromaNR/sharpness + decoder version + boost/highlights 处理） | M2DIS-04 载体；相机 WB/CAT02 分界按 D4（相机 WB 留解码层） |
| **Mask** | LayersPanelView（现有 adjustment layers）+ MaskToolbar 联动 | M2-7 Mask Groups 替换；本 phase = 现面板归位 |

- **独有面板入口**（不属于七页签调整参数）：**YiyinPanelView**（推荐 = 顶栏独立按钮，水印/印框是导出域一等公民，Alcedo 无对应物）、**McpLauncherPanelView**（推荐 = 窗口/菜单入口，现状保持）、**PresetPanelView**（推荐 = 七页签头部全局入口，Alcedo 无预设面板——沿 M1 Inspector 底部 + 管理器窗口现状）。**TextOverlayPanelView** = yiyin 文本 overlay 载体（推荐随 yiyin 顶栏入口）。
- **A（推荐）**：照上表生效（细节偏差 plan 期微调，映射表落 MATRIX 类文档与 M2-1 矩阵同格式）。
- B：逐页签再裁决——七页每页一问，粒度过细。
- C：独有项全部藏进「Advanced」单组——D6 说「归入七页签的对应分组」，yiyin 一等公民定位冲突。
**推荐 A**；映射表批准后进 plan 成为挂接任务的验收输入。

### OQ-5 禁用模块（filmic/sigmoid/agx/降噪三件）面板文件在 M2-3 的额外清理
- **A（推荐）**：**零额外删除**——M2-1 注册面收窄已钉死「禁用项不出现在任何面板/预设/批量/MCP」五面；七页签挂接按 OQ-4 映射表进行，映射表不含禁用项 → PanelView 文件自然失去挂接点（文件保留 = M2DIS「代码+测试保持全绿」政策）；`LIGHTAMER_FULL_IOP_FACE=1` 全量回切时走 env 面（七页签外保留 legacy 平铺挂接路径或测试内直挂，PanelWiringTests 依赖面不动）。收尾审计加一条「禁用 op 名在新壳路由表 grep 零命中」。
- B：删 6 个 PanelView 文件——与「代码保留」裁决冲突，测试连带破坏。
- C:灰显保留在页内——违 M2DIS-03「不出现在任何面板」。
**推荐 A**。

### OQ-6 示波器实现路径（M2UIW-04 直方图/波形二选一）
- **A（推荐）**：**GPU compute**——直方图 = 新增 Metal bin kernel（256-bin × RGB + luma，对 PREVIEW 管线输出纹理直采，unified memory 零拷贝）；波形 = 逐列下采样 + 亮度散点写入小纹理（≤1080 宽预览上限）；节流 = 参数变化/拖动中降频（如 ≤15Hz）+ 帧稳定后单次计算；`HistogramReduce` 先例（`LightamerIOP/Sources/Common/HistogramReduce.swift`，GPU reduce 已有消费缝 `PipeCoordinator.swift:1371`）扩 bin/波形 pass，同一 compute 框架。
- B：CPU 读回采样——L014 fence 纪律负担 + 大图读回延迟，双级 busy 的「调整渲染中」层级被示波器拖累。
- C：Core Image `CIAreaHistogram`——直方图可用但无波形 + CI/Metal 上下文往返开销。
**推荐 A**（M2UIW-04 本就写明 GPU 渲染；本问裁的是 kernel 归属——LightamerIOP Common 扩展 vs App 层 Metal——推荐 LightamerIOP Common 沿 HistogramReduce 先例，可单测）。

### OQ-7 设置页族 v1 范围（M2UIW-05 + M2LIB-07④ 挂账）
Alcedo 九页 = Language/Theme、Default Behavior、Cache、Local Content Recognition、Advanced Content Analysis、Acceleration、Updates、Keyboard、About（§1.4）。M2UIW-05 明文 = 语言/主题、Default Behavior（蒙版绘制三选）、缓存、LCR、ACA、键盘自定义（冲突显示+恢复默认）、关于——恰七页。
- **A（推荐）**：**M2UIW-05 明文七页 + 两个必收挂账节**——①七页照做；LCR/ACA 两页 = 页面结构与「功能体 arrives with M2-10」空态（数据面未到，不放假开关）；②**Import Defaults 节**（M2LIB-07④ 明文挂账：默认方式三选 + 记住我的选择，消费 M2-2-2 `ImportDefaults` 三键）；③既有 Displays/MCP 节保留迁移；④**砍** Acceleration（Metal 恒开无对应面）与 Updates（用户终裁砍苹果渠道/GitHub 分发，v1 无更新器——放空页违诚实空态原则）。LUT 根目录选择器（M2GRADE-06）留 M2-5 落（本 phase 不预埋）。
- B：九页全做——Acceleration/Updates 空壳页虚假。
- C：最小 4 页（语言/Default Behavior/缓存/关于）——Keyboard 是 M2UIW-05 明文、LCR/ACA 是明文，砍明文违需求。
**推荐 A**。

### OQ-8 全局搜索三合一的 M2-3 边界（CLIP/全文腿数据面在 M2-10）
- **A（推荐）**：**壳 + EXIF 词法腿真接**——对话框按 Alcedo `GlobalSearchDialog` 三段结构一次成型；EXIF tab 消费 `ExifSearchParser.parse` + `LibraryQueries`（已交付，typed error 交对话框呈现）；CLIP tab 与 AI 描述/标签全文 tab = 占位空态（「Semantic search arrives with M2-10」）；搜索结果直接过滤图库网格（`ExifSearchFilter` 集合态，Inspector SEARCH FILTER 区经 `currentFilterDescription` 同步显示）。
- B：三 tab 全静态——EXIF 腿已交付不用 = 白扔 M2-2-3 资产。
- C：只做搜索输入框不做对话框壳——偏离 Alcedo 视觉验收面。
**推荐 A**。

### OQ-9 zh/en 双语时序（M2-2 先例 = verbatim 英文键）
- **A（推荐）**：**随手键纪律 + phase 尾统一补录审计**——新 UI 开写即 `String(localized:)` + 英文默认值（键名英文族沿用 `settings_*` / `menu_*` 惯例），zh 值允许滞后；收口批跑对账脚本（新增 `String(localized` 键全集 vs `Localizable.xcstrings` diff）一次补齐 zh（基数 1146 键 `zh` code；M2-2 增量 ~20 + M2-3 预估 150-250 键）；语言 code 不引入 `zh-Hans` 第二码（现状 `zh` 惯例）。
- B：每任务同步 zh——无欠账但面板密集期反复打断，且 M2-2 已确立 verbatim 先例。
- C：推迟独立 phase——欠账滚大，违「产物与文档同批」纪律。
**推荐 A**（M2LIB-06 收口已把 zh 缺口正式挂到 M2-3）。

### OQ-10 computer-use 对照验收的执行方式
- **A（推荐）**：**executor 自照自比 + 验收方独立抽查**——executor 执行尾 computer-use 开 `/Applications/AlcedoStudio.app` 逐屏截图（AX + screencapture，UAT 自答先例同款）与新壳同屏位截图配对，按 OQ-1 差异清单表逐屏标注入 SUMMARY；验收 subagent 独立复开 Alcedo 抽查 2-3 屏防自评放水；computer-use 可用性前置检查 + 锁屏降级（截图留档转人工走查，GOAL-STATE GUI 限制惯例）。
- B：全部留验收方独立对照——executor 零接触 Alcedo，验收方工作量过大且首轮偏差修复往返慢。
- C：一次性用户人工走查——用户已授权自动化对照，人工只在 VALIDATION 终验。
**推荐 A**；证据落 `.work/gui-acceptance/`（惯例路径）。

### OQ-11 Menu 键盘快捷键与 Alcedo 对齐度
- **A（推荐）**：**菜单 IA 对齐 + 快捷键保守**——Menu 收纳 = Session 死路由清理（M2LIB-06 登记）+ Open Project/Import Folder/回图库/进编辑器回路 + View 菜单挂工具轨/示波器/页签可见性；快捷键 = macOS 惯例优先（⌘O/⌘N/⌘S/⌘Z 族现状保留），Alcedo 具体键位**不逐项照抄**（键位表未测绘，QML 键面与 AppKit Command 差异大，照抄收益低）；键盘冲突的最终裁决地 = Keyboard 设置页（冲突显示 + 恢复默认，M2UIW-05 明文）。现 25 shortcut 增删以新 IA 为准。
- B：逐键对齐 Alcedo——需 plan 首任务补「computer-use 逐菜单键位测绘」，可做但收益存疑。
**推荐 A**；若裁决 B，测绘任务并入 plan 第一波。

### OQ-12 legacyBody（`LIGHTAMER_LEGACY_LIBRARY=1` 回切面）维护策略
- **A（推荐）**：**冻结不动**——M2LIB-06 交付时已字节同构机检 + 冻结 `Set<String>` marker 快照钉死；M2-3 新壳完全旁路（gate=false = 新壳默认路径，gate=true = 冻结旧树原样）；本 phase 对 `legacyBody`/Session 面板文件（SidebarView/SessionBrowserView/CullingView/FilterBarView 等）**零 diff** 为收尾审计项；LibraryLegacyGateTests 与快照断言不动。
- B：同步改（旧树也挂七页签）——工作量翻倍，且违回切通道本意（回切 = 看 M1 行为基线）。
- C：删除 legacyBody——违 M2LIB-06「代码保留」裁决。
**推荐 A**。

## Canonical References

- `research/ALCEDO-FEATURE-MAP.md` §1（UI 逐屏）/ §1.4（设置页）/ §8（AI 设置页语境）——IA 正本
- `phases/m2-2-library-project/M2-2-3-SUMMARY.md`「M2-3 数据接口面清单」——壳零 SQL 消费面
- REQUIREMENTS M2UIW-01..06 / M2LIB-05 / M2DIS-03(04) / M2LIB-07③④
- `.work/GOAL-STATE.md` 环境备忘（Alcedo 实机 + computer-use 授权）
- AGENTS.md「Phase 2 架构增量」（Sidecar/哈希/目录惯例）+ M2-1 MATRIX（禁用面）

## Specific Ideas（起草倾向，plan 细化）

- 主题 tokens 单文件（`ThemeTokens.swift` 类）承载暗色玻璃家族语义值，全局唯一来源；禁散落 hex。
- 双工作区路由 = `AppPhase` 枚举（library/editor）+ 关联态（选中图/集合过滤器/滚动位置），切换动画对齐 Alcedo 折叠语义。
- 胶片条与图库网格同一 `LibraryGridModel` 消费者（同一集合态、同分页管线、双档缩略图）。
- 后台任务注册表协议先行（`BackgroundTaskHosting`），导入腿首实现，导出腿 M2-9 消费、AI 腿 M2-10 消费——协议一次成型防三腿三实现。

## Deferred Ideas

- 多项目切换器（v1 单窗口单项目，M2-2 OQ-1 已裁）。
- 触控栏/Stage Manager 适配。
- Keyboard 设置页的「录制式快捷键捕获」——v1 用固定候选 + 冲突提示即可，录制交互 M2 后期。


---

## Ruling（2026-09-29 用户）

D-M2-3-CONTEXT-1..12 = OQ-1..12 **全部按推荐 A 生效**，唯一修订：**胶片条不放底部，放编辑器左侧竖向滚动**（用户偏好，偏离 Alcedo 底部布局——M2UIW-02 同步修订）。OQ-10 的 computer-use 对照以修订后的布局为准（左侧胶片条为本项目标识性差异）。
