import CoreGraphics
import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// SessionThumbnailRenderer (Plan 09-03 T4) — the App-side assembly of the
// thumbnail provider's injected legs.
//
// THIS is the file that touches the plane cache — the provider (Core/
// Session) never does. The tier-B leg constructs a THROWAWAY per-run
// `PipeCache`: the browser tier's planes live for the duration of one run
// and die with it — the shared session cache (the coordinator's) is never
// consulted, never mutated, never even visible to the browser tier. The
// resident regression (`SessionThumbnailProviderTests` isolation section)
// asserts the observed cache total is byte-identical across browser
// renders, and `grep -rn PipeCache Core/Session App/Session` stays
// zero-hit outside THIS file's own throwaway.
//
// Phase 8 contract (禁改): the leg branches processComposite/process with
// the SAME shape as the coordinator's `renderCurrentChain` — the
// `LayerCompositeDriver` (terminalTailFloor 70.0) does the splitting, and
// the yiyin per-run context rides the provider's `runContextInjector` seam
// implemented here against the same atoms (captureExif, logo faces, the
// borders joint layout record).
// ─────────────────────────────────────────────────────────────────────────────

enum SessionThumbnailRenderer {

    /// The tier-B GPU leg: request → display CGImage (8-bit RGBA sRGB).
    static func renderLeg(metal: MetalContext) -> ThumbnailRenderLeg {
        { request in
            // THROWAWAY per-run cache — the isolation contract. Every run
            // builds its own; the shared session cache is never passed in.
            let cache = PipeCache()
            let longEdge = request.resolution.defaultLongEdge
            let texture: any MTLTexture
            if let stack = request.layerStack, !stack.compositeLayers.isEmpty {
                let maskDirectory = RasterMaskStore.masksDirectory(forImageURL: request.url)
                let (rendered, _) = try await RenderPipeline.processComposite(
                    image: request.decoded,
                    instances: request.instances,
                    layerStack: stack,
                    registry: request.registry,
                    imageID: request.imageID,
                    resolution: request.resolution,
                    cache: cache,
                    metal: metal,
                    longEdge: longEdge,
                    roiHint: nil,
                    policy: request.resolution == .full ? .fullColdLayer : .preview,
                    hotLayerID: nil,
                    maskDirectory: maskDirectory
                )
                texture = rendered
            } else {
                let (rendered, _) = try await RenderPipeline.process(
                    image: request.decoded,
                    instances: request.instances,
                    imageID: request.imageID,
                    resolution: request.resolution,
                    cache: cache,
                    metal: metal,
                    longEdge: longEdge
                )
                texture = rendered
            }
            // The throwaway cache dies here — no plane outlives the run.
            return try Self.cgImage(from: texture, metal: metal)
        }
    }

    /// The yiyin per-run context injector — the CONTRACT twin of the
    /// coordinator's `injectYiyinRunContext` (which stays 禁改). Same data
    /// face: watermark captureExif + embedded logo faces + the joint
    /// layout record onto the borders box.
    static func runContextInjector(yiyinLogoStore: YiyinLogoStore) -> ThumbnailRunContextInjector {
        { instances, decoded, _, longEdge in
            guard let watermarkBox = instances.first(where: {
                $0.opName == WatermarkModule.opName
            }) as? ModuleBox<WatermarkModule> else { return }

            let watermark = watermarkBox.module
            watermark.captureExif = decoded.capture
            watermark.logoExists = { make, variant in
                yiyinLogoStore.embeddedExists(make: make, variant: variant)
            }
            watermark.logoProvider = yiyinLogoStore.provider()

            // The borders joint record needs the borders PARAMS — decoded
            // from the provider-materialized box's committed paramsData
            // (the coordinator reads editorState's record; this is the
            // sidecar-driven twin).
            var bordersParams: BordersModule.Params?
            if let bordersBox = instances.first(where: {
                $0.opName == BordersModule.opName
            }) as? ModuleBox<BordersModule> {
                bordersParams = try? JSONDecoder().decode(
                    BordersModule.Params.self, from: bordersBox.paramsData
                )
            }

            // The entry plane size — the same scale math as PixelPipe.run.
            let fullWidth = max(Int(decoded.ciImage.extent.width), 1)
            let fullHeight = max(Int(decoded.ciImage.extent.height), 1)
            let scale = longEdge.map {
                min(
                    CGFloat($0) / CGFloat(fullWidth),
                    CGFloat($0) / CGFloat(fullHeight), 1.0
                )
            }
            let planeW = scale.map { max(1, Int((CGFloat(fullWidth) * $0).rounded())) } ?? fullWidth
            let planeH = scale.map { max(1, Int((CGFloat(fullHeight) * $0).rounded())) } ?? fullHeight

            watermark.jointContext = WatermarkModule.JointContext(
                mainImageSize: SIMD2(planeW, planeH), bordersParams: bordersParams
            )
            if let bordersBox = instances.first(where: {
                $0.opName == BordersModule.opName
            }) as? ModuleBox<BordersModule> {
                bordersBox.module.jointLayoutOverride = watermark.makeJointLayoutRecord(
                    mainImageSize: SIMD2(planeW, planeH), bordersParams: bordersParams
                )
            }
        }
    }

    /// The pipeline output → 8-bit RGBA sRGB CGImage.
    ///
    /// TWO source regimes (09-3 T7 spot-check finding — the FIRST cut read
    /// EVERYTHING as linear Rec2020 and swapped R/B on display-ready
    /// planes; the archive at .work/gui-acceptance/09-3-* shows the green-
    /// to-cyan corpse):
    ///   • `.bgra8Unorm` — the gamma tail's DISPLAY-READY plane (gamut+TRC
    ///     already in-pipe; the editor blit treats it the same way). The
    ///     conversion is a passthrough: the CIImage reads as sRGB (no
    ///     colorspace re-stamp) and the render is byte-faithful.
    ///   • float32 linear Rec2020 — the LEGACY/intermediate plane (no gamma
    ///     tail ran; e.g. an instances-free chain). The conversion is a REAL
    ///     Rec2020-linear → sRGB match (the CI leg performs gamut + TRC).
    /// L014: the empty-command-buffer fence FIRST (getBytes/CI reads must
    /// not race the in-flight encoders).
    static func cgImage(from texture: any MTLTexture, metal: MetalContext) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        guard width >= 1, height >= 1 else {
            throw AppError.decodeFailed("thumb convert: degenerate texture")
        }
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()

        let displayReady = texture.pixelFormat == .bgra8Unorm
        let ciOptions: [CIImageOption: Any] = displayReady
            ? [:] // display-ready bytes — as-emitted (the editor-blit posture)
            : [.colorSpace: WorkingSpace.colorSpace] // linear Rec2020 truth
        guard let ciImage = CIImage(mtlTexture: texture, options: ciOptions) else {
            throw AppError.decodeFailed("thumb convert: CIImage(mtlTexture:) failed")
        }
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)
        bitmap.withUnsafeMutableBytes { raw in
            context.render(
                ciImage,
                toBitmap: raw.baseAddress!,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        }
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bitmap) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .perceptual
        ) else {
            throw AppError.decodeFailed("thumb convert: CGImage build failed")
        }
        return image
    }
}
