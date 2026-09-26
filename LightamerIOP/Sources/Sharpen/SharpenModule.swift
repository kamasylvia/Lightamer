import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// SHARPEN — unsharp mask (Plan 04-05-T1, IOP-DETAIL-01).
//
// Darktable reference: `src/iop/sharpen.c` (tree dc58cf0ba1)
//   - params v1    :44-48   radius ∈ [0,99] DEFAULT 2 / amount ∈ [0,2]
//                           DEFAULT 0.5 / threshold ∈ [0,100] DEFAULT 0.5
//   - process_cl   :126-231 FIR h/v blur (rad taps) + sharpen_mix
//   - tiling       :235-248 overlap = rad, factor 2.1/3.0
//   - process CPU  :250-367 border rows/cols pass through unsharpened
//   - commit       :369-379 **d->radius = 2.5·p->radius** (the mask must
//                           fit 2.5σ); amount/threshold verbatim
//   - flags        SUPPORTS_BLENDING | ALLOW_TILING; colorspace IOP_CS_LAB
//   - v50 slot 35.0 ("same, worst than atrous in same use-case")
//
// σ CHAIN (DECISIONS D1): FIR σ² = (1/2.5²)·(p->radius·scale/iscale)²
// (`sharpen.c:160-161`) with the COMMITTED radius 2.5·p->radius, so the
// factors cancel: **σ = p->radius·scale** (iscale 1 — the Lightamer pipe
// carries dt's full-res piece scale, shadhi precedent). rad =
// min(12, ceil(2.5·radius·scale)) — MAXR 12 (`sharpen.c:138,240`).
//
// LAB DOMAIN (T0 decision D-04-05-T0-1): dt is IOP_CS_LAB, L channel only
// (a/b ride through — CPU `:358-359`, CL `sharpen_mix` writes pixel.x).
// Lightamer fuses the shared Rec2020→Lab→Rec2020 conversion
// (Common/LabMath.h, Plan 03-03-T1) around the IIR + mix.
//
// INTENTIONAL DIVERGENCES:
// 1. **Blur base = Deriche IIR (shared GaussianBlur), not dt's truncated
//    FIR** — the plan Goal mandates the reuse ("`GaussianBlur`（Deriche
//    IIR 双平面）+ `sharpen_mix`"). The synthesized reference mirrors the
//    IIR side (`dt_gauss_coeffs` + recursion), so parity proves the port
//    correct, not dt-identical.
// 2. **Default amount = 0 (neutral), not dt's 0.5** — the editing seed must
//    be cache-neutral (exposure-0EV style, ashift D6); `Params()` is the
//    blit-identity fast path. Head note of plan "dt 默认 0 中性" reads as
//    the amount gate, not the dt $DEFAULT (2.0/0.5/0.5 — recorded erratum).
// 3. **Border is approximate, not pass-through** (kernel header D12): dt's
//    CPU/CL legs leave the outer `rad` frame unsharpened; the IIR's edge
//    clamp makes delta ≈ 0 there instead. Interior parity <1e-4.
// 4. **scene-referred purity**: Lab L is display-referred-era semantics;
//    the working space stays linear Rec2020, conversion fused in-kernel
//    (T0 intentional-divergence note, Phase 8+ linear-Y upgrade reserved).
//
// FRAME CONVENTION (L020): detail modules are identity-ROI —
// `modifyROIOut` keeps the input verbatim; `modifyROIIn` widens by the
// halo symmetrically (xy − h, w/h + 2h) — NOT a dt formula re-add: the
// backward walk seeds from the forward result (upstream-relative coords),
// so any dt-style origin re-add would double-offset (crop postmortem).
//
// HALO (D-G5 main proof): ceil(3σ) — the visible-energy 99.7% envelope,
// calibrated against GaussianBlurTests' impulse envelope. `tileHalo` is
// the SEPARATE constant 4r+65 (toneequal 03-05 derivation: the IIR needs
// ≈14.5σ_ds runway for tile==whole <1e-6) — ROI halo serves "don't fetch
// the full frame", tileHalo serves "tiles compose exactly" (D7).
// ─────────────────────────────────────────────────────────────────────────

public enum SharpenKernel {
    public static let prepFunction = "sharpen_prep"
    public static let mixFunction = "sharpen_mix"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class SharpenModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// dt `radius` ∈ [0, 99] (sharpen.c:45). σ = radius·scale (D1).
        public var radius: Float
        /// dt `amount` ∈ [0, 2] (sharpen.c:46). 0 = blit identity.
        public var amount: Float
        /// dt `threshold` ∈ [0, 100] (sharpen.c:47) — Lab L units.
        public var threshold: Float

        /// Neutral identity (divergence #2): amount 0 ⇒ blit fast path.
        public init(radius: Float = 2.0, amount: Float = 0.0, threshold: Float = 0.5) {
            self.radius = radius
            self.amount = amount
            self.threshold = threshold
        }
    }

    public static let opName = "sharpen"

    /// Darktable v50 order slot 35.0 — after highpass (34.0), before
    /// colortransfer (37.0) (`iop_order.c` verbatim; V50Order table).
    public static let iopOrder: Float = 35.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// dt MAXR (`sharpen.c:41`).
    static let maxRadius = 12

    /// The neutral eps for the identity fast path.
    static let neutralEps: Float = 1e-6

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    // Scratch planes, cached per (width × height) — the module instance is
    // owned by one pipe run's isolation domain (ShadhiModule contract).
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

    /// dt `commit_params` (`:369-379`): radius ×2.5 into the data, amount /
    /// threshold verbatim. The derived σ (= committed radius/2.5·scale) is
    /// evaluated at process time (roi.scale); only the mix uniforms ride
    /// the piece buffer here. Hashes the RAW params (D-H4).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            var uniforms = MixUniforms(amount: params.amount, threshold: params.threshold)
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

    /// MSL mirror of `SharpenMixUniforms` (SharpenKernels.metal).
    /// srcOffset rides per-run (roiOut − roiIn; 0 under tiling — the tile
    /// driver re-bases itself), so the committed buffer only carries the
    /// commit-time half; process uploads the full struct per run.
    struct MixUniforms {
        var amount: Float
        var threshold: Float
        var srcOffsetX: Int32 = 0
        var srcOffsetY: Int32 = 0
    }

    /// dt FIR radius (`sharpen.c:138`): min(12, ceil(2.5·radius·scale)).
    /// `internal` for the derivation tests. The committed 2.5× folds in —
    /// caller passes the UI radius.
    static func firRadius(radius: Float, scale: Float) -> Int {
        min(maxRadius, Int((2.5 * radius * scale).rounded(.up)))
    }

    /// The IIR σ (D1): committed-radius/2.5·scale = UI-radius·scale.
    /// `internal` for the derivation tests.
    static func sigma(radius: Float, scale: Float) -> Float {
        max(0, radius * scale)
    }

    /// The ROI/tile halo in pixels (D-G5): ceil(3σ). `internal` for tests.
    static func halo(radius: Float, scale: Float) -> Int {
        Int((3 * sigma(radius: radius, scale: scale)).rounded(.up))
    }

    /// Neutral predicate (divergence #2 / D9): amount ≈ 0 or the radius
    /// collapses (σ ≤ 0 ⇒ the blur is identity AND delta is 0 ⇒ mix is
    /// identity regardless of amount). `internal` for tests.
    func isNeutral(_ p: Params, scale: Float = 1.0) -> Bool {
        abs(p.amount) < Self.neutralEps || Self.sigma(radius: p.radius, scale: scale) <= 0
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// D-G5 backward expansion (L020 frame note above): symmetric halo
    /// widen; the pipe clamps to the upstream plane. Neutral → verbatim
    /// (cache-neutral seed takes the identity path).
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else {
            input = roi
            return
        }
        let amount = uniforms.pointee.amount
        if abs(amount) < Self.neutralEps { input = roi; return }
        // Radius is not in the uniforms — recover the halo from the
        // committed copy (the ONLY commit path is setParams; hooks read
        // the working copy, CropModule precedent).
        let h = Self.halo(radius: committed?.radius ?? 0, scale: roi.scale)
        guard h > 0 else { input = roi; return }
        input = roi
        input.x -= h
        input.y -= h
        input.width += 2 * h
        input.height += 2 * h
    }

    // MARK: Tile seam (03-05-T6 — D7 dual-constant note)

    /// toneequal-style IIR runway (D7): 4·firRadius + 65 — the tile output
    /// must match whole-plane execution to <1e-6 (≈14.5σ_ds of transient).
    /// Neutral (amount 0) ⇒ 0 — pure per-pixel blit, never tiled.
    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else { return 0 }
        if abs(uniforms.pointee.amount) < Self.neutralEps { return 0 }
        let r = Self.firRadius(radius: committed?.radius ?? 0, scale: roi.scale)
        return 4 * max(r, 1) + 65
    }

    /// prep (16 B) + blurred (16 B) + planes share (32 B) — 64 B/px when
    /// active; the blit fast path reports 0.
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else { return 0 }
        return abs(uniforms.pointee.amount) < Self.neutralEps ? 0 : 64
    }

    // MARK: Scratch management (per-size cached; .shared storage — L018)

    private func ensureScratch(width: Int, height: Int) throws {
        guard width != scratchWidth || height != scratchHeight else { return }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(SharpenKernel.prepFunction, nil)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        prepTexture = resolved.makeTexture(descriptor: descriptor)
        blurredTexture = resolved.makeTexture(descriptor: descriptor)
        // The blur planes are a device BUFFER (dt gaussian.cl's __global
        // float4* shape — L018 defect 1/2 discipline, ShadhiModule pattern).
        blurPlanesBuffer = resolved.makeBuffer(
            length: width * height * MemoryLayout<Float>.stride * 4 * 2,
            options: .storageModeShared)
        scratchWidth = width
        scratchHeight = height
    }

    // MARK: Process (prep → IIR blur → mix, sharpen.c:126-225 CL shape)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let uniformsBuffer = piece.data else {
            throw MetalError.psoCreationFailed(SharpenKernel.mixFunction, nil)
        }
        let uniforms = uniformsBuffer.contents().assumingMemoryBound(to: MixUniforms.self).pointee
        // D9 neutral fast path: blit identity (cache-neutral + PERF —
        // delta is 0 everywhere so the mix would be identity anyway).
        if abs(uniforms.amount) < Self.neutralEps {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let sigma = Self.sigma(radius: committed?.radius ?? 0, scale: roiIn.scale)
        if sigma <= 0 {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        try ensureScratch(width: input.width, height: input.height)
        guard let prep = prepTexture, let blurPlanes = blurPlanesBuffer,
              let blurred = blurredTexture else {
            throw MetalError.psoCreationFailed(SharpenKernel.prepFunction, nil)
        }

        // Step 1 — Rec2020 → raw Lab.
        try await metal.dispatch2DTexture(
            functionName: SharpenKernel.prepFunction,
            input: input,
            output: prep
        )

        // Step 2 — the IIR domain blur (UNBOUNDED — sharpen.c clamps
        // nothing; the FIR reads raw Lab directly).
        try await GaussianBlur.blur(
            input: prep, output: blurred, planes: blurPlanes,
            sigma: sigma, order: .zero,
            boundsMin: SIMD4(repeating: -Float.greatestFiniteMagnitude),
            boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
            metal: metal
        )

        // Step 3 — the soft-threshold mix (3 textures + per-run uniforms:
        // the committed buffer carries amount/threshold; srcOffset needs
        // the run ROIs — upload the full struct through a shared buffer,
        // NOT setBytes, per the ashift/lens async-commit postmortem).
        var runUniforms = MixUniforms(
            amount: uniforms.amount, threshold: uniforms.threshold,
            srcOffsetX: Int32(roiOut.x - roiIn.x),
            srcOffsetY: Int32(roiOut.y - roiIn.y))
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &runUniforms,
            length: MemoryLayout<MixUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: SharpenKernel.mixFunction)
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
