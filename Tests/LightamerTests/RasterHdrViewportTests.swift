import AppKit
import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import MetalKit
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// RasterHdrViewportTests (Plan M4-1-02 T4, KD-5 — APP bundle, the
// DrtViewportTests assertion form) — the HDR raster's DRT-HDR viewport arm
// through the REAL decode → derive → surface chain:
//
//   • a PQ fixture decodes → the derive record rides (rec2020, st2084) →
//     the DRT-HDR surface arm (16F drawable + EDR + the itur_2100_PQ
//     colorspace) — zero NEW rendering code (the M2-6 face);
//   • HLG likewise (itur_2100_HLG);
//   • the peak THREADS: description peak → record.peakLuminance verbatim
//     (the fixture's 1000-ladder face + a 4000 synthetic);
//   • the export peak gate (ExportVariant.validate) stays zero-disturbed —
//     a seeded 4000-peak record passes; a non-finite one is typed-rejected;
//   • the manual-EDR mutual exclusion: the follow gate is OFF while the
//     raster DRT tail owns the display.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class RasterHdrViewportTests: XCTestCase {

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    private func fixture(_ name: String) throws -> URL {
        let url = Self.fixtureDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("fixture missing: \(name)")
        }
        return url
    }

    private func decodedFixture(_ name: String) async throws -> DecodedImage {
        try await RAWDecoder().decode(fixture(name))
    }

    private func record(space: DrtEncodingSpace, eotf: DrtEotf) -> DrtRecord {
        var record = DrtRecord()
        record.encodingSpace = space
        record.encodingEotf = eotf
        return record
    }

    // MARK: - The DRT-HDR arm through the real chain

    func testPqFixtureDrivesTheDrtHdrViewportArm() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let decoded = try await decodedFixture("pq-cicp-16.tif")
        let description = try XCTUnwrap(decoded.rasterColor)
        let derivation = RasterDefaultRecord.derive(
            from: description,
            contentProbeMax: decoded.rasterNative?.contentProbeMax ?? 0)
        XCTAssertEqual(derivation.record.encodingSpace, .rec2020)
        XCTAssertEqual(derivation.record.encodingEotf, .st2084)

        // The viewport arm (the DrtViewportTests form): 16F + EDR + PQ.
        let device = MTLCreateSystemDefaultDevice()!
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), device: device)
        let vc = EditorMTKView.Coordinator(
            device: device, commandQueue: device.makeCommandQueue()!, sourceTexture: nil)
        vc.drtTailSurface = EditorMTKView.Coordinator.drtSurfaceSpec(
            for: derivation.record)
        vc.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(view.colorPixelFormat, .rgba16Float, "DRT-HDR rides 16F")
        XCTAssertTrue(view.layer is CAMetalLayer)
        let layer = view.layer as! CAMetalLayer
        XCTAssertTrue(layer.wantsExtendedDynamicRangeContent, "the EDR flag flips")
        XCTAssertEqual(
            layer.colorspace, CGColorSpace(name: CGColorSpace.itur_2100_PQ))
    }

    func testHlgFixtureDrivesTheHlgArm() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let decoded = try await decodedFixture("hlg-cicp-16.tif")
        let description = try XCTUnwrap(decoded.rasterColor)
        let derivation = RasterDefaultRecord.derive(
            from: description,
            contentProbeMax: decoded.rasterNative?.contentProbeMax ?? 0)
        XCTAssertEqual(derivation.record.encodingEotf, .hlg)

        let device = MTLCreateSystemDefaultDevice()!
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), device: device)
        let vc = EditorMTKView.Coordinator(
            device: device, commandQueue: device.makeCommandQueue()!, sourceTexture: nil)
        vc.drtTailSurface = EditorMTKView.Coordinator.drtSurfaceSpec(
            for: derivation.record)
        vc.applyEDRDisplaySurface(to: view)
        let layer = view.layer as! CAMetalLayer
        XCTAssertEqual(
            layer.colorspace, CGColorSpace(name: CGColorSpace.itur_2100_HLG))
    }

    // MARK: - Peak threading

    func testPeakThreadsFromDescriptionThroughDerive() async throws {
        let decoded = try await decodedFixture("pq-cicp-16.tif")
        let description = try XCTUnwrap(decoded.rasterColor)
        let derivation = RasterDefaultRecord.derive(
            from: description,
            contentProbeMax: decoded.rasterNative?.contentProbeMax ?? 0)
        XCTAssertEqual(
            derivation.record.peakLuminance, description.peakLuminanceNits,
            "the description peak threads verbatim (the 1000-ladder face)")

        // The 4000 face: a synthetic PQ description at 4000 nits derives a
        // 4000 record (the two-ladder plan pin).
        var hot = description
        hot.peakLuminanceNits = 4000
        let hotDerivation = RasterDefaultRecord.derive(
            from: hot, contentProbeMax: 0)
        XCTAssertEqual(hotDerivation.record.peakLuminance, 4000)
    }

    func testExportPeakGateStaysZeroDisturbed() throws {
        // The OQ-7 gate (ExportVariant.validate): a seeded HDR record
        // (finite positive peak) passes untouched; drtOutput == nil never
        // triggers; a poisoned peak is typed-refused.
        var record = DrtRecord()
        record.method = .aces20
        record.encodingSpace = .rec2020
        record.encodingEotf = .st2084
        record.peakLuminance = 4000

        func variant(record: DrtRecord?) throws -> ExportVariant {
            ExportVariant(
                format: .tiff(bitDepth: .eight, compression: .none),
                colorSpace: .sRGB,
                drtOutput: record)
        }
        XCTAssertNoThrow(try variant(record: record).validate())
        XCTAssertNoThrow(try variant(record: nil).validate(), "nil never triggers")
        record.peakLuminance = .nan
        XCTAssertThrowsError(try variant(record: record).validate())
    }

    // MARK: - The manual-EDR mutual exclusion

    func testFollowGateOffWhileRasterDrtTailOwnsTheDisplay() {
        // The gate predicate (M2-6-3 E3): OFF while a DRT tail (the raster
        // seed's tail included) owns the surface — the manual EDR toggle
        // is bypassed in both directions.
        XCTAssertFalse(
            EditorMTKView.Coordinator.followGateActive(
                edrActive: false, drtTailActive: true),
            "a raster DRT tail must pin the surface against the screen follow")
        XCTAssertTrue(
            EditorMTKView.Coordinator.followGateActive(
                edrActive: false, drtTailActive: false),
            "the legacy face keeps the follow")
        XCTAssertFalse(
            EditorMTKView.Coordinator.followGateActive(
                edrActive: true, drtTailActive: false))
    }
}
