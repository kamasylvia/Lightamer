# UI Stack Successor Pre-Research — AppKit vs GPUI Preparation

> **性质**:轻量 research（M8 前置批先例形态；纯只读侦察，零源码触碰，doc-only commit）。
> **前提（用户战略判断，本文不再论证其对错）**:macOS 27 SwiftUI 缺陷上游不会及时修——
> D-6 AttributeGraph churn（upstream-only 立场 + FB 稿在案）+ sheet 族 D-1..D-5 缺陷史积累
> （D-1 Slider binding 热读 / D-4 sheet 闭包活读 / D-5 specifier 错配等，V2M 波 1 `54124c7e..bb16f8c4` 已修
> 但模式面在案，正本 = `phases/v2-maintenance/V2M-VALIDATION.md`）。本文评估**替代准备**:AppKit 或 GPUI,
> 回答「如果终有一天要换,换什么、怎么换、代价多少」。
> **方法**:仓内实测(find/wc/grep,HEAD 同源;数字见 §0)+ GPUI 2026-10 现状核查(公开渠道)
> + 既有裁决链引用(M7-1/FIX2/2026-10-18,锚点逐一给出)。**不落任何源码改动**。
> **日期**:2026-10-13。**去向**:charter 门呈用户(§6)。

---

## 0. Measured Inventory（侦察数据正本）

全部实测(2026-10-13,HEAD 在 `e9034d5e` 线上)。

### 0.1 分层规模

| 层 | 文件 | 行数 | 与 UI 栈的关系 |
|---|---|---|---|
| App/ | **198** | **71,657** | 替代对象(其中 UI/ 106 文件 34,479 行) |
| App …/UI/ | 106 | 34,479 | **SwiftUI 视图层 = 替代正面** |
| App …/State/ | 21 | 9,128 | @Observable 协调器——UI 形状耦合但**逻辑可存活** |
| App 其余(Library/Session/Settings/Export/MCP/AI/Yiyin/Catalog) | ~71 | ~28,050 | 协调器/服务/模型,少量 View;大部分可存活 |
| LightamerCore/ | 203 | 68,006 | **与 UI 无关,替换不动**(项目价值大头) |
| LightamerIOP/ | 99 | 33,844 | 同上 |
| Tests/(全部 bundle) | 427 | 156,371 | 3,967 测试方法(与裁定「A 已兑现 3967」对账一致) |
| Tests — LightamerTestsApp bundle | 103 | — | 936 测试;**仅 8/103 文件 import SwiftUI** |
| Tests — Core 侧六 bundle(IOP/IOPP/Layers/Library/Sessions/Export) | 338 | — | 3,031 测试,**零 UI 触碰** |

App UI/ 内部:Inspector/ 49 文件 10,555 行(逐 iop 面板族);Shell/ 23 文件 9,584 行
(WorkspaceHostView / EditorWorkspaceShellView / FilmstripView / DrtPanelView / FilmPanelView /
Nodes/ 3 文件 1,053 行等);Overlay/ 9 文件 3,372 行;顶层散视图(含 **LightamerApp.swift 2,904 行**
——scene + Commands + 菜单环燃料面集中地;ContentView 828 / SidebarView 1,003 /
SessionBrowserView 652 / SettingsView 126)。

### 0.2 SwiftUI API 面积(grep 计数,App target)

`.sheet(` 29 · `@State` 276 · `@Environment(` 152 · `@Observable` 73 处/54 文件 ·
`Button(` 281 · `Slider(` 215 · `keyboardShortcut` 57 · `Toggle(` 57 · `TextField(` 50 ·
`Menu {` 25 · `List` 16 · `LazyVGrid` 11 · `NavigationSplitView` 7 · `focusedSceneValue` 8 ·
`onGeometryChange` 4 · `.inspector(` 1。

### 0.3 已在岗的 AppKit 面(迁移的既有立足点)

- `EditorMTKView.swift` = **NSViewRepresentable 包 MTKView**(Metal 视口本就是 AppKit 原生件,
  AppKit 核架构下桥层直接退役,MTKView 变直挂子视图)。
- `PanelPresentation.swift`(L057 缝):`begin(withCompletionHandler:)` 非阻塞面板呈现缝,
  机检门 `grep -rn "\.runModal(" App/Sources` 零命中——**已经是 AppKit 形状的约定**。
- NSOpenPanel 27 处 / NSSavePanel 9 处 / NSWindow 13 处 / NSHostingView 1 处。
- `MenuCommandSet.swift`(86 行)——菜单 IA 已是**纯函数** `(gate, phase) → Set<MenuCommandID>`,
  与呈现层解耦(App 侧 LightamerApp CommandMenus 只消费它)——NSMenu 桥的现成数据源。
- 走查管线:screencapture / cliclick / System Events / AXManualAccessibility 成型
  (`research/XCODE27-SKILLS.md:23`;`.work/gui-acceptance/` 十余个 phase 的 MANIFEST 证据族)。

### 0.4 部署面

全部 target `deploymentTargets: .macOS("27.0")`(Project.swift;Lock-early,无历史版本包袱)。

---

## 1. Decision Matrix（正式决策矩阵）

三列 = **AppKit**( strangler 渐进)/ **GPUI**(Rust 全迁或 FFI 桥)/ **维持 SwiftUI**(基线现状)。

| 维度 | AppKit | GPUI | 维持 SwiftUI |
|---|---|---|---|
| **语言栈与项目地基相容性** | **满分**。Swift 原生,零 FFI;CIRAW RAW 9 / ColorSync / Vision / EDR 全部一等公民继续直用;Core/Pipe/Decode/IOP 101,850 行**零触碰** | **最差**。GPUI = Rust。两条路都痛:①UI 迁 Rust + Core 留 Swift = 跨 C ABI 的 FFI 桥罩住全部 Core 面(@Observable actor / async 序列过桥高税,Swift↔Rust 双语言 mental model);②Core 同迁 = **丢 RAW 9 地基**(Rust 无 Apple RAW 解码器,libraw 被项目约束明令排除,Neural Engine demosaic+denoise 归零)——**那是另一个项目** | 零成本,但 D-6 表型(编辑器 80-100% spin)持续,上游 ETA 不可控 |
| **EDR·ColorSync·Metal 互操作** | **满分**。三者全活在 UI 栈之下(MetalContext/CIContext/Core 侧);MTKView 直挂后少一层桥;`wantsExtendedDynamicRangeContent` 已在岗(08-4 T1) | **差**。GPUI 自带合成器,与 CAMetalLayer EDR 面互斥;HDR 视口四态(legacy/EDR-linear/DRT-SDR/DRT-HDR)的 colorspace 精细控制(itur_2100_PQ/HLG calibrated surfaces)要在 GPUI 合成器里重造,无先例可抄 | 现状即最优 |
| **AX 与走查管线存续** | **满分**。NSButton/NSSlider/NSMenu 等**出厂即 NSAccessibility**;现有走查配方(AXManualAccessibility + cliclick + System Events)零改动存续 | **差**。GPUI 不经 AppKit 控件,AX 靠 AccessKit 集成——Zed 侧 2025-10 才开始(PR #51097 + 后续逐元素补 ARIA 类属性),官方自认「a long project」;**现有整套 AX 走查管线可能失聪**,这是本项目质量门的支柱 | 在岗 |
| **测试资产迁移量** | **最小**。936 App 测试中仅 8 个文件 import SwiftUI——**~928 个协调器/模型/纯函数测试原地存活**;视图级测试(ToastFaceTests AX 断言、SheetEnvironmentInjectionTests 等)按面重写 | **最大**。Rust 侧测试体系另起炉灶;FFI 路线下 Swift 测试与 Rust 测试双套并存;Core 侧 3,031 测试在 FFI 路线下还要加桥接测试 | 零 |
| **solo dev 认知负荷** | **中**。AppKit 老而稳但啰嗦:声明式布局惯性要逆转,状态绑定手写(Combine/notification/withObservationTracking 桥 @Observable);学习曲线真实存在,但 NSMenu/NSWindow/NSPanel 等核心件 API 数十年冻结,资料沉积厚 | **高**。Rust 所有权模型 + GPUI entity/Context 范式 + FFI 边界三重新面;solo dev 同时维护 Swift Core 与 Rust UI 双栈 | 低(现状) |
| **生态风险** | **最低**。系统框架,Apple 维护,随 macOS 27.x 滚动修复;无第三方 bus factor | **高**。pre-1.0,breaking changes 频繁;2026 年 Zed 被报道收缩 GPUI 投入转向核心业务,社区分叉(GPUI-CE)出现——**单公司框架的存活风险已被现实演示**;macOS 独占项目用不上它的跨平台卖点 | Apple 官方路线,风险 = D-6 修复节奏不受我控 |
| **D-6 类缺陷暴露面** | **结构性消除**(对菜单环这一 D-6 环身份):无声明式重估图(AttributeGraph 不存在),NSMenu 更新是显式 `validateItems`/`update` 调用;churn 类「框架自持环」无对应机制。注:AppKit 自有老坑(resize/layout 时序、retain cycle),但**类别不同且可断点调试** | **未知**。GPUI 亦有自有 entity/invalidation 系统——无 AttributeGraph 但成熟度未经本类场景检验;Zed 的战场是文本编辑器,不是多节点图像管线视图树 | D-6 在场;遮挡/⌘H workaround 常态化(README 已落) |

### 1.1 结论(倾向明确)

**AppKit 是唯一可行方向,GPUI 维持出局。** 判定核不是「GPUI 好不好」——Zed 实证 120fps、
entity 系统确定性失效跟踪、Rust 内存安全都是真的(§2 公平列出)——而是**相容性一票否决**:
本项目价值大头(CIRAW RAW 9 解码 + ColorSync + Vision + 101,850 行 Swift Core/IOP + 3,031 Core 侧测试)
是 Swift 生态资产;GPUI 路线要么 FFI 桥税罩住全部 Core 面,要么弃 Swift 地基全迁 Rust——
弃 RAW 9 就是弃项目的 Core Value(「更快的解码与降噪」),**那是另一个项目,不是这个项目的 UI 栈替换**。
AppKit 路线下 Core 零触碰、928/936 App 测试原地存活、AX 走查管线零改动、EDR 面已在岗——
替代成本被压缩到真正该换的那 34,479 行视图层。

**维持 SwiftUI 仍是合法选项**(upstream-only + 遮挡 workaround 已常态化,M7-1 终局裁定),
本文是**替代准备**而非替代决定——最终 = charter 门用户裁(§6)。

---

## 2. GPUI Fair Evaluation（公平评估备存)

**Pros(全部属实,不回避)**:
- **Zed 生产实证**:大规模文档 120fps 渲染,同一框架支撑日常编辑器工作负载。
- **entity 系统的确定性失效跟踪**:retained + hybrid immediate 模式,更新路径显式可追——
  无 AttributeGraph 式黑箱重估图,本项目 D-6 这种「框架内部自持环不可断点」类缺陷
  在 GPUI 架构里没有对应机制(虽然它自有的 invalidation 系统成熟度未知)。
- **Rust 内存安全** + GPU 原生渲染设计(合成器内建,文本/矢量渲染质量高)。
- Apache-2.0 开源,可独立于 Zed 使用(crate 可得,社区分发 GPUI-CE 存在)。

**Cons(净判定的实际来源)**:
1. **语言栈税(决定性)**:见矩阵第一行。FFI 桥路线 = Core 全面过 C ABI
   (actor reentrancy / async 流 / @Observable 观察均无自然对应物);全迁路线 = 丢 RAW 9。
2. **AX 不成熟**:AccessKit 集成 2025-10 起步,官方定位 long-term project;
   本项目 AX 走查管线是 GUI 验收的支柱(M2-8-3 sheet 崩溃、M2-9 十项走查、D-6 探针全靠它),
   GPUI 下这条质量门直接失守。
3. **生态风险已现实化**:2026 年公开报道 Zed 收缩 GPUI 投入;框架未来系于单公司优先级
   或社区分叉的接续能力。pre-1.0 breaking changes 频繁——对 solo dev 是持续税。
4. **战场错位**:本项目性能战场在像素管线(Metal pixelpipe,已独立成立且不依赖 UI 栈),
   UI 绘制从来不是瓶颈;GPUI 的核心卖点(120fps 文本/矢量渲染)在照片编辑器 UI 面收益有限。
5. **macOS 独占项目用不到它的跨平台雄心**(Linux/Windows/mobile 支持是它的投资方向,与我无关)。

**净判定:出局——除非用户明确愿意放弃 Swift 地基重立项目**(若如此,应作为新项目立项讨论,
不在本项目 UI 栈替换的范畴内)。

---

## 3. Strangler Roadmap（AppKit strangler 渐进路线图,推荐形态)

形态 = **NSViewRepresentable 反向桥**:AppKit 为核(NSWindow/NSViewController/NSView 树),
SwiftUI 壳按面渐退(每面翻转时 SwiftUI 版本留在壳后作为回退单元)。与 strangler 反向桥经典形
一致之处在于**新栈包裹旧栈的呈现边界**,本项目已有的 `LibraryLegacyGate` env 注入门
(M2LIB-06 唯一 env 读点先例)与 M7-1 RESEARCH 的 `shell.reducedTree` flag 回切对照构想
是现成的门控惯例。

### 3.1 面-by-面替换序(churn 重灾优先)

| 序 | 面 | 内容(churn 锚点) | 资产迁移量 | 回退单元 |
|---|---|---|---|---|
| **F0** | **菜单/命令桥**(D-6 环身份所在:makeMainMenu↔updateMainMenu) | LightamerApp.swift 内 CommandMenus 段(~行 473 visibleMenuCommands + ~行 1800-2100 Menu 块)→ NSMenu 桥,数据源 = MenuCommandSet 纯函数原样消费;快捷键面(菜单子集 of 57 处 keyboardShortcut)逐条迁移 | 视图码 ~300 行 + MenuCommandSet 零改;App bundle 菜单 IA 测试 2 文件(WorkspaceRoutingTests / SettingsPagesTests 引 MenuCommandSet 面)微调 | NSMenu/Commands 双构建 runtime flag(先例 = LibraryLegacyGate env 门) |
| **F1** | **编辑器面**(churn 80-100% 重灾) | Shell/ WorkspaceHostView + EditorWorkspaceShellView 三段(filmstrip/viewport/toolRail)+ EditorAreaView/ScopePanelView/EDR/SoftProof + Inspector/ 49 面板 10,555 行 + Overlay/ 9 文件;DrtPanelView/FilmPanelView/ColorMatchPanelView 三孪生面板;EditorMTKView 桥退役(MTKView 直挂) | **xL**:~75 文件 / ~23,500 行视图码;LightamerSlider 等 11 个自绘控件换 NSView 形;State/ 协调器经观察适配器继续供数(9,128 行零迁移,只加 per-面 binding 胶水) | 每子波独立 flag;建议 Inspector 49 面板按 ~10 一组分子波,每组独立可回退 |
| **F2** | **图库面**(churn ~30%) | SessionBrowserView 652 + SidebarView 1,003 + FilterBarView 458 + CatalogBrowserView 382 + CullingView 277 + ContentView 828 + StatusBar | L:~8 文件 / ~4,600 行;NavigationSplitView 7 处中 5 处在此面 → NSSplitViewController | 面级 flag 独立回退 |
| **F3** | **设置/表单类**(或**永久混用**) | SettingsView 126 + ACA/偏好面板 + 各 dialog sheet(.sheet 29 处的表单子集) | S-M:表单类 NSForm/NSTableView 即可;**本面可不做**——churn 低、交互简单,SwiftUI 长驻混用无管理成本 | 不适用(混用态) |
| — | **State/ 协调器层** | 不是独立面:21 文件 9,128 行 @Observable 原地存活,各面翻转时补 AppKit 观察适配器(`withObservationTracking` → invalidate/refresh 的机械胶水,per-面 ~50-150 行) | M(摊入各面) | 随宿主面 |

### 3.2 混用期约定成本(双栈并存的常态管理)

- **状态桥**:@Observable 协调器被 AppKit 视图消费 = 显式观察胶水(每面一次性);SwiftUI 长驻面
  (F3)继续走 @Environment——两条消费路径并存,约定 = 「协调器不得感知宿主栈」(现在已如此)。
- **菜单面单一**:F0 完成后全 app 菜单单一 NSMenu;SwiftUI 长驻面(F3)的 context menu
  (Menu { 25 处多数是 context menu)允许留 SwiftUI,不与主菜单混权。
- **走查配方**:AppKit 控件的 AX 树路径变化(cliclick/AXManualAccessibility 寻址坐标),
  per-面翻转时走查配方同步更新——是持续成本不是一次性成本。
- **L057 缝零变化**:PanelPresentation 是 AppKit 缝,两栈通用。
- **测试**:混用期双栈并存 = App bundle 测试两套视图断言形态并存(SwiftUI AX 断言 +
  NSView 层级断言);~928 存活测试不受扰。

### 3.3 回滚单元原则

每面(或 F1 内每子波)独立 flag + 独立验收 + 独立可回退;翻转顺序内含依赖序
(F0 菜单先于一切——所有面共用;F1 不依赖 F2;F2/F3 相互独立)。
**任何一步翻完上游修复到时,就地停机保留已翻面**(已翻面功能等价,无需机械回退),
或按 flag 逐面回退——见 §5 双向对冲。

---

## 4. NSMenu Spike（从条件账拉正为 research 附属第一实验)

2026-10-18 裁决(`e9034d5e`)已把 NSMenu 外科替换挂条件账(触发 = macOS 27.1 落地仍未修
∧ 用户判定 churn 痛到值得动;「成则扩展不成一天收兵」)。建议**拉正**:它同时是
(a)AppKit 路第一块砖(F0 的 spike)与(b)D-6 直接缓解实验——双重身份使其在
上游等待期内也有独立价值,不必等触发条件齐备才动手(spike 是侦察不是迁移)。

### 4.1 Spike 规格草案

- **桥面**:LightamerApp.swift 的 CommandMenus 段换 NSMenu——构建期从
  `MenuCommandSet.visible(for:)` 纯函数生成菜单树(MenuCommandID → NSMenuItem 一对一),
  per-phase enablement 走 `NSMenuDelegate.menuNeedsUpdate`/`validateItems`
  (可见性≠可用的既有 IA 语义原样保留);快捷键 = MenuCommandID 映射表逐条
  `keyEquivalentModifierMask`;zh/en 标题走既有 xcstrings 键族。
- **双构建对测**:build A = HEAD(SwiftUI Commands)vs build B = NSMenu 桥。
  同一 D-6 探针协议(M7-1-HALT-REVIEW §2.2 配方):`caffeinate -dis` 包裹 + 裸直启 +
  System Events frontmost 门先行 + 1s 步 `ps %cpu` + `sample 6s`
  **符号总量口径**(§4 记录纪律:跨行求和,禁最大单支) +
  编辑器面 transcript `phase=editor` 机检断言(E 系教训)。三独立证据。
- **判定线(相对门,`e9034d5e` D-AR1-10 形)**:build B 编辑器面 spin 相对 build A
  差分 > 噪声带(三份独立证据 ≤1.9% 为带内)且功能 parity 全过 = PASS → 生产化为 F0,
  并以此决定 strangler 是否立项加速;差分 ≤ 带 = 环不随菜单桥消失(与 C1/C2 树形证伪
  一致的韧性结果) = FAIL,**一天封顶收兵**,NSMenu 条件账维持原触发条件。
- **功能 parity AC**:全部 MenuCommandID 项在场、快捷键全通、per-phase enablement 与
  MenuCommandSet 矩阵一致、zh/en 标题无裸键。
- **量级**:**<1 天**(构建半日 + 探针轮 3×双构建 + 报告);零 Core/IOP 触碰,零测试资产改写
  (App bundle 加 NSMenu parity 测试若 PASS 才随生产化批次入)。
- **诚实预告**:FIX2 D-FIX2-1 与 M7-1 终局均证明环骨架韧性(C1/C2 三独立复现均活;
  环 = 可见性门控 × 振幅随面重)——**无成功保证**,spike 的价值正是用一天把这条
  「菜单桥是否足以断环」的不确定性变成实测答案,无论结果都反哺 §3 路线的现实校准。

---

## 5. Risks & Sizing（风险与工期量级)

### 5.1 分面估算(S = 天级 / M = 周内 / L = 1-2 周 / xL = 多周)

| 项 | 档 | 依赖序 |
|---|---|---|
| F0 NSMenu spike | **S(<1 天)** | 无前置;可立即 |
| F0 生产化(菜单桥 + flag 门 + parity 测试) | **S-M** | spike PASS |
| F1 编辑器面(整面) | **xL** | F0;内部再分 ~5-6 子波(Shell 三段 → 三孪生面板 → Inspector 49 面 ×~10/组 → Overlay) |
| F2 图库面 | **L** | F0(独立于 F1) |
| F3 设置/表单(若做) | **S-M** | 任意时点 |
| State/ 观察适配器 | **M(摊入)** | 随各面 |
| 走查配方持续更新 | 每面 **S**(持续) | 随各面验收 |

全路线完成 ≈ **xL 总盘**(以当前面序),但**不必一次性立项**——F0+F1 子波节奏推进,
每子波独立 charter/验收门,与既有 C 档门控相容。

### 5.2 主要风险与对冲

1. **「迁移进行到一半上游修了」**——双向对冲的答案就是 §3.3 的**每面独立回退单元**:
   macOS 27.x 点版本修复到时(FB 案号在案 + 27.1 release notes 监测义务,
   `research/APPLE-FB-D6-DRAFT.md` + SHELL-04),已翻面**保留**(功能等价、无回归即不回退),
   未翻面停止翻转,strangler 就地冻结;若某面翻后出现新缺陷,该面 flag 单独回退。
   最坏情形 = 只完成了 F0(菜单桥),它本身仍是 D-6 环身份的直接实验产物,不白做。
2. **xL 面估错**:Inspector 49 面板同构度高(逐 iop 一面板,L304-L095 惯例形状统一),
   子波化后每组风险有界;第一组即建立**面板迁移模板**,后续组机械复制。
3. **混用期双栈缺陷面**:新 bug 类别(AppKit 时序/retain cycle)与 SwiftUI churn 类不同源,
   探针定罪范式(churn 先探针后动手,LESSONS 已沉淀)对 AppKit 类需补 sample/Instruments 形;
   记入迁移 charter 的 LESSONS 预算。
4. **solo dev 认知负荷峰值在 F1**:AppKit 布局惯性 + 观察胶水双新面;缓解 = 子波节奏 +
   每子波验收走查闭环(不积压未验证面)。
5. **走查管线回归风险**:AppKit AX 树结构与 SwiftUI 桥出树不同,现有 MANIFEST 配方
   per-面失效——已在 §3.2 计为持续成本,不是被遗漏的风险。

---

## 6. Relation to Timing（与时序的关系)

- **修复批 B/C 在跑,不受影响**:本文纯 research(doc-only,零源码),与 AR-02/AR-03
  机械批无文件交集;D-6 探针相对门(`e9034d5e`)继续是 B/C 批守门。
- **本产物走 charter 门呈用户**,三个裁决点:
  1. **栈终选**:AppKit 方向采纳与否(GPUI 出局是否盖棺,或保留「弃 Swift 地基 = 新项目」的口子);
  2. **是否立项**:立即立项 strangler(以 F0 spike 为第一实验)vs 维持 upstream-only 等待
     27.1 观测(FB 已提交,监测义务在 SHELL-04)vs 只先跑 spike 采数再定;
  3. **与 M8 FSIM 的先后**:M8 = M3-4 延续(FSIM 宽容度面深化),与 UI 栈替换零文件交集,
     先后纯排期问题——若并行,唯一共享资源是验收走查通道(gui-acceptance 配方),建议错峰。
- NSMenu spike(<1 天)在任何裁决下都是低 regret 动作:PASS = AppKit 路启动件 + D-6 实测缓解;
  FAIL = 条件账获得一条实测反证,「等上游」立场的证据更厚。

---

## 附:锚点清单(本文引用正本)

| 事实 | 锚点 |
|---|---|
| D-6 环身份/定罪 | `phases/fix2-defects/FIX2-01-DECISIONS.md` D-FIX2-1(makeMainMenu↔updateMainMenu 环;14298/14269 次 @self-only 重估;threshold 形持续条件) |
| D-6 终局行为模型 | `phases/m7-1-shell/M7-1-HALT-REVIEW.md`(可见性门控 × 振幅随面重:图库 ~30% / 编辑器 80-100% / legacy 0.1%;C1/C2 树形证伪;遮 0% / 置前 ≤1s 复燃) |
| 2026-10-18 裁决链 | commit `e9034d5e`(相对探针门双构建差分 ≤ 噪声带 1.9%;NSMenu 挂条件账;B/C 放行;`AUDIT-REPAIR-CONTEXT.md` 用户裁决补记节) |
| FB 稿 | `research/APPLE-FB-D6-DRAFT.md`(用户手动提交,案号槽在 REQUIREMENTS SHELL-04) |
| sheet 族 D-1..D-5 | `phases/v2-maintenance/V2M-VALIDATION.md`(波 1 `54124c7e..bb16f8c4` 全修;模式面在案) |
| L057 面板缝 | `App/Sources/Lightamer/UI/PanelPresentation.swift`;AGENTS.md「L057 面板呈现约定」节 |
| 菜单 IA 纯函数 | `App/Sources/Lightamer/UI/Shell/MenuCommandSet.swift`(86 行;M2-3-1 T5/KD-6) |
| Metal 视口桥 | `App/Sources/Lightamer/UI/EditorMTKView.swift`(NSViewRepresentable;08-4 T1 EDR 双 PSO) |
| 走查管线 | `research/XCODE27-SKILLS.md:23`;`.work/gui-acceptance/` 各 phase MANIFEST(local-only) |
| GPUI 现状(2026-10) | Apache-2.0 / pre-1.0 breaking changes;Zed 投入收缩报道与 GPUI-CE 社区分叉;AX = AccessKit 集成起步(Zed issue #41138 / PR #51097,官方「long project」定位)——公开渠道,引入时按当时快照复核 |

---

## 7. Strangler 校准终版（append,2026-10-19;F0 FAIL → F0' PASS → F0'-production chartered）

> 本文 §3/§4 的路线与 spike 规格草案已被两次 spike 实测校准。本节为终版口径,
> 原文不改保留作校准轨迹;执行正本 = `phases/f0prime-prod/RESEARCH.md`(charter
> `35a6c178`,量级 M)。

### 7.1 双 spike 结论链

1. **F0(NSMenu 桥)FAIL**(`spike/nsmenu-f0` `dfde03bc`;正本
   `phases/nsmenu-spike/SPIKE.md`):三臂对测 B vs A = −0.5pp 带内——菜单桥不断环;
   且 **macOS 27 SwiftUI 绕过 `NSApp.mainMenu`**(属性级 setter 不夺屏,像素+AX 双证)
   ——§4.1 的「菜单桥生产化」路线在其原形上结构性失效,§3.1 的 F0 行(菜单/命令桥为
   第一砖)**冻结并反转为壳交接前置**。
2. **F0'(壳交接)双门 PASS**(`spike/f0prime-shell`;正本
   `phases/nsmenu-spike/F0PRIME.md`):「SwiftUI 菜单栏宿主如何让位」的答案 =
   **生命周期整体移除**——手动 NSApplication + delegate 托管 NSWindow,SwiftUI 降为
   NSHostingView 子内容;此后 NSApp.mainMenu 恢复权威(自建树像素+AX 上屏、⌘M 原生
   selector 生效),SwiftUI 面全存活(23 对象 env/四 sheet/面板缝/缩略图/MCP host)。
3. **D-6 终局定性(churn 载体第三、第四次独立复现)**:同一编辑器面同一 MTKView,
   生命周期在场 = 96.0% 恒烧、离场 = 0.0% 事件驱动静默——**churn 振幅载体是 SwiftUI
   scene 生命周期自身的 re-eval 机器**(F0 排除菜单,F0' 排除面内容,双重排除收口)。
   §3 的 F1「编辑器面 AppKit 化」对 churn 目标**无必要**——缓解杠杆在壳层。

### 7.2 F1-F3 park 裁决 + F0'-production chartered

- **F0 改形 = 壳交接**(非菜单桥),**F0'-production 已 chartered**(2026-10-18/19,
  commit `35a6c178`):spike 形推生产(manual @main + NSMenuBridge 生产化 + 三次级窗
  AppKit 化),硬性前置 = 未追踪 @Observable 读审计(churn 机器曾「顺手」re-eval 全树,
  菜单缩放重绘缺口即实例——churn 首次被发现具有功能性,不止纯开销)。
- **F1(编辑器面 xL)/F2(图库面 L)/F3(设置表单 S-M)park**:churn 收益已由壳交接一次
  兑现,面迁移降级为可选后置(收益 = 菜单/窗口 chrome 归一,非 churn)——重启条件 =
  用户判定 chrome 归一值得 xL 投入,或上游 macOS 27.x 修复不及预期且面级缺陷积累到
  痛点。§3.1 的面序表与 §5.1 的分档估算保留作重启时的规划基线(数字需按当时 HEAD
  复测——本节数字测于 2026-10-13)。
- **条件账(NSMenu 外科替换)关闭**:其身份已被壳交接吞并(SPIKE §4 的「等上游」立场
  不再成立——不是等上游修,而是壳交接绕开上游缺陷)。
- **硬性前置的实测规模**(RESEARCH §3):审计点位 ~50,真实缺口 4(zoom 签名族/export
  note 时机/columnVisibility 提升+三窗/toolbar 视觉差异登记)——M 批预算成立。
- **验收正门换形**:D-6 相对门(§4.1 双构建差分)退役,**绝对门 <10% 编辑器静置 %cpu**
  复活(B 臂基线 0.0%;L082 哨兵四门机检)。
