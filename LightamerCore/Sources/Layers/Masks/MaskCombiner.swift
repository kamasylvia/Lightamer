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
