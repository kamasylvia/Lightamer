import Foundation
import WebP
import XCTest

/// Swift-WebP (the project's ONLY SPM dependency, D-11-CONTEXT-1) link +
/// capability smoke (Plan 11-01 T4). NOT a golden suite — the per-format
/// pixel/ICC goldens land in 11-02; this file proves the package resolves,
/// links into the Core-side test graph, and encodes real bitstreams with the
/// API face this phase pinned (RESEARCH §2: WebPEncoder + WebPEncoderConfig).
final class WebPIntegrationSmokeTests: XCTestCase {

    /// libwebp containers are RIFF: bytes 0-3 "RIFF", 8-11 "WEBP".
    private func assertRIFFWebPHeader(_ data: Data, _ label: String) {
        XCTAssertGreaterThanOrEqual(data.count, 12, label)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF", label)
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WEBP", label)
    }

    /// Encode `rgba` (width × height, RGBA8, packed stride) through the
    /// given config — the buffer rides `withUnsafeBufferPointer` so no
    /// dangling-pointer warnings are introduced.
    private func encode(
        _ rgba: [UInt8], width: Int, height: Int, config: WebPEncoderConfig
    ) throws -> Data {
        try rgba.withUnsafeBufferPointer { buffer in
            try WebPEncoder().encode(
                buffer,
                format: .rgba,
                config: config,
                originWidth: width,
                originHeight: height,
                stride: width * 4)
        }
    }

    /// 1×1 RGBA lossy encode: the minimal end-to-end call through
    /// `WebPEncoder.encode(UnsafeBufferPointer, format:config:…)`.
    func testLossyEncode1x1RGBA() throws {
        let data = try encode(
            [255, 0, 0, 255], width: 1, height: 1,
            config: WebPEncoderConfig.preset(.default, quality: 75))
        assertRIFFWebPHeader(data, "lossy")

        let features = try WebPImageInspector.inspect(data)
        XCTAssertEqual(features.width, 1)
        XCTAssertEqual(features.height, 1)
        XCTAssertEqual(features.format, WebPBitstreamFeatures.Format.lossy)
    }

    /// The independent LOSSLESS face (RESEARCH §1.2: lossless is its own
    /// config path, `losslessPreset(level:)`).
    func testLosslessEncode1x1RGBA() throws {
        let data = try encode(
            [0, 128, 255, 255], width: 1, height: 1,
            config: try WebPEncoderConfig.losslessPreset(level: 6))
        assertRIFFWebPHeader(data, "lossless")

        let features = try WebPImageInspector.inspect(data)
        XCTAssertEqual(features.format, WebPBitstreamFeatures.Format.lossless)
    }

    /// Decode round-trip of the lossless bitstream returns the exact pixel
    /// (lossless is bit-exact by contract — the 11-02 goldens lean on it).
    func testLosslessDecodeRoundTrip() throws {
        let rgba: [UInt8] = [12, 200, 77, 255]
        let data = try encode(
            rgba, width: 1, height: 1,
            config: try WebPEncoderConfig.losslessPreset(level: 6))

        var output = [UInt8](repeating: 0, count: 4)
        let bytes = try WebPDecoder().decode(
            data, into: &output, options: WebPDecoderOptions(), format: .rgba)
        XCTAssertEqual(bytes, 4)
        XCTAssertEqual(output, rgba)
    }

    /// The library identity pinned in the manifest (Project.swift packages).
    func testLibwebpVersionAvailable() {
        let version = WebPEncoder.libwebpVersion
        // libwebp 1.5.0+ per RESEARCH §2.2 (Swift-WebP 0.6.x pins it).
        XCTAssertGreaterThanOrEqual(version.major, 1)
        XCTAssertGreaterThanOrEqual(version.minor, 5)
    }
}
