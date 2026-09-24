import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// MaskCombiner (Plan 06-04) — the mask-assembly dispatch face.
//
// The mask kernels live in LightamerIOP's metallib (`ParametricMaskKernels.metal`,
// `MaskPostProcessKernels.metal`) and Core's own (`MaskCombineKernels.metal`);
// function resolution walks Core's library then the registered ones (the
// MetalContext contract) — the same soft dependency `LayerCompositeDriver`
// already carries for `compositeLayer` (06-02). The Swift struct mirrors
// below are the ABI CONTRACT: each MSL struct is the single source, these
// mirrors pin it, and the parity tests assert kernel ≙ float64 reference —
// a drift breaks them loudly (the L023 half-contract discipline).
//
// L018 red lines: every multi-pass op here reads one plane and writes
// ANOTHER (ping-pong) — never a read_write texture RMW, never in-place.
// ─────────────────────────────────────────────────────────────────────────────

/// Swift mirror of the MSL `MaskBlendifFlags` (48-byte constant layout).
struct MaskBlendifFlags {
    var blendif: UInt32        // enabled (low 16) | inverted (high 16)
    var combineFlags: UInt32   // 0x01 INV, 0x02 INCL (dt blend.h:77-88)
    var hasForm: UInt32        // 1 = mask_in carries the drawn/form plane
    var rowEnd: UInt32         // write band end (whole plane = UINT_MAX)
    var gopacity: Float        // the CLIP'd layer-opacity ceiling
    private var _pad: (Float, Float, Float) = (0, 0, 0)

    init(spec: ParametricMask, hasForm: Bool, gopacity: Float, layerInverted: Bool = false) {
        blendif = spec.channelBitmask()
        combineFlags = (spec.invert || layerInverted ? 0x01 : 0)
        self.hasForm = hasForm ? 1 : 0
        rowEnd = UInt32.max
        self.gopacity = gopacity
    }
}

/// The degrade-reason carrier across a @Sendable cache closure.
private final class ReasonBox: @unchecked Sendable {
    var value: String?
}

/// One entry of a combine reduce: (plane, op, inverted, opacity).
struct MaskCombineInput {
    var plane: any MTLTexture
    var op: MaskCombineOp
    var inverted: Bool
    var opacity: Float
}

public enum MaskCombiner {

    // MARK: - Kernel names (the metallib ABI)

    static let blendifKernel = "mask_blendif"
    static let toneCurveKernel = "mask_tone_curve"
    static let blurColKernel = "mask_blur_col"
    static let blurRowKernel = "mask_blur_row"
    static let blurStoreKernel = "mask_blur_store"

    // MARK: - T2: the single-channel Deriche coefficients (Core-side mirror)

    /// Swift mirror of the MSL `MaskBlurUniforms` (48-byte constant layout).
    struct BlurUniforms {
        var a0: Float, a1: Float, a2: Float, a3: Float
        var b1: Float, b2: Float, coefp: Float, coefn: Float
        var width: UInt32
        var height: UInt32
        var rowEnd: UInt32
        private var _pad: UInt32 = 0
    }

    /// dt `_compute_gauss_params` (gaussian.c:41-100), DT_IOP_GAUSSIAN_ZERO
    /// order — the SAME-SOURCE derivation as LightamerIOP's
    /// `GaussianBlur.coeffs` (Core cannot import IOP; the duplicate is
    /// pinned equal by `testMaskBlurCoeffsMatchIOPGaussianBlur`, so they
    /// cannot drift).
    static func maskGaussCoeffs(sigma: Float) -> GaussianMaskCoeffs {
        let alpha = Double(1.695) / Double(sigma)
        let ema = Foundation.exp(-alpha)
        let ema2 = Foundation.exp(-2.0 * alpha)
        let b1 = -2.0 * ema
        let b2 = ema2
        let k = (1.0 - ema) * (1.0 - ema) / (1.0 + (2.0 * alpha * ema) - ema2)
        let a0 = k
        let a1 = k * (alpha - 1.0) * ema
        let a2 = k * (alpha + 1.0) * ema
        let a3 = -k * ema2
        let coefp = (a0 + a1) / (1.0 + b1 + b2)
        let coefn = (a2 + a3) / (1.0 + b1 + b2)
        return GaussianMaskCoeffs(
            a0: Float(a0), a1: Float(a1), a2: Float(a2), a3: Float(a3),
            b1: Float(b1), b2: Float(b2), coefp: Float(coefp), coefn: Float(coefn))
    }

    /// The single-channel blur (dt blend.c:705-714: sigma = blur_radius,
    /// mask bounds [0,1]). Two scratch float planes (width×height each) —
    /// the L018 two-buffer discipline.
    static func blur(
        mask: any MTLTexture, sigma: Float, metal: MetalContext
    ) async throws -> any MTLTexture {
        if sigma <= 0 { return mask } // the IIR degenerates at sigma 0; identity
        let w = mask.width, h = mask.height
        let output = try maskLike(mask, metal: metal)
        let planeBytes = w * h * MemoryLayout<Float>.stride
        guard let planes = metal.device.makeBuffer(
            length: planeBytes * 2, options: .storageModeShared)
        else { throw MetalError.bufferAllocationFailed(planeBytes * 2) }
        let c = maskGaussCoeffs(sigma: sigma)
        var uniforms = BlurUniforms(
            a0: c.a0, a1: c.a1, a2: c.a2, a3: c.a3,
            b1: c.b1, b2: c.b2, coefp: c.coefp, coefn: c.coefn,
            width: UInt32(w), height: UInt32(h), rowEnd: UInt32.max)

        // Pass 1 — columns (texture → plane half 0).
        let col = try await metal.makeEncoder(functionName: blurColKernel)
        var colUniforms = uniforms
        col.encoder.setTexture(mask, index: 0)
        col.encoder.setBytes(&colUniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
        col.encoder.setBuffer(planes, offset: 0, index: 1)
        col.encoder.dispatchThreads(
            MTLSize(width: w, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(256, col.pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        col.encoder.endEncoding()
        col.commandBuffer.commit()

        // Pass 2 — rows (plane 0 → plane 1; two planes, no aliasing).
        let row = try await metal.makeEncoder(functionName: blurRowKernel)
        var rowUniforms = uniforms
        row.encoder.setBuffer(planes, offset: 0, index: 0)
        row.encoder.setBuffer(planes, offset: planeBytes, index: 1)
        row.encoder.setBytes(&rowUniforms, length: MemoryLayout<BlurUniforms>.stride, index: 2)
        row.encoder.dispatchThreads(
            MTLSize(width: h, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(256, row.pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        row.encoder.endEncoding()
        row.commandBuffer.commit()

        // Pass 3 — store (plane 1 → texture).
        let store = try await metal.makeEncoder(functionName: blurStoreKernel)
        var storeUniforms = uniforms
        store.encoder.setBuffer(planes, offset: planeBytes, index: 0)
        store.encoder.setBytes(&storeUniforms, length: MemoryLayout<BlurUniforms>.stride, index: 1)
        store.encoder.setTexture(output, index: 0)
        store.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        store.encoder.endEncoding()
        store.commandBuffer.commit()
        return output
    }

    /// The mask post-processing chain in the PINNED dt assembly order
    /// (`_get_post_operations` blend.c:305-355, the after-blur
    /// feathering-guide default): blur → feather → tone curve, each gated
    /// by dt's thresholds (radius > 0.1; |contrast|/|brightness| ≥ 0.01
    /// with opacity > 1e-4). `gopacity` = the mask plane's premultiplied
    /// ceiling (the tone curve divides it back out — blendop.cl:1318).
    static func postProcess(
        mask: any MTLTexture,
        blurRadius: Float,
        featherRadius: Float,
        contrast: Float,
        brightness: Float,
        gopacity: Float,
        metal: MetalContext
    ) async throws -> any MTLTexture {
        var plane = mask
        // blur (dt blend.c:307 gate: blur_radius > 0.1)
        if blurRadius > 0.1 {
            plane = try await blur(mask: plane, sigma: blurRadius, metal: metal)
        }
        // feather (blend.c:306 gate: feathering_radius > 0.1) — the v1
        // single-channel Gaussian leg (see 06-04-DECISIONS D-06-04-T2-1).
        if featherRadius > 0.1 {
            plane = try await blur(mask: plane, sigma: featherRadius, metal: metal)
        }
        // tone curve LAST (blend.c:349-355).
        if needsToneCurve(contrast: contrast, brightness: brightness, opacity: gopacity) {
            plane = try await toneCurve(
                mask: plane, contrast: contrast, brightness: brightness,
                gopacity: gopacity, metal: metal)
        }
        return plane
    }

    // MARK: - T1: the parametric (blendif) mask plane

    /// Evaluate the parametric mask for one pixel column of the composite:
    /// `a` = the below/composite plane, `b` = this layer's plane (both
    /// rgba32Float working space), `form` = the drawn/form plane consumed
    /// as `form · conditional` (dt's mask_in; nil = the constant-1 leg).
    ///
    /// gopacity CONTRACT (the premultiply is applied EXACTLY once across
    /// the assembly): a `form` plane already carries the layer opacity
    /// (the 06-03 rasterizer premultiplies it) → pass gopacity = 1; with
    /// no form plane the kernel owns the fold → pass the layer opacity.
    static func parametricPlane(
        a: any MTLTexture,
        b: any MTLTexture,
        form: (any MTLTexture)?,
        spec: ParametricMask,
        layerOpacity: Float,
        metal: MetalContext
    ) async throws -> any MTLTexture {
        precondition(
            a.width == b.width && a.height == b.height,
            "blendif plane mismatch: \(a.width)x\(a.height) vs \(b.width)x\(b.height)")
        precondition(
            form == nil || (form!.width == a.width && form!.height == a.height),
            "blendif form plane must match the composite size")
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: a.width, height: a.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let output = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(a.width * a.height * 4)
        }
        var flags = MaskBlendifFlags(
            spec: spec, hasForm: form != nil,
            gopacity: form != nil ? 1.0 : max(0, min(1, layerOpacity)))
        var parameters = spec.packedParameters()
        guard let flagBuffer = metal.device.makeBuffer(
            bytes: &flags, length: MemoryLayout<MaskBlendifFlags>.stride,
            options: .storageModeShared),
            let paramBuffer = metal.device.makeBuffer(
            bytes: &parameters, length: parameters.count * MemoryLayout<Float>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }

        let session = try await metal.makeEncoder(functionName: blendifKernel)
        session.encoder.setTexture(a, index: 0)
        session.encoder.setTexture(b, index: 1)
        session.encoder.setTexture(form, index: 2)
        session.encoder.setTexture(output, index: 3)
        session.encoder.setBuffer(flagBuffer, offset: 0, index: 0)
        session.encoder.setBuffer(paramBuffer, offset: 0, index: 1)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    // MARK: - T3: the combine five ops (group.c:487-630)

    /// Swift mirror of the MSL `MaskCombineUniforms` (32 bytes).
    struct CombineUniforms {
        var op: UInt32           // 0 union, 1 intersect, 2 difference, 3 sum, 4 exclusion
        var inverted: UInt32     // the item's INVERSE state bit
        var rowEnd: UInt32
        private var _pad: UInt32 = 0
        var opacity: Float
        private var _p: (Float, Float, Float) = (0, 0, 0)
    }

    /// The reduce upper bound (plan 06-04 T3: N 通常 ≤4，>4 拒绝). dt has
    /// no hard limit; the v1 pipeline rejects beyond 4 to bound the ping-
    /// pong depth — documented in 06-04-DECISIONS.
    static let maxCombineInputs = 4

    /// A constant-value plane (the zero seed / the no-form fill).
    static func fill(
        _ value: Float, width: Int, height: Int, metal: MetalContext
    ) async throws -> any MTLTexture {
        let output = try maskLikeShape(width: width, height: height, metal: metal)
        var v = value
        let session = try await metal.makeEncoder(functionName: "mask_fill")
        session.encoder.setTexture(output, index: 0)
        session.encoder.setBytes(&v, length: MemoryLayout<Float>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    /// Nearest-neighbor resample to the consuming window (the raster
    /// store's resolution-mismatch leg — see the mask_resample kernel).
    static func resample(
        _ plane: any MTLTexture, toWidth: Int, toHeight: Int, metal: MetalContext
    ) async throws -> any MTLTexture {
        let output = try maskLikeShape(width: toWidth, height: toHeight, metal: metal)
        var outSize = SIMD2<UInt32>(UInt32(toWidth), UInt32(toHeight))
        let session = try await metal.makeEncoder(functionName: "mask_resample")
        session.encoder.setTexture(plane, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&outSize, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: toWidth, height: toHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    /// The mask-level invert (dt raster_mask_invert, blend.c:567-572).
    static func invert(
        plane: any MTLTexture, metal: MetalContext
    ) async throws -> any MTLTexture {
        let output = try maskLike(plane, metal: metal)
        let session = try await metal.makeEncoder(functionName: "mask_invert")
        session.encoder.setTexture(plane, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.dispatchThreads(
            MTLSize(width: plane.width, height: plane.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    /// One combine step: reads `dest` and `src`, writes a FRESH plane
    /// (ping-pong — never in-place, L018).
    static func combinePair(
        dest: any MTLTexture,
        src: any MTLTexture,
        op: MaskCombineOp,
        inverted: Bool,
        opacity: Float,
        metal: MetalContext
    ) async throws -> any MTLTexture {
        precondition(
            dest.width == src.width && dest.height == src.height,
            "combine plane mismatch: \(dest.width)x\(dest.height) vs \(src.width)x\(src.height)")
        let output = try maskLike(dest, metal: metal)
        var uniforms = CombineUniforms(
            op: UInt32(opCode(op)), inverted: inverted ? 1 : 0, rowEnd: UInt32.max,
            opacity: max(0, min(1, opacity)))
        let session = try await metal.makeEncoder(functionName: "mask_combine_pair")
        session.encoder.setTexture(dest, index: 0)
        session.encoder.setTexture(src, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBytes(
            &uniforms, length: MemoryLayout<CombineUniforms>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: dest.width, height: dest.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    /// The op → dt state-bit-order code (masks.h:55-64).
    static func opCode(_ op: MaskCombineOp) -> Int {
        switch op {
        case .union: return 0
        case .intersect: return 1
        case .difference: return 2
        case .sum: return 3
        case .exclusion: return 4
        }
    }

    /// The ordered reduce over N ≤ 4 inputs (dt `_group_get_mask_roi` —
    /// the zeroed intermediate buffer + in-order combine).
    ///
    /// FIRST-ITEM SEMANTICS (v1 normalization, documented in
    /// 06-04-DECISIONS): the first input INSTALLS its plane (union onto
    /// the zero seed = `max(0, opacity·(±1 − s))` — identical to dt's
    /// zero-seed union, which is the only reachable first-item state in
    /// dt's GUI; a dt zero-seed first-item difference/intersect degenerates
    /// to an empty mask). Subsequent inputs apply their own op.
    static func reduce(
        _ inputs: [MaskCombineInput], metal: MetalContext
    ) async throws -> any MTLTexture {
        if inputs.isEmpty { throw AppError.unsupportedFile("combine reduce needs at least one input") }
        if inputs.count > maxCombineInputs {
            throw AppError.unsupportedFile(
                "mask group combines more than \(maxCombineInputs) items " +
                    "(got \(inputs.count)) — nest groups instead")
        }
        let first = inputs[0].plane
        var dest = try await fill(0, width: first.width, height: first.height, metal: metal)
        for (index, input) in inputs.enumerated() {
            dest = try await combinePair(
                dest: dest, src: input.plane,
                op: index == 0 ? .union : input.op,
                inverted: input.inverted, opacity: input.opacity, metal: metal)
        }
        return dest
    }

    // MARK: - T3: the drawn group evaluation (per-item combine)

    /// Evaluate a MaskGroup: per-item single-form planes (or nested child
    /// groups, recursively) combined in order with per-item
    /// op/inverted/opacity. Returns nil when no item resolves to a plane —
    /// the caller falls back to dt's no-form fill semantics
    /// (blend.c:612-616: fill 1.0 for the exclusive combine).
    static func drawnGroupPlane(
        group: MaskGroupSpec,
        forms: [MaskForm],
        window: ROI,
        mapper: GeometryPointMapper,
        metal: MetalContext,
        depth: Int = 0
    ) async throws -> any MTLTexture? {
        precondition(depth < 8, "MaskGroup nesting deeper than 8 — reject")
        var inputs: [MaskCombineInput] = []
        for item in group.items {
            let plane: any MTLTexture
            if let child = item.child {
                guard let childPlane = try await drawnGroupPlane(
                    group: child, forms: forms, window: window,
                    mapper: mapper, metal: metal, depth: depth + 1)
                else { continue }
                plane = childPlane
            } else if let form = forms.first(where: { $0.id == item.formID }) {
                plane = try await DrawnMaskRasterizer.singleFormPlane(
                    form: form, window: window, mapper: mapper, metal: metal)
            } else {
                continue // missing form — dt skips the item (nb_ok accounting)
            }
            inputs.append(MaskCombineInput(
                plane: plane, op: item.op, inverted: item.inverted,
                opacity: max(0, min(1, item.opacity))))
            if inputs.count == maxCombineInputs { break } // documented bound
        }
        guard !inputs.isEmpty else { return nil }
        return try await reduce(inputs, metal: metal)
    }

    // MARK: - T5: the three-way assembly (dt mask_mode ⊕ semantics)

    /// Assemble the layer's SINGLE effective mask plane from up to three
    /// payloads (D-06-04-T5-1, 06-RESEARCH §3.1 — dt's
    /// MASK|CONDITIONAL|RASTER combination, generalized):
    ///
    ///   plane = drawn (group-combined, or the 06-3 single form)
    ///         ⊗ parametric (the dt kernel semantics: form · conditional;
    ///           no form plane → the constant-1 leg)
    ///         ⊓ raster (the loaded PNG, inverted per ref — the five-op
    ///           INTERSECT join, opacity 1; min ≈ the multiplicative
    ///           chain's binary limit)
    ///   then the post chain (blur → feather → tone curve) and the layer
    ///   opacity folded EXACTLY ONCE (the D-06-02-T5-3 premultiply
    ///   contract).
    ///
    /// The result caches at `maskKey(spec.stableHash())` — any payload
    /// edit flips ONLY this line (the METAL-8 independence).
    ///
    /// Raster loading needs the sidecar's masks directory; `maskDirectory`
    /// nil + a raster ref present degrades through the documented all-ones
    /// leg (the reason is surfaced, never swallowed).
    /// - `upstreamHash` (GUI-21, 2026-09-24): the identity of the sampled
    ///   input planes (below ⊕ top ⊕ mask — the composite prefix hash at
    ///   the caller). The parametric leg SAMPLES the live composite; a key
    ///   blind to it reuses a stale parametric plane after any below-edit.
    ///   Default 0 = the display-tint callers (input identity not tracked
    ///   there — pre-existing behavior, different key domain from the
    ///   composite's folded keys so no collision).
    public static func effectivePlane(
        spec: MaskSpec,
        layerOpacity: Float,
        window: ROI,
        below: any MTLTexture,
        top: any MTLTexture,
        mapper: GeometryPointMapper,
        metal: MetalContext,
        cache: PipeCache,
        imageID: UUID,
        pipeType: PipeResolution,
        layerID: UUID,
        maskDirectory: URL?,
        upstreamHash: UInt64 = 0,
        rasterStore: RasterMaskStore.Type = RasterMaskStore.self
    ) async throws -> (plane: any MTLTexture, hit: Bool, degradedReason: String?) {
        var hash = DrawnMaskRasterizer.foldKeyHash(spec: spec, mapper: mapper)
        var upstream = upstreamHash
        hash = withUnsafeBytes(of: &upstream) { StableHash.combine(hash, $0) }
        let key = PipeCacheKey.maskKey(
            imageID: imageID, pipeType: pipeType, layerID: layerID,
            maskHash: hash, roi: window)
        let byteCount = window.width * window.height * 4
        let statsBefore = await cache.stats
        // The degrade reason must cross the @Sendable cache closure — a
        // tiny box (the closure runs at most once: the miss path).
        let reasonBox = ReasonBox()
        // TextureBox: the @unchecked-Sendable ownership wrapper (the planes
        // are read-only inside the closure) — the driver's pattern.
        let belowBox = TextureBox(texture: below)
        let topBox = TextureBox(texture: top)
        let box = try await cache.plane(for: key, byteCount: byteCount) {
            let (texture, reason) = try await Self.assembleUnmasked(
                spec: spec, layerOpacity: layerOpacity, window: window,
                below: belowBox.texture, top: topBox.texture, mapper: mapper,
                metal: metal, maskDirectory: maskDirectory,
                rasterStore: rasterStore)
            reasonBox.value = reason
            return texture
        }
        let delta = (await cache.stats) - statsBefore
        return (box.texture, delta.hits > 0, reasonBox.value)
    }

    /// The uncached assembly (the cache-miss closure).
    static func assembleUnmasked(
        spec: MaskSpec,
        layerOpacity: Float,
        window: ROI,
        below: any MTLTexture,
        top: any MTLTexture,
        mapper: GeometryPointMapper,
        metal: MetalContext,
        maskDirectory: URL?,
        rasterStore: RasterMaskStore.Type
    ) async throws -> (plane: any MTLTexture, degradedReason: String?) {
        let opacity = max(0, min(1, layerOpacity))
        var plane: any MTLTexture?
        var degradedReason: String?

        // ── The drawn leg.
        if spec.hasDrawnGroup, let group = spec.drawn?.group {
            // Per-item planes → the five-op reduce. The layer opacity is
            // NOT yet folded (item opacities applied at combine time per
            // dt) — folded below via the blendif leg or the scale pass.
            if let groupPlane = try await drawnGroupPlane(
                group: group, forms: spec.drawn?.forms ?? [], window: window,
                mapper: mapper, metal: metal)
            {
                plane = try await scale(
                    groupPlane, opacity: opacity, metal: metal)
            }
            // nil group plane (no resolvable item) → dt's no-form fill 1
            // leg: leave nil — the blendif leg then sees form = 1, and
            // without a parametric leg the layer opacity alone applies.
        } else if spec.hasDrawnForms {
            // The 06-3 single-form path (layer opacity folded inside).
            plane = try await DrawnMaskRasterizer.render(
                spec: spec, layerOpacity: opacity, window: window,
                mapper: mapper, metal: metal, rowBands: 1)
        }

        // ── The parametric leg (the dt form ⊗ conditional kernel).
        if let parametric = spec.parametric, parametric.hasActiveChannels {
            plane = try await parametricPlane(
                a: below, b: top, form: plane, spec: parametric,
                layerOpacity: plane != nil ? 1 : opacity, metal: metal)
        }

        // ── The raster leg (load + verify; invert inside the store).
        if let ref = spec.raster {
            if let directory = maskDirectory {
                switch try await rasterStore.load(
                    ref: ref, directory: directory,
                    windowWidth: window.width, windowHeight: window.height,
                    metal: metal)
                {
                case let .plane(rasterPlane):
                    if let current = plane {
                        // The intersect join (opacity 1 — the plane is raw).
                        plane = try await combinePair(
                            dest: current, src: rasterPlane,
                            op: .intersect, inverted: false, opacity: 1,
                            metal: metal)
                    } else {
                        // Raster-only: install with the layer opacity.
                        plane = try await scale(rasterPlane, opacity: opacity, metal: metal)
                    }
                case let .degraded(ones, reason):
                    // D-06-04-T4-2: min(effective, 1) == effective — the
                    // degrade is content-neutral for the INTERSECT join
                    // (plane != nil), but the RASTER-ONLY install must
                    // still fold the layer opacity (06-05 leftover — the
                    // 06-04 note-1 gap: an unscaled all-ones plane would
                    // blend at full opacity regardless of the slider).
                    degradedReason = reason
                    if plane == nil { plane = try await scale(ones, opacity: opacity, metal: metal) }
                }
            } else {
                degradedReason =
                    "raster mask referenced but no masks directory provided: \(ref.fileName)"
                if plane == nil {
                    // Raster-only degrade: same opacity fold as above.
                    plane = try await scale(
                        try await MaskCombiner.fill(1, width: window.width, height: window.height, metal: metal),
                        opacity: opacity, metal: metal)
                }
            }
        }

        // ── The no-payload guard is the caller's (hasAnyPayload); a fully
        // empty assembly degrades to the constant-1 plane × opacity.
        let effective: any MTLTexture
        if let plane {
            effective = plane
        } else {
            effective = try await scale(
                try await fill(1, width: window.width, height: window.height, metal: metal),
                opacity: opacity, metal: metal)
        }

        // ── The post chain (the pinned dt order; the params live on the
        // parametric payload — dt's blend params shape).
        var output = effective
        if let parametric = spec.parametric {
            output = try await postProcess(
                mask: effective,
                blurRadius: parametric.blurRadius,
                featherRadius: parametric.featherRadius,
                contrast: parametric.contrast,
                brightness: parametric.brightness,
                gopacity: opacity,
                metal: metal)
        }
        return (output, degradedReason)
    }

    /// Fold `opacity` into a raw plane once (the union-onto-zero identity:
    /// max(0, v·op) = v·op for v ≥ 0) — no dedicated kernel needed.
    static func scale(
        _ plane: any MTLTexture, opacity: Float, metal: MetalContext
    ) async throws -> any MTLTexture {
        let zero = try await fill(0, width: plane.width, height: plane.height, metal: metal)
        return try await combinePair(
            dest: zero, src: plane, op: .union, inverted: false,
            opacity: opacity, metal: metal)
    }

    // MARK: - T2: the mask post-processing chain
    // (order pinned: blur → feather → tone curve — dt `_get_post_operations`
    // blend.c:305-355, the after-blur feathering-guide default; see
    // 06-04-DECISIONS for the v1 guide/deviation record.)

    /// dt's tone-curve gate (blend.c:308-309): |contrast| ≥ 0.01 or
    /// |brightness| ≥ 0.01 (with opacity > 1e-4 — blend.c:349).
    static func needsToneCurve(contrast: Float, brightness: Float, opacity: Float) -> Bool {
        (abs(contrast) >= 0.01 || abs(brightness) >= 0.01) && opacity > 1e-4
    }

    /// The mask tone-curve post op (blend.c:407-443 CPU shape /
    /// blendop.cl:1309-1449 kernel) — `e = exp(3·contrast)` folded here.
    static func toneCurve(
        mask: any MTLTexture, contrast: Float, brightness: Float,
        gopacity: Float, metal: MetalContext
    ) async throws -> any MTLTexture {
        let output = try maskLike(mask, metal: metal)
        var uniforms = MaskToneCurveUniforms(
            e: exp(3.0 * contrast), brightness: brightness,
            gopacity: gopacity, rowEnd: UInt32.max)
        let session = try await metal.makeEncoder(functionName: toneCurveKernel)
        session.encoder.setTexture(mask, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(
            &uniforms, length: MemoryLayout<MaskToneCurveUniforms>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    /// A fresh r32Float plane shaped like `mask`.
    static func maskLike(
        _ mask: any MTLTexture, metal: MetalContext
    ) throws -> any MTLTexture {
        try maskLikeShape(width: mask.width, height: mask.height, metal: metal)
    }

    /// A fresh r32Float plane of the given shape.
    static func maskLikeShape(
        width: Int, height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height,
            mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let t = metal.device.makeTexture(descriptor: d) else {
            throw MetalError.bufferAllocationFailed(width * height * 4)
        }
        return t
    }
}

/// Swift mirror of the MSL `MaskToneCurveUniforms` (16 bytes).
struct MaskToneCurveUniforms {
    var e: Float            // exp(3·contrast) — host-computed (dt blend.c:415)
    var brightness: Float   // −1..1
    var gopacity: Float     // the mask's premultiplied ceiling
    var rowEnd: UInt32
}

/// The eight Deriche IIR coefficients (the `GaussianCoeffs` shape, mirrored
/// in Core for the mask post chain — see `MaskCombiner.maskGaussCoeffs`).
struct GaussianMaskCoeffs: Sendable, Equatable {
    var a0: Float
    var a1: Float
    var a2: Float
    var a3: Float
    var b1: Float
    var b2: Float
    var coefp: Float
    var coefn: Float
}
