import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LabelingDefaultsTests (Plan M2-10-03 T2, AC #4/#5) — the labeling mode
// three-state + the remember write-back, the ImportDefaults twin:
//
//   • default = .ask (the safe default — labeling writes user-visible state)
//   • store/read round-trip over all three modes, isolated suite
//   • an unreadable stored value degrades to .ask (never crashes, never a
//     silent .never — the dark-switch posture)
//   • reset returns to .ask
//   • the controller intent mapping (.never → nil / .always → enqueueNow /
//     .ask → ask), the accept/decline write-back only on remember, and the
//     prompt publication lifecycle
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LabelingDefaultsTests: XCTestCase {

    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "labeling-defaults-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        suiteName = nil
        try await super.tearDown()
    }

    private func makePreferences() -> LabelingPreferences {
        LabelingPreferences(defaultsSuiteName: suiteName)
    }

    // MARK: - The preferences face (AC #5)

    func testDefaultModeIsAsk() {
        XCTAssertEqual(makePreferences().mode, .ask)
    }

    func testStoreAndReadRoundTripAllThreeModes() {
        let preferences = makePreferences()
        for mode in LabelingMode.allCases {
            preferences.store(mode)
            XCTAssertEqual(preferences.mode, mode)
        }
    }

    func testUnreadableStoredValueFallsBackToAsk() {
        let preferences = makePreferences()
        UserDefaults(suiteName: suiteName)?.set(
            "garbage", forKey: LabelingPreferences.modeKey)
        XCTAssertEqual(preferences.mode, .ask)
    }

    func testResetReturnsToAsk() {
        let preferences = makePreferences()
        preferences.store(.never)
        XCTAssertEqual(preferences.mode, .never)
        preferences.reset()
        XCTAssertEqual(preferences.mode, .ask)
    }

    func testSuitesAreIsolated() {
        let other = "labeling-defaults-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: other) }
        makePreferences().store(.never)
        // The other suite still reads the default.
        XCTAssertEqual(
            LabelingPreferences(defaultsSuiteName: other).mode, .ask)
    }

    // MARK: - The controller intent mapping (AC #4 three-state)

    func testIntentAskModeRoutesToPrompt() {
        let controller = LabelingPromptController(preferences: makePreferences())
        XCTAssertEqual(controller.intentForNewImages([1, 2]), .ask)
        // The intent alone does NOT publish — the tail presents one beat
        // after the progress close (the 弹询时机 pin).
        XCTAssertNil(controller.pendingPrompt)
        controller.presentPrompt([1, 2])
        XCTAssertEqual(controller.pendingPrompt?.imageCount, 2)
    }

    func testIntentAlwaysModeEnqueuesWithoutPrompt() {
        makePreferences().store(.always)
        let controller = LabelingPromptController(preferences: makePreferences())
        XCTAssertEqual(controller.intentForNewImages([1, 2]), .enqueueNow)
        XCTAssertNil(controller.pendingPrompt)
    }

    func testIntentNeverModeDoesNothing() {
        makePreferences().store(.never)
        let controller = LabelingPromptController(preferences: makePreferences())
        XCTAssertNil(controller.intentForNewImages([1, 2]))
        XCTAssertNil(controller.pendingPrompt)
    }

    // MARK: - Remember write-back (AC #5)

    func testAcceptWithRememberPersistsAlwaysAndReturnsIDs() {
        let preferences = makePreferences()
        let controller = LabelingPromptController(preferences: preferences)
        controller.presentPrompt([3, 4, 5])
        let ids = controller.accept(remember: true)
        XCTAssertEqual(ids, [3, 4, 5])
        XCTAssertNil(controller.pendingPrompt)
        XCTAssertEqual(preferences.mode, .always)
    }

    func testAcceptWithoutRememberPersistsNothing() {
        let preferences = makePreferences()
        let controller = LabelingPromptController(preferences: preferences)
        controller.presentPrompt([1])
        XCTAssertEqual(controller.accept(remember: false), [1])
        XCTAssertEqual(preferences.mode, .ask, "a single-shot answer persisted")
    }

    func testDeclineWithRememberPersistsNever() {
        let preferences = makePreferences()
        let controller = LabelingPromptController(preferences: preferences)
        controller.presentPrompt([1])
        controller.decline(remember: true)
        XCTAssertNil(controller.pendingPrompt)
        XCTAssertEqual(preferences.mode, .never)
    }

    func testDeclineWithoutRememberPersistsNothing() {
        let preferences = makePreferences()
        let controller = LabelingPromptController(preferences: preferences)
        controller.presentPrompt([1])
        controller.decline(remember: false)
        XCTAssertEqual(preferences.mode, .ask)
    }

    func testAcceptWithoutPendingPromptIsNil() {
        let controller = LabelingPromptController(preferences: makePreferences())
        XCTAssertNil(controller.accept(remember: true))
    }
}
