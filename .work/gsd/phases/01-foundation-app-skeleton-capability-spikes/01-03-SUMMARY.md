---
phase: 1
plan: 03
status: complete
completed: 2026-09-16
duration: ~2h (single executor session)
commits:
  - ff8c4dd feat(01-03): add MetalError + PSOKey + MetalContextMarker (Core/Metal support types)
  - ed02728 feat(01-03): add MetalContext public actor — lazy PSO cache, two-layer dispatch, function-constants
  - 5c84d97 feat(01-03): add internal CIContextPool actor — CIImage→float32 Rec2020 MTLTexture bridge
  - 9190be9 feat(01-03): add PassThrough kernel + IOP bundle anchor (empty-module warning gone)
  - 71d6c90 feat(01-03): add EditorMTKView blit + wire display pipeline through EditorState/EditorAreaView
  - 408a886 test(01-03): stage MetalContextTests stubs (Plan 06 fills)
  - c913885 fix(01-03): CIContextPool bitmap render workaround + blit shader v-flip for upright display
---

# Plan 01-03 — Summary

MetalContext dispatch framework (Core/Metal) + PassThrough kernel (LightamerIOP) +
EditorMTKView blit (app/UI). **Tracer vertebra "open RAW → see it on screen" is
complete at the pipeline level**: decode → `CIContextPool` (linear Rec2020
float32) → `MetalContext` dispatch → blit shaders → sRGB bytes, verified
**byte-exact end-to-end headlessly**; the on-screen MTKView eyeball check is the
single manual remainder (screen locked in this session — same as Plans 01/02).

## What was built (per task)

- **01-03-01 checkpoint:decision** — All eleven locks affirmed from CONTEXT.md
  (D-14 default device, D-15 single queue + Phase 11 seam, D-16 lazy+memory PSO
  cache LRU-256, D-17 function-constants, D-18 typed throws, D-19 two-layer
  dispatch, D-20 tiling deferred, module placement, MetalContext owned via
  `@State` injection not singleton, per-module metallibs via `Bundle(for:)`,
  `.bgra8Unorm` display / `.rgba32Float` pipe). No re-litigation.
- **01-03-02 support types** — `MetalError` (public, 4 cases + `asAppError`
  tiered mapping to `AppError`), `PSOKey` (internal, Hashable,
  name + constants fingerprint), `MetalContextMarker` (internal,
  `Bundle(for:)` anchor — RESEARCH §1 #1 cross-module metallib gotcha).
- **01-03-03 MetalContext** — `public actor`: `nonisolated let device/commandQueue`
  (D-14/15; sync-readable from SwiftUI bodies; Phase 11 adds a NEW export queue,
  never reassigns); multi-library function lookup (Core's `default.metallib`
  first, then `registerDefaultLibrary(in:)` registrations — idempotent per
  bundle); D-16 cache `[PSOKey: MTLComputePipelineState]` + LRU-256 bound with
  move-to-end on hit; D-19 `dispatch2D` (buffers@0/1) / `dispatch2DTexture`
  (textures@0/1) high-level + `makeEncoder` low-level returning
  `ComputeEncoderSession` (`@unchecked Sendable` = documented single-thread
  encoding contract); async PSO build via completion-handler bridge (the
  reflection-out-param variant defeats Swift's auto async bridge in this SDK);
  `makeConstants`/`setConstant` D-17 helpers (nonisolated, chainable); threadgroup
  clamped to `maxTotalThreadsPerThreadgroup` (METAL-7); signposter category "metal".
  **Isolation model**: dispatch methods are `nonisolated` — buffers/textures/
  encoders stay in the caller's region (iops can reuse working buffers across
  sequential dispatches); the only actor hop is the PSO-cache lookup.
- **01-03-04 CIContextPool** — `internal actor`, ONE `CIContext` per device
  (workingColorSpace/outputColorSpace = linear Rec2020, workingFormat RGBAh,
  `cacheIntermediates: false` per CIRAW-4), renders to `.rgba32Float` textures
  (FOUND-02), `OSSignposter` interval "render", `MetalContext.renderToTexture`
  is the public facade (pool never leaks cross-module).
- **01-03-05 Passthrough kernel** — `LightamerIOP/Sources/Passthrough.metal`
  (`kernel void pass_through`, `[[function_constant(0)]] useSrgbGamma`,
  `[[function_constant(1)]] exposureEV`, float math per L006, no MSL defaults —
  Swift MUST set both constants per the RESEARCH §3 all-constants gotcha);
  `Passthrough.swift` exposes `PassthroughKernel.functionName` +
  `PassthroughKernel.metalBundle` (framework-bundle anchor for registration).
  The Plan 01 empty-module `DEFINES_MODULE` warning is gone. Verified
  `pass_through` symbol inside the built IOP `default.metallib` via
  `metal-objdump`.
- **01-03-06 EditorMTKView + wiring** — `EditorMTKView` (internal
  NSViewRepresentable): `MTKView` with injected device/queue, `.bgra8Unorm`,
  `isPaused`+`enableSetNeedsDisplay` (D-13 static blit), layer background =
  neutral-1, Coordinator owns the blit PSO (built ONCE from the APP bundle's
  metallib — `Bundle.main` is correct for app-target shaders) and per-frame
  state; `updateNSView` pushes ONLY on texture identity change (UI-1); aspect-fit
  letterbox uniforms via `setVertexBytes`; nil texture = canvas-mat clear.
  `EditorBlitShader.metal`: fullscreen triangle + aspect-fit uniforms + linear
  Rec2020→sRGB (primaries matrix + piecewise transfer) → `.bgra8Unorm`. App
  wiring: `LightamerApp` owns `@State MetalContext?` (`try? MetalContext()`;
  nil → fatal `.metalDeviceUnavailable` alert per UI-SPEC), registers the IOP
  metallib at the app root; `EditorState` gains `displayTexture` +
  `renderDisplayTexture(using:)` (URL-keyed, cleared on new load, non-blocking
  error logging); `EditorAreaView` loaded branch renders `EditorMTKView` keyed
  by `.task(id: loadedImageURL)` with the 200ms transition preserved.
- **01-03-07 tests + build + end-to-end** — `MetalContextTests` 4 stubs
  (init / bit-exact / PSO-cache-hit / constants-specialization, each
  `XCTSkipIf` GPU-guarded; Plan 06 fills). `xcodebuild build` (scheme) +
  `xcodebuild build -target LightamerTests` both `** BUILD SUCCEEDED **`.
  Headless smoke (`.work/plans/01-03/smoke.swift`, links the built frameworks,
  drives the PUBLIC surface): **13/13 PASS** — see below.
- **Metal Toolchain component** — Xcode 27 required
  `xcodebuild -downloadComponent MetalToolchain` (838.9 MB) before any `.metal`
  compiled; one-time install, now present.

## End-to-end smoke evidence (headless, real GPU: Apple M4)

| Check | Result |
|---|---|
| MetalContext init (device + queue) | PASS |
| IOP `default.metallib` registered from framework bundle | PASS |
| PSO cache: cold dispatch (w/ build) 3-4ms vs warm same-PSOKey 0.2-0.5ms | PASS (D-16) |
| `pass_through` identity constants: out == in **bit-exact** | PASS (FOUND-06) |
| `exposureEV=1` specialization: rgb×2 (distinct PSO) | PASS (D-17) |
| `useSrgbGamma` specialization: pow(rgb, 1/2.2) (distinct PSO) | PASS (D-17) |
| `makeEncoder` low-level path bit-exact | PASS (D-19) |
| `RAWDecoder.decode` → `renderToTexture`: size 160×120 == extent, `.rgba32Float`, finite linear pixels | PASS (FOUND-02) |
| App blit shaders (loaded from the APP bundle) round-trip vs fixture sRGB bytes: **max diff 0 over 192 samples** | PASS |
| Orientation: blit row sy == image row sy from top → upright on screen (v-flip verified) | PASS |

Tracer chain decoded→rendered→blitted is thereby verified at the pixel level.
GUI remainder (same status as Plans 01/02): physical screen locked →
`screencapture` black frames, window-capture rejected, so the "three columns +
image visible" eyeball check stays a 30-second human task; indirect evidence:
app process alive (PID verified after relaunch), `CGWindowList` shows the
Lightamer window on screen (1440×816), zero crash reports, unified-log capture
unavailable on this host (`log show/stream` return nothing even globally —
noted, not a Lightamer defect). Instruments signpost eyeball ("decode"/"render"
intervals) likewise deferred to the first unlocked session; the signposter code
is in place on both paths (D-31).

## Key files

- `LightamerCore/Sources/Metal/{MetalContext,MetalError,PSOKey,CIContextPool,MetalContextMarker,MetalSendability}.swift`
- `LightamerIOP/Sources/{Passthrough.swift,Passthrough.metal}`
- `App/Sources/Lightamer/UI/{EditorMTKView.swift,EditorBlitShader.metal,EditorAreaView.swift,ContentView.swift,LightamerApp.swift}`
- `App/Sources/Lightamer/State/EditorState.swift`
- `Resources/Localizable.xcstrings` (+`alert_metal_unavailable_title`, +`editor_viewport`, −`editor_loaded_placeholder`)
- `Tests/LightamerTests/MetalContextTests.swift`
- Smoke harness: `.work/plans/01-03/smoke.swift` (not a build target)

## Deviations from plan (with reasons)

1. **`CIContext.render(_:toMTLTexture:)` is BROKEN on this host — bitmap+replace
   workaround.** The command-buffer-bearing (and every other texture) render
   variant completes with status=completed, error=nil, and writes ZERO bytes —
   verified across rgba8Unorm/rgba16Float/rgba32Float × shared/managed ×
   device/queue contexts × nil/owned command buffers (probes in this session;
   bitmap render to the same formats is byte-correct, and plain Metal clears to
   the same textures work). `CIContextPool` therefore renders to a float32 CPU
   buffer (`CIFormat.RGBAf`, linear Rec2020 — FOUND-02 intact) and stages it
   into the shared texture via `replace(region:)`. Extra copy ≈ 0.3-0.5 s at
   100MP (inside the D-32 display budget; 160×120 here is ~free). **Phase 2
   must re-test the direct texture path before the linear pixelpipe replaces
   this bridge.** Documented in the CIContextPool header.
2. **MetalContext loads Core's metallib tolerantly + `registerDefaultLibrary(in:)`.**
   The plan/decision #10 assumed Core ships kernels — it ships none in Phase 1,
   so a hard `try device.makeDefaultLibrary(bundle:)` in init would throw and
   kill the app at launch. Core's bundle is still resolved via
   `Bundle(for: MetalContextMarker.self)` (gotcha honored), absence is logged,
   and kernel-owning modules register their metallibs (IOP does at the app
   root). Function lookup: Core first, then registration order. This is the
   generalization of decision #10, not a reversal.
3. **`PSOKey.constantsFingerprint` = instance identity.**
   `MTLFunctionConstantValues` has no value introspection, so identical
   constant VALUES cannot be hashed. Distinct `makeConstants` instances →
   distinct PSO entries (D-17 satisfied, verified in smoke); reusing one set
   instance is the intended iop hot path (cache hit, verified). Documented in
   `PSOKey.swift`; revisit if per-frame constant sets ever appear.
4. **`makeEncoder` returns `ComputeEncoderSession` (a struct), not the bare
   tuple.** Swift 6 forbids returning the non-Sendable trio from an actor; the
   struct is `@unchecked Sendable` carrying the documented single-thread
   encoding contract. `makeEncoder(functionName:constants:)` public signature
   shape preserved.
5. **Dispatch methods are `nonisolated` (plan sketched them actor-isolated).**
   Metal buffers/textures are protocols — the language forbids retroactive
   Sendable, so actor-isolated signatures would force `sending` ownership
   transfers and forbid iops reusing working buffers across sequential
   dispatches. Only mutable state (PSO cache, libraries, pool) is
   actor-isolated; buffers/encoders stay in the caller's region. D-33/D-19
   semantics unchanged.
6. **`EditorState.displayTexture` setter is internal, not `private(set)`** —
   `$editorState.displayTexture` via `@Bindable` needs it; `renderDisplayTexture`
   remains the only writer (app-internal type, no cross-module surface).
7. **Extra files beyond `files_modified`:** `MetalSendability.swift`
   (retroactive Sendable for the one Metal CLASS involved —
   `MTLFunctionConstantValues`; buffer/texture protocols are handled by the
   nonisolated design instead), `EditorBlitShader.metal` (the plan's blit
   shaders must live somewhere; app target per RESEARCH §4),
   `PassthroughKernel.metalBundle` anchor class (bundle registration without
   leaking an IOP-internal marker).
8. **SDK renames absorbed (same semantics):** `kCIFormatRGBAh` →
   `CIFormat.RGBAh`; `makeComputePipelineState(descriptor:)` completion-handler
   spelling retained while the reflection-out-param variant is no longer
   async-bridged (explicit `withCheckedThrowingContinuation` used);
   `MTLFunctionConstantValues.setConstantValue(_:type:index:)` (not `setBytes`);
   `MTLComputePipelineDescriptor.computeFunction` (not `function`).
9. **Blit orientation settled empirically:** CI renders bottom-up; the drawable
   row 0 displays at view top; the fragment v-flip (`1.0 - (ndc.y*0.5+0.5)`)
   is verified byte-exact against the fixture in display order (smoke check 9/9b).
10. **Manual-verification remainders (documented, not skipped silently):**
    on-screen MTKView eyeball + Instruments signpost eyeball — physical screen
    locked for the whole session (black captures; window-capture refused);
    indirect evidence listed above. Same remainder class as Plans 01/02.
11. **Real RAW (CR3/NEF) on-screen check still awaits a real camera sample** —
    unchanged from Plan 02's deviation #4; the raster fixture exercises the
    identical display path (Plan 06 stages RAW fixtures).

## Build verification output summary

- `tuist generate` → exit 0 (picks up Core/Metal, IOP sources, app/UI, tests).
- `xcodebuild build -project Lightamer.xcodeproj -scheme Lightamer
  -destination 'platform=macOS'` → `** BUILD SUCCEEDED **`, zero errors; only
  benign notes (appintentsmetadataprocessor skip).
- `xcodebuild build -target LightamerTests` → `** BUILD SUCCEEDED **`.
- `pass_through` present in
  `LightamerIOP.framework/Versions/A/Resources/default.metallib`
  (`metal-objdump --syms`: `FUNCTION_LIST pass_through`).
- Smoke `.work/plans/01-03/smoke` → `SMOKE PASS` (13/13, exit 0) against the built
  Debug frameworks + Lightamer.app bundle.

## Handoff to downstream plans

- **Plan 04** consumes `MetalContext.dispatch2D` for `PassthroughModule.process`
  (buffers bound at 0/1 — the exact smoke-verified path), refactors
  `Passthrough.swift` into `PassthroughModule: IOPModule`; kernel constants
  pattern: `makeConstants` + `setConstant` chaining (both required — no MSL
  defaults in the kernel).
- **Plan 06** fills `MetalContextTests` stub bodies (bit-exact, cache,
  specialization — the smoke in `.work/plans/01-03/smoke.swift` is the reference
  implementation for all four), stages RAW fixtures.
- **Phase 2** replaces `CIContextPool.renderToTexture` with the linear
  pixelpipe; re-test `render(_:toMTLTexture:)` on newer macOS 27 builds first
  (broken on 26A425/M4 — see deviation #1).
- **Phase 8** EDR: `.rgba16Float` drawable variant of `EditorMTKView`.
- **Phase 11**: add the low-priority export queue as a new `MetalContext`
  property (D-15 seam).
