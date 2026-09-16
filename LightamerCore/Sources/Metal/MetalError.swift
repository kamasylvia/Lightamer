import Foundation

/// Typed Metal-layer errors (D-18: Swift `throws` with typed errors; call
/// sites catch and bridge through `AppError` at the UI boundary).
///
/// `public` (cross-module contract): iops in LightamerIOP and the app's render
/// path both throw/catch through this enum. `AppError` carries the semantic
/// user-facing copy (`.metalDeviceUnavailable` / `.metalPSOFailed` /
/// `.memoryExceeded`); `asAppError` performs the tiered mapping.
public enum MetalError: Error, LocalizedError {

    /// `MTLCreateSystemDefaultDevice()` / `makeCommandQueue()` returned nil —
    /// no Metal GPU (or queue allocation failed).
    case deviceUnavailable

    /// No registered metallib contains the named function.
    case functionNotFound(String)

    /// `MTLComputePipelineState` creation failed; carries the function name
    /// and the underlying error when available (e.g. function-constant
    /// mismatch — `makeFunction(name:constantValues:)` requires ALL declared
    /// constants to be set, RESEARCH §3 gotcha).
    case psoCreationFailed(String, Error?)

    /// A buffer/texture allocation returned nil; carries the requested size
    /// in bytes.
    case bufferAllocationFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "No Metal device is available."
        case let .functionNotFound(name):
            return "Metal function not found: \(name)."
        case let .psoCreationFailed(name, underlying):
            return "Failed to create pipeline state for \(name)"
                + (underlying.map { ": \($0.localizedDescription)" } ?? ".")
        case let .bufferAllocationFailed(bytes):
            return "Failed to allocate Metal buffer (\(bytes) bytes)."
        }
    }

    /// Map into the user-facing typed enum (D-25). Internal — the bridge is a
    /// Core implementation detail; the app only ever sees `AppError`.
    internal var asAppError: AppError {
        switch self {
        case .deviceUnavailable:
            return .metalDeviceUnavailable
        case let .functionNotFound(name):
            return .metalPSOFailed(name, errorDescription)
        case let .psoCreationFailed(name, underlying):
            return .metalPSOFailed(name, underlying?.localizedDescription)
        case let .bufferAllocationFailed(bytes):
            return .memoryExceeded(bytes)
        }
    }
}
