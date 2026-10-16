---
phase: M7-1（D-6 壳专项）
slug: m7-1-shell
type: research
created: 2026-10-16
author: M7-1 research worker（zcode subagent，夜间全自动授权在案——先例 D-07-3-T5-1，晨审可推翻）
inputs:
  - phases/fix2-defects/FIX2-01-DECISIONS.md（D-FIX2-1 定罪正本）
  - phases/fix2-defects/FIX2-VALIDATION.md（§挂账①④⑤⑥）
  - phases/fix2-defects/FIX2-01-ACCEPTANCE.md（第一路七观察前三条）
  - phases/fix2-defects/FIX2-01-ACCEPTANCE-2ND.md（第二路四条）
  - phases/fix2-defects/FIX2-CHECKER.md（R-1..R-5 残留——执行批自愈/supersession 已闭合）
  - phases/v2-maintenance/V2M-CHECKER.md（C-1..C-4 执行批注记——均已消费）
  - gui-acceptance/v2m/fix2-probe/（local-only 证据域）
  - research/APPLE-FB-D6-DRAFT.md
red_lines:
  - 本批零产线 diff（探针 /tmp 即弃 + 主树临时插桩已回退——`git status` modified-tracked = 0 在案）
  - H2 = macOS 27 SwiftUI 框架共犯——修法路线 = 接受降级（减树/窗拆/燃料减频），非根治承诺
  - `--all` 全套轮仍须 orchestrator 批准 + 8G 门监视
---

# M7-1 RESEARCH — D-6 壳专项（SHELL-01..05 五块测绘 + 复验门 + 路线推荐）

> 站 charter（M7 站，2026-10-16 用户四裁全落）：M7-1 = FIX2 三选一之①「接受降级 +
> gate=false 壳减树/窗口内容拆分专项」，research 复审（三选一之②）并入专项首步——
> 即本文件 §0 判别探针复验门。夜间全自动授权在案；本批 **doc-only + /tmp 探针**
> （主树临时插桩三文件已 `git checkout --` 回退，modified-tracked = 0 亲核）。
> 基线 = FIX2 终态 `3860/35/0`；HEAD = `14ee3993`（FIX2 后全 docs-only，
> `2427670e..HEAD` 零产线文件——基线未漂移的 git 面证据）。

---

## 0. 判别探针复验门（research 首步兑现——三判据当前 HEAD 亲跑，全部复现）

**环境**：本机 macOS 27.0.1（build 26A434——与 FIX2 定罪环境逐字节同 build）+
Apple Silicon；干净 HEAD build（DerivedData `dgzsvd…`，16:11 BUILD SUCCEEDED）+
probed build（同 DerivedData，三文件临时插桩增量编译）。供件 =
`/tmp/fix2acc-import`（6 TIFF，FIX2 第一路遗留）。复现腿 = FIX2 配方：
`-la_editor_probe` 建项目 → 杀进程重启 → AX 菜单腿（File ▸ Open Recent Project
▸ EditorProbe → File ▸ Enter Editor）→ 编辑器面静置采样。

### 0.1 判据一：编辑器面 CPU 硬门（SC 主判据，<10% 为门）

| 面 | 本批复验 | FIX2 记录带 | 判定 |
|---|---|---|---|
| 无项目/图库面（gate=false 空载，可见窗） | **30-34%**（10×1s ps） | 第二路 23-31%；执行方可见窗 34% | 同域 ✓（壳族固有 churn 在位） |
| 编辑器面（重开项目 + 进入编辑器，干净 build） | **82-86%**（10×1s） | 第二路 82-87%（fresh）/98-100%（交互后）；执行批 48-53%；第一路 42-44% | 同域 ✓ |
| 编辑器面（probed build） | **86-90%**（5×1s，transcript 同窗） | — | 同域 ✓ |

**硬门 <10% 判 FAIL（复现预期）——基线未漂移。**

### 0.2 判据二：菜单环六符号（sample 签名）

干净 HEAD build 编辑器面 `sample <pid> 6 -file`，全链在位：

```
flushTransactions(15) / graphDidChange(22) / appGraphDidChange(6) /
makeMainMenu(4) / updateMainMenu(7) / invalidateProperties(51) /
requestUpdate(33) / updatePreferences(12)
+ prependValue(37) / keyboardShortcut(71) / swift_getTypeByMangledName(180)
+ AttributeGraph: UpdateStack::update(536) / update_attribute(532) /
  input_value_ref_slow(429) / LayoutEngineBox.sizeThatFits(548)
```

与 FIX2 三路自采 sample 同签名（帧计数概率性差异——采样捕获窗口不同；
签名一致性 = 判据，非计数一致性；第二路自采 sample 同量级
makeMainMenu 6/updateMainMenu 4/invalidateProperties 39）。环身份复现。

### 0.3 判据三：@self-only 决定性读数（~60k 重估全 @self / 零属性变更）

**probed build 配方（可复用，入 SHELL-05 卷）**：主树临时插桩三文件
（`ContentView.body` + `WorkspaceHostView.body` 各加
`let _ = Self._printChanges()`；`LightamerApp.body` 加 scene-tick stderr 桩）
→ 增量编译 → **PTY 捕获 stdout**（`script -q <file> <app>`——`print` 走
libc stdio 块缓冲，SIGKILL 丢整块缓冲 = L077 同族教训；PTY 下 isatty 行
缓冲逐行落盘）→ 编辑器面 ~3 分钟窗 → kill → 计数 → 三文件
`git checkout --` 回退。

**读数（`gui-acceptance/m7-1/m71-editor-transcript.log`，64,094 行）**：

| 项 | 计数 |
|---|---|
| `ContentView: @self changed.`（稳态 self-only） | **21,363** |
| `WorkspaceHostView: @self changed.`（稳态 self-only） | **21,360** |
| `sceneBodyTick`（scene body getter 求值） | 21,361 |
| `changed` 行总计 | 42,731 |
| **非 @self `changed` 行** | **8 行 = 全部一次性挂载/迁移事件**（phase 翻转 ×1、projectURL ×2、@identity 挂载 ×2、gridModel 绑定 ×1、_inspectorWidth ×2、WindowAppearanceViewModel ×1） |

**稳态重估率 ≈ 119 passes/s（21,363 / ~180s）——与 FIX2 执行批同率**
（14298/~120s ≈ 119/s）。120/s = 本机 ProMotion display cycle 锁频（见 §4.1
FB 稿勘误建议）；FIX2 稿面 "~60 Hz" 为 60Hz 屏窗口读数。**@self-only +
零稳态属性变更 = 「app 无写点」结论复现，H2 定性维持。**

### 0.4 复验批附带新观察（四条，入 SHELL-05 卷/配方节）

1. **挂账⑥ 间歇再现 1 例**：probe 轮（16:12）"grid rows never arrived"
   FAIL，DB WAL 6 行在案（`editor-probe-447EFD13…lalb-wal` 626KB，
   read-through = 6 行）——「行恒落库 + grid 刷新迟到」勘误结论再度自洽；
   间歇本批全程 ~1/2 轮（probe FAIL 轮 + 复用同项目轮）。
2. **AX 菜单腿配方 zh locale 修正**：菜单栏为本地化名（`文件`/`进入编辑器`）——
   osascript 按 `menu bar item "File"` 寻址报 -1728，须用本地化名或索引
   寻址。FIX2 配方隐含英文环境假说收窄（配方正本随本节更新）。
3. **harness PID 陷阱**：`script -q <log> <app>` 封装进程 argv 含 app 路径 →
   `pgrep -f "MacOS/Lightamer$"` 双命中，`head -1` 取到 script 封装
   （假 0.1% CPU 读数——真 app pid 须从 pty 日志头 `Lightamer[<pid>]` 读或
   `ps` 过滤掉 script 行）。SHELL-05 配方钉死此条（本批亲踩）。
4. **PTY 头部控制字符**：`script` 输出带 `^D` 前缀——计数脚本需容忍。

---

## 1. SHELL-01 — gate=false 壳减树测绘

### 1.1 当前壳树组成清单（file:line 全录）

```
Window("Lightamer", id:"main")                          LightamerApp.swift:502
└─ ContentView.body（gate=false 分支）                   ContentView.swift:177-241
   ├─ WorkspaceHostView                                  :192-194
   │  ├─ .inspector(isPresented:) 宿主（SystemSplitView）:205-223
   │  │   └─ InspectorView（export/film 页宿主）          :220
   │  ├─ .focusedSceneValue(exportPanelRequest)          :228-233
   │  └─ .onChange(projectURL → rebuildQueueForProject)  :238-240
   └─（WorkspaceHostView.body）                          WorkspaceHostView.swift:124-416
      ├─ VStack { topBar; ZStack{libraryFace|editor}; BackgroundTaskBarView }
      │   ├─ topBar（项目名 + 返回/导出/壹印钮）           :595-654
      │   ├─ phase ZStack（library / EditorWorkspaceShellView + 转场动画）:127-141
      │   └─ BackgroundTaskBarView                        :143-145
      ├─ safeAreaInset(.top)  = ProjectReadOnlyBannerView :153-157  ← 环燃料（C2 已证）
      ├─ safeAreaInset(.bottom)= ToastBarView             :166-169  ← 环燃料（C2 已证）
      ├─ .focusedSceneValue(lightamerWorkspaceModel)      :170      ← 焦点写点
      ├─ .sheets ×6（task-dialog/search/relink/yiyin/labeling/AI enhance+rating）:172-301
      ├─ .onGeometryChange（yiyinSheetDomain）            :220-222
      ├─ .onChange ×2（pendingAIEnhance / pendingStackCommand / importProgress / projectURL）:253-335
      └─ .task（AI/pipe/export 装配）+ EditorProbeIfRequested（DEBUG）:342-415
      └─（editor 臂）EditorWorkspaceShellView              EditorWorkspaceShellView.swift:47-89
         └─ HStack { EditorToolRailView? | filmstrip(148) | EditorAreaView 视口 | rightPane(280) }
            ├─ filmstrip                                   ← 环燃料（E 系已证）
            ├─ EditorAreaView（视口 hero，MTKView 承载）     ← 环燃料（E 系已证）
            └─ rightPane（ScopePanel + EditorAdjustmentStack）← 环燃料（E 系已证）
```

### 1.2 阈值面（FIX2 已证判据，减树方案的地基）

- 空载/图库面：摘 `.inspector`（C1）**或**摘双 safeAreaInset（C2）任一 → 环饿死
  （sceneBody 2/25s，CPU 归零）；B1/B2（摘焦点写点）不饿死。
- 编辑器面：**三段内容（filmstrip/viewport/rightPane）任摘一段 → 环饿死**
  （0.0-0.1% CPU，E1/E2/E3 三向复核）；摘 `.inspector`、摘 insets、
  `List→LazyVStack`、摘转场动画（D1）**全部不饿死**（48-53%）。
- 残余骨架环：空载面 churn 饿死后仍有 ~28% CPU AppKit 侧低频底噪
  （~11Hz Source1 UpdateCycle → NSWindow layoutIfNeeded → 嵌套 hosting layout
  → preferencesDidChange）——D-7 同族布局递归；**减树方案对底噪的预期 =
  部分残留（AppKit 侧），不承诺归零**。
- 活参照系：legacy 面（无 gate=false 树）+ 同一菜单结构 = idle 0.1%——
  「低于阈值的树形」真实存在，减树目标 = 把单 pass 图工作量压到该量级。

### 1.3 减树候选案清单

**案 A「inset 迁移」（最小案；空载面主攻）**
- 内容：`ToastBarView` 座位移入 host VStack（`BackgroundTaskBarView` 槽之下）；
  `ProjectReadOnlyBannerView` 座位移入 VStack（`topBar` 之上）；safeAreaInset
  ×2 → 0。功能面逐字保持（同一两视图、同一数据源、同一 AX 标识）。
- 饿死预期：**空载/图库面饿死（C2 已证等效）**；编辑器面**不**饿死（FIX2 读数：
  编辑器面摘 insets 不饿死）。
- 功能损失：视觉 stacking 语义变化（inset 吃 safe-area vs VStack 顺序槽）——
  toast 行贴底、banner 贴顶的观感等价；无键盘/浮动条交互面。损失 ≈ 0。
- 结构身份风险：无 if/else 翻 @State 面（M-3 教训不触）；纯修饰符座位移。
- 风险点：ToastBarView 的 `.animation(value: editorState.toast)` 与挂载点
  同迁；`ToastFaceTests` 3 法（AX 树 wiring 断言）须随座位移过门。

**案 B「inspector 列改造」（中案；空载面 + 与案 A 打包）**
- 内容：`.inspector(isPresented:)` SystemSplitView 宿主 → 条件尾列
  （自绘 HStack 尾列 200-460pt，宽度记忆键沿用）。
- 饿死预期：空载面饿死（C1 已证）；**编辑器面不饿死（C1 实测 53% 照转）**——
  单独行使换不来 spin 消失（D-FIX2-1 备案臂不行使裁定维持）。
- 功能损失：失去 SystemSplitView 拖拽分隔 + `navigationSplitViewColumnWidth`
  自动记忆（自实现拖拽 = 中等工作量；或钉死 240 ideal）；Export/Film 页
  dismissal 语义保持（同一 switches 单真相）。
- 结构身份风险：**挂载语义迁移是最大风险**——M3-4-01 T4 教训：InspectorView
  只在本宿主挂载点可达（`exportPageActive || filmPageActive` binding 的
  present-no-op/dismiss-双关语义逐字迁移）；`SheetEnvironmentInjectionTests`
  /`ToastFaceTests` 等 AX 断言族随迁。
- 裁定：**与案 A 合并为「空载面零 churn 包」一次落**（两案判据均已证，
  合并减少一轮走查批）。

**案 C「编辑器三段减段/重组」（中案；编辑器面主攻）**
- C3 形（推荐先试，零功能损失）：HStack 三段 → viewport hero + 可收起
  overlay（filmstrip/rightPane 作为视口上的 overlay 层，常驻性 UI 保持）。
  **饿死性未证**——E 系证据只覆盖「摘除」，不覆盖「重组」；重组改变
  树深/结构，threshold 是否跌破须 scratch 实测。
- C1 形：rightPane 并入 inspector 列（编辑器右栏挂尾列/覆盖层）——
  三段 → 两段，摘除形，饿死预期强；功能损失 = 编辑器布局偏离 Alcedo
  三段 IA（UI 对标面损失大）。
- C2 形：filmstrip 收进 tool rail 弹出层（popover）——摘除形，饿死预期强；
  功能损失 = filmstrip 常驻性（换图两步操作）。
- 预判逻辑（诚实面）：threshold 形的通用预判 = 单 pass 图工作量跌破
  legacy 面量级即饿死；摘除形（C1/C2）证据直推；重组形（C3）只有
  实验能裁。**每个 C 形都必须先 scratch 实验门再落地**（FIX2「先探针
  定罪再动手」纪律的延续——防止三改）。

**案 D「编辑器面独立 NSWindow」→ §2（SHELL-02）专节。**

### 1.4 减树后编辑器面 spin 复燃预判（汇总）

| 形 | 空载面 | 编辑器面 | 依据 |
|---|---|---|---|
| 仅案 A | 饿死（高置信，已证） | 复燃（预期不饿死） | C2 / FIX2 E 系 |
| 案 A+B | 饿死（高置信） | 复燃（预期不饿死） | C1+C2 / C1 编辑器面 53% 读数 |
| A+B + C3（重组） | 饿死 | **未知——scratch 实验裁** | E 系不覆盖重组 |
| A+B + C1/C2（摘除） | 饿死 | 饿死（强预期） | E1/E2/E3 直推 |
| 窗拆（案 D） | 主窗饿死 | **未知——scratch 实验裁** | §2.5 |

---

## 2. SHELL-02 — 编辑器面独立 NSWindow 路线评估（评估报告；落地与否 research 环裁决）

### 2.1 架构改造面（逐面）

1. **状态隶属（改动小）**：EditorState/PipeCoordinator/VersionCoordinator/
   ExportState 等 15 个 @Observable 全部 app root 持有 + `.environment`
   注入（LightamerApp.swift:520-541）——独立 Window scene 的根视图同样能收
   注入（app root 是 scene 工厂），状态面零迁移。**WorkspaceModel 是
   WorkspaceHostView `@State`**（窗口寿命，WorkspaceHostView.swift:43）——
   编辑器窗口需要自己的宿主持 workspace，或把 workspace 升 app-level
   （结构改动中等；focusedValue 桥 `lightamerWorkspaceModel` 已有跨窗
   读取面）。
2. **MTKView 迁移（改动小）**：EditorAreaView→EditorMTKView 经
   NSViewRepresentable——迁窗后 layer/coordinate 面不变；EDR 视口
   （CAMetalLayer wantsExtendedDynamicRangeContent + 16F + colorspace 四态）
   跟 layer 不跟窗，预期零改。**`WindowCapture`（D-COL2，LightamerApp:546-548）
   需重挂**：`pipeCoordinator.configure(window:)` 现跟主窗——编辑器窗为
   渲染窗后 capture 目标要跟编辑器窗（多窗 screen 跟随逻辑改动；多屏
   EDR headroom monitor 同理）。
3. **close/open 生命周期（改动中）**：phase 切换（library↔editor）从
   「ZStack 翻转 + 200ms 转场」变「窗口 open/dismiss」（`openWindow(id:)`
   已有 preset-manager 先例）；⌘E = open editor window、⌘W = 关编辑器窗回
   图库（`workspace.backToLibrary` 语义映射窗 close）；WorkspaceModel 寿命
   跨窗（editor 窗关闭时 phase 回写主窗宿主）。**单窗纪律不触**：
   Plan 02-01 的 WindowGroup 多窗 bug 是 odoc 驱动的多实例；SwiftUI
   `Window(id:)` scene 天然单实例。
4. **菜单面（不变）**：NSApp.mainMenu 全 app 共享——菜单环不随窗拆分消失；
   focusedValue 按 key window 求值，编辑器窗为 key 时 `focusedWorkspace`
   照常解析。**环燃料面原样**。
5. **功能面回切**：REQUIREMENTS SHELL-02 无 feature-flag 硬性要求——但按
   SHELL-01 先例加同一 `shell.reducedTree` 门（窗拆形态作为 flag 终值，
   可回切对照）。

### 2.2 对 spin 的预期效果（判据链）

- 窗拆后：主窗只余图库面（轻树 + 无 inspector 宿主/inset → 饿死预期强）；
  **编辑器窗自身仍是「重树 + 三段内容」**——菜单环全 app 共享，
  每 pass 图工作量取决于 key/visible 窗的树。
- 反证锚：legacy 面（无 gate=false 树）idle 0.1%——环需要重树燃料；
  编辑器窗单独看仍是重树。**但**：若编辑器窗不再承载 `.inspector` 宿主
  与双 inset（那些留在主窗），其树形 ≈「案 A+B 后的三段树」——与
  C1 实测（摘 inspector/inset 编辑器面 53% 照转）**矛盾方向**：C1 说明
  inspector/inset 不是编辑器面环的持续条件，三段内容才是 → 窗拆后编辑器窗
  三段仍在 → **饿死性倾向悲观，未证**。
- 诚实结论：窗拆对编辑器面 spin 的饿死性 = **低置信、偏悲观**，唯一
  裁判 = scratch 实验门（拆窗 scratch build + 编辑器窗 CPU/transcript）。

### 2.3 量级评估：**L 级**（2-3 个 plan 波次）

- 波 1：Window scene + workspace 归属 + 生命周期迁移 + WindowCapture/EDR
  跟窗 + 走查面全量重验（⌘E/⌘W/多屏/多窗焦点链）。
- 波 2：focusedValue 桥 + 菜单 IA 逐窗求值核对 + shell 测试族迁移
  （WorkspaceHostView AX 断言族、ToastFaceTests、SheetEnvironmentInjectionTests）。
- 波 3：回切 flag + 走查专项卷（SHELL-05）复走。
- UI 对标代价：Alcedo = 单窗三段布局；独立编辑器窗偏离对标 IA（返回图库 =
  关窗）。**「结构终案」的代价面，非免费。**

### 2.4 裁定建议

**不作为主修**；作为「结构终案备选」挂账。行使触发条件（满足其一）：
①案 C 三形（C3/C1/C2）scratch 实验全数不达 <10% 硬门；②案 C 落地后
27.x 系统更新环复燃且减树再无效；③用户明确偏好窗拆 IA（代价知情）。
scratch 实验门成本（半天级）可在案 C 实验批顺带采（同批两实验）。

---

## 3. SHELL-03 — 菜单环燃料面减频测绘

### 3.1 燃料面清单（file:line）

| 燃料面 | 位置 | 每 pass 成本 |
|---|---|---|
| `visibleMenuCommands` getter | LightamerApp.swift:468-472 | 读 `focusedWorkspace?.phase`（@FocusedValue 图依赖边 ×1）+ 纯函数求值 |
| Commands 块全量重建 | :1502-2241 | ~41 Button/Toggle/Picker + **29 个 keyboardShortcut**（重挂 = swift_getTypeByMangledName 热帧，sample 147-180 hits） |
| 动态 ForEach ×2 | :1544-1553（legacy recentSessions）/ :1586-1593（recentProjects） | 每 pass 菜单项重建（id 稳定，重建成本中等） |
| 焦点写点 ×5 | ContentView :287-288（legacy 双写）/ :228（gate=false 单写）/ WorkspaceHostView :170 / InspectorView :1 处 | **PropertyList.prependValue 每 pass 无去重逐个落盘**（sample 21-37 hits） |
| disabled 条件读状态 | Commands 块各处 | focusedWorkspace/libraryProjects/sessionState 图依赖边若干 |

### 3.2 减频候选（Apple 侧无补丁前提 = 不动框架，只削 app 侧每 pass 工作量）

1. **焦点写点合并（最高收益）**：5 处 `focusedSceneValue` 发布 → 1 个
   carrier struct 单 key（携带 workspace model 引用 + columnVisibility/
   exportPanelRequest/metadataFieldFocused 三 binding）——每 pass
   prependValue 调用 5→1（-80%）。注意：Equatable 值去重**已证无效**
   （D-FIX2-1 裁断读数：同引用重写照样失效——`PropertyList.prependValue`
   无值去重）；本候选削的是**次数**不是值。`@FocusedBinding` 消费端按
   carrier 字段拆分（机械改）。
2. **keyboardShortcut gate 收窄**：29 个 shortcut 中核对哪些挂在
   gate=false 面不显示的无条件件上（如 `menu_open` ⌘O :1527 无条件）——
   shortcut 修饰符全部移进对应 gate wrap 内 = 直接削重挂热点帧
   （mangled-name 热帧与 shortcut 件数正相关）。
3. **`visibleMenuCommands` phase 镜像断边**：getter 读 focusedWorkspace.phase
   是图依赖——phase 镜像进 app root 本地 @Observable/@State（onChange 同步）
   断开菜单渲染对焦点图的依赖边。收益小（一条边），随批顺带。
4. **菜单件数裁剪（激进档，可选）**：gate=false 面菜单 command 进一步收窄
   （placeholder disabled 件削除）——每件 = 每 pass 一次重建 + 可能的
   shortcut 重挂。涉及 IA 走查，独立裁决。
5. **ForEach 不动**：id 已稳定（\.absoluteString），换 key 无收益。

### 3.3 预期与定位

燃料减频**单独不承诺饿死环**（threshold 决定面在树侧；C1/C2 摘树段饿死
而摘焦点写点不饿死——燃料面不是持续条件的充分削减点）。定位 =
**纯叠加放大器**：降低每 pass 成本 → 与减树叠加提高饿死裕度 + 压低
残余底噪（AppKit 侧 11Hz 族不在此列）。实现全 additive/低风险；
验收 = sample 帧计数可测下降（makeMainMenu/updateMainMenu/prependValue/
mangled-name hits）+ MenuCommandSet 测试族回归（IA 矩阵已有）。

---

## 4. SHELL-04 — 上游通道

### 4.1 APPLE-FB-D6-DRAFT 稿复核（技术准确性逐条）

| 稿面 | 复核 | 裁定 |
|---|---|---|
| Summary "~60 Hz" | 本批复验 = 119 passes/s（ProMotion 120Hz display cycle 锁频）；FIX2 稿面 60Hz = 其测量窗 60Hz 屏 | **建议勘误**：「display-cycle-locked（~60-120 Hz per display refresh）」——与「遮挡断环 = display-cycle 耦合」定性自洽 |
| Summary "~34-51% CPU burn" | 空载/编辑器面静置口径成立；第二路补充数据点：交互后功能态 98-100% | **建议补一句**（interact-after 98-100%），或保持静置口径亦可——两读数均已记录 |
| Steps §5 判别面 | 与 D-FIX2-1 五读数逐条一致（C1/C2/E1-E3/B1-B2） | PASS |
| Steps §6 遮挡开关 | 与第二路 A/B 实验一致（遮挡杀 spin + 解遮不复燃 + 一次点击恢复） | PASS |
| loop 栈文本 | 与 t1-menu-loop-sample / 本批复验 sample 一致 | PASS |
| Additional Notes "@self ~14k/2min" | 本批 ~21k/3min（119/s 同率）——建议补「rate ≈ 1 pass per display cycle, OS/display-independent」 | PASS（可选补强） |
| 附件清单 | 三件 sample/截图 + transcript 按需——本批复验件可增附（m71-editor-transcript.log 头部即判据三的新鲜证据） | 可选增附 |

稿面**无技术性错误**；两处措辞勘误建议（60Hz → display-cycle-locked；
CPU 带补 98-100% 数据点）随提交批落。提交动作用户手动（Nitro LUT 先例）。

### 4.2 macOS 27.1 release notes 监测（首轮检索，2026-10-16）

- **读数：公开 release-notes 通道尚无 macOS 27.1 专页**（iOS 侧 tracker 注记
  "index still lists nothing for 27.1"；Xcode 27.1 RC / 27.2 beta notes 在案，
  无 SwiftUI menu/property-graph 修复条目命中）。macOS 27.0.1（26A434）
  仍为最新 released build——与本批复验环境一致。
- 监测节律（GOAL-STATE 巡检义务）：每批次/系统更新发布时检索——信源 =
  Apple Releases 页（developer.apple.com/news/releases）+
  developer.apple.com/documentation/macos-release-notes +
  Mr. Macintosh 更新追踪；关键词 = `menu` / `updateMainMenu` /
  `property graph` / `invalidation` / `SwiftUI`。命中即在下一批次复测
  §0 复现配方（三判据原样）。
- 27.1 beta 到手后的实测义务（FB 表单「latest beta?」字段）：
  beta 装机 → §0 配方复测 → 结果回填 FB 稿 + 本文件注记。

---

## 5. SHELL-05 — 走查专项卷测绘

### 5.1 双路七条观察（卷内容正本，复走批逐条对照）

| # | 观察 | 源 | 复走面 |
|---|---|---|---|
| 1 | churn 可见性门控（遮挡态 0.7% vs 可见窗 34%） | 第一路 §四.4 | 案 A/B 落地后复测：可见窗空载面应 <5% |
| 2 | legacy 菜单点火适用域（带图会话 41.5% vs 空面 0.0%——分歧记录双载） | 第一路 §四.4 / 第二路 §5.2.4 | 点火条件 =「菜单环 × 面内容复杂度」假说——减树后带图面复测 |
| 3 | 点击表型输入路径混淆（AXPress 零响应 vs cliclick 3/3 响应） | 第二路 §5.2.3 / 执行批 probe-11 | **双通道对照义务**：filmstrip/多选一律 AXPress + cliclick 双通道复测定表型边界 |
| 4 | 遮挡杀 spin + 解遮不复燃 + 一次点击恢复 | 第二路 §5.2.1/5.2.2 | 修后回归（workaround 文档化行为是否变化） |
| 5 | idle 反证（legacy 面 idle 0.1% = 非任意树触发） | 第一路 §5.1 | 定性措辞维持（H2 精确定性） |
| 6 | 41.5% legacy 会话面（带图）菜单挂开态点火 | 第一路 §四.4 | 同 #2 |
| 7 | churn 三面 34-98%（空载 23-34% / 编辑器静置 42-87% / 交互后 98-100%） | 三路汇总 | 修后复测基准带 |

### 5.2 复走波行集总表

| 波 | 行集 | 源挂账 |
|---|---|---|
| 复走波 1（屏面四项） | V2M-T1-02（追色 solve 屏面）/ D3-01（filmstrip 换图）/ D4-01（合并对话框三计数）/ D5-01（toast Int 化） | V2M-VALIDATION §挂账② |
| 复走波 2（m6-closeout Blocked 余行） | M6C-03/05/06/07/08（追色族）+ 16-19（pano）+ 32/33（无人像 toast/羽化三档）+ 34-38（栈面）+ 40（guided filter） | V2M-VALIDATION §挂账②硬义务 |
| 复走波 3（FIX2 挂账④） | 点击表型双通道对照（filmstrip + cmd+click 多选；AXPress vs cliclick） | FIX2-VALIDATION §挂账④ |
| 复走波 4（FIX2 挂账⑥） | 导入零行间歇（grid 刷新迟到族）**专项修后复测再裁**——本批已再采 1 例（§0.4.1）；若 churn 消失后表型消解 = 随之销账，否则独立待研立项 | FIX2-VALIDATION §挂账⑥ |
| 代码缝（FIX2 挂账⑤） | 探针缝 `exit(0)` 兜底——**触 WorkspaceHostView DEBUG 缝时顺手**（本批不改码；落 plan 顺手窗） | FIX2-VALIDATION §挂账⑤ |
| H2 措辞 | 「macOS 27 SwiftUI 菜单/焦点更新机制在特定树形〔重树 + `.inspector` 分栏宿主 + 三段内容〕下不收敛」 | 双路共识措辞（引用不重写） |

### 5.3 cmd+click 判死 harness 替代方案预研（挂账④的通道面）

- **先例核**：T3 配方已证 `cliclick dc:` 真实鼠标双击可达（会话双击进编辑器，
  MANIFEST FIX2-01 节「System Events 双 click at 不成双击」）——CGEvent
  真实鼠标路径在本机走通。
- **cmd+click 配方**：`cliclick kd:cmd c:x,y ku:cmd`（修饰键按下 → 真实单击
  → 修饰键抬起）；双击变体 `cliclick kd:cmd dc:x,y ku:cmd`。坐标从
  AX `AXPosition`+`AXSize` 求中心（复走批脚本化）。
- **AXPress 对照腿**：同一格 `osascript … click`（AXPress 合成路径）——
  两通道结果并列记录（响应/不响应 × 通道 × N≥3 重复）定表型边界
  （AXPress 伪象 vs 间歇真死）。
- 本批复验配方新增钉（§0.4）：zh 菜单名寻址 / script 封装 pid 陷阱 /
  PTY 行缓冲——复走批 harness 脚本以此三条为前提。

### 5.4 验收形态（REQUIREMENTS M7-1 行原文兑现）

- D-6 复现配方 churn 探针转绿：三判据（§0 原样配方）在修后 build 上
  复测 = CPU 硬门 <10% ✓ + 稳态 transcript 零重估（10s 窗 0 行）✓ +
  sample 环符号消失/降底噪 ✓ + **回切 flag 对照判别力**（flag off =
  复现 34%/82%，证明转绿是修法效果非环境漂移）✓。
- 走查复走行集逐行销账或如实登记 ✓；FB 案号登记 ✓（用户提交后回填）。
- SC 数字门 = 本 phase 终验全套轮判定式兑现（`--all` 批准制 + 8G 门）。

---

## 6. 主修路线裁定建议（推荐序 + 组合）

### 6.1 推荐序

1. **第一刀 = 案 A + 案 B 合并「空载面零 churn 包」**（SHELL-01 最小案）。
   依据：C1/C2 饿死性**已证**（不确定度最小）；功能损失 ≈ 0（banner/toast
   座移 + 列自绘）；结构身份风险低（无 @State 翻转；M3-4-01 T4 挂载语义
   逐字迁移 + AX 断言族随迁）。产出：空载/图库面 23-34% → 目标 <5%
   （含 AppKit 底噪注记）。**这一刀同时是后续所有实验的判别力基座**
   （`shell.reducedTree` flag 回切 = 对照臂）。
2. **第二刀 = 案 C 的 C3 形 scratch 实验门先行**（零功能损失重组形）。
   scratch build + E 系等效读数（编辑器面 CPU + transcript + sample）：
   饿死 → C3 落地（零损失主修）；不饿死 → C1/C2 形呈报用户裁决
   （功能损失知情），或按 6.1.3 行使窗拆实验。
3. **第三刀（条件行使）= SHELL-02 窗拆 scratch 实验门**（与 C3 实验同批
   顺带采数，半天级）；行使落地仅在 ①C3/C1/C2 全数不达 <10% 硬门或
   ②用户知情偏好窗拆 IA。L 级量化（§2.3）后独立立项波次。
4. **SHELL-03 燃料减频全程叠加**（焦点写点合并 + shortcut gate 收窄 +
   phase 镜像断边）——不独立成波，随任一主修批顺带；独立验收 =
   sample 帧计数下降可测。
5. **SHELL-04 全程持续**：FB 提交（用户手动；稿勘误两处随批）+ 27.1
   监测节律入 GOAL-STATE 巡检。
6. **SHELL-05 复走波殿后**：主修落地后复走才有意义（挂账⑥ 复测亦依赖
   churn 消失——推荐案 A/B 落地后即做第一轮复测，不等案 C）。

### 6.2 每路线验收铁条草案

| 路线 | 铁条 |
|---|---|
| 案 A+B | ①图库/空载面可见窗 CPU <5%（10×1s ps）；②transcript 稳态零 scene-body tick（10s 窗 0 重估）；③flag 回切对照 = 复现 23-34%（判别力）；④功能走查：toast 通道（D-26 4s auto-clear + AX `status_toast`）+ 只读横幅（AX `shell.readonly.banner`）+ M6-1 冲突对话框面；⑤AppKit 底噪注记（~11Hz 族不判 FAIL，记录口径） |
| 案 C3（或 C1/C2） | ①编辑器面 CPU <10%（SC 硬门原样）；②spin 消失铁条原样：filmstrip 点击出图（cliclick 真实鼠标）+ 视口渲染 + 右栏 mount 三步；③transcript 稳态零重估；④AX/cliclick 双通道对照（挂账④）；⑤布局走查（若 C1/C2：Alcedo IA 偏离逐项用户可接受声明） |
| SHELL-02（若行使） | ①编辑器窗 CPU <10%（同上硬门）；②多窗生命周期走查（⌘E open/⌘W close/焦点链/多屏 WindowCapture 跟窗/EDR 视口四态）；③主窗图库面同案 A+B 铁条；④shell 测试族全绿迁移 |
| SHELL-03 | ①sample 帧计数下降可测（makeMainMenu/updateMainMenu/prependValue/mangled-name hits 前 vs 后）；②MenuCommandSet IA 矩阵测试族全绿；③菜单全量手动走查（command 可用性矩阵） |
| SHELL-05 总口 | 三判据探针转绿 + 复走行集逐行销账/如实登记 + FB 案号登记 + 终验全套轮判定式（批准制） |

### 6.3 理由链

①C1/C2 已证 = 最小不确定度第一刀；②C3 零功能损失 = 第二刀免费期权；
③窗拆不确定性最大 + L 级最重 + 饿死性偏悲观（§2.2 C1 反证）= 终案/兜底；
④燃料减频纯叠加；⑤FIX2「先探针定罪再动手」纪律延续——每刀带 scratch
实验门 + 回切 flag + transcript 判据，防三改。

---

## 7. Open Questions（OQ-M7-1-*，每条带推荐）

| # | 问题 | 推荐 |
|---|---|---|
| OQ-M7-1-1 | 案 C 功能损失裁决：若 C3 重组 scratch 不饿死，是否接受 C1（右栏并入 inspector 列，偏离 Alcedo IA）/ C2（filmstrip 收弹出层，常驻性损失）？ | 先跑 C3 实验；不饿死时 C1/C2 **呈报用户二选一**（不默认——两形均有真实 UI 对标损失），窗拆实验数据并列呈报 |
| OQ-M7-1-2 | SHELL-02 窗拆在案 C 达标后是否仍立项？ | 不立项——挂账「结构终案备选」，触发条件 = 27.x 更新后环复燃 ∨ 案 C 回归 ∨ 用户知情偏好 |
| OQ-M7-1-3 | FB 提交时机：修法落地前（缺陷全量在）还是落地后（稿面数字会过时）？ | **现在就提交**（用户手动）——缺陷在 27.0.1 全量复现，框架侧修复价值独立于 app 侧减树；提交前落 §4.1 两处勘误 |
| OQ-M7-1-4 | `shell.reducedTree` flag 形态：编译期 `#if` vs 运行时（UserDefaults/env）？ | 运行时 env/UserDefaults（`LIGHTAMER_LEGACY_LIBRARY=1` QA 回切通道同款先例）；默认 = 减树形态开；flag 名登记 UserDefaults 键族 |
| OQ-M7-1-5 | 挂账⑥（导入零行/grid 刷新迟到）复测时机 | 案 A/B 落地后即复测第一轮（空载 churn 消失可能已解除 main-actor 饥饿面；不等案 C）；两轮间歇复现才立项独立待研 |
| OQ-M7-1-6 | 案 B 的 inspector 列宽度交互：自实现拖拽 vs 钉死 ideal 240？ | 首批钉死 240（`layout.inspectorWidth` 记忆键保留读取、ideal 应用），拖拽自实现挂账后续批——最小化第一刀面 |

---

## 8. Sources / 证据指针

- **本批复验证据（local-only 域，不入 git）**：`.work/gui-acceptance/m7-1/`
  —— `m71-editor-transcript.log`（64,094 行 PTY transcript，判据三正本）/
  `m71-editor-sample-head.txt`（6s sample，判据二正本）/
  `m71-six-symbols.txt`（符号计数）/ `m71-idleface-cpu.txt` +
  `m71-editorface-cpu-clean-build.txt`（判据一 CPU 系列）/
  `m71-d6-editor-state.png`（D-6 态截图：三段布局 + 空态卡 +
  filmstrip 占位——与 FIX2 acc-d6-editor-state.png 同型）/
  `m71-probe-run-gridlate-fail.log`（挂账⑥ 再现轮日志）。
- **定罪正本**：`phases/fix2-defects/FIX2-01-DECISIONS.md` D-FIX2-1 +
  `FIX2-VALIDATION.md` §挂账①④⑤⑥ + 两 ACCEPTANCE 七观察 +
  `gui-acceptance/v2m/fix2-probe/`（FIX2 证据域）。
- **FB 稿**：`research/APPLE-FB-D6-DRAFT.md`（§4.1 两处勘误建议落点）。
- **需求族**：REQUIREMENTS SHELL-01..05（M7 站 charter 2026-10-16）+
  ROADMAP §M7-1 行。
- **macOS 27.1 监测首轮信源**（2026-10-16 检索）：Apple Releases
  （developer.apple.com/news/releases）/ macOS release notes
  （developer.apple.com/documentation/macos-release-notes）/
  Xcode 27.1/27.2 beta notes / Mr. Macintosh 27.0.1 追踪页。
- **插桩配方备案**（§0.3，下批复用）：三文件锚点 =
  ContentView.body 首行 / WorkspaceHostView.body 首行 /
  LightamerApp.body 首行；`let _ = Self._printChanges()`（ViewBuilder
  语境必须 `let _ =` 形——裸语句编译错）；PTY = `script -q <file> <app>`；
  回退 = `git checkout -- <三文件>`。
