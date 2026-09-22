import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// NLMeansModule (Plan 05-06, IOP-DENOISE-02) — dt `nlmeans`
// ("astrophoto denoise", v50 29.0, Lab 域), ported from
//   - src/iop/nlmeans.c (params v2 :45-52 = 16B; Lab domain :94-99;
//     scale/P/K/sharpness :170-173,357-360; norm2 :362-365; decimate
//     :367-368; CL bucket rotation :229-310; tiling_callback :328-341;
//     commit clamp :409-417)
//   - data/kernels/nlmeans.cl:26-253 (the five Goossens kernels — see
//     NLMeansKernels.metal for the verbatim port notes)
// (tree dc58cf0ba1).
//
// Goossens sliding-window scheme: per search offset q → dist/horiz/vert/
// accu (4 passes), symmetric half-plane enumeration j ∈ [−K,0],
// i ∈ [−K,K]; finish once. K = ceil(7·scale) → 120 offsets = 481 passes.
//
// PREVIEW DOWNGRADE TRIO (plan T2; D-05-CONTEXT-6 SC#4 lever — constants
// pinned in 05-06-DECISIONS):
//   1. K clamp 3 on PREVIEW/THUMBNAIL (denoiseprofile.c:1626-1631
//      same shape; dt nlmeans itself lacks the clamp — deliberate
//      Lightamer addition, RESEARCH §3.2);
//   2. decimate — skip every other patch offset (dt nlmeans_core.c:103-118
//      `++decimate & 1` skip parity, mirrored EXACTLY — NOT spatial
//      half-sampling; U2 stays dense so finish needs no guard);
//   3. the D-C3 drag ladder (app PipeCoordinator — drag ticks render
//      PREVIEW bucket, release commits and re-renders the current bucket;
//      no nlmeans-specific code there).
// pipeType reaches the module via `piece.pipeType` (stamped once by
// PixelPipe.run alongside iscale — dt `piece->pipe->type` mirror).
//
// ROI (L020/L021): identity (dt has no modify_roi overrides — space
// support is purely tiling_callback). dscIn is THIS RUN's plane pixels
// (entry scaling already applied): the radius compensation uses ONLY the
// scalar `roi.scale ÷ piece.iscale` (dt fmin/fmax shape, nlmeans.c:170) —
// NEVER dscIn × scale. P/K are run-level constants derived from iscale
// (dt uses piece->iscale too): tiling does not move them, which is what
// makes tile execution == whole-plane execution (halo = P + K, :339).
//
// SEED (DECISIONS D-05-06-T2-1): DISABLED — dt ships nlmeans disabled
// (no default_enabled override in nlmeans.c); NO zero-param identity
// exists (strength=0 keeps sharpness=3000 which still smooths similar
// patches; luma/chroma are clamped to ≥0.0001 at commit, nlmeans.c:415-416,
// so the finish blend never reaches zero weight). Identity holds only via
// the disabled piece — colorbalancergb D1 / monochrome D2 disposition.
// ─────────────────────────────────────────────────────────────────────────

public enum NLMeansKernel {
    public static let labForwardFunction = "nlmeans_lab_forward"
    public static let distFunction = "nlmeans_dist"
    public static let horizFunction = "nlmeans_horiz"
    public static let vertFunction = "nlmeans_vert"
    public static let accuFunction = "nlmeans_accu"
    public static let finishFunction = "nlmeans_finish"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class NLMeansModule: IOPModule {

    /// dt `dt_iop_nlmeans_params_t` v2 verbatim (nlmeans.c:45-52).
    public struct Params: Codable, Hashable, Sendable {
        /// dt `radius` ($MIN 0 $MAX 10 $DEFAULT 2; GUI soft max 4).
        public var radius: Float
        /// dt `strength` ($MIN 0 $MAX 100000 $DEFAULT 50; GUI soft max 100).
        public var strength: Float
        /// dt `luma` ($MIN 0 $MAX 1 $DEFAULT 0.5).
        public var luma: Float
        /// dt `chroma` ($MIN 0 $MAX 1 $DEFAULT 1).
        public var chroma: Float

        public init(radius: Float = 2, strength: Float = 50, luma: Float = 0.5, chroma: Float = 1) {
            self.radius = radius
            self.strength = strength
            self.luma = luma
            self.chroma = chroma
        }
    }

    public static let opName = "nlmeans"

    /// Darktable v50 order slot 29.0 (after colorin 28.0 — Lab needs
    /// calibrated color, iop_order.c table note).
    public static let iopOrder: Float = 29.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    // MARK: - Pure derivations (nlmeans.c:170-173,357-368 — `internal`
    // for the derivation/tiling tests; run-level constants, never tile-

    /// dt `fmin(roi.scale, 2) / fmax(piece->iscale, 1)` (:170).
    static func radiusScale(roiScale: Float, iscale: Float) -> Float {
        min(roiScale, 2) / max(iscale, 1)
    }

    /// dt `P = ceilf(radius · scale)` (:171).
    static func patchRadius(radius: Float, roiScale: Float, iscale: Float) -> Int {
        Int((radius * radiusScale(roiScale: roiScale, iscale: iscale)).rounded(.up))
    }

    /// dt `K = ceilf(7 · scale)` (:172).
    static func fullSearchRadius(roiScale: Float, iscale: Float) -> Int {
        Int((7 * radiusScale(roiScale: roiScale, iscale: iscale)).rounded(.up))
    }

    /// PREVIEW DOWNGRADE #1: K clamp 3 on PREVIEW/THUMBNAIL
    /// (denoiseprofile.c:1626-1631 shape — DECISIONS constant).
    static func searchRadius(
        roiScale: Float, iscale: Float, pipeType: PipeResolution
    ) -> Int {
        let k = fullSearchRadius(roiScale: roiScale, iscale: iscale)
        switch pipeType {
        case .preview, .thumbnail: return min(3, k)
        case .full, .export: return k
        }
    }

    /// PREVIEW DOWNGRADE #2: decimate on PREVIEW/THUMBNAIL
    /// (nlmeans.c:367-368 `dt_pipe_is_preview || dt_pipe_is_thumb`).
    static func decimates(pipeType: PipeResolution) -> Bool {
        pipeType == .preview || pipeType == .thumbnail
    }

    /// dt `sharpness = 3000/(1 + strength)` (:173,360).
    static func sharpness(strength: Float) -> Float {
        3000 / (1 + strength)
    }

    /// Lab norm2 factors (:176-179,362-365): nL = 1/120, nC = 1/512.
    static let nL2: Float = 1.0 / (120 * 120)
    static let nC2: Float = 1.0 / (512 * 512)

    /// The symmetric half-plane offset enumeration, dt GPU order
    /// (nlmeans.c:268-269: j ∈ [−K,0], i ∈ [−K,K]) with the decimate skip
    /// parity from nlmeans_core.c:103-118 (`counter starts 1; pre-
    /// increment; odd → skip` — keeps the FIRST offset, drops every
    /// second). K=7 → 120 offsets; K=3 + decimate → 14.
    static func offsets(K: Int, decimate: Bool) -> [(qx: Int, qy: Int)] {
        var result: [(Int, Int)] = []
        var counter = decimate ? 1 : 0
        for j in -K...0 {
            for i in -K...K {
                if decimate {
                    counter += 1
                    if counter & 1 == 1 { continue }
                }
                result.append((i, j))
            }
        }
        return result
    }

    /// Finish blend weight vector (nlmeans.c:213,223 — commit-clamped
    /// luma/chroma).
    static func finishWeight(luma: Float, chroma: Float) -> SIMD4<Float> {
        SIMD4(luma, chroma, chroma, 1)
    }

    /// commit clamp (nlmeans.c:415-416): `MAX(0.0001, p)`.
    static func clampHalfPlane(_ v: Float) -> Float {
        max(0.0001, v)
    }

    // MARK: - Tile seam (L020/L021 — identity ROI; dt tiling_callback :328-341)

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    /// dt tiling_callback :339 `overlap = P + K` (P/K from the run-level
    /// roi.scale ÷ piece.iscale — NOT the tile rect; the tile driver
    /// evaluates this once per module run with the plane ROI).
    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        let p = Self.patchRadius(radius: currentRadius, roiScale: roi.scale, iscale: piece.iscale)
        let k = Self.fullSearchRadius(roiScale: roi.scale, iscale: piece.iscale)
        return p + k
    }

    /// dt tiling_callback :336 factor family: in(1) + out(1) + U2 float4(1)
    /// + 4 single-channel buckets (4 × 0.25) = 4.0, PLUS the module-local
    /// Lab plane (1.0) that dt gets from the pipeline for free → 5.0 × 16B
    /// = 80 B/px (the 05-01 preview placeholder, formalized — DECISIONS).
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        80
    }

    /// Radius for the seam/derivations (params live in the box, not the
    /// piece — the halo P uses the CURRENT panel radius; the module object
    /// is per-registry singleton so the value rides alongside commit).
    /// Set by commitParams; defaults to dt's default radius 2.
    private var currentRadius: Float = 2

    // MARK: - Commit

    private let device: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params` (:409-417): passthrough + luma/chroma clamp.
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        currentRadius = params.radius

        let clamped = Params(
            radius: params.radius,
            strength: params.strength,
            luma: Self.clampHalfPlane(params.luma),
            chroma: Self.clampHalfPlane(params.chroma))

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        if pieceBuffer == nil || committed != clamped {
            var floats = [Float](repeating: 0, count: 4)
            floats[0] = clamped.radius
            floats[1] = clamped.strength
            floats[2] = clamped.luma
            floats[3] = clamped.chroma
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: 4 * MemoryLayout<Float>.size, options: .storageModeShared)
            }
            if let buffer = pieceBuffer {
                floats.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: 4 * MemoryLayout<Float>.size)
                }
            }
            committed = clamped
        }
        piece.data = pieceBuffer
    }

    // MARK: - Scratch (per-size cache; .shared storage — L018 defect 3)

    /// The working set for one run: the Lab plane + the U2 float4
    /// accumulator + the 4 rotating single-channel buckets (dt NUM_BUCKETS).
    struct Scratch {
        let lab: any MTLTexture
        let u2: any MTLBuffer
        let buckets: any MTLBuffer
        let planeBytes: Int
    }

    private var scratch: (Scratch, Int, Int)?

    private func makeScratch(
        width: Int, height: Int, metal: MetalContext
    ) throws -> Scratch {
        if let (cached, w, h) = scratch, w == width, h == height {
            return cached
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let planeBytes = width * height * MemoryLayout<Float>.size
        guard let lab = metal.device.makeTexture(descriptor: descriptor),
            let u2 = metal.device.makeBuffer(
                length: width * height * 16, options: .storageModeShared),
            let buckets = metal.device.makeBuffer(
                length: planeBytes * 4, options: .storageModeShared)
        else {
            throw MetalError.bufferAllocationFailed(planeBytes * 6)
        }
        let made = Scratch(lab: lab, u2: u2, buckets: buckets, planeBytes: planeBytes)
        scratch = (made, width, height)
        return made
    }

    // MARK: - Process (the Goossens offset loop; plan T1 orchestrator)

    /// Threadgroup block size for the horiz/vert sliding windows — the
    /// scan-tested value (NLMeansParityTests workgroup scan; dt probes
    /// via dt_opencl_local_buffer_opt with a 2^16-cell budget, our fixed
    /// choice lands in DECISIONS).
    static let threadgroupBlockSize = 128

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard piece.data != nil else { return }
        let params = committed ?? Params()
        let owned = try makeScratch(width: input.width, height: input.height, metal: metal)
        try await Self.denoise(
            input: input, output: output,
            radius: params.radius, strength: params.strength,
            luma: Self.clampHalfPlane(params.luma),
            chroma: Self.clampHalfPlane(params.chroma),
            roiScale: roiIn.scale, iscale: piece.iscale,
            pipeType: piece.pipeType, metal: metal, scratch: owned)
    }

    /// The kernel-group orchestrator (plan T1): lab_forward → per-offset
    /// dist/horiz/vert/accu (bucket rotation, dt :229-310) → finish.
    /// `static` so tests can drive it without a module instance.
    static func denoise(
        input: any MTLTexture,
        output: any MTLTexture,
        radius: Float,
        strength: Float,
        luma: Float,
        chroma: Float,
        roiScale: Float,
        iscale: Float,
        pipeType: PipeResolution,
        metal: MetalContext,
        blockSize: Int = NLMeansModule.threadgroupBlockSize,
        scratch: Scratch
    ) async throws {
        let width = input.width
        let height = input.height
        let p = NLMeansModule.patchRadius(radius: radius, roiScale: roiScale, iscale: iscale)
        let k = NLMeansModule.searchRadius(roiScale: roiScale, iscale: iscale, pipeType: pipeType)
        let sharpen = NLMeansModule.sharpness(strength: strength)
        let decimate = NLMeansModule.decimates(pipeType: pipeType)
        let offsets = NLMeansModule.offsets(K: k, decimate: decimate)

        let planeBytes = width * height * MemoryLayout<Float>.size
        precondition(scratch.planeBytes == planeBytes, "scratch sized for another plane")
        let labTex = scratch.lab
        let u2 = scratch.u2
        let buckets = scratch.buckets

        // Pass 0 — Rec2020 → Lab plane (the module domain).
        try await metal.dispatch2DTexture(
            functionName: NLMeansKernel.labForwardFunction,
            input: input, output: labTex)

        // U2 zero-fill ONCE per run (dt :262 dt_opencl_fill_buffer 0.0;
        // .shared buffer — host memset precedes every GPU command).
        memset(u2.contents(), 0, width * height * 16)

        // Bucket rotation state (dt :151-159 bucket_next).
        var state = 0
        func bucketNext() -> Int {
            let current = state
            state = current >= 3 ? 0 : current + 1
            return current
        }

        // Kernel uniform structs (mirror the MSL layouts field-for-field —
        // all-scalar structs pack identically; FinishParams carries the
        // explicit float4 alignment pad matching the MSL float2 pad).
        struct DistParams {
            var width: UInt32
            var height: UInt32
            var qx: Int32
            var qy: Int32
            var nL2: Float
            var nC2: Float
        }
        struct BoxParams {
            var width: UInt32
            var height: UInt32
            var p: Int32
        }
        struct VertParams {
            var width: UInt32
            var height: UInt32
            var p: Int32
            var sharpness: Float
        }
        struct AccuParams {
            var width: UInt32
            var height: UInt32
            var qx: Int32
            var qy: Int32
        }
        struct FinishParams {
            var width: UInt32
            var height: UInt32
            var alignPad: (UInt32, UInt32)
            var weight: SIMD4<Float>
        }

        var distParams = DistParams(
            width: UInt32(width), height: UInt32(height), qx: 0, qy: 0,
            nL2: NLMeansModule.nL2, nC2: NLMeansModule.nC2)
        var boxParams = BoxParams(
            width: UInt32(width), height: UInt32(height), p: Int32(p))
        var vertParams = VertParams(
            width: UInt32(width), height: UInt32(height), p: Int32(p), sharpness: sharpen)
        var accuParams = AccuParams(
            width: UInt32(width), height: UInt32(height), qx: 0, qy: 0)
        var finishParams = FinishParams(
            width: UInt32(width), height: UInt32(height), alignPad: (0, 0),
            weight: NLMeansModule.finishWeight(luma: luma, chroma: chroma))

        for offset in offsets {
            distParams.qx = Int32(offset.qx)
            distParams.qy = Int32(offset.qy)
            accuParams.qx = Int32(offset.qx)
            accuParams.qy = Int32(offset.qy)

            // dist: Lab plane → bucket[state].
            let b0 = bucketNext()
            let dist = try await metal.makeEncoder(functionName: NLMeansKernel.distFunction)
            dist.encoder.setTexture(labTex, index: 0)
            dist.encoder.setBuffer(buckets, offset: planeBytes * b0, index: 0)
            dist.encoder.setBytes(&distParams, length: MemoryLayout<DistParams>.stride, index: 1)
            dist.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            dist.encoder.endEncoding()
            dist.commandBuffer.commit()

            // horiz: bucket[b0] → bucket[b1] (threadgroup sliding window).
            let b1 = bucketNext()
            let gridW = ((width + blockSize - 1) / blockSize) * blockSize
            let horiz = try await metal.makeEncoder(functionName: NLMeansKernel.horizFunction)
            horiz.encoder.setBuffer(buckets, offset: planeBytes * b0, index: 0)
            horiz.encoder.setBuffer(buckets, offset: planeBytes * b1, index: 1)
            horiz.encoder.setBytes(&boxParams, length: MemoryLayout<BoxParams>.stride, index: 2)
            horiz.encoder.setThreadgroupMemoryLength(
                (blockSize + 2 * p) * MemoryLayout<Float>.size, index: 0)
            horiz.encoder.dispatchThreadgroups(
                MTLSize(width: gridW / blockSize, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: blockSize, height: 1, depth: 1))
            horiz.encoder.endEncoding()
            horiz.commandBuffer.commit()

            // vert: bucket[b1] → bucket[b2] (+ weight application).
            let b2 = bucketNext()
            let gridH = ((height + blockSize - 1) / blockSize) * blockSize
            let vert = try await metal.makeEncoder(functionName: NLMeansKernel.vertFunction)
            vert.encoder.setBuffer(buckets, offset: planeBytes * b1, index: 0)
            vert.encoder.setBuffer(buckets, offset: planeBytes * b2, index: 1)
            vert.encoder.setBytes(&vertParams, length: MemoryLayout<VertParams>.stride, index: 2)
            vert.encoder.setThreadgroupMemoryLength(
                (blockSize + 2 * p) * MemoryLayout<Float>.size, index: 0)
            vert.encoder.dispatchThreadgroups(
                MTLSize(width: width, height: gridH / blockSize, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: blockSize, depth: 1))
            vert.encoder.endEncoding()
            vert.commandBuffer.commit()

            // accu: Lab plane + bucket[b2] → U2 (RMW, device buffer).
            let accu = try await metal.makeEncoder(functionName: NLMeansKernel.accuFunction)
            accu.encoder.setTexture(labTex, index: 0)
            accu.encoder.setBuffer(u2, offset: 0, index: 0)
            accu.encoder.setBuffer(buckets, offset: planeBytes * b2, index: 1)
            accu.encoder.setBytes(&accuParams, length: MemoryLayout<AccuParams>.stride, index: 2)
            accu.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            accu.encoder.endEncoding()
            accu.commandBuffer.commit()
        }

        // finish: blend + Lab → Rec2020 domain exit.
        let finish = try await metal.makeEncoder(functionName: NLMeansKernel.finishFunction)
        finish.encoder.setTexture(labTex, index: 0)
        finish.encoder.setBuffer(u2, offset: 0, index: 0)
        finish.encoder.setTexture(output, index: 1)
        finish.encoder.setBytes(&finishParams, length: MemoryLayout<FinishParams>.stride, index: 2)
        finish.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        finish.encoder.endEncoding()
        finish.commandBuffer.commit()
    }
}
