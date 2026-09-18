# LightamerIOP — API Contract

> D-03c module contract index. The compiler enforces this boundary;
> this file is the human-readable index code review checks against.
> LightamerIOP depends ONLY on LightamerCore's `public` surface (see
> `../LightamerCore/API.md`); its own public surface is the iop module
> classes the app instantiates.

## Access-level strategy (RESEARCH §9a)

| Level | Meaning | Example |
|---|---|---|
| `public` | Cross-module API surface — every iop ships as one | `PassthroughModule`, `PassthroughKernel` |
| `internal` (default) | Module-internal detail — never referenced by app or sibling iops | `IOPBundleMarker`, per-module helpers |

## Public surface (cross-module, stable)

### Modules
- `final class PassthroughModule: IOPModule` (Phase 1 reference conformance)
  - `struct Params: Codable, Hashable` (empty — the sidecar/cache shape proof)
  - statics: `opName = "passthrough_spike"` (custom, NOT a Darktable op —
    never enters sidecars), `iopOrder: Float = 50.5` (arbitrary Phase 1 slot
    between `shadhi` 50.0 and `zonesystem` 51.0, no V50Order collision),
    `flags = []`, `defaultColorspace = .RGB`
  - `process(input:output:roiIn:roiOut:piece:metal:)` — the no-op pipe step,
    **texture-domain end-to-end** (02-02 lock #1: `dispatch2DTexture`, input/
    output `MTLTexture` float32 RGBA, bit-exact identity; the Phase 1
    buffer↔texture staging bridge is deleted)

### Kernel surface
- `enum PassthroughKernel` — `functionName = "pass_through"` (the MSL entry
  in `Passthrough.metal`) and `metalBundle` (the `Bundle(for:)` anchor the
  app/tests pass to `MetalContext.registerDefaultLibrary(in:)`)

## DEBUG-only surface (NOT part of the Release public contract)

> Compiled out of Release builds entirely (`#if DEBUG`, whole file). Never
> registered in a default chain; tests register it explicitly. A `testgain`
> op in a sidecar read by a Release build is an unknown op → 02-06's
> unknown-op rule (keep `paramsData` verbatim, disable, toast).

- `final class TestGainModule: IOPModule` — the SC#2 demonstration vehicle:
  one-parameter linear-domain gain (TestGain.swift + TestGain.metal)
  - `struct Params: Codable, Hashable` — `var gain: Float = 1.0` (1.0 =
    bit-exact identity)
  - statics: `opName = "testgain"`, `iopOrder = 50.5` (collides with
    `passthrough_spike` legally — order collisions are Darktable-legal),
    `flags = []`, `defaultColorspace = .RGB`
  - `init(device: (any MTLDevice)? = nil)`
  - `commitParams` is the **reference implementation of the paramsHash
    contract**: `piece.paramsHash = StableHash.hash(JSONEncoder params
    bytes)` + uniforms `piece.data` (float gain, offset 0, 16-byte struct)
  - `process` — `dispatch2DTexture("test_gain", ...)` with uniforms bound
    at buffer index 0
- `enum TestGainKernel` — `functionName = "test_gain"`, `metalBundle`

## Internal (NOT for cross-module use — may change without notice)

- `IOPBundleMarker` (the class behind `PassthroughKernel.metalBundle`)
- per-module `.metal` kernel name tables beyond the published enum above
- internal param structs / staging-cache details
  (`PassthroughModule.identityConstants`, `staging`)

## Phase 2+ additions (reserved, not yet present)

- ~~`ModuleRegistry`~~ — **02-04 交付于 LightamerCore**(`Sources/Pipe/
  ModuleRegistry.swift`,terminal trio 是管线基础设施故留在 Core;本框架经
  `LightamerIOPRegistry.populate(_:)` 注册)
- `enum LightamerIOPRegistry` (02-04, `Sources/Registry.swift`) —
  `populate(_ registry: ModuleRegistry) async`:the ONE registration hook
  the app calls at launch. DEBUG registers `testgain`; Release leaves it
  unregistered (a Release sidecar carrying `testgain` = unknown op →
  02-06 degrade). `passthrough_spike` deliberately unregistered
  (test-only). Async because the registry is an actor (D-33; recorded
  plan note). Phase 3+ modules add one line here
- Phase 3+ modules follow the same shape: one `public final class
  XXXModule: IOPModule` + one `.metal` kernel per file pair
  (`XXX.swift` + `XXX.metal`), `opName` mirroring Darktable's op string.
  **commitParams MUST encode via `LightamerCore.ParamsCoding.encode`
  (sortedKeys canonical — LESSONS L013; `JSONEncoder()` raw output is
  nondeterministic across calls)**

## Code-review enforcement

Adding a module = adding one public class + one metallib kernel + a row
here. Anything else a module needs to expose must justify `public` against
staying `internal` (iops are invisible to each other per D-03).
