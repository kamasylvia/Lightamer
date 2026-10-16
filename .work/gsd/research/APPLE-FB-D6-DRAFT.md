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
