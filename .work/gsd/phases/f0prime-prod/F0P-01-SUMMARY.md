# F0P-01 SUMMARY — plan P1 执行摘要（审计修复先于翻转 + 壳交接翻转 + D-6 探针门）

> 执行窗：2026-10-18/19（单 worker 会话，commit-per-task，全英文
> Conventional Commits，未 push）。执行正本 = `F0P-01-PLAN.md`；裁定正本
> = `CONTEXT.md`；逐任务裁定 = `F0P-01-DECISIONS.md`；走查配方 + 冒烟记录
> = `.work/gui-acceptance/f0prime-p1/MANIFEST.md`（local 证据卷）。
> **执行到 P1 收口为止——C 档停，P2/P3 未启动。**

## 0. 结论头

**P1 全任务闭环：T1..T7 全落 + D-6 绝对门 PASS（0.0/0.0/0.0，<10% 判据
余量 90pp）+ 走查冒烟 1-9/14 逐项记录（4 项 ✓ 含 export 页全装配 / 5/9 两
项 ◑ 已归因——均为设计态或 P2 深度面，零翻转回归证据）+ revert 机检干净
+ 既有测试零回归（App bundle 919/4/0 三轮同值）。** 产线 commit 8 个
（T1..T6 六 + chore + T7 修正；T5 docs / T7 docs 另计）；主树 tracked 零
残留。

## 1. 逐任务 commit 表

| 任务 | commit | 内容 | 验收判定 |
|---|---|---|---|
| T1 probe-stay hunk | `907c373d` | patch 0001 逐字（10 行 = 7 注释 + 3 代码）入 EditorProbeIfRequested 探针尾 | byte-identity 面核 ✓；`la_probe_stay` App/Sources 恰 1 ✓；构建绿 ✓ |
| T2 缺口1 zoom 构造参数化 | `cb31d0ba` | EditorMTKView +`viewportSignature` 构造参数；updateNSView 三字段读摘除；EditorAreaView body 计算 ZoomSignature 传入 | updateNSView 内三字段读零命中 ✓；body ZoomSignature( 恰 1 ✓；push-once 臂原样 ✓；`let _ = viewportState` 全仓零 ✓；Editor/viewport 定向 54/0/0（BUNDLE-MAP 法数零漂移）✓ |
| T3 缺口2 exportPresent onChange 化 | `ffa4d583` | NSMenuBridge.swift 生产形（Deps+inspectorState/openSessionPicker/settings 三改形 + AX identifier 8 项）+ ContentView onChange 双态 note + InspectorView B19 + WorkspaceHostView B20 | 无 onAppear 一次性形 ✓；onChange 双态恰 1 ✓；`recentSessions.first` 桥内零 ✓（含注释）；McpServerController 零 diff ✓；`.runModal(` 零 ✓；插值禁形零 ✓；inert（install 零调用点）✓；App 919/4/0 ✓ |
| T4 缺口3 四 stub 生产化 | `cc449ecf` | ShellGraph.swift（9+columnVisibility 第 10 字段，`ShellGraph.shared` 单源）+ ShellWindowControllers.swift 三窗控制器 + ContentView columnVisibility binding 桥 | DECISIONS 先行步落位（review M2 三选一 = (a) 单例，D-F0P-01-1）✓；`@State private var columnVisibility` 零 ✓；三控制器类各恰 1 ✓；私有 selector 零 ✓；Project.swift 零 diff ✓；App 919/4/0 ✓ |
| T5 toolbar 差异登记 | `1aa9ff36` | DECISIONS tracked 正本（D-F0P-01-4）+ MANIFEST local 卷建 | 零产线 diff ✓；登记行在案 ✓ |
| （chore）selector 字面卫生 | `ff94f9c7` | NSMenuBridge 注释 3 行避字面（独立于翻转，保其恰三文件） | 注释级，零代码 |
| T6 壳交接翻转 | `752c5294` | LightamerShell.swift 新建（2368 行）+ LightamerApp entry 尾/WindowCapture + ContentView :551 缝——**恰一个 commit 恰三产线文件** | `F0PrimeShell` 零命中 ✓；fork 序逐字 ✓；空 stub 闭包零 ✓；autosave/fullScreen/reopen/willTerminate 各恰 1 ✓；ContentView openWindow 零 ✓；`private struct WindowCapture` 零 ✓；构建绿 ✓；**`git revert --no-commit` 干净应用 + abort ✓**（独立可 revert 红线）；App 919/4/0 ✓ |
| T7 实测修正 + 探针门 | `fb4a5728` | export enabler 恒 enabled（A 臂 AX 实测修正，D-F0P-01-5.2）+ 读集 19→17 + DECISIONS ⌘W 实测/探针/归因 | File 菜单 A/B AX dump 对证 ✓（`probe/logs/ax-menu/`）；走查 ⇧⌘E 路由 ✓ |
| T7 收口 docs | （本 commit） | SUMMARY + DECISIONS 终节（终名/接线终形/探针数据/偏差 5 项） | MANIFEST 冒烟表落位 ✓ |

全波清单（git log --oneline，新→旧）：本 commit → db163e1a/b820119a
（orchestrator docs，非本 plan）→ fb4a5728 → 752c5294 → ff94f9c7 →
1aa9ff36 → cc449ecf → ffa4d583 → cb31d0ba → 907c373d → 2ba9393e（plan
fixer 起点）。

## 2. D-6 探针门（T7 主验收数字）

| 轮（终二进制） | %cpu 中位 | frontmost | 窗内截图 | 主线程泊 | churn 符号族 |
|---|---|---|---|---|---|
| B-r1 | **0.0** | true | ✓ 编辑器面完整渲染 | mach_msg2_trap（4500/4502 样本） | 全 0 |
| B-r2 | **0.0** | true | ✓ | mach_msg2_trap 泊 | 全 0 |
| B-r3 | **0.0** | true | ✓ | mach_msg2_trap 泊 | 全 0 |

- **绝对门 <10% = PASS**（判据余量 90pp）；对照 spike F0PRIME A 臂 96.0
  基线 = −96.0pp 改进向复现（相对门并入对照，双证）。
- 采样配方 = 30s 窗 6 采样 @6s（`ps -o %cpu`）+ `sample 6s` 符号总量
  （前缀感知求和）；60s settle 盖 LUT 预热；frontmost 先行复验。
- 证据 = `phases/f0prime-prod/probe/logs/B-r{1,2,3}/`（meta/cpu/symbols/
  sample/stderr/screen 三件套）+ 修正前同值批 B-prefix-r*；驱动脚本 =
  `probe/run-driver-f0p1.sh`（spike 驱动派生，仅日志目录/臂位改）。
- 三臂留档：A = `/tmp/f0p1-dd-A`（worktree @907c373d 构建，strings 无桥
  符号）+ B = `/tmp/f0p1-dd-B`（HEAD 构建，strings 有桥符号 +
  LightamerShellMain）；C 臂 trace 位 P2 定版。
- 运行窗 parentage：probe pid ppid = 驱动脚本进程树（meta.txt 随行）；
  运行窗内零第二 GUI 实例。

## 3. 走查冒烟判定（1-9/14；明细 = MANIFEST §四）

✓ 面 1（启动/新建/最近项目 + L057 面板缝 + 动态子菜单）、2（探针级
import 全链）、3（真缩略图 + EXIF inspector）、4（⌘E 进出 + 解码渲染 +
⌘W 1:1 实测）、6（**export 页 ⇧⌘E 全装配**——同时实证使能修正；film
dispatch）、7（**16 项整** + B19 disarm 链 + 评分/色标应用 + 条纹刷新）、
8（copy→paste 使能实时翻转 + Edit 使能态全对）、14（⌘Q 干净退出 +
零残留）。
◑ 面 5（菜单缩放 = 静止面 crop-route by-design 锁；**A 臂同法同结果 =
非回归**；dispatch 链 trace 实证；缺口1 重绘满验证需 mask/segment 路由
= P2）、9（软打样 dispatch ✓；AX 态标记读取不确定 = P2 laState 验证点）。
面 10-13/15-16 = P2 范围（15 部分证据：Window 菜单含系统 进入全屏幕 =
.fullScreen 生效）。

## 4. ΔN 终账

**P1 实际测试增量 = +0**（带 +0..2 内）：T2 ZoomSignature 求值未抽独立
纯函数（构造点内联，无相等性负测落点——合法 ΔN=0）；全批测试族归 P2
（+15..23）。既有测试零回归：App bundle **919/4/0** 三轮同值（T3 后/T4
后/翻转后 HEAD），全套 `--all` 未跑（P2 批准制，符合 plan）。

## 5. 红线核销

15 条全核（明细 = DECISIONS 各节）：FIX2③ McpServerController.swift 零
diff ✓；封存面零 diff（全 diff 仅 App 壳域 + Shell 新文件 + docs）✓；
无 QA 回切（env 门零命中）✓；翻转单 commit 内聚 + revert 干净 ✓；
xcstrings 零 diff ✓；LocalizationValue 禁形零 ✓；disable-not-unmount
（enabler 读 holdsControl + backstop + SwiftUI 10 处零触）✓；基线
3969/37/0 口径 ✓（App 分账 919/4/0）；AppDelegate.swift 字节零改 ✓；
DEBUG fork 序零触 ✓；L057 `.runModal(` 零 ✓；UserDefaults 应用级零新键
✓（autosave = AppKit 出厂 `NSWindow Frame *` 键）；`--all` 未跑 ✓；C 档
停 ✓；LightamerShell* 改名零残留 ✓。

## 6. 偏差清单（5 项，DECISIONS 详节）

1. MANIFEST 路径随收尾指令（f0prime-p1/）+ gui-acceptance 整域
   gitignore → tracked 正本落 DECISIONS。
2. selector 字面卫生 chore commit（保翻转恰三文件）。
3. export enabler 恒 enabled（A 臂 AX 实测修正 plan B17/B18 形；晨审可
   推翻——翻回 = note ∨ exportPageActive 谓词一行）。
4. face 四属性 + ShellGraph 第 11 字段（review M1/m6 缝落形申报）。
5. DEBUG trace 脚手架（归因轮临时，已撤零残留）+ spike §4.3「状态变异✓」
   注记修订（crop-route 锁下的闭包运行 ≠ zoom 实际位移）。

## 7. P2 交接注记

- 走查面 5/9 的两处 ◑ 归因（crop-route zoom 锁链满验证需 mask/segment
  路由；菜单 Toggle 态 AX 标记读取）= P2 16 面走查的必验子项。
- 粘贴→历史零位移（恒等粘贴语义）待 P2 以真编辑复核 undo 环。
- ContentView onChange note 写腿（exportPanelRequested→note box）现无
  使能消费点 = P2/P3 修剪候选。
- 系统组标题 zh/en 差异（DECISIONS D-F0P-01-5.4）= P2 门① 双语像素对照
  复核面。
- 直启测试宿主等价性验证轮（RESEARCH §5.4）= P2 首任务（本 plan 未跑
  单 bundle 等价对账，App bundle 走 test-direct 直启全程绿即旁证）。
