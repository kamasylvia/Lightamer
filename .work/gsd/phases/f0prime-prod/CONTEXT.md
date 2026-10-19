# F0PRIME-PROD CONTEXT — F0-prime 壳交接生产批（OQ 裁决落定批，2026-10-18）

> **裁决正本**：OQ-F0P-1..10 **全部按 `RESEARCH.md` §8 推荐落定**（charter
> `35a6c178` 用户「按推荐」三裁决之一；先例 M6-3/M6-4、M7-2..M7-6、
> audit-repair 批同款「OQ 全按推荐」。**晨审可推翻**——推翻 = 用户晨审
> 修订本文件对应 D 条，下游 plan 受影响任务面重开，已执行部分按「晨审
> 推翻先例」惯例处理）。读解正本 = 同目录 `RESEARCH.md`（§0 结论头 /
> §1 壳交接生产形 / §2 菜单全族清单 / §3 未追踪读审计 / §4 @State 迁移 /
> §5 测试兼容面 / §6 回归走查 / §7 切分 / §8 OQ / §9 锚点；file:line 经
> planner 2026-10-18 HEAD `9a0b9530` 抽核 ~20 点亲核吻合——**转写勘误
> 七条**随本文 §转写勘误节登记（③ = review M3 增补；④..⑦ = omp 复审
> 转写批 2026-10-19——OMP-PLAN-REVIEW + RESEARCH-REVIEW 落位），执行
> 以勘误为准）。
>
> **特别登记一（D-F0P-5 无 QA 回切通道）**：本批**不设** env 回切门
> （`LIGHTAMER_SHELL=legacy` 形不采纳，LibraryLegacyGate 先例不适用此域）——
> 双壳并存使 churn 门失守：legacy 面（SwiftUI App/Scene lifecycle）在场则
> 96% churn 随时复活，D-6 门正门失义（churn 是生命周期自身的机器，
> F0PRIME §4.2 实证）。**回退单元 = git revert**：翻转 commit 独立可
> revert（P1 T6 壳交接一个 commit 内聚）+ spike 分支 `spike/f0prime-shell`
> 三 commits 与 worktree `../Lightamer-f0prime-shell` 保留（复测/回溯面）；
> QA 若需旧 face 行为用 revert 后构建或 release 分支。
>
> **特别登记二（D-6 绝对门 <10% 复活为验收正门）**：M7-1 时代 D-AR1-10
> 用户裁决曾把 D-6 门改「相对门」（绝对门绑上游专项）——壳交接后 B 臂
> 三轮 **0.0%** 基线（F0PRIME §2）使绝对门重新可达：**编辑器静置 %cpu
> 中位 <10%（判据线留 10pp 余量对 0.0% 基线）+ L082 四哨兵**（frontmost
> 先行复验 / 窗内截图可见 / 主线程样本泊 `mach_msg2_trap` / churn 符号族
> 零）= P1 T7 + P2 T7 的机检验收正门（review m3：P2 的 D-6 定版 = T7，
> 原文「P2 T8」任务号 stale）；相对门语义并入对照（与 F0PRIME
> A 臂 96.0 留档比 ≥86pp 改进向 = 双证，非替代绝对门）。
>
> **编排总纲**：三 plan **串行 P1→P2→P3**（P1 内部「审计修复先于翻转」是
> 硬序——churn 在场时缺口惰性生效、翻转即需；P2 依赖 P1；P3 依赖 P2，
> 退役前必须全套绿）。**C 档门控：每 plan 执行+验收闭环后停汇报**，等
> 用户确认再放行下一 plan（charter 门 + AGENTS 暂停机制）。全套 `--all`
> = orchestrator 批准制 + 运行监视 + 8G 门 + MEMFAIL 机检兜底（AGENTS
> 资源监控节）；P2 内 `--all` 正式轮 + 两轮同值复证（M7-3 三方同值先例）。

## Phase Goal（F0-prime charter 锚定）

把 F0' spike 双门 PASS（正本 = `phases/nsmenu-spike/F0PRIME.md`：门① 菜单
权威 / 门② churn −96.0pp / 门③ SwiftUI 面存活）落进产线：**@main 壳交接**
（手动 NSApplication + delegate 托管 NSWindow + NSHostingView + 自建 NSMenu
全族 parity）+ **硬前置未追踪 @Observable 读审计修复**（4 真实缺口：
zoom 构造参数化 / exportPresent onChange 化 / 四 stub 生产化 / toolbar 差异
登记）+ D-6 探针门（绝对 <10%）+ ΔN 测试族 + 16 面 GUI 走查 + 死码退役 +
FB 稿回填。验收形态：构建绿 + probe 全链 + D-6 绝对门机检 + 全套 `--all`
三轮同值 + 16 面 MANIFEST 全绿 + 门① 像素/AX 复证；**测试基线权威数
`3969/37/0`**（skip 37 = 35 基线 + 探针族 2；**勘误 RESEARCH 3905**——见
§转写勘误①），全批终值带 **3984..3994**（ΔN +15..+25：P1 分账 +0..2 /
P2 分账 +15..23 / P3 分账 +0）。

## 决议（D-F0P-1..10，生效值，硬约束，执行中不重开）

### D-F0P-1 Settings 窗 = 真窗控制器（OQ-F0P-1）

- **裁决 = RESEARCH §8 推荐**：AppKit Settings 窗控制器（NSWindow +
  NSHostingView(SettingsView) + env 三件注入 + `.preferredColorScheme(.dark)`
  + 520 系 defaultSize 形）；App 菜单 Settings…（⌘,）项 action 直调窗控制
  器 `showWindow`；**私有 selector `showSettingsWindow:` 是 Apple 随时可拆
  的面，只许 spike 冒烟用，不入生产**。
- 理由一句：私有 selector 无 API 承诺，随 macOS 升级静默失效的尾部风险
  换不来一行代码的节省。
- 证据：RESEARCH §2.1 App 菜单组 + §2.4 风险 2 + patch 0002 :2629
  （`NSApp.sendAction(Selector(("showSettingsWindow:")), …)` 冒烟形在案）；
  HEAD `LightamerApp.swift:2236-2244`（Settings scene + env
  catalogPreferences/pipeCoordinator/libraryProjects 三件注入面）。
- 晨审推翻点：翻案 = 沿用私有 selector（无承诺面随 OS 演化失效风险自担，
  不建议）。

### D-F0P-2 窗级 toolbar = 接受 in-face 差异 + 登记，不重造 NSToolbar（OQ-F0P-2）

- **裁决 = RESEARCH §8 推荐**：`.windowToolbarStyle(.unified)` 窗级附着形
  态缺席 = **已知差异登记不修**（hosting in-face 渲染的 toolbar 内容仍活
  ——F0PRIME §1.3 截图在案）；NSToolbar delegate 重造 = 后置立项候选。
- 理由一句：churn 收益与 toolbar 形态无关（壳交接的 96%→0% 不经过
  toolbar），重造 = 纯观感工程挤占 M 批预算。
- 证据：RESEARCH §1.4 已知差异①④ + §3.2-D2 + F0PRIME §1.3 偏差申报；
  HEAD `LightamerApp.swift:1798`（`.windowToolbarStyle(.unified)` 现形）。
- 晨审推翻点：翻案 = P1 内加 NSToolbar delegate 重造任务（观感工程，
  走查面加大，不建议）。

### D-F0P-3 ⌘W 语义 = 跟随现行 IA，不做语义创新（OQ-F0P-3）

- **裁决 = RESEARCH §8 推荐**：editor face ⌘W = closeEditor 优先（NSMenu
  主菜单项在窗口 performClose 之前拦截 keyEquivalent，语义可保）；
  library face ⌘W 落点 = **plan 执行阶段实测现行 File 菜单 AX 内容后 1:1
  对齐**（禁凭推断定语义）。
- 理由一句：壳交接是搬运不是重设计——现行 IA 的 ⌘W 双面语义是已验收
  行为，壳侧唯一义务是 parity。
- 证据：RESEARCH §2.4 风险 1 + `LightamerApp.swift:1928-1934`
  （menu_back_to_library ⌘W closeEditor 现形）。
- 晨审推翻点：翻案 = 重定义 ⌘W 语义（UI 行为变更超出壳交接范围，不建
  议）。

### D-F0P-4 Dock reopen / 全屏 delegate 补行 = 补（OQ-F0P-4）

- **裁决 = RESEARCH §8 推荐**：`applicationShouldHandleReopen`（一行，显
  示/重建主窗）+ styleMask 补 `.fullScreen`（一行）——SwiftUI 默认行为的
  对齐项，spike 形缺席即补。
- 理由一句：两行成本换 SwiftUI lifecycle 出厂行为等价性，缺行 = 走查面
  15（多显示器/全屏/⌘M/reopen）必挂。
- 证据：RESEARCH §1.2 多显示器/全屏/⌘M/reopen 节 + §3.2-D4/D5；spike
  styleMask 无 `.fullScreen`（patch 0002 主窗构造形）。
- 晨审推翻点：翻案 = v1 不支持全屏/reopen（功能面收窄，无收益，不建议）。

### D-F0P-5 无 QA 回切通道，回退单元 = git revert（OQ-F0P-5）【特别登记一】

- **裁决 = RESEARCH §8 推荐**：不设 `LIGHTAMER_SHELL=legacy` env 门——
  双壳并存使 churn 门失守：legacy 面在场则 96% churn 随时复活，门① 正
  门失义；回退单元 = git revert（翻转 commit 独立可 revert，P1 T6 内聚
  红线）+ spike 分支/worktree 保留；QA 需旧 face 用 revert 后构建。
- 理由一句：churn 是生命周期自身的机器（F0PRIME §4.2 排除法闭环），
  「随时可切的旧壳」= 「门永远量不准」。
- 证据：F0PRIME §4.1/§4.2 + RESEARCH §8 OQ-F0P-5 行；LibraryLegacyGate
  先例的适用域差（那是功能面双 IA 并存，本批是生命周期单选）。
- 晨审推翻点：翻案 = 加 env 门（D-6 门失义自担 + 双壳维护成本，不建议）。

### D-F0P-6 多窗 keyWindow 语义 = 恒主窗单源（OQ-F0P-6）

- **裁决 = RESEARCH §8 推荐**：bridge workspace note 恒主窗单源（v1 单编
  辑窗语义）；窗菜单自动清单交 AppKit 出厂行为；多窗聚焦判定后置。
- 理由一句：单编辑窗是现行产品语义，keyWindow 判定是未发生场景的工程。
- 证据：RESEARCH §3.2-B20（`onAppear` 单窗形已验 + keyWindow 挂账）+
  §8 OQ-F0P-6 行。
- 晨审推翻点：翻案 = keyWindow 判定入 P2（多窗场景未发生，提前工程不
  建议）。

### D-F0P-7 zoom 修法 = 构造参数化（OQ-F0P-7）

- **裁决 = RESEARCH §8 推荐**：zoom/pan/rot 签名族变 EditorMTKView **构造
  参数**（EditorAreaView body 计算传入——body tracked read 使观察纪律显
  式化）；**被否备选 = body tracked-read 形（`let _ = viewportState.zoom`）
  ——易在重构中静默丢失，机检形不成立**。
- 理由一句：与 sourceTexture push-once 同构（13-3 T1 先例），参数化后缺
  口类错误 = 编译期面非行为面。
- 证据：RESEARCH §3.2-A1 + §8 OQ-F0P-7 行；`EditorMTKView.swift:127-138`
  （ZoomSignature push-once 现形）+ `EditorAreaView.swift:61-328`（body
  对 zoom 族零 tracked read 实证）。
- 晨审推翻点：翻案 = tracked-read 形（观察纪律隐式化，重构丢失风险自担，
  不建议）。

### D-F0P-8 主窗 autosave key = 新 key `"LightamerMainWindow"`（OQ-F0P-8）

- **裁决 = RESEARCH §8 推荐**：`setFrameAutosaveName("LightamerMainWindow")`
  ——spike 的 `F0PrimeShellMain` 是实验名不入生产；项目零 `@SceneStorage`
  实证（与 SwiftUI 恢复无冲突面）。
- 理由一句：frame autosave key 是持久身份，实验名入产 = 未来 rename 即
  丢用户窗位。
- 证据：RESEARCH §3.2-D7 + §8 OQ-F0P-8 行；patch 0002
  `setFrameAutosaveName` 现形。
- 晨审推翻点：翻案 = 改键名（一次性成本，趁无用户基数现在改最便宜——
  若翻案请在 P1 T6 前定）。

### D-F0P-9 AppDelegate = 组合转发，生产 AppDelegate 文件字节零改（OQ-F0P-9）

- **裁决 = RESEARCH §8 推荐**：`LightamerShellDelegate` 组合生产
  `AppDelegate`（final 类组合转发——open Apple Events +
  `applicationWillTerminate(_ notification: Notification)` **参数类型
  load-bearing**（M2-8-2 T4 教训：`NSApplication` 型参数 "nearly matches"
  使 ObjC selector dispatch 永不触发）逐字转发）+
  `applicationShouldTerminateAfterLastWindowClosed = true` 对齐 SwiftUI
  默认。
- 理由一句：D-X 红线精神——AppDelegate 是全 App 装配信任根，改 non-final
  继承 = 换信任根；组合转发 spike 已验零风险。
- 证据：RESEARCH §1.1 + §8 OQ-F0P-9 行；`LightamerApp.swift:168-201`
  （AppDelegate final + willTerminate Notification 参数注释在案）。
- 晨审推翻点：翻案 = AppDelegate 改 non-final 继承（信任根重构，回归面
  全开，不建议）。

### D-F0P-10 FB 稿终章 = P3 收尾呈用户（OQ-F0P-10）

- **裁决 = RESEARCH §8 推荐**：`research/APPLE-FB-D6-DRAFT.md` 终章回填
  （双重排除法证据链 + churn 功能性发现〔F0PRIME §4.3——96% 机器曾承担
  未追踪读的功能性负载〕+ 壳交接 0.0% 终数据）**P3 收尾呈用户**；Apple
  FB 手动提交惯例不变（用户手动提交是上游唯一杠杆）。
- 理由一句：FB 终数据要等 P2 全套绿 + D-6 门定版，提前回填必返工。
- 证据：RESEARCH §7 P3 行 + §8 OQ-F0P-10 行；charter 裁决③（FB 稿补强）
  `35a6c178`。
- 晨审推翻点：翻案 = 提前呈稿（数据不全返工，不建议）。

## 转写勘误（RESEARCH → 本批 planner 亲核批，非矛盾、执行以勘误为准）

1. **测试基线勘误（3905 → 3969/37/0，本批最大转写勘误）**：RESEARCH
   §5.5 末行「全套预期 = 3905 + ΔN(skip 35 零漂移口径,M7-3 基线)」与
   §7 P2 行「TOTAL 3905+ΔN 三轮同值」= **漏更**（3905 是 M7-3 时代数，
   其后 M7-4 → 3925、audit-repair 批收口 `9898a0fb` → **3969**）。权威
   基线 = **`3969/37/0`**（audit-repair 批收口终态，`.work/gsd/STATE.md`
   M8 段在案）；skip 37 = 35 基线 + 探针族 2（`LIGHTAMER_PERF_PROBE`
   门控 perf 探针族 XCTSkipUnless）。全套预期 = **3969 + ΔN（+15..+25 →
   终值带 3984..3994）**；三 plan 以本数为正本。
2. **manifest 重指时序勘误（RESEARCH §7 P2 行 vs §2.3/§5.2 张力裁定）**：
   RESEARCH §7 P2 行列「AgentControl manifest 重指」为 P2 范围，而
   §2.3 末段与 §5.2 第 2 行明文「App struct Commands **退役后**重指到壳
   文件（P3）」——**裁定按 §2.3**：manifest face ⑤ 行（
   `AgentControlCoordinatorTests.swift:229-231`，grep
   `UI/LightamerApp.swift` 含 `|| agentControl.holdsControl)` token）重指
   + `ProjectReadOnlyFaceTests.swift:499-506` 的
   `LightamerApp.batchPasteBlocked` static 转移壳类型（或保留同名转发）
   **随 P3 退役同 commit 原子落地**。理由：P2 全套轮时 App struct 死码
   token 仍在、source-content guard 仍绿；重指先行反而制造「guard 指向
   桥文件 + 死码 token 并存」的双源窗口。RESEARCH §5.5「修改 2 文件」
   由此归 P3 账——**P2 = 纯增测试文件，产线零 diff**。
3. **菜单 enabler 谓词勘误（RESEARCH §2.3「7 项含 holdsControl」枚举
   错误——review M3）**：RESEARCH §2.3 行「New/Open Project、Open
   Recent、undo/redo、**paste 族** 7 项受 holdsControl 合取(spike 已形)」
   把 paste 族误计入 holdsControl 合取族——产线 paste 族 enabler =
   **hasPayload × isReadOnly 二元，无 holdsControl**（正本
   `LightamerApp.swift:2003/:2008`〔勘误⑤行号精化——m-omp-3〕
   `.disabled(!pasteboard.hasPayload || libraryProjects.isReadOnly)`；
   spike 桥 buildEditMenu 同形 `hasPayload && !isReadOnly`）；
   holdsControl 合取族实为 undo/redo / New/Open Project / Open Recent
   （holder+rows）。P2 T1 enabler 规格以本勘误为准（F0P-02 已照此
   勘正）。**语义不变申报**：本条为勘正转写文本——产线语义现状即二元、
   本批零改，无需用户裁决；若晨审欲**改**语义（paste 也受 agent 禁编辑）
   = UI 行为变更超壳交接范围，须走用户裁决面。
4. 其余 ~20 抽核点全部吻合（±1 行内微差不影响语义）：`LightamerApp.swift`
   :15-35（focused-value 键定义）/:128（entry）/:168（AppDelegate）/
   :190-201（willTerminate Notification）/:252（App struct）/:437
   （legacyLibraryEnabled let）/:507（主窗）/:1797-1799（defaultSize/
   toolbarStyle/commands 起点）/:2024/:2029（openWindow 双点）/:2212-
   2218/:2224-2227/:2236-2244（三窗 scene）/:2639（batchPasteBlocked）/
   :2692-2702（focusedColumnVisibility 写回）；`ContentView.swift` :143
   （columnVisibility @State）/:249-250（publish）/:551/:796-800；
   `EditorMTKView.swift:127-138`；`EditorAreaView.swift` :61/:274-277/
   :419/:547-553；`MenuCommandSet.swift:78-85`；`WorkspaceHostView.swift
   :195`；`InspectorView.swift:428-432`；`ProjectReadOnlyFaceTests.swift
   :499-506`；`AgentControlCoordinatorTests.swift:228-235`；
   `Scripts/test-direct.sh:214/:250-262`；patch 0001（probe-stay hunk
   WorkspaceHostView :1827 邻域 +10 行 = 7 注释 + 3 代码）/ patch 0002
   六文件形（view 三 note 修饰符 hunks + entry 切换 + WindowCapture
   private→internal）/ patch 0003（trace）；四 stub 现形（patch 0002
   :2158-2176 + :2629 Settings selector）。

5. **勘误④（AppDelegate 文件名勘误，m-omp-10，2026-10-19 omp 复审批）**：
   仓内**无 `AppDelegate.swift` 文件**——AppDelegate 类定义在
   `LightamerApp.swift:168-216` 域（@ `9a0b9530`；research 复审 m4 同
   证：类声明 :175）。红线⑨ + 三 plan 转引读法 = 「AppDelegate 类（该
   域）字节零改」，机检 = 该域 `git diff` 零 hunk；CONTEXT 红线⑨正本 +
   F0P-02/F0P-03 转引已随批改写，**F0P-01 冻结未触**（P1 在飞——执行
   面以本勘误为准，P1 DECISIONS 顺带追记即可）。
6. **勘误⑤（勘误③行号精化，m-omp-3，同批）**：勘误③正文行号
   `:2001/:2007` → **`:2003/:2008`**（9a0b9530 实测——omp 复审坐标抽查
   #9 亲核；语义零差，勘误③正文已就地精化；F0P-02 T1 转引同批改）。
7. **勘误⑥（omp plan 复审转写批登记，m-omp-1/2/4/6/7，2026-10-19）**：
   - **m-omp-1 工具数**：MCP stdio 工具数 27 → **32**（union 全数，
     M7-5 `all32`——`McpFinalSnapshotTests.swift:270` 亲核；源
     RESEARCH §6.2-11 行 stale〔RESEARCH.md:386〕，RESEARCH 正文不返
     工、执行以本数为准）；F0P-02 T7 面 11 已随批改 32。
   - **m-omp-2 读集终数勘定**：观察适配器读集 18 stale——omp 复审记
     「落地 19（双轨）」，**终值以落地代码 + D-F0P-01-2 T7 实测修正
     为准 = 17 reads**（恒 enabled、export presence 双读退役；
     `NSMenuBridge.swift:669-689` 亲核 = 11 deps 读 + 5 workspace 读 +
     1 metadata note 盒；D-F0P-01-5 终值条款在案）；F0P-02 全文
     18 → 17（T3 标题/action/ΔN 表/SC/files_modified 注记）。
   - **m-omp-4 willTerminate 机检读法**：F0P-01 T6 SC「转发形恰一处」
     grep 按字面命中 3（shell def + App def + App 注释）——机检读法 =
     转发**调用点** `\.applicationWillTerminate\(` 在 `LightamerShell
     .swift` 恰一处；F0P-01 冻结未触、P1 验收已过 T7——本勘误为读法
     留痕（P1 DECISIONS 顺带追记即可）。
   - **m-omp-6 worktree 供件步**：worktree 二进制配方须加「供件拷入
     `input/` + `Resources/AIModels`」一步（AR-02-03-ACCEPTANCE.md
     :52-53 audit 先例——缺供件 = 假性不等价/探针 fixture 缺席）；
     F0P-01 :450-452 冻结未触留痕；F0P-02 T5 已随批补。
   - **m-omp-7 MANIFEST 卷形态**：P1 落地 `.work/gui-acceptance/
     f0prime-p1/MANIFEST.md`（整批单卷）——F0P-01 :33 冻结未触留痕；
     F0P-02 files_modified/T7 引用随批改指 f0prime-p1 续写；单卷 vs
     分卷裁定 = **整批单卷续写**（P2 DECISIONS 注记承接）。
8. **勘误⑦（research-omp 复审路由项落位登记，2026-10-19）**：
   - **M1（测试基线 3905→3969/37/0）**：已由勘误①承接——omp research
     复审追认，零动作。
   - **M2（paste 族补 holdsControl 合取）**：**处方不采纳**——与勘误③
     语义零改裁定冲突（桥 paste 两臂 `NSMenuBridge.swift:413/:419`
     `hasPayload && !isReadOnly` 二元形亲核无 holdsControl；research
     复审自身亦证产线无合取）；paste 语义变更属 UI 行为变更，须走
     用户裁决面（勘误③显式申报不变）；**P2 AC 承接形 = F0P-02 T1
     enabler 二元形测试钉**（已在位）。
   - **M3（P3 退役清单展开）**：P3 承接 = F0P-03 T1 action 1/2（4
     static 全列 + `displayPlaneHash` 安全删除注记〔壳 :1980 自带副本〕
     + `PanoFailureCopy`/`McpWriteFaceBox`/`LightamerEntryPoint` 文件
     域原地保留去向表 + probe armed 旗标 :2451/:2488/:2725 对账）——
     已随批入 plan。
   - **M4（bridge AX/Close/Toggle）**：P1 腿已落（AX 迁移集 =
     D-F0P-01-3 在案；Close 项 = **实测零改**——D-F0P-01-5.1 A 臂 AX
     dump 证产线本无 Close Window 项、「不补 Close 项、不创新语义」
     行使结论）；P2 腿承接 = F0P-02 T1 AX 键断言 + softproof Toggle
     态断言腿——已随批入 plan。

## 三 plan 红线 front-matter（共用正本，三 plan 逐条引用）

1. **FIX2③ = `McpServerController.swift` 文件零 diff**（wiring 只调
   controller 公开面，壳交接不触文件——M7-3 FIX2③ 红线延续）。
2. **封存面零 diff**（M3-3 封存清单）：`LightamerIOP/` 全域、`*.metal`
   全域、`LightamerSidecar`、DrtRecord / TerminalTailPolicy /
   DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf /
   ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·
   WebPEncoder）/ NodeGraphCommand / sidecar schema（LightamerSidecar）/
   HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order /
   GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance——
   本批纯 App 壳域 + App bundle 测试域。
3. **无 QA 回切通道**（D-F0P-5）：禁 env 门（`LIGHTAMER_SHELL=legacy`
 形零命中）；回退单元 = git revert。
4. **翻转 commit 必须独立可 revert**：壳交接（entry 切换 + face 搬运 +
   bridge 装配 + menu Deps 接线 + ContentView :551 toolbar
   preset-manager openWindow 缝接线〔review M1——scene registry 翻转后
   不在场的替代缝〕）一个 commit 内聚（P1 T6）；revert 该 commit =
   SwiftUI lifecycle 完整恢复，无半态。
5. **xcstrings 零 diff 预期**：菜单键全走既有键 `String(localized:
   String.LocalizationValue(key))` 整字面量（F0PRIME 门① zh 栏 parity
   已实证 + 系统组标题现形本就英文）；如执行中出现意外新增键 = 尾块纯
   插入纪律 + DECISIONS 申报（历史键字节与顺序零触碰；zh-audit --check
   + --self-test 双 PASS）。
6. **LocalizationValue 禁形零命中**：`String.LocalizationValue("prefix_
   \(x)")` 插值动态查表键禁形（M2-9 F-2 禁令）；新本地化键一律显式
   switch 返回静态键（V14）。
7. **disable-not-unmount（agent 禁编辑面的 NSMenu enable 侧等价实现）**：
   agent 控制期禁编辑 = enabler 闭包读 `agentControl.holdsControl` +
   观察适配器 tracked 读集含 holdsControl + `handleMenu` stale-enablement
   backstop 再拦（spike 已形）；SwiftUI 侧 10 处 `.disabled(...holdsControl)`
   manifest 面**零触碰**（hosting 桥下原样存活）；门禁面（face ⑤ manifest
   行）重指 = P3 退役同 commit（勘误②）。
8. **测试基线权威数 = `3969/37/0`**（勘误 RESEARCH 3905；skip 37 = 35 基
   线 + 探针族 2，零漂移口径；第三种 skip 来源逐族差分申报禁静默吸收）。
9. **AppDelegate 类字节零改**（`LightamerApp.swift:168-216` 域 @
   `9a0b9530`——**仓内无 `AppDelegate.swift` 文件**，勘误④ m-omp-10；
   D-F0P-9 组合转发——delegate 新类型组合它，不改它；机检 = 该域
   `git diff` 零 hunk）。
10. **DEBUG fork 序零触**：entry 四把 fork（DEBUG flock fixture ×2 → MCP
    headless → AI worker → GUI）逐字保留（McpProjectToolsetTests 的
    STDIN_FILENO dup2 纪律依赖此序；壳交接只动 GUI 臂尾行）。
11. **L057 缝**：菜单/按钮 action 一律 `Task { await … }` hop +
    `PanelPresentation.begin`；`.runModal(` 在 `App/Sources` 零命中
    （P2 复跑机检）。
12. **UserDefaults 零新键（应用级显式键）**：NSWindow frame autosave 的
    系统 `NSWindow Frame *` 键 = AppKit 出厂行为（D-F0P-8），不在 KD-4
    登记面；应用级键零新增。
13. **--all 批准制 + 运行监视**：orchestrator 批准 + 8G 门 + MEMFAIL 机
    检（超门立即 kill）+ caffeinate -dis 包裹 + 测试宿主清理先核
    parentage（`ps -o ppid`——测试宿主 parent = 脚本进程树，GUI 实例
    parent = launchd，M2-7-3 先例）。
14. **C 档门控**：每 plan 执行+验收闭环后停汇报，等用户确认再放行下
    一 plan。
15. **生产改名纪律**：spike 实验名 `F0PrimeShell*` 不入产——生产形
    `LightamerShell*`（终名 DECISIONS 申报）；T6 后 `F0PrimeShell` 在
    `App/Sources` 零命中（机检）。

## 晨审推翻点索引（可推翻面速查）

- **D-F0P-1**：真窗控制器 ↔ 私有 selector（OS 演化失效风险自担）。
- **D-F0P-2**：toolbar 接受+登记 ↔ NSToolbar delegate 重造（P1 内加任务）。
- **D-F0P-3**：⌘W 1:1 对齐 ↔ 语义重定义（UI 行为变更超范围）。
- **D-F0P-4**：reopen/fullscreen 补行 ↔ 不补（走查面 15 必挂）。
- **D-F0P-5**：无回切 ↔ env 门（D-6 门失义自担）。
- **D-F0P-6**：恒主窗单源 ↔ keyWindow 判定入 P2。
- **D-F0P-7**：构造参数化 ↔ tracked-read 形。
- **D-F0P-8**：key `"LightamerMainWindow"` ↔ 改键名（P1 T6 前定）。
- **D-F0P-9**：组合转发 ↔ non-final 继承（信任根重构）。
- **D-F0P-10**：FB P3 收尾 ↔ 提前呈稿。
- **勘误②**：manifest 重指随 P3 退役原子落地 ↔ 按 §7 P2 行提前到 P2
  （双源窗口，不建议）。
- **OMP-M2 键命运**（P3 T1）：`ExportPanelRequestKey` 定义保留（(a)
  复审推荐案采纳——壳 :94 @FocusedBinding 活依赖 + 发布面四摘除后
  honest-degrade 零行为面）↔ 删键 + 壳 face 改 graph/note 直连（(b)
  ——含 :94 重指，多一壳侧 hunk）。
- **OMP-M3 T3-2 改形**（P2 T3）：re-arm 子测降级 obs 登记让渡（(a)
  plan 指引推荐——armObservation private 红线禁产线加缝）↔
  NSApp.mainMenu 稳定性代理断言（(b)）。
