import LightamerCore
import XCTest

/// D-25 coverage — the `AppError` typed-error contract: the foreign-error
/// bridge (`init(_ error: Error)`), `LocalizedError` copy, and the
/// cancellation mapping (D-34). `public` surface only.
final class AppErrorTests: XCTestCase {

    /// The bridge maps `CancellationError` → `.cancelled` (D-34 contract).
    func testCancellationErrorBridgesToCancelled() {
        let bridged = AppError(CancellationError())
        guard case .cancelled = bridged else {
            return XCTFail("expected .cancelled, got \(bridged)")
        }
    }

    /// The bridge passes an already-typed `AppError` through unchanged —
    /// double-bridging never re-wraps into `.decodeFailed`.
    func testAppErrorPassesThroughUnchanged() {
        let original = AppError.fileUnreadable("/tmp/no-such-file")
        let bridged = AppError(original)
        guard case .fileUnreadable = bridged else {
            return XCTFail("expected .fileUnreadable pass-through, got \(bridged)")
        }
    }

    /// The bridge maps `MetalError.deviceUnavailable` →
    /// `.metalDeviceUnavailable` (the tiered Metal → AppError mapping; the
    /// render facade performs the same mapping internally via
    /// `MetalError.asAppError`).
    func testMetalDeviceUnavailableBridgesToTypedCase() {
        let bridged = AppError(MetalError.deviceUnavailable)
        guard case .metalDeviceUnavailable = bridged else {
            return XCTFail("expected .metalDeviceUnavailable, got \(bridged)")
        }
    }

    /// `MetalError.psoCreationFailed` maps to `.metalPSOFailed` carrying the
    /// function name; `bufferAllocationFailed` maps to `.memoryExceeded`.
    func testOtherMetalErrorsMapTiered() {
        let pso = AppError(MetalError.psoCreationFailed("pass_through", nil))
        guard case let .metalPSOFailed(name, _) = pso, name == "pass_through" else {
            return XCTFail("expected .metalPSOFailed(pass_through), got \(pso)")
        }

        let alloc = AppError(MetalError.bufferAllocationFailed(1024))
        guard case let .memoryExceeded(bytes) = alloc, bytes == 1024 else {
            return XCTFail("expected .memoryExceeded(1024), got \(alloc)")
        }
    }

    /// Any other foreign error lands in `.decodeFailed` with the underlying
    /// localized description (the catch-all of the D-25 tiering).
    func testUnknownErrorBridgesToDecodeFailed() {
        struct Weird: Error {}
        let bridged = AppError(Weird())
        guard case .decodeFailed = bridged else {
            return XCTFail("expected .decodeFailed, got \(bridged)")
        }
    }

    /// `LocalizedError` copy is non-empty for every user-facing case. The
    /// documented exception: `.cancelled` returns nil BY CONTRACT (silent —
    /// cancellation is not a user-facing failure, UI-SPEC "Error Messages").
    func testLocalizedDescriptionsNonEmpty() {
        let cases: [AppError] = [
            .unsupportedFile("/tmp/x.xyz"),
            .decodeFailed("underlying blew up"),
            .metalDeviceUnavailable,
            .metalPSOFailed("pass_through", nil),
            .memoryExceeded(2048),
            .fileUnreadable("/tmp/locked.raw"),
        ]
        for error in cases {
            let copy = error.errorDescription
            XCTAssertNotNil(copy, "\(error): user-facing cases carry copy")
            XCTAssertFalse(copy?.isEmpty ?? true, "\(error): copy non-empty")
        }
        XCTAssertNil(
            AppError.cancelled.errorDescription,
            ".cancelled is silent by contract (UI-SPEC tiering)"
        )
    }
}
