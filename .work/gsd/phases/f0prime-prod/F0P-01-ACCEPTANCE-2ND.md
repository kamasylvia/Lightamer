# F0P-01-ACCEPTANCE-2ND — P1（壳交接翻转）第二路独立验收（对抗错位切入）

> 验收窗：2026-10-19 11:31–12:30（单 lane，与第一路并行，标记文件协调错峰）。
> 对象：执行链 `907c373d..ef312a2a` 九 commits，主树 HEAD = `ef312a2a`（P1
> 收口）✓。攻击位：壳交接 = lifecycle 级变更，专攻「翻转后坏掉了什么」。
> 零源码改动；全部构建/运行在独立 worktree `/tmp/f0p1-acc2nd-wt` + 独立
> DerivedData `/tmp/f0p1-acc2nd-dd`（L0xx-b/L0xx-d）；长任务 nohup+disown；
> 只杀自出 PID；GUI 活动标记 `/tmp/la-f0p1-acc2-gui.active` 已按 orchestrator
> 补充纪律放置并在收尾删除。

## 0. 结论头

**FAIL / 1 blocking + 2 major + 0 minor + 4 obs**

- **blocking-1（翻转回归确证）**：三窗控制器渲染空白——Settings…（⌘,）/
  预设管理器 / MCP Agent 启动器三窗出现但 content 永远空白。根因代码级
  定位 = `ShellWindowControllers.swift` 三处同形
  `if window.contentView == nil`（NSWindow init 后该 getter 惰性创建默认
  view，guard 恒 false → NSHostingView 永不挂载）。pre-flip Settings
  scene 以同一 env 集正常渲染 = 翻转回归。三窗生产化是 T4/T6 的 P1 承诺
  面（T6 SC「Settings ⌘, 真窗控制器」+ D-F0P-1），第一路面 10-13 归 P2
  未走查故第一路未发现。**C 档停位下 P2 起跑前必修**（一行级修法：去掉
  guard 或以已挂载标志判别）。
- **major-1（既有缺陷，非翻转回归；台账勘正项）**：标记应用链断——
  rating/color 菜单点击 + ⌘1 键盘双路 × 两实例，UI（filmstrip 无色标点）、
  sidecar（零写）、DB（rating/color_label 全空）三重判据全零；
  **pre-flip 对照同断**（revert 态构建亲测）= 既有缺陷。第一路 MANIFEST
  面 7「4 星 + 红(⌘1) 应用 ✓ = 元数据写脸 + 条纹刷新链活」判定不实：
  `w07-rating-color.png` 中唯一「点」为选中指示蓝点，且未做落盘核对——
  face 7 的 ✓ 应降级，P2 面走查判定基线须勘正。
- **major-2（归属不明，HEAD 态功能缺陷）**：export 页「加入选中 (1 张)」
  按钮 action 失效——AX hit-test 精确命中该元素 + AXPress err=0 +
  CGEvent 点击命中 + 干净 destination + 两实例 × ≥3 次尝试：队列零变化、
  产物零、零错误反馈。同页格式 PopUpButton 点击活、filmstrip 行点击活、
  滑杆拖动活 = 失效特定于该 Button action 链。pre-flip 对照未完成（
  pre-flip 菜单导出路由在探针宿主不达页 = 既有行为差异），翻转回归与
  既有缺陷二选一未决。
- **壳交接核心目标独立复现成立**：HEAD 态编辑器静置 churn 中位
  **0.0%**（6 采样全 0 + L082 四哨全过 + 主线程 4641/4641 泊
  `LightamerShellMain.run → NSApplication.run → mach_msg2_trap`）；图库
  静置（无项目态）**0.0%**；revert 态对照 **99.9%**（pre-flip 带）——
  churn 载体因果闭环。菜单权威（七族 dump 与第一路 A 臂逐项 parity）、
  编辑主链（⌘E/⌘W 双向、undo/redo 环、copy→paste 使能翻转、滑杆 live
  重渲染）、翻转原子性（完整 revert 流程补测闭合）全数成立。

## 1. 面 1 — 行为级全 GUI 走查（真构建 spawn）

构建：worktree @`ef312a2a` + `tuist generate` + `xcodebuild`（独立
DerivedData）BUILD SUCCEEDED；二进制 strings `LightamerShellMain` 在位。
plain 启动 + `-la_editor_probe /tmp/nsmenu-spike-fixtures
-la_probe_stay` 探针实例共 3 个（自出 pid 全部显式回收）。

### ✓ 成立项（逐项亲测）

| 项 | 结果 | 证据（`/tmp/f0p1-acc2nd/`） |
|---|---|---|
| 启动面 + 桥菜单栏 | 九项上屏（Apple/Lightamer/File/Edit/显示/标记/图像/Window/Help） | wt/a01-launch.png |
| 七族菜单 AX dump | File 18 行 / Edit 22 行 / 显示 17 / 标记 16 项整 / 图像 2 / Window+Help 系统族完整；键、修饰、enabled 逐项 | wt/ax/*.txt |
| File 菜单 parity | 与第一路 A 臂 dump（`probe/logs/ax-menu/A/menu-文件.txt`）逐项逐键逐 mod 同构 | 本路 wt/ax/menu-File.txt 对照 |
| export 使能修正 | 导出… launch 态 enabled=true（D-F0P-01-5.2 恒 enabled 行为级实证） | 同上 + A 臂 `导出… enabled=true` 亲核 |
| ⌘E / 返回图库 双向 | 相位翻转 ✓（编辑器面逐像素复现 b01） | ed/b01/b02/b03 |
| 图库 | 真缩略图 + EXIF 分组 inspector + 选中态 | ed/b02-back-to-lib.png |
| 编辑器渲染 | RAW 解码上屏 + 影调面板 + 直方图 + 色温滑杆 | ed/b01-editor.png |
| undo/redo 使能环 | 编辑后 撤销=true/重做=false → undo → redo 翻转 ✓ | wt/ax4 / ax5 |
| copy→paste 使能翻转 | 复制调整 → 粘贴调整 enabled=false→true + 部分粘贴 true 实时 | wt/ax3 vs ax2 |
| 滑杆拖动 live 重渲染 | 6504K→25000K，视口多点像素证实变化（md5 变） | ed/c01/c03 |
| Export 页 ⇧⌘E 全装配 | 五节 + 11 token + 命名冲突 + DRT readout（rec709·gamma_2_2·100 nits）+ 格式 popup 六格式实测弹出 | ed/b04/b11 |
| 双实例 | 两实例（HEAD 态 + revert 态）并行跑无崩溃 | 48685+50352 并存段 |
| 关窗即退出 | applicationShouldTerminateAfterLastWindowClosed=true 经组合 delegate 生效 | 关窗 → 进程消失 |
| 标记菜单 16 项 | dump 全 enabled；快捷键 ⌘0-6/bare/P/X 在位 | wt/ax/menu-标记.txt |

### ✗/◑ 发现项（详见 §6 分级）

- 三窗空白（blocking-1）；标记链断（major-1）；export 按钮 action 断
  （major-2）。
- 侧栏/Inspector toggle（⌥⌘S/⌥⌘I + 菜单双路）：默认 M2 面无布局效果
  ——**代码链证明 pre-flip 同为 no-op**（pre-flip `toggleSidebar()` guard
  focusedValue 缺席即 return，LightamerApp.swift:2701-2711；ShellGraph
  消费者只在 legacyBody binding 桥）= **非回归**，1:1 parity 保持。
  legacy face（env=1）桥活未测（回切通道，超本窗）。
- Dock reopen（D-F0P-4）：隐藏态发 AppleEvent reopen 未恢复窗——
  **证据力不足未定案**（osascript reopen 不含 unhide，系统语义允许不
  恢复；真实 Dock 点击路径本窗未测）→ obs。
- 全屏：Window 菜单「进入全屏幕」在案 + `.fullScreen` styleMask 代码
  在位（引用第一路 w05e dump）；未实测进入/退出全屏。

## 2. 面 2 — churn 与性能（L082 四哨全程）

| 轮 | 二进制 | %cpu 六采样 | frontmost | 主线程泊 | churn 符号族 |
|---|---|---|---|---|---|
| 编辑器静置 r1 | HEAD 构建 | **0.0 全 0** | true | 4641/4641 mach_msg2_trap（`LightamerShellMain.run` LightamerShell.swift:2366 → `NSApplication.run`） | 全 0 |
| 图库静置（无项目态） | HEAD 构建 | **0.0 全 0** | true | — | 全 0 |
| revert 态对照 | revert+generate+build | **99.9 中位**（94.0/99.5/100.0×3/99.9） | true | `main → LightamerApp.main` 路径 | sample 6s 窗符号未展开（obs：窗短；CPU 带已足裁决） |

- 编辑器 0.0 独立复现第一路 B-r1..3 ✓；图库静置数字留档（翻转前图库
  ~30% 带 → 翻转后 0.0，预期降带兑现）。
- 导出真跑未闭合（major-2）——导出轮 churn 无数据。
- L082 纪律：一切读数前 `set frontmost` 先行 + 复验；符号总量跨行求和；
  parentage 行随 meta。本路一次方法论事故（ImageChops RGBA bbox 误报
  「滑杆零变化」）被 md5/多点像素复核当场纠正——**GUI 帧对比判据 =
  md5/像素采样，禁用单通道 bbox**（建议入 LESSONS）。

## 3. 面 3 — 翻转原子性攻击

1. **恰三产线文件** ✓（`git show 752c5294 --stat`：ContentView 15 行 +
   LightamerApp 15 行 + LightamerShell.swift 2368 新建）。
2. **两小文件逐行审**：无夹带。ContentView = openWindow 摘除 +
   `ShellGraph.shared.presetManagerRequested` 写字段（review M1 修复
   形）；LightamerApp = entry 尾 swap（fork 序逐字零触）+ WindowCapture
   private→internal 恰一词。
3. **LightamerShell.swift vs spike 机械变换忠实度**：名字归一化 diff =
   219 行实质差异，**全部对应已申报偏差**（D-F0P-01-1 graph 单源 /
   -2 Deps 三改形 / -5.2 export fork / -6.1 presetManagerRequested
   onChange / -6.2 face 四属性）——零未申报差异。
4. **revert 干净应用**（git 层：M/M/D 无冲突）✓（复现第一路申报）。
5. **完整 revert 流程补测（第一路未测）**：revert → `tuist generate` →
   build = **BUILD SUCCEEDED**。⚠️ 流程注记：revert 后**必须**
   re-generate——陈旧 pbxproj 直接 build 报
   「Build input file cannot be found: LightamerShell.swift」（glob 源
   枚举时效性）；HEAD 态回切同理。第一路 T7 申报只覆盖 git 层。
6. **revert 态行为级**：churn 99.9%（pre-flip 带）+ Shell 符号离场
   （strings LightamerShellMain=0 / nm lightamershell=0；
   NSMenuBridgeController 符号在 = HEAD 基线 inert 文件属预期，与第一
   路 A 臂 907c373d 无桥符号的口径差异如实注记）。
7. **硬序** ✓：T2 `cb31d0ba` → T3 `ffa4d583` → T4 `cc449ecf` → T5
   `1aa9ff36` → chore `ff94f9c7` → T6 `752c5294` → T7 `fb4a5728`（git
   log 时间戳面核）。

## 4. 面 4 — AX/辅助功能

- AXPress 抽验 **15 项**（超 10 项门）：Settings、预设管理器、MCP
  launcher、显示侧边栏、进入编辑器、返回图库、导出…、复制调整、粘贴
  调整、撤销、重做、4 星、红(⌘1)、格式 popup、加入选中——NSMenu 全活。
- shortcut 实测：⌘,（真窗）/⌘E/⌘W（菜单路由双语义）/⇧⌘E/⌘1 键盘/
  ⌥⌘S 键盘+菜单双路/⌘Q 族（Quit + ⌥⌘Q 退出并保留窗口在 dump）。
- **⇧⌘O 口径澄清**：library 域 File 菜单实为 **⌥⌘O Open Project…**
  （pre-flip `LightamerApp.swift:1883` 同款 1:1）；bridge 的 ⇧⌘O
  `menu_open_session`（NSMenuBridge.swift:302-305 + openSessionPicker
  缝，review M4 修复形代码亲核在位）属 Session 域 gate
  （`visible.contains(.sessionOpen)`），默认面不显示。任务书「⇧⌘O
  picker」与产线默认面的偏差如实记录——非缺陷。
- AX identifier 面：pyobjc 深遍历（14 层）逐个命中 `zoom.hud.*` /
  `inspector.row.*` / `inspector.slider.temperature.kelvin.slider` /
  `export.page.*` / `export.queue.*` / `export.naming.token.*` 全族
  ——D-F0P-01-3 迁移集落实 ✓。
- zh/en 差异（D-F0P-01-5.4）亲证：本路 B dump = File/Edit/Window/Help
  英文组名 + zh 自定义族；pre-flip A 臂 dump = zh 系统组（文件/编辑）
  ——登记一致。
- VoiceOver：以双通道 AX 树完整性（osascript + pyobjc）代偿抽验，未开
  真实 VoiceOver 会话（超窗）→ obs。

## 5. 面 5 — 台账对抗

- **probe logs 存在性 + 数据一致性** ✓：`B-r1..3` + `B-prefix-r1..3`
  三件套齐全；median/frontmost/symbols/parentage 与 SUMMARY 申报逐值
  一致；B-r1 screen.png 亲核 = 编辑器面完整渲染 + 桥菜单栏。
- **偏差①-⑤逐项核** ✓：①MANIFEST `f0prime-p1/` 存在 + `.gitignore`
  政策行在案；②`ff94f9c7` = 3 行注释替换（selector 字面规避）；
  ③`fb4a5728` diff 亲核 = enabler `{ true }` + 读集 19→17（两 export
  presence 读退役）+ A 臂 dump `导出… enabled=true` 证据亲核；④face
  四属性 + ShellGraph 第 11 字段 = T6 diff 亲核；⑤DEBUG trace grep
  零残留。
- **面 5/9 归因论据亲核** ✓：`routeLocksZoom(.crop)=true`
  （EditorAreaView.swift:394-398，13-3 T3 设计锁）；soft proof laState
  代码在位（NSMenuBridge.swift:459-469）——两 ◑ 归因成立。
- **AC 承接抽查**：zcode 路 ≥4 ✓——M1（plan T6 action 5 + T6 diff
  兑现）/ M2（T4 DECISIONS 先行步 + `ShellGraph.shared` 落地）/ M3
  （CONTEXT 转写勘误③ + F0P-02-PLAN:120）/ M4（T3 openSessionPicker +
  `recentSessions.first` 零命中机检 + T6 diff）。omp 路 ≥4 ✓——
  OMP-M1/OMP-M2（F0P-03-PLAN requirements 落位行）/ OMP-M3（F0P-02 T1
  树遍历缝 + T3 re-arm 二选一落 DECISIONS）/ m-omp-2（F0P-02 T3 SC
  「17 读集逐字段触发」）。
- **OQ 兑现抽查** ✓：D-F0P-5（env 回切门 Shell 域零命中，ProcessInfo
  读全为既有探针参数）/ D-F0P-9（AppDelegate.swift 零 diff）/
  D-F0P-15（`F0PrimeShell` App/Sources 零命中）。
- **台账误判（本路新发现）**：MANIFEST 面 7 ✓ 判定不实（见 major-1）
  ——「元数据写脸」未做任何落盘核对，UI 判据（色标点）实为选中指示
  蓝点。

## 6. 分级清单

| 级 | 项 | 翻转归属 | 修复路由 |
|---|---|---|---|
| blocking-1 | 三窗控制器渲染空白（Settings/preset-manager/MCP launcher；`ShellWindowControllers.swift` 三处 `if window.contentView == nil` 恒 false） | **翻转回归确证**（pre-flip scene 同 env 正常） | 回注执行方：P2 起跑前必修；一行级（去 guard / 已挂载标志） |
| major-1 | 标记应用链断（rating/color/flag 菜单+键盘双路零效果；sidecar/DB/UI 三重零） | **既有缺陷**（pre-flip 对照同断） | 停手上报既有缺陷队列；MANIFEST 面 7 勘正 ✓→✗；P2 走查面 7 判定基线勘正 |
| major-2 | export「加入选中」action 失效（hit-test 命中 + press 成功返回 + 队列/产物/反馈三零） | **未决**（pre-flip 对照不可达——pre-flip 菜单导出不达页为既有差异） | P2 首批归因（makeRunAssembly guard 维度 / enqueue typed 拒绝面 / hosting 桥 action 投递）；本窗零源码改动未动 |
| obs-1 | revert 后必须 `tuist generate`（陈旧 pbxproj 直接 build 断）——完整 revert 可行性由本路补测闭合 | 流程注记 | plan P2/P3 revert 演练配方补一句 |
| obs-2 | ⇧⌘O `menu_open_session` 属 Session 域 gate，默认面不可见（默认面 = ⌥⌘O Open Project…） | 任务书口径偏差 | 无行动 |
| obs-3 | Dock reopen AppleEvent 隐藏态未恢复窗——证据力不足（reopen ≠ unhide 语义） | 未定案 | P2 以真实 Dock 点击补测 |
| obs-4 | VoiceOver 真会话未开（AX 树双通道完整性代偿）；GUI 帧对比禁用单通道 ImageChops bbox（本路一次误报被 md5 复核纠正） | 方法学 | 建议入 LESSONS |

## 7. 分歧清单（vs 第一路结论）

1. **face 7 判定**：第一路 ✓ ↔ 本路 ✗（三重落盘判据 + pre-flip 同断 +
   w07 证据误读）——本路判据成立，第一路冒烟级未做落盘核对。
2. **走查覆盖面**：第一路面 10-13（三窗）归 P2 未走查 ↔ 本路按任务书
   「⌘, Settings 真窗 + preset-manager 窗」重点攻击抓出 blocking——
   P1 承诺面（T4/T6 SC）内的行为级回归不应以「P2 范围」豁免。
3. **其余全数一致**：D-6 探针门 0.0/0.0/0.0 独立复现 ✓；A 臂 96 带
   revert 对照 ✓；菜单 parity ✓；偏差①-⑤ ✓；AC 承接 ✓；翻转原子性
   ✓（本路加测完整 revert 流程）。

## 8. 还原核验

- 全机 Lightamer 进程 **零残留**（自出 pid 44193/44491/48685/50352 及
  探针轮全部显式回收）。
- 主树零触碰（全部 git 写操作在 worktree）；worktree `git revert
  --abort` 回 `ef312a2a` detached + 最终 `tuist generate` 恢复 pbxproj
  一致态。
- defaults：`library.ai.labelingMode` 已删（原 UNSET）；
  `export.lastDirectory` 遗留 `/tmp/f0p1-acc2nd/out`（本路写值，
  /tmp 即弃域，无害保留）；GUI 活动标记已删。
- 遗留构建产物：`/tmp/f0p1-acc2nd-wt`、`/tmp/f0p1-acc2nd-dd`、
  `/tmp/f0p1-acc2nd/`（即弃域，P2 复测可按同配方重建）。
