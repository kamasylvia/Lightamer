---
phase: 1
plan: 01
status: complete
completed: 2026-09-16
duration: ~2h (single executor session)
commits:
  - db57559 feat(01-01): add Tuist Project.swift with 5-target module DAG
  - 83454a7 feat(01-01): add public AppError + WorkingSpace to LightamerCore/Foundation
  - dba4d31 feat(01-01): add four isolated @Observable state objects (D-03b)
  - c24b4a4 feat(01-01): add color tokens + String Catalog (en source + zh)
  - 7791cee feat(01-01): build SwiftUI shell per UI-SPEC (three columns, toolbar, menus)
  - 47dc3fa feat(01-01): land module skeleton, assets; fix manifest for Tuist 4.208/macOS 27 SDK
  - 52b26b0 fix(01-01): single-line column-width modifiers in ContentView
---

# Plan 01-01 — Summary

Tuist Project.swift (5 targets, module DAG) + SwiftUI shell + isolated state objects.
Tracer vertebra "tuist generate → app launches → empty shell": **achieved** (app builds, launches,
holds the four isolated state objects, renders the three-column chrome; visual confirmation of the
running window is the single manual remainder — see "Deviations" #4).

## What was built (per task)

- **01-01-01 checkpoint:decision** — All nine one-way/costly locks affirmed from CONTEXT.md
  (D-02/D-02a multi-target+Tuist, D-03 DAG, D-05 Bundle ID, D-07 three-column shell, D-25 AppError,
  D-33 Swift 6 strict concurrency, D-35+D-03b state isolation, macOS 27 floor, D-04 resources).
  No re-litigation, no user escalation needed.
- **01-01-02 Project.swift** — Five Tuist targets (`LightamerCore` framework ← `LightamerIOP`
  framework ← `Lightamer` app; `LightamerTests` → Core+IOP; `LightamerUITests` → app), all
  `deploymentTargets: .macOS("27.0")`, `SWIFT_STRICT_CONCURRENCY: complete`, hardened runtime,
  app bundle ID `com.kamasylvia.lightamer` with `CFBundleDocumentTypes` (Viewer for
  camera-raw-image/heic/jpeg/png/tiff/webp), shared `Lightamer` scheme (debug run / unit+UI test /
  release archive). `.gitignore` per Tuist convention (`*.xcodeproj` never committed).
- **01-01-03 Foundation types** — `AppError` (public enum, `Error & LocalizedError`, 7 cases,
  `init(_ error:)` bridge, `errorDescription` per UI-SPEC error copy, shared `os.Logger`) and
  `WorkingSpace` (linear Rec2020 `CGColorSpace`, `.rgba32Float`, `bytesPerPixel: 16`) — both
  `public` in `LightamerCore/Sources/Foundation/`.
- **01-01-04 State isolation** — Four separate `@Observable @MainActor final class` files under
  `App/Sources/Lightamer/State/` (`SessionState`, `EditorState`, `ExportState`, `InspectorState`),
  zero cross-references; `EditorState.load(url:)` cancels any in-flight `decodeTask` (D-34) and
  carries the marked Plan 02 `RAWDecoder` integration point.
- **01-01-05 Design tokens** — `LightamerColors` (neutral-0..7 hex literals from the UI-SPEC dark
  table, 4 text tokens, semantic surfaces, system accent/danger/warning/success) +
  `Resources/Localizable.xcstrings` (48 keys, `sourceLanguage: en`, `zh` at parity).
- **01-01-06 Shell** — `LightamerApp` (@main, four `@State` owners, `.environment` injection,
  `.preferredColorScheme(.dark)`, full menu bar incl. Cmd+O → `EditorState.load`, View-menu toggles
  via `@FocusedBinding`, Settings scene) · `ContentView` (three-column `NavigationSplitView` with
  UI-SPEC widths 180/240/320 + 240/320/460, `.balanced`, three `layout.*` `@AppStorage` keys,
  toolbar per spec — active: sidebar/Open/inspector toggles; disabled: import/export/before-after/
  fit/100% — blocking `.alert` on `editorState.decodeError`) · `SidebarView` / `EditorAreaView` /
  `InspectorView` (each injects exactly one state object; 200ms `.easeInOut` empty↔loaded
  transition; 22pt `StatusBar` with monospaced Ready/Decoding) · `EmptyStateView` (hero
  `folder.badge.plus`, catalog-keyed copy, `.onDrop` file-URL → load, accent border when targeted,
  VoiceOver labels) · `FileOpenHelper` (shared NSOpenPanel wrapper; folder→first-image Phase 1
  fallback per UI-SPEC drag rule 2).
- **01-01-07 Generate + build + launch** — Module `.gitkeep` skeleton (Core Decode/Metal/Pipe/
  Layers, IOP Sources, app Session/Export/Yiyin/AI, both test targets), `Resources/Assets.xcassets`
  with single-size 1024 AppIcon, `tuist generate` (exit 0), DAG verified in `project.pbxproj`
  (acyclic, exactly the five targets), `xcodebuild build` exit 0, app launched (on-screen
  1412×800 window, process alive, no crash reports, no error/fault log entries), module-boundary
  spot check passed (scratch Core-internal enum referenced from the app target →
  `cannot find 'BoundaryProbeInternal' in scope` → probe removed, clean rebuild).

## Key files created

- `Project.swift`, `Tuist.swift`, `.gitignore`
- `LightamerCore/Sources/Foundation/AppError.swift`, `WorkingSpace.swift`
- `App/Sources/Lightamer/State/{SessionState,EditorState,ExportState,InspectorState}.swift`
- `App/Sources/Lightamer/UI/{LightamerApp,ContentView,SidebarView,EditorAreaView,EmptyStateView,InspectorView,StatusBar,FileOpenHelper}.swift`
- `App/Sources/Lightamer/UI/Theme/LightamerColors.swift`
- `Resources/Localizable.xcstrings`, `Resources/Assets.xcassets/` (+ AppIcon.appiconset)
- Module `.gitkeep` skeleton per plan `files_modified`

## Deviations from plan (with reasons)

1. **`Tuist/Config.swift` → root `Tuist.swift`.** Tuist 4.208.0 explicitly deprecates
   `Tuist/Config.swift` ("Rename Tuist/Config.swift to Tuist.swift at the root"). Same content
   (minimal `Config()` + Phase 11 libwebp/libavif comment).
2. **Manifest API deltas (same semantics).** Tuist 4.208: `Destination.mac` (not `.macOS`),
   `TestAction.targets(...)` with string-literal `TestableTarget`s, no project-wide
   `deploymentTargets` in `Project.Options` (per-target `.macOS("27.0")` is the single source —
   the RESEARCH §1 consistency gotcha is still satisfied on every target), scheme argument order.
3. **`WorkingSpace.colorSpace` spelling.** `CGColorSpace.rec2020Linear` no longer exists in the
   macOS 27 SDK — renamed to `CGColorSpace.linearITUR_2020` (linear Rec2020, same space, FOUND-02
   intact).
4. **Visual launch confirmation is indirect.** The physical display is locked in this session, so
   `screencapture` produces black frames. Verified instead: window exists on screen
   (`CGWindowList`: 1412×800 "Lightamer"), process stays alive, zero crash reports, zero
   error/fault log entries. The VALIDATION.md manual row (three columns visible, forced dark,
   empty-state prompt) remains a 30-second human check on first unlocked launch.
5. **Small helper file beyond the plan list:** `UI/FileOpenHelper.swift` — one NSOpenPanel wrapper
   shared by the menu, toolbar, and empty-state CTA (avoids triple duplication).
6. **Close Session menu placement.** SwiftUI `CommandGroupPlacement` has no `.closeItem`; the
   disabled Close Session item sits in the File command group after Open Recent instead.
7. **Inspector toggle semantics.** Per the UI-SPEC table the toggle maps `.all ↔ .detailOnly`
   (which collapses to the inspector alone, since no enum value hides *only* the detail column of a
   three-column split). Sidebar toggle maps `.all ↔ .doubleColumn` (content + detail stay visible)
   — matches both spec and function. Revisit inspector hiding via `.inspector()` in Phase 3 when
   real iop panels land.

## Build verification output summary

- `tuist generate` → exit 0, `Lightamer.xcodeproj` + `Lightamer.xcworkspace`, targets: exactly
  `LightamerCore`, `LightamerIOP`, `Lightamer`, `LightamerTests`, `LightamerUITests`.
- DAG (from `project.pbxproj` `PBXTargetDependency`): app → {Core, IOP}; IOP → Core;
  Tests → {Core, IOP}; UITests → app. Acyclic.
- `xcodebuild build -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS'
  -configuration Debug` → `** BUILD SUCCEEDED **`, zero errors, one benign warning
  (`DEFINES_MODULE` umbrella-header note on the still-empty `LightamerIOP`; disappears when Plan 04
  adds Passthrough).
- Source assertions: all plan acceptance greps pass (Bundle ID, `SWIFT_STRICT_CONCURRENCY`,
  `.macOS("27.0")` × 5, AppError cases, `linearITUR_2020` + `.rgba32Float` public, four
  `@Observable @MainActor final class` state files with no cross-references, per-view single-state
  injection, no `@StateObject`/`@ObservedObject` usage, no hardcoded user-facing Chinese,
  `*.xcodeproj` untracked).

## Handoff to downstream plans

- Plan 02: replace the marked stub in `EditorState.load(url:)` with `RAWDecoder.decode`;
  fill `LightamerCore/Sources/Decode/`.
- Plan 03: replace the loaded branch in `EditorAreaView` with `EditorMTKView`; `WorkingSpace` is
  the CIContext working color space.
- Plan 04: fill `LightamerCore/Sources/{Pipe,Layers}/` + `LightamerIOP/Sources/`.
- Plan 06: `LightamerTests` / `LightamerUITests` targets are already declared and buildable.
