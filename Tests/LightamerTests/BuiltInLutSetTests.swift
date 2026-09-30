import LightamerIOP
import XCTest

/// BuiltInLutSetTests (Plan M2-5-3 T5, M2GRADE-07 / KD-4) — the vendored
/// built-in film LUT set riding the app bundle as the `LUTs/` folder:
/// exactly the evidence manifest (40 tables, the CMake-glob reality
/// corrected in
/// `.work/gsd/phases/m2-5-color-grade/evidence/spectral-film-lut-license.md`),
/// LICENSE + NOTICE attribution present, every table a 65^3 .cube, and
/// the seeder's first-launch/second-launch idempotency contract.
///
/// App-bundle member by design: Bundle.main IS the app bundle in the
/// direct host, so these assertions see the SHIPPED resources (the store
/// level faces live in the IOPP recursion tests). The init's default-root
/// branch itself is code-reviewed, not executed here — running it would
/// seed the developer's real ~/Library Application Support tree.
final class BuiltInLutSetTests: XCTestCase {

    /// The evidence manifest — the vendored file set, one line per row of
    /// the license-gate comparison table (39 exact upstream stocks +
    /// Kodak_Ultramax_400; Alcedo's Ultramax_500 / Vision3_500T_5219_3200
    /// have no upstream stock and are documented out).
    static let manifest: [String] = [
        "Agfa_Vista_100", "Fuji_C200", "Fuji_Eterna_500", "Fuji_Eterna_500_Vivid",
        "Fuji_Natura_1600", "Fuji_Pro_160C", "Fuji_Pro_160S", "Fuji_Pro_400H",
        "Fuji_Superia_Reala", "Fuji_Superia_X-Tra_400",
        "Kodak_5222", "Kodak_5247", "Kodak_5247_II", "Kodak_5247_II_Alt",
        "Kodak_5248", "Kodak_5250", "Kodak_Aerocolor_IV_2460",
        "Kodak_Aerocolor_IV_2460_High", "Kodak_Aerocolor_IV_2460_Low",
        "Kodak_Ektar_100", "Kodak_EXR_100T_5248", "Kodak_EXR_200T_5293",
        "Kodak_Gold_200", "Kodak_Portra_160", "Kodak_Portra_400",
        "Kodak_Portra_800", "Kodak_Portra_800_@1600", "Kodak_Portra_800_@3200",
        "Kodak_Tri-X_400", "Kodak_Trix-X_400_Dev_11", "Kodak_Trix-X_400_Dev_7",
        "Kodak_Trix-X_400_Dev_9", "Kodak_Ultramax_400", "Kodak_Verita_200D_5206",
        "Kodak_Vericolor_III", "Kodak_Vision_320T_5277", "Kodak_Vision3_200T_5213",
        "Kodak_Vision3_250D_5207", "Kodak_Vision3_500T_5219", "Kodak_Vision3_50D_5203",
    ]

    private var bundledLUTs: URL? { Bundle.main.url(forResource: "LUTs", withExtension: nil) }

    // MARK: - The packaged folder

    func testBundleCarriesExactlyTheManifestSetPlusAttribution() throws {
        let luts = try XCTUnwrap(bundledLUTs, "the app bundle carries the LUTs folder")
        let items = try FileManager.default.contentsOfDirectory(at: luts, includingPropertiesForKeys: nil)
        let cubes = items.filter { $0.pathExtension == "cube" }
        XCTAssertEqual(cubes.count, 40, "exactly the evidence manifest set")
        XCTAssertEqual(
            Set(cubes.map { $0.deletingPathExtension().lastPathComponent }),
            Set(Self.manifest),
            "file names match the license-gate evidence table line by line")
        // Attribution ships in the folder.
        let names = Set(items.map { $0.lastPathComponent })
        XCTAssertTrue(names.contains("LICENSE"), "the MIT license text ships")
        XCTAssertTrue(names.contains("NOTICE"), "the provenance notice ships")
        XCTAssertEqual(items.count, 42, "40 tables + LICENSE + NOTICE, nothing else")
    }

    func testAttributionContent() throws {
        let luts = try XCTUnwrap(bundledLUTs)
        let license = try String(
            contentsOf: luts.appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertTrue(license.contains("MIT License"), "the vendored LICENSE is the MIT text")
        XCTAssertTrue(license.contains("Jan Lohse"), "the upstream copyright line")
        let notice = try String(
            contentsOf: luts.appendingPathComponent("NOTICE"), encoding: .utf8)
        XCTAssertTrue(notice.contains("spectral_film_lut"), "the upstream project is named")
        XCTAssertTrue(notice.contains("0.18.2"), "the pinned generation version")
    }

    func testEveryTableIsA65CubeAndSamplesParse() throws {
        let luts = try XCTUnwrap(bundledLUTs)
        for name in Self.manifest {
            let url = luts.appendingPathComponent("\(name).cube")
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let header = String(decoding: handle.readData(ofLength: 128), as: UTF8.self)
            XCTAssertTrue(
                header.contains("LUT_3D_SIZE 65"),
                "\(name) is a 65^3 table (the Alcedo-packaged size)")
        }
        // Two representative tables parse through the production parser.
        let portra = try CubeLutParser.parse(
            data: Data(contentsOf: luts.appendingPathComponent("Kodak_Portra_400.cube")))
        guard case .lut3d(let size) = portra.kind else {
            return XCTFail("Portra 400 should be a 3D table")
        }
        XCTAssertEqual(size, 65)
        let trix = try CubeLutParser.parse(
            data: Data(contentsOf: luts.appendingPathComponent("Kodak_Tri-X_400.cube")))
        guard case .lut3d(let bwSize) = trix.kind else {
            return XCTFail("Tri-X should be a 3D table")
        }
        XCTAssertEqual(bwSize, 65)
    }

    // MARK: - The seeder contract (first launch / second launch)

    func testFirstLaunchSeedsBuiltInAndSecondLaunchIsIdempotent() throws {
        let luts = try XCTUnwrap(bundledLUTs)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("builtin-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // First launch: the whole folder copies into <root>/BuiltIn/.
        let first = LutLibraryStore.seedBuiltIns(from: luts, into: root)
        XCTAssertEqual(first, 42, "40 tables + LICENSE + NOTICE")
        let builtIn = root.appendingPathComponent("BuiltIn", isDirectory: true)
        let seeded = try FileManager.default.contentsOfDirectory(at: builtIn, includingPropertiesForKeys: nil)
        XCTAssertEqual(seeded.count, 42)
        // The recursive rescan registers the seeded tables under
        // BuiltIn/… relative paths (KD-1 encoding, M2GRADE-05 synergy).
        let store = LutLibraryStore(directory: root)
        XCTAssertEqual(store.installedNames.count, 40)
        XCTAssertEqual(
            store.entry(named: "BuiltIn/Kodak_Portra_400.cube")?.subdirectory, "BuiltIn")
        XCTAssertNotNil(store.lut(named: "BuiltIn/Agfa_Vista_100.cube"))
        // Second launch: the count+size sentinel copies nothing.
        let second = LutLibraryStore.seedBuiltIns(from: luts, into: root)
        XCTAssertEqual(second, 0, "the sentinel makes the seeding idempotent")
        // A drifted table (same name, different bytes) re-copies.
        let target = builtIn.appendingPathComponent("Kodak_Portra_160.cube")
        let original = try Data(contentsOf: target)
        // A different BYTE COUNT (the sentinel's discriminator).
        try (original + Data([0x0A])).write(to: target)
        let third = LutLibraryStore.seedBuiltIns(from: luts, into: root)
        XCTAssertEqual(third, 1, "content drift re-copies exactly that file")
    }
}
