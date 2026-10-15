import Foundation
import LightamerCore
import LightamerIOP
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchPanelModel (Plan M5-1-02 T6/T7, KD-6/KD-7; TRACK-04) — the
// colormatch panel's ViewModel: the FilmPanelModel structural twin adapted
// to the PER-INSTANCE params channel.
//
// READ (the three-level projection): the open live window's pending
// params FIRST (the strength drag reads back its own value), then the
// SNAPSHOT of the chain's committed record (decoded once per committed
// change at a discrete refresh point — V2M-01 T1 defect D-1: the binding
// get must stay a pure local read, never a per-layout coordinator scan +
// JSONDecoder), finally the pristine default.
//
// WRITE: every discrete action lands exactly ONE history item through the
// InspectorEditSession face (the per-instance params channel — ZERO new
// history key family); the strength slider rides the D-H1 live/commit
// trio (the M2-5 per-op session shape).
//
// REFERENCES (KD-7, TRACK-02): the multi-reference list is PANEL SESSION
// STATE — never persisted (the committed truth is the pooled solve
// product); reopening an image starts with an empty list and re-solve
// re-picks. N = 1 is the default single-row flow.
//
// PRESENTATION (L057): the reference file panel goes through
// `PanelPresentation.present` — `runModal` never appears on this path.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class ColorMatchPanelModel {

    /// The strength producer range (the params' domain).
    static let strengthRange: ClosedRange<Float> = 0...1
    /// The reference weight producer range (normalized at pooling — the
    /// slider is the RAW ratio face).
    static let weightRange: ClosedRange<Float> = 0...1

    /// One reference row (panel session state — never persisted).
    struct ReferenceRow: Identifiable, Equatable {
        let id: UUID
        let url: URL
        var name: String
        var weight: Float
        /// The extracted statistics (nil = not yet extracted / failed).
        var stats: ColorMatchStats?
        /// The extraction/typed failure face (the readout discloses it).
        var errorText: String?
    }

    /// The passed-in record (the inspector re-renders with the current
    /// projection — the model refreshes through `updateInstance`).
    private(set) var instance: ModuleInstance?
    private weak var editorState: EditorState?
    private weak var pipeCoordinator: PipeCoordinator?
    private let decoder = RAWDecoder()

    // The committed-truth SNAPSHOT (Plan V2M-01 T1, defect D-1): the chain
    // record decoded ONCE per committed change at a discrete refresh point
    // (init / the view-level `updateInstance` hook / the solve backfill /
    // the strength-commit tail) — NEVER per binding-get read. The strength
    // slider's binding get runs during SwiftUI layout; reading through
    // `pipeCoordinator.instanceRecord` there re-scans `editorState.instances`
    // and re-runs JSONDecoder on EVERY layout pass, registering the hot
    // observables as layout-attribute dependencies and starving the
    // MainActor (the D-1 flush storm). The getters below read ONLY local
    // state; the coordinator is touched exclusively from action contexts.
    private var snapshotParams: ColormatchModule.Params?
    private var snapshotRecord: ModuleInstance?

    /// The service (owned by the shell composition root; shared across
    /// panel lifetimes — the session curves + the pipe faces live there).
    private let service: ColorMatchService

    /// The panel's edit session (the InspectorView hands one in — the
    /// active layer scope rides it).
    private var editSession: InspectorEditSession?

    /// The multi-reference list (session state; N=0 = the pristine panel).
    private(set) var references: [ReferenceRow] = []

    /// The in-flight solve face (the button spins; actions serialize).
    private(set) var isSolving = false
    /// The last typed failure (the panel discloses; the toast rides too).
    private(set) var solveError: String?

    init(
        instance: ModuleInstance?, editorState: EditorState?,
        pipeCoordinator: PipeCoordinator?, service: ColorMatchService,
        editSession: InspectorEditSession? = nil
    ) {
        self.instance = instance
        self.editorState = editorState
        self.pipeCoordinator = pipeCoordinator
        self.service = service
        self.editSession = editSession
        refreshSnapshot(from: instance)
    }

    // MARK: - The committed-truth snapshot refresh (V2M-01 T1)

    /// Adopt a new committed projection: the view's `.onChange(of: instance)`
    /// seam fires this on every re-render that carries a new instance value
    /// (instance switch / post-commit re-render / MCP `apply_params`
    /// external writes / undo-redo + version-swap `rebuildInstances`). The
    /// passed value IS the committed truth (both sides derive from
    /// `editorState.instances`), so decoding it here needs no coordinator
    /// read. Action/hook context only — never layout.
    func updateInstance(_ newInstance: ModuleInstance?) {
        instance = newInstance
        refreshSnapshot(from: newInstance)
    }

    /// Re-decode the snapshot from a record (one decode per refresh).
    private func refreshSnapshot(from record: ModuleInstance?) {
        snapshotRecord = record
        snapshotParams = record.flatMap { try? $0.params(of: ColormatchModule.self) }
    }

    /// Re-read the chain's current record and refresh the snapshot from it
    /// (the solve backfill — action context, never layout).
    private func refreshSnapshotFromChain() {
        let current = pipeCoordinator?.instanceRecord(opName: ColormatchModule.opName)
        refreshSnapshot(from: current ?? instance)
    }

    // MARK: - Read projection (the three-level face)

    /// The live window's pending params (nil = no drag / clean).
    private var liveParams: ColormatchModule.Params?

    var hasImage: Bool { pipeCoordinator?.liveImageURL != nil }

    /// The current params: the live drag window's value → the SNAPSHOT of
    /// the chain's committed record (refreshed at discrete points — the
    /// binding get is a pure local read, zero coordinator touches; V2M-01
    /// T1) → the passed-in record (layer scopes / pre-assembly) → the
    /// pristine default.
    var params: ColormatchModule.Params {
        if let liveParams { return liveParams }
        if let snapshotParams { return snapshotParams }
        if let instance, let decoded = try? instance.params(of: ColormatchModule.self) {
            return decoded
        }
        return ColormatchModule.Params()
    }

    /// Whether a colormatch record exists in the current chain (the
    /// add/solve face creates it on the first solve — the P1 placeholder
    /// add-face is the manual route).
    var hasInstance: Bool { instance != nil }

    // MARK: - The solve actions (T6)

    /// Add a reference row from a file URL (the PanelPresentation seam's
    /// landing point). The row's stats extract lazily at solve time (the
    /// reference decode is the expensive leg — one decode per solve, then
    /// the service's session cache).
    func addReference(url: URL) {
        guard !references.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL })
        else { return }
        references.append(
            ReferenceRow(
                id: UUID(), url: url, name: url.lastPathComponent,
                weight: 1, stats: nil, errorText: nil))
    }

    /// Remove a reference row.
    func removeReference(id: UUID) {
        references.removeAll { $0.id == id }
    }

    /// A weight slider tick (the list row's inline slider — normalized at
    /// pooling, the slider is the raw ratio).
    func setWeight(_ value: Float, id: UUID) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].weight = min(max(value, Self.weightRange.lowerBound), Self.weightRange.upperBound)
    }

    /// THE SOLVE: extract source + references, pool, solve, attach — one
    /// discrete commit. The re-solve edge (a second press) rides
    /// `invalidateAll` first (the G1 re-solve closure).
    func solve(solver: ColorMatchSolverKind, strength: Float) {
        guard let editorState, let pipeCoordinator, !isSolving else { return }
        guard !references.isEmpty else {
            solveError = String(localized: "colormatch_error_no_reference")
            return
        }
        isSolving = true
        solveError = nil
        // The re-solve edge: the second press re-extracts everything (the
        // registered feedback-loop break — E5's plane makes it stable).
        service.invalidateAll()
        let service = self.service
        let references = self.references
        Task { [weak self] in
            defer { self?.isSolving = false }
            do {
                let source = try await service.extractSourceStats(
                    coordinator: pipeCoordinator, editorState: editorState)
                var entries: [ColorMatchPoolEntry] = []
                for row in references {
                    do {
                        let stats = try await service.extractReferenceStats(
                            imageURL: row.url, decoder: self?.decoder ?? RAWDecoder())
                        entries.append(ColorMatchPoolEntry(stats: stats, weight: Double(row.weight)))
                    } catch {
                        // A dead reference degrades the solve with a typed
                        // message naming the row (the panel discloses).
                        self?.setRowError(row.id, String(localized: "colormatch_error_reference_unreadable"))
                        throw AppError.decodeFailed(
                            "colormatch reference \(row.name): \(error)")
                    }
                }
                _ = try await service.solveAndAttach(
                    source: source, references: entries, solver: solver,
                    strength: strength, editorState: editorState,
                    coordinator: pipeCoordinator)
                self?.clearRowErrors()
                self?.liveParams = nil
                self?.solveError = nil
                // The solve backfill: the attach landed new committed
                // params — refresh the snapshot from the chain (action
                // context; the view seam re-confirms on the next re-render).
                self?.refreshSnapshotFromChain()
            } catch {
                self?.solveError = String(localized: "colormatch_error_solve_failed")
                self?.pipeCoordinator?.presentToast("\(error.localizedDescription)")
            }
        }
    }

    private func setRowError(_ id: UUID, _ text: String) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].errorText = text
    }

    private func clearRowErrors() {
        for index in references.indices { references[index].errorText = nil }
    }

    // MARK: - The strength D-H1 trio (the M2-5 per-op session shape)

    /// The drag's base — the SNAPSHOT record (V2M-01 T1: zero coordinator
    /// touches; the commit's async landing re-seats the snapshot through
    /// the view seam, and the commit-tail refresh below carries the final
    /// live params so a re-drag before that landing builds on its own
    /// value). Basing ticks on the STALE passed-in record would wipe
    /// fields the panel doesn't edit (the solved assetRef family) — the
    /// snapshot keeps the committed identity + the freshest params.
    private var currentRecord: ModuleInstance? {
        snapshotRecord ?? instance
    }

    func beginStrengthDrag() {
        liveParams = nil
        editSession?.beginEditing()
    }

    func setStrengthLive(_ value: Float) {
        guard var next = currentRecord ?? instancePlaceholder else { return }
        var p = (try? next.params(of: ColormatchModule.self)) ?? ColormatchModule.Params()
        p.strength = min(max(value, Self.strengthRange.lowerBound), Self.strengthRange.upperBound)
        try? next.setParams(p, as: ColormatchModule.self)
        liveParams = p
        editSession?.update(next)
    }

    func commitStrengthDrag() {
        // The commit-tail snapshot refresh (refresh point ④ — the LIVE
        // VALUE arm, C-2): the commit lands asynchronously, so re-reading
        // the chain record HERE would seat the pre-drag value for the
        // window until the view seam re-fires; the last live value IS the
        // commit's snapshot (the tick = the commit payload), so adopting
        // it directly keeps the read face continuous across the async gap.
        let lastLive = liveParams
        liveParams = nil
        if let lastLive {
            snapshotParams = lastLive
            if var record = snapshotRecord ?? instance {
                try? record.setParams(lastLive, as: ColormatchModule.self)
                snapshotRecord = record
            }
        }
        editSession?.endEditing(label: String(localized: "history_colormatch"))
    }

    /// A pristine template (the actions that need a record when the panel
    /// opened before the first solve).
    private var instancePlaceholder: ModuleInstance? {
        ModuleInstance(
            module: ColormatchModule.self, multiPriority: 0, multiName: "",
            params: ColormatchModule.Params())
    }

    // MARK: - The readout (KD-6: solver/effectiveSolver/statsHash/support)

    /// The readout bundle (nil lines hide; never fake data — the film
    /// panel's dashed-absent posture).
    var readout: (solver: String, effective: String, statsHash: String?, supportWidth: String?) {
        let p = params
        let solverName = Self.solverDisplayName(p.solver)
        let effectiveName = p.effectiveSolver.map(Self.solverDisplayName) ?? solverName
        let support: String? = service.lastSourceStats.map { stats in
            let widths = (0..<3).map { channel -> Double in
                Double(stats.supportHi[channel] - stats.supportLo[channel])
            }
            return String(
                localized: "colormatch_readout_support",
                defaultValue: "L ±\(String(format: "%.2f", widths[0]))  a ±\(String(format: "%.2f", widths[1]))  b ±\(String(format: "%.2f", widths[2]))")
        }
        return (solverName, effectiveName, p.sourceStatsHash, support)
    }

    /// The asset degrade probe (the typed-degrade readout face — a nil
    /// reason means the asset verifies or doesn't exist yet).
    var degradeNote: String? {
        guard let assetRef = params.assetRef else { return nil }
        return service.resolver.lastDegradeReason
    }

    static func solverDisplayName(_ solver: ColorMatchSolverKind) -> String {
        switch solver {
        case .gaussianOT: return String(localized: "colormatch_solver_gaussian_ot")
        case .reinhard: return String(localized: "colormatch_solver_reinhard")
        case .cdf: return String(localized: "colormatch_solver_cdf")
        }
    }
}
