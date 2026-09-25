@testable import LightamerCore
import WebP
import XCTest

/// The libwebp encoder goldens (Plan 11-02 T4): lossless BITWISE round
/// trips through `WebPDecoder`, lossy known-point bands, odd-dimension
/// vectors, the quality→effort fold, and the OQ-11-5 metadata-exception
/// anchor (a structural RIFF chunk walk asserting NO EXIF/XMP/ICCP chunk
/// ever rides the container).
final class WebPEncoderTests: XCTestCase {

    /// SplitMix64 deterministic plane (alpha forced opaque — WebP lossless
    /// is bit-exact only through the same alpha semantics).
    private func randomPlane(width: Int, height: Int, seed: UInt64) -> ExportQuantizedPlane {
        var state = seed
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        var data = Data(capacity: width * height * 4)
        for _ in 0..<(width * height) {
            var bytes = [UInt8](repeating: 255, count: 4)
            for c in 0..<3 { bytes[c] = UInt8(truncatingIfNeeded: next()) }
            data.append(contentsOf: bytes)
        }
        return ExportQuantizedPlane(data: data, width: width, height: height, layout: .rgba8)
    }

    /// The 33×17 known-point plane (odd dims — the alignment probe): three
    /// saturated quadrants around a neutral-gray band.
    private func knownPointPlane() -> ExportQuantizedPlane {
        let w = 33, h = 17
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let quadrant = (x < w / 2 ? 0 : 1) + (y < h / 2 ? 0 : 2)
                let rgb: [UInt8] = switch quadrant {
                case 0: [255, 0, 0]
                case 1: [0, 255, 0]
                case 2: [0, 0, 255]
                default: [128, 128, 128]
                }
                bytes[i] = rgb[0]; bytes[i + 1] = rgb[1]; bytes[i + 2] = rgb[2]; bytes[i + 3] = 255
            }
        }
        return ExportQuantizedPlane(data: Data(bytes), width: w, height: h, layout: .rgba8)
    }

    private func goldenDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("11-02-webp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func encode(_ plane: ExportQuantizedPlane, quality: Double, lossless: Bool) throws -> (url: URL, data: Data) {
        let url = goldenDir().appendingPathComponent("out-\(lossless ? "lossless" : "lossy").webp")
        let request = ExportEncodeRequest(
            plane: plane, spec: .webp(quality: quality, lossless: lossless),
            colorSpace: CGColorSpace(name: "kCGColorSpaceSRGB" as CFString)!,
            destination: url)
        try ExportEncoderRegistry.encoder(for: request.spec, plane: plane).encode(request)
        let data = try Data(contentsOf: url)
        return (url, data)
    }

    private func decodeToRGBA(_ data: Data, width: Int, height: Int) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: width * height * 4)
        let bytes = try WebPDecoder().decode(
            data, into: &output, options: WebPDecoderOptions(), format: .rgba)
        XCTAssertEqual(bytes, width * height * 4)
        return output
    }

    /// Walk the RIFF chunk list and return the fourcc set (payload size
    /// padded to even per the RIFF/WebP container spec).
    private func riffChunks(_ data: Data) throws -> [String] {
        guard data.count >= 12,
            String(data: data.prefix(4), encoding: .ascii) == "RIFF",
            String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WEBP"
        else { throw AppError.decodeFailed("not a RIFF/WEBP container") }
        var chunks: [String] = []
        var offset = 12
        while offset + 8 <= data.count {
            let fourcc = String(data: data.subdata(in: offset..<offset + 4), encoding: .ascii) ?? "????"
            let sizeField = data.subdata(in: offset + 4..<offset + 8)
            let size = sizeField.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            chunks.append(fourcc)
            offset += 8 + Int(size) + (Int(size) & 1)
        }
        return chunks
    }

    // MARK: - Lossless (bitwise contract)

    func testWebPLosslessBitwiseRoundTrip() throws {
        let plane = randomPlane(width: 37, height: 19, seed: 0x57454250)
        let (url, data) = try encode(plane, quality: 0.75, lossless: true)
        _ = url
        let features = try WebPImageInspector.inspect(data)
        XCTAssertEqual(features.width, 37)
        XCTAssertEqual(features.height, 19)
        XCTAssertEqual(features.format, WebPBitstreamFeatures.Format.lossless)
        let decoded = try decodeToRGBA(data, width: 37, height: 19)
        XCTAssertEqual(decoded, [UInt8](plane.data), "webp lossless: BITWISE round-trip")
    }

    // MARK: - Lossy (known points + bands)

    func testWebPLossyKnownPoints() throws {
        let plane = knownPointPlane()
        let (_, data) = try encode(plane, quality: 0.9, lossless: false)
        let features = try WebPImageInspector.inspect(data)
        XCTAssertEqual(features.width, 33, "odd width survives exactly")
        XCTAssertEqual(features.height, 17, "odd height survives exactly")
        XCTAssertEqual(features.format, WebPBitstreamFeatures.Format.lossy)
        let decoded = try decodeToRGBA(data, width: 33, height: 17)

        func at(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * 33 + x) * 4
            return (decoded[i], decoded[i + 1], decoded[i + 2])
        }
        func near(_ v: UInt8, _ want: Int, _ label: String) {
            XCTAssertLessThan(abs(Int(v) - want), 7, "webp lossy \(label): \(v) vs \(want)")
        }
        let red = at(2, 2)
        near(red.0, 255, "R r"); near(red.1, 0, "R g"); near(red.2, 0, "R b")
        let green = at(30, 2)
        near(green.1, 255, "G g")
        let blue = at(2, 14)
        near(blue.2, 255, "B b")
        let gray = at(30, 14)
        near(gray.0, 128, "gray r"); near(gray.1, 128, "gray g"); near(gray.2, 128, "gray b")
        XCTAssertLessThan(abs(Int(gray.0) - Int(gray.1)), 7, "webp lossy gray neutrality")
    }

    // MARK: - The OQ-11-5 metadata exception (structural anchor)

    func testWebPContainerCarriesNoMetadataChunks() throws {
        // OQ-11-5 verdict: Swift-WebP exposes NO mux face (probed: zero
        // mux/EXIF/ICC symbols in the package sources) — WebP ships with no
        // embedded EXIF/ICC/XMP, DOCUMENTED. This walk pins the container
        // structure so a metadata chunk sneaking in (or a future mux
        // adoption) is visible.
        for lossless in [true, false] {
            let (_, data) = try encode(knownPointPlane(), quality: 0.9, lossless: lossless)
            let chunks = try riffChunks(data)
            let allowed: Set<String> = ["VP8 ", "VP8L", "VP8X", "ALPH"]
            for chunk in chunks {
                XCTAssertTrue(
                    allowed.contains(chunk),
                    "webp lossless=\(lossless): unexpected container chunk \(chunk) — metadata face changed, refresh OQ-11-5")
            }
            XCTAssertFalse(chunks.contains("EXIF"))
            XCTAssertFalse(chunks.contains("XMP "))
            XCTAssertFalse(chunks.contains("ICCP"))
        }
    }

    // MARK: - The quality→effort fold (pure vectors)

    func testLosslessEffortFoldVectors() {
        XCTAssertEqual(LightamerWebPEncoder.losslessEffortLevel(forQuality: 0.0), 0)
        XCTAssertEqual(LightamerWebPEncoder.losslessEffortLevel(forQuality: 1.0), 9)
        XCTAssertEqual(LightamerWebPEncoder.losslessEffortLevel(forQuality: 0.5), 5)
        // 0.75*9 = 6.75 → 7 (round half away from zero family).
        XCTAssertEqual(LightamerWebPEncoder.losslessEffortLevel(forQuality: 0.75), 7)
        // Out-of-domain values clamp (defensive; the spec validates first).
        XCTAssertEqual(LightamerWebPEncoder.losslessEffortLevel(forQuality: -1), 0)
        XCTAssertEqual(LightamerWebPEncoder.losslessEffortLevel(forQuality: 42), 9)
    }

    // MARK: - Registry guard

    func testRegistryRejectsNon8BitPlaneForWebP() throws {
        let plane = randomPlane(width: 4, height: 4, seed: 9)
        let wrongTier = ExportQuantizedPlane(
            data: plane.data, width: 4, height: 4, layout: .rgba16)
        XCTAssertThrowsError(
            try ExportEncoderRegistry.encoder(for: .webp(quality: 0.8, lossless: true), plane: wrongTier)
        ) { error in
            guard case AppError.invalidParameter = error else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
    }
}
