import AppKit
import Foundation
import LightamerCore
import LightamerIOP
import Metal
import Observation
import simd
import os

/// The multi-resolution pipe owner (Plan 02-03-04; FOUND-04 SC#4's pipe
/// half + D-03b state isolation — a dedicated subsystem object, NOT
/// `EditorState` growth).
///
/// Translates *what changed* into *which pipe re-renders*, per the
/// 02-RESEARCH §2.1 lifecycle table:
///
/// | Event                        | PREVIEW          | THUMBNAIL            | FULL              |
/// |------------------------------|------------------|----------------------|-------------------|
/// | `load(...)`                  | create + render  | `needsRender = true` | never             |
/// | `historyDidChange()`         | re-render NOW    | `needsRender = true` (lazy) | never       |
/// | `drawableDidChange(_:)`      | re-render iff bucket CROSS (D-C3) | —   | never            |
/// | `fetchThumbnail()`           | —                | render iff needsRender | —               |
/// | `requestFull()`              | —                | —                    | render on-demand  |
///
/// **History → pipes (Plan 02-05, D-H1 trio + HIST-02):** `EditorState`
/// owns the `HistoryStack` and the live `[ModuleInstance]` records; this
/// coordinator is their RENDER side. The contract for every editing
/// control (Phase 3 sliders call exactly this):
///
/// ```
/// beginContinuousEdit()                    // drag start
/// await setLiveParams(snapshot)            // per drag tick — preview only,
///                                          // ZERO history items
/// await commitContinuousEdit(label:)       // drag end — exactly ONE item
/// ```
/// plus the navigation entries `undo()` / `redo()` / `jumpToHistory(_:)`
/// (HIST-02's UI-facing shape; Phase 3 attaches the first real panel).
/// Every path funnels into `historyDidChange()`, which RE-MATERIALIZES
/// the boxes from `editorState.instances` (in-place by instanceUUID —
/// unchanged params keep their uniforms and cache planes) and re-renders.
///
/// **Display push (D-X1 invariant):** this coordinator is the ONLY writer
/// of `EditorState.displayTexture` — every path funnels through
/// `renderPreview` → `editorState?.displayTexture`. Views never trigger
/// renders; `drawableDidChange` is an INPUT event (geometry), not a render
/// producer.
///
/// **EditorState linkage (plan choice, documented):** the plan offered a
/// weak `EditorState` reference OR a display-push closure. Chosen: the weak
/// reference (`attach(editorState:)`), because both objects are strongly
/// owned by the app root (`@State`) — a single weak back-reference gives
/// the cycle-free graph with zero closure plumbing. Construction order
/// (coordinator needs the state instance; state needs the coordinator for
/// `load` delegation) also rules out true init-time injection.
///
/// **Render-path isolation:** coordinator methods are `@MainActor async`,
/// but the heavy work (CIRAW decode leg, bitmap render, kernel dispatch)
/// lives in nonisolated async Core code — the MainActor only awaits results
/// and mutates this state. A `generation` counter discards results from
/// superseded events (newest-wins without task bookkeeping).
///
/// **SEAMS (documented extension points, no code yet per plan):**
/// - **02-06 sidecar (LANDED):** load-switch flush → restore-or-fresh in
///   `load(...)`; `scheduleSidecarWrite()` on every history-move caller;
///   `flushSidecar()` / `flushForTermination()` (AppDelegate's
///   `applicationWillTerminate`); drift + unknown-op degrade +
///   `EditorState.presentToast` (D-26 background grading).
/// - **02-06 clearCaches (D-C1/D-C2):** `load(...)` fires the
///   `cache.enforceBudget(keeping:)` at its entry (KeepingPolicy consumes
///   `currentImageID` + `previousImageID`, both tracked here), plus a 60s
///   sweep task.
/// - **02-04 terminal trio / display profile:** a display-profile change
///   hooks in next to `drawableDidChange` and invalidates ONLY the terminal
///   segment (colorout/gamma) — upstream planes must survive it. The fold
///   is environment identity and deliberately stays OUT of history
///   records; `historyDidChange` re-folds after each re-materialization.
@Observable
@MainActor
final class PipeCoordinator {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "coordinator"
    )

    // ── Owned state ──────────────────────────────────────────────────────

    /// One cache per coordinator = per app; shared across ALL resolutions
    /// (keys carry `pipeType`, so PREVIEW/THUMBNAIL/FULL planes coexist
    /// without aliasing — Risk #8).
    private let cache = PipeCache()

    /// The decoded source + current instance set for re-renders. Phase 2
    /// pass-through: the app passes `[]` until 02-04's registry supplies
    /// the default chain (terminal trio).
    private var decoded: DecodedImage?
    private var instances: [any ModuleBoxing] = []
    private var metal: MetalContext?

    /// The per-image pipe instances, LIFECYCLE-side: the `PixelPipe` itself
    /// stays internal to Core (plan artifacts list keeps `roi`/`isDirty`/
    /// `runIfDirty`/`runOnce` internal, test-driven via `@testable`); the
    /// coordinator owns the per-resolution lifecycle STATE and drives runs
    /// through `RenderPipeline.process` — the public Core entry (recorded
    /// plan deviation: the plan's `PixelPipe?` fields are realized as this
    /// lifecycle state, because a public `PixelPipe` would widen the
    /// cross-module surface the plan explicitly froze).
    private(set) var currentImageID: UUID?

    /// D-C1 keep-policy input: the image loaded BEFORE the current one
    /// (02-06's `KeepingPolicy` keeps its PREVIEW while evicting the rest).
    private var previousImageID: UUID?

    /// Stable per-image UUIDs: generated once per URL and cached here this
    /// phase; 02-06 persists them with sidecars (SEAM above).
    private var imageIDMap: [URL: UUID] = [:]

    /// The D-C3 bucket the PREVIEW pipe is currently warm at (nil = no
    /// bucket decided yet — first drawable event or load picks one).
    private var currentBucket: Int?

    /// Last reported viewport point long edge — remembered even when no
    /// image is loaded (the view's `onAppear` input typically precedes the
    /// decode), so `load` renders PREVIEW directly at the REAL window
    /// bucket instead of the cap fallback.
    private var lastDrawableLongEdge: Int?

    /// THUMBNAIL lazy lifecycle (`PipeResolution.isLazy` mirror): armed on
    /// load/param-change WITHOUT rendering; `fetchThumbnail()` renders only
    /// when armed (Phase 9 browser seam).
    private var thumbnailNeedsRender = false

    /// Last rendered THUMBNAIL plane (≈5MB at 360px float32) so clean
    /// fetches hand back the existing plane instead of nil.
    private var lastThumbnail: (any MTLTexture)?

    /// Newest-wins guard: incremented on every state-changing event; a
    /// render result whose captured generation no longer matches is dropped
    /// (superseded by a newer load/param/bucket event).
    private var generation = 0

    /// Weak back-reference (see linkage note in the header).
    private weak var editorState: EditorState?

    // ── 02-05 history-driven rendering (D-H1 trio state) ─────────────────

    /// True between `beginContinuousEdit()` and `commitContinuousEdit` —
    /// the drag window. Live params flow WITHOUT history; the commit
    /// collapses the whole interaction into ONE item.
    private var isEditingContinuous = false

    /// The live snapshots touched during the current continuous edit,
    /// keyed by instance UUID — what `commitContinuousEdit` turns into
    /// history items (usually exactly one entry per drag).
    private var liveEdited: [UUID: ModuleInstance] = [:]

    /// The URL the in-memory history currently belongs to (Phase 2 keeps
    /// history per image session; a NEW url flushes the outgoing sidecar,
    /// then restores the incoming one or resets to pristine).
    private var historyLoadedURL: URL?

    // ── 02-06 sidecar persistence (D-S2/D-S3) ────────────────────────────

    /// The per-image store for the CURRENT url (throttle + atomic write +
    /// load). Recreated per load switch; the destination is
    /// `<original FULL name>.lra` beside the original (D-C2/D-S3 era:
    /// `<original FULL name>.lra`, D-S2).
    private var sidecarStore: SidecarStore?
    private var sidecarDestination: URL?

    // ── 02-06 session memory budget (D-C1/D-C2) ──────────────────────────

    /// The 60-second BACKSTOP sweep task (D-C2 trigger b): long sessions
    /// on ONE image accumulate PREVIEW bucket versions as the window
    /// resizes across D-C3 steps; the load-entry sweep alone never fires
    /// for them. Actor-internal Task loop — NOT a Timer/RunLoop
    /// (`enforceBudget` stays the unit-testable pure executor; the timer
    /// is only a caller, research Open Question #7). Cancellation-safe:
    /// dies with the coordinator (app-lifetime object).
    private var budgetSweepTask: Task<Void, Never>?

    /// Toast throttle state: one "cache freed" notice per sweep interval
    /// (D-26 — silent small cleanups never surface).
    private var lastCacheToastAt: ContinuousClock.Instant = .now - .seconds(61)

    // ── 02-04 terminal trio + display follow ─────────────────────────────

    /// The app-built module registry (terminal trio + IOP populate hook);
    /// supplies the default chain when a load passes no explicit instances.
    private var registry: ModuleRegistry?

    /// The colorout box of the CURRENT chain, typed — the D-COL2 screen
    /// follow re-commits its params (folding `DisplayProfile.stableID`)
    /// so a display change invalidates exactly the ≥colorout cache keys.
    private var coloroutBox: ModuleBox<ColorOutModule>?

    /// The display profile the current chain was committed for (nil = no
    /// chain yet). Idempotence gate for the screen-change notifications.
    private var displayStableID: UInt64?

    /// The window whose screen drives D-COL2 (multi-display follows the
    /// WINDOW's screen). Captured via `configure(window:)` from the app
    /// root's `WindowCapture` accessory (view.window at first placement —
    /// the least-invasive option per the plan).
    private weak var window: NSWindow?

    /// Screen-follow observers (`notifications` async-sequence tasks,
    /// app-lifetime — the coordinator lives for the whole session).
    private var screenWatchTasks: [Task<Void, Never>] = []

    private static let colorLogger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "color"
    )

    // ── Lifecycle ────────────────────────────────────────────────────────

    /// Wire the display sink (called once by the app root after both
    /// `@State` objects exist — see the header for why this is not init).
    func attach(editorState: EditorState) {
        self.editorState = editorState
    }

    /// Inject the module registry (Plan 02-04-05) — the app builds
    /// `ModuleRegistry.makeDefault()`, populates LightamerIOP's modules,
    /// then attaches it here. Loads with empty instance sets resolve to
    /// the registry's default chain (terminal trio).
    func attach(registry: ModuleRegistry) {
        self.registry = registry
    }

    /// Capture the editor window (D-COL2: follow the WINDOW's screen) and
    /// start the screen-follow observers. Called by the app root's window
    /// capture accessory; safe to call again (idempotent).
    func configure(window: NSWindow) {
        let isNewWindow = window !== self.window
        self.window = window
        guard screenWatchTasks.isEmpty || isNewWindow else { return }
        startScreenFollow()
        // Initial resolve (also covers a same-window re-configuration).
        Task { await self.displayDidChange(initial: true) }
    }

    /// D-COL2 observers: `NSWindow.didChangeScreen` (window dragged to
    /// another display) + `NSApplication.didChangeScreenParameters`
    /// (displays connected/changed resolution/profile). App-lifetime tasks.
    private func startScreenFollow() {
        guard screenWatchTasks.isEmpty else { return }
        let center = NotificationCenter.default
        screenWatchTasks.append(Task { [weak self] in
            for await _ in center.notifications(
                named: NSWindow.didChangeScreenNotification
            ) {
                await self?.displayDidChange()
            }
        })
        screenWatchTasks.append(Task { [weak self] in
            for await _ in center.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            ) {
                await self?.displayDidChange()
            }
        })
    }

    /// A screen event arrived: re-resolve the window's display profile;
    /// only an actual `stableID` change re-commits + re-renders (the
    /// notification can fire for unrelated screen events — idempotent).
    /// The re-commit folds the new `stableID` into colorout's paramsHash,
    /// so the PREVIEW re-render hits everything upstream of colorout and
    /// re-runs ONLY the colorout+gamma terminal segment (SC#2 terminal
    /// variant; cached planes stop at colorout — research §3.3).
    private func displayDidChange(initial: Bool = false) async {
        let profile = DisplayProfile.resolve(
            window?.screen?.colorSpace ?? NSScreen.main?.colorSpace
        )
        if initial {
            Self.colorLogger.info("display profile → \(profile.label, privacy: .public)")
        }
        guard profile.stableID != displayStableID else {
            if !initial {
                Self.colorLogger.debug(
                    "screen event without a profile change — idempotent no-op"
                )
            }
            return
        }
        displayStableID = profile.stableID
        Self.colorLogger.info("display profile → \(profile.label, privacy: .public)")

        // Re-commit colorout for the new display (params content unchanged;
        // the folded stableID changes the hash).
        await recommitColoroutForDisplay()
        // Re-render the visible pipe (upstream cache planes survive).
        guard decoded != nil else { return }
        generation += 1
        thumbnailNeedsRender = true
        await renderPreview(
            bucket: currentBucket ?? PreviewBucket.cap, generation: generation
        )
    }

    /// Adopt a chain for rendering: explicit instances win; empty → the
    /// history-owned instance set (02-05). Captures the typed colorout
    /// box and commits its params for the CURRENT display.
    private func adoptChain(_ explicit: [any ModuleBoxing]) async
        -> [any ModuleBoxing]
    {
        if !explicit.isEmpty {
            captureColoroutBox(from: explicit)
            await recommitColoroutForDisplay()
            return explicit
        }
        guard let registry else { return [] }
        let chain = await registry.makeDefaultChain()
        captureColoroutBox(from: chain)
        await recommitColoroutForDisplay()
        return chain
    }

    /// Re-commit colorout's params for the CURRENT display (folds the
    /// resolved `DisplayProfile.stableID` into the committed piece hash —
    /// D-COL2's terminal-segment invalidation atom). ENVIRONMENT identity:
    /// deliberately NOT part of history records; `rematerializeInstances`
    /// re-folds after every canonical re-apply so a history navigation
    /// never drops the live display follow.
    private func recommitColoroutForDisplay() async {
        guard let box = coloroutBox else { return }
        let profile = DisplayProfile.resolve(
            window?.screen?.colorSpace ?? NSScreen.main?.colorSpace
        )
        box.module.displayProfileOverride = profile
        let params = (try? JSONDecoder().decode(
            ColorOutModule.Params.self, from: box.paramsData
        )) ?? ColorOutModule.Params()
        await box.setParams(params)
    }

    /// Find the colorout box in a chain (typed, for the display follow).
    private func captureColoroutBox(from chain: [any ModuleBoxing]) {
        coloroutBox = chain.first { $0.opName == ColorOutModule.opName }
            as? ModuleBox<ColorOutModule>
    }

    /// A new image finished decoding: assign the stable imageID, (re)arm
    /// the multi-resolution lifecycle, and render PREVIEW immediately
    /// (always-warm). THUMBNAIL is armed dirty, not rendered (lazy). FULL
    /// is never touched here.
    func load(
        url: URL,
        decoded: DecodedImage,
        instances: [any ModuleBoxing],
        metal: MetalContext
    ) async {
        generation += 1
        let gen = generation
        self.decoded = decoded
        self.metal = metal
        if !instances.isEmpty {
            // Explicit chains (tests, restore previews) bypass the
            // history-owned instance set — adopt as-is (02-04 behavior).
            self.instances = await adoptChain(instances)
        } else {
            // 02-05/02-06: the HISTORY owns the instance set. A NEW url
            // first FLUSHES the outgoing image's pending sidecar (D-S3),
            // then restores the incoming `.lra` when present (drift check
            // + unknown-op degrade) or seeds pristine with a MINTED
            // imageID (checkpoint lock #7). A same-url reload keeps the
            // session's in-memory history.
            if historyLoadedURL != url {
                await flushSidecar()
                let destination = LightamerSidecar.sidecarURL(for: url)
                let store = SidecarStore(destination: destination)
                sidecarStore = store
                sidecarDestination = destination
                if let document = await store.load() {
                    await restoreFromSidecar(
                        document: document, url: url, decoded: decoded
                    )
                } else {
                    // Pristine seed (Plan 03-02-T4): terminal trio + the
                    // LightamerIOP tone iops with permanent panels at
                    // IDENTITY params — their Inspector panels need
                    // instances to drive. Identity keeps the chain
                    // cache-neutral (same hashes as the bare trio).
                    let defaults = (await registry?.makeDefaultInstances() ?? [])
                        + LightamerIOPRegistry.editingDefaultInstances()
                    editorState?.resetHistoryForNewImage(
                        defaultInstances: defaults.sorted {
                            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
                        }
                    )
                }
                historyLoadedURL = url
            }
            await rematerializeInstances()
        }

        previousImageID = currentImageID // D-C1 input for the keep policy
        if let existing = imageIDMap[url] {
            currentImageID = existing
        } else {
            let fresh = UUID()
            imageIDMap[url] = fresh
            currentImageID = fresh
        }

        // D-C2 trigger (a): the LOAD-ENTRY sweep — BEFORE the new image's
        // pipes render, purge the outgoing session's planes. Evidence for
        // the hard requirement: Phase 1 spike-b measured 4.3-5.4 GB of
        // cross-decode accumulation WITHOUT it (CI/RawCamera internal
        // per-camera state included — hence the pool-level clearCaches
        // below); the D-32 4 GB session budget breaks by the third large
        // image. Uses the freshly assigned currentImageID (the incoming
        // image's namespace) + the outgoing one as `previousImageID`.
        // Phase 9 hook (documented): session SWITCH also calls
        // `cache.invalidateAll()` + this sweep once multi-session lands.
        if let currentImageID {
            let freed = await cache.enforceBudget(
                keeping: PipeCache.KeepingPolicy(
                    currentImageID: currentImageID, previousImageID: previousImageID
                )
            )
            await metal.clearCICaches()
            presentCacheFreedToast(freed)
        }
        startBudgetSweepIfNeeded()

        // Reconcile the bucket before the first render: a drawable input
        // that arrived before the decode finished is honored now (else the
        // first PREVIEW would render at the cap and wait for the next
        // resize to correct).
        if currentBucket == nil, let last = lastDrawableLongEdge {
            currentBucket = PreviewBucket.longEdge(forDrawable: last)
        }

        thumbnailNeedsRender = true
        lastThumbnail = nil
        await renderPreview(
            bucket: currentBucket ?? PreviewBucket.cap, generation: gen
        )

        // PERF-5 PSO startup pre-warm (Plan 03-06-T7, Open#7 decision):
        // background task pre-compiles the current chain's compute PSOs so
        // the FIRST interactive drag does not pay the cold PSO build
        // (METAL-5). Fire-and-forget — the lazy PSO cache stays the source
        // of truth and the warm task only touches `pipelineState`.
        startPSOPrewarmIfNeeded()
    }

    /// Arm the one-shot PSO pre-warm (idempotent per session).
    private func startPSOPrewarmIfNeeded() {
        guard psoPrewarmTask == nil, let metal else { return }
        psoPrewarmTask = Task { [weak self] in
            // Small settle delay: let the first frame's own PSO hits land.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await metal.prewarmPipelineStates(
                functionNames: LightamerIOPRegistry.prewarmFunctionNames
            )
        }
    }

    // ── 02-06 session memory budget (D-C1/D-C2 sweep + toast) ────────────

    /// The one-shot PSO pre-warm task (nil = not armed yet).
    private var psoPrewarmTask: Task<Void, Never>?

    /// Arm the 60s backstop sweep once (idempotent; first load arms it).
    /// The Task inherits the coordinator's MainActor isolation — the loop
    /// body reads state directly and only `await`s the cache/pool actors.
    private func startBudgetSweepIfNeeded() {
        guard budgetSweepTask == nil else { return }
        budgetSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled, let currentImageID = self.currentImageID else {
                    continue
                }
                let freed = await self.cache.enforceBudget(
                    keeping: PipeCache.KeepingPolicy(
                        currentImageID: currentImageID,
                        previousImageID: self.previousImageID
                    )
                )
                self.presentCacheFreedToast(freed)
            }
        }
    }

    /// D-26 background toast when a sweep freed > 500 MB, throttled to one
    /// notice per sweep interval.
    private func presentCacheFreedToast(_ freed: PipeCache.Freed) {
        guard freed.bytesFreed > 500 * 1024 * 1024 else { return }
        let now = ContinuousClock.now
        guard now - lastCacheToastAt > .seconds(60) else { return }
        lastCacheToastAt = now
        let gb = Double(freed.bytesFreed) / (1024 * 1024 * 1024)
        let formatted = String(format: "%.1f GB", gb)
        editorState?.presentToast(
            String(format: String(localized: "toast_cache_freed"), formatted)
        )
        Self.logger.info(
            "cache sweep freed \(formatted, privacy: .public) (\(freed.planesEvicted, privacy: .public) planes)"
        )
    }

    // ── 02-06 sidecar persistence (restore + throttled write) ────────────

    /// Restore a decoded `.lra` into EditorState (checkpoint locks #5/#7):
    /// the stored imageID REPLACES the in-memory UUID (never re-mint), the
    /// drift anchor is recomputed and compared (mismatch → log + toast,
    /// memory wins, NO write-back), unknown ops degrade to
    /// `enabled = false` with `paramsData` verbatim, then the history +
    /// persisted instances land in EditorState.
    private func restoreFromSidecar(
        document: LightamerSidecar, url: URL, decoded: DecodedImage
    ) async {
        imageIDMap[url] = document.imageID

        // Decode-stamp diff is INFORMATIONAL: a decoder upgrade (RAW 8 → 9)
        // changes the live decode hash legitimately. The drift recompute is
        // seeded with the FILE's own decode hash, so this never reads as
        // user-data drift.
        let liveDecodeHash = HistoryHash.decodeParamsHash(for: decoded)
        if liveDecodeHash != document.decodeParamsHash {
            Self.logger.info(
                "sidecar \(url.lastPathComponent, privacy: .public): decode stamp differs from live decode — anchor keeps the stored seed"
            )
        }

        // HIST-04/SC#5 drift: external edit detection BEFORE any degrade
        // (the anchor was written from the as-saved state).
        if document.driftDetected {
            Self.logger.error(
                "sidecar \(url.lastPathComponent, privacy: .public): history hash MISMATCH — externally edited? In-memory (decoded) state wins; file is NOT rewritten until the next user edit"
            )
            editorState?.presentToast(String(localized: "toast_drift_detected"))
        }

        // Unknown-op degrade (checkpoint lock #4): keep params verbatim,
        // disable, toast — user data is never dropped. No registry (never
        // expected — attach happens before any load) = restore verbatim.
        guard let registry else {
            Self.logger.error("no module registry attached — sidecar restored without unknown-op degrade")
            editorState?.restoreFromSidecar(
                history: document.history, persistedInstances: document.instances
            )
            return
        }
        let (degradedHistory, unknownOps) = await document
            .degradedForUnknownOps(registry: registry)
        for op in unknownOps {
            Self.logger.error(
                "sidecar \(url.lastPathComponent, privacy: .public): unknown op '\(op, privacy: .public)' — instance kept disabled, params preserved"
            )
            editorState?.presentToast(
                String(format: String(localized: "toast_unknown_module_disabled"), op)
            )
        }

        editorState?.restoreFromSidecar(
            history: degradedHistory, persistedInstances: document.instances
        )
        Self.logger.info(
            "sidecar restored: \(url.lastPathComponent, privacy: .public) (history \(document.history.position + 1)/\(document.history.items.count), imageID \(document.imageID.uuidString, privacy: .public))"
        )
    }

    /// The current session as a persistable document (history + live
    /// records + decode stamps + the current imageID). nil = nothing to
    /// persist yet (no decode / no imageID).
    private func makeSidecarDocument() -> LightamerSidecar? {
        guard let decoded, let editorState, let imageID = currentImageID else {
            return nil
        }
        let decodeHash = HistoryHash.decodeParamsHash(for: decoded)
        return LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: decoded.decoderVersionUsed.rawValue,
            decodeParamsHash: decodeHash,
            instances: editorState.instances,
            history: editorState.history,
            historyHash: HistoryHash.hash(
                stack: editorState.history, decodeParamsHash: decodeHash
            ),
            appVersion: LightamerSidecar.currentAppVersion
        )
    }

    /// D-S3: every committed history MOVE throttles a `.lra` write (2s
    /// merge). Live preview ticks (`setLiveParams`) deliberately do NOT
    /// schedule — the file must always satisfy the rebuild-from-history
    /// invariant, and uncommitted drag state is not history.
    private func scheduleSidecarWrite() {
        guard let sidecarStore, let document = makeSidecarDocument() else { return }
        Task { await sidecarStore.scheduleWrite(document) }
    }

    /// Force the pending write NOW (image switch, termination seam).
    /// Failures toast (D-26 background) — the session keeps working.
    func flushSidecar() async {
        guard let sidecarStore else { return }
        do {
            try await sidecarStore.flushNow()
        } catch {
            let appError = AppError(error)
            Self.logger.error(
                "sidecar flush failed: \(appError.localizedDescription, privacy: .public)"
            )
            editorState?.presentToast(
                String(localized: "toast_sidecar_write_failed")
            )
        }
    }

    #if DEBUG
    /// Probe-only GPU completion fence: getBytes on shared memory does not
    /// wait for in-flight encoders, and the headless sidecar probe hashes
    /// the display plane right after the render push. Same pattern as the
    /// test-suite drain helpers.
    func drainGPUForProbe() {
        guard let metal else { return }
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }
    #endif

    /// `applicationWillTerminate` flush: the AppKit callback is SYNCHRONOUS
    /// and the process exits when it returns, so the actor hop runs on a
    /// detached task behind a bounded semaphore (5s ceiling — L009: USB-
    /// volume writes can be slow; a hung disk must not block termination
    /// forever). Runs on the MainActor (the AppKit callback is main-thread).
    func flushForTermination() {
        guard let sidecarStore else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await sidecarStore.flushNow()
            } catch {
                AppError.logger.error(
                    "sidecar flush at termination failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + .seconds(5))
    }

    // ── 02-05 history-driven rendering (D-H1 trio + HIST-02 navigation) ──

    /// THE param-change path (replaces 02-03's `paramsDidChange`):
    /// re-materialize the boxes from `EditorState`'s live instance
    /// records, then PREVIEW re-renders NOW; THUMBNAIL only marks dirty
    /// (lazy — no render until fetched); FULL never auto-renders.
    ///
    /// Idempotent by construction: re-materialization keeps byte-identical
    /// params untouched (uniforms survive, cache keys unchanged), so a
    /// post-commit pass after a live-edited drag re-renders from cache
    /// hits — and an undo lands on the previous params' planes the same
    /// way (SC#2's undo leg end-to-end).
    ///
    /// The 02-06 sidecar `scheduleWrite()` lives on the HISTORY-MOVE
    /// callers below (`commitContinuousEdit`/`undo`/`redo`/
    /// `jumpToHistory`), NOT here — live drag ticks funnel through this
    /// too, and uncommitted drag state must never hit disk (the sidecar's
    /// rebuild-from-history invariant).
    func historyDidChange() async {
        guard decoded != nil else { return }
        await rematerializeInstances()
        generation += 1
        thumbnailNeedsRender = true
        await renderPreview(
            bucket: currentBucket ?? PreviewBucket.cap, generation: generation
        )
    }

    /// History → pipes materialization: rebuild `instances` (the BOXES)
    /// from `editorState.instances` (the RECORDS). Existing boxes are
    /// reused IN PLACE by instance UUID (`apply(_:)` fast-paths
    /// byte-identical params, so unchanged instances keep uniforms + cache
    /// planes); new records mint boxes via the registry (identity-
    /// preserving); records whose box vanished from the set are dropped
    /// (undo past an instance's birth). The colorout display fold is
    /// re-applied last — records stay canonical, environment folds live
    /// on boxes only. Unknown ops cannot occur from live edits (commits
    /// originate from registered boxes); a future sidecar-driven record
    /// set degrades upstream in 02-06 before reaching here.
    private func rematerializeInstances() async {
        guard let editorState else { return }
        let records = editorState.instances
        var boxes: [any ModuleBoxing] = []
        boxes.reserveCapacity(records.count)
        for record in records {
            if let existing = instances.first(where: { $0.instanceID == record.id }) {
                do {
                    try await existing.apply(record)
                    boxes.append(existing)
                } catch {
                    Self.logger.error(
                        "instance \(record.opName, privacy: .public) re-apply failed: \(error.localizedDescription, privacy: .public)"
                    )
                    boxes.append(existing) // keep last-good committed state
                }
            } else if let fresh = await registry?.makeBox(
                opName: record.opName, instanceID: record.id
            ) {
                do {
                    try await fresh.apply(record)
                } catch {
                    Self.logger.error(
                        "instance \(record.opName, privacy: .public) apply failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                boxes.append(fresh)
            } else {
                Self.logger.error(
                    "no registered module for op '\(record.opName, privacy: .public)' — record skipped"
                )
            }
        }
        instances = boxes
        captureColoroutBox(from: boxes)
        await recommitColoroutForDisplay()
    }

    /// D-H1 drag START: open a continuous-edit window. Live param updates
    /// (`setLiveParams`) drive preview re-renders with ZERO history items
    /// until `commitContinuousEdit` collapses the interaction into
    /// exactly ONE entry (checkpoint lock #1 — discrete controls skip the
    /// trio and commit once per click).
    func beginContinuousEdit() {
        isEditingContinuous = true
        liveEdited.removeAll()
    }

    /// D-H1 live leg (per drag tick): upsert the snapshot into the live
    /// instance set WITHOUT history, re-materialize + re-render. Inside
    /// an edit window the snapshot is remembered for the commit; outside
    /// one it previews only (defensive — Phase 3 sliders always begin
    /// first; a stray call must not fabricate history state).
    func setLiveParams(_ snapshot: ModuleInstance) async {
        guard let editorState else { return }
        if isEditingContinuous {
            liveEdited[snapshot.id] = snapshot
        }
        editorState.applyLiveInstance(snapshot)
        await historyDidChange()
    }

    /// D-H1 drag END: commit the touched live snapshots as history —
    /// exactly ONE `HistoryItem` per touched instance (one for every
    /// slider interaction). The pipes already rendered the live state, so
    /// the notification-driven `historyDidChange` pass is idempotent
    /// (cache hits end-to-end) — no second render is issued here.
    func commitContinuousEdit(label: String, autoEnable: Bool = true) async {
        isEditingContinuous = false
        // 04-08-T3 (GUI-7, D-08-T3-1): editing a disabled module's params
        // auto-enables at COMMIT (dt "edit implies enable"; live ticks keep
        // the stored enabled so the drag preview stays cache-stable —
        // enabled flips levelHash, and flipping per-tick would miss the
        // whole chain mid-drag). D-08-T3-2: explicit toggle-OFF
        // (`autoEnable = false`) bypasses the flip — otherwise the row
        // toggle could never disable a module.
        let touched = liveEdited.values.sorted {
            ($0.iopOrder, $0.multiPriority, $0.opName)
                < ($1.iopOrder, $1.multiPriority, $1.opName)
        }
        liveEdited.removeAll()
        guard !touched.isEmpty else { return }
        for snapshot in touched {
            var effective = snapshot
            if autoEnable, !effective.enabled { effective.enabled = true }
            editorState?.recordChange(effective, label: label)
        }
        scheduleSidecarWrite() // D-S3: the committed move throttles a write
    }

    /// HIST-02 undo (UI-facing shape; Phase 3 attaches the first panel):
    /// step the stack back via EditorState, then re-materialize + render.
    /// The edited position's plane misses (params reverted); everything
    /// upstream hits — and the REVERTED-TO params' planes usually still
    /// sit in the cache from before the edit.
    func undo() async {
        guard let editorState, editorState.performUndo() else { return }
        await historyDidChange()
        scheduleSidecarWrite() // position moved — persist it too
    }

    /// HIST-02 redo: into an untruncated tail only.
    func redo() async {
        guard let editorState, editorState.performRedo() else { return }
        await historyDidChange()
        scheduleSidecarWrite()
    }

    /// HIST-02/D-H3 jump-to-any-point: the stack clamps out-of-range
    /// indices (−1 = pristine); a clamp-only no-op still re-renders
    /// cheaply (all cache hits).
    func jumpToHistory(_ index: Int) async {
        guard let editorState else { return }
        editorState.performJump(to: index)
        await historyDidChange()
        scheduleSidecarWrite()
    }

    // ── D-T4 color sampling plumbing (Plan 03-02-T5) ─────────────────────

    /// The picked LINEAR Rec2020 color at a viewport point — the D-T4
    /// eyedropper base (and Phase 3's shared sampling plumbing for the
    /// filmic auto keys).
    ///
    /// Chain: viewport POINT → aspect-fit normalized uv (mirrors
    /// `EditorMTKView.Coordinator.aspectFitUniforms` exactly) → the LINEAR
    /// pipe plane re-run → fence (L014) → 5×5 area mean (dt AREA picker
    /// semantics, `color_picker_proxy`).
    ///
    /// The LINEAR plane is obtained by re-running the chain MINUS the
    /// display segment (colorout+gamma) at the CURRENT bucket: every plane
    /// of that segment is already cached from the last full render (same
    /// imageID/bucket/levelHash — the terminal modules sit above), so this
    /// costs zero GPU work and yields the float32 working-space values the
    /// WB module actually operates on. Sampling the display-ready `.bgra8`
    /// texture instead would be gamma-encoded 8-bit — useless for a
    /// scene-linear neutral solve (1e-5 tolerance).
    ///
    /// nil = nothing loaded, no GPU, click outside the fitted image rect,
    /// or the linear segment failed. Never mutates `displayTexture` (D-X1).
    func pickColor(at point: CGPoint, viewportSize: CGSize) async -> simd_float3? {
        guard let decoded, let metal, let display = editorState?.displayTexture else {
            return nil
        }
        let texSize = SIMD2<Int>(display.width, display.height)
        guard let uv = Self.viewportUV(
            at: point, viewportSize: viewportSize, textureSize: texSize
        ) else {
            Self.logger.debug("eyedropper click outside the fitted image rect")
            return nil
        }

        let linearChain = instances.filter {
            $0.opName != ColorOutModule.opName && $0.opName != GammaModule.opName
        }
        guard !linearChain.isEmpty else { return nil }
        do {
            let (texture, _) = try await RenderPipeline.process(
                image: decoded,
                instances: linearChain,
                imageID: currentImageID ?? UUID(),
                resolution: .preview,
                cache: cache,
                metal: metal,
                longEdge: currentBucket ?? PreviewBucket.cap
            )
            // L014: getBytes does not wait for in-flight encoders — fence
            // the queue before the CPU readback (async-safe completion await;
            // the CPU-side getBytes follows on this same task).
            let fence = metal.commandQueue.makeCommandBuffer()
            fence?.commit()
            await fence?.completed()
            return Self.sampleArea(texture: texture, uv: uv)
        } catch {
            Self.logger.error(
                "pickColor linear segment failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// The decoded source image for auto-detect features (04-03 ashift
    /// horizon/rectangle via `AshiftAutoDetect`): read-only, zero pipe
    /// involvement (panels render small probes from it — no pipe-plane
    /// readback, L014-clean by construction). nil when nothing is loaded.
    /// Additive seam (no existing caller touched).
    func detectionSourceImage() -> DecodedImage? {
        decoded
    }

    /// Forward a non-blocking status-bar toast to EditorState (D-26).
    /// Additive seam for 04-08-T2 (GUI-8): auto-detect nil/failure paths
    /// must be user-visible; no existing caller touched.
    func presentToast(_ message: String) {
        editorState?.presentToast(message)
    }

    /// Full-image per-channel RGB min/max over the linear chain (Plan
    /// 03-06-T5, the filmic auto black/white keys — dt's
    /// `picked_color_min/max` whole-preview semantics via the shared
    /// HistogramReduce). nil when nothing is loaded or the render failed.
    /// Never mutates `displayTexture` (D-X1).
    func sampleLinearNormMinMax() async -> (min: simd_float3, max: simd_float3)? {
        guard let decoded, let metal else { return nil }
        let linearChain = instances.filter {
            $0.opName != ColorOutModule.opName && $0.opName != GammaModule.opName
        }
        guard !linearChain.isEmpty else { return nil }
        do {
            let (texture, _) = try await RenderPipeline.process(
                image: decoded,
                instances: linearChain,
                imageID: currentImageID ?? UUID(),
                resolution: .preview,
                cache: cache,
                metal: metal,
                longEdge: currentBucket ?? PreviewBucket.cap
            )
            let fence = metal.commandQueue.makeCommandBuffer()
            fence?.commit()
            await fence?.completed()
            return try await HistogramReduce.rgbMinMax(of: texture, metal: metal)
        } catch {
            Self.logger.error(
                "linear norm min/max failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Viewport POINT → normalized texture uv, mirroring the blit's
    /// aspect-fit (`aspectFitUniforms` + the vertex uv chain):
    /// `uv.x = 0.5 + scale.x·(p.x/vw − 0.5)`,
    /// `uv.y = 0.5 − scale.y·(0.5 − p.y/vh)`. nil when the point falls in
    /// the letterbox (outside the fitted image rect).
    nonisolated static func viewportUV(
        at point: CGPoint, viewportSize: CGSize, textureSize: SIMD2<Int>
    ) -> SIMD2<Double>? {
        // 04-02-T4: single-source math (ViewportFit); the guard + letterbox
        // semantics are unchanged (EyedropperTests pin them).
        ViewportFit.uv(
            at: point, viewportSize: viewportSize,
            textureSize: CGSize(width: textureSize.x, height: textureSize.y))
    }

    /// N×N area mean around the uv point (dt AREA picker; default radius 2
    /// = 5×5), clamped at the borders. The texture is the float32 linear
    /// working-space plane.
    nonisolated static func sampleArea(
        texture: any MTLTexture, uv: SIMD2<Double>, radius: Int = 2
    ) -> simd_float3? {
        guard texture.pixelFormat == WorkingSpace.pixelFormat else { return nil }
        let width = texture.width
        let height = texture.height
        let cx = min(max(Int((uv.x * Double(width)).rounded()), 0), width - 1)
        let cy = min(max(Int((uv.y * Double(height)).rounded()), 0), height - 1)
        let x0 = max(cx - radius, 0), y0 = max(cy - radius, 0)
        let x1 = min(cx + radius, width - 1), y1 = min(cy + radius, height - 1)
        let w = x1 - x0 + 1, h = y1 - y0 + 1
        var pixels = [Float](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * WorkingSpace.bytesPerPixel,
                from: MTLRegionMake2D(x0, y0, w, h), mipmapLevel: 0
            )
        }
        var acc = simd_float3.zero
        for i in 0..<(w * h) {
            acc += simd_float3(pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2])
        }
        return acc / Float(w * h)
    }

    /// Viewport geometry changed (an INPUT event — the view never renders).
    /// Re-evaluates the D-C3 bucket: only a CROSS-step change re-renders
    /// PREVIEW; a within-step change is a logged no-op (the anti-jitter
    /// guard — window edge drags must not storm the pipe). The previous
    /// bucket's planes stay cached, so jittering back across the boundary
    /// is a cache hit, not a re-render (02-RESEARCH §2.3).
    func drawableDidChange(drawableLongEdge: Int) async {
        lastDrawableLongEdge = drawableLongEdge // remembered even pre-image
        guard decoded != nil else { return }
        let bucket = PreviewBucket.longEdge(forDrawable: drawableLongEdge)
        guard bucket != currentBucket else {
            Self.logger.debug(
                "drawable \(drawableLongEdge, privacy: .public)px within bucket \(bucket, privacy: .public)px — no re-render (D-C3)"
            )
            return
        }
        currentBucket = bucket
        generation += 1
        await renderPreview(bucket: bucket, generation: generation)
    }

    /// THUMBNAIL lazy fetch (Phase 9 browser seam): renders ONLY when the
    /// lazy flag is armed; clean fetches return the retained last plane
    /// (nil if none yet). Runs at the fixed 360px `defaultLongEdge`.
    func fetchThumbnail() async -> (any MTLTexture)? {
        guard let decoded, let metal, thumbnailNeedsRender else {
            return lastThumbnail
        }
        do {
            let (texture, stats) = try await RenderPipeline.process(
                image: decoded,
                instances: instances,
                imageID: currentImageID ?? UUID(),
                resolution: .thumbnail,
                cache: cache,
                metal: metal,
                longEdge: nil // THUMBNAIL defaultLongEdge 360
            )
            thumbnailNeedsRender = false
            lastThumbnail = texture
            Self.logger.info(
                "thumbnail ready (360px, \(stats.planesRendered, privacy: .public) planes)"
            )
        } catch {
            Self.logger.error(
                "THUMBNAIL render failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        return lastThumbnail
    }

    /// FULL on-demand scaffold (tests + Phase 4 zoom seam): scale-1.0 run;
    /// the caller owns the result and must DROP it after use — nothing here
    /// retains FULL planes (the 1.55GB@100MP input/output pair is left to
    /// the cache's eviction; 02-06 owns the session-level budget sweep).
    /// NEVER called from param-change paths.
    func requestFull() async throws -> any MTLTexture {
        guard let decoded, let metal else {
            throw AppError.decodeFailed("requestFull: no image loaded")
        }
        let (texture, _) = try await RenderPipeline.process(
            image: decoded,
            instances: instances,
            imageID: currentImageID ?? UUID(),
            resolution: .full,
            cache: cache,
            metal: metal,
            longEdge: nil // FULL: scale 1.0, full extent
        )
        return texture
    }

    // ── The single PREVIEW render path (D-X1 producer) ───────────────────

    private func renderPreview(bucket: Int, generation gen: Int) async {
        guard let decoded, let metal else { return }
        do {
            let (texture, stats) = try await RenderPipeline.process(
                image: decoded,
                instances: instances,
                imageID: currentImageID ?? UUID(),
                resolution: .preview,
                cache: cache,
                metal: metal,
                longEdge: bucket
            )
            guard gen == generation else {
                Self.logger.debug("PREVIEW render superseded — dropping stale frame")
                return
            }
            editorState?.displayTexture = texture
            Self.logger.info(
                "pixelpipe output ready: PREVIEW bucket \(bucket, privacy: .public)px (\(stats.hits, privacy: .public) hits / \(stats.misses, privacy: .public) misses, \(stats.planesRendered, privacy: .public) planes)"
            )
        } catch {
            // UI-SPEC severity: render failures log; they never clear the
            // decode state or block the editor.
            Self.logger.error(
                "PREVIEW render failed (bucket \(bucket, privacy: .public)px): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
