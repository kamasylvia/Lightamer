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

    // ── 06-05 layer dimension (composite routing + persistence) ─────────

    /// The live layer stack MIRROR (EditorState owns it; this copy feeds
    /// the render branch). nil/empty = the flat legacy path (exact Phase
    /// 2-5 key space); non-empty adjustment layers = the composite.
    private var currentLayerStack: LayerStack?

    /// The layer currently under edit (the D-06-CONTEXT-8 hot layer: its
    /// chain output survives the FULL cold-layer sweep). Driven by the UI
    /// layer selection; nil = no hot layer.
    private(set) var currentHotLayerID: UUID?

    /// The ORIGINAL image URL of the current session — the masks directory
    /// anchor (`<original>.lra.masks/`) for raster-mask loading.
    private var currentImageURL: URL?

    /// The UI-facing hot-layer setter (the LayersPanel selection drives
    /// this through the session; additive, idempotent).
    func setHotLayer(_ layerID: UUID?) {
        currentHotLayerID = layerID
    }

    /// 「显示蒙版」request (the LayersPanel eye-on-mask toggle): tint the
    /// DISPLAY plane with the selected layer's mask after each composite
    /// (the 06-3 `mask_overlay_display` leg on real user state — the
    /// 06-03 `-la_mask_overlay_probe` DEBUG probe becomes the production
    /// path here). nil = no overlay. 13-3 T5: the tuple carries the
    /// display STYLE (translucent/rubylith/on-black) — a display-leg
    /// parameter only, never a record.
    var maskOverlayRequest: (layerID: UUID, strength: Float, style: MaskOverlayStyle)?

    func setMaskOverlayRequest(_ request: (layerID: UUID, strength: Float, style: MaskOverlayStyle)?) {
        maskOverlayRequest = request
        // The tint lives INSIDE renderPreview — a request change must
        // re-render or the toggle/selection would not visibly update
        // (GUI-15, found in the 06-05 GUI round).
        Task { [weak self] in
            guard let self, self.decoded != nil else { return }
            await self.renderPreview(
                bucket: self.currentBucket ?? PreviewBucket.cap, generation: self.generation)
        }
    }

    /// Unwrap-or-throw for the overlay helper's precondition ladders
    /// (every exit throws — `base` is never returned after a send).
    private func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw AppError.decodeFailed(message) }
        return value
    }

    /// Tint the freshly rendered display with the requested layer's mask
    /// plane (best effort — a failure logs and leaves the plain display).
    /// v1 geometry note (mirrors D-06-06-T4-2): the mapper is rebuilt from
    /// the display frame, so upstream frame-changing geometry may misalign
    /// the tint — the content-anchored integration is a single follow-up
    /// (same seam the liquify overlay documents).
    ///
    /// 07-3 T1: drawn specs ride the drawn rasterizer (unchanged);
    /// parametric/raster payloads fall back to `MaskCombiner.effectivePlane`
    /// (the SAME assembly the composite uses — the tint IS the effective
    /// mask, not an approximation). `base` is passed as both blendif
    /// sampling planes (the parametric leg samples the real image).
    ///
    /// MainActor + plain params: the display plane and the returned plane
    /// live in the coordinator's isolation domain end-to-end (MTLTexture
    /// is Sendable per `MetalSendability`), so no `sending` choreography.
    private func applyMaskOverlayIfRequested(
        base: sending any MTLTexture,
        request: (layerID: UUID, strength: Float, style: MaskOverlayStyle)?,
        stack: LayerStack?,
        boxes: [any ModuleBoxing],
        imageID: UUID,
        imageURL: URL?,
        metal: MetalContext
    ) async throws -> any MTLTexture {
        // PRECONDITION (caller-checked): request.layerID is in the stack,
        // its mask has SOME payload. `base` is NEVER used on any path after
        // the caller hands it over (the 06-3 probe pattern — every exit is
        // a throw or the overlay's own sending return).
        let request = try unwrap(request, "mask overlay: no request")
        let stack = try unwrap(stack, "mask overlay: no layer stack")
        let layer = try unwrap(
            stack.compositeLayers.first { $0.id == request.layerID },
            "mask overlay: layer vanished")
        let mask = try unwrap(layer.mask, "mask overlay: no mask")
        let window = ROI(
            x: 0, y: 0, width: base.width, height: base.height, scale: 1.0)
        let mapper = GeometryPointMapper.compose(
            boxes: boxes,
            frameSize: SIMD2(Double(base.width), Double(base.height)))
        let plane: any MTLTexture
        if let drawn = try await DrawnMaskRasterizer.planeIfDrawn(
            spec: mask, layerOpacity: layer.opacity, window: window,
            mapper: mapper, metal: metal, cache: cache,
            imageID: imageID, pipeType: .preview, layerID: layer.id)
        {
            plane = drawn
        } else {
            // The raster/parametric fallback — the effective-plane
            // assembly (mask-store load + invert + intersect joins).
            let assembled = try await MaskCombiner.effectivePlane(
                spec: mask, layerOpacity: layer.opacity, window: window,
                below: base, top: base, mapper: mapper, metal: metal,
                cache: cache, imageID: imageID, pipeType: .preview,
                layerID: layer.id,
                maskDirectory: imageURL.map {
                    RasterMaskStore.masksDirectory(forImageURL: $0)
                })
            plane = assembled.plane
        }
        // 13-3 T5: the three display states — SAME overlay kernel, three
        // parameterizations (L031 holds: no new GPU face):
        //   translucent — the 06-3 legacy yellow scrim at the request
        //                 strength;
        //   rubylith    — the classic red scrim, slightly lighter;
        //   onBlack     — the dt inspection form: the mask WHITE on a
        //                 BLACK full-frame plane (the black plane is a
        //                 CPU-zeroed `.shared` texture — zero GPU submit).
        switch request.style {
        case .translucent:
            return try await DrawnMaskRasterizer.overlay(
                display: base, mask: plane, strength: request.strength,
                tint: SIMD3<Float>(1, 1, 0), metal: metal)
        case .rubylith:
            return try await DrawnMaskRasterizer.overlay(
                display: base, mask: plane, strength: 0.6,
                tint: SIMD3<Float>(1, 0.05, 0.1), metal: metal)
        case .onBlack:
            // The unchecked-Sendable box is the established ownership
            // seam here (the same pattern as the probe call site — the
            // plane is render-current and read-only from here on).
            let black = SendableTextureBox(
                texture: try Self.makeZeroedPlane(
                    matching: base, device: metal.device))
            return try await DrawnMaskRasterizer.overlay(
                display: black.texture, mask: plane, strength: 1.0,
                tint: SIMD3<Float>(1, 1, 1), metal: metal)
        }
    }

    /// A zero-filled plane with the display's size/format (the on-black
    /// style's backdrop). `.shared` storage written through `replace` —
    /// a CPU memset, NOT a GPU command (the L031 red line holds).
    private static func makeZeroedPlane(
        matching display: any MTLTexture, device: any MTLDevice
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: display.pixelFormat, width: display.width,
            height: display.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(
                display.width * display.height * 4)
        }
        let bytesPerRow = display.width * 4
        let row = Data(repeating: 0, count: bytesPerRow)
        try row.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            texture.replace(
                region: MTLRegionMake2D(0, 0, display.width, display.height),
                mipmapLevel: 0, withBytes: raw.baseAddress!,
                bytesPerRow: bytesPerRow)
        }
        return texture
    }

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

    // ── 13-2 T2: soft proof (COLOR-02) — the display-leg runtime override ──

    /// The coordinator-minted proof box. NOT a registry module: it never
    /// enters `EditorState.instances` (no history item, no sidecar record,
    /// no export chain) — it is INJECTED into the rendered chain only while
    /// proof is ON (the zero-regression red line: proof OFF renders a chain
    /// byte-identical to the pre-13-2 pipeline).
    private var softProofBox: ModuleBox<SoftProofStage>?

    /// The live soft-proof state (nil = proof OFF). Coordinator-level
    /// per-run override — never persisted, never part of history (the
    /// `SoftProofProfile` doc comment is the contract).
    private(set) var softProofProfile: SoftProofProfile?

    /// Set/clear the soft proof and re-render the display leg. THUMBNAIL is
    /// deliberately NOT dirtied (browser thumbnails do not simulate print —
    /// 13-2-DECISIONS); the PREVIEW re-render rides the proof box's hash
    /// fold, so upstream cache planes survive the toggle.
    func setSoftProof(_ profile: SoftProofProfile?) {
        softProofProfile = profile
        guard decoded != nil else { return }
        generation += 1
        Task { [weak self] in
            guard let self else { return }
            await self.renderPreview(
                bucket: self.currentBucket ?? PreviewBucket.cap, generation: self.generation)
        }
    }

    /// Mint-or-reparameterize the proof box for `profile` (idempotent: the
    /// SAME profile keeps the committed hash — cache-neutral).
    private func mintSoftProofBox(_ profile: SoftProofProfile) -> ModuleBox<SoftProofStage> {
        if let box = softProofBox {
            if box.module.softProofOverride != profile {
                box.module.softProofOverride = profile
                box.setParams(SoftProofStage.Params())
            }
            return box
        }
        let box = ModuleBox(module: SoftProofStage())
        box.module.softProofOverride = profile
        box.setParams(SoftProofStage.Params())
        softProofBox = box
        return box
    }

    /// The proof-injected chain: the proof box rides UPSTREAM of colorout
    /// (iop 69.5 < 70.0 — the v50 sort and the composite driver's
    /// `splitTerminal` floor both place it in the base chain). Display legs
    /// only (PREVIEW + FULL); THUMBNAIL never simulates print.
    private func chainWithSoftProof(
        _ base: [any ModuleBoxing], resolution: PipeResolution
    ) -> [any ModuleBoxing] {
        guard resolution != .thumbnail, let profile = softProofProfile, !base.isEmpty else {
            return base
        }
        let box = mintSoftProofBox(profile)
        var chain = base
        if let coloroutIdx = base.firstIndex(where: { $0.opName == ColorOutModule.opName }) {
            chain.insert(box, at: coloroutIdx)
        } else {
            chain.append(box)
        }
        return chain
    }

    /// The yiyin logo store (08-3 T3 wiring): the embedded 26-brand PDF
    /// raster cache + user uploads, ONE per coordinator. Its init scans
    /// the user directory once (a handful of files at most).
    private let yiyinLogoStore = YiyinLogoStore()

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
    ///
    /// 13-2 T6: the resolution honors the MANUAL per-display override
    /// (`ManualDisplayOverrideStore`) — a hand-picked ICC wins over the
    /// auto matching table for THIS display only.
    private func displayDidChange(initial: Bool = false) async {
        let profile = resolvedDisplayProfile()
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
        recommitColoroutForDisplay()
        // Re-render the visible pipe (upstream cache planes survive).
        guard decoded != nil else { return }
        generation += 1
        thumbnailNeedsRender = true
        await renderPreview(
            bucket: currentBucket ?? PreviewBucket.cap, generation: generation
        )
    }

    /// The effective display profile for the WINDOW's screen: the manual
    /// override (Settings, 13-2 T6) wins; the standard matching table is
    /// the default. The single resolution point the screen follow + the
    /// re-commits + the override renders all share.
    private func resolvedDisplayProfile() -> DisplayProfile {
        let screen = window?.screen ?? NSScreen.main
        return ManualDisplayOverrideStore.shared.resolvedProfile(screen: screen)
    }

    /// The Settings-side refresh (13-2 T6): an override was set/cleared —
    /// forget the folded identity and re-run the resolution (idempotent
    /// when nothing changed).
    func refreshDisplayProfile() {
        displayStableID = nil
        Task { await displayDidChange() }
    }

    /// Adopt a chain for rendering: explicit instances win; empty → the
    /// history-owned instance set (02-05). Captures the typed colorout
    /// box and commits its params for the CURRENT display.
    private func adoptChain(_ explicit: [any ModuleBoxing]) async
        -> [any ModuleBoxing]
    {
        if !explicit.isEmpty {
            captureColoroutBox(from: explicit)
            recommitColoroutForDisplay()
            return explicit
        }
        guard let registry else { return [] }
        let chain = await registry.makeDefaultChain()
        captureColoroutBox(from: chain)
        recommitColoroutForDisplay()
        return chain
    }

    /// Re-commit colorout's params for the CURRENT display (folds the
    /// resolved `DisplayProfile.stableID` into the committed piece hash —
    /// D-COL2's terminal-segment invalidation atom). ENVIRONMENT identity:
    /// deliberately NOT part of history records; `rematerializeInstances`
    /// re-folds after every canonical re-apply so a history navigation
    /// never drops the live display follow.
    private func recommitColoroutForDisplay() {
        guard let box = coloroutBox else { return }
        let profile = resolvedDisplayProfile()
        box.module.displayProfileOverride = profile
        let params = (try? JSONDecoder().decode(
            ColorOutModule.Params.self, from: box.paramsData
        )) ?? ColorOutModule.Params()
        box.setParams(params)
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
        currentImageURL = url // the 06-05 masks-directory anchor
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
        currentLayerStack = editorState?.layerStack // fresh or restored stack
        if currentHotLayerID != nil,
           currentLayerStack?.compositeLayers.contains(where: { $0.id == currentHotLayerID }) != true {
            currentHotLayerID = nil // the new image's stack has no such layer
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

        // 06-05 layer dimension: the unknown-op degrade pass over the
        // LAYER chains (whole layer flips enabled=false — the 06-1 T6
        // mechanism), then the decoded records install as the live stack.
        // A v1 document (layerStack nil) installs the EMPTY stack.
        let (layerRecord, layerUnknownOps) = await document
            .degradedLayerStack(registry: registry)
        for op in layerUnknownOps {
            Self.logger.error(
                "sidecar \(url.lastPathComponent, privacy: .public): layer chain unknown op '\(op, privacy: .public)' — layer kept disabled, params preserved"
            )
        }
        editorState?.installLayerStack(from: layerRecord?.runtimeLayers ?? [])
        currentLayerStack = editorState?.layerStack
    }

    /// The current session as a persistable document (history + live
    /// records + decode stamps + the current imageID + the 06-05 LAYER
    /// STACK record). nil = nothing to persist yet (no decode / no
    /// imageID). The layer record carries the LIVE effective chains (the
    /// structure-snapshot state merged with the layerScope items — the
    /// rebuild invariant holds: layer state = document record ⊕ history
    /// items, and the live stack already IS that merged state). Empty
    /// stacks persist `nil` (the v1 document shape, zero drift impact).
    private func makeSidecarDocument() -> LightamerSidecar? {
        guard let decoded, let editorState, let imageID = currentImageID else {
            return nil
        }
        let decodeHash = HistoryHash.decodeParamsHash(for: decoded)
        let stackRecord: SidecarLayerStackRecord? =
            editorState.layerStack.map { SidecarLayerStackRecord($0) }
            .flatMap { $0.layers.isEmpty ? nil : $0 }
        return LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: decoded.decoderVersionUsed.rawValue,
            decodeParamsHash: decodeHash,
            instances: editorState.instances,
            history: editorState.history,
            historyHash: HistoryHash.hash(
                stack: editorState.history, decodeParamsHash: decodeHash,
                layerSnapshot: stackRecord?.snapshot),
            appVersion: LightamerSidecar.currentAppVersion,
            layerStack: stackRecord
        )
    }

    /// D-S3: every committed history MOVE throttles a `.lra` write (2s
    /// merge). Live preview ticks (`setLiveParams`) deliberately do NOT
    /// schedule — the file must always satisfy the rebuild-from-history
    /// invariant, and uncommitted drag state is not history.
    // ── Session switch (Plan 09-01 T1; the documented Phase 9 hook at the
    // D-C2 sweep site, `load(...)`'s "session SWITCH also calls
    // cache.invalidateAll() + this sweep" comment) ──

    /// Test-visible invocation count (`SessionSwitchTests` leak assertion —
    /// the invalidateAll spy; the thumbnail-LRU seam lands with the 9-3
    /// provider and this counter pins the teardown CALL until then).
    private(set) var sessionSwitchPrepCount = 0

    /// Session-switch teardown leg: purge EVERY cached plane (no keep
    /// policy — the whole session is going away) + the CI/RawCamera
    /// internal caches. The D-C2 budget sweep is subsumed — invalidateAll
    /// drains every plane, so a KeepingPolicy pass would early-return on
    /// the empty cache. Idempotent.
    func prepareForSessionSwitch() async {
        sessionSwitchPrepCount += 1
        await cache.invalidateAll()
        if let metal {
            await metal.clearCICaches()
        }
    }

    /// Test seam: the PipeCache byte total (`SessionSwitchTests` asserts
    /// == 0 after a switch).
    var totalBytesForTesting: Int {
        get async { await cache.totalBytes }
    }

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
        currentLayerStack = editorState?.layerStack // undo/redo move the stack too
        await rematerializeInstances()
        generation += 1
        thumbnailNeedsRender = true
        await renderPreview(
            bucket: currentBucket ?? PreviewBucket.cap, generation: generation
        )
    }

    /// 08-3 dual-instance face: the CURRENT global-chain record for
    /// `opName` — the yiyin panel's sibling lookup (the watermark section
    /// drives the borders record and vice versa; both sections commit
    /// THEIR OWN instance through the shared session). nil = the op has no
    /// record in the current chain (old sidecar restore without it — the
    /// panel then offers the manual mint face).
    func instanceRecord(opName: String) -> ModuleInstance? {
        editorState?.instances.first { $0.opName == opName }
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
    ///
    /// Concurrency (GUI-10/GUI-13 fix, 2026-09-23): `ModuleBox.apply`/
    /// `setParams` are SYNC (pure CPU), and the registry lookups below are
    /// hoisted into a pre-pass — the mutation loop contains NO suspension
    /// point, so this whole pass runs MainActor-atomically. The two
    /// history-triggering chains (the commit leg `EditorState.recordChange
    /// → historyDidChange` and the live leg `InspectorEditSession.update →
    /// setLiveParams → historyDidChange`, both fire-and-forget Tasks) can
    /// therefore no longer interleave INSIDE a box mutation — the old
    /// nonisolated-async `apply` let the MainActor hop away mid-apply and
    /// two cooperative-pool threads wrote the same box's `paramsData`/
    /// `committedPiece` concurrently (Data over-release → SIGSEGV/
    /// SIGABRT, forensics `.work/gui-acceptance/gui10-forensics.md`).
    /// A later pass re-applies over an earlier one idempotently (sync
    /// apply + byte-identical fast path); a duplicate fresh box from two
    /// interleaved pre-passes is benign (same UUID, last `instances`
    /// write wins, the discarded box is never shared).
    private func rematerializeInstances() async {
        guard let editorState else { return }
        let records = editorState.instances
        // Pre-pass: resolve fresh boxes for unknown records (the ONLY
        // suspension points) before the mutation loop below.
        var freshBoxes: [UUID: any ModuleBoxing] = [:]
        var unknownOps: [UUID: String] = [:]
        for record in records
        where !instances.contains(where: { $0.instanceID == record.id }) {
            if let fresh = await registry?.makeBox(
                opName: record.opName, instanceID: record.id
            ) {
                freshBoxes[record.id] = fresh
            } else {
                unknownOps[record.id] = record.opName
            }
        }
        // Mutation loop: NO awaits — MainActor-atomic (see concurrency
        // note above). Do not reintroduce suspension points here.
        var boxes: [any ModuleBoxing] = []
        boxes.reserveCapacity(records.count)
        for record in records {
            if let existing = instances.first(where: { $0.instanceID == record.id }) {
                do {
                    try existing.apply(record)
                    boxes.append(existing)
                } catch {
                    Self.logger.error(
                        "instance \(record.opName, privacy: .public) re-apply failed: \(error.localizedDescription, privacy: .public)"
                    )
                    boxes.append(existing) // keep last-good committed state
                }
            } else if let fresh = freshBoxes[record.id] {
                do {
                    try fresh.apply(record)
                } catch {
                    Self.logger.error(
                        "instance \(record.opName, privacy: .public) apply failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                boxes.append(fresh)
            } else {
                Self.logger.error(
                    "no registered module for op '\(unknownOps[record.id] ?? record.opName, privacy: .public)' — record skipped"
                )
            }
        }
        instances = boxes
        captureColoroutBox(from: boxes)
        recommitColoroutForDisplay()
    }

    // ── 06-05 layer dimension (render branch + history/undo funnel) ─────

    /// THE layer-event path: EditorState's layer mutators (structure
    /// commits, live property/mask ticks, undo/redo of layer items) land
    /// here — refresh the stack mirror, re-render (the composite branch
    /// picks the driver when adjustment layers exist), and optionally
    /// schedule the sidecar write (live ticks pass persist=false; the
    /// D-S3 rule: uncommitted state never hits disk).
    func layerStackDidChange(persist: Bool = true) async {
        guard decoded != nil else { return }
        currentLayerStack = editorState?.layerStack
        await historyDidChange()
        if persist { scheduleSidecarWrite() }
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
    /// `layerID` non-nil (06-05): the tick targets a LAYER chain record
    /// instead of the global set (the `layerScope`-型 live leg). The
    /// snapshot still rides `liveEdited` so the commit leg finds it.
    func setLiveParams(_ snapshot: ModuleInstance, layerID: UUID? = nil) async {
        guard let editorState else { return }
        if isEditingContinuous {
            liveEdited[snapshot.id] = snapshot
        }
        if let layerID {
            editorState.applyLiveLayerInstance(snapshot, layerID: layerID)
            await historyDidChange()
            return
        }
        editorState.applyLiveInstance(snapshot)
        await historyDidChange()
    }

    /// D-H1 drag END: commit the touched live snapshots as history —
    /// exactly ONE `HistoryItem` per touched instance (one for every
    /// slider interaction). The pipes already rendered the live state, so
    /// the notification-driven `historyDidChange` pass is idempotent
    /// (cache hits end-to-end) — no second render is issued here.
    /// `layerScope` non-nil (06-05): the commit lands as a LAYER-SCOPED
    /// item (one per touched record) and the live leg's records upsert
    /// into that layer's chain (`EditorState.recordLayerChange`).
    func commitContinuousEdit(
        label: String, autoEnable: Bool = true, layerScope: UUID? = nil
    ) async {
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
            if let layerScope {
                editorState?.recordLayerChange(
                    effective, layerID: layerScope, label: label)
            } else {
                editorState?.recordChange(effective, label: label)
            }
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

    /// 09-04 HIST-05: a PASTE landed on the current image (the live leg).
    /// The same committed-move shape as undo/redo: re-render + persist.
    func pasteDidChange() async {
        guard decoded != nil else { return }
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
    /// 13-3 T1: `transform` non-nil = the click inverse-maps through the
    /// zoom/pan/rotation state (the eyedropper stays correct while zoomed).
    func pickColor(
        at point: CGPoint, viewportSize: CGSize,
        transform: ViewportTransform? = nil
    ) async -> simd_float3? {
        guard let decoded, let metal, let display = editorState?.displayTexture else {
            return nil
        }
        let texSize = SIMD2<Int>(display.width, display.height)
        guard let uv = Self.viewportUV(
            at: point, viewportSize: viewportSize, textureSize: texSize,
            transform: transform
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

    /// The Metal context for the AI mask bake channel (07-3 T3 — the
    /// SkinSmoothPanel「定位皮肤」bake rides the same context the pipes
    /// use). Read-only additive seam (the detectionSourceImage twin).
    func detectionMetal() -> MetalContext? {
        metal
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
    /// the letterbox (outside the fitted image rect). 13-3 T1: `transform`
    /// non-nil inverse-maps through the zoom/pan/rotation state FIRST
    /// (the same `ViewportFit` math — no second formula; nil = outside
    /// the transformed image content).
    nonisolated static func viewportUV(
        at point: CGPoint, viewportSize: CGSize, textureSize: SIMD2<Int>,
        transform: ViewportTransform? = nil
    ) -> SIMD2<Double>? {
        // 04-02-T4: single-source math (ViewportFit); the guard + letterbox
        // semantics are unchanged (EyedropperTests pin them).
        ViewportFit.uv(
            at: point, viewportSize: viewportSize,
            textureSize: CGSize(width: textureSize.x, height: textureSize.y),
            transform: transform)
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
            let rendered = try await renderCurrentChain(
                bucket: nil, resolution: .thumbnail)
            thumbnailNeedsRender = false
            let texture = rendered.texture
            let stats = rendered.stats
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
        let rendered = try await renderCurrentChain(bucket: nil, resolution: .full)
        return rendered.texture
    }

    // ── The single PREVIEW render path (D-X1 producer) ───────────────────

    #if DEBUG
    /// Plan 06-03 T7 GUI probe (`-la_mask_overlay_probe`): tints the display
    /// plane yellow where a seeded adjustment layer's drawn mask is set —
    /// the 6-3 render leg of the「显示蒙版」state (the UI toggle + selected-
    /// layer routing land in 6-5). Read-only with respect to user state:
    /// the probe layer lives in a static (never in EditorState.layerStack).
    nonisolated static let maskOverlayProbeArmed = ProcessInfo.processInfo
        .arguments.contains("-la_mask_overlay_probe")

    private static let maskOverlayProbeLayerID = UUID(
        uuidString: "06030603-0603-0603-0603-060306030603")!
    private static let maskOverlayProbeSpec = MaskSpec(drawn: DrawnMaskSpec(forms: [
        MaskForm(kind: .brush(BrushStroke(
            points: [
                BrushPoint(
                    corner: MaskPoint(x: 0.35, y: 0.45),
                    ctrl1: MaskPoint(x: 0.42, y: 0.35),
                    ctrl2: MaskPoint(x: 0.5, y: 0.45)),
                BrushPoint(
                    corner: MaskPoint(x: 0.65, y: 0.55),
                    ctrl1: MaskPoint(x: 0.58, y: 0.65),
                    ctrl2: MaskPoint(x: 0.5, y: 0.55)),
            ],
            radius: 0.09, hardness: 0.7, density: 1.0, opacity: 1.0))),
    ]))

    /// Tint the PREVIEW display plane with the probe mask (bgra8 display
    /// order: (0,1,1) = yellow on screen).
    nonisolated private func applyMaskOverlayProbe(
        base: sending any MTLTexture, metal: MetalContext, cache: PipeCache
    ) async throws -> sending any MTLTexture {
        // The probe runs identity geometry (the default chain carries no
        // geometric module) at the display plane's own frame — the mask
        // coordinate system IS the display frame here.
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(base.width), Double(base.height)))
        let maskPlane = try await DrawnMaskRasterizer.plane(
            spec: Self.maskOverlayProbeSpec, layerOpacity: 1.0,
            window: ROI(x: 0, y: 0, width: base.width, height: base.height, scale: 1.0),
            mapper: mapper, metal: metal, cache: cache,
            imageID: currentImageID ?? UUID(), pipeType: .preview,
            layerID: Self.maskOverlayProbeLayerID).plane
        return try await DrawnMaskRasterizer.overlay(
            display: base, mask: maskPlane, strength: 0.85,
            tint: SIMD3<Float>(1, 1, 0), metal: metal) // shader RGB (bgra8 reads RGBA-ordered) = yellow
    }
    #endif

    private func renderPreview(bucket: Int, generation gen: Int) async {
        guard let decoded, let metal else { return }
        do {
            let rendered = try await renderCurrentChain(bucket: bucket)
            let texture = rendered.texture
            let stats = rendered.stats
            guard gen == generation else {
                Self.logger.debug("PREVIEW render superseded — dropping stale frame")
                return
            }
            #if DEBUG
            if Self.maskOverlayProbeArmed {
                // Re-anchor the plane's region through an unchecked-Sendable
                // box (same ownership contract as MetalSendability — the
                // plane is render-current, read-only from here on).
                let box = SendableTextureBox(texture: texture)
                let overlaid = try await applyMaskOverlayProbe(
                    base: box.texture, metal: metal, cache: cache)
                editorState?.displayTexture = overlaid
                Self.logger.info("mask overlay probe applied (06-03 T7)")
                return
            }
            #endif
            if let request = maskOverlayRequest,
               let stack = currentLayerStack,
               let layer = stack.compositeLayers.first(where: { $0.id == request.layerID }),
               // 07-3 T1: ANY payload tints (was drawn-only) — the AI
               // masks are RASTER payloads and the「显示蒙版」affordance
               // must work for them (the T4 GUI ΔR quantification rides
               // this leg).
               layer.mask?.hasAnyPayload == true {
                // The「显示蒙版」tint rides the newest-wins gate above — a
                // superseded frame never pays the overlay pass.
                let overlaid: any MTLTexture
                do {
                    overlaid = try await applyMaskOverlayIfRequested(
                        base: texture, request: request,
                        stack: currentLayerStack, boxes: instances,
                        imageID: currentImageID ?? UUID(),
                        imageURL: currentImageURL, metal: metal)
                } catch {
                    Self.logger.error(
                        "mask overlay failed: \(error.localizedDescription, privacy: .public)")
                    overlaid = texture
                }
                editorState?.displayTexture = overlaid
            } else {
                editorState?.displayTexture = texture
            }
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

    /// The chain runner shared by PREVIEW/THUMBNAIL/FULL (06-05): stacks
    /// WITH adjustment layers route through the `LayerCompositeDriver`
    /// composite (`RenderPipeline.processComposite`); the flat legacy
    /// path (`process`) is preserved BYTE-EXACTLY for stacks without
    /// adjustment layers (the Phase 2-5 key space + behavior).
    private func renderCurrentChain(
        bucket: Int?, resolution: PipeResolution = .preview
    ) async throws -> RenderChainOutput {
        guard let decoded, let metal else {
            throw AppError.decodeFailed("renderCurrentChain: no image loaded")
        }
        let longEdge: Int?
        if resolution == .preview {
            longEdge = bucket ?? currentBucket ?? PreviewBucket.cap
        } else {
            longEdge = bucket // THUMBNAIL: nil (360 default); FULL: nil
        }
        // 08-3 T3: the yiyin per-run context rides the run's entry scale
        // (joint layout / EXIF / logo faces — per-run DATA, never params).
        injectYiyinRunContext(longEdge: longEdge, resolution: resolution)
        // 13-2 T2: the soft-proof box rides the DISPLAY legs only — proof
        // OFF leaves `instances` untouched (byte-identical chain).
        let chain = chainWithSoftProof(instances, resolution: resolution)
        if let stack = currentLayerStack, !stack.compositeLayers.isEmpty,
           let registry {
            let (texture, stats) = try await RenderPipeline.processComposite(
                image: decoded,
                instances: chain,
                layerStack: stack,
                registry: registry,
                imageID: currentImageID ?? UUID(),
                resolution: resolution,
                cache: cache,
                metal: metal,
                longEdge: longEdge,
                roiHint: nil,
                policy: resolution == .full
                    ? .fullColdLayer : .preview,
                hotLayerID: currentHotLayerID,
                maskDirectory: currentImageURL.map {
                    RasterMaskStore.masksDirectory(forImageURL: $0)
                })
            return RenderChainOutput(texture: texture, stats: stats)
        }
        let (texture, stats) = try await RenderPipeline.process(
            image: decoded,
            instances: chain,
            imageID: currentImageID ?? UUID(),
            resolution: resolution,
            cache: cache,
            metal: metal,
            longEdge: longEdge
        )
        return RenderChainOutput(texture: texture, stats: stats)
    }

    // ── 09-04 T6 (HIST-06): render-with-instances override + the
    // before/after planes ─────────────────────────────────────────────────

    /// The OVERRIDE render variant: run the pipe against EXPLICIT records
    /// WITHOUT touching the live state machine — no position move, no
    /// history item, no box mutation, no `displayTexture` push (the
    /// before/after planes are consumed by the split blit, never by the
    /// live path). The default chain runners above are UNTOUCHED — their
    /// byte semantics are the Phase 2-8 contract (the regression suite +
    /// `BeforeAfterTests` pin the independence).
    ///
    /// Cache keys derive from the RECORDS' paramsHash chain, so the
    /// pristine plane (seed records) and any peek(k) plane land on their
    /// OWN `upstreamHash` lines — zero schema change, planes stay resident
    /// under the current image's namespace (D-C1 keep policy applies).
    ///
    /// - Parameters:
    ///   - instances: the records to render (the pristine seed, or a
    ///     `projectedState(at:)` projection).
    ///   - layerStack: the layer stack to composite (nil = the flat path,
    ///     preserving the legacy key space for layer-less projections).
    ///   - bucket: the PREVIEW bucket (nil = the current bucket).
    func renderPreview(
        instances overrideRecords: [ModuleInstance],
        layerStack: LayerStack?,
        bucket: Int? = nil
    ) async throws -> RenderChainOutput {
        overrideRenderCount += 1
        guard let decoded, let metal else {
            throw AppError.decodeFailed("renderPreview(override): no image loaded")
        }
        let imageID = currentImageID ?? UUID()
        let longEdge = bucket ?? currentBucket ?? PreviewBucket.cap
        guard let registry else {
            throw AppError.decodeFailed("renderPreview(override): no registry")
        }
        let (boxes, _) = await registry.materializeBoxes(for: overrideRecords)
        // The display fold rides the override's colorout too — WITHOUT
        // capturing it as the live chain's box (the live follow state is
        // never mutated by an override render).
        if let colorout = boxes.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            colorout.module.displayProfileOverride = resolvedDisplayProfile()
            let params = (try? JSONDecoder().decode(
                ColorOutModule.Params.self, from: colorout.paramsData))
                ?? ColorOutModule.Params()
            colorout.setParams(params)
        }
        if let layerStack, !layerStack.compositeLayers.isEmpty {
            let (texture, stats) = try await RenderPipeline.processComposite(
                image: decoded,
                instances: boxes,
                layerStack: layerStack,
                registry: registry,
                imageID: imageID,
                resolution: .preview,
                cache: cache,
                metal: metal,
                longEdge: longEdge,
                roiHint: nil,
                policy: .preview,
                hotLayerID: nil,
                maskDirectory: currentImageURL.map {
                    RasterMaskStore.masksDirectory(forImageURL: $0)
                })
            return RenderChainOutput(texture: texture, stats: stats)
        }
        let (texture, stats) = try await RenderPipeline.process(
            image: decoded,
            instances: boxes,
            imageID: imageID,
            resolution: .preview,
            cache: cache,
            metal: metal,
            longEdge: longEdge
        )
        return RenderChainOutput(texture: texture, stats: stats)
    }

    /// The override-render counter (the T7 render-count assertion face:
    /// the hold fast path must NOT move it).
    private(set) var overrideRenderCount = 0

    /// The BEFORE plane: the image's PRISTINE chain (the seed instance set,
    /// flat) — rendered once on first entry into a before/after mode and
    /// resident in the plane cache afterwards (the key's upstreamHash is
    /// the seed chain's — a pristine image shares the live plane, which is
    /// exactly right: before == current when nothing is edited).
    func renderPristinePlane() async throws -> any MTLTexture {
        guard let editorState else {
            throw AppError.decodeFailed("pristine plane: no editor state")
        }
        let rendered = try await renderPreview(
            instances: editorState.pristineSeedRecords, layerStack: nil)
        return rendered.texture
    }

    /// The PEEK plane: a NON-mutating projection of history point `index`
    /// (the snapshot-point comparison). Never moves the pointer, never
    /// creates a history item (D-H1 orthogonality — asserted in tests).
    func renderHistoryPeekPlane(at index: Int) async throws -> any MTLTexture {
        guard let editorState else {
            throw AppError.decodeFailed("peek plane: no editor state")
        }
        let (records, snapshot) = editorState.history.projectedState(at: index)
        var stack: LayerStack?
        if let snapshot {
            var rebuilt = LayerStack(
                baseLayer: editorState.layerStack?.baseLayer ?? BackgroundLayer())
            for layer in snapshot.makeLayers() { rebuilt.addAdjustment(layer) }
            stack = rebuilt.compositeLayers.isEmpty ? nil : rebuilt
        }
        let rendered = try await renderPreview(
            instances: records, layerStack: stack)
        return rendered.texture
    }

    // ── 08-3 T3: the yiyin per-run context injection (D-08-3-T3-2) ──────

    /// Inject the yiyin terminal-segment PER-RUN DATA into the materialized
    /// boxes before the render: the watermark box receives captureExif /
    /// logo faces / the joint context (mainImageSize ⊕ borders params),
    /// computes the joint layout record (D-08-2-10's division of labor)
    /// and the record rides `BordersModule.jointLayoutOverride` — ONE
    /// computation, two consumers, so borders reserves the text band the
    /// watermark rows actually occupy. Per-run DATA only: nothing here
    /// touches `paramsData`/`paramsHash` (the D-H4 atoms stay record-owned;
    /// L013 — injection is not configuration).
    ///
    /// `mainImageSize` mirrors `PixelPipe.run`'s entry scale exactly
    /// (min(target/long, target/short, 1.0) — downscale-only): the borders
    /// box's `dscIn` for full-frame runs, which is what the record's
    /// `sourceImageSize` guard checks. A mismatched size (ROI-hinted
    /// windowed runs — zoom) degrades gracefully: the borders override is
    /// rejected by its own guard and borders local-computes the empty-rows
    /// layout; the watermark falls back to its input plane.
    private func injectYiyinRunContext(longEdge: Int?, resolution: PipeResolution) {
        guard let decoded else { return }
        guard let watermarkBox = instances.first(where: { $0.opName == WatermarkModule.opName })
            as? ModuleBox<WatermarkModule>
        else { return }
        let bordersRecord = editorState?.instances.first {
            $0.opName == BordersModule.opName
        }
        let bordersParams = try? bordersRecord?.params(of: BordersModule.self)

        // The entry plane size (the borders box's input frame — the same
        // math `PixelPipe.run` performs for the scale-at-entry).
        let fullWidth = max(Int(decoded.ciImage.extent.width), 1)
        let fullHeight = max(Int(decoded.ciImage.extent.height), 1)
        let targetLongEdge = longEdge ?? resolution.defaultLongEdge
        let scale = targetLongEdge.map {
            min(
                CGFloat($0) / CGFloat(fullWidth),
                CGFloat($0) / CGFloat(fullHeight), 1.0)
        }
        let planeW = scale.map { max(1, Int((CGFloat(fullWidth) * $0).rounded())) } ?? fullWidth
        let planeH = scale.map { max(1, Int((CGFloat(fullHeight) * $0).rounded())) } ?? fullHeight

        let watermark = watermarkBox.module
        watermark.captureExif = decoded.capture
        watermark.logoExists = { [yiyinLogoStore] make, variant in
            yiyinLogoStore.embeddedExists(make: make, variant: variant)
        }
        watermark.logoProvider = yiyinLogoStore.provider()
        let context = WatermarkModule.JointContext(
            mainImageSize: SIMD2(planeW, planeH), bordersParams: bordersParams)
        watermark.jointContext = context
        // The joint record → the borders box (nil = no reserve; the
        // borders local layout takes over).
        guard let bordersBox = instances.first(where: { $0.opName == BordersModule.opName })
            as? ModuleBox<BordersModule>
        else { return }
        bordersBox.module.jointLayoutOverride = watermark.makeJointLayoutRecord(
            mainImageSize: SIMD2(planeW, planeH), bordersParams: bordersParams)
    }
}

/// The renderCurrentChain product (a nominal type so the plane's region
/// transfers as a whole to the caller — the probe's `sending` param then
/// accepts it).
struct RenderChainOutput {
    let texture: any MTLTexture
    let stats: RenderPipeline.PipeRunStats
}

/// Region re-anchor for display planes handed to `sending`-param legs
/// (the ownership contract: the plane is fully rendered and treated as
/// immutable from hand-off on — MetalSendability's documented pattern).
private struct SendableTextureBox: @unchecked Sendable {
    let texture: any MTLTexture
}
