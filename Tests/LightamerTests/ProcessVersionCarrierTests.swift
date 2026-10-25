import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ProcessVersionCarrierTests (Plan M6-2-01 T3, KD-3/KD-4 — APP bundle, the
// SidecarV5Tests true load-chain form + the AdjustmentTransferTests
// assembly/paste precedent) — the per-image process carrier through the REAL
// EditorState + PipeCoordinator + WorkspaceModel (+ VersionCoordinator) web:
//
//   1. THE MINT GATE (G4): a pristine load (no `.lra`) mints `.current`
//      into the carrier; the first committed edit lands `"process": 1` in
//      the flushed file.
//   2. THE LEGACY PRESERVATION GATE: a loaded key-less (v9-era) document
//      re-saves with the key STILL ABSENT (never passively upgraded), the
//      existing keys byte-identical, the writer face = v10.
//   3. THE FORWARD-NUMBER GATE (OQ-3): a stored 7 loads 7 and re-saves 7
//      verbatim (no downgrade on the write side).
//   4. THE CORRUPT GATE: `"process": "x"` loads (the rest of the document
//      alive) and re-saves WITHOUT the key (损坏值不保留).
//   5. THE UNDO/SWAP ZERO-TOUCH GATE (OQ-2): undo to the top + a version
//      branch/swap never touch the value — the re-save keeps 1, the items
//      carry no process field.
//   6. THE COPY ADJUSTMENTS NEGATIVE (OQ-2): the paste transport never
//      carries the process — a pasted-into legacy target re-saves ABSENT.
//   7. THE CLOSE/REOPEN IDEMPOTENCE (KD-3): the editor-close drop empties
//      the carrier; a fresh reopen restores the same value from the file.
//   8. THE DETACHED-WORKSPACE FACE (KD-4): no workspace → the write leg
//      reads the `.legacy` default → a key-less v10 document.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ProcessVersionCarrierTests: XCTestCase {

    private var workDirs: [URL] = []

    override func tearDown() {
        for dir in workDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        workDirs.removeAll()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A fresh per-test work directory + a synthetic image URL in it (the
    /// sidecar lands beside it — never the workspace, L009).
    private func makeImageURL(prefix: String = "carrier") -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        workDirs.append(dir)
        return dir.appendingPathComponent("DSC00001.ARW")
    }

    private nonisolated static func decodedFlat(size: Int = 96) -> DecodedImage {
        let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: image,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    /// A drift-free document with an optional history edit, written with
    /// the PRODUCTION appVersion (the writer convention — re-saves stay
    /// comparable) and the current schema version.
    private func writeDriftFreeSidecar(
        to imageURL: URL, process: RenderProcessVersion? = nil,
        withEdit: Bool = false
    ) throws {
        var history = HistoryStack()
        if withEdit {
            history.commit(
                ModuleInstance(
                    module: TestGainModule.self,
                    params: TestGainModule.Params(gain: 1.25)),
                label: "base gain")
        }
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 42,
            instances: history.effectiveInstances(), history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 42),
            appVersion: LightamerSidecar.currentAppVersion,
            process: process)
        try Self.canonicalEncoder.encode(document).write(
            to: LightamerSidecar.sidecarURL(for: imageURL))
    }

    /// Rewind the on-disk schemaVersion digit (the digit-rewound form —
    /// the FilmSidecarTests mechanics) to simulate a v9-era file.
    private func rewindSchemaVersion(_ imageURL: URL, to version: Int) throws {
        let sidecarURL = LightamerSidecar.sidecarURL(for: imageURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: sidecarURL)) as? [String: Any])
        object["schemaVersion"] = version
        try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ).write(to: sidecarURL)
    }

    private func readJSONObject(_ imageURL: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: LightamerSidecar.sidecarURL(for: imageURL)))
            as? [String: Any])
    }

    /// The D-H1 production commit face — the write schedule's real trigger
    /// (a plain recordChange does NOT schedule the D-S3 write).
    private func commitOneEdit(
        _ editorState: EditorState, _ coordinator: PipeCoordinator
    ) async {
        let edited = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params(gain: 1.5))
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(edited)
        await coordinator.commitContinuousEdit(label: "gain tick")
    }

    /// The production composition minus windowing (the SidecarV5Tests
    /// makeAssembly + the version coordinator edges).
    private func makeAssembly(withVersions: Bool = false, withWorkspace: Bool = true)
        async throws -> (editorState: EditorState, coordinator: PipeCoordinator,
                         workspace: WorkspaceModel?, versions: VersionCoordinator?,
                         metal: MetalContext)
    {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let workspace = withWorkspace ? WorkspaceModel() : nil
        var versions: VersionCoordinator?
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        if let workspace {
            workspace.attach(pipeCoordinator: coordinator)
            coordinator.attach(workspace: workspace)
        }
        if withVersions {
            let versionCoordinator = VersionCoordinator()
            versionCoordinator.attach(
                editorState: editorState, pipeCoordinator: coordinator)
            editorState.attach(versionCoordinator: versionCoordinator)
            coordinator.attach(versionCoordinator: versionCoordinator)
            versions = versionCoordinator
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, workspace, versions, metal)
    }

    /// Flush-poll until the PREDICATE holds against the re-written file
    /// (the file may pre-exist as the fixture — existence proves nothing;
    /// the poll re-flushes until the scheduled write lands, the
    /// AdjustmentTransferTests form hardened for pre-existing fixtures).
    private func flushUntil(
        _ imageURL: URL, _ coordinator: PipeCoordinator,
        timeout: TimeInterval = 10,
        _ predicate: @escaping ([String: Any]) -> Bool
    ) async throws {
        let sidecarURL = LightamerSidecar.sidecarURL(for: imageURL)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await coordinator.flushSidecar()
            if let data = try? Data(contentsOf: sidecarURL),
                let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                predicate(object)
            {
                try await Task.sleep(for: .milliseconds(100))
                return
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("the sidecar write never landed: \(sidecarURL.lastPathComponent)")
    }

    // MARK: - 1: the mint gate (G4)

    func testPristineLoadMintsCurrentAndFirstEditWritesIt() async throws {
        let url = makeImageURL()
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))

        let (editorState, coordinator, workspace, _, metal) = try await makeAssembly()
        await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)
        // The pristine branch minted `.current` into the carrier — no file
        // was written yet (the mint is carrier-only until an edit).
        XCTAssertEqual(workspace?.processVersion(for: url), .current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))

        await commitOneEdit(editorState, coordinator)
        try await flushUntil(url, coordinator) { object in
            object["process"] as? Int == RenderProcessVersion.current.rawValue
        }
        let object = try readJSONObject(url)
        XCTAssertEqual(
            object["process"] as? Int, RenderProcessVersion.current.rawValue,
            "the first committed edit lands the mint stamp (G4)")

        // Reload on a FRESH assembly: the file's value primes the carrier.
        let (_, coordinator2, workspace2, _, metal2) = try await makeAssembly()
        await coordinator2.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal2)
        XCTAssertEqual(workspace2?.processVersion(for: url), .current)
    }

    // MARK: - 2: the legacy preservation gate

    func testLegacyDocumentReSavesWithTheKeyAbsentAndKeysPreserved() async throws {
        let url = makeImageURL()
        try writeDriftFreeSidecar(to: url, process: nil, withEdit: true)
        try rewindSchemaVersion(url, to: 9) // the v9-era file
        let before = try readJSONObject(url)

        let (editorState, coordinator, workspace, _, metal) = try await makeAssembly()
        await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)
        XCTAssertEqual(workspace?.processVersion(for: url), .legacy)

        await commitOneEdit(editorState, coordinator)
        try await flushUntil(url, coordinator) { object in
            !object.keys.contains("process")
                && object["schemaVersion"] as? Int
                    == LightamerSidecar.schemaVersionCurrent
        }

        let after = try readJSONObject(url)
        XCTAssertFalse(
            after.keys.contains("process"),
            "a loaded legacy document is NEVER passively upgraded (OQ-1)")
        XCTAssertEqual(
            after["schemaVersion"] as? Int, LightamerSidecar.schemaVersionCurrent,
            "the writer face is v10")
        // The existing keys survive byte-faithfully through the
        // decode→edit→re-encode cycle. (decodeParamsHash/historyHash are
        // the documented writer-face re-stamps — the write-time live atom
        // and the recomputed anchor over the edited state.)
        XCTAssertEqual(after["imageID"] as? String, before["imageID"] as? String)
        XCTAssertEqual(
            after["appVersion"] as? String, before["appVersion"] as? String)
        // The history grew by exactly the one committed item; the loaded
        // item is preserved verbatim and the anchor recomputed over the
        // edited state (self-consistent — no false drift).
        let beforeItems = try XCTUnwrap(
            (before["history"] as? [String: Any])?["items"] as? [[String: Any]])
        let afterItems = try XCTUnwrap(
            (after["history"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(afterItems.count, beforeItems.count + 1)
        XCTAssertEqual(
            afterItems.first as NSDictionary?, beforeItems.first as NSDictionary?,
            "the loaded item is preserved byte-faithfully")
        let reSavedDocument = try Self.decoder.decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: url)))
        XCTAssertFalse(reSavedDocument.driftDetected)
    }

    // MARK: - 3: the forward-number gate

    func testForwardLargeNumberRoundTripsVerbatim() async throws {
        let url = makeImageURL()
        try writeDriftFreeSidecar(
            to: url, process: RenderProcessVersion(rawValue: 7)!, withEdit: true)

        let (editorState, coordinator, workspace, _, metal) = try await makeAssembly()
        await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)
        XCTAssertEqual(
            workspace?.processVersion(for: url),
            RenderProcessVersion(rawValue: 7)!,
            "the forward number loads verbatim (OQ-3)")

        await commitOneEdit(editorState, coordinator)
        try await flushUntil(url, coordinator) { object in
            object["process"] as? Int == 7
                && (object["history"] as? [String: Any])?["items"] != nil
        }
        let object = try readJSONObject(url)
        XCTAssertEqual(
            object["process"] as? Int, 7,
            "the re-save preserves the forward number (no downgrade)")
    }

    // MARK: - 4: the corrupt gate

    func testCorruptProcessValueLoadsAndRewritesWithoutTheKey() async throws {
        let url = makeImageURL()
        try writeDriftFreeSidecar(to: url, process: nil, withEdit: true)
        // Inject `"process": "x"` into the file bytes (the hand-edit form).
        var object = try readJSONObject(url)
        object["process"] = "x"
        try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ).write(to: LightamerSidecar.sidecarURL(for: url))

        let (editorState, coordinator, workspace, _, metal) = try await makeAssembly()
        await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)
        // The document loads: the corrupt value normalized to legacy, the
        // rest of the document fully alive.
        XCTAssertEqual(workspace?.processVersion(for: url), .legacy)
        XCTAssertEqual(editorState.history.items.count, 1)

        await commitOneEdit(editorState, coordinator)
        try await flushUntil(url, coordinator) { object in
            !object.keys.contains("process")
                && (object["history"] as? [String: Any])?["items"] != nil
        }

        let reSaved = try readJSONObject(url)
        XCTAssertFalse(
            reSaved.keys.contains("process"),
            "损坏值不保留 — the re-save drops the key (G4)")
        XCTAssertNotNil(reSaved["history"], "the rest of the document survived")
    }

    // MARK: - 5: the undo / version-swap zero-touch gate

    func testUndoToTopAndVersionSwapLeaveTheValueUntouched() async throws {
        let url = makeImageURL()
        try writeDriftFreeSidecar(to: url, process: .current, withEdit: true)

        let (editorState, coordinator, workspace, versions, metal) =
            try await makeAssembly(withVersions: true)
        await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)
        let versionsCoordinator = try XCTUnwrap(versions)

        // Undo to the top (the loaded item drops; undo schedules its own
        // write), then a branch + swap-back (the version commands ride the
        // finishVersionAction tail → write).
        await coordinator.undo()
        XCTAssertEqual(editorState.history.position, -1, "undo reached the top")
        versionsCoordinator.branchFromCurrent(name: "branch")
        XCTAssertEqual(versionsCoordinator.slots.count, 2)
        let implicitID = versionsCoordinator.slots[0].id
        versionsCoordinator.switchTo(implicitID)
        try await flushUntil(url, coordinator) { object in
            object["process"] as? Int == RenderProcessVersion.current.rawValue
                && object["versions"] != nil
        }

        let object = try readJSONObject(url)
        XCTAssertEqual(
            object["process"] as? Int, RenderProcessVersion.current.rawValue,
            "undo/swap never touch the document-level value (OQ-2)")
        // Zero history-item face: the item records carry no process key.
        let items = try XCTUnwrap(
            (object["history"] as? [String: Any])?["items"] as? [[String: Any]])
        for item in items {
            XCTAssertFalse(item.keys.contains("process"))
        }
        XCTAssertEqual(workspace?.processVersion(for: url), .current)
    }

    // MARK: - 6: the Copy Adjustments negative

    func testPasteTransportNeverCarriesTheProcess() async throws {
        // The TARGET: a legacy document (the key ABSENT).
        let targetURL = makeImageURL(prefix: "carrier-target")
        try writeDriftFreeSidecar(to: targetURL, process: nil, withEdit: true)
        // The SOURCE document carries process 1 + a grade instance.
        let sourceURL = makeImageURL(prefix: "carrier-source")
        try writeDriftFreeSidecar(
            to: sourceURL, process: .current, withEdit: true)

        let (editorState, coordinator, workspace, versions, metal) =
            try await makeAssembly(withVersions: true)
        await coordinator.load(
            url: targetURL, decoded: Self.decodedFlat(), instances: [], metal: metal)
        let versionsCoordinator = try XCTUnwrap(versions)
        XCTAssertEqual(workspace?.processVersion(for: targetURL), .legacy)

        // The paste payload materialized from the SOURCE document (the
        // typed payload — records + snapshot + drtRecord ONLY; the
        // document-level process is structurally outside it).
        let sourceDocument = try Self.decoder.decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: sourceURL)))
        XCTAssertEqual(sourceDocument.process, .current)
        let payload = AdjustmentTransferPayload(
            records: sourceDocument.instances.filter {
                NodeOwnershipCatalog.owner(of: $0.opName) == .grade
            },
            snapshot: nil, drtRecord: nil)
        XCTAssertFalse(payload.isEmpty, "防空转: the payload has transferables")

        versionsCoordinator.pasteChain(
            records: payload.records, layerSnapshot: payload.snapshot,
            drtRecord: payload.drtRecord, name: "Pasted adjustments")
        // The paste materializes the implicit slot first (the captured
        // target chain) then lands the pasted slot (the
        // AdjustmentTransferTests shape: 2 slots, active = the paste).
        XCTAssertEqual(versionsCoordinator.slots.count, 2, "the paste landed")
        XCTAssertEqual(versionsCoordinator.activeVersionID, versionsCoordinator.slots[1].id)
        try await flushUntil(targetURL, coordinator) { object in
            object["versions"] != nil
        }

        let object = try readJSONObject(targetURL)
        XCTAssertNotNil(object["versions"], "the paste landed in the document")
        XCTAssertNil(
            object["process"],
            "the pasted-into legacy target re-saves STILL ABSENT (OQ-2)")
        XCTAssertEqual(workspace?.processVersion(for: targetURL), .legacy)
    }

    // MARK: - 7: the close / reopen idempotence

    func testCloseDropsAndReopenRestoresTheCarrierIdempotently() async throws {
        let url = makeImageURL()
        try writeDriftFreeSidecar(to: url, process: .current, withEdit: true)

        let (_, coordinator, workspace, _, metal) = try await makeAssembly()
        await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)
        let workspaceA = try XCTUnwrap(workspace)
        XCTAssertEqual(workspaceA.processVersion(for: url), .current)

        // The editor-close drop (closeEditor's face): the map empties, the
        // read face falls back to legacy.
        workspaceA.closeEditor()
        XCTAssertTrue(workspaceA.processVersions.isEmpty)
        XCTAssertEqual(workspaceA.processVersion(for: url), .legacy)

        // The fresh reopen (the closed-editor semantics — a NEW assembly):
        // the file's value restores the same carrier state.
        let (_, coordinator2, workspace2, _, metal2) = try await makeAssembly()
        await coordinator2.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal2)
        XCTAssertEqual(
            workspace2?.processVersion(for: url), .current,
            "the reopen restores the value from the file (idempotent)")
    }

    // MARK: - 8: the detached-workspace face

    func testDetachedWorkspaceWriteLegProducesAKeylessV10Document() async throws {
        let url = makeImageURL()
        // NO workspace attached: the load leg's prime is a no-op and the
        // write leg reads the `.legacy` default.
        let (editorState, coordinator, _, _, metal) =
            try await makeAssembly(withWorkspace: false)

        await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)
        await commitOneEdit(editorState, coordinator)
        try await flushUntil(url, coordinator) { object in
            object["schemaVersion"] as? Int
                == LightamerSidecar.schemaVersionCurrent
        }

        let object = try readJSONObject(url)
        XCTAssertFalse(
            object.keys.contains("process"),
            "a detached workspace writes the key-less (legacy) face")
        XCTAssertEqual(
            object["schemaVersion"] as? Int, LightamerSidecar.schemaVersionCurrent,
            "the writer face is v10")
    }
}
