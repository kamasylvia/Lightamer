import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// CleanTerminateSentinelTests (Plan M2-8-2 T4, KD-6; AC#8 — APP bundle) —
// the crash sentinel's pure-core truth table + the injected-suite storage
// round trip (the AppPreferences suite precedent — no .standard touch):
//
//   TRUTH TABLE: stored true = unclean (the last session never cleared);
//   stored false = clean; nil/missing key = first launch = silent.
//   ROUND TRIP: consumeAtLaunch reads-then-sets-true (the verdict rides
//   the PREVIOUS value); markClean writes false; the NEXT consume reads
//   clean; reset clears.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CleanTerminateSentinelTests: XCTestCase {

    private var suiteName: String!
    private var store: CleanTerminateSentinelStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "cleanTerminate-\(UUID().uuidString)"
        store = CleanTerminateSentinelStore(defaultsSuiteName: suiteName)
        store.reset()
    }

    override func tearDown() async throws {
        store.reset()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    // MARK: - The truth table (four cells)

    func testTruthTable() {
        // stored true → the last session never cleared = UNCLEAN.
        XCTAssertTrue(CleanTerminateSentinel.uncleanTermination(stored: true))
        // stored false → a clean termination.
        XCTAssertFalse(CleanTerminateSentinel.uncleanTermination(stored: false))
        // nil (the key absent) → first launch → silent.
        XCTAssertFalse(CleanTerminateSentinel.uncleanTermination(stored: nil))
        // The storage face of a missing key answers nil.
        XCTAssertNil(
            UserDefaults(suiteName: suiteName)!
                .object(forKey: CleanTerminateSentinel.key) as? Bool)
    }

    // MARK: - The injected-suite round trip

    func testStoreRoundTripThroughTheInjectedSuite() {
        // First launch: the key is missing → silent verdict; the session
        // marks itself RUNNING.
        XCTAssertFalse(store.consumeAtLaunch())
        XCTAssertEqual(
            UserDefaults(suiteName: suiteName)!
                .object(forKey: CleanTerminateSentinel.key) as? Bool, true,
            "the running mark is on disk")

        // A KILL (no markClean): the flag stays true — the NEXT launch
        // reads unclean, then re-marks running.
        XCTAssertTrue(store.consumeAtLaunch())

        // A CLEAN exit: the terminate leg clears after the flush; the next
        // launch reads clean.
        store.markClean()
        XCTAssertEqual(
            UserDefaults(suiteName: suiteName)!
                .object(forKey: CleanTerminateSentinel.key) as? Bool, false)
        XCTAssertFalse(store.consumeAtLaunch())

        // Reset = the first-launch state again.
        store.reset()
        XCTAssertNil(
            UserDefaults(suiteName: suiteName)!
                .object(forKey: CleanTerminateSentinel.key))
        XCTAssertFalse(store.consumeAtLaunch())
    }

    // MARK: - The toast copy + the registered key

    func testKeyAndToastCopyAreRegistered() {
        XCTAssertEqual(CleanTerminateSentinel.key, "app.cleanTerminate")
        XCTAssertFalse(CleanTerminateSentinel.toastCopy.isEmpty)
    }
}
