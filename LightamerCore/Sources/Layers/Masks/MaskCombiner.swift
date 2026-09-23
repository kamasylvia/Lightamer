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

/// One entry of a combine reduce: (plane, op, inverted, opacity).
struct MaskCombineInput {
    var plane: any MTLTexture
    var op: MaskCombineOp
    var inverted: Bool
    var opacity: Float
}

enum MaskCombiner {

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
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: mask.width, height: mask.height,
            mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let t = metal.device.makeTexture(descriptor: d) else {
            throw MetalError.bufferAllocationFailed(mask.width * mask.height * 4)
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
