@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// LutLibraryStoreTests (Plan 12-5 T5) — the user LUT library: import
/// (parse-validate + content dedup + copy), the name-reference semantics
/// (D-6: the library file name IS the reference — paths are dropped), the
/// rescan self-heal (YiyinFontStore three-part pattern), the missing-entry
/// degradation chain into the module (12-4 D10), and the develop-preset
/// container round-trip with a LUT instance (12-4 linkage).
final class LutLibraryStoreTests: XCTestCase {

    private var workDir: URL!
    private var libraryDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lut-store-tests-\(UUID().uuidString)", isDirectory: true)
        libraryDir = workDir.appendingPathComponent("LUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func writeSource(_ name: String, _ text: String) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let cube3D = """
        TITLE "Test Cube"
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

    private let cube1D = """
        LUT_1D_SIZE 3
        0.0 0.0 0.0
        0.5 0.5 0.5
        1.0 1.0 1.0
        """

    // MARK: - Import

    func testImport3D() throws {
        let store = LutLibraryStore(directory: libraryDir)
        let entry = try store.importLut(from: writeSource("test.cube", cube3D))
        XCTAssertEqual(entry.name, "test.cube")
        XCTAssertEqual(entry.is1D, false)
        XCTAssertEqual(entry.size, 2)
        XCTAssertEqual(entry.title, "Test Cube")
        XCTAssertEqual(store.installedNames, ["test.cube"])
        // The library file exists and the resolution face serves the table.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: libraryDir.appendingPathComponent("test.cube").path))
        let lut = store.lut(named: "test.cube")
        XCTAssertNotNil(lut)
        XCTAssertEqual(lut?.kind, .lut3d(size: 2))
    }

    func testImport1D() throws {
        let store = LutLibraryStore(directory: libraryDir)
        let entry = try store.importLut(from: writeSource("ramp.cube", cube1D))
        XCTAssertEqual(entry.is1D, true)
        XCTAssertEqual(entry.size, 3)
        XCTAssertEqual(store.lut(named: "ramp.cube")?.kind, .lut1d(size: 3))
    }

    func testImportRejectsNonCube() {
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertThrowsError(
            try store.importLut(from: try! writeSource("table.cube.txt", "LUT_3D_SIZE 2\n"))
        ) {
            XCTAssertEqual(
                $0 as? LutLibraryStore.LutError,
                .unsupportedFormat(name: "table.cube.txt"))
        }
    }

    func testImportRejectsCorruptCube() throws {
        let store = LutLibraryStore(directory: libraryDir)
        XCTAssertThrowsError(
            try store.importLut(from: writeSource("bad.cube", "LUT_3D_SIZE 2\nnot numbers\n"))
        ) {
            guard case .corruptCube(let name, _) = $0 as? LutLibraryStore.LutError else {
                return XCTFail("expected corruptCube")
            }
            XCTAssertEqual(name, "bad.cube")
        }
        // Nothing landed in the library.
        XCTAssertTrue(store.installedNames.isEmpty)
    }

    // MARK: - Content dedup (同哈希改名不重拷)

    func testContentDedupSameHashDifferentName() throws {
        let store = LutLibraryStore(directory: libraryDir)
        let first = try store.importLut(from: writeSource("one.cube", cube3D))
        // The same BYTES under a different name do not copy again.
        let second = try store.importLut(from: writeSource("two.cube", cube3D))
        XCTAssertEqual(second.name, "one.cube", "dedup folds the renamed import")
        XCTAssertEqual(second.hash, first.hash)
        XCTAssertEqual(store.installedNames, ["one.cube"])
    }

    func testSameNameNewContentUpdates() throws {
        let store = LutLibraryStore(directory: libraryDir)
        _ = try store.importLut(from: writeSource("lut.cube", cube3D))
        let before = store.entry(named: "lut.cube")
        // Overwrite the SOURCE with different content and re-import.
        let updated = try writeSource("lut.cube", cube1D)
        let after = try store.importLut(from: updated)
        XCTAssertNotEqual(after.hash, before?.hash)
        XCTAssertEqual(after.is1D, true, "the update re-parses the new shape")
    }

    // MARK: - Rescan self-heal (YiyinFontStore three-part pattern)

    func testRescanDropsVanishedFiles() throws {
        let store = LutLibraryStore(directory: libraryDir)
        _ = try store.importLut(from: writeSource("gone.cube", cube3D))
        // External deletion.
        try FileManager.default.removeItem(
            at: libraryDir.appendingPathComponent("gone.cube"))
        // A FRESH store (the startup rescan) drops the row.
        let rescanned = LutLibraryStore(directory: libraryDir)
        XCTAssertNil(rescanned.entry(named: "gone.cube"))
        XCTAssertTrue(rescanned.installedNames.isEmpty)
    }

    func testRescanAdoptsUnregisteredFiles() throws {
        let store = LutLibraryStore(directory: libraryDir)
        _ = try store.importLut(from: writeSource("registered.cube", cube3D))
        // An external drop-in (copy directly into the library, no import).
        let raw = """
            LUT_1D_SIZE 2
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        try raw.write(
            to: libraryDir.appendingPathComponent("dropin.cube"), atomically: true,
            encoding: .utf8)
        let rescanned = LutLibraryStore(directory: libraryDir)
        XCTAssertEqual(Set(rescanned.installedNames), ["registered.cube", "dropin.cube"])
        XCTAssertEqual(rescanned.lut(named: "dropin.cube")?.kind, .lut1d(size: 2))
    }

    // MARK: - Missing-entry degradation chain (12-4 D10)

    func testRemovalDegradesModuleToIdentity() async throws {
        let store = LutLibraryStore(directory: libraryDir)
        _ = try store.importLut(from: writeSource("doomed.cube", cube3D))
        XCTAssertTrue(store.lut(named: "doomed.cube") != nil)
        XCTAssertTrue(!store.isMissing("doomed.cube"))

        let module = Lut3dModule(resolver: store)
        var piece = IOPiece()
        module.commitParams(Lut3dModule.Params(lutName: "doomed.cube"), into: &piece)
        XCTAssertNotNil(piece.data, "present table commits uniforms")

        try store.removeLut(named: "doomed.cube")
        XCTAssertTrue(store.isMissing("doomed.cube"))
        module.commitParams(Lut3dModule.Params(lutName: "doomed.cube"), into: &piece)
        XCTAssertNil(piece.data, "removed table degrades to the blit identity")
        XCTAssertThrowsError(try store.removeLut(named: "doomed.cube")) {
            XCTAssertEqual($0 as? LutLibraryStore.LutError, .notFound(name: "doomed.cube"))
        }
    }

    // MARK: - Develop-preset linkage (12-4: the container carries the
    // LUT instance by NAME — save → apply round-trip with the library
    // present, degraded identity when it is gone)

    func testPresetContainerCarriesLutInstanceByName() throws {
        // The preset container serializes sidecar instance records — a LUT
        // instance is just another op whose paramsData pins lutName.
        let store = LutLibraryStore(directory: libraryDir)
        _ = try store.importLut(from: writeSource("preset.cube", cube3D))

        let module = Lut3dModule(resolver: store)
        var params = Lut3dModule.Params(
            lutName: "preset.cube", colorspace: .proPhotoLinear,
            interpolation: .trilinear)
        var piece = IOPiece()
        module.commitParams(params, into: &piece)

        // The params bytes round-trip through JSON (the preset container
        // shape) with the library name intact — cross-machine by name.
        let encoded = ParamsCoding.encode(params)
        let decoded = try JSONDecoder().decode(
            Lut3dModule.Params.self, from: encoded)
        XCTAssertEqual(decoded.lutName, "preset.cube")
        XCTAssertEqual(decoded.colorspace, .proPhotoLinear)
        XCTAssertEqual(decoded.interpolation, .trilinear)
        _ = params
    }
}
