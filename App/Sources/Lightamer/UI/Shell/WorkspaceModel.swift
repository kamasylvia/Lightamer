import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// WorkspaceModel (Plan M2-3-1 T2, KD-2 / D2 = OQ-2 A) — the two-workspace
// routing state of the NEW shell: ONE window, two routed phases (the Alcedo
// WorkspaceHost semantics). The model is the P2/P3 SEAM (本 plan 是缝正本):
// the library collection model (LibraryGridModel), the editor shell and the
// ⌘F search dialog all consume THIS face — later plans only consume, never
// reopen the shape.
//
// LOSSLESS ROUND TRIP (the D2 red line): library → editor → library restores
// the ENTIRE library face verbatim — filter, sort, selection, page anchor,
// scroll position and inspector selection are preserved field-for-field
// (pinned by WorkspaceRoutingTests). The library state is snapshotted at
// editor entry and restored at editor exit; the editor face (current image +
// filmstrip anchor) survives the round trip too (re-entering without a new
// image id reopens the last image).
//
// EXHAUSTIVE SWITCHES: every `switch` over AppPhase is exhaustive with NO
// `default` arm — a future phase case must answer every switch site at
// compile time (the D-16-CONTEXT-3② discipline carried into the shell).
//
// ⌘F PRESENTATION (checker m6, P1 预埋): `isSearchDialogPresented` is a plain
// presentation boolean OWNED here. The P2 GlobalSearchDialog is presented by
// WorkspaceHostView reading THIS boolean — the dialog never self-owns its
// presentation state, so the menu command, the grid and the dialog itself
// stay consistent through one source.
// ─────────────────────────────────────────────────────────────────────────────

/// The two routed workspaces of the shell (D2: single-window two-state
/// routing — no tabs, no second window).
enum AppPhase: Equatable, Sendable {
    case library
    case editor
}

/// The preserved LIBRARY face (everything the library workspace renders
/// from). Every field survives the editor round trip.
struct LibraryPhaseState: Equatable, Sendable {
    /// The collection filter (structured group + lexical plan) — the ONE
    /// source the grid / filmstrip / search dialog agree on (KD-3).
    var filter: ExifSearchFilter
    /// The sort (the five-key library whitelist rides LibraryQueries' guard).
    var sort: FilterSort
    /// The multi-select set (library rowids).
    var selectedIDs: Set<Int64>
    /// The keyset pagination cursor (the last page's last row).
    var pageAnchor: LibraryPageAnchor?
    /// The scroll face (the topmost visible row + the offset into it).
    var scrollPosition: WorkspaceScrollPosition?
    /// The Album Inspector group card selection (nil = overview / none).
    var inspectorSelection: LibraryGroupKey?

    init(
        filter: ExifSearchFilter = ExifSearchFilter(),
        sort: FilterSort = FilterSort(key: .filename, ascending: true),
        selectedIDs: Set<Int64> = [],
        pageAnchor: LibraryPageAnchor? = nil,
        scrollPosition: WorkspaceScrollPosition? = nil,
        inspectorSelection: LibraryGroupKey? = nil
    ) {
        self.filter = filter
        self.sort = sort
        self.selectedIDs = selectedIDs
        self.pageAnchor = pageAnchor
        self.scrollPosition = scrollPosition
        self.inspectorSelection = inspectorSelection
    }
}

/// The preserved EDITOR face. Survives the library round trip (D2).
struct EditorPhaseState: Equatable, Sendable {
    /// The image the editor is opened on (library rowid; nil = none yet).
    var currentImageID: Int64?
    /// The filmstrip's scroll anchor (kept aligned to the current image).
    var filmstripScrollAnchor: Int64?

    init(currentImageID: Int64? = nil, filmstripScrollAnchor: Int64? = nil) {
        self.currentImageID = currentImageID
        self.filmstripScrollAnchor = filmstripScrollAnchor
    }
}

/// The scroll face of a virtualized collection surface: the anchor image id
/// (the topmost visible row) + the pixel offset into that row — enough for
/// the P2 grid / filmstrip to restore the scroll exactly.
struct WorkspaceScrollPosition: Equatable, Sendable {
    var anchorImageID: Int64
    var rowOffset: Double

    init(anchorImageID: Int64, rowOffset: Double = 0) {
        self.anchorImageID = anchorImageID
        self.rowOffset = rowOffset
    }
}

/// The shell's routing state (KD-2). `@MainActor` + `@Observable` — the
/// routing state IS main-thread state (plan risk note: never split out of
/// the actor for testability; tests run on the main actor like the other
/// MainActor model suites).
@MainActor
@Observable
final class WorkspaceModel {

    private(set) var phase: AppPhase = .library

    /// The live library face (restored verbatim on editor exit).
    private(set) var libraryState = LibraryPhaseState()

    /// The live editor face (kept across the round trip).
    private(set) var editorPhase = EditorPhaseState()

    /// The library face as it stood at editor entry (the round-trip
    /// snapshot; restored by `closeEditor`).
    private var preservedLibraryState = LibraryPhaseState()

    /// The ⌘F global-search dialog presentation (P1 预埋, m6). The P2
    /// GlobalSearchDialog is presented by WorkspaceHostView reading THIS
    /// boolean — the dialog never self-owns its presentation state, so the
    /// menu command, the grid and the dialog itself stay consistent through
    /// one source. P2 consumes it ONLY through the two faces below.
    var isSearchDialogPresented = false

    /// The ⌘F presentation route (the menu command + the dialog's own
    /// re-open faces go through here — m6: ONE presentation owner).
    func presentSearchDialog() {
        isSearchDialogPresented = true
    }

    /// The dismissal route (the host's sheet binding writes back through
    /// here; the dialog never pokes the boolean directly).
    func dismissSearchDialog() {
        isSearchDialogPresented = false
    }

    // MARK: - Editor-shell visibility toggles (the View-menu placeholder
    // faces, T5/KD-6 — P3 hangs the real panels on these)

    /// The editor tool rail (History/Versions/Nodes icon column).
    var toolRailVisible = true
    /// The scopes column (histogram/waveform, M2UIW-04).
    var scopesVisible = true
    /// The adjustment stack column (seven tabs).
    var adjustmentStackVisible = true

    // MARK: - P3 editor seams (Plan M2-3-3 T1)

    /// The shell-owned decode actor (D-21 family). The ContentView/
    /// LightamerApp assembly is a zero-diff surface for M2-3-3 (the
    /// front-matter file set excludes both), so the app-owned instance is
    /// unreachable from the new shell — the shell carries its own
    /// long-lived `RAWDecoder`. The actor is stateless (a per-instance
    /// probe cache only) and decode output is a function of
    /// (file, overrides) — `contentDedupeID` keys on the file fingerprint,
    /// so the CI render memo and the pipe caches see identical keys. A
    /// second coexisting instance diverges nothing (DECISIONS D-exec).
    let editorDecoder = RAWDecoder()

    /// The library collection face the editor reads rows through (the
    /// filmstrip source + the EXIF readout + the current-image load leg).
    /// Weak: the grid is OWNED by the host (`@State`); the shell borrows.
    /// Set/dropped by the host's `rebuildLibrarySurface`.
    weak var editorGrid: LibraryGridModel?

    /// The row → source-URL resolver (the ImageLinker face the host builds
    /// beside the grid — zero path guessing in the shell).
    var editorURLResolver: ((LibraryImageRow) -> URL?)?

    /// The current image's library row (the EXIF readout face: the node
    /// header's focal/aperture/shutter/ISO come from here — one lookup,
    /// no copying).
    var currentRow: LibraryImageRow? {
        guard let id = editorPhase.currentImageID else { return nil }
        return editorGrid?.rows.first { $0.id == id }
    }

    // MARK: - RAW decode overrides carrier (Plan M2-3-3 T4, KD-4)

    /// The session-level RAW decode overrides, keyed by the source file
    /// path. Session-scoped by contract: a switched-away image keeps its
    /// values for the session; closing the editor drops them (sidecar
    /// persistence = M2-4's node-model schema, the D3 boundary).
    ///
    /// M2-4-1 T5: the map is ALSO the persisted truth's in-memory face —
    /// `PipeCoordinator.makeSidecarDocument` reads it for the sidecar v5
    /// `rawOverrides` field (one truth, no second mirror), and the restore
    /// leg primes it from a loaded document (`restoreSessionOverrides`).
    private(set) var rawDecodeOverrides: [String: RAWTechnicalOverrides] = [:]

    /// The M2-4-1 T5 persistence channel (E1③ — weak back-reference, the
    /// `EditorState.attach` M2-3-1 pattern; the app-root/host strongly owns
    /// both ends). nil = detached (tests, pre-assembly): the session dict
    /// still works, only the sidecar pass-through is dark.
    private weak var pipeCoordinator: PipeCoordinator?

    /// Wire the sidecar-persistence channel (called once from the host's
    /// assembly task).
    func attach(pipeCoordinator: PipeCoordinator) {
        self.pipeCoordinator = pipeCoordinator
    }

    /// The read face (identity when the image has no session overrides).
    func rawDecodeOverrides(for url: URL) -> RAWTechnicalOverrides {
        rawDecodeOverrides[url.path] ?? .identity
    }

    /// The write face (the RawDecodePanelView routes through here; the
    /// caller then re-issues the `EditorState.load` request chain).
    /// M2-4-1 T5: the persistence pass-through hook rides AFTER the session
    /// dict write — the dict semantics above are untouched (zero diff).
    func setRawDecodeOverrides(_ overrides: RAWTechnicalOverrides, for url: URL) {
        rawDecodeOverrides[url.path] = overrides.isIdentity ? nil : overrides
        if rawDecodeOverrides[url.path] == nil {
            rawDecodeOverrides.removeValue(forKey: url.path)
        }
        pipeCoordinator?.updateRawOverrides(overrides, for: url)
    }

    /// The M2-4-1 T5 restore-leg priming face: seed the session cache from
    /// a LOADED sidecar document WITHOUT the persistence pass-through —
    /// the document IS this value's source, so a write-back echo would
    /// schedule a redundant sidecar write stamped by the identity first
    /// frame (the E1 double-decode window). The panel's user write face
    /// (`setRawDecodeOverrides`) keeps its hook semantics unchanged.
    func restoreSessionOverrides(_ overrides: RAWTechnicalOverrides, for url: URL) {
        rawDecodeOverrides[url.path] = overrides.isIdentity ? nil : overrides
        if rawDecodeOverrides[url.path] == nil {
            rawDecodeOverrides.removeValue(forKey: url.path)
        }
    }

    /// The editor-close drop face (KD-4: 关图丢弃).
    func dropSessionOverrides() {
        rawDecodeOverrides.removeAll()
    }

    // MARK: - DRT record carrier (Plan M2-6-3 T1, KD-1 — the rawOverrides
    // four-piece shape's session-carrier twin)

    /// The session-level document DRT records, keyed by the source file
    /// path. Session-scoped by contract (the rawDecodeOverrides carrier's
    /// shape): a switched-away image keeps its record for the session;
    /// closing the editor drops them (sidecar persistence = the v6
    /// `displayTransform` field). ABSENT KEY = pristine — a DEFAULT record
    /// never occupies the map (KD-1: 默认记录不写 sidecar, the
    /// `isDrtRecordDefault` judgment folds here at the write faces so the
    /// map is always the non-pristine truth).
    private(set) var drtRecords: [String: DrtRecord] = [:]

    /// The read face (pristine when the image has no session record).
    func drtRecord(for url: URL) -> DrtRecord {
        drtRecords[url.path] ?? DrtRecord()
    }

    /// Whether the image carries a NON-pristine session record (the run
    /// pass-through's `.drt` gate + the EDR mutual-exclusion face).
    func hasDrtRecord(for url: URL) -> Bool {
        drtRecords[url.path] != nil
    }

    /// The raw write face — stores the record (nil = pristine, drops the
    /// key), NO coordinator pass-through. Callers that must also schedule
    /// the sidecar write go through the coordinator legs (the persistence
    /// hook lives THERE, mirroring rawOverrides: the carrier is the memory
    /// truth, the coordinator owns the disk face).
    func setSessionDrtRecord(_ record: DrtRecord?, for url: URL) {
        if let record, !isDrtRecordDefault(record) {
            drtRecords[url.path] = record
        } else {
            drtRecords.removeValue(forKey: url.path)
        }
    }

    /// The editor-close drop face (the rawOverrides 关图丢弃 twin).
    func dropSessionDrtRecords() {
        drtRecords.removeAll()
    }


    // MARK: - AI enhancement entry requests (Plan M2-10-07 T3, KD-3)

    /// The editor Image menu's two enhancement commands route through HERE
    /// (the ⌘F presentation-boolean pattern: one presentation owner — the menu
    /// command sets the request, WorkspaceHostView consumes it and presents
    /// the EnhanceDialog sheet; the dialog never self-owns its state).
    enum AIEnhanceKind: Equatable, Sendable {
        case upscale
        case denoise
    }

    struct AIEnhanceRequest: Equatable, Sendable {
        let kind: AIEnhanceKind
        /// The library rowids to enhance (the editor entry = the current
        /// image; the grid entry carries the whole selection).
        let imageIDs: [Int64]
    }

    /// The pending enhancement request (nil = nothing pending; consumed by
    /// the host's onChange leg).
    var pendingAIEnhance: AIEnhanceRequest?

    func requestAIEnhance(
        kind: AIEnhanceKind, imageIDs: [Int64]
    ) {
        pendingAIEnhance = AIEnhanceRequest(kind: kind, imageIDs: imageIDs)
    }

    /// The one consumption face (the host clears after reading).
    func consumeAIEnhance() -> AIEnhanceRequest? {
        let request = pendingAIEnhance
        pendingAIEnhance = nil
        return request
    }

    // MARK: - Phase transitions (the D2 semantics)

    /// Enter the editor on `imageID` (nil = reopen the last image — the
    /// Alcedo re-entry semantics). The library face is snapshotted for the
    /// lossless return. THIS IS THE T1-POINTLIGHT FACE (KD-1/D2 真缝): the
    /// grid's double-click routes through here — `EditorPhaseState` carries
    /// the current image id + the filmstrip anchor from this call.
    func openEditor(imageID: Int64?) {
        if phase == .library {
            preservedLibraryState = libraryState
        }
        if let imageID {
            editorPhase.currentImageID = imageID
        }
        editorPhase.filmstripScrollAnchor =
            editorPhase.currentImageID ?? editorPhase.filmstripScrollAnchor
        phase = .editor
    }

    /// Close the editor back to the library, restoring the snapshotted face
    /// field-for-field (the D2 red line). The session RAW-decode overrides
    /// drop with the editor (KD-4: 关图丢弃) — the DRT carrier rides the
    /// same close (M2-6-3 KD-1 twin).
    func closeEditor() {
        libraryState = preservedLibraryState
        dropSessionOverrides()
        dropSessionDrtRecords()
        phase = .library
    }

    /// The single toggle (⌘E / ⌘W equivalents route here).
    func switchPhase() {
        switch phase {
        case .library: openEditor(imageID: nil)
        case .editor: closeEditor()
        }
    }

    /// The ONE mutation face for the library state (the P2 grid / search
    /// dialog write through this; keeping it a closure keeps the field
    /// read-only to everything else).
    func updateLibraryState(_ mutation: (inout LibraryPhaseState) -> Void) {
        mutation(&libraryState)
    }

    /// The ONE mutation face for the editor state (P3 filmstrip/viewport).
    func updateEditorPhase(_ mutation: (inout EditorPhaseState) -> Void) {
        mutation(&editorPhase)
    }
}
