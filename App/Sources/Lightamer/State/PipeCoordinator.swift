import AppKit
import Foundation
import LightamerCore
import Metal
import Observation
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
/// - **02-06 clearCaches (D-C1/D-C2):** `load(...)` fires
///   `cache.clearCaches(keeping:)` at its entry (KeepingPolicy consumes
///   `currentImageID` + `previousImageID`, both tracked here), plus a 60s
///   sweep task; the per-URL `imageIDMap` UUIDs persist into sidecars.
/// - **02-06 sidecar:** `historyDidChange()` is where `scheduleWrite()`
///   hooks in (every committed history mutation throttles a `.lra`
///   write), and `load(...)`'s pristine reset is where a sidecar restore
///   lands (decode history + instances from `.lra` instead of seeding
///   defaults).
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
    /// history per image session; a NEW url resets to pristine — 02-06
    /// replaces the reset with the sidecar restore).
    private var historyLoadedURL: URL?

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
            // Explicit chains (tests, 02-06 restore previews) bypass the
            // history-owned instance set — adopt as-is (02-04 behavior).
            self.instances = await adoptChain(instances)
        } else {
            // 02-05: the HISTORY owns the instance set. A NEW url resets
            // EditorState to pristine (default-chain records + empty
            // stack); a same-url reload keeps the session's history.
            // SEAM(02-06): the sidecar restore replaces this reset —
            // decoded history + instances land in EditorState here.
            if historyLoadedURL != url {
                let defaults = await registry?.makeDefaultInstances() ?? []
                editorState?.resetHistoryForNewImage(defaultInstances: defaults)
                historyLoadedURL = url
            }
            await rematerializeInstances()
        }

        previousImageID = currentImageID // D-C1 input for 02-06 (SEAM)
        if let existing = imageIDMap[url] {
            currentImageID = existing
        } else {
            let fresh = UUID()
            imageIDMap[url] = fresh
            currentImageID = fresh
        }
        // SEAM(02-06): the load-entry `cache.clearCaches(keeping:)` fires
        // right here, keyed on currentImageID/previousImageID.

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
    /// SEAM(02-06): the sidecar `scheduleWrite()` hooks right here (every
    /// committed history mutation throttles a `.lra` write).
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
    func commitContinuousEdit(label: String) async {
        isEditingContinuous = false
        let touched = liveEdited.values.sorted {
            ($0.iopOrder, $0.multiPriority, $0.opName)
                < ($1.iopOrder, $1.multiPriority, $1.opName)
        }
        liveEdited.removeAll()
        guard !touched.isEmpty else { return }
        for snapshot in touched {
            editorState?.recordChange(snapshot, label: label)
        }
    }

    /// HIST-02 undo (UI-facing shape; Phase 3 attaches the first panel):
    /// step the stack back via EditorState, then re-materialize + render.
    /// The edited position's plane misses (params reverted); everything
    /// upstream hits — and the REVERTED-TO params' planes usually still
    /// sit in the cache from before the edit.
    func undo() async {
        guard let editorState, editorState.performUndo() else { return }
        await historyDidChange()
    }

    /// HIST-02 redo: into an untruncated tail only.
    func redo() async {
        guard let editorState, editorState.performRedo() else { return }
        await historyDidChange()
    }

    /// HIST-02/D-H3 jump-to-any-point: the stack clamps out-of-range
    /// indices (−1 = pristine); a clamp-only no-op still re-renders
    /// cheaply (all cache hits).
    func jumpToHistory(_ index: Int) async {
        guard let editorState else { return }
        editorState.performJump(to: index)
        await historyDidChange()
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
