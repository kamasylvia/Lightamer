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
/// | `paramsDidChange()`          | re-render NOW    | `needsRender = true` (lazy) | never       |
/// | `drawableDidChange(_:)`      | re-render iff bucket CROSS (D-C3) | —   | never            |
/// | `fetchThumbnail()`           | —                | render iff needsRender | —               |
/// | `requestFull()`              | —                | —                    | render on-demand  |
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
/// - **02-05 history:** `paramsDidChange()` internals are replaced by the
///   history stack's `effectiveInstances()` — the instance set here is
///   swapped wholesale on history navigation instead of mutating in place.
/// - **02-06 clearCaches (D-C1/D-C2):** `load(...)` fires
///   `cache.clearCaches(keeping:)` at its entry (KeepingPolicy consumes
///   `currentImageID` + `previousImageID`, both tracked here), plus a 60s
///   sweep task; the per-URL `imageIDMap` UUIDs persist into sidecars.
/// - **02-04 terminal trio / display profile:** a display-profile change
///   hooks in next to `drawableDidChange` and invalidates ONLY the terminal
///   segment (colorout/gamma) — upstream planes must survive it.
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
        if let box = coloroutBox {
            box.module.displayProfileOverride = profile
            let params = (try? JSONDecoder().decode(
                ColorOutModule.Params.self, from: box.paramsData
            )) ?? ColorOutModule.Params()
            await box.setParams(params)
        }
        // Re-render the visible pipe (upstream cache planes survive).
        guard decoded != nil else { return }
        generation += 1
        thumbnailNeedsRender = true
        await renderPreview(
            bucket: currentBucket ?? PreviewBucket.cap, generation: generation
        )
    }

    /// Adopt a chain for rendering: explicit instances win; empty → the
    /// registry's default chain (terminal trio). Captures the typed
    /// colorout box and commits its params for the CURRENT display.
    private func adoptChain(_ explicit: [any ModuleBoxing]) async
        -> [any ModuleBoxing]
    {
        if !explicit.isEmpty {
            captureColoroutBox(from: explicit)
            return explicit
        }
        guard let registry else { return [] }
        let chain = await registry.makeDefaultChain()
        captureColoroutBox(from: chain)
        if let box = coloroutBox {
            let profile = DisplayProfile.resolve(
                window?.screen?.colorSpace ?? NSScreen.main?.colorSpace
            )
            box.module.displayProfileOverride = profile
            let params = (try? JSONDecoder().decode(
                ColorOutModule.Params.self, from: box.paramsData
            )) ?? ColorOutModule.Params()
            await box.setParams(params)
        }
        return chain
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
        // 02-04: empty instances → the registry's default chain (terminal
        // trio), committed for the CURRENT display. SEAM(02-05): the
        // history stack passes its materialized instance set here instead.
        self.instances = await adoptChain(instances)

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

    /// Params changed (slider drag commit, future history navigation):
    /// PREVIEW re-renders NOW (the interactive workhorse); THUMBNAIL only
    /// marks dirty (lazy — no render until fetched); FULL never auto-renders.
    ///
    /// SEAM(02-05): the history stack replaces `instances` wholesale here
    /// (`effectiveInstances()`) before the re-render.
    func paramsDidChange() async {
        guard decoded != nil else { return }
        generation += 1
        thumbnailNeedsRender = true
        await renderPreview(
            bucket: currentBucket ?? PreviewBucket.cap, generation: generation
        )
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
