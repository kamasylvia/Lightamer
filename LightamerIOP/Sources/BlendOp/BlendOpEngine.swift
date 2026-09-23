import Foundation
import LightamerCore
import Metal

/// The test/consumer dispatch face of the blendop engine (Plan 06-02 T2).
///
/// `LayerCompositeDriver` (Core) owns the PRODUCTION dispatch — it cannot
/// import LightamerIOP, so it carries its own uniform mirror
/// (`BlendCompositeUniforms`) and packs the SAME 32-byte ABI defined by
/// `BlendOpUniforms` in BlendOpKernels.metal. This engine exposes the
/// kernel to LightamerIOP consumers and the parity tests with explicit
/// raw parameters (per-mode × opacity sweeps, mask planes, tiling splits).
/// Both packings are pinned by the same test gates — a drift breaks them
/// loudly (the L023-style half-contract discipline: kernel ↔ mirrors are
/// one contract, tests pin the whole).
public enum BlendOpEngine {

    /// MSL function name of the composite triple kernel.
    public static let compositeKernel = "compositeLayer"

    /// MSL function name of the L023 exact-leg probe
    /// (mode 0 = matrix legs, 1 = polar legs).
    public static let probeKernel = "blendop_jz_probe"

    /// Dispatch one composite pass into a fresh plane.
    ///
    /// - `below`/`layer`: float32 RGBA planes, same size (working space).
    /// - `mask`: optional single-channel-or-RGBA plane whose **red channel
    ///   is the per-pixel EFFECTIVE opacity** (dt's post-fold mask plane,
    ///   blend.c:530 — gopacity × form already applied; never re-multiplied).
    ///   nil = uniform opacity path (`blendop_set_mask` equivalence).
    /// - `opacity`: the layer opacity, CLIPped here (blend.c:458).
    /// - `blendParameter`: dt blend_parameter; p = exp2 is folded here
    ///   (blend.c:1301) before the kernel sees it.
    public static func composite(
        below: any MTLTexture,
        layer: any MTLTexture,
        mask: (any MTLTexture)? = nil,
        opacity: Float,
        blendMode: BlendMode,
        blendParameter: Float = 0.0,
        reverse: Bool = false,
        metal: MetalContext
    ) async throws -> any MTLTexture {
        precondition(
            below.width == layer.width && below.height == layer.height,
            "blend plane mismatch: \(below.width)x\(below.height) vs \(layer.width)x\(layer.height)")
        precondition(
            mask == nil || (mask!.width == below.width && mask!.height == below.height),
            "mask plane must match the composite size")
        let clipped = max(0, min(1, opacity))
        var uniforms = BlendOpDispatchUniforms(
            opacity: clipped,
            blendMode: UInt32(blendMode.rawValue),
            reverse: reverse ? 1 : 0,
            hasMask: mask != nil ? 1 : 0,
            blendParam: exp2(blendParameter))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: below.width, height: below.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let output = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(
                below.width * below.height * WorkingSpace.bytesPerPixel)
        }
        let session = try await metal.makeEncoder(functionName: compositeKernel)
        session.encoder.setTexture(below, index: 0)
        session.encoder.setTexture(layer, index: 1)
        session.encoder.setTexture(mask, index: 2)
        session.encoder.setTexture(output, index: 3)
        session.encoder.setBytes(
            &uniforms, length: MemoryLayout<BlendOpDispatchUniforms>.stride, index: 0)
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        precondition(
            threadsPerGroup.width * threadsPerGroup.height
                <= session.pipelineState.maxTotalThreadsPerThreadgroup,
            "compositeLayer threadgroup exceeds the PSO budget")
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: threadsPerGroup)
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    /// Dispatch a composite pass writing ONLY the row band [rowStart,
    /// rowEnd) of a pre-sized output — the tiling-identity seam (plan T5.3:
    /// a pointwise kernel must produce byte-identical output split or
    /// whole; the gate pins against future neighborhood semantics).
    public static func compositeRows(
        below: any MTLTexture,
        layer: any MTLTexture,
        mask: (any MTLTexture)?,
        opacity: Float,
        blendMode: BlendMode,
        blendParameter: Float = 0.0,
        reverse: Bool = false,
        rows: Range<Int>,
        into output: any MTLTexture,
        metal: MetalContext
    ) async throws {
        var uniforms = BlendOpDispatchUniforms(
            opacity: max(0, min(1, opacity)),
            blendMode: UInt32(blendMode.rawValue),
            reverse: reverse ? 1 : 0,
            hasMask: mask != nil ? 1 : 0,
            blendParam: exp2(blendParameter),
            rowBegin: UInt32(rows.lowerBound),
            rowEnd: UInt32(rows.upperBound))
        let session = try await metal.makeEncoder(functionName: compositeKernel)
        session.encoder.setTexture(below, index: 0)
        session.encoder.setTexture(layer, index: 1)
        session.encoder.setTexture(mask, index: 2)
        session.encoder.setTexture(output, index: 3)
        session.encoder.setBytes(
            &uniforms, length: MemoryLayout<BlendOpDispatchUniforms>.stride, index: 0)
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        precondition(
            threadsPerGroup.width * threadsPerGroup.height
                <= session.pipelineState.maxTotalThreadsPerThreadgroup,
            "compositeLayer threadgroup exceeds the PSO budget")
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: threadsPerGroup)
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// Dispatch the L023 exact-leg probe (mode 0 = Rec2020⇄XYZ matrix pair
    /// identity, mode 1 = polar round trip) over `input` into a fresh plane.
    public static func probe(
        input: any MTLTexture, mode: UInt32, metal: MetalContext
    ) async throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: input.width, height: input.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let output = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(
                input.width * input.height * WorkingSpace.bytesPerPixel)
        }
        var modeValue = mode
        let session = try await metal.makeEncoder(functionName: probeKernel)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&modeValue, length: 4, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }
}

/// Swift mirror of the MSL `BlendOpUniforms` (32-byte constant layout).
public struct BlendOpDispatchUniforms {
    public var opacity: Float
    public var blendMode: UInt32
    public var reverse: UInt32
    public var hasMask: UInt32
    public var blendParam: Float
    public var rowBegin: UInt32
    public var rowEnd: UInt32
    public private(set) var _pad: UInt32 = 0

    public init(
        opacity: Float, blendMode: UInt32, reverse: UInt32,
        hasMask: UInt32, blendParam: Float,
        rowBegin: UInt32 = 0, rowEnd: UInt32 = UInt32.max
    ) {
        self.opacity = opacity
        self.blendMode = blendMode
        self.reverse = reverse
        self.hasMask = hasMask
        self.blendParam = blendParam
        self.rowBegin = rowBegin
        self.rowEnd = rowEnd
    }
}
