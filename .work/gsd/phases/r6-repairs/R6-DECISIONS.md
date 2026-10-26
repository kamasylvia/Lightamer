# R6 修复批 — DECISIONS（2026-10-26/27）

基线 HEAD = `29be5cba`（全套 4287/39/0）。批内容 = T1 导入零行真修 +
T2 omp obs-3 消费 + T3 姐妹载体三件 + T4 收口。

## 一、T1 导入零行 — 归因与修法

### 1.1 归因（file:line + 机制）

**病灶机制 = run tail 的 nil 直写与 coalescer 排队交付的 main-queue
交错复活**：

- 写点全景（`App/Sources/Lightamer/Library/LibraryProjectController.swift`）：
  - :418 deliver 闭包（coalescer 交付面）
  - :438 run 开头 importing（无害）
  - :459 run tail `importProgress = nil`（**直写**，终态载体）
- 竞态链：service 终态 `.completed` → `submit` 的 terminal bypass 排
  `Task { @MainActor flushTerminal() }`（:810-814）→ `importFolder`
  返回 → runImport resume job 与 flushTerminal job **竞争 main queue，
  顺序无保证**。若 nil 先落、交付后到：
  - `importProgress` 被复活为 interim/completed 且**再无写者**；
  - 消费者 `ImportProgressModifier`（`WorkspaceHostView.swift:1119-1143`）
    的 else 分支（progress == nil → `reloadFirstPage()`，**grid 行到达
    发布的唯一触发**）永不触发；
  - DB 行恒在（法证 n=1 五项目）、grid 永零行、全线程 idle（R5-2 采栈
    形态）——「grid rows never arrived」probe 表型全解释。
- 负载敏感 + 低载 2/5 基线：纯调度竞态，高载下 main queue 拥塞拉宽
  交错窗口（4/9），低载亦发（2/5）。
- FIX2-01（`da99ea2f`）与本病灶的边界：FIX2 修的是「完成态发布」
  （O(files) main-queue storm 饿死 run tail）；本病灶在「行到达发布」
  （nil 终态被迟到交付覆盖）——同一腿的下一环。既有测试
  `ImportProgressCoalescingTests.swift:10-14` 的设计假设「两载体都
  直达 UI」未防交错，正是漏网处。

### 1.2 修法（最小缝）

`ImportProgressCoalescer.invalidate()`（锁内置 invalid + pending 清空；
submit/drainWindow/flushTerminal 三面锁内检查失效即丢；已交付不回撤）。
run tail 在 nil 直写**之前**调用（:459 前插 `coalescer.invalidate()`）——
nil 恒为终写者。两载体设计形态保持，只有输掉的竞态死掉。

### 1.3 回归测试（阈值申报）

- 机制面（`ImportProgressCoalescingTests` +2 法）：确定性交错复现——
  三个交付 job（leading drain / in-window / terminal flush）全部排队后
  invalidate 先行 → 断言零交付 + 已交付不回撤 + invalidate 后 submit 丢。
  「等待」= main-queue drain 语义（waitMain + 300ms straggler 窗），
  非时间轮询硬等待。
- 生产缝（`ImportCompletionRegressionTests` +1 法）：真 `runImport` 后
  20 轮 main-queue drain，断言 nil 终态永不复活 + DB 行 3/3 在册。
  **阈值申报：选择发布断言（importProgress 终值 + drain 后稳定性）
  而非 grid 可见性时间窗**——grid reload 的触发源 = onChange else
  分支，其必要条件 = nil 不被复活；机制面的确定性交错 + 生产缝的
  终态稳定两腿合围即完整判别，grid 行可见时间阈值在本测试形态下
  不可靠（竞态是概率性的，时间窗断言会假绿）。

## 二、T2 omp obs-3 — 实测判定与文档化出口

### 2.1 实测（GUI 探针，2026-10-26）

配方 = `-la_film_probe /tmp/r6-t2-probe`（v1 老档 fixture = M8-FIX
验收同源 float32-gradient.tif + process:1 sidecar）+ swift AX 探针
（`/tmp/r6-ax-probe.swift`，即弃）全树收集 kAXIdentifierAttribute。

**结果实锤且扩面**：不止迁移按钮——**Inspector 列全部无显式容器化
的控件 id 均被祖先覆盖**：`MIGRATE-BUTTON-ELEMENT: id=Inspector
role=AXButton title=更新到当前渲染代`；同列的 film.close / 双 picker /
全部 slider / content.toggle / solve.button 同判。**存活例外** =
latitude/placement 两 section（有显式 `.accessibilityElement(children:
.contain)` + 自有 id，`FilmPanelView.swift:407-408/565-566`）。

**机制**：无显式容器化的中间层子控件，identifier 被最近带 identifier
的祖先（`InspectorView.swift:133` 的 `"Inspector"`）覆盖——macOS 27
SwiftUI AX 实现的穿透行为，列级系统缺陷非单按钮缺陷。

### 2.2 出口裁定：文档化（产线零 diff）

否决单点修的三依据：
1. 覆盖是列级系统行为——单点修 migrate（contain + 新 id）触碰
   FilmPanelSpectralUITests frozen inventory 冻结面 + 制造列内孤岛
   （其余十余控件继续死）。
2. `.accessibilityElement(children: .ignore)` 形态风险：Button 变叶子
   可能吞 title（AXPress 的实际寻址键），把 omp 已验证的 by-title
   通道（AXPress err=0 即现 sheet）反修坏。
3. omp 处方正向 = 工具面统一 AXPress，非按钮改造（obs-3 原文）。

交付 = `.work/gui-acceptance/r6-axpress/Synthetic-Input-AXPress-Notes.md`
（机制说明 + 驱动配方 + DRT 面板同病预警 + 系统性修复的独立批裁决面
登记）。列级容器化系统性修复（每 section 显式 contain）留独立批。

## 三、T3 姐妹载体三件 — 逐载体结论

### 3.1 判定法（M-1 诊断法复用）

重开载入腿核实：`EditorWorkspaceShellView.loadCurrentImage()`
（`EditorWorkspaceShellView.swift:193`）`guard editorState.loadedImageURL
!= url else { return }`——**重开同图全跳 load 链**；`loadedImageURL`
唯一写点 = load 本体（close 链不清）；`PipeCoordinator.load` 的
`historyLoadedURL != url` guard（`PipeCoordinator.swift:1210`）同样不
触发 → sidecar restore 腿（:1233/:1237/:1241）不跑。restore/sync 腿
全部调用点已核：唯一触发 = 真 load（guard 内）与 history 导航/commit
——重开后均无。**三载体同判：零载入 → drop 即真丢。**

### 3.2 逐载体（全部修，M8-FIX-1 同款 = 删 closeEditor drop 行 + 函数本体 + doc 偏离申报）

| 载体 | commit | 病链（伤害面） | 判别腿 |
|---|---|---|---|
| DRT | `95729b14`（issue #5） | `terminalTailPolicy`（PipeCoordinator:667-677）读空 carrier → DRT 尾段静默掉至下次 DRT commit/navigation；面板读 history 投影掩盖 | DrtPersistenceTests 改写：close 后 hasDrtRecord + record 读面（terminalTailPolicy 的两读面）答保留值 |
| film | `f77d3488`（issue #6） | `filmTailPolicy`（:815）读空 carrier → 胶片腿静默掉；§1.6 登记缺口正主 | FilmCoordinatorTests 改写 + **新真渲染门腿**：commit 起 filmTailPolicy(.preview) 非 nil → close 后仍非 nil（public 缝直断言） |
| raw | `eba66447`（issue #7） | 双读面饿死：RawDecodePanelView.reseed（:278）读空 → 面板控件观感归零；任何重开后 re-decode（load 链 overrides 传参 :259）用 identity → 存档技术参数真丢 | SidecarV5Tests 新法：双 url overrides 经 close 存活（reseed/re-decode 链的唯一重开源） |

安全性（三载体同 process 审计）：per-path 键控跨图无泄漏；真载入恒
覆盖（restore 腿 graded 语义）；session 内 sidecar 不重读（保留 vs
drop 无差别）；图库面不写 sidecar。**无载体走「不修」分支**——三
载体均无合法重开重载腿（依据见 3.1，两 guard 事实）。

附带勘误：processVersions doc 的「unlike the film/DRT/raw carriers」
对比句随家族全员豁免而失效，已更正（历史行为语义未改写，仅注释
勘误 + R6 注记）。

## 四、封存面申报（15 项零 diff 红线核验）

`git diff 29be5cba..HEAD --name-only` 产品面全量 = 8 文件：

- `App/Sources/Lightamer/Library/LibraryProjectController.swift`（T1，
  非封存面）
- `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift`（T3——**封存面
  例外 = M8-FIX 先例的载体族区段**，逐 hunk：①drtRecords/filmRecords/
  rawDecodeOverrides 三段 doc 注释偏离申报 ②三 drop 函数本体删除
  ③closeEditor 体（三 drop 调用行删 + doc 重写）④processVersions
  doc 勘误句。**载体读写面函数（setSession*/restore*/read faces）
  零语义改动**）
- 6 个测试文件（改写 + 新增判别腿）

`LightamerCore/`、`LightamerIOP/` 自基线**零 diff**——DrtRecord /
TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal /
DrtEotf / ExportQueueContract / 六格式矩阵 / NodeGraphCommand / sidecar
schema（LightamerSidecar）/ HistoryStack / HistoryHash /
PipelineDocument / V50Order / GradeCatalog 全部未触。

## 五、测试增量与机器纪律

- ΔN = **+5**（任务书预估 +4..+10 区间内）：CoalescingTests +2 /
  CompletionRegression +1 / FilmCoordinator +1 / SidecarV5 +1；
  DrtPersistence/DrtPanelModel 改写零增量。
- 全套机器纪律：guard --wait 通过 + 起跑前 ps 清零验证（GUI 实例 0）+
  `machine-guard.sh --monitor 21600` 伴跑 + nohup disown；GUI 探针
  （T2 film probe）用后 quit→kill 清零复核（parentage 核验后处置，
  pid 22313 parent=1 = GUI 实例）。
- 网络：gh issue 建单期间 px --up（订阅超时一次，清死代理残留
  `~/.config/xray/proxy.{fish,bash}`/xray.pid 后重试成功）——issue
  建完继续伴跑至全套收口后 px --stop（见 SUMMARY 卫生节）。
