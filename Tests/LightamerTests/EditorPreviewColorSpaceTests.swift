import CoreGraphics
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// EditorPreviewColorSpaceTests (Plan M7-6-01 T2, UQ-A1 — APP domain) — the
// preview/export ICC closure:
//
//   • the 8 legal SDR pairs: `drtLayerColorSpace` returns the EXPORT-side
//     ICC v4 instance (the same cached object the exported file carries —
//     the preview/file double-curve mismatch is gone; the UQ-A1 defect rode
//     the calibrated 2.2-power approximation on the preview face only);
//   • the srgbPiecewise pair: the preview face decodes like the TRUE
//     piecewise table (the linear segment below the 0.04045 knee), NOT the
//     retired [2.2 2.2 2.2] power approximation (the M4-1-01 KD-8 deviation
//     this fix resolves);
//   • the out-of-domain pairs: the preview still answers non-nil (the
//     calibrated fallback arm — the display obligation covers every
//     space×SDR-eotf combination) while the export resolver keeps its typed
//     rejection (the export legal table stays closed, OQ-M7-6-4).
//
// (implementation form, DECISIONS-declared): the plan's ramp-equality leg
// collapses to the same-instance assertion — preview space === export space
// makes a per-step decode comparison trivially equal, so the ramp leg rides
// the srgbPiecewise-vs-ideal decode check instead (the only place the decode
// face carries real information).
// ─────────────────────────────────────────────────────────────────────────────

final class EditorPreviewColorSpaceTests: XCTestCase {

    /// The 8 legal SDR pairs (the export linkage table's SDR subset — the
    /// HDR rows rec2020×{st2084,hlg} + p3d65×st2084 ride the HDR arm above,
    /// untouched; gamma18 sits in NO legal set).
    static let legalSDRPairs: [(DrtEncodingSpace, DrtEotf)] = [
        (.rec709, .bt1886), (.rec709, .gamma22), (.rec709, .srgbPiecewise),
        (.p3d65, .gamma22), (.p3d65, .srgbPiecewise),
        (.p3d60, .gamma26), (.p3dci, .gamma26), (.xyz, .gamma26),
    ]

    private static func makeRecord(
        space: DrtEncodingSpace, eotf: DrtEotf
    ) -> DrtRecord {
        // Read-only construction (the record layer is a sealed face — the
        // test never writes it back).
        var record = DrtRecord()
        record.encodingSpace = space
        record.encodingEotf = eotf
        return record
    }

    private static func previewSpace(
        space: DrtEncodingSpace, eotf: DrtEotf
    ) throws -> CGColorSpace {
        try XCTUnwrap(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                makeRecord(space: space, eotf: eotf)),
            "the preview must answer a colorspace for \(space.rawValue)+\(eotf.rawValue)")
    }

    // MARK: - The legal pairs: preview === export (the UQ-A1 closure)

    func testLegalSDRPairsPreviewSharesTheExportICCInstance() throws {
        for (space, eotf) in Self.legalSDRPairs {
            let preview = try Self.previewSpace(space: space, eotf: eotf)
            let export = try DrtOutputColorSpace.drtOutputColorSpace(
                space: space, eotf: eotf)
            XCTAssertTrue(
                preview === export,
                "\(space.rawValue)+\(eotf.rawValue): the preview must return the "
                    + "export-side cached instance (one object, one curve)")
            let previewBytes = try XCTUnwrap(preview.copyICCData() as Data?)
            let exportBytes = try XCTUnwrap(export.copyICCData() as Data?)
            XCTAssertEqual(
                previewBytes, exportBytes,
                "\(space.rawValue)+\(eotf.rawValue): identical ICC bytes")
        }
    }

    // MARK: - The srgbPiecewise pair: the TRUE piecewise decode face

    /// Encodes gray levels in `space`, decodes to linear through the real
    /// ICC conversion (the CGColor ColorSync transform — the profile's TRC
    /// drives the decode), returns the red channel per level.
    private static func decodeThroughICC(
        _ space: CGColorSpace, codes: [UInt8]
    ) throws -> [CGFloat] {
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        return try codes.map { code in
            let encoded = CGFloat(code) / 255.0
            let color = try XCTUnwrap(
                CGColor(colorSpace: space,
                        components: [encoded, encoded, encoded, 1.0]),
                "the gray color needs the space's component count")
            let converted = try XCTUnwrap(
                color.converted(
                    to: linear, intent: .relativeColorimetric,
                    options: nil),
                "the ColorSync transform must answer the linear decode")
            return converted.components![0]
        }
    }

    func testSrgbPiecewisePreviewDecodesLikeTheTruePiecewiseTable() throws {
        // The retired preview face (the [2.2 2.2 2.2] power approximation)
        // answers ~4.9x lower at the below-knee codes — this leg proves the
        // preview face now rides the export ICC's sampled table (the linear
        // segment answers code/12.92 there).
        let preview = try Self.previewSpace(space: .rec709, eotf: .srgbPiecewise)
        let codes: [UInt8] = [8, 32, 128, 254]
        let decoded = try Self.decodeThroughICC(preview, codes: codes)
        XCTAssertEqual(decoded.count, codes.count)
        for (index, code) in codes.enumerated() {
            let encoded = Double(code) / 255.0
            let ideal = DrtEotfMath.srgbPiecewiseDecode(encoded)
            let powerApproximation = pow(encoded, 2.2)
            XCTAssertLessThan(
                abs(Double(decoded[index]) - ideal), 0.004,
                "code \(code): the preview decode must ride the piecewise "
                    + "table (ideal \(ideal), got \(decoded[index]))")
            if code <= 16 {
                // The discriminator: the linear-segment decode sits far
                // above the retired power face at the below-knee codes.
                XCTAssertGreaterThan(
                    Double(decoded[index]), powerApproximation * 3.0,
                    "code \(code): the 2.2-power approximation is retired "
                        + "(power \(powerApproximation), got \(decoded[index]))")
            }
        }
    }

    // MARK: - The out-of-domain pairs: the calibrated fallback stays

    func testOutOfDomainPairsFallBackToCalibratedPreview() throws {
        for (space, eotf) in [(DrtEncodingSpace.rec709, DrtEotf.gamma18),
                              (DrtEncodingSpace.p3d65, DrtEotf.bt1886)] {
            // The export resolver keeps the typed rejection (the legal
            // table stays closed — OQ-M7-6-4; expanding it would be an
            // export-semantics change outside this fix's scope).
            do {
                _ = try DrtOutputColorSpace.drtOutputColorSpace(
                    space: space, eotf: eotf)
                XCTFail("\(space.rawValue)+\(eotf.rawValue) must stay typed-rejected")
            } catch let error as AppError {
                guard case .invalidParameter = error else {
                    return XCTFail("unexpected error case: \(error)")
                }
            }
            // The preview display obligation: non-nil (the calibrated
            // fallback arm), and NOT any export instance (no legal pair
            // leaks its profile into the out-of-domain face).
            let preview = try Self.previewSpace(space: space, eotf: eotf)
            XCTAssertEqual(preview.model, .rgb)
            for (legalSpace, legalEotf) in Self.legalSDRPairs {
                let export = try DrtOutputColorSpace.drtOutputColorSpace(
                    space: legalSpace, eotf: legalEotf)
                XCTAssertFalse(
                    preview === export,
                    "the out-of-domain face must not share a legal profile")
            }
        }
    }
}
