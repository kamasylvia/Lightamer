import AppKit
import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-04 T6/T7 — the before/after base (HIST-06):
//
//   ① the BEFORE plane == an INDEPENDENT pristine-chain render, BYTE-EXACT
//     (L014 fenced read-back; the L020 content-level rule);
//   ② the PEEK(k) plane == a replay of that point's projected state,
//     BYTE-EXACT, and the projection never moves the pointer;
//   ③ peek/hold produce ZERO history items (D-H1 orthogonality);
//   ④ the hold fast path performs ZERO renders (the plane is resident —
//     the override-render counter must not move);
//   ⑤ the override render with the LIVE records == the default path's
//     output byte-for-byte (the "无参调用 == 既有语义" regression pin at
//     the data level; the default path itself is untouched — additive
//     method — and the golden/parity suites re-run as the broader pin).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class BeforeAfterTests: XCTestCase {

    private var metal: MetalContext!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var registry: ModuleRegistry!

    override func setUp() async throws {
        try await super.setUp()
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
        self.registry = registry
    }

    // MARK: - Fixtures

    nonisolated private static func decodedGradient(size: Int = 240) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8
        )
    }

    /// Load the fixture through the REAL coordinator load (pristine seed).
    private func loadFixture() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ba-\(UUID().uuidString).ARW")
        try Data(repeating: 0xCD, count: 64).write(to: url)
        await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    /// L014-fenced byte read-back.
    nonisolated private static func readBytes(_ texture: any MTLTexture) -> [UInt8] {
        let w = texture.width, h = texture.height
        let rowBytes = w * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return bytes
    }

    nonisolated private static func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// An INDEPENDENT render of the given records (throwaway cache, the
    /// same display fold the override path applies) — the reference leg.
    nonisolated private static func independentRender(
        records: [ModuleInstance], decoded: DecodedImage, imageID: UUID,
        longEdge: Int, metal: MetalContext, registry: ModuleRegistry
    ) async throws -> [UInt8] {
        let (boxes, _) = await registry.materializeBoxes(for: records)
        if let colorout = boxes.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            colorout.module.displayProfileOverride = DisplayProfile.resolve(
                NSScreen.main?.colorSpace)
            let params = (try? JSONDecoder().decode(
                ColorOutModule.Params.self, from: colorout.paramsData))
                ?? ColorOutModule.Params()
            colorout.setParams(params)
        }
        let (texture, _) = try await RenderPipeline.process(
            image: decoded, instances: boxes, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: longEdge)
        drain(metal)
        return readBytes(texture)
    }

    private func currentBucket() -> Int {
        PreviewBucket.cap
    }

    // MARK: ① the pristine BEFORE plane

    func testBeforePlaneMatchesIndependentPristineRenderByteExactly() async throws {
        try await loadFixture()
        let before = try await coordinator.renderPristinePlane()
        Self.drain(metal)
        let beforeBytes = Self.readBytes(before)

        let decoded = try XCTUnwrap(coordinator.detectionSourceImage())
        let reference = try await Self.independentRender(
            records: editorState.pristineSeedRecords, decoded: decoded,
            imageID: UUID(), // cache-isolated reference leg (byte equality, not cache reuse)
            longEdge: currentBucket(), metal: metal, registry: registry)
        XCTAssertEqual(
            beforeBytes, reference,
            "the BEFORE plane is byte-identical to an independent pristine-chain render (L020 content-level)")
    }

    // MARK: ② the PEEK plane

    func testPeekPlaneMatchesReplayedProjectionByteExactly() async throws {
        try await loadFixture()
        // Two commits: exposure +1EV then exposure +2EV (latest wins).
        let first = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.0))
        let second = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 2.0))
        editorState.recordChange(first, label: "e1")
        editorState.recordChange(second, label: "e2")
        XCTAssertEqual(editorState.history.items.count, 2)

        // PEEK at point 0 (the +1EV state): the plane must equal a replay
        // of that point's projected state.
        let peek = try await coordinator.renderHistoryPeekPlane(at: 0)
        Self.drain(metal)
        let peekBytes = Self.readBytes(peek)
        let (records, _) = editorState.history.projectedState(at: 0)
        let reference = try await Self.independentRender(
            records: records,
            decoded: try XCTUnwrap(coordinator.detectionSourceImage()),
            imageID: UUID(), // cache-isolated reference leg
            longEdge: currentBucket(), metal: metal, registry: registry)
        XCTAssertEqual(
            peekBytes, reference,
            "peek(k) is byte-identical to a replay of the point-k projection")
        // The peeked point's exposure is the +1EV record (not live's +2EV).
        XCTAssertEqual(
            records.first { $0.opName == ExposureModule.opName }?.paramsHash,
            first.paramsHash)

        // D-H1 orthogonality: the peek moved NOTHING.
        XCTAssertEqual(editorState.history.items.count, 2)
        XCTAssertEqual(editorState.history.position, 1)
        XCTAssertEqual(
            editorState.history.currentValue?.paramsHash, second.paramsHash,
            "the live pointer still sits at the newest commit")
    }

    // MARK: ③④ zero history items + the hold zero-render fast path

    func testPeekAndHoldProduceZeroHistoryItemsAndHoldRendersNothing() async throws {
        try await loadFixture()
        let itemsBefore = editorState.history.items.count
        let positionBefore = editorState.history.position

        // The first compare-plane fetch renders (the resident cost).
        _ = try await coordinator.renderPristinePlane()
        let rendersAfterFirst = coordinator.overrideRenderCount
        XCTAssertEqual(rendersAfterFirst, 1)

        // HOLD on/off: a pure blit/state flip — ZERO new renders.
        let state = BeforeAfterState()
        state.splitEnabled = true
        state.isHoldingOriginal = true
        XCTAssertEqual(state.effectiveSplitFraction, 0, "hold forces the whole viewport to BEFORE")
        state.isHoldingOriginal = false
        XCTAssertEqual(state.effectiveSplitFraction, 0.5)
        state.isHoldingOriginal = true
        state.isHoldingOriginal = false
        XCTAssertEqual(
            coordinator.overrideRenderCount, rendersAfterFirst,
            "the hold fast path performs ZERO renders (the plane is resident)")

        // And zero history items through it all.
        XCTAssertEqual(editorState.history.items.count, itemsBefore)
        XCTAssertEqual(editorState.history.position, positionBefore)
    }

    // MARK: ⑤ the default-path regression pin (data level)

    func testOverrideWithLiveRecordsMatchesDefaultPathOutput() async throws {
        try await loadFixture()
        // Commit an edit so the live chain is non-trivial, then let the
        // default path render it (historyDidChange pushes displayTexture).
        var edit = try XCTUnwrap(editorState.instances.first { $0.opName == ExposureModule.opName })
        try edit.setParams(ExposureModule.Params(exposure: 0.7), as: ExposureModule.self)
        editorState.recordChange(edit, label: "e0.7")
        // recordChange fires its render as a fire-and-forget Task; settle
        // until the push chain is quiescent (the GUI22 pattern) — reading
        // displayTexture mid-flight would race the newest-wins renders.
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<20 { await Task.yield() }
        Self.drain(metal)
        let display = try XCTUnwrap(editorState.displayTexture)
        let defaultBytes = Self.readBytes(display)

        // The OVERRIDE with the SAME live records (flat — no layers here)
        // must be byte-identical to the default path's output.
        let overridden = try await coordinator.renderPreview(
            instances: editorState.instances, layerStack: nil,
            bucket: PreviewBucket.cap)
        Self.drain(metal)
        XCTAssertEqual(
            Self.readBytes(overridden.texture), defaultBytes,
            "override(live records) == default path output byte-for-byte (the no-op-override regression pin)")
    }

    // MARK: state unit face

    func testBeforeAfterStateUnitFace() {
        let state = BeforeAfterState()
        XCTAssertFalse(state.isCompareActive)
        state.splitEnabled = true
        XCTAssertTrue(state.isCompareActive)
        state.peekIndex = 2
        // The compare label is 1-BASED for users (history index 2 = step 3).
        XCTAssertTrue(
            state.comparePointLabel.contains("3"),
            "the label shows the 1-based step (got: \(state.comparePointLabel))")
        state.peekIndex = nil
        state.isHoldingOriginal = true
        XCTAssertTrue(state.comparePointLabel.contains("原图"))
        state.reset()
        XCTAssertNil(state.peekIndex)
        XCTAssertFalse(state.splitEnabled)
        XCTAssertFalse(state.isHoldingOriginal)
    }
}

