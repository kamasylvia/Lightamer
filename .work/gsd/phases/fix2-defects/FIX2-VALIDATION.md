---
phase: FIX2（修复批 II）
slug: fix2-defects
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-16
---

# Phase FIX2（修复批 II）— Validation（D-6 探针定罪降级裁定 + D-7 合流修复 + D-8 翻案核销：双路独立验收 PASS 的闭环签核）

> 体例对齐 `phases/v2-maintenance/V2M-VALIDATION.md`（正本链上溯
> `phases/m2-11-performance/M2-11-VALIDATION.md`）。**双重验收
> （dual_acceptance）双路 zcode 独立验收全部落终态后成文**：第一路
> （`FIX2-01-ACCEPTANCE.md`）+ 第二路（`FIX2-01-ACCEPTANCE-2ND.md`，
> 零共享上下文）**双路 PASS / 0 error 产物缺陷、零实质分歧**——三路
> （执行方 + 两验收路）全套 `--all` **`TOTAL|3860/35/0|` 同值**
> （2070s / 2079s / 2059s，exit 0、七 bundle 全绿零 MEMFAIL），对账链
> **3857（V2/Maintenance 终态基线）+ ΔN 3（T2 `ImportProgressCoalescingTests`）=
> 3860 精确**；skip 35 = 24 基线 + 11 真 RAW 供件域漂移（口径维持）。
> 执行链 = `da99ea2f..2427670e`（4 commits；T2 产线+测试 1 + docs 3，
> T1/T3 零产线 diff）。**翻账只认证据**：裁定正本 =
> `FIX2-01-DECISIONS.md`（D-FIX2-1..5）+ 两份 ACCEPTANCE 六份亲跑/亲读
> 记录。**批内两大裁定**：①T1 D-6 探针定罪（H1 写点假说三连证伪 →
> **H2 = macOS 27 SwiftUI 菜单/焦点更新机制在特定树形下不收敛**）修法
> 不可落地 BLOCKED，**双路同判三选一 = ①接受降级 + gate=false 壳减树/
> 窗口内容拆分专项立项**；②D-FIX2-4 诊断翻案三腿封死——「导入零行
> 间歇 = per-file insert 静默失败」被双路 DB 法证证伪，真实失效面 =
> **grid 页刷新迟到**（行恒落库），勘误六处随本 VALIDATION 批落账。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest。**+3 法**（App 824→827：`ImportProgressCoalescingTests`——TestClock 手拨钟注入零真睡 + leading 即时/窗内合流/尾沿不丢/终态 bypass-supersede〔含「窗缘后 superseded interim 不复活」负断言〕+ 纯函数窗口判定缝三臂；Project.swift 恰一行 + BUNDLE-MAP 恰一行，tuist generate 末位随批〔L041〕）；T1 ΔN=0（断环缝不可纯函数化，视图级 seam——D-3 先例）；T3 零码 |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/crash 签名/no-total-line 机检全挂靠——L055 双保险本批三路亲证有效：执行批首轮 IOP NLMeans 窗外 crash 被正确置零计数**非假绿**） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3860 tests / 35 skip / 0 fail**（执行方 2070s + 第一路 2079s + 第二路 2059s 三路独立亲跑同值，exit 0 零 MEMFAIL，七 bundle 全 8G 门内）；逐 bundle（三路逐位一致）：IOP **687/5/0**〔7189-7701MB〕/ IOPParity **460/3/0**〔7009-8112MB 贴线带内〕/ Layers **494/5/0** / Library **729/4/0** / Sessions **284/9/0** / Export **379/5/0** / App **827/4/0**——段和 687+460+494+729+284+379+827 = 3860 机械闭合 |
| **基线演变** | 3857（V2/Maintenance 终态）→ +3（T2 合流测试）= **3860 终态**；对账链 3857+3 = 3860 精确 |
| **skip 35 构成声明** | 与 V2/Maintenance 终态同值同构成 = 基线恒有 24 + 真 RAW 供件域漂移 11；无第三种 skip 来源（三路独立亲核） |
| **在案发现（本 phase 事件）** | **零 error 级产物缺陷、零 open minor**；1 error 级**诊断翻案**（D-FIX2-4「per-file insert 静默失败」证伪——观察成立、机理误标，勘误本批落账，见 §特殊事项 1）；2 分歧记录（点击表型输入路径混淆 / legacy 菜单点火适用域收窄——均不影响判定，见 §特殊事项 4/5）；NLMeans 窗外 crash flake 1 例（隔离重跑绿 + 全套重跑绿 + 双路独立全套轮 IOP 687/5/0 四轮互证——flake 台账延续先例）；watchdog 日志失聪 = 诊断面现状 + `--level info` 缺失假说注记（下批 D-7 族开工一行验证） |
| **GUI 证据** | **Blocked 族如实登记不硬造判定**（Checker #6 条款）：T5 四波走查可走行全走（T3 配方三步 Executed + D-7 生产链完成态 Executed〔`-la_editor_probe` 走 `controller.runImport` 产线路，11 轮 8 完成态〕）；Blocked 族三源（D-6 编辑器面交互行 / cmd+click 多选旗标判死再证 / import 面板 /tmp 供件不可达）逐行证据亲读双路追认；「零行以代码面证据替代屏面判据销账」声明双路复核成立（唯一 Executed 标记两行均有屏面/生产链运行证据）；D-4「快照上移」返工预案不触发（对话框从未呈现 ≠ 复验见 0，与波 2 双路追认同裁定） |
| **zh 对账** | xcstrings **零 diff**；UserDefaults **零新键**；`\.runModal(` App/Sources 全域零命中；LocalizationValue 插值禁形 regex 恰 1 命中 = `LightamerApp.swift:2069` doc comment 豁免锚（`ExportInspectorView:534` 亲读 = 拼接形非插形，合法） |

## SC/AC 生效值对照（plan 修订版 `dafcec88`+`029f84bc` 裁决落点终态）

| # | 生效值 | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **D-6 判别探针定罪先行**（两段形探针：View 面 `_printChanges` + App/Scene 面手动桩；五条读数裁决 H1/H2；修法不可落地 → M-8 结构性偏差 BLOCKED 上报三选一，不硬造判定） | T1 零产线 diff | **Delivered（BLOCKED 分支行使，双路追认合规）**：H1-a（onGeometryChange 写环，4 tick 零振荡）/ H1-b（`.focusedSceneValue` 双写点 B1/B2 摘除 churn 不变）/ H1-c（任意 app 写点——**决定性**：编辑器面 ~60k 次重估〔14298+29984 两窗亲扫〕**全部 `@self`、零属性变更**，深层七视图仅挂载一次）三连证伪；**环身份** = `flushTransactions→graphDidChange→appGraphDidChange→makeMainMenu→updateMainMenu→invalidateProperties→requestUpdate→updatePreferences` 自持环（六符号三路自采 sample 独立坐实；`PropertyList.prependValue` 逐 pass 无去重 + `swift_getTypeByMangledName` 热帧）；**持续条件 = threshold 形**（空载摘 `.inspector`/双 safeAreaInset 任一饿死；编辑器三段内容任摘一段饿死；焦点写点/List→LazyVStack/动画摘除全不饿死）；H2 备案臂 C1 实测（摘 `.inspector` 编辑器面环照转 53% + 点击零响应）换不来 spin 消失——行使收益零，不行使正确。**H2 精确定性（双路共识措辞）** = 「macOS 27 SwiftUI 菜单/焦点更新机制在特定树形〔重树 + `.inspector` 分栏宿主 + 三段内容〕下不收敛」——框架缺陷面与特定 app 树形合谋，非任意树触发（legacy 树 idle 0.1% 为证）；表型终态 = **功能态-with-churn**（第二路：遮挡杀 spin CPU 归零 + 解遮不复燃 + 一次点击即恢复编辑并复燃 churn）。**三选一双路同判 = ①接受降级 + gate=false 壳减树/窗口内容拆分专项立项**（③回退 macOS 27 与 Lock-early 决策冲突不取；②research 复审五读数已决定性，并入专项首步） |
| 2 | **D-7 进度投递合流 + watchdog**（非阻塞形 M-1①：handler 锁内单槽 stash + fire-and-forget 调度零 await；保序钉 M-1②：投递恒 `@MainActor` 单飞 + 单槽 latest-wins + adapter 单调钳；终态恒穿透双载体：`.completed/.cancelled` bypass + supersede 在途 interim，controller nil 直写 tail 零改；watchdog os Logger 一行零行为；App +3 法判别力亲证） | T2 `da99ea2f` | **Delivered**：代码面四面（非阻塞/保序/穿透/watchdog）双路独立亲审成立；doc comment Defect A（actor↔main 互等）保持切断；**N≥3 导入轮亲跑** = 执行批 11 轮 8 完成态（6/6 行落库 + 逐行 loaded/rendered）+ 第一路 3 轮 2 完成态 + 第二路 3 轮 **3/3 完成态**（自备供件全新文件名）——≥AC 的 N≥3 满足；间歇零行经三腿法证勘误为 grid 刷新迟到（见 §特殊事项 1），不影响本 AC（完成态发布面）；窄边界两枚登记（§挂账③） |
| 3 | **D-8 翻案核销（零产线 diff）**：真腿亲证 + 配方固化 + 核销口径 = 翻案（走查错腿 + inert-by-design）非「已修复」 | T3 零码 | **Delivered（翻案核销追认）**：真腿 = 打开会话… ⌘⇧O / Open Recent 会话列表全链路亲证可用（建会话网格带图 CPU 0.1% → 双击进编辑器 Single 带图渲染 + 右栏调整栈 mount → 返回图库；三步截图 `t3-legacy-step{1,2,3}`）；第一路亲启 legacy 面复核（File 菜单件清单含 New/Open/Close Session + idle 0.1%）；「inert-by-design」锚 `LightamerApp.swift:1600` `.disabled(libraryProjects.projectStore == nil)` 亲读；配方固化 = MANIFEST「FIX2-01 批 T3 legacy 通道正确配方」节（含 W4 复走映射表）；V2 #4 SESSION-LEGACY-READONLY 无「先修通道」前置；TODO/VALIDATION 行措辞「翻案核销非已修复」双路亲核合规 |
| 4 | **红线族机检**（029f84bc..2427670e 批窗：`.metal`/`LightamerIOP/`/sidecar/封存面九件零 diff；runModal 零；插值禁形豁免锚亲读；UserDefaults 零新键；xcstrings 零 diff；Project.swift 恰两登记行） | T4 | **Delivered（双路独立亲跑全 PASS）**：批窗 `git diff --stat` = 9 文件（4 code + 5 docs），T1/T3 零产线 diff 申报成立；批外新 HEAD `a35a734e`（Alcedo CLI/AI 调研 docs，另一会话产物）零产线文件不触批窗（第二路双窗机检亲证）；L055 假绿签名三路零现 |
| 5 | **T5 走查复走四波**（可走行全走 + Blocked 如实登记 + 排除清单逐行理由 + M-4/M-5 行集完备钉） | T5 `2427670e` | **Delivered（双路三源对表追认）**：W1 = D-6 三铁条 Blocked-升级（T1 未过）+ V2M-T1-02/M6C-03/05/06/07 Blocked-Channel；W2 = 配方前置 Executed（T3 亲证）+ D3-01/D4-01〔cmd+click 旗标判死再证，两次独立通道，对话框从未呈现 → 返工预案不触发〕/D5-01/08 + 32/33 Blocked-Channel；W3 = D-7 复验 **Executed（生产链口径）** + 面板腿 Blocked-Channel〔Spotlight 不索引 /tmp + ⌘⇧G 判死 + 家目录禁令〕+ F-1 未触达挂账维持 + 零行间歇 Registered；W4 = pano 16-19/栈面 34-38/40 Blocked-Channel；排除清单 10/12/14/24-31/39 逐行理由注记；第一路全量对表 + 第二路错开抽验 14 行——**行集完备、零缺行、零双计** |
| — | **AC 零回归门** | T4 + 双路机检 | **Delivered**：见 Test Infrastructure zh 对账行 + 红线族行；全套终验 3860/35/0 三路同值（六 bundle 逐值零漂移——唯一 Δ = App 824→827 = 本批 +3 法自身） |

## 双重验收记录（dual_acceptance 链）

| 路 | 结论 | 证据要点 | 分歧与处置 |
|---|---|---|---|
| **第一路 zcode 独立验收**（2026-10-16，零共享执行方上下文） | **PASS / 0 error 产物缺陷 + 4 minor 注记**（+1 error 级诊断翻案 D-FIX2-4） | 全套自建亲跑 **3860/35/0**（2079s）+ T2 修法四面亲读 + 导入轮 ×3（自备供件）+ D-6 重开复现 + **环签名自采 sample 坐实**（不依赖执行方采样）+ threshold 面树差隔离廉价等效抽验 + legacy 面亲启 + 红线族机检 ×9 + **DB 法证 16 项目库**（翻案第一腿）+ 探针语料全量亲读（transcript ×2 + sample ×5 + 11 轮日志）+ T5 全量对表 + T3 亲启复核 | 4 minor：①D-FIX2-4 勘误（本批落）②`/tmp/fix2t1` B/C/E 系易失（本批回填落账）③探针缝 `NSApp.terminate` 遮挡态不可靠（挂账⑤）④churn 可见性门控 + legacy 开菜单态点火 + 菜单环燃料面三条新观察（入专项卷） |
| **第二路 zcode 独立眼**（零共享第一路上下文） | **PASS / 0 error 产物缺陷 + 2 minor 自产**（D-FIX2-4 翻案三腿二次坐实） | 全套新鲜构建亲跑 **3860/35/0**（2059s）三轮互证逐位一致 + T2 独立导入轮 **3/3 完成态** + **DB 法证 16 包全量亲查**（`sqlite3 -readonly` 防 checkpoint 副作用）+ **行为级重开实验**（`A8AC64C8` fresh reload 6/6 可见 = 翻案第二腿）+ 逐轮日志 12 件亲核（翻案第三腿）+ 环签名自采 sample ×2 + 遮挡断环/点击恢复 A/B 实验 + 编辑器面 CPU 82-100% 硬门亲测 + 红线族双窗机检 + 三源对表错开抽验 14 行 + 第一路 4 minor 全裁决 | 2 分歧记录（不阻断）：①点击表型输入路径混淆——本路 cliclick 真实鼠标 3/3 全响应（含 1 次无遮挡直接点击）vs 执行批 AXPress「零响应」截图；假说 = AXPress 合成路径 vs CGEvent 真实鼠标输入通道差异或间歇表型，不影响 T1 CPU 硬门判定 → 挂账④专项双通道对照；②legacy 菜单点火适用域收窄——本路空 legacy 面菜单挂开态 0.0% vs 第一路 41.5%（其面带图会话），点火条件疑与「菜单环 × 面内容复杂度」相关，第一路观察维持其记录口径 |

双路终态：**零 error 产物缺陷、零 open minor、零实质分歧**（两路独立
全套同值 3860/35/0 + D-FIX2-4 翻案三腿互证 + D-6 三选一同判 ① +
T5 对表互证）——**dual_acceptance 意图满足**。omp 制度路本批未派
（双 zcode 独立眼先例沿用——M6-2/M6-3/M6-4 同款；晨审可裁）。

## Per-Plan Map

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| FIX2-01（修复批 II：D-6/D-7/D-8 三缺陷 + T4 红线 + T5 走查） | T1 D-6 判别探针定罪（五读数 + H2 坐实 + BLOCKED 三选一上报，零产线 diff）→ T2 D-7 `ImportProgressCoalescer` 合流 + watchdog + 测试 +3 法 → T3 D-8 翻案核销（零码）→ T4 红线族机检全 PASS + 台账 → T5 四波走查收口 | worker 四提交 `da99ea2f..2427670e`；未 push | 双路 PASS / 0 error 产物缺陷零实质分歧；三路全套 3860/35/0 同值；T1 BLOCKED 双路追认合规 + 三选一双路同判 ① |

零红线域终态（三路亲跑，`029f84bc..2427670e` 批窗）：`.metal` 全域 =
**0 diff**；`LightamerIOP/` = **0 diff**；`LightamerSidecar.swift` =
**0 diff**；封存面九件（DrtRecord/GradeCatalog/Registry/HistoryStack/
V50Order/ExportFormatSpec/ImageIOEncoders/WebPEncoder/ExportQueueContract）
= 0 diff；`Project.swift` = 恰一行测试登记 + BUNDLE-MAP 恰一行
（dependencies 块零 diff，**零新 SPM**）；UserDefaults = **零新键**；
runModal = 0；LocalizationValue 插值禁形 = 恰 1 豁免锚；xcstrings =
0 diff。FIX2 修法形态与范式沉淀见 AGENTS「V2-Maintenance 架构增量」节
FIX2 两行（执行批行 + 闭环行）。

## 挂账单一清单（FIX2 单一移交清单，六项）

1. **D-6 专项立项（charter 门待用户，本批最大移交项）**：双路同判 =
   ①接受降级 + **gate=false 壳减树/窗口内容拆分专项立项**。专项卷
   charter 候选内容：a) 减树（拆 `.inspector` 分栏宿主依赖 +
   safeAreaInset 横幅族入子窗/覆盖层）；b) 窗口内容拆分（编辑器面独立
   NSWindow 路线评估）；c) 菜单环燃料面减频（`visibleMenuCommands` 门内
   menu 重建频度与 `prependValue` 无去重组合）；d) 上游通道 = macOS
   27.x 系统更新验证 + **Apple Feedback 提交**（环签名 sample
   `t1-menu-loop-sample.txt` / `acc2-d6-editor-sample*.txt` 可直接附）+
   **macOS 27.1 release notes 监测**；e) 走查专项卷 = 第一路 §四.4 三条
   （可见性门控 / legacy 开菜单态点火 / 菜单环燃料面）+ 第二路 §5.2 四条
   （遮挡断环不复燃 / 点击恢复 / 输入路径分歧 / 菜单点火适用域）+
   H2 精确定性措辞 + 五读数全帧行集。**workaround 已补记用户可及文档
   （本批落）**= README「Known issues」节：窗口最小化/完全遮挡即断环
   （CPU 归零），解遮后一次点击即恢复编辑。
2. **D-FIX2-4 勘误 + workaround 文档化（均已本批落账 ✓）**：「per-file
   insert 静默失败」→「**grid 页刷新迟到**（行恒落库、WAL 在案、fresh
   reload 自愈）」六处标签勘误落点 = ①TODO D-7 行 ②AGENTS FIX2 行 ④
   ③MANIFEST「FIX2 批同场证据指针」T2 节 ④MANIFEST W3 Registered 行
   ⑤DECISIONS D-FIX2-4 节尾勘误注记（原文保留）⑥GOAL-STATE 移交句
   （随新续接点承载）；独立待研立项以双路三腿法证为起点（DB 法证 16 包
   / 行为级重开实验 / 逐轮日志），勿再循 insert 路径排查。workaround
   用户可及文档补记 = README Known issues（同上）。
3. **T2 窄边界两枚（下批触 LibraryProjectController 时顺手）**：①
   throw-path stale-interim（`importFolder` 中途 throw 无终态 emit，
   armed drain 苏醒回写陈旧 interim → 后续导入被拒，重启自愈——第一路
   发现 + 第二路代码面独立复核）；②flushTerminal-vs-tail 理论竞态
   （主 actor 无契约 FIFO，tail nil 先于 flushTerminal 执行则终态滞留
   `.completed`，概率极低——第二路新登记）。同根修法 = tail 处对
   coalescer `cancelAndClear()`（锁内清 pending + 置代际/取消位）。
4. **点击表型双输入通道对照（入 D-6 专项走查卷）**：cmd+click 多选旗标
   判死（W2 D4-01 两次独立通道）与 filmstrip「点击零响应」（执行批
   AXPress）vs「3/3 全响应」（第二路 cliclick 真实鼠标）的输入路径
   混淆——专项走查对 filmstrip/多选一律 **AXPress + cliclick 双通道
   对照复测**再定表型边界（AXPress 伪象 vs 间歇真死）。
5. **探针缝 `exit(0)` 兜底（下批触 WorkspaceHostView DEBUG 缝时顺手）**
   + **/tmp B/C/E 系回填（本批落 ✓）**：`-la_editor_probe` 跑完
   `NSApp.terminate` 在窗口遮挡/非 frontmost 态不可靠（第一路 2/2 +
   第二路 3/3 复现）——缝内补 `exit(0)` 兜底或配方明写 kill 收尾；
   `/tmp/fix2t1` B/C/E 系 threshold 定罪原始证据 24 候选件已回填
   `gui-acceptance/v2m/fix2-probe/`（21 件新入域 + 3 件与既有 t1-*
   字节恒等跳过〔b2-sample = t1-c2-burst-sample /
   c1-sample = t1-c1-inspector-off-sample / rearm-sample =
   t1-menu-loop-sample，md5 亲证〕；d1/rearm 等 DECISIONS 引用件全
   闭合）——易失域清账，第三次警告解除。local-only 不入 git 惯例维持。
6. **导入零行间歇（grid 刷新迟到族）登记备查**：观察成立（间歇 ~29%：
   4/14 跨两路独立复现）+ 勘误后机理 = grid 页刷新迟到（>10s，行恒
   落库）——疑 D-6/D-7 同族 main-actor 饥饿面；独立待研立项与否待用户
   （若 D-6 专项修后 churn 消失，本表型或随之消解——立项前先在专项后
   复测一轮）。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。plan 全部 SC/AC 每条均有 ≥1 机器锚
  （T2 +3 法 TestClock 手拨钟判别力亲证 + grep 结构机检族；T1 定罪 =
  `_printChanges` transcript 计数机检 + sample 符号统计 + 三路自采互证；
  T4 红线族 9 项机检双路亲跑）+ ≥1 实证背书（三路全套同值 3860/35/0 +
  对账链 3857+3 精确 + 段和机械闭合 + D-FIX2-4 三腿法证 + D-6 环签名
  三路自采 sample 独立坐实 + N≥3 导入轮三路亲跑）。
- 采样密度：全 AC 逐条机检 + 双路零共享上下文独立验收（各自自建 build +
  各自全套 `--all` 亲跑，第二路证据亲跑/亲读重取不复述第一路）+ 修法
  深审含独立复现（T2 三路各自自备供件导入轮 / T1 三路独立 sample 采集 /
  翻案双路独立 DB 法证 + 行为级实验）；「无证据 ✅」零项。
- 数字对账：三路互证（3860/35/0 逐值一致 + ΔN=+3 分解亲证 + 段和
  687+460+494+729+284+379+827 = 3860 机械闭合）；skip 35 = 24+11 三路
  一致；D-7 生产链 8/11 逐轮亲核精确（12 件日志双路亲读）。

## 特殊事项入册（phase 级事件台账）

1. **D-FIX2-4 诊断翻案（本 phase 最重方法事件，三腿封死）**：执行批
   「导入零行间歇 = per-file insert 静默失败（images 零行）」诊断被
   双路独立法证**证伪**——①DB 法证腿：执行批 FAIL 三轮 + 第一路 FAIL
   轮的项目 DB **全部含 6 行**（WAL 落库，插入发生于探针 10s 等窗期间；
   16 包全量亲查 `sqlite3 -readonly`）；②行为级腿：FAIL 项目 fresh
   reload 后 6/6 全可见（失效面锁定 import 完成时的 grid 刷新时机——
   nil 终态触发的 `reloadFirstPage` 被 churn/饥饿延迟 >10s）；③逐轮
   日志腿：8/11 申报数字精确吻合 + FAIL 轮号与 DB 映射一致。唯一真零行
   DB `869ED347` = T1 时代异轮语境（疑错误归纳源）。**观察本身（间歇
   真实性 + 登记合规）成立，机理标签错误**——勘误六处本批落账（§挂账②）；
   教训 = 「诊断捕获面 lastError=nil」是**缺证**不是**零行**的证据，
   零行断言须先 DB 取证。
2. **T1 结构性偏差行使（修法不可落地 → BLOCKED 上报）双路追认合规**：
   行使依据在 plan 内（M-8 区间裁定路径 + 执行纪律停手汇报条款）；行使
   形态合规（代码面零 diff + 不硬造判定 + 三选一上报 + 非 D-6 依赖
   波次不受阻继续）；SC 的 CPU<10% 硬门与「spin 消失/点击出图」铁条
   未过如实 BLOCKED（执行批 48-53% + 第一路 42-44% + 第二路 82-100%
   交互后——三路读数同域远超门）。
3. **NLMeans 窗外 crash flake 1 例（执行批首轮，非产物缺陷）**：
   `t4-all.log` terminated abnormally + exit=133 + peak 5090MB 亲读在案；
   隔离重跑 687/5/0 + 全套重跑绿 + 双路独立全套轮 IOP 687/5/0 四轮互证；
   flake 台账延续先例（波 1 GrainTests / 波 2 ProcessVersionCarrierTests
   同族口径），不构成对账阻断。
4. **分歧记录①：点击表型输入路径混淆**——执行批 probe-11 AXPress
   「零响应」+ `t1-filmstrip-click-dead.png` 占位变体 vs 第二路 cliclick
   真实鼠标 3/3 全响应（含无遮挡直接点击）；假说 = AXPress 合成路径 vs
   CGEvent 输入通道差异（m6 harness「键盘 CGEvent 不进 app」同族）或
   间歇表型；不影响 T1 判定（CPU 硬门独立成立）→ 挂账④双通道对照。
5. **分歧记录②：legacy 菜单点火适用域收窄**——第一路带图会话 legacy
   面开菜单态 41.5% vs 第二路空 legacy 面 0.0%（菜单确实开着）；点火
   条件疑与「菜单环 × 面内容复杂度」相关非无条件；第一路观察维持其
   记录口径，第二路数据点收窄适用域；两记录均如实双载不裁决。
6. **watchdog 日志失聪（诊断面现状）**：`log stream --process Lightamer`
   捕获系统级消息但零 import-watchdog 行（双路亲证）；代码面 `.info` 级
   与「stream 未带 `--level info`（`.info` 默认不入 Default 流）」假说
   自洽——下批 D-7 族开工时
   `log stream --level info --predicate 'subsystem == "com.kamasylvia.lightamer"'`
   一行验证即知；若仍失聪再考虑落文件通道。
7. **批外新 HEAD `a35a734e`（Alcedo CLI/AI 调研 docs，另一会话产物）**：
   零产线文件，不触本批窗（第二路红线机检双窗 `029f84bc..HEAD` 与
   `..2427670e` 均 PASS）——在飞批隔离纪律维持的活例。

## 授权记录（C 档 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 +
  M3/M4/M5/M6 全系 + V2/Maintenance 两波 + 本 phase 执行/验收同款沿用；
  晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：FIX2 闭环批任务书明载「夜间全
  自动授权在案（先例 D-07-3-T5-1，晨审可推翻）」——VALIDATION 成文、
  勘误落账、workaround 补记与翻账为同一授权链尾段。
- 依授权，本 VALIDATION 由 FIX2 闭环批 worker 落盘签核（dual_acceptance
  双路验收已先行落终态）；用户晨审可推翻本签核（推翻 = FIX2 签核作废
  回退，已交付面与三路执行/验收证据不受影响；翻账批同批执行，推翻时
  五正本翻账随 revert）。
- 签核 executor：ZCode FIX2 闭环批 worker（2026-10-16）；**doc-only——
  零源码 diff**（工作树既有 untracked 兄弟批/孤儿域件〔M3-1-ACCEPTANCE-PI
  / retro-dual / dt-clone-archive〕零触碰）。
- **呈报裁决点（禁静默，charter 门一并呈报）**：①D-6 专项立项 charter
  （§挂账①，内容五块已列——默认 = 用户定向后立项）；②Alcedo CLI+AI
  照抄 charter（`research/ALCEDO-CLI-AI-SURVEY.md` 三块切分）；③
  UPSTREAM-QUEUE 四候选；④导入零行间歇（grid 刷新迟到族）独立待研立项
  时机（默认 = D-6 专项后复测再裁）。

## 翻账与移交（本批同 commit）

- **AGENTS**：「V2-Maintenance 架构增量」节尾追加 FIX2 闭环行（VALIDATION
  正本指针 + D-7 Coalescer 先例 / D-6 定罪与降级裁定 / D-8 翻案核销 /
  勘误落账 / workaround README 指针 / 终态 3860/35/0）；执行批 FIX2-01
  行 ④ 勘误标注（原行保留）。
- **ROADMAP**：V2/Maintenance 站节尾追加 FIX2 行（执行链 + 双路结论 +
  终态 3860/35/0 + 挂账六项指针 + charter 门）；「下一步」句更新。
- **STATE**：current_phase / status 追加 FIX2 闭环段（终态 + 双路 +
  续接点 = charter 门待用户三件呈报）。
- **TODO**：V2/Maintenance 两波闭环行后追加 FIX2 闭环行（[x]）；D-6 行
  追加双路同判① + workaround README 指针；D-7 行勘误标注。
- **GOAL-STATE**：顶部追加新续接点 = FIX2 closed（VALIDATION signed +
  终态 + 挂账六项）→ **续接点 = charter 门待用户**（D-6 专项 + Alcedo
  CLI+AI 照抄 charter + UPSTREAM-QUEUE 四候选一并呈报）；移交句勘误随
  新续接点承载。
- 修批/执行链 `da99ea2f..2427670e` 已在库；未 push；两份 ACCEPTANCE 文档
  随本批 commit 入库（local-only 证据域 gui-acceptance 与
  fix2-probe/ 不入 git 惯例维持；/tmp 回填件留在本地证据域）。

## 签核

- plan 全部 SC/AC + 红线族 + 数字门全项 **Delivered**（三列证据齐；数字
  对账 = 三路 3860/35/0 同值，对账链 3857+3 = 3860 精确闭合；双重验收
  零实质分歧）；T1 BLOCKED 分支行使双路追认合规（D-6 降级裁定 +
  专项 charter 待用户 = 诚实终态，非缺陷遗留）。
- `status: validated` + `nyquist_compliant: true`。
- **FIX2（修复批 II）closed**：双路独立验收 PASS / 0 error 产物缺陷 +
  零 open minor，终验全套实测 `TOTAL|3860/35/0|`（skip 35 = 基线 24 +
  供件漂移 11）；D-FIX2-4 勘误六处 + workaround 用户可及文档 + /tmp
  证据回填三件本批落账；挂账单一清单六项（§挂账）移交 D-6 专项与
  下批顺手窗。
- 晨审裁决项：charter 门四件呈报（见授权记录）+ 签核推翻窗（原话授权
  在案）。
- **C 档 VALIDATION = 夜间授权先例落签，晨审可推翻。**
