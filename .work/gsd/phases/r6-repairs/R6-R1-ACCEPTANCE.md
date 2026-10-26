# R6-R1 修复批 — 综合验收（2026-10-27）

## 结论

**PASS / 0 B + 0 M + 0 m + 2 obs（新增）**

验收对象 = `80f8814f`（B-1 导入尾事件通道，issue #8）/ `0507135b`（DRT 叶修复，
issue #9）/ `555727e3`（账本），基线 `fb32ef92`。独立复跑全套
**4295/35/0**（3988s，零 MEMFAIL，per-bundle 七值与登记逐位同）；GUI 统计功效
独立复验 **15/15 全绿零败**（round9 = onChange 丢失活体再现 + tail 补偿到达
——修复语义的活体实证）；DRT 面板实机 AX **控件 ALL-PRESENT + 峰值 400/700
双值回读**；反自取消 = 掏空 tail 触发后**机制法①②确定性真红**（5 断言败，
判别力成立）。B/M/m 零新增；obs 两项新增（见 §六）。

## 一、AC 逐条对账

### 1. B-1 双通道幂等语义（file:line 亲核）

| 项 | 核验 | 判 |
|---|---|---|
| 监听面 | `LibraryProjectController.swift:111` `var onImportRunEnded: (@MainActor () -> Void)?` 公开监听面（verifyStrategy/uuidProbe 先例形态） | ✅ |
| 触发时序 | `:488-499`：DEBUG tail 插桩 → `let runEnded = onImportRunEnded; onImportRunEnded = nil; runEnded?()`——**clear-first 单发**，位于 nil 写（:486）之后、AI tail（enqueue :505）之前，同 main-actor turn 同步触发 | ✅ |
| invalidate 序列 | `:484-486`（`coalescer.invalidate()` + `importProgress = nil` + `importProgressCoalescer = nil`）**逐字节未动**——窗口 diff 纯插入（零删除/修改行，`git diff | grep "^-"` 空输出亲证），R6 病灶一修复面零触碰 | ✅ |
| FIX2-01 | `ImportProgressCoalescer` 类体（:790 起，同文件）随整文件纯插入零触碰——完成态发布面零 diff | ✅ |
| 挂臂点 | `WorkspaceHostView.swift` ImportProgressModifier onChange `if importAdapter == nil` 注册分支内挂臂（注册 adapter 时）；闭包 `[weak adapter]` + `guard let adapter, importAdapter != nil else { return }` 幂等闸门 | ✅ |
| 逐行镜像 | tail 闭包体（finish(id:) → `importAdapter = nil` → `guard gridModel != nil` → hoisted-locals Task：reloadFirstPage + inspector.refresh）与 onChange else 臂体**逐行一致**（含 M2-11-02 hoisted locals 注释同款） | ✅ |
| 幂等互锁 | tail 先跑（恒先，同 turn 先于 SwiftUI 事务）→ adapter=nil → else 臂 `else if let adapter` 读 nil 跳过；反向（else 先）→ tail 闭包 guard `importAdapter != nil` 拦截。双通道结构性 no-op 成立 | ✅ |
| else 臂保留价值 | 挂载前在飞 run（无 adapter 无挂臂）onChange 从非 nil 初值的 nil 转换仍可达——diff 未删 else 臂（纯插入亲证） | ✅ |

### 2. 三机制法判别力（读测 + 反自取消实证）

- **法①** `testRunEndEventFiresAfterNilTerminalAndClears`（:190）：fireCount==1
  / 闭包内 `controller.importProgress == nil`（同 turn 排序契约）/ 触发后
  listener 自清——三断言各锚一个失效形态；
- **法②** `testRunEndEventDrivesFinishAndReloadWhenObservationAbsent`（:232）：
  **观察缺席世界**——单测进程无 SwiftUI 图 = 失败轮 onChange 丢失形态的确定性
  同构；真 runImport + 生产挂臂镜像（registry + adapter 注册 + 终态 apply）+
  无 SwiftUI 消费者 → `reloadCount==1` + `registry.handles.isEmpty` 必达断言；
- **法③** `testRunEndEventUnarmedTailIsNoOp`（:271）：无挂臂尾零动作（nil 终态
  照常发布），锚防误触面。

三法读毕判别面成立；判别力由反自取消（§四）实证。

### 3. DRT 修复 diff + 死锁叙事自洽

- diff：else 臂 `EmptyView()` → `Color.clear.frame(height: 0).accessibilityHidden(true)`
  （真零尺寸叶）；onAppear 块仅重排（无语义变化）；accessibilityIdentifier
  `editor.stack.drt.panel` 未动；
- 死锁叙事自洽：model nil → EmptyView（无渲染内容）→ appear 事件无附着体 →
  onAppear 零触发 → model 永不构建（鸡生蛋）；Color.clear 是参与渲染的真视图
  = appear 事件获得内容钩子；Film 同款 lazy-build 存活因常驻 header 在 if-let
  之外（`DrtPanelView.swift:46` 结构亲读吻合，`FilmPanelView` 对照成立）；
  AR-01 m11 意图（祖先 body 不每评估抛 model）经 Color.clear 保持。

## 二、diff 审

- **窗口恰 6 文件**（`fb32ef92..555727e3`）：2 账本 md（.work 内部免关联）+
  `LibraryProjectController.swift`（+33 纯插）+ `WorkspaceHostView.swift`
  （+46 纯插）+ `ImportCompletionRegressionTests.swift`（+112 纯插）+
  `DrtPanelView.swift`（+19/-4）。产品面恰 2 处 fix 面，Core/IOP 零触碰，
  WorkspaceModel 未触（无载体族例外申报需求）✅
- **封存面 17 件机检**：DrtRecord / TerminalTailPolicy / DrtTailAssembly /
  PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract /
  ExportFormatSpec / ImageIOEncoders / WebPEncoder / NodeGraphCommand /
  LightamerSidecar / HistoryStack / HistoryHash / PipelineDocument / V50Order /
  NodeOwnershipCatalog——窗口 name-only 逐名 grep **零命中** ✅
- **invalidate / FIX2-01 零 diff 亲证**：整文件 diff 零删除/修改行（§一表格）✅

## 三、GUI 统计功效独立复验（15 轮）

- **binary 归属三重证据**：strings 含 `tail nil written`（修复特征）×1 +
  `import-obs` ×3；全部涉改源文件 mtime（03:56/03:56/04:12/03:59）≤ binary
  mtime（04:13）；工作区对 HEAD `git diff` 空（逐字节一致）。DerivedData Debug
  构建即 `555727e3` 修复构建（构建产物交接纪律，未重建）。
- **15 轮 fresh 导入计时**（`-la_editor_probe /tmp/r6r1-fixture/Src` 16 文件，
  fresh 进程 + fresh UUID 项目，独立轮脚本 `/tmp/r6r1-acc/round15.sh`）：

| 轮 | 判定 | 耗时 | 轮 | 判定 | 耗时 |
|---|---|---|---|---|---|
| 1 | ROWS-ARRIVED | 2.1s | 9 | **ROWS-ARRIVED** | 1.1s |
| 2-8 | ROWS-ARRIVED ×7 | 1.0-1.1s | 10-15 | ROWS-ARRIVED ×6 | 1.1s |

  **15/15 全绿、0 败、0 超时**（omp 判据 0/15 满足；未修复基线 28%/轮下
  15 连绿概率 ≈1.7%）。
- **round9 = 丢失形态活体补偿实证**：trace 序列 `fire#2 -> completed →
  tail nil written →（无 fire#3）→ rows 到达`——onChange 对 (.completed→nil)
  的丢失**真实发生**（旧代码该轮必败 zero-row），tail 直通道补偿后行到达。
  其余 14 轮 fire#3 正常消费（`fire#3 -> nil adapter=nil` = tail 先 nil 掉
  adapter、else 臂幂等跳过——DECISIONS §二「双通道序贯幂等」形态）。
  本环境丢失率 1/15（omp harness 28% 同量级下限，非零即足以实证补偿语义）。

## 四、DRT 面板实机 AX（关键面独立复验）

- fresh stay 实例（PID 25336）+ rail 位置聚类（y∈[480,510] 恰 7 钮，
  x 排序）压第 4 钮（displayTransform）；
- **控件断言 ALL-PRESENT**：方法 radio 组（ACES 2.0 / OpenDRT）+ 编码空间
  PopUp + 编码 EOTF PopUp + 限色空间 PopUp + 面板内 AXSlider 恰 1（doc-order
  = EOTF popup 后首个，`/tmp/r6r1-acc/drt-full-v3.swift`）；
- **峰值滑杆写通道双值复验**：set 400 → 回读 400.0；set 700 → 回读 700.0
  （非巧合；R6-R1 配方 100→400 的独立加严）；
- 方法学注记（obs-4）：控件 accessibilityIdentifier（drt.method.picker 等）
  被 Group 容器 `editor.stack.drt.panel` 的 AX 传播覆盖，子控件 id 不达 AX
  树——走查须按 role+description 断言（本验收采用）；tab rail 索引漂移
  （executor obs-2）位置聚类法免疫，本验收 y 窗收紧后恰 7 钮复证。

## 五、反自取消（判别力实证）

- **实施形态偏离申报说明**：任务书预想 /tmp worktree；实测 `test-direct.sh`
  的 DerivedData 定位按 mtime 撿 `~/Library/.../Lightamer-*` 容器——worktree
  独立 DD 不被识别。改用**主仓 sed 掏空**（触发三行 `runEnded?()` 族替换为
  no-op，声明/挂臂保留 = 「tail 事件通道失效」世界）+ 增量 build-for-testing
  + 定向跑 + `git checkout` 完整还原，语义等效且省构建；
- **真红确认**（`--bundle Library 'ImportCompletionRegressionTests'`）：
  `Executed 6 tests, with 5 failures`——法①三断言（:210/:212/:216）+
  **法②双断言**（:258 `reloadCount ("0") is not equal to ("1")` + :263
  `handles.isEmpty` 假）全红；法③（UnarmedTail）仍绿（不依赖 fire，语义正确）；
  既有 Contract 1/2/3 三法仍绿（掏空不影响 R6 面）；
- **还原亲证**：`ANTICANCEL` 零命中 + `git status` 零修改 + 还原构建
  exit=0（服务全套起跑）。

## 六、全套复跑

纪律 = guard PASS（heavy=0 free=53%）+ ps 内联清零（0 实例）+
`machine-guard.sh --monitor 21600` nohup 伴跑 + `test-direct.sh --all`
nohup disown。

**全套终值 = 4295/35/0（3988s，零 MEMFAIL）**——与 SUMMARY 登记逐位同：

| bundle | 值 | peakRSS | 登记值 |
|---|---|---|---|
| IOP | 788/1/0 | 5829MB | 788/1/0 ✅ |
| IOPParity | 529/11/0 | 5641MB | 529/11/0 ✅ |
| Layers | 507/5/0 | 1063MB | 507/5/0 ✅ |
| Library | 782/4/0 | 745MB | 782/4/0 ✅ |
| Sessions | 285/4/0 | 1209MB | 285/4/0 ✅ |
| Export | 385/4/0 | 4915MB | 385/4/0 ✅ |
| App | 1019/6/0 | 2832MB | 1019/6/0 ✅ |

skip 35 恒定；`DrtPersistenceTests` teardown SIGTRAP flake **未复现**（全套绿，
executor obs-1 维持观察登记）。

## 七、B/M/m/obs 逐条

**B = 0，M = 0，m = 0**（两项修复的 AC 全数独立复核通过）。

新增 obs：

- **obs-4（DRT 峰值滑杆初值 400 ≠ 理论默认 100）**：fresh stay 实例、任何
  set 之前 AXValue = 400.0；理论读序（live → history effectiveDrtRecord →
  carrier → `DrtRecord()` 默认 peakLuminance=100，`DrtRecord.swift:378` +
  `WorkspaceModel.swift:266` carrier 缺省同落 DrtRecord()）pristine 全链应
  100。写通道已证活（400/700 双值回读），初值语义待查（读序分支 / AXSlider
  value 映射 / D-H1 live 态）。**非本批引入**——else 臂 Color.clear 不触
  record 读序（M2-6 交付面）；登记待 M2-6 面专项或下轮 omp T3-DRT 链顺路。
- **obs-5（accessibilityIdentifier 容器传播覆盖子控件 id）**：DRT 面板内
  drt.method.picker / drt.peak.slider 等子 id 不达 AX 树（全被
  editor.stack.drt.panel 覆盖），控件级 id 断言在该挂载形态不可用——GUI
  走查按 role+desc 断言的惯例注记（影响所有同形态面板的自动化断言面）。

沿袭 executor obs：obs-1（teardown SIGTRAP flake，本轮全套未复现，维持）/
obs-2（tab 轨索引漂移，位置聚类免疫——本轮复证 y 窗收紧恰 7 钮）/ obs-3
（图库网格 cell 无 AX 物化，T3-DRT 重进腿仍阻，移交下轮）。

## 八、卫生

- 验收 /tmp 域 = `/tmp/r6r1-acc/`（轮脚本 / 15 轮日志 / DRT AX 脚本 / 全套
  log / monitor log，即弃留存）；executor 留存域 `/tmp/r6r1-{fixture,runs,drt}`
  复用未动；
- GUI 实例逐一 kill 清零复核（ps 0）；monitor 全套后 pkill 停止复核 0；
  `library.recentProjects` 探针污染复查 = 键不存在（无污染）；
- 反自取消掏空已还原（零 diff 亲证）；无 worktree 残留；DerivedData 单容器
  （dgzs…）增量构建三次（掏空/还原/全套服务），无独立 DD；
- px 代理全程未开（本验收无 gh/push 动作）；commit 免关联不 push。

## 九、commit

- 验收 commit：`docs(r6r1): acceptance report — full suite 4295/35/0, 15/15 GUI, DRT AX pass`（本文件，单 commit 免关联不 push）。
