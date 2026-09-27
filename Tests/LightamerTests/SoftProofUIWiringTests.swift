@testable import Lightamer
@testable import LightamerCore
import XCTest

// Plan 13-2 T4 — the soft-proof UI state machine's routing suite (the same
// shape the capsule/View-menu produce), the recency memory's dedup + limit,
// the typed rejections, and the L025 zh/en key smoke for the softproof
// family. The proof PIPE behavior lives in SoftProofStageTests; here the
// contract is: every UI route funnels into PipeCoordinator.setSoftProof
// with the SAME value the state machine committed.
@MainActor
final class SoftProofUIWiringTests: XCTestCase {

    private var state: SoftProofState!
    private var coordinator: PipeCoordinator!

    private let adobeEntry = PrinterProfileCatalog.Entry(
        name: "AdobeRGB (1998)",
        url: URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/AdobeRGB1998.icc"))
    private let cmykEntry = PrinterProfileCatalog.Entry(
        name: "Generic CMYK",
        url: URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc"))

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "softproof.recent.names")
        state = SoftProofState()
        coordinator = PipeCoordinator()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "softproof.recent.names")
        try await super.tearDown()
    }

    func testToggleWithoutSelectionStaysOffWithRejection() {
        state.toggle(coordinator: coordinator)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(coordinator.softProofProfile)
        XCTAssertNotNil(state.lastRejection, "the no-printer toggle must reject with a message")
    }

    func testSelectActivatesProofAndRecordsRecency() {
        XCTAssertTrue(state.select(entry: adobeEntry, coordinator: coordinator))
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(coordinator.softProofProfile?.label, "AdobeRGB (1998)")
        XCTAssertEqual(state.recentNames.first, "AdobeRGB (1998)")
        XCTAssertNil(state.lastRejection)
    }

    func testSelectCMYKRejectedStateUntouched() {
        // Pre-arm a good selection; the CMYK rejection must not disturb it.
        XCTAssertTrue(state.select(entry: adobeEntry, coordinator: coordinator))
        let armedProfile = coordinator.softProofProfile

        XCTAssertFalse(state.select(entry: cmykEntry, coordinator: coordinator))
        XCTAssertNotNil(state.lastRejection, "the CMYK downgrade must surface a message")
        XCTAssertEqual(coordinator.softProofProfile, armedProfile,
                       "a rejected entry must not disturb the active proof")
        XCTAssertFalse(state.recentNames.contains("Generic CMYK"),
                       "a rejected entry must not enter the recency memory")
    }

    func testToggleOffClearsCoordinator() {
        state.select(entry: adobeEntry, coordinator: coordinator)
        state.toggle(coordinator: coordinator)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(coordinator.softProofProfile)
    }

    func testGamutCheckRecommitsWithNewIdentity() throws {
        state.select(entry: adobeEntry, coordinator: coordinator)
        let before = try XCTUnwrap(coordinator.softProofProfile).stableID
        state.setGamutCheck(true, coordinator: coordinator)
        let after = try XCTUnwrap(coordinator.softProofProfile)
        XCTAssertTrue(state.gamutCheck)
        XCTAssertNotEqual(after.stableID, before,
                          "the gamut flip must re-commit (the cache keys flip below the stage)")
        XCTAssertEqual(coordinator.softProofProfile?.gamutCheck, true)
    }

    func testRecentMemoryDedupAndLimit() throws {
        let names = ["A", "B", "C", "D", "E", "F"]
        let catalog = PrinterProfileCatalog.installedProfiles()
        // Recency records NAMES on successful selects; use the sRGB fixture
        // entries that actually exist in the catalog when available, else
        // synthesize through the state's own record path via selects.
        let entries = catalog.prefix(6)
        guard entries.count >= 2 else {
            throw XCTSkip("needs at least 2 installed profiles")
        }
        for entry in entries { state.select(entry: entry, coordinator: coordinator) }
        // Re-select the first entry: it moves to the front, no duplicate.
        let first = entries.first!
        state.select(entry: first, coordinator: coordinator)
        XCTAssertEqual(state.recentNames.first, first.name)
        XCTAssertEqual(state.recentNames.filter { $0 == first.name }.count, 1)
        XCTAssertLessThanOrEqual(
            state.recentNames.count, SoftProofState.recentLimit,
            "recency memory is capped (names counted: \(names.count) fixture)")
    }

    // MARK: - L025: the softproof key family carries en AND zh

    func testSoftproofKeysL025EnZhComplete() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let softproofKeys = strings.keys.filter { $0.hasPrefix("softproof_") }
        XCTAssertGreaterThanOrEqual(softproofKeys.count, 8, "the softproof family landed")
        for key in softproofKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in ["en", "zh"] {
                let face = try XCTUnwrap(
                    localizations[language] as? [String: Any], "\(key) missing \(language)")
                let unit = try XCTUnwrap(face["stringUnit"] as? [String: Any], key)
                XCTAssertEqual(unit["state"] as? String, "translated", key)
                XCTAssertFalse((unit["value"] as? String ?? "").isEmpty, "\(key) empty \(language)")
            }
        }
    }
}
