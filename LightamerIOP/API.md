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
  - `process(input:output:roiIn:roiOut:piece:metal:)` — the no-op pipe step
    (buffer↔texture staging + `pass_through` dispatch, bit-exact identity)

### Kernel surface
- `enum PassthroughKernel` — `functionName = "pass_through"` (the MSL entry
  in `Passthrough.metal`) and `metalBundle` (the `Bundle(for:)` anchor the
  app/tests pass to `MetalContext.registerDefaultLibrary(in:)`)

## Internal (NOT for cross-module use — may change without notice)

- `IOPBundleMarker` (the class behind `PassthroughKernel.metalBundle`)
- per-module `.metal` kernel name tables beyond the published enum above
- internal param structs / staging-cache details
  (`PassthroughModule.identityConstants`, `staging`)

## Phase 2+ additions (reserved, not yet present)

- `ModuleRegistry` — `opName → IOPModule.Type` mapping (Phase 2 fills;
  Phase 1 has only Passthrough). Registry stores METATYPES (Sendable);
  module instances are owned per pipe run.
- Phase 3+ modules follow the same shape: one `public final class
  XXXModule: IOPModule` + one `.metal` kernel per file pair
  (`XXX.swift` + `XXX.metal`), `opName` mirroring Darktable's op string.

## Code-review enforcement

Adding a module = adding one public class + one metallib kernel + a row
here. Anything else a module needs to expose must justify `public` against
staying `internal` (iops are invisible to each other per D-03).
