import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// PERF-07 (Plan 09-04 T5) — the mass-apply measurement gate:
//
//   GATE: segments 1+2 (memory compose + index single transaction) over a
//   10k-sidecar fixture ≤ 5 s wall clock. The plan pins the gate at
//   RELEASE on an internal SSD; the Debug harness number is recorded
//   alongside (test-direct.sh is Debug-anchored — the 09-3 ledger note).
//   The fixture is built in FileManager.temporaryDirectory (internal SSD —
//   L009: the external volume USB volume is FORBIDDEN for gate numbers; its drain
//   figure is recorded as a labeled comparison only).
//
//   RECORD-ONLY: segment-3 drain throughput (the serial sidecar write
//   queue — minutes-level on USB is the documented expectation, dt puts
//   its XMP sync outside the loop for the same reason) and the external volume
//   per-write comparison.
//
// The fixture's "originals" are 8-byte placeholders (apply NEVER decodes —
// the lazy red line), the `.lra` documents are REAL JSON.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class Perf07MassApplyTests: XCTestCase {

    private static let count = 10_000

    private var tempDirectory: URL!
    private var sessionRoot: URL!
    private var store: SessionIndexStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("perf07-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Fixture

    /// 10k × (8-byte placeholder original + real `.lra` JSON with a one-
    /// commit history). Returns the build wall clock (recorded, not gated).
    private func buildFixture() async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let captureDate = Date(timeIntervalSince1970: 1_770_000_000)

        // Encode ONE document template and vary the identity fields per
        // file (the JSON encode dominates; 10k distinct docs are needed
        // because apply DECODES every one of them in segment 1).
        for index in 0..<Self.count {
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
                appVersion: "perf07",
                layerStack: nil)
            let sidecarURL = LightamerSidecar.sidecarURL(for: url)
            try encoder.encode(document).write(to: sidecarURL)
        }
        _ = captureDate
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
    }

    private func openIndex() async throws {
        let encoder = JSONEncoder()
        var entries: [SessionScanEntry] = []
        for index in 0..<Self.count {
            let rel = "img\(index).ARW"
            let url = sessionRoot.appendingPathComponent(rel)
            let sidecar = LightamerSidecar.sidecarURL(for: url)
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            entries.append(SessionScanEntry(
                relPath: rel,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0)))
            // The scan's sidecar-presence stat touches the .lra once; the
            // backfill then DECODES every sidecar — the open leg is not
            // part of the gate, but its cost must not silently rot either,
            // so its wall clock is printed for the ledger.
            _ = encoder
            _ = sidecar
        }
        let scan = AsyncStream<SessionScanPage> { continuation in
            // One page per 1000 (the stream seam; page size is irrelevant
            // to the gate).
            for chunk in stride(from: 0, to: entries.count, by: 1000) {
                continuation.yield(
                    SessionScanPage(entries: Array(entries[chunk..<min(chunk + 1000, entries.count)])))
            }
            continuation.finish()
        }
        _ = try await store.openSession(root: sessionRoot, scan: scan)
    }

    private func payload() -> PastePayload {
        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.5))
        return PastePayload(
            sourceImageID: UUID(), sourceURL: nil,
            instances: [exposure], layerStack: nil)
    }

    private func seedInstances() async -> [ModuleInstance] {
        (
            await ModuleRegistry.makeDefault().makeDefaultInstances()
                + LightamerIOPRegistry.editingDefaultInstances()
        )
        .sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    // MARK: - The gate

    /// PERF-07 GATE: segments 1+2 over 10k ≤ 5 s (RELEASE on internal SSD).
    /// Prints PERF07-GATE for the perf.md ledger.
    func testTenThousandMassApplySegmentOneAndTwoGate() async throws {
        let buildSeconds = try await buildFixture()
        print("PERF07-FIXTURE-BUILD: \(String(format: "%.3f", buildSeconds))s")
        let openStart = ContinuousClock.now
        try await openIndex()
        let openElapsed = ContinuousClock.now - openStart
        print(
            "PERF07-OPEN-10k: \(String(format: "%.3f", Double(openElapsed.components.seconds) + Double(openElapsed.components.attoseconds) / 1e18))s (not gated)")

        let seed = await seedInstances()
        let rels = (0..<Self.count).map { "img\($0).ARW" }

        let clock = ContinuousClock()
        let start = clock.now
        let s1a = clock.now
        let segment1 = SessionBatchApplier.composeSegment(
            root: sessionRoot, relPaths: rels, skipRelPaths: [],
            payload: payload(), mode: .merge, seed: seed, label: "perf07")
        let s1 = clock.now - s1a
        let s1s = String(format: "%.3f", Double(s1.components.seconds) + Double(s1.components.attoseconds) / 1e18)
        print("PERF07-PROBE composeSegment: \(s1s)s")
        let s2a = clock.now
        try await store.claimBatchApply(claims: segment1.composed.map { relPath, document in
            SessionIndexStore.BatchApplyClaim(
                relPath: relPath, paramsHash: String(document.historyHash),
                hasEdits: 1, layerCount: nil, layerSummary: nil)
        })
        let s2 = clock.now - s2a
        let s2s = String(format: "%.3f", Double(s2.components.seconds) + Double(s2.components.attoseconds) / 1e18)
        print("PERF07-PROBE claimBatchApply: \(s2s)s")
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        print("PERF07-GATE segments1+2 10k: \(String(format: "%.3f", seconds))s (gate ≤ 5.000s)")
        XCTAssertEqual(segment1.composed.count, Self.count, "every target claimed")

        #if DEBUG
        // Debug gate: the plan's 5s gate is a RELEASE number; Debug pays
        // unoptimized JSON decode on all 10k sidecars. The Debug ceiling is
        // recorded (not gated) — assert a generous 4× ceiling so a rot is
        // still caught in the Debug harness.
        XCTAssertLessThan(
            seconds, 20.0,
            "PERF-07 Debug sanity ceiling (the RELEASE gate ≤5s runs separately)")
        print("PERF07-GATE-CONFIG: Debug (the ≤5s gate = Release; this run is the harness record)")
        #else
        XCTAssertLessThan(
            seconds, 5.0,
            "PERF-07 GATE: segments 1+2 over 10k must stay under 5s (Release, SSD)")
        print("PERF07-GATE-CONFIG: Release (the ≤5s gate itself)")
        #endif

        // Spot-verify the claim state on a few rows.
        for index in [0, 5000, Self.count - 1] {
            let row = try await store.fetchRow(relPath: "img\(index).ARW")
            XCTAssertEqual(try XCTUnwrap(row).dirty, 1)
        }
    }

    // MARK: - Record-only: segment-3 drain throughput

    func testSegmentThreeDrainThroughputRecord() async throws {
        try await buildFixture()
        try await openIndex()
        let seed = await seedInstances()
        let rels = (0..<Self.count).map { "img\($0).ARW" }

        let writer = BatchSidecarWriter(root: sessionRoot, store: store)
        let clock = ContinuousClock()
        let start = clock.now
        _ = await SessionBatchApplier.apply(
            root: sessionRoot, relPaths: rels, payload: payload(),
            mode: .overwrite, seed: seed,
            store: store, writer: writer, label: "perf07")
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print(
            "PERF07-SEGMENT3-SSD drain 10k: \(String(format: "%.3f", seconds))s (\(String(format: "%.0f", Double(Self.count) / max(seconds, 0.001))) docs/s) — record only, never gated")

        let pending = await writer.pendingCountForTesting
        XCTAssertEqual(pending, 0, "the drain completed")
    }

    /// The external-volume (USB HDD) per-write comparison — a 100-doc
    /// sample on the comparison volume, recorded and NEVER gated (L009: the
    /// gate fixture is forbidden there). Set LA_PERF07_VOLUME to the volume
    /// root on the machine that records the metric; unset or absent volume
    /// skips (other machines).
    func testExternalVolumeDrainComparisonRecordOnly() async throws {
        guard let volumeRoot = ProcessInfo.processInfo.environment["LA_PERF07_VOLUME"] else {
            throw XCTSkip("LA_PERF07_VOLUME unset — comparison recorded on the volume-bearing machine only")
        }
        let comparisonRoot = URL(fileURLWithPath: volumeRoot)
        guard FileManager.default.fileExists(atPath: comparisonRoot.path) else {
            throw XCTSkip("LA_PERF07_VOLUME target absent — comparison recorded on the volume-bearing machine only")
        }
        let sample = 100
        let temp = comparisonRoot.appendingPathComponent("Documents/Development/Lightamer/.work/tmp-perf07-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let clock = ContinuousClock()
        let start = clock.now
        for index in 0..<sample {
            let url = temp.appendingPathComponent("img\(index).ARW.lra")
            var history = HistoryStack()
            history.commit(
                ModuleInstance(
                    module: ExposureModule.self, multiName: "e\(index)",
                    params: ExposureModule.Params(exposure: 1.0)),
                label: "exposure")
            let document = LightamerSidecar(
                imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 1,
                instances: history.effectiveInstances(), history: history,
                historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 1),
                appVersion: "perf07", layerStack: nil)
            try encoder.encode(document).write(to: url)
        }
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print(
            "PERF07-SEGMENT3-external volume sample \(sample) raw JSON writes: \(String(format: "%.3f", seconds))s (\(String(format: "%.1f", Double(sample) / max(seconds, 0.001) / 1000)) ms/doc) — record only (L009 volume)")
        XCTAssertLessThan(seconds, 60.0, "a pathological stall guard, not a gate")
    }
}
