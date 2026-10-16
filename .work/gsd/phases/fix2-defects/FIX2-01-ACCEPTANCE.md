# FIX2-01 ACCEPTANCE — 修复批 II 第一路独立验收（2026-10-16）

> 验收身份：zcode 第一路独立验收（夜间全自动授权在案，先例 D-07-3-T5-1）。
> 输入 = 修订版 plan（`dafcec88`+`029f84bc`）+ CONTEXT + CHECKER +
> SUMMARY + DECISIONS + 执行链 `da99ea2f..2427670e`（4 commits）+
> 证据域 `gui-acceptance/v2m/fix2-probe/`（含本批新增 `acc-*` / `t2-r*.log`
> 回填件）。**本文所有读数均为本路亲跑/亲采，非转述执行方。**

---

## 结论头

**PASS（代码面 T2/T3/T4/T5）/ T1 升级待裁追认（D-6 BLOCKED 判定成立，
三选一上报转入 orchestrator 裁决）+ 0 error 产物缺陷 + 1 error 级诊断翻案
（D-FIX2-4「per-file insert 静默失败」证伪——观察成立、机理误标，详见
§四.1）+ 4 minor 注记。**

- 全套独立复跑 **`TOTAL|3860/35/0|`（2079s，exit 0，七 bundle 全绿零
  MEMFAIL）** = 申报值逐位闭合（3857 + ΔN 3 精确；skip 35 = 24 基线 +
  11 RAW 供件漂移口径维持）。
- T2 合流 + watchdog 修法四面亲审成立；N≥3 导入亲跑 2/3 完成态 +
  1/3 零 grid 行（间歇独立复现，DB 法证 = 行恒落库、grid 刷新迟到）。
- T3 零码翻案核销追认；T5 四波 MANIFEST 逐行对表过（「零行以代码面
  证据替代屏面判据销账」声明复核成立）；红线族全 PASS 亲跑。
- D-6：探针定罪五读数独立复核成立（H1 三写点证伪 + H2 环签名本路
  自采 sample 坐实），BLOCKED 判定追认；本路验收意见 = 三选一中的
  **①接受降级 + 减树专项立项**（附带本路新观察三条入卷），③回退
  macOS 27 与 Lock-early 决策冲突不建议。

---

## 一、全套独立复跑（对账）

新鲜 `xcodebuild build-for-testing`（TEST BUILD SUCCEEDED）后
`caffeinate -dis Scripts/test-direct.sh --all`：

| bundle | 本路亲跑 | 执行方申报 | RSS |
|---|---|---|---|
| IOP | 687/5/0 | 687/5/0 | 7615MB |
| IOPParity | 460/3/0 | 460/3/0 | 7009MB |
| Layers | 494/5/0 | 494/5/0 | 808MB |
| Library | 729/4/0 | 729/4/0 | 622MB |
| Sessions | 284/9/0 | 284/9/0 | 1664MB |
| Export | 379/5/0 | 379/5/0 | 6430MB |
| App | 827/4/0 | 827/4/0 | 2832MB |
| **TOTAL** | **3860/35/0 \| 2079s** | 3860/35/0 \| 2070s | 零 MEMFAIL |

对账链 3857 + 3（T2 ImportProgressCoalescingTests）= 3860 精确；skip
35 = 24 + 11 口径维持（无第三种 skip 来源）。IOPParity 峰值 7009MB
8G 门内（±3% 方差注记下与执行方 8112MB 同域）。build-for-testing
新鲜度 = 本路重建（HEAD `2427670e`）；L055 假绿签名零现（七 bundle
全 `Test Suite 'All tests'` 总计段挂靠）。

## 二、红线族亲跑（029f84bc..HEAD 全窗）

`.metal` 零 diff ✓ / `LightamerIOP/` 零 diff ✓ / `LightamerSidecar.swift`
零 diff ✓ / 封存面九件（DrtRecord/GradeCatalog/Registry/HistoryStack/
V50Order/ExportFormatSpec/ImageIOEncoders/WebPEncoder/ExportQueueContract）
零 diff ✓ / `\.runModal(` App/Sources **全域零命中**（含
PanelPresentation——比禁令口径更严）✓ / LocalizationValue 插值禁形
regex 恰 1 命中 = `LightamerApp.swift:2069` doc comment 豁免锚 ✓
（`ExportInspectorView:534` 亲读 = 拼接形非插形，合法）✓ / UserDefaults
零新键（批内新增行 grep 空）✓ / xcstrings 零 diff ✓ / Project.swift
恰 T2 测试一行 + BUNDLE-MAP 一行（tuist generate 末位随批）✓。
批内 diff 面 = 9 文件（4 code + 5 docs），T1/T3 零产线 diff 申报成立。

## 三、T2 D-7 修法深审（`da99ea2f` 亲读）

- **非阻塞形（M-1①）**：`submit` = 锁内单槽 stash + fire-and-forget
  调度即返回，零 await；节流 sleep 在 drain 任务内不在 handler 内。
  handler 闭包 `{ [weak coalescer] snapshot in coalescer?.submit(snapshot) }`
  同步形 ✓——doc comment Defect A（actor↔main 互等）保持切断。
- **保序钉（M-1②）**：投递恒 `Task { @MainActor }` 单飞；单槽
  latest-wins；`ImportTaskAdapter` 单调钳亲读（`max(fraction,
  lastFraction)`，nil 尾面不经 adapter）belt-and-braces 在位 ✓。
- **终态恒穿透（双载体）**：`.completed/.cancelled` bypass 窗口 +
  supersede 在途 interim ✓；controller `importProgress = nil` 直写
  tail 零改动 ✓。终态与 drain 竞态两面（flushTerminal 先/后于唤醒
  drain）逐面推演均收敛无双投递无吞终态。
- **watchdog**：`os Logger`（subsystem com.kamasylvia.lightamer /
  category import-watchdog）tail 前一行，零行为变更 ✓。日志失聪口径
  见 §六.4。
- **测试判别力（+3 法亲读）**：TestClock 手拨钟注入（零真睡竞争面）；
  leading 即时 / 窗内合流 / 尾沿不丢 / 终态 bypass-supersede（含
  「窗缘后 superseded interim 不复活」负断言）/ 纯函数缝三臂。四语义
  （双载体断言之服务侧载体）覆盖成立；controller-nil 载体按构造不入
  coalescer（测试头注记言明）。
- **N≥3 轮导入亲跑（本路自备供件 /tmp/fix2acc-import 6 TIFF，生产链
  探针缝 `-la_editor_probe`）**：3 轮 = r1 ✓ 6/6 行 + 逐行
  loaded/rendered；r2 ✓ 6/6；**r3 FAIL（grid rows never arrived）**。
  完成轮 2/3 + 完成态发布 ≥ AC 的 N≥3（执行方口径）。
- **窄边界登记（本路自产，不阻断）**：importFolder 中途 throw 路径
  （如 rebuildFTS 抛）无终态 emit——若尾沿 drain 在 `importProgress =
  nil` 之后苏醒，陈旧 interim 写回 importProgress，而 runImport 入口
  `guard importProgress == nil else { return }` 将拒绝后续导入（重启
  app 自愈）。常规完成/取消路径被终态 supersede 封死，仅异常 throw
  路径可达。建议下批触此文件时补 tail 处 pending 清位。

## 四、独立发现（本路自产）

1. **【error 级诊断翻案——D-FIX2-4 机理误标】**「导入零行间歇 =
   per-file insert 静默失败（images 零行）」**被 DB 法证否定**。birth
   time 对齐执行方 11 轮项目库：三轮 FAIL 项目的 DB **全部含 6 行**
   （r1=B58CAA6A / r3=8F4D1DC5 / r9=AE849F33，WAL 落库；8F4D1DC5 的
   WAL 于本路 sqlite3 读取时 checkpoint，mtime 13:46 即此故）；插入
   发生在 `importFolder` 返回前 = 探针 10s 等窗期间行已在库。
   **真实失效模式 = grid 页刷新迟到**（projectURL 变更触发的库面
   reload >10s 未反映已落库行）——本路 r3 同型亲证（A8AC64C8：探针
   FAIL 后 app 存活期间 DB 出现 6 行，WAL 626KB）。执行方语料中唯一
   真零行 DB = `869ED347`（09:51 T1 时代，异轮语境，疑为此诊断的
   错误归纳源）。**影响**：观察本身（间歇 ~29%：4/14 跨两路）与登记
   （独立待研）成立，但机理标签会把下次排查引向 insert 路径而真因在
   库面刷新路径（疑 D-6/D-7 同族 main-actor 饥饿面）。**处置建议**：
   TODO/DECISIONS 的「per-file insert 静默失败」表述勘误为「grid 页
   刷新迟到（行恒落库）」，移交独立待研时以本节法证为起点。
2. **【minor·证据位】** MANIFEST W3 行与 SUMMARY 引用的
   `fix2-probe/t2-r*.log` 证据族实际存于 `/tmp/fix2t1/`（易失域），
   证据域内原缺席。本路已回填拷贝（`t2-round1.log` + `t2-r1..r10.log`
   + `watchdog-stream2.log`）入 `fix2-probe/`，指针现闭合；另有
   `/tmp/fix2t1` 大部探针语料（B1/B2/C1/C2/E 系/D1/rearm 等）仍在
   易失域，**重启即失**——建议 orchestrator 裁量是否再回填一轮
   （B/C/E 系是 threshold 定罪的原始证据）。
3. **【minor·探针缝】** `-la_editor_probe` 跑完 6 行后
   `NSApp.terminate` 在窗口被遮挡/非 frontmost 态不可靠（本路 2/2
   不退出，0% CPU idle 挂起；repro.sh 亦以 kill 收尾）——DEBUG 缝
   非产线缺陷，建议缝内补 `exit(0)` 兜底或配方明写 kill 收尾。
4. **【minor·churn 可见性门控】** 本路窗口遮挡态空载 gate=false 面
   CPU 0.7%（执行方可见窗 34%）——**churn 受窗口 on-screen 门控**
   （display-cycle 耦合，与 D-7 样本 Source1 UpdateCycle/
   NSDisplayCycleFlush 族一致）。leg面 idle 0.1%（关菜单后）亲测同口径。
   另：**legacy 面 File 菜单挂开态实测 41.5%**——菜单环在 legacy 面
   开菜单态同样点火（环归因 = 菜单机制的又一独立佐证）。三条一并
   入减树专项卷。

## 五、D-6 探针定罪独立复核 + 三选一表态

### 5.1 定罪复核（全部亲读/亲采）

- **H1-c 决定性读数**：`t1-editor-spin-transcript.log` 全量亲扫 =
  ContentView `@self` ×29984 + WorkspaceHostView `@self` ×29938，
  **零次非 @self 属性变更**；非 @self 行仅挂载一次性（phase/projectURL/
  gridModel/@identity 各 1）。「28k+ 重估零属性变更」读数独立坐实。
- **环身份**：`t1-menu-loop-sample.txt` :4488-4496 亲读 =
  flushTransactions(852)→graphDidChange(852)→appGraphDidChange(295)→
  makeMainMenu(254)→updateMainMenu(240)→invalidateProperties(239)→
  requestUpdate(231)→updatePreferences(231)，与 DECISIONS 数字逐一
  吻合；`PropertyList.prependValue`(21 hits) + `keyboardShortcut`(54)
  + `swift_getTypeByMangledName`(147) 在案。
- **本路独立复现（重开项目进编辑器）**：AX 菜单腿 Open Recent →
  Enter Editor → 编辑器面 **CPU 42-44%**（10s cputime 窗）+ 复现态
  截图（`acc-d6-editor-state.png`：项目编辑器面呈 legacy 空态卡 +
  filmstrip 占位 + No Image Selected——比执行方变体更重的一型）。
- **本路自采 sample（3s）环签名**：appGraphDidChange(65)→
  makeMainMenu(55)→updateMainMenu(52)→invalidateProperties(52)→
  requestUpdate(47)→updatePreferences + prependValue(9) 全链在位
  （`acc-d6-editor-sample.txt`）——**环身份独立坐实，非依赖执行方
  采样**。
- **threshold 面抽验（廉价等效）**：完整 C1/E1-E3 摘除实验需 scratch
  重建本路未重跑；以树差隔离 + 菜单态两点抽验替代——legacy 面（无
  gate=false 树）idle 0.1% vs 同机 gate=false 编辑器面 42%；legacy
  开菜单态 41.5%（菜单环点火与树无关、与菜单机制有关）。与
  「threshold 形持续条件」叙事相容；E1/E2/E3 三向读数维持执行方
  记录口径（注记：其独立 evidence 文件仅 C1/C2 sample，E 系读数
  载于 DECISIONS 文字）。
- **修法不可落地裁定追认**：无写点可断（第 3 条读数即定罪）；H2
  备案 C1 实测（摘 .inspector 编辑器面环照转 53% + 点击零响应
  `t1-filmstrip-click-dead.png` 亲读）换不来 spin 消失——行使收益
  零，备案不行使正确。三铁条未过如实 BLOCKED、不硬造判定，追认。

### 5.2 「H2 = macOS 27 SwiftUI 框架缺陷」结论独立表态

**成立（高置信）**：环三层全框架帧 + app 树零写点（@self-only 决定性
读数）+ 环身份签名本路自采复现 + legacy/occluded 双向反证隔离。
保留措辞建议：H2 的精确定性 = **「macOS 27 SwiftUI 菜单/焦点更新
机制在特定树形（重树 + .inspector 分栏宿主 + 三段内容）下不收敛」**
——是框架缺陷面与特定 app 树形的合谋，非任意树都触发（legacy 树
idle 零 churn 为证）。此措辞对专项立项的目标树形圈定有直接价值。

### 5.3 三选一验收意见

**选 ①：接受降级 + gate=false 壳减树/窗口内容拆分专项立项。**

- ③（回退 macOS 27 目标评估）与 PROJECT.md Lock-early 决策（最低
  macOS 27）直接冲突，且 RAW 9/原生 AVIF 能力面绑定的不只是本缺陷，
  不建议作为可选项上报（除非用户亲自推翻 Lock-early）。
- ②（research 复审）边际价值有限——五读数已决定性（写点不存在是
  可机检事实）；复审更适合作为专项的第一步（带 §四.4 三条新观察 +
  本节独立复核数据入卷），而非独立选项。
- ① 的专项范围建议：a) 减树（拆 `.inspector` 分栏宿主依赖 +
  safeAreaInset 横幅族入子窗/覆盖层）；b) 窗口内容拆分（编辑器面
  独立 NSWindow 路线评估）；c) 菜单环侧）（Commands 求值面减频——
  `visibleMenuCommands` 门内 menu 重建频度与 `prependValue` 无去重
  的组合是环的燃料）；d) 上游通道：macOS 27.x 系统更新验证 +
  Apple Feedback 提交（环签名 sample 可直接附）。注：C 档用户裁决点
  不变——专项立项本身待用户定向。
- 降级期内可用性止损注记：窗口遮挡态 churn 归零（§四.4）——「把
  Lightamer 窗口最小化/遮挡即可止损」可作为降级期用户侧 workaround
  记入挂账行（无需代码）。

## 六、偏差四项裁决

1. **T1 结构性偏差行使（修法不可落地 → BLOCKED 上报）**：**合规**。
   行使依据在 plan 内（M-8 区间裁定路径 + 执行纪律停手汇报条款）；
   行使形态合规（代码面零 diff + 不硬造判定 + 三选一上报 + 非 D-6
   依赖波次不受阻继续）。追认。
2. **导入零行间歇新观察**：**观察成立、登记合规；机理标签错误**
   （§四.1 翻案）。移交前须先勘误标签（insert 失败 → grid 刷新
   迟到），否则独立待研立项即带错起点。
3. **NLMeans flake（首轮窗外 crash 1 例）**：**追认**。crash 证据
   （t4-all.log `terminated abnormally` + exit=133 + peak 5090MB）
   亲读在案；隔离重跑 687/5/0 + 全套重跑绿 + 本路独立全套轮 IOP
   687/5/0 三轮互证；flake 台账延续先例（波 1 GrainTests / 波 2
   ProcessVersionCarrierTests 同族口径）。不构成对账阻断。
4. **watchdog 日志失聪证据口径**：**接受为诊断面现状 + 注记改进**。
   失聪亲证成立（`log stream --process Lightamer` 捕获系统级消息但
   零 import-watchdog 行——`watchdog-stream2.log` 亲读 0 命中）；
   tail 已过的旁证（R9 轮 progress=nil）成立。**注记**：失聪疑似
   stream 未带 `--level info`（`.info` 级默认不入 Default 流）而非
   硬环境限制——下次 D-7 族开工时以
   `log stream --level info --predicate 'subsystem == "com.kamasylvia.lightamer"'`
   一行验证即知；若仍失聪再考虑落文件通道。

## 七、T5 走查四波 MANIFEST 终态逐行对表

三源对表（V2M-VALIDATION §挂账② + v2m/MANIFEST wave-2 终表 +
m6-closeout 总队列）：E2-1 四行（T1-02/D3-01/D4-01/D5-01）+ 挂账②
硬义务（03/05/06/07/08）+ 32/33（W2 尾）+ W3 D-7 复验 + W4（16-19/
34-38/40）+ 排除清单（24/25/26/27-31/39 + 10/12/14 逐行理由）——
**行集完备、无缺行无双计**（M-4/M-5 配套钉兑现）。

- W1/W2/W4 Blocked 族三源（D-6 / cmd+click 旗标 / 面板 /tmp）逐行
  证据亲读：`t1-editor-d6-state.png`（D-6 态）✓ /
  `t5-w2-multiselect-cmdflag-dead.png`（两次 cmd+click 后单格 ring =
  REPLACE 非 toggle，判据面成立）✓ / `t5-w3-panel-tmp-unsearchable.png`
  （Spotlight 对 /tmp 搜索空转）✓。
- **「快照上移」返工不触发**追认：对话框从未呈现（通道死）≠ 复验
  见 0，与波 2 双路追认同裁定；返工 contingency 面
  （SessionBrowserView.swift）零 diff 与申报一致。
- **「零行以代码面证据替代屏面判据销账」声明复核：成立**——唯一
  Executed 标记的两行（T3 配方三步 / D-7 生产链完成态）均有屏面或
  生产链运行证据；D-7 的「生产链口径」经本路亲读探针缝坐实（走
  `controller.runImport` 产线路）；GUI 对话框腿如实 Blocked 未混记。
- D-7 生产链数字 8/11 逐轮亲核**精确吻合**（本路 §四.1 DB 法证另证
  其「零行」三轮行恒落库）。
- F-1 cancel 腿未触达登记 ✓（挂账维持，只记录不修条款兑现）。

## 八、T3 D-8 翻案核销追认

- 真腿三步证据（`t3-legacy-step{1,2,3}`）亲读：step2 = legacy 面
  Single 模式带图渲染 + 右栏调整栈（Temperature/Tint 6504K）+ Ready。
- 本路 legacy 面亲启亲测：File 菜单件清单含 **New Session… /
  Open Session… / Close Session**（真腿在位）+ **idle CPU 0.1%**
  （与 MANIFEST 配方节 0.0-0.1% 口径一致）。
- 「inert-by-design」锚 `LightamerApp.swift:1600` 亲读 =
  `.disabled(libraryProjects.projectStore == nil)` ✓。
- 配方固化落点 = MANIFEST「FIX2-01 批 T3 legacy 通道正确配方」节
  （含 W4 复走映射表）✓；核销口径 = **翻案核销（走查错腿 +
  inert-by-design），非代码修复**（TODO/VALIDATION 行措辞亲核合规，
  Checker #5 兑现）✓；T3 `git diff --stat` 仅 docs ✓。

## 九、台账时序与产物面

- M-6 时序钉：T4 commit（e46ca566）GOAL-STATE = 「T5 走查复走批执行
  中」非 closed ✓；T5 末 commit（2427670e）方翻「修复批 II closed →
  新特性立项待用户定向」✓（历史行追加不改写亲核）。
- TODO 三行翻账口径亲核：D-6 open（三选一待裁）/ D-7 fixed（W3 收口
  注记）/ D-8 翻案核销非「已修复」✓。AGENTS FIX2 行在位 ✓。
- commit 链 = `da99ea2f`（T2 产线+测试+登记）+ `4ee0ccd6`（T2/T3
  裁定 docs）+ `e46ca566`（T4 对账+台账）+ `2427670e`（T5 收口）；
  未 push ✓（remote 状态本路未触）。
- 验收波产物：本文件（FIX2-01-ACCEPTANCE.md）+ 证据域回填 12 件
  （t2-r*.log ×11 + watchdog-stream2.log）+ 本路亲跑证据 5 件
  （acc-round{1,2,3}.log / acc-d6-editor-sample.txt /
  acc-d6-editor-state.png）。零产线 diff；未 push。

## 十、移交决策项（orchestrator）

1. **D-6 三选一**：本路意见 = ①（§5.3）；专项卷建议带上 §四.4 三条
   新观察（可见性门控 / legacy 开菜单态点火 / 菜单环燃料面）。
2. **D-FIX2-4 机理标签勘误**（§四.1）：TODO/DECISIONS「per-file
   insert 静默失败」→「grid 页刷新迟到（行恒落库）」——建议下批
   docs 顺手修（一行级）。
3. `/tmp/fix2t1` 剩余探针语料（B/C/E 系 threshold 原始证据）是否
   回填证据域（重启即失，§四.2）。
4. 双重验收（dual_acceptance）：本路 PASS 收口后按制度串行呼叫 omp
   二次验收（computer-use 单实例约束）。

---

> 验收人：FIX2-01 第一路独立验收 subagent（zcode，2026-10-16）。
> 亲跑清单：全套 --all ×1（2079s）/ 导入轮 ×3 / D-6 重开复现 ×1 +
> 自采 sample ×1 / legacy 面亲启 ×1 / 红线族机检 ×9 项 / DB 法证
> 16 项目库 / 探针语料全量亲读（transcript ×2 + sample ×5 + 11 轮
> 日志）。
