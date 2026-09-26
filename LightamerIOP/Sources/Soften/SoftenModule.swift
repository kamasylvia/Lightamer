import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// SOFTEN — Orton effect (Plan 04-05-T3, IOP-DETAIL-03).
//
// Darktable reference: `src/iop/soften.c` (tree dc58cf0ba1)
//   - params v1    :44-49   size ∈ [0,100] DEFAULT 50 / saturation
//                           ∈ [0,100] DEFAULT 100 / brightness ∈ [−2,2]
//                           DEFAULT 0.33 / amount ∈ [0,100] DEFAULT 50
//   - process CPU  :105-148 overexposed (rgb2hsl × sat/bri) →
//                           `dt_box_mean` (radius below) → linear blend
//   - process_cl   :152-285 overexposed → h/v gaussian blur → mix
//   - radius chain :138-142 mrad = hypot(iwidth·iscale, iheight·iscale)
//                           ×0.01; rad = mrad·min(100,size+1)/100;
//                           radius = min(mrad, ceil(rad·scale))
//   - tiling       :288-315 overlap = wdh (3σ of the correlation σ)
//   - commit       :339-351 verbatim copy; default_colorspace IOP_CS_RGB
//   - v50 slot 66.0 (creative module)
//
// σ CHAIN (D4): σ = √((radius·(radius+1)·8+2)/3) (`soften.c:306`,
// BOX_ITERATIONS = 8) — the box-mean↔gaussian correlation.
//
// RGB LINEAR DOMAIN (T0): dt is IOP_CS_RGB — NO Lab conversion anywhere
// (the overexposed/mix kernels work the Rec2020 linear pixels directly).
//
// MIX DIRECTION (D5): `dt_iop_image_linear_blend(out, amt, in)` =
// `buf = amt·buf + (1−amt)·other` (`imagebuf.c:452`) with buf = blurred,
// other = in ⇒ **out = amt·blurred + (1−amt)·in** — matches `soften_mix`
// (`soften.cl:164`). amount = 0 ⇒ out == in EXACTLY (blit fast path).
//
// FLAT-FIELD IDENTITY (D5): saturation 100 + brightness 0 ⇒
// overexposed == identity on ANY image ⇒ blur of a flat == the flat ⇒
// mix == the flat at ANY amount. Pinned by the T3 probe (no dt-cli leg
// needed — the identity holds for any DC-1 blur, L017-proof).
//
// FRAME CONVENTION (L020): identity-ROI module (sharpen twin) — forward
// keeps input; backward widens by ceil(3σ) symmetrically (NOT a dt
// re-add; the backward walk seeds from the forward result).
//
// HALO (D7): ceil(3σ) (D-G5); `tileHalo` = dt's tiling overlap wdh =
// ceil(3σ) — same coincidence as highpass (finite-support source).
// ─────────────────────────────────────────────────────────────────────────

public enum SoftenKernel {
    public static let overFunction = "soften_overexposed"
    public static let mixFunction = "soften_mix"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class SoftenModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// dt `size` ∈ [0, 100] (soften.c:46), default 50.
        public var size: Float
        /// dt `saturation` ∈ [0, 100] (soften.c:47), default 100.
        public var saturation: Float
        /// dt `brightness` ∈ [−2, 2] EV (soften.c:48), default 0.33.
        public var brightness: Float
        /// dt `amount` ∈ [0, 100] (soften.c:49), default 50.
        public var amount: Float

        public init(size: Float = 50.0, saturation: Float = 100.0, brightness: Float = 0.33, amount: Float = 50.0) {
            self.size = size
            self.saturation = saturation
            self.brightness = brightness
            self.amount = amount
        }
    }

    public static let opName = "soften"

    /// Darktable v50 order slot 66.0 — after grain (65.0), before
    /// splittoning (67.0) (`iop_order.c` verbatim; V50Order table).
    public static let iopOrder: Float = 66.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    static let neutralEps: Float = 1e-6

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var overBuffer: (any MTLBuffer)?
    private var mixBuffer: (any MTLBuffer)?
    private var committed: Params?

    // Scratch planes, cached per (width × height) — single-owner contract.
    private var scratchWidth = 0
    private var scratchHeight = 0
    private var overTexture: (any MTLTexture)?
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

        if overBuffer == nil || mixBuffer == nil || committed != params {
            var over = OverUniforms(
                saturation: params.saturation / 100.0,
                brightness: exp2(params.brightness))
            var mix = MixUniforms(amount: params.amount / 100.0)
            if overBuffer == nil {
                overBuffer = resolved.makeBuffer(
                    length: MemoryLayout<OverUniforms>.stride, options: .storageModeShared)
                mixBuffer = resolved.makeBuffer(
                    length: MemoryLayout<MixUniforms>.stride, options: .storageModeShared)
            }
            if let buffer = overBuffer {
                withUnsafeBytes(of: &over) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<OverUniforms>.stride)
                }
            }
            if let buffer = mixBuffer {
                withUnsafeBytes(of: &mix) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<MixUniforms>.stride)
                }
            }
            committed = params
        }
        // The mix uniforms ride piece.data (the single-buffer seam);
        // the over uniforms are read from the committed copy at process
        // time (same isolation domain — CropModule precedent).
        piece.data = mixBuffer
    }

    /// MSL mirror of `SoftenOverUniforms`.
    struct OverUniforms {
        var saturation: Float
        var brightness: Float
        var pad0: Float = 0
        var pad1: Float = 0
    }

    /// MSL mirror of `SoftenMixUniforms`. srcOffset rides per-run
    /// (sharpen precedent — committed buffer carries the commit-time half).
    struct MixUniforms {
        var amount: Float
        var pad0: Float = 0
        var srcOffsetX: Int32 = 0
        var srcOffsetY: Int32 = 0
        // NOTE: MSL pads to 16 bytes — pad2 dropped, struct is 4+4+8 = 16.
    }

    /// dt radius chain (`soften.c:138-142`, iscale 1 — the Lightamer pipe
    /// carries dt's full-res piece scale; dscIn is the pipe-level plane
    /// geometry, dt's `piece->iwidth`). `internal` for tests.
    static func radius(size: Float, bufW: Int, bufH: Int, scale: Float) -> Int {
        let mrad = Int((Double(bufW * bufW + bufH * bufH).squareRoot() * 0.01).rounded(.down))
        guard mrad > 0 else { return 0 }
        let rad = Float(mrad) * (min(100.0, size + 1.0) / 100.0)
        return min(mrad, Int((rad * scale).rounded(.up)))
    }

    /// dt σ correlation (`soften.c:306`, BOX_ITERATIONS = 8).
    /// `internal` for tests.
    static func sigma(size: Float, bufW: Int, bufH: Int, scale: Float) -> Float {
        let r = Float(radius(size: size, bufW: bufW, bufH: bufH, scale: scale))
        return ((r * (r + 1) * 8 + 2) / 3).squareRoot()
    }

    /// The ROI/tile halo (D7): ceil(3σ). `internal` for tests.
    static func halo(size: Float, bufW: Int, bufH: Int, scale: Float) -> Int {
        Int((3 * sigma(size: size, bufW: bufW, bufH: bufH, scale: scale)).rounded(.up))
    }

    /// Neutral predicate (D9): amount ≈ 0 ⇒ blit identity (the overexposed
    /// + blur legs cannot move the image through a 0 mix).
    /// `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        abs(p.amount / 100.0) < Self.neutralEps
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// D-G5 backward expansion (L020 frame note above): symmetric halo
    /// widen; the pipe clamps to the upstream plane. Neutral → verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else {
            input = roi
            return
        }
        if abs(uniforms.pointee.amount) < Self.neutralEps { input = roi; return }
        let h = Self.halo(
            size: committed?.size ?? 50,
            bufW: piece.dscIn.width, bufH: piece.dscIn.height, scale: roi.scale)
        guard h > 0 else { input = roi; return }
        input = roi
        input.x -= h
        input.y -= h
        input.width += 2 * h
        input.height += 2 * h
    }

    // MARK: Tile seam (D7 — halo == dt overlap wdh here)

    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else { return 0 }
        if abs(uniforms.pointee.amount) < Self.neutralEps { return 0 }
        return Self.halo(
            size: committed?.size ?? 50,
            bufW: piece.dscIn.width, bufH: piece.dscIn.height, scale: roi.scale)
    }

    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else { return 0 }
        return abs(uniforms.pointee.amount) < Self.neutralEps ? 0 : 64
    }

    // MARK: Scratch management (per-size cached; .shared storage — L018)

    private func ensureScratch(width: Int, height: Int) throws {
        guard width != scratchWidth || height != scratchHeight else { return }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(SoftenKernel.overFunction, nil)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        overTexture = resolved.makeTexture(descriptor: descriptor)
        blurredTexture = resolved.makeTexture(descriptor: descriptor)
        blurPlanesBuffer = resolved.makeBuffer(
            length: width * height * MemoryLayout<Float>.stride * 4 * 2,
            options: .storageModeShared)
        scratchWidth = width
        scratchHeight = height
    }

    // MARK: Process (overexposed → IIR blur → mix, soften.c:105-148 shape)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let mixUniformsBuffer = piece.data, let overUniformsBuffer = overBuffer else {
            throw MetalError.psoCreationFailed(SoftenKernel.mixFunction, nil)
        }
        let mix = mixUniformsBuffer.contents().assumingMemoryBound(to: MixUniforms.self).pointee
        // D9 neutral fast path: amount 0 ⇒ out == in.
        if abs(mix.amount) < Self.neutralEps {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let sigma = Self.sigma(
            size: committed?.size ?? 50,
            bufW: piece.dscIn.width, bufH: piece.dscIn.height, scale: roiIn.scale)
        try ensureScratch(width: input.width, height: input.height)
        guard let over = overTexture, let blurPlanes = blurPlanesBuffer,
              let blurred = blurredTexture else {
            throw MetalError.psoCreationFailed(SoftenKernel.overFunction, nil)
        }

        // Step 1 — the overexposed image.
        do {
            let session = try await metal.makeEncoder(functionName: SoftenKernel.overFunction)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(over, index: 1)
            session.encoder.setBuffer(overUniformsBuffer, offset: 0, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: input.width, height: input.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
            )
            session.encoder.endEncoding()
            session.commandBuffer.commit()
        }

        // Step 2 — the IIR domain blur at dt's σ (UNBOUNDED — dt's box
        // mean clamps nothing).
        try await GaussianBlur.blur(
            input: over, output: blurred, planes: blurPlanes,
            sigma: sigma, order: .zero,
            boundsMin: SIMD4(repeating: -Float.greatestFiniteMagnitude),
            boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
            metal: metal
        )

        // Step 3 — the mix (per-run uniforms: shared-buffer upload,
        // NOT setBytes — ashift/lens postmortem).
        var runUniforms = MixUniforms(
            amount: mix.amount,
            srcOffsetX: Int32(roiOut.x - roiIn.x),
            srcOffsetY: Int32(roiOut.y - roiIn.y))
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &runUniforms,
            length: MemoryLayout<MixUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: SoftenKernel.mixFunction)
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

    /// Whole-window blit (dt `copy_image_roi` fast path, `imagebuf.c`).
    /// Sync (no GPU wait — same-queue FIFO orders it; the caller's fence
    /// covers readback, L014).
    private func blitIdentity(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) throws {
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        guard dx >= 0, dy >= 0 else { return }
        let width = min(roiOut.width, roiIn.width, output.width, max(0, input.width - dx))
        let height = min(roiOut.height, roiIn.height, output.height, max(0, input.height - dy))
        guard width > 0, height > 0 else { return }
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: dx, y: dy, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008: encode close precedes commit, never defer
        commandBuffer.commit()
    }
}
