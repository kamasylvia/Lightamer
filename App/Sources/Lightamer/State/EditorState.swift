import Foundation
import LightamerCore
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

    /// True while a decode task is in flight (status bar "Decoding…").
    private(set) var isDecoding: Bool = false

    /// Last decode failure, surfaced as a blocking alert (D-26).
    private(set) var decodeError: AppError?

    /// The in-flight decode task; cancelled when a newer load supersedes it
    /// (D-34: background async decode, cancellable, MainActor UI updates).
    private var decodeTask: Task<Void, Never>?

    /// Load an image/RAW file through `RAWDecoder` (D-21/D-24). Cancels any
    /// in-flight decode first (D-34). The decode itself runs off-MainActor
    /// (`RAWDecoder` is an actor); state mutations below hop back implicitly
    /// because this `Task` inherits the `@MainActor` context. Failures land
    /// in `decodeError` as typed `AppError`s (D-25). The whole decode is
    /// wrapped in an `os.signpost` interval for Instruments (D-31).
    func load(url: URL, decoder: RAWDecoder, logger: Logger) {
        decodeTask?.cancel()
        loadedImageURL = url
        decodeError = nil
        isDecoding = true

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
            } catch {
                let appError = AppError(error) // D-25 bridge
                if case .cancelled = appError {
                    logger.info("decode cancelled: \(url.lastPathComponent, privacy: .public)")
                } else {
                    logger.error(
                        "decode failed (\(url.lastPathComponent, privacy: .public)): \(appError.localizedDescription, privacy: .public)"
                    )
                    self.decodeError = appError
                }
            }
        }
    }

    /// Dismiss the blocking decode-error alert (D-26 skeleton).
    func clearError() {
        decodeError = nil
    }
}
