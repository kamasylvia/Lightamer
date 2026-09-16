import LightamerCore
import Metal

/// Phase-1 entry surface for the pass-through kernel (success criterion #2).
///
/// The kernel-name + bundle-anchor convenience kept from Plan 03: the
/// app/tests register LightamerIOP's `default.metallib` (which contains the
/// compiled `.metal` file) via
/// `MetalContext.registerDefaultLibrary(in: PassthroughKernel.metalBundle)`.
///
/// `public` (cross-module).
public enum PassthroughKernel {

    /// MSL function name of the pass-through kernel (`Passthrough.metal`).
    public static let functionName = "pass_through"

    /// The LightamerIOP framework bundle — the `registerDefaultLibrary(in:)`
    /// anchor. RESEARCH §1 gotcha #1: the IOP metallib lives in the FRAMEWORK
    /// bundle, never `Bundle.main`.
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// `Bundle(for:)` anchor class for `PassthroughKernel.metalBundle`.
/// `internal` — never referenced outside LightamerIOP.
final class IOPBundleMarker {}

/// The no-op reference iop (success criterion #3, FOUND-03): the FULL
/// `IOPModule` conformance that every Phase 3+ module copies — params,
/// defaults, ROI plumbing, and a `process` that drives GPU work through
/// `MetalContext` (the smoke-verified `pass_through` kernel from Plan 03).
///
/// `opName` is `"passthrough_spike"` (NOT a Darktable op string — this
/// module never enters sidecars; RESEARCH §5 gotcha). `iopOrder` 50.5 is
/// an arbitrary Phase 1 position between `shadhi` (50.0) and `zonesystem`
/// (51.0) in the `V50Order` table.
///
/// `process` buffer↔texture staging: the IOPModule contract is
/// buffer-based (Darktable's `dt_iop_module_t` model), while the Phase 1
/// `pass_through` kernel is texture-based (Plan 03's MetalContext proof).
/// The process step therefore stages the input buffer into a texture
/// (explicit blit command buffer, awaited), dispatches the kernel via
/// `metal.dispatch2D` with the textures bound in `configure`, drains the
/// queue (same-queue FIFO ordering — Metal executes command buffers in
/// commit order), and blits the output texture back into the output
/// buffer. Phase 2 re-evaluates buffer- vs texture-domain kernels when the
/// real pipe lands; the staging here is the reference for either choice.
///
/// Not `Sendable` by design: a module instance (and its cached constant
/// set + staging textures) is owned by its pipe run's isolation domain —
/// the same contract as `IOPiece`. Phase 2's `ModuleRegistry` stores
/// METATYPES (`PassthroughModule.Type`), which are Sendable.
public final class PassthroughModule: IOPModule {

    /// Empty parameter record — the pass-through has nothing to tune; the
    /// shape proves the `Codable & Hashable` sidecar/cache plumbing.
    public struct Params: Codable, Hashable {
        public init() {}
    }

    public static let opName = "passthrough_spike"

    /// Arbitrary Phase 1 position (between shadhi 50.0 and zonesystem 51.0).
    public static let iopOrder: Float = 50.5

    public static let flags: IOPFlags = []

    public static let defaultColorspace: IOPColorspace = .RGB

    /// Identity specialization of the kernel — `useSrgbGamma = false`,
    /// `exposureEV = 0`. BOTH constants must be set (the kernel declares no
    /// MSL defaults; RESEARCH §3 gotcha). Cached per instance so every
    /// dispatch hits the same `PSOKey` (D-16: instance identity is the
    /// constants fingerprint; Plan 03 verified the cache-hit path).
    private var identityConstants: MTLFunctionConstantValues?

    /// Reused staging textures keyed by ROI size (allocated on first use).
    private var staging: (input: any MTLTexture, output: any MTLTexture, width: Int, height: Int)?

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        // The cache-identity hash (Phase 2 keys pipe output on this).
        piece.paramsHash = params.hashValue
    }

    /// Identity: the pass-through produces exactly the input ROI.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Identity: the pass-through needs exactly the output ROI as input.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func process(
        input: any MTLBuffer,
        output: any MTLBuffer,
        roiIn: ROI,
        roiOut: ROI,
        piece: IOPiece,
        metal: MetalContext
    ) async throws {
        let width = roiOut.width
        let height = roiOut.height
        guard width >= 1, height >= 1 else {
            throw MetalError.bufferAllocationFailed(width * height * WorkingSpace.bytesPerPixel)
        }
        let bytesPerRow = width * WorkingSpace.bytesPerPixel

        // 0. Kernel constants: identity specialization (lazily built once
        // per module instance → stable PSOKey → D-16 cache hits).
        let constants: MTLFunctionConstantValues
        if let identityConstants {
            constants = identityConstants
        } else {
            let built = metal.makeConstants(false, at: 0, type: .bool)
            metal.setConstant(Float(0.0), at: 1, type: .float, into: built)
            identityConstants = built
            constants = built
        }

        // 1. Staging textures (shared storage, UMA — METAL-4).
        let textures: (input: any MTLTexture, output: any MTLTexture, width: Int, height: Int)
        if let staging, staging.width == width, staging.height == height {
            textures = staging
        } else {
            func makeTexture() throws -> any MTLTexture {
                let d = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: WorkingSpace.pixelFormat,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                d.usage = [.shaderRead, .shaderWrite]
                d.storageMode = .shared
                guard let t = metal.device.makeTexture(descriptor: d) else {
                    throw MetalError.bufferAllocationFailed(width * height * WorkingSpace.bytesPerPixel)
                }
                return t
            }
            textures = (try makeTexture(), try makeTexture(), width, height)
            staging = textures
        }

        // 2. Stage the input buffer into the input texture (explicit blit
        // command buffer, awaited — same-queue FIFO then orders the kernel
        // dispatch after it).
        guard let stageIn = metal.commandQueue.makeCommandBuffer(),
              let blitIn = stageIn.makeBlitCommandEncoder() else {
            throw MetalError.deviceUnavailable
        }
        blitIn.copy(
            from: input,
            sourceOffset: 0,
            sourceBytesPerRow: bytesPerRow,
            sourceBytesPerImage: bytesPerRow,
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: textures.input,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitIn.endEncoding()
        stageIn.commit()

        // 3. THE iop dispatch (the acceptance-critical path): buffers bound
        // at 0/1 per the dispatch2D contract; the kernel's textures bound
        // through `configure`.
        try await metal.dispatch2D(
            functionName: PassthroughKernel.functionName,
            input: input,
            output: output,
            width: width,
            height: height,
            constants: constants
        ) { encoder in
            encoder.setTexture(textures.input, index: 0)
            encoder.setTexture(textures.output, index: 1)
        }

        // 4. Drain: an empty command buffer committed AFTER the kernel's
        // completes only when the kernel has (same-queue FIFO).
        guard let drain = metal.commandQueue.makeCommandBuffer() else {
            throw MetalError.deviceUnavailable
        }
        drain.commit()
        _ = await drain.completed()

        // 5. Stage the output texture back into the output buffer, awaited
        // so `process` returning implies the output buffer is valid.
        guard let stageOut = metal.commandQueue.makeCommandBuffer(),
              let blitOut = stageOut.makeBlitCommandEncoder() else {
            throw MetalError.deviceUnavailable
        }
        blitOut.copy(
            from: textures.output,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow
        )
        blitOut.endEncoding()
        stageOut.commit()
        _ = await stageOut.completed()
    }
}
