@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// LutLibraryRecursionTests (Plan M2-5-3 T2/T4/T5, M2GRADE-05/06) — the
/// registry key upgrade to root-relative POSIX paths (KD-1) and the
/// recursive rescan (KD-2): deep-tree collection, hidden-directory
/// skipping, legacy registry tolerance + migration idempotency, the
/// legacy-reference tail-segment resolution fallback (ambiguous =
/// degrade), the panel tree grouping face, the rescan scale sanity
/// (KD-2 soft cap), the configurable root (KD-3: per-root registries,
/// bad-root tolerance, cross-root degrade) and the built-in seeder's
/// idempotency face (KD-4).
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

    /// OQ-11 observation ③ — the TEN-THOUSAND-file probe behind
    /// `LIGHTAMER_PERF_PROBE=1` (skipped in the default suite: fixture
    /// creation dominates the runtime; the measurement is an observation
    /// record, not a gate). Run manually:
    ///   LIGHTAMER_PERF_PROBE=1 Scripts/test-direct.sh 'LutLibraryRecursionTests'
    func testRescanTenThousandFilesManualProbe() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "manual probe — set LIGHTAMER_PERF_PROBE=1 (OQ-11 observation ③)")
        for index in 0..<10_000 {
            try write("Pack/Sub\(index % 50)/Deep\(index % 5)/Lut\(index).cube")
        }
        let start = Date()
        let store = LutLibraryStore(directory: libraryDir)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(store.installedNames.count, 10_000)
        print("PERF-PROBE|LUT-RESCAN|10000 files|\(String(format: "%.2f", elapsed))s")
        // A second store on the warm registry (the panel-reopen shape).
        let warmStart = Date()
        _ = LutLibraryStore(directory: libraryDir)
        print(
            "PERF-PROBE|LUT-RESCAN-WARM|10000 files|"
                + String(format: "%.2f", Date().timeIntervalSince(warmStart)) + "s")
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

    // MARK: - KD-3 configurable root

    func testSwitchingRootBuildsAnIndependentRegistry() throws {
        try write("FirstRootOnly.cube")
        let secondRoot = workDir.appendingPathComponent("SecondRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        try cube2.write(
            to: secondRoot.appendingPathComponent("SecondRootOnly.cube"), atomically: true,
            encoding: .utf8)
        let first = LutLibraryStore(directory: libraryDir)
        let second = LutLibraryStore(directory: secondRoot)
        // Each root holds its own self-contained registry (KD-3).
        XCTAssertEqual(first.installedNames, ["FirstRootOnly.cube"])
        XCTAssertEqual(second.installedNames, ["SecondRootOnly.cube"])
        // The shared holder swaps atomically; the getter face serves the
        // new instance.
        let previous = LutLibraryStore.shared
        LutLibraryStore.replaceShared(second)
        XCTAssertTrue(LutLibraryStore.shared === second)
        // The forwarding resolver keeps resolution on the live instance.
        XCTAssertNotNil(LutLibraryStore.sharedResolver.lut(named: "SecondRootOnly.cube"))
        XCTAssertNil(LutLibraryStore.sharedResolver.lut(named: "FirstRootOnly.cube"))
        LutLibraryStore.replaceShared(previous)
        XCTAssertNil(LutLibraryStore.sharedResolver.lut(named: "SecondRootOnly.cube"))
    }

    func testBadRootDegradesWithoutCrashing() throws {
        // An unwritable/absent container (the L009 external-volume case):
        // the store degrades to an empty library — typed absence, no
        // throw, no crash.
        let badRoot = URL(fileURLWithPath: "/nonexistent-volume-\(UUID().uuidString)/LUTs")
        let store = LutLibraryStore(directory: badRoot)
        XCTAssertTrue(store.installedNames.isEmpty)
        XCTAssertTrue(store.isMissing("anything.cube"))
        // The reachability probe rejects it BEFORE a switch persists it.
        XCTAssertFalse(LutLibraryStore.validateRoot(badRoot))
    }

    func testValidateRootAcceptsARealDirectoryAndRejectsFiles() throws {
        // setUp creates the work dir only; the library dir appears on the
        // first write. Materialize it explicitly for the probe.
        try FileManager.default.createDirectory(
            at: libraryDir, withIntermediateDirectories: true)
        XCTAssertTrue(LutLibraryStore.validateRoot(libraryDir))
        let file = try write("plain.cube")
        XCTAssertFalse(LutLibraryStore.validateRoot(file), "files are not roots")
        XCTAssertFalse(
            LutLibraryStore.validateRoot(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
    }

    func testOldReferenceMissingUnderNewRootDegrades() throws {
        try write("OnlyHere.cube")
        let secondRoot = workDir.appendingPathComponent("OtherRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        // The reference rides a document across a root switch; the new
        // root has no such table → the degrade semantics (blit identity +
        // toast) — the store face reports the typed absence.
        let oldStore = LutLibraryStore(directory: libraryDir)
        XCTAssertNotNil(oldStore.lut(named: "OnlyHere.cube"))
        let newStore = LutLibraryStore(directory: secondRoot)
        XCTAssertNil(newStore.lut(named: "OnlyHere.cube"))
        XCTAssertTrue(newStore.isMissing("OnlyHere.cube"))
    }

    // MARK: - KD-4 seeder (store-level idempotency face; the packaged
    // folder itself is the APP-level BuiltInLutSetTests' subject)

    func testBuiltInSeederIsIdempotentByCountAndSize() throws {
        let source = workDir.appendingPathComponent("BundleLUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try cube2.write(to: source.appendingPathComponent("A.cube"), atomically: true,
                        encoding: .utf8)
        try cube2.write(to: source.appendingPathComponent("B.cube"), atomically: true,
                        encoding: .utf8)
        try "MIT".write(to: source.appendingPathComponent("LICENSE"), atomically: true,
                        encoding: .utf8)
        let root = workDir.appendingPathComponent("SeedRoot", isDirectory: true)
        // First launch: everything copies.
        let first = LutLibraryStore.seedBuiltIns(from: source, into: root)
        XCTAssertEqual(first, 3)
        let builtIn = root.appendingPathComponent("BuiltIn", isDirectory: true)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: builtIn, includingPropertiesForKeys: nil).count, 3)
        // Second launch: the count+size sentinel skips every file.
        let second = LutLibraryStore.seedBuiltIns(from: source, into: root)
        XCTAssertEqual(second, 0)
        // A drifted file (same name, different size) re-copies.
        try (cube2 + "\n").write(
            to: builtIn.appendingPathComponent("A.cube"), atomically: true, encoding: .utf8)
        let third = LutLibraryStore.seedBuiltIns(from: source, into: root)
        XCTAssertEqual(third, 1)
    }

    func testSeederOnlyRunsOnTheDefaultRootBranch() throws {
        // A custom directory never receives BuiltIn (user-data sovereignty,
        // KD-4) even when a bundle LUTs folder exists.
        try write("User.cube")
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: libraryDir.appendingPathComponent("BuiltIn").path),
            "custom roots are never seeded")
        XCTAssertEqual(store.installedNames, ["User.cube"])
    }
}
