import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExportAssemblyTests (Plan M2-9-04 T3, KD-5) — the M2 入队装配 face, captured
// through the REAL queue with injected legs (the ExportQueueTests trick):
// `enqueueExportM2` fans the batch out and the legs read the per-job payload
// carriers INSIDE the `withValue` scopes the actor scopes them in — the
// capture IS the production chain shape (真链形态，非 stub).
//
//   • AC5 逐字段: instancesOverride = the live projection for the OPEN
//     image / nil for the others (disk sidecar truth); drtTail.record =
//     the passed record + the catalog post-op demotion set; sequence =
//     the queue-stamped batch ordinal; collision/subfolder carried; the
//     exifSoftware carrier rides `$jobExifSoftware` into the encode leg.
//   • the peak gate 兜底: a bad record on the assembled variant is the
//     validate() typed refusal (the M2-9-03 gate — the assembly never
//     pre-validates, the renderer's gate owns it).
//   • the queue face's state-layer contracts: the four-state projection +
//     the 36-row preview cap.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ExportAssemblyTests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("m2904-assembly-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = tempDirectory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// The thread-safe capture box (the ExportQueueTests Counter precedent).
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [CapturedJob] = []

        struct CapturedJob: Equatable {
            var relPath: String
            var instancesOverride: [ModuleInstance]?
            var drtRecord: DrtRecord?
            var postOpNames: [String]
            var pattern: String?
            var sequence: Int?
            var fallbackStem: String?
            var collisionPolicy: ExportNamer.ExportCollisionPolicy
            var subfolder: String?
            var exifSoftware: String?
            var variant: ExportVariant?
        }

        func append(_ row: CapturedJob) {
            lock.lock()
            defer { lock.unlock() }
            rows.append(row)
        }

        var all: [CapturedJob] {
            lock.lock()
            defer { lock.unlock() }
            return rows
        }
    }

    /// The ExportState with an injected-leg queue (the test seam; no Metal).
    private func makeState(_ capture: Capture) -> ExportState {
        let state = ExportState()
        let renderLeg: ExportRenderLeg = { snapshot, context in
            capture.append(Capture.CapturedJob(
                relPath: snapshot.relPath,
                instancesOverride: context.instancesOverride,
                drtRecord: ExportRenderer.jobDrtTail?.record,
                postOpNames: ExportRenderer.jobDrtTail?.postOpNames ?? [],
                pattern: ExportRenderer.jobNamingCarrier?.naming?.pattern,
                sequence: ExportRenderer.jobNamingCarrier?.naming?.sequence,
                fallbackStem: ExportRenderer.jobNamingCarrier?.naming?.fallbackStem,
                collisionPolicy: ExportRenderer.jobNamingCarrier?.collisionPolicy
                    ?? .increment,
                subfolder: ExportRenderer.jobNamingCarrier?.subfolder,
                exifSoftware: nil,
                variant: nil))
            return ExportRenderArtifact(
                token: snapshot.seq, width: 8, height: 8, stage: nil)
        }
        let encodeLeg: ExportEncodeLeg = { artifact, variant in
            capture.append(Capture.CapturedJob(
                relPath: "encode",
                instancesOverride: nil,
                drtRecord: nil,
                postOpNames: [],
                pattern: nil,
                sequence: nil,
                fallbackStem: nil,
                collisionPolicy: .increment,
                subfolder: nil,
                exifSoftware: ExportRenderer.jobExifSoftware,
                variant: variant))
            return URL(fileURLWithPath: "/synthetic/\(artifact.token).jpg")
        }
        state.installQueueForTesting(ExportQueue(
            metal: nil,
            registry: ModuleRegistry.makeDefault(),
            renderLeg: renderLeg,
            encodeLeg: encodeLeg))
        return state
    }

    /// Poll until every snapshot reached a terminal state (the injected
    /// legs settle in ms; the bound guards a wedged pump).
    private func waitUntilSettled(
        _ state: ExportState, expected: Int, timeout: TimeInterval = 5
    ) async -> [ExportJobSnapshot] {
        let deadline = Date().addingTimeInterval(timeout)
        var rows: [ExportJobSnapshot] = []
        while Date() < deadline {
            rows = await state.queue?.snapshots() ?? []
            if rows.count == expected, rows.allSatisfy({ $0.state.isTerminal }) {
                return rows
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return rows
    }

    // MARK: - The target derivation (KD-4)

    func testM2TargetURLsSelectionBeatsLoadedImageAndFallsBack() {
        let selection = [URL(fileURLWithPath: "/p/a.ARW"), URL(fileURLWithPath: "/p/b.ARW")]
        let loaded = URL(fileURLWithPath: "/p/c.ARW")
        XCTAssertEqual(
            ExportState.m2TargetURLs(selection: selection, loadedImageURL: loaded),
            selection, "the grid selection wins")
        XCTAssertEqual(
            ExportState.m2TargetURLs(selection: [], loadedImageURL: loaded),
            [loaded], "no selection → the current editor image")
        XCTAssertEqual(
            ExportState.m2TargetURLs(selection: [], loadedImageURL: nil),
            [], "neither → empty (the run gate stays disabled)")
    }

    func testM2SelectionProviderFace() {
        let state = ExportState()
        let provided = [URL(fileURLWithPath: "/grid/1.ARW")]
        state.m2SelectionProvider = { provided }
        XCTAssertEqual(
            state.m2Targets(currentImageURL: URL(fileURLWithPath: "/p/x.ARW")),
            provided, "the armed provider (the shell's grid selection) wins")
        state.m2SelectionProvider = nil
        XCTAssertEqual(
            state.m2Targets(currentImageURL: URL(fileURLWithPath: "/p/x.ARW")),
            [URL(fileURLWithPath: "/p/x.ARW")],
            "unarmed → the loaded-image fallback")
    }

    // MARK: - The assembly (KD-4 / AC5)

    func testEnqueueExportM2CapturesTheRealChainFace() async throws {
        let capture = Capture()
        let state = makeState(capture)
        let loaded = URL(fileURLWithPath: "/library/IMG_0001.ARW")
        let second = URL(fileURLWithPath: "/library/IMG_0002.ARW")
        let instances = [ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())]
        var record = DrtRecord()
        record.peakLuminance = 320
        var variant = ExportVariant(
            format: .jpeg(quality: 0.85),
            metadataPolicy: .standard,
            embedICC: false)
        variant.sizing = YiyinExportSettings(mode: .longEdge(px: 2048), dpi: 300)

        try await state.enqueueExportM2(
            images: [loaded, second],
            instancesOverrides: [instances, nil],
            drtRecord: record,
            variant: variant,
            destination: outputDirectory,
            subfolder: "Processed",
            namingPattern: "{source}-{sequence:0000}",
            collisionPolicy: .fail,
            exifSoftware: "Lightamer 9.9.9")

        let rows = await waitUntilSettled(state, expected: 2)
        XCTAssertEqual(rows.count, 2)
        let renders = capture.all.filter { $0.variant == nil }
        let encodes = capture.all.filter { $0.variant != nil }
        XCTAssertEqual(renders.count, 2)
        XCTAssertEqual(encodes.count, 2)

        // The projection override rides the OPEN image only (KD-4: the
        // live face; the other image keeps its disk sidecar truth).
        let byPath = Dictionary(uniqueKeysWithValues: renders.map { ($0.relPath, $0) })
        XCTAssertEqual(byPath["IMG_0001.ARW"]?.instancesOverride?.count, 1)
        XCTAssertNil(byPath["IMG_0002.ARW"]?.instancesOverride)

        // The DRT carrier: the record + the catalog demotion set (the
        // PixelPipe-side enabled intersection consumes it — 同法).
        for render in renders {
            XCTAssertEqual(render.drtRecord, record)
            XCTAssertEqual(render.postOpNames, NodeOwnershipCatalog.drtPostOpNames)
            XCTAssertEqual(render.pattern, "{source}-{sequence:0000}")
            XCTAssertEqual(render.fallbackStem, ExportFileNameTemplate.fallbackStem)
            XCTAssertEqual(render.collisionPolicy, .fail)
            XCTAssertEqual(render.subfolder, "Processed")
        }
        // The queue-stamped batch ordinal (sequence = 选中序 1 起).
        XCTAssertEqual(
            Set(renders.compactMap(\.sequence)), [1, 2],
            "the two images stamp 1 then 2 (the batch order)")
        // FIFO: the first image's job carries sequence 1.
        XCTAssertEqual(renders.first?.sequence, 1)

        // The exifSoftware carrier lands in the ENCODE leg (the
        // $jobExifSoftware scope) on every job.
        for encode in encodes {
            XCTAssertEqual(encode.exifSoftware, "Lightamer 9.9.9")
        }

        // The variant face: drtOutput = the record (OQ-7 强制联动), the
        // policy/ICC/format carried, the relPath = the display name.
        for encode in encodes {
            XCTAssertEqual(encode.variant?.drtOutput, record)
            XCTAssertEqual(encode.variant?.metadataPolicy.mode, .standard)
            XCTAssertFalse(encode.variant?.embedICC ?? true)
            XCTAssertEqual(encode.variant?.format, .jpeg(quality: 0.85))
        }
        XCTAssertEqual(
            Set(rows.map(\.relPath)), ["IMG_0001.ARW", "IMG_0002.ARW"],
            "the snapshot display face carries the file names (no relPath projection)")
    }

    func testEnqueueExportM2RejectsPayloadCountMismatchTyped() async {
        let state = ExportState()
        do {
            try await state.enqueueExportM2(
                images: [URL(fileURLWithPath: "/a.ARW"), URL(fileURLWithPath: "/b.ARW")],
                instancesOverrides: [nil],
                drtRecord: DrtRecord(),
                variant: ExportVariant(format: .jpeg(quality: 0.9)),
                destination: outputDirectory,
                subfolder: nil,
                namingPattern: "{source}")
            XCTFail("the count mismatch must throw typed")
        } catch {
            guard case AppError.invalidParameter(let message) = error else {
                return XCTFail("typed invalidParameter expected, got \(error)")
            }
            XCTAssertTrue(
                message.contains("count"),
                "the message names the mismatch face: \(message)")
        }
    }

    func testEnqueueExportM2RequiresQueueAndDegradesEmptyBatch() async {
        let state = ExportState()
        do {
            try await state.enqueueExportM2(
                images: [URL(fileURLWithPath: "/a.ARW")],
                instancesOverrides: [nil],
                drtRecord: DrtRecord(),
                variant: ExportVariant(format: .jpeg(quality: 0.9)),
                destination: outputDirectory,
                subfolder: nil,
                namingPattern: "{source}")
            XCTFail("no queue → typed throw")
        } catch {
            guard case AppError.invalidParameter = error else {
                return XCTFail("typed invalidParameter expected, got \(error)")
            }
        }
        // The empty batch is a silent no-op (nothing enqueued, no throw).
        let seeded = makeState(Capture())
        try? await seeded.enqueueExportM2(
            images: [],
            instancesOverrides: [],
            drtRecord: DrtRecord(),
            variant: ExportVariant(format: .jpeg(quality: 0.9)),
            destination: outputDirectory,
            subfolder: nil,
            namingPattern: "{source}")
        let rows = await seeded.queue?.snapshots() ?? []
        XCTAssertTrue(rows.isEmpty, "an empty batch never enqueues")
    }

    func testPeakGateFiresTypedOnTheAssembledVariant() {
        // The assembly hands the record to the variant verbatim — a bad
        // peak is the M2-9-03 validate gate's typed refusal (the 兜底;
        // the assembly never pre-validates).
        var record = DrtRecord()
        record.peakLuminance = -1
        let variant = ExportVariant(
            format: .jpeg(quality: 0.9), drtOutput: record)
        XCTAssertThrowsError(try variant.validate()) { error in
            guard case AppError.invalidParameter(let message) = error else {
                return XCTFail("typed refusal expected")
            }
            XCTAssertTrue(message.contains("peak"), "the gate names the peak: \(message)")
        }
        // A nil drtOutput (the legacy face) never triggers the gate.
        let legacy = ExportVariant(format: .jpeg(quality: 0.9))
        XCTAssertNoThrow(try legacy.validate())
    }

    // MARK: - The carrier faces

    func testExifSoftwareStringComposition() {
        XCTAssertEqual(
            ExportState.exifSoftwareString(version: "1.2.3"), "Lightamer 1.2.3")
        XCTAssertTrue(
            ExportState.currentExifSoftware.hasPrefix("Lightamer "),
            "the app face resolves the bundle version (or ? in the test host)")
    }

    func testM2DrtTailCarriesTheCatalogPostOps() {
        let tail = ExportState.m2DrtTail(record: DrtRecord())
        XCTAssertEqual(tail.postOpNames, NodeOwnershipCatalog.drtPostOpNames)
        XCTAssertFalse(tail.postOpNames.isEmpty, "the demotion set is non-empty")
    }

    // MARK: - The queue face state layer (KD-2 节 5)

    func testFourStateProjectionMapsTheEngineStates() {
        XCTAssertEqual(ExportQueueFaceState.map(.pending), .queued)
        XCTAssertEqual(ExportQueueFaceState.map(.rendering), .exporting)
        XCTAssertEqual(ExportQueueFaceState.map(.encoding), .exporting)
        XCTAssertEqual(ExportQueueFaceState.map(.done(URL(fileURLWithPath: "/x"))), .done)
        XCTAssertEqual(ExportQueueFaceState.map(.failed(.cancelled)), .failed)
        XCTAssertEqual(ExportQueueFaceState.map(.cancelled), .failed,
            "the cancellation folds into the FAILED tier (the plan ruling)")
    }

    func testQueuePreviewCapIsThirtySixRowsWithSummary() {
        XCTAssertEqual(ExportQueueFaceView.previewCap, 36)
        let rows = (0..<40).map { index in
            ExportJobSnapshot(
                id: UUID(), imageURL: URL(fileURLWithPath: "/p/\(index).ARW"),
                relPath: "\(index).ARW", variants: [], seq: index,
                generation: 0, state: .pending)
        }
        let slice = ExportQueueFaceView.previewSlice(rows)
        XCTAssertEqual(slice.preview.count, 36)
        XCTAssertEqual(slice.more, 4)
        XCTAssertEqual(slice.preview.first?.relPath, "0.ARW", "FIFO prefix")
        // Under the cap: the whole list, no summary.
        let small = ExportQueueFaceView.previewSlice(Array(rows.prefix(36)))
        XCTAssertEqual(small.preview.count, 36)
        XCTAssertEqual(small.more, 0)
    }

    func testRebuildQueueForProjectDegradesQuietlyWithoutMetal() async {
        let state = ExportState()
        state.configure(metal: nil, registry: ModuleRegistry.makeDefault())
        await state.rebuildQueueForProject()
        let rows = await state.queue?.snapshots() ?? []
        XCTAssertTrue(rows.isEmpty, "no Metal → no queue, the degrade is quiet")
    }
}
