/// The PSO cache key (D-16 — lazy + memory cache, RESEARCH §9 internal
/// surface).
///
/// `internal`: cache key only — invisible cross-module; renaming it breaks
/// nothing outside Core.
///
/// `constantsFingerprint` identifies the function-constant specialization a
/// PSO was built for. `MTLFunctionConstantValues` has no value introspection,
/// so `MetalContext` fingerprints by instance identity: every
/// `makeConstants`/`setConstant` chain produces a fresh object, so two
/// distinct constant combinations always hash to distinct cache entries
/// (D-17: one kernel file → many specialized PSO variants), while reusing one
/// instance (the intended hot-path pattern for iops) is a cache hit.
internal struct PSOKey: Hashable {
    let name: String
    let constantsFingerprint: String
}
