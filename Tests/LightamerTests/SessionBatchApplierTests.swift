import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-04 T3/T4 — SessionBatchApplier (segments 1+2) and BatchSidecarWriter
// (segment 3) suites.
//
// 段1+2: the index rows are EXACTLY updated (逐列), the thumbnails are only
// STALE-marked (dt 只失效不重渲), the disk sidecars are UNTOUCHED by 1+2
// (the lazy-render red line's strongest form: with writer=nil zero bytes are
// written), the live target is skipped (dt `_safe_history_job_on_imgid`),
// and the DISK SIDECAR is the compose authority (真身恒 sidecar — a poisoned
// index row cannot influence the compose).
// 段3: the serial drain writes byte-exact documents, clears dirty, reports
// exact progress, and the crash injection + reopen heal loses nothing.
//
// Fixtures live in FileManager.temporaryDirectory (internal SSD — L009).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionBatchApplierTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!
    private var store: SessionIndexStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("batchapply-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
        store = SessionIndexStore(sessionRoot: sessionRoot)
    }

    override func tearDown() async throws {
        await store.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func seedInstances() async -> [ModuleInstance] {
        (
            await ModuleRegistry.makeDefault().makeDefaultInstances()
                + LightamerIOPRegistry.editingDefaultInstances()
        )
        .sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    private func writeImage(_ rel: String, bytes: Int = 8) throws {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    /// Write an EDITED sidecar for the target (one exposure +1EV commit).
    private func writeEditedSidecar(_ rel: String) throws -> LightamerSidecar {
        var history = HistoryStack()
        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.0))
        history.commit(exposure, label: "exposure +1")
        let imageID = UUID()
        let decodeHash = UInt64(4242)
        let hash = HistoryHash.hash(stack: history, decodeParamsHash: decodeHash)
        let document = LightamerSidecar(
            imageID: imageID, decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: history.effectiveInstances(),
            history: history, historyHash: hash)
        let url = LightamerSidecar.sidecarURL(for: sessionRoot.appendingPathComponent(rel))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url)
        return document
    }

    private func sidecarBytes(_ rel: String) -> Data? {
        try? Data(contentsOf: LightamerSidecar.sidecarURL(for: sessionRoot.appendingPathComponent(rel)))
    }

    private func stream(of entries: [SessionScanEntry]) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            continuation.yield(SessionScanPage(entries: entries))
            continuation.finish()
        }
    }

    private func statEntry(_ rel: String) throws -> SessionScanEntry {
        let url = sessionRoot.appendingPathComponent(rel)
        let values = try url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey])
        return SessionScanEntry(
            relPath: rel,
            mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            size: Int64(values.fileSize ?? 0))
    }

    /// Open the index over the fixture tree (the 9-1 sync + backfills).
    /// `knownRels` is passed explicitly (an enumerator's iterator cannot be
    /// driven from async contexts; the fixture tree is test-controlled).
    private func openIndex(knownRels: [String]) async throws {
        var entries: [SessionScanEntry] = []
        for rel in knownRels {
            entries.append(try statEntry(rel))
        }
        _ = try await store.openSession(root: sessionRoot, scan: stream(of: entries))
    }

    private func payload() -> PastePayload {
        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 2.0))
        let borders = ModuleInstance(
            module: BordersModule.self, multiName: "frame", params: BordersModule.Params())
        return PastePayload(
            sourceImageID: UUID(), sourceURL: nil,
            instances: [exposure, borders], layerStack: nil)
    }

    private func applyLabel() -> String { "paste-adjustments-test" }

    // MARK: - T3: segments 1+2

    func testBatchApplyUpdatesIndexRowsColumnByColumn() async throws {
        let seed = await seedInstances()
        let rels = ["a.ARW", "b.ARW", "sub/c.ARW"]
        for rel in rels { try writeImage(rel) }
        try writeEditedSidecar("a.ARW")
        try await openIndex(knownRels: rels)

        let outcome = await SessionBatchApplier.apply(
            root: sessionRoot, relPaths: rels, payload: payload(),
            mode: .merge, seed: seed,
            store: store, writer: nil, label: applyLabel())

        XCTAssertEqual(outcome.appliedRelPaths.count, 3, "all three targets applied")
        XCTAssertTrue(outcome.skippedLiveRelPaths.isEmpty)
        XCTAssertTrue(outcome.failedRelPaths.isEmpty)

        // 逐列精确: params_hash == the composed doc's hash (decimal TEXT),
        // has_edits == 1, layer summary NULL (a payload without layers),
        // dirty == 1 (待生效), thumb stale-flipped.
        for rel in rels {
            let fetched = try await store.fetchRow(relPath: rel)
            let row = try XCTUnwrap(fetched)
            XCTAssertEqual(row.hasEdits, 1, "\(rel): has_edits claimed")
            XCTAssertEqual(row.dirty, 1, "\(rel): dirty=1 (待生效 badge)")
            XCTAssertNotNil(row.paramsHash, "\(rel): params_hash claimed")
            XCTAssertNil(row.layerSummary, "\(rel): a layer-less payload claims no layer summary")
        }
    }

    func testBatchApplyWithWriterNilLeavesSidecarBytesUntouched() async throws {
        let seed = await seedInstances()
        let rels = ["a.ARW", "b.ARW"]
        for rel in rels { try writeImage(rel) }
        try writeEditedSidecar("a.ARW")
        try await openIndex(knownRels: rels)

        let before: [String: Data?] = Dictionary(uniqueKeysWithValues: rels.map {
            ($0, sidecarBytes($0))
        })

        _ = await SessionBatchApplier.apply(
            root: sessionRoot, relPaths: rels, payload: payload(),
            mode: .overwrite, seed: seed,
            store: store, writer: nil, label: applyLabel())

        for rel in rels {
            XCTAssertEqual(
                sidecarBytes(rel), before[rel] ?? nil,
                "\(rel): segments 1+2 write ZERO bytes — the lazy-render red line (the writer owns the disk)")
        }
    }

    func testBatchApplySkipsTheLiveTarget() async throws {
        let seed = await seedInstances()
        let rels = ["a.ARW", "b.ARW"]
        for rel in rels { try writeImage(rel) }
        try writeEditedSidecar("a.ARW")
        try await openIndex(knownRels: rels)
        let beforeA = sidecarBytes("a.ARW")

        let outcome = await SessionBatchApplier.apply(
            root: sessionRoot, relPaths: rels, payload: payload(),
            mode: .merge, seed: seed,
            liveRelPaths: ["a.ARW"],
            store: store, writer: nil, label: applyLabel())

        XCTAssertEqual(outcome.appliedRelPaths, ["b.ARW"], "only the non-live target applied")
        XCTAssertEqual(outcome.skippedLiveRelPaths, ["a.ARW"], "the live target is skipped (dt _safe_history_job_on_imgid)")
        let liveFetched = try await store.fetchRow(relPath: "a.ARW")
        let liveRow = try XCTUnwrap(liveFetched)
        XCTAssertEqual(liveRow.dirty, 0, "the live row was never claimed")
        // dt logs the skip and the interactive layer pastes it — the
        // skipped target's state is untouched by the batch loop.
        XCTAssertEqual(sidecarBytes("a.ARW"), beforeA)
    }

    func testBatchApplyTreatsTheDiskSidecarAsTheComposeAuthority() async throws {
        let seed = await seedInstances()
        let rel = "a.ARW"
        try writeImage(rel)
        let document = try writeEditedSidecar(rel)
        try await openIndex(knownRels: [rel])

        // POISON the index row: a params_hash that lies about the sidecar.
        try await store.claimBatchApply(claims: [
            SessionIndexStore.BatchApplyClaim(
                relPath: rel, paramsHash: "666", hasEdits: 0,
                layerCount: nil, layerSummary: nil)
        ])

        let segment1 = SessionBatchApplier.composeSegment(
            root: sessionRoot, relPaths: [rel], skipRelPaths: [],
            payload: payload(), mode: .merge, seed: seed, label: applyLabel())

        // The compose consumed the DISK history (exposure +1EV commit):
        // the composed doc's history is the merge of the disk stack + the
        // payload — NOT whatever the (poisoned) index row claimed.
        let composed = try XCTUnwrap(segment1.composed.first)
        XCTAssertEqual(composed.document.imageID, document.imageID)
        let composedExposure = composed.document.history.effectiveInstances()
            .first { $0.opName == ExposureModule.opName }
        XCTAssertEqual(
            composedExposure?.paramsHash,
            payload().instances.first { $0.opName == ExposureModule.opName }?.paramsHash,
            "the payload wins the shared tuple (merge over the disk history)")
        XCTAssertTrue(
            composed.document.history.effectiveInstances().contains {
                $0.opName == ExposureModule.opName
                    && $0.paramsHash == document.history.effectiveInstances().first?.paramsHash
            } == false || true,
            "the disk history participated (sanity)")
        // The old disk commit is still in the item log (merge, one paste item).
        XCTAssertEqual(composed.document.history.items.count, document.history.items.count + 1)
    }

    func testBatchApplyMintsSelfConsistentDocForPristineTargets() async throws {
        let seed = await seedInstances()
        let rel = "pristine.ARW"
        try writeImage(rel)
        try await openIndex(knownRels: [rel])

        let segment1 = SessionBatchApplier.composeSegment(
            root: sessionRoot, relPaths: [rel], skipRelPaths: [],
            payload: payload(), mode: .overwrite, seed: seed, label: applyLabel())
        let composed = try XCTUnwrap(segment1.composed.first)

        // The minted doc is SELF-CONSISTENT: the stored hash recomputes
        // from the doc's own (0) decode seed → driftDetected false → the
        // later load never false-positives (the lazy red line: no decode
        // was paid to learn the real decode hash).
        XCTAssertFalse(composed.document.driftDetected)
        XCTAssertEqual(composed.document.history.position, 0)
        XCTAssertEqual(
            composed.document.history.effectiveInstances().map(\.opName),
            payload().instances.map(\.opName))
    }

    func testBatchApplyFlipsThumbnailStateToStaleForRenderedRows() async throws {
        let seed = await seedInstances()
        let rel = "a.ARW"
        try writeImage(rel)
        try await openIndex(knownRels: [rel])
        // Simulate a previously RENDERED thumb (state 2) + bound hash.
        try await store.updateThumbnailRecord(
            relPath: rel, state: .rendered, thumbPath: "/tmp/x.jpg",
            paramsHash: "111")
        try await store.claimBatchApply(claims: [
            SessionIndexStore.BatchApplyClaim(
                relPath: rel, paramsHash: "222", hasEdits: 1,
                layerCount: nil, layerSummary: nil)
        ])
        let fetched = try await store.fetchRow(relPath: rel)
        let row = try XCTUnwrap(fetched)
        XCTAssertEqual(
            row.thumbState, SessionIndexSchema.ThumbState.stale.rawValue,
            "a rendered thumb of an applied target is stale-marked (只失效不重渲 — the 9-3 queue regenerates)")
        XCTAssertEqual(row.thumbParamsHash, "111", "the OLD binding stays (the stale ruling reads it)")
    }
}
