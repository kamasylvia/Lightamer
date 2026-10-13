import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// VersionCoordinator (Plan M2-8-1 T2, KD-2; D-M2-8-CONTEXT-2/3/4/5/11) — the
// side-orchestration observable for the VERSION dimension:
//
//   • `EditorState.history` stays the ONLY chain truth source — the active
//     version IS the live history (OQ-4-A, zero rebuild); the coordinator
//     holds version METADATA + the NON-ACTIVE chains and performs swaps.
//   • The swap is ONE MainActor-synchronous state transfer (outgoing
//     capture → install → target clear → activate) with NO await point —
//     the disk never sees a mid-swap state because `makeSidecarDocument`
//     reads the POST-swap snapshot once and SidecarStore writes it as one
//     atomic tmp-promote document (KD-2's write atomicity answer); rapid
//     re-clicks merge into the same 2s debounce write.
//   • Switch immediacy = chain swap + `rebuildLayerStack()` param replay
//     (the single path, milliseconds) + the coordinator notification chain
//     (re-render + DRT carrier re-sync — the M2-6-3 undo restore-leg
//     shape). Decode textures ride PipeCache: same-image switches never
//     re-decode. rawOverrides deliberately do NOT follow the version (the
//     image-global decode domain — swapping them would trigger a re-decode
//     and violate immediacy; KD-2 signed exclusion).
//   • materialize-on-first-create: the implicit single version stays
//     KEY-LESS (v6 bytes) until the first create command materializes it
//     as 「版本 1」.
//   • The projection sink (KD-5) is INJECTED (the shell's load point);
//     Sessions mode never assembles one, so the projection is naturally
//     skipped (L036: views read nothing here; the assembly root injects).
// ─────────────────────────────────────────────────────────────────────────────

/// One version slot in the in-memory list. `chain == nil` marks the ACTIVE
/// slot — its items live in `EditorState.history` and are captured INTO the
/// slot only when another version activates (the swap's outgoing leg).
struct VersionSlot: Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// nil = the ACTIVE slot (truth = `EditorState.history`).
    var chain: HistoryStack?
}

/// The `.lalb` version_ref projection sink (KD-5): assembled by the shell
/// when a project is open (`EditorWorkspaceShellView.loadCurrentImage` —
/// the row.id seam); nil in Sessions mode. The projection is a REBUILDABLE
/// mirror of the `.lra` truth — failures log, never block editing.
struct VersionProjectionSink: Sendable {
    /// The `images.id` row the current image's `.lra` belongs to.
    let elementID: Int64
    let store: LibraryStore
}

@Observable
@MainActor
final class VersionCoordinator {

    nonisolated private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "versions"
    )

    /// The version list. EMPTY = the implicit single version (the panel's
    /// empty state — P2 consumes); the implicit chain is never materialized
    /// into `versions[]` until the first create command (KD-2).
    private(set) var slots: [VersionSlot] = []

    /// The active version's id (nil = the implicit single version).
    private(set) var activeVersionID: UUID?

    /// Weak back-reference (the pipeCoordinator attach pattern) — the app
    /// root strongly owns both.
    weak var editorState: EditorState?

    /// The pipe owner back-reference: version commands notify it for the
    /// re-render + sidecar write (the one-edge notification face).
    private weak var pipeCoordinator: PipeCoordinator?

    /// The `.lalb` projection sink (KD-5; injected by the shell, T3).
    var projection: VersionProjectionSink?

    // ── M6-1-01 omp E-OMP-1 (b): the coordinator-level read-only gate ────

    /// Injectable read-only gate — the app root reads
    /// `libraryProjects.isReadOnly` into it (the ExportState seam shape;
    /// nil default = writable, every existing construction and test is
    /// zero-diff). When the gate reads TRUE every write command below
    /// (createFromScratch / branchFromCurrent / pasteChain / switchTo /
    /// rename / remove) typed-no-ops: the FIRST defense is the Versions
    /// panel's disabled projection (E-OMP-1 (d)), this is the backstop so
    /// no stray path lands sidecar bytes through `installVersionChain` +
    /// `finishVersionAction` (and the version_ref projection tail). No
    /// throw, no crash, no new copy key — the EditorState guard family's
    /// silent shape.
    var projectReadOnlyGate: (() -> Bool)? = nil

    /// The same-source boolean for the panel's disabled projection
    /// (E-OMP-1 (d)): true = the open project is on the read-only face.
    /// Body-evaluation reads stay Observable-tracked: the closure executes
    /// synchronously inside the view body, so the captured controller's
    /// `isReadOnly` is a tracked access.
    var isReadOnly: Bool {
        guard let projectReadOnlyGate else { return false }
        return projectReadOnlyGate()
    }

    nonisolated private static let readOnlyLogger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "versions-readonly"
    )

    /// The gate read (shared by the write-command family): true = suppressed.
    private func projectWriteSuppressed() -> Bool {
        guard let projectReadOnlyGate, projectReadOnlyGate() else { return false }
        Self.readOnlyLogger.debug(
            "version command suppressed: project is read-only")
        return true
    }

    /// Wire the editor + pipe faces (called once by the app root beside the
    /// other attaches).
    func attach(editorState: EditorState, pipeCoordinator: PipeCoordinator) {
        self.editorState = editorState
        self.pipeCoordinator = pipeCoordinator
    }

    // MARK: - Restore (the KD-4 hydrate leg; called by PipeCoordinator)

    /// Hydrate from a loaded document. `versions == nil` (a v6 document, or
    /// an image whose `.lra` carries no version structure) RESETS to the
    /// implicit single-version state — slots cleared, `history` kept
    /// (checker E4: an A-image slot list must never leak into B's panel or
    /// its next materialize; the SAME path as removing the last version).
    /// A dangling `activeVersionID` (no matching slot) typed-degrades: log
    /// + the structure drops whole, the chain stays — edits are NEVER lost
    /// and the structure is user-rebuildable (KD-2).
    func hydrate(versions: [SidecarVersionRecord]?, activeVersionID: String?) {
        guard let versions else {
            resetToImplicit()
            return
        }
        let hydrated = versions.map { record in
            VersionSlot(
                id: record.id, name: record.name,
                createdAt: record.createdAt, updatedAt: record.updatedAt,
                chain: record.chainStack)
        }
        if let active = activeVersionID.flatMap(UUID.init(uuidString:)),
            hydrated.contains(where: { $0.id == active }) {
            slots = hydrated
            self.activeVersionID = active
        } else {
            Self.logger.error(
                "version structure degraded: activeVersionID missing or dangling — dropping the structure, the edit chain is kept"
            )
            resetToImplicit()
        }
        syncProjection()
    }

    /// Back to the implicit single version (the E4 clear path — the same
    /// semantics as removing the last version; the CURRENT chain stays in
    /// `EditorState.history` untouched).
    func resetToImplicit() {
        slots = []
        activeVersionID = nil
    }

    /// Whether a version structure exists (the write face consults this —
    /// a structure-less document keeps the v6 byte shape).
    var hasVersionStructure: Bool { !slots.isEmpty }

    /// KD-2's updatedAt touch rule (the WRITE face): every sidecar write
    /// with a version structure bumps the active slot's timestamp (chain
    /// content moved or metadata operated). Pure memory — never hashed.
    func touchActive() {
        guard let activeVersionID,
            let index = slots.firstIndex(where: { $0.id == activeVersionID })
        else { return }
        slots[index].updatedAt = Date()
    }

    // MARK: - Commands (create / branch / switch / rename / remove)

    /// Create a version FROM SCRATCH (「另起炉灶」): a new EMPTY chain
    /// (position −1 — pristine-of-chain, the base seed renders). Implicit
    /// chain materializes first (版本 1); the new version ACTIVATES (the
    /// Alcedo create-activates semantics, DECISIONS signed). P2 KD-1: the
    /// caller (the Versions panel) supplies the NAME — default-name
    /// generation lives in the UI layer; only the materialized implicit
    /// slot's 「版本 1」 stays coordinator-internal.
    func createFromScratch(name: String) {
        // M6-1-01 omp E-OMP-1 (b): a write command — read-only refuses.
        if projectWriteSuppressed() { return }
        guard let editorState else { return }
        materializeImplicitChainIfNeeded()
        let now = Date()
        let slot = VersionSlot(
            id: UUID(), name: name, createdAt: now,
            updatedAt: now, chain: nil)
        // The swap discipline with an EMPTY incoming chain: outgoing
        // capture → install the empty chain → the new slot is active
        // (chain stays nil).
        captureActiveChain(from: editorState.history)
        slots.append(slot)
        editorState.installVersionChain(HistoryStack())
        activeVersionID = slot.id
        finishVersionAction()
    }

    /// Branch from the CURRENT state: copy `items[0...position]` (the redo
    /// tail STAYS in the source — the snapshot point is the command's
    /// instant `history.position`, not the chain end) into a new version
    /// that ACTIVATES. The prefix copy rides the public Core seam
    /// (`HistoryStack.copyingPrefixOf`). P2 KD-1: `name` is caller-supplied
    /// (the panel's UI-side default-name face).
    func branchFromCurrent(name: String) {
        // M6-1-01 omp E-OMP-1 (b): a write command — read-only refuses.
        if projectWriteSuppressed() { return }
        guard let editorState else { return }
        materializeImplicitChainIfNeeded()
        let now = Date()
        let branchChain = HistoryStack.copyingPrefixOf(
            editorState.history, upTo: editorState.history.position)
        let slot = VersionSlot(
            id: UUID(), name: name, createdAt: now,
            updatedAt: now, chain: branchChain)
        // Capture the source state into ITS slot, then activate the branch
        // (its chain becomes the live history; the slot copy drops to nil).
        captureActiveChain(from: editorState.history)
        slots.append(slot)
        editorState.installVersionChain(branchChain)
        activeVersionID = slot.id
        finishVersionAction()
    }

    /// Copy Adjustments' landing command (Plan M2-8-2 T3, KD-4;
    /// D-M2-8-CONTEXT-7): the checked transfer payload lands as a NEW
    /// VERSION on the TARGET image (the dialog opens ON the target).
    /// materialize-if-needed → the new slot (`name` = the panel's default
    /// 「粘贴的调色」) → the new chain = ①ONE OVERWRITE-paste epoch item
    /// (`pasteSet` = the checked record set, `stackSnapshot` = the checked
    /// layer payload, `snapshot` slot = the first record placeholder, scope
    /// = `pasteEpochScope` — the 09-04 HIST-05 shape VERBATIM) + ②when DRT
    /// is checked, ONE `commitDrt`-shaped item (`drtRecord` payload +
    /// `drtDocumentScope` placeholder). ZERO new projection semantics: the
    /// epoch truncation, the stackSnapshot rebuild and the
    /// `effectiveDrtRecord` scan are ALL existing paths (P1 swap already
    /// reused them). The new slot activates; render/write ride the same
    /// `finishVersionAction` tail as every P1 command.
    ///
    /// Two-step undo note (DECISIONS signed deviation): with DRT checked
    /// the version's undo costs TWO steps (epoch + DRT) — Alcedo's single
    /// commit has no counterpart here, the behavior face is equivalent.
    func pasteChain(
        records: [ModuleInstance],
        layerSnapshot: LayerStackSnapshot?,
        drtRecord: DrtRecord?,
        name: String
    ) {
        // M6-1-01 omp E-OMP-1 (b): a write command — read-only refuses.
        if projectWriteSuppressed() { return }
        guard let editorState, !records.isEmpty || drtRecord != nil else { return }
        materializeImplicitChainIfNeeded()
        var chain = HistoryStack()
        if !records.isEmpty {
            chain.commitPaste(
                records: records,
                label: String(
                    localized: "history_paste_adjustments",
                    defaultValue: "Paste Adjustments"),
                scope: HistoryStack.pasteEpochScope,
                stackSnapshot: layerSnapshot)
        }
        if let drtRecord {
            // The placeholder = the current top global record (the
            // `recordDrtChange` shape); the drtDocumentScope marker keeps
            // it out of every projection.
            guard let placeholder = editorState.instances.first else { return }
            chain.commitDrt(
                record: drtRecord, placeholder: placeholder,
                label: String(
                    localized: "history_drt_paste",
                    defaultValue: "Paste Display Transform"))
        }
        let now = Date()
        let slot = VersionSlot(
            id: UUID(), name: name, createdAt: now, updatedAt: now,
            chain: nil)
        captureActiveChain(from: editorState.history)
        slots.append(slot)
        editorState.installVersionChain(chain)
        activeVersionID = slot.id
        finishVersionAction()
    }

    /// Switch to `id`: the swap — outgoing capture → install the target's
    /// chain → target cleared → activate. Same-image switches never
    /// re-decode (PipeCache); switching to the active id is a no-op.
    func switchTo(_ id: UUID) {
        // M6-1-01 omp E-OMP-1 (b): a write command (chain swap + updatedAt
        // touch) — read-only refuses.
        if projectWriteSuppressed() { return }
        guard let editorState, id != activeVersionID,
            let targetIndex = slots.firstIndex(where: { $0.id == id })
        else { return }
        captureActiveChain(from: editorState.history)
        let incoming = slots[targetIndex].chain ?? HistoryStack()
        editorState.installVersionChain(incoming)
        slots[targetIndex].chain = nil
        activeVersionID = id
        // switch-in is a metadata operation: touch the incoming slot.
        slots[targetIndex].updatedAt = Date()
        finishVersionAction()
    }

    /// Rename a version (metadata only — no chain move, no activation).
    func rename(_ id: UUID, to rawName: String) {
        // M6-1-01 omp E-OMP-1 (b): a write command (the .lra version list
        // is metadata truth) — read-only refuses.
        if projectWriteSuppressed() { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
            let index = slots.firstIndex(where: { $0.id == id })
        else { return }
        slots[index].name = name
        slots[index].updatedAt = Date()
        finishVersionAction()
    }

    /// Remove a version. Removing the ACTIVE one switches to the LIST'S
    /// FIRST slot (OQ-3); removing the LAST one returns to the implicit
    /// single-version state (slots cleared, the current chain kept — the
    /// version structure disappears, the edits do not).
    func remove(_ id: UUID) {
        // M6-1-01 omp E-OMP-1 (b): a write command (chain deletion +
        // possible activation move) — read-only refuses.
        if projectWriteSuppressed() { return }
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = slots[index].id == activeVersionID
        slots.remove(at: index)
        if slots.isEmpty {
            // The current chain simply stays in EditorState.history.
            resetToImplicit()
            finishVersionAction()
            return
        }
        if wasActive {
            // Activate the list's first slot WITHOUT capturing the just-
            // removed chain (its state died with the removal — the user
            // asked for it): install the first slot's stored chain.
            let first = slots[0]
            let incoming = first.chain ?? HistoryStack()
            editorState?.installVersionChain(incoming)
            slots[0].chain = nil
            activeVersionID = first.id
        }
        finishVersionAction()
    }

    // MARK: - KD-5: the projection sync (the sink call face; T3 fills it)

    /// One whole-table reconcile per version command tail + per restore
    /// hydrate (KD-5's trigger answer). Idempotent by the reconcile
    /// semantics; failures LOG — the projection is not truth (the `.lra`
    /// is), so a failed sync never blocks editing. Sessions mode (nil
    /// sink) returns with zero reference held. The active marker is
    /// deliberately NOT projected (`image_edit_state` stays reserved —
    /// OQ-5-A; the rows mirror the version LIST only).
    func syncProjection() {
        guard let projection else { return } // Sessions mode: skip
        let store = projection.store
        let elementID = projection.elementID
        let rows = slots.map { slot in
            LibraryStore.VersionRefRow(
                versionID: slot.id.uuidString, elementID: elementID,
                displayName: slot.name,
                createdAtUnix: Int64(slot.createdAt.timeIntervalSince1970),
                updatedAtUnix: Int64(slot.updatedAt.timeIntervalSince1970))
        }
        Task {
            do {
                try await store.replaceVersionRefs(elementID: elementID, rows: rows)
            } catch {
                Self.logger.error(
                    "version_ref projection failed (non-blocking): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Internals

    /// materialize-on-first-create: the implicit chain becomes 「版本 1」
    /// (chain nil = still ACTIVE — its items stay in the history key; the
    /// document only grows the versions keys from now on). Before this
    /// moment the document keeps the v6 byte shape (KD-2).
    private func materializeImplicitChainIfNeeded() {
        guard slots.isEmpty else { return }
        let now = Date()
        let slot = VersionSlot(
            id: UUID(), name: implicitVersionName(), createdAt: now,
            updatedAt: now, chain: nil)
        slots = [slot]
        activeVersionID = slot.id
    }

    /// The swap's outgoing leg: the ACTIVE slot captures the live history
    /// (value copy — param bytes, KB scale). No-op without a structure.
    private func captureActiveChain(from history: HistoryStack) {
        guard let activeVersionID,
            let index = slots.firstIndex(where: { $0.id == activeVersionID })
        else { return }
        slots[index].chain = history
    }

    /// 「版本 1」 — the MATERIALIZED implicit slot's internal name only (the
    /// P2 KD-1 name rule: every USER-CREATED version's name is supplied by
    /// the panel; the coordinator mints no user-facing defaults). Cosmetic
    /// only — identity is the UUID.
    private func implicitVersionName() -> String {
        String(localized: "versions_default_name", defaultValue: "Version 1")
    }

    /// The command tail: one coordinator notification (carrier re-sync +
    /// re-render + the sidecar write with the post-command snapshot) and
    /// one projection reconcile. Both idempotent — double-clicks merge.
    private func finishVersionAction() {
        syncProjection()
        guard let pipeCoordinator else { return }
        Task { await pipeCoordinator.versionActionDidChange() }
    }
}
