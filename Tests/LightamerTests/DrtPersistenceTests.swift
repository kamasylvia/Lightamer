import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// DrtPersistenceTests (Plan M2-6-3 T1, AC#1 — APP bundle, SidecarV5Tests
// precedent) — the DRT persistence four-piece transaction (KD-1, the
// rawOverrides shape):
//
//   1. CARRIER: per-url isolation; a DEFAULT record never occupies the map
//      (KD-1: 默认记录不写 sidecar); the editor-close drop face.
//   2. HISTORY ADDITIVE: the HistoryItem `drtRecord` field round-trips;
//      pre-M2-6-3 items (nil) keep their canonical bytes; the DRT item's
//      placeholder snapshot never pollutes the projections (the
//      drtDocumentScope ignore face).
//   3. historyHash FOLD (set-fields-move): a DRT edit moves the anchor;
//      an undo across the item moves it back; a history with NO DRT item
//      hashes BIT-IDENTICALLY to the pre-M2-6-3 formula.
//   4. COMMIT/UNDO/REDO end-to-end: recordDrtChange lands EXACTLY ONE item
//      (the preset single-commit shape), the carrier re-syncs on every
//      navigation face; the flushed FILE carries the displayTransform field
//      AND the history item (the fold formula's two halves agree —
//      driftDetected false); undo → flush → the key is ABSENT again (the
//      v5 byte shape restored).
//   5. RESTORE LEG: pristine doc → zero priming; a doc with the field →
//      the carrier primes and the record round-trips.
// ─────────────────────────────────────────────────────────────────────────────

final class DrtPersistenceTests: XCTestCase {

    /// Canonical JSON (the D-S2 writer convention).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    /// A non-pristine record (peak moved off the default 100).
    private static func editedRecord(peak: Float = 480) -> DrtRecord {
        var record = DrtRecord()
        record.peakLuminance = peak
        return record
    }

    // MARK: - 1: the session carrier (rawOverrides shape)

    /// Per-url isolation + the default-absence rule + the close drop.
    @MainActor
    func testCarrierPerUrlIsolationAndDefaultAbsence() {
        let workspace = WorkspaceModel()
        let urlA = URL(fileURLWithPath: "/tmp/drt-a.arw")
        let urlB = URL(fileURLWithPath: "/tmp/drt-b.arw")

        // Read face: absent key = pristine.
        XCTAssertEqual(workspace.drtRecord(for: urlA), DrtRecord())
        XCTAssertFalse(workspace.hasDrtRecord(for: urlA))

        // A DEFAULT record never occupies the map (KD-1: the sidecar key
        // stays absent for pristine — the map is the non-pristine truth).
        workspace.setSessionDrtRecord(DrtRecord(), for: urlA)
        XCTAssertFalse(
            workspace.hasDrtRecord(for: urlA),
            "a default record must not occupy the carrier (absent-key = pristine)")

        // Non-default records isolate per url.
        workspace.setSessionDrtRecord(Self.editedRecord(peak: 300), for: urlA)
        workspace.setSessionDrtRecord(Self.editedRecord(peak: 900), for: urlB)
        XCTAssertEqual(workspace.drtRecord(for: urlA).peakLuminance, 300)
        XCTAssertEqual(workspace.drtRecord(for: urlB).peakLuminance, 900)
        XCTAssertTrue(workspace.hasDrtRecord(for: urlA))
        XCTAssertTrue(workspace.hasDrtRecord(for: urlB))

        // Undoing back to pristine through the carrier face drops the key.
        workspace.setSessionDrtRecord(nil, for: urlA)
        XCTAssertFalse(workspace.hasDrtRecord(for: urlA))
        XCTAssertTrue(workspace.hasDrtRecord(for: urlB), "the sibling url is untouched")

        // R6: the editor close KEEPS the carrier (the M8-FIX-1 process
        // deviation extended to the DRT sister). The disease chain: a
        // same-image reopen runs NO load leg (the historyLoadedURL +
        // loadedImageURL guards both skip), so a close-time drop left
        // `terminalTailPolicy`'s two read faces — hasDrtRecord + the
        // record read — answering pristine/off until the next DRT
        // commit/navigation re-synced the carrier, while the panel read
        // the history projection and masked the loss (the omp M-1 chain's
        // DRT twin, M8-FIX-1-DECISIONS §1.6).
        workspace.setSessionDrtRecord(Self.editedRecord(peak: 650), for: urlA)
        XCTAssertTrue(workspace.hasDrtRecord(for: urlA))
        workspace.closeEditor()
        XCTAssertTrue(
            workspace.hasDrtRecord(for: urlA),
            "close must keep the DRT carrier — the reopen runs no load leg")
        XCTAssertEqual(
            workspace.drtRecord(for: urlA).peakLuminance, 650,
            "the render gate's record read must answer the retained record")
    }

    // MARK: - 2: the additive history item

    func testDrtHistoryItemRoundTripsAndNilKeepsCanonicalBytes() throws {
        // A nil-drtRecord item encodes WITHOUT the key (the pre-M2-6-3
        // byte shape — zero drift for older documents).
        let instance = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        let plain = HistoryStack.HistoryItem(
            snapshot: instance, label: "Exposure")
        let plainBytes = try Self.canonicalEncoder.encode(plain)
        XCTAssertFalse(
            String(decoding: plainBytes, as: UTF8.self).contains("drtRecord"),
            "writers omit the key when nil (encodeIfPresent)")
        let plainDecoded = try Self.decoder.decode(
            HistoryStack.HistoryItem.self, from: plainBytes)
        XCTAssertNil(plainDecoded.drtRecord)

        // A DRT item round-trips the record verbatim.
        let drt = HistoryStack.HistoryItem(
            snapshot: instance, label: "drt", layerScope: HistoryStack.drtDocumentScope,
            drtRecord: Self.editedRecord())
        let drtDecoded = try Self.decoder.decode(
            HistoryStack.HistoryItem.self, from: Self.canonicalEncoder.encode(drt))
        XCTAssertEqual(drtDecoded.drtRecord, Self.editedRecord())
    }

    func testOldDocumentWithoutDrtFieldsDecodesZeroDrift() throws {
        // A pre-M2-6-3 document (items carry NO drtRecord key) round-trips
        // with nil and the anchor recomputes clean — the zero-drift gate.
        let instance = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        var forged = HistoryStack()
        forged.commit(instance, label: "Exposure")
        let decodeHash = UInt64(42)
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash, instances: [], history: forged,
            historyHash: HistoryHash.hash(
                stack: forged, decodeParamsHash: decodeHash, layerSnapshot: nil),
            appVersion: "test")
        let bytes = try Self.canonicalEncoder.encode(document)
        XCTAssertFalse(
            String(decoding: bytes, as: UTF8.self).contains("drtRecord"),
            "a document without DRT edits carries no drtRecord key anywhere")
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: bytes)
        XCTAssertNil(decoded.history.items.first?.drtRecord)
        XCTAssertNil(decoded.displayTransform)
        XCTAssertFalse(
            decoded.driftDetected,
            "no DRT item → the anchor is the pre-M2-6-3 formula, recomputed clean")
    }

    // MARK: - 3: the historyHash fold (set-fields-move)

    func testHistoryHashFoldMovesWithDrtAndStaysBitIdenticalWithout() {
        let instance = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        var stack = HistoryStack()
        stack.commit(instance, label: "Exposure")
        let decodeHash = UInt64(0x1234_5678_9ABC_DEF0)

        // A history with NO DRT item: the 4-argument form is BIT-IDENTICAL
        // to the pre-M2-6-3 3-argument formula (the regression gate).
        let base = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil)
        let withEmptyFold = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: stack.effectiveDrtRecord())
        XCTAssertEqual(
            base, withEmptyFold,
            "no DRT item → the anchor must not move (bit-identical)")

        // The DRT commit moves the anchor (set-fields-move, OQ-2-A).
        stack.commitDrt(
            record: Self.editedRecord(), placeholder: instance, label: "drt")
        let folded = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: stack.effectiveDrtRecord())
        XCTAssertNotEqual(folded, base, "a DRT edit must move the drift anchor")

        // An undo across the item moves it back (time-travel safety).
        stack.undo()
        let undone = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: stack.effectiveDrtRecord())
        XCTAssertEqual(undone, base, "undo across the DRT item restores the anchor")

        // A DIFFERENT record folds differently (the record hash is the fold).
        stack.redo()
        stack.commitDrt(
            record: Self.editedRecord(peak: 999), placeholder: instance, label: "drt")
        let refolded = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: stack.effectiveDrtRecord())
        XCTAssertNotEqual(refolded, folded)
    }

    // MARK: - 4: the commit / undo / redo end-to-end

    /// The production composition minus windowing (SidecarV5Tests' shape).
    @MainActor
    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator,
        workspace: WorkspaceModel, metal: MetalContext
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, workspace, metal)
    }

    /// Synthetic gradient plane (EditorMetalLegRegressionTests' shape).
    nonisolated private static func decodedGradient(size: Int = 160) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    @MainActor
    private func loadGradient(
        _ url: URL, into coordinator: PipeCoordinator, metal: MetalContext
    ) async throws {
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    /// Bounded flush-until-persisted: the 2s-throttle store writes only
    /// when a schedule landed; the commit notification's re-render must
    /// settle first, so poll-flush until the FILE appears (SidecarV5Tests'
    /// readback-wait shape, file-existence flavor).
    @MainActor
    private func flushUntilPersisted(
        _ sidecarURL: URL, _ coordinator: PipeCoordinator, timeout: TimeInterval = 10
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                // Give the write task itself a beat to finish the rename.
                try await Task.sleep(for: .milliseconds(100))
                return
            }
            try await Task.sleep(for: .milliseconds(100))
            await coordinator.flushSidecar()
        }
        XCTFail("the sidecar file never appeared: \(sidecarURL.lastPathComponent)")
    }

    /// The single-commit shape: recordDrtChange lands EXACTLY ONE item, the
    /// projections stay unpolluted, the carrier re-syncs; one ⌘Z undoes the
    /// edit AND the carrier (the preset atomicity — OQ-2-A).
    @MainActor
    func testRecordDrtChangeCommitsOnceAndCarrierSyncsOnUndoRedo() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drt-persist-\(UUID().uuidString).tif")
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        defer { try? FileManager.default.removeItem(at: url) }
        try await loadGradient(url, into: coordinator, metal: metal)

        let before = editorState.history.items.count
        let instanceCountBefore = editorState.instances.count
        editorState.recordDrtChange(
            Self.editedRecord(), label: String(localized: "history_drt_param"))
        // The notification hops once; give the Task a beat, then settle.
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(
            editorState.history.items.count, before + 1,
            "one edit = exactly ONE history item (the discrete commit)")
        XCTAssertEqual(
            editorState.history.effectiveDrtRecord(), Self.editedRecord())
        XCTAssertEqual(
            workspace.drtRecord(for: url), Self.editedRecord(),
            "the notification primed the session carrier")
        // The placeholder never pollutes the projections.
        let global = editorState.history.effectiveInstances()
        XCTAssertFalse(
            global.contains { $0.opName == "drtMethod" || $0.opName == "drtEotf" },
            "the DRT item must never leak an instance into the global set")
        XCTAssertEqual(
            editorState.instances.count, instanceCountBefore,
            "the live instance set is unchanged by the DRT commit")

        // Undo: one ⌘Z → pristine (item skipped + carrier re-synced).
        await coordinator.undo()
        XCTAssertNil(editorState.history.effectiveDrtRecord())
        XCTAssertFalse(
            workspace.hasDrtRecord(for: url),
            "the undo leg must re-derive the carrier from the history")
        XCTAssertEqual(coordinator.drtTailActive, false)

        // Redo: back to the record.
        await coordinator.redo()
        XCTAssertEqual(
            workspace.drtRecord(for: url), Self.editedRecord(),
            "the redo leg restores the record")
        XCTAssertEqual(coordinator.drtTailActive, true)
    }

    /// The write leg end-to-end: the committed record lands in the FILE
    /// (displayTransform + the history item), the anchor is self-consistent
    /// (driftDetected false — the fold formula's two halves agree), and the
    /// undo leg flushes the v5 byte shape back (key absent).
    @MainActor
    func testWriteLegPersistsDisplayTransformAndUndoRestoresV5Shape() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drt-write-\(UUID().uuidString).tif")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        try await loadGradient(url, into: coordinator, metal: metal)

        // The DRT edit (the panel's exact commit face) → flush → both the
        // field and the item are on disk and the anchor agrees.
        editorState.recordDrtChange(
            Self.editedRecord(), label: String(localized: "history_drt_param"))
        try await flushUntilPersisted(sidecarURL, coordinator)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: sidecarURL))
                as? [String: Any])
        // The current-version constant (M2-8-1 E3 补点——checker 点名四处外
        // 的实测第五处): a write NOW always stamps the writer's version.
        XCTAssertEqual(
            object["schemaVersion"] as? Int, LightamerSidecar.schemaVersionCurrent)
        XCTAssertTrue(object.keys.contains("displayTransform"))
        let document = try Self.decoder.decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(document.displayTransform, Self.editedRecord())
        XCTAssertNotNil(document.history.effectiveDrtRecord())
        XCTAssertFalse(
            document.driftDetected,
            "the write-side fold and the reload-side recompute must agree")
        _ = workspace // alive to scope end (the weak web must not die)
        _ = coordinator

        // Undo + flush (content-poll: the file exists from the edit leg —
        // wait until the UNDONE document reached disk): the record leaves
        // the file (the v5 shape again).
        await coordinator.undo()
        let undoStart = Date()
        while Date().timeIntervalSince(undoStart) < 10 {
            await coordinator.flushSidecar()
            let onDisk = try? Self.decoder.decode(
                LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
            if let onDisk, onDisk.displayTransform == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: sidecarURL))
                as? [String: Any])
        XCTAssertFalse(
            object.keys.contains("displayTransform"),
            "undo past the DRT item must persist the pristine byte shape")
    }

    // MARK: - 5: the restore leg

    /// A sidecar with a DRT item + field loads: the carrier primes, the
    /// record round-trips, and the tail gate reports active. A pristine
    /// sidecar loads with zero priming.
    @MainActor
    func testRestoreLegPrimesCarrierFromTheDocument() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drt-restore-\(UUID().uuidString).tif")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }

        // Forge a drift-free document carrying the DRT edit through the
        // REAL write path first (commit + flush on assembly #1).
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        try await loadGradient(url, into: coordinator, metal: metal)
        editorState.recordDrtChange(
            Self.editedRecord(peak: 650), label: String(localized: "history_drt_param"))
        try await flushUntilPersisted(sidecarURL, coordinator)
        XCTAssertTrue(workspace.hasDrtRecord(for: url))

        // A FRESH assembly (the closed-editor semantics) loads the file.
        let (editorState2, coordinator2, workspace2, metal2) = try await makeAssembly()
        try await loadGradient(url, into: coordinator2, metal: metal2)
        XCTAssertEqual(
            workspace2.drtRecord(for: url).peakLuminance, 650,
            "the restore leg primed the session carrier from the document")
        XCTAssertEqual(
            editorState2.history.effectiveDrtRecord()?.peakLuminance, 650,
            "the history item replay carries the same record")
        XCTAssertEqual(coordinator2.drtTailActive, true)
        // The reload is the SAME value → the switch-back skip face: a
        // second load keeps the record (no double-prime side effect).
        try await loadGradient(url, into: coordinator2, metal: metal2)
        XCTAssertEqual(workspace2.drtRecord(for: url).peakLuminance, 650)

        // Pristine twin: the same file after an undo-past-DRT (the undo
        // leg's flushed shape) loads with zero priming. Flush-retry until
        // the on-disk document lost its displayTransform key.
        let (editorState3, coordinator3, workspace3, metal3) = try await makeAssembly()
        try await loadGradient(url, into: coordinator3, metal: metal3)
        await coordinator3.undo() // strip the DRT item (restores pristine)
        let undoStart = Date()
        while Date().timeIntervalSince(undoStart) < 10 {
            await coordinator3.flushSidecar()
            let onDisk = try? Self.decoder.decode(
                LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
            if let onDisk, onDisk.displayTransform == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(
            try Self.decoder.decode(LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
                .displayTransform)
        let (editorState4, coordinator4, workspace4, metal4) = try await makeAssembly()
        try await loadGradient(url, into: coordinator4, metal: metal4)
        XCTAssertFalse(
            workspace4.hasDrtRecord(for: url),
            "a pristine document never primes the DRT carrier")
        XCTAssertNil(editorState4.history.effectiveDrtRecord())
        XCTAssertEqual(coordinator4.drtTailActive, false)
        _ = editorState3 // scoped-alive pins (the weak webs must not die)
        _ = workspace3
        _ = metal3
        _ = editorState2
        _ = metal2
        _ = metal
    }
}
