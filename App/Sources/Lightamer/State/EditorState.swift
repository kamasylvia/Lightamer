import Foundation
import LightamerCore
import Metal
import Observation
import os

/// Editor-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the currently edited image (URL + `DecodedImage`), the
/// decode/error lifecycle, and the in-flight decode task. Does NOT own the
/// export queue or inspector selection, and holds no references to the other
/// state objects.
@Observable
@MainActor
final class EditorState {

    /// Shared decode-path logger + signpost subsystem/category (D-27/D-31);
    /// passed into `load` so callers own the logging identity.
    nonisolated static let decodeLogger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "decode"
    )

    /// URL of the currently loaded image (nil = empty state, D-11).
    private(set) var loadedImageURL: URL?

    /// The decoded image — RAWDecoder output (D-21). Plan 03's
    /// `EditorMTKView` consumes `image?.ciImage` via `MetalContext`.
    private(set) var image: DecodedImage?

    /// The layer stack for the loaded image (D-03a skeleton — D-03b places
    /// ownership here). Constructed fresh on every successful decode with
    /// a `BackgroundLayer` base (LAYER-01); adjustment layers arrive in
    /// Phase 6. nil = no image loaded.
    private(set) var layerStack: LayerStack?

    /// The pixelpipe output — what `EditorMTKView` blits to the drawable.
    /// Produced by Core's render bridge (`RenderPipeline.render`, the
    /// public face of the internal `PixelPipe`). Cleared on every new load.
    /// The setter is deliberately internal (not `private(set)`): the
    /// `$editorState.displayTexture` binding that `EditorAreaView` derives
    /// via `@Bindable` needs it; the pixelpipe paths are the only writers.
    var displayTexture: (any MTLTexture)?

    /// Guards the render step: the URL whose texture `displayTexture` holds.
    private var displayTextureRenderedForURL: URL?

    /// True while a decode task is in flight (status bar "Decoding…").
    private(set) var isDecoding: Bool = false

    /// Last decode failure, surfaced as a blocking alert (D-26).
    private(set) var decodeError: AppError?

    /// The in-flight decode task; cancelled when a newer load supersedes it
    /// (D-34: background async decode, cancellable, MainActor UI updates).
    private var decodeTask: Task<Void, Never>?

    /// Load an image/RAW file through `RAWDecoder` (D-21/D-24) and run the
    /// no-op pixelpipe over the result (success criterion #3). Cancels any
    /// in-flight decode first (D-34). The decode runs off-MainActor
    /// (`RAWDecoder` is an actor); on success a fresh
    /// `LayerStack(baseLayer: BackgroundLayer())` is installed (D-03a) and
    /// Core's render bridge produces the display texture. Failures land in
    /// `decodeError` as typed `AppError`s (D-25); pixelpipe failures are
    /// non-blocking (logged only — same severity as the Plan 03 render
    /// leg). The decode leg is wrapped in an `os.signpost` interval (D-31);
    /// the pixelpipe leg is signposted inside `RenderPipeline` itself.
    /// `metal` nil = no GPU — decode still succeeds, display stays empty
    /// (the fatal no-GPU alert is hosted by `ContentView`).
    func load(url: URL, decoder: RAWDecoder, metal: MetalContext?, logger: Logger) {
        decodeTask?.cancel()
        loadedImageURL = url
        decodeError = nil
        isDecoding = true
        // Drop the previous image's viewport texture + layer stack so the
        // editor never shows a stale frame while the new decode runs.
        displayTexture = nil
        layerStack = nil
        displayTextureRenderedForURL = nil

        decodeTask = Task { [weak self] in
            guard let self else { return }
            let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer", category: "decode")
            let interval = signposter.beginInterval("decode", id: signposter.makeSignpostID())
            defer {
                signposter.endInterval("decode", interval)
                self.isDecoding = false
            }

            do {
                let decoded = try await decoder.decode(url) // off-MainActor
                guard !Task.isCancelled else { // a newer load superseded this one
                    logger.info("decode superseded: \(url.lastPathComponent, privacy: .public)")
                    return
                }
                self.image = decoded
                let camera = decoded.capture.cameraModel ?? "-"
                logger.info(
                    "decoded \(url.lastPathComponent, privacy: .public) v\(decoded.decoderVersionUsed.rawValue, privacy: .public)"
                )
                logger.info(
                    "camera=\(camera, privacy: .public) blackLevel=\(decoded.rawTech.blackLevel, privacy: .public)"
                )

                // D-03a: every decoded image gets a fresh layer stack —
                // base layer only in Phase 1 (adjustment layers: Phase 6).
                let stack = LayerStack(baseLayer: BackgroundLayer())
                self.layerStack = stack

                // The no-op pixelpipe (success criterion #3): the decoded
                // image flows through Core's internal `PixelPipe` (which
                // now holds the layer stack) and lands as the display
                // texture `EditorMTKView` blits.
                if let metal {
                    let texture = try await RenderPipeline.render(
                        image: decoded,
                        layerStack: stack,
                        metal: metal
                    )
                    guard !Task.isCancelled else { // superseded mid-pipe
                        logger.info("pixelpipe superseded: \(url.lastPathComponent, privacy: .public)")
                        return
                    }
                    self.displayTexture = texture
                    self.displayTextureRenderedForURL = url
                    logger.info(
                        "pixelpipe output ready: \(url.lastPathComponent, privacy: .public)"
                    )
                }
            } catch {
                let appError = AppError(error) // D-25 bridge
                if case .cancelled = appError {
                    logger.info("decode cancelled: \(url.lastPathComponent, privacy: .public)")
                } else {
                    logger.error(
                        "pixelpipe/decode failed (\(url.lastPathComponent, privacy: .public)): \(appError.localizedDescription, privacy: .public)"
                    )
                    self.decodeError = appError
                }
            }
        }
    }

    /// Re-render the decoded `image` through the no-op pixelpipe via Core's
    /// `RenderPipeline` bridge. Idempotent per loaded URL — `load` already
    /// renders on the success path, so this is the URL-keyed `.task`
    /// fallback in `EditorAreaView` (no-op once `load`'s render landed).
    /// Failures are non-blocking (UI-SPEC severity table: render issues
    /// log; they don't clear the decode state).
    func renderDisplayTexture(using metal: MetalContext) async {
        guard let image, let url = loadedImageURL else { return }
        if displayTexture != nil, displayTextureRenderedForURL == url { return }
        displayTextureRenderedForURL = url
        do {
            displayTexture = try await RenderPipeline.render(
                image: image,
                layerStack: layerStack,
                metal: metal
            )
            Self.decodeLogger.info(
                "display texture ready: \(url.lastPathComponent, privacy: .public)"
            )
        } catch {
            Self.decodeLogger.error(
                "display render failed (\(url.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Dismiss the blocking decode-error alert (D-26 skeleton).
    func clearError() {
        decodeError = nil
    }
}
