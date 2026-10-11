@testable import Lightamer
@testable import LightamerCore
import CoreGraphics
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensRasterDomainTests (Plan M5-2-02 T2, KD-2) — the two-domain
// discriminator pins on the merge products' color-space tags:
//
//   • the Mertens product = sRGB-TAGGED 32f → reimport resolves
//     .srgbPiecewise / .displayReferred with a REAL origin (the Primé rule
//     does not fire — the transfer is not linear). This is the OQ-2
//     "zero new mechanism + kind domain discriminator" production landing.
//   • the Robertson02 product = working-tagged (linear Rec2020) 32f → the
//     ①′ Primé rule routes it to .sceneLinear — the CONTRASTING domain.
//   • the writeFloatTIFF additive default = the working space (the
//     pre-M5-2-02 callers byte-identical — the negative pin).
//   • the ② no-ICC float32 → scene-linear rule stays unregressed (the KD-2
//     correction basis: an UNTAGGED float32 product would have been
//     domain-misjudged, hence the explicit sRGB tag).
//
// Fixtures are TEMP-domain throwaway TIFFs (L072).
// ─────────────────────────────────────────────────────────────────────────────

final class MertensRasterDomainTests: XCTestCase {

    private static let width = 24
    private static let height = 16

    /// A small deterministic display-domain plane (values in [0,1]).
    private static func plane() -> [Float] {
        var floats = [Float](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let base = pixel * 4
            let ramp = Float(pixel % 97) / 97
            floats[base] = ramp
            floats[base + 1] = ramp * 0.5
            floats[base + 2] = 1 - ramp
            floats[base + 3] = 1
        }
        return floats
    }

    private func writeTemp(_ name: String, colorSpace: CGColorSpace?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mertens-domain-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        if let colorSpace {
            try BandStreamer.writeFloatTIFF(
                Self.plane(), width: Self.width, height: Self.height,
                to: url, colorSpace: colorSpace)
        } else {
            try BandStreamer.writeFloatTIFF(
                Self.plane(), width: Self.width, height: Self.height, to: url)
        }
        return url
    }

    /// The Mertens domain declaration: sRGB-tagged 32f →
    /// .srgbPiecewise + .displayReferred, a REAL origin (not the sRGB
    /// default face), and the Primé rule untouched (transfer ≠ linear).
    func testMertensProductResolvesSrgbDisplayReferred() async throws {
        let url = try writeTemp(
            "mertens_srgb.tif", colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let decoded = try await RAWDecoder().decode(url)
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertEqual(description.transfer, .srgbPiecewise)
        XCTAssertEqual(description.referral, .displayReferred)
        XCTAssertNotEqual(
            description.origin, .defaultSrgb,
            "the tag must describe the file, not fall to the ③ default")
        XCTAssertNotNil(description.profileHash, "the ICC rides the product")
        XCTAssertNil(description.defaultReason, "no default demotion")
    }

    /// The contrasting domain: the Robertson02 product (working-space tag —
    /// linear Rec2020 on float32) routes through the ①′ Primé rule to
    /// .sceneLinear. Two domains, two gates, one resolver.
    func testRobertsonProductResolvesSceneLinearViaPrime() async throws {
        let url = try writeTemp("robertson_working.tif", colorSpace: nil)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let decoded = try await RAWDecoder().decode(url)
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertEqual(description.transfer, .linear)
        XCTAssertEqual(description.referral, .sceneLinear)
        XCTAssertEqual(
            description.defaultReason, "linear-ICC float32 → scene-linear",
            "the Primé marker must be on the record")
    }

    /// The additive-default zero-drift negative: omitting `colorSpace`
    /// produces BYTE-IDENTICAL files to passing the working space
    /// explicitly (the pre-M5-2-02 callers' contract).
    func testWriteFloatTIFFDefaultParameterZeroDrift() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mertens-domain-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let implicit = dir.appendingPathComponent("implicit.tif")
        let explicit = dir.appendingPathComponent("explicit.tif")
        try BandStreamer.writeFloatTIFF(
            Self.plane(), width: Self.width, height: Self.height, to: implicit)
        try BandStreamer.writeFloatTIFF(
            Self.plane(), width: Self.width, height: Self.height, to: explicit,
            colorSpace: WorkingSpace.colorSpace)
        XCTAssertEqual(
            try Data(contentsOf: implicit), try Data(contentsOf: explicit),
            "the default arm must be byte-invisible")
    }

    /// The KD-2 correction basis stays pinned: an UNTAGGED float32 TIFF
    /// resolves scene-linear Rec2020 (the ② rule) — which is exactly why
    /// the Mertens product must carry the explicit sRGB tag.
    func testNoIccFloat32RuleUnregressed() {
        let description = RasterColorResolver.resolve(
            iccData: nil, colorSpaceName: nil, isFloat: true)
        XCTAssertEqual(description.referral, .sceneLinear)
        XCTAssertEqual(description.transfer, .linear)
        XCTAssertEqual(description.origin, .tiffNoIccFloatLinear)
        XCTAssertEqual(description.primariesXY, RasterColorResolver.rec2020Primaries)
    }

    /// The end-to-end face: a real Mertens leg run lands an sRGB-tagged
    /// product whose reimport resolves the display-referred description
    /// (the M4-1 display leg then linearizes — zero new mechanism).
    func testMertensLegProductResolvesSrgbEndToEnd() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mertens-domain-leg-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        // A compact half-exact two-frame bracket (the MertensLegTests
        // fixture shape, inlined for file independence).
        let width = 32, height = 24
        var floats = [Float](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let base = pixel * 4
            let checker = ((pixel % width) / 4 + (pixel / width) / 4) % 2 == 0
            floats[base] = checker ? 0.75 : 0.25
            floats[base + 1] = checker ? 0.75 : 0.25
            floats[base + 2] = checker ? 0.75 : 0.25
            floats[base + 3] = 1
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let decodeLeg: StackDecodeLeg = { _ in
            let ci = CIImage(
                bitmapData: data, bytesPerRow: width * 16,
                size: CGSize(width: width, height: height),
                format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
            return DecodedImage(
                ciImage: ci, rawTech: RAWTechnicalParams(),
                capture: CaptureMetadata(), segmentationSkyMatte: nil,
                decoderVersionUsed: .v8)
        }
        let service = try StackMergeService(device: device, decodeLeg: decodeLeg)
        var sources: [URL] = []
        for index in 0..<2 {
            let url = dir.appendingPathComponent("src\(index).tif")
            try Data([UInt8(index)]).write(to: url)
            sources.append(url)
        }
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "off"),
            sessionRoot: dir)
        let deadline = Date().addingTimeInterval(30)
        var product: URL?
        while Date() < deadline {
            let snapshots = await service.snapshots()
            if let newest = snapshots.last, newest.state.isTerminal {
                guard case .done(let url) = newest.state else {
                    XCTFail("expected .done, got \(newest.state)")
                    return
                }
                product = url
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let landed = try XCTUnwrap(product, "the leg never settled")
        let decoded = try await RAWDecoder().decode(landed)
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertEqual(description.transfer, .srgbPiecewise)
        XCTAssertEqual(description.referral, .displayReferred)
        XCTAssertNotEqual(description.origin, .defaultSrgb)
    }
}
