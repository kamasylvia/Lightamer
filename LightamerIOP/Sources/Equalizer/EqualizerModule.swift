import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// EQUALIZER — detail enhancement (Plan 04-05-T4, IOP-DETAIL-04).
//
// Darktable reference: `src/iop/equalizer.c` (tree dc58cf0ba1) — REFERENCED,
// NOT ported:
//   - legacy equalizer (DEPRECATED): 3 channels × 6-point curves over a
//     lifting-scheme wavelet (`:113-166` process; `equalizer_x/y[3][6]`
//     params, `equalizer.c:45-48`)
//   - the CONTRAST equalizer (the live module): edge-aware wavelet 6
//     bands (`equalizer_eaw.h` `dt_iop_equalizer_wtf` + `atrous.cl`
//     `eaw_decompose/eaw_synthesize/eaw_addbuffers`)
//   - default_colorspace IOP_CS_LAB; v50 slot 27.0
//
// D-G4 IMPLEMENTATION: GaussianBlur half-octave pyramid (σ doubling
// 1/2/4/8/16 over the L plane — 5 blurs + prep = 6 levels, 5 residual
// bands + coarse) → per-band residuals → per-band scalar gains (6
// sliders) → recombine. The band→gain→recombine architecture mirrors
// toneequal's CorrectionLUT "parameters → per-band values → apply"
// (D-G4 lock); v1 emits UNIFORM gains straight from the sliders — no
// 80001-entry LUT, because the LUT exists to serve a curve and six
// sliders need six uniforms (the architecture is isomorphic, the
// transfer function is trivial).
//
// LAB DOMAIN (T0): dt is IOP_CS_LAB; only L runs the pyramid (a/b ride
// through — sharpen precedent; dt hangs a curve per channel, v1 a
// single gain set — deviation #2 below). Conversion fused in-kernel
// (LabMath.h). scene-referred-purity note as sharpen's divergence.
//
// INTENTIONAL DIVERGENCES:
// 1. **Pure gaussian bands, no edge-aware weights** (T0 decision
//    D-04-05-T0-3): dt eaw's `gweight` (1/(|Δ|+1e-5) edge stopping) is
//    absent — halos at strong gains are possible; EIGF-weight接入 is a
//    stretch goal (not done). Recorded here, not hidden.
// 2. **One gain set for L only** (DECISIONS D8): dt's 3×6 curves → v1
//    six sliders on L, a/b straight through. Per-channel curves are a
//    stretch (panel + params shape change).
// 3. **Blur base = Deriche IIR** (shared GaussianBlur) — dt eaw uses
//    à-trous separable kernels; the pyramid SEMANTIC (half-octave
//    residuals) is shared, the kernel shape follows the plan Goal.
//
// FRAME CONVENTION (L020): identity-ROI module (sharpen twin) — forward
// keeps input; backward widens by the halo symmetrically (NOT a dt
// re-add; the backward walk seeds from the forward result).
//
// HALO (D7): the coarsest blur (σ=16) dominates: ceil(3·16) = 48 + 16
// pyramid-chain margin = 64. `tileHalo` = 4·16+65 = 129 (toneequal
// coefficient at the coarse radius — tile == whole <1e-6).
// ─────────────────────────────────────────────────────────────────────────

public enum EqualizerKernel {
    public static let prepFunction = "equalizer_prep"
    public static let recombineFunction = "equalizer_recombine"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class EqualizerModule: IOPModule {

    /// Six band gains: g0..g4 = the five half-octave residual bands
    /// (finest → coarsest), g5 = the coarse base. 1.0 = neutral.
    public struct Params: Codable, Hashable, Sendable {
        public var g0: Float
        public var g1: Float
        public var g2: Float
        public var g3: Float
        public var g4: Float
        public var g5: Float

        public init(
            g0: Float = 0.0, g1: Float = 0.0, g2: Float = 0.0,
            g3: Float = 0.0, g4: Float = 0.0, g5: Float = 0.0
        ) {
            self.g0 = g0
            self.g1 = g1
            self.g2 = g2
            self.g3 = g3
            self.g4 = g4
            self.g5 = g5
        }

        /// All-zero deltas = the blit-identity fast path.
        public static let neutral = Params()

        var gains: [Float] { [g0, g1, g2, g3, g4, g5] }
    }

    public static let opName = "equalizer"

    /// Darktable v50 order slot 27.0 — after profile_gamma (26.0), before
    /// colorin (28.0) (`iop_order.c` verbatim; V50Order table).
    public static let iopOrder: Float = 27.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// The pyramid sigmas (half-octave doubling). `internal` for tests.
    static let pyramidSigmas: [Float] = [1, 2, 4, 8, 16]

    static let neutralEps: Float = 1e-6

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    // Scratch planes, cached per (width × height): prep + 5 blur levels +
    // the gaussian buffer (shared across the 5 sequential blurs).
    private var scratchWidth = 0
    private var scratchHeight = 0
    private var prepTexture: (any MTLTexture)?
    private var levelTextures: [(any MTLTexture)] = []
    private var blurPlanesBuffer: (any MTLBuffer)?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            var uniforms = RecombineUniforms(gains: params.gains.map { 1 + $0 })
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: MemoryLayout<RecombineUniforms>.stride, options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                withUnsafeBytes(of: &uniforms) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<RecombineUniforms>.stride)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    /// MSL mirror of `EqualizerRecombineUniforms` — six scalar floats
    /// (NOT an array: the ashift `float hinv[9]` packing postmortem —
    /// scalar floats are 4-byte aligned on both sides).
    struct RecombineUniforms {
        var g0: Float
        var g1: Float
        var g2: Float
        var g3: Float
        var g4: Float
        var g5: Float
        // NOTE: NO pad0 — MSL packs int2 at offset 24 (4-byte aligned),
        // Swift Int32 pair matches; struct is 6×4 + 8 = 32 bytes both sides.
        var srcOffsetX: Int32 = 0
        var srcOffsetY: Int32 = 0

        init(gains: [Float]) {
            self.g0 = gains.count > 0 ? gains[0] : 1
            self.g1 = gains.count > 1 ? gains[1] : 1
            self.g2 = gains.count > 2 ? gains[2] : 1
            self.g3 = gains.count > 3 ? gains[3] : 1
            self.g4 = gains.count > 4 ? gains[4] : 1
            self.g5 = gains.count > 5 ? gains[5] : 1
        }
    }

    /// Neutral predicate (D9): all-zero deltas ⇒ blit identity.
    /// `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        p.gains.allSatisfy { abs($0) < Self.neutralEps }
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// D-G5 backward expansion (L020 frame note above): fixed 64px
    /// symmetric widen; the pipe clamps to the upstream plane. Neutral →
    /// verbatim (cache-neutral seed takes the identity path).
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: RecombineUniforms.self) else {
            input = roi
            return
        }
        let u = uniforms.pointee
        let neutral = [u.g0, u.g1, u.g2, u.g3, u.g4, u.g5]
            .allSatisfy { abs($0 - 1) < Self.neutralEps }
        if neutral { input = roi; return }
        let h = 64
        input = roi
        input.x -= h
        input.y -= h
        input.width += 2 * h
        input.height += 2 * h
    }

    // MARK: Tile seam (D7)

    /// 4·16 + 65 = 129 — the toneequal coefficient at the coarse radius.
    /// Neutral ⇒ 0.
    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: RecombineUniforms.self) else { return 0 }
        let u = uniforms.pointee
        let neutral = [u.g0, u.g1, u.g2, u.g3, u.g4, u.g5]
            .allSatisfy { abs($0 - 1) < Self.neutralEps }
        return neutral ? 0 : 129
    }

    /// prep + 5 levels (16 B each = 96 B) + planes share (32 B) ≈ 128 B/px
    /// when active; the blit fast path reports 0.
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: RecombineUniforms.self) else { return 0 }
        let u = uniforms.pointee
        let neutral = [u.g0, u.g1, u.g2, u.g3, u.g4, u.g5]
            .allSatisfy { abs($0 - 1) < Self.neutralEps }
        return neutral ? 0 : 128
    }

    // MARK: Scratch management (per-size cached; .shared storage — L018)

    private func ensureScratch(width: Int, height: Int) throws {
        guard width != scratchWidth || height != scratchHeight || levelTextures.isEmpty else { return }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(EqualizerKernel.prepFunction, nil)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        prepTexture = resolved.makeTexture(descriptor: descriptor)
        levelTextures = (0..<5).map { _ in resolved.makeTexture(descriptor: descriptor)! }
        // The blur planes are a device BUFFER (L018 defect 1/2 discipline,
        // ShadhiModule pattern) — shared across the 5 sequential blurs.
        blurPlanesBuffer = resolved.makeBuffer(
            length: width * height * MemoryLayout<Float>.stride * 4 * 2,
            options: .storageModeShared)
        scratchWidth = width
        scratchHeight = height
    }

    // MARK: Process (prep → 5-level pyramid → recombine)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let uniformsBuffer = piece.data else {
            throw MetalError.psoCreationFailed(EqualizerKernel.recombineFunction, nil)
        }
        let uniforms = uniformsBuffer.contents().assumingMemoryBound(to: RecombineUniforms.self).pointee
        // D9 neutral fast path: all-zero deltas ⇒ the pyramid recombines
        // telescopically to the input — blit identity, bit-exact.
        let neutral = [uniforms.g0, uniforms.g1, uniforms.g2, uniforms.g3, uniforms.g4, uniforms.g5]
            .allSatisfy { abs($0 - 1) < Self.neutralEps }
        if neutral {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        try ensureScratch(width: input.width, height: input.height)
        guard let prep = prepTexture, let planes = blurPlanesBuffer,
              levelTextures.count == 5 else {
            throw MetalError.psoCreationFailed(EqualizerKernel.prepFunction, nil)
        }

        // Step 1 — Rec2020 → raw Lab.
        try await metal.dispatch2DTexture(
            functionName: EqualizerKernel.prepFunction,
            input: input,
            output: prep
        )

        // Step 2 — the pyramid: level[i] = blur(predecessor, σᵢ),
        // chained (dt eaw decomposes level-by-level; the IIR has infinite
        // support so chaining == direct — and halves the pass count vs
        // blurring the prep 5× independently).
        var predecessor: any MTLTexture = prep
        for (i, sigma) in Self.pyramidSigmas.enumerated() {
            let level = levelTextures[i]
            try await GaussianBlur.blur(
                input: predecessor, output: level, planes: planes,
                sigma: sigma, order: .zero,
                boundsMin: SIMD4(repeating: -Float.greatestFiniteMagnitude),
                boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
                metal: metal
            )
            predecessor = level
        }

        // Step 3 — the recombine (7 textures + per-run uniforms:
        // shared-buffer upload, NOT setBytes — ashift/lens postmortem).
        var runUniforms = RecombineUniforms(gains: [
            uniforms.g0, uniforms.g1, uniforms.g2,
            uniforms.g3, uniforms.g4, uniforms.g5])
        runUniforms.srcOffsetX = Int32(roiOut.x - roiIn.x)
        runUniforms.srcOffsetY = Int32(roiOut.y - roiIn.y)
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &runUniforms,
            length: MemoryLayout<RecombineUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: EqualizerKernel.recombineFunction)
        session.encoder.setTexture(prep, index: 0)
        for (i, level) in levelTextures.enumerated() {
            session.encoder.setTexture(level, index: 1 + i)
        }
        session.encoder.setTexture(input, index: 6)
        session.encoder.setTexture(output, index: 7)
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
        guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
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
