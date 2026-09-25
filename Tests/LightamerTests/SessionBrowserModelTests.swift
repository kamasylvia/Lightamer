import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-03 T1 — SessionBrowserModel: the collection row projection +
// selection data-face + progressive-placeholder ingest suite.
//
// The double-tier ruling input (has_edits) rides the projection; the
// ⌘-toggle / ⇧-range / plain-single semantics are asserted as DATA
// vectors (Set/ordered array), independent of any View.
// Fixtures live in FileManager.temporaryDirectory (internal SSD — L009).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionBrowserModelTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("browsermodel-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func makeModel() -> SessionBrowserModel {
        SessionBrowserModel()
    }

    private func makeStore() -> SessionIndexStore {
        SessionIndexStore(sessionRoot: sessionRoot)
    }

    private func write(_ rel: String, bytes: Int = 8) throws {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    private func writeSidecar(_ rel: String, imageID: UUID) throws {
        var stack = HistoryStack()
        stack.commit(
            ModuleInstance(module: TestGainModule.self, multiName: "t", params: .init(gain: 2.0)),
            label: "test"
        )
        let document = LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: 42,
            instances: [],
            history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: 42, layerSnapshot: nil),
            appVersion: LightamerSidecar.currentAppVersion,
            layerStack: nil
        )
        let encoder = JSONEncoder()
        try encoder.encode(document).write(
            to: sessionRoot.appendingPathComponent(rel + ".lra")
        )
    }

    private func statEntry(_ rel: String) throws -> SessionScanEntry {
        let url = sessionRoot.appendingPathComponent(rel)
        let values = try url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        return SessionScanEntry(
            relPath: rel,
            mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            size: Int64(values.fileSize ?? 0)
        )
    }

    private func page(_ entries: [SessionScanEntry]) -> SessionScanPage {
        SessionScanPage(entries: entries)
    }

    // MARK: - Projection

    func testReloadProjectsRowsWithHashesAndFiltersOrphans() async throws {
        try write("Capture/A.ARW")
        try write("B.ARW")
        try writeSidecar("B.ARW", imageID: UUID())
        // An ORPHAN sidecar: `GONE.ARW.lra` whose original is gone — the
        // scanner classifies it in the orphan lane; the browse rows must
        // NOT include it.
        try Data("{}".utf8).write(to: sessionRoot.appendingPathComponent("GONE.ARW.lra"))

        let store = makeStore()
        let entries = [try statEntry("Capture/A.ARW"), try statEntry("B.ARW")]
        _ = try await store.openSession(
            root: sessionRoot, scan: AsyncStream { c in
                c.yield(SessionScanPage(entries: entries, orphanSidecarRelPaths: ["GONE.ARW.lra"]))
                c.finish()
            }
        )

        let model = makeModel()
        await model.reload(store: store)
        let rows = model.rows
        // Orphan row is NOT a browse row (the grid never shows it; the
        // sidebar orphan actions own it).
        XCTAssertEqual(rows.map(\.relPath), ["B.ARW", "Capture/A.ARW"], "ORDER BY path")
        let edited = try XCTUnwrap(rows.first { $0.relPath == "B.ARW" })
        XCTAssertTrue(edited.hasEdits, "the sidecar's committed history projects has_edits=true")
        XCTAssertNil(edited.thumbState, "9-1 sync leaves thumb_state NULL until 9-3 produces one")
        XCTAssertNil(edited.thumbParamsHash)
        let pristine = try XCTUnwrap(rows.first { $0.relPath == "Capture/A.ARW" })
        XCTAssertFalse(pristine.hasEdits, "no sidecar → pristine (tier A input)")
        // Stable identifier input: pathHash == the shared FNV hex spelling.
        XCTAssertEqual(pristine.pathHash, ThumbnailPath.hash("Capture/A.ARW"))
    }

    func testReloadRepairsSelectionOfVanishedRows() async throws {
        try write("A.ARW")
        try write("B.ARW")
        let store = makeStore()
        let entries = [try statEntry("A.ARW"), try statEntry("B.ARW")]
        _ = try await store.openSession(
            root: sessionRoot, scan: AsyncStream { c in
                c.yield(page(entries)); c.finish()
            }
        )
        let model = makeModel()
        await model.reload(store: store)
        model.handleClick("A.ARW", commandPressed: false, shiftPressed: false)
        model.handleClick("B.ARW", commandPressed: true, shiftPressed: false)
        XCTAssertEqual(Set(model.selectedPaths), ["A.ARW", "B.ARW"])

        // B vanishes (reconcile removal) → the stale selection must not
        // survive the next reload.
        try FileManager.default.removeItem(at: sessionRoot.appendingPathComponent("B.ARW"))
        let survivors = [try statEntry("A.ARW")]
        _ = try await store.openSession(
            root: sessionRoot, scan: AsyncStream { c in
                c.yield(page(survivors)); c.finish()
            }
        )
        await model.reload(store: store)
        XCTAssertEqual(model.selectedPaths, ["A.ARW"], "vanished rows drop out of the selection")
    }

    // MARK: - Selection semantics (data face)

    private func makeSelectionFixture() async throws -> (SessionBrowserModel, SessionIndexStore) {
        let store = makeStore()
        let model = await makeModel()
        for rel in ["A.ARW", "B.ARW", "C.ARW", "D.ARW"] {
            try write(rel)
        }
        let entries = [
            try statEntry("A.ARW"), try statEntry("B.ARW"),
            try statEntry("C.ARW"), try statEntry("D.ARW"),
        ]
        _ = try await store.openSession(
            root: sessionRoot, scan: AsyncStream { c in
                c.yield(page(entries)); c.finish()
            }
        )
        await model.reload(store: store)
        return (model, store)
    }

    func testPlainClickSelectsSingleAndMovesAnchor() async throws {
        let (model, _) = try await makeSelectionFixture()
        model.handleClick("B.ARW", commandPressed: false, shiftPressed: false)
        XCTAssertEqual(model.selectedPaths, ["B.ARW"])
        model.handleClick("C.ARW", commandPressed: false, shiftPressed: false)
        XCTAssertEqual(model.selectedPaths, ["C.ARW"], "plain click REPLACES the selection")
        XCTAssertEqual(model.selectionAnchor, "C.ARW")
    }

    func testCommandClickTogglesAccumulatingVector() async throws {
        let (model, _) = try await makeSelectionFixture()
        model.handleClick("A.ARW", commandPressed: false, shiftPressed: false)
        model.handleClick("C.ARW", commandPressed: true, shiftPressed: false)
        XCTAssertEqual(Set(model.selectedPaths), ["A.ARW", "C.ARW"], "⌘ accumulates")
        model.handleClick("C.ARW", commandPressed: true, shiftPressed: false)
        XCTAssertEqual(model.selectedPaths, ["A.ARW"], "⌘ on a selected row DESELECTS it")
        XCTAssertEqual(model.selectionAnchor, "C.ARW", "⌘ moves the anchor")
    }

    func testShiftClickSelectsRangeAndKeepsAnchor() async throws {
        let (model, _) = try await makeSelectionFixture()
        model.handleClick("A.ARW", commandPressed: false, shiftPressed: false)
        model.handleClick("C.ARW", commandPressed: false, shiftPressed: true)
        XCTAssertEqual(
            Set(model.selectedPaths), ["A.ARW", "B.ARW", "C.ARW"],
            "⇧ selects the anchor..click range INCLUSIVE"
        )
        XCTAssertEqual(model.selectionAnchor, "A.ARW", "⇧ never moves the anchor")
        // Extending downward from the SAME anchor replaces nothing — the
        // union grows to the new range.
        model.handleClick("D.ARW", commandPressed: false, shiftPressed: true)
        XCTAssertEqual(Set(model.selectedPaths), ["A.ARW", "B.ARW", "C.ARW", "D.ARW"])
    }

    func testShiftWithoutAnchorFallsBackToSingle() async throws {
        let (model, _) = try await makeSelectionFixture()
        model.handleClick("C.ARW", commandPressed: false, shiftPressed: true)
        XCTAssertEqual(model.selectedPaths, ["C.ARW"], "no anchor → single select")
        XCTAssertEqual(model.selectionAnchor, "C.ARW")
    }

    func testSelectedOrderedPathsFollowCollectionOrder() async throws {
        let (model, _) = try await makeSelectionFixture()
        model.handleClick("D.ARW", commandPressed: true, shiftPressed: false)
        model.handleClick("B.ARW", commandPressed: true, shiftPressed: false)
        XCTAssertEqual(
            model.selectedOrderedPaths, ["B.ARW", "D.ARW"],
            "the paste/batch vector is ORDER-STABLE (collection order), not set order"
        )
    }

    // MARK: - Progressive placeholder ingest

    func testPlaceholderPageUpsertsOnlyUnknownRowsAndTraceRecords() async throws {
        let (model, _) = try await makeSelectionFixture() // rows A..D present
        model.ingestPlaceholderPage(entries: [
            SessionScanEntry(relPath: "E.ARW", mtime: 1, size: 2),
            SessionScanEntry(relPath: "A.ARW", mtime: 1, size: 2), // known → skip
        ])
        XCTAssertTrue(model.progressiveIngestActive)
        XCTAssertEqual(model.lastIngestTrace.pagesConsumed, 1)
        XCTAssertEqual(model.lastIngestTrace.placeholderUpserts, 1, "only the UNKNOWN row upserts")
        XCTAssertEqual(model.rows.last?.relPath, "E.ARW")
        let placeholder = model.rows.last
        XCTAssertEqual(placeholder?.hasEdits, false, "placeholder tier input is the SAFE default")
        XCTAssertNil(placeholder?.thumbState, "placeholder rows carry NO thumb state (no render)")
    }

    func testFinishProgressiveIngestReloadsAuthoritativeAndClearsFlag() async throws {
        try write("E.ARW")
        let store = makeStore()
        let entries = [try statEntry("E.ARW")]
        _ = try await store.openSession(
            root: sessionRoot, scan: AsyncStream { c in
                c.yield(page(entries)); c.finish()
            }
        )
        let model = makeModel()
        model.ingestPlaceholderPage(entries: [
            SessionScanEntry(relPath: "E.ARW", mtime: 1, size: 2),
        ])
        XCTAssertTrue(model.progressiveIngestActive)
        await model.finishProgressiveIngest(store: store)
        XCTAssertFalse(model.progressiveIngestActive, "the authoritative reload closes the phase")
        XCTAssertEqual(model.rows.map(\.relPath), ["E.ARW"], "authority replaces placeholders")
        XCTAssertNotEqual(model.lastIngestTrace, SessionBrowserModel.IngestTrace(), "trace persists")
    }

    func testResetClearsRowsAndSelection() async throws {
        let (model, _) = try await makeSelectionFixture()
        model.handleClick("A.ARW", commandPressed: false, shiftPressed: false)
        model.reset()
        XCTAssertTrue(model.rows.isEmpty, "session-switch teardown: rows empty")
        XCTAssertTrue(model.selectedPaths.isEmpty)
        XCTAssertNil(model.selectionAnchor)
        XCTAssertFalse(model.progressiveIngestActive)
    }
}

// MARK: - T5: progressive ingest timing (real scanner stream)

@MainActor
extension SessionBrowserModelTests {

    /// The T5 timing assertion: the FIRST placeholder cells land BEFORE the
    /// walk finishes (网格边扫边出 — 9-1's stream seam consumed through the
    /// model). Builds a 600-file tree (3+ scanner pages).
    func testProgressiveIngestFirstPageLandsBeforeScanFinishes() async throws {
        let dirs = ["", "day1/", "day2/", "day3/"]
        for index in 0..<600 {
            let rel = dirs[index % dirs.count] + String(format: "IMG%04d.ARW", index)
            try write(rel)
        }
        var firstPageAtRows = 0
        var firstPageLanded = false
        let model = makeModel()
        var pages = 0
        for await page in SessionTreeScanner.scan(root: sessionRoot) {
            model.ingestPlaceholderPage(entries: page.entries)
            pages += 1
            if !firstPageLanded {
                firstPageLanded = true
                firstPageAtRows = model.rows.count
            }
        }
        XCTAssertGreaterThanOrEqual(pages, 2, "the tree spans multiple scanner pages")
        XCTAssertGreaterThan(firstPageAtRows, 0, "the FIRST page already populated cells")
        XCTAssertLessThan(
            firstPageAtRows, model.rows.count,
            "later pages added more rows after the first landed (真 progress, not vacuous)"
        )
        // The trace records the same facts for the acceptance round.
        XCTAssertEqual(model.lastIngestTrace.pagesConsumed, pages)
        XCTAssertGreaterThan(model.lastIngestTrace.placeholderUpserts, 0)
    }
}
