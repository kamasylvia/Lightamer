import Foundation
import os

/// The unified, typed error enum for every Lightamer layer (D-25, cross-module
/// contract — `public` in LightamerCore so IOP, the app, and tests all throw
/// and catch through the same type).
///
/// Tiering follows UI-SPEC "Error Messages": `.cancelled` is silent (log only);
/// decode/file failures surface as blocking alerts; Metal/PSO failures as
/// non-blocking alerts.
public enum AppError: Error, LocalizedError {

    /// The file's UTI is not an openable image/RAW format.
    case unsupportedFile(String)

    /// Decode (CIRAW / CGImageSource) failed; carries the underlying message.
    case decodeFailed(String)

    /// `MTLCreateSystemDefaultDevice()` returned nil — no Metal GPU.
    case metalDeviceUnavailable

    /// A Metal function/PSO could not be created; carries the function name
    /// and the underlying error description when available.
    case metalPSOFailed(String, String?)

    /// A texture/buffer allocation exceeded the memory budget (bytes).
    case memoryExceeded(Int)

    /// The user (or a newer request) cancelled the operation (D-34).
    case cancelled

    /// The file exists but cannot be opened/read (permissions, truncated, …).
    case fileUnreadable(String)

    /// Bridge a foreign `Error` into the typed enum (D-18/D-25: layers throw
    /// typed errors; this is the catch-site bridge Plan 02/03 throw through).
    /// - `CancellationError` → `.cancelled`
    /// - an already-typed `AppError` → passed through unchanged
    /// - a `MetalError` → its tiered case (`.metalDeviceUnavailable` /
    ///   `.metalPSOFailed` / `.memoryExceeded` — the same mapping the
    ///   `MetalContext.renderToTexture` facade performs internally)
    /// - anything else → `.decodeFailed(underlying.localizedDescription)`
    public init(_ error: Error) {
        if let appError = error as? AppError {
            self = appError
        } else if let metalError = error as? MetalError {
            self = metalError.asAppError
        } else if error is CancellationError {
            self = .cancelled
        } else {
            self = .decodeFailed(error.localizedDescription)
        }
    }

    /// Human-readable copy per UI-SPEC "Error Messages" (en source; the app
    /// layer routes these through the String Catalog at the UI boundary).
    public var errorDescription: String? {
        switch self {
        case let .unsupportedFile(path):
            return "Lightamer can't open this file format. (\(path))"
        case let .decodeFailed(underlying):
            return "Failed to decode. \(underlying) The file may be corrupted."
        case .metalDeviceUnavailable:
            return "No Metal GPU is available. Lightamer requires Apple Silicon or a Metal-capable GPU."
        case let .metalPSOFailed(functionName, underlying):
            return "A graphics operation failed to initialize (\(functionName))"
                + (underlying.map { ": \($0)" } ?? ".")
                + " Try reopening the image."
        case let .memoryExceeded(bytes):
            return "This image exceeds the memory budget (\(bytes) bytes). Try a smaller file or close other apps."
        case .cancelled:
            // Silent by contract — cancellation is not a user-facing failure.
            return nil
        case let .fileUnreadable(path):
            return "Lightamer can't read the file at “\(path)”."
        }
    }

    /// Shared logger (D-27 os.Logger; Console.app filterable by category).
    public static let logger = Logger(subsystem: "com.kamasylvia.lightamer", category: "error")
}
