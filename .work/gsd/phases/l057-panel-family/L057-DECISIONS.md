# L057 面板族加固 — DECISIONS

> fix(l057) 批，2026-10-08。范围 = M3-1-02-ACCEPTANCE §三全集 + 本批两处勘误。
> 判别式先行（本文件 D1-D3），代码修复按判别式取模式（D4-D6）。
>
> **⚠️ D1R 机制修正（本批走查期内落盘，读 D1 时以本节为准）**：本批新证
> `.ips Lightamer-2026-10-08-140155.ips`（副本在 fix-batch/）表明 L057 家族的
> 归因需二分——见 D8。三份在案 .ips（085205 / 0937 / 140155）的 exception 全部是
> **主线程栈边界故障**（stack guard：'Thread stack size exceeded due to excessive
> recursion' / 'Could not determine thread index for stack guard region'，fault
> 地址均在主线程栈区 0x16d…），**不是可证的堆过度释放**；栈顶的
> `__swift_closure_destructor` → `_swift_release_dealloc` 链是触 guard 时恰在执行
> 的代码，不构成悬垂闭包的直接证据。且 140155 实例**全程零面板**（打开项目 →
> 返回图库 → AX 树遍历，无任何面板动作）仍以同签名崩——**面板取消不是全部实例
> 的必要条件；共同因子是 AX 自动化压力**（AXManualAccessibility + 深度 AX 树遍历 +
> 合成事件；三个 detonation 面 = 菜单 AX populate(`menuNeedsUpdate`)、hover
> hitTest(`ButtonResponder.updateValue`)、layout 期 accessibility graph 更新
> (`AccessibilityViewGraph.needsUpdate` → `AccessibilityNode.updateAttachment`)）。
> 因此：D1 的「嵌套 modal 撕闭包」假说降级为**未经证实的机制假说之一**；
> D2 的判别式作为工程防线仍然成立（嵌套 modal 是 Apple 文档明示的禁忌形态，
> begin 缝是正确卫生，Phase A/⌘O/Export 页 ×5×3 实测零崩）；家族的完整根修
> 归 L057-B 专项（D8）。

## D1 根因（两份 .ips 亲读 + F-1 81d7107 综合）

`NSOpenPanel/NSSavePanel.runModal()` 在 SwiftUI 动作 callout（菜单命令 / Button action /
contextMenu 项 / sheet 内容按钮）的调用栈内启动**嵌套 modal session**（调用帧未返回）。
嵌套 session 期间 run loop 以 tracking/modal 模式重入，SwiftUI 图被重入驱动；重入更新 pass
对 Button / menu-item 的 action closure 上下文做 assignWithTake/destroy 拆装，而悬着的外层
帧 / 上一轮 populate 仍引用同一 context → 双重所有权 → 悬垂引用在**随后任意一次** update
命中 → `_swift_release_dealloc` 过度释放 SIGSEGV。

两份 .ips 证明**崩点 = 悬垂引用的下一次使用点，可以远离触发点且栈上无面板代码**：

| .ips | 触发面 | 崩点栈顶 |
|---|---|---|
| `Lightamer-2026-10-08-085205.ips`（New Project，菜单命令 **Task 包裹**路 + Esc 取消） | AX `_openForInspection` 驱动菜单重灌 | `AppKitMainMenuItem.menuNeedsUpdate` → `PlatformItemList.update` → `destroy for Button` → Lightamer 闭包析构链 |
| `guiwalk-crash-2026-10-07-0937-lut-import-panel.ips`（FINDING-F，LUT 面板） | hover 驱动 hitTest | `NSHostingView.hitTestingResponder` → `ButtonResponder.updateValue` → `assignWithTake for AppKitButtonConfiguration` → 闭包析构链 |

排除项：`appbundle-crash-2026-10-07-0812.ips` = ToneEqual/PipeCache（`swift_unknownObjectRetain`
in `ToneEqualModule.dispatchPack`），非 L057 族，不入本批。

## D2 判别式（什么点位 Task 足够 / 不够 / 充分模式是什么）

- **崩溃必要条件** = modal session 嵌套在「SwiftUI 正在驱动的 callout」内。
- **`Task {}` hop 的本质** = 把面板启动推迟到 main actor 队列的下一拍；拆掉的只是动作闭包帧。
  而 main actor/main queue 的 drain 挂在 CFRunLoop **common modes** 上，
  `NSEventTrackingRunLoopMode`（菜单追踪 / AX simulated-open 维持态）∈ common modes →
  Task 体可以在菜单追踪/模拟打开尚未拆除时执行 → **嵌套依旧成立**。
  - Task 足够 ⇔ 动作返回到 Task 执行之间追踪态已自然拆除（手动点击菜单项的常见时序；
    F-1 验证 ×5 恰落此窗口）——**时序幸运，非结构免疫**；
  - Task 不够 ⇔ AX 驱动 press（simulated-open 维持）等时序（.ips 085205 实证：
    Task 包裹的菜单命令路仍崩）；
  - `DispatchQueue.main.async` 与 main-actor Task 同机制类（main queue drain），**同不免疫**，
    禁止当「修复」使用。
- **充分模式** = 结构性消除嵌套：面板呈现换 **`begin(withCompletionHandler:)`**（文档语义 =
  非阻塞、面板 modal loop 由 AppKit 在当前事件处理完毕后的安全点自行调度，**从不嵌套进调用方
  任意 callout 栈**；结果经 completion handler 在干净栈上交回）；调用点再套 `Task { }` hop
  （begin 调用本身也脱离动作帧）= 双保险。
- 免疫面与调用路径无关：菜单命令 / 按钮 / 上下文菜单 / sheet 内容 / AX 驱动，凡 presentation
  走 begin + 动作帧先返回，均无嵌套 → 按判别式判定「安全」。

## D3 修复形态（单一缝）

新增唯一呈现缝 `PanelPresentation.present(_:) async -> URL?`
（`App/Sources/Lightamer/UI/PanelPresentation.swift`）：`withCheckedContinuation` 包
`panel.begin`，OK → `panel.url`、取消 → nil。全族 wrapper（LibraryPanels ×4 / FileOpener ×3 /
PresetFilePanels ×1）与就地 `NSOpenPanel` 构造点（Export ×3 / Settings ×3 / Relink ×1 /
Sidebar ×1 / LUT ×1）一律改 async 走该缝；按钮/菜单/上下文菜单调用点套 `Task { await … }`。
机检 gate = `grep -rn "\.runModal(" App/Sources` 零命中（注释不带括号形态不计）。

回归测试可行性：**不可行，声明**——NSOpenPanel 不可注入（具体类、无协议缝），且 F-1 先例
（81d7107 body）已证连 GUI 自动化在修复前都难复现该崩（需 AX simulated-open 时序）；
进程内注入无意义。回归门 = 机检 grep 零命中 + 实机走查（每类点位取消 ×5 + hover 撞击 +
菜单重开）。

## D4 勘误一：FileOpener 不是死代码（账面「零调用」为 grep 假阴性）

M3-1-02-ACCEPTANCE §三记「FileOpenHelper :19/:31/:62 零调用者（死代码）」——**不成立**。
grep 假阴性根因：**类型名是 `FileOpener`，文件名才是 `FileOpenHelper.swift`**（按文件名 grep
类型引用自然零命中）。实测调用点 5 处：

| 调用点 | 可达性 |
|---|---|
| LightamerApp :1227 `File→Open…`（⌘O） | **无条件可见**（不在 visibleMenuCommands 门内）——**活体同步 runModal in 菜单帧，今日即 F-1 同形活崩点** |
| ContentView :529 工具栏打开钮（⌘O 同款） | 活 |
| EmptyStateView :40（EditorAreaView :67 空态 CTA） | 活 |
| LightamerApp :1242 `File→Open Session…` | legacy 门内（gate=true 才渲染），QA 回切通道可达 |
| SidebarView :578 `openSessionPanel` | legacy Sessions 区 |

处置：**三方法全修**（async + present 缝 + 调用点 Task hop）；FileOpenHelper.swift 保留。

## D5 勘误二：PresetManagerWindow ×2 实为 ×1 活 + ×1 死

- `PresetFilePanels.exportPanel` :416 = **活**（contextMenu 导出 :229 ← exportPreset :355）→ 修。
- `PresetFilePanels.importPanel` :404 = **真死代码**——导入面已被 `.fileImporter`
  （PresetManagerWindow :94-105，sheet 型、非本族）替换，全仓零调用 → **删除**。

## D6 逐点位修复表（16 点位 → 0 runModal）

| # | 文件:处 | 调用形态 | 修复 |
|---|---|---|---|
| 1-4 | LibraryProjectController LibraryPanels ×4（newProject/openProject/folder/destination） | 菜单命令（LightamerApp :1614/:1625/:1635/:1648/:1662 handlers）+ Welcome sheet :1154-1155 | wrapper → async + present 缝；菜单/Welcome 调用点已 Task 包裹（补 await）；`importFolderFromPanel` 改 async |
| 5-7 | FileOpenHelper ×3（openImage/openFolder/openSessionFolder） | 菜单 ⌘O（无条件）+ 工具栏 + 空态 CTA + legacy 门两处 | 三方法 async + present 缝；5 个调用点 Task hop |
| 8-9 | ExportPanelView :248 chooseDestination / :310 chooseScript | 检查器 Export 页按钮 | async + present 缝 + 按钮 Task hop |
| 10 | ExportInspectorView :206 chooseDestination | M2 Export 页按钮（M3-1-03 同文件，改动半径 = 该函数 + 按钮行两处） | 同上 |
| 11-13 | SettingsPages :321 chooseLutRoot / :1206 chooseICCProfile / :1467 chooseLocation | Settings 三页按钮 | 同上 |
| 14 | PresetManagerWindow :421 exportPanel | contextMenu 导出项（菜单形态） | async + present 缝 + contextMenu 项 Task hop；importPanel 死代码删除（D5） |
| 15 | RelinkSheetView :191 pickDirectory | sheet 内按钮 | 同上 |
| 16 | SidebarView :985 chooseRelinkDirectory | **contextMenu 菜单项**（目录会话行右键——与崩溃族同形的活体菜单点） | async + present 缝 + contextMenu 项 Task hop |
| 17 | LutPanelView :239 importLut | a81483d 已 Task 包裹（判别式：时序幸运非免疫） | 函数体走 present 缝 + 按钮 `Task { await }`，注释更正 |

## D7 行为与边界

- 面板外观/行为不变：`begin(withCompletionHandler:)` 与 runModal 同为 application-modal
  窗口（非 sheet），仅呈现调度点不同。
- 取消语义逐点保持：nil → 各调用点既有 guard-return / relinkSessionTarget 清理路径不变。
- `panel.directoryURL` 预置、allowedContentTypes、canCreateDirectories 等配置逐字段零 diff。
- completion handler 在 MainActor 缝内 resume（AppKit 主线程回调 → await 恢复 MainActor 语境），
  后续状态突变（exportState/@State/store 写）时序与原同步路径一致（面板结束后执行）。

## D8 走查期新发现（本批不修，挂账）

1. **L057-B（error，OPEN）——AX 自动化压力下的主线程栈溢出**：见 D1R。证据 =
   三份 .ips 全 stack-guard + 140155 零面板实例。疑与发现 2 同根（AX/AG 子树）。
   后续专项首务：修 AX 压力稳定性，否则一切深度 GUI 走查（本批 B1/B2 反复被其
   干扰）都踩雷。走查脚本落 fix-batch/（l057_drive/l057_phaseb/l057_phaseb2）。
2. **LUT 检查器页全局空白（error，OPEN）**：HEAD（89f21b2，本批 diff stash 对照
   实测）上 LUT 页选中后内容区空白（导入 .cube… 按钮不可达）——m31walk 与
   editor-probe 两项目复现，色调页正常；M2-11 T7（10-07 09:36 截图
   `.work/gui-acceptance/m2-11/t7-lut-pane-builtin40.png`）时渲染正常。M3-1-01 批
   恰触 LutPanelView（编码 Picker）且其验收对 panel AC 走读码+单测腿、无 GUI 腿，
   为最可疑致破批。证据 = /tmp 截图已失（未入库），复现路径：开项目 → 编辑器 →
   LUT 页签。本批 Phase B 的 LUT 面板取消走查因此被阻（ff_drive 形态不可达），
   该点位的修复本身（present 缝）与其余点位同缝，已由其它三类点位实测覆盖。
3. **Settings 窗口 AX 树不物化（工具面，OPEN）**：`com_apple_SwiftUI_Settings_window`
   深度遍历（maxd 20-26）只见窗口不见内容（SwiftUI Settings scene 的 AX 惰性），
   SettingsPages 三点的实机取消走查被阻——同缝覆盖声明同上，后续 L057-B 专项
   修 AX 稳定性后补走。

## D9 实机取消走查汇总（修复后 build，全部零崩）

| 形态 | 点位 | 轮数 | 结果 |
|---|---|---|---|
| 菜单命令（AX simulated-open 驱动 + ⌘N 键盘第 1 轮） | LibraryPanels.newProject/openProject ← LightamerApp 菜单 | ×5 | PASS（每轮取消后 AX 重开文件菜单 + hover 撞击） |
| 键盘等价（⌘O） | FileOpener.openImage ← File→Open | ×5 | PASS（同上撞击序列） |
| 检查器页按钮 | ExportInspectorView.chooseDestination（export.page.choose_directory） | ×5 | PASS |
| LUT 页按钮 | LutPanelView.importLut | — | **被 D8-2 阻**（HEAD 同样空白，非本批回归） |
| Settings 三按钮 | SettingsPages ×3 | — | **被 D8-3 阻**（AX 不物化，同缝声明） |

证据 = `.work/gui-acceptance/fix-batch/`（l057a/⌘O l057d/Export 页 l057f 三组
round png + 两份 .ips 副本 + 三个驱动脚本 + MANIFEST）。

## D10 修复批结案（2026-10-08 夜间双 error 批；证据 = `gui-acceptance/fix-batch/L057-B-EVIDENCE.md`）

1. **D8-1（L057-B）已交付**：三 .ips 全主线程栈底 guard 故障（74/92/165 帧）——无自研
   循环，析构级联撞 8MB 主栈，Debug -Onone 巨帧放大；detonation 三面均为 VoiceOver
   等价真实 AX 路径（非纯自动化伪影）。修复 = 主线程栈 `-stack_size 0x4000000`（64MB，
   双配置；vmmap 机检 thread-0 64.0M reserve）→ `fix(l057)` 9c074a4。0937 的
   runModal 嵌套形态另由 L057-A begin 缝结构性消除（D3），与本旗标互补。
2. **D8-2（LUT 页空白）改判 + 已交付**：**非 M3-1-01 回归**——空白 = 老 base 文档
   （快照早于 lut3d 入种子）恢复后活集缺 lut3d 实例，页面零行零面板无空态；
   同构建上 base 含 lut3d 的文档（GFX editor-probe）完整渲染（AX 验证选中态对照）。
   D8-2 原判「M3-1-01 最可疑」系文档考古错位（T7 与复现用的是不同文档；且 recents
   存在 8 个 editor-probe-*，AX press 未生效会误报「按钮不可达」——本批起按压一律
   AXSelected 复核）。修复 = 恢复补种（`SidecarSeedTopUp` + restoreFromSidecar 接线，
   5 测入 Library bundle）→ `fix(app)` 571c3c0；先前空白文档的 LUT 页取消 ×5 补课
   全零崩（D9 表 LUT 行缺口就此闭合）。
3. **D8-3（Settings AX 不物化）不在本批**：L057-B 栈旗标落地后 AX 压力面余量 8×，
   后续走查可重试；仍挂工具面账（SwiftUI Settings scene AX 惰性非崩溃面）。

