import Foundation
import LightamerCore
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

    // ── 02-05 history mutators (the ONLY writers of history/instances) ──

    /// Seed a freshly loaded image to PRISTINE: empty history + the
    /// default-chain records as the live instance set (the coordinator
    /// passes `ModuleRegistry.makeDefaultInstances()`).
    func resetHistoryForNewImage(defaultInstances: [ModuleInstance]) {
        history = HistoryStack()
        baseInstances = defaultInstances
        instances = defaultInstances
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

    /// 04-08-F2 (GUI-9 闭环): menu enablement source — true while the
    /// stack has an entry at/below the pointer to step back into.
    /// The Edit → Undo menu binds `.disabled(!canUndo)` to this, so ⌘Z
    /// availability always mirrors the Phase 2 stack semantics.
    var canUndo: Bool { history.position >= 0 }

    /// 04-08-F2: redo availability — a non-empty tail past the pointer
    /// (undo followed by NO new commit; any commit truncates it).
    var canRedo: Bool { history.position + 1 < history.items.count }

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
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
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
    func load(url: URL, decoder: RAWDecoder, metal: MetalContext?, logger: Logger) {
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
                let decoded = try await decoder.decode(url) // off-MainActor
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
        let layer = AdjustmentLayer(name: Self.nextLayerName(in: layerStack))
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
    @discardableResult
    func addModuleToLayer(layerID: UUID, template: ModuleInstance) -> ModuleInstance? {
        guard let layer = adjustmentLayer(id: layerID) else { return nil }
        let record = template.clonedWithFreshIdentity()
        layer.chain.append(record)
        layer.chain.sort {
            ($0.iopOrder, $0.multiPriority, $0.opName)
                < ($1.iopOrder, $1.multiPriority, $1.opName)
        }
        commitLayerStructure(layerID: layerID, label: String(localized: "history_layer_module_add"))
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
    /// marker) + the post-edit FULL stack snapshot.
    private func commitLayerStructure(layerID: UUID, label: String) {
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
        notifyLayerChange(persist: true)
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
        let layer = RetouchLayer(name: Self.nextLayerName(in: layerStack))
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
    private func rebuildLayerStack() {
        var stack = LayerStack(baseLayer: layerStack?.baseLayer ?? BackgroundLayer())
        let upTo = history.position >= 0 ? Array(history.items[0...history.position]) : []
        if let lastStructure = upTo.lastIndex(where: {
            $0.layerScope == Self.layerStructureScope
        }), let snapshot = upTo[lastStructure].stackSnapshot {
            for layer in snapshot.makeLayers() { stack.addAdjustment(layer) }
        }
        for item in upTo where item.layerScope != nil && item.layerScope != Self.layerStructureScope {
            guard let layer = stack.compositeLayers.first(where: {
                $0.id.uuidString == item.layerScope
            }) as? AdjustmentLayer else { continue }
            layer.chain = HistoryStack.effectiveChain(layer.chain + [item.snapshot])
        }
        self.layerStack = stack
    }

    /// The default layer name: "调整 N" style ordinal (never reused —
    /// derived from the current stack size + a collision sweep).
    private static func nextLayerName(in stack: LayerStack) -> String {
        let base = String(localized: "layer_default_name")
        let existing = Set(stack.compositeLayers.map(\.name))
        var ordinal = stack.compositeLayers.count + 1
        var candidate = "\(base) \(ordinal)"
        while existing.contains(candidate) {
            ordinal += 1
            candidate = "\(base) \(ordinal)"
        }
        return candidate
    }
}
