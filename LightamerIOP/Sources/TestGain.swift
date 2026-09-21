// Plan 03-06-T7 revision: the TYPE compiles in all configurations (the
// Release-configuration PERF-5 test build @testable-imports this module
// through test files that reference it), but the APP-CHAIN registration
// below stays DEBUG-only — a Release sidecar carrying a `testgain` op
// still degrades to UNKNOWN exactly as before (the observable behavior
// is unchanged: the class is never instantiated outside tests).
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// DEV-ONLY MODULE — never registered into app chains outside DEBUG.
//
// SC#2's demonstration vehicle (02-RESEARCH Validation Architecture): a
// one-parameter gain module the cache tests re-parameterize to prove the
// hash-chain fast path (run1 all-miss → param change → partial hit → undo
// → full hit). Phase 2 has no real sliders; this module is the first param
// change to flow through the pipe. NOT registered in any default chain —
// tests register it explicitly (02-04's ModuleRegistry populates modules
// explicitly; sidecars never legitimately contain `testgain`).
//
// Sidecar note: a `testgain` op found in a sidecar opened by a RELEASE
// build is an unknown op and must degrade per 02-06's unknown-op rule
// (keep paramsData verbatim, disable the instance, toast) — exactly the
// scenario this dev-only module exercises.
//
// `iopOrder` 50.5 collides with `passthrough_spike`'s 50.5 — legal:
// Darktable has deliberate order collisions, and chain position is
// disambiguated by (iopOrder, multiPriority) at pipe build time.
// ─────────────────────────────────────────────────────────────────────────

/// Kernel-name + bundle-anchor convenience (same pattern as
/// `PassthroughKernel`).
public enum TestGainKernel {

    /// MSL function name of the gain kernel (`TestGain.metal`).
    public static let functionName = "test_gain"

    /// 04-01 ROI probe: offset-sampled gain (`test_gain_windowed`) — reads
    /// input at `gid + (roiIn.xy − roiOut.xy)`, so a downstream module's
    /// output proves it consumed the negotiated window.
    public static let windowedFunctionName = "test_gain_windowed"

    /// The LightamerIOP framework bundle — the `registerDefaultLibrary(in:)`
    /// anchor (the IOP metallib lives in the FRAMEWORK bundle, never
    /// `Bundle.main`).
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// The parameterized dev-only gain iop. See the file header for scope.
public final class TestGainModule: IOPModule {

    /// Single tunable: linear-domain RGB multiplier (default 1.0 = identity,
    /// so a default-parameterized TestGain in a chain is a true no-op).
    public struct Params: Codable, Hashable {
        public var gain: Float

        public init(gain: Float = 1.0) {
            self.gain = gain
        }
    }

    public static let opName = "testgain"

    /// Free slot between colorin 28.0 and colorout 70.0 (collision with
    /// passthrough_spike 50.5 is legal — see file header).
    public static let iopOrder: Float = 50.5

    public static let flags: IOPFlags = []

    public static let defaultColorspace: IOPColorspace = .RGB

    /// Device for the uniforms `MTLBuffer` allocation in `commitParams`.
    /// Nil default → lazily resolved system default device (DEBUG test
    /// module only; production modules never allocate in commitParams —
    /// they get the device context in `process`).
    private let device: (any MTLDevice)?

    /// Cached uniforms buffer, reallocated when the gain value changes.
    private var uniformsBuffer: (any MTLBuffer)?
    private var uniformsGain: Float = .nan

    /// Last committed gain (04-01: the windowed `process` path builds its
    /// uniforms per call — it reads this, not the GPU buffer).
    private var committedGain: Float = 1.0

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// THE reference implementation of the paramsHash contract (checkpoint
    /// lock #2 / D-H4): `piece.paramsHash = StableHash.hash(JSONEncoder
    /// params bytes)` — StableHash FNV-1a 64, the only legal generator, the
    /// SAME atom the pipe cache keys and the 02-05 history identity hash on.
    /// Also writes the uniforms into `piece.data` (float gain, offset 0,
    /// 16-byte-aligned struct).
    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        committedGain = params.gain
        guard let resolvedDevice = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        if uniformsGain != params.gain || uniformsBuffer == nil {
            var uniforms = TestGainUniforms(gain: params.gain)
            uniformsBuffer = resolvedDevice.makeBuffer(
                bytes: &uniforms,
                length: MemoryLayout<TestGainUniforms>.stride,
                options: .storageModeShared
            )
            uniformsGain = params.gain
        }
        piece.data = uniformsBuffer
    }

    /// Identity ROI: a gain does not resample.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Identity ROI: a gain needs exactly the output ROI as input.
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
        let uniforms = piece.data // local copy for the gain when offset is zero
        let dx = Int32(roiIn.x - roiOut.x)
        let dy = Int32(roiIn.y - roiOut.y)
        if dx == 0 && dy == 0 {
            try await metal.dispatch2DTexture(
                functionName: TestGainKernel.functionName,
                input: input,
                output: output
            ) { encoder in
                if let uniforms {
                    encoder.setBuffer(uniforms, offset: 0, index: 0)
                }
            }
            return
        }
        let captured = ROIGainUniforms(
            gain: committedGain, inOffsetX: dx, inOffsetY: dy
        )
        try await metal.dispatch2DTexture(
            functionName: TestGainKernel.windowedFunctionName,
            input: input,
            output: output
        ) { encoder in
            var uniformsCopy = captured
            encoder.setBytes(
                &uniformsCopy,
                length: MemoryLayout<ROIGainUniforms>.stride, index: 0)
        }
    }
}

/// Swift mirror of the MSL `TestGainUniforms` struct — 16-byte stride
/// (float gain at offset 0 + padding) so the buffer length satisfies
/// constant-addressable alignment.
struct TestGainUniforms {
    var gain: Float
    private var _pad: (Float, Float, Float) = (0, 0, 0)

    init(gain: Float) {
        self.gain = gain
    }
}

/// Swift mirror of the MSL `ROIGainUniforms` struct (04-01 probe):
/// `float gain` + `int2 inOffset` (= `roiIn.xy − roiOut.xy`, negotiated
/// sampling shift). 16-byte total — constant-addressable aligned.
struct ROIGainUniforms {
    var gain: Float
    var inOffsetX: Int32
    var inOffsetY: Int32
    private var _pad: Float = 0

    init(gain: Float, inOffsetX: Int32, inOffsetY: Int32) {
        self.gain = gain
        self.inOffsetX = inOffsetX
        self.inOffsetY = inOffsetY
    }
}
