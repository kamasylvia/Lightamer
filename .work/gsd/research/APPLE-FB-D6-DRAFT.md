# Apple Feedback 报告稿 — D-6（SwiftUI 菜单/焦点更新自持环，macOS 27）

> **性质**：报告稿（agent 备稿；**提交动作用户手动执行**——Nitro LUT 先例）。提交后回填 FB 案号至 REQUIREMENTS SHELL-04 与 GOAL-STATE。
> **定性正本** = `phases/fix2-defects/FIX2-01-DECISIONS.md` D-FIX2-1 + `phases/fix2-defects/FIX2-VALIDATION.md` §挂账①（双路独立验收同判，2026-10-16）。
> **终局定性补强（2026-10-16 M7-1 定罪批，正本 = `phases/m7-1-shell/M7-1-VALIDATION.md` + `M7-1-HALT-REVIEW.md`——内部分卷，Apple 侧只呈现可复现配方不呈现内部排查史）**：①遮挡门控确定性复现（遮 0% ↔ 置前 ≤1s 复燃无需点击，两形三面）②树形证伪（摘 `.inspector`/双 `safeAreaInset` 形三独立复现均活 ~30-36%——饿死型判据不入稿）③跨日稳定编辑器 spin 配方（78.7-100% 三路在案）。本稿 Steps/Notes 已按终局行为模型勘定。
> **配套证据** = `.work/gui-acceptance/v2m/fix2-probe/`（local-only，勿入 git）：环签名 sample `t1-menu-loop-sample.txt`、编辑器面 sample `acc2-d6-editor-sample.txt` / `acc2-d6-editor-sample2.txt`、transcript 族 `b1-/b2-/c1-/c2-*transcript.log`、截图族（`acc2-d6-editor-broken.png` / `acc2-d6-click-after-occlude.png` 等）。提交时按 Feedback Assistant 附件上限择要附（2 个 sample txt + 1 张截图足矣）。
> **需求族** = REQUIREMENTS SHELL-04（M7 站 charter 2026-10-16）。上游监测义务（macOS 27.1 release notes）随 SHELL-04 持续跟踪。

---

## Feedback Assistant 表单（建议值，提交时核对）

| 字段 | 值 |
|---|---|
| Area | SwiftUI（主诉：menu bar / property-graph update loop）；次诉 AppKit（NSMenu updateImmediately 路径） |
| Title | SwiftUI menu/focus property-graph update loop does not converge in specific view-tree shapes on macOS 27 — sustained ~50-100% CPU spin while the UI stays functional |
| Type | Incorrect/Unexpected Behavior（性能/能耗；非 crash 非 hang——UI 可交互） |
| OS Version | macOS 27.0.1 (Build 26A434) |
| Hardware | Apple Silicon（提交时补本机型号；两台 Apple Silicon 均可复现则双机注记） |
| App | Lightamer（开发中 SwiftUI + Metal 照片编辑器；标准 Menu + `.commands` API，无 MenuBarExtra） |
| Does the issue also occur in the latest beta? | 提交时按当时最新 beta 实测后勾选（27.1 beta 待验——SHELL-04 监测项） |

---

## Summary（表单正文，可直接粘贴）

A SwiftUI (macOS 27) app whose scene hosts a Menu with `.commands` can enter a
**self-sustaining property-graph update loop** under specific view-tree shapes
(a "heavy" tree: a three-segment content row + `.inspector` split host +
`safeAreaInset` banners). Once entered, the loop re-evaluates the app/scene
body graph at roughly the display refresh rate (display-cycle-locked,
~60-120 Hz per display refresh) indefinitely while **no app-side state ever
changes** — `_printChanges()` reports only `@self` across ~14k re-evaluations
in a 2-minute window (a follow-up measurement on a 120 Hz ProMotion display
counted ~21k re-evaluations in ~3 minutes ≈ 119 passes/s — one pass per
display cycle; the rate follows the display, it is not a fixed 60 Hz). The
UI remains functional (no hang, no crash); the cost is a permanent ~34-51%
CPU burn (one full core; up to 98-100% on the editor face after user
interaction) plus battery drain.

Thread samples show the loop lives entirely in framework code:

```
flushObservers → beginTransaction → flushTransactions → graphDidChange
→ appGraphDidChange → makeMainMenu → updateMainMenu(updateImmediately:)
→ invalidateProperties → requestUpdate → GraphHost.updatePreferences
→ UpdateStack::update → ForEachChild → View.keyboardShortcut (per-menu-item
re-mount, with hot swift_getTypeByMangledName metadata frames)
→ (loop closes back into graphDidChange)
```

The focus-store side participates each pass:
`FocusBridge/ToolbarBridge.preferencesDidChange →
FocusedValueModifier.Transform.updateValue → PropertyList.prependValue`
— the focus store is structurally rewritten every pass with **no value
dedup**, which itself constitutes a change that feeds the next invalidation.

## Steps to Reproduce

1. Build a SwiftUI app (macOS 27 SDK) whose WindowGroup content is a
   three-segment horizontal editor layout (e.g. a side filmstrip `List`,
   a center viewport, a right pane) wrapped so the scene also carries:
   - an `.inspector(isPresented:)` split host attached at the app root, and
   - two `safeAreaInset(edge:)` banner layers at the bottom of the content.
2. Attach a standard `Commands` menu with per-command
   `.keyboardShortcut(...)` modifiers (our menu has ~13 top-level commands,
   many items rebuilt from app state each render).
3. Launch, open a project document, enter the editor face.
4. Let the app idle with the editor visible. Observe CPU ≈ 34-51% of one
   core while the user performs no interaction (98-100% on the editor
   face after interaction).
5. The loop is robust to app-side tree surgery: removing the `.inspector`
   host, removing the `safeAreaInset` banners, or removing focus-value
   write points does **not** stop it — the tree-removal variants were
   re-tested three independent times on the current build and each still
   sustains ≈ 30-36% CPU. Ignition requires the heavy tree shape above.
6. Occlusion gate (deterministic, the only clean on/off switch we found):
   minimize or fully occlude the window (⌘H also works) → spin stops and
   CPU drops to exactly 0 (spindump shows zero loop frames). Bring the
   window back to the front (activate it) — the loop re-ignites within
   ≤ 1 s with **no click needed**, verified across two tree shapes ×
   three faces (idle gallery ~30%, editor face 80-100%).
7. Cross-day stability: the editor-face spin reproduces at 78.7-100%
   across three independent sessions on different days with a scripted
   recipe — bare direct launch, System Events `frontmost` gate before
   every reading, 1 s-step `ps %cpu` sampling, and `sample <pid> 6`
   spindumps. A probed build (`Self._printChanges` on
   ContentView/WorkspaceHostView + three-stage `sample` captures) plus
   the repro script can be provided on request.

## Expected Results

Menu-bar/property-graph invalidation settles: after the initial render pass
the graph reaches a fixed point; CPU returns to ~0% while idle. Focus-store
rewrites should be value-deduped so an unchanged prepend is not itself an
invalidation.

## Actual Results

`makeMainMenu → updateMainMenu(updateImmediately:) → invalidateProperties →
requestUpdate → GraphHost.updatePreferences → graphDidChange` never converges
for the tree shapes above: each menu update ends by changing the graph, which
re-triggers menu rebuild. Display-cycle-locked (~60-120 Hz per display
refresh) scene-body re-evaluation with zero app-state changes; sustained
single-core CPU for as long as the window is visible (98-100% measured on
the editor face after interaction).

## Additional Notes for Triage

- **App-side write points: none.** In a ~2-minute editor-face window we
  measured 14298 ContentView + 14269 WorkspaceHostView re-evaluations; every
  `_printChanges()` diff was `@self` only (parent-passed values / closure
  identity). Deep child views each re-evaluate exactly once at mount, then
  never again — all churn is driven top-down from the scene/app graph.
- **Tree-shape robustness.** Ignition requires the heavy tree above, but
  once entered the loop survives app-side tree reduction: removing the
  `.inspector` host or the `safeAreaInset` banners still sustains
  ≈ 30-36% CPU (three independent reproductions on the current build,
  occlusion-gated readings). This makes a minimal repro hard — we can
  supply the exact tree.
- **Occlusion is a clean on/off switch** for the spin (minimize / full
  occlusion / ⌘H → 0% CPU with zero loop frames; bringing the window to
  front re-ignites within ≤ 1 s with no click), which localizes the loop
  to the scene-visible update path rather than any timer/async source.
- **Regression window: not established.** The app is macOS 27-only
  (deployment target macOS 27), so no earlier-OS comparison exists; we
  first observed the spin after the macOS 27.0.1 update cycle. We did
  not bisect across 27.0.x builds.
- **Workaround shipped** (documented for our users): minimize/occlude
  the window or ⌘H to stop the burn; bringing the window to front
  resumes within ~1 s, no click. App-side mitigation (tree reduction /
  window splitting) was evaluated and ruled out — the loop survives
  tree surgery; the fix path is upstream.

## Attachments（择要）

1. `t1-menu-loop-sample.txt` — 6s `sample` of the editor face: the full loop
   stack with per-frame counts (makeMainMenu 254 / updateMainMenu 240 /
   invalidateProperties 239 / requestUpdate 231 / updatePreferences 231,
   main thread 51%).
2. `acc2-d6-editor-sample.txt` (+ `...2.txt`) — second/third independent
   captures confirming the same ring from a separate session/machine run.
3. `acc2-d6-editor-broken.png` / `acc2-d6-click-after-occlude.png` — the
   functional-but-spinning editor face and the post-occlusion recovery
   (file name from an earlier capture round; the corrected semantics is
   front-most reveal re-ignites, click not required).
4. Transcript excerpts (on request): `_printChanges()` counters
   (~14k/2min, all `@self`), tree-surgery re-test matrix (three
   independent `.inspector`/`safeAreaInset`-removal runs, all alive),
   occlusion A/B logs (0% ↔ ≤1s re-ignite, no click).

---

## 提交后动作（用户）

1. Feedback Assistant 提交（附上表择要 2-4 件；正文直接粘贴上方英文段）。
2. 案号回填：REQUIREMENTS SHELL-04 行 + GOAL-STATE 续接点（把「FB 案号待回填」改为 FB##########）。
3. macOS 27.1 release notes 监测（SHELL-04 持续义务）：关键字 `menu` / `updateMainMenu` / `property graph` / `invalidation`；命中即在下一批次复测 D-6 复现配方。

---

## 修订节（append,2026-10-19:F0' 壳交接 spike 后的双重排除法终章——提交前并入正文)

> 正本:`phases/nsmenu-spike/SPIKE.md`(F0 FAIL)+ `phases/nsmenu-spike/F0PRIME.md`
> (F0' 双门 PASS)。本节把两次 spike 的机制证据并入报告稿——给 Apple 的复现与定位
> 价值显著提升,建议提交时以本节替换/增补 Additional Notes 与 Steps。

### 修订 1:最小复现配方升级——「壳交接」即消(96% → 0.0%)

原稿的复现需要「heavy tree shape」(三段式内容行 + `.inspector` host + 双
`safeAreaInset`),点火条件复杂且对树形手术鲁棒(Notes 已述)。F0' spike 给出了
**结构性最小复现与结构性消除**:

- **消除配方**:把 SwiftUI `App`/Scene 生命周期整体移除——`NSApplicationDelegate`
  手动托管 NSWindow,同一 ContentView 树降级为 `NSHostingView` 子内容(零面内容改动,
  同一 MTKView、同一 isPaused/enableSetNeedsDisplay 配置)→ 编辑器静置 %cpu 中位
  **96.0% → 0.0%**(三轮交错对测,9/9 轮 frontmost 门 + L082 哨兵;0% 栈证 = 主线程
  4643/4643 样本泊在 `NSApplication.run → mach_msg2_trap`,全进程 4 线程全闲)。
- **对照配方(同一 face,仅保留 SwiftUI lifecycle)**:96.0 / 97.1 / 95.7——两臂
  面逐字节同源(spike 为同一 wiring 逐字移植),唯一变量 = 生命周期宿主。
- 对 triage 的含义:**不需要构造 heavy tree 也能触发**——任何常驻 SwiftUI scene
  lifecycle + 稳态编辑面的 app 在本版本上都值得先测静置 %cpu;而「是否宿主在
  SwiftUI scene 生命周期」是一个一行即可切换的判定开关,定位成本低。

### 修订 2:双重排除法证据链(振幅载体 = scene 生命周期机器本身)

| 实验 | 摘除物 | 结果 | 排除 |
|---|---|---|---|
| 原稿树形手术(三独立复现) | `.inspector` host / 双 `safeAreaInset` | 仍 30-36% | 排除「树形宿主件」 |
| **F0**(`spike/nsmenu-f0`) | **菜单面整体**(Commands 45 项 → inert stub + NSMenu 桥;menu 环符号三臂一致缺席) | B vs A **−0.5pp 带内** | 排除「菜单重建环」——`makeMainMenu/updateMainMenu` 符号在场与不在场不改变振幅 |
| **F0'**(`spike/f0prime-shell`) | **面内容差异**(同一 face 逐字移植)+ **Scene 生命周期**(手动 NSApplication) | **96.0% → 0.0%** | 定位振幅载体 = scene 生命周期自身的 ViewGraph re-eval/layout 机器(UpdateStack/sizeThatFits 族,两臂栈差分在案) |

注:原稿环签名(makeMainMenu→updateMainMenu→invalidateProperties→…)在稳态编辑器面
的 sample 中缺席(menu 环符号 ≈0/样本而 CPU 恒 ~95%,F0 §2.1)——**原稿的环栈是
图库/idle 通用面的形态;编辑器面的 churn 是同一机器的另一种燃烧形态(无 menu 环符
号、纯 ViewGraph/layout)**。报告稿表述建议从「menu/focus update loop」放宽为
「**scene-graph churn**」一族,menu 环作为其在轻面上的一个具体环身份。

### 修订 3:churn 机器的功能性副作用(未追踪读被 churn「顺手」续命)

壳静默后暴露一个真实功能回归(生产中大概率同样存在,只是被 churn 掩盖——推断,未在
生产复验):

- **现象**:菜单命令「实际大小/适配屏幕」变异 `ViewportState.zoom` 后视口零重绘。
  链路:变异 ✓ → 分发 ✓ → 重绘桥 = `NSViewRepresentable.updateNSView` 的 zoom 签名
  push-once——但 `updateNSView` 是**非追踪上下文**,视图 body 对该状态无 tracked read,
  SwiftUI 从不 re-eval 该 representable → `setNeedsDisplay` 永不武装。
- **生产为何「看起来正常」**:96% 常驻 churn 机器持续 re-eval 全树,「顺手」替所有
  未追踪消费者跑 updateNSView——**churn 不止是开销,它在承担失效传播的功能**。
- 对 Apple 的定位价值:这把缺陷的影响从「性能/能耗」扩到「**正确性被开销掩盖**」——
  修复 churn 后,所有依赖常驻 re-eval 的未追踪读点(NSViewRepresentable 族为主嫌)
  会连环暴露为功能回归。建议修复方向注释:**churn 消除应伴随「未追踪读不再被隐式
  续命」的迁移说明**(或提供显式的 representable invalidation 面)。

### 修订 4:表单字段更新建议

- Title 建议改为:`SwiftUI scene lifecycle sustains a display-cycle-locked ViewGraph
  churn (96% CPU idle) on macOS 27; manual NSApp lifecycle eliminates it (0.0%) and
  exposes untracked-read functional regressions it was masking`
- Steps 增补第 8 步:the shell-handover differential above(one-line lifecycle swap,
  zero face-content change)。
- 附件增补:F0' 对测 logs 目录(`f0prime-logs/<arm>-<round>/`)+ 双臂 sample.txt
  (A = UpdateStack/sizeThatFits 654-770,B = 主线程全泊 mach_msg2_trap)。

---

## 终章（append,2026-10-20:生产化壳交接落地 + D-6 门定版终数据——呈用户提交形态)

> 本节为报告稿的**提交终态补章**:壳交接已作为生产变更落地(单一 commit,
> revert-clean),D-6 门以生产二进制定版。前三修订节(spike 双重排除法/功能性
> 发现/表单字段建议)全部维持,数值以本节生产终数据为准。**提交动作 = 用户手
> 动(惯例不变,本稿不代提交、不含提交渠道面)。**

### 终 1:壳交接已生产化(不再是 spike 形)

- **落地形态**:@main 入口 fork 的 GUI 臂尾一行切换——`LightamerShellMain.run()`
  (手动 NSApplication + NSApplicationDelegate 托管 NSWindow + 同一 ContentView
  树降级 NSHostingView 子内容 + 自建 NSMenu 全族 parity)。生产翻转 commit =
  `752c5294`(恰三产线文件,`git revert` 干净应用已验——独立可回退)。
- **全量回归**:壳交接后全套单测三轮同值 `TOTAL|3991/37/0|`(七 bundle,
  exit 0 零 MEMFAIL);直启测试宿主等价性双轮逐值(翻转前/后二进制 Library
  bundle 738/4/0 = 738/4/0,peakRSS 615MB 同值)——生命周期替换对宿主行为
  零可观察影响。
- **死码退役**:SwiftUI App/Scene/Commands 全族已从源码退役(生产二进制
  strings 无 App struct;退役后 App bundle 943/6/0 零漂移)——「双壳并存」
  的任何疑虑不成立:生产只存在手动 NSApplication 生命周期单选。

### 终 2:D-6 门定版终数据(生产二进制,四哨兵全过)

| 轮 | 二进制 | 生命周期 | %cpu 中位(30s 窗 6 采样) | 主线程泊 | churn 符号族 |
|---|---|---|---|---|---|
| spike A-r1..3 | spike 构建 | SwiftUI App/Scene | 96.0 / 97.1 / 95.7 | 活跃 ViewGraph/layout | UpdateStack/sizeThatFits 654-770 |
| spike F0'-B | spike 构建 | 手动 NSApp | **0.0** ×3 | mach_msg2_trap 全泊 | 全 0 |
| 生产 d6-B-r1..3(HEAD) | 生产构建 | 手动 NSApp | **0.0 / 0.0 / 0.0** | mach_msg2_trap 泊(4656/4655 样本,`LightamerShellMain.run → NSApplication.run` 栈证) | 全 0 |
| 生产 d6-A-r1(pre-flip 重建) | 生产构建 | SwiftUI App/Scene | **97.6** | — | — |

- **消除振幅终值:−97.6pp**(97.6 → 0.0;spike 期 −96.0pp 的生产复现,两代
  一致)。
- 四哨兵(L082):frontmost 先行复验 3/3 true;窗内截图编辑器面完整渲染;
  主线程样本泊 `mach_msg2_trap`;churn 符号族(makeMainMenu/updateMainMenu/
  appGraphDidChange/prependValue/beginTransaction/UpdateStack/sizeThatFits)
  全 0。
- **判读**:同一 ContentView face、零面内容改动,仅生命周期载体不同,静置
  CPU 96-97.6% → 0.0%。载体 = SwiftUI scene 生命周期自身的 ViewGraph
  re-eval/layout 机器(修订 2 的「scene-graph churn」族表述维持)。

### 终 3:功能性发现的最终注记(修订 3 维持 + 生产侧处置)

- churn 机器曾承担未追踪读的失效传播功能(菜单缩放重绘即实例)——生产侧
  处置 = 未追踪读审计修复先行于翻转(zoom/pan/rot 构造参数化 + export
  presence onChange 化 + 四 stub 生产化),壳交接后逐面走查复证;这同时是
  给 Apple 的修复建议注记的实证:**churn 消除应伴随未追踪读的显式迁移**,
  本项目已按此序执行,可作为报告的 remediation 附件。
- 报告稿 Title/Steps/附件建议(修订 4)维持,数值替换为本节终数据
  (96.0/97.1/95.7 → 0.0 生产定版;附件目录增
  `phases/f0prime-prod/probe/logs/d6-{B-r1..3,A-r1}/`)。

### 终 4:提交前核对清单(呈用户)

- [x] 双重排除法证据链完整(F0 菜单桥 FAIL + F0' 面排除 → 载体 = 生命周期机器)
- [x] churn 功能性发现成节(修订 3 + 生产侧处置实证)
- [x] 壳交接终数据(97.6 → 0.0,生产二进制,四哨兵,三轮交错)
- [x] 全量回归同值(3991/37/0 三轮)+ 宿主等价性(738/4/0 双轮)
- [ ] **用户手动提交 Feedback Assistant**(表单值 = 修订 1 节 + 本终章数值)
