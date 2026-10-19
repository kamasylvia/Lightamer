# F0P-PLAN-REVIEW-OMP — F0'-production 三 plan 独立复审（omp 制度复审）

> **结论头：PASS / 0 blocking + 3 major + 10 minor。**
> 审计对象 = `CONTEXT.md` + `F0P-01/02/03-PLAN.md`（fixer 后 HEAD `ff94f9c7` 起算，plan 文本自 `2ba9393e` 冻结零改）。
> 背景基座 = `phases/nsmenu-spike/F0PRIME.md` + 分支 `spike/f0prime-shell`（`a35ad151`/`c9a91562`/`d8d1380a`）。
> 方法 = 纯只读 + 独立坐标抽查（~25 处亲核，以 plan 引用基线 `9a0b9530` 为准）+ 落地执行对照（P1 T1–T6 已落，用作 plan 可执行性实证，不作结论替代）。
> 与 `F0P-PLAN-REVIEW.md` 关系：已读；fixer 13 条回写逐条在位亲验（§六），但本评审结论全部来自独立取证，不照抄其条目——下文 13 条均为新发现（无一条与 zcode M1–M4/m1–m9 重合）。
> P1 已执行至 T6（`752c5294`）的含义：P1 面 findings 须以后验口径判（落位偏差归执行 DECISIONS，不归 plan 缺陷）；本评审 3 major 全部落在未执行的 P2/P3 面，可在 C 档停期间修 plan，不动执行。

---

## 一、Goal-backward（charter `35a6c178` 六目标覆盖）

| # | Chartered 目标 | 落点 | 判定 |
|---|---|---|---|
| G1 | 壳交接（@main 手动 NSApplication + NSHosting + 自建 NSMenu） | P1 T6（entry 切换 + face 搬运 + bridge 装配 + Deps 接线） | ✓ 全覆盖；落地 `752c5294` 恰三文件，与 SC 一致 |
| G2 | 菜单全族 parity | P1 T3/T6（树/去桩/接线）+ P2 T1（树镜像/enabler/shortcut/标题）+ P2 T7 面 16（像素对照） | ✓ 全覆盖；抽查见 §三 |
| G3 | 未追踪 @Observable 读审计（硬前置，4 缺口） | P1 T2 缺口1 / T3 缺口2 / T4 缺口3 / T5 缺口4（登记） | ✓ 4 缺口逐项闭合，硬序（先于翻转）在 red_lines + 执行序双钉 |
| G4 | @State→@Observable 迁移 | P1 T4（ShellGraph 9+1 字段 + columnVisibility 提升）+ P2 T2（迁移等价测试） | ✓；RESEARCH §4「零新增迁移、唯一增量 columnVisibility」与 T4 一致 |
| G5 | 全套回归 | P2 T5（等价性门）+ T6（三轮同值）+ P3 T5（退役定向轮） | ✓；门链完整（等价门→全套门→退役定向） |
| G6 | FB 稿补强（双重排除法证据链） | P3 T3（终章回填呈用户） | ✓；时机（P2 定版后）正确 |

Charter ②（F1–F3 park）属排除项，三 plan 零承接 ✓（无越界任务）。

## 二、翻转原子性与可 revert 性 — 成立（亲测）

- **内聚性 ✓**：T6 落地 `752c5294` = 恰三产线文件（`LightamerApp.swift` 15 行 entry 尾 + WindowCapture 可见性 / `ContentView.swift` 15 行 :551 缝 / `LightamerShell.swift` 新建 2368 行），与 F0P-01 T6 SC（:384–387）逐字一致。
- **revert 完整性 ✓（亲测）**：本评审执行 `git revert --no-commit 752c5294` 干净应用 + `git revert --abort`，树恢复干净。revert 后语义 = entry 回 `LightamerApp.main()` + T3/T4 inert 件保留但无激活路径（`install(deps:)` 唯一调用点在 `LightamerShell` 内，随文件删除而消失）= T5 态，零半态。
- **fork 序零触 ✓**：`9a0b9530..HEAD` 对 `LightamerApp.swift` 的 diff 仅两 hunk（entry 尾 7 行注释+1 行调用 / WindowCapture 可见性 1 行），四把 fork（DEBUG flock ×2 → MCP headless → AI worker → GUI）逐字节在位。
- **增量 vs spike 可控**：`LightamerShell.swift` vs spike `F0PrimeShell.swift`（改名归一后 diff 250 行）= 注释重写 + graph 共享单例 + M1 缝 + export gate fork + 四 stub 接线 + D-F0P-4/8 行 + 控制器装配，无计划外搬运变形。

## 三、坐标抽查（25 处，以 `9a0b9530` 为准，全部吻合）

| # | 坐标 | 亲核 |
|---|---|---|
| 1 | `LightamerApp.swift:128-158` entry fork 序 | ✓ 四把 fork + `LightamerApp.main()` 尾 |
| 2 | `:168-203` AppDelegate final + willTerminate Notification | ✓ final + load-bearing 注释在位 |
| 3 | `:252` App struct / `:437` legacyLibraryEnabled let | ✓ |
| 4 | `:507` Window main / `:1797-1799` defaultSize/toolbar/commands | ✓ |
| 5 | `:2024/:2029` openWindow 双点 + `ContentView:140/:551/:553`（M1 缝） | ✓（AX id 在 :553，plan 写 :551±2 行内） |
| 6 | `:2212/:2224/:2236` 三窗 scene + env 注入 | ✓ 与 T4 SC 逐项对齐 |
| 7 | `:2639/:2645` batchPasteBlocked/readOnlyPasteToast statics | ✓ |
| 8 | `:2692/:2699` toggleSidebar/toggleInspector（.all↔doubleColumn/detailOnly） | ✓ 与 shell 写侧逐点平移一致 |
| 9 | paste enabler 二元形（CONTEXT 写 :2001/:2007，实测 **:2003/:2008**） | ✓ 语义对，行号漂移 2 行 → m-omp-3 |
| 10 | `:1928` ⌘W back_to_library（enabler `phase != .editor` + ⌘W） | ✓；D-F0P-01-5 落地实测 1:1 已闭环 |
| 11 | `:1831-1838` ⇧⌘O picker（`FileOpener.openSessionFolder`）vs spike `recentSessions.first` 直开 | ✓ 分歧实证成立，M4 picker 缝已落 P1 T3 + 落地 `openSessionPicker` |
| 12 | `ContentView:143` columnVisibility @State / `:249-250` 双 publish / **`:798` page 腿 publish** | ✓ 前两处；**:798 未被 P3 枚举 → OMP-M2** |
| 13 | `EditorMTKView:131-138` ZoomSignature push-once + `EditorAreaView` body 对 zoom 族零 tracked read（:299 是手势闭包读、`transform(` 无 tracked 语义） | ✓ 缺口1 证据链成立 |
| 14 | `MenuCommandSet:78` visibleCommandIDs 纯函数 | ✓ P2 T1 双臂镜像数据源成立 |
| 15 | `WorkspaceHostView:195` workspace publish / `:25-35` WorkspaceModelKey 定义 | ✓ |
| 16 | `InspectorView:428-432` metadataFocused publish | ✓ |
| 17 | `Scripts/test-direct.sh:214` HOST_BIN / `:250-262` DYLD 注入 | ✓；app main 照常跑，先例成立 |
| 18 | face ⑤ manifest `AgentControlCoordinatorTests:228-231`（token `|| agentControl.holdsControl)`） | ✓；注意 manifest 共 10 行（face ①–⑧⑩⑪⑫，非「12 行」字面） |
| 19 | `ProjectReadOnlyFaceTests:499-506` batchPasteBlocked ×4 + toast | ✓ P3 重指对象精确 |
| 20 | `SettingsPagesTests:107-125` DefaultKeymap pin / `SheetEnvironmentInjectionTests:66-97` 自挂 harness | ✓ P2 T1/T4 先例真实存在 |
| 21 | spike `armObservation` 读集 = 18（`_ = deps.`×12 + ws×5 + shared×2，`NSMenuBridge.swift:614-632`） | ✓ m1 实数成立；落地 19（+exportPageActive 双轨）→ m-omp-2 |
| 22 | 标记族 16 项（rating clear+`1...5`=6 / flag ×3 / color clear+`0..<6`=7，`:2119-2164`） | ✓ m2 实数成立 |
| 23 | AX id 族（:1927/:1934/:1945/:2018/:2090/:2094 + Marker upscale/denoise） | ✓ m5 迁移集精确；落地 `setAccessibilityIdentifier` 方法形已补 |
| 24 | spike Deps 无 `inspectorState`（7 对象）/ 无 `settings` 闭包 | ✓ m6 + D-F0P-01-2 两扩展的必要性成立 |
| 25 | `LightamerTests` 代码级 `LightamerApp.` 引用 = 恰 2 文件（AgentControl manifest 行 + ProjectReadOnlyFace 调用点；AppLaunchTests 命中是注释） | ✓ RESEARCH §5.2「2 文件」成立 |

## 四、ΔN 算术 — 闭合

- 基线权威数 `3969/37/0` ✓：`AR-02-03-ACCEPTANCE.md:50` 全套净轮三方同值，bundle 分账 687+460+494+738+284+385+921=3969，skip 5+3+5+4+9+5+6=37（App 921/6/0，`--all` 口径；定向轮 skip 16 vs 6 方差见 obs3，不污染 `--all` 门）。
- CONTEXT 勘误①（3905→3969）✓：3905 系 M7-3 数，M7-4→3925→audit→3969 演化链在案。
- 分账加总 ✓：P2 四族 (8..12)+(3..4)+(3..4)+(1..3)=15..23；P1(+0..2)+P2(+15..23)+P3(+0)=+15..+25 → 3984..3994。全批带与三 plan front-matter 一致。
- P1 落地 ΔN=0（T1–T6 零测试文件）∈ +0..2 ✓。

## 五、红线 15 条落位 — 逐条有夫（附 1 条文本缺陷 → m-omp-10）

| # | 红线 | 落位 | 态 |
|---|---|---|---|
| 1 | FIX2③ McpServerController 零 diff | P1 T3/T6 SC + P2/P3 红线；`9a0b9530..HEAD` 该文件零 commit | ✓ |
| 2 | 封存面零 diff | 三 plan 红线 + P1 T6 SC；IOP/metal 零 commit | ✓ |
| 3 | 无 QA 回切 | D-F0P-5 + `LIGHTAMER_SHELL` 全仓零命中（亲测） | ✓ |
| 4 | 翻转独立可 revert | P1 T6 SC + §二亲测干净 revert | ✓ |
| 5 | xcstrings 零 diff 预期 | P1 T3 + P3 T2；`9a0b9530..HEAD` 零 diff（亲测） | ✓ |
| 6 | LocalizationValue 禁形 | P1 T3 + P3 T2；`String.LocalizationValue("prefix_` 零命中（亲测） | ✓ |
| 7 | disable-not-unmount | enabler 三拼写（`!$0…` New/Open/ProjectRecent / `&& !d…` undo/redo / `||…` SwiftUI 侧）在位；face ⑤ P3 重指（勘误②） | ✓ 设计成立 |
| 8 | 基线 3969/37/0 + skip 口径 | 三 plan baseline 行 + §四 | ✓ |
| 9 | AppDelegate 零改 | 意图正确，但文件名错误——**仓内无 `AppDelegate.swift` 文件**，类在 `LightamerApp.swift:168-216` | ⚠ → m-omp-10 |
| 10 | DEBUG fork 序零触 | P1 T6/P2 T5/P3 保留段；落地 diff 证逐字 | ✓ |
| 11 | L057 | 三 plan `.runModal(` 复跑；亲测零命中 | ✓ |
| 12 | UserDefaults 应用级零新键 | 三 plan；代码 diff 无 defaults 键（autosave 系运行时系统键） | ✓ |
| 13 | --all 批准制 + 监视 | P2 T6 全链（批准/caffeinate/8G/MEMFAIL/parentage） | ✓ |
| 14 | C 档门控 | P1 T7.6 / P2 T7.6 / P3 T5.4 三停位 | ✓ |
| 15 | LightamerShell* 改名 | P1 T6 SC + P3 复跑；`F0PrimeShell` 在 `App/Sources` 零命中（亲测） | ✓ |

---

## 六、Major 清单（3 条——门位修正，不动结构）

### OMP-M1 — P3 T1 漏列 `runAIDeterminismProbeIfRequested` static 迁移：退役按字面执行 = DEBUG 编译断（major）

- **severity**：major。P3 未执行，在 P2 C 档停期间修 plan 即可；不阻塞 P1/P2。
- **证据链**：
  - `App/Sources/Lightamer/UI/Shell/LightamerShell.swift:2214`：`LightamerShellController.init()` 内 `LightamerApp.runAIDeterminismProbeIfRequested()`（DEBUG，App struct `init` 体的逐字平移——`LightamerApp.swift:439-447` @ `9a0b9530`）。
  - `F0P-03-PLAN.md:84-91`（T1 action 1）：退役域 = App struct 全体；SC `F0P-03-PLAN.md:109-112` 要求 `struct LightamerApp` 零命中。
  - `F0P-03-PLAN.md:92-95`（T1 action 2）：statics 迁壳只列 `batchPasteBlocked`/`readOnlyPasteToast` + armed 旗标确认——`runAIDeterminismProbeIfRequested`（`LightamerApp.swift:2873` @ `9a0b9530`）不在迁移清单。
  - `F0P-03-PLAN.md:16` 红线：壳侧四文件本 plan 零 diff。
  - 四者合取 = 不可满足三元组：删 struct（含该 static）→ shell :2214 悬空（DEBUG 编译红）；保 struct → SC 零命中门挂；改 shell 重指 → 犯壳侧零 diff 红线。（`displayPlaneHash` 不在此列：shell `:1980` 已自带副本，删 App 侧安全。）
- **处方**：P3 T1 action 2 增第三腿——`runAIDeterminismProbeIfRequested` 迁壳类型（或与 shell 同文件 helper），`LightamerShell.swift:2214` 调用点同 commit 重指；红线「壳侧零 diff」加显式例外行（仅此一调用点重指，`git diff` 单 hunk 面核）；SC 增「`LightamerApp.runAIDeterminism` 零命中 + shell 内新宿主恰一处定义」机检。
- **门位**：P2 闭环停期间修入 F0P-03-PLAN.md，P3 开工前复核。

### OMP-M2 — P3 T1 focused-value 退役域缺 `:798` 站点 + 与壳 face 活 `@FocusedBinding` 碰撞（major）

- **severity**：major。两腿同属「退役域圈定不完整」，P2 C 档停期间修 plan。
- **证据链**：
  - 腿 A（漏点）：`ContentView.swift` 的 `.focusedSceneValue` 发布是**三处**不是两处——`:249-250`（column + export sheet 腿）+ **`:798-802`**（export page 腿，`InspectorPageMount` 路由，get=exportPageActive/set→openExportPage）。`F0P-03-PLAN.md:96-100`（T1 action 3）只枚举 `:249-250`；SC（:109-112）+ T2（:126-131）的 `focusedSceneValue` 全零命中门按字面执行必挂（残留 :798）。
  - 腿 B（碰撞）：`LightamerShell.swift:94` `@FocusedBinding(\.exportPanelRequest)` 是 T6 落地的 gate=true sheet 腿活代码，依赖 `ExportPanelRequestKey` 定义存在。T1 action 3 要求退役键定义（含该键）→ 删键 = shell 编译断；保键 = 「键族退役」SC 落空一半。同样受红线壳侧零 diff 锁死，无 plan 内合法解。
- **处方**：action 3 改枚举为「ContentView 两处（:249-250 + :798 page 腿）+ WorkspaceHost :195 + Inspector :428-432」；键定义命运二选一落 DECISIONS：(a) 保留 `ExportPanelRequestKey` 定义（壳 face 活依赖，退役域缩为 column/workspace metadata 三键 + 说明行），或 (b) 壳 face 改读 graph/note 直连并删键（含 :94 重指，配与 OMP-M1 同形的壳侧单 hunk 例外）。推荐 (a)（零行为面，单定义保留成本一行注释）。
- **门位**：同 OMP-M1；与 m-omp-5 的门 scoping 同批改。

### OMP-M3 — P2 T1 树遍历 seam 未指定 + T3 re-arm「计数守恒」无可观察 seam（major）

- **severity**：major。按字面执行必触发 P2 自设的「不可达 = 停手上报」或逼出 plan 外测试形态；在 P1 C 档停期间修 plan（P2 开工前）。
- **证据链**：
  - T1（`F0P-02-PLAN.md:87-124`）：树镜像/enabler 谓词测试要求驱动 bridge 树构建，但 `NSMenuBridge.swift` 的 `rootMenu`（:165）、`build*Menu`（:252 起全 private）、`itemEnablers/itemActions`（:175-176 private）全部私有；plan 只写「internal 可达性亲核，不可达停手」，未指定**用哪个 internal 缝走**。实际可行缝存在但须处方化：`install(deps:)`（:183 internal）+ `NSApp.mainMenu` 遍历 + `validateMenuItem`（~:700 internal，enabler 探针）+ `register`（:155-156）。
  - T3-2（`F0P-02-PLAN.md:157-158`）：「re-arm 计数守恒」要求计数观察闭包重武装次数，但 `armObservation` private（:666）且仓内无任何 arm 计数器（唯一计数器 `mainMenuStomps` 与观察无关）。该子测试**无可观察量**，字面不可写；P2 红线禁产线加缝 → 死锁（停手上报是唯一字面出路）。
  - 附加负担（处方须含）：`Deps` 构造需 8 状态对象 + ~40 闭包（:71-150）；`install` 写全局 `NSApp.mainMenu` + `armObservation` 读 `Self.shared` 单例盒（workspace/note 盒）→ 测试隔离须显式 save/restore 形态，否则跨法污染。
- **处方**：T1 action 增 seam 处方段——fresh `NSMenuBridgeController()`（internal init 经 `@testable` 可达）+ stub Deps（闭包全空函数，状态对象真值）+ `install` + `NSApp.mainMenu` 遍历对账 + `validateMenuItem` 逐项 enabler 探针；每法前后 save/restore `NSApp.mainMenu` + 复位 `shared` note 盒（隔离形态落 DECISIONS）。T3-2 改字面为行为形——「同一字段连续变异 → `item.isEnabled` 终态收敛且单 mutation 至多一次可见翻转」（以 `refreshAll` 可观察后果代替计数器）；或 orchestrator 特批一枚 internal arm 计数器（P1 冻结例外，单行 + 文档）。
- **门位**：P1 闭环停期间修入 F0P-02-PLAN.md。

---

## 七、Minor 清单（10 条——随批勘正，不阻塞起跑）

| # | 内容 | 证据（file:line） | 处方 |
|---|---|---|---|
| m-omp-1 | P2 T7 面 11「MCP stdio 27 工具」数字 stale——union 现为 **32**（M7-5 `all32`） | `F0P-02-PLAN.md:252`；源头 `RESEARCH.md:386`；`Tests/LightamerTests/McpFinalSnapshotTests.swift:270` | 改「32 工具（union 全数）」；RESEARCH 行随批勘误注记 |
| m-omp-2 | 「18 读集」数字 stale——落地为 **19**（m1 的 18 + B18 `exportPageActive` 直读，DECISIONS D-F0P-01-2 双轨终形） | `F0P-02-PLAN.md:9,:23,:60,:148,:151`；`NSMenuBridge.swift:669-689` | P2 开工前全局 18→19 + 引 DECISIONS 双轨段；T3「以最终适配器源为基数」保留作兜底 |
| m-omp-3 | 勘误③ paste 行号 `:2001/:2007` 漂移——`9a0b9530` 实测 **:2003/:2008** | `CONTEXT.md:207-209` | 改数字；语义已亲验无误，无行为面 |
| m-omp-4 | P1 T6 SC willTerminate「转发形恰一处」grep 按字面命中 3（shell def + App def + App 注释） | `F0P-01-PLAN.md:394-395`；落地三命中亲测 | 改机检为转发**调用点** `\.applicationWillTerminate\(` 在 `LightamerShell.swift` 恰一处（或 shell 文件内 def 恰一处） |
| m-omp-5 | P3 T1 SC + T2 ① 的零命中门按字面不可满足：`WindowGroup` 在既有注释命中（`EditorMTKView.swift:30`、`SessionCoordinator.swift:24`），`@FocusedBinding`/`focusedSceneValue` 在壳注释 + 活代码（shell :94）命中 | `F0P-03-PLAN.md:109-112,:126-131` | 门 scoping：`LightamerApp.swift` 文件域 + 排除 `//` 注释行；shell :94 按 OMP-M2 终形豁免或同步退役 |
| m-omp-6 | P2 T5 + P1 T7 的 worktree 二进制配方漏供件步——audit 先例要求拷入 `input/` + `Resources/AIModels`，缺供件 = 假性不等价/探针 fixture 缺席 | `F0P-02-PLAN.md:193-199`；`F0P-01-PLAN.md:450-452`；`AR-02-03-ACCEPTANCE.md:52-53` | 两配方增「供件拷入 worktree」一步（与 audit 偏差③配方同形） |
| m-omp-7 | MANIFEST 路径漂移：plan 写 `f0prime-prod/`，执行落 `f0prime-p1/` | `F0P-01-PLAN.md:33`；`F0P-02-PLAN.md:27`；落地 `.work/gui-acceptance/f0prime-p1/MANIFEST.md` | P2 开工前定单卷形态（整批单 MANIFEST 续写 vs per-plan 分卷）并 DECISIONS 注记；P2 T7 引用随之改 |
| m-omp-8 | P2 T6 同值门只钉 TOTAL——跨 bundle skip 迁移可掩盖（audit obs3 已证定向/App skip 方差存在） | `F0P-02-PLAN.md:221-227`；`AR-02-03-ACCEPTANCE.md:50`（向量 5/3/5/4/9/5/6） | SC 增 per-bundle executed/skip 向量逐值钉（IOP 687/5 · Parity 460/3 · Layers 494/5 · Library 738/4 · Sessions 284/9 · Export 385/5 · App 921+P2ΔN/6） |
| m-omp-9 | P2 T1 标题测试「zh bundle 环境断言」无 harness 先例（全仓测试零 `AppleLanguages`  precedent） | `F0P-02-PLAN.md:114-116` | 降格为 en 默认 locale 下「解析 ≠ 键字面量」+ strings 表抽查；zh parity 已由 spike 门①像素证 + xcstrings 零 diff 界定，无需 locale 切换门 |
| m-omp-10 | 红线⑨文件名错误：仓内无 `AppDelegate.swift`，类在 `LightamerApp.swift:168-216` | `CONTEXT.md:269`（+ 三 plan 转引） | 改字面为「AppDelegate 类（`LightamerApp.swift:168-216` 域）字节零改」；机检 = 该域 `git diff` 零 hunk |

---

## 八、判定

- **结构面 PASS**：三 plan 切分（审计修复先于翻转 / 测试+回归 / 退役+回填）、硬序、原子 commit 边界、C 档三停位、SC 机检密度（grep / git stat / 探针数值级）、ΔN 对账式预算，齐备且自洽。P1 已落 T1–T6 是 plan 可执行性的最强实证：翻转 commit 形态、红线遵守（FIX2③/封存/fork 序/改名/xcstrings/L057 全亲测干净）、⌘W 实测闭环，均与 plan 字面一致。
- **3 major 可处方化、不动排列**：OMP-M3 落点 P1→P2 交接停（P2 开工前修）；OMP-M1/M2 落点 P2→P3 交接停（P3 开工前修）。修法均为 plan 文本增量（迁移腿/枚举补点/seam 处方 + 两处壳侧单 hunk 例外），无重排、无重估量级。
- **10 minor 随批勘正**，不阻塞起跑；其中 m-omp-7/m-omp-2 建议在 P2 开工前顺手改（引用路径与测试基数，越早越便宜）。
- **zcode 评审关系声明**：`F0P-PLAN-REVIEW.md` 的 M1–M4/m1–m9 在 fixer `2ba9393e` 中的回写已逐条亲验在位（T6 action 5 缝接线 / T4 action 0 单源先行 / paste 二元规格 / picker 缝 + 零命中门 / 18 读集 / 16 项 / P2 T7 号 / WindowCapture SC 行 / AX 迁移集 / Deps+inspectorState / worktree 二分措辞 / tracked-read 禁形门 / T5 构建配方）；本评审未采信其论证过程，所有结论（§一–§七）来自本评审独立取证——13 条 findings 与其零重合。
