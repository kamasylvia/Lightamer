import Foundation
import LightamerCore
import LightamerIOP
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelModel (Plan M3-3-03 T3, KD-3; extended M3-4-01 T3, KD-3) — the
// film-simulation panel's ViewModel: DrtPanelModel's structural twin. Read =
// the three-level projection (the open live window's pending value FIRST,
// then the history's effective projection — the committed truth,
// pointer-faithful across undo/redo — then the coordinator's carrier face,
// which covers the sidecar restore leg's field-wins priming); write = every
// action lands exactly ONE `history_film_*` item through EditorState's
// document-level commit face, or the D-H1 live/commit pair for sliders.
//
// M3-4-01 EXTENSION (FSIM-02): the latitude section (the stats snapshot +
// the descriptor read face + the below/inside/above shares + the two
// teaching notes) and the PLACEMENT EDITING SECTION (the resolver's single
// source lives in `PlacementResolver` below: anchors = live stats P99.9/P0.1
// + the descriptor's useful EV pair, the no-film fallback constants
// demoted to the documented fallback arm; validity = the T1 typed faces
// only — rule ① rides the sliders' dynamic minimums, rule ② is the typed
// refusal naming a slider, rule ③ is the Fit's suggestion-face guard).
// The placement instance rides the EXISTING command faces: lookup through
// the coordinator's sibling-record face, add through
// `addAdjustmentLayer`+`addModuleToLayer` (the grade envelope hosts it),
// params through the M2-5 per-op D-H1 session shape.
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
    ///
    /// m2① errata note (audit-repair RESEARCH §4, zero code): the solve is
    /// NOT a per-tick full solve — `FilmRuntimeSolve.solve` consults
    /// `FilmSolveCache.shared.autoSolution(for:)` internally
    /// (LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift:629); the
    /// per-tick residual is the cache key computation + the dictionary hit
    /// + two `store.profile(id:)` reads. No further caching here.
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

    // MARK: - The process migration row (Plan M8-3 T3, M6-2 §6 正主)

    /// The document's stored render generation (nil = no image; the absent
    /// carrier answers `.legacy` — the coordinator read face's contract).
    var documentProcess: RenderProcessVersion? {
        guard let coordinator = pipeCoordinator, coordinator.liveImageURL != nil
        else { return nil }
        return coordinator.documentProcessVersion
    }

    /// The migration row's gate — the pure model's evaluate face (the
    /// panel never re-derives it: the action's inputs are the coordinator's
    /// read faces and the evaluation is a pure function).
    var migrationAction: FilmMigrationAction {
        guard let coordinator = pipeCoordinator, let url = coordinator.liveImageURL
        else { return .notApplicable }
        return FilmMigrationAction.evaluate(
            processRawValue: coordinator.documentProcessVersion?.rawValue,
            hasFilmRecord: coordinator.hasFilmRecord(for: url),
            editingInFlight: coordinator.filmEditInFlight)
    }

    /// The confirm sheet's confirm leg (the ONE production caller of the
    /// coordinator's migration face).
    func runMigration() {
        Task { await pipeCoordinator?.runProcessMigration() }
    }

    // MARK: - The latitude section (FSIM-02, KD-3)

    /// The histogram's native EV axis (256 bins × [0,1] linear through the
    /// bin→EV formula — the drawable span; [−12,+12] is the descriptor
    /// ramp's domain and never mixes with this axis, checker m4).
    static let latitudeAxisMinEV = Foundation.log2(0.5 / 256.0 / 0.184)
    static let latitudeAxisMaxEV = Foundation.log2(255.5 / 256.0 / 0.184)

    /// bin→EV: the contentAdaptiveShift.channelEV formula (one source).
    static func binEV(_ bin: Int) -> Double {
        Foundation.log2((Double(bin) + 0.5) / 256.0 / 0.184)
    }

    /// The consumed medium descriptor (nil = the probe hasn't landed for
    /// the current pair — the dashed lines stay absent + noted, never
    /// fake data).
    var latitudeDescriptor: ProfileLatitudeDescriptor?
    /// The pair hash the current descriptor was probed for (the refresh
    /// gate — a material switch re-probes once).
    private var latitudeDescriptorPairHash: UInt64 = 0
    private var latitudeDescriptorTask: Task<Void, Never>?

    /// The film stats' read face (the coordinator's mirrored snapshot —
    /// the panel's ONLY stats source, mechanism (c)).
    var latitudeStats: FilmStatsSeam.PlaneHistogram? {
        pipeCoordinator?.filmStatsSnapshot
    }

    /// The descriptor refresh (cache-first; the probe is the compute-back).
    /// Driven by the view on the pair-identity change.
    func refreshLatitudeDescriptor() {
        guard let coordinator = pipeCoordinator,
            let store = coordinator.filmMaterialStore,
            !record.filmStock.isEmpty, !record.paperStock.isEmpty,
            let film = store.profile(id: record.filmStock),
            let paper = store.profile(id: record.paperStock)
        else {
            latitudeDescriptor = nil
            latitudeDescriptorPairHash = 0
            return
        }
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        guard pairHash != latitudeDescriptorPairHash else { return }
        latitudeDescriptorPairHash = pairHash
        latitudeDescriptorTask?.cancel()
        latitudeDescriptorTask = Task { [weak self] in
            let descriptor = await coordinator.filmDescriptor(
                film: film, paper: paper, materialPairHash: pairHash)
            guard !Task.isCancelled else { return }
            self?.latitudeDescriptor = descriptor
        }
    }

    /// The share readout (below / inside / above the useful pair), from
    /// the LUMA histogram counts against the linear thresholds. Whole-bin
    /// classification: a bin counts BELOW only when its entire range sits
    /// under the threshold, ABOVE only when entirely over — a straddling
    /// bin counts INSIDE (the ≤1-bin tolerance, DECISIONS). nil levels =
    /// nil (the descriptor's absence is presented, never faked).
    static func latitudeShares(
        histogram: FilmStatsSeam.PlaneHistogram,
        belowEV: Double?, aboveEV: Double?
    ) -> (below: Double, inside: Double, above: Double)? {
        guard let belowEV, let aboveEV else { return nil }
        let luma = histogram.perChannel[3]
        let total = luma.reduce(0) { $0 + Int($1) }
        guard total > 0 else { return nil }
        let vLow = 0.184 * Foundation.pow(2.0, belowEV)
        let vHigh = 0.184 * Foundation.pow(2.0, aboveEV)
        var below = 0
        var inside = 0
        var above = 0
        for (bin, count) in luma.enumerated() {
            let lowEdge = Double(bin) / 256.0
            let highEdge = Double(bin + 1) / 256.0
            if highEdge <= vLow {
                below += Int(count)
            } else if lowEdge >= vHigh {
                above += Int(count)
            } else {
                inside += Int(count)
            }
        }
        return (
            Double(below) / Double(total),
            Double(inside) / Double(total),
            Double(above) / Double(total))
    }

    // MARK: - The placement editing section (KD-3; the resolver single
    // source = `PlacementResolver` below)

    /// The document's placement instance, wherever it sits: the base
    /// chain's flat set first, then the adjustment layers' chains (the
    /// add face lands it in a LAYER — the grade envelope's host — so the
    /// layer chains are the primary residence). The host layer id rides
    /// along: the edit session routes layer-scoped (the 06-05 dual-track).
    ///
    /// m2③ (AR-01 T3): the layer-leg scan is memoized and REFRESHED at the
    /// model's write faces (addPlacement / commitPlacement /
    /// tickPlacementRecord / resetPlacementSide / stepM), with a live-truth
    /// VALIDATION on every read as the master guard — the validation reads
    /// the same observable faces the rescan would (the coordinator registry
    /// + `editorState.adjustmentLayer(id:)`), so the dependency registration
    /// is preserved (no stale UI: an undo/redo or a foreign edit fails the
    /// validation and forces the full rescan). Hit-path cost basis (the
    /// F-3 evidence): one `adjustmentLayer(id:)` jump + one chain
    /// first-where + one `ModuleInstance ==` — strictly below the rescan's
    /// `compactMap` array allocation + the front-of-stack layer walk. The
    /// base-chain leg stays un-memoized (the registry probe is already a
    /// dictionary hit — memoizing it would add overhead, not remove it).
    var placementTarget: (instance: ModuleInstance, layerID: UUID?)? {
        guard let coordinator = pipeCoordinator else { return nil }
        if let instance = coordinator.instanceRecord(opName: FilmPlacementModule.opName) {
            placementTargetMemo = nil
            return (instance, nil)
        }
        if let memo = placementTargetMemo,
            let layerID = memo.layerID,
            let layer = editorState?.adjustmentLayer(id: layerID),
            let found = layer.chain.first(
                where: { $0.opName == FilmPlacementModule.opName }),
            found == memo.instance {
            return (instance: memo.instance, layerID: memo.layerID)
        }
        placementTargetMemo = nil
        let layers = editorState?.layerStack?.adjustmentLayers.compactMap {
            $0 as? AdjustmentLayer
        } ?? []
        for layer in layers {
            if let instance = layer.chain.first(
                where: { $0.opName == FilmPlacementModule.opName }) {
                let target = (instance: instance, layerID: layer.id)
                placementTargetMemo = target
                return target
            }
        }
        return nil
    }

    /// The m2③ layer-leg memo (the write-point refresh + read validation —
    /// see placementTarget).
    @ObservationIgnored private var placementTargetMemo:
        (instance: ModuleInstance, layerID: UUID?)?

    /// The placement edit session (the M2-5 provider shape, routed to the
    /// host layer when the record lives in a layer chain).
    private func placementSession(layerID: UUID?) -> InspectorEditSession? {
        guard let coordinator = pipeCoordinator else { return nil }
        return InspectorEditSession(coordinator: coordinator, layerScope: layerID)
    }

    /// The ADD face (the existing command surfaces, zero new commands):
    /// ensure a host layer (the topmost adjustment layer, else ONE
    /// structure commit) + land the identity template in its chain (ONE
    /// commit). The placement is a grade-domain op — the ACEScc envelope
    /// wraps it ONLY inside an adjustment layer's sub-run.
    @discardableResult
    func addPlacement() -> ModuleInstance? {
        guard let editorState else { return nil }
        placementTargetMemo = nil  // m2③: write-point refresh
        let layerID: UUID
        if let top = editorState.layerStack?.adjustmentLayers.last {
            layerID = top.id
        } else {
            guard let created = editorState.addAdjustmentLayer() else { return nil }
            layerID = created.id
        }
        guard let template = EditorState.templateInstance(
            for: FilmPlacementModule.opName)
        else { return nil }
        return editorState.addModuleToLayer(layerID: layerID, template: template)
    }

    /// The resolver's current anchors (live stats + descriptor; any miss
    /// drops to the fallback constants + the note flag).
    var placementAnchors: PlacementAnchors {
        PlacementResolver.anchors(
            stats: latitudeStats, descriptor: latitudeDescriptor)
    }

    /// The resolve + write (ONE discrete commit through the D-H1 session):
    /// the resolver's validity faces are the panel's ONLY write gate —
    /// rule ② refusal names a slider in the view, no silent clamp.
    func commitPlacement(nH: Double, nS: Double, m: Float) -> PlacementResolveOutcome {
        placementTargetMemo = nil  // m2③: write-point refresh
        switch PlacementResolver.resolve(
            anchors: placementAnchors, nH: nH, nS: nS, m: m) {
        case .failure(let rejection):
            return .rejected(rejection)
        case .success(let params):
            guard let target = placementTarget else { return .rejected(.noInstance) }
            guard let record = PanelEditing.updated(
                target.instance, params: params, as: FilmPlacementModule.self)
            else { return .rejected(.noInstance) }
            placementSession(layerID: target.layerID)?.applyDiscrete(
                record, label: String(localized: "history_film_placement"))
            return .committed
        }
    }

    /// The Fit face (§9.3, ONE discrete commit): the default policy pair,
    /// the m≥3 crossing share, the H_min suggestion-face guard (a refusal
    /// writes NOTHING — the manual values stay).
    func applyFit(m: Float) -> PlacementFitOutcome {
        let outcome = PlacementResolver.fit(anchors: placementAnchors, m: m)
        guard !outcome.refusedByHMin else { return outcome }
        switch commitPlacement(nH: outcome.nH, nS: outcome.nS, m: m) {
        case .committed:
            return outcome
        case .rejected(let rejection):
            var refused = outcome
            refused.refusedByHMin = true
            refused.rejection = rejection
            return refused
        }
    }

    /// The placement params of the document's instance (nil = none).
    var placementParams: FilmPlacementModule.Params? {
        guard let target = placementTarget else { return nil }
        return PanelEditing.params(of: target.instance, as: FilmPlacementModule.self)
    }

    /// The typed refusal surfaced by the last write attempt (the view
    /// names the slider; cleared by the next successful commit).
    var lastPlacementRejection: PlacementReject?
    /// The last Fit's outcome (the refusal/shared/off notes ride it).
    var lastFitOutcome: PlacementFitOutcome?

    /// The placement live window (the M2-5 per-op provider shape: the
    /// ticks write the RESOLVER's output — resolved knees + pull-backs —
    /// so the preview rides the same math the commit lands).
    private func tickPlacementRecord(
        _ mutate: (inout FilmPlacementModule.Params) -> Void
    ) {
        placementTargetMemo = nil  // m2③: write-point refresh
        guard let target = placementTarget else { return }
        var params = placementParams ?? FilmPlacementModule.Params()
        mutate(&params)
        switch PlacementResolver.resolve(
            anchors: placementAnchors,
            nH: Double(params.highlightsPullBack),
            nS: Double(params.shadowsPullBack),
            m: params.rolloff)
        {
        case .success(let resolved):
            lastPlacementRejection = nil
            if let record = PanelEditing.updated(
                target.instance, params: resolved, as: FilmPlacementModule.self) {
                placementSession(layerID: target.layerID)?.update(record)
            }
        case .failure(let rejection):
            // The typed refusal: the tick does NOT write — the slider
            // binding reads the instance truth and springs back.
            lastPlacementRejection = rejection
        }
    }

    /// D-H1 drag START (zero items until the commit).
    func beginPlacementDrag() {
        placementSession(layerID: placementTarget?.layerID)?.beginEditing()
    }

    /// The N_h tick (the resolver re-solves; a rejection leaves the truth).
    func tickPlacement(highlights: Double?, shadows: Double?) {
        tickPlacementRecord { params in
            if let highlights {
                params.highlightsPullBack = Float(highlights)
            }
            if let shadows {
                params.shadowsPullBack = Float(shadows)
            }
        }
    }

    /// D-H1 drag END: exactly ONE history item (the window's net gate).
    func endPlacementDrag() {
        placementSession(layerID: placementTarget?.layerID)?.endEditing(
            label: String(localized: "history_film_placement"))
    }

    /// The double-click reset (one side to the OFF identity).
    func resetPlacementSide(highlights: Bool) {
        placementTargetMemo = nil  // m2③: write-point refresh
        guard let target = placementTarget else { return }
        var params = placementParams ?? FilmPlacementModule.Params()
        if highlights {
            params.highlightsPullBack = 0
            params.kHighlight = nil
            params.hHighlight = nil
        } else {
            params.shadowsPullBack = 0
            params.kShadow = nil
            params.hShadow = nil
        }
        // The reset re-resolves the surviving side (one discrete commit).
        switch PlacementResolver.resolve(
            anchors: placementAnchors,
            nH: Double(params.highlightsPullBack),
            nS: Double(params.shadowsPullBack),
            m: params.rolloff) {
        case .success(let resolved):
            lastPlacementRejection = nil
            if let record = PanelEditing.updated(
                target.instance, params: resolved, as: FilmPlacementModule.self) {
                placementSession(layerID: target.layerID)?.applyDiscrete(
                    record, label: String(localized: "history_film_placement"))
            }
        case .failure(let rejection):
            lastPlacementRejection = rejection
        }
    }

    /// The m stepper (ONE discrete commit per click; the resolve re-runs
    /// at the new order — the m≥3 crossing is the expected physics and
    /// names its slider through the typed refusal).
    func stepM(_ m: Float) {
        placementTargetMemo = nil  // m2③: write-point refresh
        guard let target = placementTarget else { return }
        let clamped = FilmPlacementModule.clamped(
            FilmPlacementModule.Params(
                shadowsPullBack: placementParams?.shadowsPullBack ?? 0,
                highlightsPullBack: placementParams?.highlightsPullBack ?? 0,
                rolloff: m))
        switch PlacementResolver.resolve(
            anchors: placementAnchors,
            nH: Double(clamped.highlightsPullBack),
            nS: Double(clamped.shadowsPullBack),
            m: clamped.rolloff) {
        case .success(let resolved):
            lastPlacementRejection = nil
            if let record = PanelEditing.updated(
                target.instance, params: resolved, as: FilmPlacementModule.self) {
                placementSession(layerID: target.layerID)?.applyDiscrete(
                    record, label: String(localized: "history_film_placement"))
            }
        case .failure(let rejection):
            lastPlacementRejection = rejection
        }
    }

    /// The Fit gesture (§9.3, ONE discrete commit when it lands).
    func runFit(m: Float) {
        let outcome = applyFit(m: m)
        lastFitOutcome = outcome
    }
}

// MARK: - The placement resolver (KD-3's validity single source — the App
// side of the T1 typed faces)

/// The resolver's anchor set (stops relative to mid-gray). `usedFallback`
/// = the no-film fallback constants answered (the panel notes it).
struct PlacementAnchors: Equatable {
    var aH: Double
    var cH: Double
    var aS: Double
    var cS: Double
    var usedFallback: Bool
}

enum PlacementReject: Equatable, Error {
    /// §9.2 rule ② — the identity core collapsed; the panel names a
    /// slider (never a silent clamp).
    case kneeOrder
    /// The T1 typed invalid-demand face, named per side.
    case highlightDemand
    case shadowDemand
    case noInstance
}

enum PlacementResolveOutcome: Equatable {
    case committed
    case rejected(PlacementReject)
}

/// The Fit outcome (the suggestion face — a refusal writes NOTHING).
struct PlacementFitOutcome: Equatable {
    var nH: Double = 0
    var nS: Double = 0
    /// The m≥3 crossing share engaged (the recommended pair is the
    /// proportionally scaled one, or the sides-off degenerate).
    var sharedDeficit = false
    /// The recommendation landed at both-sides-off (§9.3's degenerate).
    var sidesOff = false
    /// The H_min suggestion-face guard fired — the recommendation is
    /// WITHHELD (the panel shows the notice; manual values stay).
    var refusedByHMin = false
    /// The resolver's rejection when the apply leg failed (diagnostic).
    var rejection: PlacementReject?

    static func == (lhs: PlacementFitOutcome, rhs: PlacementFitOutcome) -> Bool {
        lhs.nH == rhs.nH && lhs.nS == rhs.nS && lhs.sharedDeficit == rhs.sharedDeficit
            && lhs.sidesOff == rhs.sidesOff && lhs.refusedByHMin == rhs.refusedByHMin
    }
}

enum PlacementResolver {

    /// The Fit policy constants (§9.3's defaults + the §7.3 curvature
    /// ceiling — the DECISIONS-registered calibration: 0.8587/3.0 ≈ 0.286
    /// = the mapper's peak magnitude anchor at m=2, §6.1's 0.289).
    static let fitMargin = 0.25
    static let hMin = 3.0

    /// The anchors: the film stats' P99.9/P0.1 (integer rank through
    /// `FilmRuntimeSolve.percentileBin`, bin→EV the channelEV formula) +
    /// the descriptor's useful pair. Any miss = the documented no-film
    /// fallback constants (the M3-3 constants, demoted — never deleted).
    static func anchors(
        stats: FilmStatsSeam.PlaneHistogram?,
        descriptor: ProfileLatitudeDescriptor?
    ) -> PlacementAnchors {
        let fallback = PlacementAnchors(
            aH: FilmPlacementModule.sceneTopEV, cH: FilmPlacementModule.mediumTopEV,
            aS: FilmPlacementModule.sceneBottomEV, cS: FilmPlacementModule.mediumBottomEV,
            usedFallback: true)
        guard let descriptor else { return fallback }
        var aH: Double?
        var aS: Double?
        if let stats {
            let luma = stats.perChannel[3]
            let topBin = FilmRuntimeSolve.percentileBin(luma, fraction: 0.999)
            let bottomBin = FilmRuntimeSolve.percentileBin(luma, fraction: 0.001)
            aH = log2((Double(topBin) + 0.5) / 256.0 / 0.184)
            aS = log2((Double(bottomBin) + 0.5) / 256.0 / 0.184)
        }
        guard let topEV = aH, let bottomEV = aS else { return fallback }
        return PlacementAnchors(
            aH: topEV, cH: descriptor.usefulHighlightEV,
            aS: bottomEV, cS: descriptor.usefulShadowEV,
            usedFallback: false)
    }

    /// The sliders' dynamic minimums (§9.2 rule ①, the side-explicit form:
    /// the shadow side's literal a−C substitution is NEGATIVE — the true
    /// lower bound is C−a; max(0, ·) covers the side-off degenerate).
    static func sliderMinimums(
        anchors: PlacementAnchors, margin: Double = PlacementResolver.fitMargin
    ) -> (nH: Double, nS: Double) {
        (
            max(0, (anchors.aH - anchors.cH) + margin),
            max(0, (anchors.cS - anchors.aS) + margin)
        )
    }

    /// The resolve: both sides against the anchors → the joint validity →
    /// the v2 params (resolved knees + pull-backs, one unit).
    static func resolve(
        anchors: PlacementAnchors, nH: Double, nS: Double, m: Float
    ) -> Result<FilmPlacementModule.Params, PlacementReject> {
        let hi = FilmPlacementModule.solveKnee(
            pullBack: nH, rolloff: Double(m),
            sceneExtreme: anchors.aH, mediumBoundary: anchors.cH)
        let lo = FilmPlacementModule.solveKnee(
            pullBack: nS, rolloff: Double(m),
            sceneExtreme: anchors.aS, mediumBoundary: anchors.cS)
        guard let hi else { return .failure(.highlightDemand) }
        guard let lo else { return .failure(.shadowDemand) }
        switch FilmPlacementModule.validateCoreOrder(highlights: hi, shadows: lo) {
        case .valid:
            return .success(FilmPlacementModule.Params(
                shadowsPullBack: Float(nS), highlightsPullBack: Float(nH), rolloff: m,
                kShadow: lo.knee, hShadow: lo.room,
                kHighlight: hi.knee, hHighlight: hi.room))
        case .kneeOrderViolation:
            return .failure(.kneeOrder)
        }
    }

    /// The Fit (§9.3's default policy): land each robust extreme a quarter
    /// stop inside the medium; a side whose scene extreme sits at/below
    /// its boundary goes OFF (the degenerate that matters most); the m≥3
    /// crossing shares the deficit proportionally (the pair's ratio kept,
    /// the landing degenerate = both sides off + reported); the H_min
    /// curvature ceiling REFUSES the recommendation (the suggestion face —
    /// the manual values are never touched).
    static func fit(
        anchors: PlacementAnchors, m: Float,
        margin: Double = PlacementResolver.fitMargin,
        hMin: Double = PlacementResolver.hMin
    ) -> PlacementFitOutcome {
        var outcome = PlacementFitOutcome()
        // §9.3's side-off degenerate: a ≤ C → the branch is the identity.
        let baseNH = anchors.aH > anchors.cH ? (anchors.aH - anchors.cH) + margin : 0
        let baseNS = anchors.cS > anchors.aS ? (anchors.cS - anchors.aS) + margin : 0
        outcome.nH = baseNH
        outcome.nS = baseNS
        if case .failure(let rejection) = resolve(
            anchors: anchors, nH: baseNH, nS: baseNS, m: m) {
            if rejection == .kneeOrder {
                // The m≥3 crossing: scale the pair, ratio kept — the
                // deficit spent proportionally (40-step deterministic
                // bisection on λ; λ→0 = the sides-off degenerate).
                var low = 0.0
                var high = 1.0
                for _ in 0..<40 {
                    let mid = (low + high) / 2
                    if case .success = resolve(
                        anchors: anchors, nH: baseNH * mid, nS: baseNS * mid, m: m) {
                        low = mid
                    } else {
                        high = mid
                    }
                }
                if low > 0 {
                    outcome.nH = baseNH * low
                    outcome.nS = baseNS * low
                } else {
                    outcome.nH = 0
                    outcome.nS = 0
                    outcome.sidesOff = true
                }
                outcome.sharedDeficit = true
            } else {
                // An invalid-demand at the fit's own anchors: refuse the
                // recommendation (the suggestion face).
                outcome.refusedByHMin = false
                outcome.rejection = rejection
                outcome.nH = 0
                outcome.nS = 0
                outcome.sidesOff = true
                return outcome
            }
        }
        // The H_min guard (§7.3): a solved side's room below the ceiling
        // → withhold the recommendation (the manual values stay).
        if case .success(let params) = resolve(
            anchors: anchors, nH: outcome.nH, nS: outcome.nS, m: m) {
            if params.highlightsPullBack > 0, let hH = params.hHighlight, hH < hMin {
                outcome.refusedByHMin = true
            }
            if params.shadowsPullBack > 0, let hS = params.hShadow, hS < hMin {
                outcome.refusedByHMin = true
            }
        }
        return outcome
    }

    /// The §9.2 endpoint slope readout: f'(a∓) = g'_Δ = (1+w)^−(m+1)/m at
    /// the scene extreme (the §5.4 pair's Δ face — the documented formula).
    static func endpointSlope(
        extreme a: Double, boundary c: Double, knee k: Double, m: Double
    ) -> Double {
        let delta = abs(a - k)
        let room = max(abs(c - k), 1e-9)
        guard delta > 0 else { return 1 }
        let w = Foundation.pow(delta / room, m)
        return Foundation.pow(1 + w, -(m + 1) / m)
    }
}
