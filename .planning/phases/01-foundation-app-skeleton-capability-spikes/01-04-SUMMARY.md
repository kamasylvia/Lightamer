---
phase: 1
plan: 04
status: complete
completed: 2026-09-16
duration: two executor sessions (first completed tasks 01-04-01..05 + 4 commits, stalled mid-wiring; second session assessed state, finished 01-04-06..08, verified, summarized)
commits:
  - a6ca69b feat(01-04): add IOPModule protocol + IOPFlags/IOPColorspace/ROI/IOPiece pipe contract (FOUND-03)
  - 4c72bc6 feat(01-04): add V50Order — verbatim port of Darktable iop_order.c:298-415 v50_order (93 entries)
  - 7934417 feat(01-04): add Layer skeleton (D-03a) — protocol Layer, LayerKind, BlendMode (blend.h raw values), LayerStack, BackgroundLayer
  - d7c3684 feat(01-04): refactor Passthrough into full PassthroughModule: IOPModule reference conformance
  - 5550fc7 fix(01-04): absorb macOS 27 SDK changes in PassthroughModule process (blit copy signatures, non-throwing completed)
  - 4b3c918 feat(01-04): add PixelPipe skeleton (internal, layer-aware) + RenderPipeline public render bridge
  - f8e0975 feat(01-04): run decode through no-op pixelpipe in EditorState (LayerStack + displayTexture)
  - 328e727 test(01-04): stage IOPModule, V50Order and LayerSkeleton test stubs (Plan 06 fills)
---

# Plan 01-04 — Summary

IOPModule contract (Core/Pipe) + V50Order (Core/Foundation) + Layer skeleton
(Core/Layers, D-03a) + PassthroughModule (LightamerIOP) + PixelPipe skeleton
(Core/Pipe, internal) + app wiring. **Success criterion #3 is met at the
pipeline level**: File → decode → `LayerStack(baseLayer: BackgroundLayer())`
→ `PixelPipe` (no-op base-layer traversal) → `displayTexture` →
`EditorMTKView` blit, verified **headless 13/13 PASS** on the real GPU
(Apple M4) through the public surface. The on-screen MTKView eyeball check
carries the same manual remainder as Plans 01/02 (screen locked in these
sessions — the blit path itself was byte-verified headlessly in Plan 03).

## What was built (per task)

- **01-04-01 checkpoint:decision** — All eight locks affirmed (FOUND-03
  protocol shape with `associatedtype Params: Codable & Hashable`; supporting
  Pipe types; verbatim V50Order port; D-03a Layer skeleton all-public; C1
  layer model; NO `iopChain`/`mask` on `Layer` in Phase 1; BlendMode raw
  values frozen now; PixelPipe `internal`, base-layer-only scope). No
  re-litigation.
- **01-04-02 IOPModule + contract types** (a6ca69b) — `public protocol
  IOPModule` (`LightamerCore/Sources/Pipe/IOPModule.swift`): `associatedtype
  Params: Codable & Hashable`, `opName`/`iopOrder`/`flags`/
  `defaultColorspace` statics, `reloadDefaults`/`commitParams`/
  `modifyROIOut`/`modifyROIIn`/`process(input:output:roiIn:roiOut:piece:
  metal:) async throws`. Supporting: `IOPFlags` (OptionSet, 6 flags from
  `imageop.h:84-110`), `IOPColorspace` (4 cases), `ROI` (x/y/w/h/scale,
  Equatable+Sendable), `IOPiece` + `IOPBufferDesc` (paramsHash / dscIn /
  dscOut / uniforms buffer).
- **01-04-03 V50Order** (4c72bc6) — `public enum V50Order`
  (`entries: [(opName: String, order: Float)]`, `order(for:)`),
  verbatim port of `iop_order.c:298-415`: **93 entries** (plan's ~76 estimate
  undercounted; the verbatim source wins), positions 1.0 `rawprepare` →
  78.0 `gamma`, deliberate 28.5 cluster intact (channelmixerrgb / diffuse /
  censorize / negadoctor / blurs / primaries).
- **01-04-04 Layer skeleton (D-03a)** (7934417) — `public protocol Layer:
  Sendable, Identifiable` (id/name/isVisible/opacity/blendMode/enabled/kind;
  **no `iopChain`/`mask`** — Phase 6), `LayerKind { background, adjustment }`,
  `BlendMode: Int` with the frozen Darktable `blend.h:44-91` raw values
  (`normal = 0x01` …), `LayerStack: Sendable, Identifiable` (baseLayer +
  adjustmentLayers, mutation API deliberately absent), `public final class
  BackgroundLayer: Layer, @unchecked Sendable` (documented single-owner
  contract).
- **01-04-05 PassthroughModule** (d7c3684 + SDK fix 5550fc7) — `public final
  class PassthroughModule: IOPModule`: `Params: Codable, Hashable` (empty),
  `opName "passthrough_spike"`, `iopOrder 50.5` (between shadhi 50.0 and
  zonesystem 51.0), `flags []`, `defaultColorspace .RGB`; `process` stages
  buffer→texture (blit), dispatches `pass_through` via `dispatch2D`
  (buffers bound 0/1, kernel textures via `configure`, identity constants
  cached per instance → stable PSOKey), drains (FIFO), stages texture→output
  buffer. `PassthroughKernel` bundle anchor kept for metallib registration.
- **01-04-06 PixelPipe** (4b3c918) — `internal final class PixelPipe`
  (`LightamerCore/Sources/Pipe/PixelPipe.swift`): holds `layerStack:
  LayerStack?` (layer-aware from day one, D-03a), `process(image:metal:)`
  guarantees a base layer (default `BackgroundLayer` when nil), renders via
  `MetalContext.renderToTexture` (the CIContextPool float32
  linear-Rec2020 bridge, FOUND-02) and returns it unchanged — the literal
  Phase 1 no-op. Doc comments mark Phase 2 (iop-chain traversal, per-module
  per-ROI cache, multi-resolution, terminal trio) and Phase 6 (multi-layer
  composite, mask rasterization, blendop loop). **`RenderPipeline` public
  enum** is the app↔Core render bridge (`render(image:layerStack:metal:)`
  with signpost category "pixelpipe") — PixelPipe stays internal per plan.
- **01-04-07 EditorState wiring** (f8e0975) — `EditorState` gains
  `private(set) var layerStack: LayerStack?` and `displayTexture` (internal
  setter for the `@Bindable` binding); `load(url:decoder:metal:logger:)`
  constructs `LayerStack(baseLayer: BackgroundLayer())` on successful decode
  and runs `RenderPipeline.render` → `displayTexture` (supersede-guarded,
  signposted, pixelpipe failures non-blocking per UI-SPEC severity table);
  `renderDisplayTexture` re-routes through the same bridge (URL-keyed
  `.task` fallback in `EditorAreaView`). Call sites (`ContentView`,
  `EditorAreaView`, `LightamerApp`) pass the app-owned `metalContext`.
- **01-04-08 test stubs + build + end-to-end** (328e727) —
  `IOPModuleTests` (3 stubs: conformance / Params Codable+Hashable /
  process bit-exact no-op, GPU-guarded), `V50OrderTests` (3 stubs: count /
  duplicates-except-28.5-cluster / milestone lookups), `LayerSkeletonTests`
  (3 stubs: stack construction / BlendMode raw / BackgroundLayer
  conformance) — bodies are Plan 06's. `tuist generate` + both builds green;
  headless smoke replaces the on-screen manual check (see below).

## End-to-end smoke evidence (headless, real GPU: Apple M4)

`.work/plans/01-04/smoke.swift` (public surface only; decode fixture =
`Resources/TestFixtures/sample-gradient.jpg`):

| Check | Result |
|---|---|
| MetalContext init (device + queue) | PASS |
| IOP `default.metallib` registered from framework bundle | PASS |
| RAWDecoder.decode fixture: 160×120, decoder=v8 | PASS |
| `reloadDefaults`/`commitParams` → `piece.paramsHash == params.hashValue` | PASS |
| ROI plumbing identity (`modifyROIOut`/`modifyROIIn`) | PASS |
| `PassthroughModule.process` buffer→buffer **bit-exact** (staging blits + dispatch2D buffers@0/1) | PASS |
| `LayerStack(baseLayer: BackgroundLayer())` — base present, zero adjustments | PASS |
| `BlendMode.normal.rawValue == 1` (sidecar-stable) | PASS |
| `BackgroundLayer` LAYER-01 defaults | PASS |
| **Vertebra:** `RenderPipeline.render` (internal PixelPipe, layerStack installed) → texture 160×120 == decoded extent | PASS |
| pixelpipe output format `.rgba32Float` (FOUND-02) | PASS |
| pixelpipe output pixels finite (probed row0 col0) | PASS |
| nil layerStack → pipe installs default `BackgroundLayer`, still renders | PASS |

`SMOKE PASS`, 13/13, exit 0. This proves the plan's success criterion #3
end-to-end minus the eyeball: the exact `EditorState.load` render path
(decode → LayerStack → PixelPipe → MTLTexture) runs without error and
produces the display texture `EditorMTKView` blits (that blit was proven
byte-exact in Plan 03's smoke and is unchanged).

## Build verification output summary

- `tuist generate` → exit 0 (picks up Pipe/PixelPipe + 3 test files; glob
  set changed even though `Project.swift` did not).
- `xcodebuild build -project Lightamer.xcodeproj -scheme Lightamer
  -destination 'platform=macOS' -quiet` → exit 0, zero diagnostics.
- `xcodebuild build -project Lightamer.xcodeproj -target LightamerTests
  -configuration Debug` → exit 0 (note: `xcodebuild -list` shows no
  LightamerTests *scheme* — Tuist generates app/framework schemes only;
  `-target` is the build path, same as Plan 03).
- Manual remainder (unchanged class from Plans 01/02): on-screen eyeball of
  `EditorMTKView` while opening a file — screen locked in session; the
  pipeline is smoke-verified at the pixel level instead.

## Deviations from plan (with reasons)

1. **V50Order = 93 entries, not ~76.** The verbatim port of
   `iop_order.c:298-415` yields 93 rows (the plan's estimate undercounted;
   the source is authoritative — plan acceptance said "exact count verified
   by Plan 06's V50OrderTests"). Test stub doc comments already assert the
   93 expectation for Plan 06 to fill.
2. **`RenderPipeline` public bridge (new enum in Core/Pipe).** The plan's
   01-04-07 note anticipated this: PixelPipe is `internal`, so Core exposes
   `RenderPipeline.render(image:layerStack:metal:)` as the app↔Core render
   contract (to be documented in `LightamerCore/API.md` in Plan 06). Phase 1
   builds an ephemeral pipe per call; Phase 2 introduces the persistent,
   cache-carrying instance.
3. **Phase 1 no-op dispatches NO kernel in the pipe** (plan 01-04-06
   pre-authorized this option): `PixelPipe.process` returns the
   CIContextPool-rendered texture unchanged; the `pass_through` kernel is
   proven through `PassthroughModule.process` (smoke check 4c, bit-exact)
   and Plan 06's tests. Core cannot import IOP, and Core ships no kernels of
   its own (Plan 03 deviation #2 context).
4. **macOS 27 SDK absorption in `PassthroughModule.process`** (5550fc7):
   `MTLBlitCommandEncoder.copy` now requires `sourceSize` /
   `destinationOrigin` / `sourceOrigin` spellings, and
   `MTLCommandBuffer.completed()` is no longer throwing (`try?` removed).
   Same semantics; smoke-verified bit-exact after the change.
5. **`EditorState.load` gained a `metal:` parameter** (plan described the
   render leg inside `load` but not the signature change): the app-owned
   `MetalContext?` is now passed to all three call sites; `metal == nil`
   (no-GPU host) still decodes and simply leaves the display empty (the
   fatal alert remains hosted by `ContentView`, per UI-SPEC).
6. **`displayTextureRenderedForURL` guard retained from Plan 03** and now
   also guards the `load`-path render — belt-and-braces against the
   `.task` fallback double-rendering; purely app-internal.
7. **Commit split**: the stalled session left the SDK fix and the wiring in
   one working tree; landed as 4 logical commits (fix / PixelPipe+bridge /
   app wiring / test stubs) instead of one — cleaner bisect surface, same
   content.
8. **Manual-verification remainder** (same as Plans 01/02): locked-screen
   session → no on-screen eyeball; indirect pixel-level evidence above.

## Handoff to downstream plans

- **Plan 06** fills the 9 staged test stubs (the smoke in
  `.work/plans/01-04/smoke.swift` is the reference for `IOPModuleTests`
  bodies) and stages RAW fixtures; document `RenderPipeline` in
  `LightamerCore/API.md` (D-03c).
- **Phase 2** replaces the no-op body of `PixelPipe.process` with the real
  base-layer iop-chain traversal (V50Order-ordered, per-module per-ROI
  `IOPiece` cache, multi-resolution pipes, terminal trio) and swaps the
  ephemeral-per-call pipe for a persistent instance owned by the editor —
  `RenderPipeline` is the seam to rework.
- **Phase 3+** iop authors copy `PassthroughModule` as the reference
  conformance; register `opName`/`iopOrder` against `V50Order`.
- **Phase 6** fills `Layer.iopChain`/`mask` + multi-layer composite inside
  `PixelPipe`; the D-03a skeleton needs no rewrite (L005 satisfied).

## Key files

- `LightamerCore/Sources/Pipe/{IOPModule,IOPFlags,IOPColorspace,ROI,IOPiece,PixelPipe}.swift`
- `LightamerCore/Sources/Foundation/V50Order.swift`
- `LightamerCore/Sources/Layers/{Layer,LayerKind,BlendMode,LayerStack,BackgroundLayer}.swift`
- `LightamerIOP/Sources/Passthrough.swift`
- `App/Sources/Lightamer/State/EditorState.swift`, `App/Sources/Lightamer/UI/{ContentView,EditorAreaView,LightamerApp}.swift`
- `Tests/LightamerTests/{IOPModuleTests,V50OrderTests,LayerSkeletonTests}.swift`
- Smoke harness: `.work/plans/01-04/smoke.swift` (not a build target)
