---
phase: v2-maintenance
plan: "V2M-01"
title: "V2M 波 1 缺陷修复批——D-1 追色按钮零响应（params 快照去热观察读取 + Film/Drt 孪生同构面排查 + GUI-M6C 四行解锁复走）/ D-2 视口绿染（七步侦查 bisect → 按裁定修法 → 绿染回归钉 + Alcedo 交叉证人）/ D-3 filmstrip 不换图（复现加固 + 换图通道钉序）/ D-4 合并对话框「0 张」计数（arm 时快照，三 sheet 同族同修）/ D-5 toast 裸键名（调用点 Int 化对齐在册 %lld 变体）+ 收口全套 --all 对账（批准制 + 8G 门）"
wave: 1
depends_on: []
autonomous: true
requirements: ["V2/Maintenance 修复批（RESEARCH §一.A 缺陷族 D-1..D-5 全 open 逐项闭合；正本 = phases/v2-maintenance/RESEARCH.md + V2M-CONTEXT.md OQ 裁决）"]
success_criteria: "SC 全可机检——T1：ColorMatchPanelModel params 读取链静态机检（binding get 零 coordinator 触达）+ 快照刷新单测 + GUI-M6C-03/05/08 三零消除走查证据；T2：bisect 七步 transcript + 修法落地 + 绿染目测复验证据；T3：复现加固脚本 N 轮零卡死；T4：三 sheet 标题读快照属性 grep + 走查证据；T5：调用点 Int 化 grep + zh-audit --check PASS；T6：全套 --all = 3848+ΔN 对账闭合"
estimated_tests: "+3..5（T1 快照刷新/优先级单测 +1..2 / T2 回归钉 +1..2〔供件缺席可合法 ΔN 更小〕/ T3 +0..1；执行时逐任务如实记账）"
test_bundles: [App, Sessions, IOP, Library]
baseline: "3848/24/0（M6-5 T9 确认轮终值，三路亲跑同值）"
expected_all: "3848 + ΔN₁（对账式；ΔN₁ = 本批实增测试数，预期带 +3..5，执行时按实记账；供件缺席面如实记小）"
files_modified:
  - App/Sources/Lightamer/UI/Shell/ColorMatchPanelModel.swift        # T1：params 快照修法——链记录读取从 getter 热路径摘除（snapshot 存储属性 + 刷新钩子补真〔doc comment :54 已许诺 updateInstance 而实现缺席——本批兑现〕）；binding get 退化纯本地读；D-H1 liveParams 窗口语义零变
  - App/Sources/Lightamer/UI/Shell/ColorMatchPanelView.swift         # T1：:187 binding get 保持 `model.params.strength` 字面（读取链下沉 model 内）；如修法需传参形态则同批微调；onEditingChanged D-H1 三件零触
  - Tests/LightamerTests/ColorMatchPanelModelTests.swift             # T1：+1..2 法（APP bundle :289 现归域）——快照刷新语义（链记录变更 → 刷新钩子 → 快照同步）+ liveParams 窗口优先级保持负测
  - App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift              # T1 同构面排查（同病同修改此文件；健康则零 diff 登记 DECISIONS）
  - App/Sources/Lightamer/UI/Shell/DrtPanelModel.swift               # T1 同构面排查（同上——record getter 穿 editorState.history.effectiveDrtRecord / workspace.drtRecord，无 JSONDecoder 热解码，先验风险低于 ColorMatch；读码裁定）
  - LightamerCore/Sources/Decode/RAWDecoder.swift                    # T2：按 bisect 裁定修法落点（H-Aa 三选：resolveDecoderVersion automatic 收紧 / 机身白名单 / 解码后通道健全性门；H-Ab/H-B 各自落点）——形态执行批定，DECISIONS 申报
  - Tests/LightamerTests/RawDecodeOverridesTests.swift               # T2：+1..2 法（IOP bundle :181 现归域）——裁定行为的回归钉（如 automatic 收紧后的 resolveDecoderVersion 行为矩阵）
  - App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift    # T3：换图三腿钉序（:94-96 .task(id:) / :101-109 grid onChange / :117-123 filmstrip onOpen → :178 loadedImageURL 守卫）——单一换图通道收敛 + 重入守卫，形态按侦查定
  - Tests/LightamerTests/FilmstripModelTests.swift                   # T3：+0..1 法（LIB bundle :382 现归域）——可纯函数化的换图序判定的回归钉；不可纯函数化则 ΔN=0 走 GUI 复现加固证据
  - App/Sources/Lightamer/UI/SessionBrowserView.swift                # T4：arm 时快照计数（@State pendingTargetsCount 或同形）+ 三 sheet 标题改读快照（:280 focus_stack / :305 stack_denoise / :340 hdr_merge 同族同修）
  - App/Sources/Lightamer/UI/LightamerApp.swift                      # T5：:2019 `holeFraction * 100` Float 插值 → `Int((holeFraction * 100).rounded())` 对齐在册 `%lld` 变体（xcstrings 零改动）
  - .work/gsd/phases/v2-maintenance/V2M-01-SUMMARY.md                # T6：执行摘要（逐任务 ΔN 记账 + bisect transcript 指针 + 走查证据指针）
  - .work/gsd/phases/v2-maintenance/V2M-01-DECISIONS.md              # T6：裁定记录（D-1 同构面排查结论 / D-2 修法三选裁定 + 选择理由 / D-3 钉序形态 / D-4 机制定案 / D-5 形态复核）
  - AGENTS.md                                                        # T6：「V2-Maintenance 架构增量」节（五缺陷修法形态 + ΔN 终值 + 全套终值登记）
  - .work/TODO.md                                                    # T6：缺陷登记小节 D-1..D-5 翻账
  - .work/GOAL-STATE.md                                              # T6：续接点翻新（波 1 closed → 波 2）
---

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。清查与裁决正本 =
> `V2M-CONTEXT.md`（OQ-VM-1..5 全按推荐 A）+ `RESEARCH.md`（D-1 根因 §二 /
> D-2 侦查配方 §三 / 盘点表 §一）。D-1 根因链 HEAD 亲核（2026-10-16 后
> planner 复核）：`ColorMatchPanelView.swift:187` binding get →
> `ColorMatchPanelModel.swift:99-111` params getter（**:102
> `coordinator.instanceRecord` → `PipeCoordinator.swift:1667-1669` 每读
> 线性扫 `editorState.instances` + 每读 `JSONDecoder` 解码 paramsData**）
> → sample 84/84 flush 悬挂 + 297 sizeThatFits。
>
> **批次红线**（收口 T6 逐条机检）：零新 SPM；UserDefaults 零新键；
> `.metal` 零 diff（**D-2 例外口**：侦查裁定需要 kernel 时先停手修订本
> plan 申报）；xcstrings 本批预期**零 diff**（D-5 走调用点形态；若执行批
> 复核翻案走 `%lf` 变体形态则恰一变体键尾块纯插入 + DECISIONS 申报）；
> `\.runModal(` App/Sources 零命中；封存面零触（DrtRecord / sidecar schema /
> V50Order / 六格式矩阵 / GradeCatalog / HistoryStack / Registry）；
> `Project.swift` 无新测试文件则全零 diff。构建 `caffeinate -dis` 包裹；
> 单测 = `Scripts/test-direct.sh`（bundle token 大小写敏感无归一：
> `App`/`Sessions`/`IOP`/`Library`/`Export`）。

# Plan V2M-01 — 波 1 缺陷修复批（D-1..D-5）

> **执行序**：T1 → T2 → T3 → T4 → T5 → T6（T4/T5 为 S 级顺带，T3 概率性
> 侦查前置）。每任务独立 commit（Conventional Commits，只 add 相关文件）。
> GUI 走查证据落 `.work/gui-acceptance/v2m/`（local-only，零 commit）。
> D-2 触发供件门：缺陷原两文件（7RM5 ARW / 5G4A DNG）若不可得 → 同机身
> 任意样张替代复现；再不可得 → T2 停在 bisect transcript 登记供件缺口
> 上报，**不硬造裁定**。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/v2-maintenance/V2M-CONTEXT.md`（OQ 裁决 + 红线正本）
- `.work/gsd/phases/v2-maintenance/RESEARCH.md` §二（D-1 根因）+ §三（D-2
  配方——T2 侦查直接照跑）
- `.work/config.toml [gsd]` paused/auto 开关
- `.work/LESSONS.md` L014（GPU 读回 fence）/ L077（$TMPDIR 残留清扫）/
  L041（tuist generate 恒末位——本批无 Project.swift 变更，预期不触）
- `.work/gui-acceptance/m6-closeout/MANIFEST.md`（D-1 样本栈 + 走查通道
  批注记：AXPress 可靠 / CGEvent 键盘判死 / 多选清选不可靠）

---

## T1 — D-1 追色按钮零响应：params 快照去热观察读取（M；修复批首项）

> **机制**（RESEARCH §2.2 已确认，此处执行化）：强度 Slider 的
> `Binding(get:)` 在 layout 期被求值 → getter 穿三个 @Observable
> （`liveParams` → `editorState.instances`〔经 `instanceRecord` 线性扫 +
> **每次 JSONDecoder 解码**〕→ `instance`）→ 热观察对象被注册为 layout
> 属性依赖 → 点击 Solve 的同步突变引发 layout 重测 → 事务反复 invalidate
> 永不沉降 → MainActor 饥饿（solve 的 async Task 排不上）→ 三零症状
> （无进度态 / 无 history item / 无 sidecar）。
> **修法方向（RESEARCH §2.3 推荐已裁）**：binding get 去「热观察读取」——
> 链记录解码改事件驱动快照，`get` 退化为纯本地读。
> **planner 补充亲核**：`ColorMatchPanelModel.swift:54` doc comment 许诺
> 「the model refreshes through `updateInstance`」而**该方法实现缺席**
> （全仓 grep 仅注释命中）——getter 每读穿 coordinator 正是对缺席钩子的
> 补偿读取。本批兑现该钩子 = 修法正形。

- **action**：
  1. `ColorMatchPanelModel` 增链记录快照：普通存储属性
     `snapshotParams: ColormatchModule.Params?`（或含 record 身份戳的
     快照结构），刷新时机 = ①init ②实例切换/revision 变更钩子（兑现
     `updateInstance`——由面板 provider 在 instance 参数变化时调用；
     provider 侧挂点按现挂载面最小改动定）③solve 成功回填点
     （`solve` 尾 `liveParams = nil` 处同批刷快照）。
  2. `params` getter 重排：`liveParams` → `snapshotParams` → 传入
     `instance` 解码（保持既有三级序语义）→ pristine default；
     **getter 零 `pipeCoordinator` 触达**。`currentRecord`（:208-215，
     setStrengthLive 的拖动基座）同面审查：若同穿 coordinator 每次
     tick 线性扫 + 解码，一并快照化（拖动窗内 liveParams 优先不受扰）。
  3. **D-H1 三件语义零变**：begin/live tick/commit 的恰一次 history
     item、拖动读回自身值、`setStrengthLive` 的 clamp——行为面单测
     （既有 `ColorMatchPanelModelTests`）不红为硬门。
  4. **Film/Drt 孪生面板同构面排查**（RESEARCH §2.3 义务）：读码裁定
     `FilmPanelModel.record`（:62-71，穿 `editorState.history.
     effectiveFilmRecord()` / `coordinator.currentFilmRecord`）与
     `DrtPanelModel.record`（:68-81，穿 `editorState.history.
     effectiveDrtRecord()` / `workspace.drtRecord(for:)`）——同为
     binding get → @Observable 穿读，但**无 per-read JSONDecoder**，
     且读面是 history/carrier 而非 instances 线性扫。裁定三分：
     同病（layout 期热读 + 重解码）→ 同修；仅热读无重解码 → 按实测
     sample 证据裁（无证据不预防性重写，登记 DECISIONS）；健康 → 登记。
  5. 回归测试（APP bundle 归域 :289）：`ColorMatchPanelModelTests` +1..2 法
     ——①快照刷新语义：链记录变更 → 刷新钩子 → 快照同步（getter 返回
     新值）；②liveParams 窗口优先级：拖动窗内快照被 liveParams 压住，
     commit 后回落快照。layout 期零观察读取属 SwiftUI 运行时行为
     （XCT 不可达）——可测性边界如实记 DECISIONS，以 GUI 走查证据替代。
  6. **GUI-M6C-03/05/08 解锁复走**（AX harness，配方 =
     `gui-acceptance/m6-closeout/MANIFEST.md` 行 03/05/08 + omp-03 §3.1
     会话）：solve 点击 → 1s 内进度态/readout 出现 + history item 落
     （⌘Z 恰一次撤销）+ `.lra` 落盘（sidecar 面机检）——三零消除逐项
     记证据截图/AX transcript。**06 行（B 类色彩目测）**：池化方向数值面
     （权重 0.1/1.0 的 solve 产物符号）本批可验；色彩目测部分 D-2 未清
     前不可信——挂 V2M-02 T2 走查批（或 D-2 修复后本批内补走，按 D-2
     先后定，SUMMARY 记实际）。
- **验收标准（机检）**：
  - `grep -n "pipeCoordinator" App/Sources/Lightamer/UI/Shell/
    ColorMatchPanelModel.swift` 的 params/currentRecord getter 函数体内
    零命中（形态级机检——getter 退化为本地读；hasImage/solve 的合法
    触达不受此条约束，DECISIONS 附改后文件段锚定）。
  - 定向 `--bundle App` 全绿（含 ColorMatchPanelModelTests 新法 + 既有
    D-H1 行为法不红）。
  - GUI-M6C-03/05/08 三行复走证据在案（`.work/gui-acceptance/v2m/`，
    三零消除逐项截图/transcript）；sample 复验（复现态点击 solve 后
    3s `sample` 无 flush 风暴——修复对照，证据可选做）。
  - Film/Drt 排查结论落 DECISIONS（三分之一坐实即改文件 + 该面板定向
    测试全绿；判健康则两文件零 diff）。
- **commit**: `fix(v2m): snapshot colormatch panel params off the hot binding path`

## T2 — D-2 编辑器视口绿染：侦查 bisect → 按裁定修法 → 回归钉（M；三段式验收）

> **OQ-VM-2 裁决 A 直接兑现**：假说未收敛前不预设修法。假说排序正本 =
> RESEARCH §3.3（H-A 首推〔H-Aa RAW 9 CoreML per-file 毒化 / H-Ab profile
> 错配〕> H-B sidecar 持久态 > H-C 弱）；**关键读码事实**：缩略图 Tier A =
> 内嵌 JPEG 从不进 CIRAW——「缩略图正常」不解罪解码腿；pano_slice TIFF 走
> M4-1 原生腿与 RAW 腿异路。配方 = RESEARCH §3.4 七步，探针 /tmp 即弃
> （M2-7 进程内真链探针方法论），transcript 逐步落 `evidence/`。

- **action（三段）**：
  1. **侦查 bisect**（配方 1-7 步照跑，每步记录判定）：
     ①基线复现 ②sidecar 切断（`.lra` 移走——H-B 一步判）③新项目导入
     ④解码探针：两文件各跑 `RAWDecoder.decode`（`.automatic` vs
     `.forceV8`）小尺寸渲 + 每通道均值/直方图 dump——v9 毒而 v8 净 =
     H-Aa 坐实 ⑤v8 仍毒 → CIRAW options 二分（NR off / vendor lens
     correction off 逐项）⑥解码净而编辑器绿 → 管线双臂（terminalTail
     legacy vs `.drt` 平面统计比对）⑦**Alcedo 交叉证人**：
     `/Applications/AlcedoStudio.app` 开同两文件——正常 = CIRAW 特异 /
     同异常 = 文件本身特异（弱化我方缺陷定性，记录在案）。
  2. **修法落地**（随 bisect 裁定，DECISIONS 申报选择理由）：
     H-Aa → 三选再裁（automatic 收紧〔如 `resolveDecoderVersion` 对
     未验证机身回落 v8〕/ 受影响机身 v8 白名单 / 解码后通道健全性门）；
     H-Ab → profile 臂处理（working space 转换面）；H-B → sidecar 毒化
     路径修。落点优先 `RAWDecoder.swift` 既有 declared seam（M2-3-3 T4
     technicalOverrides 面；`resolveDecoderVersion` :257-273 纯函数面
     单测友好）。**若裁定需要 `.metal` → 停手修订 plan 申报（红线）**。
  3. **绿染回归钉（fixture 级）**：供件可入 fixtures → 缺陷文件（或同
     机身小样张）入 `Tests/Fixtures/` + 通道统计断言法（IOP bundle 归域
     :175/:181）；供件不可入（尺寸/许可）→ 钉**规则**不钉文件
     （`resolveDecoderVersion` 行为矩阵 / 健全性门合成数据单测），
     DECISIONS 记选择。修后 GUI 复现配方重跑两图非绿（目测走查证据 +
     直方图面复验）。
- **验收标准（机检）**：
  - bisect transcript 七步逐步在案（`evidence/v2m/d2-bisect/`，含每步
    判定 + 探针脚本/输出）；Alcedo 交叉证人记录在案。
  - 修法落地 + 定向轮绿（IOP bundle 含 RawDecodeOverridesTests/RAWDecoderTests
    新旧法全绿；App bundle 解码消费面不受扰）。
  - 回归钉在案（fixture 级或规则级，+1..2 法如实记账；供件缺席 = ΔN
    如实记 0 + 缺口登记）。
  - 绿染复验证据：两图重开非绿（截图 + 直方图非单色饱和）。
  - `git diff LightamerCore/Sources/Decode/RAWDecoder.swift` 落窗内
    （decode/resolve/健全性门缝）；`.metal` 零 diff（除非修订申报获批）。
- **commit**: `fix(v2m): resolve the RAW viewport color poisoning per the bisect ruling`

## T3 — D-3 filmstrip 点击不换图：复现加固 + 换图通道钉序（S-M）

> 概率性（复现 ×1 + omp-02 o-ompre1 先例「探针多图会话末图锁定，M2-2
> 面」）。嫌疑缝（RESEARCH §一.D-3 行 + planner 现码复核）：
> `EditorWorkspaceShellView.swift:94-96`（`.task(id: currentImageID)` 重载腿）
> + `:101-109`（grid selection onChange 腿）+ `:117-123`（filmstrip onOpen
> 只写 phase id 腿）+ `:178`（`loadedImageURL != url` 守卫）——三条腿并发
> 序未钉：onOpen 与 onChange 可对同一点击双触发（id 相同则 onChange 守卫
> 挡、不同则双写），`.task(id:)` 重载与守卫竞态可吞换图。

- **action**：
  1. **复现加固**：AX harness 脚本化多图会话连点（≥4 图 filmstrip 循环
     点击 ×N 轮，记录每次画布 URL/sidecar 解码日志）——把概率复现变为
     可重复配方（加固配方落 `evidence/v2m/d3-repro/`）。
  2. **钉序修法**（形态按侦查定，DECISIONS 申报）：收敛单一换图通道
     （filmstrip onOpen 与 grid onChange 走同一 mutation 路径）+ 重入/
     竞态守卫（`.task(id:)` 取消-重启序 vs `loadedImageURL` 守卫的
     时序钉）；omp 先例注记（末图锁定）对照核。
  3. 可纯函数化的换图序判定 → `FilmstripModelTests` +0..1 法（LIB 归域
     :382）；不可纯函数化 → ΔN=0，以复现加固 N 轮零卡死证据收口。
- **验收标准（机检）**：复现加固脚本 ≥3 轮 ×N 连点零卡死（修前配方能
  复现则修后同配方零复现；修前不可稳定复现则加固轮数如实记录 +
  DECISIONS 记置信声明）；定向 `--bundle Library` + `--bundle App` 全绿；
  `git diff` 仅 EditorWorkspaceShellView 换图腿窗内 + 测试文件。
- **commit**: `fix(v2m): serialize the filmstrip image-switch legs`

## T4 — D-4 合并对话框「0 张」计数：arm 时快照（S；三 sheet 同族同修）

> 根因（RESEARCH 定位 + planner 现码复核）：`.sheet` 内容闭包读**活的**
> `pendingTargets.count`（`SessionBrowserView.swift:340` hdr_merge；
> **:280 focus_stack / :305 stack_denoise 同族同构**——RESEARCH 只登记
> HDR，同族扫描本批一并修），sheet 渲染时点计数已 0（正文静态串故正确；
> 为何 live read 取 0 的机制定案 = 执行批 DECISIONS 义务——候选：
> 菜单收起引发视图身份/状态重置 vs 竞态，走查复验）。

- **action**：
  1. arm 点（`pendingTargets = targets` 各赋值点，:152/:157/:168/:180/
     :191/:199/:205）同点快照计数（`@State private var
     pendingTargetsCount: Int` 或同形——以「arm 一次写、sheet 只读」为
     纪律）。
  2. 三 sheet 标题（:280/:305/:340）改读快照属性；启动按钮
     （`let targets = pendingTargets` 捕获面）零改（动作面仍用全数组）。
  3. 机制定案走查：AX harness 重跑 HDR merge 对话框（合成 bracket 供件
     配方 = m6-closeout 批注记）标题计数正确 + 三 sheet 走查各一轮；
     机制解释（为何原形态取 0）落 DECISIONS。
- **验收标准（机检）**：
  - `grep -n "pendingTargets.count" App/Sources/Lightamer/UI/
    SessionBrowserView.swift` 仅剩 arm 赋值点右侧（或零命中——快照后
    sheet 闭包零直读）；三 sheet 标题行读快照属性（grep 三行在案）。
  - 走查证据：三对话框标题计数正确（截图/AX transcript 落
    `.work/gui-acceptance/v2m/`）。
  - 零新本地化键（标题键族 `%lld` 变体原位复用）；`--bundle Sessions`
    全绿（SessionBrowserModelTests 不受扰）。
- **commit**: `fix(v2m): snapshot the merge dialog target count at arm time`

## T5 — D-5 完成 toast 裸键名：调用点 Int 化对齐在册变体（S）

> 根因 = specifier 错配（RESEARCH 定位 + planner 现码复核）：插值是
> Float（`LightamerApp.swift:2019` `holeFraction * 100`）→ 运行时查表键
> `toast_hdr_merge_done %lf`，目录在册变体是 **`%lld`**（xcstrings:23513，
> extractionState manual）→ 查表 miss 回退默认值面 = 裸键名「0.000000」。
> **修法裁定（planner 定，执行批复核可翻案）**：调用点
> `Int((holeFraction * 100).rounded())` 对齐在册 `%lld` 变体——目录
> en/zh 两值按整数百分数语义撰写（`%lld%%`），`%lf` 变体会渲染
> 「12.340000%」反劣化且 xcstrings 零改动；RESEARCH §四「补 %lf 变体」
> 的替代形态，翻案 = 加 `%lf` 变体尾块纯插入 + DECISIONS 申报。
> 与 V17 同款机检：V17（波 2）specifier 深检落地后此键成为绿例活体。

- **action**：`LightamerApp.swift:2019` 插值表达式 Int 化（rounded 半分
  边界行为 = DECISIONS 记一句）；其余零触。
- **验收标准（机检）**：`grep -n "holeFraction \* 100"
  App/Sources/Lightamer/UI/LightamerApp.swift` 命中行含 `Int(...rounded())`
  形态；运行时键命中（走查证据：HDR merge 完成 toast 呈 zh 文案非裸键，
  复用 T4 走查会话顺带取证）；`python3 Scripts/zh-audit.py --check` PASS
  且 xcstrings 零 diff。
- **commit**: `fix(v2m): match the merge-done toast key to its integer catalog variant`

## T6 — 收口：SUMMARY/DECISIONS + 定向轮 + 全套 `--all` 对账（批准制 + 8G 门）

- **action**：
  1. 定向轮：受影响 bundle 全绿（App / Sessions / IOP / Library——按
     实际 files_modified 增删）。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （**orchestrator 批准制**——夜间授权链覆盖在案；运行中保持监视，
     >8G 或内存压力转红立即 kill；MEMFAIL 机检兜底）。
  3. SUMMARY（逐任务 ΔN 记账 + D-2 bisect transcript 指针 + GUI 走查
     证据指针）+ DECISIONS（五缺陷裁定记录）；AGENTS「V2-Maintenance
     架构增量」节（修法形态 + ΔN 终值 + 全套终值）；TODO 缺陷登记
     D-1..D-5 翻账；GOAL-STATE 续接点 = 波 1 closed → 波 2。
- **验收标准（机检）**：exit 0 + 0 fail + 0 MEMFAIL + 七 bundle 全 8G
  门内；**TOTAL == 3848 + ΔN₁（对账式精确，ΔN₁ 按执行实记账；异常形态
  ΔN 与记账不符 → 停手上报）**；red_lines 全项机检过（文尾清单）。
- **commit**: `docs(v2m): close wave-1 defect batch (full-suite reconciliation)`

---

## red_lines（零 diff 机检族，T6 收口核对）

- `LightamerIOP/` 全域零 diff（T2 落点在 `LightamerCore/Sources/Decode/`
  ——不在 IOP 模块域）；全部 `*.metal` 零 diff（D-2 修订申报获批为例外
  口，未申报则零 diff 硬门）。
- `LightamerSidecar.swift` 零 diff；`Pipe/History/` + V50Order 零触；
  Export 六格式矩阵面零 diff；GradeCatalog/Registry 封存面零 diff。
- `Project.swift` 零 diff（本批 files_modified 无新测试文件——新法全落
  既有文件；若执行批确需新文件 → 同批 Project.swift/BUNDLE-MAP 登记 +
  `tuist generate` 恒末位（L041）+ red_lines 本条修订申报）。
- `*.xcstrings` 零 diff（D-5 主形态；翻案形态 = 恰一变体键尾块纯插入）；
  UserDefaults 零新键；`\.runModal(` App/Sources 零命中；
  `String.LocalizationValue("` 插值禁形零命中；`zh-audit --check` PASS。
- 工作树零新增 untracked 源文件（探针/走查产物全落 /tmp 即弃域与
  gitignored 证据域）。

## 风险与回退

- **T1**：快照刷新钩子的 provider 侧挂点若改动面超预期（挂载链深）→
  回退预案 = coordinator 侧 revision 通知（Notification/闭包注入）替代
  provider 传参，DECISIONS 记选择；D-H1 行为法红 = 硬停（语义回归禁收）。
- **T2**：bisect 无法收敛（七步后假说均不成立）→ 停手上报 orchestrator
  （research 复审 / 降级接受 / 另立专项三选），**禁押注修**；供件缺失 =
  同面目（复现配方以同机身样张替代；再缺 = T2 只交 transcript）。
- **T3**：概率缺陷修后无法证明「已修」（复现本就不稳）→ 验收 = 加固
  脚本大 N 轮零复现 + 钉序改动机制论证（DECISIONS），如实记置信声明。
- **T4**：机制若为视图身份重置（@State 快照同灭）→ 快照上移（arm 状态
  提到父层/外部绑定），DECISIONS 申报。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——窗外 fail = 既有缺陷，
  停手上报不静默修。

---

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §一.A 缺陷族 5 行 ↔ T1..T5 逐项映射（D-4/D-5
   各一 S 任务；D-1/D-2 各一 M 任务；D-3 一任务）+ T6 收口；无孤儿项。
2. **D-1 根因链复核**：`ColorMatchPanelView.swift:187` / `ColorMatchPanelModel.swift:99-111`
   （:102 instanceRecord）/ `PipeCoordinator.swift:1667-1669` 现码亲读对
   RESEARCH §二——确认修法（快照 + 钩子兑现）确实切断 layout 期
   JSONDecoder/线性扫路径；**:54 doc comment 许诺 updateInstance 而实现
   缺席**是 planner 新发现（改法 = 兑现钩子），checker 复核该读法。
3. **D-1 三级序语义**：修后 `params` 的 live → snapshot → instance →
   default 序与修前 live → coordinator record → instance → default 语义
   等价性——「committed truth, never a stale cached copy」注释（:96-98）
   与快照化的张力：刷新钩子时机覆盖所有 committed 变更路径（solve 回填 /
   history move / 实例切换）吗？checker 反向找漏刷新路径。
4. **Film/Drt 三分裁定**：同病同修 / 登记 / 健康的证据充分性（DECISIONS
   是否引 sample/读码证据，非直觉）。
5. **D-2 三段式**：bisect transcript 逐步可复跑；修法与裁定证据链一致
   （三选的理由非事后包装）；回归钉钉住的是裁定本体而非旁支。
6. **D-5 形态翻案权**：planner 裁 Int 化 vs RESEARCH 原文「补 %lf 变体」
   的偏离已显式申报（任务头注）；checker 复核目录两值的整数语义读法
   （xcstrings:23513-23529）。
7. **红线干跑**：xcstrings 零 diff / `.metal` 零 diff / Project.swift
   零 diff 三条干跑核；bundle token 大小写（`App`/`Sessions`/`IOP`/
   `Library`）。
8. **ΔN 对账**：expected_all 为对账式非死数——checker 核执行批 SUMMARY
   的 ΔN 记账逐任务可追。
