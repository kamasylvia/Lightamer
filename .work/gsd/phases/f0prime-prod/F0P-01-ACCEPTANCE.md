# F0P-01-ACCEPTANCE — plan P1（F0P-01）第一路独立验收（plan 忠实路线）

> **PASS / 0 blocking + 0 major + 2 minor + 4 obs。**
> 验收对象 = F0P-01 执行链 `907c373d..ef312a2a`（主树 HEAD = P1 收口
> commit `ef312a2a` 亲核 ✓）；方法 = 零源码触碰 + 逐任务验收标准机检
> （grep / git show --stat / worktree revert 复跑）+ D-6 探针独立复测
> （本验收轮自建二进制三轮）+ 红线电池 15 条亲跑 + 定向测试两域 + 双
> 复审 AC 承接抽查（zcode 11/13 + omp 9/13，均 ≥4 达标）。
> 验收环境：主树 HEAD 不动；构建 = 主树 HEAD `build-for-testing`（增量，
> TEST BUILD SUCCEEDED，二进制 strings 亲证含 NSMenuBridgeController +
> LightamerShellMain 壳符号）；worktree `/tmp/f0p1-acc-revert`（已还原
> 移除）；探针证据 = `probe/logs/acc-r{1,2,3}/`；探针窗与第二路 GUI 错
> 峰（锁协议 `/tmp/f0p1-acc-lane1.lock` + ps parentage 亲核，探针轮期
> 间零他路 Lightamer 实例）。

## 0. 结论头

**PASS / 0 blocking + 0 major + 2 minor + 4 obs**——plan F0P-01 全任务
（T1..T7）按验收标准逐条机检通过；D-6 绝对门独立复测 **0.0/0.0/0.0**
（<10% 判据余量 90pp）+ L082 四哨兵 3/3 全过；翻转 commit 独立可
revert 复跑干净（翻转树 revert 后与翻转前父树 **逐字节** 相等）；红线
15 条全亲核通过；定向测试零回归（App 921/6/0 两轮同值 + Editor·
viewport 54/0/0）；ΔN +0 与申报一致；偏差①-⑤逐条判等价终形成立。
2 minor 均为证据/措辞面（不触行为），4 obs 含两条可机检读法建议。

## 一、逐任务判定

| 任务 | commit | 判定 | 机检证据（本轮亲跑） |
|---|---|---|---|
| T1 probe-stay hunk | `907c373d` | **✓** | `git show --stat` 恰 1 产线文件（WorkspaceHostView +10）；`la_probe_stay` App/Sources 恰 1（:1844）；hunk 与 patch 0001 **byte-identity**（同 blob index `a491acf7` + hunk 体逐字）；全 body 在 `#if DEBUG` 探针函数域内 |
| T2 缺口1 zoom 构造参数化 | `cb31d0ba` | **✓** | 恰 2 产线文件；updateNSView 函数体内 `viewportState.(zoom\|pan\|rotationDegrees)` 零命中；EditorAreaView body `ZoomSignature(` 恰 1（:98 构造点）；push-once 比对臂原样（EditorMTKView :146-147）；`let _ = viewportState` 全仓零（m8 门）；diff 亲读 = 手势路径/ZoomHUD 零触（仅构造参数 + 比对臂注释） |
| T3 缺口2 bridge 生产形 | `ffa4d583` | **✓** | 恰 4 产线文件；`.onChange(of: exportPanelRequested)` 双态注入恰 1（ContentView :275）；onAppear 一次性形零命中；B19 onChange（InspectorView :434-437）+ B20 onAppear（WorkspaceHostView :201-203）逐字落位；`NSMenuBridgeController` 恰 1 文件定义；`recentSessions.first` 桥内零（含注释）；McpServerController 零 diff；`.runModal(` / 插值禁形零；**inert 时序亲证**：`ffa4d583` 时 `install(deps` 全 App/Sources 恰 1 命中 = 定义体零调用点；翻转后激活点 = LightamerShell :2000——形态变化由 plan 结构（T3 inert → T6 激活）+ DECISIONS D-F0P-01-2/6（Deps 接线终形）申报，无缺口 |
| T4 缺口3 四 stub 生产化 | `cc449ecf` | **✓** | 恰 3 产线文件 + DECISIONS 先行步（review M2 三选一 = (a) `ShellGraph.shared` 单例，D-F0P-01-1 落位）；`final class ShellGraph` 恰 1；字段 11（spike 9 + columnVisibility :54 + presetManagerRequested :62——第 11 字段 = 偏差④申报）；三控制器类各恰 1（ShellWindowControllers :28/:62/:86），env 注入面与 HEAD scene 形逐项对齐（presetsStore/presetController + dark + 520×480 / 720×480 / SettingsView(legacyLibraryEnabled:) + catalogPreferences/pipeCoordinator/libraryProjects + dark）；`@State private var columnVisibility` 零；`showSettingsWindow` 零；Project.swift 零 diff |
| T5 toolbar 差异登记 | `1aa9ff36` | **✓** | 零产线 diff（恰 DECISIONS 1 文件）；MANIFEST 卷在 `.work/gui-acceptance/f0prime-p1/`（整域 gitignore :79——偏差① declared，tracked 正本落 DECISIONS D-F0P-01-4） |
| （chore）selector 卫生 | `ff94f9c7` | **✓** | NSMenuBridge 注释 3 行，零代码；保 T6 翻转恰三文件 |
| T6 壳交接翻转 | `752c5294` | **✓** | 恰 1 commit 恰 3 产线文件（LightamerApp 15 行 + ContentView 15 行 + LightamerShell 新建 2368 行）；`F0PrimeShell` App/Sources 零；`LightamerShellMain.run()` 恰 1 调用（:162）+ `_ = { LightamerApp.main() }` 死行保留（D-F0P-01-6.3）；fork 四把逐字（:130-160 面核）；空 stub 闭包零；`setFrameAutosaveName("LightamerMainWindow")` 恰 1；`.fullScreen` 恰 1（:2240，D-F0P-4）；`applicationShouldHandleReopen` 恰 1；willTerminate 转发**调用点**恰 1（:2348，Notification 参数类型面核——m-omp-4 机检读法）；`openWindow` ContentView 零（M1 缝 = :583 写 `ShellGraph.shared.presetManagerRequested` + face :114 onChange 消费复位——同实例）；`private struct WindowCapture` 零（internal 翻转恰 1 处 + doc 注记）；**revert 复跑**：worktree @752c5294 `git revert --no-commit HEAD` → `git diff ff94f9c7` **0 行 = 逐字节回 T5 态**；HEAD 态 revert 干净应用 + abort |
| T7 探针门 + 走查 + 收口 | `fb4a5728`+`ef312a2a` | **✓** | 见 §二（探针独立复测）+ §五（偏差③实测修正证据亲核：A 臂 dump 导出… enabled=true + 桥 :382 `{ true }`）；MANIFEST 冒烟表 1-9/14 逐项记录与 SUMMARY §3 一致（行为级点验归第二路，本路不重做） |

## 二、D-6 探针独立复测（本验收轮自建二进制）

二进制 = 主树 HEAD `ef312a2a` 增量构建（`build-for-testing`，11:20 产
物；strings 亲证壳符号在位）。驱动 = 执行方 `run-one-f0p1.sh` 协议同形
派生（仅日志目录/二进制改）；协议 = `-la_editor_probe
/tmp/nsmenu-spike-fixtures -la_probe_stay` + stay 标记 → 60s settle →
frontmost 先行 → 截图 → 30s 窗 6 采样 @6s 中位 → `sample 6s` 符号总量。

| 轮 | %cpu 中位 | ①frontmost | ②窗内截图 | ③主线程泊 | ④churn 符号族 |
|---|---|---|---|---|---|
| acc-r1 | **0.0** | true | ✓（识图亲验：编辑器面完整渲染——桥菜单栏 + filmstrip + 视口 + inspector 全活） | LightamerShellMain.run → NSApplication.run 泊（4777/4777 样本） | 7 符号全 0 |
| acc-r2 | **0.0** | true | ✓ | 同形泊（4617 样本） | 全 0 |
| acc-r3 | **0.0** | true | ✓ | 同形泊（4635 样本） | 全 0 |

- **绝对门 <10% = PASS**（与申报 0.0/0.0/0.0 独立同值；判据余量 90pp）。
- pid parentage：探针 GUI ppid = 验收驱动脚本进程树（meta.txt 随行）；
  运行窗内零第二 GUI 实例；defaults labelingMode 写入/还原随行
  （acc-defaults-state.txt）。证据 = `probe/logs/acc-r{1,2,3}/` 六件套。
- 执行方 B-r{1,2,3} 留档同核（10:31/10:33/10:34 三轮 0.0 + 四哨兵 + 父
  亲age），与本轮独立互证。

## 三、红线电池 15 条（全亲跑）

| # | 红线 | 本轮机检 | 判定 |
|---|---|---|---|
| 1 | FIX2③ McpServerController 零 diff | `git diff 9a0b9530..HEAD` 该文件 0 | ✓ |
| 2 | 封存面零 diff | 全 diff 文件清单 = 10 个 App 壳域文件（UI/ + UI/Shell/）+ docs；零 LightamerIOP/*.metal/Sidecar/PixelPipe/Drt*/V50Order/GradeCatalog 等 | ✓ |
| 3 | 无 QA 回切（env 门零命中） | `LIGHTAMER_SHELL` 全仓零；壳域 `environment[` 零 | ✓ |
| 4 | 翻转独立可 revert | worktree 双态复跑（§一 T6 行） | ✓ |
| 5 | xcstrings 零 diff | 0 | ✓ |
| 6 | LocalizationValue 禁形 | `String.LocalizationValue("prefix_` 零 | ✓ |
| 7 | disable-not-unmount | AgentControlCoordinatorTests 零 diff（manifest 10 行零触，holdsControl 18 处在位）；桥 enabler holdsControl 读集（:318/:324/:393/:401/:609/:614/:679）+ handleMenu backstop（:712-716） | ✓ |
| 8 | 基线 3969/37/0 口径 | App 分账本轮 921/6/0 = audit-repair `--all` 口径 App 向量逐值同（AR-02-03 vectors）；skip 6 枚举 = perf 探针 3 + depth 包缺席 3（零第三来源） | ✓ |
| 9 | AppDelegate 类字节零改 | 类体 :168-212 @9a0b9530 零 hunk；LightamerApp 全文件仅 2 hunk（entry 尾 + WindowCapture，见 obs-1 读法注记） | ✓ |
| 10 | DEBUG fork 序零触 | entry hunk 仅尾行（四把 fork 逐字面核） | ✓ |
| 11 | L057 `.runModal(` | App/Sources 零 | ✓ |
| 12 | UserDefaults 应用级零新键 | diff 零 defaults 键（autosave = AppKit 出厂系统键豁免） | ✓ |
| 13 | --all 批准制（本 plan 不跑） | P1 窗内零全套轮亲证：/tmp 六 bundle 日志 mtime = Oct 18 21:49-22:10（audit-repair 验收复现轮，先于 P1 首 commit 09:14）；App 轮 = 定向；P2 承接 = F0P-02 T5 等价门 + T6 --all 三轮同值（per-bundle 向量逐值钉 m-omp-8 已回写） | ✓ |
| 14 | C 档停 | SUMMARY/DECISIONS 收口于 ef312a2a；P2/P3 未启动 | ✓ |
| 15 | LightamerShell* 改名 | `F0PrimeShell` App/Sources 零 | ✓ |

## 四、ΔN / 偏差 / 申报核对

- **ΔN = +0 ✓**：`git diff 2ba9393e..HEAD -- Tests/ Project.swift` 零文
  件；带 +0..2 内。
- **全套未跑申报 ✓**：见红线 13；与 P2 计划衔接完整（F0P-02 T5 等价性
  门 + T6 全套三轮同值 + m-omp-8 向量钉）。
- **偏差①-⑤ 逐条判等价终形**：
  1. MANIFEST 路径 + gitignore 政策（.gitignore:79 `.work/gui-acceptance/`）
     ——tracked 正本落 DECISIONS ✓ 等价成立。
  2. chore commit 保翻转恰三文件 ✓ 成立。
  3. **export enabler 恒 enabled（重点亲核）**：A 臂 AX dump 亲读 =
     launch 态「导出… | key=E | mod=1 | **enabled=true**」（plan B17/B18
     形在 launch 态 disabled = 主项 parity 破坏）；修正后桥 :382
     `{ true }`；观察读集 17（11 deps + 5 workspace + 1 metadata note
     盒，armObservation 逐行亲数；export presence 双读退役）；ContentView
     onChange note 写腿保留为 action 路由信号（:275）。授权链 = plan 风
     险节「实测不一致 → 按 1:1 对齐原则修 Deps」+ omp 复审同族语义
     （勘误③「壳侧唯一义务是 parity」）。**等价终形成立**（晨审可翻 =
     DECISIONS D-F0P-01-5.2 已声明翻回形）。
  4. face 四属性（LightamerShell :91-94）+ ShellGraph 第 11 字段（:62）
     ——review M1/m6 缝落形申报完整 ✓。
  5. DEBUG trace 撤除零残留（grep 零 + tracked 树零 diff）✓。

## 五、双复审 AC 承接抽查

- **zcode 13 条抽 11**：M1（:551 缝 = graph 请求字段 + face 消费 +
  openWindow 零命中）✓；M2（ShellGraph.shared 单例 + D-F0P-01-1 三选一
  论证 + face/ContentView/菜单闭包同实例）✓；M4（openSessionPicker 闭包
  缝 + recentSessions.first 零命中机检）✓；m1（读集全实数→T3 落 18→终
  17 演变留痕链完整）✓；m2（标记 16 项——本路源码亲数 rating 6+flag
  3+color 7 = 16 整）✓；m3（CONTEXT「P2 T7」勘正在位）✓；m4（WindowCapture
  SC 行 + 措辞）✓；m5（AX identifier 恰 8 项 setAccessibilityIdentifier
  方法形 + Marker 常量引用）✓；m6（Deps+inspectorState 扩展）✓；m7
  （二分措辞改任务边界重建）✓；m8（tracked-read 禁形 grep 门）✓。
- **omp 13 条抽 9**：OMP-M1（F0P-03 补 runAIDeterminismProbeIfRequested
  迁移腿 + 壳侧单 hunk 例外红线行）✓；OMP-M2（:798 page 腿枚举 +
  ExportPanelRequestKey 保留 (a) 案采纳）✓；OMP-M3（T1 树遍历缝处方 =
  install + NSApp.mainMenu 遍历 + validateMenuItem 探针）✓；m-omp-1
  （F0P-02「32 工具」）✓；m-omp-2（17 读集全文回写）✓；m-omp-4
  （willTerminate 转发调用点机检读法——本轮按修正读法亲验恰 1）✓；
  m-omp-6（供件步入 F0P-02 T5）✓；m-omp-7（f0prime-p1 单卷）✓；m9
  （T5 翻转前基线构建配方 = worktree + 独立 DerivedData）✓。
- fixer `7f49225f` 申报「F0P-01-PLAN.md untouched（冻结）」亲核 ✓。

## 六、分级残留清单

**minor（2）**

1. **MANIFEST 面 7 证据指针断裂**：`§四` 面 7 行引
   `w07-mark-menu-dump.txt`，但 `.work/gui-acceptance/f0prime-p1/evidence/`
   无此文件（w01..wA2 共 20 件在卷，独缺该 dump）。16 项断言本身已由本
   路源码亲数闭合（buildMetadataMenu = 16 整），行为面无虞；卷内指针悬
   空 = 证据账不严格。处方：P2 走查轮补 dump 或 MANIFEST 该行改指源码
   坐标（NSMenuBridge :507-559）。
2. **SUMMARY §4「App bundle 919/4/0 三轮同值（T3 后/T4 后/翻转后
   HEAD）」两处弱化**：①最后一次 App 轮（10:05:54 起，404s）跑在
   752c5294 树，而 fb4a5728（10:29，NSMenuBridge 33 行修正）晚于它——
   「翻转后 HEAD」在终 HEAD 语义下不成立（fb4a5728 产线改动当时无 App
   bundle 轮覆盖）；②执行方三轮详细 log 已被自身后续轮覆写，919/4/0 不
   可逐 test 对账。**风险实质 ≈0**（bridge 在测试宿主 inert 无激活路径 +
   构建级回归被 build 绿兜住）；**本轮闭合**：终 HEAD App bundle 复跑两
   轮同值 921/6/0（387s/392s，零失败零 MEMFAIL，`Test Suite 'All tests'
   passed`）。处方：P2 若引 919/4/0 数字处改注终 HEAD 复测值或口径。

**obs（4）**

1. **勘误④域坐标尾端字面含非 AppDelegate 区**：「AppDelegate 类
   （LightamerApp.swift:168-216 域）」的 216 实落在 WindowCapture doc 注
   释区（类体止于 :212；T6 的 review m4 hunk @@ -213,8 恰起于 :213）。
   严格按域坐标「该域零 hunk」机检会误报；语义判定（AppDelegate 类体零
   触碰）PASS。处方：P3 退役批把勘误④域精化 :168-212。
2. **App bundle 定向口径差**：执行方申报 919/4/0，本轮终 HEAD 两轮
   921/6/0（= audit-repair `--all` 口径 App 向量逐值同）。差 = env 条件
   skip 族（omp obs3 已登记家族）；skip 6 枚举亲列 = perf 探针 3 +
   depth 包缺席 3，零第三来源。零失败两口径一致，无行动项。
3. **ax-menu/B dump = 修正前二进制留档**（导出… enabled=false）——修正
   依据链 = A 臂实测真值 + 修正代码 + 走查 ⇧⌘E 路由 ✓，可接受；P2 门①
   像素/AX 复证时补终二进制 dump 即闭环。
4. **D-6 门双证结构注记**：B 臂 %cpu 0.0 使绝对门读数饱和，−96pp 对照
   （A 臂 96.0）作为改进向双证已在 CONTEXT 特别登记二闭合；P2 定版轮按
   既定配方复跑即可，无行动项。

## 七、验收轮痕迹与还原

- 主树 HEAD = `ef312a2a` 零改动（tracked 零 diff 亲核）；本报告 +
  `probe/logs/acc-*` 为 untracked 落盘，不 commit。
- worktree `/tmp/f0p1-acc-revert` 已 remove；探针/测试零残留进程
  （ps 亲核 0）；锁 `/tmp/f0p1-acc-lane1.lock` 收尾移除。
- /tmp 即弃域：`/tmp/f0p1-acc-*`（构建 log/测试 log/探针脚本/证据
  log）、`/tmp/f0p1-acc-evidence-app-full.log`、
  `/tmp/f0p1-acc-lane1.lock`——即弃，报告内数字已转抄。
