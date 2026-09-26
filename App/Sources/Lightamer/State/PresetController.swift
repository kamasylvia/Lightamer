import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// PresetController (Plan 12-4 T3) — the App-side preset APPLY face.
//
// The D-03b isolated state object bridging the UI (the Inspector preset
// panel, the manager window) to the Core `PresetApplier` (the paste-twin
// batch face — GUI apply and the Phase 14 MCP-09 tools share it). The
// controller holds NO back-references to other states: the app root wires
// the per-session (root/store/writer/seed) inputs plus FOUR closure seams
// (the MetadataController pattern):
//
//   targetsProvider      — browser/culling selection, else the editor's
//                          current image (the 12-1 command routing shape)
//   liveRelPathsProvider — the currently edited image's relPath set
//   livePaste            — the interactive-layer install for the LIVE
//                          target (ONE ⌘Z-able commit; dt
//                          _safe_history_job_on_imgid — the batch loop
//                          skips the live image, the interactive layer
//                          pastes it)
//   composeCurrent       — the ⌘⇧C compose产物 (skip set applied) for
//                          「从当前图创建预设」
//   onWrite              — the browser-model reload seam
//
// All failures are SC#2 soft: logged + surfaced as `false`/thrown typed
// errors, never a crash.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class PresetController {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "preset-ctl")

    /// The per-session apply inputs (nil = no open session).
    private(set) var root: URL?
    private var store: SessionIndexStore?
    private var writer: BatchSidecarWriter?
    private var seed: [ModuleInstance] = []
    private var presetsStore: PresetsStore?

    // MARK: - The app-root closure seams (D-03b)

    var targetsProvider: (() -> [String])?
    var liveRelPathsProvider: (() -> Set<String>)?
    var livePaste: (
        (_ payload: PastePayload, _ selection: Set<PastePayload.InstanceKey>?,
         _ mode: PasteMode) async -> Void
    )?
    var composeCurrent: (() async -> PastePayload?)?
    var onWrite: (() async -> Void)?

    func configure(
        root: URL, store: SessionIndexStore,
        writer: BatchSidecarWriter?, seed: [ModuleInstance],
        presetsStore: PresetsStore
    ) {
        self.root = root
        self.store = store
        self.writer = writer
        self.seed = seed
        self.presetsStore = presetsStore
    }

    /// Session teardown (before the index closes).
    func invalidate() {
        root = nil
        store = nil
        writer = nil
        seed = []
    }

    // MARK: - Apply (single + batch — PRES-04; the routing is the caller's
    // targets: the browser/culling SELECTION when non-empty, else the
    // editor's current image — the same shape as the 12-1 metadata
    // commands)

    /// Apply one develop preset over the routed targets. The LIVE target
    /// (currently edited, when among the targets) is skipped by the batch
    /// and installed through `livePaste` (ONE ⌘Z-able commit). Partial
    /// apply rides `selection` (the checked `InstanceKey` subset).
    @discardableResult
    func apply(
        presetID: String,
        selection: Set<PastePayload.InstanceKey>? = nil,
        mode: PasteMode = .merge
    ) async -> Bool {
        guard let root, let store, let presetsStore else { return false }
        let targets = targetsProvider?() ?? []
        guard !targets.isEmpty else {
            Self.logger.warning("preset apply: no target image")
            return false
        }
        let live = liveRelPathsProvider?() ?? []
        let liveInTargets = live.filter { targets.contains($0) }
        do {
            let outcome = try await PresetApplier.apply(
                presetID: presetID, presetsStore: presetsStore,
                root: root, relPaths: targets, mode: mode,
                seed: seed, selection: selection,
                liveRelPaths: Set(liveInTargets),
                indexStore: store, writer: writer,
                label: String(localized: "history_apply_preset"))
            Self.logger.info(
                "preset applied: \(outcome.appliedRelPaths.count, privacy: .public) target(s), \(outcome.skippedLiveRelPaths.count, privacy: .public) live")
            // The live target pastes through the interactive layer (the
            // batch skipped it; ONE ⌘Z undoes the whole install).
            if !liveInTargets.isEmpty {
                let document = try presetsStore.loadDocument(id: presetID)
                let payload = PresetApplier.makePayload(
                    from: document,
                    copiedAt: PresetApplier.fileTime(
                        store: presetsStore, presetID: presetID))
                await livePaste?(payload, selection, mode)
            }
            await onWrite?()
            return true
        } catch {
            Self.logger.error(
                "preset apply failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Create from the current image (the manager's entry)

    /// 「从当前图创建预设」: compose the CURRENT effective chain through the
    /// copy path (skip set applied by `PastePayload.compose` — D-09-
    /// CONTEXT-5 正本), then persist it as a develop preset. Throws the
    /// store's typed errors (empty name).
    @discardableResult
    func createPresetFromCurrent(name: String, category: String?) async throws
        -> StoredPreset
    {
        guard let presetsStore else {
            throw PresetError.notFound(id: "no-library")
        }
        guard let payload = await composeCurrent?(),
              !payload.instances.isEmpty else {
            throw PresetError.emptyComposition
        }
        return try presetsStore.create(
            name: name, kind: .develop, category: category,
            instances: payload.instances)
    }
}
