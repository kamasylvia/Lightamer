# M2-8-3 ACCEPTANCE — 收口（zh 对账 + 观察项三查 + 翻账 + phase 小结）独立验收 + 两 FINDING 修复

> 验收：ZCode 验收 subagent（零共享上下文），2026-10-02 深夜。对象 = 执行方三提交
> `7b7f475`（T1 zh 对账）/ `71c8baf`（T2 观察项 + 走查）/ `5102ea4`（T3 翻账五账）；
> plan 正本 = `M2-8-3-PLAN.md`。带**两 FINDING 修复授权**（执行方按零源码 diff 红线
> 未修、DECISIONS §3.2/§3.3 登记在案；修复属验收循环职责，小修直接修先例）。
> 方式 = AC 8 条逐条核对 + 三提交边界机检 + 两 FINDING 实机复现（AX/截图）→ 修复
> （各一笔 fix commit + 回归测试随修随补）→ 定向 bundle + 全套 `--all` 独立复跑 →
> 实机复验走查 → 翻账同批。
> **结论头：PASS / 0 error + 0 minor + 2 observation（含两 FINDING 已修闭环）。**

## 一、三提交边界与申报核实（AC#1/4/5/6/8）

- 逐 commit `--name-only` 对照 front-matter：T1 = DECISIONS §1（对账表）；T2 =
  DECISIONS §2-3 + `.work/gui-acceptance/m2-8/` 证据 11 件；T3 = REQUIREMENTS/
  GOAL-STATE/TODO/AGENTS.md/SUMMARY/DECISIONS §4——**零第三类源码文件**，零源码
  diff 红线以更严形态达成（.xcstrings 亦零改动，zh 键前波已落齐）。
- 工作区滞留甄别：`09-3-tiers-*.jpg` 两文件改动 = 前波走查遗留（mtime 早于执行窗），
  未纳入本批——与 SUMMARY 边界节申报一致；其余 untracked 均为更早批次遗留。
- AC#1 zh-audit：`uv run python3 Scripts/zh-audit.py --check` 复跑 **PASS**（1362
  source keys / 1588 catalog keys / zh complete / locale {en,zh}，EXIT=0）；对账
  42 键口径与 DECISIONS §1 一致（43→42 勘误承前波验收 observation①）。
- AC#2/3 观察项三查：SUMMARY 四行数字（500 链切换 0.562ms avg / 万条 .lra
  save≈55ms·load≈46ms / 105 版本滚动 / pristine 三客户面差分）与 DECISIONS §2
  成对；程序化探针即弃形态与 checker M5a 落法一致。
- AC#4/5/6 翻账五账：REQUIREMENTS M2VER-01..05 终态 + 两条追认项注记、GOAL-STATE
  C 档第 3 停、TODO 清账、AGENTS.md M2-8 增量节、SUMMARY phase 小结节（含挂账
  五项全量 + M2-9 交接）——文内交叉引用亲核无悬空。

## 二、两 FINDING 实机复现（修复前，签名亲证）

### FINDING-A（error）：Copy Adjustments 对话框开即崩——复现 1/1（累计 3/3）

- 驱动：Debug 构建（`5102ea4` 树）真机启动 → 探针项目导入 IMG_3061.ARW → 编辑器
  开图 → Edit 菜单「复制调整…」→ **进程即死**。崩溃报告
  `Lightamer-2026-10-02-000854.ips`（存档 `gui-acceptance/m2-8/m2-8-15-prefix-a-crash.ips`）：
  **EXC_BREAKPOINT (SIGTRAP)**，faultingThread 0——与执行方两轮 .ips 签名一致。
- 根因确认（读码级，与 DECISIONS §3.2 判断吻合并落实机制）：app-root 的
  `.sheet(isPresented:)` 闭包挂链在 `.environment(...)` 写入**之外**（modifier 链
  外层看不到内层写入），sheet 内容环境快照缺 `VersionCoordinator` /
  `EditorState` 两 Observable——`@Environment(Type.self)` 首次解析即 trap。
  仓内旁证：全部 app-root 级 sheet（LibraryWelcomeView / ImportModeDialog /
  PastePartialDialog / ExportPanelView）皆 init 参数注入，唯本对话框裸
  `@Environment` 跨界。

### FINDING-B（error）：哨兵 toast 及全部 D-26 toast 默认面零渲染点——复现成立

- 驱动：`defaults write app.cleanTerminate -bool true` → 重启 → Open Recent 开
  项目 → 双击进编辑器（图加载 = editorReady = 哨兵 toast 触发点）→ 4s 窗口内
  连拍 9 帧：**帧帧无 toast**（`m2-8-14-prefix-b-no-toast-9frames.png`）。
  键机制真（触发链机器已验）+ 渲染点结构性缺席（StatusBar 只挂 legacyBody，
  grep 机检零 toast 面）——与 DECISIONS §3.3 完全一致。

## 三、修复（各一笔独立 fix commit，回归测试随修随补）

### FINDING-A → `e9c03af` fix(m2-8-3): re-inject the Copy Adjustments sheet environment

- **修复面**：新增 `AdjustmentTransferSheetContent`（AdjustmentTransferView.swift
  文内）——sheet 内容面子组件，`.environment(versions)` + `.environment(editorState)`
  注入在呈现内容内部（DECISIONS §3.2 建议线 + preset-manager Window 重注入惯例）；
  app-root 闭包改挂该面（LightamerApp.swift 一处）。零其他面触碰。
- **回归测试**（同 commit）：`SheetEnvironmentInjectionTests`（App bundle）——
  以**真 `.sheet` 呈现**挂载生产 face（NSWindow + NSHostingView + runloop 泵，
  NodeCanvasGeometryTests 挂载先例），专防「挂非 sheet 层级测绿」盲区复发：
  - 正腿：sheet 内容 onAppear 达成 = 环境（含两 Observable）在 sheet 层级解析
    成功，1/0/0 PASS（日志亲核；test-direct.sh 对 "Executed 1 test" 单数形态
    计 0——**预存解析 quirk**，见 observation②）。
  - **负腿实测**：临时掏空 face 注入（模拟回归）重建重跑 → 测试挂载点复现**同一
    fatal 签名**（「No Observable object of type VersionCoordinator found」），
    宿主进程死 = bundle 硬失败——检测力实证后还原修复复建。

### FINDING-B → `4e7fc58` fix(m2-8-3): mount the D-26 toast render site on the default shell

- **修复面**：新增 `ToastBarView`（WorkspaceHostView.swift 文内）——零 chrome
  契约（nil toast = EmptyView，默认面不新增常驻条；legacy 面 Ready/Decoding 尾位
  保持 legacy-only），有 toast 时以 StatusBar 同款视觉语言（22pt / surfaceRaised /
  monospaced / hairline top border / `status_toast` 标识）渲染；挂载点 =
  `WorkspaceHostView` 底部 `safeAreaInset(edge: .bottom)`，读
  `@Environment(EditorState.self).toast`（该深度注入可达——YiyinTopBarSheet
  同深度读法在案）。legacyBody 零触碰。
- **回归测试**（同 commit）：`ToastFaceTests` 3/0/0——①nil toast 零 chrome
  （fittingSize ≤ 0.5）；②有 toast 渲染 22pt 面；③**wiring 腿**：真
  WorkspaceHostView 挂载（注入 EditorState + PipeCoordinator），toast 升起后
  AX 树出现 `status_toast` 元素、无 toast 时不存在（自进程 AX 走查，即走查
  驱动同款读法）——「结构上挂没挂」被真面挂载钉死。

### 登记纪律

- Project.swift（App target sources +2 行）+ BUNDLE-MAP（APP 两行 + 增行记录节）
  随各自 fix commit 同批；`tuist generate` 恒末位（L041）。
- 两 commit 各自自洽（A 树无 B 面、B 树含 A），提交序 = 修复序。

## 四、独立复跑（AC#7）

- 定向（修复树）：SheetEnvironmentInjectionTests 1/0/0（日志）· ToastFaceTests
  3/0/0 · AdjustmentTransferTests 8/0/0 · WorkspaceRoutingTests 11/0/0 ·
  CleanTerminateSentinelTests 3/0/0 · LibraryLegacyGateTests 11/0/0（LIB bundle）
  ——全绿。
- **全套**：`caffeinate -dis Scripts/test-direct.sh --all` = **`TOTAL|2577/16/0|896s
  EXIT=0`**。七 bundle 逐行：`IOP 467/1/0|6386MB · IOPParity 362/3/0|5999MB ·
  Layers 298/3/0|1053MB · Library 436/4/0|313MB · Sessions 279/4/0|1652MB ·
  Export 260/1/0|6641MB · App 475/0/0|1396MB`。MEMFAIL 零（峰值 Export 6641MB <
  8192 门）。
- 对账：**2573（M2-8-2/3 终态）+ 4（SheetEnvironmentInjectionTests 1 +
  ToastFaceTests 3）= 2577 精确**；App bundle 471→475 精确；skip 恒 16。

## 五、修复后实机复验走查（两缺陷路径重走）

### A 路径：Copy Adjustments 开 → 不崩 + 三 pane 真渲染（4 次开启零崩）

- 修复树真机启动 → 开项目 → 编辑器开图 → Edit「复制调整…」×4 次（空链 / 温度
  编辑后 / Grade 层新建后 / 层选中态）：**每次全渲染无崩溃**——来源段（当前图像 /
  外部 .lra）、调色节点 pane、调整项 pane、粘贴为新版本 pane、取消/粘贴钮全部
  在场（`m2-8-09/10/11` 三截图）。
- 传输面语义实测旁证：空链图 =「来源中没有调色节点」（白平衡=develop 域正确
  排除）；新建 Color Grade 1 层后节点行「Color Grade 1 · 0/0 可贴」正确枚举、
  空层粘贴钮正确禁用——排除面/枚举面/守卫面在真 sheet 层级全部活体工作。
- 传输落盘腿（pasteChain → 新版本物化）由同树单测面机器覆盖（AdjustmentTransferTests
  8/0/0 含真 .lra 粘贴 + 版本物化 + 激活写盘），叠加 sheet 层级环境注入回归测试
  = 修复面（环境跨界）+ 传输面（pasteChain 语义）双覆盖。屏上全传输（含 grade
  项的层内编辑驱动）本轮未走通——**驱动深度问题非修复面问题**（层激活编辑的 AX
  驱动超出走查性价比），如实登记 observation①。

### B 路径：哨兵 toast 默认面可见

- `defaults write app.cleanTerminate -bool true` → 修复树重启 → Open Recent →
  双击进编辑器 → 连拍 10 帧（0.35s 间隔，4s toast 窗内）：**toast 面清晰渲染**——
  「上次会话异常退出—编辑已自动保存（至多丢失最后数秒）。」于窗口底条 22pt 面
  （`m2-8-12-fix-b-toast-visible.png`），末帧自动消退 = 4s auto-clear 语义在
  默认面工作（`m2-8-13-fix-b-toast-autocleared.png`）。
- M2VER-04「崩溃恢复条最小面」的屏上面**自本修复起在默认 shell 用户可达**。

## 六、observation（不阻塞）

1. **observation①（走查驱动深度）**：屏上「含 grade 项的真传输」未走通——需要
   层激活态的层内编辑（节点画布激活 → 面板编辑入层），AX 驱动成本超出验收性价比；
   传输语义已由单测面机器覆盖（见 §五 A 路径）。后续 GUI 批如需可视化粘贴证据，
   建议探针参数化（`-la_transfer_probe` 形态）而非 AX 手摇。
2. **observation②（test-direct.sh 预存 quirk）**：记账解析 `Executed [0-9]+ tests`
   不匹配单数形态「Executed 1 test」——恰好 1 条用例的过滤跑记 0（判定逻辑仅无
   过滤时把 executed=0 判失败，故无假绿风险，TOTAL 低记 1）。本批以日志亲核兜底；
   修复归 test-direct.sh 另案（一行 regex），不顺手修。
3. 前波 observation②③（ANE 尾段脆弱面 / SidecarV5 temp 恒漏）：本轮 `--all`
   单轮即绿零复发，继续挂账观察（不扩范围）。

## 七、判定与移交

- **判定：PASS**——AC 8 条全过（§一）+ 两 FINDING 复现→修复→复验证据链闭环
  （§二/三/五）+ 全套 2577/16/0 精确对账（§四）；修复双 commit 边界干净（各触
  缺陷面 + 各带回归测试），红线零违例。
- **M2-8 phase VALIDATION 输入就绪**：三 SUMMARY + 三 DECISIONS + SUMMARY phase
  小结节 + 本报告（两 FINDING 已修闭环，C 档第 3 停裁决项消解——签核时「带挂账
  签核」分支不再适用，「先修后签」已兑现）。
- 提交清单（本轮验收批，未 push）：
  - `e9c03af` fix(m2-8-3): re-inject the Copy Adjustments sheet environment
  - `4e7fc58` fix(m2-8-3): mount the D-26 toast render site on the default shell
  - 本 docs commit（ACCEPTANCE + REQUIREMENTS 追记改写 + AGENTS/TODO/GOAL-STATE
    + 证据件 7 件）
- 工作区滞留：`09-3-tiers-*.jpg` 两文件（前波遗留，维持未纳入）；探针 scratch
  （/tmp/la-m283）即弃；走查宿主侧效已还原（app.cleanTerminate /
  library.recentProjects defaults 已删，quit 路径走 pkill——非清态退出，defaults
  复删兜底已做）。
