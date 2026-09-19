import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// TONEEQUAL — tone equalizer (Plan 03-05, IOP-TONE-07). Phase 3's heaviest
// module: a three-stage Metal graph (luma mask estimate → detail-preserving
// filter → correction-LUT apply) plus the FIRST TilingPlan-driven FULL
// pipeline (T6).
//
// Darktable reference (tree dc58cf0ba1):
//   - src/iop/toneequal.c   params v2 :170-190; commit :1592-1651;
//                           luminance mask :866-934; LUT apply :771-803;
//                           modify_roi_in :1342-1358 (the radius/halo
//                           semantics the tile seam reports)
//   - src/common/luminance_mask.h   the SEVEN luma estimators + linear_contrast
//                           (plan erratum: "9 estimators" — the enum is 7;
//                           the 9 refers to the user BANDS)
//   - src/common/eigf.h             fast_eigf_surface_blur — the EIGF
//                           detail leg (Gaussian, NOT box mean; plan erratum
//                           recorded on the kernel file)
//   - src/common/fast_guided_filter.h  fast_surface_blur — the guided leg
//                           (box mean)
//
// D-T3 SEMANTICS (checkpoint, plan T3): toneequal = GLOBAL multi-band
// (dt's default mode; no mask dependency — per-region arrives in Phase 6).
// Golden acceptance TWO-TIER: details=none <1e-5 first, EIGF (dt default)
// <1e-4 + ΔE p99 <1.0 second.
//
// DARKTABLE HAS NO OpenCL for this iop (toneequal.c:313 TODO) — the Metal
// port is free-form but the MATH is transcribed formula-by-formula from the
// CPU sources above, and the golden references replicate that math in
// float64 (L017 synthesized route; dt-side evidence = XMP blob adoption +
// uniform-flat PFM probes).
//
// APPLY QUIRK (dt verbatim): `apply_toneequalizer` multiplies ALL FOUR
// channels by the correction (`for_each_channel` = 4) — including alpha.
// We follow: the golden compare sees the same 4th-channel semantics.
// ─────────────────────────────────────────────────────────────────────────

public enum ToneEqualKernel {
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
    // T2-T4 fill these as the kernels land.
    public static let lumaEstimateFunction = "toneeq_luma_estimate"
    public static let bilinear1cFunction = "toneeq_bilinear_1c"
    public static let quantizeFunction = "toneeq_quantize"
    public static let pack4Function = "toneeq_pack4"
    public static let boxMeanXFunction = "toneeq_box_mean_x"
    public static let boxMeanYFunction = "toneeq_box_mean_y"
    public static let guidedABFunction = "toneeq_guided_ab"
    public static let blendFunction = "toneeq_blend"
    public static let applyFunction = "toneeq_apply"
}

/// dt `dt_iop_toneequalizer_filter_t` (:158-165) — raw values for XMP
/// fidelity.
public enum ToneEqualDetails: Int, Codable, Hashable, Sendable {
    case none = 0
    case averagedGuided = 1
    case guided = 2
    case averagedEIGF = 3
    /// dt DEFAULT (:184).
    case eigf = 4
}

/// dt `dt_iop_luminance_mask_method_t` (luminance_mask.h:40-48) — the
/// SEVEN estimators, raw values aligned.
public enum ToneEqualMethod: Int, Codable, Hashable, Sendable {
    case mean = 0
    case lightness = 1
    case value = 2
    case norm1 = 3
    /// dt DEFAULT (:186).
    case norm2 = 4
    case normPower = 5
    case geomean = 6
}

public final class ToneEqualModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {

        /// The 9 EV bands, each ∈ [−2, 2] default 0 (toneequal.c:171-179).
        public var noise: Float
        public var ultraDeepBlacks: Float
        public var deepBlacks: Float
        public var blacks: Float
        public var shadows: Float
        public var midtones: Float
        public var highlights: Float
        public var whites: Float
        public var speculars: Float
        /// smoothing diameter, % of the largest dimension ∈ [0.01, 100],
        /// default 5 (:180).
        public var blending: Float
        /// RBF sigma, default √2 (:181).
        public var smoothing: Float
        /// edges feathering ∈ [0.01, 10000], default 1 (:182); commit
        /// INVERTS it (d->feathering = 1/p — :1617).
        public var feathering: Float
        /// mask quantization step ∈ [0, 2], default 0 (:183).
        public var quantization: Float
        /// mask contrast compensation ±16 EV, default 0 (:184).
        public var contrastBoost: Float
        /// mask exposure compensation ±16 EV, default 0 (:185).
        public var exposureBoost: Float
        /// detail preservation, default EIGF (:186).
        public var details: ToneEqualDetails
        /// luma estimator, default NORM_2 (:187).
        public var method: ToneEqualMethod
        /// filter diffusion iterations ∈ [1, 20], default 1 (:188).
        public var iterations: Int

        public init(
            noise: Float = 0,
            ultraDeepBlacks: Float = 0,
            deepBlacks: Float = 0,
            blacks: Float = 0,
            shadows: Float = 0,
            midtones: Float = 0,
            highlights: Float = 0,
            whites: Float = 0,
            speculars: Float = 0,
            blending: Float = 5,
            smoothing: Float = 1.414_213_5,
            feathering: Float = 1,
            quantization: Float = 0,
            contrastBoost: Float = 0,
            exposureBoost: Float = 0,
            details: ToneEqualDetails = .eigf,
            method: ToneEqualMethod = .norm2,
            iterations: Int = 1
        ) {
            self.noise = noise
            self.ultraDeepBlacks = ultraDeepBlacks
            self.deepBlacks = deepBlacks
            self.blacks = blacks
            self.shadows = shadows
            self.midtones = midtones
            self.highlights = highlights
            self.whites = whites
            self.speculars = speculars
            self.blending = blending
            self.smoothing = smoothing
            self.feathering = feathering
            self.quantization = quantization
            self.contrastBoost = contrastBoost
            self.exposureBoost = exposureBoost
            self.details = details
            self.method = method
            self.iterations = iterations
        }

        /// The 9 bands in dt's order (noise → speculars), for the LUT and
        /// the panel.
        public var bands: [Float] {
            [noise, ultraDeepBlacks, deepBlacks, blacks, shadows,
             midtones, highlights, whites, speculars]
        }
    }

    public static let opName = "toneequal"
    public static let iopOrder: Float = 24.0
    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Commit-time derived state (dt `dt_iop_toneequalizer_data_t` scalar
    /// half, :192-205 + commit :1596-1620). `internal` for the derivation
    /// tests.
    struct Derived: Equatable {
        var blending: Float        // params.blending / 100
        var feathering: Float      // 1 / params.feathering (dt INVERTS)
        var contrastBoost: Float   // exp2(params.contrastBoost)
        var exposureBoost: Float   // exp2(params.exposureBoost)
        var smoothing: Float
        var quantization: Float
        var iterations: Int32
        var details: Int32
        var method: Int32
    }

    static func derive(_ params: Params) -> Derived {
        Derived(
            blending: params.blending / 100.0,
            feathering: 1.0 / params.feathering,
            contrastBoost: Foundation.exp2f(params.contrastBoost),
            exposureBoost: Foundation.exp2f(params.exposureBoost),
            smoothing: params.smoothing,
            quantization: params.quantization,
            iterations: Int32(params.iterations),
            details: Int32(params.details.rawValue),
            method: Int32(params.method.rawValue)
        )
    }

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var lutBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: Commit (toneequal.c:1592-1651)

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            var derived = Self.derive(params)
            let bands = params.bands
            let weights = CorrectionLUT.weights(bands: bands, sigma: params.smoothing)
                ?? [Float](repeating: 0, count: CorrectionLUT.controlPointCount)
            let lut = CorrectionLUT.lut(weights: weights, sigma: params.smoothing)

            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: MemoryLayout<Derived>.stride, options: .storageModeShared
                )
                lutBuffer = resolved.makeBuffer(
                    length: CorrectionLUT.lutCount * MemoryLayout<Float>.stride,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                withUnsafeBytes(of: &derived) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<Derived>.stride)
                }
            }
            if let buffer = lutBuffer {
                lut.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: CorrectionLUT.lutCount * MemoryLayout<Float>.stride)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    // MARK: Tile seam (Plan 03-05-T6 — TilingPlan FULL first engagement)

    /// dt modify_roi_in (toneequal.c:1352-1357) radius + the IIR/filter
    /// halo requirement. radius = (blending% × full-image max-dim ×
    /// scale − 1)/2. The halo is MORE than one radius because the EIGF
    /// leg's gaussian is a RECURSIVE IIR (gaussian.c): its per-edge
    /// transient decays as exp(−1.695·distance/σ_ds) and the tile output
    /// must match whole-plane execution to <1e-6, which needs ≈14.5σ_ds
    /// of runway; with σ_ds = radius/clamp(radius,1,4) that is
    /// 4·radius + 64 (+1 for the bilinear/quantize edge rounding). The
    /// guided leg's box mean is a finite window (one radius would do) and
    /// simply shares the larger EIGF halo. (The plan text's
    /// "max(radius,1)+halo" is this number — the module reports its real
    /// requirement through the seam, per the plan's own wording.)
    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: Derived.self) else { return 0 }
        let d = uniforms.pointee
        if d.details == Int32(ToneEqualDetails.none.rawValue) {
            return 0 // pure per-pixel — never needs a halo
        }
        let fullMax = Float(max(max(piece.dscIn.width, 1), max(piece.dscIn.height, 1)))
        let diameter = d.blending * fullMax * roi.scale
        let radius = Int((diameter - 1.0) / 2.0)
        return 4 * max(radius, 1) + 64 + 1
    }

    /// mask (4 B) + quantized mask (4 B) + the ds-plane share (bilinear
    /// pairs, packed moments, gaussian planes ≈ 4 B/px of output) — 12
    /// B/px on the filter legs, mask only on NONE.
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: Derived.self) else { return 0 }
        let none = uniforms.pointee.details == Int32(ToneEqualDetails.none.rawValue)
        return none ? 4 : 12
    }

    // MARK: Scratch management (per-size cached; .shared storage — L018)

    private struct Scratch {
        var width = 0
        var height = 0
        var dsWidth = 0
        var dsHeight = 0
        // Full-res luma planes (r32): the ping pair + the quantized mask.
        var maskA: (any MTLTexture)?
        var maskB: (any MTLTexture)?
        var quantFull: (any MTLTexture)?
        // Downsampled planes: two r32 (guided's ds image ping + quantized
        // mask) + two rgba32 (the packed moments and the av/ab result).
        var dsImage: (any MTLTexture)?
        var dsMask: (any MTLTexture)?
        var dsPacked: (any MTLTexture)?
        var dsAv: (any MTLTexture)?
        var gaussPlanes: (any MTLBuffer)?
    }

    private var scratch = Scratch()

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

    private func ensureScratch(
        width: Int, height: Int, dsWidth: Int, dsHeight: Int
    ) throws {
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(ToneEqualKernel.lumaEstimateFunction, nil)
        }
        let s = scratch
        if s.width == width, s.height == height, s.dsWidth == dsWidth, s.dsHeight == dsHeight,
           s.maskA != nil {
            return
        }
        scratch = Scratch(
            width: width, height: height, dsWidth: dsWidth, dsHeight: dsHeight,
            maskA: Self.r32(resolved, width: width, height: height),
            maskB: Self.r32(resolved, width: width, height: height),
            quantFull: Self.r32(resolved, width: width, height: height),
            dsImage: Self.r32(resolved, width: dsWidth, height: dsHeight),
            dsMask: Self.r32(resolved, width: dsWidth, height: dsHeight),
            dsPacked: Self.rgba32(resolved, width: dsWidth, height: dsHeight),
            dsAv: Self.rgba32(resolved, width: dsWidth, height: dsHeight),
            gaussPlanes: resolved.makeBuffer(
                length: max(dsWidth, 1) * max(dsHeight, 1) * 16 * 2,
                options: .storageModeShared))
    }

    // MARK: Process (toneequal.c:866-934 compute_luminance_mask + :771-803 apply)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let uniformsBuffer = piece.data, let lutBuffer else {
            throw MetalError.psoCreationFailed(ToneEqualKernel.applyFunction, nil)
        }
        let derived = uniformsBuffer.contents().assumingMemoryBound(to: Derived.self).pointee
        let width = input.width
        let height = input.height

        // dt modify_roi_in (toneequal.c:1352-1357): the smoothing diameter
        // is blending% of the FULL-IMAGE largest dimension (piece->iwidth,
        // NOT the current ROI — the piece geometry carries the pipe-scale
        // plane; the tile driver keeps this semantics stable under tiles).
        let fullMax = max(max(piece.dscIn.width, 1), max(piece.dscIn.height, 1))
        let diameter = derived.blending * Float(fullMax) * roiIn.scale
        let radius = Int((diameter - 1.0) / 2.0)

        // The boost configuration per detail mode (:869-934): the AVG legs
        // and NONE leave the mask unboosted (fulcrum 0, contrast 1); the
        // plain GUIDED/EIGF legs contrast-boost around exp2(−4).
        let boosted = derived.details == Int32(ToneEqualDetails.guided.rawValue)
            || derived.details == Int32(ToneEqualDetails.eigf.rawValue)
        let lumaUniforms = LumaUniforms(
            method: derived.method,
            exposureBoost: derived.exposureBoost,
            fulcrum: boosted ? Float(exp2(-4.0)) : 0,
            contrastBoost: boosted ? derived.contrastBoost : 1)
        var lumaU = lumaUniforms

        // dt's blending MODE (linear vs geomean) per detail leg.
        let geomeanFinal =
            derived.details == Int32(ToneEqualDetails.averagedGuided.rawValue)
            || derived.details == Int32(ToneEqualDetails.averagedEIGF.rawValue)

        // NONE: mask passes straight to the apply kernel (:871-878).
        if derived.details == Int32(ToneEqualDetails.none.rawValue) {
            try await ensureScratch(width: width, height: height, dsWidth: 1, dsHeight: 1)
            guard let mask = scratch.maskA else {
                throw MetalError.psoCreationFailed(ToneEqualKernel.lumaEstimateFunction, nil)
            }
            try await dispatchLuma(
                metal, input: input, output: mask, uniforms: &lumaU,
                width: width, height: height)
            try await dispatchApply(
                metal, input: input, luma: mask, output: output, lut: lutBuffer,
                width: width, height: height)
            return
        }

        // The filter legs — EIGF scaling (eigf.h fast_eigf_surface_blur):
        //   scaling = clamp(sigma(=radius), 1, 4); ds_sigma = max(σ/s, 1)
        //   ds size = floor(size / scaling)   (float division, truncated)
        // guided (fast_guided_filter.h fast_surface_blur): scaling fixed 4,
        // ds_radius = radius < 4 ? 1 : radius / 4 (int division).
        let sigmaRadius = Float(radius)
        let scaling: Float
        let dsSigma: Float
        var dsRadius: Int = 1
        let isEigf = derived.details == Int32(ToneEqualDetails.eigf.rawValue)
            || derived.details == Int32(ToneEqualDetails.averagedEIGF.rawValue)
        if isEigf {
            scaling = max(min(sigmaRadius, 4.0), 1.0)
            dsSigma = max(sigmaRadius / scaling, 1.0)
        } else {
            scaling = 4.0
            dsSigma = 0
            dsRadius = radius < 4 ? 1 : radius / 4
        }
        let dsWidth = max(1, Int(Float(width) / scaling))
        let dsHeight = max(1, Int(Float(height) / scaling))
        try await ensureScratch(
            width: width, height: height, dsWidth: dsWidth, dsHeight: dsHeight)
        guard let maskA = scratch.maskA, let maskB = scratch.maskB,
              let quantFull = scratch.quantFull, let dsImage = scratch.dsImage,
              let dsMask = scratch.dsMask, let dsPacked = scratch.dsPacked,
              let dsAv = scratch.dsAv, let gaussPlanes = scratch.gaussPlanes
        else {
            throw MetalError.psoCreationFailed(ToneEqualKernel.lumaEstimateFunction, nil)
        }

        // Stage 1 — the luma mask.
        try await dispatchLuma(
            metal, input: input, output: maskA, uniforms: &lumaU,
            width: width, height: height)

        let iterations = max(1, Int(derived.iterations))
        if isEigf {
            // ── EIGF leg (eigf.h fast_eigf_surface_blur): every iteration
            // downsamples the CURRENT full-res mask, gaussian-blurs the
            // packed moments, and blends AT FULL RES (bilinear av upsample
            // inlined in the blend kernel).
            var cur = maskA
            var next = maskB
            for i in 0..<iterations {
                try await dispatchBilinear(
                    metal, input: cur, output: dsImage,
                    srcW: width, srcH: height, dstW: dsWidth, dstH: dsHeight,
                    gridW: dsWidth, gridH: dsHeight)
                var blendMode = 0 // no-mask
                var guideSrc = dsImage
                var maskSrc = dsImage
                if derived.quantization != 0 {
                    try await dispatchQuantize(
                        metal, input: cur, output: quantFull, sampling: derived.quantization,
                        gridW: width, gridH: height)
                    try await dispatchBilinear(
                        metal, input: quantFull, output: dsMask,
                        srcW: width, srcH: height, dstW: dsWidth, dstH: dsHeight,
                        gridW: dsWidth, gridH: dsHeight)
                    blendMode = 1
                    guideSrc = dsMask
                    maskSrc = quantFull
                }
                try await dispatchPack(
                    metal, guide: guideSrc, mask: dsImage, output: dsPacked,
                    gridW: dsWidth, gridH: dsHeight)
                try await GaussianBlur.blur(
                    input: dsPacked, output: dsAv, planes: gaussPlanes,
                    sigma: dsSigma,
                    boundsMin: SIMD4(repeating: Float(exp2(-16.0))),
                    boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
                    metal: metal)
                try await dispatchBlend(
                    metal, image: cur, mask: maskSrc, aux: dsAv, output: next,
                    mode: blendMode, upsample: true,
                    geomean: geomeanFinal && i == iterations - 1,
                    feathering: derived.feathering,
                    auxW: dsWidth, auxH: dsHeight, srcW: width, srcH: height,
                    gridW: width, gridH: height)
                // FIFO order makes the swap safe: the next iteration
                // reads what we just wrote.
                swap(&cur, &next)
            }
            try await dispatchApply(
                metal, input: input, luma: cur, output: output, lut: lutBuffer,
                width: width, height: height)
        } else {
            // ── guided leg (fast_guided_filter.h fast_surface_blur): ONE
            // downsample; iterations run ON THE DS PLANE (quantize → pack →
            // box mean → ab → box mean → ds blend); the final blend
            // upsamples the box-smoothed a/b to full res.
            try await dispatchBilinear(
                metal, input: maskA, output: dsImage,
                srcW: width, srcH: height, dstW: dsWidth, dstH: dsHeight,
                gridW: dsWidth, gridH: dsHeight)
            for i in 0..<iterations {
                try await dispatchQuantize(
                    metal, input: dsImage, output: dsMask, sampling: derived.quantization,
                    gridW: dsWidth, gridH: dsHeight)
                try await dispatchPack(
                    metal, guide: dsMask, mask: dsImage, output: dsPacked,
                    gridW: dsWidth, gridH: dsHeight)
                var boxRadius = UInt32(dsRadius)
                try await dispatchBox(metal, input: dsPacked, output: dsAv, radius: &boxRadius,
                                      width: dsWidth, height: dsHeight, horizontal: true)
                try await dispatchBox(metal, input: dsAv, output: dsPacked, radius: &boxRadius,
                                      width: dsWidth, height: dsHeight, horizontal: false)
                try await dispatchAB(metal, input: dsPacked, output: dsAv,
                                     feathering: derived.feathering,
                                     gridW: dsWidth, gridH: dsHeight)
                try await dispatchBox(metal, input: dsAv, output: dsPacked, radius: &boxRadius,
                                      width: dsWidth, height: dsHeight, horizontal: true)
                try await dispatchBox(metal, input: dsPacked, output: dsAv, radius: &boxRadius,
                                      width: dsWidth, height: dsHeight, horizontal: false)
                let last = i == iterations - 1
                try await dispatchBlend(
                    metal, image: last ? maskA : dsImage, mask: dsImage, aux: dsAv,
                    output: last ? maskB : dsMask,
                    mode: 2, upsample: last,
                    geomean: geomeanFinal && last,
                    feathering: derived.feathering,
                    auxW: dsWidth, auxH: dsHeight, srcW: width, srcH: height,
                    gridW: last ? width : dsWidth, gridH: last ? height : dsHeight)
                if !last {
                    // dsImage ← dsMask for the next iteration (ds plane ping).
                    try await dispatchCopy1C(metal, input: dsMask, output: dsImage,
                                             width: dsWidth, height: dsHeight)
                }
            }
            try await dispatchApply(
                metal, input: input, luma: maskB, output: output, lut: lutBuffer,
                width: width, height: height)
        }
    }

    // MARK: Dispatch helpers (each: encode → endEncoding → commit, L008)

    struct LumaUniforms {
        var method: Int32
        var exposureBoost: Float
        var fulcrum: Float
        var contrastBoost: Float
    }

    private func dispatchLuma(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        uniforms: inout LumaUniforms, width: Int, height: Int
    ) async throws {
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.lumaEstimateFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&uniforms, length: MemoryLayout<LumaUniforms>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func dispatchBilinear(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        srcW: Int, srcH: Int, dstW: Int, dstH: Int,
        gridW: Int, gridH: Int
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
            MTLSize(width: gridW, height: gridH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func dispatchQuantize(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        sampling: Float, gridW: Int, gridH: Int
    ) async throws {
        struct U {
            var sampling: Float
            var clipMin: Float
            var clipMax: Float
        }
        var u = U(sampling: sampling, clipMin: Float(exp2(-14.0)), clipMax: 4)
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.quantizeFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&u, length: MemoryLayout<U>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: gridW, height: gridH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func dispatchPack(
        _ metal: MetalContext, guide: any MTLTexture, mask: any MTLTexture,
        output: any MTLTexture, gridW: Int, gridH: Int
    ) async throws {
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.pack4Function)
        session.encoder.setTexture(guide, index: 0)
        session.encoder.setTexture(mask, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.dispatchThreads(
            MTLSize(width: gridW, height: gridH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func dispatchBox(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        radius: inout UInt32, width: Int, height: Int, horizontal: Bool
    ) async throws {
        let session = try await metal.makeEncoder(
            functionName: horizontal ? ToneEqualKernel.boxMeanXFunction : ToneEqualKernel.boxMeanYFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&radius, length: MemoryLayout<UInt32>.stride, index: 0)
        if horizontal {
            session.encoder.dispatchThreads(
                MTLSize(width: 1, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: min(64, session.pipelineState.maxTotalThreadsPerThreadgroup), depth: 1))
        } else {
            session.encoder.dispatchThreads(
                MTLSize(width: width, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(64, session.pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        }
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func dispatchAB(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        feathering: Float, gridW: Int, gridH: Int
    ) async throws {
        struct U { var feathering: Float }
        var u = U(feathering: feathering)
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.guidedABFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&u, length: MemoryLayout<U>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: gridW, height: gridH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func dispatchBlend(
        _ metal: MetalContext, image: any MTLTexture, mask: any MTLTexture,
        aux: any MTLTexture, output: any MTLTexture,
        mode: Int, upsample: Bool, geomean: Bool, feathering: Float,
        auxW: Int, auxH: Int, srcW: Int, srcH: Int, gridW: Int, gridH: Int
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
            mode: Int32(mode), upsample: upsample ? 1 : 0, geomean: geomean ? 1 : 0,
            feathering: feathering,
            auxWidth: UInt32(auxW), auxHeight: UInt32(auxH),
            srcWidth: UInt32(srcW), srcHeight: UInt32(srcH))
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.blendFunction)
        session.encoder.setTexture(image, index: 0)
        session.encoder.setTexture(mask, index: 1)
        session.encoder.setTexture(aux, index: 2)
        session.encoder.setTexture(output, index: 3)
        session.encoder.setBytes(&u, length: MemoryLayout<U>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: gridW, height: gridH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// r32 plane copy (the guided ds ping between iterations) — gaussian_copy
    /// reads rgba; a dedicated r32 copy rides the bilinear kernel with
    /// identity scaling instead (src == dst dims → dt's bilinear is a copy).
    private func dispatchCopy1C(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        width: Int, height: Int
    ) async throws {
        try await dispatchBilinear(
            metal, input: input, output: output,
            srcW: width, srcH: height, dstW: width, dstH: height,
            gridW: width, gridH: height)
    }

    private func dispatchApply(
        _ metal: MetalContext, input: any MTLTexture, luma: any MTLTexture,
        output: any MTLTexture, lut: any MTLBuffer, width: Int, height: Int
    ) async throws {
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.applyFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(luma, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(lut, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }
}
