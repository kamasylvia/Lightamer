import CoreGraphics
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// LibraryAnalysisService (Plan LUMEN-A T5, X1 seam 5 / D-LU-5 / H-LU1) — the
// background culling-analysis pass over an opened `.lalb` package.
//
// Loop (the Lumen library_tasks.py `_run_analysis`/`paused()` semantics,
// transliterated): scan rows with `analysis_version IS NULL OR < CURRENT`
// (LibraryQueries.pendingAnalysisRows, id order) → per row: resolve the
// link (ImageLinker), read the EMBEDDED PREVIEW at ≤1600px (D-LU-10 — the
// sharpness calibration is bound to this edge), grayscale →
// SharpnessAnalyzer + Signature16 → faces>0 → EyeClosureAnalyzer →
// LibraryStore.setAnalysis. Three defenses (H-LU1): QoS .utility, a
// concurrency CAP of 2 (the CPU work runs OFF this actor — the group tasks
// call the nonisolated analyze leg and hop back only to persist), and the
// PAUSE semantics (the injected activity probe — export/AI busy — suspends
// the walk; idle resumes; Lumen paused()/kick()).
//
// Anti-retry-storm (Lumen :162): a file that cannot be opened/resolved
// writes the EMPTY analysis (analysis_version = CURRENT, products nil) —
// exactly once, never re-tried until the version moves.
//
// Lazy backfill (X2): while the EXIF is read for a row whose
// camera_serial is NULL, a found serial (and a subsecond capture fold when
// the stored capture_date is whole-second) rides the SAME write.
//
// Progress/cancel: the run publishes LibraryAnalysisProgress events through
// `progressEvents()` (an AsyncStream — the App-side
// BackgroundTaskRegistry adapter consumes it; Core cannot import the App
// registry, review M-2). Cancellation = task cancellation through
// `cancel()`.
//
// RED LINE (default-neutral, CONTEXT 红线 10): the pass only ever writes
// the seven analysis columns + the additive notify seam
// (`LibraryStore.analysisEvents`, review m-2 — no existing row-change
// channel exists); rows with NULL analysis_version render byte-identical
// to the pre-plan face. The grid scroll path is never touched.
// ─────────────────────────────────────────────────────────────────────────────

/// One pending row as the scan projects it (the link-carrier triple + the
/// lazy-backfill witness).
public struct PendingAnalysisRow: Sendable, Equatable {
    public let id: Int64
    public let imagePath: String
    public let pathKind: LibrarySchema.PathKind
    public let volumeUUID: String?
    public let cameraSerial: String?

    public init(
        id: Int64, imagePath: String, pathKind: LibrarySchema.PathKind,
        volumeUUID: String?, cameraSerial: String?
    ) {
        self.id = id
        self.imagePath = imagePath
        self.pathKind = pathKind
        self.volumeUUID = volumeUUID
        self.cameraSerial = cameraSerial
    }
}

/// The per-image analysis product (the LibraryStore.setAnalysis carrier).
public struct LibraryAnalysisRecord: Sendable, Equatable {
    public let imageID: Int64
    public let analysisVersion: Int
    public let sharpness: Double?
    public let faces: Int?
    public let eyesClosed: Int?
    /// Signature16: 256 bytes.
    public let signature: Data?
    /// JSON face boxes: [[x, y, w, h, closed, ratioRight, ratioLeft]]
    /// normalized 0-1 top-left (the Lumen 5-tuple extended with the two
    /// ratios T6's threshold-free best sort consumes).
    public let faceBoxes: String?
    /// The X2 lazy-backfill leg (nil = leave the stored serial).
    public let cameraSerial: String?
    /// The X2 subsecond capture fold (nil = leave the stored date).
    public let captureDate: Double?

    public init(
        imageID: Int64, analysisVersion: Int, sharpness: Double?,
        faces: Int?, eyesClosed: Int?, signature: Data?, faceBoxes: String?,
        cameraSerial: String?, captureDate: Double?
    ) {
        self.imageID = imageID
        self.analysisVersion = analysisVersion
        self.sharpness = sharpness
        self.faces = faces
        self.eyesClosed = eyesClosed
        self.signature = signature
        self.faceBoxes = faceBoxes
        self.cameraSerial = cameraSerial
        self.captureDate = captureDate
    }
}

/// The progress event (the App registry adapter's snapshot source).
public struct LibraryAnalysisProgress: Sendable, Equatable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

public actor LibraryAnalysisService {

    /// The analysis-stamp version this binary computes (rows below recompute).
    public static let analysisVersion = 1

    /// THE UserDefaults key — the single source (T7's Settings row consumes
    /// the same constant; KD-4: typed read + injectable defaults).
    public static let enabledKey = "library.analysis.enabled"

    /// The concurrency cap (H-LU1 defense #2; Lumen's three low-priority
    /// threads map to a TaskGroup of this width).
    public static let concurrencyCap = 2

    /// The analysis base edge (D-LU-10 — the sharpness calibration is bound
    /// to this; the LU3 display edge 2560 is a DIFFERENT档 and never here).
    static let previewMaxPixel = 1600

    /// The pause poll interval while an export/AI activity is live.
    static let pausePollNanoseconds: UInt64 = 2_000_000_000

    private let store: ProjectFileStore
    private let queries: LibraryQueries
    private let faceProvider: FaceLandmarkProviding
    private let defaultsSuiteName: String?
    /// The notify-seam store: ONE LibraryStore actor instance owned by the
    /// service (injected at assembly or created from `store` here). The
    /// badge refresh chain (LUMEN-A acceptance §八) rides THIS instance's
    /// `analysisContinuations` table — the per-row `LibraryStore(store:)`
    /// instantiation yielded every event into a fresh instance's EMPTY
    /// table and the subscriber (the WorkspaceHostView badge loop) never
    /// saw it. Consumers must subscribe THIS instance (the wiring's
    /// `analysisEvents()` seam).
    public private(set) var libraryStore: LibraryStore
    /// The package directory (the kind-0 resolve base) — captured at init
    /// (the store's fileURL is actor-isolated; the CPU leg reads this copy).
    private let projectDirectory: URL

    private var runTask: Task<Void, Never>?
    /// The injected export/AI activity probe (true = busy → pause).
    private var activityProbe: (@Sendable () async -> Bool)?

    public init(
        store: ProjectFileStore, queries: LibraryQueries,
        faceProvider: FaceLandmarkProviding, defaultsSuiteName: String? = nil,
        libraryStore: LibraryStore? = nil
    ) async {
        self.store = store
        self.queries = queries
        self.faceProvider = faceProvider
        self.defaultsSuiteName = defaultsSuiteName
        // The injection seam: the assembly point (the wiring) passes THE
        // instance the consumers subscribe; nil = create one here (the
        // headless/test face) — either way ONE instance for every row.
        self.libraryStore = libraryStore ?? LibraryStore(store: store)
        self.projectDirectory = await store.fileURL.deletingLastPathComponent()
    }

    // MARK: - The enabled gate (D-LU-5: 默认开 + Settings 开关)

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The typed enabled read: unset = TRUE (默认开); any stored Bool wins.
    public static func isEnabled(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    func isEnabled() -> Bool {
        Self.isEnabled(defaults: defaults)
    }

    // MARK: - Injection + lifecycle

    /// The export/AI activity probe (the App wiring injects the composed
    /// closure; nil = never paused — the headless/test face).
    public func setActivityProbe(_ probe: (@Sendable () async -> Bool)?) {
        activityProbe = probe
    }

    /// Spawn the analysis walk (idempotent — a live run is never doubled).
    /// The enabled gate is checked HERE and per-loop (the Settings toggle
    /// takes effect without a restart).
    public func start() {
        guard runTask == nil else { return }
        runTask = Task(priority: .utility) { [weak self] in
            await self?.run()
        }
    }

    /// Cancel the live walk (the App registry's cancel route). The next
    /// `start()` re-scans; done rows never recompute.
    public func cancel() {
        runTask?.cancel()
        runTask = nil
    }

    public var isRunning: Bool { runTask != nil }

    // MARK: - Progress events (the App registry adapter's source)

    private var progressContinuations:
        [UUID: AsyncStream<LibraryAnalysisProgress>.Continuation] = [:]

    /// Multi-consumer progress stream (the wiring's adapter consumes one).
    public func progressEvents() -> AsyncStream<LibraryAnalysisProgress> {
        AsyncStream { continuation in
            let id = UUID()
            progressContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeProgressContinuation(id) }
            }
        }
    }

    private func removeProgressContinuation(_ id: UUID) {
        progressContinuations[id] = nil
    }

    private func emitProgress(_ progress: LibraryAnalysisProgress) {
        for continuation in progressContinuations.values {
            continuation.yield(progress)
        }
    }

    // MARK: - The walk

    private func run() async {
        guard isEnabled() else { return }
        while !Task.isCancelled {
            // H-LU1 defense #3: pause while export/AI owns the machine
            // (Lumen paused()); idle resumes the walk.
            if let probe = activityProbe, await probe() {
                try? await Task.sleep(nanoseconds: Self.pausePollNanoseconds)
                continue
            }
            guard isEnabled() else { return }
            let batch: [PendingAnalysisRow]
            do {
                batch = try await queries.pendingAnalysisRows(
                    version: Self.analysisVersion)
            } catch {
                return  // the package closed under us — the wiring restarts
            }
            if batch.isEmpty { return }
            let total = (try? await queries.pendingAnalysisCount(
                version: Self.analysisVersion)) ?? batch.count
            doneCount = max(total - batch.count, 0)
            emitProgress(LibraryAnalysisProgress(done: doneCount, total: total))
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for row in batch {
                    while inFlight >= Self.concurrencyCap {
                        await group.next()
                        inFlight -= 1
                    }
                    inFlight += 1
                    group.addTask {
                        // The CPU leg runs OFF the actor; only the persist
                        // hop is serialized (H-LU1 defense #2, cap 2).
                        let product = await Self.analyzeRow(
                            row: row, projectDirectory: self.projectDirectory,
                            faceProvider: self.faceProvider)
                        await self.persistAndTick(product, total: total)
                    }
                }
            }
        }
    }

    /// The batch-local completed counter (the actor lane owns it — the
    /// group tasks never mutate captured state).
    private var doneCount = 0

    /// The persist hop (the actor lane): the store write + the additive
    /// notify seam ride LibraryStore; progress emits here.
    private func persistAndTick(
        _ product: LibraryAnalysisRecord, total: Int
    ) async {
        try? await libraryStore.setAnalysis(product)
        doneCount += 1
        emitProgress(LibraryAnalysisProgress(done: doneCount, total: total))
    }

    // MARK: - The per-row CPU leg (nonisolated — never on the actor)

    /// Analyze one row: resolve → preview → sharpness/signature → faces →
    /// the lazy EXIF backfill. Unreadable/unresolvable → the EMPTY record
    /// (anti-retry-storm, Lumen :162). Runs on the calling task's executor
    /// (the group lane), QoS .utility inherited.
    nonisolated static func analyzeRow(
        row: PendingAnalysisRow, projectDirectory: URL,
        faceProvider: FaceLandmarkProviding
    ) async -> LibraryAnalysisRecord {
        let url: URL?
        switch ImageLinker.resolve(
            imagePath: row.imagePath, pathKind: row.pathKind,
            volumeUUID: row.volumeUUID, projectDirectory: projectDirectory) {
        case .resolved(let resolved): url = resolved
        case .stale: url = nil
        }
        guard let url else {
            return LibraryAnalysisRecord(
                imageID: row.id, analysisVersion: analysisVersion,
                sharpness: nil, faces: nil, eyesClosed: nil,
                signature: nil, faceBoxes: nil,
                cameraSerial: nil, captureDate: nil)
        }

        // The lazy EXIF backfill leg (X2): only when the serial is missing.
        var backfillSerial: String?
        var backfillCapture: Double?
        if row.cameraSerial == nil,
           let read = ExifSearchIndexer.readProperties(from: url) {
            backfillSerial = read.cameraSerial
            backfillCapture = read.captureDate?.timeIntervalSince1970
        }

        guard let thumbnail = Self.embeddedPreview(url: url),
              let gray = Self.grayscalePlane(thumbnail) else {
            return LibraryAnalysisRecord(
                imageID: row.id, analysisVersion: analysisVersion,
                sharpness: nil, faces: nil, eyesClosed: nil,
                signature: nil, faceBoxes: nil,
                cameraSerial: backfillSerial, captureDate: backfillCapture)
        }

        let sharpness = SharpnessAnalyzer.analyze(
            gray: gray.plane, width: gray.width, height: gray.height)
        let signature = Signature16.bytes(
            gray: gray.plane, width: gray.width, height: gray.height)

        // Faces: only when the sharpness leg found any (a nil sharpness on
        // a readable image is a <64px view — faces are moot there too).
        var faceBoxesJSON: String?
        var faceCount: Int?
        var closedCount: Int?
        if sharpness != nil {
            let eyes = EyeClosureAnalyzer.analyze(
                image: thumbnail, provider: faceProvider)
            faceCount = eyes.faces.count
            closedCount = eyes.closedCount
            faceBoxesJSON = Self.encodeFaceBoxes(eyes.faces)
        }

        return LibraryAnalysisRecord(
            imageID: row.id, analysisVersion: analysisVersion,
            sharpness: sharpness, faces: faceCount, eyesClosed: closedCount,
            signature: Data(signature), faceBoxes: faceBoxesJSON,
            cameraSerial: backfillSerial, captureDate: backfillCapture)
    }

    /// The ImageIO embedded preview at the analysis edge (the
    /// SessionThumbnailProvider.embeddedPreview option shape, 1600档 —
    /// Core-side, the Session 720 constant zero-touch).
    nonisolated static func embeddedPreview(url: URL) -> CGImage? {
        let options = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: previewMaxPixel,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options)
        else { return nil }
        return image
    }

    /// Float 0-1 row-major grayscale plane (the analyzers' input).
    nonisolated static func grayscalePlane(
        _ image: CGImage
    ) -> (plane: [Float], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
                    ?? CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height)
        var plane = [Float](repeating: 0, count: width * height)
        for index in 0..<plane.count {
            plane[index] = Float(bytes[index]) / 255
        }
        return (plane, width, height)
    }

    /// The face_boxes JSON: [[x, y, w, h, closed, ratioRight, ratioLeft]].
    nonisolated static func encodeFaceBoxes(
        _ faces: [EyeClosureResult.Face]
    ) -> String? {
        guard !faces.isEmpty else { return nil }
        var arrays: [[Double?]] = []
        for face in faces {
            arrays.append([
                Double(face.box.origin.x), Double(face.box.origin.y),
                Double(face.box.width), Double(face.box.height),
                face.closed ? 1 : 0, face.ratioRight, face.ratioLeft,
            ])
        }
        guard let data = try? JSONEncoder().encode(arrays) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
