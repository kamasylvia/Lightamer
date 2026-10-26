# F0' Shell-Spike（lifecycle/shell 交接）— F0PRIME.md

> **性质**：NSMenu F0 spike FAIL（2026-10-19）的修订实验——回答 F0 证伪暴露的迁移前提问题
> 「SwiftUI 菜单栏宿主如何让位」。worktree `../Lightamer-f0prime-shell`，分支
> `spike/f0prime-shell`（commit `a35ad151` probe-stay hunk / `c9a91562` 壳交接 /
> `d8d1380a` 分发 trace 诊断；主 tip `34364bf8`）。对测窗 2026-10-19 05:14–05:41。
>
> **结论头：双门 PASS（改进向），附一条机制级新发现（churn 机器曾承担未追踪消费者的
> 功能性负载）。**
>
> - **门① 菜单权威 ✓**——NSApplicationDelegate 托管 NSWindow（SwiftUI 降级为
>   NSHostingView 子内容、无任何 App/Scene 生命周期）下，自建 NSMenu **像素 + AX 双证
>   上屏**：菜单栏 = ` Lightamer | File | Edit | 显示 | 标记 | 图像 | Window | Help`
>   （F0 的 SwiftUI 骨架 `Lightamer|显示|窗口|帮助` 消失）；⌘M 等 AppKit 原生 selector
>   生效；AXPress → handleMenu → Deps 闭包全链 trace 落地。
> - **门② churn ✓（−96.0pp，判据线 1.9pp）**——编辑器静置面 A 中位 **96.0%**（96.0 /
>   97.1 / 95.7）vs B 中位 **0.0%**（0.0 / 0.0 / 0.0）。L082 哨兵四道门全过：9/9 轮
>   frontmost=true；3/3 B 轮窗内截图可见（编辑器面完整渲染）；sample 栈主线程
>   4643/4643 样本泊在 `mach_msg2_trap`（事件循环等待，全进程 4 线程全闲）；
>   churn 符号族（UpdateStack/sizeThatFits/beginTransaction）B 三轮全零 vs A 50-66/654-770。
> - **门③ SwiftUI 面存活 ✓**——probe 全链（建项目/导入/行/编辑器/解码渲染/stay）、
>   图库往返（缩略图真渲染 + EXIF 分组 inspector）、工具轨 toggle（纯 SwiftUI 观察路径）、
>   色温滑杆拖拽（pipe 重渲染 → 视口像素 255→206）、New Project 保存面板呈现、
>   welcome/import/transfer sheet 装配、MCP host 装配（wiring 全跑）——hosting 桥下全部存活。
>
> **对 strangler 路线的最终校准（详见 §5）**：F0 的冻结条件解除——「SwiftUI 菜单栏宿主
> 让位」有答案且工程可行（让位 = 壳整体交接，不是菜单桥）；且 **D-6 的 96% churn 是
> 生命周期自身的机器**，壳交接一次消除，无需 AppKit 化任何编辑器面。代价面新增一条
> 硬性前置：未追踪 @Observable 读审计（§4.3，菜单缩放重绘缺口即其实例）。

---

## §1 实验设计

### 1.1 两臂（F0 的三臂收敛为两臂——本实验无 flag，两臂是不同二进制）

| 臂 | 构建 | 内容 | 身份 strings 校验 |
|---|---|---|---|
| **A** | commit `a35ad151`（= 主 tip `34364bf8` + 仅 probe-stay hunk） | HEAD 现行（SwiftUI App/Scene 生命周期全族） | 有 `staying alive for measurement`、无 `F0PrimeShell`/`NSMenuBridgeController` |
| **B** | commit `c9a91562`（壳交接） | `@main` 改 `F0PrimeShellMain.run()`：手动 `NSApplication`（regular policy）+ NSApplicationDelegate 托管 NSWindow（1440×900）+ `NSHostingView(rootView: F0PrimeShellFace)` + 自建 NSMenu（`NSMenuBridgeController` 树，F0 桥去 flag 直装） | 三者全有；stay marker 亦有（hunk 同在分支） |

- `d8d1380a`（handleMenu stderr trace）在**测量完成后**才提交，仅冒烟轮使用；A/B 对测二进制
  分别构建自 `a35ad151` / `c9a91562`（独立 DerivedData `/tmp/f0prime-dd-{A,B}`，Tuist glob
  纳新文件，`tuist generate` 后 `xcodebuild` 直连——env 剥代理变量，SPM 解析坑规避）。
- **移植形**：App struct 的 wiring `.task` 体（~1088 行）+ helpers（panel/metadata/probe/
  copy-paste/sidecar ~660 行）+ Window 内容闭包（env 链 23 对象 + 三 `.task` + 四 `.sheet` +
  onChange/overlay/alert）**逐字移植**进 `F0PrimeShellFace`——一个 View **struct**、同名属性
  （值语义保持所有抽离闭包的隐式 self 捕获形与生产一致；机械 perl 变换仅两族）。
- **值态迁移（§4.4）**：六个值型 @State（libraryImportRequest/Choice、libraryWelcomePresented、
  pastePartialRequested、adjustmentTransferPresented、lastLaunchWasUnclean）+ 三个 per-session
  重建 optional（thumbnailProvider/catalogThumbnailRouter/batchSidecarWriter）→
  `F0PrimeShellGraph`（@Observable box）——App struct 的 @State 存储不跨 struct copy 共享，
  菜单闭包与 delegate 在宿主视图树**外**写值必须走类实例观察。
- **AppDelegate 组合**：生产 `AppDelegate` 是 final → `F0PrimeShellDelegate` 组合转发
  （open Apple Events + applicationWillTerminate 同步 flush 原语义）。
- 菜单树复用 F0 `NSMenuBridge.swift`（去 `NSMenuBridge.isEnabled` flag——整个构建即实验臂），
  Deps 闭包由 face 装配；export 项改走 `inspectorState.openExportPage()`（M2 工作区自己的
  focusedSceneValue 发布点同一 seam）；presetManager/mcpLauncher/showSidebar/showInspector
  四项 stub（openWindow 无 scene、列可见性是 ContentView 本地 @State——spike 不求全）。

### 1.2 协议（D-AR1-10 F-8 + L082，与 F0 逐字同配方）

`run-one-f0prime.sh` = F0 `run-one.sh` 仅改日志目录；`-la_editor_probe <fixtures>`
（2 DNG link 导入）+ `-la_probe_stay`；probe stderr 标记（`rendered=yes` + `staying alive`）
= phase=editor 机检（9/9 轮绿）；settle 60s（盖 LUT 预热 ~50s）→ System Events
`frontmost` 先行 + 复验 → 截图 → 30s 窗 6 采样 @6s 中位（`ps -o %cpu`）→ `sample 6s`
符号总量（跨行求和）→ 杀自启 pid。三轮交错 A→B ×3（`run-driver-f0prime.sh`）。

### 1.3 偏差申报

- A 臂非纯 HEAD：+probe-stay hunk（DEBUG 探针尾 3 行，F0 同款，测量基建）。
- B 臂 face 与 A 的可见差异（如实申报）：窗口级 unified toolbar 样式缺席（`.toolbar`
  内容在 hosting 下仍渲染——截图在案——但无 title-bar 附着形态）；Settings/preset-manager/
  mcp-launcher 三个次级 window scene 未移植（menu 对应项 stub）。
- 冒烟轮与测量轮共用同一 B 二进制（trace commit 后的二进制仅多 stderr 日志行）。

## §2 对测数据

| 轮 | A %cpu 中位 | B %cpu 中位 |
|---|---|---|
| r1 | 96.0 | 0.0 |
| r2 | 97.1 | 0.0 |
| r3 | 95.7 | 0.0 |
| **中位** | **96.0** | **0.0** |

- **B vs A = −96.0pp**——改进判据线（>1.9pp）的 50 倍，量级差而非带内抖动。
- 9/9 轮 `editor-face=confirmed` + `frontmost=true` + VERDICT=OK。
- 正本 = `f0prime-logs/<臂>-<轮>/{meta,cpu,symbols}.txt + sample.txt + screen.png`。

### 2.1 栈旁证（符号总量，前缀感知求和）

| 量 | A (r1/r2/r3) | B (r1/r2/r3) |
|---|---|---|
| makeMainMenu / updateMainMenu / appGraphDidChange | 0/0/0 | 0/0/0 |
| UpdateStack | 50 / 66 / 57 | 0 / 0 / 0 |
| sizeThatFits | 654 / 763 / 770 | 0 / 0 / 0 |
| beginTransaction | 0 / 0 / 0 | 0 / 0 / 0 |
| prependValue | 0 / 21 / 23 | 0 / 0 / 0 |

- A 与 F0 的 A 臂同族（UpdateStack/sizeThatFits = ViewGraph churn 机器）。
- **B 的 sample 栈**（B-r1 正本）：主线程 4643/4643 样本泊在
  `start → main → F0PrimeShellMain.run → NSApplication.run → mach_msg2_trap`
  ——事件循环等待；全进程 4 线程全闲；physical footprint 3.2G（面已加载）。
  **0% 是真静默（事件驱动），不是遮挡伪象也不是僵死**（L082 哨兵四门验证在案）。

## §3 门③ 冒烟记录（B 臂，trace 版实例）

| 项 | 结果 | 证据 |
|---|---|---|
| probe 全链 | ✓ 建项目/导入 2 行/编辑器开/解码 rendered=yes×2/stay | `f0prime-logs/smoke-dispatch-trace.log` 尾 |
| 菜单分发（AXPress） | ✓ 5 动作全 `handleMenu title=… actions=true`（无 BLOCKED） | 同上 |
| AppKit 原生 selector | ✓ ⌘M 最小化（AXMinimized true） | 走查记录 |
| 图库往返（菜单驱动相位路由） | ✓ 返回图库 = 网格 + **真缩略图** + EXIF 分组 inspector；进入编辑器 = 面恢复 | `nav-lib.png` / `nav-editor.png` |
| 纯 SwiftUI 观察路径 | ✓ 工具轨 toggle 全窗布局变化（diff bbox 跨窗） | 走查记录 |
| 面板滑杆（色温拖拽，cliclick 合成） | ✓ 视口中心像素 255→206（白平衡重渲染落地）+ 滑杆拇指位移 | `smoke-pre/post-drag.png` |
| 保存面板（L057 begin 缝） | ✓ New Project… → `New Project, Lightamer` 窗出现 | 走查记录 |
| 编辑器菜单缩放（实际大小/适配屏幕） | **✗ 分发✓ 闭包✓ 状态变异✓ 但视口零重绘**——见 §4.3 | 三次点击 diff 仅菜单栏区 |

渲染对照：B 臂视口的 fixture Poster 化渲染与 F0 留档像素一致（同 fixtures 同 probe 终态，
臂无关，非壳交接回归）。

## §4 机制发现（净知识增益）

### 4.1 「让位」的答案 = 壳整体交接（F0 冻结条件解除）

macOS 27 SwiftUI 对菜单栏的所有权绑定在 **App struct/Scene 生命周期**上（F0 证伪了
属性级 `NSApp.mainMenu` 夺屏）。F0' 证明：生命周期整体移除（手动 NSApplication +
delegate 托管 NSWindow，SwiftUI 降为 NSHostingView 子内容）后，**NSApp.mainMenu 恢复
权威**——自建树上屏、原生 selector 工作、无 SwiftUI 反夺屏（三轮截图 + AX 双证）。
**strangler 路线的 F0 前置项从「不可能/等上游」翻转为「有答案、工程可行」。**

### 4.2 D-6 的 96% churn 是生命周期自身的机器

同一编辑器面、同一 MTKView（isPaused 按需重绘，两臂同代码）、同一操作点：SwiftUI
生命周期在场 = 96% 恒烧（ViewGraph re-eval/layout）；生命周期离场 = 0% 事件驱动静默。
**churn 振幅的载体不是任何面内容（F0 已排除菜单；本次排除「面」本身），而是
SwiftUI scene 生命周期的常驻 re-eval 机器。** 对 D-6 的含义：缓解杠杆在壳层，
AppKit 化编辑器面对 churn 无必要（B 臂面仍是 SwiftUI）。

### 4.3 churn 机器曾承担功能性负载：未追踪读缺口暴露（strangler 硬性前置）

壳静默后暴露一个真实缺口：**菜单缩放（实际大小/适配屏幕）不再重绘视口**。
链路解剖：`ViewportState` 变异 ✓（无守卫拦截，zoomLocked 仅 false 赋值）；分发 ✓
（handleMenu trace）；变异→重绘的桥 = `EditorMTKView.updateNSView` 的 zoom 签名
push-once——但 `updateNSView` 是**非追踪上下文**，编辑器面 body 对
`viewportState.zoom` 无任何 tracked read（EditorAreaView 只读 displayTexture）。
SwiftUI 因此从不 re-eval 该 representable → setNeedsDisplay 永不武装。
**生产（A 臂）为何工作：96% 常驻 churn 机器在持续 re-eval 全树，"顺手"替所有未追踪
消费者跑 updateNSView。** 手势路径不受影响（coordinator 自持 view 引用直接武装重绘）。
推断（未在生产验证）：该缺口在生产中大概率同样存在，只是被 churn 掩盖——churn 首次
被发现具有**功能性**（不止是纯开销）。
**对 strangler：任何「静默化壳层」的落地必须先完成未追踪 @Observable 读审计**
（NSViewRepresentable.updateNSView 族为主嫌），逐处补 tracked read 或显式 redraw seam。

### 4.4 值型 @State 在壳交接下的不可保留性（移植约束，已解）

App struct 的值型 @State 存储不跨 struct copy 共享；NSHostingView 挂载 + 树外写者
（菜单闭包/delegate）的形态下必须迁 @Observable box（本 spike 的
`F0PrimeShellGraph` 形，9 字段一次到位）。per-session 重建 optional 同理需要 body
重读点（本 spike 用 root face body 读 box → ContentView 重建）。

### 4.5 hosting 桥兼容面清单（冒烟实证）

存活：23 对象 env 链、@Observable 三级读、Bindings（Bindable box）、四 sheet 装配、
面板 begin 缝（NSSavePanel 呈现）、缩略图管线（真图渲染）、EXIF/元数据 inspector、
EditorProbe、MCP host 装配、AppDelegate open/terminate 转发。
已知差异：window 级 toolbar 样式、三处次级 window scene、菜单缩放重绘（§4.3）。

## §5 strangler 路线最终校准

1. **F0 解冻，且反转为第一砖候选**：壳交接后菜单/快捷键/启用态全 AppKit 化无障碍
   （本 spike 的 NSMenuBridge 树即现成起点）。AppKit 路线不再需要「从 F1 编辑器面
   绕开菜单」的绕行。
2. **D-6 主收益在壳层**：96%→0% 由壳交接达成。若 churn 痛感成立，优先立项「壳交接」
   而非「面重写」；面迁移降级为可选后置（收益 = 菜单/窗口 chrome 归一，非 churn）。
3. **壳交接已验证可行且便宜**：一日 spike 完成全状态图移植（~2300 行，其中 ~1750 行
   为逐字机械搬运），无架构层阻力；三处次级 window scene（openWindow seam）是最大
   未移植面，需 AppKit 窗管理器立项。
4. **前置新增（硬性）**：§4.3 未追踪读审计——churn 机器静默前完成，否则壳交接会
   静默破坏依赖 churn 的功能（缩放重绘即实例）。
5. **保留意见**：B 臂 0% 是新操作点——交互时延/连续手势流畅度/长会话行为未走查；
   smoke 覆盖为 spike 级（无导出流/undo 环/MCP 流量/多窗）。F1 若立项，验收面
   应含「静默壳下的全交互走查」。

## §6 处置

- 分支 `spike/f0prime-shell` 保留（`a35ad151` / `c9a91562` / `d8d1380a`）；worktree
  `../Lightamer-f0prime-shell` 保留（复测可直接构建）；**main 零触碰**。
- patch 归档：本目录 `0001..0003-*.patch` + `f0prime-full.stat`。
- 测量/驱动脚本：`run-one-f0prime.sh` / `run-driver-f0prime.sh`（本目录）。
- 二进制（即弃域）：`/tmp/f0prime-dd-{A,B}`（DerivedData 与 .app 均在，可复跑）。
- defaults 还原：`library.ai.labelingMode=never` 原值保持（driver 记录
  `f0prime-logs/defaults-state.txt`）；无新增持久键（trace 日志走 stderr）。
- 冒烟实例已清杀（`ps` 零 Lightamer 残留）。

## §7 证据文件清单

- `f0prime-logs/<臂>-<轮>/`：meta/cpu/symbols/sample/stderr + 每轮 screen.png（B 轮三张
  均为「自建菜单栏 + 编辑器面」像素正本）。
- `f0prime-logs/smoke-b-menubar.png`：门① 像素正本（菜单栏 8 顶项 + AX 文本见 §3）。
- `f0prime-logs/nav-lib.png` / `nav-editor.png`：图库往返正本（缩略图/EXIF inspector）。
- `f0prime-logs/smoke-{pre,post}-drag.png`：滑杆重渲染 diff 对（视口 255→206）。
- `f0prime-logs/smoke-dispatch-trace.log`：handleMenu 分发 trace（5 动作全绿）。
- `f0prime-logs/driver.txt` / `driver-stdout.log` / `defaults-state.txt`：驱动留痕。
- 对照正本：`logs/bridge-ownership-screen.png`（F0 的 SwiftUI 骨架菜单栏 + 同 fixtures
  渲染对照）。
