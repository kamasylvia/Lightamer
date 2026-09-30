@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// LutLibraryRecursionTests (Plan M2-5-3 T2/T4, M2GRADE-05/06) — the
/// registry key upgrade to root-relative POSIX paths (KD-1) and the
/// recursive rescan (KD-2): deep-tree collection, hidden-directory
/// skipping, legacy registry tolerance + migration idempotency, the
/// legacy-reference tail-segment resolution fallback (ambiguous =
/// degrade), the panel tree grouping face, the rescan scale sanity
/// (KD-2 soft cap) and — T4 — the configurable root (KD-3: per-root
/// registries, bad-root tolerance, cross-root degrade).
final class LutLibraryRecursionTests: XCTestCase {

    private var workDir: URL!
    private var libraryDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lut-recursion-\(UUID().uuidString)", isDirectory: true)
        libraryDir = workDir.appendingPathComponent("LUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private let cube2 = """
        TITLE "T"
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """

    private func write(_ relative: String, _ text: String = "") throws -> URL {
        let url = libraryDir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = text.isEmpty ? cube2 : text
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - KD-2 recursive collection

    func testDeepTreeIsCollectedRecursively() throws {
        try write("root.cube")
        try write("BuiltIn/Fuji_Deep.cube")
        try write("BuiltIn/Weddings/Kodak_Deep.cube")
        try write("Travel/2024/Summer/Beach.cube")
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertEqual(
            Set(store.installedNames),
            ["BuiltIn/Fuji_Deep.cube", "BuiltIn/Weddings/Kodak_Deep.cube",
                "Travel/2024/Summer/Beach.cube", "root.cube"])
        // Every depth resolves through the module face.
        XCTAssertNotNil(store.lut(named: "BuiltIn/Weddings/Kodak_Deep.cube"))
        XCTAssertNotNil(store.lut(named: "Travel/2024/Summer/Beach.cube"))
        // Subdirectory bookkeeping feeds the panel grouping.
        XCTAssertEqual(store.entry(named: "BuiltIn/Fuji_Deep.cube")?.subdirectory, "BuiltIn")
        XCTAssertEqual(
            store.entry(named: "BuiltIn/Weddings/Kodak_Deep.cube")?.subdirectory,
            "BuiltIn/Weddings")
        XCTAssertNil(store.entry(named: "root.cube")?.subdirectory)
    }

    func testHiddenDirectoriesAndNonCubeFilesAreSkipped() throws {
        try write("visible.cube")
        try write(".hidden/secret.cube")
        try write(".buried.cube")
        try write("notes.txt")
        // registry.json written by hand must never be adopted as a table.
        try "{\"legacy.cube\":{}}" .write(
            to: libraryDir.appendingPathComponent("registry.json"), atomically: true,
            encoding: .utf8)
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertEqual(store.installedNames, ["visible.cube"])
    }

    func testRescanPicksUpExternallyPlacedSubdirectory() throws {
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertTrue(store.installedNames.isEmpty)
        // Manual placement (the checker m4 walkthrough): drop a .cube into
        // a NEW subdirectory with the Finder, then rescan.
        try write("NewPacks/Late.cube")
        store.rescan()
        XCTAssertEqual(store.installedNames, ["NewPacks/Late.cube"])
        // Deleting the directory + rescan drops the row (self-heal).
        try FileManager.default.removeItem(at: libraryDir.appendingPathComponent("NewPacks"))
        store.rescan()
        XCTAssertTrue(store.installedNames.isEmpty)
    }

    // MARK: - KD-2 scale sanity (soft cap, DEBUG)

    func testLargeTreeRescanStaysWithinSoftCap() throws {
        // 500 files across a 3-level tree — guards against accidental
        // O(n²) adoption walks (soft cap 5s; not a performance gate).
        for index in 0..<500 {
            try write("PackA/Sub\(index % 10)/Deep\(index % 5)/Lut\(index).cube")
        }
        let start = Date()
        let store = LutLibraryStore(directory: libraryDir)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(store.installedNames.count, 500)
        XCTAssertLessThan(elapsed, 5.0, "rescan soft cap (KD-2)")
    }

    // MARK: - KD-1 legacy registry tolerance + migration idempotency

    private func legacyRegistryFixture() throws -> Data {
        let data = try Data(contentsOf: try write("Old_Lut.cube"))
        let hash = String(StableHash.hash(data))
        // The pre-upgrade shape: flat file-name keys, no relativePath /
        // subdirectory fields (the synthesized decode reads them as nil).
        let json = """
            {"Old_Lut.cube": {"name": "Old_Lut.cube", "hash": "\(hash)",
              "is1D": false, "size": 2, "title": "Old"}}
            """
        return Data(json.utf8)
    }

    func testLegacyRegistryDecodesAndMigratesIdempotently() throws {
        try legacyRegistryFixture().write(
            to: libraryDir.appendingPathComponent("registry.json"), options: .atomic)
        let store = LutLibraryStore(directory: libraryDir)
        // The legacy row survives and gains the derived fields.
        let entry = store.entry(named: "Old_Lut.cube")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.relativePath, "Old_Lut.cube")
        XCTAssertNil(entry?.subdirectory)
        // First rescan persisted the upgraded form.
        let upgraded = try Data(contentsOf: libraryDir.appendingPathComponent("registry.json"))
        XCTAssertTrue(
            String(decoding: upgraded, as: UTF8.self).contains("relativePath"),
            "migration writes the upgraded registry")
        // Second store: keys stable (idempotent — no re-derivation drift).
        let second = LutLibraryStore(directory: libraryDir)
        XCTAssertEqual(second.installedNames, ["Old_Lut.cube"])
        XCTAssertEqual(second.entry(named: "Old_Lut.cube")?.relativePath, "Old_Lut.cube")
    }

    // MARK: - KD-1 legacy reference resolution

    func testLegacyBareNameReferenceResolvesThroughTailFallback() throws {
        try write("Packs/FilmLook.cube")
        let store = LutLibraryStore(directory: libraryDir)
        // A legacy document references the bare file name; resolution
        // finds the unique tail-segment match.
        XCTAssertNotNil(store.lut(named: "FilmLook.cube"))
        XCTAssertEqual(store.displayKey(for: "FilmLook.cube"), "Packs/FilmLook.cube")
        XCTAssertFalse(store.isMissing("FilmLook.cube"))
        XCTAssertEqual(store.entry(named: "FilmLook.cube")?.relativePath, "Packs/FilmLook.cube")
    }

    func testAmbiguousBareNameDegrades() throws {
        try write("PacksOne/Dup.cube")
        try write("PacksTwo/Dup.cube")
        let store = LutLibraryStore(directory: libraryDir)
        // Two same-name tables: the tail fallback is ambiguous → nil (the
        // degrade path), while the exact relative paths resolve uniquely.
        XCTAssertNil(store.lut(named: "Dup.cube"))
        XCTAssertNil(store.displayKey(for: "Dup.cube"))
        XCTAssertTrue(store.isMissing("Dup.cube"))
        XCTAssertNotNil(store.lut(named: "PacksOne/Dup.cube"))
        XCTAssertNotNil(store.lut(named: "PacksTwo/Dup.cube"))
    }

    func testMissingReferenceDegradesTyped() throws {
        try write("present.cube")
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertNil(store.lut(named: "vanished.cube"))
        XCTAssertTrue(store.isMissing("vanished.cube"))
        XCTAssertFalse(store.isMissing(nil))
    }

    // MARK: - Same-name coexistence + tree grouping face

    func testSameNameRowsCoexistAndGroupFaceLeadsWithBuiltIn() throws {
        try write("BuiltIn/Film.cube")
        try write("Mine/Film.cube")
        try write("Zed/Alone.cube")
        try write("AtRoot.cube")
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertEqual(store.installedNames.count, 4)
        let groups = store.libraryGroups()
        // Root group first, BuiltIn leads the subdirectories, rest sorted.
        XCTAssertEqual(groups.map(\.path), ["", "BuiltIn", "Mine", "Zed"])
        XCTAssertEqual(groups[0].keys, ["AtRoot.cube"])
        XCTAssertEqual(groups[1].keys, ["BuiltIn/Film.cube"])
        XCTAssertEqual(groups[2].keys, ["Mine/Film.cube"])
        XCTAssertEqual(groups[3].keys, ["Zed/Alone.cube"])
    }
}
