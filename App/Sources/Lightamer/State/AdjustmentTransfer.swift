import Foundation
import LightamerCore
import LightamerIOP
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// AdjustmentTransfer (Plan M2-8-2 T3, KD-3; D-M2-8-CONTEXT-7) — the Copy
// Adjustments transfer model: the three-pane (Node→Item→Version) dialog's
// data face over a REAL source chain.
//
//   • SOURCE SEGMENT (KD-3's 跨图悬决销账): 「当前图」 (the active chain —
//     the same-image degenerate path) or 「外部 .lra 文件…」 (NSOpenPanel →
//     `LightamerSidecar` decode → the version list (v7) or the single
//     active chain (v6) as the second-level pick). The in-library image
//     picker is DEFERRED (the plan's morning-review note).
//   • NODE PANE: every Grade layer of `LayerStackProjection.rebuild` = one
//     row (name + chain count) — the KD-5 single-source projection, never
//     a second replay of the rule.
//   • ITEM PANE: the layer chain's instances, each checkboxed (default =
//     every TRANSFERABLE one); non-transferable rows render greyed with a
//     count note (the exclusion face is VISIBLE, never silently swallowed).
//   • DRT: one independent row when the source chain carries an effective
//     `drtRecord` (document-level value copy).
//
// THE EXCLUSION PREDICATE IS ONE FUNCTION (`isAdjustmentTransferable`) —
// this panel and any future batch face share it; no second copy of the
// exclusion logic may appear at the view layer.
// ─────────────────────────────────────────────────────────────────────────────

/// KD-3's transferable predicate (THE single function — CONTEXT Specific
/// Ideas): a Grade-owned chain instance. The terminal trio answers `.grade`
/// through the catalog's default arm (checker M1's measured final table —
/// `colorin`/`colorout`/`gamma` are NOT in any catalog row), so the
/// EXPLICIT exclusion set below pins them off.
func isAdjustmentTransferable(_ instance: ModuleInstance) -> Bool {
    !AdjustmentTransferTerminalTrio.opNames.contains(instance.opName)
        && NodeOwnershipCatalog.owner(of: instance.opName) == .grade
}

/// The terminal trio's explicit exclusion set (KD-3 终表 — opName constants,
/// zero string literals).
enum AdjustmentTransferTerminalTrio {
    static let opNames: [String] = [
        ColorInModule.opName, ColorOutModule.opName, GammaModule.opName,
    ]
}

/// One source version row (the second-level pick; external v7 lists the
/// document's versions, everything else offers the single active chain).
struct TransferSourceVersion: Identifiable, Equatable {
    /// The version UUID string, or `SidecarSource.activeChainID` sentinel.
    let id: String
    let name: String
    /// The decoded chain backing this row (value semantics — param bytes).
    let chain: HistoryStack

    /// The v6 / no-version-structure sentinel row id.
    static let activeChainID = "__activeChain__"
}

/// One Node-pane row: a Grade layer of the source stack.
struct TransferNode: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// The layer chain's TOTAL record count (the row's caption).
    let chainCount: Int
    /// How many of the chain's records are transferable (the row's
    /// checkable payload; the rest are the greyed exclusion face).
    let transferableCount: Int
}

/// One Item-pane row.
struct TransferItem: Identifiable, Equatable {
    let instance: ModuleInstance
    /// `isAdjustmentTransferable` at enumeration (the greyed face).
    let transferable: Bool
    /// The checkbox (defaults to `transferable` — 默认全选可贴面).
    var checked: Bool

    var id: UUID { instance.id }
}

/// The typed external-source load failure (the dialog renders the copy —
/// never a crash, never a silent swallow).
enum AdjustmentTransferError: Equatable {
    case unreadable(String)
    case noTransferableSource

    var localizedCopy: String {
        switch self {
        case .unreadable(let detail):
            String(
                localized: "transfer_error_unreadable",
                defaultValue: "The sidecar file could not be read — \(detail)")
        case .noTransferableSource:
            String(
                localized: "transfer_error_empty",
                defaultValue: "This source carries no grade adjustments to copy.")
        }
    }
}

// MARK: - The paste payload (the VersionCoordinator command's input)

/// The checked selection, materialized (KD-4's pasteChain input):
/// `records` = every checked instance (flat), `snapshot` = the checked
/// layers' stack payload (each layer's chain = its checked records; nil
/// when no layer is checked), `drtRecord` = the checked DRT row's record.
struct AdjustmentTransferPayload: Equatable {
    var records: [ModuleInstance]
    var snapshot: LayerStackSnapshot?
    var drtRecord: DrtRecord?

    var isEmpty: Bool { records.isEmpty && drtRecord == nil }
}

@Observable
@MainActor
final class AdjustmentTransferModel {

    /// The source origin (the segment's two entries).
    enum SourceKind: Equatable {
        case currentImage
        case externalFile(URL)
    }

    private(set) var source: SourceKind = .currentImage

    /// The second-level version rows (external v7 → the version list;
    /// every other source → the single active-chain row).
    private(set) var sourceVersions: [TransferSourceVersion] = []

    /// The picked row's id (drives the enumeration).
    private(set) var selectedVersionID: String?

    /// The typed load failure (nil = healthy).
    private(set) var loadError: AdjustmentTransferError?

    /// The source stack's Grade layers as snapshots (index-aligned with
    /// `nodes` — the payload build slices these).
    private(set) var layerSnapshots: [LayerStackSnapshot.Layer] = []

    /// The Node pane rows.
    private(set) var nodes: [TransferNode] = []

    /// The selected Node row (the List's selection binding writes through;
    /// the Item pane reads it).
    var selectedNodeID: UUID?

    /// The Item pane state per node (populated at enumeration).
    private(set) var items: [UUID: [TransferItem]] = [:]

    /// The DRT row (nil = the source carries no effective DRT record).
    private(set) var drtRecord: DrtRecord?
    private(set) var drtChecked = false

    init() {}

    // MARK: - Source loading

    /// Load the CURRENT image's active chain (the degenerate path). The
    /// editor's live history + base layer feed the SAME KD-5 projection
    /// the external path uses.
    func loadCurrentImage(editorState: EditorState) {
        source = .currentImage
        loadError = nil
        let chain = editorState.history
        sourceVersions = [
            TransferSourceVersion(
                id: TransferSourceVersion.activeChainID,
                name: String(
                    localized: "transfer_source_active",
                    defaultValue: "Current edits"),
                chain: chain)
        ]
        selectedVersionID = TransferSourceVersion.activeChainID
        drtRecord = chain.effectiveDrtRecord()
        drtChecked = drtRecord != nil
        enumerate(chain: chain)
    }

    /// Load an EXTERNAL `.lra` (the KD-3 跨图主用例): decode → the version
    /// rows (v7: every version, the active one riding the `history` key;
    /// v6/structure-less: the single active-chain row) → pick the first.
    /// A corrupt/canted file lands the typed error (never a crash).
    func loadExternalFile(at url: URL) {
        source = .externalFile(url)
        loadError = nil
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(LightamerSidecar.self, from: data)
            var rows: [TransferSourceVersion] = []
            if let versions = document.versions, !versions.isEmpty {
                for record in versions {
                    let isActive = document.activeVersionID == record.id.uuidString
                    let chain = isActive ? document.history : (record.chainStack ?? HistoryStack())
                    rows.append(
                        TransferSourceVersion(
                            id: record.id.uuidString, name: record.name, chain: chain))
                }
            } else {
                // v6 / structure-less: the active chain is the only face.
                rows = [
                    TransferSourceVersion(
                        id: TransferSourceVersion.activeChainID,
                        name: String(
                            localized: "transfer_source_active",
                            defaultValue: "Current edits"),
                        chain: document.history)
                ]
            }
            sourceVersions = rows
            selectedVersionID = rows.first?.id
            let chain = rows.first?.chain ?? HistoryStack()
            drtRecord = chain.effectiveDrtRecord()
            drtChecked = drtRecord != nil
            enumerate(chain: chain)
        } catch {
            sourceVersions = []
            selectedVersionID = nil
            layerSnapshots = []
            nodes = []
            items = [:]
            drtRecord = nil
            drtChecked = false
            loadError = .unreadable(error.localizedDescription)
        }
    }

    /// The second-level pick: re-enumerate against the chosen row's chain.
    func selectVersion(id: String) {
        guard let row = sourceVersions.first(where: { $0.id == id }) else { return }
        selectedVersionID = id
        drtRecord = row.chain.effectiveDrtRecord()
        drtChecked = drtRecord != nil
        enumerate(chain: row.chain)
    }

    // MARK: - The enumeration (the KD-5 single-source projection)

    private func enumerate(chain: HistoryStack) {
        let stack = LayerStackProjection.rebuild(
            history: chain, baseLayer: BackgroundLayer())
        let snapshots = stack.adjustmentLayers.map(LayerStackSnapshot.Layer.init)
        layerSnapshots = snapshots
        nodes = snapshots.map { snap in
            TransferNode(
                id: snap.id, name: snap.name, chainCount: snap.chain.count,
                transferableCount: snap.chain.filter(isAdjustmentTransferable).count)
        }
        // Item state rebuilds; the selection falls to the first node that
        // has anything checkable.
        var rebuilt: [UUID: [TransferItem]] = [:]
        for snap in snapshots {
            rebuilt[snap.id] = snap.chain.map { instance in
                let transferable = isAdjustmentTransferable(instance)
                return TransferItem(
                    instance: instance, transferable: transferable, checked: transferable)
            }
        }
        items = rebuilt
        selectedNodeID =
            snapshots.first(where: { (rebuilt[$0.id] ?? []).contains { $0.transferable } })?
            .id
    }

    // MARK: - The pane writes

    var selectedNodeItems: [TransferItem] {
        selectedNodeID.flatMap { items[$0] } ?? []
    }

    func selectNode(id: UUID) {
        selectedNodeID = id
    }

    /// One checkbox write (no-op for the greyed non-transferable rows).
    func setChecked(instanceID: UUID, checked: Bool, in nodeID: UUID) {
        guard var list = items[nodeID],
            let index = list.firstIndex(where: { $0.id == instanceID }),
            list[index].transferable
        else { return }
        list[index].checked = checked
        items[nodeID] = list
    }

    func setDrtChecked(_ checked: Bool) {
        guard drtRecord != nil else { return }
        drtChecked = checked
    }

    // MARK: - The payload (the Version pane's materialized summary)

    /// The checked selection as the paste payload. nil = nothing checkable
    /// was enumerated (the dialog shows the empty note instead).
    ///
    /// KD-3's mask-epoch reset (悬决销账销账): the copied layer's mask
    /// `contentRevision` resets to NIL — the optimistic-concurrency guard
    /// restarts from zero for the new identity (a stale in-flight writer
    /// on the SOURCE image must never validate against the PASTED mask;
    /// the paste is a new epoch by construction).
    func pastePayload() -> AdjustmentTransferPayload? {
        if layerSnapshots.isEmpty && drtRecord == nil { return nil }
        var records: [ModuleInstance] = []
        var layers: [LayerStackSnapshot.Layer] = []
        for snap in layerSnapshots {
            let checked = (items[snap.id] ?? []).filter { $0.checked }.map(\.instance)
            guard !checked.isEmpty else { continue }
            var layer = snap
            layer.chain = checked
            if var mask = layer.mask {
                mask.contentRevision = nil
                layer.mask = mask
            }
            layers.append(layer)
            records.append(contentsOf: checked)
        }
        let drt = drtChecked ? drtRecord : nil
        let payload = AdjustmentTransferPayload(
            records: records,
            snapshot: layers.isEmpty ? nil : LayerStackSnapshot(layers: layers),
            drtRecord: drt)
        return payload.isEmpty ? nil : payload
    }

    /// The Version pane's summary line (the paste button's subtitle face).
    var summaryCopy: String {
        let payload = pastePayload()
        guard let payload else {
            return String(
                localized: "transfer_summary_none",
                defaultValue: "Nothing selected")
        }
        let layers = payload.snapshot?.layers.count ?? 0
        let drt = payload.drtRecord != nil ? 1 : 0
        return String(
            localized: "transfer_summary",
            defaultValue:
                "\(layers) grades, \(payload.records.count) adjustments, \(drt) display transform")
    }
}
