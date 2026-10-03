import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// EnhanceDialogTests (Plan M2-10-06 T3d, KD-5 — APP bundle) — the dialog
// model + the engine orchestration, MODEL-FREE unless the resource gate
// opens:
//
//   • CANCEL (KD-2): a mid-run close arms the close-after semantics — the
//     current tile finishes, the engine cancels at the next checkpoint,
//     the phase lands on .cancelled, and shouldClose flips (never a hard
//     kill); the in-flight tile tmp files are swept (E4: the deletion
//     terminal state).
//   • PROGRESS: monotone non-decreasing, 15 → 93 endpoints (the Lumen
//     three-segment budget).
//   • IDENTITY (the multi-tile blend anchor, no model): an identity stub
//     inferencer through a 4-tile grid reproduces the input exactly (the
//     weight-normalized blend of equal values is the value).
//   • MODEL ABSENT: the typed failure surfaces (never a fake result);
//     the release-tier status face is the honest digestUnpublished.
//   • GOLDEN (resource gate): the real bundled general-x4v3 through the
//     REAL worker process — 64² → 256², deterministic within 1/255.
// ─────────────────────────────────────────────────────────────────────────────

func identityRun(_ request: EnhanceTileRequest) throws {
        let input = try EnhanceEngine.readTileFile(request.inputTile)
        var pixels = [UInt16](repeating: UInt16.max, count: input.width * input.height * 4)
        for index in 0..<(input.width * input.height) {
            for channel in 0..<3 {
                pixels[index * 4 + channel] = UInt16(
                    Int((min(max(input.rgb[index * 3 + channel], 0), 1)
                        * 65535.0).rounded()))
            }
        }
        let image = try EnhanceEngine.tileImage(
            pixels: pixels, width: input.width, height: input.height)
        guard let destination = CGImageDestinationCreateWithURL(
            request.outputTile as CFURL, "public.tiff" as CFString, 1, nil)
        else {
            throw EnhanceEngineError.tileFailed(
                index: request.tileIndex, detail: "stub destination failed")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EnhanceEngineError.tileFailed(
                index: request.tileIndex, detail: "stub finalize failed")
        }
    }

fileprivate let identityExecutor: @Sendable (EnhanceTileRequest) async throws -> Void = { request in
    try identityRun(request)
}


@MainActor
final class EnhanceDialogTests: XCTestCase {

    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("enhance-dialog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Stub plumbing

    /// A quantized gradient frame (values land on the uint16 grid — the
    /// identity round-trip stays within one quantization step).
    private func gradientFrame(width: Int, height: Int) -> EnhanceFrame {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            let k = (index * 7) % 65536
            let value = Float(k) / 65535.0
            rgba[index * 4] = value
            rgba[index * 4 + 1] = 1 - value
            rgba[index * 4 + 2] = value
            rgba[index * 4 + 3] = 1
        }
        return EnhanceFrame(rgba: rgba, width: width, height: height)
    }

    /// The identity stub inferencer: decodes the input tile and writes it
    /// back verbatim (scale 1). The engine's shape contract holds.
    private func makeModel(
        facts: (tileEdges: [Int], scale: Int) = (tileEdges: [256], scale: 1),
        tileExecutor: @escaping @Sendable (EnhanceTileRequest) async throws -> Void,
        modelFactsError: (any Error)? = nil,
        frame: EnhanceFrame? = nil
    ) -> EnhanceDialogModel {
        let frame = frame ?? gradientFrame(width: 300, height: 300)
        let context = EnhanceContext(
            originalURL: root.appendingPathComponent("orig.tif"),
            sourceImageID: UUID().uuidString,
            projectDirectory: root.appendingPathComponent("Proj", isDirectory: true),
            albumID: nil,
            importService: LightamerCore.ImportService(
                store: ProjectFileStore(
                    at: root.appendingPathComponent("unused.lalb"))))
        return EnhanceDialogModel(
            choice: .denoise(
                profileID: ModelAssetCatalog.drunetColorFP16.profileID,
                strength: 35),
            context: context,
            frameProvider: { frame },
            modelFacts: { _ in
                if let modelFactsError { throw modelFactsError }
                return facts
            },
            tileExecutor: tileExecutor)
    }

    // MARK: - Cancel (close-after)

    func testCancelMidRunLandsCancelledAndClosesAfter() async throws {
        let model = makeModel(tileExecutor: { request in
            // Each tile takes a beat — the cancel lands between tiles.
            try await Task.sleep(for: .milliseconds(120))
            try identityRun(request)
        })
        let runTask = Task { await model.runFullCopy() }
        // Wait for the run to start, then arm the close-after.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(model.isBusy)
        model.closeRequested()
        // Join the run (the bare handle await does not wait for the value).
        _ = await runTask.value

        XCTAssertEqual(model.phase, .cancelled,
            "the cancel lands at the next tile checkpoint")
        XCTAssertTrue(model.shouldClose, "the close-after arm fires on settle")
    }

    func testEngineCancelSweepsInFlightTileFiles() async throws {
        // The E4 terminal state at the ENGINE level: a cancel deletes the
        // in-flight tile tmp files (the model's close-after arm feeds this
        // flag through in production).
        let engine = EnhanceEngine(supportedEdges: [256], scale: 1, amount: 35)
        let tmp = root.appendingPathComponent("cancel-tmp", isDirectory: true)
        let flag = CancelBox()
        // Tile 0 arms the cancel; tile 1's checkpoint fires it.
        do {
            _ = try await engine.run(
                prepared: EnhanceEngine.prepareInput(
                    gradientFrame(width: 300, height: 300)),
                tmpDirectory: tmp,
                tileExecutor: { request in
                    if request.tileIndex == 0 { flag.setTrue() }
                    try await Task.sleep(for: .milliseconds(60))
                    try identityRun(request)
                },
                cancellation: { flag.isSet })
            XCTFail("the armed cancel must surface as .cancelled")
        } catch EnhanceEngineError.cancelled {
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "no half-made tile tmp survives")
    }

    private final class CancelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var isSetStorage = false
        func setTrue() {
            lock.lock()
            isSetStorage = true
            lock.unlock()
        }
        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isSetStorage
        }
    }

    func testIdleCloseClosesImmediately() async {
        let model = makeModel(tileExecutor: identityExecutor)
        XCTAssertFalse(model.isBusy)
        model.closeRequested()
        XCTAssertTrue(model.shouldClose, "an idle close needs no cancel arm")
        XCTAssertEqual(model.phase, .idle)
    }

    // MARK: - Progress

    func testProgressIsMonotonicWithPinnedEndpoints() async throws {
        let recorded = RecordedProgress()
        // Drive the ENGINE directly so the progress callbacks are
        // observable (the model maps them onto the phase face).
        let engine = EnhanceEngine(
            supportedEdges: [256], scale: 1, amount: 35)
        let tmp = root.appendingPathComponent("progress-tmp", isDirectory: true)
        _ = try await engine.run(
            prepared: EnhanceEngine.prepareInput(
                gradientFrame(width: 300, height: 300)),
            tmpDirectory: tmp,
            tileExecutor: identityExecutor,
            onProgress: { percent in recorded.append(percent) })
        let values = recorded.values
        XCTAssertGreaterThanOrEqual(values.first ?? 0, 15)
        XCTAssertEqual(values.last, 93)
        for index in 1..<values.count {
            XCTAssertGreaterThanOrEqual(
                values[index], values[index - 1], "monotone non-decreasing")
        }
    }

    private final class RecordedProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Int] = []
        func append(_ value: Int) {
            lock.lock()
            storage.append(value)
            lock.unlock()
        }
        var values: [Int] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    // MARK: - The identity multi-tile anchor (no model)

    func testEngineMultiTileIdentityReproducesInputExactly() async throws {
        let engine = EnhanceEngine(supportedEdges: [256], scale: 1, amount: 35)
        let input = gradientFrame(width: 300, height: 300) // 2×2 tiles
        let output = try await engine.run(
            prepared: EnhanceEngine.prepareInput(input),
            tmpDirectory: root.appendingPathComponent("identity-tmp"),
            tileExecutor: identityExecutor)
        XCTAssertEqual(output.width, 300)
        XCTAssertEqual(output.height, 300)
        // The identity blend is the value (within one quantization step —
        // the fp32→uint16 input quantization is the only lossy leg).
        for index in 0..<(300 * 300 * 4) {
            XCTAssertEqual(
                output.rgba[index], input.rgba[index], accuracy: 2.0 / 65535.0,
                "index \(index): the tiled identity reproduces the input")
        }
    }

    // MARK: - Model absent (typed faces)

    func testModelFactsFailureSurfacesTypedAndNeverFakes() async throws {
        struct Unavailable: Error {}
        let model = makeModel(
            tileExecutor: identityExecutor, modelFactsError: Unavailable())
        await model.runFullCopy()
        guard case .failed(let message) = model.phase else {
            return XCTFail("typed failure expected, got \(model.phase)")
        }
        XCTAssertFalse(message.isEmpty, "the honest failure face")
        XCTAssertFalse(model.shouldClose, "a failure does not arm close-after")
    }

    func testReleaseModelWithoutDigestIsDigestUnpublished() async {
        // Fail-closed: x4plus has no published digest (M2-10-01) — the
        // honest「待发布」face, never a download attempt.
        let store = ModelAssetStore()
        let status = await store.status(
            for: ModelAssetCatalog.realESRGANX4PlusFP16.profileID)
        XCTAssertEqual(status, .digestUnpublished)
        let model = makeModel(tileExecutor: identityExecutor)
        await model.refreshModelStatus()
        // The dialog refreshes the SELECTED profile (drunet — also release
        // tier, also digest-unpublished).
        XCTAssertEqual(
            model.modelStatuses[ModelAssetCatalog.drunetColorFP16.profileID],
            .digestUnpublished)
        // The bundled fast tier IS ready (this machine carries the folder
        // reference; absent environments skip the bundle-level tests).
        if ModelLocator().bundledProfileURL(
            ModelAssetCatalog.realesrGeneralX4V3FP16.profileID) != nil {
            let fast = await store.status(
                for: ModelAssetCatalog.realesrGeneralX4V3FP16.profileID)
            XCTAssertEqual(fast, .bundled)
        }
    }

    // MARK: - Preview

    func testCentralCropTakesTheClampedCenter() {
        let frame = gradientFrame(width: 100, height: 60)
        let crop = EnhanceDialogModel.centralCrop(frame, edge: 40)
        XCTAssertEqual(crop.width, 40)
        XCTAssertEqual(crop.height, 40)
        XCTAssertEqual(crop.rgba.count, 40 * 40 * 4)
        // The crop origin is the image center (30, 10).
        let originX = 30, originY = 10
        let sourceIndex = (originY * 100 + originX) * 4
        XCTAssertEqual(crop.rgba[0], frame.rgba[sourceIndex])
        XCTAssertEqual(crop.rgba[1], frame.rgba[sourceIndex + 1])
    }

    func testPreviewWithIdentityStubMakesBeforeEqualAfter() async throws {
        let model = makeModel(
            tileExecutor: identityExecutor,
            frame: gradientFrame(width: 300, height: 300))
        await model.runPreview()
        XCTAssertEqual(model.phase, .previewReady)
        let before = try XCTUnwrap(model.beforePreview)
        let after = try XCTUnwrap(model.afterPreview)
        XCTAssertEqual(before.width, after.width)
        XCTAssertEqual(before.height, after.height)
        // Identity: the enhanced preview equals the input preview.
        for index in 0..<before.rgba.count {
            XCTAssertEqual(
                after.rgba[index], before.rgba[index], accuracy: 2.0 / 65535.0)
        }
    }

    // MARK: - The real-model golden (resource gate)

    func testRealModelGolden64SquaredTo256SquaredThroughWorker() async throws {
        // RESOURCE GATE: the bundled general-x4v3 folder reference. Absent
        // = XCTSkip (the zero-fail hard AC; the skip count is registered).
        let profile = ModelAssetCatalog.realesrGeneralX4V3FP16
        let locator = ModelLocator()
        guard locator.bundledProfileURL(profile.profileID) != nil else {
            throw XCTSkip("bundled general-x4v3 absent — the resource-gate skip")
        }
        // The REAL worker process (M2-10-05 harness) + the M2-10-06 leg.
        let record = CompatRecord(path: root.appendingPathComponent("compat.json"))
        let client = AIWorkerClient(
            configuration: .init(
                record: record, openTimeout: 600, runTimeout: 300))
        defer { Task { await client.stop() } }
        let facts = try await client.openEnhancement(profile.profileID)
        // The static-converted asset reports exactly its baked edge and
        // the ×4 factor (the worker leg's constraint reading).
        XCTAssertEqual(facts.tileEdges, [256])
        XCTAssertEqual(facts.scale, 4)

        let engine = EnhanceEngine(
            supportedEdges: facts.tileEdges, scale: facts.scale, amount: nil)
        let input = gradientFrame(width: 64, height: 64)
        let tmp = root.appendingPathComponent("golden-tmp", isDirectory: true)
        let executor: @Sendable (EnhanceTileRequest) async throws -> Void =
            { request in
                _ = try await client.enhanceTile(
                    profile.profileID,
                    inPath: request.inputTile.path,
                    outPath: request.outputTile.path,
                    feedHeight: request.feedHeight,
                    feedWidth: request.feedWidth,
                    amount: request.amount)
            }
        let first = try await engine.run(
            prepared: EnhanceEngine.prepareInput(input),
            tmpDirectory: tmp, tileExecutor: executor)
        XCTAssertEqual(first.width, 256, "64² × 4 = 256²")
        XCTAssertEqual(first.height, 256)
        // Finite + in-domain.
        for value in first.rgba {
            XCTAssertTrue(value.isFinite)
            XCTAssertTrue((0.0...1.0).contains(value))
        }
        // Determinism within 1/255 (the tile-consistency tolerance — the
        // CoreML numeric-stability anchor, Lumen MODEL.md:9). The SECOND
        // run reuses the SAME prepared input — the quantization is
        // deterministic and the golden is reproducible.
        let second = try await engine.run(
            prepared: EnhanceEngine.prepareInput(input),
            tmpDirectory: tmp, tileExecutor: executor)
        XCTAssertEqual(second.width, 256)
        for index in 0..<first.rgba.count {
            XCTAssertEqual(
                first.rgba[index], second.rgba[index], accuracy: 1.0 / 255.0,
                "index \(index): the golden is deterministic within 1/255")
        }
        await client.stop()
    }

    // MARK: - The M-1 memory-posture regression (the two-phase pin, the
    // typed gate, the footprint arithmetic)

    func testPrepareInputFiresOnInputConsumedAndQuantizesClamped() {
        let frame = gradientFrame(width: 8, height: 8)
        let fired = CounterBox()
        let prepared = EnhanceEngine.prepareInput(frame) {
            fired.increment()
        }
        XCTAssertEqual(
            fired.value, 1,
            "the callback fires before prepareInput returns — the caller "
                + "drops their fp32 there")
        XCTAssertEqual(prepared.width, 8)
        XCTAssertEqual(prepared.height, 8)
        XCTAssertEqual(prepared.working.count, 8 * 8 * 3)
        // The quantization contract: uint16 RGB off the [0,1] clamp.
        XCTAssertEqual(
            prepared.working[0],
            UInt16(Int((frame.rgba[0] * 65535.0).rounded())))
        var hot = gradientFrame(width: 2, height: 2)
        hot.rgba[0] = 1.5
        hot.rgba[1] = -0.5
        let hotPrepared = EnhanceEngine.prepareInput(hot)
        XCTAssertEqual(hotPrepared.working[0], 65535, "values clamp on encode")
        XCTAssertEqual(hotPrepared.working[1], 0)
    }

    func testMemoryBudgetGateRejectsTypedBeforeAnyTileRuns() async throws {
        let calls = CounterBox()
        // A budget no real job meets — the gate must fire BEFORE the tile
        // loop (no I/O, no tmp, no allocation toward the output).
        let engine = EnhanceEngine(
            supportedEdges: [256], scale: 2, amount: nil,
            memoryBudgetBytes: 1024)
        let tmp = root.appendingPathComponent("gate-tmp", isDirectory: true)
        do {
            _ = try await engine.run(
                prepared: EnhanceEngine.prepareInput(
                    gradientFrame(width: 300, height: 300)),
                tmpDirectory: tmp,
                tileExecutor: { _ in calls.increment() })
            XCTFail("the gate must reject before the tile loop")
        } catch EnhanceEngineError.memoryBudgetExceeded(
            let estimated, let limit)
        {
            XCTAssertEqual(limit, 1024)
            XCTAssertGreaterThan(estimated, limit)
        }
        XCTAssertEqual(calls.value, 0, "no tile ran — no OOM button")
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "the rejection precedes any I/O")
    }

    func testEstimatedPeakBytesPinsTheFootprintConstants() {
        // The honest worst case the gate guards: 16 B/output px (the fp32
        // RGBA accumulator — the single buffer) + 8 B/output px (the
        // writer's uint16 encode transient) + 6 B/input px (the uint16
        // working input).
        XCTAssertEqual(
            EnhanceEngine.estimatedPeakBytes(
                outputPixels: 100, inputPixels: 25),
            100 * 24 + 25 * 6)
        // The default budget sits under the 8192 MB run gate with
        // headroom (the MEMFAIL line stays unreachable through the gate).
        XCTAssertLessThan(
            EnhanceEngine.memoryBudgetBytes, 8 * 1024 * 1024 * 1024)
        // The M2AI-09 headline case (100MP@×2 = 400M output px) is
        // HONESTLY gated out until the E3 streaming unlock — the gate
        // arithmetic must refuse it rather than OOM (the M-1 #3 ruling).
        XCTAssertGreaterThan(
            EnhanceEngine.estimatedPeakBytes(
                outputPixels: 400_000_000, inputPixels: 100_000_000),
            EnhanceEngine.memoryBudgetBytes)
    }

    private final class CounterBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0
        func increment() {
            lock.lock(); storage += 1; lock.unlock()
        }
        var value: Int {
            lock.lock(); defer { lock.unlock() }; return storage
        }
    }

}
