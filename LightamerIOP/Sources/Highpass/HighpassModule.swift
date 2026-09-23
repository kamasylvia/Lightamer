import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// HIGHPASS — inverted highpass (Plan 04-05-T3, IOP-DETAIL-03).
//
// Darktable reference: `src/iop/highpass.c` (tree dc58cf0ba1)
//   - params v1    :41-45   sharpness ∈ [0,100] DEFAULT 50 / contrast
//                           ∈ [0,100] DEFAULT 50 — TWO params (the plan's
//                           "contrast/center/radius" triple is a source
//                           erratum, DECISIONS D3)
//   - process_cl   :120-231 invert → h/v box-mean blur → CL mix
//   - CPU process  :255-302 invert-pack → `dt_box_mean` → `_blend` double
//                           traversal + 1/16 tail (same formula)
//   - tiling       :98-116  overlap = wdh (the 3σ gaussian half-width)
//   - commit       :304-312 verbatim copy; default_colorspace IOP_CS_LAB
//   - MAX_RADIUS 16 (`highpass.c:37`); v50 slot 34.0
//
// RADIUS CHAIN (D4): rad = 16·min(100, sharpness+1)/100 (`:135`),
// radius = min(16, ceil(rad·scale)) (`:136`), σ =
// √((radius·(radius+1)·8+2)/3) (`:140`, BOX_ITERATIONS = 8).
//
// LAB DOMAIN (T0): dt is IOP_CS_LAB; the L path above is fused with the
// shared LabMath.h conversion (Plan 03-03-T1); a/b desaturate to 0 in
// the mix (CL `o.y/o.z = 0`). scene-referred-purity note as sharpen's
// divergence #4.
//
// INTENTIONAL DIVERGENCES:
// 1. **Blur base = Deriche IIR (shared GaussianBlur) at dt's σ**, not
//    dt's `dt_box_mean` (8 iterations) — plan Goal mandates the reuse.
//    The synthesized reference mirrors the IIR side.
// 2. **disabled-neutral, not "zero-params identity"** (D3): contrast 0
//    yields flat 50-gray by formula (`o.x = 50`), so identity holds only
//    via the disabled piece (the editing seed carries highpass DISABLED).
//
// FRAME CONVENTION (L020): identity-ROI module (sharpen twin) — forward
// keeps input; backward widens by ceil(3σ) symmetrically (NOT a dt
// re-add; the backward walk seeds from the forward result).
//
// HALO (D7): ceil(3σ) (D-G5); `tileHalo` = dt's tiling overlap wdh =
// ceil(3σ) — the box-mean's finite support needs no IIR runway, so both
// constants coincide here (documented, not duplicated by accident).
// ─────────────────────────────────────────────────────────────────────────

public enum HighpassKernel {
    public static let prepFunction = "highpass_prep"
    public static let mixFunction = "highpass_mix"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class HighpassModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// dt `sharpness` ∈ [0, 100] (highpass.c:43), default 50.
        public var sharpness: Float
        /// dt `contrast` ∈ [0, 100] (highpass.c:44), default 50.
        public var contrast: Float

        public init(sharpness: Float = 50.0, contrast: Float = 50.0) {
            self.sharpness = sharpness
            self.contrast = contrast
        }
    }

    public static let opName = "highpass"

    /// Darktable v50 order slot 34.0 — after lowpass (33.0), before
    /// sharpen (35.0) (`iop_order.c` verbatim; V50Order table).
    public static let iopOrder: Float = 34.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// dt MAX_RADIUS (highpass.c:37).
    static let maxRadius = 16

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    // Scratch planes, cached per (width × height) — single-owner contract.
    private var scratchWidth = 0
    private var scratchHeight = 0
    private var prepTexture: (any MTLTexture)?
    private var blurPlanesBuffer: (any MTLBuffer)?
    private var blurredTexture: (any MTLTexture)?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            var uniforms = MixUniforms(contrastScale: (params.contrast / 100.0) * 7.5)
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: MemoryLayout<MixUniforms>.stride, options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                withUnsafeBytes(of: &uniforms) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<MixUniforms>.stride)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    /// MSL mirror of `HighpassMixUniforms`. srcOffset rides per-run
    /// (sharpen precedent — committed buffer carries the commit-time half).
    struct MixUniforms {
        var contrastScale: Float
        var pad0: Float = 0
        var srcOffsetX: Int32 = 0
        var srcOffsetY: Int32 = 0
    }

    /// dt radius chain (`highpass.c:135-140`). `internal` for tests.
    static func radius(sharpness: Float, scale: Float) -> Int {
        let rad = Float(maxRadius) * (min(100.0, sharpness + 1.0) / 100.0)
        return min(maxRadius, Int((rad * scale).rounded(.up)))
    }

    /// dt σ correlation (`highpass.c:140`, BOX_ITERATIONS = 8).
    /// `internal` for tests.
    static func sigma(sharpness: Float, scale: Float) -> Float {
        let r = Float(radius(sharpness: sharpness, scale: scale))
        return ((r * (r + 1) * 8 + 2) / 3).squareRoot()
    }

    /// The ROI/tile halo (D7): ceil(3σ) == dt's wdh. `internal` for tests.
    static func halo(sharpness: Float, scale: Float) -> Int {
        Int((3 * sigma(sharpness: sharpness, scale: scale)).rounded(.up))
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// D-G5 backward expansion (L020 frame note above): symmetric halo
    /// widen; the pipe clamps to the upstream plane. rad == 0 (sharpness
    /// −1 clamp floor) still blurs nothing — halo 0 ⇒ verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        let h = Self.halo(sharpness: committed?.sharpness ?? 50, scale: roi.scale)
        guard h > 0 else { input = roi; return }
        input = roi
        input.x -= h
        input.y -= h
        input.width += 2 * h
        input.height += 2 * h
    }

    // MARK: Tile seam (D7 — halo == dt overlap wdh here)

    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        Self.halo(sharpness: committed?.sharpness ?? 50, scale: roi.scale)
    }

    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        64 // prep (16 B) + blurred (16 B) + planes share (32 B)
    }

    // MARK: Scratch management (per-size cached; .shared storage — L018)

    private func ensureScratch(width: Int, height: Int) throws {
        guard width != scratchWidth || height != scratchHeight else { return }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(HighpassKernel.prepFunction, nil)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        prepTexture = resolved.makeTexture(descriptor: descriptor)
        blurredTexture = resolved.makeTexture(descriptor: descriptor)
        blurPlanesBuffer = resolved.makeBuffer(
            length: width * height * MemoryLayout<Float>.stride * 4 * 2,
            options: .storageModeShared)
        scratchWidth = width
        scratchHeight = height
    }

    // MARK: Process (prep → IIR blur → CL mix)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let uniformsBuffer = piece.data else {
            throw MetalError.psoCreationFailed(HighpassKernel.mixFunction, nil)
        }
        let sigma = Self.sigma(sharpness: committed?.sharpness ?? 50, scale: roiIn.scale)
        try ensureScratch(width: input.width, height: input.height)
        guard let prep = prepTexture, let blurPlanes = blurPlanesBuffer,
              let blurred = blurredTexture else {
            throw MetalError.psoCreationFailed(HighpassKernel.prepFunction, nil)
        }

        // Step 1 — Rec2020 → inverted L.
        try await metal.dispatch2DTexture(
            functionName: HighpassKernel.prepFunction,
            input: input,
            output: prep
        )

        // Step 2 — the IIR domain blur at dt's σ (UNBOUNDED box — dt's
        // box mean clamps nothing; the CL invert pre-clamps to [0,100]).
        // rad == 0 ⇒ σ = √(2/3) > 0: dt runs the box mean with radius 0
        // (= copy); the IIR at σ < 1 approximates the copy within the
        // parity envelope — no branch (halo 0 keeps the ROI exact).
        try await GaussianBlur.blur(
            input: prep, output: blurred, planes: blurPlanes,
            sigma: sigma, order: .zero,
            boundsMin: SIMD4(repeating: -Float.greatestFiniteMagnitude),
            boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
            metal: metal
        )

        // Step 3 — the CL mix (per-run uniforms: shared-buffer upload,
        // NOT setBytes — ashift/lens postmortem).
        let committed = committed ?? Params()
        var runUniforms = MixUniforms(
            contrastScale: (committed.contrast / 100.0) * 7.5,
            srcOffsetX: Int32(roiOut.x - roiIn.x),
            srcOffsetY: Int32(roiOut.y - roiIn.y))
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &runUniforms,
            length: MemoryLayout<MixUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: HighpassKernel.mixFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(blurred, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(runBuffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }
}
