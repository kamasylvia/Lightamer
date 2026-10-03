import CoreGraphics
import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// EnhanceDialogModel (Plan M2-10-06 T3c, KD-5) — the enhancement dialog's
// orchestration: the preview leg (single central-region tile), the full
// copy run (engine → writer → import twin), the progress face, the
// close-after cancel semantics (Lumen ai_dialog.py:177-185 paradigm —
// a busy close sets the cancel flag and waits for the current tile; never
// a hard kill), and the release-tier model download row (the M2-10-01
// store's status machine).
//
// SEAMS (everything a test needs to inject — the M2-10-07 wiring point
// passes the production closures):
//   • frameProvider  — the editor render / library decode face (fp32 RGBA).
//   • modelFacts     — the worker openEnhancement wrapper.
//   • tileExecutor   — the worker enhanceTile wrapper (the path channel).
//   • store          — the ModelAssetStore (status + download).
// The project import face (projectDirectory / albumID / ImportService /
// source image identity) rides the EnhanceContext.
// ─────────────────────────────────────────────────────────────────────────────

/// The dialog's project-side context (the M2-10-07 wiring passes it).
struct EnhanceContext: Sendable {
    /// The ORIGINAL file (the EXIF inheritance + the copy stem).
    var originalURL: URL
    /// The original image's UUID string (the provenance link).
    var sourceImageID: String
    var projectDirectory: URL
    var albumID: Int64?
    /// The import twin (the same service the project grid uses).
    var importService: LightamerCore.ImportService
}

/// The enhancement operation face (KD-5: upscale with a model tier, or
/// denoise with a strength).
enum EnhanceOperationChoice: Equatable, Sendable {
    case upscale(profileID: String)
    case denoise(profileID: String, strength: Double)

    var profileID: String {
        switch self {
        case .upscale(let profileID): return profileID
        case .denoise(let profileID, _): return profileID
        }
    }

    var provenanceOperation: AIProvenanceOperation {
        switch self {
        case .upscale: return .upscale
        case .denoise: return .denoise
        }
    }

    var amount: Double? {
        switch self {
        case .upscale: return nil
        case .denoise(_, let strength): return strength
        }
    }
}

/// The dialog's observable phase face.
enum EnhancePhase: Equatable, Sendable {
    case idle
    case previewRunning
    case previewReady
    case running(Int) // the tile-progress percent (15...93)
    case done(String) // the copy's file name
    case failed(String)
    case cancelled
}

@MainActor
@Observable
final class EnhanceDialogModel {

    // MARK: - Observable state

    private(set) var phase: EnhancePhase = .idle
    var choice: EnhanceOperationChoice
    private(set) var beforePreview: EnhanceFrame?
    private(set) var afterPreview: EnhanceFrame?
    private(set) var modelStatuses: [String: ModelAssetStatus] = [:]
    /// The close-after arm: set while busy, honored when the run settles.
    private(set) var shouldClose = false

    // MARK: - Seams + context

    private let context: EnhanceContext
    private let frameProvider: @Sendable () async throws -> EnhanceFrame
    private let modelFacts: @Sendable (String) async throws -> (
        tileEdges: [Int], scale: Int
    )
    private let tileExecutor: @Sendable (EnhanceTileRequest) async throws -> Void
    private let store: ModelAssetStore
    private let colorSpace: CGColorSpace

    /// The cancel flag (the engine's checkpoint input — checked before
    /// every tile). A lock-guarded Sendable box: the engine's checkpoint
    /// closure reads it off the main actor.
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var isSetStorage = false
        func set() {
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

    private let cancelFlag = CancelFlag()
    private var runInProgress = false

    init(
        choice: EnhanceOperationChoice,
        context: EnhanceContext,
        frameProvider: @escaping @Sendable () async throws -> EnhanceFrame,
        modelFacts: @escaping @Sendable (String) async throws -> (
            tileEdges: [Int], scale: Int
        ),
        tileExecutor: @escaping @Sendable (EnhanceTileRequest) async throws -> Void,
        store: ModelAssetStore = ModelAssetStore(),
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    ) {
        self.choice = choice
        self.context = context
        self.frameProvider = frameProvider
        self.modelFacts = modelFacts
        self.tileExecutor = tileExecutor
        self.store = store
        self.colorSpace = colorSpace
    }

    // MARK: - Derived

    var isBusy: Bool {
        switch phase {
        case .running, .previewRunning: return true
        default: return runInProgress
        }
    }

    /// The four-hundred-megapixel budget message (the planner's typed
    /// rejection mapped to the honest copy text).
    static func budgetMessage(outputPixels: Int, limit: Int) -> String {
        "输出超过 4 亿像素上限（\(outputPixels) > \(limit)），请降低倍率或裁切后重试。"
    }

    // MARK: - Model availability (the release-tier download row)

    func refreshModelStatus() async {
        modelStatuses[choice.profileID] = await store.status(for: choice.profileID)
    }

    func downloadSelectedModel() async {
        do {
            try await store.download(choice.profileID)
        } catch {
            phase = .failed("\(error)")
            return
        }
        await refreshModelStatus()
    }

    /// The operation's model is usable (bundled or installed).
    var selectedModelReady: Bool {
        switch modelStatuses[choice.profileID] {
        case .bundled, .installed: return true
        default: return false
        }
    }

    // MARK: - Preview (KD-5: central 192×192 original pixels, one tile)

    /// Run the preview: crop the CENTRAL 192×192 region from the frame,
    /// enhance it through the SAME engine path (one tile — determinism
    /// per Lumen MODEL.md:9), and hold before/after for the dialog.
    func runPreview() async {
        guard !isBusy else { return }
        phase = .previewRunning
        defer { runInProgress = false }
        runInProgress = true
        do {
            let full = try await frameProvider()
            let facts = try await modelFacts(choice.profileID)
            let edge = 192
            let crop = Self.centralCrop(full, edge: edge)
            let engine = EnhanceEngine(
                supportedEdges: facts.tileEdges, scale: facts.scale,
                amount: choice.amount)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("lightamer-enhance-preview-\(UUID().uuidString)",
                    isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let output = try await engine.run(
                input: crop, tmpDirectory: tmp,
                tileExecutor: tileExecutor,
                onProgress: nil,
                cancellation: { [cancelFlag] in cancelFlag.isSet })
            beforePreview = crop
            afterPreview = output
            phase = .previewReady
        } catch let error as EnhanceEngineError {
            phase = Self.phase(for: error)
        } catch {
            phase = .failed("\(error)")
        }
    }

    // MARK: - The full copy run (KD-2/KD-3/KD-4)

    /// Enhance the full frame → write the copy → import it as a NEW images
    /// row (D-3: the original untouched, version_ref untouched).
    func runFullCopy() async {
        guard !isBusy else { return }
        phase = .running(0)
        runInProgress = true
        do {
            let frame = try await frameProvider()
            let facts = try await modelFacts(choice.profileID)
            let engine = EnhanceEngine(
                supportedEdges: facts.tileEdges, scale: facts.scale,
                amount: choice.amount)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("lightamer-enhance-\(UUID().uuidString)",
                    isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let output = try await engine.run(
                input: frame, tmpDirectory: tmp,
                tileExecutor: tileExecutor,
                onInputConsumed: nil,
                onProgress: { [weak self] percent in
                    Task { @MainActor in
                        self?.phase = .running(percent)
                    }
                },
                cancellation: { [cancelFlag] in cancelFlag.isSet })

            // The copy write (KD-3) + the import twin (KD-4).
            let copyURL = try await Self.writeCopy(
                output: output, choice: choice, context: context,
                colorSpace: colorSpace)
            phase = .running(93)
            let provenance = SidecarAIProvenanceRecord(
                operation: choice.provenanceOperation,
                scale: facts.scale,
                amount: choice.amount ?? 0,
                sourceFile: context.originalURL.lastPathComponent,
                sourceImageID: context.sourceImageID,
                backend: "coreml-worker")
            _ = try await context.importService.importFile(
                at: copyURL,
                projectDirectory: context.projectDirectory,
                albumID: context.albumID,
                aiProvenance: provenance)
            phase = .done(copyURL.lastPathComponent)
        } catch let error as EnhanceEngineError {
            phase = Self.phase(for: error)
        } catch {
            phase = .failed("\(error)")
        }
        // The close-after arm: the run settled, honor the busy close.
        if cancelFlag.isSet {
            shouldClose = true
        }
    }

    // MARK: - Cancel / close-after (the Lumen :177-185 semantics)

    /// The close button while busy: set the cancel flag; the engine stops
    /// at the next tile checkpoint, the CURRENT tile finishes (never a
    /// hard kill), the run settles, and the dialog closes.
    func closeRequested() {
        if isBusy {
            cancelFlag.set()
        } else {
            shouldClose = true
        }
    }

    // MARK: - Helpers

    private static func phase(for error: EnhanceEngineError) -> EnhancePhase {
        switch error {
        case .cancelled:
            return .cancelled
        case .pixelBudgetExceeded(let pixels, let limit):
            return .failed(budgetMessage(outputPixels: pixels, limit: limit))
        case .tileFailed(_, let detail):
            return .failed(detail)
        case .modelFactsInvalid(let detail):
            return .failed(detail)
        }
    }

    /// The central `edge`×`edge` crop (clamped at the image edges — the
    /// Lumen `region` arithmetic, :117-118).
    static func centralCrop(_ frame: EnhanceFrame, edge: Int) -> EnhanceFrame {
        let width = min(edge, frame.width)
        let height = min(edge, frame.height)
        let originX = max(0, frame.width / 2 - width / 2)
        let originY = max(0, frame.height / 2 - height / 2)
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let source = ((originY + y) * frame.width + originX) * 4
            let target = y * width * 4
            for offset in 0..<(width * 4) {
                rgba[target + offset] = frame.rgba[source + offset]
            }
        }
        return EnhanceFrame(rgba: rgba, width: width, height: height)
    }

    /// The copy write (KD-3): container rule → reserve → encode. Returns
    /// the copy's URL. Static + injected everything (testable).
    static func writeCopy(
        output: EnhanceFrame, choice: EnhanceOperationChoice,
        context: EnhanceContext, colorSpace: CGColorSpace
    ) async throws -> URL {
        let mediaDirectory = context.projectDirectory
            .appendingPathComponent(LibrarySchema.mediaDirectoryName,
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: mediaDirectory, withIntermediateDirectories: true)
        let container = EnhanceCopyWriter.outputContainer(
            forOriginal: context.originalURL)
        let stem = context.originalURL.deletingPathExtension().lastPathComponent
        let destination = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: stem,
            operation: choice.provenanceOperation, container: container)
        try EnhanceCopyWriter.writeCopy(
            rgba: output.rgba, width: output.width, height: output.height,
            colorSpace: colorSpace, to: destination,
            originalURL: context.originalURL)
        return destination
    }
}
