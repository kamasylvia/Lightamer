@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MaskRefineCoordinatorTests (Plan LUMEN-C T2) — the App-side orchestration
// pins: ① single-flight + waiting queue (later requests wait, no second
// pass), ② the successful swap = the EXISTING commit seam (one history item,
// the raster hash flips, ⌘Z removes it) — the M6-4 channel reuse, zero new
// item type, ③ failure keeps the quick mask (typed throw, mask plane and
// history unchanged, the toast lands), ④ the fineAuto gate (typed read:
// absent = true, false = off; the off state schedules nothing while the
// manual entry stays reachable), ⑤ the trigger hook's loop break (the
// refine's own commit does NOT re-trigger). The guide leg is INJECTED (the
// synthetic-guide seam) — the headless GPU render is the production face.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MaskRefineCoordinatorTests: XCTestCase {

    private var tempDirectory: URL!

    /// A tiny @Sendable counter box (the closure-capture discipline).
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        var value = 0
        func bump() { lock.lock(); value += 1; lock.unlock() }
    }
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var editingState: LayerEditingState!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("maskrefine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        editorState = EditorState()
        coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
        editingState = LayerEditingState()
        suiteName = "maskrefine-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        AIMaskEditing.fineAutoTrigger = nil
        editorState?.maskRefine = nil
        if let suiteName { UserDefaults().removePersistentDomain(forName: suiteName) }
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: fixtures (the AIMaskPatchFlowTests shapes)

    /// The REAL load path (EditorState.load — it sets `loadedImageURL`,
    /// the session identity the coordinator arms against; the synthetic
    /// `PipeCoordinator.load` seam does not).
    private func loadSynthetic() async throws {
        let source = Self.fixtureDirectory.appendingPathComponent("no-icc-8.tif")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("fixture missing: no-icc-8.tif")
        }
        let url = tempDirectory.appendingPathComponent("no-icc-8.tif")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: source, to: url)
        editorState.load(
            url: url, decoder: RAWDecoder(), metal: metal,
            logger: EditorState.decodeLogger)
        let start = Date()
        while editorState.isDecoding, Date().timeIntervalSince(start) < 30 {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    private func commitQuickMask(layer: AdjustmentLayer) async throws -> RasterMaskRef {
        editingState.select(layer.id)
        // imageURL: nil = the production anchor (the LIVE session url — the
        // same directory the coordinator's process() reads the PNG back
        // from).
        return try await AIMaskEditing.commitRasterMask(
            plane: softPlane(), source: .subject,
            imageURL: nil, label: "quick",
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
    }

    /// A soft horizontal ramp — the uncertain band the fine pass acts on.
    private func softPlane() -> AIMaskPlane {
        AIMaskPlane(width: 48, height: 32, floats: (0..<1536).map { i in
            let x = Double(i % 48)
            return Float(1.0 / (1.0 + Foundation.exp(-(x - 24.0) / 4.0)))
        })
    }

    /// A two-tone guide with a strong colour edge (the fine pass has
    /// something to say on it).
    private func edgeGuide() -> MaskRefineGuide {
        let w = 96, h = 64
        var rgba = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if x < w / 2 {
                    rgba[i] = 0.1; rgba[i + 1] = 0.1; rgba[i + 2] = 0.12
                } else {
                    rgba[i] = 0.9; rgba[i + 1] = 0.85; rgba[i + 2] = 0.7
                }
                rgba[i + 3] = 1
            }
        }
        return MaskRefineGuide(width: w, height: h, rgba: rgba)
    }

    private func makeCoordinator(
        guideProvider: (@Sendable (URL) async throws -> MaskRefineGuide)? = nil
    ) -> MaskRefineCoordinator {
        let coordinator = MaskRefineCoordinator(
            pipe: self.coordinator, editor: editorState, editing: editingState,
            metal: metal, registry: ModuleRegistry.makeDefault(),
            defaults: defaults)
        coordinator.guideProvider = guideProvider
        return coordinator
    }

    // MARK: ① single flight + queue

    func testSingleFlightQueuesLaterRequests() async throws {
        try await loadSynthetic()
        let first = try XCTUnwrap(editorState.addAdjustmentLayer())
        _ = try await commitQuickMask(layer: first)
        let second = try XCTUnwrap(editorState.addAdjustmentLayer())
        _ = try await commitQuickMask(layer: second)
        let entered = Counter()
        let refine = makeCoordinator(guideProvider: { _ in
            entered.bump()
            try? await Task.sleep(for: .milliseconds(120))
            return MaskRefineCoordinatorTests.edgeGuideStatic()
        })
        refine.refineLater([first.id])
        // The first pass is in flight; the second request WAITS.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(refine.isBusy, "the first pass is in flight")
        refine.refineLater([second.id])
        XCTAssertEqual(refine.waitingCount, 1, "the later request queues")
        // The drain: both pass one at a time, then the queue empties.
        let deadline = Date().addingTimeInterval(15)
        while (refine.isBusy || refine.waitingCount > 0), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(refine.isBusy)
        XCTAssertEqual(refine.waitingCount, 0)
        XCTAssertEqual(entered.value, 2, "both passes ran (one at a time)")
    }

    /// Static twin of edgeGuide() (the @Sendable closure cannot capture
    /// self's mutable state — the guide is a pure value anyway).
    nonisolated static func edgeGuideStatic() -> MaskRefineGuide {
        let w = 96, h = 64
        var rgba = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if x < w / 2 {
                    rgba[i] = 0.1; rgba[i + 1] = 0.1; rgba[i + 2] = 0.12
                } else {
                    rgba[i] = 0.9; rgba[i + 1] = 0.85; rgba[i + 2] = 0.7
                }
                rgba[i + 3] = 1
            }
        }
        return MaskRefineGuide(width: w, height: h, rgba: rgba)
    }

    // MARK: ② the successful swap (the existing commit seam)

    func testSuccessfulRefineSwapsRasterWithOneHistoryItem() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let quickRef = try await commitQuickMask(layer: layer)
        let historyBefore = editorState.history.items.count
        let refine = makeCoordinator(guideProvider: { _ in
            MaskRefineCoordinatorTests.edgeGuideStatic()
        })
        try await refine.process(layerID: layer.id)
        // ONE history item (the M6-4 channel — ⌘Z removes the refine).
        XCTAssertEqual(
            editorState.history.items.count, historyBefore + 1,
            "the refine is ONE history commit (no new item type)")
        let layer2 = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        let refinedRef = try XCTUnwrap(layer2.mask?.raster)
        XCTAssertEqual(refinedRef.fileName, quickRef.fileName, "same-maskID overwrite")
        XCTAssertNotEqual(
            refinedRef.maskHash, quickRef.maskHash,
            "the raster hash flips → the plane actually changed")
        // ⌘Z removes exactly the refine; the quick face returns.
        XCTAssertTrue(editorState.performUndo())
        let undone = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        XCTAssertEqual(undone.mask?.raster?.maskHash, quickRef.maskHash)
    }

    /// The refine commit does NOT re-fire the auto trigger (the loop break
    /// — `refineCommit: true`); a plain generation commit DOES.
    func testTriggerHookLoopBreak() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        var fires = 0
        let refine = makeCoordinator(guideProvider: { _ in
            MaskRefineCoordinatorTests.edgeGuideStatic()
        })
        editorState.maskRefine = refine
        AIMaskEditing.fineAutoTrigger = { _ in fires += 1 }
        // The quick commit (a generation face) fires once.
        _ = try await commitQuickMask(layer: layer)
        XCTAssertEqual(fires, 1, "the generation commit fires the hook")
        // The refine's own commit does not.
        try await refine.process(layerID: layer.id)
        XCTAssertEqual(fires, 1, "the refine's own commit never re-triggers")
    }

    // MARK: ③ failure keeps the quick mask

    func testFailureKeepsQuickMaskAndToasts() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let quickRef = try await commitQuickMask(layer: layer)
        let historyBefore = editorState.history.items.count
        struct Injected: LocalizedError {
            var errorDescription: String? { "injected guide failure" }
        }
        let refine = makeCoordinator(guideProvider: { _ in throw Injected() })
        do {
            try await refine.process(layerID: layer.id)
            XCTFail("the injected failure must throw")
        } catch {
            // typed surface — the pump toasts it; the direct process call
            // sees the throw itself.
        }
        // The mask plane and the history are UNTOUCHED (the quick mask
        // floor — RESEARCH §风险 9).
        let after = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        XCTAssertEqual(after.mask?.raster?.maskHash, quickRef.maskHash)
        XCTAssertEqual(editorState.history.items.count, historyBefore)
        // The pump's toast face: run the queue path and observe the toast.
        let refine2 = makeCoordinator(guideProvider: { _ in throw Injected() })
        refine2.refineLater([layer.id])
        let deadline = Date().addingTimeInterval(10)
        while refine2.isBusy, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(editorState.toast, "the failure toast is present")
        XCTAssertTrue(
            editorState.toast?.contains("蒙版精细化失败") == true
                || editorState.toast?.contains("refinement failed") == true,
            "the toast names the keep-quick face: \(editorState.toast ?? "nil")")
    }

    // MARK: ④ the fineAuto gate

    func testFineAutoGateTypedReadAndSchedule() async throws {
        // Typed read: absent = true, explicit false = off.
        XCTAssertTrue(MaskRefineCoordinator.fineAutoEnabled(defaults: defaults))
        defaults.set(false, forKey: MaskRefineCoordinator.fineAutoKey)
        XCTAssertFalse(MaskRefineCoordinator.fineAutoEnabled(defaults: defaults))
        defaults.removeObject(forKey: MaskRefineCoordinator.fineAutoKey)
        XCTAssertTrue(MaskRefineCoordinator.fineAutoEnabled(defaults: defaults))
        // Off → the auto schedule is a no-op; the manual entry stays.
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        _ = try await commitQuickMask(layer: layer)
        defaults.set(false, forKey: MaskRefineCoordinator.fineAutoKey)
        let refine = makeCoordinator(guideProvider: { _ in
            MaskRefineCoordinatorTests.edgeGuideStatic()
        })
        refine.scheduleAutoRefine(layerID: layer.id)
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertFalse(refine.isBusy, "the off gate schedules nothing")
        // The manual entry still reaches the same pump.
        let entered = Counter()
        refine.guideProvider = { _ in
            entered.bump()
            return MaskRefineCoordinatorTests.edgeGuideStatic()
        }
        refine.refineLater([layer.id])
        let deadline = Date().addingTimeInterval(10)
        while refine.isBusy, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(entered.value, 1, "the manual entry still runs")
        // On → the auto schedule enqueues through the debounce.
        defaults.set(true, forKey: MaskRefineCoordinator.fineAutoKey)
        refine.scheduleAutoRefine(layerID: layer.id)
        let autoDeadline = Date().addingTimeInterval(10)
        while !refine.isBusy, Date() < autoDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(refine.isBusy, "the enabled gate auto-fires after the debounce")
        let drain = Date().addingTimeInterval(10)
        while refine.isBusy, Date() < drain {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(refine.isBusy)
    }

    // MARK: ⑤ the MCP face (string ids, typed unknown)

    func testMCPFaceTypesUnknownIDs() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        _ = try await commitQuickMask(layer: layer)
        let refine = makeCoordinator(guideProvider: { _ in
            MaskRefineCoordinatorTests.edgeGuideStatic()
        })
        // A garbage id and a well-formed-but-absent UUID both type out.
        for bad in ["not-a-uuid", UUID().uuidString] {
            do {
                try await refine.refineMasksForMCP([bad])
                XCTFail("'\(bad)' must type out")
            } catch let error as MaskRefineCoordinator.MaskRefineError {
                guard case .unknownMaskID(let id) = error else {
                    return XCTFail("unexpected error \(error)")
                }
                XCTAssertEqual(id, bad)
            }
        }
        // The valid id goes through (typed no-throw; the pump runs).
        try await refine.refineMasksForMCP([layer.id.uuidString])
        let deadline = Date().addingTimeInterval(10)
        while refine.isBusy, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(refine.isBusy)
    }
}
