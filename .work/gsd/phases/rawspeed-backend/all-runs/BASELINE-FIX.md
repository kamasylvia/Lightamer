# Baseline Fix — frozen inventory + SpektraFilmModule.process crash

**结论头：PASS / 1 open**（对象一已修并验证；对象二未能确立根因，按纪律不改产品代码，转专案 issue 草案）

- 工作树 HEAD：`a2f6a6078b2850ad72649969556da5151caafc73`（2026-11-25 10:22，`main`）；开工亲核无偏差。
- 输入：`.work/gsd/phases/rawspeed-backend/all-runs/BASELINE.md`（FAIL / 1 failure + 1 偶发崩溃）。
- 时间窗：2026-11-25 10:25 → 11:20（墙钟 ≈55min；总预算 2.5h 内）。
- 机器：`Scripts/machine-guard.sh` 的 G1 在本 lane 起点误报（命中的是**本 lane 自己的 omp 命令行文本**——prompt 里含 `test-direct.sh` 字样；`ps` 复核 heavy=0）。G2 可用内存 76% / G4 Data 卷 36GB → 实际放行。`--monitor` 伴跑。

---

## 0 结论

| 项 | 状态 |
|---|---|
| 对象一 `FilmPanelSpectralUITests.testPanelControlInventoryMatchesTheFrozenSnapshot` | **已修**（测试侧，提交见 §5）：convert 臂的四枚 AX id 是有意功能（`a88eb770` + PLAN T4' item 4），冻结清单补入 |
| 对象二 `SpektraFilmModule.process` 偶发 `SIGSEGV` | **open**：未确立根因，未改产品代码；证据/嫌疑/下一步见 §4。App 域本轮 1135/6/0 干净（偶然性未消） |

---

## 1 对象一：冻结清单

### 判定

**有意功能 → 清单没跟上**，只改测试。

- 引入提交：`a88eb770`（2026-11-04，`feat(sm): add dual-track gate + convert row + tags resolver`）——spektra-module T4' 的 convert 臂。
- 依据：`.work/gsd/phases/spektra-module/PLAN.md` §T4' item 4 明文预算「AX id 前缀 `film.convert.*`」，且 convert 臂复用同一 migration row/sheet 壳（键族 `panel_film_convert_*` ≤4，cancel 复用 `alert_cancel`）。
- 控件**数量**未变（壳共享），新增的只是按 action 分叉的标识符（`isConvert ? "film.convert.*" : "film.migrate.*"`，`FilmPanelView.swift:180/248/267/272`）。

### 处理

`Tests/LightamerTests/FilmPanelSpectralUITests.swift`：`frozenControlInventory` 增 4 项 + 注释块记来历（`a88eb770` / PLAN T4' item 4 / 壳共享不变数量）。产品代码零改。

### 同类清单扫查

- `grep -rn "inventoryFromSource\|frozenControlInventory" Tests/`：只有本文件消费，无第二处可漂移的冻结清单。
- 全 App 域 `*Inventory*` / `*FrozenSnapshot*` 类测试只有本类；同批（`a88eb770`）新增的其它控件 id 不在任何清单消费面。

---

## 2 对象二：SpektraFilmModule.process 偶发崩溃

### 2.1 代码预判（先读码，未复现前写下）

`SpektraFilmModule.process(record:…)` 的共享可变面盘点：

| 面 | 形态 | 判定 |
|---|---|---|
| `committed: Params?` | module 实例存储（`commitParams` 写 / `process` 读） | **非嫌疑**：layer 链的 box 每次 `LayerCompositeDriver.composite` 经 `registry.materializeBoxes` 全新铸造（`ModuleRegistry.makeBox` = `factories[opName]?(id)` → 工厂每次 `SpektraFilmModule()`），`apply→setParams→commitParams` 与 `process` 同任务先后序，无跨任务写者 |
| `FilmMaterialSeam.resolver` | `nonisolated(unsafe) static var`，**2 字宽闭包**（fn+ctx） | **嫌疑 A**：`PipeCoordinator.attachFilmStore`（MainActor，每开项目/每次测试 setUp）赋值 vs 渲染腿 cooperative 线程读取；无锁，读侧 load→retain 与写侧 release 可交错（与 M5-1 `FilmMethodBox.runContext` 同族） |
| `FilmStatsSeam.histogram` | 同上（2 字宽闭包） | 同族嫌疑（本崩溃栈未走到，`process` 早段就崩了） |
| `SpektraFilmModule.liveSurfaceCount` | `nonisolated(unsafe) static var: Int`（`+=`/`-=`） | 真实 data race（UB），但只丢计数、不可能产出坏指针 → **非本次崩溃机理** |
| `layer.chain`（`AdjustmentLayer` 是 `final class`） | `EditorState.addModuleToLayer` 原地 `append`+`sort`；`LayerStack` 拷贝只复制类引用，渲染腿读同一对象 | **嫌疑 B**：`LayerCompositeDriver.composite → materializeBoxes(for: adjustment.chain)` 与 MainActor 原地改数组并发 = torn `Array<ModuleInstance>`（元素含 `Data`/`String`） |
| GPU 缓冲生命周期 | `metal.makeCommandBuffer()` 默认 `retainedReferences=true`；模块自持 `linear` 面 `.shared` | 非嫌疑（命令缓冲持有资源至完成；L014 的读回面在 `FilmStatsSeam` 内） |

### 2.2 崩溃报告重读（新增证据）

`Lightamer-2026-11-25-094309.ips` 关键事实（本 lane 复核）：

- faulting thread `104379773`，queue = `com.apple.root.user-initiated-qos.cooperative`。
- 栈：`_swift_release_dealloc+0x30` ← `RefCounts::doDecrementSlow` ← `SpektraFilmModule.process(record:…)`（`LightamerIOP` imageOffset `0x2d491c`，反汇编落点 = 对 `[async-frame]` 槽位调 `swift_bridgeObjectRelease`）← `process(input:…)` ← `ModuleBox.processErased` ← `PixelPipe.runSub` ← `LayerCompositeDriver.composite`。
- **寄存器证据（决定性）**：`x0 = 0x76d99e0200`（与同帧其它对象同段的**合法堆指针**），`x16 = 0x0068b4a740225e45`（= fault address + 0x10，即**该对象的 metadata/isa 字**）。→ 不是"野指针被 release"，而是**一个活对象的头部 8 字节被写成垃圾**（0x0068b4a740225e45）。这是 **heap 写坏**（受害者），不是单纯 over-release。
- 同刻并发面（25 线程全量扫描）：**6 帧 `SpektraFilmModule.process`**（1 崩溃 + 3 阻塞在 `SpectralPrintBake.tables` 的 buildLock + 2 在建 `SpectralGPUPayloads`）、8 帧 `LayerCompositeDriver.composite`、2 条 film tail 腿（`runFilmLeg`）+ 1 条 `SpectralBuildEngine.build`、4 线程在 `SpectralPrintBake.tables`；主线程在 `loadGradient → rematerializeInstances → ToneCurveModule.commitParams`。即：**6 条并发的 spektra 渲染腿 + 一次主线程 box 变更**，seconds 级 bake 把重叠窗口从毫秒放大到秒级。

### 2.3 复现尝试

1. `Scripts/test-direct.sh` **无消毒器入口**（头注释/参数解析只有 `--all/--bundle/<过滤>`，全篇无 sanitizer 旋钮；实测亦无 env 钩子）。→ 按纪律走"循环定向跑"。
2. **定向循环**：`--bundle App FilmPanelTests`（崩溃发生的那一类）带 `MallocScribble=1`：
   - 首轮即撞上该类的**冷启动系数拟合**（`SpectralTcFit.fitCoefficientTable` 经 `dispatch_apply`，8 核满载 ~100s/进程）——每轮进程重启都要重付，且 `MallocGuardEdges=1` 会把该路径拖到分钟级（已弃用 GuardEdges）。
   - 计 2 轮（含一次提前终止）：**未出现崩溃**；时间预算内无法用整类循环堆到足够轮次。
3. **嫌疑 A 的机械 A/B（独立探针，不动仓库）**：`swiftc -Onone` 直编 `FilmRecord.swift + FilmProfile.swift + SpectralNeutralSolve.swift + FilmMaterialSeam.swift + 探针`（框架 import 路线被 `libwebp` 模块闭包挡死，M2-7 同款；改走源级直编）。探针 = 1 写者每轮**新建**闭包盒赋给 `FilmMaterialSeam.resolver`、8 读者每轮 `let r = resolver; r(record)`；`MallocScribble=1` 下跑 20s：
   - **写 82,158,907 次换手 / 读 259,9xx,xxx 次调用，零崩溃**（`NO-CRASH`）。
   - 结论：嫌疑 A 在 arm64 上极难触发（16B 载入 + 释放窗口都很窄），**不足以解释**本次崩溃；但代码层面的无锁 2 字宽共享槽仍是真实竞态（同族先例已致过 over-release），列 P2 待修，不作为本次根因结论。

### 2.4 根因结论

**未确立**。已排除：`committed` 撕裂（layer 链 box 每 run 全新）、GPU 资源早释（命令缓冲 retainedReferences 默认持有）、单纯 over-release（寄存器显示对象头被写坏）。

剩余最强候选 = **嫌疑 B**（活 `AdjustmentLayer.chain` 在渲染窗口内被 MainActor 原地改写 → torn `Array<ModuleInstance>` → 元素里的 `Data`/`String` 头被半写 → 写坏相邻对象头部；崩溃位置只是受害者）。该面**结构性存在且可读码证明**，但本 lane 未能做出确定性复现（需要在渲染窗口内精确命中 append/sort，且要绕过 XCTest 的单进程串行测试编排）。

按任务纪律「根因不清楚或修法会动大面，不要硬修」：**产品代码零改动**，转 §4 专案 issue 草案。

---

## 3 App 域终值

命令与结果（构建 = `xcodebuild build-for-testing`（10:51:19→10:55:05，`** TEST BUILD SUCCEEDED **`，零 error）；构建后宿主/测试 bundle mtime = 10:54，`test-direct.sh` 亲取该产物）：

| 轮 | 命令 | 结果 | 峰值 RSS | 秒 |
|---|---|---|---|---|
| 定向（对象一） | `Scripts/test-direct.sh --bundle App FilmPanelSpectralUITests` | **7/0/0** `verdict=ok`（`testPanelControlInventoryMatchesTheFrozenSnapshot` 绿） | 305MB | 270 |
| 全 App 域 | `Scripts/test-direct.sh --bundle App` | **1135/6/0** `verdict=ok`（基线 1135/6/**1**） | **1999MB** | 680 |

- 与基线逐项对账：executed/skipped 逐位相同（1135/6），failed 1→0（唯一差异即对象一）；峰值 1999MB（基线 2831MB），无 MEMFAIL、无 `terminated abnormally`/`Restarting after unexpected exit`、无 RSS-KILL。
- 定向轮 270s 中约 220s 是**冷启动系数拟合**（`SpectralTcFit.fitCoefficientTable`，dispatch_apply 满核）——该类在整 App 轮里由更早的 film 测试类预热，故整轮 680s 反而快于基线 757s。
- 崩溃面：本轮**未复现**（对象二本来即偶发；一次干净轮不构成"已修"证据，见 §2.4/§4）。

---

## 4 未解决项与建议（含专案 issue 草稿）

（见下）

### 4.1 专案 issue 草案（可直接粘贴；英文，符合本仓 issues 语言约定）

**Title:** `fix(pipe): SpektraFilmModule.process sporadically dies on a clobbered object header under overlapping film legs`

```markdown
## Goal
- Eliminate the sporadic host crash first observed in the 2026-11-25 full-suite rerun
  (`Scripts/test-direct.sh --bundle App`, ~446 s in, exit 139).

## Status
- 2026-11-25: crash observed ONCE (App bundle rerun). The first full-suite run (4618 tests)
  and the 2026-11-03 reference run never crashed. Not reproduced since.

## Evidence (fixed facts)
- `.ips`: `.work/gsd/phases/rawspeed-backend/all-runs/Lightamer-2026-11-25-094309.ips`.
  EXC_BAD_ACCESS/SIGSEGV/KERN_INVALID_ADDRESS, faulting thread =
  `com.apple.root.user-initiated-qos.cooperative`.
- Stack: `_swift_release_dealloc+0x30` ← `RefCounts::doDecrementSlow` ←
  `SpektraFilmModule.process(record:input:output:piece:metal:)` ← `process(input:…)` ←
  `ModuleBox.processErased` ← `PixelPipe.runSub` ← `LayerCompositeDriver.composite` ←
  `RenderPipeline.processComposite` ← `PipeCoordinator.renderCurrentChainInner`.
  The release site is a `swift_bridgeObjectRelease` over an async-frame slot (LightamerIOP
  imageOffset 0x2d491c).
- Registers at fault: `x0 = 0x76d99e0200` (a live-looking heap object in the same arena as the
  frame's other objects), `x16 = 0x0068b4a740225e45` (= the fault address + 0x10). The object's
  **metadata/isa word was overwritten with garbage** → this is a *heap write corruption* whose
  victim was being released, NOT a plain over-release of a stale pointer.
- Concurrency census at the crash: 3 layer-composite legs (one crashing, two blocked on
  `SpectralPrintBake.tables`'s buildLock) + 2 film-tail legs (`runFilmLeg →
  assembleSpectralFilmLeg`, two threads inside `SpectralGPUPayloads.init`) + the main thread in
  `loadGradient → rematerializeInstances → ToneCurveModule.commitParams`. The seconds-scale
  spectral bake (`SpectralPrintBake.tables`) holds overlapping coordinator renders open for
  seconds instead of milliseconds.

## Repro attempts (all negative)
- `Scripts/test-direct.sh` has NO sanitizer entry (only `--all/--bundle/<filter>`); no env hook.
- Filtered loop `--bundle App FilmPanelTests` with `MallocScribble=1`: 2 rounds, no crash. Each
  process pays the cold `SpectralTcFit.fitCoefficientTable` (~100 s of 8-core CPU), so rounds
  are 2-3 min; `MallocGuardEdges=1` pushes that to minutes and was dropped.
- Standalone source-level probe of the seam race (`FilmMaterialSeam.resolver` swap-vs-call,
  1 writer installing a fresh closure box per iteration + 8 readers): 82,158,907 swaps /
  259.9M calls in 20 s under `MallocScribble=1` → **NO-CRASH**. (The Swift-framework import route
  is blocked by the `libwebp` module closure — M2-7 precedent; the probe compiled the Core
  sources directly.)

## Suspects (ranked)
1. **Live `AdjustmentLayer` mutated while renders read it.** `AdjustmentLayer` is a
   `final class`; `EditorState.addModuleToLayer` mutates `layer.chain` in place
   (`append` + `sort`), and `LayerStack` copies only the class *references*. Any in-flight
   `LayerCompositeDriver.composite` reads the same `adjustment.chain`
   (`HistoryStack.effectiveChain` + `ModuleRegistry.materializeBoxes`). A torn
   `Array<ModuleInstance>` (elements carry `Data`/`String`) is a plausible source of an 8-byte
   write landing on an adjacent object's header. This is the only *long-window* shared mutable
   state on the layer path.
2. **`FilmMaterialSeam.resolver` / `FilmStatsSeam.histogram`** — `nonisolated(unsafe) static var`
   holding 2-word closures, written by `PipeCoordinator.attachFilmStore` (project open) and the
   QL appex while render legs read them. Same family as the M5-1 `FilmMethodBox.runContext`
   over-release (fixed by removing the static slot). The probe above did not reproduce it, so it
   is ranked below (1) — but it is still an unsynchronized slot read by concurrent legs.
3. **`SpektraFilmModule.liveSurfaceCount`** — `nonisolated(unsafe) static var: Int`, `+=`/`-=`
   from concurrent legs. Real data race/UB, but cannot produce a bad pointer.

## Proposed next steps
- [ ] Make renders snapshot-isolated from MainActor layer mutations (e.g. deep-copy the
      `LayerStack`/`AdjustmentLayer.chain` at render entry, or make the layer model a value type).
      Acceptance: golden suites byte-identical; `--bundle Layers` + `--bundle App` green.
- [ ] Snapshot-lock the two seam closures (`NSLock` + getter that returns a retained copy) and
      the census counter.
- [ ] Add a TSan lane: a `build-for-testing -enableThreadSanitizer YES` recipe outside
      `test-direct.sh`, or an opt-in `LA_SANITIZER=thread` env that re-execs a sanitized host.
- [ ] For a repro: `MallocScribble=1` + `MallocStackLogging=1` under a filtered
      film-heavy suite, and keep the `.ips` + `/tmp/la-direct-tests-App.log`.

## References
- BASELINE: `.work/gsd/phases/rawspeed-backend/all-runs/BASELINE.md`
- Fix-lane report: `.work/gsd/phases/rawspeed-backend/all-runs/BASELINE-FIX.md`
- Prior same-family fix: `.work/gsd/phases/m5-1-track/FILM-LEG-FIX.md` (§1 root cause: process-wide
  `FilmMethodBox.runContext` slot, store-release vs load-retain across overlapping legs).
```

### 4.2 其它未决/建议

- `Scripts/test-direct.sh` **没有消毒器入口**：建议加 `LA_SANITIZER=thread|address` 旋钮（重新 exec 一个 sanitized 宿主）或独立的 `Scripts/test-tsan.sh`；本 lane 无此能力，崩溃只能靠循环。
- App 域定向跑的**冷启动系数拟合**（`SpectralTcFit.fitCoefficientTable`，dispatch_apply 满核 ~100 s）让任何"单位类循环"式复现都变成分钟级/轮——后续复现工作建议直接跑整 App bundle 或先预热 memo。
- 本次崩溃的受害者是 `SpektraFilmModule.process` 帧里被 release 的对象，但**寄存器证据表明是他人写坏了它的头**——排查方向应是"谁在并发写堆"，而不是"这个 String 为什么野"。

---

## 5 commit 清单与改动范围声明

### 提交 1（对象一，测试侧）

`test(film-panel): admit the convert arm's identifiers to the frozen inventory`（`refs #21`）— **`a1ca23899f1b2861f731d620b23d585f5f30dfa7`**

逐 hunk（唯一改动文件 = `Tests/LightamerTests/FilmPanelSpectralUITests.swift`，+11/−0）：

| hunk | 内容 |
|---|---|
| A（doc comment） | `frozenControlInventory` 上方追加 spektra-module T4'（`a88eb770`）来历：convert 臂复用同一 row/sheet 壳、`film.convert.*` 按 action 分叉、PLAN §T4' item 4 预算该前缀、控件数量不变 |
| B（清单体） | `film.convert.button` / `.sheet` / `.cancel` / `.confirm` 四行（紧跟 `film.migrate.*` 块） |

### 提交 2（对象二）

**无提交**。根因未确立（§2.4），按纪律「不要硬修」：产品代码（`LightamerIOP/Sources/SpektraFilm/**`、`LightamerCore/Sources/Pipe/Film/**`、`App/Sources/.../PipeCoordinator.swift`、`EditorState*`）逐字节未动。

封存面核对（两处来源，均逐条比对）：
- AGENTS「封存面清单」：`SpektraFilmModule` 不在列。
- spektra-module `SUMMARY.md` §封存面终声明：`SpektraFilmModule` 亦不在列；但**嫌疑面所在文件在列**——`FilmStatsSeam` 的宿主 `FilmTailPolicy.swift`、以及 `FilmPrintBake.swift`、`FilmMaterialStore.swift`、`LayerCompositeDriver.swift` 均为「零 diff」封存件（`LayerStack` 仅 mergeDown ⑯ 例外）。→ 若后续修嫌疑 1/2，**必须按逐 hunk 申报制走封存例外**，不能顺手改。本 lane 对上述文件全部零改动（`git diff` 仅测试文件一处）。

### 不提交的产物（orchestrator 面，按本仓惯例留本地）

`.work/gsd/phases/rawspeed-backend/all-runs/**`（BASELINE-FIX.md、repro/ 下的 build/app 日志与复现材料）、`.work/gsd/phases/rawspeed-backend/omp-baseline-fix-summary.md`。

### 其它声明

- 零 push；issue 只读（#21 未评论）。
- 未动用户可见文案 → 未跑 zh-audit（无新键/无改动）。
- 未新增测试文件 → 未触 `Project.swift` 与 BUNDLE-MAP，无需 `tuist generate`。
- 机器：构建 + App 域全程 `machine-guard.sh --monitor 7200` 伴跑；无残留宿主（收尾 `ps` 复核）；只杀过本 lane 自起的宿主/循环。
