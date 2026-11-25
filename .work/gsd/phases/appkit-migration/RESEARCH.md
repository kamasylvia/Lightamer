# AppKit Migration Research (HEAD 671762f, 2026-11-25)

> **性质**:只读 research lane。零产品代码、零构建、零测试、零 commit。所有源码数字按 HEAD 实测，
> 命令写在每处；旧研究 `research/UI-STACK-SUCCESSOR-PRE.md`（2026-10-13）的数字并列在 §1.3。
> **范围**:回答 Q1-Q10（用户任务书），给出分波与顺序建议。**未做**:任何 AppKit 原型、构建或性能测量。

---

## §0 Conclusion and decisions

**一句话结论**:这次迁移的真实工作量不在「把视图重写成 AppKit」，而在**重建一层当前完全不存在的 AppKit 控件与观察词汇**：123 个 SwiftUI 文件 / 46,489 行 / 470 个 `some View`，其中编辑器面 24,293 行（52.2%）；而产品里现在 **0 个 `NSButton`、0 个 `NSTextField`、0 个 `NSSlider`、0 个 `NSTableView`**（`rg -o -w` 全 `App/Sources` 命中数均为 0）。壳、菜单、窗口、文件面板已经是 AppKit；Core/IOP/Decode 零触碰。按 3 小时一个 lane、全套 7 bundle 串行 35-40 分钟估，**26 个 UI lane**（W0-W25）+ #24/#28 core 4-6 lane = **30-32 个**才能做到「`App/Sources` 无 `import SwiftUI`」。

### 裁决点（每点 = 问题 / 选项 / 推荐 / 依据）

**D1. 核心轨与 UI 轨谁先。**
- 选项:A 按 #23 建议 `#24 → #28 core → #31 W1-2…`；B 先 `#31 W1-3`（AppKit 壳 + 控件词汇 + 面板模板），再 `#24 → #28 core`，再 `#31` 其余；C 只做 W0 脚手架后立刻转 `#24`。
- 推荐:**B**。
- 依据:#24 有两个未决前置（#30 间歇崩溃、LGPL 静态链接合规），#31 无前置；#27、#25、#29 的 UI 面全部等 AppKit 基础（#27 的三步 1-3 与 #31 W1-2 是同一批工作）；W1-2 两个 lane 就能让用户看到第一块 AppKit 面板，见 §7。

**D2. 遗留 Sessions/Catalogs 面删还是迁。**
- 选项:迁到 AppKit（3,203 行视图 + 3,601 行 Session/Catalog 模型）；删除 UI + gate；保留代码但永不编译。
- 推荐:**删除 UI 与 gate，保留仍被 MCP/非 UI 测试使用的 Session/Catalog 模型（先审计）**。见 §10。
- 依据:该面默认关闭（`LibraryLegacyGate` 默认 false），只在 `LIGHTAMER_LEGACY_LIBRARY=1` 时出现；迁它是纯沉没成本，而 #31 的验收要求最终 `grep -rn "^import SwiftUI" App/Sources` 为空。

**D3. 双栈并存期怎么控（已决，留档，不请求用户裁决）。**
- 决定:面级 flag，单一 env 读点，默认 SwiftUI 直到该面验收后翻 AppKit；最后一个 lane 删除 SwiftUI 与 flag。
- 依据:`LibraryLegacyGate.isLegacyLibraryRequested(environment:)` 是现成先例（`Library/LibraryPreferences.swift:28-41`，唯一 ProcessInfo 读点，纯函数可注入）；#31 acceptance 也要求「每波可独立回退，直到删除双栈开关的那一波」。这不是用户口味问题，是 #31 验收的机械要求。

**D4. #27 的控件层是否与 #31 合并（已决，留档）。**
- 决定:全部 AppKit，#27 步骤 1-3 并入 #31 W1-W8。
- 依据:2026-11-25 用户裁决覆盖 #27 的旧控件层结论（#31 正文与 #23 裁决节）；保留 SwiftUI 容器会在最终验收留下 `NSHostingView`，与 #31 验收冲突。

**D5. 全套基线怎么用。**
- 选项:把 4618/35/1 当每波硬门；先把 #30 间歇崩溃定性/隔离再当门；改用 App bundle 单跑当门。
- 推荐:**先给 #30 一个明确处置（修复或标记已知偶发并在验收轮记录），再以「App bundle 无新增失败 + 全套无新增失败」为门**。
- 依据:#30 的崩溃只在一次 App bundle 重跑出现（`SpektraFilmModule.process`，`~446 s`），与 UI 无关；用它挡住 UI 波次会把无关风险变成迁移风险。App bundle 当前基线 1135/6/0（#24 评论），是 UI 迁移的直接暴露面。

**D6. 三个次级窗口何时去 `NSHostingView`（已决，留档）。**
- 决定:最后一批（W24），与设置/对话框同批。
- 依据:三者已经是 `NSWindowController + NSHostingView`（`ShellWindowControllers.swift:28-130`），迁移机械；提前做不产生用户可见收益，却要同步改三套 environment 注入；W24 的验收本来就要覆盖窗口生命周期。

---

## §1 Q1 — Current surface at HEAD

### 1.1 Method

```bash
git rev-parse HEAD                         # 671762ffa3a16ac3041d0b0bd60203a803e2328d
find App/Sources -name '*.swift' | wc -l   # 218
rg -l '^import SwiftUI' App/Sources | wc -l # 123
rg -l '^import SwiftUI' App/Sources | xargs wc -l | tail -1 # 46489
rg -o 'some View' App/Sources | wc -l      # 470
```

Per-file table = `INVENTORY.md`. Counts are raw textual occurrences; comments included.

### 1.2 Face table

| Face | Files | Lines | `some View` | Self-drawn controls (Canvas/Gesture-bearing files) | Main coupling |
|---|---:|---:|---:|---:|---|
| Editor shell | 15 | 5,847 | 109 | 3 / 2 | `EditorState` 9, `AgentControlCoordinator` 7, `PipeCoordinator` 6 |
| Inspector panels | 50 | 11,548 | 104 | 7 / 5 | `EditorState` 10, `PipeCoordinator` 8, `LayerEditingState` 8 |
| Overlays | 10 | 4,204 | 25 | 4 / 6 | `EditorState` 5, `LayerEditingState` 4, `PipeCoordinator` 4 |
| Editor misc (viewport/status/EDR) | 8 | 2,694 | 17 | 0 / 1 (+1 AppKit MTKView) | `PipeCoordinator` 4, `EditorState` 4, `ViewportState` 3 |
| Library | 13 | 7,907 | 72 | 0 / 3 | `EditorState` 4, `InspectorState` 4, `AgentControlCoordinator` 3 |
| Export | 4 | 2,656 | 39 | 0 / 0 | `ExportState` 2, `EditorState` 2, `PipeCoordinator` 2 |
| Settings | 2 | 1,866 | 28 | 0 / 0 | `LibraryProjectController`, `PipeCoordinator`, `CatalogPreferencesModel` |
| Yiyin | 2 | 1,031 | 10 | 0 / 0 (drag lives in `WorkspaceHostView`) | `EditorState`, `PipeCoordinator`, `YiyinLogoStore` |
| App windows/dialogs | 5 | 1,318 | 17 | 0 / 1 | `PresetsStore`, `PresetController`, `AIDownloadModel` |
| Legacy (gate off) | 6 | 3,203 | 48 | 0 / 2 | `SessionState` 3, `CatalogTreeModel` 2 |
| Shell/theme/state | 8 | 4,215 | 1 | 0 / 0 | 无 `@Environment`；持有全部 40+ 协调器 |
| **Total** | **123** | **46,489** | **470** | **14 / 20** | |

Editor face (shell + inspector + overlay + misc) = **24,293 lines = 52.2%**. Library = 17.0%. All other faces = 30.7%.

Self-drawn control instances named in §2. The "files" column counts files that contain `Canvas {` or a gesture; a file can hold several controls.

### 1.3 Old research vs this measurement

Old numbers: `research/UI-STACK-SUCCESSOR-PRE.md` §0.1/§0.2, measured 2026-10-13 at `e9034d5e`.

**Scope caveat**: the old research row `106 / 34,479` was the **`UI/` directory**, not "files importing SwiftUI". At HEAD, `UI/` is 115 files / 39,306 lines; `UI/` files importing SwiftUI are 105 / 36,559; all SwiftUI-importing files in `App/Sources` are 123 / 46,489. Only the `App/Sources` row (198/71,657 → 218/81,610) and the `UI/` directory row are same-scope comparisons; the all-SwiftUI row has no 2026-10-13 counterpart.

| Metric | 2026-10-13 | 2026-11-25 (HEAD) | Delta |
|---|---:|---:|---|
| `App/Sources` files / lines | 198 / 71,657 | 218 / 81,610 | +20 / +9,953 |
| `UI/` directory files / lines | 106 / 34,479 | 115 / 39,306 | +9 / +4,827 |
| `UI/` files importing SwiftUI / lines | not measured separately | 105 / 36,559 | — |
| All SwiftUI-importing files / lines | not measured (old row was UI/ only) | 123 / 46,489 | — |
| `State/` files / lines | 21 / 9,128 | 24 / 10,956 | +3 / +1,828 |
| `some View` | not measured | 470 | — |
| `.sheet(` | 29 | 30 | +1 |
| `@State` | 276 | 277 (`.swift` only; 270 in SwiftUI files) | +1 |
| `@Environment(` | 152 | 156 | +4 |
| `@Observable` | 73 occurrences / 54 files | 82 occurrences / 59 declarations / 55 files | +9 / +5 |
| `Button(` | 281 | 258 | −23 |
| `Slider(` | 215 | 220 | +5 |
| `keyboardShortcut` | 57 | 32 | −25 |
| `Toggle(` | 57 | 63 | +6 |
| `TextField(` | 50 | 51 | +1 |
| `Menu {` | 25 | 27 | +2 |
| `List` (exact `List {`/`List(`) | 16 | 13 | −3 |
| `LazyVGrid` | 11 | 11 | 0 |
| `NavigationSplitView` | 7 | 2 real call sites (`ContentView.swift:241`, `SettingsView.swift:70`); 8 textual hits | −5 |
| `focusedSceneValue` | 8 | 3 textual hits (1 key definition + comments; the publish faces retired in F0P-03) | −5 |
| `onGeometryChange` | 4 | 4 | 0 |
| `.inspector(` | 1 | 1 (`ContentView.swift:836`, the default-shell page mount) | 0 |

The `Button` drop and `keyboardShortcut` drop are the F0' menu handover: `Commands`/`keyboardShortcut` moved to `NSMenuBridge` (`UI/Shell/NSMenuBridge.swift`, 738 lines, 18 `NSMenuItem` hits). The default shell no longer uses `NavigationSplitView`; the two real uses are the legacy body and the Settings window.

Issue #31 states 467 `some View`; HEAD measures 470. The issue number is 3 low; use 470.

### 1.4 What is already AppKit

- `@main` is a manual `NSApplication` lifecycle: `LightamerEntryPoint.main()` → `LightamerShellMain.run()` (`UI/LightamerApp.swift:126-180`, `UI/Shell/LightamerShell.swift:2480-2541`).
- Main window = `NSWindow` + `NSHostingView(rootView: LightamerShellFace)` (`LightamerShell.swift:2401-2425`).
- Main menu = static `NSApp.mainMenu` tree + `NSMenuDelegate`/observation refresh (`NSMenuBridge.swift:1-738`).
- File panels = `NSOpenPanel` (27) / `NSSavePanel` (9), all through `PanelPresentation.present(_:)` (`UI/PanelPresentation.swift`).
- Viewport = `MTKView` inside `NSViewRepresentable` (`UI/EditorMTKView.swift:33`); the `NSView` subclass already overrides `magnify/rotate/scrollWheel/smartMagnify` (`:879-915`) — the viewport gesture surface is native AppKit, not SwiftUI.
- Three secondary windows = `NSWindowController` + `NSHostingView` (`UI/Shell/ShellWindowControllers.swift`).
- **Not present**: any `NSButton`, `NSTextField`, `NSSlider`, `NSTableView`, `NSSplitView`, `NSStackView`, `NSCollectionView`, `NSVisualEffectView`, `NSColorWell`, `NSPopover`, `NSAlert` (`rg -o -w` counts = 0; `NSSplitView` appears only in comments).

---

## §2 Q2 — Control vocabulary

### 2.1 System controls (SwiftUI), with AppKit landing point

Counts = exact token forms (`rg -o -F` for the listed form; `Path(` uses a word boundary because `filePath(` matches the raw token). The `List` row counts `List {` (3) + `List(` (10); the drag row counts `onDrop` 4, `onDrag {` 2, `draggable` 2, `dropDestination` 2 — a bare `rg -F onDrag` would also hit `onDragBegin`.

| SwiftUI | Count | AppKit landing |
|---|---:|---|
| `Button(` | 258 | `NSButton` (`.borderless` 65, plain 29, `.bordered` 3, `.borderedProminent` 11) |
| `Slider(` | 220 (180 `LightamerSlider` call sites + 40 direct `Slider` sites) | `NSSlider` inside a custom `LMControlRow`; `isContinuous = true`; begin/end from `mouseDown`/`mouseUp` tracking |
| `Toggle(` | 63 | `NSButton` checkbox / `NSSwitch` (2 `.switch`, 4 `.checkbox`) |
| `TextField(` | 51 | `NSTextField` + `NSTextFieldDelegate` |
| `Picker(` | 113 (23 `.segmented`, 7 `.menu`, 5 `.radioGroup`) | `NSSegmentedControl` / `NSPopUpButton` / radio `NSButton` group |
| `Menu {` / `Menu(` | 27 / 50 | `NSMenu` + `NSPopUpButton` |
| `Stepper(` | 2 | `NSStepper` |
| `ProgressView(` | 35 | `NSProgressIndicator` |
| `ColorPicker(` | 2 | `NSColorWell` |
| `DatePicker(` | 4 | `NSDatePicker` |
| `SecureField(` / `TextEditor(` | 1 / 1 | `NSSecureTextField` / `NSTextView` |
| `ScrollView` | 27 | `NSScrollView` |
| `LazyVGrid` | 11 | `NSCollectionView` |
| `List` | 13 (`List {` 3 + `List(` 10) | `NSTableView` / `NSOutlineView` |
| `DisclosureGroup` | 8 | disclosure `NSButton` + container |
| `.sheet(` | 30 | window sheet (`beginSheet`) / `NSWindowController` |
| `.alert(` / `.confirmationDialog(` | 20 / 7 | `NSAlert` |
| `.popover(` | 3 | `NSPopover` |
| `.contextMenu` | 13 | `NSView.menu(for:)` / `rightMouseDown` |
| `keyboardShortcut` | 32 | `NSMenuItem.keyEquivalent` / `performKeyEquivalent` |
| Drag/drop (`onDrop` 4, `onDrag` 2, `draggable` 2, `dropDestination` 2) | 10 | `NSDraggingDestination` / `NSPasteboard` |
| `@FocusState` | 3 real declarations (4 occurrences incl. 1 comment) | `NSWindow.makeFirstResponder` + responder chain |
| `PreferenceKey` | 1 (`NodeCardFramesKey`) | delegate callback / layout notification |
| `Canvas {` / `Path(` (word-boundary) / gestures | 15 / 49 / 40 | `NSView.draw(_:)` or `CALayer`; `NSGestureRecognizer` / `NSEvent` |
| `NSViewRepresentable` | 2 types (`EditorMTKView`, `WindowCapture`) | none — direct `NSView` |
| `NSHostingView` | 3 mounts (`LightamerShell:2407`, `ShellWindowControllers:52/81/117` — the latter three are the three secondary windows) + 6 comment mentions, 4 files | delete at the end |

### 2.2 Self-drawn controls (named)
Editor/inspector:
1. `LightamerSlider` (`UI/Inspector/LightamerSlider.swift:18`) — wraps `Slider` + numeric readout + readout scrub (`DragGesture` at `:88`) + double-click reset (`:128`) + Shift 1/10 speed (`:110-126`).
2. `CurveEditorView` (`:21`) — `Canvas` + drag nodes; begin/change/end callbacks (`:23-27`).
3. `TrackballView` (`ColorWheelsPanelView.swift:420`) — `Canvas` + drag.
4. `ColorBalanceRGBHueDisc` (`ColorBalanceRGBPanelView.swift:346`) — `Canvas` + drag.
5. `HueStrip` (`ColorZonesPanelView.swift:201`) — `Canvas`.
6. `ForceCurveView` (`DenoiseProfilePanelView.swift:355`) — `Canvas`.
7. `MonochromeColorWheel` (`MonochromePanelView.swift:125`) — `Canvas` + drag.
8. `ToneEqualCurveView` (`ToneEqualPanelView.swift:257`) — `Canvas`.
9. Film curve inside `FilmPanelView` (`:789`) — `Canvas`.
10. `ScopePanelView` (`:84`) — two `Canvas` (histogram/waveform).
11. `EditorNodesPanelView` (`:21`) — `Canvas` + node drag (`DragGesture` at `:371`) + `PreferenceKey` frames.
12. `FilmstripView` (`:253`) — tap-to-open over system `ScrollView`.
13. `EditorAdjustmentStackView` (`:521` lines) — row list, no raw canvas.
14. `MaskToolbarView` (`:290/:321/:894` sliders), `InstancePickerOverlay`, `CropToolPanelView` — standard controls in overlay chrome.

Viewport/overlays:
15. `EditorMTKView` / `ViewportMTKView` (`:33`, `:861-915`) — already AppKit; mouse/gesture events already `NSEvent` overrides.
16. `EditorAreaView` — `SpatialTapGesture` (`:359`), split handle (`:759`), drop target (`:294`).
17. `MaskOverlayHost` (`:113` canvas, `:263` drag).
18. `SegmentEditingOverlayHost` (`:501` `SegmentPointsCanvas`, drags at `:174/:190`).
19. `RetouchOverlayHost` (`:257` canvas, drag `:111`).
20. `LiquifyOverlayHost` (`:184` canvas, drags).
21. `CropOverlayView` (drags `:262/:291`).
22. `UprightGuidesOverlay` (`:249` drag).
23. `InstancePickerOverlay`.
24. Yiyin sheet edge handles (`WorkspaceHostView.swift:1900-1980`): two invisible drag strips, global-coordinate drag because the sheet re-hangs while resizing.

Library/export/settings:
25. `LibraryGridView` — `NSCollectionView` analogue; cell is SwiftUI, double-click tap.
26. `CullFaceView` — two-pane compare + keyboard focus (`@FocusState`).
27. `LibraryInspectorView` — form/table hybrid.
28. `ExportInspectorView` / `ExportPanelView` — scroll form + queue list + quality slider.
29. `SettingsPages` — ten pages of forms.
30. `YiyinPanelView` — sliders + logo picker + sheet sizing.

### 2.2b Landing points for the self-drawn controls

| Control | AppKit landing |
|---|---|
| `LightamerSlider` | `LMSliderRow: NSView` = label `NSTextField` + `NSSlider` (`isContinuous`) + value `NSTextField`; begin/end from `NSSlider` tracking or `mouseDown`/`mouseUp`; readout scrub = `NSPanGestureRecognizer`; double-click = `NSClickGestureRecognizer(numberOfClicks: 2)` |
| `CurveEditorView`, `ToneEqualCurveView`, `ForceCurveView`, film curve | custom `NSView` with `draw(_:)` (Core Graphics) + `NSPanGestureRecognizer` / `mouseDragged`; nodes as `CALayer` or drawn in one pass |
| `TrackballView`, `ColorBalanceRGBHueDisc`, `HueStrip`, `MonochromeColorWheel` | custom `NSView` + `draw(_:)`; drag = `NSEvent`/`NSPanGestureRecognizer`; double-click reset |
| `ScopePanelView` | custom `NSView` (layer-backed) or `CAMetalLayer`; throttle already exists (`ScopeThrottle`) |
| `EditorNodesPanelView` | custom `NSView` host + `NSView` cards (or `CALayer`), `NSPanGestureRecognizer`; frames read in `layout()` |
| `MaskOverlayHost`, `SegmentEditingOverlayHost`, `RetouchOverlayHost`, `LiquifyOverlayHost`, `CropOverlayView`, `UprightGuidesOverlay`, `InstancePickerOverlay` | transparent `NSView` sibling above the `MTKView`; `hitTest`, `mouseDown/Dragged/Up`, `NSAccessibility` for handles |
| `MaskToolbarView`, `CropToolPanelView` | `NSStackView` + `NSButton` / `NSPopUpButton` / `NSSlider` / `NSSegmentedControl` |
| `FilmstripView` | vertical `NSCollectionView` (flow layout) |
| `LibraryGridView` | `NSCollectionView` (flow layout, item = thumbnail cell) |
| `CullFaceView` | `NSSplitViewController` (2 panes) + `NSImageView`/custom compare view |
| Yiyin sheet edge handles | borderless `NSPanel` + `NSView` hit strips, `NSCursor.resizeLeftRight` / `.resizeUpDown`, global mouse delta + clamp/persist |
| `EditorMTKView` | delete the `NSViewRepresentable`; mount the existing `MTKView` subclass directly (`EditorMTKView.swift:861-915` already owns `NSEvent`) |
| `EditorAreaView` drop / split handle | `NSDraggingDestination`; `NSSplitViewController` divider instead of the custom 140 pt handle |

### 2.3 D-H1 (begin / setLive / end) controls

`InspectorEditSession` is the only façade (`UI/Inspector/IOPPanelProvider.swift:49-160`):
`beginEditing()` → `PipeCoordinator.beginContinuousEdit`; `update(_:)` → `setLiveParams` (0 history);
`endEditing(label:)` → `commitContinuousEdit` (exactly one `HistoryItem`); `applyDiscrete` = begin+update+commit for click controls.

- 180 `LightamerSlider` call sites across 40 files pass `onDragBegin`/`onChange`/`onDragEnd` into that façade. Example: `AgXPanelView.swift:39-41`.
- 40 direct `Slider(` sites (220 total occurrences − 180 `LightamerSlider` calls); 8 use `onEditingChanged` (e.g. `FilmPanelView.swift:731`).
- Custom canvases reuse the same trio: `CurveEditorView` (`onDragBegin`/`onNodesChanged`/`onDragEnd`), color wheels/balance/zones via `onChange` + `applyDiscrete` reset.
- Dependency on `@Observable`: the panel does **not** observe `PipeCoordinator` for editing values; it receives an immutable `ModuleInstance` + the session. Reads of the live record come from `EditorState.instances` (`InspectorView.swift:92-95`). This is the seam that makes AppKit port cheap: an `NSSlider` only needs the same three callbacks.
- Continuous-control counts: 180 slider sites + ~10 canvas controls + 8 `onEditingChanged` sites. A ported control must fire begin once on mouse-down, live ticks during drag, end once on mouse-up; the readout scrub is a second gesture on the number field.

---

## §3 Q3 — Observation glue

### 3.1 What exists

- `@Observable` declarations: **59 in 55 files** (`rg -n '^@Observable' App/Sources`). Occurrence count incl. comments = 82. `State/` holds 17 observable files / 9,352 lines of 24 files / 10,956.
- `@Environment(` = 156: 151 `Type.self`, 4 `\.dismiss`, 1 comment. No `EnvironmentKey` definitions, no `ObservableObject`/`@Published`/`@StateObject` anywhere — the app is pure Observation.
- Existing AppKit observation precedent: `NSMenuBridgeController.armObservation()` uses one `withObservationTracking` read-set (17 reads) and re-arms after `DispatchQueue.main.async` refresh (`NSMenuBridge.swift:683-712`). This is the model for every AppKit face.
- `@State` = 277 total (270 in SwiftUI files); these are view-local, not shared state. AppKit equivalent = view-controller properties.
- `.task` = 61 total / 50 in SwiftUI files; `.onChange` = 56; `.onAppear` = 33. These are lifecycle glue, not state.

### 3.2 SwiftUI-specific mechanisms and replacements

| Mechanism | Count | Replacement |
|---|---:|---|
| `@Environment(Type.self)` injection | 151 | explicit init injection (already the `ShellWindowControllers` shape) or a typed `AppContext` passed down; no magic lookup |
| `@Environment(\.dismiss)` | 4 | `dismiss` closure / `NSWindowController.close` |
| `.sheet` | 30 | `NSWindow.beginSheet` + `NSWindowController`; one controller per sheet |
| `.alert` | 20 | `NSAlert` (beginSheetModal) |
| `.confirmationDialog` | 7 | `NSAlert` with 2-3 buttons |
| `.popover` | 3 | `NSPopover` |
| `.task` / `.task(id:)` | 61 | `Task` started in `viewDidAppear`/`viewDidMoveToWindow`; cancellation token tied to controller lifetime; id-change = cancel+restart |
| `.onChange` | 56 | explicit observation relay (`withObservationTracking` re-arm) or delegate callback from the model |
| `.onAppear` | 33 | `viewDidAppear` / `viewDidMoveToWindow` |
| `@FocusState` | 3 real (4 occurrences) | `NSWindow.makeFirstResponder` + `NSResponder` chain; menu enabler reads first responder |
| `.inspector(isPresented:)` | 1 (`ContentView.swift:836`, export/film page mount) | `NSSplitViewItem.isCollapsed` toggle / right-pane container show-hide |
| `focusedSceneValue` | 3 textual (publish retired) | already replaced by `NSMenuBridge` notes; delete the key/accessor |
| `PreferenceKey` | 1 (`NodeCardFramesKey`) | layout delegate / `NotificationCenter` / parent reads child frames after layout |
| `NavigationSplitView` | 2 real | `NSSplitViewController` |
| drag/drop modifiers | 10 | `NSDraggingDestination`, `NSPasteboard` |
| `keyboardShortcut` | 32 | `NSMenuItem.keyEquivalent` for menu commands; `performKeyEquivalent` for in-view keys |
| `buttonStyle` | 65 borderless + 29 plain + 3 bordered + 11 borderedProminent | `NSButton.isBordered = false` / `bezelStyle` / custom `NSButton` cell drawing |
| `pickerStyle` | 23 segmented / 7 menu / 5 radio | `NSSegmentedControl` / `NSPopUpButton` / radio group |
| `Canvas` / `Path` (word-boundary) / gestures | 15 / 49 / 40 | `NSView.draw(_:)` or `CALayer`; `NSGestureRecognizer` / `NSEvent` |

### 3.3 Glue estimate per face

Formula used (inference): one observation relay per view controller (60-120 lines) + 3-8 lines per tracked property + 8-15 lines per `.task` + 5-10 lines per `.onChange`.

| Face | View structs | Env types | `@State` | `.task` | `.onChange` | Glue estimate (lines) |
|---|---:|---:|---:|---:|---:|---:|
| Inspector panels | 68 | 6 | 43 | 2 | 6 | 1,200-2,300 (50 panels × 20-40 + shared host) |
| Editor shell | 28 | 7 | 40 | 7 | 9 | 600-1,000 |
| Overlays | 14 | 7 | 27 | 2 | 7 | 400-800 |
| Editor misc | 10 | 11 | 7 | 4 | 5 | 300-600 |
| Library | 35 | 10 | 56 | 18 | 17 | 800-1,500 |
| Export | 7 | 6 | 13 | 1 | 0 | 300-500 |
| Settings | 13 | 3 | 21 | 1 | 4 | 300-500 |
| Yiyin | 1 | 0 | 6 | 1 | 0 | 200-300 |
| App windows | 5 | 3 | 14 | 3 | 2 | 200-300 |
| Legacy | 9 | 7 | 40 | 4 | 2 | 0 (delete) |
| Shell/theme | 1 | 0 | 3 | 7 | 3 | 0 |
| **Total** | **191** | | **270** | **50** | **55** | **4,300-7,300** |

`.task` and `.onChange` totals here are the SwiftUI-file counts (50 / 55); the whole-tree raw greps are 61 / 56 (one `.onChange` lives outside a SwiftUI-importing file).

Use the upper half for planning. The single biggest lever is a shared `ObservationRelay` + `AppKitPanelHost` so 50 panels do not each hand-roll a relay.

---

## §4 Q4 — Layout and theme

### 4.1 Current layout mechanics

- **Default shell is not `NavigationSplitView`.** `WorkspaceHostView` is `VStack` (top bar / phase `ZStack` / task bar) with `safeAreaInset` for read-only banner and toast (`UI/Shell/WorkspaceHostView.swift:135-245`).
- **Editor**: `EditorWorkspaceShellView` is an `HStack`: tool rail (conditional) + filmstrip `.frame(width: 148)` + viewport `maxWidth: .infinity` + right pane `.frame(width: 280)` (`EditorWorkspaceShellView.swift:38-90`). Widths are constants (`:47`, `:50`), not user-resizable.
- **Library**: `HStack`: `LibraryGridView` flexible + `LibraryInspectorView` fixed `.frame(width: 280)` (`WorkspaceHostView.swift:594-694`). No sidebar in project mode.
- **`NavigationSplitView`**: only 2 real sites — legacy `ContentView.swift:241` and `SettingsView.swift:70`.
- **`.inspector(isPresented:)`**: one live site — `ContentView.swift:836`, the default shell's export/film page mount. It is a presentation modifier, not a split; AppKit replacement = show/hide the right pane (`NSSplitViewItem.isCollapsed` or a container swap).
- **No `HSplitView`/`VSplitView`** (`rg -F` = 0). Only fixed HStacks.

### 4.2 AppKit replacement

| Region | Current | AppKit |
|---|---|---|
| Root window | `NSWindow` + `NSHostingView` | `NSWindowController` + root `NSViewController`; phase swap = `addChild`/`removeChild` or a container view with hidden subviews |
| Editor 4 columns | `HStack` fixed widths | `NSSplitViewController` with 4 items; filmstrip and right pane `holdingPriority` high, viewport low; `minimumThickness`/`maximumThickness` = current constants. Fixed-by-default preserves behavior; resizable is a later UX decision |
| Library 2 columns | `HStack` grid + 280 inspector | `NSSplitViewController` (2 items), inspector collapsible |
| Settings | `NavigationSplitView` | `NSSplitViewController`: sidebar `NSTableView`/`NSOutlineView` + detail container |
| Inspector list | `ScrollView` + `VStack` rows | `NSScrollView` + `NSStackView` (not `NSTableView`: variable-height panels) |
| Export queue | `ScrollView` + rows | `NSTableView` (or `NSStackView` if row heights vary) |
| Grid / filmstrip | `LazyVGrid` / `ScrollView` | `NSCollectionView` (flow layout) / `NSCollectionView` vertical |
| Dialogs | `.sheet` | `NSWindowController` + `beginSheet` |
| Menus | `NSMenu` (already) | keep |

`NSSplitViewController` is not required for behavior parity (current widths are fixed), but it is the boring AppKit answer and gives future resize for free. Do not build a custom split view.

### 4.3 Theme mapping

- `LightamerColors` (`UI/Theme/LightamerColors.swift`): 22 tokens — 8 neutrals, 4 text, 6 semantic surfaces, 4 status colors (`Color.accentColor`, `.red`, `.orange`, `.green`). Map to static `NSColor(srgbRed:green:blue:alpha:)`; system status colors → `NSColor.controlAccentColor` / `systemRed` / `systemOrange` / `systemGreen`.
- `ThemeTokens` (`UI/Theme/ThemeTokens.swift`): 7 glass families, 8 tokens, some semi-transparent (`cardSurface` alpha 0.80, `cardBorder` alpha 0.18). Map to `NSColor`; material blur → `NSVisualEffectView` with `.hudWindow`/`.underWindowBackground` if the glass look is kept. The comment says consumers may drop `.regularMaterial`/`.ultraThinMaterial`; AppKit equivalent is `NSVisualEffectView`.
- Dark is forced in 4 places via `.preferredColorScheme(.dark)` (`LightamerShell.swift:169`, `ShellWindowControllers.swift:56/125`, `McpLauncherPanelView.swift:185`). AppKit: `NSApp.appearance = NSAppearance(named: .darkAqua)` once at launch; per-window `window.appearance` if needed.
- **No spacing or typography token system exists.** Fonts are inline: `.font(.caption` (includes `.caption2`) 412, `.font(.callout` 59, `.font(.headline` 31, `.system(size:)` 34, `monospacedDigit` 42. Spacing literals: 0×39, 2×27, 4×47, 6×63, 8×42, 10×24, 12×17, 14×10, 16×6, 20/24 ×1. Darktable parity needs a new `ControlMetrics` (row height, label width, value width, slider height, separator) before panels are ported, otherwise each panel re-invents rhythm — the current drift #27 complains about.
- `InspectorRowView` shows the current row anatomy: 16 pt toggle circle, `.callout` label, 6 pt vertical padding, 12 pt horizontal padding (`UI/InspectorRowView.swift:73-99`). Darktable's row is ~20 px with no inter-row padding. Use one `LMPanelRow` height constant and monospaced digits for values.

### 4.4 darktable-style compact path

1. One `LMControlRow: NSView` = label (`NSTextField`, 11-12 pt) + control + value (`monospacedDigitSystemFont` 11 pt), fixed height 20-22 pt, no rounded background.
2. `NSSlider` with `.small` control size, custom cell to remove the default knob shadow; drag anywhere on the row = slider tracking + label/value not intercepting.
3. Double-click reset = `NSClickGestureRecognizer(numberOfClicks: 2)` on the row; right-click = `NSMenu` with Reset / Type-in / Preset.
4. Panel chrome = `NSBox`-free custom `NSView` header (enable circle, name, preset menu, reset), 1 px separator; no card corner radius.
5. Theme = `NSColor` tokens + `ControlMetrics`; row height and alignment pinned by a snapshot or frame-assert test.

---

## §5 Q5 — Test strategy

### 5.1 Current test assets

- `Tests/` = **531 files / 187,374 lines**, 4,626 static `func test…` occurrences (`rg -o 'func test[A-Za-z0-9_]+' | wc -l`), 0 `@Test`. Baseline is 4,618 **executed**; the 8-count difference is skip/parameterization/naming and was not audited.
- Baseline per #24/#30: **4618 executed / 35 skipped / 1 failed**; App bundle **1135 / 6 / 0**.
- 7 unit bundles: IOP, IOPParity, Layers, Library, Sessions, Export, App (`Scripts/test-direct.sh:173`). The **App target** uses a glob: `sources: ["App/Sources/**"]` (`Project.swift:171`), so new app files need no source-list edit. The **test targets** use explicit lists: `LightamerTestsApp` 132 entries, IOP 103, IOPParity 87, Layers 69, Library 86 (85 Swift + 1 fixture), Sessions 27, Export 42.
- SwiftUI-importing test files: **14 files / 4,655 lines**. 10 mount `NSHostingView` (25 hits); 5 use `AXUIElement` (26 hits); 1 `XCUIApplication` (`LightamerUITests/AppLaunchTests.swift`).
- View-level methods in the 10 hosting files: **66** (Culling 6, ExportCollision 5, ExportInspector 9, FilmPanel 7, NodeCanvas 9, ProjectReadOnly 19, SheetEnv 2, ShellGraph 4, ShellWindow 2, Toast 3). The other 4 SwiftUI files are pure model/menu/theme tests (AgentControl, MenuBridgeObservation, NSMenuParity, ThemeTokens).

So **1,135 App-bundle tests are the migration exposure; only ~66 are view-level**. Core-side 3,483 tests do not touch UI and must not change.

### 5.2 Mapping after migration

| Today | AppKit equivalent |
|---|---|
| `NSHostingView(rootView:).fittingSize` (Toast) | `NSView.fittingSize` / `intrinsicContentSize` + `layoutSubtreeIfNeeded` |
| Host + `.sheet` environment test (SheetEnv) | `NSWindowController` sheet mount; assert no missing-injection crash + content `viewDidAppear` |
| AX tree queries (`AXUIElement`, `accessibilityIdentifier`) | same AX queries against `NSView`/`NSButton`; set `setAccessibilityIdentifier`, `setAccessibilityRole`, `setAccessibilityLabel`; custom views implement `NSAccessibility` |
| `@FocusState` assertions | `window.firstResponder` identity |
| Menu parity (`NSMenuParityTests`) | unchanged — menu is already AppKit |
| Theme token tests | unchanged (port `Color` → `NSColor` assertions) |
| Event-driven view tests (NodeCanvas, Export panel) | `NSView` hit-test + `NSEvent`/gesture injection, or extract the same pure model (already done for NodeCanvasGeometry) |

The 66 view-level tests are a **floor, not a ceiling**: each ported face should get at least the same observable assertions (identifier exists, value updates, D-H1 one-commit, layout height) plus one negative probe for the AppKit-specific failure (stale frame, missing first responder, retain cycle).

### 5.3 What the 4618/35/1 baseline means for acceptance

- Full suite **lower bound** is ~2,080 s across 7 bundles from the F0' acceptance round-2 log (`.work/gsd/phases/f0prime-prod/all-runs/acc2-round-l2.log`, `TOTAL|3991/37/0|2081s`); HEAD has 4,618 tests (+15.7%), so budget **35-40 min**, not 35. Not re-run at HEAD. A 3 h lane leaves ~2 h 10 for implementation after build + full suite.
- #30 is a one-off `SpektraFilmModule.process` crash during an App bundle rerun; it is not UI-related. Do not use a single green full-suite run as the only proof; record per-bundle `BUNDLE|` lines and mark #30 as known-intermittent until fixed.
- Coverage must not drop: keep each SwiftUI face's tests green behind the flag until the AppKit face's equivalent tests exist; then delete only the duplicated mount assertions. Count executed tests per bundle before/after each wave (no silent skip growth).

---

## §6 Q6 — Overlap with other issues

| Work | Owner | Build on AppKit directly? | Why / dependency |
|---|---|---|---|
| Module self-registration (`@_used @_section`, no `iopOrder`) | #27 step 1 | **Yes, now** — Core/IOP only, no UI | Independent of UI stack; unblocks panel list data |
| Registry-driven panel list (category/relativeOrder) | #27 step 1 | Yes, now (Core) + W1 (host) | `InspectorState.registerDefaultProviders()` has 50 hand-written providers (`State/InspectorState.swift:129-238`); panel selection is already instance-driven (`InspectorState.panelView(for:edit:)`, `State/InspectorState.swift:244`) |
| One control vocabulary (`SliderRow`/`ComboBoxRow`/`ToggleRow`/`SectionHeader`) | #27 step 2 | **Yes, W1** | #27's old "AppKit controls + SwiftUI containers" comment is stale after the 2026-11-25 decision; building SwiftUI controls now is double work |
| Panel chrome (enable/name/preset/reset/advanced) | #27 step 3 | **Yes, W1** | Same; #25's mask widget group plugs into this chrome |
| Module order/group UI | #27 step 4 | Yes, after W1 + registry | Data model can land earlier |
| Theme parity | #27 step 5 | Yes, W1 (tokens) + continuous | `ControlMetrics` must exist before panel batches |
| Per-module masks — Core ownership/composite/cache | #25 | **No UI dependency; can start now** | `MaskSpec`, `LayerCompositeDriver`, `IOPModule` mask hook; huge Core change, independent |
| Per-module mask widget group — UI | #25 | **Yes, after #27 chrome (W1)** | Panel chrome is the mount point; do not build it in SwiftUI |
| RAW 9 as manual module — registry/async/decode | #29 | Core/registry yes; panel after W1 | Needs #27 registry + #28 async render |
| RAW 9 module panel | #29 | Yes, after W1 | One more `IOPPanelProvider` |
| Batch paste route in project UI | #28 | **Yes, Library wave** | `SessionBatchApplier` exists; UI route is new AppKit code |
| Thumbnail invalidation after edit/paste | #28 | **Yes, Library wave** | Grid/filmstrip are being rebuilt anyway; do it once |
| Small-tier decode / first-screen JPEG | #28 | No UI dependency | Core decode policy |
| Latest-wins per surface + slider handoff | #28 | **D-H1 façade stays; AppKit slider built W1** | Freeze `InspectorEditSession`/`PipeCoordinator` public faces; #28 changes internals behind them |
| M1/M2/M3 measurements | #26 | Gate every wave | Measure before/after each face flip |
| Decode backend (rawspeed/CIRAW fallback) | #24 | No UI dependency | Start after D1 decision; blockers #30 + LGPL |

**Rule**: anything that is a *control, panel, or window* is built once in AppKit. Anything that is a *Core record, cache key, or decode/render policy* is built in Core and consumed by both stacks during the transition.

---

## §7 Q7 — Order and rationale

**This section is a judgment, not a measurement.** Lane counts are inference from the file sizes in §1 and the 3 h / 35 min-suite constraint; no wave has been piloted.

Assumptions: one heavy job at a time (`machine_single_heavy = true`, `.work/config.toml:90`); one lane = 3 h; full suite ≈ 35 min; build ≈ 5-10 min incremental.

### Candidate A — ledger order (`#24 → #28 core → #31`)

- Lanes: #24 2-3 → #28 core 2-3 → W0+W1 2 → W2-W25 24 → total 30-32.
- Earliest user-visible: decode improvement at **lane 3-4**; first AppKit panel at **lane 6-8**.
- Risk: #24 blocked by #30/LGPL; AppKit foundation (#27/#25/#29) waits; total calendar longest.
- Best if: decode is the top user pain and #30/LGPL are settled.

### Candidate B — AppKit foundation first (`#31 W1-3 + #27 steps 1-3 → #24 → #28 core → #31 rest`)

- Lanes: W0+W1 (2) → #24 2-3 → #28 core 2-3 → W2-W25 24 → total 30-32 including core.
- Earliest user-visible: **lane 2** (AppKit inspector chrome + controls on exposure/temperature/WB), then decode at lane 4-5.
- Risk: AppKit panels built before #28's async render internals change; mitigated by freezing the `InspectorEditSession` façade and `EditorState.instances` read shape. #30 crash can hit full-suite gates.
- Best if: user wants the darktable interaction model soon and #24 is still gated by decisions.

### Candidate C — scaffolding only, then core (`W0 → #24 → #28 core → W1+`)

- Lanes: W0 1 → #24 2-3 → #28 core 2-3 → W1-W25 25 → total 30-32.
- Earliest user-visible: **lane 6-7**.
- Risk: W0 sits unused for 4-6 lanes; interfaces drift.
- Best if: #24 is ready today and decode is the only priority.

**Recommendation: B.** It starts the only track with no external blocker, unblocks #27/#25/#29 UI, and produces a visible control/panel change in ~2 lanes. #24 follows as soon as #30 and LGPL are decided; #28 core follows #24; the remaining #31 waves then land on a stable control layer.

---

## §8 Q8 — Scale and waves

### 8.1 Size

- SwiftUI surface: 123 files / 46,489 lines / 470 `some View` / 191 view structs / 50 panel providers.
- Of 46,489 lines: **40,901 are ported** (W1-W24), **3,203 are deleted legacy** (W25), and **2,385 are not ported** — `LibraryGridModel` 575 + `WorkspaceModel` 584 (models), `NSMenuBridge` 738 + `ShellWindowControllers` 130 + `ShellGraph` 71 + `InspectorState` 287 (already AppKit or non-view).
- Per-lane capacity (inference from 3 h minus 35-40 min suite minus build): **1,000-2,000 lines** for control/canvas-heavy code, **2,000-2,600** for form/list code; 24 porting lanes average **1,704 lines/lane**.
- Minimum: **26 UI lanes** (W0 scaffold + W1-W24 porting + W25 legacy/final, ≈78 h) **plus #24/#28 core 4-6 lanes = 30-32 total**. Realistic with rework and review: **32-36 lanes**.

### 8.2 Wave plan (each row = one omp lane, 3 h target)

| # | Wave | Content | Ported lines | Acceptance draft | Rollback |
|---|---|---|---:|---|---|
| 0 | Scaffold | `AppKit/` tree, root `NSWindowController`/container, `ObservationRelay`, `ControlMetrics`, `NSColor` theme bridge, test host; no face flip | 600-900 new | builds; SwiftUI face unchanged; full suite green; idle CPU unchanged | delete new files |
| 1 | Control kit + template panels | `LMRow`, `LMSliderRow` (D-H1), `LMToggleRow`, `LMComboRow`, `LMSectionHeader`, panel chrome; port `ExposurePanel`, `TemperaturePanel`, `GradeScalarPanels`, `LightamerSlider`, `Theme/*` | 1,187 | AX ids preserved; D-H1 exactly one history item per drag (test); row height pinned; side-by-side vs darktable; full suite | `LIGHTAMER_UI_KIT=swiftui` |
| 2 | Scalar panels A | `AgX`, `Ashift`, `Bilateral`, `Bloom`, `ChannelMixer`, `ChannelMixerRGB`, `ColorContrast`, `Colisa`, `Dehaze`, `Equalizer` | 1,630 | shared control contract; no raw `Slider` in ported files; full suite | flag |
| 3 | Scalar panels B | `FilmicRGB`, `Flip`, `Grain`, `HighpassSoften`, `LocalContrast`, `NLMeans`, `Sharpen`, `Sigmoid`, `Vibrance`, `Velvia`, `Vignette` | 1,465 | same; color/tone panel parity spot-check | flag |
| 4 | Scalar panels C | `SkinSmooth`, `TextOverlay`, `Shadhi`, `Levels`, `ToneCurve`, `CropPanel`, `Hls`, `LensProfileBrowser`, `UprightPanel` | 1,724 | same; curve editor host in `ToneCurve` uses W5 kit | flag |
| 5 | Complex panels A | `ColorWheels` (Trackball), `ColorBalanceRGB`, `ColorZones`, `ToneEqual`, `Monochrome`, `CurveEditorView` | 1,839 | wheel/curve drag = one commit; double-click reset; AX | flag |
| 6 | Complex panels B | `FilmPanelView`, `DenoiseProfile`, `LuminanceColorRange` | 1,898 | solve button; film page; profile curve; one commit per drag | flag |
| 7 | Complex panels C | `LensPanel`, `LutPanel`, `MaskGroups`, `PresetPanel` | 1,665 | LUT encoding pair; mask group; preset apply | flag |
| 8 | Layers/retouch/inspector host | `LayersPanel`, `RetouchPanel`, `InspectorView`, `InspectorRowView`, `IOPPanelProvider` | 1,806 | row toggle/select; layer add/remove; panel dispatch; AX tree | flag |
| 9 | Shell root | `LightamerShell` face + `LightamerApp` (the 2,541-line root shrinks as windows/menu stay AppKit) | 2,800 | phase swap; menu closures; window capture; idle CPU <10% | flag |
| 10 | Editor chrome | `EditorWorkspaceShellView`, `EditorToolRail`, `Filmstrip`, `BackgroundTaskBar`, `VersionsPanel`, `EditorTabRoute` | 1,945 | widths 148/280; filmstrip switch; versions; task bar | flag |
| 11 | Viewport | direct `MTKView` mount, `EditorAreaView`, `EDRControl`, `SoftProofControl`, `StatusBar` | 2,022 | EDR four states; drawable-size → bucket; drop routing; status/toast | flag |
| 12 | Crop + mask overlay | `CropOverlayView`, `CropOverlayHost`, `CropToolPanel`, `MaskOverlayHost` | 1,584 | overlay hit-test; crop handles; mask draw; AX | flag |
| 13 | Mask toolbar + segment | `MaskToolbarView`, `SegmentEditingOverlayHost` | 1,468 | mask create/edit/combine; segment points; sheet mounts | flag |
| 14 | Retouch/liquify/upright/instance | `RetouchOverlayHost`, `LiquifyOverlayHost`, `LiquifyPanel`, `UprightGuidesOverlay`, `InstancePickerOverlay` | 1,388 | brush/stroke; liquify; guides; instance picker | flag |
| 15 | Scopes/nodes/DRT | `ScopePanel`, `EditorNodesPanel`, `DrtPanel`, `EditorNodeHeader` | 1,341 | node drag; scope redraw; DRT page; process migration row | flag |
| 16 | ColorMatch/RawDecode/stack | `ColorMatchPanel`, `RawDecodePanel`, `EditorAdjustmentStack` | 1,068 | match apply; decode panel; stack reorder | flag |
| 17 | Library host | `WorkspaceHostView` (top bar, phase router, sheets, analysis wiring) | 2,224 | open/import/close/cull route; toast; read-only banner | flag |
| 18 | Library root/controller | `ContentView` + `LibraryProjectController` SwiftUI views | 1,799 | welcome/open/create; project conflict; gate arms | flag |
| 19 | Import + grid + cull | `ImportModeDialog`, `ImportProgress`, `EmptyState`, `LibraryGridView`, `CullFaceView` | 1,574 | import modes; selection/open; cull compare; AX | flag |
| 20 | Library inspector/search | `LibraryInspectorView`, `GlobalSearchDialog`, `RelinkSheet`, `LibraryAutoStackDialog` | 1,234 | album inspector; search; relink; stacks | flag |
| 21 | Export A | `ExportInspectorView`, `ExportQueueFaceView` | 1,501 | six formats; queue states; naming preview | flag |
| 22 | Export B + yiyin | `ExportPanelView`, `ExportNamingEditor`, `YiyinPanelView`, `YiyinSheetSizing` | 2,186 | export panel; naming tokens; yiyin ratio drag/persist | flag |
| 23 | Settings | settings shell + ten pages + Catalogs gate page | 1,866 | all pages; persistence; gate page; AX | flag |
| 24 | Windows/dialogs | `PresetManagerWindow`, `McpLauncherPanel`, `EnhanceDialog`, `AIDownloadPrompt`, `PastePartialDialog`, `AdjustmentTransferView` | 1,687 | window lifecycle; sheet env; preset CRUD; parity tests | flag |
| 25 | Legacy delete + SwiftUI removal | delete legacy views/gate/tests; delete `import SwiftUI` / `NSHostingView`; final gates | −3,203 | `rg '^import SwiftUI' App/Sources` = 0; `NSHostingView` = 0; full suite green; all #31 acceptance | revert commit |

Coverage: W1-W24 sum to 40,901 ported lines; W25 deletes 3,203; the remaining 2,385 are listed in §8.1. All 123 inventory files are assigned. W9, W17 and W22 are near the ceiling; split them if the 3 h lane overruns. W11-W14 are the highest gesture/AX risk.

### 8.3 Acceptance template (every wave)

1. `Scripts/machine-guard.sh` before the build; one heavy job only.
2. New app files under `App/Sources` are picked up by the glob (`Project.swift:171`); a new **test** file must be added to its test target's explicit source list, then `tuist generate` as the last action (L041); build.
3. `Scripts/test-direct.sh --bundle App` at minimum; full `--all` before flipping the default of a face.
4. New face assertions: AX identifiers preserved (list the old ids in the wave report), one D-H1 commit test, layout frame test, one negative probe.
5. #26 M1/M2/M3 measured before/after the flip; editor idle CPU <10%; no full-size decode in thumbnails.
6. `grep` gates: no `import SwiftUI` in the wave's ported files; no `NSHostingView` for the face; no raw `Slider(` outside the shared control kit.
7. Record `BUNDLE|` lines and compare executed/skipped/failed to baseline; no silent skip growth.
8. Screenshot of the face at 1440×900 and at the minimum supported window (990×695) for the walkthrough archive.

### 8.4 Rollback unit

One env var, one read point, mirroring `LibraryLegacyGate`:

```swift
enum UIStackGate {
    static let environmentKey = "LIGHTAMER_UI_KIT"   // "swiftui" = old face
    static func isSwiftUIRequested(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool
}
```

The assembly evaluates it once and passes a Bool; view bodies never read `ProcessInfo`. Each wave's new AppKit face sits behind the flag; after acceptance, the default flips and the SwiftUI face stays compiled (but unreachable) until W18.

---

## §9 Q9 — AppKit-specific risks

1. **Layout timing.** SwiftUI's layout is deferred and `onGeometryChange` fires after geometry settles; AppKit `layout()`/`viewDidLayout` runs inside the layout pass. `EditorAreaView.swift:398-407` sends `drawableDidChange` from a geometry change; `EditorMTKView.swift:488` re-blits on `drawableSizeWillChange`. In AppKit, wire `viewDidLayout` → `drawableDidChange`, and guard re-entrancy (layout → render → layout). The yiyin sheet currently uses a **global-coordinate** drag because the sheet re-hangs while resizing (`WorkspaceHostView.swift:1960-1975`); an `NSPanel` resize changes the coordinate space the same way — keep the global-delta model and test it.
2. **Retain cycles.** The app already uses `[weak self]` in the window-controller seams (`LightamerShell.swift:2455-2470`) and `NSMenuBridgeController.shared` holds strong coordinator refs app-long. AppKit controllers must own their observation relay and break it in `deinit`/`viewWillDisappear`; a `withObservationTracking` closure that captures the controller strongly will leak the whole face. Test: mount/unmount the face 100 times, assert `weak` controller becomes nil.
3. **AX tree.** SwiftUI identifiers are load-bearing: `status_toast` (`WorkspaceHostView.swift:2049`, `StatusBar.swift:31`), `inspector.row.<op>.toggle` (`InspectorRowView.swift:80`), `yiyin.sheet.splitter.*`, `shell.workspace.host`. Custom `NSView` overlays are invisible to AX unless they implement `NSAccessibility` (`accessibilityRole`, `accessibilityChildren`, `accessibilityFrame`). The current custom row needed explicit `.accessibilityAction(.default)` to make AXPress work (`InspectorRowView.swift:84-89`) — expect the same class of bug on every custom control.
4. **Keyboard focus ring.** Three real `@FocusState` declarations (4 occurrences incl. one comment): metadata keywords/note (`InspectorView.swift:397`), quick filter (`FilterBarView.swift:33`), cull face (`CullFaceView.swift:29`). The metadata field also disarms bare-key menu shortcuts through `NSMenuBridgeController.noteMetadataFieldFocused` (`InspectorView.swift:433-436`). In AppKit, first responder changes must drive the same enabler; a custom control that becomes first responder without notifying the bridge re-introduces the "typing digits triggers menu" bug. Focus rings on custom rows need `focusRingType = .none` + custom draw, or the system ring will fight the 1 px row.
5. **Dark theme.** Four `.preferredColorScheme(.dark)` sites; no `NSAppearance` code today. Set `NSApp.appearance = NSAppearance(named: .darkAqua)` once; do not rely on `NSColor` dynamic colors for the token palette (tokens are fixed sRGB). `NSVisualEffectView` materials can render differently under EDR/ProMotion; verify the glass surfaces at 100% and 200% scaling.
6. **EDR viewport and view hierarchy.** EDR requires a layer-backed, opaque `CAMetalLayer` with `wantsExtendedDynamicRangeContent = true` and the right colorspace (`EditorMTKView.swift:380-400`). Mounting `MTKView` directly under an `NSView` that is not layer-backed, or adding a sibling overlay that forces a layer-backed superview, can silently disable EDR or change the colorspace. `PipeCoordinator.configure(window:)` currently gets the window from `WindowCapture` (`LightamerApp.swift:233-259`); in AppKit use `viewDidMoveToWindow` directly and keep `EDRHeadroomMonitor` following the window's screen (`EDRHeadroomMonitor.swift:75-90`).
7. **Sheet and window lifecycle.** 30 `.sheet` sites; the M2-8-3 crash was a sheet closure outside the environment injection (`SheetEnvironmentInjectionTests.swift:12-24`). In AppKit, a sheet is a separate `NSWindow` with its own controller; every dependency must be injected explicitly at construction. `ShellWindowControllers` already documents the trap that `NSWindow.contentView` lazily creates a default view, so an `== nil` guard never mounts the hosting view (`ShellWindowControllers.swift:48-56`) — same class of bug when replacing `NSHostingView` with a real view controller.
8. **L057 panel presentation.** `PanelPresentation.present(_:)` is the only allowed file-panel seam; `grep -rn '\.runModal(' App/Sources` = 0. Do not "simplify" back to `runModal` when rewriting call sites. L057-B (AX automation stack-guard crashes) had its batch fix delivered (`L057-DECISIONS.md` D10) but no proof that AX stress can never trigger it again; custom AppKit views increase the AX surface, so keep the AX-stress walkthrough in every wave.
9. **Menu/command parity.** `NSMenuBridge` is 738 lines of hand-built menu + 17-read observation set; AppKit faces must route actions through the same closures, not add a second command path. The `NSMenuParityTests` (677 lines) are the contract.
10. **Test host process identity.** `test-direct.sh` and `open`-launched GUI share the process name `Lightamer`; the M2-7-3 incident killed a test host by mistake. AppKit migration adds more windows/processes; keep the parentage check before killing anything.

---

## §10 Q10 — Legacy faces

### 10.1 Inventory

| Item | Files / lines | Gate |
|---|---|---|
| `SidebarView` | 1,001 | `LibraryLegacyGate` (`ContentView.legacyBody`) |
| `SessionBrowserView` | 658 | same |
| `FilterBarView` | 463 | same |
| `CatalogBrowserView` | 386 | same |
| `CatalogFilterBarView` | 397 | same |
| `CullingView` | 298 | same |
| `ContentView.legacyBody` branch | inside 881-line file | `legacyLibraryEnabled` at `ContentView.swift:203` |
| `SettingsCatalogsPage` | inside `SettingsPages.swift:1584-1738` | `displayedPages(legacyLibraryEnabled:)` (`SettingsPages.swift:103`) |
| Session models | `Session/` 9 files / 2,372 | used by legacy UI + some MCP/tests |
| Catalog models | `Catalog/` 4 files / 1,229 | used by legacy UI + tests |
| Gate tests | `LibraryLegacyGateTests`, `WorkspaceRoutingTests`, `RegistryFilmModuleTests` | App bundle |

### 10.2 Recommendation

**Delete the legacy UI + gate; keep only the Session/Catalog model code that non-UI consumers still need.** Reasons:

- Default product is project-first; the gate is default false (`LibraryPreferences.swift:28-41`) and there is deliberately no Settings switch.
- Porting 3,203 lines of hidden UI to AppKit buys nothing; #31's final acceptance forbids SwiftUI anyway.
- Deletion is not free: `SessionCoordinator.swift:143` references `SessionBrowserView.StackDenoiseMode`, and `CatalogThumbnailRouter.swift:40` references the sidebar's session-management role. Move those types to Core (or delete the handler) before deleting the views; audit `Sessions` bundle (27 test files) and `LibraryLegacyGateTests` / `WorkspaceRoutingTests` in the same wave.
- Keep `Session/`/`Catalog/` models if MCP tools or non-UI tests use them; delete them too if the audit shows no consumer. Do not keep dead models "just in case".

**Decision needed**: delete vs port (recommend delete). If the user wants the QA env channel preserved, the alternative is to port only `SidebarView` + `SessionBrowserView` (the minimum session browse face), not the catalog grid; that is ~1,700 lines of extra AppKit work for a hidden feature.

---

## §11 Not found / not measured

- **Exact per-bundle counts at HEAD**: not run (lane is read-only). Baseline 4618/35/1 and App 1135/6/0 come from #24/#30 comments, not a fresh run. Full-suite wall clock (~2,081 s) comes from F0' logs, not HEAD.
- **AppKit control performance vs SwiftUI**: no prototype; no measurement of `NSSlider` drag latency, `NSCollectionView` scroll, or `NSView.draw` scopes. The gpui prototype in #27 is a design reference, not an AppKit measurement.
- **AX tree differences**: no build, so the exact SwiftUI AX tree vs a hypothetical AppKit tree is not compared. The identifiers and the 66 view-level test shapes are known; the node paths are not.
- **Memory per face**: no measurement; the 8 GB test-host gate and 9 GB GUI watchdog are documented in AGENTS.md but no per-face AppKit numbers exist.
- **#27 prototype code**: not read (it is a gpui-kit prototype, not AppKit); only the issue text and the 2026-11-25 comment were used.
- **#25 mask UI exact widget shape**: read the issue, not darktable's mask widget source; the panel chrome mount point is known, the widget's internal layout is not measured.
- **Localization key counts per face**: not audited; `xcstrings` keys are shared and must survive the port, but no per-face key inventory was produced.
- **Accessibility of custom AppKit overlays**: not prototyped; whether `NSAccessibility` on a transparent overlay can expose mask handles the way SwiftUI does is unverified.
- **Whether `NSSplitViewController` autosave conflicts with the existing `NSSplitView` autosave comment** (`ContentView.swift:182-193`): the current default shell does not use `NSSplitView`; the legacy body claims autosave but no live `NSSplitView` exists in the tree. Not resolved.
