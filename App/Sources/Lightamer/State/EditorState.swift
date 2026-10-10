import Foundation
import LightamerCore
import LightamerIOP
import Metal
import Observation
import os

/// Editor-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the currently edited image (URL + `DecodedImage`), the
/// decode/error lifecycle, and the in-flight decode task. Does NOT own the
/// export queue or inspector selection, and holds no references to the other
/// state objects.
@Observable
@MainActor
final class EditorState {

    /// Shared decode-path logger + signpost subsystem/category (D-27/D-31);
    /// passed into `load` so callers own the logging identity.
    nonisolated static let decodeLogger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "decode"
    )

    /// URL of the currently loaded image (nil = empty state, D-11).
    private(set) var loadedImageURL: URL?

    /// The decoded image — RAWDecoder output (D-21). Plan 03's
    /// `EditorMTKView` consumes `image?.ciImage` via `MetalContext`.
    private(set) var image: DecodedImage?

    /// The layer stack for the loaded image (D-03a skeleton — D-03b places
    /// ownership here). Constructed fresh on every successful decode with
    /// a `BackgroundLayer` base (LAYER-01); adjustment layers arrive in
    /// Phase 6. nil = no image loaded.
    private(set) var layerStack: LayerStack?

    /// The pixelpipe output — what `EditorMTKView` blits to the drawable.
    /// The setter is deliberately internal (not `private(set)`): the
    /// `$editorState.displayTexture` binding that `EditorAreaView` derives
    /// via `@Bindable` needs it. SINGLE-PRODUCER invariant (D-X1, Plan
    /// 02-03 shape): ONLY `PipeCoordinator` writes this — its
    /// `renderPreview` is the one render producer; views never trigger
    /// renders (issue #1's race is the view-level-producer anti-pattern).
    var displayTexture: (any MTLTexture)?

    /// True while a decode task is in flight (status bar "Decoding…").
    private(set) var isDecoding: Bool = false

    /// Last decode failure, surfaced as a blocking alert (D-26).
    private(set) var decodeError: AppError?

    /// The in-flight decode task; cancelled when a newer load supersedes it
    /// (D-34: background async decode, cancellable, MainActor UI updates).
    private var decodeTask: Task<Void, Never>?

    // ── 02-06 toast surface (D-26 background grading) ────────────────────

    /// Non-blocking status-bar notice (drift detected / unknown module
    /// disabled / cache freed / sidecar write failed). Background grading:
    /// never steals focus, never blocks — distinct from the blocking
    /// `decodeError` alert. Auto-clears after 4s.
    private(set) var toast: String?

    private var toastClearTask: Task<Void, Never>?

    /// Raise a background toast (D-26). Multiple raises reset the timer.
    func presentToast(_ message: String) {
        toastClearTask?.cancel()
        toast = message
        toastClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// The multi-resolution pipe owner (Plan 02-03-04), attached by the app
    /// root AFTER both `@State` objects exist (the coordinator's display
    /// sink needs this instance; the app root strongly owns BOTH, this is
    /// the single weak back-reference — no retain cycle). The decodeTask
    /// delegates all rendering to it.
    private weak var pipeCoordinator: PipeCoordinator?

    // ── 02-05 history ownership (D-03b: "当前编辑的图像 + 图层栈 + history"
    // live here; the PipeCoordinator CONSUMES the stack) ──────────────────

    /// The non-destructive edit history (HIST-01/02). Value semantics:
    /// `commit/undo/redo/jump` are the only writers, through the `record*`
    /// mutators below (D-H1: one commit per drag-end; D-H2: uncapped).
    /// Phase 2 keeps the stack in memory per image session; 02-06 persists
    /// it verbatim into sidecars (and restores it on load).
    private(set) var history = HistoryStack()

    /// The LIVE instance set — the pipe-facing projection of
    /// `baseInstances ∪ history.effectiveInstances()`, v50-sorted. The
    /// PipeCoordinator materializes boxes FROM these records (identity
    /// preserved by UUID), so this array is the single source of truth for
    /// what the pipe contains. Seeded pristine (terminal trio, default
    /// params) on a fresh image load.
    private(set) var instances: [ModuleInstance] = []

    /// The pristine seed (terminal trio records with default params) —
    /// the base the history projections merge onto: undoing back to
    /// pristine restores exactly this set.
    private var baseInstances: [ModuleInstance] = []

    /// Wire the pipe owner (called once from the app root's startup task).
    func attach(pipeCoordinator: PipeCoordinator) {
        self.pipeCoordinator = pipeCoordinator
    }

    // ── M2-8-1 T2: the version dimension (KD-2) ─────────────────────────

    /// The version-orchestration back-reference (the pipeCoordinator weak
    /// pattern — the app root strongly owns both). The coordinator never
    /// writes history except THROUGH `installVersionChain` below; P2's
    /// Versions panel consumption rides this same attach. Weak: no cycle.
    private weak var versionCoordinator: VersionCoordinator?

    /// Wire the version orchestrator (called once beside the other
    /// attaches).
    func attach(versionCoordinator: VersionCoordinator) {
        self.versionCoordinator = versionCoordinator
    }

    /// The version-swap INSTALL face (KD-2): assign the incoming chain and
    /// re-derive the live projections through the SAME single rebuild path
    /// every other history assignment uses (`restoreFromSidecar`,
    /// `performUndo/Redo/Jump`) — zero new projection code. `baseInstances`
    /// is deliberately untouched: the pristine seed is shared across
    /// versions (only chain-owned instances differ).
    func installVersionChain(_ chain: HistoryStack) {
        history = chain
        rebuildInstances()
        rebuildLayerStack()
    }

    // ── 02-05 history mutators (the ONLY writers of history/instances) ──

    /// Seed a freshly loaded image to PRISTINE: empty history + the
    /// default-chain records as the live instance set (the coordinator
    /// passes `ModuleRegistry.makeDefaultInstances()`).
    func resetHistoryForNewImage(defaultInstances: [ModuleInstance]) {
        history = HistoryStack()
        baseInstances = defaultInstances
        instances = defaultInstances
        clearPreviewDenoiseBypass()
    }

    /// 02-06 sidecar RESTORE (replaces the pristine reset when a `.lra`
    /// exists): installs the decoded history and derives the live set with
    /// the SAME merge rule as undo/redo. `baseInstances` = the persisted
    /// instances NOT owned by the restored history's effective set — their
    /// persisted UUIDs + params are preserved VERBATIM (NDE-1: identity is
    /// never re-minted on reload; checkpoint 02-06-01 lock #7), while
    /// history-owned instances come back through their inline snapshots.
    func restoreFromSidecar(history restoredHistory: HistoryStack, persistedInstances: [ModuleInstance]) {
        history = restoredHistory
        let effective = restoredHistory.effectiveInstances()
        baseInstances = persistedInstances.filter { record in
            !effective.contains {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }
        }
        rebuildInstances()
    }

    /// D-H1 commit leg: one history entry per interaction
    /// (`PipeCoordinator.commitContinuousEdit` calls this), then the live
    /// instance set picks up the snapshot and the coordinator is notified
    /// (weak back-reference + Task — the same loose coupling as every
    /// other EditorState → coordinator edge; the render itself is the
    /// coordinator's business, and is idempotent here: the pipes already
    /// rendered the live state during the drag, so the post-commit pass
    /// proves cache hits).
    func recordChange(_ snapshot: ModuleInstance, label: String) {
        history.commit(snapshot, label: label)
        // M3-1-03 KD-3: a commit IS the truth landing — an armed bypass on
        // the committed instance yields here (the real flow disarms before
        // the commit; this keeps any racing commit path from diverging the
        // live set from the history truth via the upsert's enforcement).
        previewDenoiseBypass.removeValue(forKey: snapshot.id)
        upsert(instance: snapshot)
        guard let pipeCoordinator else { return }
        Task { await pipeCoordinator.historyDidChange() }
    }

    /// D-H1 live leg: drag-preview upsert WITHOUT a history commit (the
    /// coordinator calls this per `setLiveParams`; zero items accumulate —
    /// the commit lands once at drag end).
    func applyLiveInstance(_ snapshot: ModuleInstance) {
        upsert(instance: snapshot)
    }

    // ── M3-1-03 T3: the drag-time denoise preview bypass (OQ-6①/KD-3) ──

    /// The drag-window bypass state: the DRAGGED instance's UUID → the
    /// `enabled` value the record carried when the bypass armed (restored
    /// verbatim on disarm — a user-disabled module stays disabled).
    /// Live-projection only: never enters params, history, or liveEdited,
    /// so FULL renders OUTSIDE the drag window are byte-identical (a FULL
    /// rerun DURING the window briefly misses denoise — the DECISIONS
    /// registered risk, M4 coordinator serialization is the根治余量).
    private var previewDenoiseBypass: [UUID: Bool] = [:]

    /// Drag-time preview bypass (M3-1-03 KD-3, OQ-6①): while a nlmeans
    /// slider drags, the DRAGGED instance's live projection temporarily
    /// reads `enabled = false` so the PREVIEW pipe skips it (full-quality
    /// nlmeans ≈ 65ms — far over the 16.6ms interactive budget, perf.md
    /// OQ-7-A; decimate 减趟 proved math-unreachable, skip = the maximal
    /// downgrade). Keyed by INSTANCE IDENTITY, never opName — a
    /// layer-embedded nlmeans is never collateral (checker 回注 M6).
    func setPreviewDenoiseBypass(_ instanceID: UUID, on: Bool) {
        if on {
            guard previewDenoiseBypass[instanceID] == nil else { return }
            guard let index = instances.firstIndex(where: { $0.id == instanceID })
            else { return }
            previewDenoiseBypass[instanceID] = instances[index].enabled
            instances[index].enabled = false
        } else {
            guard let prior = previewDenoiseBypass.removeValue(forKey: instanceID)
            else { return }
            if let index = instances.firstIndex(where: { $0.id == instanceID }) {
                instances[index].enabled = prior
            }
        }
    }

    /// Wholesale projection replacement drops any armed bypass (load /
    /// version swap / undo-redo-jump rebuilds) — a stale force-false would
    /// diverge the live set from the history truth after the gesture.
    private func clearPreviewDenoiseBypass() {
        guard !previewDenoiseBypass.isEmpty else { return }
        previewDenoiseBypass.removeAll()
    }

    // ── M2-6-3 T1 (KD-1): the document-level DRT commit face ─────────────

    /// D-H1 COMMIT leg for the document-level DRT record: EXACTLY ONE
    /// history item whose payload rides `drtRecord` (the additive
    /// HistoryItem field); the required snapshot slot carries the current
    /// top global record as a PLACEHOLDER (the `commitLayerStructure`
    /// shape) and the `HistoryStack.drtDocumentScope` marker keeps that
    /// placeholder out of every projection (KD-1's hard constraint — the
    /// instance set is never polluted). Preset applications, method
    /// switches and encodings all land through here (the panel passes the
    /// `history_drt_*` label family); undo/redo restore through the
    /// coordinator's navigation faces (the carrier re-syncs from
    /// `effectiveDrtRecord()` there).
    func recordDrtChange(_ record: DrtRecord, label: String) {
        let placeholder = instances.first ?? baseInstances.first
        guard let placeholder else { return }
        history.commitDrt(record: record, placeholder: placeholder, label: label)
        notifyDrtChange(record)
    }

    /// The EditorState → coordinator edge for the DRT dimension (the
    /// `notifyPasteChange` shape): the coordinator updates the session
    /// carrier, re-renders (the tail re-runs on the record hash fold) and
    /// schedules the sidecar write — the caller does none of that.
    private func notifyDrtChange(_ record: DrtRecord) {
        guard let pipeCoordinator else { return }
        Task { await pipeCoordinator.drtRecordDidChange(record) }
    }

    // ── M3-3-02 T5 (KD-6): the document-level FILM commit face — the DRT
    //    commit's twin (one item per interaction, `history_film_*` labels;
    //    undo/redo restore through the coordinator's navigation faces).

    /// D-H1 COMMIT leg for the document-level film record: EXACTLY ONE
    /// history item whose payload rides `filmRecord`; the placeholder slot
    /// keeps the instance set unpolluted (the commitDrt shape).
    func recordFilmChange(_ record: FilmRecord, label: String) {
        let placeholder = instances.first ?? baseInstances.first
        guard let placeholder else { return }
        history.commitFilm(record: record, placeholder: placeholder, label: label)
        notifyFilmChange(record)
    }

    /// The EditorState → coordinator edge for the film dimension (the
    /// notifyDrtChange twin).
    private func notifyFilmChange(_ record: FilmRecord) {
        guard let pipeCoordinator else { return }
        Task { await pipeCoordinator.filmRecordDidChange(record) }
    }

    /// 04-08-F2 (GUI-9 闭环): menu enablement source — true while the
    /// stack has an entry at/below the pointer to step back into.
    /// The Edit → Undo menu binds `.disabled(!canUndo)` to this, so ⌘Z
    /// availability always mirrors the Phase 2 stack semantics.
    var canUndo: Bool { history.position >= 0 }

    /// 04-08-F2: redo availability — a non-empty tail past the pointer
    /// (undo followed by NO new commit; any commit truncates it).
    var canRedo: Bool { history.position + 1 < history.items.count }

    // ── 09-04 HIST-05 paste landing (the live-path surface) ──────────────

    /// Install a MERGE paste (the currently edited image as the target —
    /// dt `_safe_history_job_on_imgid`'s live leg): the composed stack
    /// already carries the ONE paste item; the base set is untouched
    /// (undo-safe). One ⌘Z steps back over the paste item.
    func installMergePaste(history newHistory: HistoryStack) {
        history = newHistory
        rebuildInstances()
        rebuildLayerStack()
        notifyPasteChange()
    }

    /// Install an OVERWRITE paste: the composed stack is the epoch item;
    /// the base becomes `seed ∪ oldBase` (the「默认种子 + 载荷实例」
    /// acceptance — the seed records the OLD effective set shadowed come
    /// back so a ⌘Z re-projects the pre-paste state byte-exactly).
    func installOverwritePaste(
        history newHistory: HistoryStack, seed: [ModuleInstance]
    ) {
        history = newHistory
        var merged = seed
        for record in baseInstances
        where !merged.contains(where: {
            $0.opName == record.opName && $0.multiPriority == record.multiPriority
        }) {
            merged.append(record)
        }
        baseInstances = merged.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
        rebuildInstances()
        rebuildLayerStack()
        notifyPasteChange()
    }

    /// The paste → coordinator edge (mirror of recordChange's tail: the
    /// committed move re-renders AND schedules the sidecar write).
    private func notifyPasteChange() {
        guard let pipeCoordinator else { return }
        Task { await pipeCoordinator.pasteDidChange() }
    }

    /// HIST-02 navigation (coordinator-driven): step back; false when
    /// already pristine. Rebuilds the live instance set from the stack.
    @discardableResult
    func performUndo() -> Bool {
        guard history.undo() != nil else { return false }
        rebuildInstances()
        rebuildLayerStack()
        return true
    }

    /// HIST-02 navigation: step forward into an untruncated tail.
    @discardableResult
    func performRedo() -> Bool {
        guard history.redo() != nil else { return false }
        rebuildInstances()
        rebuildLayerStack()
        return true
    }

    /// HIST-02/D-H3 navigation: jump to an arbitrary point (the stack
    /// clamps out-of-range indices; −1 = pristine).
    func performJump(to index: Int) {
        history.jump(to: index)
        rebuildInstances()
        rebuildLayerStack()
    }

    /// Upsert by instance UUID, keep v50 order (records ARE the pipe
    /// order — boxes are materialized in this sequence).
    private func upsert(instance: ModuleInstance) {
        // M3-1-03 KD-3: while the drag-window bypass is armed for this
        // instance, the live projection keeps `enabled = false` — the
        // panel's ticks carry the record's stored enabled (true), the
        // projection enforces the downgrade until disarm restores the
        // prior value. Zero trace outside the window.
        var incoming = instance
        if previewDenoiseBypass[incoming.id] != nil {
            incoming.enabled = false
        }
        if let index = instances.firstIndex(where: { $0.id == incoming.id }) {
            instances[index] = incoming
        } else {
            instances.append(incoming)
        }
        instances.sort {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    /// Rebuild the live set after undo/redo/jump: the pristine base ∪ the
    /// stack's effective instances, where a history instance with the same
    /// `(opName, multiPriority)` REPLACES the base record (the committed
    /// identity wins — Darktable keeps mandatory modules with their latest
    /// history params). Instances that exist only in abandoned redo-state
    /// vanish (their box is dropped at the next materialization).
    private func rebuildInstances() {
        clearPreviewDenoiseBypass()
        var merged = baseInstances
        for record in history.effectiveInstances() {
            if let index = merged.firstIndex(where: {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }) {
                merged[index] = record
            } else {
                merged.append(record)
            }
        }
        instances = merged.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    /// 09-04 T6 (HIST-06): the pristine seed RECORDS for the loaded image
    /// — the before-plane's compose input (the render override mints its
    /// own boxes from these). Empty when no image is loaded.
    var pristineSeedRecords: [ModuleInstance] { baseInstances }

    /// Load an image/RAW file through `RAWDecoder` (D-21/D-24); on success
    /// the PipeCoordinator renders PREVIEW and pushes the display texture
    /// (Plan 02-03-04 — the D-X1 single render path). Cancels any in-flight
    /// decode first (D-34). The decode runs off-MainActor (`RAWDecoder` is
    /// an actor); on success a fresh `LayerStack(baseLayer:
    /// BackgroundLayer())` is installed (D-03a) and the decodeTask hands
    /// the result to the attached coordinator. Failures land in
    /// `decodeError` as typed `AppError`s (D-25); pixelpipe failures are
    /// non-blocking (logged only — same severity as the Plan 03 render
    /// leg). The decode leg is wrapped in an `os.signpost` interval (D-31);
    /// the pixelpipe leg is signposted inside `RenderPipeline` itself.
    /// `metal` nil = no GPU — decode still succeeds, display stays empty
    /// (the fatal no-GPU alert is hosted by `ContentView`).
    /// M2-3-3 T4 (checker E2): the RAW Decode panel's session overrides ride
    /// the ONE decode request chain. Default nil = identity — every existing
    /// call site compiles and behaves unchanged (the declared incremental
    /// seam; `RAWDecoder.decode` clamps + treats identity as the no-op).
    /// M2-5-2 KD-5: `defaultLookPending` carries the per-image pending flag
    /// the OPEN entry read from the library (the sanctioned fallback — the
    /// editor session has no row channel of its own); mint happens AFTER
    /// the pipe load's sidecar probe settled, only when the `.lra` is
    /// absent (restore 恒压过 flag).
    func load(
        url: URL, decoder: RAWDecoder, metal: MetalContext?, logger: Logger,
        overrides: RAWTechnicalOverrides? = nil,
        defaultLookPending: Bool = false
    ) {
        decodeTask?.cancel()
        loadedImageURL = url
        decodeError = nil
        isDecoding = true
        // Drop the previous image's viewport texture + layer stack so the
        // editor never shows a stale frame while the new decode runs.
        displayTexture = nil
        layerStack = nil

        decodeTask = Task { [weak self] in
            guard let self else { return }
            let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer", category: "decode")
            let interval = signposter.beginInterval("decode", id: signposter.makeSignpostID())
            defer {
                signposter.endInterval("decode", interval)
                self.isDecoding = false
            }

            do {
                let decoded = try await decoder.decode(
                    url, technicalOverrides: overrides ?? .init()) // off-MainActor
                guard !Task.isCancelled else { // a newer load superseded this one
                    logger.info("decode superseded: \(url.lastPathComponent, privacy: .public)")
                    return
                }
                self.image = decoded
                let camera = decoded.capture.cameraModel ?? "-"
                logger.info(
                    "decoded \(url.lastPathComponent, privacy: .public) v\(decoded.decoderVersionUsed.rawValue, privacy: .public)"
                )
                logger.info(
                    "camera=\(camera, privacy: .public) blackLevel=\(decoded.rawTech.blackLevel, privacy: .public)"
                )

                // D-03a: every decoded image gets a fresh layer stack —
                // base layer only in Phase 1 (adjustment layers: Phase 6).
                let stack = LayerStack(baseLayer: BackgroundLayer())
                self.layerStack = stack

                // D-X1 single render path (Plan 02-03-04): the decodeTask
                // hands the decoded image to the PipeCoordinator, which
                // owns the multi-resolution pipes, renders PREVIEW at the
                // D-C3 bucket and pushes `displayTexture`. Since 02-05 the
                // HISTORY owns the instance set: empty instances → the
                // coordinator seeds/resets `EditorState` to pristine
                // (terminal trio records) and materializes boxes from
                // them; 02-06 restores per-image sidecars here instead.
                if let metal {
                    guard let pipeCoordinator else {
                        logger.error("PipeCoordinator not attached — no render path")
                        return
                    }
                    await pipeCoordinator.load(
                        url: url,
                        decoded: decoded,
                        instances: [],
                        metal: metal
                    )
                    guard !Task.isCancelled else { // superseded mid-pipe
                        logger.info("pixelpipe superseded: \(url.lastPathComponent, privacy: .public)")
                        return
                    }
                    // M2-5-2 KD-5 (checker E5): the default-look mint —
                    // strictly AFTER the pipe load's sidecar probe settled
                    // (restore-or-pristine). The .lra absence is re-probed
                    // at the file level: restore 恒压过 flag; the mint is a
                    // MEMORY document operation (single AdjustmentLayer +
                    // one commit + the persist-skipping channel, decode
                    // async) with zero sidecar scheduling.
                    // M4-1-02 T3 (KD-2, upstream D2): a RASTER document
                    // never mints the RAW default look (the neutral Color
                    // Grade is RAW-domain — the raster doc opens WITH the
                    // derived DRT record instead; the carrier seed ran
                    // inside the pipe load above).
                    if defaultLookPending {
                        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
                        if decoded.rasterColor != nil {
                            logger.info(
                                "default look skipped (raster document): \(url.lastPathComponent, privacy: .public)"
                            )
                        } else if FileManager.default.fileExists(atPath: sidecarURL.path) {
                            logger.info("default look suppressed: sidecar present for \(url.lastPathComponent, privacy: .public)")
                        } else {
                            if mintDefaultLook() != nil {
                                logger.info("default look minted: \(url.lastPathComponent, privacy: .public)")
                            }
                        }
                    }
                }
            } catch {
                let appError = AppError(error) // D-25 bridge
                if case .cancelled = appError {
                    logger.info("decode cancelled: \(url.lastPathComponent, privacy: .public)")
                } else {
                    logger.error(
                        "pixelpipe/decode failed (\(url.lastPathComponent, privacy: .public)): \(appError.localizedDescription, privacy: .public)"
                    )
                    self.decodeError = appError
                }
            }
        }
    }

    /// Dismiss the blocking decode-error alert (D-26 skeleton).
    func clearError() {
        decodeError = nil
    }

    // MARK: - 06-05 Layer stack (LAYER-01/04 + history 全粒度)

    /// The `layerScope` marker of STACK-STRUCTURE history items (add/
    /// remove/reorder/duplicate/mergeDown/property/mask edits): never a
    /// valid UUID string, so the item is excluded from the GLOBAL
    /// projection (`effectiveInstances()` filters `layerScope == nil`)
    /// AND from every layer-chain projection (those match a layer's UUID
    /// string). Its payload lives in `stackSnapshot` only.
    nonisolated static let layerStructureScope = "__layerStack__"

    /// The adjusted layer, or nil when `id` is not in the live stack.
    func adjustmentLayer(id: UUID) -> AdjustmentLayer? {
        layerStack?.compositeLayers.first { $0.id == id }
    }

    // ── Structure operations (each lands EXACTLY ONE history item) ──────

    /// Add a new adjustment layer on top: default name, EMPTY chain,
    /// normal blend, opacity 1, full-mask passthrough (plan T1.2).
    /// Exactly ONE structure commit.
    @discardableResult
    func addAdjustmentLayer() -> AdjustmentLayer? {
        // Bootstrap when no image session installed a stack yet (tests,
        // headless loads): LAYER-01's base layer is constructible freely.
        guard let layerStack else {
            let stack = LayerStack(baseLayer: BackgroundLayer())
            self.layerStack = stack
            return addAdjustmentLayer()
        }
        let layer = AdjustmentLayer(
            name: layerStack.nextLayerName(
                base: String(localized: "layer_default_name")))
        var stack = layerStack
        stack.addAdjustment(layer)
        self.layerStack = stack
        commitLayerStructure(layerID: layer.id, label: String(localized: "history_layer_add"))
        return layer
    }

    /// Remove the layer with `id` (the base layer is not removable).
    /// Exactly ONE structure commit.
    func removeLayer(id: UUID) {
        guard let layerStack, layerStack.adjustmentLayers.contains(where: { $0.id == id }) else {
            return
        }
        var stack = layerStack
        stack.remove(id: id)
        self.layerStack = stack
        commitLayerStructure(layerID: id, label: String(localized: "history_layer_remove"))
    }

    /// Duplicate the layer with `id` (fresh identities above the
    /// original). Exactly ONE structure commit.
    @discardableResult
    func duplicateLayer(id: UUID) -> (any Layer)? {
        guard let layerStack else { return nil }
        var stack = layerStack
        guard let copy = stack.duplicate(id: id) else { return nil }
        self.layerStack = stack
        commitLayerStructure(
            layerID: copy.id, label: String(localized: "history_layer_duplicate"))
        return copy
    }

    /// Merge the layer with `id` down (the 06-1 data face). Into another
    /// adjustment layer: exactly ONE structure commit. Into the BASE
    /// (bottommost layer): the combined chain folds into the GLOBAL
    /// instance set through one `recordChange` per record on top of the
    /// structure item — N+1 items, the dt-faithful shape (documented:
    /// D-06-05-T1-2; the 1-commit acceptance pins the into-layer case).
    func mergeLayerDown(id: UUID) {
        guard let layerStack else { return }
        var stack = layerStack
        guard let outcome = stack.mergeDown(id: id) else { return }
        self.layerStack = stack
        commitLayerStructure(layerID: id, label: String(localized: "history_layer_merge"))
        if case let .mergedIntoBase(chain) = outcome {
            // Each merged record REPLACES its global (opName, priority)
            // twin through the normal D-H1 commit path (layerScope nil).
            for record in chain {
                recordChange(record, label: String(localized: "history_layer_merge"))
            }
        }
    }

    /// Reorder (bottom-to-top target index, clamped). Exactly ONE
    /// structure commit; layer identities untouched (NDE-1).
    func reorderLayer(id: UUID, to targetIndex: Int) {
        guard let layerStack else { return }
        var stack = layerStack
        stack.reorder(id: id, to: targetIndex)
        self.layerStack = stack
        commitLayerStructure(layerID: id, label: String(localized: "history_layer_reorder"))
    }

    // MARK: M2-7-2 T4 (KD-4): the Default Behavior newLayer migration

    /// The drawn-mask migration: a FRESH adjustment layer ABOVE the source
    /// carries the just-finished drawn mask; the source is left WITHOUT it
    /// (原层无残留). Exactly ONE structure item (one stack snapshot carries
    /// both changes) — the AC's 「恰 1 history item」pin. A source without
    /// drawn forms = a silent no-op (the dispatch guards before this).
    @discardableResult
    func migrateMaskToNewLayer(from sourceID: UUID) -> AdjustmentLayer? {
        guard let layerStack,
            let source = adjustmentLayer(id: sourceID),
            let mask = source.mask,
            mask.hasDrawnForms
        else { return nil }
        var stack = layerStack
        let migrated = AdjustmentLayer(
            name: stack.nextLayerName(base: String(localized: "layer_default_name")),
            mask: mask)
        var stripped = source
        stripped.mask = nil
        stack.replace(stripped)
        stack.addAdjustment(migrated)
        self.layerStack = stack
        commitLayerStructure(
            layerID: migrated.id,
            label: String(
                localized: "history_mask_behavior_migrated",
                defaultValue: "Move mask to new layer"))
        return migrated
    }

    // MARK: M2-7-2 (KD-3): the Mask Groups panel's unified mask seams

    /// D-H1 LIVE leg for panel mask edits: swap the layer's mask in place,
    /// ZERO history, ZERO bump (the write-point-⑤ bump rides the commit
    /// seam only — the slider preview never moves the guard).
    func applyLiveMaskEdit(layerID: UUID, mutate: (inout MaskSpec) -> Void) {
        guard let layer = adjustmentLayer(id: layerID) else { return }
        var mask = layer.mask ?? MaskSpec()
        mutate(&mask)
        layer.mask = mask
        applyLiveLayer(layer)
    }

    /// D-H1 COMMIT leg for panel mask edits (the `history_mask_item_*` /
    /// `history_mask_range_*` key families): exactly ONE structure item,
    /// and the contentRevision bump happens HERE — before the commit,
    /// exactly once (KD-5's division: the facade setters are value writes;
    /// the producer = this seam).
    func commitMaskEdit(layerID: UUID, label: String, mutate: (inout MaskSpec) -> Void) {
        guard let layer = adjustmentLayer(id: layerID) else { return }
        var mask = layer.mask ?? MaskSpec()
        mutate(&mask)
        mask.bumpContentRevision()
        let copy = AdjustmentLayer(
            id: layer.id, name: layer.name, isVisible: layer.isVisible,
            opacity: layer.opacity, blendMode: layer.blendMode,
            blendOptions: layer.blendOptions, enabled: layer.enabled,
            chain: layer.chain, mask: mask)
        commitLayerEdit(copy, label: label)
    }

    // MARK: M2-4 node-graph command entry (Plan M2-4-1 T2, KD-2)

    /// The ONE execution entry for every node-graph command (the P3 panels
    /// are pure producers — they never switch on commands). Runs the pure
    /// Core transform (`NodeGraphCommand.apply(to:)`), reassigns
    /// `layerStack` (the GUI-19 @Observable atom), then lands EXACTLY ONE
    /// structure history item carrying the post-edit stack snapshot with a
    /// `history_graph_*` label — undo/redo restore through the existing
    /// single `rebuildLayerStack` path, identity-preserving (M2NODE-02).
    ///
    /// Error face (the plan's toast 面序): `lockedNode` is intercepted
    /// SILENTLY (the endpoint lock is a visible affordance, not an error);
    /// every other typed failure raises the D-26 background toast. Both
    /// switches are exhaustive with NO default arm — a new command or
    /// error case must be answered here at compile time (checker ①).
    func apply(_ command: NodeGraphCommand) {
        guard let layerStack else { return }
        do {
            let transformed = try command.apply(to: layerStack)
            self.layerStack = transformed
            let face = Self.graphCommandFace(of: command)
            commitLayerStructure(
                layerID: face.target ?? layerStack.baseLayer.id, // dead slot (scope lives in layerStructureScope)
                label: face.label)
        } catch {
            guard let graphError = error as? NodeGraphError else { return }
            switch graphError {
            case .lockedNode:
                break // silent interception (D-M2-4-CONTEXT-7)
            case .nodeNotFound, .notAGrade, .badPayload, .badPosition:
                presentToast(String(
                    localized: "toast_graph_command_rejected",
                    defaultValue: "This node action cannot be applied"))
            }
        }
    }

    /// The command's history label + target id in ONE exhaustive switch
    /// (the `history_graph_*` label family, plan M2-4-1 KD-2).
    private static func graphCommandFace(of command: NodeGraphCommand)
        -> (label: String, target: UUID?)
    {
        switch command {
        case .addCleanGrade:
            (String(localized: "history_graph_add", defaultValue: "Add color grade"), nil)
        case let .removeGradeAndBridge(id):
            (String(localized: "history_graph_remove", defaultValue: "Remove color grade"), id)
        case let .reconnectGrade(id, _):
            (String(localized: "history_graph_reconnect", defaultValue: "Reconnect color grade"), id)
        case let .renameGrade(id, _):
            (String(localized: "history_graph_rename", defaultValue: "Rename color grade"), id)
        case let .setGradeEnabled(id, _):
            (String(localized: "history_graph_enable", defaultValue: "Toggle color grade"), id)
        case let .setGradeMix(id, _):
            (String(localized: "history_graph_mix", defaultValue: "Adjust color grade mix"), id)
        case .insertGradeFromJSON:
            (String(localized: "history_graph_insert", defaultValue: "Insert color grade"), nil)
        }
    }

    /// D-H1 LIVE leg for layer properties/mask: swap the layer in place,
    /// ZERO history (the drag/stroke preview renders live; the commit
    /// lands once at drag/stroke end through `commitLayerStructure`).
    func applyLiveLayer(_ layer: AdjustmentLayer) {
        guard let layerStack,
              layerStack.adjustmentLayers.contains(where: { $0.id == layer.id })
        else { return }
        var stack = layerStack
        stack.replace(layer)
        self.layerStack = stack
        notifyLayerChange(persist: false)
    }

    /// D-H1 COMMIT leg for a property/mask edit on `layer`: exactly ONE
    /// structure item carrying the post-edit stack snapshot.
    func commitLayerEdit(_ layer: AdjustmentLayer, label: String) {
        guard let layerStack,
              layerStack.adjustmentLayers.contains(where: { $0.id == layer.id })
        else { return }
        var stack = layerStack
        stack.replace(layer)
        self.layerStack = stack
        commitLayerStructure(layerID: layer.id, label: label)
    }

    /// Add a module record (fresh identity clone of `template`) to the
    /// layer's chain. Exactly ONE structure commit (the chain is part of
    /// the stack snapshot). The UI「添加模块」menu drives this.
    ///
    /// GUI-19 (2026-09-24): the chain append must REASSIGN the observed
    /// `layerStack` property. `AdjustmentLayer` is a class — the in-place
    /// append alone updated the data (sidecar/history correct) but never
    /// tripped @Observable, so the Inspector's chain list (which reads
    /// `layerStack` through `adjustmentLayer(id:)`) never re-rendered:
    /// the row was missing until some unrelated observation re-ran the
    /// body. The copy-replace dance matches every sibling mutator.
    @discardableResult
    func addModuleToLayer(layerID: UUID, template: ModuleInstance) -> ModuleInstance? {
        guard let layerStack,
              let layer = adjustmentLayer(id: layerID)
        else { return nil }
        // M2-4 ownership seam (Plan M2-4-1 T3, KD-3; D-M2-4-CONTEXT-8
        // grace): the UI insert face refuses develop/drtPost-owned ops
        // INTO a grade — the typed check surfaces through the EXISTING
        // toast (never a crash, never silent). Sidecar loading, undo/redo
        // and InsertFromJson restoration stay validation-free (the user's
        // own data; M2-5 activates the strict face by widening the TABLE,
        // never this seam).
        if NodeOwnership.validate(
            owner: NodeOwnershipCatalog.owner(of: template.opName),
            into: .grade) != nil {
            presentToast(String(
                localized: "toast_module_owner_rejected",
                defaultValue: "This adjustment belongs to the Develop or DRT stage and cannot enter a color grade"))
            return nil
        }
        let record = template.clonedWithFreshIdentity()
        layer.chain.append(record)
        layer.chain.sort {
            ($0.iopOrder, $0.multiPriority, $0.opName)
                < ($1.iopOrder, $1.multiPriority, $1.opName)
        }
        var stack = layerStack
        stack.replace(layer)
        self.layerStack = stack // the @Observable invalidation atom
        commitLayerStructure(layerID: layerID, label: String(localized: "history_layer_module_add"))
        return record
    }

    // MARK: M2-5-2 KD-4: the catalog-driven add face (18 目录严格化)

    /// One add-menu entry — the enumeration's unit (KD-4).
    struct AdjustmentAddEntry: Equatable, Identifiable {
        /// The menu section (the Develop face vs the D6 compat fold).
        enum Section: String, Sendable, Equatable {
            case develop
            case compat
        }

        let section: Section
        /// The GradeCatalog id (nil = a non-catalog develop/compat op).
        let catalogID: String?
        /// The identity template — `addModuleToLayer`/`addModuleToBaseChain`
        /// fresh-identity-clone it on insert.
        let template: ModuleInstance
        var id: String { template.opName }
    }

    /// The add-face enumeration for a scope (KD-4's strict face; the
    /// RADIUS is new actions only — historical loads/undo stay validation
    /// free, and the `addModuleToLayer` typed seam remains the backstop):
    ///
    ///   selected Grade → EXACTLY the 14 grade-owned catalog rows (13
    ///                    Grade ops + Tint; LMT stays on the LUT page and
    ///                    the four DRT seats never enumerate);
    ///   no selection   → the develop-owned PANEL face only (geometry/
    ///                    yiyin/temperature) — ZERO grade-owned entries
    ///                    (D4 收窄: the base chain no longer accepts new
    ///                    grade-owned inserts from the menu).
    ///
    /// A dangling `layerID` (removed layer) answers the Develop scope —
    /// the same self-healing rule `activeLayerID` applies.
    func addFaceEntries(layerID: UUID?) -> [AdjustmentAddEntry] {
        if let layerID, adjustmentLayer(id: layerID) != nil {
            return Self.gradeScopeEntries()
        }
        return Self.developScopeEntries()
    }

    /// The grade-owned catalog rows, narrowed to the ADD face (KD-4):
    ///   − the lmt seat (D10/AC#7: LMT is hosted by the LUT page's library
    ///     picker — an empty lut3d add is meaningless; the four DRT seats
    ///     are excluded by owner already);
    ///   − deduped by opName (the shadows/highlights pair share the ONE
    ///     shadhi op — the checker-m2 single-row semantics; a second
    ///     identical-priority record would be silently merged by the
    ///     effectiveChain dedupe anyway).
    /// COUNT NOTE (DECISIONS): the plan's "恰 14" counted gradeItems()
    /// literally — 14 rows INCLUDING the lmt row and the shadhi duplicate —
    /// which cannot coexist with the binding "LMT 不在枚举" clause; the
    /// face carries 12 unique-op entries.
    private static func gradeScopeEntries() -> [AdjustmentAddEntry] {
        var seenOps = Set<String>()
        return GradeCatalog.gradeItems()
            .filter { $0.opName != Lut3dModule.opName }
            .compactMap { item in
                guard seenOps.insert(item.opName).inserted,
                    let template = templateInstance(for: item.opName)
                else { return nil }
                return AdjustmentAddEntry(
                    section: .develop, catalogID: item.catalogID, template: template)
            }
    }

    /// The Develop-scope face: the develop-owned ops WITH a panel face.
    /// The M2-1 disabled six are develop-owned but carry no panel and stay
    /// out of every menu (the M2-1 narrowing's menu corollary).
    private static func developScopeEntries() -> [AdjustmentAddEntry] {
        let developFaceOps: [(AdjustmentAddEntry.Section, String)] = [
            (.develop, TemperatureModule.opName),
            (.develop, CropModule.opName),
            (.develop, FlipModule.opName),
            (.develop, LensModule.opName),
            (.compat, AshiftModule.opName),
            (.compat, LiquifyModule.opName),
            (.compat, BordersModule.opName),
            (.compat, WatermarkModule.opName),
            (.compat, TextOverlayModule.opName),
        ]
        return developFaceOps.compactMap { section, op in
            // Guard by construction: every listed op must answer .develop.
            guard NodeOwnershipCatalog.owner(of: op) == .develop,
                let template = templateInstance(for: op)
            else { return nil }
            return AdjustmentAddEntry(
                section: section, catalogID: nil, template: template)
        }
    }

    /// The typed template factory (exhaustive over the add-face op set —
    /// the Params() defaults ARE the catalog identityJSON bytes; a new
    /// add-face op must land a case here at compile time).
    static func templateInstance(for opName: String) -> ModuleInstance? {
        switch opName {
        // The 13 grade-owned catalog ops + Tint.
        case Cat02WBModule.opName:
            ModuleInstance(module: Cat02WBModule.self, params: Cat02WBModule.Params())
        case ExposureModule.opName:
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params())
        case ContrastModule.opName:
            ModuleInstance(module: ContrastModule.self, params: ContrastModule.Params())
        case WhiteModule.opName:
            ModuleInstance(module: WhiteModule.self, params: WhiteModule.Params())
        case BlackModule.opName:
            ModuleInstance(module: BlackModule.self, params: BlackModule.Params())
        case ShadhiModule.opName:
            // The checker-m5 split: the ADD seed = the catalog identity
            // (shadows 0 / highlights 0), decoded from the row's
            // identityJSON (the P1 single source) — NOT the panel working
            // point (50/−50). Every other grade op's Params() IS its
            // identity, so only this case needs the decode.
            ModuleInstance(
                module: ShadhiModule.self,
                params: (GradeCatalog.item(opName: ShadhiModule.opName)
                    .flatMap { item in
                        try? JSONDecoder().decode(
                            ShadhiModule.Params.self,
                            from: Data(item.identityJSON.utf8))
                    }) ?? ShadhiModule.Params())
        case ToneCurveModule.opName:
            ModuleInstance(module: ToneCurveModule.self, params: ToneCurveModule.Params())
        case HlsModule.opName:
            ModuleInstance(module: HlsModule.self, params: HlsModule.Params())
        case SaturationModule.opName:
            ModuleInstance(module: SaturationModule.self, params: SaturationModule.Params())
        case VibranceModule.opName:
            ModuleInstance(module: VibranceModule.self, params: VibranceModule.Params())
        case ColorWheelsModule.opName:
            ModuleInstance(module: ColorWheelsModule.self, params: ColorWheelsModule.Params())
        case TintModule.opName:
            ModuleInstance(module: TintModule.self, params: TintModule.Params())
        // M3-3-02 T4 (KD-5/m4): the placement op joins the ADD face as the
        // 19th row's identity template — the addable, NON-editable identity
        // placeholder (the per-op hand-written provider mechanism = no
        // editing face until the M3-4 FSIM-02 panel; Params() IS the
        // kernel no-op point, so add + leave = bit-exact pass-through).
        case FilmPlacementModule.opName:
            ModuleInstance(module: FilmPlacementModule.self, params: FilmPlacementModule.Params())
        // M5-1-01 T5 (KD-5, checker E2): colormatch joins the ADD face as
        // the 20th row's identity template — the addable, NON-editable
        // identity placeholder until the M5-1-02 panel (Params() IS the
        // byte identity core, strength 0 = blit). Missing this case would
        // silently drop the row from the menu via the compactMap below.
        case ColormatchModule.opName:
            ModuleInstance(module: ColormatchModule.self, params: ColormatchModule.Params())
        // The develop-owned panel face.
        case TemperatureModule.opName:
            ModuleInstance(module: TemperatureModule.self, params: TemperatureModule.Params())
        case CropModule.opName:
            ModuleInstance(module: CropModule.self, params: CropModule.Params())
        case FlipModule.opName:
            ModuleInstance(module: FlipModule.self, params: FlipModule.Params())
        case LensModule.opName:
            ModuleInstance(module: LensModule.self, params: LensModule.Params())
        case AshiftModule.opName:
            ModuleInstance(module: AshiftModule.self, params: AshiftModule.Params())
        case LiquifyModule.opName:
            ModuleInstance(module: LiquifyModule.self, params: LiquifyModule.Params())
        case BordersModule.opName:
            ModuleInstance(module: BordersModule.self, params: BordersModule.Params())
        case WatermarkModule.opName:
            ModuleInstance(module: WatermarkModule.self, params: WatermarkModule.Params())
        case TextOverlayModule.opName:
            ModuleInstance(module: TextOverlayModule.self, params: TextOverlayModule.Params())
        default:
            nil
        }
    }

    /// The Develop-scope add (the base chain): fresh-identity clone → ONE
    /// D-H1 discrete commit landing the record in the global instance set
    /// (`recordChange` shape — the same single-commit semantics a layer
    /// add carries, minus the stack structure item). Undo steps over it.
    @discardableResult
    func addModuleToBaseChain(template: ModuleInstance) -> ModuleInstance? {
        let record = template.clonedWithFreshIdentity()
        recordChange(
            record, label: String(
                localized: "history_base_module_add", defaultValue: "Add module"))
        return record
    }

    /// D-H1 LIVE leg for a LAYER-SCOPED module param edit: upsert the
    /// record into the layer's chain, ZERO history.
    func applyLiveLayerInstance(_ snapshot: ModuleInstance, layerID: UUID) {
        guard let layer = adjustmentLayer(id: layerID) else { return }
        layer.chain = HistoryStack.effectiveChain(layer.chain + [snapshot])
        notifyLayerChange(persist: false)
    }

    /// D-H1 COMMIT leg for a LAYER-SCOPED module param edit (`layerScope`
    /// 型, the 06-1 enabled reservation): exactly ONE item whose snapshot
    /// is the chain record. Undo re-derives the chain from the structure
    /// snapshot + the remaining in-scope items (`rebuildLayerStack`).
    func recordLayerChange(_ snapshot: ModuleInstance, layerID: UUID, label: String) {
        guard let layer = adjustmentLayer(id: layerID) else { return }
        history.commit(snapshot, label: label, layerScope: layerID.uuidString)
        layer.chain = HistoryStack.effectiveChain(layer.chain + [snapshot])
        notifyLayerChange(persist: true)
    }

    /// Sidecar RESTORE (layer dimension): install the decoded records as
    /// the live stack (identity + params verbatim). No history — the
    /// restored items ARE the history. Bootstraps the base layer when no
    /// stack exists yet. Kind-dispatched since 06-07 (adjustment +
    /// retouch records restore their concrete layers).
    func installLayerStack(from layers: [any Layer]) {
        var stack = LayerStack(baseLayer: layerStack?.baseLayer ?? BackgroundLayer())
        for layer in layers { stack.addAdjustment(layer) }
        self.layerStack = stack
        notifyLayerChange(persist: false)
    }

    /// The shared structure-commit tail: exactly ONE item, snapshot
    /// placeholder (excluded from every projection — see the scope
    /// marker) + the post-edit FULL stack snapshot. `schedulePersist: false`
    /// is the M2-5-2 mint's persist-skipping channel (the 2s debounce is
    /// never scheduled — the `.lra` absence = unedited invariant holds
    /// constructively; the render leg still runs so the preview shows the
    /// minted look).
    private func commitLayerStructure(
        layerID: UUID, label: String, schedulePersist: Bool = true
    ) {
        guard let layerStack else { return }
        // Placeholder snapshot: the CURRENT top global record. The
        // `layerStructureScope` marker keeps it out of the global AND
        // every layer projection; the sidecar rebuild uses stackSnapshot.
        let placeholder = instances.first ?? baseInstances.first
        guard let placeholder else { return }
        history.commit(
            placeholder, label: label,
            layerScope: Self.layerStructureScope,
            stackSnapshot: LayerStackSnapshot(layerStack))
        notifyLayerChange(persist: schedulePersist)
    }

    // MARK: M2-5-2 KD-5: the default-look mint (checker E5 shape)

    /// The mint: memory-construct ONE AdjustmentLayer whose chain carries
    /// the three `GradeCatalog.defaultLook` instances (+1.5 EV / contrast
    /// +15 / saturation 1.3 — decoded through each module's own Codable
    /// face, the same ParamsCoding path a panel commit writes), land it as
    /// EXACTLY ONE history item through the persist-SKIPPING channel, and
    /// leave the sidecar untouched. Undo steps back to pristine
    /// constructively (one item). A stack that already carries adjustment
    /// layers (restore won the race) never mints.
    @discardableResult
    func mintDefaultLook() -> AdjustmentLayer? {
        guard let layerStack, layerStack.adjustmentLayers.isEmpty else { return nil }
        var chain: [ModuleInstance] = []
        for entry in GradeCatalog.defaultLook {
            guard var record = Self.templateInstance(for: entry.opName) else { continue }
            switch entry.opName {
            case ExposureModule.opName:
                if let params = try? JSONDecoder().decode(
                    ExposureModule.Params.self, from: Data(entry.paramsJSON.utf8)) {
                    try? record.setParams(params, as: ExposureModule.self)
                }
            case ContrastModule.opName:
                if let params = try? JSONDecoder().decode(
                    ContrastModule.Params.self, from: Data(entry.paramsJSON.utf8)) {
                    try? record.setParams(params, as: ContrastModule.self)
                }
            case SaturationModule.opName:
                if let params = try? JSONDecoder().decode(
                    SaturationModule.Params.self, from: Data(entry.paramsJSON.utf8)) {
                    try? record.setParams(params, as: SaturationModule.self)
                }
            default:
                continue
            }
            chain.append(record)
        }
        guard !chain.isEmpty else { return nil }
        let layer = AdjustmentLayer(
            name: layerStack.nextLayerName(
                base: String(localized: "layer_default_name")),
            chain: chain.sorted {
                ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
            })
        var stack = layerStack
        stack.addAdjustment(layer)
        self.layerStack = stack
        commitLayerStructure(
            layerID: layer.id,
            label: String(
                localized: "history_default_look", defaultValue: "Default look"),
            schedulePersist: false)
        return layer
    }

    /// The EditorState → coordinator edge for the layer dimension (same
    /// loose coupling as `recordChange`). `persist` schedules the sidecar
    /// write (live drag/stroke ticks never hit disk — the D-S3 rule).
    private func notifyLayerChange(persist: Bool) {
        guard let pipeCoordinator else { return }
        Task { await pipeCoordinator.layerStackDidChange(persist: persist) }
    }

    // ── 06-07 retouch kind (the stroke list = the layer's whole edit) ──

    /// The retouch layer with `id`, when the live stack carries one.
    func retouchLayer(id: UUID) -> RetouchLayer? {
        layerStack?.adjustmentLayers.first { $0.id == id } as? RetouchLayer
    }

    /// Add a new retouch layer on top (the D-06-CONTEXT-4 C1 semantic:
    /// healing is an independently toggleable edit step). Exactly ONE
    /// structure commit.
    @discardableResult
    func addRetouchLayer() -> RetouchLayer? {
        guard let layerStack else {
            let stack = LayerStack(baseLayer: BackgroundLayer())
            self.layerStack = stack
            return addRetouchLayer()
        }
        let layer = RetouchLayer(
            name: layerStack.nextLayerName(
                base: String(localized: "layer_default_name")))
        var stack = layerStack
        stack.addAdjustment(layer)
        self.layerStack = stack
        commitLayerStructure(layerID: layer.id, label: String(localized: "history_layer_add"))
        return layer
    }

    /// D-H1 LIVE leg for retouch strokes: swap the layer in place,
    /// ZERO history (stroke drags preview live; the commit lands once
    /// at stroke end / discrete edit).
    func applyLiveRetouch(_ layer: RetouchLayer) {
        guard let layerStack,
              layerStack.adjustmentLayers.contains(where: { $0.id == layer.id })
        else { return }
        var stack = layerStack
        stack.replaceAny(layer)
        self.layerStack = stack
        notifyLayerChange(persist: false)
    }

    /// D-H1 COMMIT leg for retouch strokes/properties: exactly ONE
    /// structure item (the stackSnapshot path — strokes ride the frozen
    /// snapshot spelling).
    func commitRetouchEdit(_ layer: RetouchLayer, label: String) {
        guard let layerStack,
              layerStack.adjustmentLayers.contains(where: { $0.id == layer.id })
        else { return }
        var stack = layerStack
        stack.replaceAny(layer)
        self.layerStack = stack
        commitLayerStructure(layerID: layer.id, label: label)
    }

    /// History → layer state (the layer twin of `rebuildInstances`):
    /// the stack = the LAST structure item ≤ position's snapshot (none =
    /// no adjustment layers), then every in-scope param item ≤ position
    /// re-applies onto its layer's chain (newest-wins per the shared
    /// dedup tuple — items recorded AFTER a structure edit are already
    /// baked into that snapshot, so re-applying ALL in-scope items is
    /// idempotent and chronology-safe).
    ///
    /// M2-8-2 T3 (KD-5): the rule lives in Core as
    /// `LayerStackProjection.rebuild(history:baseLayer:)` — this body is a
    /// ONE-LINE delegation (the single-path/single-source mandate; the
    /// Copy Adjustments source enumeration shares the SAME function, and
    /// the transfer model must never re-derive a second copy).
    private func rebuildLayerStack() {
        layerStack = LayerStackProjection.rebuild(
            history: history,
            baseLayer: layerStack?.baseLayer ?? BackgroundLayer())
    }
}
