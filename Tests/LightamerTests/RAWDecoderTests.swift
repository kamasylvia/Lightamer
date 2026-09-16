import LightamerCore
import XCTest

/// RAWDecoder decode tests (D-21) — Wave 0 stubs staged in Plan 02.
///
/// Plan 06 replaces every stub body with real assertions against the
/// `Resources/TestFixtures/` samples (RAW bodies additionally need the real
/// camera fixtures staged there — see the fixtures README). The stubs exist
/// so the test target compiles and the test inventory is fixed now; they
/// skip rather than assert, so a green run here means nothing yet.
final class RAWDecoderTests: XCTestCase {

    /// RAW-01 — Canon CR3 decodes via the CIRAW path.
    func testDecodeCR3() throws {
        // Plan 06: real camera fixture pending in Resources/TestFixtures.
        throw XCTSkip("Plan 06: CR3 fixture not staged yet")
    }

    /// RAW-01 — Nikon NEF decodes via the CIRAW path.
    func testDecodeNEF() throws {
        // Plan 06: real camera fixture pending in Resources/TestFixtures.
        throw XCTSkip("Plan 06: NEF fixture not staged yet")
    }

    /// RAW-01 — Sony ARW decodes via the CIRAW path.
    func testDecodeARW() throws {
        // Plan 06: real camera fixture pending in Resources/TestFixtures.
        throw XCTSkip("Plan 06: ARW fixture not staged yet")
    }

    /// RAW-01 — Fujifilm RAF (X-Trans) decodes via the CIRAW path.
    func testDecodeRAF() throws {
        // Plan 06: real camera fixture pending in Resources/TestFixtures.
        throw XCTSkip("Plan 06: RAF fixture not staged yet")
    }

    /// RAW-02 — Adobe DNG decodes via the CIRAW path.
    func testDecodeDNG() throws {
        // Plan 06: DNG fixture pending in Resources/TestFixtures.
        throw XCTSkip("Plan 06: DNG fixture not staged yet")
    }

    /// RAW-04 — raster formats route through the CGImageSource path.
    func testDecodeRaster_JPEG_HEIC_PNG_WebP_TIFF() throws {
        // Plan 06: asserts sample-gradient.{jpg,heic,png,tiff} + a WebP
        // sample produce a DecodedImage with empty RAWTechnicalParams.
        throw XCTSkip("Plan 06: assertions pending")
    }

    /// RAW-05 / D-22 / L001 — RAW 9 opt-in when the file supports it,
    /// silent `.version8` fallback otherwise; `decoderVersionUsed` stamped.
    func testRAW9OptInAndFallback() throws {
        // Plan 06: requires a RAW-9-supported camera sample on macOS 27.
        if #available(macOS 27, *) {
            throw XCTSkip("Plan 06: RAW 9 fixture pending")
        } else {
            throw XCTSkip("RAW 9 requires macOS 27 (L001)")
        }
    }

    /// RAW-06 — EXIF/IPTC/GPS metadata extraction (camera/lens/focal/
    /// aperture/shutter/ISO/GPS/time).
    func testMetadataExtraction() throws {
        // Plan 06: needs an EXIF-bearing fixture.
        throw XCTSkip("Plan 06: EXIF fixture pending")
    }

    /// D-25 — corrupt/truncated RAW fails with a typed AppError, not a crash.
    func testCorruptRAWThrowsTypedError() throws {
        // Plan 06: feeds a truncated RAW and asserts AppError.decodeFailed.
        throw XCTSkip("Plan 06: assertions pending")
    }

    /// D-34 — Task.cancel() aborts an in-flight decode.
    func testDecodeIsCancellable() throws {
        // Plan 06: starts a decode, cancels, asserts AppError.cancelled /
        // CancellationError.
        throw XCTSkip("Plan 06: assertions pending")
    }
}
