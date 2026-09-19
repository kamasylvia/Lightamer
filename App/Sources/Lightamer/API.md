# Lightamer (app) — API Contract

> D-03c module contract index. **The app target has NO public surface** —
> it is the top of the dependency DAG (`LightamerCore` ← `LightamerIOP` ←
> app); nothing imports it. `LightamerUITests` drives the RUNNING app via
> XCUITest launcher/accessibility APIs, never via `import`. All app code
> is `internal` by default.

## Subsystem directories (all internal)

| Directory | Contents |
|---|---|
| `UI/` | SwiftUI shell: `LightamerApp` (entry), `ContentView` (three-column NavigationSplitView + toolbar + alerts), `SidebarView`, `EditorAreaView` + `EditorMTKView` (NSViewRepresentable MTKView blit), `EmptyStateView`, `InspectorView`, `StatusBar`, `FileOpenHelper`, `Theme/LightamerColors` |
| `State/` | The four D-03b isolated `@Observable` state objects (below) |
| `Session/` | Capture One Session model — Phase 9 (empty) |
| `Export/` | Export pipeline — Phase 11 (empty) |
| `Yiyin/` | 印框/水印 panel — Phase 10 (empty) |
| `AI/` | Vision masks — Phase 7 (empty) |

## D-03b state-isolation contract (the load-bearing app rule)

Four separate `@Observable` objects — **no god-object**:

| State object | Owns | Does NOT own |
|---|---|---|
| `SessionState` | current session folder, recent list, watch status | image data, layers, inspector |
| `EditorState` | current image (`DecodedImage`), `LayerStack`, `history` (`HistoryStack`) + live `instances` records (02-05; D-03b history ownership), `displayTexture`, decode/error lifecycle, in-flight decode task | export queue, inspector selection |
| `ExportState` | export queue, recipes, progress | image data, inspector |
| `InspectorState` | selected iop panel, expand state, metadata display | image data, layers |

Rules:
- Views inject ONLY the state object they need.
- States hold NO references to each other; cross-state coordination flows
  through `ContentView` (RESEARCH §7c). A true coordinator (Observable/
  actor CommandBus) may be introduced in Phase 2+ — never state→state refs.
- `LightamerApp` owns all four via `@State` (never singletons) and owns
  the `RAWDecoder` actor + `MetalContext` (injected, not global).

## Cross-module touch points (all via Core/IOP `public` surface)

- `EditorState.load(url:decoder:metal:logger:)` → `RAWDecoder.decode` →
  `PipeCoordinator.load` (02-03) → `RenderPipeline.process` →
  `displayTexture` (float32 linear-Rec2020).
- `PipeCoordinator` (02-03/02-05, internal) is the ONLY render producer
  and the ONLY writer of `displayTexture` (D-X1). Editing controls
  consume its D-H1 trio — `beginContinuousEdit` /
  `setLiveParams(_:)` / `commitContinuousEdit(label:)` (one drag = ONE
  history item) — and the HIST-02 entries `undo()` / `redo()` /
  `jumpToHistory(_:)`; `EditorState` owns the stack + records, the
  coordinator re-materializes boxes from them.
- `LightamerApp.task` registers the IOP metallib once:
  `metalContext.registerDefaultLibrary(in: PassthroughKernel.metalBundle)`.
- `EditorMTKView` consumes `MetalContext.device` + the `displayTexture`.

## Accessibility contract (drives `AppLaunchTests`)

String-Catalog keys with stable labels, queried by XCUITest (en/zh):
`editor_viewport` ("Image viewport"), `sessions` ("Sessions"),
`a11y_inspector_label` ("Inspector"), `a11y_empty_state_label` (the D-11
empty-state prompt). Changing these labels is a UI-test contract change.

## Code-review enforcement

A `public` declaration in the app target is always a mistake — reject it
in review. New subsystem directories (Session/Export/Yiyin/AI) stay
internal; anything they need from Core/IOP goes through the published
surfaces in `LightamerCore/API.md` / `LightamerIOP/API.md`.
