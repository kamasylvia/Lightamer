---
phase: fix2-defects
plan: "FIX2-01"
title: "修复批 II——D-6 重开项目态编辑器 AttributeGraph spin（壳失刷源判别探针 → 定罪断环 → 屏面走查铁律验收）/ D-7 导入停滞（主 actor 饥饿对表 + 进度投递合流硬化）/ D-8 legacy 会话通道翻案核销（零码）+ 全套对账收口 + 走查复走批（屏面四项义务 + D-4 复验 + GUI-M6C 复走 + m6-closeout B 类余行，B 类 computer-use）"
wave: 1
depends_on: []
autonomous: true
requirements: ["修复批 II（用户指令：直到全量修复完成，再执行新特性立项；夜间全自动授权先例 D-07-3-T5-1）", "根因正本 = phases/fix2-defects/FIX2-CONTEXT.md（本批三路亲跑侦查定稿）", "挂账正本 = phases/v2-maintenance/V2M-VALIDATION.md §挂账①②"]
success_criteria: "SC 全可机检——T1：判别探针 transcript 定罪写点（DECISIONS 记录 view/属性名）+ 断环修法落地 + 重开空载静置 CPU<10%（ps/sample 机检）+ 屏面走查三铁条（重开进编辑器 spin 消失/filmstrip 点击换图出图/截图证据）+ 既有 App 套件零回归；T2：进度投递合流缝单测（若有可纯函数化缝，ΔN=0 合法）+ 导入循环 N 轮完成态发布机检（images 行数=供件数 × N 轮）+ 完成后 CPU 静置回落；T3：legacy 配方走查三步证据（建会话/网格带图/编辑器加载）+ MANIFEST 配方节 + DECISIONS 翻案登记（零产线 diff）；T4：全套 --all = 3857+ΔN 对账闭合（批准制 + 8G 门 + MEMFAIL 机检）+ 红线族机检全过；T5：走查复走四波逐行终态（W1 D-6 铁条 + T1-02/03/05/08 + W2 D3-01/D4-01〔若见 0 按快照上移预案返工〕/D5-01 + W3 D-7 复验 + W4 legacy 行）MANIFEST 逐行记账，Blocked 行如实保持不硬造判定"
estimated_tests: "+0..4（T1 回归钉 +0..2〔断环缝可纯函数化才加，视图级 seam ΔN=0 走屏面走查证据——D-3 先例〕/ T2 合流缝 +0..2 / T3 +0；执行时逐任务如实记账）"
test_bundles: [App]
baseline: "3857/35/0（V2M 终态；skip 35 = 基线 24 + RAW 供件域漂移 11，环境漂移口径维持，供件备料前不收敛）"
expected_all: "3857 + ΔN（对账式；ΔN 预期带 +0..4，执行时按实记账）"
red_lines:
  - "全部 *.metal 零 diff（D-6/D-7 修法均在 App UI/调度域，无 kernel 义务；若侦查翻案需要 kernel 先停手修订本 plan 申报）"
  - "LightamerIOP/ 全域零 diff；LightamerSidecar.swift 零 diff"
  - "封存面零触（DrtRecord / GradeCatalog / Registry / HistoryStack / V50Order / ExportFormatSpec / ImageIOEncoders / WebPEncoder / ExportQueueContract）"
  - "\\.runModal( 在 App/Sources 零命中（L057 禁令——面板一律 PanelPresentation.begin 缝）"
  - "LocalizationValue 插值禁形（String.LocalizationValue(\"prefix_\\(x)\")) 代码零命中"
  - "UserDefaults 零新键；xcstrings 零 diff"
  - "Project.swift：无新测试文件则全零 diff；有则 BUNDLE-MAP + Project.swift 同批登记 + tuist generate 恒为该批最后一个动作（L041）"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle <域>；全套 --all orchestrator 批准制 + 运行 8G 门 + MEMFAIL 机检（AGENTS 资源监控节）"
files_modified:
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift            # T1 主战场（H1 嫌面：:170 focusedSceneValue 写点 / :220-222 onGeometryChange 写点 / :153-157 / :166-169 横幅读缝）——按探针定罪结果断环；探针本身 /tmp 即弃零 commit
  - App/Sources/Lightamer/UI/ContentView.swift                        # T1 备案口（:205-219 .inspector SystemSplitView 宿主改形——主案消环后 spin 仍现才行使，行使 = DECISIONS 申报 + M3-4-01 T4 挂载语义走查复验）
  - App/Sources/Lightamer/UI/LightamerApp.swift                       # T1 可能触面（Commands 求值缝若坐实为失刷回环一环；T2 完成尾 watchdog OsLog 诊断面；零行为变更）
  - App/Sources/Lightamer/Library/LibraryProjectController.swift      # T2：runImport 进度投递合流（:389-391 逐文件 Task{@MainActor} → 节流合流，完成态恒即时）+ 完成尾 watchdog（:416 前 OsLog）
  - Tests/LightamerTests/ImportProgressCoalescingTests.swift          # T2 条件新增（合流节流纯函数缝可抽才加；+0..2 法；不加则本行撤销，ΔN=0 合法）
  - .work/gsd/phases/fix2-defects/FIX2-01-SUMMARY.md                  # T4：执行摘要（逐任务 ΔN 记账 + 探针 transcript 指针 + 走查证据指针）
  - .work/gsd/phases/fix2-defects/FIX2-01-DECISIONS.md                # T4：裁定记录（H1 写点定罪 + 断环形态 / 主案-备案择臂 / T2 合流参数 / D-8 翻案核销）
  - .work/gsd/phases/fix2-defects/FIX2-01-ACCEPTANCE.md               # T5 后追加：走查复走四波 MANIFEST 终态汇总（或独立 gui-acceptance MANIFEST + 指针）
  - AGENTS.md                                                         # T4：「V2-Maintenance 架构增量」节后追加 FIX2 行（失刷源定罪 + 断环范式 + D-8 配方正本 + 终值登记）
  - .work/TODO.md                                                     # T4：D-6/D-7/D-8 登记行翻账（D-8 = 翻案核销口径）
  - .work/GOAL-STATE.md                                               # T4：续接点翻新（修复批 II closed → 新特性立项待用户定向）
---

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。根因侦查正本 =
> `FIX2-CONTEXT.md`（本批 research 亲跑三路证据：执行批 t2-spin.sample.txt
> 1094 帧 + wave-1 import-stall-sample.txt 2116 帧 + 本批 probe 三面采样，
> 证据域 = `gui-acceptance/v2m/`〔含 fix2-probe/ 新采样，local-only〕）。
> **侦查定稿四行**：①churn 是 gate=false 壳族长期固有病（三面 34-82% CPU，
> legacy 面同机 0.0% 反证隔离）；②D-6 spin = 失刷源 × `.inspector`
> SystemSplitView 项重渲的再入环（栈 :49-:91 三层嵌套结构在案）；③D-7 =
> 同根异症——`runImport` @MainActor 全链（LibraryProjectController.swift:41
> + :384-435）被 churn 饿停（样本零 actor 帧 + 完成尾永不发布）；④D-8 =
> 走查错腿翻案（打开… 单图腿 ≠ 会话腿；打开会话… ⌘⇧O 全链路亲证可用，
> probe-20 六图会话 + 0.0% CPU）。

# Plan FIX2-01 — 修复批 II（D-6 → D-7 → D-8 → 收口 → 走查复走批）

> **执行序**：T1 → T2 → T3 → T4 → **T5（T1-T4 全绿后，本 plan 内闭环——
> 「直到全量修复完成」用户指令的走查半边）**。每任务独立 commit
> （Conventional Commits，全英文，只 add 相关文件；不 push）。GUI 走查证据
> 落 `.work/gui-acceptance/v2m/`（local-only）。侦查探针一律 /tmp 即弃。

## T1 — D-6 根因裁定与断环（error 级候选修复 + 屏面走查铁律）

**read_first**：FIX2-CONTEXT.md §一（假说表 + 修法主/备 + 探针配方）；
`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（:124-416 body 面）；
`App/Sources/Lightamer/UI/ContentView.swift`（:170-241 gate-false 装配）；
`App/Sources/Lightamer/UI/LightamerApp.swift`（:443-489 Commands 求值面 +
:490-1560 body）；`gui-acceptance/v2m/fix2-probe/sample-idle-face.txt`。

- action 1 **判别探针（/tmp 即弃，零 commit）**：临时 `Self._printChanges()`
  （或 OsLog signpost 同效形）挂 `WorkspaceHostView.body` /
  `LightamerApp.body` / `ContentView.body`，Debug 直启空载静置 30s + 重开
  项目进编辑器 30s，采两段重估流 transcript。产出 = **定罪记录**：哪个
  view 因哪个属性每帧重估（H1-a onGeometryChange / H1-b focusedSceneValue
  写-回环 / H1-c 第四写点 / 均不成立 → H2 框架共犯备案口）。
- action 2 **断环修法（按定罪落点，主案优先）**：
  - H1-a：`yiyinSheetDomain` 写点（WorkspaceHostView.swift:220-222）加等值
    早退或改量测时机（sheet 挂载期才量测）——写点不出渲染语义域。
  - H1-b：`.focusedSceneValue(\.lightamerWorkspaceModel, workspace)`（:170）
    改条件发布——body 直写改 `.onChange(of: workspace.phase)`（或同效任务
    缝）单次发布，或引入稳定 Equatable 载体使 FocusedValues 去重生效；
    同缝核查 `WorkspaceModelKey` 侧消费面（LightamerApp.swift:461-472）
    语义零变（⌘E/⌘W/⌘F/View toggles 全部既有走查行为保持）。
  - H1-c／第四写点：按定罪点断环（等值守卫 / 写点出渲染路径 / 延迟
    Task 化），形态 DECISIONS 申报。
  - **备案（H2 或主案消环后 spin 仍现）**：`ContentView.swift:205-219`
    `.inspector` 宿主改形（页面未激活不挂 SystemSplitView；改形 =
    M3-4-01 T4 挂载语义迁移重验：dismiss 双关 + present no-op + film 页
    分支）——行使时 DECISIONS 申报并加走查行（export 页/film 页挂载 +
    dismiss 双向）。
- action 3 **回归钉（可纯函数化才加，ΔN=0 合法）**：断环若落在可抽纯函数
  缝（如条件发布的判定函数），+1..2 法入 App bundle（BUNDLE-MAP + 
  Project.swift 同批 + tuist generate 恒末位）；视图级 seam 不可纯函数化
  则 ΔN=0，以屏面走查证据承载（D-3 先例）。
- action 4 **修复验证三铁条（屏面走查，SC 硬门，非仅单测）**：Debug 直启
  → Open Recent 重开 ≥6 图项目 → 文件 > 进入编辑器 → (1) 静置 30s CPU
  <10%（`ps`/`sample` 机检，与修前 82-99% 对照）；(2) 编辑器可用：filmstrip
  点击换图 + 视口出图 + 右栏 mount（三步各一截图）；(3) 空载无项目面静置
  CPU 同口径复测（churn 源若在壳常挂件，此面应一并回落——一并记录）。
  证据 = `gui-acceptance/v2m/`（MANIFEST 行 FIX2-D6-01..03）。
- **AC**：探针 transcript 在案 + 定罪写点有 file:line 锚 + 断环 diff 落
  定罪点（非盲改）+ 三铁条全过 + 既有 App 定向轮零回归（`--bundle App`
  全绿）+ 既有三面静置 CPU 机检记录。

## T2 — D-7 主 actor 饥饿硬化（合流投递 + watchdog；对表 F-1 不修）

**read_first**：FIX2-CONTEXT.md §二；`LibraryProjectController.swift`
（:384-435 runImport）；`LightamerCore/Sources/Library/ImportService.swift`
（:297-346 importFolder + :736-738 emit）。

- action 1 **进度投递合流**：`setProgressHandler` 闭包（:389-391）的逐文件
  `Task { @MainActor in self?.importProgress = snapshot }` 改节流合流
  （投递间隔 ≥100ms 或批次尾强制；**完成态与取消态恒即时投递**——
  WorkspaceHostView.swift:309-332 的 onChange 消费面依赖 nil 终态收尾，
  合流不得吞终态）。纯函数化节流判定可抽则 +1..2 法
  （`ImportProgressCoalescingTests`：首投递即时 / 窗内合流 / 尾投递不丢 /
  终态穿透四语义；BUNDLE-MAP 同批 + tuist generate 恒末位）。
- action 2 **完成尾 watchdog（诊断面零行为变更）**：`importProgress = nil`
  发布点（:416）前 OsLog 一行（耗时 + outcome 摘要），停滞复发时留痕。
- action 3 **复验机检**：Debug 直启 → 建项目 → Import Folder（≥6 文件）
  × N≥3 轮（每轮删 `.lalb` 重建或用新目录）——每轮 images 行数 = 供件数、
  进度条发布完成态（BackgroundTaskBar 收尾）、完成后静置 CPU 记录（T1
  修后应 <10%）；顺带记录 cancel 腿 F-1 现状（只记录不修）。
- **AC**：N 轮全完成 + 完成态发布证据 + 静置 CPU 记录 + （若加测试）定向
  轮全绿；F-1 现状登记 MANIFEST。

## T3 — D-8 翻案核销（零产线 diff；配方固化 + 回归确认）

**read_first**：FIX2-CONTEXT.md §三；`gui-acceptance/v2m/MANIFEST.md`
D-8 行；probe-16..20 证据（fix2-probe/）。

- action 1 **回归确认走查**：`LIGHTAMER_LEGACY_LIBRARY=1` 直启 → 文件 >
  打开会话…（⌘⇧O）→ 选文件夹 → (1) 会话建立 + 网格带图；(2) 双击进编辑器
  加载成功；(3) 静置 CPU 记录（legacy 面 0% 口径）。三步截图入证据域。
  **若真腿意外失败**（环境差异翻案失败）→ 升级真修任务 + DECISIONS 申报，
  本 plan 不扩范围（上报 orchestrator 定夺）。
- action 2 **配方固化**：MANIFEST 增「legacy 通道正确配方」节（env 注入 +
  菜单腿 + 供件目录约定），m6-closeout Blocked-Channel 行的复走映射表
  （pano 16-19 / 栈面 34-38 / 40 → W4 波次行）。
- action 3 **挂账核销登记**：DECISIONS 记 D-8 翻案（走查错腿 + inert-by-
  design 两事叠加；真腿亲证可用；V2 #4 SESSION-LEGACY-READONLY 无「先修
  通道」前置）；VALIDATION §挂账① D-8 行核销口径入 SUMMARY。
- **AC**：零产线 diff（本任务 `git diff --stat` 仅 docs）+ 三步走查证据 +
  配方节 + DECISIONS 登记。

## T4 — 全套对账收口

- action 1 红线族机检（front-matter `red_lines` 逐条亲跑：metal/IOP/sidecar/
  封存面零 diff；runModal 零；LocalizationValue 禁形零；UserDefaults 零新
  键；xcstrings 零 diff；Project.swift 对账）。
- action 2 全套 `caffeinate -dis Scripts/test-direct.sh --all`（**orchestrator
  批准后**跑；运行中保持监视 + 8G 门 + MEMFAIL 机检）——`TOTAL|3857+ΔN/35/0|`
  对账闭合（ΔN 逐任务记账；skip 35 = 环境漂移口径维持）。
- action 3 台账同批：SUMMARY / DECISIONS / AGENTS FIX2 行 / TODO D-6..D-8
  翻账 / GOAL-STATE 续接点（§3.1 文档原子同步纪律；历史行只追加不改写）。
- **AC**：对账式 `expected_all` 精确闭合 + 红线族 PASS + 三台账同批落盘。

## T5 — 走查复走批（T1-T4 全绿后；B 类 computer-use；本 plan 内闭环）

**read_first**：FIX2-CONTEXT.md §四（四波编排表）；`V2M-VALIDATION.md`
§挂账②；`V2M-01-ACCEPTANCE-2ND.md` §五 E2-1；`V2M-02-ACCEPTANCE.md` §六；
`gui-acceptance/m6-closeout/MANIFEST.md` 余行集。

- 前置口：T1-T4 全绿 + T1 三铁条已过（编辑器通道恢复）；harness = AX +
  CGEvent + screencapture（波 2 已证健康）为主，B 类 computer-use 承担
  交互判据行（用户指令兑现）；通道受阻按「不硬造判定」登记 Blocked 保持。
- **W1**：D-6 修复验证三铁条终态固化（T1 复录）+ V2M-T1-02（D-1 三零消除
  点击：solve 进度态/读数 1s 内/history item + sidecar）+ GUI-M6C-03/05
  （追色 solve 面）+ 06 数值面 + 07 before/after；hasImage=nil 批外疑点
  现状顺带记录（不扩范围）。
- **W2**：V2M-D3-01（≥4 图 ×N 轮 filmstrip 连点零卡死）+ V2M-D4-01（三
  合并对话框标题计数——**复验仍见 0 → 按「快照上移」预案返工，一轮损失
  不产假交付**）+ V2M-D5-01（merge 完成 toast zh 文案）+ GUI-M6C-08。
- **W3**：D-7 复验（= T2 action 3 的走查面固化 + F-1 现状行）。
- **W4**：legacy 面行（T3 配方）：pano 16-19（合成切片供件）+ 栈面 34-38
  （连拍 auto-stack 供件）+ 40（guided filter 编辑器面）。
- 不入波（供件/硬件缺座维持）：24/25（HDR 显示器）/26（UltraHDR 样张）/
  27-31/39（layer 资产/真多人素材族）。
- **AC**：四波逐行终态入 `gui-acceptance/v2m/` MANIFEST（行 id + 判据 +
  证据指针）；可走行全 Executed；Blocked 行如实保持；W2 若触发「快照上移」
  返工 → 返工后复走一轮并 DECISIONS 申报（返工本身即本 plan 范围内）。

## 执行纪律

- 每任务独立 commit（全英文 Conventional Commits；只 add 相关文件；不
  push）；D-6 探针/走查产物零入 git（gui-acceptance 域 local-only 惯例）。
- 进程纪律：spin 实例处置按 AGENTS §8（本会话自起实例静默处理）；GUI app
  资源监控线（>3G / 持续 >50% 非构建态）全程适用。
- 测试宿主清理先核 parentage（`ps -o ppid`，M2-7-3 事故先例）。
- 停等点：无（本批直通；唯一外部依赖 = T4 全套 --all 的 orchestrator 批准
  ——批准前 T5 不开工）。

---

## Checker 关注点

1. **T1 断环 diff 与定罪点对应性**：修法 hunk 必须落在探针定罪的写点/
   读缝（file:line 对应），警惕「消环失败后盲改横幅/动画修饰符凑数」——
   DECISIONS 无定罪记录而 diff 落别处 = 打回。
2. **T1 备案口行使门槛**：`.inspector` 宿主改形（ContentView.swift:205-219）
   仅在主案消环后 spin 仍现时行使；checker 须核 DECISIONS 是否记录了
   「主案先行 + 备案行使理由」两段，且 M3-4-01 T4 的 present no-op /
   dismiss 双关语义在改形后保留（film 页挂载回归）。
3. **T2 合流的终态穿透**：合流节流不得吞 `importProgress = nil` 终态
   （WorkspaceHostView :309-332 onChange 消费面以此收尾——吞终态 = 进度条
   永挂 = D-7 换形复发）；测试四语义中「终态穿透」缺位 = 打回。
4. **T3 零码申报**：本任务 `git diff --stat` 若出现任何 Swift/Product 文件
   = 与「零码翻案」申报冲突，须 DECISIONS 说明（真腿翻案失败升级真修是
   唯一合法形态，且须上报记录）。
5. **D-8 核销口径**：TODO/VALIDATION 翻账行必须写「翻案核销（走查错腿 +
   inert-by-design），非代码修复」——禁止写成「已修复」；V2 #4 前置句
   同步勘误。
6. **T5 判据污染面**：W2 的 D-4 计数判据以**对话框实际呈现**为前提；
   走查批若再现任何通道阻断，Blocked 保持并逐行登记，禁止以
   「代码面证据」替代屏面判据销账（V2M-02 先例条款）。
7. **skip 口径**：全套对账 skip 恒 35（基线 24 + RAW 供件漂移 11）；
   出现第三种 skip 来源 = 供件/环境新漂移，须逐族差分申报，禁止静默吸收。
8. **红灯族豁免锚**：LocalizationValue 插值禁形的 :2069 doc comment 豁免
   锚沿用（V2M-02 在案）；runModal 禁令对 `PanelPresentation.begin` 内部
   实现不适用（grep 形限 App/Sources 调用点）。
