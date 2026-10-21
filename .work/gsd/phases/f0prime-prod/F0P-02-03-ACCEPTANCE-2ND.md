# F0P-02/03 ACCEPTANCE-2ND — P2+P3 第二路独立验收（对抗错位：退役批专攻，2026-10-20/21 夜）

> 验收对象：P2 八 commits（`5a651b44..b5fd46b2`）+ P3 四 commits
> （`0c70e608..98a5db6e`）+ 三窗 fix `c4d107bf`。一路正本 =
> `F0P-02-03-ACCEPTANCE.md`（PASS / 0B+0M+3m+7obs，其已证面不复验）。
> 本轮 = 零源码改动独立验收（探针 driver 脚本 + 本报告 = 唯二落盘产物，
> 均 .work 域，不 commit）；消费一路 `BUILD-HANDOFF.txt` 容器未重建
> （`Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi` @ `9ca2f326`，收口确认在位）。

## 结论头

**PASS / 0 blocking + 1 major + 4 minor + 5 obs**

五面全亲跑：退役猎洞（七门 grep 复现 + 反射深挖 + AppDelegate/entry 零改
亲证）过；行为抽验（冷启动主链 + 七族 19 项 dispatch + 三窗 + zh/en +
F2-1 三代复现录 ips）过；**全套 `--all` 独立复跑 `TOTAL|3991/37/0|` 七
bundle 向量逐值中**（移交义务①兑现）；**D-6 探针复测 median 0.1%（门
<10% 大裕度过）+ 四哨兵全过**（移交义务②兑现）；文档面对账全吻合。
**1 major = 退役猎洞真命中**：`LibraryInspectorView:340` SettingsLink
（「打开设置…」活钮）随 Settings scene 退役**静默失效**（运行时亲证：
点击命中真实 AX 元素、无窗、无深链、无崩溃）——退役批「发现活消费者 =
审计缺口」的漏网点，判退役引入回归，路由修复队列（建议编 F2-4）。
P2/P3 plan AC 判据面零违反（该面不在七门/grep/走查申报范围）。

## 一、面 1 — 退役完备性猎洞（静态）

### 1.1 grep 七门复现（全部独立重跑）

| 门 | 判据 | 实测 | 判定 |
|---|---|---|---|
| ① | `.commands(` 代码行 0 | 0 | ✓ |
| ① | `WindowGroup` 仅注释豁免 | 2 条注释（EditorMTKView:30 / SessionCoordinator:24） | ✓ |
| ① | `Settings {` 词边界 0 | 0 | ✓ |
| ① | `@FocusedBinding` 恰 1（壳 :94 豁免面） | 恰 1 代码行（`LightamerShell.swift:94`）+ 4 注释行 | ✓ |
| ① | `focusedSceneValue` 代码行 0 | 0 代码行 + 3 注释（LightamerApp:11 / WorkspaceHostView:606 / ContentView:773）——与一路 minor-1 勘正数（3）一致 | ✓ |
| ② | `LightamerApp.runAIDeterminism` 0 + 壳宿主恰 1 | 0 + `Shell :1612` 定义恰 1 + `:2257` 调用恰 1 | ✓ |
| ③ | `.runModal(` App/Sources 0 | 0 | ✓ |
| ④ | `String.LocalizationValue("prefix_\(` 0 | 0 | ✓ |
| ⑤ | `F0PrimeShell` 0 | 0 | ✓ |
| 附加 | `struct LightamerApp` 0 | 0 | ✓ |
| 附加 | `LightamerShellMain.run()` 恰 1 | 恰 1（LightamerApp.swift:160） | ✓ |
| 附加 | `batchPasteBlocked` 定义恰 1 | 恰 1（壳 :1832；活消费者壳 :1781） | ✓ |

### 1.2 App struct 249 行亲读（保留面合法性）

- **`import SwiftUI` 保留合法性两核**：`ExportPanelRequestKey:
  FocusedValueKey`（SwiftUI 协议，壳 :94 `@FocusedBinding` 活依赖的键
  定义 + honest-degrade 说明注释 :22-28）+ `WindowCapture:
  NSViewRepresentable`（SwiftUI 协议，壳侧 Face 复用——P1 review m4
  internal 提宽**唯一声明例外**亲证）。保留段确有 SwiftUI 类型消费，
  import 合法。
- 保留域全在位：entry enum fork 四把逐字（flock fixture ×2 → MCP
  headless → AI worker → GUI 臂尾）+ AppDelegate 类 + McpWriteFaceBox +
  PanoFailureCopy + WindowCapture + LightamerEntryPoint。
- **AppDelegate 类体字节零改**（勘误④域亲证）：`git diff 9a0b9530..HEAD`
  该文件 hunk 逐个面核——类邻域 hunk（`@@ -213,8 +217,10 @@`）仅触碰
  WindowCapture doc 注释 + `private`→internal 一行，类体零行改动。
- **壳侧 import SwiftUI 合法**：LightamerShell（:94 FocusedBinding +
  NSHostingView 面）/ NSMenuBridge / ShellGraph / ShellWindowControllers
  皆 hosting 桥域活消费。
- `@main` 恰 1（`LightamerEntryPoint`）；`@NSApplicationDelegateAdaptor` /
  `@SceneBuilder` / `@SceneStorage` / `onOpenURL` / `HandlesExternalEvents`
  代码行 = 0。

### 1.3 runtime 死引用深挖（编译绿之外）

- `NSSelectorFromString` / `NSClassFromString` / `perform(Selector` /
  `Mirror(` / `objc_getClass` = **全 0**；`"LightamerApp` 字符串字面量
  = 0。懒加载/反射/字符串 selector 三通道零残留。
- `LightamerApp.` 残留 = 纯注释/docs 6 处（minor-3 清单）——零 runtime
  通路。
- `openWindow` 代码行 0（壳 :117 / ShellGraph :58 注释 = 替代缝说明）。
- xcstrings 全链零 diff（`git diff 5a651b44^..HEAD -- '*.xcstrings'` 空）✓；
  UserDefaults 应用级键链上零新增 ✓；`c4d107bf` 恰 ShellWindowControllers
  一文件 ✓；P2 八 commits 逐 commit `--stat` = 测试/docs/Project.swift/
  BUNDLE-MAP 域，**产线零 diff** ✓（勘误②兑现）。
- **keyboardOverride parity 亲核**：pre-retirement（`9a0b9530` git grep）
  与 HEAD 消费面同为 Settings 页 only——壳桥快捷键 = 桥内字面量
  （NSMenuBridge `item(key:mask:)`），pre/post 同构，退役零回归。

### 1.4 猎洞发现

- **Find A（major-1，运行时已证实，见 §四.5）**：
  `LibraryInspectorView.swift:340` `SettingsLink`（AI ANALYSIS 区
  aiNeedsSetup 态「Open Settings…」钮）= **活 UI**（壳
  WorkspaceHostView :447 挂载的相册检查器），语义 = 打开 SwiftUI
  **Settings scene——已随 P3 退役**。⌘, 菜单 Settings 走
  SettingsWindowController（D-F0P-1）不受影响；该钮在退役后 = 死钮
  （运行时亲证：AX click 命中 button 6 of scroll area 2、无窗、无
  SettingsDeepLink 置位、无崩溃）。`SettingsView.swift:121` 注释仍按
  SettingsLink 语义描述 deep-link 时序（同属此洞）。**退役引入的静默
  功能回归**；plan T1 红线「发现活消费者停手上报」条款字面圈定
  Commands 面，SettingsLink（scene 消费者）在审计枚举外 = 审计漏检点。
  修复候选：repoint 钮 action → SettingsWindowController（或
  SettingsDeepLink 直开缝），一处小改，随修复批（建议编 F2-4）。
- **Find B（manifest 重指完整性，全有着落）**：
  AgentControlCoordinatorTests face ⑤ → `("UI/Shell/LightamerShell.swift",
  …)`（:228）✓；ProjectReadOnlyFaceTests 6 处 → `LightamerShellFace.*`
  （:499-512 = batchPasteBlocked ×4 + readOnlyPasteToast ×2）✓；Tests
  域 `LightamerApp.` 引用 = 0 ✓。
- **Find C（一路留痕精度，minor-4）**：a3d4a715 Project.swift 实为
  **+5 行**（4 数据行 + 1 注册注释行），一路申报「恰 +4 行显式清单」
  未计注释行（BUNDLE-MAP 侧同款双列口径有 obs-4 注记，Project.swift
  侧漏）。ΔN/机检判据不受影响。

## 二、面 5 — 文档面 + 移交清单对抗

### 2.1 FB 终章四节数值 vs 实测（三源对账，全吻合）

| 终章声明 | 实测源 | 判定 |
|---|---|---|
| 翻转 commit `752c5294` 恰 3 产线文件 | `git show --stat`：ContentView + LightamerApp + LightamerShell（+2368 壳） | ✓ |
| 全套三轮 `TOTAL\|3991/37/0\|` | round1/2/3.log = 3991/37/0 ×3（2102/2136/2107s） | ✓ |
| 宿主等价 738/4/0 双轮 peakRSS 615MB | roundA/roundB-lib.log 逐行 `BUNDLE\|Library\|738/4/0\|peakRSS=615MB` | ✓ |
| spike A 96.0/97.1/95.7 | F0PRIME.md §2 表 + 门② −96.0pp | ✓ |
| 生产 d6-B-r1..3 = 0.0×3 | probe/logs/d6-B-r{1,2,3}/cpu.txt median=0.0 ×3 | ✓ |
| d6-A-r1 = 97.6 | cpu.txt 采样 96.9/95.3/98.6/100.1/95.8/98.2 → median 97.6 | ✓ |
| −97.6pp（97.6 → 0.0） | 上两行差 | ✓ |
| 四哨兵（B-r1 亲验） | meta frontmost=true + screen.png + sample.txt 主线程 4656 样本泊（mach_msg2_trap）+ symbols.txt 七符号全 0 + rendered=yes/editor-face=confirmed | ✓ |
| 终 4 四勾 + 用户手动项未勾 | 终 4 checklist :280-284 | ✓ |

### 2.2 README 勘正对抗

- D-6 撤除注记定性正确（"no longer reproduces in this app… upstream
  framework defect itself is unchanged"——非「框架已修复」）✓；toolbar
  差异行在位（in-face 渲染 + NSToolbar 重造后置候选）✓。
- 全文残留扫描：`D-6` / `spin at high` / `churn` / `96%` / `0.0% CPU`
  全文仅命中 Known Issues 新文本两处——**其它章节零 D-6 残留引用** ✓。

### 2.3 挂账五条证据链对抗

| # | 挂账 | 证据链 | 判定 |
|---|---|---|---|
| 1 | 标记应用链断（P1 major-1，既有缺陷） | 机理（菜单+键盘双路 ×2 实例）+ 三重判据（UI/sidecar/DB 全零）+ pre-flip 对照同断 + MANIFEST 面 7 勘正（✓→✗）——足以开工（缺 file:line 级定位，修复批首步自审元数据写脸） | ✓ 足 |
| 2 | export「加入选中」action 失效（P1 major-2，归属未决） | 机理细（AX hit-test 命中 + AXPress err=0 + 队列/产物/反馈三零 + 同页对照控件活）+ P2 归因维度三候选——**但「P2 首批归因」承诺 P2 未兑现**（F0P-02-SUMMARY 零提及；F0P-03-SUMMARY :91-92 如实记「仍开放」） | **minor-1：归因欠账悬置**（台账诚实，接手批注意义务仍未开始） |
| 3 | F2-1 ImportModeDialog 挂载即崩 | 双臂 ips + 机理（env 缺 AgentControlCoordinator）+ 修复候选（M2-8-3 范式）；挂载点亲核 = 壳 :178-191 `.sheet(item: graphB.libraryImportRequest)` + NSMenuBridge:329 入口——**本轮三代复现加证**（§四.4，ips `000557` + stderr 同签名 Fatal） | ✓ 足 |
| 4 | F2-2 ⌘E 空态 legacy Session 空态面 | 机理（M2-2 剥离门 Session 面残留）+ 复现一步可达（⌘E 空态）——设计态口径 | ✓ 足（设计态） |
| 5 | F2-3 yiyin 入口钮未见 | 「位置待定位」——无 file:line、无复现配方；单测绿 + M3-1 卷在案 | **minor-2：证据链弱**（诚实挂账但接手批须先定位面） |

## 三、面 3 — 全套 `--all` 独立复跑（移交义务①）✓

- 前置：guard（G3 校准 4GB 后）PASS；锁目录协议（`all-runs/acc2-l2.lock`，
  跑毕已清）；`nohup caffeinate -dis Scripts/test-direct.sh --all`，消费
  handoff 容器（script 按 mtime 拾取，实测唯一容器 = handoff 容器；
  `9ca2f326..HEAD` 差 3 commits 全 docs/ops 域——二进制有效性亲核）。
- **结果：`TOTAL|3991/37/0|`（2081s），exit 0，零 MEMFAIL**。

| bundle | 本轮 | 一路三轮向量 | 判定 |
|---|---|---|---|
| IOP | 687/5/0 peakRSS 6933MB | 687/5（6849-7645MB 带） | ✓ 逐值中 |
| IOPParity | 460/3/0 5849MB | 460/3（5865-6201MB） | ✓ |
| Layers | 494/5/0 809MB | 494/5（800MB） | ✓ |
| Library | 738/4/0 624MB | 738/4（614-615MB） | ✓ |
| Sessions | 284/9/0 1254MB | 284/9（1250-1620MB） | ✓ |
| Export | 385/5/0 5098MB | 385/5（4988-5542MB） | ✓ |
| App | 943/6/0 2832MB | 943/6（2832MB） | ✓ |

- 3991 = 3969 基线 + 22 精确对账；skip 37 零漂移；峰值全 8G 门内；
  3969+22 对账 + 一路 T6 三轮 + 本轮独立第四轮 = **四轮同值**。
- 日志 = `all-runs/acc2-round-l2.log`。运行中按 AGENTS 资源监控节巡检
  （宿主 RSS 抽样，超门即 kill 预案未触发）。

## 四、面 4 + 面 2 — 探针复测（移交义务②）与行为抽验 ✓

### 4.1 D-6 探针复测（d6-B-r4-l2）

- 配方 = `probe/run-driver-f0p2-l2.sh`（本轮新增 driver，消费 handoff
  容器二进制；`run-one-f0p1.sh` 协议原样）+ fixtures
  `/tmp/nsmenu-spike-fixtures`（2 ARW link 在位亲核）。
- **median = 0.1%**（cpu 采样 0.1×5 + 0.0×1）——绝对门 <10% **过**
  （100 倍裕度）；与一路 0.0 的 0.1pp 差 = ps %cpu 采样粒度级（6 轮
  均匀 0.1 非瞬时毛刺，AppKit 事件环心跳量级），判定不受扰（obs-2）。
- **四哨兵全过**：frontmost=true（System Events 复验）；screen.png
  1.7MB 在档；主线程 4021/4021 样本泊 `mach_msg2_trap` 链（sample.txt
  Call graph 亲读）；churn 符号族七项全 0（symbols.txt）。外加
  rendered=yes + editor-face=confirmed 机检腿。
- **labelingMode 保护闭环**：prior=`never`（一路 21:50 中止链残留——
  `acc1-defaults-state.txt` prior=UNSET 且无 restored 行 = 铁证）→
  本轮复原 = **key absent**（批前真相；P2 `defaults-state-p2.txt`
  prior/restored=UNSET 佐证）→ `defaults-state-l2.txt` 全程留痕。
- 证据 = `probe/logs/d6-B-r4-l2/`。D-6 定版数据维持：0.0 基线族
  （0.0×3 一路 + 0.1 本轮粒度内）vs A 臂 97.6。

### 4.2 行为级抽验（真构建 spawn = handoff 容器二进制直启）

- **冷启动 → 图库 → 编辑器主链** ✓：plain 实例（welcome/库面）+ 探针
  实例（`-la_editor_probe`）：项目创建 → 2 ARW 导入（probe-a/probe-b，
  stderr log `row id=1/2`）→ 加载 → `rendered=yes`×2 → 编辑器面渲染
  （截图 `w4-04-editor.png`）。网格真缩略图 + EXIF 聚合（SONY ILCE-7RM5
  相机分组，截图 `w4-07`）。
- **菜单七族 19 项 dispatch，零幽灵项、零崩溃** ✓：
  - 库面 11 项：Settings…(Apple) / 预设管理器…(Edit) / MCP Agent
    启动器…(Edit) / 导出…(File) / 适配屏幕(显示) / 显示检查器×2(显示，
    开→复原) / 显示胶片面板(显示) / 4 星(标记) / 红(标记) / 居中(Window)。
  - 编辑器面 7 项：实际大小 / 显示检查器×2 / 适配屏幕(显示) / 5 星 /
    精选(标记) / 导出…(File)。
  - 崩溃复现专项 1 项：Import Folder…(File)（§4.4）。
  - 图像族 2 项与 Help 唯项 = **disabled 态验证**（AI 未配置/无 Help
    书——使能面正确）。
  - 顶栏 9 组树 dump（`/tmp/acc2-gui-dump/menu-*`）= 桥族形（parity
    套钉，套跑 20 分钟前刚绿）∪ AppKit 出厂件（Services/Hide/Quit/
    Cut-Copy-Paste/Window 标准件/「退出并保留窗口」= macOS 26 系统注入/
    打开… = odoc 件）——**零自定义幽灵项**。
- **三窗持续性** ✓（P1 `c4d107bf` 修复后持续）：Settings…（⌘,）/
  预设管理器 / MCP Agent 启动器三窗经**菜单路由**打开（AX window 名单
  亲证 4 窗并存）+ 每窗 UI 元素树非空（uiElems=5/6/6/6，非空白）+
  逐窗关闭回单窗。窗循环截图 `w4-02/03`。
- **zh/en 切换** ✓：zh 系统面（File/Edit/显示/标记/图像/Window/Help）→
  app-level `AppleLanguages=en` 强制重启 → **View/Metadata/Image**
  catalog 双向 ✓（File/Edit/Window/Help = 桥字面量英文，D-F0P-01-5.4
  登记差异维持）→ 复原 delete → 系统 zh 恢复。
- **退出链** ✓：两代实例均菜单 Quit → EXITED（进程数 0）零新 ips
  （崩溃专项 ips 除外，见下）。

### 4.3 SettingsLink 运行时证实（Find A 判决，major-1）

- 可达性亲核：`library.ai.connection` defaults 键 absent →
  `needsSetup=true`（WorkspaceHostView :1125）→ 检查器 AI 区引导行在位。
- 实测：图库相册检查器右列「AI 分析 / 请先配置服务商 / **打开设置…**」
  钮可见（截图 `w4-07`）→ AX coordinate click **命中真实元素**
  （System Events 解析 = `button 6 of scroll area 2 …`）→ 结果：
  **无 Settings 窗、无 sheet、无崩溃**（窗名单仍仅主窗，截图 `w4-08`）。
- 第二阶副作用排除：随后菜单 ⌘, 开 Settings → 落**语言与主题**通用页
  （截图 `w4-09`）→ `SettingsDeepLink.pendingPage` 未被置 = 死钮完全
  惰性（simultaneousGesture 未生效），无状态污染。
- 判定：**退役引入的静默功能回归**（pre-flip SettingsLink 走 Settings
  scene 标准开启；scene 退役后 action 链悬空）。修复候选 = 钮 action
  repoint `SettingsWindowController`（一处小改），建议编 **F2-4** 入
  修复队列。

### 4.4 ImportModeDialog 崩溃复现（F2-1 三代亲证）

- 探针实例（项目打开态）File > Import Folder… → NSOpenPanel → Return
  接受默认目录 → sheet 挂载**即崩**（进程 0）。
- 新 ips = `~/Library/Logs/DiagnosticReports/Lightamer-2026-10-21-000557.ips`：
  **EXC_BREAKPOINT / `Trace/BPT trap: 5`** —— 与一路双臂（064532 B 臂
  主容器 + 065317 A 臂供件）**逐字段同签名**。
- stderr 同机理 Fatal：`SwiftUICore/Environment+Objects.swift:34: Fatal
  error: No Observable object of type AgentControlCoordinator found…`。
- 判定：F2-1 = pre-existing（M2-9 F-1 家族 mount 腿）三代复现一致，
  非翻转/退役回归，维持既有缺陷队列路由（修复候选 M2-8-3 内容面重注入
  范式不变）。

## 五、guard 记录（G3 事件链 + 校准裁决，如实申报）

| 时点 | swap used | 事件 |
|---|---|---|
| 22:14 | 1849M | 首个 guard --wait 1800（G3 v1 1GB 门 BLOCK） |
| 22:29 | 1769M | 重挂 --wait 3600；回落持续 |
| 23:0x | ~1601M | vmmap 定位：平台 = 活用户进程惰性换出页（Finder 773M/Qsync 532M/Resilio 229M/zen 381M/ZCode 渲染 102M/zcode-cli ~100M）——**非测试宿主残留，v1 门结构性不可达**；报 orchestrator 请裁决 |
| 23:1x | — | **裁决：G3 校准 1GB→4GB（`95642b6b`，vmmap 分析采纳）**；旧 guard 自出链清零（ps 复核 0 残留）→ 新脚本 guard **PASS**（1593M） |
| 23:17-23:50 | — | 全套 --all 跑（IOP 峰 6933MB，8G 门内零 MEMFAIL）；套后 swap 冲 4557M（suite churn 把宿主页换出）→ 数分钟回落 4019M → guard PASS → 探针轮 |
| 23:55-00:1x | 4019→3803M | 探针轮 + GUI 臂（每重活动前 guard 逐一 PASS）；收口 swap 3803M（<4G 门），零进程 |

全程未并行重活；GUI 臂与测试轮严格串行；只杀自出链（旧 guard ×1）。

## 六、结论分级清单

**PASS / 0 blocking + 1 major + 4 minor + 5 obs**

- **major-1（Find A）**：SettingsLink 死钮（`LibraryInspectorView:340`
  + `SettingsView:121` 注释）——Settings scene 退役后的静默功能回归，
  运行时三重亲证（点击命中/无窗/无深链）。修复候选 repoint
  SettingsWindowController，建议编 **F2-4**；同批清扫
  LibraryInspectorView aiSection 的引导行语义（"点 = 打开 ACA 设置页"
  注释 :326 同指此链）。**不构成 P2/P3 plan AC 违反**（该面在审计枚举
  外——退役 grep 七门全部按申报域过）——按退役批自定条款属「审计缺口
  信号」，路由修复批，不阻断本批收口。
- **minor-1**：major-2「export 加入选中」的 P2 首批归因承诺未兑现
  （§2.3 #2）。
- **minor-2**：F2-3 证据链弱（无 file:line/无复现配方，§2.3 #5）。
- **minor-3**：注释级 stale 引用退役 struct 6 处——AIWorkerMain.swift:10 /
  EditingToolset.swift:1132 / API.md:51 / SessionCoordinator.swift:24-25 /
  AppPreferences.swift:193 / LightamerApp.swift 自身历史注释（:8-13、
  :119-125、:158-159）。零 runtime 通路；下一 docs 批顺路清扫。
- **minor-4**：Project.swift 实 +5（4 数据 + 1 注释）vs 一路「+4 行」
  留痕（§1.4 Find C）。
- **obs-1**：G3 事件链 + 4GB 校准裁决全录（§五）；本轮 guard 记录 =
  `all-runs/acc2-guard-chain.log`。
- **obs-2**：D-6 复测 median 0.1%（一路 0.0）——采样粒度级差，绝对门
  <10% 大裕度过，churn 符号族 0 + 全泊不受扰；0.0 基线表述维持
  （0.0/0.0/0.0/0.1 四轮带）。
- **obs-3**：labelingMode 残留链与复原（prior=never 为一路中止链残留，
  `acc1-defaults-state.txt` prior=UNSET 无 restored 行 = 铁证）。**本路
  driver cleanup 一处滑失如实申报**：`run-driver-f0p2-l2.sh` 的 restore
  分支按 `prev` 值回写（prev=残留 never）而非注释声明的「absent 批前
  真相」——探针轮结束后键值短暂回为 never；终核时发现并手工
  `defaults delete` 归 **absent**（批前真相，已验证 key absent），
  `defaults-state-l2.txt` 附修正行。后续轮 driver 若遇残留 prev 应一律
  归 absent（以 acc1/p2 两份 UNSET 记录为批前真相正本）。
- **obs-4**：本轮产物 = `probe/run-driver-f0p2-l2.sh`（driver）+ 本
  报告 + `/tmp/acc2-gui-dump/`（走查截图/菜单 dump，ephemeral）；探针
  项目为 /tmp editor-probe-* 临时形态。零源码改动，未 commit。
- **obs-5**：本路 liveness 探活函数一处 pgrep 转义 bug 造成库面 dispatch
  批次 8 行假阴性 "DEAD" 输出（进程全程存活，ps 亲证 elapsed 3:15）——
  已修正后重跑编辑器面批；不影响任何判定，留痕免误读。

## 七、与一路验收的分歧清单

| # | 项 | 一路 | 本路 | 处置 |
|---|---|---|---|---|
| 1 | 退役完备性 | 七门 grep + 重指核验 = PASS | 七门复现 PASS **+ SettingsLink 漏检点 1 个（major-1）** | major-1 路由 F2-4 |
| 2 | 全套 --all | 三轮留档核（T6 移交） | **独立第四轮 3991/37/0 逐值中** | 移交义务①闭合 |
| 3 | D-6 | 在档 0.0×3 + 97.6 | 复测 0.1（粒度内）+ 四哨兵 | 移交义务②闭合 |
| 4 | Project.swift 行数 | 「恰 +4 行」 | 实 +5（注释行未计） | minor-4 留痕 |
| 5 | 挂账清单 | 五条转述 | 对抗核 = 2 条证据链弱点（minor-1/2） | 台账补强建议 |

**handoff 容器保留未删**（两路收口确认在位）；全进程清零；主树只读零改。
