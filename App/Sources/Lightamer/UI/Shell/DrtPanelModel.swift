import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// DrtPanelModel (Plan M2-6-3 T2, KD-2) — the Display Transform panel's
// ViewModel: a read-only projection of the session carrier + THREE action
// faces, all routed through EditorState's document-level commit face (KD-1:
// the DRT record is a DOCUMENT parameter — every action lands exactly ONE
// `history_drt_*` item; the coordinator notification syncs the carrier,
// re-renders the tail and schedules the sidecar write).
//
// STRUCTURE (FEATURE-MAP §5 line-for-line, M2DRT-01): the Method segmented
// card is ALWAYS expanded and pinned on top; Color & Encoding (a disclosure
// group, expanded by default) carries the six-space menu, the EOTF picker
// (the LEGAL subset from the Core single source — no UI-local copy of the
// linkage table, OQ-5-B rejection) and the Peak slider (100–1000, default
// 100); the ACES 2.0 limiting group renders only under `aces20`; the OpenDRT
// preset trio renders only under `opendrt`. NO detailed-parameter editing
// face (the CONTEXT non-goal — the editor-owned 53-param group is
// preset-snapshot data only).
//
// COMMIT SEMANTICS (KD-2, the commitContinuousEdit :1284 semantic port):
// discrete controls (menus/pickers/method) commit once per click;
// the Peak slider runs the D-H1 trio — beginDrtEdit → setDrtLive (carrier +
// re-render, ZERO items) → commitDrtEdit (exactly ONE item when the drag
// window saw a net change; a no-op drag lands nothing). The commit-time
// judgment is pinned in M2-6-3-DECISIONS.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class DrtPanelModel {

    /// The peak slider's producer range (the dctl slider bounds; the Core
    /// pure functions do NOT clamp — the panel owns validation, KD-2).
    public static let peakRange: ClosedRange<Float> = 100...1000

    private weak var workspace: WorkspaceModel?
    private weak var editorState: EditorState?
    private weak var pipeCoordinator: PipeCoordinator?

    /// All three refs may be nil (tests, pre-assembly): the read face
    /// answers the pristine default and the actions no-op.
    init(
        workspace: WorkspaceModel?, editorState: EditorState?,
        pipeCoordinator: PipeCoordinator?
    ) {
        self.workspace = workspace
        self.editorState = editorState
        self.pipeCoordinator = pipeCoordinator
    }

    // MARK: - Read projection (the carrier is the single in-memory truth)

    var hasImage: Bool {
        pipeCoordinator?.liveImageURL != nil
    }

    /// The current record — the OPEN LIVE WINDOW's pending value FIRST
    /// (the slider's binding must read back what the drag is producing),
    /// then the HISTORY's effective projection (the committed truth:
    /// pointer-faithful across undo/redo, and immune to the carrier-sync
    /// Task's hop lag — rapid successive edits each build on the previous
    /// COMMIT, never on a stale carrier), falling back to the carrier (the
    /// restore-leg field-wins face) and finally the pristine default. The
    /// history and carrier sources agree by construction on every write
    /// path (KD-1); the fallback only matters for foreign documents.
    var record: DrtRecord {
        if let liveRecord { return liveRecord }
        if let editorState, let effective = editorState.history.effectiveDrtRecord() {
            return effective
        }
        guard let url = pipeCoordinator?.liveImageURL, let workspace else {
            return DrtRecord()
        }
        return workspace.drtRecord(for: url)
    }

    /// The pending value of an open live window (nil = no window / clean).
    private var liveRecord: DrtRecord?

    /// The EOTF picker's data source — the Core single source consumed
    /// DIRECTLY (OQ-5-B: the linkage knowledge never gets a UI-local copy).
    var legalEotfs: [DrtEotf] {
        legalEOTFs(for: record.encodingSpace)
    }

    /// The derived custom judgment (OQ-2-A): the 53 params match no
    /// built-in look snapshot → custom. Display value only — never stored.
    var isCustomLook: Bool {
        DrtPresets.isCustomLook(record)
    }

    // MARK: - The structure descriptor (FEATURE-MAP §5, machine-checkable)

    /// One panel section — the structure face the TAB-MATRIX transcription
    /// and the tests both consume (the routing-table transcription rule).
    struct Section: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// The Method segmented card — ALWAYS expanded (no disclosure).
            case method
            /// Color & Encoding — disclosure, expanded by default.
            case colorEncoding
            /// ACES 2.0 limiting group — `.aces20` only.
            case acesLimiting
            /// OpenDRT preset trio — `.opendrt` only.
            case opendrtPresets
        }
        let kind: Kind
        let expandedByDefault: Bool
    }

    /// The section list for a method (组序 = the FEATURE-MAP §5 order;
    /// visibility follows the method switch — the AC#2 assertion face).
    static func sections(method: DrtMethod) -> [Section] {
        var sections: [Section] = [
            Section(kind: .method, expandedByDefault: true),
            Section(kind: .colorEncoding, expandedByDefault: true),
        ]
        switch method {
        case .aces20:
            sections.append(Section(kind: .acesLimiting, expandedByDefault: true))
        case .opendrt:
            sections.append(Section(kind: .opendrtPresets, expandedByDefault: true))
        }
        return sections
    }

    /// The panel's sections for the CURRENT record's method.
    var sections: [Section] {
        Self.sections(method: record.method)
    }

    /// The peak clamp face (the slider binds through this).
    static func clampedPeak(_ value: Float) -> Float {
        min(max(value, peakRange.lowerBound), peakRange.upperBound)
    }

    // MARK: - Action faces (every write lands ONE document-level commit)

    /// The ONE discrete-commit funnel: build the next record, commit it.
    /// The carrier sync + re-render + sidecar write ride the coordinator
    /// notification (EditorState.recordDrtChange → drtRecordDidChange).
    private func commit(_ mutate: (inout DrtRecord) -> Void, label: String) {
        guard let editorState else { return }
        var next = record
        mutate(&next)
        guard next != record else { return } // idempotent click = no item
        editorState.recordDrtChange(next, label: label)
    }

    /// Method switch (the segmented card) — one discrete commit.
    func setMethod(_ method: DrtMethod) {
        commit({ $0.method = method }, label: String(localized: "history_drt_method"))
    }

    /// The preset trio, ONE application at a time (each picker change is a
    /// single discrete commit — undo steps back over it; OQ-2-A). The look
    /// snapshot replaces the 53-param group wholesale, then the tonescale
    /// override applies (DrtPresets.applyPreset is the atomic builder).
    func applyLook(_ look: DrtLookPreset) {
        commit({ record in
            let applied = DrtPresets.applyPreset(
                record: record, look: look,
                tonescale: DrtTonescalePreset(rawValue: record.tonescalePreset)
                    ?? .useLookPreset,
                white: DrtCreativeWhite(rawValue: record.creativeWhite)
                    ?? .useLookPreset)
            record = applied
        }, label: String(localized: "history_drt_preset"))
    }

    func applyTonescale(_ tonescale: DrtTonescalePreset) {
        commit({ record in
            record.tonescalePreset = tonescale.rawValue
            // The tonescale picker overrides ONLY the tn* group onto the
            // CURRENT parameters (the look owns everything else);
            // use_look_preset clears to the look's tn values is NOT done
            // here — the look snapshot's tn values ARE in the params, so
            // the no-override case just keeps them.
            if let o = tonescale.tonescaleOverride {
                record.parameters.tnCon = o.tnCon
                record.parameters.tnSh = o.tnSh
                record.parameters.tnToe = o.tnToe
                record.parameters.tnOff = o.tnOff
                record.parameters.tnHcon = o.tnHcon
                record.parameters.tnHconPv = o.tnHconPv
                record.parameters.tnHconSt = o.tnHconSt
                record.parameters.tnLcon = o.tnLcon
                record.parameters.tnLconW = o.tnLconW
            }
        }, label: String(localized: "history_drt_preset"))
    }

    func applyCreativeWhite(_ white: DrtCreativeWhite) {
        commit(
            { $0.creativeWhite = white.rawValue },
            label: String(localized: "history_drt_preset"))
    }

    // MARK: Color & Encoding (T2 discrete faces; T3 adds the EOTF snap)

    /// Encoding space switch — one discrete commit; the EOTF snap rides
    /// the SAME commit in T3 (the atomic dual-value rule, KD-3).
    func setEncodingSpace(_ space: DrtEncodingSpace) {
        commit({ record in
            record.encodingSpace = space
            let legal = legalEOTFs(for: space)
            if !legal.contains(record.encodingEotf) {
                record.encodingEotf = legal.first ?? record.encodingEotf
            }
        }, label: String(localized: "history_drt_encoding"))
    }

    /// EOTF switch — one discrete commit. The picker's data source is the
    /// legal subset, so an illegal value is unconstructible from the UI.
    func setEncodingEotf(_ eotf: DrtEotf) {
        commit(
            { $0.encodingEotf = eotf },
            label: String(localized: "history_drt_encoding"))
    }

    /// ACES 2.0 limiting space — one discrete commit (the aces20 group).
    func setLimiting(_ space: DrtLimitingSpace) {
        commit(
            { $0.limitingSpace = space },
            label: String(localized: "history_drt_param"))
    }

    /// Peak luminance — the D-H1 LIVE leg (drag tick): carrier + re-render,
    /// ZERO history items. Clamped to the producer range. The pending value
    /// rides `liveRecord` so the binding reads back the drag's own value.
    func setPeakLive(_ nits: Float) {
        guard let pipeCoordinator, let url = pipeCoordinator.liveImageURL else {
            return
        }
        var next = record
        let clamped = Self.clampedPeak(nits)
        guard next.peakLuminance != clamped else { return }
        next.peakLuminance = clamped
        liveRecord = next
        workspace?.setSessionDrtRecord(next, for: url)
        Task { await pipeCoordinator.setDrtLive(next) }
    }

    /// Peak luminance — the drag END (the commit leg; exactly ONE item when
    /// the drag window saw a net change — the commitDrtEdit seed gate).
    func commitPeak() {
        liveRecord = nil
        Task { await pipeCoordinator?.commitDrtEdit(
            label: String(localized: "history_drt_encoding")) }
    }

    /// Arm the peak live window (the slider's onEditingChanged(true)).
    func beginPeakDrag() {
        liveRecord = nil
        pipeCoordinator?.beginDrtEdit()
    }
}
