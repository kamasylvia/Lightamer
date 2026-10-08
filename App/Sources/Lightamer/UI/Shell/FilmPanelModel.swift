import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelModel (Plan M3-3-03 T3, KD-3) — the film-simulation panel's
// ViewModel: DrtPanelModel's structural twin. Read = the three-level
// projection (the open live window's pending value FIRST, then the history's
// effective projection — the committed truth, pointer-faithful across
// undo/redo — then the coordinator's carrier face, which covers the sidecar
// restore leg's field-wins priming); write = every action lands exactly ONE
// `history_film_*` item through EditorState's document-level commit face, or
// the D-H1 live/commit pair for sliders (drag ticks re-render with ZERO
// items through the coordinator's film live window; the drag end commits
// exactly ONE item when the window saw a net change).
//
// PANEL SCOPE (KD-3's裁界): the film/paper pickers (the material store's
// typed lists, display = info.name, value = stock id; a material change =
// ONE commit — the solve cache re-keys naturally on the pair hash), the Y/M
// dual sliders (CC domain 0-100, the panel owns the clamp — Core does not),
// strength (0-1) + exposure trim (-3..3 EV) sliders, the content-adaptive
// offset Toggle (default off — the SpektraLab-aligned behavior), the solve
// readout row (the current effective (M, Y, gain), read-only) with the
// Solve button (the solve cache's invalidation face), and the enable entry
// (pristine documents: one tap commits the default-pair record — enabling
// IS an edit, the KD-3 pristine-gate note). NO tolerance teaching face, no
// histogram, no descriptor — FSIM-02 (M3-4). NO placement parameters (the
// filmPlacement op is the M3-4 add-face placeholder).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class FilmPanelModel {

    /// The slider producer ranges (the record's domains; the Core pure
    /// functions do NOT clamp — the panel owns validation, the DrtPanel
    /// split).
    public static let shiftRange: ClosedRange<Float> = 0...100
    public static let strengthRange: ClosedRange<Float> = 0...1
    public static let exposureRange: ClosedRange<Float> = -3...3

    private weak var editorState: EditorState?
    private weak var pipeCoordinator: PipeCoordinator?

    /// Both refs may be nil (tests, pre-assembly): the read face answers the
    /// pristine default and the actions no-op.
    init(editorState: EditorState?, pipeCoordinator: PipeCoordinator?) {
        self.editorState = editorState
        self.pipeCoordinator = pipeCoordinator
    }

    // MARK: - Read projection (the three-level KD-3 face)

    var hasImage: Bool {
        pipeCoordinator?.liveImageURL != nil
    }

    /// The current record — the OPEN LIVE WINDOW's pending value FIRST (the
    /// slider binding reads back the drag's own value), then the HISTORY's
    /// effective projection (the committed truth), then the coordinator's
    /// CARRIER face (the sidecar restore leg primes the carrier without a
    /// history item — the render's truth), finally the pristine default.
    var record: FilmRecord {
        if let liveRecord { return liveRecord }
        if let editorState, let effective = editorState.history.effectiveFilmRecord() {
            return effective
        }
        if let coordinator = pipeCoordinator, let carrier = coordinator.currentFilmRecord {
            return carrier
        }
        return FilmRecord()
    }

    /// The pending value of an open live window (nil = no window / clean).
    private var liveRecord: FilmRecord?

    /// The pristine gate: the document carries NO film record (the panel
    /// shows the enable entry; enabling = the first commit).
    var isPristine: Bool {
        let r = record
        return r.filmStock.isEmpty && r.paperStock.isEmpty
            && r.mFilterShift == 0 && r.yFilterShift == 0
            && !r.contentAdaptiveShift && r.strength == 1.0 && r.exposureEv == 0
            && !hasActiveRecord
    }

    /// Whether the RENDER face sees a record (the carrier's non-pristine
    /// gate — the coordinator's own `hasFilmRecord` face).
    var hasActiveRecord: Bool {
        guard let url = pipeCoordinator?.liveImageURL else { return false }
        return pipeCoordinator?.hasFilmRecord(for: url) ?? false
    }

    /// The film picker's data source — the store's stock-id-sorted list.
    var filmStocks: [FilmProfile] {
        pipeCoordinator?.filmMaterialStore?.filmStocks() ?? []
    }

    /// The paper picker's data source.
    var paperStocks: [FilmProfile] {
        pipeCoordinator?.filmMaterialStore?.paperStocks() ?? []
    }

    /// A stock's display name (the asset's info.name; unknown ids degrade to
    /// the raw id — the typed-degrade posture).
    func displayName(for stockId: String) -> String {
        guard !stockId.isEmpty,
            let profile = pipeCoordinator?.filmMaterialStore?.profile(id: stockId)
        else { return stockId }
        return profile.info.name ?? stockId
    }

    /// The solve readout: the CURRENT effective dials (the neutral pack ⊕
    /// the content-adaptive projection when armed ⊕ the manual shifts ⊕ the
    /// gain with the EV trim). Computed through the production solve (the
    /// cache consult is value-invisible); a nil store / unbound pair
    /// answers nil (the readout hides).
    var solveReadout: (magentaCC: Double, yellowCC: Double, gain: Double)? {
        guard let coordinator = pipeCoordinator,
            let store = coordinator.filmMaterialStore,
            !record.filmStock.isEmpty, !record.paperStock.isEmpty,
            let film = store.profile(id: record.filmStock),
            let paper = store.profile(id: record.paperStock)
        else { return nil }
        guard let solution = try? FilmRuntimeSolve.solve(
            record: record, film: film, paper: paper,
            materialPairHash: FilmMaterialStore.materialPairHash(film: film, paper: paper),
            histogram: nil)
        else { return nil }
        return (solution.magentaCC, solution.yellowCC, solution.exposureGain)
    }

    /// The Solve button: force a re-solve through the cache invalidation
    /// face (the readout recomputes on the next read).
    func forceResolve() {
        FilmSolveCache.shared.invalidateAll()
    }

    // MARK: - The enable entry (pristine → the default-pair record)

    /// Enabling = ONE commit of the default-pair record (the first sorted
    /// film × paper — the deterministic default session). The commit makes
    /// the document non-pristine by the key-presence gate, and the RENDER
    /// face activates (a stock-less default record would gate off in
    /// `filmTailPolicy` — the default PAIR is the honest enable).
    func enableFilm() {
        guard let film = filmStocks.first, let paper = paperStocks.first else {
            return
        }
        commit({ record in
            record.filmStock = film.info.stock ?? ""
            record.paperStock = paper.info.stock ?? ""
        }, label: String(localized: "history_film_enable"))
    }

    // MARK: - Action faces (every write lands ONE document-level commit)

    /// The ONE discrete-commit funnel (the DrtPanelModel shape).
    private func commit(
        _ mutate: (inout FilmRecord) -> Void, label: String
    ) {
        guard let editorState else { return }
        var next = record
        mutate(&next)
        guard next != record else { return }   // idempotent click = no item
        editorState.recordFilmChange(next, label: label)
    }

    /// Film stock switch — ONE discrete commit (the solve cache re-keys on
    /// the pair hash naturally).
    func setFilmStock(_ id: String) {
        commit({ $0.filmStock = id }, label: String(localized: "history_film_material"))
    }

    /// Paper stock switch — ONE discrete commit.
    func setPaperStock(_ id: String) {
        commit({ $0.paperStock = id }, label: String(localized: "history_film_material"))
    }

    /// The content-adaptive offset arm — ONE discrete commit (default off =
    /// the SpektraLab-aligned behavior).
    func setContentAdaptive(_ on: Bool) {
        commit(
            { $0.contentAdaptiveShift = on },
            label: String(localized: "history_film_param"))
    }

    // MARK: - The D-H1 live/commit trio (the sliders)

    /// The drag arm (onEditingChanged(true)): open the coordinator's film
    /// live window (zero items during the drag).
    func beginDrag() {
        liveRecord = nil
        pipeCoordinator?.beginFilmEdit()
    }

    private func setLive(_ mutate: (inout FilmRecord) -> Void) {
        guard let pipeCoordinator else { return }
        var next = record
        mutate(&next)
        guard next != record else { return }
        liveRecord = next
        Task { await pipeCoordinator.setFilmLive(next) }
    }

    /// Y dial live tick (clamped into the CC producer range).
    func setYShiftLive(_ cc: Float) {
        setLive { $0.yFilterShift = min(max(cc, Self.shiftRange.lowerBound), Self.shiftRange.upperBound) }
    }

    /// M dial live tick (clamped into the CC producer range).
    func setMShiftLive(_ cc: Float) {
        setLive { $0.mFilterShift = min(max(cc, Self.shiftRange.lowerBound), Self.shiftRange.upperBound) }
    }

    /// Strength live tick (clamped 0-1).
    func setStrengthLive(_ value: Float) {
        setLive { $0.strength = min(max(value, Self.strengthRange.lowerBound), Self.strengthRange.upperBound) }
    }

    /// Exposure trim live tick (clamped ±3 EV).
    func setExposureLive(_ ev: Float) {
        setLive { $0.exposureEv = min(max(ev, Self.exposureRange.lowerBound), Self.exposureRange.upperBound) }
    }

    /// The drag end (onEditingChanged(false)): exactly ONE history item when
    /// the drag window saw a net change (the coordinator's seed gate).
    func commitDrag() {
        liveRecord = nil
        Task { await pipeCoordinator?.commitFilmEdit(
            label: String(localized: "history_film_shift")) }
    }
}
