import LightamerCore
import Metal

/// Phase-1 entry surface for the pass-through kernel (success criterion #2).
///
/// The kernel-name + bundle-anchor convenience kept from Plan 03: the
/// app/tests register LightamerIOP's `default.metallib` (which contains the
/// compiled `.metal` file) via
/// `MetalContext.registerDefaultLibrary(in: PassthroughKernel.metalBundle)`.
///
/// `public` (cross-module).
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

/// The no-op reference iop (success criterion #3, FOUND-03): the FULL
/// `IOPModule` conformance that every Phase 3+ module copies — params,
/// defaults, ROI plumbing, and a `process` that drives GPU work through
/// `MetalContext` (the smoke-verified `pass_through` kernel from Plan 03).
///
/// `opName` is `"passthrough_spike"` (NOT a Darktable op string — this
/// module never enters sidecars; RESEARCH §5 gotcha). `iopOrder` 50.5 is
/// an arbitrary Phase 1 position between `shadhi` (50.0) and `zonesystem`
/// (51.0) in the `V50Order` table.
///
/// `process` is texture-domain end-to-end (Plan 02-02 checkpoint lock #1):
/// the pipe's currency is `MTLTexture` (float32 RGBA linear Rec2020), and
/// `dispatch2DTexture` binds input/output directly at texture indices 0/1 —
/// the Phase 1 buffer↔texture staging bridge is gone. Same-queue FIFO
/// ordering makes a chain of dispatches correct without awaiting completion;
/// CPU-side readers (tests) drain the queue explicitly.
///
/// Not `Sendable` by design: a module instance (and its cached constant
/// set) is owned by its pipe run's isolation domain — the same contract as
/// `IOPiece`. Phase 2's `ModuleRegistry` stores METATYPES
/// (`PassthroughModule.Type`), which are Sendable.
public final class PassthroughModule: IOPModule {

    /// Empty parameter record — the pass-through has nothing to tune; the
    /// shape proves the `Codable & Hashable` sidecar/cache plumbing.
    public struct Params: Codable, Hashable {
        public init() {}
    }

    public static let opName = "passthrough_spike"

    /// Arbitrary Phase 1 position (between shadhi 50.0 and zonesystem 51.0).
    public static let iopOrder: Float = 50.5

    public static let flags: IOPFlags = []

    public static let defaultColorspace: IOPColorspace = .RGB

    /// Identity specialization of the kernel — `useSrgbGamma = false`,
    /// `exposureEV = 0`. BOTH constants must be set (the kernel declares no
    /// MSL defaults; RESEARCH §3 gotcha). Cached per instance so every
    /// dispatch hits the same `PSOKey` (D-16: instance identity is the
    /// constants fingerprint).
    private var identityConstants: MTLFunctionConstantValues?

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        // The cache-identity hash (D-H4): StableHash FNV-1a 64 over the
        // JSON-encoded params bytes — the ONLY legal generator. The
        // reference shape every Phase 3+ module copies.
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
    }

    /// Identity: the pass-through produces exactly the input ROI.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Identity: the pass-through needs exactly the output ROI as input.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        // Kernel constants: identity specialization (lazily built once per
        // module instance → stable PSOKey → D-16 cache hits).
        let constants: MTLFunctionConstantValues
        if let identityConstants {
            constants = identityConstants
        } else {
            let built = metal.makeConstants(false, at: 0, type: .bool)
            metal.setConstant(Float(0.0), at: 1, type: .float, into: built)
            identityConstants = built
            constants = built
        }

        // THE iop dispatch: textures bound at 0/1 per the dispatch2DTexture
        // contract; the grid spans the output texture. No uniforms for the
        // pass-through (`piece.data` is nil). Same-queue FIFO ordering keeps
        // chained pipe dispatches correctly sequenced.
        try await metal.dispatch2DTexture(
            functionName: PassthroughKernel.functionName,
            input: input,
            output: output,
            constants: constants
        )
    }
}
