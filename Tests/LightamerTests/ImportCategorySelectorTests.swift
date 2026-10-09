import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ImportCategorySelectorTests (Plan M4-1-02 T5, KD-4 — APP bundle) — the
// import type selector's state face (the dialog renders the model; the
// tests drive the model directly — the makeRunAssembly paradigm):
//
//   • the checkbox write toggles the mask AND persists immediately
//     (记忆 = 选择即写 `library.import.categories`);
//   • the persisted mask re-seeds a fresh model (the next dialog reads
//     it back);
//   • the import gate = 扫描完成 && 允许数 > 0 (unscanned = disabled;
//     both families off = disabled; the mask slicing the counts);
//   • the counts ride ImportTypeSummary.aggregate (the one scan fold).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ImportCategorySelectorTests: XCTestCase {

    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        defaultsSuiteName = "import-selector-tests-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try await super.tearDown()
    }

    private func makeModel() -> ImportTypeSelectionModel {
        ImportTypeSelectionModel(
            defaults: ImportDefaults(defaultsSuiteName: defaultsSuiteName))
    }

    func testDefaultsSeedDoubleOnAndUnscannedGateClosed() {
        let model = makeModel()
        XCTAssertTrue(model.isOn(.raw), "缺键 = 双开")
        XCTAssertTrue(model.isOn(.tiff))
        XCTAssertFalse(model.scanned, "the scan has not completed")
        XCTAssertFalse(
            model.importEnabled,
            "the gate stays closed until the scan completes")
    }

    func testScanCompletesAndOpensTheGate() {
        let model = makeModel()
        model.scanCompleted(ImportTypeSummary(
            rawCount: 3, tiffCount: 2, otherCount: 5))
        XCTAssertTrue(model.scanned)
        XCTAssertTrue(model.importEnabled, "allowed = 5 > 0")
    }

    func testCheckboxTogglePersistsImmediately() {
        let model = makeModel()
        model.setFamily(.raw, on: false)
        XCTAssertFalse(model.isOn(.raw))
        // The write landed in defaults — a FRESH model reads it back.
        XCTAssertEqual(
            ImportTypeSelectionModel(
                defaults: ImportDefaults(defaultsSuiteName: defaultsSuiteName)
            ).categories, .tiff)
        model.setFamily(.tiff, on: false)
        XCTAssertFalse(model.isOn(.tiff))
        XCTAssertEqual(
            ImportTypeSelectionModel(
                defaults: ImportDefaults(defaultsSuiteName: defaultsSuiteName)
            ).categories, ImportCategory(rawValue: 0))
    }

    func testGateFollowsTheMaskAgainstTheCounts() {
        let model = makeModel()
        model.scanCompleted(ImportTypeSummary(
            rawCount: 0, tiffCount: 2, otherCount: 9))
        XCTAssertTrue(model.importEnabled, "tiff allowed")
        model.setFamily(.tiff, on: false)
        XCTAssertFalse(
            model.importEnabled,
            "no RAW present + tiff off → nothing to import")
        model.setFamily(.raw, on: true)
        XCTAssertFalse(
            model.importEnabled,
            "raw on but zero raw files → still nothing")
    }

    func testBothOffBlocksTheGate() {
        let model = makeModel()
        model.scanCompleted(ImportTypeSummary(
            rawCount: 3, tiffCount: 2, otherCount: 0))
        model.setFamily(.raw, on: false)
        model.setFamily(.tiff, on: false)
        XCTAssertFalse(model.importEnabled, "允许数 = 0 → the gate stays closed")
    }
}
