import LightamerCore
import LightamerIOP
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-02 T1 — the reconcile pure-diff suite:
//
//   • five-bucket goldens with EXACT member paths (anti-vacuous: every
//     bucket asserted member-by-member, never by mere existence):
//     ① pure addition ② pure removal ③ mtime/size drift (changed)
//     ④ rename survival pairing (the FSEvents-split remedy — the row is
//     re-paired, never delete+add) ⑤ orphan `.lra` classification
//   • externalEdits: the changed subset whose SIDECAR mtime did not move
//   • purity: identical inputs → equal plans (no hidden state)
//   • orphan classification rows excluded from the file math
//   • subtree-filter reporting restriction (optimization seam)
//   • the APPLY leg through the real store: rename-survival keeps every
//     backfilled column; external changes converge index == disk exactly;
//     a second reconcile run diffs all zeros (no churn)
//
// Fixtures live in `FileManager.temporaryDirectory` (internal SSD — L009);
// scan streams are hand-built (SessionTreeScanner is App-layer; the pure
// function and the store never need it).
// ─────────────────────────────────────────────────────────────────────────────

final class ReconcileDiffTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("reconcilediff-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers (deterministic stats — mtime pinned via setAttributes)

    /// Write a file and pin its mtime to an exact epoch value so stat
    /// fingerprints (the rename ruling input) are bit-stable across reads.
    @discardableResult
    private func write(
        _ rel: String, bytes: Int = 8, mtime: TimeInterval = 1000
    ) throws -> SessionScanEntry {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: mtime)],
            ofItemAtPath: url.path
        )
        return SessionScanEntry(relPath: rel, mtime: mtime, size: Int64(bytes))
    }

    private func entry(_ rel: String, mtime: TimeInterval, size: Int64) -> SessionScanEntry {
        SessionScanEntry(relPath: rel, mtime: mtime, size: size)
    }

    private func row(
        _ path: String, mtime: TimeInterval, size: Int64,
        sidecarMtime: Double? = nil, orphan: Bool = false
    ) -> SessionIndexRow {
        var row = SessionIndexRow(path: path)
        row.fileMtime = mtime
        row.fileSize = size
        row.sidecarMtime = sidecarMtime
        row.orphanSidecar = orphan ? 1 : 0
        return row
    }

    private func stream(of entries: [SessionScanEntry], orphans: [String] = [])
        -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            continuation.yield(
                SessionScanPage(entries: entries, orphanSidecarRelPaths: orphans)
            )
            continuation.finish()
        }
    }

    // MARK: - Pure-diff goldens

    func testPureAdditionGolden() {
        let plan = ReconcileDiff.diff(
            previousRows: [],
            current: ReconcileScanSnapshot(entries: [
                entry("b.arw", mtime: 100, size: 10),
                entry("sub/a.arw", mtime: 200, size: 20),
            ])
        )
        // EXACT membership — anti-vacuous.
        XCTAssertEqual(plan.added, ["b.arw", "sub/a.arw"])
        XCTAssertTrue(plan.removed.isEmpty)
        XCTAssertTrue(plan.changed.isEmpty)
        XCTAssertTrue(plan.renamedSurvived.isEmpty)
        XCTAssertTrue(plan.orphanSidecars.isEmpty)
        XCTAssertTrue(plan.externalEdits.isEmpty)
        XCTAssertFalse(plan.isTrivial)
    }

    func testPureRemovalGolden() {
        let plan = ReconcileDiff.diff(
            previousRows: [
                row("a.arw", mtime: 100, size: 10),
                row("gone.arw", mtime: 300, size: 30),
            ],
            current: ReconcileScanSnapshot(entries: [entry("a.arw", mtime: 100, size: 10)])
        )
        XCTAssertEqual(plan.removed, ["gone.arw"])
        XCTAssertTrue(plan.added.isEmpty)
        XCTAssertTrue(plan.changed.isEmpty)
        XCTAssertTrue(plan.renamedSurvived.isEmpty)
        XCTAssertTrue(plan.isTrivial == false)
    }

    func testMtimeAndSizeDriftChangedGolden() {
        let plan = ReconcileDiff.diff(
            previousRows: [
                row("m.arw", mtime: 100, size: 10),
                row("s.arw", mtime: 100, size: 10),
                row("same.arw", mtime: 100, size: 10),
            ],
            current: ReconcileScanSnapshot(entries: [
                entry("m.arw", mtime: 200, size: 10),  // mtime drifted
                entry("s.arw", mtime: 100, size: 99),  // size drifted
                entry("same.arw", mtime: 100, size: 10),  // untouched
            ])
        )
        XCTAssertEqual(plan.changed, ["m.arw", "s.arw"], "drift = mtime OR size")
        XCTAssertTrue(plan.added.isEmpty)
        XCTAssertTrue(plan.removed.isEmpty)
        XCTAssertTrue(plan.externalEdits.isEmpty, "no sidecar context → not external")
    }

    func testRenameSurvivalPairingGolden() {
        // mv preserves mtime+size: the removed×added pair with an EXACT
        // stat fingerprint match is one rename — the row SURVIVES.
        let plan = ReconcileDiff.diff(
            previousRows: [row("old/summer.arw", mtime: 100, size: 10)],
            current: ReconcileScanSnapshot(entries: [
                entry("old/autumn.arw", mtime: 100, size: 10),
            ])
        )
        XCTAssertEqual(
            plan.renamedSurvived,
            [SessionReconcileRename(fromPath: "old/summer.arw", toPath: "old/autumn.arw")]
        )
        XCTAssertTrue(plan.added.isEmpty, "paired rename is NOT an addition")
        XCTAssertTrue(plan.removed.isEmpty, "paired rename is NOT a removal")
        XCTAssertTrue(plan.changed.isEmpty)
    }

    func testRenameDoesNotPairMismatchedStats() {
        // Different stat fingerprint (mtime moved) → NOT provably a rename;
        // falls out as remove+add (the sidecar re-read leg covers the rest).
        let plan = ReconcileDiff.diff(
            previousRows: [row("a.arw", mtime: 100, size: 10)],
            current: ReconcileScanSnapshot(entries: [entry("b.arw", mtime: 200, size: 10)])
        )
        XCTAssertTrue(plan.renamedSurvived.isEmpty)
        XCTAssertEqual(plan.added, ["b.arw"])
        XCTAssertEqual(plan.removed, ["a.arw"])
    }

    func testRenamePairingIsOneToOne() {
        // Two identical stats added, one removed → exactly ONE pairing; the
        // other added candidate stays an addition. Deterministic pairing:
        // lexicographically-first destination wins.
        let plan = ReconcileDiff.diff(
            previousRows: [row("a.arw", mtime: 100, size: 10)],
            current: ReconcileScanSnapshot(entries: [
                entry("b.arw", mtime: 100, size: 10),
                entry("c.arw", mtime: 100, size: 10),
            ])
        )
        XCTAssertEqual(
            plan.renamedSurvived,
            [SessionReconcileRename(fromPath: "a.arw", toPath: "b.arw")]
        )
        XCTAssertEqual(plan.added, ["c.arw"])
        XCTAssertTrue(plan.removed.isEmpty)
    }

    func testOrphanSidecarBucketGolden() {
        // `.lra` stayed, the original walked — classification, never failure.
        let plan = ReconcileDiff.diff(
            previousRows: [row("x.arw", mtime: 100, size: 10)],
            current: ReconcileScanSnapshot(
                entries: [],
                orphanSidecars: ["x.arw.lra"]
            )
        )
        XCTAssertEqual(plan.orphanSidecars, ["x.arw.lra"])
        XCTAssertEqual(plan.removed, ["x.arw"], "the original row goes")
        XCTAssertTrue(plan.added.isEmpty)
    }

    func testExternalEditsBucketSidecarUntouched() {
        // Original drifted while the sidecar mtime stayed → outside edit.
        let external = ReconcileDiff.diff(
            previousRows: [row("e.arw", mtime: 100, size: 10, sidecarMtime: 50)],
            current: ReconcileScanSnapshot(
                entries: [entry("e.arw", mtime: 200, size: 10)],
                sidecarMtimes: ["e.arw": 50]
            )
        )
        XCTAssertEqual(external.changed, ["e.arw"])
        XCTAssertEqual(external.externalEdits, ["e.arw"])

        // Contrast: the sidecar ALSO moved → a regular changed row.
        let normal = ReconcileDiff.diff(
            previousRows: [row("e.arw", mtime: 100, size: 10, sidecarMtime: 50)],
            current: ReconcileScanSnapshot(
                entries: [entry("e.arw", mtime: 200, size: 10)],
                sidecarMtimes: ["e.arw": 60]
            )
        )
        XCTAssertEqual(normal.changed, ["e.arw"])
        XCTAssertTrue(normal.externalEdits.isEmpty)

        // Contrast: no sidecar at all (pristine) → not external.
        let pristine = ReconcileDiff.diff(
            previousRows: [row("e.arw", mtime: 100, size: 10, sidecarMtime: nil)],
            current: ReconcileScanSnapshot(
                entries: [entry("e.arw", mtime: 200, size: 10)],
                sidecarMtimes: [:]
            )
        )
        XCTAssertTrue(pristine.externalEdits.isEmpty)
    }

    func testMixedScenarioAllFiveBucketsExact() {
        let previousRows: [SessionIndexRow] = [
            row("keep.arw", mtime: 100, size: 10, sidecarMtime: 55),
            row("gone.arw", mtime: 300, size: 30),
            row("drift.arw", mtime: 100, size: 10, sidecarMtime: 56),
            row("old.arw", mtime: 777, size: 70),
            row("ext.arw", mtime: 100, size: 10, sidecarMtime: 50),
        ]
        let current = ReconcileScanSnapshot(
            entries: [
                entry("keep.arw", mtime: 100, size: 10),
                entry("new.arw", mtime: 400, size: 40),
                entry("drift.arw", mtime: 900, size: 10),
                entry("moved.arw", mtime: 777, size: 70),
                entry("ext.arw", mtime: 150, size: 12),
            ],
            sidecarMtimes: ["keep.arw": 55, "drift.arw": 96, "ext.arw": 50],
            orphanSidecars: ["dead.arw.lra"]
        )
        let plan = ReconcileDiff.diff(previousRows: previousRows, current: current)

        // ALL FIVE buckets, member-exact.
        XCTAssertEqual(plan.added, ["new.arw"])
        XCTAssertEqual(plan.removed, ["gone.arw"])
        XCTAssertEqual(plan.changed, ["drift.arw", "ext.arw"])
        XCTAssertEqual(
            plan.renamedSurvived,
            [SessionReconcileRename(fromPath: "old.arw", toPath: "moved.arw")]
        )
        XCTAssertEqual(plan.orphanSidecars, ["dead.arw.lra"])
        XCTAssertEqual(
            plan.externalEdits, ["ext.arw"],
            "size AND mtime moved, sidecar untouched → external edit"
        )
        XCTAssertFalse(plan.isTrivial)
    }

    func testPuritySameInputYieldsEqualPlan() {
        let previousRows = [
            row("a.arw", mtime: 100, size: 10, sidecarMtime: 50),
            row("b.arw", mtime: 200, size: 20),
        ]
        let current = ReconcileScanSnapshot(
            entries: [
                entry("a.arw", mtime: 300, size: 10),
                entry("c.arw", mtime: 100, size: 10),
            ],
            sidecarMtimes: ["a.arw": 50],
            orphanSidecars: ["b.arw.lra"]
        )
        let first = ReconcileDiff.diff(previousRows: previousRows, current: current)
        let second = ReconcileDiff.diff(previousRows: previousRows, current: current)
        XCTAssertEqual(first, second, "the pure diff has NO hidden state")
    }

    func testOrphanRowsExcludedFromFileMath() {
        // An orphan classification row (orphan_sidecar=1, path = the .lra
        // relPath) must never enter the added/removed/changed math.
        let plan = ReconcileDiff.diff(
            previousRows: [
                row("x.arw.lra", mtime: 100, size: 10, orphan: true),
            ],
            current: ReconcileScanSnapshot(entries: [])
        )
        XCTAssertTrue(plan.removed.isEmpty, "orphan rows are the orphan legs' business")
        XCTAssertTrue(plan.isTrivial)
    }

    func testSubtreeFilterRestrictsReportedBuckets() {
        let previousRows = [row("sub/old.arw", mtime: 100, size: 10)]
        let current = ReconcileScanSnapshot(entries: [
            entry("root-new.arw", mtime: 500, size: 50),
            entry("sub/new.arw", mtime: 600, size: 60),
            entry("sub/old.arw", mtime: 100, size: 10),
        ])
        let full = ReconcileDiff.diff(previousRows: previousRows, current: current)
        XCTAssertEqual(full.added, ["root-new.arw", "sub/new.arw"])

        let filtered = ReconcileDiff.diff(
            previousRows: previousRows, current: current, subtreeFilter: ["sub"]
        )
        XCTAssertEqual(filtered.added, ["sub/new.arw"], "only the affected subtree reports")
    }

    // MARK: - Apply leg through the real store (single transaction)

    func testApplyRenameSurvivalKeepsBackfilledColumns() async throws {
        // ① Open with a.arw + an EDITED sidecar (backfilled row).
        try write("a.arw", bytes: 16, mtime: 1000)
        let imageID = UUID()
        let gain = ModuleInstance(
            module: TestGainModule.self, multiName: "t", params: .init(gain: 2.0)
        )
        let hash = HistoryHash.hash(instances: [gain], decodeParamsHash: 42)
        var stack = HistoryStack()
        stack.commit(gain, label: "test")
        let document = LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: 42,
            instances: [gain],
            history: stack,
            historyHash: hash,
            layerStack: nil
        )
        let sidecarURL = sessionRoot.appendingPathComponent("a.arw.lra")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: sidecarURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 500)],
            ofItemAtPath: sidecarURL.path
        )

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [
                SessionScanEntry(relPath: "a.arw", mtime: 1000, size: 16)
            ])
        )
        var rows = try await store.fetchAllRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].paramsHash, String(hash), "precondition: backfilled")
        XCTAssertEqual(rows[0].hasEdits, 1)

        // ② EXTERNAL Finder rename: original + sidecar move together
        //    (same-volume move preserves the pinned stats).
        try FileManager.default.moveItem(
            at: sessionRoot.appendingPathComponent("a.arw"),
            to: sessionRoot.appendingPathComponent("b.arw")
        )
        try FileManager.default.moveItem(
            at: sidecarURL, to: sessionRoot.appendingPathComponent("b.arw.lra")
        )

        // ③ Pure diff rules the rename; the apply leg executes it.
        let plan = ReconcileDiff.diff(
            previousRows: rows,
            current: ReconcileScanSnapshot(
                entries: [entry("b.arw", mtime: 1000, size: 16)],
                sidecarMtimes: ["b.arw": 500]
            )
        )
        XCTAssertEqual(
            plan.renamedSurvived,
            [SessionReconcileRename(fromPath: "a.arw", toPath: "b.arw")]
        )
        _ = try await store.reconcile(
            root: sessionRoot,
            scan: stream(of: [entry("b.arw", mtime: 1000, size: 16)]),
            renames: plan.renamedSurvived
        )

        // ④ The ROW SURVIVED: path updated, every backfilled column KEPT
        //    (delete+insert would have discarded them until a re-read).
        rows = try await store.fetchAllRows()
        XCTAssertEqual(rows.map(\.path), ["b.arw"], "exactly one row — no dup, no loss")
        XCTAssertNil(rows[0].dir, "root-level files carry a NULL dir (sync convention)")
        XCTAssertEqual(rows[0].filename, "b.arw")
        XCTAssertEqual(rows[0].paramsHash, String(hash), "rename keeps the sidecar truth")
        XCTAssertEqual(rows[0].hasEdits, 1)
        XCTAssertEqual(rows[0].imageID, imageID.uuidString)
        XCTAssertEqual(rows[0].fileMtime, 1000)
        XCTAssertEqual(rows[0].fileSize, 16)
        XCTAssertEqual(rows[0].sidecarPresent, 1, "sidecar followed the move")
        await store.close()
    }

    func testReconcileConvergesIndexToDiskExactly() async throws {
        // ① Open with a/b; then external changes: delete a, drift b, add c.
        try write("a.arw", bytes: 8, mtime: 100)
        try write("b.arw", bytes: 8, mtime: 100)
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [
                entry("a.arw", mtime: 100, size: 8), entry("b.arw", mtime: 100, size: 8),
            ])
        )

        // Finder simulation: delete a, REPLACE b (new content+mtime), add c.
        try FileManager.default.removeItem(at: sessionRoot.appendingPathComponent("a.arw"))
        try write("b.arw", bytes: 64, mtime: 200)
        try write("sub/c.arw", bytes: 32, mtime: 300)

        let result = try await store.reconcile(
            root: sessionRoot, scan: stream(of: [
                entry("b.arw", mtime: 200, size: 64),
                entry("sub/c.arw", mtime: 300, size: 32),
            ])
        )
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.changed, 1)

        // Index == disk EXACTLY (paths + stat columns).
        let rows = try await store.fetchAllRows()
        XCTAssertEqual(Set(rows.map(\.path)), ["b.arw", "sub/c.arw"])
        let b = try XCTUnwrap(rows.first { $0.path == "b.arw" })
        XCTAssertEqual(b.fileSize, 64)
        XCTAssertEqual(b.fileMtime, 200)
        let c = try XCTUnwrap(rows.first { $0.path == "sub/c.arw" })
        XCTAssertEqual(c.dir, "sub")
        XCTAssertEqual(c.fileSize, 32)
        await store.close()
    }

    func testReconcileOrphanClassificationRow() async throws {
        try write("x.arw", bytes: 8, mtime: 100)
        try write("x.arw.lra", bytes: 4, mtime: 100)
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [entry("x.arw", mtime: 100, size: 8)])
        )

        // The original walks; the sidecar stays → orphan classification row.
        try FileManager.default.removeItem(at: sessionRoot.appendingPathComponent("x.arw"))
        let result = try await store.reconcile(
            root: sessionRoot,
            scan: stream(of: [], orphans: ["x.arw.lra"])
        )
        XCTAssertEqual(result.orphanAdded, 1)
        XCTAssertEqual(result.removed, 1, "the original row goes")
        XCTAssertEqual(result.counts.orphans, 1)

        let rows = try await store.fetchAllRows()
        XCTAssertEqual(rows.map(\.path), ["x.arw.lra"])
        XCTAssertEqual(rows[0].orphanSidecar, 1)
        await store.close()
    }

    func testSecondReconcileRunDiffsAllZeros() async throws {
        try write("a.arw", bytes: 8, mtime: 100)
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [entry("a.arw", mtime: 100, size: 8)])
        )
        let first = try await store.reconcile(
            root: sessionRoot, scan: stream(of: [entry("a.arw", mtime: 100, size: 8)])
        )
        XCTAssertEqual(first.added, 0)
        XCTAssertEqual(first.removed, 0)
        XCTAssertEqual(first.changed, 0)
        XCTAssertEqual(first.orphanAdded, 0)
        XCTAssertEqual(first.orphanRemoved, 0)
        // And the tree state survives the no-churn re-run byte-identically.
        let rows = try await store.fetchAllRows()
        XCTAssertEqual(rows.map(\.path), ["a.arw"])
        await store.close()
    }
}
