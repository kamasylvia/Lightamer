import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// The module-boundary verification (RESEARCH §9 / D-02): everything the
/// app and IOP legitimately reach is `public` and resolves through plain
/// `import`; everything else is `internal` and INVISIBLE from this file.
final class ModuleBoundaryTests: XCTestCase {

    /// The entire documented public surface instantiates / resolves from a
    /// bare `import LightamerCore` + `import LightamerIOP`. This test is the
    /// executable mirror of `LightamerCore/API.md` (D-03c): a type listed
    /// there must compile here; a `public` type removed from Core must fail
    /// HERE first (RESEARCH §9d — loud, immediate boundary signal).
    func testCorePublicSurfaceAccessible() throws {
        // Decode
        let decoder = RAWDecoder()
        _ = decoder
        let decoded = DecodedImage(
            ciImage: CIImage(color: .gray),
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(cameraModel: "boundary-test"),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
        XCTAssertEqual(decoded.capture.cameraModel, "boundary-test")
        XCTAssertEqual(decoded.decoderVersionUsed, .v8)
        _ = RAWTechnicalParams().whiteLevel
        _ = CaptureMetadata.GPSInfo()

        // Metal (GPU-guarded — context init needs a device)
        if MTLCreateSystemDefaultDevice() != nil {
            let metal = try MetalContext()
            XCTAssertNotNil(metal.device)
            XCTAssertNotNil(metal.commandQueue)
        }
        _ = MetalError.deviceUnavailable.localizedDescription

        // Pipe
        _ = PassthroughModule.flags
        _ = IOPFlags.allowTiling
        _ = IOPColorspace.RGB
        var piece = IOPiece()
        piece.paramsHash = 7
        _ = IOPBufferDesc(width: 1, height: 1)
        _ = ROI(x: 0, y: 0, width: 2, height: 2)

        // Layers (D-03a)
        let stack = LayerStack(baseLayer: BackgroundLayer())
        XCTAssertEqual(stack.baseLayer.kind, .background)
        _ = BlendMode.normal
        _ = LayerKind.adjustment

        // Foundation
        XCTAssertFalse(V50Order.entries.isEmpty)
        _ = WorkingSpace.pixelFormat
        _ = AppError.cancelled.errorDescription ?? "nil-by-contract"

        // Core render bridge (public face of the internal PixelPipe)
        _ = RenderPipeline.self
    }

    /// The NEGATIVE half of the boundary: `internal` Core symbols are not
    /// referenceable from this target. This cannot be asserted positively
    /// in Swift (a bad reference is a compile error, not a runtime one), so
    /// it is enforced two ways:
    ///
    /// 1. **This file compiles while referencing ONLY `public` symbols** —
    ///    any `internal` leak into these tests would break the build.
    /// 2. **Executor-verified negative compile check** (done in this plan,
    ///    recorded verbatim): temporarily appending
    ///    `let _ = PSOKey(name: "x", constantsFingerprint: "y")` to this
    ///    file made `xcodebuild build` fail with
    ///    `error: cannot find 'PSOKey' in scope`
    ///    (Tests/LightamerTests/ModuleBoundaryTests.swift) — the internal
    ///    cache key is invisible across the module boundary, exactly the
    ///    D-02/RESEARCH §9a guarantee. The reference was then removed.
    ///    Renaming `PSOKey` (or any other internal) still compiles IOP,
    ///    the app, and these tests — zero blast radius.
    func testInternalSymbolsNotAccessible() {
        // The compile proof lives in the doc comment above; this body
        // asserts the positive corollary so the method is not vacuous:
        // the PUBLIC cache-adjacent surface stays reachable.
        let metal = MTLCreateSystemDefaultDevice()
        if metal != nil {
            XCTAssertNoThrow(try MetalContext())
        }
        // `psoCache`, `PSOKey`, `CIContextPool`, `MetalContextMarker`,
        // `PixelPipe`, `RAWDecoder.decodeRAW` … are NOT named here — doing
        // so must fail the build (verified, see above).
    }
}
