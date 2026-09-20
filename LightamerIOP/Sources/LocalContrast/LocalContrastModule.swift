import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// LOCAL CONTRAST — clarity (Plan 04-05-T2, IOP-DETAIL-02).
//
// Darktable reference: `src/iop/bilat.c` (tree dc58cf0ba1) — REFERENCED,
// NOT ported (D-G3):
//   - params     :49-56   mode (bilateral=0/local-laplacian=1 DEFAULT) /
//                           sigma_r DEFAULT 0.5 / sigma_s DEFAULT 0.5 /
//                           detail ∈ [−1,4] DEFAULT 0.25 / midtone
//   - iscale comp:341-344 `scale = max(iscale/roi.scale, 1)`,
//                           sigma_s_eff = sigma_s/scale
//   - tiling     :259-290 overlap = ceil(4·sigma_s) (bilateral) /
//                           rad = min(w, ceil(256·scale)) (laplacian)
//   - commit     :293-309 verbatim copy (no derivation)
//   - default_colorspace IOP_CS_LAB; v50 slot 54.0 ("improve clarity
//                           after all the bad things we have done to it
//                           with tonemapping" — sits after sigmoid 45.3)
//
// D-G3 IMPLEMENTATION: luma (Lab L, T0) → EIGF/guided detail-preserving
// decomposition (03-05 toneequal leg: ds bilinear → pack4 → Deriche IIR
// gaussian → no-mask blend, `toneeq_*` kernels dispatched from here) as
// the base layer → `out = luma + detail·(luma − base)`. The toneequal
// module owns those kernels; this module drives them with its own
// scratch (uniform helper structs are module-local — Swift cannot reuse
// toneequal's `private` dispatch helpers, only the kernel names).
//
// INTENTIONAL DIVERGENCES (D6 + T0):
// 1. **No bilateral grid, no local-laplacian** — the EIGF leg IS the
//    clarity decomposition (D-G3 lock). dt-cli reference unavailable by
//    construction; golden = synthesized EIGF formula + detail=0 exact
//    identity + step-image direction.
// 2. **sigmaS = full-res pixel radius** (self-defined — dt's sigma_s is
//    grid units with no pixel mapping): σ_eff = sigmaS·scale (sharpen
//    convention); EIGF scaling/ds_sigma math verbatim from toneequal
//    (scaling = clamp(r,1,4), ds_sigma = max(r/scaling,1)).
// 3. **sigmaR → EIGF feathering eps = sigmaR²·4** (self-defined): default
//    sigmaR 0.5 ⇒ eps 1.0 = toneequal's default (1/feathering 1).
// 4. **No `midtone`, single iteration, no-mask, quantization 0** — the
//    mask/quantize path is Phase 6. `midtones` masking arrives with
//    layers; iterations beyond 1 are a panel stretch.
// 5. **scene-referred purity** (T0 note): Lab L base, conversion fused
//    in-kernel; linear-Y upgrade reserved Phase 8+.
//
// FRAME CONVENTION (L020): identity-ROI module (sharpen twin) — forward
// keeps input; backward widens by the halo symmetrically (NOT a dt
// re-add; the backward walk seeds from the forward result).
//
// HALO (D7): base-leg support = ceil(3·r_eff) + 8 (ds bilinear corner
// margin). `tileHalo` = toneequal-coefficient 4r+65 (IIR runway, tile ==
// whole <1e-6) — the TilingPlan FULL second consumer after toneequal.
// ─────────────────────────────────────────────────────────────────────────

public enum LocalContrastKernel {
    public static let prepFunction = "localcontrast_prep"
    public static let applyFunction = "localcontrast_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class LocalContrastModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Clarity strength ∈ [−1, 4] (dt `detail`, bilat.c:54). 0 = blit
        /// identity. Negative values soften local contrast.
        public var detail: Float
        /// Spatial radius in full-res pixels (v1 semantics, D6 note 2).
        /// ∈ [1, 100], default 20 (clarity-scale large radius).
        public var sigmaS: Float
        /// Range sigma (v1 semantics, D6 note 3): eps = sigmaR²·4.
        /// ∈ [0.05, 2], default 0.5.
        public var sigmaR: Float

        public init(detail: Float = 0.0, sigmaS: Float = 20.0, sigmaR: Float = 0.5) {
            self.detail = detail
            self.sigmaS = sigmaS
            self.sigmaR = sigmaR
        }
    }

    /// dt op string for the v50 54.0 slot (bilat.c `name()` returns
    /// "local contrast" as the GUI label; the op is `bilat`).
    public static let opName = "bilat"

    /// Darktable v50 order slot 54.0 — after relight (53.0), before
    /// colorcorrection (55.0) (`iop_order.c` verbatim; V50Order table).
    public static let iopOrder: Float = 54.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    static let neutralEps: Float = 1e-6

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    // Scratch planes, cached per (width × height) — single-owner contract
    // (ShadhiModule). r32 luma pair + ds planes + gaussian buffer.
    private var scratchWidth = 0
    private var scratchHeight = 0
    private var dsWidth = 0
    private var dsHeight = 0
    private var lumaTexture: (any MTLTexture)?
    private var baseTexture: (any MTLTexture)?
    private var dsImage: (any MTLTexture)?
    private var dsPacked: (any MTLTexture)?
    private var dsAv: (any MTLTexture)?
    private var gaussPlanes: (any MTLBuffer)?

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
            var uniforms = ApplyUniforms(detail: params.detail)
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: MemoryLayout<ApplyUniforms>.stride, options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                withUnsafeBytes(of: &uniforms) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<ApplyUniforms>.stride)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    /// MSL mirror of `LocalContrastApplyUniforms` (LocalContrastKernels.metal).
    /// srcOffset rides per-run (roiOut − roiIn; 0 under tiling), so the
    /// committed buffer carries the commit-time half; process uploads the
    /// full struct per run (sharpen precedent).
    struct ApplyUniforms {
        var detail: Float
        var pad0: Float = 0
        var srcOffsetX: Int32 = 0
        var srcOffsetY: Int32 = 0
    }

    /// Effective pixel radius (D6 note 2): sigmaS·scale. `internal` for tests.
    static func effectiveRadius(sigmaS: Float, scale: Float) -> Float {
        max(1, sigmaS * scale)
    }

    /// EIGF eps from sigmaR (D6 note 3): sigmaR²·4. `internal` for tests.
    static func feathering(sigmaR: Float) -> Float {
        sigmaR * sigmaR * 4
    }

    /// EIGF downsample geometry (toneequal verbatim): scaling =
    /// clamp(r,1,4), ds = floor(size/scaling). `internal` for tests.
    static func downsample(width: Int, height: Int, radius: Float) -> (w: Int, h: Int, sigma: Float) {
        let scaling = max(min(radius, 4.0), 1.0)
        let dsSigma = max(radius / scaling, 1.0)
        return (max(1, Int(Float(width) / scaling)), max(1, Int(Float(height) / scaling)), dsSigma)
    }

    /// The ROI/tile halo in pixels (D7): ceil(3·r_eff) + 8.
    /// `internal` for tests.
    static func halo(sigmaS: Float, scale: Float) -> Int {
        Int((3 * effectiveRadius(sigmaS: sigmaS, scale: scale)).rounded(.up)) + 8
    }

    /// Neutral predicate (D9): detail ≈ 0 ⇒ blit identity.
    /// `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        abs(p.detail) < Self.neutralEps
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// D-G5 backward expansion (L020 frame note above): symmetric halo
    /// widen; the pipe clamps to the upstream plane. Neutral → verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: ApplyUniforms.self) else {
            input = roi
            return
        }
        if abs(uniforms.pointee.detail) < Self.neutralEps { input = roi; return }
        let h = Self.halo(sigmaS: committed?.sigmaS ?? 20, scale: roi.scale)
        input = roi
        input.x -= h
        input.y -= h
        input.width += 2 * h
        input.height += 2 * h
    }

    // MARK: Tile seam (03-05-T6 — D7 dual-constant note; FULL 2nd consumer)

    /// toneequal-coefficient IIR runway (D7): 4·r_eff + 65 — tile output
    /// matches whole-plane execution to <1e-6. Neutral ⇒ 0.
    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: ApplyUniforms.self) else { return 0 }
        if abs(uniforms.pointee.detail) < Self.neutralEps { return 0 }
        let r = Int(Self.effectiveRadius(sigmaS: committed?.sigmaS ?? 20, scale: roi.scale))
        return 4 * max(r, 1) + 65
    }

    /// luma pair (8 B) + ds planes + gaussian share — 12 B/px when active
    /// (toneequal working-set figure); the blit fast path reports 0.
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: ApplyUniforms.self) else { return 0 }
        return abs(uniforms.pointee.detail) < Self.neutralEps ? 0 : 12
    }

    // MARK: Scratch management (per-size cached; .shared storage — L018)

    private static func r32(_ device: any MTLDevice, width: Int, height: Int) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)!
    }

    private static func rgba32(_ device: any MTLDevice, width: Int, height: Int) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return device.makeTexture(descriptor: d)!
    }

    private func ensureScratch(width: Int, height: Int, dsW: Int, dsH: Int) throws {
        let sOK = scratchWidth == width && scratchHeight == height
            && dsWidth == dsW && dsHeight == dsH && lumaTexture != nil
        guard !sOK else { return }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(LocalContrastKernel.prepFunction, nil)
        }
        lumaTexture = Self.rgba32(resolved, width: width, height: height)
        baseTexture = Self.r32(resolved, width: width, height: height)
        dsImage = Self.r32(resolved, width: dsW, height: dsH)
        dsPacked = Self.rgba32(resolved, width: dsW, height: dsH)
        dsAv = Self.rgba32(resolved, width: dsW, height: dsH)
        gaussPlanes = resolved.makeBuffer(
            length: max(dsW, 1) * max(dsH, 1) * 16 * 2,
            options: .storageModeShared)
        scratchWidth = width
        scratchHeight = height
        dsWidth = dsW
        dsHeight = dsH
    }

    // MARK: Process (prep → EIGF no-mask base → clarity apply)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let uniformsBuffer = piece.data else {
            throw MetalError.psoCreationFailed(LocalContrastKernel.applyFunction, nil)
        }
        let uniforms = uniformsBuffer.contents().assumingMemoryBound(to: ApplyUniforms.self).pointee
        // D9 neutral fast path: detail 0 ⇒ out == luma ⇒ blit identity.
        if abs(uniforms.detail) < Self.neutralEps {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let params = committed ?? Params()
        let width = input.width
        let height = input.height
        let rEff = Self.effectiveRadius(sigmaS: params.sigmaS, scale: roiIn.scale)
        let (dsW, dsH, dsSigma) = Self.downsample(width: width, height: height, radius: rEff)
        try ensureScratch(width: width, height: height, dsW: dsW, dsH: dsH)
        guard let luma = lumaTexture, let base = baseTexture,
              let dsImg = dsImage, let packed = dsPacked,
              let av = dsAv, let planes = gaussPlanes else {
            throw MetalError.psoCreationFailed(ToneEqualKernel.lumaEstimateFunction, nil)
        }

        // Stage 1 — Rec2020 → raw Lab (4-channel; the EIGF leg blurs the
        // packed moments of the L plane — guide == mask, no-mask path).
        try await metal.dispatch2DTexture(
            functionName: LocalContrastKernel.prepFunction,
            input: input,
            output: luma
        )

        // Stage 2 — EIGF no-mask leg (toneequal kernels, single iteration):
        // ds bilinear (the prep's L channel — toneeq_bilinear_1c reads .r,
        // which IS L on the prep Lab plane) → pack4 (guide == mask) →
        // IIR gaussian → blend at full res (image == the prep plane; the
        // kernel upsamples av inline and writes the base into `base`).
        try await dispatchBilinear(
            metal, input: luma, output: dsImg,
            srcW: width, srcH: height, dstW: dsW, dstH: dsH)
        try await dispatchPack(metal, guide: dsImg, mask: dsImg, output: packed)
        try await GaussianBlur.blur(
            input: packed, output: av, planes: planes,
            sigma: dsSigma,
            boundsMin: SIMD4(repeating: Float(exp2(-16.0))),
            boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
            metal: metal)
        try await dispatchBlendNoMask(
            metal, image: luma, aux: av, output: base,
            feathering: Self.feathering(sigmaR: params.sigmaR),
            auxW: dsW, auxH: dsH, srcW: width, srcH: height)

        // Stage 3 — the clarity apply (per-run uniforms: srcOffset needs
        // the run ROIs — shared-buffer upload, NOT setBytes, per the
        // ashift/lens async-commit postmortem).
        var runUniforms = ApplyUniforms(
            detail: uniforms.detail,
            srcOffsetX: Int32(roiOut.x - roiIn.x),
            srcOffsetY: Int32(roiOut.y - roiIn.y))
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &runUniforms,
            length: MemoryLayout<ApplyUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: LocalContrastKernel.applyFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(base, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(runBuffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    // MARK: toneeq-kernel dispatch (shapes mirror ToneEqualModule's helpers)


    private func dispatchBilinear(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        srcW: Int, srcH: Int, dstW: Int, dstH: Int
    ) async throws {
        struct U {
            var srcWidth: UInt32
            var srcHeight: UInt32
            var dstWidth: UInt32
            var dstHeight: UInt32
        }
        var u = U(srcWidth: UInt32(srcW), srcHeight: UInt32(srcH),
                  dstWidth: UInt32(dstW), dstHeight: UInt32(dstH))
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.bilinear1cFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&u, length: MemoryLayout<U>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: dstW, height: dstH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func dispatchPack(
        _ metal: MetalContext, guide: any MTLTexture, mask: any MTLTexture,
        output: any MTLTexture
    ) async throws {
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.pack4Function)
        session.encoder.setTexture(guide, index: 0)
        session.encoder.setTexture(mask, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.dispatchThreads(
            MTLSize(width: dsWidth, height: dsHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// toneeq_blend mode 0 (EIGF no-mask) at full res with the bilinear av
    /// upsample inlined (dt upsamples then blends — the kernel does both).
    private func dispatchBlendNoMask(
        _ metal: MetalContext, image: any MTLTexture, aux: any MTLTexture,
        output: any MTLTexture, feathering: Float,
        auxW: Int, auxH: Int, srcW: Int, srcH: Int
    ) async throws {
        struct U {
            var mode: Int32
            var upsample: Int32
            var geomean: Int32
            var feathering: Float
            var auxWidth: UInt32
            var auxHeight: UInt32
            var srcWidth: UInt32
            var srcHeight: UInt32
        }
        var u = U(
            mode: 0, upsample: 1, geomean: 0, feathering: feathering,
            auxWidth: UInt32(auxW), auxHeight: UInt32(auxH),
            srcWidth: UInt32(srcW), srcHeight: UInt32(srcH))
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.blendFunction)
        session.encoder.setTexture(image, index: 0)
        session.encoder.setTexture(image, index: 1)
        session.encoder.setTexture(aux, index: 2)
        session.encoder.setTexture(output, index: 3)
        session.encoder.setBytes(&u, length: MemoryLayout<U>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: srcW, height: srcH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
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
