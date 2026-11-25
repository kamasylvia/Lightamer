# AppKit Migration Inventory (HEAD 671762f, 2026-11-25)

Read-only measurement of `App/Sources` at HEAD `671762ffa3a16ac3041d0b0bd60203a803e2328d`
(`2026-11-25 19:59:08 +0800`, `docs(gpui-fast-scout)`). No build, no test run, no product edit.

## Method

```bash
find App/Sources -name '*.swift' | wc -l                         # 218
rg -l '^import SwiftUI' App/Sources | wc -l                      # 123
rg -l '^import SwiftUI' App/Sources | xargs wc -l | tail -1      # 46489
rg -o 'some View' App/Sources | wc -l                            # 470
```

Per-file columns were collected with one `rg -o -F` count per file for each token
(`some View`, `@State`, `@Environment(`, `.sheet(`, `.task`, `Canvas {`, `Gesture(`).
Counts are raw textual occurrences, so comments and doc-comment mentions are included.
The three `@Environment` forms are 151 `Type.self`, 4 `\.dismiss`, 1 `Observable` in a comment
(`rg -o '@Environment\([A-Za-z0-9_]+\.self\)' App/Sources | wc -l` = 151).

## Face definitions

| Face | Files in this inventory |
|---|---|
| `shell_theme` | `UI/Shell/LightamerShell.swift`, `NSMenuBridge.swift`, `ShellWindowControllers.swift`, `ShellGraph.swift`, `UI/LightamerApp.swift`, `UI/Theme/*`, `State/InspectorState.swift` |
| `editor.shell` | `UI/Shell` editor views + `UI/Shell/Nodes/*` (not `WorkspaceHostView`/`WorkspaceModel`, not the four shell files above) |
| `editor.inspector` | `UI/Inspector/*` except `PastePartialDialog.swift` |
| `editor.overlay` | `UI/Overlay/*` |
| `editor.misc` | `EditorAreaView`, `EditorMTKView`, `StatusBar`, `EDRControlView`, `SoftProofControlView`, `InspectorView`, `InspectorRowView`, `EmptyStateView` |
| `library` | `WorkspaceHostView`, `WorkspaceModel`, `ContentView`, `Library/Views/*`, `Library/{ImportModeDialog,ImportProgressView,LibraryGridModel,LibraryProjectController}` |
| `export` | `Export/*` |
| `settings` | `UI/SettingsView`, `Settings/SettingsPages` |
| `yiyin` | `Yiyin/*` |
| `app_windows` | `PresetManagerWindow`, `McpLauncherPanelView`, `AIDownloadPrompt`, `Views/EnhanceDialog`, `Inspector/PastePartialDialog` |
| `legacy` | `SidebarView`, `SessionBrowserView`, `FilterBarView`, `CatalogBrowserView`, `CatalogFilterBarView`, `CullingView` (all behind `LibraryLegacyGate`, default off) |

## Aggregate

| Face | Files | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas-bearing files | Gesture-bearing files |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| editor.shell | 15 | 5,847 | 109 | 40 | 33 | 1 | 7 | 3 | 2 |
| editor.inspector | 50 | 11,548 | 104 | 43 | 31 | 1 | 2 | 7 | 5 |
| editor.overlay | 10 | 4,204 | 25 | 27 | 19 | 1 | 2 | 4 | 6 |
| editor.misc | 8 | 2,694 | 17 | 7 | 22 | 0 | 4 | 0 | 1 |
| library | 13 | 7,907 | 72 | 56 | 23 | 11 | 18 | 0 | 3 |
| export | 4 | 2,656 | 39 | 13 | 10 | 2 | 1 | 0 | 0 |
| settings | 2 | 1,866 | 28 | 21 | 3 | 0 | 1 | 0 | 0 |
| yiyin | 2 | 1,031 | 10 | 6 | 0 | 0 | 1 | 0 | 0 |
| app_windows | 5 | 1,318 | 17 | 14 | 4 | 1 | 3 | 0 | 1 |
| legacy | 6 | 3,203 | 48 | 40 | 11 | 9 | 4 | 0 | 2 |
| shell_theme | 8 | 4,215 | 1 | 3 | 0 | 4 | 7 | 0 | 0 |
| **Total** | **123** | **46,489** | **470** | **270** | **156** | **30** | **50** | **14** | **20** |

`@State` in SwiftUI-importing files = 270; the whole `App/Sources` grep is 277 (7 more in
non-SwiftUI-importing files/comments). `.task` in SwiftUI-importing files = 50; whole tree = 61
(11 more in comments or non-SwiftUI files, e.g. `MCP/McpServerController.swift` doc text).

Editor face (shell + inspector + overlay + misc) = **24,293 lines, 52.2% of the SwiftUI surface**.
Library = 7,907 (17.0%). The rest = 14,289 (30.7%).

## Full file table

### shell_theme

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/Shell/LightamerShell.swift` | 2541 | 1 | 0 | 0 | 4 | 7 | 0 | 0 |
| `UI/Shell/NSMenuBridge.swift` | 738 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `State/InspectorState.swift` | 287 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/LightamerApp.swift` | 259 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Shell/ShellWindowControllers.swift` | 130 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Theme/ThemeTokens.swift` | 110 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Theme/LightamerColors.swift` | 79 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Shell/ShellGraph.swift` | 71 | 0 | 2 | 0 | 0 | 0 | 0 | 0 |

### editor.shell

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/Shell/FilmPanelView.swift` | 1124 | 24 | 2 | 3 | 1 | 2 | 1 | 0 |
| `UI/Shell/Nodes/EditorNodesPanelView.swift` | 573 | 15 | 8 | 0 | 0 | 0 | 1 | 4 |
| `UI/Shell/EditorAdjustmentStackView.swift` | 521 | 8 | 6 | 5 | 0 | 0 | 0 | 0 |
| `UI/Shell/DrtPanelView.swift` | 405 | 13 | 4 | 0 | 0 | 0 | 0 | 0 |
| `UI/Shell/FilmstripView.swift` | 378 | 4 | 2 | 1 | 0 | 1 | 0 | 1 |
| `UI/Shell/AdjustmentTransferView.swift` | 369 | 10 | 2 | 3 | 0 | 0 | 0 | 0 |
| `UI/Shell/EditorToolRailView.swift` | 364 | 6 | 1 | 5 | 0 | 0 | 0 | 0 |
| `UI/Shell/VersionsPanelView.swift` | 335 | 5 | 3 | 3 | 0 | 0 | 0 | 0 |
| `UI/Shell/EditorTabRoute.swift` | 322 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Shell/BackgroundTaskBarView.swift` | 310 | 5 | 0 | 2 | 0 | 0 | 0 | 0 |
| `UI/Shell/RawDecodePanelView.swift` | 295 | 4 | 7 | 1 | 0 | 1 | 0 | 0 |
| `UI/Shell/ColorMatchPanelView.swift` | 252 | 6 | 2 | 3 | 0 | 0 | 0 | 0 |
| `UI/Shell/ScopePanelView.swift` | 243 | 3 | 3 | 1 | 0 | 1 | 2 | 0 |
| `UI/Shell/EditorWorkspaceShellView.swift` | 236 | 5 | 0 | 4 | 0 | 2 | 0 | 0 |
| `UI/Shell/EditorNodeHeaderView.swift` | 120 | 1 | 0 | 2 | 0 | 0 | 0 | 0 |

### editor.inspector

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/Inspector/LayersPanelView.swift` | 663 | 6 | 2 | 10 | 0 | 0 | 0 | 0 |
| `UI/Inspector/LensPanelView.swift` | 656 | 1 | 11 | 0 | 0 | 1 | 0 | 0 |
| `UI/Inspector/ColorWheelsPanelView.swift` | 496 | 6 | 1 | 0 | 0 | 0 | 1 | 2 |
| `UI/Inspector/LutPanelView.swift` | 440 | 4 | 5 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/GradeScalarPanels.swift` | 434 | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ColorBalanceRGBPanelView.swift` | 428 | 3 | 1 | 0 | 0 | 0 | 1 | 2 |
| `UI/Inspector/MaskGroupsPanelView.swift` | 418 | 4 | 2 | 6 | 0 | 1 | 0 | 0 |
| `UI/Inspector/DenoiseProfilePanelView.swift` | 415 | 2 | 2 | 0 | 0 | 0 | 1 | 0 |
| `UI/Inspector/ChannelMixerRGBPanelView.swift` | 404 | 4 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/LuminanceColorRangePanelView.swift` | 359 | 5 | 2 | 3 | 0 | 0 | 0 | 0 |
| `UI/Inspector/RetouchPanelView.swift` | 327 | 9 | 1 | 2 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ToneEqualPanelView.swift` | 308 | 2 | 0 | 0 | 0 | 0 | 1 | 0 |
| `UI/Inspector/AshiftPanelView.swift` | 299 | 1 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/TemperaturePanelView.swift` | 238 | 1 | 0 | 1 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ColorZonesPanelView.swift` | 237 | 2 | 1 | 0 | 0 | 0 | 1 | 0 |
| `UI/Inspector/LiquifyPanelView.swift` | 236 | 4 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/HlsPanelView.swift` | 235 | 2 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/FilmicRGBPanelView.swift` | 231 | 4 | 0 | 1 | 0 | 0 | 0 | 0 |
| `UI/Inspector/IOPPanelProvider.swift` | 227 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/MonochromePanelView.swift` | 213 | 2 | 0 | 0 | 0 | 0 | 1 | 2 |
| `UI/Inspector/SkinSmoothPanelView.swift` | 212 | 1 | 1 | 3 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ToneCurvePanelView.swift` | 208 | 1 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/VignettePanelView.swift` | 199 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/CropPanelView.swift` | 193 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/LightamerSlider.swift` | 192 | 1 | 3 | 0 | 0 | 0 | 0 | 2 |
| `UI/Inspector/ShadhiPanelView.swift` | 188 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/UprightPanelView.swift` | 184 | 2 | 0 | 3 | 0 | 0 | 0 | 0 |
| `UI/Inspector/TextOverlayPanelView.swift` | 183 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/HighpassSoftenPanelView.swift` | 175 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/SigmoidPanelView.swift` | 175 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/LensProfileBrowser.swift` | 171 | 1 | 4 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/AgXPanelView.swift` | 169 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/CurveEditorView.swift` | 157 | 2 | 1 | 0 | 0 | 0 | 1 | 3 |
| `UI/Inspector/PresetPanelView.swift` | 151 | 3 | 1 | 2 | 1 | 0 | 0 | 0 |
| `UI/Inspector/LevelsPanelView.swift` | 150 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ChannelMixerPanelView.swift` | 144 | 1 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ExposurePanelView.swift` | 134 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/NLMeansPanelView.swift` | 134 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/BilateralPanelView.swift` | 113 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ColorContrastPanelView.swift` | 113 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/LocalContrastPanelView.swift` | 109 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/GrainPanelView.swift` | 105 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/SharpenPanelView.swift` | 104 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/BloomPanelView.swift` | 102 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/DehazePanelView.swift` | 102 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/EqualizerPanelView.swift` | 100 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/ColisaPanelView.swift` | 84 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/VelviaPanelView.swift` | 81 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/FlipPanelView.swift` | 80 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/Inspector/VibrancePanelView.swift` | 72 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |

### editor.overlay

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/Overlay/MaskOverlayHost.swift` | 907 | 2 | 4 | 4 | 0 | 0 | 1 | 3 |
| `UI/Overlay/MaskToolbarView.swift` | 903 | 8 | 7 | 6 | 1 | 2 | 0 | 0 |
| `UI/Overlay/SegmentEditingOverlayHost.swift` | 565 | 4 | 3 | 4 | 0 | 0 | 1 | 2 |
| `UI/Overlay/UprightGuidesOverlay.swift` | 447 | 3 | 1 | 3 | 0 | 0 | 0 | 1 |
| `UI/Overlay/CropOverlayView.swift` | 406 | 1 | 4 | 0 | 0 | 0 | 0 | 2 |
| `UI/Overlay/RetouchOverlayHost.swift` | 330 | 2 | 5 | 2 | 0 | 0 | 1 | 2 |
| `UI/Overlay/LiquifyOverlayHost.swift` | 245 | 2 | 1 | 0 | 0 | 0 | 1 | 4 |
| `UI/Overlay/CropOverlayHost.swift` | 168 | 1 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Overlay/InstancePickerOverlay.swift` | 130 | 1 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/Overlay/CropToolPanelView.swift` | 103 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |

### editor.misc

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/EditorMTKView.swift` | 919 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| `UI/EditorAreaView.swift` | 828 | 4 | 3 | 10 | 0 | 3 | 0 | 2 |
| `UI/InspectorView.swift` | 489 | 6 | 3 | 7 | 0 | 1 | 0 | 0 |
| `UI/SoftProofControlView.swift` | 129 | 2 | 0 | 2 | 0 | 0 | 0 | 0 |
| `UI/InspectorRowView.swift` | 100 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `UI/EDRControlView.swift` | 87 | 2 | 0 | 2 | 0 | 0 | 0 | 0 |
| `UI/EmptyStateView.swift` | 83 | 1 | 1 | 0 | 0 | 0 | 0 | 0 |
| `UI/StatusBar.swift` | 59 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |

### library

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/Shell/WorkspaceHostView.swift` | 2224 | 18 | 30 | 11 | 7 | 9 | 0 | 3 |
| `Library/LibraryProjectController.swift` | 918 | 2 | 0 | 0 | 1 | 0 | 0 | 0 |
| `UI/ContentView.swift` | 881 | 7 | 6 | 10 | 2 | 0 | 0 | 0 |
| `Library/Views/LibraryGridView.swift` | 609 | 5 | 3 | 0 | 1 | 1 | 0 | 1 |
| `UI/Shell/WorkspaceModel.swift` | 584 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| `Library/Views/LibraryInspectorView.swift` | 581 | 12 | 0 | 1 | 0 | 0 | 0 | 0 |
| `Library/LibraryGridModel.swift` | 575 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `Library/Views/CullFaceView.swift` | 456 | 9 | 3 | 0 | 0 | 5 | 0 | 1 |
| `Library/ImportModeDialog.swift` | 356 | 6 | 4 | 1 | 0 | 2 | 0 | 0 |
| `Library/Views/RelinkSheetView.swift` | 284 | 6 | 4 | 0 | 0 | 0 | 0 | 0 |
| `Library/Views/GlobalSearchDialog.swift` | 270 | 5 | 3 | 0 | 0 | 0 | 0 | 0 |
| `Library/Views/LibraryAutoStackDialog.swift` | 99 | 1 | 2 | 0 | 0 | 1 | 0 | 0 |
| `Library/ImportProgressView.swift` | 70 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |

### export

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `Export/ExportInspectorView.swift` | 1282 | 13 | 6 | 4 | 0 | 1 | 0 | 0 |
| `Export/ExportPanelView.swift` | 835 | 14 | 2 | 6 | 1 | 0 | 0 | 0 |
| `Export/ExportNamingEditor.swift` | 320 | 8 | 5 | 0 | 1 | 0 | 0 | 0 |
| `Export/ExportQueueFaceView.swift` | 219 | 4 | 0 | 0 | 0 | 0 | 0 | 0 |

### settings

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `Settings/SettingsPages.swift` | 1738 | 27 | 20 | 2 | 0 | 1 | 0 | 0 |
| `UI/SettingsView.swift` | 128 | 1 | 1 | 1 | 0 | 0 | 0 | 0 |

### yiyin

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `Yiyin/YiyinPanelView.swift` | 745 | 10 | 6 | 0 | 0 | 1 | 0 | 0 |
| `Yiyin/YiyinSheetSizing.swift` | 286 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

### app_windows

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/PresetManagerWindow.swift` | 422 | 5 | 10 | 2 | 1 | 0 | 0 | 1 |
| `UI/McpLauncherPanelView.swift` | 293 | 4 | 1 | 0 | 0 | 1 | 0 | 0 |
| `UI/Views/EnhanceDialog.swift` | 271 | 5 | 1 | 1 | 0 | 1 | 0 | 0 |
| `UI/AIDownloadPrompt.swift` | 177 | 1 | 0 | 1 | 0 | 1 | 0 | 0 |
| `UI/Inspector/PastePartialDialog.swift` | 155 | 2 | 2 | 0 | 0 | 0 | 0 | 0 |

### legacy

| File | Lines | `some View` | `@State` | `@Environment` | `.sheet` | `.task` | Canvas | Gesture |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `UI/SidebarView.swift` | 1001 | 15 | 12 | 6 | 0 | 1 | 0 | 0 |
| `UI/SessionBrowserView.swift` | 658 | 3 | 14 | 2 | 7 | 1 | 0 | 1 |
| `UI/FilterBarView.swift` | 463 | 10 | 4 | 1 | 1 | 0 | 0 | 0 |
| `UI/CatalogFilterBarView.swift` | 397 | 10 | 4 | 0 | 1 | 0 | 0 | 0 |
| `UI/CatalogBrowserView.swift` | 386 | 7 | 4 | 2 | 0 | 1 | 0 | 1 |
| `UI/CullingView.swift` | 298 | 3 | 2 | 0 | 0 | 1 | 0 | 0 |

## Non-SwiftUI files inside these faces

Models/coordinators that a face owns but that do not import SwiftUI (they survive a UI rewrite):
`UI/Shell/WorkspaceModel.swift` (584), `FilmPanelModel.swift` (1,237), `DrtPanelModel.swift` (281),
`ColorMatchPanelModel.swift` (332), `NodesPanelModel.swift` (171), `NodeCanvasGeometry.swift` (186),
`MenuCommandSet.swift` (86), `FinderReveal.swift` (77); `Library/*` non-SwiftUI files
(`LibraryGridModel` is SwiftUI-importing but has 0 `some View`); `State/` 24 files / 10,956 lines;
`Session/` 9 files / 2,372; `Catalog/` 4 files / 1,229; `MCP/` 18 files.

## Coupling points (cross-face references)

`@Environment` reads, counted by face (distinct types):

| Face | Coordinator types read |
|---|---|
| editor.inspector | `EditorState` 10, `PipeCoordinator` 8, `LayerEditingState` 8, `InspectorState` 3, `PresetsStore`/`PresetController` 1 each |
| editor.shell | `EditorState` 9, `AgentControlCoordinator` 7, `PipeCoordinator` 6, `LayerEditingState` 3, `InspectorState` 3, `VersionCoordinator` 3, `ColorMatchService` 1 |
| editor.overlay | `EditorState` 5, `LayerEditingState` 4, `PipeCoordinator` 4, `ViewportState` 2, `AIDownloadModel`/`DepthMaskService`/`InspectorState` 1 each |
| editor.misc | `PipeCoordinator` 4, `EditorState` 4, `ViewportState` 3, `InspectorState` 2, `LayerEditingState` 2, `BeforeAfterState` 2, plus 5 one-off types |
| library | `EditorState` 4, `InspectorState` 4, `AgentControlCoordinator` 3, `ExportState` 3, `PipeCoordinator` 3, plus 5 one-off types |
| export | `ExportState` 2, `EditorState` 2, `PipeCoordinator` 2, `SessionState`/`PresetsStore`/`InspectorState` 1 each |
| settings | `LibraryProjectController`, `PipeCoordinator`, `CatalogPreferencesModel` 1 each |
| legacy | `SessionState` 3, `CatalogTreeModel` 2, `CatalogPreferencesModel` 2, plus 4 one-off types |

Hard cross-face calls (not environment):
- `WorkspaceHostView` owns the phase router (`library`/`editor`/`cull`) and constructs the editor face.
- `ContentView` owns the legacy body and the `ProjectWorkspaceFace`; `ContentView.swift` also carries `ContentView.BrowserMode` and the toolbar.
- `ExportInspectorView` is mounted from `InspectorView` when `inspectorState.exportPageActive`; `FilmPanelView` when `filmPageActive`.
- `WorkspaceHostView` opens the yiyin sheet and hands it `editorState`/`pipeCoordinator`; the sheet drag handling is in `WorkspaceHostView.swift:1920-1980`.
- `InspectorState.registerDefaultProviders()` registers 50 `IOPPanelProvider`s; panels are selected from `EditorState.instances`, so the Inspector panel list is already instance-driven (the label switch in `InspectorView.swift:293-340` is still hand-written).
