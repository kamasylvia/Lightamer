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

    /// The injected defaults (OQ-3/OQ-10 memory keys read/write through
    /// HERE — the M2-1 D-EXEC-1 discipline: views never touch UserDefaults,
    /// the state object is the single access face). The default init passes
    /// `.standard` (the app face — the app-root construction site is a
    /// zero-diff surface); tests pass an isolated suite.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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

    // MARK: - The preset face (Plan 12-4 T4; the Phase 11 移交① mount)

    /// Fill the inline-edited recipe from an export preset (D-11-CONTEXT-3
    /// 升级路径字面兑现): the persisted recipe REPLACES the memory-only
    /// editing state; the panel's inline editors keep working untouched —
    /// a preset fill is just another recipe assignment. The load gate
    /// already validated the file, and this re-checks every variant BEFORE
    /// assigning (typed error, never a partial fill).
    func applyPresetRecipe(_ recipe: ExportRecipe) throws {
        for variant in recipe {
            try variant.validate()
        }
        guard !recipe.isEmpty else {
            throw AppError.invalidParameter("export preset recipe is empty")
        }
        self.recipe = recipe
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

    // MARK: - The M2 face (Plan M2-9-04; additive — the legacy sheet face
    // above is byte-frozen)

    // MARK: Memory keys (OQ-3 destination + OQ-10 quality four)

    /// The registered storage keys (the ONLY spellings — AC4 greps these).
    nonisolated static let lastDirectoryKey = "export.lastDirectory"
    nonisolated static let jpegQualityKey = "export.jpegQuality"
    nonisolated static let heicQualityKey = "export.heicQuality"
    nonisolated static let avifQualityKey = "export.avifQuality"
    nonisolated static let webpQualityKey = "export.webpQuality"

    /// The four quality memory keys by format kind (the page's memory map —
    /// every quality knob gets its own key, OQ-10 A: AVIF 95 ≠ WebP 95).
    nonisolated static let qualityKeysByFormat: [String: String] = [
        "jpeg": ExportState.jpegQualityKey,
        "heic": ExportState.heicQualityKey,
        "avif": ExportState.avifQualityKey,
        "webp": ExportState.webpQualityKey,
    ]

    /// The last-used destination directory (OQ-3 B). nil = unset/first use
    /// — the fallback face below serves the source-image directory. Stored
    /// as a path STRING (the destinationSection precedent: a plain URL, no
    /// bookmark — the app is not sandboxed; Alcedo `defaultExportFolder`
    /// same-shape memory).
    func loadM2LastDirectory() -> URL? {
        let path = defaults.string(forKey: Self.lastDirectoryKey) ?? ""
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The directory-picker write-back face (OQ-3: 目录选择器记忆写回).
    func storeM2LastDirectory(_ url: URL) {
        defaults.set(url.path, forKey: Self.lastDirectoryKey)
    }

    /// The effective destination (OQ-3's first-use fallback): the memory
    /// key wins; nil memory falls back to the first target's directory
    /// (首用回落 = 当前选中首图所在目录); neither → nil (the run gate stays
    /// disabled — no silent guess).
    func m2EffectiveDestination(firstTargetDirectory: URL?) -> URL? {
        loadM2LastDirectory() ?? firstTargetDirectory
    }

    /// One quality knob's memory (0...1). Absent / foreign-typed / out-of-
    /// domain / non-finite degrade to nil (a corrupt value never blocks
    /// the panel — and never masquerades as a remembered 0: the TYPED
    /// read distinguishes unset, a stored 0.0, and garbage).
    func loadM2Quality(forKey key: String) -> Double? {
        guard let stored = defaults.object(forKey: key) as? Double else { return nil }
        guard stored.isFinite, ExportFormatSpec.qualityRange.contains(stored) else {
            return nil
        }
        return stored
    }

    /// The quality write-back face (the page writes on run + off-page —
    /// the Alcedo QML:271-288 lifecycle).
    func storeM2Quality(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: The M2 target derivation (KD-4 — additive; the session-semantics
    // `targetRelPaths` above never enters the M2 face)

    /// The M2 selection provider — armed by the SHELL (the grid state
    /// machine's multi-select, resolved to source URLs in row order). The
    /// L036 shape: the assembly point reads, views inject. nil/unarmed =
    /// no selection face (the derivation falls to the current image).
    var m2SelectionProvider: (() -> [URL])?

    /// The pure M2 目标 derivation: the grid selection when non-empty,
    /// else the currently edited image, else empty (no URL guessing — the
    /// M2 leg holds URL values directly; no relPath projection, plan risk
    /// note / DECISIONS).
    nonisolated static func m2TargetURLs(
        selection: [URL], loadedImageURL: URL?
    ) -> [URL] {
        if !selection.isEmpty { return selection }
        guard let loaded = loadedImageURL else { return [] }
        return [loaded]
    }

    /// The instance face the page consults (provider + the editor fallback).
    func m2Targets(currentImageURL: URL?) -> [URL] {
        Self.m2TargetURLs(
            selection: m2SelectionProvider?() ?? [],
            loadedImageURL: currentImageURL)
    }

    /// The project-open rebuild leg (KD-1 队列生命周期): the SAME semantics
    /// the session-open face uses — a fresh queue + rows/progress/recipe
    /// reset (the M2 workspace has no Session concept; the reset point is
    /// the project switch). The M2 face calls THIS; the legacy face keeps
    /// its session-open call site — one rebuild body, two named entries.
    func rebuildQueueForProject() async {
        await rebuildQueueForSession()
    }

    /// Test seam (the Core `inFlightCountForTesting` precedent — never
    /// called by app code): installs a queue with INJECTED legs so the
    /// assembly face is assertable without Metal. The production face
    /// stays `rebuildQueueForSession/Project` (metal-gated).
    func installQueueForTesting(_ queue: ExportQueue) {
        self.queue = queue
    }

    // MARK: The M2 assembly (KD-4 — D-M2-9-CONTEXT-4's terminal form)

    /// The EXIF Software stamp (D-M2-9-CONTEXT-5): `Lightamer <version>`.
    /// The pure face is injectable for tests; the app face resolves
    /// CFBundleShortVersionString.
    nonisolated static func exifSoftwareString(version: String) -> String {
        "Lightamer \(version)"
    }

    static var currentExifSoftware: String {
        exifSoftwareString(
            version: (Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?")
    }

    /// The batch DRT tail params (KD-4: `NodeOwnershipCatalog.drtPostOpNames
    /// ∩ 启用集` — the intersection happens INSIDE PixelPipe's tail demotion
    /// (enabled-box filter), so the App passes the catalog list verbatim,
    /// the PipeCoordinator 同法).
    nonisolated static func m2DrtTail(record: DrtRecord) -> DrtTailParams {
        DrtTailParams(record: record, postOpNames: NodeOwnershipCatalog.drtPostOpNames)
    }

    /// The M2 入队装配: per-image overrides + the batch DRT record + the
    /// panel's variant + the naming/collision/subfolder/destination face →
    /// variant 组 + the per-image drtTails carrier + the exifSoftware
    /// carrier (KD-4). `enqueueExport`'s body stays byte-frozen — the
    /// legacy sheet keeps the old face.
    ///
    ///   • `variant.drtOutput` = `drtRecord` (OQ-7 强制联动; the peak gate
    ///     rides M2-9-03's `ExportVariant.validate` typed refusal — a bad
    ///     record fails the job typed, never silently);
    ///   • `naming` = the pattern with the queue-stamped batch ordinal
    ///     (sequence = 选中序 1 起 — the queue stamps imageIndex+1);
    ///   • `relPath` = the file's display name (the M2 leg holds URLs —
    ///     no session-root projection; the snapshot display face is
    ///     unaffected, plan risk note / DECISIONS).
    func enqueueExportM2(
        images: [URL],
        instancesOverrides: [[ModuleInstance]?],
        drtRecord: DrtRecord,
        variant: ExportVariant,
        destination: URL,
        subfolder: String?,
        namingPattern: String,
        collisionPolicy: ExportNamer.ExportCollisionPolicy = .increment,
        exifSoftware: String? = nil,
        filmTails: [FilmTailParams?]? = nil
    ) async throws {
        if let filmTails, filmTails.count != images.count {
            throw AppError.invalidParameter(
                "export m2: per-image filmTails count \(filmTails.count) "
                    + "!= image count \(images.count)")
        }
        // The M2-9-02 acceptance O-2 前车之鉴: the per-image carriers are
        // INDEXED — a count mismatch is a caller bug and gets the typed
        // rejection BEFORE any environment lookup (the queue's per-image
        // precondition would otherwise trap).
        guard instancesOverrides.count == images.count else {
            throw AppError.invalidParameter(
                "export m2: per-image payload count \(instancesOverrides.count) "
                    + "!= image count \(images.count)")
        }
        guard let queue else {
            throw AppError.invalidParameter("no export queue (no project open)")
        }
        guard !images.isEmpty else { return }
        try ExportFileWriter.ensureDirectory(destination)
        // OQ-7: the DRT linkage is FORCED — the record lands on the variant
        // (peak gate: a non-finite/non-positive peak is the renderStage
        // validate's typed refusal, the 03 兜底 face) and on every image's
        // tail carrier (the render half of the same linkage).
        var assembled = variant
        assembled.drtOutput = drtRecord
        let tails = images.map { _ in Self.m2DrtTail(record: drtRecord) }
        let naming = ExportNamingRequest(
            pattern: namingPattern,
            sequence: 1,
            fallbackStem: ExportFileNameTemplate.fallbackStem)
        await queue.enqueue(
            images: images.map { (url: $0, relPath: $0.lastPathComponent) },
            variants: [assembled],
            destinationDirectory: destination,
            instancesOverrides: instancesOverrides,
            drtTails: tails,
            filmTails: filmTails,
            naming: naming,
            collisionPolicy: collisionPolicy,
            subfolder: subfolder,
            exifSoftware: exifSoftware)
        await refreshFromQueue()
    }
}
