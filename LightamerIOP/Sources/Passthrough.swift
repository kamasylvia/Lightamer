import Foundation

/// Phase-1 entry surface for the pass-through kernel (success criterion #2).
///
/// Minimal by design: Plan 04 refactors this file into the full
/// `PassthroughModule: IOPModule` conformance once `IOPModule` lands; Plan 03
/// only needs the kernel name + bundle anchor so `MetalContextTests` and the
/// app can dispatch the kernel through `MetalContext`.
///
/// `public` (cross-module): the app/tests register LightamerIOP's
/// `default.metallib` (which contains the compiled `.metal` file) via
/// `MetalContext.registerDefaultLibrary(in: PassthroughKernel.metalBundle)`.
public enum PassthroughKernel {

    /// MSL function name of the pass-through kernel (`Passthrough.metal`).
    public static let functionName = "pass_through"

    /// The LightamerIOP framework bundle — the `registerDefaultLibrary(in:)`
    /// anchor. RESEARCH §1 gotcha #1: the IOP metallib lives in the FRAMEWORK
    /// bundle, never `Bundle.main`.
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// `Bundle(for:)` anchor class for `PassthroughKernel.metalBundle`.
/// `internal` — never referenced outside LightamerIOP.
final class IOPBundleMarker {}
