---
phase: v2-maintenance
plan: "V2M-02"
title: "V2M 波 2 清算批——V17 zh-audit 门扩展（specifier 深检 + Text 插值族 + String( 跨行族合门，V16 状态机扩展 + self-test golden 负测）+ 活体 ABSENT 清偿 / Manual-Only GUI 批余行执行（B 类 AX/computer-use 波，前置 = 波 1 D-1+D-2 验收闭环）/ PATCH-LIVEPLANE + RELEASE-DIRECT-INJECT 顺带候选（随容量）/ EXPORT-PRESET-01 波尾（导出命名预设层）/ D-5 条件并入（波 1 未清时）+ 收口全套 --all 对账（批准制 + 8G 门）"
wave: 2
depends_on: ["V2M-01"]
autonomous: true
requirements: ["V2/Maintenance 清算批（RESEARCH §一.B/C/F + §四波 2 编排；正本 = phases/v2-maintenance/RESEARCH.md + V2M-CONTEXT.md OQ 裁决；V2 S 件正本 = phases/v2-station/V2-PROPOSAL.md §七）"]
success_criteria: "SC 全可机检——T1：zh-audit --self-test PASS + --check PASS（ABSENT 零命中 + spec 错配零命中）+ xcstrings diff = 恰活体清偿键尾块纯插入；T2：MANIFEST 余行逐行终态 + 证据指针（local-only 零 commit）；T3/T4：余量盘点结论 + 修复/销账双向收口；T5：预设存取单测 + 新键登记 + zh-audit PASS；T6：全套 --all = 波 1 终值 + ΔN₂ 对账闭合"
estimated_tests: "+2..6（T3 顺带 +0..2〔销账形态 ΔN=0 合法，另记〕/ T5 预设层 +2..4〔波尾固定范围，下界不可为 0——M-4 组成闭合〕；V17 self-test = 脚本侧非 XCT 记 ΔN 0；执行时逐任务如实记账）"
test_bundles: [App, Export]
baseline: "V2M-01 终值（= 3848 + ΔN₁；本批开工时以 V2M-01 T6 全套轮实测为准）"
expected_all: "波 1 终值 + ΔN₂（对账式；ΔN₂ 预期带 +2..6〔T5 波尾固定范围使下界为 2——M-4〕，执行时按实记账）"
files_modified:
  - Scripts/zh-audit.py                                              # T1：V17——V16 状态机扩展（断言 5 PRESENT/ABSENT 之上加 specifier 类型深检 + Text 插值族扫描 + String( 跨行族合门）；不可判面豁免登记；报告节扩展；self-test golden 负测
  - Resources/Localizable.xcstrings                                  # T1：活体 ABSENT 键尾块纯插入（planner 预扫已证 1 键：catalog_session_remove_confirm_body %@——xcstrings:2072 裸键在册无变体 + SidebarView.swift:262 活体；全表以 V17 首跑 transcript 为准）+ T5 预设 UI 键族（如有）
  - App/Sources/Lightamer/UI/SidebarView.swift                        # T1：仅当活体清偿需调用点配合时（预期零改——键落目录即清偿）；列此为「可能触」申报位
  - App/Sources/Lightamer/State/EditorState.swift                     # T3（顺带候选）：livePlane eager 释放（EditorState→LayerEditingState 新横 wire）——余量盘点后按裁执行或零 diff 销账
  - App/Sources/Lightamer/State/LayerEditingState.swift               # T3：同上（planner 已核路径在位：App/Sources/Lightamer/State/）
  - Scripts/make-release-direct-launchable.sh                         # T4（顺带候选）：Release 直启自足化助手（embed PackageFrameworks + ad-hoc 全量重签——m6-closeout P1 批注记已验证配方脚本化）；形态（脚本 vs Tuist 配置）执行批裁
  - App/Sources/Lightamer/State/ExportState.swift                     # T5：命名预设层模型面（预设存取 + 套用投影；**预设不捕获 collisionPolicy**——M-5/M3-1-03 KD-1 会话态裁定锚；planner 已核路径在位）+ makeRunAssembly 纯缝扩展（M3-1-03 范式）
  - App/Sources/Lightamer/Export/ExportInspectorView.swift            # T5：预设选择器/管理 UI（M2 页载体，planner 已核路径在位）；zh 键族尾块纯插入
  - Tests/LightamerTests/ExportPresetTests.swift                      # T5：+2..4 法（归域按 BUNDLE-MAP 核对后定；新文件则 Project.swift/BUNDLE-MAP 同批登记 + tuist generate 恒末位）
  - .work/gsd/phases/v2-maintenance/V2M-02-SUMMARY.md                 # T6：执行摘要
  - .work/gsd/phases/v2-maintenance/V2M-02-DECISIONS.md               # T6：裁定记录
  - AGENTS.md                                                        # T6：V17 门形态 + 键族登记（T1 活体清偿键 + T5 预设新键）+ ΔN 终值 + 全套终值
  - .work/TODO.md                                                    # T6：清算族条目翻账
  - .work/GOAL-STATE.md                                              # T6：续接点（波 2 closed → VALIDATION/收尾）
---

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。裁决正本 =
> `V2M-CONTEXT.md`（OQ-VM-3 = 两 S 件顺带候选 / OQ-VM-4 = EXPORT-PRESET-01
> 波尾 / OQ-VM-5 = GUI 走查批提前口）。**波间纪律**：源码面串行（波 1 全套
> 验收闭环后本批开工）；**唯一并行口 = T2 GUI 走查行**——V2M-01 的 T1（D-1）
> + T2（D-2）定向验收闭环后即可开跑（走查不占源码面，OQ-VM-5-A）。
>
> **批次红线**：零新 SPM；UserDefaults 新键须 AGENTS 登记（**T5 预设层是
> 本批唯一预设新键口**——键形执行批裁后登记）；`.metal` 零 diff；xcstrings
> 尾块纯插入 + `zh-audit --check` PASS 对账（T1 落新门后以新门跑）；
> `\.runModal(` App/Sources 零命中；`String.LocalizationValue("` 插值禁形
> **代码行（非注释）**零命中（M-3 钉形——两处已知豁免锚 =
> `LightamerApp.swift:2061` doc comment 注记字面 / `ExportInspectorView.
> swift:433` 拼接形在用，同 V2M-01 red_lines 登记口径；V17 落地后由门
> 自动兜）；封存面零触；测试文件新设须 Project.swift
> + BUNDLE-MAP 同批登记 + `tuist generate` 恒末位（L041）。构建
> `caffeinate -dis` 包裹；单测 = `Scripts/test-direct.sh`（bundle token
> 大小写敏感：`App`/`Export`/…）。

# Plan V2M-02 — 波 2 清算批（V17 + Manual-Only GUI + S 件 + EXPORT-PRESET-01）

> **任务序与容量规则**：T1（V17）→ T2（GUI 走查批，可提前口并行）→
> T3/T4（S 件顺带候选——**开工先盘点余量**：波 1 拖批 / 供件等待 / 走查
> 返工吃掉容量时，本两件原样留 V2 挂账不销不修，登记 SUMMARY）→ T5
> （EXPORT-PRESET-01 波尾）→ T6 收口。D-5 条件并入：V2M-01 T5 未清（翻案
> 返工等）→ 本批并一任务清偿后收口。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/v2-maintenance/V2M-CONTEXT.md`（OQ 裁决 + 红线正本）
- `.work/gsd/phases/v2-maintenance/RESEARCH.md` §一.B（V17 缺口正本）+
  §一.C/F（S 件与 EXPORT-PRESET-01 锚）
- `Scripts/zh-audit.py` 头注 + V16 断言 5（:358-367——「Specifier
  deep-checking stays manual」注释即 V17 要拆的门）
- `.work/gui-acceptance/m6-closeout/MANIFEST.md`（走查总队列正本 + 通道
  批注记）+ `.work/gsd/phases/v2-station/V2-PROPOSAL.md` §七.2/.9（S 件）
- `.work/config.toml [gsd]` paused/auto 开关

---

## T1 — V17：zh-audit 门扩展（specifier 深检 + Text 族 + 跨行族合门）

> **缺口正本**（RESEARCH §一.B + planner 现码亲核）：V16 断言 5 只做
> `K + " "` 前缀 PRESENT/ABSENT 三态（`zh-audit.py:358-367`），三类不设防：
> ①**specifier 类型深检**（Int→`%lld` / Float→`%lf`/`%f` / String→`%@`）
> ——D-5 是活体样本（变体在册但形态错配 → 运行时 miss，V16 全绿放过）；
> ②**SwiftUI `Text("K \(x)")` 插值族**——planner 单行预扫 9 处
> （RESEARCH 记树内 11 含多行形态；执行批重derive定格），活体 ABSENT
> ≥1（`catalog_session_remove_confirm_body`：xcstrings:2072 裸静态键在册
> 无 `%@` 变体 + `SidebarView.swift:262` 活体调用 → 运行时裸键）；
> ③**`String(` 跨行族**——form 1c 续行面 3 处（`LightamerApp.swift:943/
> :1103/:2019`）已有提取（V16 form 1c），V17 把「变体存在性 + spec 类型」
> 合门覆盖。

- **action**：
  1. `Scripts/zh-audit.py` V17 扩展（V15/V16 同族惯例）：
     - **Text 族提取**：`Text("K \(…)")` 单行 + 多行形态 regex（键形同
       KEY_SHAPE 小写偏置——大写/数字键盲区与 V15/V16 同口径，范围注记
       登记）→ `text_interp_keys`（key → 路径表）。
     - **specifier 深检**：对每个插值键推导实参静态类型。**推导供给面
       （E-2 修订扩形）**= `let/var` 声明 + **函数参数声明** + 简单算式
       传播 + **`Int(…)` 包装调用形**（覆盖 `.rounded()` 等链尾——D-5
       修后调用点 `Int((holeFraction * 100).rounded())`，`holeFraction`
       为函数参数；供给面不含函数参数/包装形则此键落 EXEMPT 非绿，波间
       交叉引用的「D-5 绿例活体」不可交付）。**类型映射表 = 全 Int 族
       （Int/Int32/Int64/UInt…）→ `%lld`**（`mcp_launcher_status_running`
       的 pid = Int32 对 `%lld` 变体在册活体，M6-6 rider 亲证）/
       `Float|Double` → `%lf`（同映射）/ `String` → `%@`；
       **不可判面豁免登记**（tap 面收窄：跨文件推断/泛型/协议类型/元组
       成员不判，报告 EXEMPT 节），禁误报。
     - **断言 6**（V17）：插值键 K 必须存在目录变体 `K <specs>` 且 specs
       与推导类型**逐参有序一致**（PRESENT/ABSENT/spec-MISMATCH 三态；
       ABSENT = V16 断言 5 语义延伸，MISMATCH = V17 新增）。**判定式 =
       逐参有序比对（E-2 修订）：长度不等或任一位错配 = MISMATCH——
       弃「集合 ∩ = 空」形**（`[String, Int]` vs `%lld %lld` 的类型集合
       交集非空会放行逐位错配；在册多参活体
       `settings_catalogs_rebuild_progress %lld %lld`〔SettingsPages.swift:
       1406 / CatalogBrowserView.swift:71 两调用点〕/ `session_counts
       %lld %lld %lld` / `toast_import_partial %lld %lld` 即门一上线就要
       面对的形态）。
     - 报告节扩展（[5] 节扩三态 + Text 族并入或独立节）；`AuditViolations`
       计入 total。
     - **self-test golden 八例（E-2 修订扩四例）**：①spec 错配红例
       ②Text 族无变体红例 ③跨行绿例 ④豁免例 ⑤**位置错配红例**
       （`[String, Int]` vs `%lld %lld` 型逐位错配——集合交集形会误
       放行的洞）⑥**Int32→`%lld` 正例**（全 Int 族映射表锚）⑦
       **Float=Double 同映射 `%lf` 正例**（D-5 样本同款）⑧**注释免疫
       例**（doc comment 内含插值禁形字面不红——`LightamerApp.swift:
       2061` 在册活体；V15 form 1c「注释行保持 pending」逻辑同款延伸到
       Text 族 regex，否则 V17 新增误报源）——`--self-test` PASS 为 AC。
  2. V17 首跑分诊 transcript（清偿前红面全表定格 → 清偿后全绿），记
     SUMMARY。
  3. **活体 ABSENT 清偿**：首跑红面逐键尾块纯插入（planner 预扫已证 1 键
     = `catalog_session_remove_confirm_body %@`；全表以首跑为准；键值
     措辞对齐既有相邻键族 `catalog_session_remove_confirm_*`）。D-5 键
     （波 1 已 Int 化）应全绿——供给链 = 函数参数 `holeFraction: Float`
     → `Int(…rounded())` 包装形 → Int → `%lld` 与目录一致（E-2 供给面
     扩形后可判，非 EXEMPT）；红则波 1 修法翻案信号，停手上报。
  4. AGENTS 登记 V17 门形态一行（后续批红线电池引用 =
     `zh-audit --check` ABSENT/MISMATCH 零命中）。
- **验收标准（机检）**：`python3 Scripts/zh-audit.py --self-test` PASS；
  `--check` PASS（ABSENT 零命中 + MISMATCH 零命中）；`git diff
  Resources/Localizable.xcstrings` = 恰活体清偿键尾块纯插入（调用点代码
  零改——SidebarView.swift 预期零 diff，改了即偏差须 DECISIONS 解释）；
  分诊 transcript 在案；AGENTS 登记行落盘。
- **commit**: `fix(v2m): extend zh-audit with specifier deep-checking and the Text family`

## T2 — Manual-Only GUI 批余行执行（B 类 AX/computer-use 波；前置 = 波 1 D-1+D-2 闭环）

> **队列正本** = `.work/gui-acceptance/m6-closeout/MANIFEST.md`（42 行
> 总队列；local-only 不入 git）。余行集 = Blocked-Manual/Blocked-Env/
> Blocked-Defect 中**波 1 解锁后可达**的行：GUI-M6C-06/07（色彩目测，
> D-2 解锁；**06 行波 1 T1 已走数值面〔solve 产物符号〕以波 1 证据为准
> 不重跑，本波只走 D-2 解锁后的色彩目测剩余面——M-6 防双走条款，同
> 03/05/08**）+ 16/17/18/19（pano 四行）+ 26（sips 重导出，D-2 解锁 +
> UltraHDR 供件）+ 32/33（AI 蒙版族）+ 34-38（栈面五行，连拍/import 缝
> 供件）+ 39（D-06/D-07 补录）+ 40（guided filter F 行）+ 03/05/08 复查
> （波 1 T1 已走则以波 1 证据为准不重跑）。C 类硬锁行（24/25 HDR 屏、
> 27/28/29 生态可选）**不入本波**——留真人工清单原样。**显式排除注记
> （M-6 供件矩阵孤儿项处置）**：GUI-M6C-30（layer B patch 真图，
> Blocked-Env assetStatus=notReady）不入可达行集——blocker = SAM 资产
> 供件而非波 1 缺陷，与 14（双通道缺席）/31（真多人素材）同族；SAM
> 资产到位即可走，届时随缺口清单补入。

- **action**：
  1. 开工盘点：余行 × 供件矩阵（自然样张 / 真无人像照片 / layer B 资产 /
     连拍素材 / UltraHDR 样张 / merge 产物经 import 缝）——供件缺席行
     如实记 Blocked 保持 + 缺口清单上报 orchestrator 备料，**不硬造判定**。
  2. 逐行执行（AX + CGEvent + screencapture harness；机检判据用脚本直判，
     目测行 B 类判据 = 截图留证 + 判定文字）：每行终态 + 证据指针更新
     本 plan 专属 MANIFEST（`.work/gui-acceptance/v2m/MANIFEST.md`，
     引 m6-closeout 行 id 溯源）。
  3. 新发现缺陷**只登记不修**（m6-closeout D-1..D-5 同款纪律）——登记
     表落 MANIFEST 缺陷节 + SUMMARY 指针；error 级新缺陷停手上报。
  4. **零源码改动**（走查批不动源码；构建产物/临时脚本全 /tmp 即弃域）。
- **验收标准**：可达行逐行终态 + 证据在案；供件缺口清单在案；新缺陷
  登记在案；MANIFEST 落盘（gitignored，零 commit——SUMMARY 记路径）。
- **commit**：**无**（local-only 证据域；本任务产出 = MANIFEST + 证据）。

## T3 — PATCH-LIVEPLANE（V2 #9；顺带候选，随容量）

> 正本 = `V2-PROPOSAL.md` §七.9 + `M6-4-VALIDATION.md` 挂账 E5（D-13
> 申报两笔）：livePlane eager 释放（EditorState→LayerEditingState 新横
> wire）+ patch pass 互斥锁（confirm 在飞切图竞态消解）。主修 `b49215bb`
> 已闭环、登记级零用户可见面、余量小。

- **action**：
  1. **余量盘点先行**：读挂账 E5 原文 + `b49215bb` diff——余量为零
     （主修已覆盖两笔）→ 记销账收工（DECISIONS + 锚），本任务 ΔN=0
     零 diff。余量非零 → 2-3。
  2. livePlane eager 释放：切层/切图身份比对点释放 live 平面（新横 wire
     形态按挂账原文；封存面核查——EditorState/LayerEditingState 非封存
     清单成员，可触）。
  3. patch pass 互斥锁：confirm 在飞 × 切图竞态消解（串行化或守卫）。
  4. 可测面：释放/互斥语义单测 +0..2（归域按 BUNDLE-MAP；不可纯函数化
     则走结构断言或 ΔN=0 登记）。
- **验收标准（机检）**：余量盘点结论在案（销账或修复二选一有锚）；
  修复形态 → `--bundle Layers` + `--bundle App` 全绿 + 语义单测在案；
  `git diff` 窗内（两文件 + 测试）。
- **commit**: `fix(v2m): release the live plane eagerly and serialize the patch pass`
  （销账形态 → `docs(v2m): close the PATCH-LIVEPLANE ledger item as already resolved`）

## T4 — RELEASE-DIRECT-INJECT（V2 #2；顺带候选，随容量）

> 正本 = `V2-PROPOSAL.md` §七.2 + `phases/m5-2-mertens/perf.md` §事故 4 +
> m6-closeout P1 批注记（**配方已实证**：WebP/libwebp PackageProduct
> framework 落 `Release/PackageFrameworks/` 未 embed → 直启 dyld 失败；
> 修复 = 拷入 `Contents/Frameworks/` + `codesign --force --sign -` 全量
> ad-hoc 重签——P1 探针 rc=0 亲证）。

- **action**：
  1. 形态裁（执行批定，DECISIONS 申报）：**助手脚本形态**（首选——
     `Scripts/` 下 make-release-direct-launchable.sh，零产线源码 diff；
     步骤 = Release 构建 → embed 拷贝 → 全量重签 → 直启探针）或 Tuist
     配置面（embed rules——触 Project.swift，须零行为门 + red_lines
     修订申报）。注意 Tuist 版本固化面（dependencies 块零 diff 红线——
     scripts/runcodesign 面按现配置原位扩）。
  2. 直启探针脚本化：构建 → 直启 → rc=0 + 主窗起来（日志判据）——
     transcript 落 evidence。
- **验收标准（机检）**：Release 直启探针 PASS transcript（rc=0）；脚本
  形态 → 产线源码零 diff（`git diff` 仅 Scripts/）；Debug 面零触
  （Debug 静态链接现状不扰）。
- **commit**: `chore(v2m): make Release builds self-contained for direct launch`

## T5 — EXPORT-PRESET-01：导出面板命名预设层（S-M；波尾）

> 正本 = REQUIREMENTS :401 行 + `research/ALCEDO-PARITY-2026-10.md` §二
> （上游 `7052355` 全选项预设形态）。**范围**：格式/质量/位深/sizing/
> 元数据策略/ICC/命名模板整组存具名预设 + Export 页一键套用 + 内置默认
> + 用户预设管理（增删改/重命名）。**预设不捕获 collisionPolicy（M-5
> 钉死）**：REQUIREMENTS :401 字段清单无冲突档 + M3-1-03 KD-1 裁定其为
> Export 页会话态（页关即复位）——预设捕获即静默开立 KD-1 挂账的
> 「跨会话记忆」；套用只动面板态，冲突档仍由用户显式选。执行批若要
> 捕获 = 先修订申报。
> **数据基座零撞**：既有逐项记忆键族
> （`export.jpegQuality` 等 6 键）不动，预设层为加层（`export.presets`
> 单键 JSON 数组形态候选——键形执行批裁，**AGENTS 键族登记义务**）；
> 无 Core/管线触碰（封存面红线：六格式矩阵/sidecar/ExportQueueContract
> 零 diff——预设只装配 `ExportVariant` 面）。

- **action**：
  1. 预设模型 + 存取（UserDefaults JSON 族，注入式 defaults 面——KD-4
     范式：body 零 UserDefaults 直读；typed decode 容错 + 域校验）；
     内置默认预设（代码内置不入库，同 NamingTemplateStore 三内置先例）。
  2. Export 页 UI：预设选择器 + 套用（投影到面板既有控件态）+ 管理
     （保存当前态为预设 / 删除 / 重命名）；`makeRunAssembly` 纯缝扩展
     （M3-1-03 范式——picker→queue 路径可机检）。
  3. zh 键族（预设 UI 面）尾块纯插入 + zh-audit 对账（T1 新门全绿）。
  4. 单测 +2..4 法：预设 encode/decode round-trip + 套用投影（变体字段
     逐项落位——含悬挂命名模板引用 typed degrade〔NamingTemplateStore
     三内置 + Custom 回落先例〕与 collisionPolicy 不在捕获面断言）+
     内置默认不可删 + 损坏 JSON typed 容错。
- **验收标准（机检）**：`--bundle App` + `--bundle Export` 全绿（新法
  在案）；新键 AGENTS 登记；`zh-audit --check` PASS + xcstrings diff =
  尾块纯插入；封存面零 diff（六格式矩阵/ExportQueueContract/sidecar）；
  UserDefaults 键形登记与实现一致（grep 双向）。
- **commit**: `feat(v2m): named export presets on the M2 export page`

## T6 — 条件任务（D-5 并入）+ 收口：全套 `--all` 对账 + 翻账

- **action**：
  1. **条件任务**：V2M-01 T5 未清（DECISIONS 翻案返工等）→ 本批补一
     任务按 V2M-01 T5 原文清偿（已清则本步零动作记一行）。
  2. 定向轮（App/Export + 本批实触 bundle）全绿。
  3. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （**orchestrator 批准制 + 8G 门 + MEMFAIL 机检 + 运行中监视**）。
  4. SUMMARY + DECISIONS；AGENTS 登记（V17 门 + 键族 + ΔN 终值 + 全套
     终值）；TODO/GOAL-STATE 翻账（波 2 closed → VALIDATION/收尾批；
     ROADMAP 行翻账留 VALIDATION）。
- **验收标准（机检）**：exit 0 + 0 fail + 0 MEMFAIL + 七 bundle 8G 门内；
  **TOTAL == 波 1 终值 + ΔN₂（对账式精确；不符 → 停手上报）**；两波
  合并 red_lines 总核对（V2M-01 文尾清单 + 本文件文尾清单并集）。
- **commit**: `docs(v2m): close wave-2 clearing batch (full-suite reconciliation)`

---

## red_lines（零 diff 机检族，T6 收口核对）

- 全部 `*.metal` 零 diff；`LightamerIOP/` 全域零 diff（本批无 IOP 触碰面）。
- `LightamerSidecar.swift` 零 diff；sidecar schemaVersion 零触；V50Order
  零触；Export 六格式矩阵面（ExportFormatSpec/ImageIOEncoders/WebPEncoder）
  零 diff（T5 只加预设装配层）；ExportQueueContract 零 diff；
  GradeCatalog/Registry/HistoryStack 封存面零 diff。
- `Project.swift`：无新测试文件则全零 diff（T5 新测试文件预设落
  `Tests/LightamerTests/ExportPresetTests.swift` 新文件——同批 Project.swift
  + BUNDLE-MAP 登记 + `tuist generate` 恒末位，L041；dependencies 块
  零 diff 硬门）。
- `*.xcstrings`：**仅 T1 活体清偿键 + T5 预设 UI 键族尾块纯插入**；
  `zh-audit --check`（V17 新门）PASS——ABSENT/MISMATCH 零命中。
- UserDefaults：仅 T5 预设键（键形裁后 AGENTS 登记）；其余零新键。
- `\.runModal(` App/Sources 零命中；`String.LocalizationValue("` 插值
  字面形、代码行（非注释）零命中（M-3 钉形——已知豁免锚两处：
  `LightamerApp.swift:2061` doc comment 注记字面〔注释免疫，V15 form 1c
  同款〕/ `ExportInspectorView.swift:433` 拼接形动态查表键〔非插值
  字面，在用豁免锚〕；:433 V17 化由执行批裁量非本批义务）。
- T2 走查批：App/Sources + LightamerCore/Sources + LightamerIOP/Sources
  零 diff（走查零源码改动——T2 时窗内逐 commit 核）。
- 工作树零新增 untracked 源文件（探针/走查产物落 /tmp 即弃与 gitignored
  证据域）。

## 风险与回退

- **T1**：specifier 静态推导误报（Swift 类型推断面深）→ 豁免面收窄纪律
  （不可判 = EXEMPT 不红）；self-test golden 锚死误报边界；误报破既有
  PASS 面 → 收窄重跑，**禁放水豁免到全绿**。
- **T2**：供件大面积缺席 → 可达行缩水合法（缺口清单上报）；AX 通道
  已知限制（CGEvent 键盘判死 / 多选清选不可靠）——交互设计绕行，绕不
  过的行如实记 Blocked-Channel。
- **T3/T4 容量**：余量盘点即决策点——容量不足原样留 V2 挂账（登记不
  销账），禁为凑数带病入批。
- **T5**：预设层与逐项记忆键交互（套用后记忆键写不写）→ 键语义执行批
  定（推荐 = 套用只动面板态，记忆键仍由用户显式动作驱动——与 Alcedo
  预设语义对齐），DECISIONS 申报。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——窗外 fail = 既有缺陷，
  停手上报不静默修。

---

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §一.B（V17 + Manual-Only + N-1 已剔除）+
   §一.C #2/#9 + §一.F（EXPORT-PRESET-01）↔ T1..T5 逐项映射；§一.D 留置
   5 项 + V2 大件 7 项零触碰（不越批）；无孤儿项。
2. **V17 门语义**：三态（PRESENT/ABSENT/MISMATCH）与 D-5 活体的对应关系
   ——checker 用波 1 修后树干跑 `--check`：`toast_hdr_merge_done %lld`
   应为绿例（供给链 = 函数参数 `holeFraction: Float` → `Int(…rounded())`
   包装形 → Int → `%lld` 与目录一致——供给面缺函数参数/包装形则此键
   EXEMPT 非绿，即 E-2 修订失守的哨兵）；多参活体
   `settings_catalogs_rebuild_progress %lld %lld` 应走逐参有序比对
   不误放（位置洞哨兵）；`catalog_session_remove_confirm_body` 应为
   ABSENT 红（清偿前）→ 绿（清偿后）。spec 推导的豁免边界（EXEMPT 节）
   不放水复核。
3. **T2 行集口径**：m6-closeout MANIFEST 余行逐行对表——C 类硬锁行
   （24/25/27/28/29）确实未混入本波；03/05/08/06 不重跑（波 1 证据为
   准，06 只走 D-2 解锁后的色彩目测剩余面）；30 行排除理由注记在案
   （SAM 资产供件族）；供件矩阵真实（不硬造判定）。
4. **S 件余量盘点诚实性**：T3 销账形态须引 `b49215bb` diff + 挂账 E5
   原文逐笔对照；修复形态须证「主修未覆盖的残余」确实存在。
5. **T5 边界**：预设层零撞键族（6 既有 `export.*` 键零 diff）；封存面
   （六格式矩阵/ExportQueueContract）零 diff 干跑；新键登记与实现
   双向 grep。
6. **D-5 条件任务**：波 1 T5 状态核对（已清/未清）与 T6 条件步的实际
   动作一致性。
7. **红线干跑**：xcstrings 尾块纯插入形态（JSON diff 无重排）/ `.metal`
   零 diff / Project.swift dependencies 块零 diff / T2 时窗源码零 diff。
8. **ΔN 对账**：baseline 引用链（3848 → +ΔN₁ → 波 1 终值 → +ΔN₂）逐环
   可追，两波 SUMMARY 记账闭合。
