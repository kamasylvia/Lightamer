@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

/// AIMaskIterativeSessionTests (M9-1 T3, M9AIM-02) — the iterative
/// tap-to-segment session pins:
/// ① the point-level delete (D-M9A-5's minimal face — the budget headroom
///    returns with the point);
/// ② the 300ms re-solve debounce state machine (a burst of point changes
///    collapses into ONE solve, the last wins — the injected clock seam);
/// ③ the candidate-retention face: a FAILED re-solve keeps the OLD
///    candidate (a scripted not-ready store — the typed refusal path);
/// ④ the `.candidate` style's AI-06 fence: the display enum case exists,
///    the picker whitelist EXCLUDES it (M-1), the sidecar schema carries
///    nothing new;
/// ⑤ the commit/cancel clearance: the candidate plane AND the
///    coordinator's candidate overlay request both die (D-M9A-4);
/// ⑥ the visual mapping's single source (the marker RGB constants).
@MainActor
final class AIMaskIterativeSessionTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aimaskiter-\(UUID().uuidString)", isDirectory: true)
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
    }

    override func tearDown() async throws {
        editingState?.segmentSession.candidateDebounceTask?.cancel()
        editingState?.segmentSession.patchDebounceTask?.cancel()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func loadSynthetic() async throws {
        let width = 32, height = 32
        var rgba = [Float](repeating: 0.25, count: width * height * 4)
        for i in 0..<(width * height) { rgba[i * 4 + 3] = 1.0 }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        try await coordinator.load(
            url: tempDirectory.appendingPathComponent("image.exr"),
            decoded: DecodedImage(
                ciImage: CIImage(cgImage: cg),
                rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
                segmentationSkyMatte: nil, decoderVersionUsed: .v8),
            instances: [], metal: metal)
        try await Task.sleep(for: .milliseconds(20))
    }

    // MARK: ① the point-level delete

    /// Removing an included/excluded refine point returns the budget
    /// headroom; a seed reset clears the whole candidate face with it.
    func testPointDeleteReturnsBudgetHeadroom() throws {
        let session = SegmentSession()
        try session.addIncluded(AIMaskPoint(x: 0.5, y: 0.5)) // becomes the SEED
        try session.addIncluded(AIMaskPoint(x: 0.6, y: 0.5)) // refine #1
        try session.addExcluded(AIMaskPoint(x: 0.4, y: 0.5)) // refine #2
        XCTAssertEqual(session.usedPoints, 3)

        session.removeIncluded(at: 0)
        XCTAssertEqual(session.included.count, 0)
        XCTAssertEqual(session.usedPoints, 2, "the headroom returns with the point")

        session.removeExcluded(at: 0)
        XCTAssertEqual(session.usedPoints, 1)

        // Out-of-range removals are no-ops.
        session.removeIncluded(at: 9)
        XCTAssertEqual(session.included.count, 0)
    }

    // MARK: ② the re-solve debounce state machine

    /// Five schedules inside the window → exactly ONE solve runs and it
    /// is the LAST one (each schedule cancels the previous — the D-M9A-1
    /// merge; the injected `delay` is the clock seam).
    func testCandidateDebounceMergesBurstIntoSingleSolve() async throws {
        let session = SegmentSession()
        var runs = 0
        var lastTag = 0
        for tag in 1...5 {
            AIMaskEditing.scheduleCandidateResolve(
                session: session, delay: .milliseconds(60)) {
                runs += 1
                lastTag = tag
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(runs, 1, "a burst of point changes collapses into ONE solve")
        XCTAssertEqual(lastTag, 5, "the LAST scheduled solve is the one that runs")
        session.candidateDebounceTask?.cancel()
        // The constant in册 (the single source).
        XCTAssertEqual(SegmentSession.candidateDebounceMs, 300)
    }

    // MARK: ③ the candidate retention on failure

    /// A FAILED re-solve keeps the OLD candidate (the upstream「推理期间
    /// 保留旧 coverage」semantics): a scripted not-ready store throws the
    /// typed modelNotReady — the candidate plane survives, the state
    /// returns to ready, nothing clears.
    func testFailedResolveKeepsOldCandidate() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        let session = editingState.segmentSession
        session.recordSeed(.point(AIMaskPoint(x: 0.5, y: 0.5)))
        let oldPlane = AIMaskPlane(
            width: 8, height: 8, floats: [Float](repeating: 0.5, count: 64))
        session.candidatePlane = oldPlane
        session.candidateState = .ready

        let notReady = AIAssetStore(
            statusProbe: { .notReady }, downloader: { _ in })
        await AIMaskEditing.runCandidateResolve(
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal, assets: notReady)

        XCTAssertEqual(session.candidatePlane?.floats, oldPlane.floats,
                       "the failed solve KEEPS the old candidate")
        XCTAssertEqual(session.candidateState, .ready,
                       "the state returns to ready (the old candidate is shown)")
    }

    // MARK: ④ the .candidate style's AI-06 fence

    /// The fourth display case exists; the user-facing whitelist EXCLUDES
    /// it (M-1 — the picker can never offer it); `allCases` carries it
    /// (the display arm's own enumeration).
    func testCandidateStyleIsDisplayOnlyAndWhitelistedOut() {
        XCTAssertTrue(MaskOverlayStyle.allCases.contains(.candidate))
        XCTAssertFalse(
            MaskOverlayStyle.userSelectableCases.contains(.candidate),
            "M-1: the session's coverage arm never enters the user menu")
        XCTAssertEqual(
            MaskOverlayStyle.userSelectableCases,
            [.translucent, .rubylith, .onBlack])
        // The tint constant in册 (the upstream numeric fact).
        XCTAssertEqual(MaskOverlayStyle.candidateTint.x, 1.0, accuracy: 1e-6)
        XCTAssertEqual(MaskOverlayStyle.candidateTint.y, 0.32, accuracy: 1e-6)
        XCTAssertEqual(MaskOverlayStyle.candidateTint.z, 0.42, accuracy: 1e-6)
    }

    /// The AI-06 negative: the session candidate NEVER enters the sidecar
    /// — serializing a document that carries one yields zero candidate
    /// keys (the schema gained nothing; the interaction writes no
    /// parameter truth).
    func testCandidateNeverPersistsIntoSidecar() throws {
        let session = SegmentSession()
        session.recordSeed(.point(AIMaskPoint(x: 0.5, y: 0.5)))
        session.candidatePlane = AIMaskPlane(
            width: 4, height: 4, floats: [Float](repeating: 1, count: 16))
        session.candidateState = .ready
        let document = makeSidecarDocument()
        let data = try JSONEncoder().encode(document)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("candidate"),
                       "AI-06: the candidate plane/state stays out of the sidecar")
        XCTAssertFalse(text.contains("candidatePlane"))
        // The .candidate style: the display enum never had a record face —
        // the sidecar's mask spec carries raster/parametric only.
        XCTAssertFalse(text.contains("mask_overlay_style"))
    }

    // MARK: ⑤ the commit/cancel clearance (D-M9A-4)

    /// A real commit through the seam: the candidate plane AND the
    /// coordinator's candidate overlay request BOTH clear (the ordinary
    /// edit tint takes over inside commitRasterMask); exactly ONE
    /// history item lands (the AI-06 form).
    func testCommitClearsCandidatePlaneAndOverlayRequest() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        let session = editingState.segmentSession
        session.recordSeed(.point(AIMaskPoint(x: 0.5, y: 0.5)))
        session.candidatePlane = AIMaskPlane(
            width: 16, height: 16,
            floats: (0..<256).map { ($0 % 16 < 8) ? Float(1) : Float(0) })
        session.candidateState = .ready
        let texture = try AIMaskResample.texture(
            from: session.candidatePlane!, metal: metal)
        coordinator.setCandidateOverlayRequest((texture, 0.6))
        XCTAssertNotNil(coordinator.candidateOverlayRequest)

        let historyBefore = editorState.history.items.count
        _ = try await AIMaskEditing.commitRasterMask(
            plane: session.candidatePlane!, source: .segment,
            imageURL: tempDirectory, label: "iterative commit",
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)

        XCTAssertNil(session.candidatePlane, "D-M9A-4: the candidate plane dies at commit")
        XCTAssertEqual(session.candidateState, .idle)
        XCTAssertNil(coordinator.candidateOverlayRequest,
                     "D-M9A-4: the candidate channel disappears at commit")
        XCTAssertEqual(
            editorState.history.items.count, historyBefore + 1,
            "exactly ONE stackSnapshot per confirm")
    }

    /// The cancel face: releaseCandidate + the request clear — zero
    /// bake, zero history (the「已解候选未 confirm」discard).
    func testCancelDiscardsCandidateWithZeroBake() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        let session = editingState.segmentSession
        session.recordSeed(.point(AIMaskPoint(x: 0.5, y: 0.5)))
        session.candidatePlane = AIMaskPlane(
            width: 4, height: 4, floats: [Float](repeating: 1, count: 16))
        session.candidateState = .ready
        let texture = try AIMaskResample.texture(from: session.candidatePlane!, metal: metal)
        coordinator.setCandidateOverlayRequest((texture, 0.6))
        let historyBefore = editorState.history.items.count

        session.releaseCandidate()
        coordinator.setCandidateOverlayRequest(nil)

        XCTAssertNil(session.candidatePlane)
        XCTAssertEqual(session.candidateState, .idle)
        XCTAssertNil(coordinator.candidateOverlayRequest)
        XCTAssertNil(layer.mask?.raster, "cancel bakes NOTHING")
        XCTAssertEqual(
            editorState.history.items.count, historyBefore,
            "cancel publishes zero history items")
    }

    // MARK: ⑥ the visual mapping's single source

    /// The marker palette constants (the upstream numeric facts the
    /// canvas projects from — the machine-checkable side of the visual
    /// mapping).
    func testMarkerPaletteSingleSource() {
        XCTAssertEqual(SegmentEditingOverlayHost.includedMarkerRGB.x, Float(0x30) / 255, accuracy: 1e-6)
        XCTAssertEqual(SegmentEditingOverlayHost.includedMarkerRGB.y, Float(0xA4) / 255, accuracy: 1e-6)
        XCTAssertEqual(SegmentEditingOverlayHost.includedMarkerRGB.z, Float(0x6C) / 255, accuracy: 1e-6)
        XCTAssertEqual(SegmentEditingOverlayHost.excludedMarkerRGB.x, Float(0xE5) / 255, accuracy: 1e-6)
        XCTAssertEqual(SegmentEditingOverlayHost.excludedMarkerRGB.y, Float(0x48) / 255, accuracy: 1e-6)
        XCTAssertEqual(SegmentEditingOverlayHost.excludedMarkerRGB.z, Float(0x4D) / 255, accuracy: 1e-6)
    }

    // MARK: fixtures

    private func makeSidecarDocument() -> LightamerSidecar {
        LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 0,
            instances: [], history: HistoryStack(), historyHash: 0)
    }
}
