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
///
/// ⚠ HOST FINDING (Phase 1, 2026-09-16): `CIContext.render(_:toMTLTexture:)`
/// completes without error but writes NOTHING on this macOS 27.0 / Apple M4
/// host — verified across rgba8Unorm/rgba16Float/rgba32Float,
/// shared/managed storage, device/queue contexts, nil/owned command buffers
/// (`.work/01-03/smoke` + probes). The bitmap render path
/// (`render(_:toBitmap:...)`, `CIFormat.RGBAf`) is byte-correct, so this
/// bridge renders to an float32 CPU buffer and stages it into the shared
/// texture via `replace(region:)`. The extra copy costs ~0.3-0.5 s at 100MP
/// (within the D-32 display budget); Phase 2 must re-test the direct
/// texture path before the linear pixelpipe replaces this bridge.
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
            .workingFormat: CIFormat.RGBAh,                // CI-internal half working format; the cast to float32 happens at the render step
            .cacheIntermediates: false,                    // CIRAW-4
        ])
    }

    /// Render `image` into a freshly allocated `.rgba32Float` texture sized
    /// to the image extent, with pixels in linear Rec2020 (FOUND-02).
    /// Ownership handoff is carried by `RenderedTexture` (same documented
    /// `@unchecked Sendable` pattern as `MetalContext.ComputeEncoderSession`):
    /// the pool retains nothing; the receiver owns the texture exclusively.
    internal struct RenderedTexture: @unchecked Sendable {
        let texture: any MTLTexture
    }

    internal func renderToTexture(_ image: CIImage) throws -> RenderedTexture {
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

        let signposter = Self.signposter
        let interval = signposter.beginInterval("render", id: signposter.makeSignpostID())
        defer { signposter.endInterval("render", interval) }

        let rowBytes = width * WorkingSpace.bytesPerPixel
        let byteCount = rowBytes * height
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { buffer.deallocate() }

        // Bitmap render (see host-finding note): float32 RGBA pixels in the
        // linear Rec2020 output space — the pixelpipe format, byte-exact.
        ciContext.render(
            image,
            toBitmap: buffer,
            rowBytes: rowBytes,
            bounds: extent,
            format: CIFormat.RGBAf,
            colorSpace: WorkingSpace.colorSpace
        )
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: rowBytes
        )
        return RenderedTexture(texture: texture)
    }
}
