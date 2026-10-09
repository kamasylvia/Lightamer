import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ImportCategoryTests (Plan M4-1-02 T5, KD-4 — LIB bundle) — the import
// category mask:
//
//   • the three-order discipline is LOAD-BEARING and untouched: ① hidden
//     → ② sidecar → ③ the family mask — a mask can never re-admit a
//     sidecar or a hidden file;
//   • ③: tif/tiff ride the HARDCODED family (never the RAW whitelist —
//     the rawExtensions semantics stay byte-identical), a masked-off
//     family rejects `.excludedType`, everything else stays
//     `.extensionNotWhitelisted`;
//   • the defaults face: 缺键 = 双开 / 域外 = 缺席 = 双开 / set+reset
//     round-trip / the rawExtensions keys never cross.
// ─────────────────────────────────────────────────────────────────────────────

final class ImportCategoryTests: XCTestCase {

    private var tempDirectory: URL!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("import-category-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        defaultsSuiteName = "import-category-tests-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func url(_ name: String) -> URL {
        tempDirectory.appendingPathComponent(name)
    }

    private func reasonMap(
        _ names: [String], categories: ImportCategory,
        whitelist: Set<String> = LibrarySchema.defaultRawExtensions
    ) -> [String: ImportRejection.Reason?] {
        let selection = ImportFilter.select(
            names.map(url), whitelist: whitelist, categories: categories)
        var map: [String: ImportRejection.Reason?] = [:]
        for rejection in selection.rejected {
            map[rejection.url.lastPathComponent] = rejection.reason
        }
        for accepted in selection.accepted {
            map[accepted.lastPathComponent] = nil
        }
        return map
    }

    private func makeDefaults() -> ImportDefaults {
        ImportDefaults(defaultsSuiteName: defaultsSuiteName)
    }

    // MARK: - ③: the mask over the two families

    func testBothOnAcceptsRawAndTiff() {
        let map = reasonMap(
            ["a.arw", "b.tif", "c.TIFF"], categories: .all)
        XCTAssertNil(map["a.arw"])
        XCTAssertNil(map["b.tif"])
        XCTAssertNil(map["c.TIFF"], "case-insensitive exact match")
    }

    func testTiffMaskedOffRejectsExcludedType() {
        let map = reasonMap(["b.tif", "c.tiff"], categories: .raw)
        XCTAssertEqual(map["b.tif"], .excludedType)
        XCTAssertEqual(map["c.tiff"], .excludedType)
    }

    func testRawMaskedOffRejectsExcludedType() {
        let map = reasonMap(["a.arw", "a.nef"], categories: .tiff)
        XCTAssertEqual(map["a.arw"], .excludedType)
        XCTAssertEqual(map["a.nef"], .excludedType)
    }

    func testBothOffRejectsEveryFamilyAsExcludedType() {
        let map = reasonMap(
            ["a.arw", "b.tif"], categories: ImportCategory(rawValue: 0))
        XCTAssertEqual(map["a.arw"], .excludedType)
        XCTAssertEqual(map["b.tif"], .excludedType)
    }

    func testUnknownFormatsStayExtensionNotWhitelisted() {
        // The excludedType account NEVER absorbs unrelated formats.
        let map = reasonMap(
            ["x.jpeg", "y.png", "noext"], categories: .all)
        XCTAssertEqual(map["x.jpeg"], .extensionNotWhitelisted)
        XCTAssertEqual(map["y.png"], .extensionNotWhitelisted)
        XCTAssertEqual(map["noext"], .extensionNotWhitelisted)
    }

    // MARK: - The order discipline (①② outrank ③)

    func testHiddenStillOutranksTheMask() {
        let map = reasonMap([".hidden.tif", ".hidden.arw"], categories: .all)
        XCTAssertEqual(map[".hidden.tif"], .hidden)
        XCTAssertEqual(map[".hidden.arw"], .hidden)
    }

    func testSidecarStillOutranksTheMask() {
        // `photo.tif.xmp` — the LAST extension hits the sidecar table
        // before the family mask ever sees "xmp".
        let map = reasonMap(["photo.tif.xmp"], categories: .all)
        XCTAssertEqual(map["photo.tif.xmp"], .sidecar)
    }

    func testDoubleExtensionTiffDisguisePassesByDesign() {
        // raw.xmp.tif — the last-extension-exact contract (the KD-1
        // documented semantics, tiff flavor).
        let map = reasonMap(["raw.xmp.tif"], categories: .all)
        XCTAssertNil(map["raw.xmp.tif"])
    }

    // MARK: - The two keys are orthogonal (OQ-5)

    func testTiffFamilyNeverRidesTheRawWhitelist() {
        // A whitelist WITHOUT tif/tiff still accepts .tif when the mask is
        // on — the family is hardcoded, the whitelist is RAW-only.
        let map = reasonMap(["b.tif"], categories: .all, whitelist: ["arw"])
        XCTAssertNil(map["b.tif"])
        // Conversely: putting "tif" INTO the whitelist never gates it —
        // the family branch wins first.
        let map2 = reasonMap(["b.tif"], categories: .raw, whitelist: ["tif"])
        XCTAssertEqual(map2["b.tif"], .excludedType)
    }

    func testRawExtensionsKeyUnchangedByCategoryFace() {
        let defaults = makeDefaults()
        defaults.setCategories(.tiff)
        XCTAssertNil(
            UserDefaults(suiteName: defaultsSuiteName)?
                .stringArray(forKey: ImportDefaults.rawExtensionsKey),
            "the category write never touches the RAW whitelist key")
    }

    // MARK: - The defaults face (缺键/域外 = 双开)

    func testAbsentKeyResolvesDoubleOn() {
        XCTAssertNil(
            UserDefaults(suiteName: defaultsSuiteName)?
                .object(forKey: ImportDefaults.categoriesKey))
        XCTAssertEqual(makeDefaults().resolvedCategories(), .all)
    }

    func testOutOfDomainValueResolvesDoubleOn() {
        let suite = UserDefaults(suiteName: defaultsSuiteName)!
        suite.set(7, forKey: ImportDefaults.categoriesKey)
        XCTAssertEqual(makeDefaults().resolvedCategories(), .all, "域外 = 缺席 = 双开")
        suite.set(-1, forKey: ImportDefaults.categoriesKey)
        XCTAssertEqual(makeDefaults().resolvedCategories(), .all)
    }

    func testStoredValueRoundTrips() {
        let defaults = makeDefaults()
        defaults.setCategories(.tiff)
        XCTAssertEqual(defaults.resolvedCategories(), .tiff)
        defaults.setCategories([])
        XCTAssertEqual(defaults.resolvedCategories(), ImportCategory(rawValue: 0))
        defaults.setCategories(.all)
        XCTAssertEqual(defaults.resolvedCategories(), .all)
    }

    func testResetClearsCategories() {
        let defaults = makeDefaults()
        defaults.setCategories(.raw)
        defaults.reset()
        XCTAssertNil(
            UserDefaults(suiteName: defaultsSuiteName)?
                .object(forKey: ImportDefaults.categoriesKey))
        XCTAssertEqual(makeDefaults().resolvedCategories(), .all)
    }

    // MARK: - The summary fold + the progress account

    func testSummaryAggregateSplitsTheThreeAccounts() {
        let summary = ImportTypeSummary.aggregate(
            [url("a.arw"), url("b.tif"), url("c.tiff"), url("x.jpeg")],
            whitelist: LibrarySchema.defaultRawExtensions)
        XCTAssertEqual(summary.rawCount, 1)
        XCTAssertEqual(summary.tiffCount, 2)
        XCTAssertEqual(summary.otherCount, 1)
        XCTAssertEqual(summary.allowedCount(categories: .all), 3)
        XCTAssertEqual(summary.allowedCount(categories: .raw), 1)
        XCTAssertEqual(summary.allowedCount(categories: .tiff), 2)
        XCTAssertEqual(summary.allowedCount(categories: []), 0)
    }

    func testChoiceCarriesCategoriesWithCodableTolerance() throws {
        // The choice round-trips the mask; a payload WITHOUT the key
        // decodes to .all (the additive tolerance).
        let choice = ImportModeChoice(mode: .copy, remember: true, categories: .tiff)
        let data = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(ImportModeChoice.self, from: data)
        XCTAssertEqual(decoded.categories, .tiff)

        let legacy = try JSONDecoder().decode(ImportModeChoice.self, from: Data(
            #"{"mode":"copy","remember":true}"#.utf8))
        XCTAssertEqual(legacy.categories, .all)
    }
}
