# F0P-01 DECISIONS — plan P1 执行裁定记录

> 正本性质：plan F0P-01（壳交接翻转 P1）执行期裁定 + 偏差申报。规格正本 =
> `F0P-01-PLAN.md`；裁决正本 = `CONTEXT.md`（D-F0P-1..10）。本文只记录
> plan 授权范围内的「落 DECISIONS」点与执行偏差，不重开已定裁决。

## D-F0P-01-1 ShellGraph 实例单源形（review M2，T4 先行步，已定死）

**裁定 = (a) `ShellGraph.shared` 共享单例**（三选一：shared 单例 / env
optional 回落 / init 参数）。

- **理由**：
  - (c) init 参数：须在翻转前改 App struct 的 Window 内容构造点传参——App
    struct 主体（:252-2244）本 plan 冻结（T6 diff 上限 = entry 尾 +
    WindowCapture 可见性 + ContentView :551 缝），(c) 违反冻结面，直接排除。
  - (b) env optional：pre-flip nil 回落须保留本地 @State 孪生（双真相源）+
    pre/post 两套代码路径（发散风险），恰是 plan 警示的双实例静默失效模式
    的变体，排除。
  - (a) 进程级唯一实例：face 装配段、ContentView binding 桥、菜单闭包三方
    消费同一对象——「菜单写 A、视图读 B」静默失效结构性排除；零 seam 改动；
    pre-flip 在 churn 在场下 binding 即活（body 对 `ShellGraph.shared.
    columnVisibility` 的 tracked read 立即生效）；先例 = `LutLibraryStore.
    shared`（M2-5 检查器 m6 形）。
- **对先例的简化申报**：不做 `NSLock` + `replaceShared` 形（M2-5 m6 全形）
  ——LutLibraryStore 的锁/换实例面服务于 Settings 切根热替换；ShellGraph 无
  热替换需求，裸 `static let shared = ShellGraph()` 足够。
- **接线含义（T4/T6 以此为准）**：T4 ContentView binding 桥 get/set 直指
  `ShellGraph.shared`；T6 `LightamerShellController` 不再自持 graph 实例，
  face 的 `graph`/`graphB` 属性 = `ShellGraph.shared` / `Bindable(ShellGraph.
  shared)`；NSMenuBridge Deps 的 showSidebar/showInspector 闭包写
  `ShellGraph.shared.columnVisibility`。

## D-F0P-01-2 NSMenuBridge 生产形三点（T3 落形记录）

1. **export enabler 读集终形 = 双轨（19 reads）→ T7 实测修正为恒 enabled
   （17 reads）**：T3 落形按 plan 规格 = review m1 的 18 字段全读集 +
   `exportPageActive` 第 19 读、enabler = note ∨ exportPageActive；T7
   A-arm AX 实测（D-F0P-01-5.2）证 plan 形与 pre-flip 真相冲突，修正 =
   enabler 恒 enabled、两 export presence 读退役（终形 17 reads）。终值以
   D-F0P-01-5 为准（本条留痕 = 规格演变轨迹）。
2. **menu_open_session（⇧⌘O）= 新增 `openSessionPicker: () -> Void` 闭包**
   （弃「复用 openSession 零参变体」）——语义分明（picker 缝 vs 直开），
   face 侧接线 = `FileOpener.openSessionFolder` picker 形（产线正本
   LightamerApp.swift:1831-1838 同构）；recent-sessions 子菜单行保持
   `openSession(url)` 直开路由不变。grep 机检：`recentSessions.first` 在
   NSMenuBridge.swift 零命中（含注释——注释亦避用该字面串）。
3. **Deps 新增 `settings: () -> Void`**（spike 无此闭包，Settings 项原为
   私有 selector 内联——D-F0P-1 真窗控制器缝），T6 接线 =
   `SettingsWindowController.showWindow(nil)`。

## D-F0P-01-3 AX identifier 迁移集（review m5，T3 落形）

NSMenuItem AX identifier 补齐（`setAccessibilityIdentifier(_:)` 方法形——
探针实测 `accessibilityIdentifier` 属性赋值形不可用（method 非 property），
`swiftc -typecheck` 亲证）：menu.workspace.enterEditor / backToLibrary /
menu.library.search / menu.edit.copyAdjustments / menu.view.stacks.
expandAll / collapseAll / menu.image.aiUpscale（`AIEntryPointCoordinator.
Marker.menuUpscale` 常量引用）/ menu.image.aiDenoise（同）。SwiftUI 侧尚有
menu.preset_manager / menu.mcp_launcher / menu.show_film_panel 三 identifier
未随迁（plan 授权清单外）——如 T7 走查面需要 AX 断言再补，缺项在此申报不
静默。

## D-F0P-01-4 Toolbar 差异登记（T5，D-F0P-2 接受+登记）

- **差异**：窗级 `.windowToolbarStyle(.unified)`（原 HEAD
  `LightamerApp.swift:1798`）是 Scene 生命周期属性，壳交接后缺席——toolbar
  内容在 hosting 面内照常渲染（三 toolbar 组功能态 tracked 读全活，
  F0PRIME §1.3 截图在案），但窗 title 区无 unified 附着形态。
- **裁定**：接受 + 登记，不重造 NSToolbar（OQ-F0P-2 全按推荐，CONTEXT
  D-F0P-2）；churn 收益与 toolbar 形态无关；NSToolbar delegate 重造 =
  后置立项候选。README Known Issues 补行 = P3 T4 范围。
- **登记落点申报 (deviation)**：走查卷 `.work/gui-acceptance/f0prime-p1/
  MANIFEST.md` 已建（T5 配方 + 本差异行）；该目录整域 `.gitignore`（仓库
  政策 line 79，历来 gui-acceptance 证据卷全部 local-only 不入库）——plan
  files_modified 把 MANIFEST 列为 commit 文件与仓库 ignore 政策冲突，故本
  DECISIONS 文件承载 tracked 侧登记正本，MANIFEST 为 local 证据卷（路径随
  orchestrator 收尾指令用 f0prime-p1/，plan 原文 f0prime-prod/，两者并注）。

## D-F0P-01-5 ⌘W 双面实测记录 + export 使能实测修正（T6 action 6 / D-F0P-3）

实测方法：A/B 二进制（`/tmp/f0p1-dd-{A,B}`，独立 DerivedData）plain 启动
后 System Events AX dump 菜单栏 + File 菜单（证据 =
`phases/f0prime-prod/probe/logs/ax-menu/{A,B}/`）。

1. **⌘W 双面语义 = 1:1 已对齐，零改**：pre-flip A 臂 File 菜单 AX 全量 16
   项（无 SwiftUI 默认 Close Window 项）——library face 唯一 ⌘W 项 =
   返回图库（disabled）；⌘W 在 library face = 无动作（无 Close 回落）。
   post-flip B 臂 File 菜单同构 16 项同键同修饰（返回图库 ⌘W disabled 同）
   ——两 face 语义逐点一致：editor face ⌘W = closeEditor（item enabled）、
   library face ⌘W = no-op。**不补 Close 项、不创新语义**（plan 风险节
   「按 1:1 对齐原则修 Deps」的行使结论 = 零改）。
2. **export 使能实测修正 (deviation，晨审可推翻)**：plan T3/B17/B18 规格
   （enabler = note ∨ exportPageActive）与实测 pre-flip 真相冲突——A 臂
   dump 显示 导出… **launch 即 enabled=true**（两 face 都无条件发布
   focused key；值本身是 action 载荷非使能信号）。plan 形在 launch 态
   disabled = 主项 parity 破坏 + T7 走查面 6 的 ⇧⌘E 菜单路由必挂。修正 =
   enabler **恒 enabled**（`{ true }`）；note 双态（B17）与 page 直读
   （B18）转为 **action 路由**信号（壳 export 闭包的 gate fork），使能面
   不再消费。观察适配器读集随之 19→17（16 观察字段 + metadata note box；
   两 export presence 读退役）；ContentView 的 onChange note 写腿保留
   （P2/P3 修剪面）。**依据 = 「壳侧唯一义务是 parity」+ plan 风险节授权
   （实测不一致 → 按 1:1 对齐原则修 Deps）**。
3. **AX 查询 stale 注记（非缺陷）**：passive AX dump 不触发
   menuNeedsUpdate——workspace 条件项（搜索图库/进出编辑器/AI/stacks）在
   dump 中呈注册期初值；用户真实打开菜单时 menuNeedsUpdate → refreshAll
   刷新（正确面）。B dump 的 搜索图库 enabled=false 即此 artifacts。
4. **系统组标题 zh/en 差异（登记不修）**：A 臂（SwiftUI）系统组 =
   文件/编辑/窗口/帮助（系统本地化）+ 双 显示 菜单；B 臂（桥）= File/
   Edit/Window/Help（桥内字面量）。F0PRIME 门① 记录的 B 臂栏形在案；
   zh 栏自定义菜单（显示/标记/图像）两侧一致。P2 走查面 16（双语像素
   对照）复核面；若晨审判定须 parity，桥侧系统组标题改走系统本地化串 =
   后置微任务。

## 偏差申报（行内 (deviation) 标记累计）

- （暂无——T1/T2/T3 零偏差：T1 hunk byte-identity；T2 参数命名
  `viewportSignature` = plan 示例名；T3 三改形点全按 plan 落地。）

## T6/T7 待落节（执行至此回填）

- LightamerShell* 终名终账 / Deps 接线终形 / ⌘W 双面实测记录 / toolbar 缝
  接线形（graph 请求字段 vs 闭包参数二选一）/ 探针三轮数据 / 各偏差。
