import Foundation
import LightamerCore
import Observation
import os

/// Editor-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the currently edited image's URL, the decode/error lifecycle,
/// and the in-flight decode task. Does NOT own the export queue or inspector
/// selection, and holds no references to the other state objects.
///
/// The `DecodedImage` / layer-stack properties arrive in Plans 02/04 — Plan 01
/// carries the URL + decode/error state that drives the empty-state switch.
@Observable
@MainActor
final class EditorState {

    /// URL of the currently loaded image (nil = empty state, D-11).
    private(set) var loadedImageURL: URL?

    /// True while a decode task is in flight (status bar "Decoding…").
    private(set) var isDecoding: Bool = false

    /// Last decode failure, surfaced as a blocking alert (D-26).
    private(set) var decodeError: AppError?

    /// The in-flight decode task; cancelled when a newer load supersedes it
    /// (D-34: background async decode, cancellable, MainActor UI updates).
    private var decodeTask: Task<Void, Never>?

    /// Load an image/RAW file. Cancels any in-flight decode first (D-34).
    ///
    /// Plan 01 stub: the actual decode is a no-op — Plan 02 replaces the
    /// marked section with `RAWDecoder.decode(url)` (which runs off the
    /// MainActor) and Plan 04 attaches the layer stack. The cancellation
    /// check keeps the D-34 contract honest even for the stub.
    func load(url: URL) {
        decodeTask?.cancel()
        decodeError = nil
        isDecoding = true
        decodeTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }

            // ── Plan 02 integration point ────────────────────────────────
            // let decoded = try await RAWDecoder().decode(url)
            // self.finishLoad(url: url, decoded: decoded)
            // ─────────────────────────────────────────────────────────────
            self.loadedImageURL = url
            self.isDecoding = false
        }
    }

    /// Dismiss the blocking decode-error alert (D-26 skeleton).
    func clearError() {
        decodeError = nil
    }
}
