import CoreGraphics
import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-4 T2 — the PresetApplier suite. The core face:
//
//   • preset-apply == clipboard-paste TERMINAL STATE (the T7 equivalence):
//     identical pre-state targets, one path through PresetApplier (preset
//     file → loadDocument → payload), the other through the ⌘⇧V shape
//     (SessionBatchApplier.apply with the SAME payload construction) —
//     terminal INDEX ROWS equal field-for-field AND terminal SIDECAR BYTES
//     equal after canonicalizing ONLY the 9-4 recast instance UUIDs (the
//     recast namespace is by-design per-call random: PasteSemantics mints
//     fresh ids per paste; HistoryHash digests NO UUIDs, so the index
//     params_hash is invariant — everything else must be byte-identical)
//   • the semantic CONTRAST (12-1 vs 12-4): a preset apply flips
//     params_hash AND stales thumbnails (claimBatchApply); a metadata
//     write flips NEITHER (claimMetadataApply) — the two claims are
//     opposite by design, both asserted here
//   • partial apply = `payload.filtered(by:)` semantics (PRES-04)
//   • live protection + empty-preset no-op + export-kind typed rejection
//   • unknown-op preset instances carry VERBATIM through the batch (user
//     data never dropped) and degrade through the EXISTING load face —
//     no special-casing
//   • the 万张 gate: segments 1+2 over a 10k fixture (the PERF-07 shape;
//     Debug sanity ceiling — the ≤5s gate is RELEASE)
//
// Fixtures live in FileManager.temporaryDirectory (internal SSD — L009).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PresetApplierTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!
    private var presetsDirectory: URL!
    private var store: SessionIndexStore!
    private var presetsStore: PresetsStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("presetapply-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        presetsDirectory = tempDirectory.appendingPathComponent("presets", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
        store = SessionIndexStore(sessionRoot: sessionRoot)
        presetsStore = PresetsStore(directory: presetsDirectory)
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

    /// The preset's develop content: one exposure commit + one borders
    /// instance (the SessionBatchApplierTests payload's twin).
    private func presetInstances() -> [ModuleInstance] {
        [
            ModuleInstance(
                module: ExposureModule.self,
                params: ExposureModule.Params(exposure: 2.0)),
            ModuleInstance(
                module: BordersModule.self, multiName: "frame",
                params: BordersModule.Params()),
        ]
    }

    @discardableResult
    private func makeDevelopPreset(name: String = "Warm Film") throws -> StoredPreset {
        try presetsStore.create(
            name: name, kind: .develop, category: "Tone",
            instances: presetInstances())
    }

    /// Write an IDENTICAL pre-state sidecar for a target (one exposure
    /// +1EV commit) — both equivalence targets share the SAME document.
    private func writePreStateSidecar(_ rel: String) throws {
        var history = HistoryStack()
        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.0))
        history.commit(exposure, label: "exposure +1")
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8",
            decodeParamsHash: UInt64(4242),
            instances: history.effectiveInstances(),
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 4242))
        let url = LightamerSidecar.sidecarURL(for: sessionRoot.appendingPathComponent(rel))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url)
    }

    private func writeImage(_ rel: String) throws {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 8).write(to: url)
    }

    private func sidecarBytes(_ rel: String) -> Data? {
        try? Data(contentsOf: LightamerSidecar.sidecarURL(
            for: sessionRoot.appendingPathComponent(rel)))
    }

    private func stream(of entries: [SessionScanEntry]) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            continuation.yield(SessionScanPage(entries: entries))
            continuation.finish()
        }
    }

    private func openIndex(knownRels: [String]) async throws {
        var entries: [SessionScanEntry] = []
        for rel in knownRels {
            let url = sessionRoot.appendingPathComponent(rel)
            let values = try url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            entries.append(SessionScanEntry(
                relPath: rel,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0)))
        }
        _ = try await store.openSession(root: sessionRoot, scan: stream(of: entries))
    }

    /// The pinned apply inputs (both equivalence legs share them).
    private func pinnedTimestamp() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private func pinnedLabel() -> String { "apply-preset-equivalence" }

    /// Canonicalize the ONLY by-design variances between two apply calls —
    /// the recast instance UUID namespace (PasteSemantics mints fresh ids
    /// per paste), the minted history-item ids, the per-target imageID
    /// (different images), and the fixture's build-time commit stamp —
    /// then re-encode. Byte equality after this proves EVERYTHING else is
    /// identical: labels, paramsData, ordering, hash stamps, app version.
    private func canonicalizedBytes(_ document: LightamerSidecar) throws -> Data {
        var doc = document
        let pinnedStamp = Date(timeIntervalSince1970: 1_799_999_999)
        func fixed(_ n: Int) -> UUID {
            UUID(uuidString: String(format: "AAAAAAAA-0000-0000-0000-%012d", n))!
        }
        doc.imageID = fixed(99_999)
        doc.instances = doc.instances.enumerated().map { index, instance in
            var copy = instance
            copy.id = fixed(index)
            return copy
        }
        var items = doc.history.items
        for itemIndex in items.indices {
            let item = items[itemIndex]
            var snapshot = item.snapshot
            snapshot.id = fixed(20_000 + itemIndex)
            let pasteSet = item.pasteSet?.enumerated().map { setIndex, record in
                var copy = record
                copy.id = fixed(30_000 + setIndex)
                return copy
            }
            items[itemIndex] = HistoryStack.HistoryItem(
                id: fixed(10_000 + itemIndex),
                snapshot: snapshot,
                label: item.label,
                timestamp: pinnedStamp,
                layerScope: item.layerScope,
                stackSnapshot: item.stackSnapshot,
                pasteSet: pasteSet)
        }
        doc.history = HistoryStack(items: items, position: doc.history.position)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(doc)
    }

    // MARK: - THE equivalence (T7): preset-apply == clipboard-paste

    func testPresetApplyEqualsClipboardPasteTerminalState() async throws {
        let seed = await seedInstances()
        // Two targets sharing the IDENTICAL pre-state document.
        try writeImage("a.ARW")
        try writeImage("b.ARW")
        try writePreStateSidecar("a.ARW")
        try writePreStateSidecar("b.ARW")
        try await openIndex(knownRels: ["a.ARW", "b.ARW"])
        let preset = try makeDevelopPreset()

        let writer = BatchSidecarWriter(root: sessionRoot, store: store)
        let timestamp = pinnedTimestamp()
        let label = pinnedLabel()

        // Path 1: PRESET apply (preset file → loadDocument → payload →
        // the 9-4 face).
        let presetOutcome = try await PresetApplier.apply(
            presetID: preset.id, presetsStore: presetsStore,
            root: sessionRoot, relPaths: ["a.ARW"], mode: .merge,
            seed: seed, indexStore: store, writer: writer,
            timestamp: timestamp, label: label)

        // Path 2: CLIPBOARD paste (the ⌘⇧V batch shape: the SAME payload
        // construction over the SAME document → the SAME 9-4 face).
        let payload = PresetApplier.makePayload(
            from: presetsStore.presets()[0].document,
            copiedAt: PresetApplier.fileTime(store: presetsStore, presetID: preset.id))
        let pasteOutcome = await SessionBatchApplier.apply(
            root: sessionRoot, relPaths: ["b.ARW"], payload: payload,
            mode: .merge, seed: seed,
            store: store, writer: writer,
            timestamp: timestamp, label: label)

        XCTAssertEqual(presetOutcome.appliedRelPaths, ["a.ARW"])
        XCTAssertEqual(pasteOutcome.appliedRelPaths, ["b.ARW"])

        // ── Terminal INDEX ROWS: field-for-field EQUAL (HistoryHash folds
        // no UUIDs, so even params_hash agrees).
        let rowAOpt = try await store.fetchRow(relPath: "a.ARW")
        let rowBOpt = try await store.fetchRow(relPath: "b.ARW")
        let rowA = try XCTUnwrap(rowAOpt)
        let rowB = try XCTUnwrap(rowBOpt)
        XCTAssertEqual(rowA.paramsHash, rowB.paramsHash)
        XCTAssertEqual(rowA.hasEdits, rowB.hasEdits)
        XCTAssertEqual(rowA.layerCount, rowB.layerCount)
        XCTAssertEqual(rowA.layerSummary, rowB.layerSummary)
        XCTAssertEqual(rowA.dirty, rowB.dirty, "both drained by the shared writer")
        XCTAssertEqual(rowA.thumbState, rowB.thumbState)

        // ── Terminal SIDECAR BYTES: equal after canonicalizing ONLY the
        // recast UUID namespace — the strongest byte-equality the 9-4
        // per-paste recast permits.
        let bytesA = try XCTUnwrap(sidecarBytes("a.ARW"))
        let bytesB = try XCTUnwrap(sidecarBytes("b.ARW"))
        let docA = try JSONDecoder().decode(LightamerSidecar.self, from: bytesA)
        let docB = try JSONDecoder().decode(LightamerSidecar.self, from: bytesB)
        let canonA = try canonicalizedBytes(docA)
        let canonB = try canonicalizedBytes(docB)
        XCTAssertEqual(canonA, canonB,
                       "preset apply and clipboard paste land the SAME terminal document")
        XCTAssertFalse(docA.driftDetected)
        XCTAssertFalse(docB.driftDetected)
        // The labels and item shapes agree (the label is the history face
        // the user reads in both paths).
        XCTAssertEqual(
            docA.history.items.map(\.label), docB.history.items.map(\.label))
        XCTAssertEqual(docA.history.items.last?.label, label)
    }

    // MARK: - The semantic contrast (12-1 metadata vs 12-4 preset)

    func testPresetApplyFlipsThumbAndParamsWhileMetadataPathDoesNot() async throws {
        let seed = await seedInstances()
        let presetRel = "p.ARW"
        let metadataRel = "m.ARW"
        for rel in [presetRel, metadataRel] { try writeImage(rel) }
        try await openIndex(knownRels: [presetRel, metadataRel])
        // Both rows: a previously RENDERED thumb bound to a hash.
        for rel in [presetRel, metadataRel] {
            try await store.updateThumbnailRecord(
                relPath: rel, state: .rendered, thumbPath: "/tmp/x.jpg",
                paramsHash: "111")
        }
        let preset = try makeDevelopPreset()

        // 12-4 path: the preset FLIPS params (the claim marks「待生效」)
        // and the rendered thumb goes STALE (只失效不重渲 — 9-3 regenerates).
        _ = try await PresetApplier.apply(
            presetID: preset.id, presetsStore: presetsStore,
            root: sessionRoot, relPaths: [presetRel], mode: .merge,
            seed: seed, indexStore: store, writer: nil,
            timestamp: pinnedTimestamp(), label: pinnedLabel())
        let presetRowOpt = try await store.fetchRow(relPath: presetRel)
        let presetRow = try XCTUnwrap(presetRowOpt)
        XCTAssertEqual(presetRow.thumbState, SessionIndexSchema.ThumbState.stale.rawValue,
                       "a preset flips params → the thumb is STALE (claimBatchApply)")
        XCTAssertEqual(presetRow.dirty, 1, "claimed 待生效 (segments 1+2 gate shape)")
        XCTAssertNotNil(presetRow.paramsHash, "the claim flips params_hash")
        XCTAssertEqual(presetRow.thumbParamsHash, "111",
                       "the OLD thumb binding stays (the stale ruling reads it)")

        // 12-1 path (the contrast): a metadata write flips NEITHER.
        let service = MetadataService(
            root: sessionRoot, store: store, writer: nil, seed: seed)
        _ = try await service.setRating(4, relPaths: [metadataRel])
        let metadataRowOpt = try await store.fetchRow(relPath: metadataRel)
        let metadataRow = try XCTUnwrap(metadataRowOpt)
        XCTAssertEqual(metadataRow.thumbState, SessionIndexSchema.ThumbState.rendered.rawValue,
                       "a rating is NOT a params change → the thumb stays (claimMetadataApply)")
        XCTAssertNil(metadataRow.paramsHash, "params_hash untouched by metadata (never claimed)")
        XCTAssertEqual(metadataRow.thumbParamsHash, "111", "the thumb binding is untouched")
        XCTAssertEqual(metadataRow.rating, Int64(4))
    }

    // MARK: - Partial apply (PRES-04 selection semantics)

    func testPartialApplyAppliesOnlyTheCheckedSubset() async throws {
        let seed = await seedInstances()
        let rel = "a.ARW"
        try writeImage(rel)
        try writePreStateSidecar(rel)
        try await openIndex(knownRels: [rel])
        let preset = try makeDevelopPreset()

        // The dialog checks ONLY the exposure instance.
        let exposureKey = PastePayload.InstanceKey(
            opName: ExposureModule.opName, multiPriority: 0, multiName: "")
        let writer = BatchSidecarWriter(root: sessionRoot, store: store)
        _ = try await PresetApplier.apply(
            presetID: preset.id, presetsStore: presetsStore,
            root: sessionRoot, relPaths: [rel], mode: .merge,
            seed: seed, selection: [exposureKey],
            indexStore: store, writer: writer,
            timestamp: pinnedTimestamp(), label: "partial-apply")

        let bytes = try XCTUnwrap(sidecarBytes(rel))
        let document = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        // The paste landed the exposure VALUE but not the borders record.
        let applied = document.history.items.last?.pasteRecords ?? []
        XCTAssertEqual(applied.map(\.opName), [ExposureModule.opName],
                       "the checked subset is the whole paste set")
        // The merge won the shared tuple with the payload's exposure value.
        let exposure = document.instances.first { $0.opName == ExposureModule.opName }
        XCTAssertEqual(
            exposure?.paramsHash,
            presetInstances().first { $0.opName == ExposureModule.opName }?.paramsHash,
            "the preset's exposure value won")
        XCTAssertNil(
            document.instances.first { $0.opName == BordersModule.opName },
            "the unchecked borders record never landed")
    }

    // MARK: - Live protection + no-op + typed rejections (inherited faces)

    func testLiveTargetIsSkippedAndUntouched() async throws {
        let seed = await seedInstances()
        try writeImage("live.ARW")
        try writeImage("other.ARW")
        try writePreStateSidecar("live.ARW")
        try await openIndex(knownRels: ["live.ARW", "other.ARW"])
        let preset = try makeDevelopPreset()
        let beforeLive = sidecarBytes("live.ARW")

        let outcome = try await PresetApplier.apply(
            presetID: preset.id, presetsStore: presetsStore,
            root: sessionRoot, relPaths: ["live.ARW", "other.ARW"],
            mode: .merge, seed: seed, liveRelPaths: ["live.ARW"],
            indexStore: store, writer: nil,
            timestamp: pinnedTimestamp(), label: pinnedLabel())

        XCTAssertEqual(outcome.appliedRelPaths, ["other.ARW"])
        XCTAssertEqual(outcome.skippedLiveRelPaths, ["live.ARW"])
        XCTAssertEqual(sidecarBytes("live.ARW"), beforeLive,
                       "the live target is the interactive layer's business")
    }

    func testEmptyPresetNoOpsEveryTarget() async throws {
        let seed = await seedInstances()
        let rel = "a.ARW"
        try writeImage(rel)
        try writePreStateSidecar(rel)
        try await openIndex(knownRels: [rel])
        let empty = try presetsStore.create(
            name: "Empty", kind: .develop, instances: [])

        let outcome = try await PresetApplier.apply(
            presetID: empty.id, presetsStore: presetsStore,
            root: sessionRoot, relPaths: [rel], mode: .merge,
            seed: seed, indexStore: store, writer: nil,
            timestamp: pinnedTimestamp(), label: "noop")
        XCTAssertTrue(outcome.appliedRelPaths.isEmpty)
        XCTAssertEqual(outcome.skippedLiveRelPaths, [rel],
                       "an empty payload pastes nothing (dt posture)")
        // The pre-state sidecar was never rewritten.
        let bytes = try XCTUnwrap(sidecarBytes(rel))
        let document = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertEqual(document.history.items.count, 1)
    }

    func testExportPresetIsTypedNotApplicable() async throws {
        let seed = await seedInstances()
        try writeImage("a.ARW")
        try await openIndex(knownRels: ["a.ARW"])
        let exportPreset = try presetsStore.create(
            name: "Web 2000", kind: .export,
            exportRecipe: [
                ExportVariant(format: .jpeg(quality: 0.9), colorSpace: .sRGB)
            ])

        do {
            _ = try await PresetApplier.apply(
                presetID: exportPreset.id, presetsStore: presetsStore,
                root: sessionRoot, relPaths: ["a.ARW"], mode: .merge,
                seed: seed, indexStore: store, writer: nil,
                timestamp: pinnedTimestamp(), label: "wrong door")
            XCTFail("an export preset must not enter the develop pipeline")
        } catch let error as PresetApplier.ApplyError {
            XCTAssertEqual(error, .exportPresetNotApplicable(name: "Web 2000"))
        }
    }

    // MARK: - Unknown-op preset instances (no special-casing)

    func testUnknownOpCarriesVerbatimThroughBatchAndDegradesAtLoadFace() async throws {
        let seed = await seedInstances()
        let rel = "a.ARW"
        try writeImage(rel)
        try writePreStateSidecar(rel)
        try await openIndex(knownRels: [rel])

        // A preset written by a FUTURE binary: an op this build cannot
        // construct, params bytes preserved verbatim (L013 projection).
        let futureOp = ModuleInstance(
            id: UUID(), opName: "ghost-future-op", multiPriority: 0,
            multiName: "", iopOrder: 40.0, version: 1, enabled: true,
            paramsData: Data("future-bytes".utf8), paramsHash: 42)
        try presetsStore.create(name: "From The Future", kind: .develop,
                                instances: [futureOp])
        let presetID = presetsStore.presets()[0].id

        let writer = BatchSidecarWriter(root: sessionRoot, store: store)
        _ = try await PresetApplier.apply(
            presetID: presetID, presetsStore: presetsStore,
            root: sessionRoot, relPaths: [rel], mode: .merge,
            seed: seed, indexStore: store, writer: writer,
            timestamp: pinnedTimestamp(), label: "future-op")

        // The batch carried the record VERBATIM (user data never dropped).
        let bytes = try XCTUnwrap(sidecarBytes(rel))
        let document = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        let carried = document.instances.first { $0.opName == "ghost-future-op" }
        XCTAssertEqual(carried?.paramsData, Data("future-bytes".utf8))
        XCTAssertTrue(carried?.enabled ?? false)

        // The EXISTING load face reacts (the toast vector) and flips the
        // unknown op's snapshot disabled — the bytes survive for a future
        // binary. The batch path adds NOTHING special.
        let registry = ModuleRegistry.makeDefault()
        let (degraded, unknownOps) = await document.degradedForUnknownOps(
            registry: registry)
        XCTAssertTrue(unknownOps.contains("ghost-future-op"))
        let ghostItem = degraded.items.first {
            $0.snapshot.opName == "ghost-future-op"
        }
        XCTAssertEqual(ghostItem?.snapshot.enabled, false,
                       "the existing face disables the unknown op")
        XCTAssertEqual(ghostItem?.snapshot.paramsData, Data("future-bytes".utf8),
                       "the degrade keeps the bytes for a future binary")
    }

    // MARK: - The 万张 gate (PERF-07 fixture shape; segments 1+2)

    private static let massCount = 10_000

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
                instances: history.effectiveInstances(),
                history: history,
                historyHash: HistoryHash.hash(stack: history, decodeParamsHash: decodeHash),
                appVersion: "preset-gate", layerStack: nil)
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

    func testTenThousandPresetApplySegmentsOneAndTwoGate() async throws {
        try await buildMassFixture()
        try await openMassIndex()
        let seed = await seedInstances()
        let preset = try makeDevelopPreset()
        let rels = (0..<Self.massCount).map { "img\($0).ARW" }

        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await PresetApplier.apply(
            presetID: preset.id, presetsStore: presetsStore,
            root: sessionRoot, relPaths: rels, mode: .merge,
            seed: seed, indexStore: store, writer: nil,
            timestamp: pinnedTimestamp(), label: "preset-gate")
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        print("PRESET12-GATE preset apply segments1+2 10k: \(String(format: "%.3f", seconds))s (gate ≤ 5.000s)")
        XCTAssertEqual(outcome.appliedRelPaths.count, Self.massCount)

        #if DEBUG
        XCTAssertLessThan(
            seconds, 20.0,
            "PRESET-12 Debug sanity ceiling (the RELEASE ≤5s gate runs separately)")
        print("PRESET12-GATE-CONFIG: Debug (the ≤5s gate = Release; this run is the harness record)")
        #else
        XCTAssertLessThan(seconds, 5.0,
                          "PRESET-12 GATE: segments 1+2 over 10k must stay under 5s")
        print("PRESET12-GATE-CONFIG: Release (the ≤5s gate itself)")
        #endif

        // The claim shape spot-check: claimed + stale-flipped per row.
        for index in [0, 5000, Self.massCount - 1] {
            let row = try await store.fetchRow(relPath: "img\(index).ARW")
            let fetched = try XCTUnwrap(row)
            XCTAssertEqual(fetched.dirty, 1)
        }    }
}
