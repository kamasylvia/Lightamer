import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-1 T3/T4 — the metadata write face:
//
//   PRELUDE (T3 evidence):
//   • healDirtyRows backfills the FIVE metadata columns precisely from the
//     disk sidecar (the crash-window heal's 旧值回填)
//   • backfillSidecarSummaries' mtime-drift re-read PRESERVES (re-derives)
//     the metadata columns — drift never drops the rating face
//   • claimMetadataApply's SET list never touches thumb_state/params_hash
//     (text assertion + functional thumb-invariance)
//
//   SERVICE (T4):
//   • three segments: index claim + disk sidecar truth + dirty cleared
//   • hash isolation through the service: history/params hashes unchanged
//   • pristine targets mint self-consistent seeded documents
//   • unreadable sidecars are SKIPPED, never clobbered
//   • `|` keyword rejection (typed) writes nothing
//   • nil vs [] keyword semantics (NULL vs empty string)
//   • 万张 gate: 10k setRating segments 1+2 ≤ 5s (RELEASE/SSD; Debug
//     ceiling recorded) + thumb_state/params_hash 逐行不变
//   • crash injection: the F6 window heals to the OLD sidecar values,
//     zero three-state drift
//
// Fixtures in FileManager.temporaryDirectory (L009).
// ─────────────────────────────────────────────────────────────────────────────

final class MetadataServiceTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!
    private var store: SessionIndexStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("metaservice-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
        store = SessionIndexStore(sessionRoot: sessionRoot)
    }

    override func tearDown() async throws {
        await store.close()
        store = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Write one original + a sidecar with an edited history and the given
    /// metadata. Returns the relPath.
    @discardableResult
    private func writeImage(
        _ rel: String, rating: Int? = nil, flag: Int? = nil,
        colorLabel: Int? = nil, keywords: [String]? = nil, note: String? = nil,
        exposure: Float = 0.5
    ) throws -> String {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 16).write(to: url)
        var history = HistoryStack()
        history.commit(
            ModuleInstance(
                module: ExposureModule.self, multiName: "e",
                params: ExposureModule.Params(exposure: exposure)),
            label: "exposure")
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 42,
            instances: history.effectiveInstances(), history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 42),
            appVersion: "meta-test", layerStack: nil,
            rating: rating, flag: flag, colorLabel: colorLabel,
            keywords: keywords, note: note)
        try JSONEncoder().encode(document).write(
            to: LightamerSidecar.sidecarURL(for: url))
        return rel
    }

    private func scanOf(_ rels: [String], orphans: [String] = []) -> AsyncStream<SessionScanPage> {
        var page = SessionScanPage()
        for rel in rels {
            let values = try! sessionRoot.appendingPathComponent(rel).resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            page.entries.append(SessionScanEntry(
                relPath: rel,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0)))
        }
        page.orphanSidecarRelPaths = orphans
        return AsyncStream { continuation in
            continuation.yield(page)
            continuation.finish()
        }
    }

    private func openIndex(_ rels: [String], orphans: [String] = []) async throws {
        _ = try await store.openSession(
            root: sessionRoot, scan: scanOf(rels, orphans: orphans))
    }

    private func readDiskDocument(_ rel: String) throws -> LightamerSidecar {
        try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(
                for: sessionRoot.appendingPathComponent(rel))))
    }

    private func makeService(writer: BatchSidecarWriter? = nil, seed: [ModuleInstance] = [])
        -> MetadataService
    {
        MetadataService(root: sessionRoot, store: store, writer: writer, seed: seed)
    }

    private func seedDefaults() async -> [ModuleInstance] {
        await ModuleRegistry.makeDefault().makeDefaultInstances()
    }

    // MARK: - Prelude (T3): heal backfills the five columns precisely

    func testHealDirtyRowsBackfillsFiveMetadataColumnsFromDiskTruth() async throws {
        let rel = try writeImage(
            "one.arw", rating: 4, flag: 1, colorLabel: 2,
            keywords: ["Nature|Flower", "Street"], note: "keeper")
        try await openIndex([rel])
        // The claim whose segment 3 never wrote (the crash window): the
        // index says 2 everywhere, the disk sidecar still says 4.
        try await store.claimMetadataApply(claims: [
            SessionIndexStore.MetadataClaim(
                relPath: rel, rating: 2, colorLabel: 0,
                keywords: "wrong", flag: 2, note: "wrong",
                sidecarMtime: Date().timeIntervalSince1970),
        ])
        var row = try await store.fetchRow(relPath: rel)
        XCTAssertEqual(row?.rating, 2, "the claim landed (待生效 state)")
        XCTAssertEqual(row?.dirty, 1)

        // REOPEN: the heal leg re-derives from the DISK truth.
        await store.close()
        store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: scanOf([rel]))
        row = try await store.fetchRow(relPath: rel)
        XCTAssertEqual(row?.rating, 4, "healed back to the disk sidecar's value")
        XCTAssertEqual(row?.colorLabel, 2)
        XCTAssertEqual(row?.keywords, "Nature|Flower|Street")
        XCTAssertEqual(row?.flag, 1)
        XCTAssertEqual(row?.note, "keeper")
        XCTAssertEqual(row?.dirty, 0)
    }

    // MARK: - Prelude (T3 + 12-5 fix): the late-sidecar promotion

    /// The 12-2 acceptance gap (GOAL-STATE blocker #4, fixed 12-5): a row
    /// scanned BEFORE its `.lra` existed stayed sidecar_present = 0 forever
    /// and never re-read. The backfill now stats the absent rows and
    /// promotes + reads the late sidecar on the next open.
    func testBackfillPromotesLateSidecarRows() async throws {
        let rel = "late.arw"
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 16).write(to: url)
        try await openIndex([rel])
        var row = try await store.fetchRow(relPath: rel)
        XCTAssertEqual(row?.sidecarPresent, 0, "no .lra at scan time")

        // The sidecar appears afterwards (the MetadataService first-write).
        var history = HistoryStack()
        history.commit(
            ModuleInstance(
                module: ExposureModule.self, multiName: "e",
                params: ExposureModule.Params(exposure: -0.25)),
            label: "exposure")
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 42,
            instances: history.effectiveInstances(), history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 42),
            appVersion: "meta-test", layerStack: nil,
            rating: 3, flag: nil, colorLabel: nil, keywords: nil, note: nil)
        try JSONEncoder().encode(document).write(
            to: LightamerSidecar.sidecarURL(for: url))

        await store.close()
        store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: scanOf([rel]))
        row = try await store.fetchRow(relPath: rel)
        XCTAssertEqual(row?.sidecarPresent, 1, "promoted by the backfill's absent-row stat")
        XCTAssertEqual(row?.rating, 3, "the late sidecar actually re-read")
        XCTAssertEqual(row?.hasEdits, 1)
    }

    // MARK: - Prelude (T3): the drift re-read preserves metadata

    func testBackfillSidecarSummariesDriftReReadRefreshesMetadata() async throws {
        let rel = try writeImage("one.arw", rating: 4, keywords: ["Old"])
        try await openIndex([rel])
        var row = try await store.fetchRow(relPath: rel)
        XCTAssertEqual(row?.rating, 4)

        // Rewrite the sidecar UNDER the index (the external-edit shape):
        // different metadata + necessarily a new mtime.
        let url = sessionRoot.appendingPathComponent(rel)
        var history = HistoryStack()
        history.commit(
            ModuleInstance(
                module: ExposureModule.self, multiName: "e",
                params: ExposureModule.Params(exposure: 0.5)),
            label: "exposure")
        let updated = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 42,
            instances: history.effectiveInstances(), history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 42),
            appVersion: "meta-test", layerStack: nil,
            rating: 5, flag: 1, colorLabel: 3,
            keywords: ["Nature|Flower", "New"], note: "changed")
        try JSONEncoder().encode(updated).write(
            to: LightamerSidecar.sidecarURL(for: url))

        await store.close()
        store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: scanOf([rel]))
        row = try await store.fetchRow(relPath: rel)
        // The F7 duty: the drift re-read refreshes the rating face from
        // the new sidecar instead of dropping it.
        XCTAssertEqual(row?.rating, 5)
        XCTAssertEqual(row?.colorLabel, 3)
        XCTAssertEqual(row?.keywords, "Nature|Flower|New")
        XCTAssertEqual(row?.flag, 1)
        XCTAssertEqual(row?.note, "changed")
        XCTAssertEqual(row?.dirty, 0)
    }

    // MARK: - Prelude (T3): the claim SQL never touches thumb columns

    func testClaimMetadataApplySQLColumnSetAndThumbInvariance() async throws {
        // The SET list is the contract (F6): the five metadata columns +
        // sidecar_mtime + dirty — NOTHING else.
        let sql = SessionIndexStore.claimMetadataApplySQL
        for column in ["rating", "color_label", "keywords", "flag", "note",
                       "sidecar_mtime", "dirty"] {
            XCTAssertTrue(sql.contains(column), "SET must contain \(column)")
        }
        for forbidden in ["thumb_state", "thumb_path", "thumb_params_hash",
                          "params_hash", "has_edits", "layer_count",
                          "layer_summary"] {
            XCTAssertFalse(
                sql.contains(forbidden),
                "a metadata claim must never rewrite \(forbidden)")
        }

        // Functional: a RENDERED-thumb row keeps its thumb state + params
        // hash through a claim.
        let rel = try writeImage("one.arw")
        try await openIndex([rel])
        try await store.updateThumbnailRecord(
            relPath: rel, state: .rendered,
            thumbPath: "/tmp/t.jpg", paramsHash: "98765432109876543210")
        let before = try await store.fetchRow(relPath: rel)
        try await store.claimMetadataApply(claims: [
            SessionIndexStore.MetadataClaim(
                relPath: rel, rating: 3, colorLabel: nil, keywords: nil,
                flag: nil, note: nil,
                sidecarMtime: Date().timeIntervalSince1970),
        ])
        let row = try await store.fetchRow(relPath: rel)
        XCTAssertEqual(row?.thumbState, SessionIndexSchema.ThumbState.rendered.rawValue)
        XCTAssertEqual(row?.thumbParamsHash, "98765432109876543210")
        XCTAssertEqual(row?.paramsHash, before?.paramsHash, "untouched too")
        XCTAssertEqual(row?.hasEdits, before?.hasEdits)
        XCTAssertEqual(row?.rating, 3)
        XCTAssertEqual(row?.dirty, 1)
    }

    // MARK: - Service: the three segments end-to-end

    func testSetRatingWritesSidecarTruthAndClearsDirty() async throws {
        let edited = try writeImage("a.arw", rating: 4)
        let pristine = "b.arw"
        try Data(repeating: 0xCD, count: 16).write(
            to: sessionRoot.appendingPathComponent(pristine))
        try await openIndex([edited, pristine])

        let writer = BatchSidecarWriter(root: sessionRoot, store: store)
        let service = makeService(writer: writer, seed: await seedDefaults())
        let outcome = try await service.setRating(3, relPaths: [edited, pristine])

        XCTAssertEqual(outcome.appliedRelPaths, [edited, pristine])
        XCTAssertTrue(outcome.skippedRelPaths.isEmpty)

        // Segment 3 drained → every row clean.
        let rowA = try await store.fetchRow(relPath: edited)
        XCTAssertEqual(rowA?.rating, 3)
        XCTAssertEqual(rowA?.dirty, 0)
        let rowB = try await store.fetchRow(relPath: pristine)
        XCTAssertEqual(rowB?.rating, 3)
        XCTAssertEqual(rowB?.dirty, 0)

        // DISK truth: rating in the sidecar, parameters untouched, hash
        // self-consistent (drift stays false — D-8).
        let docA = try readDiskDocument(edited)
        XCTAssertEqual(docA.rating, 3)
        XCTAssertEqual(docA.history.items.count, 1, "no history item was created")
        XCTAssertEqual(docA.history.items[0].label, "exposure")
        XCTAssertFalse(docA.driftDetected)

        // The PRISTINE target minted a seeded, self-consistent document.
        let docB = try readDiskDocument(pristine)
        XCTAssertEqual(docB.rating, 3)
        XCTAssertFalse(docB.driftDetected)
        XCTAssertEqual(docB.history.items.count, 0)
        let seedInstances = await seedDefaults()
        XCTAssertEqual(docB.instances.count, seedInstances.count)
        // No pending writes left.
        let pending = await writer.pendingCountForTesting
        XCTAssertEqual(pending, 0)
    }

    func testUnreadableSidecarIsSkippedNeverClobbered() async throws {
        let rel = "a.arw"
        let url = sessionRoot.appendingPathComponent(rel)
        try Data(repeating: 0xAB, count: 16).write(to: url)
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        let garbage = Data("not json at all {{{".utf8)
        try garbage.write(to: sidecarURL)
        try await openIndex([rel])
        let before = try Data(contentsOf: sidecarURL)

        let service = makeService()
        let outcome = try await service.setRating(3, relPaths: [rel])
        XCTAssertEqual(outcome.appliedRelPaths, [])
        XCTAssertEqual(outcome.skippedRelPaths, [rel])
        XCTAssertEqual(try Data(contentsOf: sidecarURL), before)
        let row = try await store.fetchRow(relPath: rel)
        XCTAssertNil(row?.rating, "no claim for a skipped target")
    }

    // MARK: - Keyword validation + nil/[] semantics + appends

    func testKeywordSeparatorRejectionWritesNothing() async throws {
        let rel = try writeImage("a.arw")
        try await openIndex([rel])
        let before = try Data(
            contentsOf: LightamerSidecar.sidecarURL(
                for: sessionRoot.appendingPathComponent(rel)))

        let service = makeService(writer: BatchSidecarWriter(root: sessionRoot, store: store))
        do {
            _ = try await service.setKeywords(["Nature", "Na|ture"], relPaths: [rel])
            XCTFail("a `|` entry must be rejected")
        } catch let error as MetadataService.MetadataError {
            XCTAssertEqual(error, .keywordContainsSeparator("Na|ture"))
        }
        do {
            _ = try await service.appendKeywords(["x|y"], relPaths: [rel])
            XCTFail("append must reject `|` too")
        } catch let error as MetadataService.MetadataError {
            XCTAssertEqual(error, .keywordContainsSeparator("x|y"))
        }
        XCTAssertEqual(
            try Data(contentsOf: LightamerSidecar.sidecarURL(
                for: sessionRoot.appendingPathComponent(rel))),
            before, "a rejected edit writes nothing")
        let row = try await store.fetchRow(relPath: rel)
        XCTAssertNil(row?.keywords)
    }

    func testKeywordsNilVsEmptyAreDistinct() async throws {
        let nilTarget = try writeImage("a.arw")
        let clearedTarget = try writeImage("b.arw", keywords: ["Old"])
        try await openIndex([nilTarget, clearedTarget])
        let service = makeService(writer: BatchSidecarWriter(root: sessionRoot, store: store))

        _ = try await service.setKeywords(nil, relPaths: [nilTarget])
        _ = try await service.setKeywords([], relPaths: [clearedTarget])

        let rowA = try await store.fetchRow(relPath: nilTarget)
        XCTAssertNil(rowA?.keywords, "nil → NULL (never tagged)")
        let rowB = try await store.fetchRow(relPath: clearedTarget)
        XCTAssertEqual(rowB?.keywords, "", "[] → empty string (cleared)")
        XCTAssertEqual(try readDiskDocument(clearedTarget).keywords, [])
    }

    func testAppendKeywordsDeduplicatesAndAppendNoteJoinsLines() async throws {
        // The fixture carries a pre-existing full PATH (as an XMP import
        // would land it); the SERVICE entry ban is on `|` in TYPED
        // entries — the appended entries are single levels.
        let rel = try writeImage(
            "a.arw", keywords: ["Nature|Flower"], note: "first")
        try await openIndex([rel])
        let service = makeService(writer: BatchSidecarWriter(root: sessionRoot, store: store))

        _ = try await service.appendKeywords(
            ["Flower", "Street"], relPaths: [rel])
        _ = try await service.appendNote("second", relPaths: [rel])
        _ = try await service.appendNote("third", relPaths: [rel])

        let document = try readDiskDocument(rel)
        XCTAssertEqual(document.keywords, ["Nature|Flower", "Flower", "Street"])
        XCTAssertEqual(document.note, "first\nsecond\nthird")
        let row = try await store.fetchRow(relPath: rel)
        XCTAssertEqual(row?.keywords, "Nature|Flower|Flower|Street")
        XCTAssertEqual(row?.dirty, 0, "segment 3 drained")
    }

    // MARK: - The 万张 gate (PERF-07 fixture shape)

    private static let massCount = 10_000

    /// The PERF-07 fixture: 10k originals + real `.lra` documents.
    private func buildMassFixture() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for index in 0..<Self.massCount {
            let rel = "img\(index).ARW"
            let url = sessionRoot.appendingPathComponent(rel)
            try Data(repeating: 0xAB, count: 8).write(to: url)
            var history = HistoryStack()
            let exposure = ModuleInstance(
                module: ExposureModule.self, multiName: "e\(index)",
                params: ExposureModule.Params(exposure: Float(index % 7) * 0.1))
            history.commit(exposure, label: "exposure")
            let decodeHash = UInt64(index + 1)
            let document = LightamerSidecar(
                imageID: UUID(), decoderVersionUsed: "v8",
                decodeParamsHash: decodeHash,
                instances: history.effectiveInstances(), history: history,
                historyHash: HistoryHash.hash(stack: history, decodeParamsHash: decodeHash),
                appVersion: "meta-gate", layerStack: nil)
            try encoder.encode(document).write(
                to: LightamerSidecar.sidecarURL(for: url))
        }
    }

    private func openMassIndex() async throws {
        var entries: [SessionScanEntry] = []
        for index in 0..<Self.massCount {
            let url = sessionRoot.appendingPathComponent("img\(index).ARW")
            let values = try url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            entries.append(SessionScanEntry(
                relPath: url.lastPathComponent,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0)))
        }
        let scan = AsyncStream<SessionScanPage> { continuation in
            for chunk in stride(from: 0, to: entries.count, by: 1000) {
                continuation.yield(SessionScanPage(
                    entries: Array(entries[chunk..<min(chunk + 1000, entries.count)])))
            }
            continuation.finish()
        }
        _ = try await store.openSession(root: sessionRoot, scan: scan)
    }

    /// GATE: setRating over 10k, segments 1+2 (writer nil) ≤ 5s on
    /// RELEASE/SSD (Debug ceiling recorded like PERF-07). Prints
    /// META12-GATE for `.work/12/perf.md`. Also asserts the D-8 red line:
    /// thumb_state AND params_hash are 逐行 invariant.
    func testTenThousandSetRatingSegmentsOneAndTwoGate() async throws {
        try await buildMassFixture()
        try await openMassIndex()

        let rels = (0..<Self.massCount).map { "img\($0).ARW" }
        let before = try await store.fetchAllRows()

        let service = makeService(writer: nil) // the gate shape: segments 1+2
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await service.setRating(3, relPaths: rels)
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        print("META12-GATE setRating segments1+2 10k: \(String(format: "%.3f", seconds))s (gate ≤ 5.000s)")
        XCTAssertEqual(outcome.appliedRelPaths.count, Self.massCount)

        #if DEBUG
        XCTAssertLessThan(
            seconds, 20.0,
            "META-12 Debug sanity ceiling (the RELEASE ≤5s gate runs separately)")
        print("META12-GATE-CONFIG: Debug (the ≤5s gate = Release; this run is the harness record)")
        #else
        XCTAssertLessThan(seconds, 5.0, "META-12 GATE: segments 1+2 over 10k must stay under 5s")
        print("META12-GATE-CONFIG: Release (the ≤5s gate itself)")
        #endif

        // D-8 red line: thumbs and params are row-for-row invariant — a
        // ten-thousand-image rating sweep regenerates NOTHING.
        let after = try await store.fetchAllRows()
        XCTAssertEqual(after.count, before.count)
        for (old, new) in zip(before, after) {
            XCTAssertEqual(old.thumbState, new.thumbState, old.path)
            XCTAssertEqual(old.thumbParamsHash, new.thumbParamsHash, old.path)
            XCTAssertEqual(old.paramsHash, new.paramsHash, old.path)
            XCTAssertEqual(old.hasEdits, new.hasEdits, old.path)
            XCTAssertEqual(new.rating, 3, old.path)
            XCTAssertEqual(new.dirty, 1, "writer nil → rows stay honestly dirty")
        }
    }

    // MARK: - Crash injection (F6): zero three-state drift

    func testCrashBetweenClaimAndWriteHealsToOldValues() async throws {
        let rels = [
            try writeImage("a.arw", rating: 4),
            try writeImage("b.arw", rating: 4),
            try writeImage("c.arw", rating: 4),
        ]
        try await openIndex(rels)

        // The metadata write with a crash injected after the FIRST
        // segment-3 write (the process-death shape).
        let writer = BatchSidecarWriter(root: sessionRoot, store: store)
        await writer.armCrashInjectionForTesting()
        let service = makeService(writer: writer)
        let outcome = try await service.setRating(2, relPaths: rels)
        XCTAssertEqual(outcome.appliedRelPaths, rels)

        // The F6 window, observed live: exactly ONE row's sidecar landed
        // (dirty cleared); the other two carry the CLAIMED new value with
        // dirty=1 — the index is ahead of the disk, honestly flagged.
        let claimed = try await store.fetchAllRows()
        for row in claimed {
            XCTAssertEqual(row.rating, 2, "the claim landed on every row")
        }
        let written = rels[0] // FIFO queue order
        let writtenLiveRow = try await store.fetchRow(relPath: written)
        XCTAssertEqual(writtenLiveRow?.dirty, 0)
        for rel in rels.dropFirst() {
            let row = try await store.fetchRow(relPath: rel)
            XCTAssertEqual(row?.dirty, 1)
        }
        XCTAssertEqual(try readDiskDocument(rels[1]).rating, 4, "disk untouched yet")

        // "Process death": abandon the writer + its pending queue, close
        // the index, reopen — the heal leg must re-derive EVERY row from
        // the disk truth (zero three-state drift).
        await store.close()
        store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: scanOf(rels))

        let healed = try await store.fetchAllRows()
        XCTAssertEqual(healed.count, rels.count)
        for row in healed {
            XCTAssertEqual(row.dirty, 0, "the heal clears every dirty row")
            // Index == disk truth, row for row (the 三态一致性 proof).
            let disk = try readDiskDocument(row.path)
            XCTAssertEqual(row.rating, disk.rating.map(Int64.init), row.path)
            XCTAssertEqual(row.keywords, disk.keywords?.joined(separator: "|"), row.path)
            XCTAssertEqual(row.note, disk.note, row.path)
        }
        // The written row kept its NEW value; the UNWRITTEN rows healed
        // BACK to the old 4 (a claimed-but-unwritten rating did not lie).
        let writtenRow = try await store.fetchRow(relPath: written)
        XCTAssertEqual(writtenRow?.rating, 2)
        for rel in rels.dropFirst() {
            let row = try await store.fetchRow(relPath: rel)
            XCTAssertEqual(
                row?.rating, 4,
                "the crash rolled the unwritten claim back to the disk truth")
        }
    }
}
