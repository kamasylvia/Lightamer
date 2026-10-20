@testable import LightamerCore
import CoreImage
import XCTest

/// DNGOpcodeProbeTests (Plan LENS-01 T2) — the double-correction mutex
/// detector.
///
/// Table-driven over hand-woven TIFF bytes (the opcode-list tags 51008 /
/// 51009 / 51010 = DNG OpcodeList1/2/3): both endiannesses, the IFD0 face,
/// the SubIFD face (ProRAW multi-frame carries the opcodes in a sub-IFD),
/// the Exif-IFD pointer face, the negative (no tags), and the malformed
/// inputs (bad magic / out-of-range offsets / absurd entry counts / empty
/// window) — the probe must degrade to `false` without ever throwing.
/// Plus the four `DecodedImage` construction-site stamps (review M6): the
/// raster/TIFF legs all carry `.notApplicable`; the RAW-leg DNG/unknown
/// branch rides the probe itself (the CIRAW decode needs a real sensor
/// file, so the branch is pinned through `isDNGUTI` + the probe pair).
final class DNGOpcodeProbeTests: XCTestCase {

    // MARK: - TIFF weaver (little/big endian, IFD0 + optional one sub-IFD)

    private func wovenTIFF(
        bigEndian: Bool = false,
        ifd0Tags: [(tag: Int, value: Int)],
        subIFDPointerTag: Int? = nil,
        subIFDTags: [(tag: Int, value: Int)] = []
    ) -> Data {
        func u16(_ v: Int, into out: inout [UInt8]) {
            if bigEndian { out.append(UInt8((v >> 8) & 0xFF)); out.append(UInt8(v & 0xFF)) }
            else { out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF)) }
        }
        func u32(_ v: Int, into out: inout [UInt8]) {
            if bigEndian {
                out.append(UInt8((v >> 24) & 0xFF)); out.append(UInt8((v >> 16) & 0xFF))
                out.append(UInt8((v >> 8) & 0xFF)); out.append(UInt8(v & 0xFF))
            } else {
                out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF))
                out.append(UInt8((v >> 16) & 0xFF)); out.append(UInt8((v >> 24) & 0xFF))
            }
        }
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) -> [UInt8] {
            var e: [UInt8] = []
            u16(tag, into: &e); u16(type, into: &e); u32(count, into: &e); u32(value, into: &e)
            return e
        }

        let hasSub = subIFDPointerTag != nil
        let ifd0Size = 2 + (ifd0Tags.count + (hasSub ? 1 : 0)) * 12 + 4
        let subOffset = 8 + ifd0Size
        let subSize = 2 + subIFDTags.count * 12 + 4
        let pixelOffset = subOffset + (hasSub ? subSize : 0)
        let pixelBytes = 4 * 4 * 3

        var d: [UInt8] = []
        d.append(contentsOf: bigEndian ? [0x4D, 0x4D] : [0x49, 0x49])
        u16(42, into: &d)
        u32(8, into: &d)

        u16(ifd0Tags.count + (hasSub ? 1 : 0), into: &d)
        for (tag, value) in ifd0Tags { d.append(contentsOf: entry(tag, 4, 1, value)) }
        if let subTag = subIFDPointerTag {
            d.append(contentsOf: entry(subTag, 4, 1, subOffset))
        }
        u32(0, into: &d)

        if hasSub {
            u16(subIFDTags.count, into: &d)
            for (tag, value) in subIFDTags { d.append(contentsOf: entry(tag, 4, 1, value)) }
            u32(0, into: &d)
        }
        d.append(contentsOf: [UInt8](repeating: 128, count: pixelBytes))
        return Data(d)
    }

    // MARK: - probe(data:) table

    func testLittleEndianIFD0OpcodeTagDetected() {
        let tiff = wovenTIFF(ifd0Tags: [(51008, 16)])
        XCTAssertTrue(DNGOpcodeProbe.probe(data: tiff))
    }

    func testBigEndianIFD0OpcodeTagDetected() {
        let tiff = wovenTIFF(bigEndian: true, ifd0Tags: [(51009, 16)])
        XCTAssertTrue(DNGOpcodeProbe.probe(data: tiff))
    }

    func testSubIFDOpcodeTagDetected() {
        let tiff = wovenTIFF(
            ifd0Tags: [(256, 4)],
            subIFDPointerTag: 0x014A,
            subIFDTags: [(51010, 8)])
        XCTAssertTrue(DNGOpcodeProbe.probe(data: tiff))
    }

    func testExifIFDPointerOpcodeTagDetected() {
        let tiff = wovenTIFF(
            ifd0Tags: [],
            subIFDPointerTag: 0x8769,
            subIFDTags: [(51008, 8)])
        XCTAssertTrue(DNGOpcodeProbe.probe(data: tiff))
    }

    func testNoOpcodeTagsReadsFalse() {
        let tiff = wovenTIFF(
            ifd0Tags: [(256, 4), (257, 4)],
            subIFDPointerTag: 0x014A,
            subIFDTags: [(256, 4)])
        XCTAssertFalse(DNGOpcodeProbe.probe(data: tiff))
    }

    // MARK: - Malformed inputs (容错: false, never throw)

    func testMalformedInputsDegradeToFalse() {
        XCTAssertFalse(DNGOpcodeProbe.probe(data: Data()))
        XCTAssertFalse(DNGOpcodeProbe.probe(data: Data([0x49, 0x49, 0x2A])))
        XCTAssertFalse(DNGOpcodeProbe.probe(data: Data([0x58, 0x58, 0x2A, 0x00, 0x00, 0x00, 0x00, 0x00])))
        // IFD0 offset past the window.
        XCTAssertFalse(DNGOpcodeProbe.probe(data: wovenTIFF(ifd0Tags: []) + Data(repeating: 0, count: 8)))
        // Absurd entry count (0xFFFF > 4096 cap).
        var absurd = Data([0x49, 0x49]); absurd.append(contentsOf: [0x2A, 0x00])
        absurd.append(contentsOf: [0x08, 0x00, 0x00, 0x00])
        absurd.append(contentsOf: [0xFF, 0xFF])
        XCTAssertFalse(DNGOpcodeProbe.probe(data: absurd))
        // Window semantics: header only — the IFD0 reference falls outside.
        XCTAssertFalse(DNGOpcodeProbe.probe(data: wovenTIFF(ifd0Tags: [(51008, 8)]).prefix(8)))
    }

    // MARK: - probe(url:) (the production FileHandle face)

    func testProbeURLOnDiskFiles() throws {
        let hit = FileManager.default.temporaryDirectory
            .appendingPathComponent("dng-probe-hit-\(UUID().uuidString).dng")
        let miss = FileManager.default.temporaryDirectory
            .appendingPathComponent("dng-probe-miss-\(UUID().uuidString).dng")
        defer {
            try? FileManager.default.removeItem(at: hit)
            try? FileManager.default.removeItem(at: miss)
        }
        try wovenTIFF(ifd0Tags: [(51009, 16)]).write(to: hit)
        try wovenTIFF(ifd0Tags: [(256, 4)]).write(to: miss)
        XCTAssertTrue(DNGOpcodeProbe.probe(url: hit))
        XCTAssertFalse(DNGOpcodeProbe.probe(url: miss))
        XCTAssertFalse(DNGOpcodeProbe.probe(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("dng-probe-absent-\(UUID().uuidString)")))
    }

    // MARK: - The RAW-leg branch predicates (review M6 pinning)

    func testDNGUTIFamilyPredicate() {
        XCTAssertTrue(RAWDecoder.isDNGUTI("com.adobe.raw-image"))
        XCTAssertTrue(RAWDecoder.isDNGUTI("public.adobe-dng"))
        XCTAssertFalse(RAWDecoder.isDNGUTI("public.jpeg"))
        XCTAssertFalse(RAWDecoder.isDNGUTI("com.canon.cr3-raw-image"))
    }

    // MARK: - The raster construction sites (review M6: all stamped)

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
            throw XCTSkip("fixture missing: \(name) — run Scripts/gen-tiff-fixtures.py")
        }
        return url
    }

    func testNativeTIFFLegStampsNotApplicable() throws {
        let decoded = try RasterDecoder.decodeTIFF(try fixture("srgb-matrix-8.tif"))
        XCTAssertEqual(decoded.embeddedGeometry, .notApplicable)
    }

    func testLUTICCTIFFLegStampsNotApplicable() throws {
        let decoded = try RasterDecoder.decodeTIFF(try fixture("lut-a2b0-8.tif"))
        XCTAssertEqual(decoded.embeddedGeometry, .notApplicable)
    }

    func testRetiredRasterLegStampsNotApplicable() async throws {
        let decoder = RAWDecoder()
        let decoded = try await decoder.decodeRaster(try fixture("srgb-matrix-8.tif"), uti: "public.tiff")
        XCTAssertEqual(decoded.embeddedGeometry, .notApplicable)
    }

    /// The zero-drift negative (the additive-optional contract): an init
    /// that does not pass the new parameter reads nil — the pre-batch
    /// synthetic shape the panel treats as "undetermined".
    func testAdditiveFieldDefaultsNil() {
        let image = CIImage.empty()
        let record = DecodedImage(
            ciImage: image, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8, contentDedupeID: 7)
        XCTAssertNil(record.embeddedGeometry)
    }
}
