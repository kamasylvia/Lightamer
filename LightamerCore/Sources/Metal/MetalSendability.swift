import Metal

// Swift 6 strict-concurrency bridge for Metal handle types (RESEARCH §3).
//
// `MTLDevice` / `MTLCommandQueue` are already Sendable-annotated in the SDK.
// `MTLBuffer` / `MTLTexture` are PROTOCOLS — the language forbids retroactive
// protocol-conformance declarations, so they cross isolation via `sending`
// region transfer or stay in the caller's region (MetalContext's dispatch
// methods are `nonisolated` for exactly this reason).
//
// `MTLFunctionConstantValues` is a class: this conformance documents the
// ownership contract — a constant set is fully populated by
// `makeConstants`/`setConstant` BEFORE it is handed to the dispatch path and
// is treated as immutable afterwards (the actor only reads it to specialize
// the PSO).
extension MTLFunctionConstantValues: @unchecked @retroactive Sendable {}
