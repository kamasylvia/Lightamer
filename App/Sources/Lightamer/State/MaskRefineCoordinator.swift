import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// MaskRefineCoordinator (Plan LUMEN-C T2, X8/D-LU-7) — the background fine
// pass' orchestration: single-flight + waiting queue + one-step history
// commit + failure keeps the quick mask.
//
// LUMEN TRANSLITERATION (v2.0.1 `auto_masks.py` refine_masks_later, review
// m-4's line domain): the work runs OFF the image job queue (the CPU fine()
// detaches at .utility); one pass at a time, later requests wait; each
// finished raster replaces the quick one; failure keeps the quick mask and
// surfaces the reason (the mask domain is NEVER emptied by a refine
// failure — RESEARCH §风险 9's double floor, the algorithm's own
// certain-region early return being the first).
//
// TRIGGER FACES (D-LU-7): ① automatic — AIMaskEditing.fineAutoTrigger
// fires on every successful AI raster commit; THIS coordinator debounces
// (1.2s after the LAST write — the patch pass' 1s debounce settles first,
// so the refine reads the settled plane) and gates on `mask.fineAuto`
// (typed read + injectable defaults, default true — the ONE new
// UserDefaults key of the batch, spelled exactly here); ② manual — the
// mask toolbar's「精细化所选蒙版」button and the MCP refine_masks tool
// (T3) both land in `refineLater`.
//
// COMMIT SEMANTICS: the refined plane re-commits through the EXISTING
// `AIMaskEditing.commitRasterMask` seam (the M6-4 history/revision
// channel — HistoryStack/LightamerSidecar zero diff): same AIMaskSource
// (derived from the file prefix) overwrites the same PNG (D-07-CONTEXT-5),
// `patchRebake: true` skips the segment-session re-arm (a refine must not
// re-open the tap session), `refineCommit: true` breaks the trigger loop.
// The optimistic-concurrency gate (`expectedRevision`) captures the mask
// revision when the work STARTS — a concurrent write (a user tap landing
// mid-refine) refuses the install typed (toast, quick mask intact), never
// clobbers.
//
// REGISTERED BOUNDARIES (LUMEN-C-DECISIONS): (a) a multi-id batch commits
// per-mask (N undo steps; Lumen swaps a batch in ONE commit — a batch-wide
// commit would need a new history item type, the sealed surface forbids
// it; the auto path is single-mask = one step either way); (b) the re-bake
// carries featherRadius 0 — the stored PNG already materialized any Edge
// feather (positive percent bakes into the pixels), re-applying would
// double-feather (AIMaskFeather stays zero-diff, X8); (c) the guide leg is
// the headless developed display render (QuickLookRenderer.renderedPlane
// at ≤4096 — the disk-truth develop state); a live session's uncommitted
// slider edits are not in it (the mask semantics anchor to the decode
// frame; the guide is a quality aid).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MaskRefineCoordinator {

    /// The UserDefaults key of the auto-trigger gate (D-LU-7) — the ONE
    /// literal in the repo (the Settings row writes through it).
    nonisolated static let fineAutoKey = "mask.fineAuto"

    /// Typed read: absent key = true (the Lumen fine_masks default-open).
    nonisolated static func fineAutoEnabled(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: fineAutoKey) as? Bool ?? true
    }

    /// The auto-trigger debounce (the patch pass' 1s debounce must settle
    /// first — 1.2s collapses generation+patch bursts into one refine).
    static let autoDebounce: Duration = .seconds(1.2)

    /// The default fine parameters (Lumen `fine()`'s own defaults — the
    /// sky calibration .3/.02 is Lumen's per-kind sample tuning; ours is
    /// one face, DECISIONS pins the values).
    static let defaultNetworkPx = 320
    static let defaultGrow = 0.05
    static let defaultShrink = 0.05

    enum MaskRefineError: LocalizedError {
        case noSession
        case noLayer
        case notAIMask
        case unknownMaskID(String)
        case quickPlaneUnreadable
        case guideUnavailable
        case refineFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSession: return "no open image session"
            case .noLayer: return "layer vanished"
            case .notAIMask: return "not an AI raster mask"
            case .unknownMaskID(let id): return "unknown or non-AI mask id: \(id)"
            case .quickPlaneUnreadable: return "quick mask PNG unreadable"
            case .guideUnavailable: return "guide render unavailable"
            case .refineFailed(let reason): return reason
            }
        }
    }

    private let pipe: PipeCoordinator
    private let editor: EditorState
    private let editing: LayerEditingState
    private let metal: MetalContext?
    private let registry: ModuleRegistry
    private let defaults: UserDefaults

    /// Test seam: the guide provider (nil = the production headless
    /// developed-display render). `imageURL → guide`.
    var guideProvider: (@Sendable (URL) async throws -> MaskRefineGuide)?

    init(
        pipe: PipeCoordinator,
        editor: EditorState,
        editing: LayerEditingState,
        metal: MetalContext?,
        registry: ModuleRegistry,
        defaults: UserDefaults = .standard
    ) {
        self.pipe = pipe
        self.editor = editor
        self.editing = editing
        self.metal = metal
        self.registry = registry
        self.defaults = defaults
    }

    // MARK: - Single flight + waiting queue (refine_masks_later form)

    /// The running pass' layer ids (dedupe: a re-trigger while pending
    /// joins the pending set, not a second pass).
    private var pending: [UUID] = []
    /// Later requests wait here (Lumen `fine_waiting`); drained after the
    /// current pass.
    private var waiting: [UUID] = []
    private var running = false

    /// True while one pass is in flight (the manual button's disabled
    /// face + the tests' single-flight sentinel).
    var isBusy: Bool { running }

    /// The queued-but-not-started count (tests).
    var waitingCount: Int { waiting.count }

    /// AUTOMATIC trigger (the fineAuto hook's landing): gated by
    /// `mask.fineAuto`, debounced — each fire cancels the previous sleep,
    /// so a burst of raster commits collapses into ONE scheduled refine of
    /// the LAST written mask.
    func scheduleAutoRefine(layerID: UUID) {
        guard Self.fineAutoEnabled(defaults: defaults) else { return }
        autoTask?.cancel()
        autoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoDebounce)
            guard !Task.isCancelled else { return }
            await self?.refineLater([layerID])
        }
    }

    private var autoTask: Task<Void, Never>?

    /// MANUAL / MCP entry: validate + enqueue. Unknown / non-AI ids are
    /// dropped typed (the MCP tool surfaces them; the button gates first).
    func refineLater(_ layerIDs: [UUID]) {
        var accepted: [UUID] = []
        for id in layerIDs {
            guard canRefine(layerID: id), !pending.contains(id),
                !waiting.contains(id)
            else { continue }
            accepted.append(id)
        }
        guard !accepted.isEmpty else { return }
        if running {
            waiting.append(contentsOf: accepted)
            return
        }
        pending = accepted
        running = true
        Task { [weak self] in
            await self?.pump()
        }
    }

    /// The MCP face (T3): string ids → layer UUIDs; an unknown or
    /// non-refinable id is a TYPED error (the tool face — no silent drop),
    /// valid ids enqueue through the same single-flight pump.
    func refineMasksForMCP(_ ids: [String]) async throws {
        var resolved: [UUID] = []
        for id in ids {
            guard let uuid = UUID(uuidString: id), canRefine(layerID: uuid) else {
                throw MaskRefineError.unknownMaskID(id)
            }
            resolved.append(uuid)
        }
        guard !resolved.isEmpty else { return }
        refineLater(resolved)
    }

    /// The pre-flight face: an open session + the layer exists + its mask
    /// carries an AI-prefixed raster (only AI masks refine).
    func canRefine(layerID: UUID) -> Bool {
        guard editor.loadedImageURL != nil,
            let layer = editor.adjustmentLayer(id: layerID),
            let ref = layer.mask?.raster,
            AIMaskSource.source(ofFileName: ref.fileName) != nil
        else { return false }
        return true
    }

    /// ONE pass at a time: drain the pending list, then the waiting queue
    /// (the Lumen finish() re-dispatch shape). Any per-mask failure toasts
    /// and moves on — the queue never stalls on one bad mask.
    private func pump() async {
        while !pending.isEmpty {
            let id = pending.removeFirst()
            do {
                try await process(layerID: id)
            } catch {
                let reason = error.localizedDescription
                editor.presentToast(
                    String(localized: "ai_mask_refine_failed") + " (\(reason))")
            }
        }
        running = false
        if !waiting.isEmpty {
            let next = waiting
            waiting = []
            refineLater(next)
        }
    }

    // MARK: - One mask's pass

    /// Load the quick plane → render the guide → `MaskRefine.fine` (the
    /// CPU leg detaches at .utility) → one-step history commit. Every
    /// precondition failure throws BEFORE any state change (the quick mask
    /// stays).
    func process(layerID: UUID) async throws {
        guard let metal else { throw MaskRefineError.guideUnavailable }
        guard let imageURL = editor.loadedImageURL else {
            throw MaskRefineError.noSession
        }
        // The armed identity + revision (captured BEFORE the awaits — an
        // image switch mid-pass drops the result; a concurrent mask write
        // fails the revision gate at commit time).
        let armedURL = imageURL
        guard let layer = editor.adjustmentLayer(id: layerID) else {
            throw MaskRefineError.noLayer
        }
        guard let ref = layer.mask?.raster,
            let source = AIMaskSource.source(ofFileName: ref.fileName)
        else { throw MaskRefineError.notAIMask }
        let expectedRevision = layer.mask?.contentRevision
        let directory = RasterMaskStore.masksDirectory(forImageURL: armedURL)
        guard let quick = RasterMaskStore.loadPlane(ref: ref, directory: directory)
        else { throw MaskRefineError.quickPlaneUnreadable }
        let guide: MaskRefineGuide
        if let guideProvider {
            guide = try await guideProvider(armedURL)
        } else {
            guide = try await renderGuide(imageURL: armedURL, metal: metal)
        }
        // The CPU fine pass — off the main thread (Lumen's own-thread
        // semantics; the image job queue stays free).
        let networkPx = Self.defaultNetworkPx
        let grow = Self.defaultGrow
        let shrink = Self.defaultShrink
        let refined = try await Task.detached(priority: .utility) {
            MaskRefine.fine(
                alpha: quick, guide: guide, networkPx: networkPx,
                grow: grow, shrink: shrink)
        }.value
        // The identity re-check BEFORE the commit (the image switched
        // mid-pass → the plane belongs to the previous identity).
        guard editor.loadedImageURL == armedURL else {
            throw MaskRefineError.noSession
        }
        _ = try await AIMaskEditing.commitRasterMask(
            plane: refined, source: source,
            invert: ref.invert,
            featherRadius: 0,
            imageURL: armedURL,
            label: String(localized: "history_mask_refine"),
            activateTool: nil,
            coordinator: pipe, editorState: editor,
            editingState: editing, metal: metal,
            expectedRevision: expectedRevision,
            patchRebake: true,
            refineCommit: true)
    }

    /// The guide leg: the developed display-domain render at ≤4096 long
    /// edge (the headless chain's RGBA8 plane → floats).
    private func renderGuide(
        imageURL: URL, metal: MetalContext
    ) async throws -> MaskRefineGuide {
        let rendered = try await QuickLookRenderer.renderedPlane(
            imageURL: imageURL, targetLongEdge: MaskRefine.fineEdge,
            metal: metal, registry: registry, decodeLeg: nil,
            pristineOnly: false)
        let plane = rendered.plane
        let bytes = [UInt8](plane.data)
        let count = plane.width * plane.height * 4
        guard plane.layout == .rgba8, bytes.count == count else {
            throw MaskRefineError.guideUnavailable
        }
        var rgba = [Float](repeating: 0, count: count)
        for i in 0..<count { rgba[i] = Float(bytes[i]) / 255 }
        return MaskRefineGuide(width: plane.width, height: plane.height, rgba: rgba)
    }
}
