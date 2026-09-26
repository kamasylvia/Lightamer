import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-4 T1 — the PresetsStore suite (the YiyinFontStore 三拆 mirror,
// SmartAlbumStore twin):
//
//   • round-trip: create → a SECOND store over the same directory rescans
//     the SAME file set (one preset = one file; uuid-stem ids stable)
//   • startup self-heal: a corrupt file is SKIPPED (标坏不崩 — typed
//     degrade, never a crash, never a deletion), the readable set loads
//   • forward-compat degradation: a future-schema file is TOLERATED; a
//     develop file carrying an export recipe lands on the skipped list
//     (the typed mutual-exclusion violation) while its NEIGHBORS stay
//     usable
//   • PRES-02: export/import = FILE COPY with ZERO format conversion
//     (bytes out == bytes in; a foreign file re-imports byte-equal under a
//     fresh stem); typed errors on corrupt/unreadable imports
//   • the L009 no-tmp-leftovers assertion (the same-directory promotion
//     sweeps its own artifacts)
// ─────────────────────────────────────────────────────────────────────────────

final class PresetsStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("presets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A deterministic develop instance (the container golden's twin).
    private func goldenInstance() -> ModuleInstance {
        ModuleInstance(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            opName: "testgain",
            multiPriority: 0,
            multiName: "",
            iopOrder: 21.5,
            version: 1,
            enabled: true,
            paramsData: Data("abc".utf8),
            paramsHash: 1_234_567_890_123_456_789)
    }

    private func developRecipe() -> ExportRecipe {
        [ExportVariant(format: .jpeg(quality: 0.9), colorSpace: .sRGB)]
    }

    private func writeFile(_ name: String, _ json: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(json.utf8).write(to: url)
        return url
    }

    private func goodDevelopJSON(name: String) -> String {
        """
        {
          "appVersion" : "test",
          "category" : "Tone",
          "createdAt" : 1770000000,
          "instances" : [
            {
              "enabled" : true,
              "id" : "11111111-2222-3333-4444-555555555555",
              "iopOrder" : 21.5,
              "multiName" : "",
              "multiPriority" : 0,
              "opName" : "testgain",
              "paramsData" : "YWJj",
              "paramsHash" : "1234567890123456789",
              "version" : 1
            }
          ],
          "kind" : "develop",
          "name" : "\(name)",
          "schemaVersion" : 1
        }
        """
    }

    // MARK: - Round-trip (one preset = one file; ids stable)

    func testCreateRoundTripAndSecondStoreRescan() throws {
        let store = PresetsStore(directory: directory)
        let stored = try store.create(
            name: "  Warm Film  ", kind: .develop, category: "Tone",
            instances: [goldenInstance()])

        XCTAssertEqual(stored.document.name, "Warm Film")
        XCTAssertTrue(UUID(uuidString: stored.id) != nil, "the id is the uuid stem")
        // Exactly ONE file in the directory, named <id>.lightamer-preset,
        // with NO tmp leftovers (the L009 promotion swept itself).
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(
            files.map(\.lastPathComponent),
            [stored.id + ".lightamer-preset"])

        // A SECOND store over the SAME directory rescans the SAME set.
        let second = PresetsStore(directory: directory)
        let rows = second.presets()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, stored.id)
        XCTAssertEqual(rows[0].document, stored.document,
                       "documents round-trip byte-equal through the file")
        XCTAssertTrue(second.skippedFiles.isEmpty)
    }

    func testExportKindRoundTrip() throws {
        let store = PresetsStore(directory: directory)
        let stored = try store.create(
            name: "Journal Set", kind: .export,
            exportRecipe: developRecipe())
        XCTAssertEqual(stored.document.kind, .export)
        XCTAssertEqual(stored.document.exportRecipe, developRecipe())

        let second = PresetsStore(directory: directory)
        XCTAssertEqual(second.presets(kind: .export).count, 1)
        XCTAssertEqual(second.presets(kind: .develop).count, 0)
        XCTAssertEqual(
            second.preset(id: stored.id)?.document.exportRecipe,
            developRecipe())
    }

    // MARK: - The self-heal (corrupt skipped, never deleted, never a crash)

    func testCorruptFileIsSkippedNeverDeletedAndNeighborsSurvive() throws {
        let store = PresetsStore(directory: directory)
        let good = try store.create(
            name: "Neighbor", kind: .develop,
            instances: [goldenInstance()])
        _ = try writeFile(
            "broken.lightamer-preset", "{ this is not json ]")

        let healed = PresetsStore(directory: directory)
        XCTAssertEqual(healed.skippedFiles, ["broken.lightamer-preset"])
        XCTAssertEqual(healed.presets().map(\.id), [good.id],
                       "the readable neighbor still loads")

        // 标坏不崩: the corrupt file was NEVER deleted by the scanner.
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .map(\.lastPathComponent)),
            Set(["broken.lightamer-preset", good.id + ".lightamer-preset"]))

        // The user (or a future reader) deletes the corrupt file — the
        // rescan reconciles to a clean registry.
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("broken.lightamer-preset"))
        healed.rescan()
        XCTAssertTrue(healed.skippedFiles.isEmpty)
        XCTAssertEqual(healed.presets().count, 1)
    }

    // MARK: - Forward-compat degradation

    func testFutureSchemaFileIsToleratedNotSkipped() throws {
        _ = try writeFile("future.lightamer-preset", """
        {
          "appVersion" : "future",
          "createdAt" : 1770000000,
          "instances" : [],
          "kind" : "develop",
          "name" : "From The Future",
          "schemaVersion" : 2,
          "futureOnly" : true
        }
        """)
        let store = PresetsStore(directory: directory)
        XCTAssertTrue(store.skippedFiles.isEmpty)
        XCTAssertEqual(store.presets().first?.document.name, "From The Future")
        XCTAssertEqual(store.presets().first?.document.schemaVersion, 2)
    }

    func testDevelopCarryingRecipeSkipsWhileNeighborsStayUsable() throws {
        // The pinned mutual-exclusion violation, as an ON-DISK file.
        _ = try writeFile("mismatch.lightamer-preset", """
        {
          "appVersion" : "test",
          "createdAt" : 1770000000,
          "exportRecipe" : [
            {"format": {"jpeg": {"quality": 0.9}}, "colorSpace": "sRGB", "sizing": {"mode": {"original": {}}, "dpi": 300}, "yiyin": false}
          ],
          "instances" : [],
          "kind" : "develop",
          "name" : "Mismatch",
          "schemaVersion" : 1
        }
        """)
        _ = try writeFile("good.lightamer-preset", goodDevelopJSON(name: "Good"))

        let store = PresetsStore(directory: directory)
        XCTAssertEqual(store.skippedFiles, ["mismatch.lightamer-preset"])
        XCTAssertEqual(store.presets().map(\.document.name), ["Good"])

        // The load face throws the SAME typed error for the skipped file
        // (never a silent fallback).
        XCTAssertThrowsError(
            try store.loadDocument(id: "mismatch")
        ) { error in
            XCTAssertEqual(
                error as? PresetError,
                .invalidPreset(.developCarriesExportRecipe(name: "Mismatch")))
        }
        // The good file loads fresh from DISK (the apply leg's truth read).
        let loaded = try store.loadDocument(id: "good")
        XCTAssertEqual(loaded.name, "Good")
        XCTAssertEqual(loaded.instances.count, 1)
    }

    // MARK: - The write face (typed errors)

    func testRenameAndCategoryPersistThroughTheFile() throws {
        let store = PresetsStore(directory: directory)
        let stored = try store.create(
            name: "Draft", kind: .develop, instances: [goldenInstance()])

        try store.rename(id: stored.id, to: "Final")
        try store.setCategory(id: stored.id, category: "  Blacks  ")

        // Fresh from disk.
        let loaded = try store.loadDocument(id: stored.id)
        XCTAssertEqual(loaded.name, "Final")
        XCTAssertEqual(loaded.category, "Blacks")

        // The registry row refreshed too; category back to nil via empty.
        try store.setCategory(id: stored.id, category: "   ")
        XCTAssertNil(try store.loadDocument(id: stored.id).category)

        // Typed rejections.
        XCTAssertThrowsError(try store.rename(id: stored.id, to: "   ")) {
            error in XCTAssertEqual(error as? PresetError, .emptyName)
        }
        XCTAssertThrowsError(try store.rename(id: "nope", to: "X")) { error in
            XCTAssertEqual(error as? PresetError, .notFound(id: "nope"))
        }
    }

    func testCreateTypedRejections() throws {
        let store = PresetsStore(directory: directory)
        XCTAssertThrowsError(
            try store.create(name: "  ", kind: .develop)
        ) { error in
            XCTAssertEqual(error as? PresetError, .emptyName)
        }
        // An export preset WITHOUT a recipe is meaningless — typed reject.
        XCTAssertThrowsError(
            try store.create(name: "Empty Export", kind: .export)
        ) { error in
            XCTAssertEqual(
                error as? PresetError, .emptyExportRecipe(name: "Empty Export"))
        }
        XCTAssertTrue(store.presets().isEmpty, "no file was written on rejection")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count, 0)
    }

    func testRemoveGoesFileFirstThenRegistry() throws {
        let store = PresetsStore(directory: directory)
        let stored = try store.create(
            name: "Gone Soon", kind: .develop, instances: [goldenInstance()])
        let file = directory.appendingPathComponent(
            stored.id + ".lightamer-preset")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        try store.remove(id: stored.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(store.presets().isEmpty)
        XCTAssertThrowsError(try store.remove(id: stored.id)) { error in
            XCTAssertEqual(error as? PresetError, .notFound(id: stored.id))
        }
    }

    // MARK: - PRES-02: import/export (file copy, zero conversion)

    func testExportImportRoundTripIsByteIdenticalWithFreshStem() throws {
        let store = PresetsStore(directory: directory)
        let original = try store.create(
            name: "Traveler", kind: .develop, category: "Tone",
            instances: [goldenInstance()])
        let libraryFile = directory.appendingPathComponent(
            original.id + ".lightamer-preset")

        // EXPORT: the bytes out are the library file's bytes VERBATIM.
        let exportedURL = directory.appendingPathComponent("share-out.lightamer-preset")
        try store.exportFile(id: original.id, to: exportedURL)
        XCTAssertEqual(
            try Data(contentsOf: exportedURL),
            try Data(contentsOf: libraryFile),
            "zero format conversion — the on-disk format IS the interchange format")

        // IMPORT into a SECOND store (the receiving machine's shape): the
        // document round-trips byte-equal under a FRESH stem.
        let receiver = PresetsStore(directory: directory)
        try receiver.remove(id: original.id)
        let imported = try receiver.importPreset(from: exportedURL)
        XCTAssertNotEqual(imported.id, original.id, "imports mint a fresh stem")
        XCTAssertEqual(imported.document, original.document)

        // The exported file RE-IMPORTS AS-IS even after the original is
        // gone (the PRES-02 no-conversion contract end-to-end).
        XCTAssertEqual(
            try receiver.loadDocument(id: imported.id).instances.count, 1)
    }

    func testImportTypedErrors() throws {
        let store = PresetsStore(directory: directory)
        // Corrupt bytes.
        let corrupt = try writeFile(
            "in.lightamer-preset", "{ not a preset ]")
        XCTAssertThrowsError(try store.importPreset(from: corrupt)) { error in
            XCTAssertEqual(
                error as? PresetError, .corruptPreset(name: "in.lightamer-preset"))
        }
        // Missing source.
        XCTAssertThrowsError(
            try store.importPreset(
                from: directory.appendingPathComponent("absent.lightamer-preset"))
        ) { error in
            XCTAssertEqual(
                error as? PresetError,
                .unreadableFile(name: "absent.lightamer-preset"))
        }
        // A mutual-exclusion-violating foreign file is rejected TYPED.
        let mismatch = try writeFile("bad.lightamer-preset", """
        {
          "appVersion" : "test",
          "createdAt" : 1770000000,
          "exportRecipe" : [
            {"format": {"jpeg": {"quality": 0.9}}, "colorSpace": "sRGB", "sizing": {"mode": {"original": {}}, "dpi": 300}, "yiyin": false}
          ],
          "instances" : [],
          "kind" : "develop",
          "name" : "Bad",
          "schemaVersion" : 1
        }
        """)
        XCTAssertThrowsError(try store.importPreset(from: mismatch)) { error in
            XCTAssertEqual(
                error as? PresetError,
                .invalidPreset(.developCarriesExportRecipe(name: "Bad")))
        }
        XCTAssertTrue(store.presets().isEmpty, "nothing was registered")
    }

    func testExportFileOfUnknownIdIsTyped() throws {
        let store = PresetsStore(directory: directory)
        XCTAssertThrowsError(
            try store.exportFile(
                id: "ghost", to: directory.appendingPathComponent("x.out"))
        ) { error in
            XCTAssertEqual(error as? PresetError, .notFound(id: "ghost"))
        }
    }

    // MARK: - The T4 export-recipe load gate (validate 降级向量)

    func testInvalidExportRecipeFileIsSkippedTypedAndNeighborsSurvive() throws {
        // An export preset whose recipe fails `ExportVariant.validate()`
        // (quality 1.5 — outside the 0...1 domain): a BAD PRESET, degraded
        // at load exactly like a corrupt file.
        _ = try writeFile("badrecipe.lightamer-preset", """
        {
          "appVersion" : "test",
          "createdAt" : 1770000000,
          "exportRecipe" : [
            {"format": {"jpeg": {"quality": 1.5}}, "colorSpace": "sRGB", "sizing": {"mode": {"original": {}}, "dpi": 300}, "yiyin": false}
          ],
          "instances" : [],
          "kind" : "export",
          "name" : "Bad Recipe",
          "schemaVersion" : 1
        }
        """)
        _ = try writeFile("goodexp.lightamer-preset", """
        {
          "appVersion" : "test",
          "createdAt" : 1770000000,
          "exportRecipe" : [
            {"format": {"jpeg": {"quality": 0.9}}, "colorSpace": "sRGB", "sizing": {"mode": {"original": {}}, "dpi": 300}, "yiyin": false}
          ],
          "instances" : [],
          "kind" : "export",
          "name" : "Good Recipe",
          "schemaVersion" : 1
        }
        """)

        let store = PresetsStore(directory: directory)
        // 标坏不崩: the bad file is on the skipped list; the good export
        // preset stays usable.
        XCTAssertEqual(store.skippedFiles, ["badrecipe.lightamer-preset"])
        XCTAssertEqual(store.presets().map(\.document.name), ["Good Recipe"])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: "") , "sanity")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("badrecipe.lightamer-preset").path),
            "the bad file was never deleted")

        // The load face throws the SAME typed error (never a silent
        // fallback for the apply/fill faces).
        XCTAssertThrowsError(try store.loadDocument(id: "badrecipe")) { error in
            XCTAssertEqual(
                error as? PresetError,
                .invalidExportRecipe(name: "badrecipe.lightamer-preset"))
        }
        // The good one loads and its recipe validates.
        let good = try store.loadDocument(id: "goodexp")
        XCTAssertNoThrow(try good.exportRecipe?.first?.validate())
    }
}
