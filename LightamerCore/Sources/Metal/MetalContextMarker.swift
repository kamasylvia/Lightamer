/// `Bundle(for:)` anchor so `MetalContext` can locate LightamerCore's
/// framework bundle at runtime.
///
/// RESEARCH §1 gotcha #1 (the single most likely "kernel not found" bug): a
/// framework target's `default.metallib` lives in the FRAMEWORK bundle, not
/// `Bundle.main`. `device.makeDefaultLibrary()` (no-arg) reads `Bundle.main`
/// and fails for framework-shipped kernels — always resolve via
/// `device.makeDefaultLibrary(bundle: Bundle(for: MetalContextMarker.self))`.
///
/// `internal`: implementation anchor only — never referenced cross-module.
final class MetalContextMarker {}
