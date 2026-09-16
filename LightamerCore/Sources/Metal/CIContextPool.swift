import CoreImage
import Metal
import os

/// The CIImage → MTLTexture bridge (internal to Core — RESEARCH §9 internal
/// surface: only Core's RAWDecoder/pixelpipe path uses it; the app reaches it
/// through `MetalContext.renderToTexture`).
///
/// - ONE `CIContext` per `MTLDevice` (WWDC "Optimize the Core Image
///   pipeline") — this actor owns it for the app's lifetime.
/// - Working/output color space = `WorkingSpace.colorSpace` (linear Rec2020,
///   FOUND-02); output pixels land in `WorkingSpace.pixelFormat`
///   (`.rgba32Float`, float32 RGBA — L006: no half on shadow-sensitive
///   paths).
/// - `cacheIntermediates: false` is MANDATORY (CIRAW-4): lazy CIImage chains
///   on 100MP otherwise hold gigabytes of ROI descriptors.
internal actor CIContextPool {

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let ciContext: CIContext

    /// D-31: the render leg of the vertebra is signposted ("decode" lives in
    /// RAWDecoder/EditorState; "render" here).
    private static let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer", category: "metal")

    init(device: any MTLDevice, commandQueue: any MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: WorkingSpace.colorSpace,   // linear Rec2020 (FOUND-02)
            .outputColorSpace: WorkingSpace.colorSpace,
            .workingFormat: CIFormat.RGBAh,               // CI-internal half working format; the cast to float32 happens at the render step
            .cacheIntermediates: false,                    // CIRAW-4
        ])
    }

    /// Render `image` into a freshly allocated `.rgba32Float` texture sized
    /// to the image extent, using the command-buffer-bearing `render`
    /// overload (RESEARCH §3 gotcha #5 — never the synchronous MainActor-
    /// blocking variant). The committed command buffer serializes on the
    /// shared queue, so downstream draws/tests see complete pixels. The
    /// texture is `sending`-transferred to the caller (ownership leaves this
    /// actor; the pool retains nothing).
    internal func renderToTexture(_ image: CIImage) throws -> sending any MTLTexture {
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width >= 1, height >= 1 else {
            throw AppError.decodeFailed("CIImage has an empty extent")
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, // .rgba32Float
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared // METAL-4: Apple Silicon UMA
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            // 100MP float32 RGBA ≈ 1.6GB — allocation failure = budget
            // exceeded; the Phase 2 tiling path (D-20) engages later.
            throw MetalError.bufferAllocationFailed(width * height * WorkingSpace.bytesPerPixel)
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw MetalError.deviceUnavailable
        }

        let signposter = Self.signposter
        let interval = signposter.beginInterval("render", id: signposter.makeSignpostID())
        defer { signposter.endInterval("render", interval) }

        ciContext.render(
            image,
            to: texture,
            commandBuffer: commandBuffer,
            bounds: extent,
            colorSpace: WorkingSpace.colorSpace
        )
        commandBuffer.commit()
        return texture
    }
}
