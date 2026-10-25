# F0P-02-03-ACCEPTANCE-OMP — P2+P3 终审（dual_acceptance 终审眼，computer-use 实机）

> **PASS / 0 blocking + 1 major + 2 minor + 3 obs。**
> 验收窗：2026-10-24 19:04–19:30（retry 轮；前轮 2026-10-23 报告已入 commit
> `6cc3e8ae`，本轮独立重验六项全做）。验收对象 = P2 执行链
> `5a651b44..b5fd46b2` + P3 执行链 `0c70e608..98a5db6e`（lane HEAD
> `9ca2f326` 亲核：与 P3 收口差仅 ops/docs 四文件 59 行，无产品差——
> `9ca2f326` 即 P2+P3 产品终态）。
> 方法 = 零源码改动 + lane HEAD 独立 worktree + 独立 DerivedData 自建二进制
> （`/tmp/f0p23-omp2/{wt,dd}`，BUILD SUCCEEDED，strings 亲证
> LightamerShellMain×1 + NSMenuBridgeController×2）+ 探针协议复跑
> （70s settle + frontmost 先行 + stay 标记）+ computer-use 实机抽验
> （a/b/c/d/e/f 六项全做）+ 零残留收尾（worktree + 容器 + fixtures 拆除，
> 自出 pid 80939 崩溃自然消亡，`pgrep Lightamer.app` 零残留）。
> 前置双路结论：一路 PASS（0B+0M+3m+7obs，机检路线），二路
> PASS+1 major（F2-4 SettingsLink 死钮路由）。本轮 = 终审眼独立复验。
> 证据卷 = `.work/gui-acceptance/f0prime-p23/omp2/`（10 截图 + 8 菜单 dump +
> cpu 采样 + sample + stderr + F2-1 ips；`omp/` 为前轮已 commit 卷，保留未
> 覆盖——本轮改用 `omp2/`，见 §七）。

## 0. 结论头

**PASS / 0 blocking + 1 major + 2 minor + 3 obs**——六项实机抽验：

- a) 冷启动→图库→编辑器主链：探针实例双 ARW 导入（row id=1/2）→ 双
  `rendered=yes` → 编辑器面渲染 → ⌘W 图库（2 缩略图 + EXIF 概览
  SONY ILCE-7RM5 + AI 区引导行）→ ⌘E 回编辑器（使能环翻转
  enter=false/back=true）。**✓**
- b) 菜单七族抽 10 项点验全活（AX click 实测 + enabled 翻转判读），零幽灵项、
  零死项（F2-1 除外，见 e）。**✓**
- c) 三窗（⌘, / preset-manager / MCP launcher）逐个菜单路由开窗，内容真实
  渲染，零空白。**✓**
- d) 编辑器静置 CPU：六采样 1.3→1.0 单调衰减（中位 1.15）；churn 符号族
  全 0；主线程 4510/4510 泊 `LightamerShellMain.run → NSApplication.run →
  mach_msg`。**D-6 绝对门 <10% = PASS**（余量 8.8pp；非零归因见 minor-1）。
- e) ImportModeDialog 崩溃签名复现：File > Import Folder… → NSOpenPanel →
  Return 接受 → sheet 挂载即崩。ips `Lightamer-2026-10-24-192534` =
  **EXC_BREAKPOINT / Trace/BPT trap: 5** + stderr `No Observable object of
  type AgentControlCoordinator`——与四代（064532 B 臂 / 065317 A 臂 /
  000557 二路 / 092209 前轮）**逐字段同签名**，F2-1 pre-existing 第五代亲证。**✓（预期内）**
- f) SettingsLink 死钮复证（F2-4）：图库检查器 AI 区「打开设置…」钮 AX
  coordinate click 命中真实元素（`button 6 of scroll area 2 …`）→ 无窗、
  无深链（随后 ⌘, 落语言与主题通用页）、无崩溃。**二路 major-1 独立复现
  （第二轮），维持 F2-4 路由**（HEAD 主树 `926ba65d` 已修，本审验的是退役批
  终态故仍见死钮——见 §五）。

1 major = 二路 major-1 追认（F2-4 SettingsLink 死钮，退役引入静默回归，
路由修复队列，不阻断收口）；2 minor = 证据解读/口径留痕；3 obs = 方法学注记。

## 一、抽验 d) 编辑器静置 CPU（D-6 门独立复测）

二进制 = lane HEAD `9ca2f326` 自建（独立 worktree + 独立 DerivedData
`/tmp/f0p23-omp2/dd`，与执行/双路/前轮构建路径全异构；worktree 供件 =
input/ 312MB + Resources/AIModels/ 195MB 拷入 + tuist generate 零网络）。
协议 = `-la_editor_probe /tmp/f0p23-omp2/fixtures -la_probe_stay`（供件 =
probe-a/b 双 ARW link 亲建）→ stay 标记（stderr 亲核双行 loaded/rendered=yes
+ staying alive，pid=80939 ppid=本 omp 进程）→ 70s settle → frontmost 先行
复验 Lightamer → 截图 → 36s 窗 6 采样 @6s → `sample 6s`。

| 窗 | 六采样 | 中位 | 判定 |
|---|---|---|---|
| t=0..36s | 1.3/1.2/1.2/1.1/1.1/1.0 | **1.15** | <10% ✓ |

- L082 四哨兵：①frontmost true（读数前先行）②窗内截图编辑器面完整渲染
  （§六）③主线程泊 4510/4510（`LightamerShellMain.run → NSApplication.run
  → … → __CFRunLoopServiceMachPort → mach_msg` 全泊链）④churn 符号族
  displaylink/CVDisplayLink/timerFired/setNeedsDisplay/
  layoutSubtreeIfNeeded/updateConstraints 全 0（`runloop` 字面命中 =
  泊链 `__CFRunLoopRun/RunSpecific` 帧，非 churn）。
- 非零归因（minor-1）：读数呈严格单调衰减（1.3→1.0），`ps %cpu` 为指数衰减
  平均——启动/解码残留热未散尽；主线程 100% 泊 + 符号族全零 = 无 churn
  机器在场。与 P1 终审轮（1.4/0.8）/前轮（1.2）同构，差值 = 衰减曲线采样
  时点差，非行为差。D-6 门余量 8.8pp，结论不受影响。

## 二、抽验 c) 三窗逐个开（⌘, / preset-manager / MCP launcher）

逐窗 AX 真点击菜单路由开窗 → 截图 → 识图 → 红叉关窗 → 窗清单复核。每窗结论：

| 窗 | 路由 | 渲染内容（识图亲验） | 判定 |
|---|---|---|---|
| Settings（⌘,） | Lightamer 菜单 Settings… | 10 侧栏项（语言与主题选中/默认行为/缓存/本地内容识别/高级内容分析/键盘/关于/导入默认设置/显示/MCP）+ 详情面（界面语言跟随系统/主题外观深色 v1 固定）；AX entire contents 56 节点 | ✓ 非空白 |
| 预设管理器 | Edit 菜单 预设管理器… | Tone/Sunny 调整行 + 未分类/Web150 导出行 + 顶部 +/导入按钮 + 底部坏预设脚注 broken.lightamer-preset | ✓ 非空白 |
| MCP 启动器 | Edit 菜单 MCP Agent 启动器… | 工具栏（启动 Agent/停止灰/跟随输出勾/复制日志）+ 空闲——无 agent 会话 + (暂无输出) 占位 | ✓ 非空白（占位 = 空闲态合法面） |

- 三窗开关过程 app 存活（ALIVE 逐窗复核），关窗后窗清单回单主窗。
- P3 退役后三窗经 SettingsWindowController 系路由（⌘, 菜单面不受 struct
  退役影响），本轮为退役终态终审眼亲证（第二轮）。

## 三、抽验 b) 菜单七族抽查 10 项点验

menubar 九项上屏（Apple/Lightamer/File/Edit/显示/标记/图像/Window/Help，
中英混排 = D-F0P-01-5.4 登记态）。七族全量 dump 存档（File 18/Edit 21/
显示 20/标记 18/图像 2/Window 20/Help 1 + Lightamer 12；user-visible 计数）
——树 = 桥族形 ∪ AppKit 出厂件（Services/Hide/Quit/退出并保留窗口/
Cut-Copy-Paste/自动填充/听写/表情/打开… odoc 件/填充/居中/Minimize/Zoom/
Bring All to Front/标签页族）——**零自定义幽灵项**。

| # | 项 | 点验法 | 结果 |
|---|---|---|---|
| 1 | Settings… | AX click → 真窗渲染（§二） | ✓ |
| 2 | 返回图库 ⌘W | AX click → 图库面（§四） | ✓ |
| 3 | 进入编辑器 ⌘E | AX click → 编辑器面 + 使能环翻转（enter=false/back=true） | ✓ |
| 4 | 导出… ⇧⌘E | launch 态 enabled=true + AX click → 导出页全装配（§四） | ✓ |
| 5 | 复制调整 ⇧⌘C | AX click | ✓（下游翻转见 6） |
| 6 | 粘贴调整 ⇧⌘V / 部分粘贴… | click 前 false/false → 复制后 true/true | ✓ 实时翻转 |
| 7 | 5 星（标记） | AX click（写链动作），存活 | ✓ |
| 8 | 撤销/重做环 | 撤销 click → undo=false/redo=true；重做 click → 翻回 | ✓ 环翻转 |
| 9 | 预设管理器… / MCP 启动器… | AX click → 真窗渲染（§二） | ✓ |
| 10 | 软打样 / 适配屏幕 / 实际大小 / 居中 | AX click ×4，存活 | ✓ |

附加判读：标记族 16 语义项全 enabled（rating 6+flag 3+color 7）；⌘W 双面
语义与 D-F0P-01-5.1 对齐；export 恒 enabled（D-F0P-01-5.2）行为级再证；
软打样开→色域警告项恒 disabled（无 profile 恒 OFF by-design，P2 面 9 同判）；
Help 唯项 disabled（无 Help 书——使能面正确）；图像族 2 项 enabled
（AI 未配置态仍 enabled——与二路库面 disabled 读数面差，见 obs-2）。

## 四、抽验 a) 冷启动→图库→编辑器主链往返 + 导出页

探针实例 = 冷启动形态（双 ARW 导入 → 双 rendered=yes → 编辑器面渲染，
截图 omp2-01/02）。返回图库点击 → 图库面（2 缩略图 + 图库概览 inspector：
2 照片总数 + 按日期/相机 SONY ILCE-7RM5/色标/镜头分组 + 活动/搜索/AI 分析/
智能相册）→ 进入编辑器点击 → 编辑器面（大画布 + 右调色面板 + 左 filmstrip
+ 底工具轨；画布 false-color = 探针 fixture 无 sidecar 默认管线显示态，
P1 终审 obs-2 同构）。导出页 ⇧⌘E 全装配再证（预设/输出位置/文件命名 10 token/
命名冲突 Increment/元数据与色彩/SDR 导出 JPEG/UltraHDR 灰/质量 95%/
原尺寸/高级折叠）。

## 五、抽验 e/f) F2-1 复现 + F2-4 复证

**e) F2-1 ImportModeDialog 挂载即崩（✗ 项，预期 pre-existing）**：编辑器面
File > Import Folder… → NSOpenPanel 出现（6s 内，截图 omp2-12）→ Return
接受默认目录 → 面板消失 → 约 1s 后进程消亡。新 ips =
`Lightamer-2026-10-24-192534.ips`：**EXC_BREAKPOINT / SIGTRAP /
Trace/BPT trap: 5** + stderr `SwiftUICore/Environment+Objects.swift:34:
Fatal error: No Observable object of type AgentControlCoordinator found…`
——与四代逐字段同签名（064532 B 臂主容器 / 065317 A 臂供件 / 000557 二路 /
092209 前轮）。procPath = `/tmp/*/Lightamer.app`（本轮独立容器二进制）。
判定：F2-1 = pre-existing（M2-9 F-1 家族 mount 腿）**第五代复现一致**，
非翻转/退役回归，维持既有缺陷队列路由（修复候选 M2-8-3 内容面重注入范式不变）。

**f) F2-4 SettingsLink 死钮复证（major-1 追认）**：`library.ai.connection`
键 absent → 检查器 AI 区引导行在位（截图 omp2-06：AI 分析 / 请先配置
服务商 / 打开设置…）。AX coordinate click {1388,613} 命中真实元素
（System Events 返回 `scroll area 2 …` 真实元素引用）→ 结果：**无 Settings
窗、无 sheet、无崩溃**（窗名单仍仅主窗，截图 omp2-10）。第二阶副作用排除：
随后菜单 ⌘, 开 Settings → 落语言与主题通用页（截图 omp2-11）→
`SettingsDeepLink.pendingPage` 未被置 = 死钮完全惰性，无状态污染。
worktree 源码亲核：`LibraryInspectorView.swift:340 SettingsLink` 在位。
判定：**二路 major-1 独立复现（第二轮）**，退役引入的静默功能回归，维持
F2-4 路由。注：HEAD 主树 `926ba65d fix(f2-4)` 已修（SettingsLink 清零 +
request-field 形态），本审验的是退役批终态 `9ca2f326` 故仍见死钮——修复
有效性属 r12-repairs 批验收面（该批终审已实机复验真窗+ACA 深链 ✓），本轮不越界验。

## 六、分级残留清单

**major（1，二路追认）**

1. **F2-4 SettingsLink 死钮**（`LibraryInspectorView:340` +
   `SettingsView:121` 注释）：Settings scene 退役后的静默功能回归，
   本轮三重亲证（点击命中/无窗/无深链）。退役批「发现活消费者 = 审计缺口」
   信号；路由修复队列（HEAD 已修 `926ba65d`，r12-repairs 批验收覆盖）。
   **不构成 P2/P3 plan AC 违反**（该面在审计枚举外——本轮 menubar 九项 +
   七族树 dump 亦零幽灵项，佐证「审计域内完备」）。不阻断本批收口。

**minor（2）**

1. **CPU 读数非零归因留痕**：本轮中位 1.15，前五方 0.0/0.0/0.0/0.1/1.2。
   主证据链（主线程全泊 + 符号族全零 + 单调衰减曲线）已闭合「无 churn」
   结论，差值 = `ps %cpu` 衰减平均的采样时点差（P1 终审轮 1.4/0.8 同构）。
   D-6 门余量 8.8pp。本条为终审轮读数诚实留痕，不开修复项。
2. **16 面计数口径注记追认**：一路 minor-2（面 15 双列计入两桶）口径注记
   属实，建议后续卷补一行说明；不触判定。

**obs（3）**

1. **worktree 旧 guard G3 门 BLOCK 下构建仍起跑（过程瑕疵如实申报）**：
   worktree 内旧版 guard（G3 = 1GB 门）BLOCK → `--wait 600` 超时（本机
   swap 常态 ~5.9G，该门结构性不可达——二路 §五已申报并获 4GB 校准裁决，
   主树 guard 已 v1.4）；`| tail -3` 吞 exit 致 `&&` 右侧构建照常执行，
   BUILD SUCCEEDED。实质单重活成立：构建窗零他路 Lightamer 进程（ps 亲核）
   + `machine-guard.sh --monitor` 伴跑零触发 + 构建成功。形式 BLOCK 如实
   留痕；后续 worktree 轮应拷主树 guard v1.4 或显式判 guard exit。
2. **图像族使能面差**：本轮编辑器面图像族 2 项（AI 超分辨率/去杂色）
   enabled=true；二路库面读 disabled（AI 未配置）。面差 = 编辑器面 vs
   库面 enabler 上下文差（同 `enter-editor/back-library` 环翻转类机制），
   非回归信号；两读数各在其面自洽。
3. **AI modal Esc 解配方复用有效**：本轮探针实例启动后中央 modal 为「用 AI
   分析照片内容？」（暂不/分析），Esc 可解（AX 名址不可达），解后走查全程
   无再弹；defaults 零副作用（Remember 未勾，labelingMode/connection 终核
   absent）。

**双路遗留路由追认**：F2-1（既有缺陷队列）/ F2-2（设计态）/ F2-3（证据链弱，
接手批先定位）/ P1 major-1（r12 fix `266647c1` 已修）/ P1 major-2
（归因欠账悬置 minor-1，二路 §2.3 #2）按既有路由生效，本轮不重验。
revert 两步叙事（P1 范畴）不在 P2/P3 验收边界内。

## 七、验收轮痕迹与还原

- 主树起跑 `bc2baf39` → 收口 `6cc3e8ae`（窗内他人推进：前轮 omp 报告 commit
  入库），本轮零改动（本报告重写 + `omp2/` 证据卷为唯一写产物，不 commit）；
  审验对象锁定 lane HEAD `9ca2f326`（`98a5db6e..9ca2f326` 差 = ops/docs
  四文件 59 行亲核，无产品差）。`omp/` 为前轮已 commit 卷，保留未覆盖。
- 未追踪改动 `r12-repairs/omp-acceptance.log`（M）= 他人并发会话产物，
  非本轮改动，未触。
- defaults `library.ai.labelingMode` / `library.ai.connection` /
  `AppleLanguages` 终核全 absent/未写。
- 构建：worktree `/tmp/f0p23-omp2/wt` @`9ca2f326` + 独立 DerivedData
  `/tmp/f0p23-omp2/dd`（Debug, BUILD SUCCEEDED；供件 input 312MB +
  AIModels 195MB 拷入；tuist generate 零网络）。
- 进程：自出 pid 80939（ppid = 本 omp 进程）经 F2-1 复现崩溃自然消亡；
  `pgrep Lightamer.app` 零残留；收口拆除 worktree + 独立容器 + fixtures
  link（按 P2 LESSONS 候选「worktree 轮收尾即刻拆除」）；monitor 收口 kill，
  零触发记录。
- GUI 独占：本轮实机窗（19:19–19:25，起 app 至 F2-1 崩溃）零他路 Lightamer
  实例（起跑前 ps 亲核零残留）；收尾复核时（19:29）见他路实例 pid 83064
  （ppid=1，handoff 容器二进制，elapsed 起点 ~19:27——本轮实机结束后出现，
  未污染抽验）——非自出进程，按纪律未触。
