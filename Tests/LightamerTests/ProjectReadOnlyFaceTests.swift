import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T4/T5 (KD-8 golden gate 4): the GUI read-only fallback face —
// the conflict projection (controller + the legacy ride-along, m3a), the
// dialog three legs, the termination flush, the three write-seam guards and
// the red-line self-checks. The omp plan-review batch (E-OMP-1 (e), 4 more
// methods) covers the history-navigation / version-command / paste / batch
// entry faces the original 14 could not see. L009: fixtures on
// NSTemporaryDirectory.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ProjectReadOnlyFaceTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ro-face-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Widget.lalb")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    private var lockURL: URL {
        packageURL.deletingPathExtension().appendingPathExtension("lalb.lock")
    }

    /// A fresh package created through the controller (the production shape).
    private func makePackage(name: String = "Widget") async throws {
        let controller = LibraryProjectController()
        try await controller.createProject(at: packageURL, name: name)
        try await controller.closeProject()
    }

    /// Acquire the package lock as a foreign holder would (second open file
    /// description in this process — the checker o1 semantics) and write the
    /// diagnostics payload.
    @discardableResult
    private func holdPackageLock(pid: Int32 = 4242) throws -> SingleWriterLock {
        let holder = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        holder.writePayload(
            SingleWriterLockPayload(
                role: .gui, pid: pid,
                startedAt: SingleWriterLockPayload.nowISO8601()))
        return holder
    }

    // MARK: - T4 前半（6 法）

    /// The typed conflict projects onto `pendingConflict` (url + holder pid
    /// + holder role), the store stays nil. m3a 并档: the SAME method
    /// asserts the legacy ride-along's conflict face — a held session.lock
    /// reports through the handler and fails the sync honestly.
    func testOpenProjectConflictPublishesPendingConflict() async throws {
        try await makePackage()
        let holder = try holdPackageLock(pid: 4242)
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        let conflict = try XCTUnwrap(controller.pendingConflict)
        XCTAssertEqual(conflict.url, packageURL)
        XCTAssertEqual(conflict.holderPid, 4242)
        XCTAssertEqual(conflict.holderRole, "gui")
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertNil(isOpen, "the conflict open leaves no store behind")
        holder.unlock()

        // ── m3a 并档: the legacy session conflict face ──
        let sessionRoot = tempDirectory.appendingPathComponent("legacy-root")
        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent(".lightamer"),
            withIntermediateDirectories: true)
        let sessionLock = sessionRoot.appendingPathComponent(".lightamer")
            .appendingPathComponent("session.lock")
        let sessionHolder = try XCTUnwrap(
            SingleWriterLock.acquire(at: sessionLock).get())
        let indexController = SessionIndexController()
        var reported: String?
        indexController.sessionLockConflictHandler = { reported = $0 }
        let result = await indexController.openAndSync(root: sessionRoot)
        XCTAssertTrue(result.failed, "a held session.lock fails the open")
        XCTAssertNotNil(reported, "the conflict handler reports the holder")
        XCTAssertTrue(reported?.contains("pid") == true, "copy carries pid info")
        sessionHolder.unlock()
        await indexController.close()
    }

    /// The 只读打开 leg: lockless open, the face flag + the holder pid land,
    /// the project becomes current (the read-only one).
    func testConflictReadOnlyLeg() async throws {
        try await makePackage()
        let holder = try holdPackageLock(pid: 5150)
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        XCTAssertNotNil(controller.pendingConflict)
        try await controller.openProjectReadOnly(at: packageURL)
        XCTAssertTrue(controller.isReadOnly)
        XCTAssertEqual(controller.readOnlyHolderPid, 5150)
        XCTAssertEqual(controller.projectURL, packageURL)
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertTrue(isOpen == true, "the read-only face holds an open store")
        controller.dismissConflict()
        holder.unlock()
        try await controller.closeProject()
    }

    /// The 重试 leg: after the holder exits (the five-state ③ window) the
    /// retry re-acquires the write right — the upgrade path.
    func testConflictRetryLegAfterHolderExit() async throws {
        try await makePackage()
        let holder = try holdPackageLock()
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        XCTAssertNotNil(controller.pendingConflict)
        holder.unlock()
        try await controller.openProject(at: packageURL)
        XCTAssertFalse(controller.isReadOnly, "the retry won the write right")
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertTrue(isOpen == true)
        try await controller.closeProject()
    }

    /// The 取消 leg: dismiss the conflict, open nothing.
    func testConflictCancelLegOpensNothing() async throws {
        try await makePackage()
        let holder = try holdPackageLock()
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        XCTAssertNotNil(controller.pendingConflict)
        controller.dismissConflict()
        XCTAssertNil(controller.pendingConflict)
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertNil(isOpen, "cancel opens nothing")
        holder.unlock()
    }

    /// flushForTermination: the bounded close releases the project lock
    /// (the kernel-side observable) and clears the controller face.
    func testFlushForTerminationReleasesLock() async throws {
        try await makePackage()
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        // The open store holds the lock.
        guard case .failure(.heldByOther) = SingleWriterLock.acquire(at: lockURL)
        else {
            return XCTFail("the open project must hold the lock")
        }
        controller.flushForTermination()
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertNil(isOpen, "the termination flush clears the face")
        let second = try XCTUnwrap(
            SingleWriterLock.acquire(at: lockURL).get(),
            "the flush must release the project lock")
        second.unlock()
    }

    /// L057 red line: the runModal ban — zero `.runModal(` hits across the
    /// App sources (the conflict dialog is a SwiftUI sheet, not a modal
    /// panel). Machine-checked here so the ban cannot silently rot.
    func testL057RunModalZeroHits() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        // <repo>/Tests/LightamerTests/<file> → <repo>
        let repoRoot = testFile
            .deletingLastPathComponent()  // Tests/LightamerTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo
        let appSources = repoRoot.appendingPathComponent("App/Sources")
        var hits: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: appSources, includingPropertiesForKeys: nil)
        while let next = enumerator?.nextObject() as? URL {
            guard next.pathExtension == "swift" else { continue }
            guard let source = try? String(contentsOf: next, encoding: .utf8)
            else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains(".runModal(") {
                hits.append("\(next.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(
            hits.isEmpty,
            "L057 ban: .runModal( must stay out of App/Sources — \(hits)")
    }

    // MARK: - T5 后半（8 法）

    /// Seam 1 through a REAL consumer: the read-only open's LibraryStore
    /// write (createAlbum) typed-rejects via the withWriteBatch breaker.
    func testReadOnlyStoreRejectsLibraryStoreWrite() async throws {
        try await makePackage()
        let holder = try holdPackageLock(pid: 9)
        let controller = LibraryProjectController()
        try await controller.openProjectReadOnly(at: packageURL)
        let library = LibraryStore(store: controller.projectStore!)
        do {
            _ = try await library.createAlbum(kind: .album, name: "Blocked")
            XCTFail("a read-only library must reject album writes")
        } catch let error as LibraryError {
            guard case .projectReadOnly = error else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
        holder.unlock()
        try await controller.closeProject()
    }

    /// Seam 2, gate CLOSED: every commit* entry no-ops (typed no-throw, no
    /// history items, no crash) — the commit family名单 (KD-3 m3b 勘误):
    /// recordChange / commitMaskEdit / commitLayerEdit / commitRetouchEdit /
    /// commitLayerStructure / recordDrtChange / recordFilmChange.
    func testGateClosedCommitsAreNoOps() {
        let editorState = EditorState()
        editorState.projectReadOnlyGate = { true }
        let module = Self.record("exposure")
        // recordChange — suppressed.
        editorState.recordChange(module, label: "history_test")
        // Drt/Film records — suppressed.
        editorState.recordDrtChange(DrtRecord(), label: "history_drt_param")
        editorState.recordFilmChange(FilmRecord(), label: "history_film_param")
        // Layer family — suppressed (structure + edit + mask + retouch).
        editorState.commitMaskEdit(
            layerID: UUID(), label: "history_mask_item") { _ in }
        editorState.commitLayerEdit(
            AdjustmentLayer(name: "L"), label: "history_layer_test")
        editorState.commitRetouchEdit(
            RetouchLayer(name: "R"), label: "history_retouch_test")
        let canUndo = editorState.canUndo
        XCTAssertFalse(canUndo, "no history item may land read-only")
        XCTAssertTrue(editorState.instances.isEmpty, "the live set stays put")
    }

    /// The internal raw-field init (the AdjustmentTransferTests fixture
    /// shape — @testable).
    private static func record(
        _ opName: String, multiPriority: Int = 0
    ) -> ModuleInstance {
        ModuleInstance(
            id: UUID(), opName: opName, multiPriority: multiPriority,
            multiName: "", iopOrder: 50, version: 1, enabled: true,
            paramsData: Data("{}".utf8), paramsHash: 0)
    }

    /// Seam 2, gate OPEN (nil): the same recordChange lands — the guard is
    /// zero-diff for every unwired construction.
    func testGateOpenCommitsLand() {
        let editorState = EditorState()
        editorState.recordChange(Self.record("exposure"), label: "history_test")
        XCTAssertTrue(editorState.canUndo, "the gate nil default must not block")
    }

    /// Seam 3: ExportState gate closed → both enqueue faces typed-reject
    /// with the read-only copy BEFORE any environment lookup.
    func testExportStateGateRejectsEnqueues() async throws {
        let exportState = ExportState()
        exportState.projectReadOnlyGate = { true }
        do {
            _ = try await exportState.enqueueExportM2(
                images: [], instancesOverrides: [], drtRecord: DrtRecord(),
                variant: ExportVariant(format: .jpeg(quality: 0.9)),
                destination: tempDirectory,
                subfolder: nil, namingPattern: "{stem}")
            XCTFail("the read-only face must reject the M2 enqueue")
        } catch let error as AppError {
            guard case .invalidParameter(let message) = error,
                message.contains("read-only")
            else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
        do {
            try await exportState.enqueueExport(images: [])
            XCTFail("the read-only face must reject the session enqueue")
        } catch let error as AppError {
            guard case .invalidParameter(let message) = error,
                message.contains("read-only")
            else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
    }

    /// Seam 3 zero-diff: gate nil → the pre-existing failure face (no
    /// queue = the「no export queue」rejection, NOT the read-only copy).
    func testExportStateGateOpenKeepsLegacyFace() async throws {
        let exportState = ExportState()
        do {
            try await exportState.enqueueExport(images: [])
            XCTFail("no-queue enqueue must still throw")
        } catch let error as AppError {
            guard case .invalidParameter(let message) = error,
                message.contains("no export queue")
            else {
                return XCTFail("the legacy face changed: \(error)")
            }
        }
    }

    /// The banner: mounted on a REAL on-screen WorkspaceHostView (the
    /// ToastFaceTests AX-window shape), read-only = the banner surfaces in
    /// the accessibility tree; writable = absent. The same-source boolean
    /// (`controller.isReadOnly`) drives it.
    func testBannerAccessibilityFace() async throws {
        try await makePackage()
        let holder = try holdPackageLock(pid: 6161)
        let readOnlyController = LibraryProjectController()
        try await readOnlyController.openProjectReadOnly(at: packageURL)
        XCTAssertTrue(readOnlyController.isReadOnly)

        func pumpMount(_ controller: LibraryProjectController) -> Set<String> {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            let host = NSHostingView(
                rootView: FaceHostRoot(projectController: controller))
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
            window.contentView = host
            window.orderFrontRegardless()
            let deadline = Date().addingTimeInterval(3)
            var identifiers = Set<String>()
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                identifiers = []
                Self.collectIdentifiers(
                    AXUIElementCreateApplication(
                        ProcessInfo.processInfo.processIdentifier),
                    into: &identifiers)
                if identifiers.contains("shell.readonly.banner") { break }
            }
            window.orderOut(nil)
            window.contentView = nil
            return identifiers
        }

        // Read-only mount: the banner is in the AX tree.
        let readOnlyIDs = pumpMount(readOnlyController)
        XCTAssertTrue(
            readOnlyIDs.contains("shell.readonly.banner"),
            "the read-only face must surface the banner")

        // Writable mount (a fresh controller, no project): no banner chrome.
        let writableIDs = pumpMount(LibraryProjectController())
        XCTAssertFalse(
            writableIDs.contains("shell.readonly.banner"),
            "the writable face must not render the banner")
        holder.unlock()
        try await readOnlyController.closeProject()
    }

    /// The move face refuses on the read-only project (the controller
    /// typed backstop; the UI disables the entry — DECISIONS table).
    func testReadOnlyMoveTypedRefused() async throws {
        try await makePackage()
        let holder = try holdPackageLock()
        let controller = LibraryProjectController()
        try await controller.openProjectReadOnly(at: packageURL)
        do {
            try await controller.moveProject(
                to: tempDirectory.appendingPathComponent("Moved"))
            XCTFail("a read-only move must refuse")
        } catch let error as LibraryError {
            guard case .projectReadOnly = error else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
        holder.unlock()
        try await controller.closeProject()
    }

    /// The keep-available set: backup (the ONLY sanctioned copy path)
    /// stays reachable on the read-only face, through the controller.
    func testReadOnlyBackupStillAvailable() async throws {
        try await makePackage()
        let holder = try holdPackageLock()
        let controller = LibraryProjectController()
        try await controller.openProjectReadOnly(at: packageURL)
        let destination = tempDirectory.appendingPathComponent("Ro-backup.lalb")
        try await controller.backupProject(to: destination)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destination.path),
            "the read-only face keeps the backup path alive")
        holder.unlock()
        try await controller.closeProject()
    }

    // MARK: - omp E-OMP-1 (e) 回注（4 法）：history 导航 / 版本 / paste / batch

    /// ① gate closed → history navigation no-ops: undo/redo refuse (false),
    /// jump never steps — the stack pointer stays exactly where it was, so
    /// the sidecar position write these moves schedule can never diverge
    /// (PipeCoordinator guards on the false return; jumpToHistory reads the
    /// gate before its sidecar tail).
    func testGateClosedHistoryNavigationIsNoOp() {
        let editorState = EditorState()
        editorState.recordChange(Self.record("exposure"), label: "history_test")
        editorState.recordChange(Self.record("saturation"), label: "history_test")
        editorState.performUndo()  // gate still open: the legit step to 0
        XCTAssertEqual(editorState.history.position, 0)
        editorState.projectReadOnlyGate = { true }
        XCTAssertFalse(editorState.performUndo(), "a read-only undo must refuse")
        XCTAssertFalse(editorState.performRedo(), "a read-only redo must refuse")
        editorState.performJump(to: -1)
        XCTAssertEqual(
            editorState.history.position, 0,
            "a read-only jump must not move the pointer")
        XCTAssertTrue(editorState.canUndo, "the stack was never stepped back")
        XCTAssertTrue(editorState.canRedo, "the redo tail was never consumed")
    }

    /// ② the coordinator-level gate: all six write commands refuse
    /// read-only (create / branch / paste / switch / rename / remove) — no
    /// slot growth, no activation move, no metadata mutation, and the
    /// EditorState chain the commands install through stays untouched.
    func testVersionCoordinatorGateRejectsWriteCommands() throws {
        let editorState = EditorState()
        let versions = VersionCoordinator()
        versions.attach(
            editorState: editorState, pipeCoordinator: PipeCoordinator())
        editorState.recordChange(Self.record("exposure"), label: "history_test")
        // Gate open: materialize the structure the gate will then protect
        // (implicit 「版本 1」 + one created version). createFromScratch
        // legitimately installs the new empty chain here — the gate's
        // contract is that NOTHING lands AFTER it reads true.
        versions.createFromScratch(name: "V2")
        XCTAssertEqual(versions.slots.count, 2)
        let activeID = try XCTUnwrap(versions.activeVersionID)
        let otherID = try XCTUnwrap(
            versions.slots.first(where: { $0.id != activeID })?.id)
        let otherNameBefore = versions.slots
            .first(where: { $0.id == otherID })?.name
        let setupPosition = editorState.history.position
        let setupCanUndo = editorState.canUndo
        versions.projectReadOnlyGate = { true }
        XCTAssertTrue(versions.isReadOnly)
        versions.createFromScratch(name: "Blocked")
        versions.branchFromCurrent(name: "Blocked")
        versions.pasteChain(
            records: [Self.record("saturation")], layerSnapshot: nil,
            drtRecord: nil, name: "Blocked")
        versions.switchTo(otherID)
        XCTAssertEqual(
            versions.activeVersionID, activeID,
            "a read-only switch must not move the activation")
        versions.rename(otherID, to: "Renamed")
        XCTAssertEqual(
            versions.slots.first(where: { $0.id == otherID })?.name,
            otherNameBefore,
            "a read-only rename must not land")
        versions.remove(otherID)
        XCTAssertEqual(versions.slots.count, 2, "a read-only remove must not land")
        XCTAssertEqual(
            editorState.history.position, setupPosition,
            "no command ever reached the install face")
        XCTAssertEqual(editorState.canUndo, setupCanUndo)
        XCTAssertFalse(editorState.canRedo, "the pasteChain chain never landed")
    }

    /// ③ gate closed → the two paste installs no-op: neither the live set
    /// nor the stack may change (⌘V's live leg has no landing read-only).
    func testGateClosedPasteInstallsAreNoOps() {
        let editorState = EditorState()
        editorState.recordChange(Self.record("exposure"), label: "history_test")
        let namesBefore = editorState.instances.map(\.opName)
        var pasted = HistoryStack()
        pasted.commit(Self.record("saturation"), label: "history_test")
        editorState.projectReadOnlyGate = { true }
        editorState.installMergePaste(history: pasted)
        editorState.installOverwritePaste(
            history: pasted, seed: [Self.record("noise_reduction")])
        XCTAssertEqual(
            editorState.instances.map(\.opName), namesBefore,
            "the live set must stay put")
        XCTAssertEqual(
            editorState.history.position, 0,
            "the pasted chain never installed")
        XCTAssertFalse(editorState.canRedo, "no paste tail landed")
    }

    /// ④ the batch entry predicate: gate closed = the batch paste refuses
    /// through the SAME EditorState toast face the read-only open uses;
    /// nil/false stay writable (the zero-diff default).
    func testBatchPasteEntryGateBlocksAndToasts() {
        XCTAssertTrue(LightamerShellFace.batchPasteBlocked(gate: { true }))
        XCTAssertFalse(LightamerShellFace.batchPasteBlocked(gate: { false }))
        XCTAssertFalse(
            LightamerShellFace.batchPasteBlocked(gate: nil),
            "the nil default must stay writable")
        let editorState = EditorState()
        editorState.projectReadOnlyGate = { true }
        if LightamerShellFace.batchPasteBlocked(gate: editorState.projectReadOnlyGate) {
            editorState.presentToast(
                LightamerShellFace.readOnlyPasteToast(holderPid: 4242))
        }
        XCTAssertEqual(
            editorState.toast,
            LightamerShellFace.readOnlyPasteToast(holderPid: 4242),
            "the refusal raises the read-only toast face")
    }

    /// M-OMP-4 (the omp second acceptance's error finding): create/move
    /// carry the SAME lock as a normal roled open — a second instance's
    /// `open(role:)` must see `heldByOther` after a create, and after
    /// both move reopens. Without the role the first instance writes
    /// lockless while the second takes the writer right unknowingly.
    func testCreateAndMoveReopensHoldTheWriterLock() async throws {
        let controller = LibraryProjectController()
        let name = "LockLife"
        let directory = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
            .appendingPathExtension("lalb")
        try await controller.createProject(at: url, name: name)
        // The create leg holds the lock: a foreign open is typed-held.
        let second = ProjectFileStore(at: url)
        do {
            _ = try await second.open(role: .gui)
            XCTFail("a created project must hold the writer lock")
        } catch let error as LibraryError {
            guard case .projectHeldByOther = error else {
                return XCTFail("expected projectHeldByOther, got \(error)")
            }
        }
        // The happy-path move reopen holds the lock at the NEW location.
        let destination = tempDirectory.appendingPathComponent("Moved", isDirectory: true)
        try await controller.moveProject(to: destination)
        let newPackage = destination.appendingPathComponent("\(name).lalb")
        // The moved package's own lock (the harness `lockURL` targets the
        // setUp Widget package, not this one) must be HELD at the new
        // location — a free probe here would mean the reopen leg lost it.
        let newLockURL = newPackage.deletingPathExtension()
            .appendingPathExtension("lalb.lock")
        XCTAssertFalse(
            SingleWriterLock.probeLockAvailable(at: newLockURL),
            "the moved project's lock must be held at the new location")
        let third = ProjectFileStore(at: newPackage)
        do {
            _ = try await third.open(role: .gui)
            XCTFail("the moved project must hold the writer lock")
        } catch let error as LibraryError {
            guard case .projectHeldByOther = error else {
                return XCTFail("expected projectHeldByOther, got \(error)")
            }
        }
        try await controller.closeProject()
    }
    // MARK: - Shared harness (the ToastFaceTests mount shape)

    /// A hosting root carrying exactly the injections WorkspaceHostView
    /// reads at its depth (the ToastFaceTests HostRoot + the controller).
    private struct FaceHostRoot: View {
        let projectController: LibraryProjectController?

        var body: some View {
            WorkspaceHostView(projectController: projectController, onImportFolder: { })
                .environment(EditorState())
                .environment(PipeCoordinator())
                .environment(ExportState())
                .environment(InspectorState())
                // M7-5-01: the turn-taking coordinator joined the host's
                // environment face (never held here — the faces stay
                // byte-identical).
                .environment(AgentControlCoordinator())
        }
    }

    /// Depth-first AX identifier walk (the ToastFaceTests collector — the
    /// AX attribute tree, self-app needs no TCC grant).
    private static func collectIdentifiers(
        _ element: AXUIElement, into set: inout Set<String>, depth: Int = 0
    ) {
        guard depth < 40 else { return }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXIdentifierAttribute as CFString, &value) == .success,
            let identifier = value as? String {
            set.insert(identifier)
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children) == .success,
            let kids = children as? [AXUIElement] else { return }
        for kid in kids {
            collectIdentifiers(kid, into: &set, depth: depth + 1)
        }
    }
}
