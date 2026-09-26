import Darwin
import Foundation
import LightamerCore
import LightamerIOP
import Observation
import os

/// Export-subsystem state (D-03b isolation contract — UNCHANGED).
///
/// Owns ONLY: the export queue actor (session-scoped, rebuilt per open),
/// the recipe editing face (in-memory, D-11-CONTEXT-3 — v1 never persists),
/// and the queue observation rows the export panel renders. Does NOT own
/// image data and holds no references to the other state objects — the
/// Metal/registry dependencies arrive through `configure` from the app root
/// (the sessionCoordinator.configure closure-seam pattern), and the panel
/// triggers the pre-export sidecar flush through ITS OWN environment.
///
/// OQ-11-4: failures surface per-job (the row's `.failed(AppError)` is
/// rendered inline with a retry button) + the summary counters
/// (`progress.done/total`); no batch-level toast.
@Observable
@MainActor
final class ExportState {

    private static let logger = AppError.logger

    // MARK: - Queue plumbing (configured by the app root, D-03b-safe)

    private var metal: MetalContext?
    private var registry: ModuleRegistry?
    /// Stateless logo-face source for the yiyin injection (owned HERE — a
    /// file-probe helper, not a state object).
    private let yiyinLogoStore = YiyinLogoStore()

    /// The session-scoped queue (nil = no session open yet — the panel's
    /// actions no-op with a toast).
    private(set) var queue: ExportQueue?

    // MARK: - Recipe editing face (D-11-CONTEXT-3: memory only)

    /// The inline-edited recipe. Session-lifetime: rebuilt defaults on a
    /// session switch, never written to disk in v1 (Phase 12 presets take
    /// over persistence).
    var recipe: [ExportVariant] = [ExportState.defaultVariant]

    /// The destination override (nil = the session's Output/ default,
    /// EXP-08). Set by the panel's directory picker; also memory-only.
    var customDestination: URL?

    /// The default recipe variant (16-bit TIFF is a heavy default — v1
    /// starts at JPEG 0.9 sRGB, the interop choice; panel edits from here).
    static var defaultVariant: ExportVariant {
        ExportVariant(
            sizing: YiyinExportSettings(mode: .original, dpi: 300),
            format: .jpeg(quality: 0.9),
            colorSpace: .sRGB,
            yiyin: false)
    }

    // MARK: - Targets derivation (the header count / run gate / enqueue face)

    /// The export targets' rel paths (EXP-07 N×M): the browser selection
    /// when one exists, otherwise the currently edited image.
    ///
    /// F-11-04-1: the loaded odoc URL may arrive in the SYMLINK-RESOLVED
    /// spelling (the scanner enumerates with a realpath'd root: `/tmp` →
    /// `/private/tmp`) while the session root keeps the link spelling (or
    /// the reverse, if the session was opened through an already-resolved
    /// path), and Foundation's `resolvingSymlinksInPath` does NOT resolve
    /// the prefix link (L027/SessionWatcher precedent) — realpath(3) once
    /// on BOTH sides and match any spelling pair; no match → empty (the
    /// run gate then disables, the enqueue action never fires with a
    /// silently empty batch).
    static func targetRelPaths(
        selection: [String], loadedImageURL: URL?, sessionRoot: URL?
    ) -> [String] {
        let selection = selection.filter { !$0.isEmpty }
        if !selection.isEmpty { return selection }
        guard let loaded = loadedImageURL, let root = sessionRoot else { return [] }
        let rootSpellings = Set([root.path, physicalPath(of: root.path)])
        let loadedSpellings = Set([loaded.path, physicalPath(of: loaded.path)])
        for rootPath in rootSpellings {
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            for loadedPath in loadedSpellings where loadedPath.hasPrefix(prefix) {
                return [String(loadedPath.dropFirst(prefix.count))]
            }
        }
        return []
    }

    /// realpath(3) once (the L027 discipline: `withCString` caller-owned
    /// buffer scope, never handed to free/deallocate).
    private static func physicalPath(of path: String) -> String {
        path.withCString { cpath -> String in
            var buffer = [CChar](repeating: 0, count: 4096)
            if realpath(cpath, &buffer) != nil {
                return String(cString: buffer)
            }
            return path
        }
    }



    /// Job rows FIFO by seq — per-job state + the inline error face.
    private(set) var jobRows: [ExportJobSnapshot] = []

    /// The two-layer progress snapshot (queue done/total + active phase).
    private(set) var progress = ExportProgress(done: 0, total: 0)

    // MARK: - Configure (app root, once at scene task)

    func configure(metal: MetalContext?, registry: ModuleRegistry) {
        self.metal = metal
        self.registry = registry
    }

    // MARK: - Session lifecycle (the 11-04 T3 wiring, checker E1)

    /// openSession leg: REBUILD the queue for the new session (the 9-3
    /// thumbnail-provider pattern — the old instance's `cancelAll`
    /// semantics are implicit in the drop; its detached stragglers finish
    /// into the void). Session scope ruling OQ-11-3: no cross-session
    /// journal (D-11-CONTEXT-8).
    func rebuildQueueForSession() async {
        guard let metal, let registry else {
            Self.logger.error("export state: configure() never ran — no queue")
            return
        }
        let queue = ExportQueue(
            metal: metal,
            registry: registry,
            yiyinInjector: Self.makeYiyinInjector(logoStore: yiyinLogoStore))
        await queue.setProgressHook { [weak self] in
            await self?.refreshFromQueue()
        }
        // The per-job post-action trigger (EXP-08, OQ-11-7): every
        // promoted FILE fires once; failed/cancelled jobs never do.
        await queue.setCompletionHook { [weak self] snapshot, url in
            await self?.jobDidComplete(snapshot, url: url)
        }
        self.queue = queue
        jobRows = []
        progress = ExportProgress(done: 0, total: 0)
        // Recipe resets on a session switch (session-lifetime memory).
        recipe = [Self.defaultVariant]
        customDestination = nil
    }

    /// applicationWillTerminate leg (the 02-06 flush-slot shape): the
    /// export queue has NO journal (D-11-CONTEXT-8) and exports are
    /// re-runnable — v1 records the in-flight count and lets termination
    /// proceed. A render stage holds NO partial file (nothing is written
    /// before the encode's atomic promote), so an aborted job leaves no
    /// half-written destination behind.
    func flushForTermination() {
        let inFlight = progress.total - progress.done
        if inFlight > 0 {
            Self.logger.info(
                "export terminate: \(inFlight, privacy: .public) unsettled job(s) abandoned (no journal, re-runnable)"
            )
        }
    }

    // MARK: - Queue actions (the panel's verbs)

    /// Fan the queue action out: `images × recipe` jobs, ONE call (EXP-07).
    /// The caller owns the pre-export sidecar flush (the panel hops through
    /// its environment — D-03b keeps THIS object pipe-free), the
    /// destination decision (Output/ default vs the custom pick) and the
    /// canvas hint (the CURRENT image's extent — only the percent sizing
    /// mode's derived tag needs it; every other mode's tag is
    /// canvas-independent).
    ///
    /// Tag resolution (D-11-CONTEXT-4): the recipe's tags resolve HERE via
    /// `resolvedOutputTags` (explicit tag wins; multi-variant batches get
    /// the size/format-derived tag so same-stem outputs never overwrite
    /// each other; single variant → no tag). Same-batch same-name
    /// collisions across IMAGES degrade to ExportNamer's -1/-2 increments.
    func enqueueExport(
        images: [(url: URL, relPath: String)],
        canvasSize: SIMD2<Int>? = nil
    ) async throws {
        guard let queue else {
            throw AppError.invalidParameter("no export queue (no session open)")
        }
        guard !recipe.isEmpty, !images.isEmpty else { return }
        guard let destination = customDestination
            ?? sessionRoot.map({ ExportFileWriter.defaultDestination(for: $0) })
        else {
            throw AppError.invalidParameter("no export destination (no session open)")
        }
        try ExportFileWriter.ensureDirectory(destination)
        let size = canvasSize ?? SIMD2(0, 0)
        let tags = recipe.resolvedOutputTags(
            canvasWidth: size.x, canvasHeight: size.y)
        let tagged = zip(recipe, tags).map { variant, tag -> ExportVariant in
            var copy = variant
            copy.outputTag = tag
            return copy
        }
        await queue.enqueue(
            images: images,
            variants: tagged,
            destinationDirectory: destination)
        await refreshFromQueue()
    }

    func cancelJob(_ id: UUID) async {
        await queue?.cancel(jobID: id)
    }

    func cancelAllJobs() async {
        await queue?.cancelAll()
    }

    func retryJob(_ id: UUID) async {
        do {
            try await queue?.retry(jobID: id)
        } catch {
            Self.logger.error(
                "export retry rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Observation refresh (the hook's MainActor hop)

    /// The per-job DONE trigger (EXP-08): the post-export actions fire per
    /// promoted file (the dt `darktable|exported` per-image semantics) —
    /// a failed/cancelled job never reaches here (the queue only fires the
    /// hook for `.done`). The reveal hops to AppKit on the main thread;
    /// the script process detaches (fire-and-forget — a slow script must
    /// not block the bridge).
    private func jobDidComplete(_ snapshot: ExportJobSnapshot, url: URL) {
        guard case .done = snapshot.state else { return }
        let script =
            PostExportActions.wantsRunScript
            ? PostExportActions.resolveScript() : nil
        guard PostExportActions.wantsRevealInFinder || script != nil else { return }
        PostExportActions.fire(for: url, script: script)
    }

    /// The queue's progress hook hops HERE (await from the detached task —
    /// the MainActor boundary is the D-03b bridge; the hook body is
    /// fire-and-forget so it never blocks the pump).
    private func refreshFromQueue() async {
        guard let queue else { return }
        jobRows = await queue.snapshots()
        progress = await queue.progress()
    }

    // MARK: - The session root (for the Output/ default)

    /// Set by the app root on every open (the ONLY session fact this state
    /// holds — a URL, not a reference to another state object).
    var sessionRoot: URL?

    // MARK: - The yiyin injector (the 11-03 seam's App-side production fill)

    /// `injectYiyinRunContext`'s semantic mirror for the headless export
    /// (the YiyinE2ETests.wireYiyinContext shape): watermark captureExif +
    /// logo faces + the JointContext riding the ENTRY plane size, and the
    /// borders joint-layout override. The renderer guarantees the injector
    /// runs after box materialization and before the render.
    static func makeYiyinInjector(
        logoStore: YiyinLogoStore
    ) -> ExportYiyinInjector {
        ExportYiyinInjector { boxes, records, mainImageSize, capture in
            guard let watermarkBox = boxes.first(where: {
                $0.opName == WatermarkModule.opName
            }) as? ModuleBox<WatermarkModule> else { return }
            let bordersRecord = records.first { $0.opName == BordersModule.opName }
            let bordersParams = try? bordersRecord?.params(of: BordersModule.self)
            let watermark = watermarkBox.module
            watermark.captureExif = capture
            watermark.logoExists = { make, variant in
                logoStore.embeddedExists(make: make, variant: variant)
            }
            watermark.logoProvider = logoStore.provider()
            watermark.jointContext = WatermarkModule.JointContext(
                mainImageSize: mainImageSize, bordersParams: bordersParams)
            guard let bordersBox = boxes.first(where: {
                $0.opName == BordersModule.opName
            }) as? ModuleBox<BordersModule> else { return }
            bordersBox.module.jointLayoutOverride = watermark.makeJointLayoutRecord(
                mainImageSize: mainImageSize, bordersParams: bordersParams)
        }
    }
}
