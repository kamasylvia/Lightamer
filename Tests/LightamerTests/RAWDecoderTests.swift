import LightamerCore
import XCTest

/// RAWDecoder decode tests (D-21) — real assertions against the Plan 05
/// CC0 camera samples (RAW) and the bundled gradient rasters (RAW-04).
///
/// RAW samples resolve from the untracked `.work/01-05/samples/` checkout
/// (see `Fixtures.swift` for the two-tier fixture strategy); tests skip
/// with a documented reason on machines without the download. All
/// assertions go through the `public` surface (`import LightamerCore`,
/// no `@testable`).
final class RAWDecoderTests: XCTestCase {

    // MARK: - RAW-01 (proprietary RAW decode)

    /// RAW-01 — Canon CR3 decodes via the CIRAW path.
    func testDecodeCR3() async throws {
        try Fixtures.require(Fixtures.cr3)
        let decoded = try await RAWDecoder().decode(Fixtures.cr3)
        XCTAssertNotNil(decoded.ciImage)
        XCTAssertGreaterThan(decoded.ciImage.extent.width, 0)
        XCTAssertGreaterThan(decoded.ciImage.extent.height, 0)
    }

    /// RAW-01 — Nikon NEF decodes via the CIRAW path.
    func testDecodeNEF() async throws {
        try Fixtures.require(Fixtures.nef)
        let decoded = try await RAWDecoder().decode(Fixtures.nef)
        XCTAssertNotNil(decoded.ciImage)
        XCTAssertGreaterThan(decoded.ciImage.extent.width, 0)
    }

    /// RAW-01 — Sony ARW decodes via the CIRAW path.
    func testDecodeARW() async throws {
        try Fixtures.require(Fixtures.arw)
        let decoded = try await RAWDecoder().decode(Fixtures.arw)
        XCTAssertNotNil(decoded.ciImage)
        XCTAssertGreaterThan(decoded.ciImage.extent.width, 0)
    }

    /// RAW-01 — Fujifilm RAF (X-Trans) decodes via the CIRAW path.
    func testDecodeRAF() async throws {
        try Fixtures.require(Fixtures.raf)
        let decoded = try await RAWDecoder().decode(Fixtures.raf)
        XCTAssertNotNil(decoded.ciImage)
        XCTAssertGreaterThan(decoded.ciImage.extent.width, 0)
    }

    // MARK: - RAW-02 (DNG)

    /// RAW-02 — Adobe DNG decodes via the CIRAW path (Apple's universal
    /// fallback — "just works" per RESEARCH §2).
    func testDecodeDNG() async throws {
        try Fixtures.require(Fixtures.dng)
        let decoded = try await RAWDecoder().decode(Fixtures.dng)
        XCTAssertNotNil(decoded.ciImage)
        XCTAssertGreaterThan(decoded.ciImage.extent.width, 0)
    }

    // MARK: - RAW-04 (raster path)

    /// RAW-04 — raster formats route through the CGImageSource path. The
    /// discriminators: rasters carry NO RAW technical state (defaults:
    /// blackLevel 0, whiteLevel 1) and are stamped `.v8` (field non-optional,
    /// "n/a for raster" per `DecodedImage`). WebP has no fixture in this
    /// phase (the Wave 0 fixture list excludes it; WebP decode is native
    /// since macOS 11 and rides the exact same raster path).
    func testDecodeRaster_JPEG_HEIC_PNG_WebP_TIFF() async throws {
        let cases: [(String, String)] = [
            ("sample-gradient", "jpg"),
            ("sample-gradient", "heic"),
            ("sample-gradient", "png"),
            ("sample-gradient", "tiff"),
        ]
        let decoder = RAWDecoder()
        for (name, ext) in cases {
            let url = try Fixtures.raster(name, ext)
            let decoded = try await decoder.decode(url)
            XCTAssertNotNil(decoded.ciImage, "\(ext) produced no image")
            XCTAssertGreaterThan(decoded.ciImage.extent.width, 0, "\(ext) empty extent")
            // Raster discriminators (D-24: one entry point, no RAW state).
            XCTAssertEqual(decoded.rawTech.blackLevel, 0.0, "\(ext) must carry no RAW blackLevel")
            XCTAssertEqual(decoded.rawTech.whiteLevel, 1.0, "\(ext) must carry no RAW whiteLevel")
            XCTAssertEqual(decoded.decoderVersionUsed, .v8, "raster stamps .v8 (n/a)")
            XCTAssertNil(decoded.segmentationSkyMatte)
        }
    }

    // MARK: - RAW-05 / D-22 / L001 (RAW 9 opt-in + silent fallback)

    /// RAW-05 — RAW 9 opt-in: the A7R V sample reports `version9` at GM
    /// (Spike B measured `.v9` on this exact file), and `RAWDecoder` requests
    /// it by default (D-22), so `decoderVersionUsed == .v9`.
    func testRAW9OptIn() async throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("RAW 9 requires macOS 27 (L001)")
        }
        try Fixtures.require(Fixtures.arw)
        let decoded = try await RAWDecoder().decode(Fixtures.arw)
        XCTAssertEqual(
            decoded.decoderVersionUsed, .v9,
            "RAW-9-capable file must decode under v9 (D-22 default opt-in)"
        )
    }

    /// RAW-05 — silent `.version8` fallback: the Z8 is NOT in the macOS
    /// 27.0 GM v9 camera list (Spike A `models.txt`), and setting v9 on an
    /// unsupported file silently clamps instead of throwing (Spike A #8) —
    /// so `decoderVersionUsed` must come back `.v8`.
    ///
    /// Version-pinned expectation: Apple expands the v9 list across the
    /// macOS 27 lifecycle. If a later SDK/OTA adds the Z8, this assertion
    /// legitimately flips to `.v9` — update fixture + comment then.
    func testRAW9FallbackForUnsupportedCamera() async throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("RAW 9 probe requires macOS 27 (L001)")
        }
        try Fixtures.require(Fixtures.nef)
        let decoded = try await RAWDecoder().decode(Fixtures.nef)
        XCTAssertEqual(
            decoded.decoderVersionUsed, .v8,
            "Z8 not in GM v9 list (Spike A) — expect the silent v8 fallback"
        )
    }

    // MARK: - RAW-06 (metadata extraction — deep coverage in MetadataTests)

    /// RAW-06 — CR3 + NEF expose camera/lens/exposure capture metadata.
    func testMetadataExtraction() async throws {
        try Fixtures.require(Fixtures.cr3)
        try Fixtures.require(Fixtures.nef)
        let decoder = RAWDecoder()

        for url in [Fixtures.cr3, Fixtures.nef] {
            let decoded = try await decoder.decode(url)
            let capture = decoded.capture
            XCTAssertNotNil(capture.cameraModel, "\(url.pathExtension): camera model")
            XCTAssertNotNil(capture.lensModel, "\(url.pathExtension): lens model")
            XCTAssertGreaterThan(capture.focalLength ?? 0, 0, "\(url.pathExtension): focal length")
            XCTAssertGreaterThan(capture.aperture ?? 0, 0, "\(url.pathExtension): aperture")
            XCTAssertGreaterThan(capture.shutterSpeed ?? 0, 0, "\(url.pathExtension): shutter")
            XCTAssertGreaterThan(capture.iso ?? 0, 0, "\(url.pathExtension): ISO")
            XCTAssertNotNil(capture.captureTime, "\(url.pathExtension): capture time")
            XCTAssertGreaterThan(capture.width ?? 0, 0)
            XCTAssertGreaterThan(capture.height ?? 0, 0)
        }
    }

    // MARK: - D-25 (typed error on corrupt input)

    /// D-25 — a truncated RAW fails with a typed `AppError`
    /// (`.decodeFailed` / `.fileUnreadable` / `.unsupportedFile`), never a
    /// crash.
    func testCorruptRAWThrowsTypedError() async throws {
        try Fixtures.require(Fixtures.cr3)
        let truncated = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightamer-corrupt-\(UUID().uuidString).CR3")
        let head = try Data(contentsOf: Fixtures.cr3, options: .alwaysMapped).prefix(100)
        try Data(head).write(to: truncated)
        defer { try? FileManager.default.removeItem(at: truncated) }

        do {
            _ = try await RAWDecoder().decode(truncated)
            XCTFail("truncated CR3 must throw")
        } catch let error as AppError {
            switch error {
            case .decodeFailed, .fileUnreadable, .unsupportedFile:
                break // the documented typed failure modes
            default:
                XCTFail("unexpected AppError case: \(error)")
            }
        } catch {
            XCTFail("non-typed error escaped the decode layer: \(error)")
        }
    }

    // MARK: - D-34 (cancellation)

    /// D-34 — a pre-cancelled decode throws `AppError.cancelled`
    /// deterministically (the first `checkCancellation` checkpoint); a
    /// mid-flight cancellation settles (typed `.cancelled` OR completes)
    /// without crashing.
    func testDecodeIsCancellable() async throws {
        guard let url = [Fixtures.nef, Fixtures.arw, Fixtures.cr3]
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else {
            throw XCTSkip("no RAW fixture downloaded (Plan 05 samples)")
        }
        let decoder = RAWDecoder()

        // Deterministic path: cancel BEFORE the decode starts.
        let task = Task { try await decoder.decode(url) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("pre-cancelled decode must throw")
        } catch let error as AppError {
            guard case .cancelled = error else {
                return XCTFail("expected AppError.cancelled, got \(error)")
            } // decode layer rethrows typed cancellation
        } catch is CancellationError {
            // also acceptable at the Task layer
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        // Mid-flight path: cancel a big decode while running; the task must
        // settle (typed cancellation OR a completed decode) without crashing
        // — the outcome depends on where the checkpoint lands.
        try Fixtures.require(Fixtures.arw)
        let mid = Task { try await decoder.decode(Fixtures.arw) }
        try await Task.sleep(for: .milliseconds(50))
        mid.cancel()
        do {
            let decoded = try await mid.value
            XCTAssertNotNil(decoded.ciImage) // checkpoint landed post-decode
        } catch let error as AppError {
            guard case .cancelled = error else {
                return XCTFail("expected AppError.cancelled, got \(error)")
            } // checkpoint landed mid-decode
        } catch is CancellationError {
            // Task-layer cancellation
        }
    }
}
