import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PasteSemantics (Plan 09-04 T2; HIST-05 paste side) — the three paste
// modes composed against a target HistoryStack, the pure-CORE twin of dt's
// `dt_history_paste` (overwrite = history.c:754-846's DELETE+INSERT reset;
// merge = :590-745's per-module append).
//
// **One paste = ONE commit** (the per-image undo contract): each mode lands
// exactly one `HistoryItem` whose `pasteSet` carries the whole payload —
// ⌘Z once steps the pointer back over the paste item and the pre-paste
// projection is restored byte-exactly (HistoryStack's epoch/merge paste
// projection). A cross-image undo GROUP is explicitly NOT v1 (09-CONTEXT
// deferred; UI copy must never promise batch undo).
//
// **Modes:**
// - **overwrite** — the target's history EPOCH-RESETS to the payload (the
//   default seed merges back through EditorState's base; the composed doc
//   carries `instances = base ∪ payload`); layer stack = the payload's
//   snapshot wholesale (nil = layers dropped — overwrite is an EXACT
//   duplicate, dt history.c:763-771 deletes masks too).
// - **merge** — the payload appends ONE paste item onto the UNCHANGED
//   stack; `effectiveChain`'s (opName, multiPriority) latest-wins handles
//   same-tuple collisions (the payload, being newest, wins); the target's
//   own instances survive. Layer structure is NOT merged in v1
//   (execution decision — global instances only).
// - **partial** — the payload is pre-filtered through the checked
//   `InstanceKey` subset (the dialog's face), then routed through either
//   mode.
//
// **UUID recast:** pasted records get FRESH UUIDs per paste call — the
// (opName, multiPriority, multiName) tuple is the semantic identity;
// per-image cache namespaces make the fresh ids collision-free.
//
// Live protection (dt `_safe_history_job_on_imgid`, control_jobs.c:1600)
// is a CALLER contract: the currently edited image routes through
// EditorState's install methods (live path), the batch loop skips it.
// ─────────────────────────────────────────────────────────────────────────────

/// The paste mode (dt DT_HISTORY_COPY_* twin).
public enum PasteMode: Sendable, Equatable {
    /// Reset the target history to the payload (exact duplicate).
    case overwrite
    /// Append the payload onto the target's existing chain.
    case merge
}

/// The composed paste outcome — everything the caller needs to install
/// (live path: EditorState; batch path: a new sidecar document).
public struct PasteComposeResult: Sendable, Equatable {

    /// The new history stack (ONE paste commit on top / as epoch).
    public var history: HistoryStack

    /// The persisted live instance set (base ∪ effective, v50-sorted) —
    /// the sidecar `instances` projection for the batch path; the live
    /// path recomputes it through EditorState.rebuildInstances().
    public var instances: [ModuleInstance]

    /// The effective layer-stack record after the paste (nil = no layers).
    public var layerStack: SidecarLayerStackRecord?

    /// The records the paste actually landed (recast UUIDs).
    public var pastedRecords: [ModuleInstance]
}

public enum PasteSemantics {

    /// Compose a paste against a target. nil = the payload is empty (the
    /// paste no-ops — dt's `dt_history_paste` failure posture).
    ///
    /// - Parameters:
    ///   - targetHistory: the target's current history stack.
    ///   - targetInstances: the target's current persisted live set
    ///     (base ∪ effective — the sidecar doc's `instances`).
    ///   - payload: the frozen clipboard entry (skip set already applied).
    ///   - mode: overwrite / merge.
    ///   - seed: the identity-default seed (`ModuleRegistry
    ///     .makeDefaultInstances() + LightamerIOPRegistry
    ///     .editingDefaultInstances()` sorted) — overwrite merges it back
    ///     into the base (the「默认种子 + 载荷实例」acceptance).
    ///   - selection: optional partial-paste subset (checked keys).
    ///   - timestamp: the paste commit's timestamp (tests pin it).
    ///   - label: the commit's history label (the CALLER localizes — Core
    ///     has no String Catalog dependency).
    public static func paste(
        targetHistory: HistoryStack,
        targetInstances: [ModuleInstance],
        payload: PastePayload,
        mode: PasteMode,
        seed: [ModuleInstance],
        selection: Set<PastePayload.InstanceKey>? = nil,
        timestamp: Date = Date(),
        label: String = "Paste Adjustments"
    ) -> PasteComposeResult? {
        // Partial: the checked subset first (an empty selection no-ops).
        let effectivePayload =
            selection.map { payload.filtered(by: $0) } ?? payload
        guard !effectivePayload.instances.isEmpty else { return nil }

        // UUID recast: fresh ids per paste (cross-image namespaces).
        let recast = effectivePayload.instances.map { record -> ModuleInstance in
            var copy = record
            copy.id = UUID()
            return copy
        }

        // Base = the target's persisted records NOT owned by the current
        // effective chain (the restore-path rule, EditorState twin).
        let effective = targetHistory.effectiveInstances()
        var base = targetInstances.filter { record in
            !effective.contains {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }
        }

        // Sorted-by-v50 helper (the persisted live-set ordering contract).
        func v50(_ records: [ModuleInstance]) -> [ModuleInstance] {
            records.sorted {
                ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
            }
        }
        // Tuple-union (existing record wins; the caller passes precedence
        // by argument order).
        func union(_ primary: [ModuleInstance], _ secondary: [ModuleInstance])
            -> [ModuleInstance]
        {
            var merged = primary
            for record in secondary
            where !merged.contains(where: {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }) {
                merged.append(record)
            }
            return merged
        }

        switch mode {
        case .overwrite:
            // The paste item is appended as an EPOCH on the UNTOUCHED
            // stack: forward, the projection ignores everything older
            // (dt DELETE+INSERT observable behavior — the effective set
            // is the payload EXACTLY); undo, the pointer drops below the
            // epoch and the OLD projection returns byte-exactly. One new
            // item = one ⌘Z.
            var history = targetHistory
            history.commitPaste(
                records: recast, label: label, timestamp: timestamp,
                scope: HistoryStack.pasteEpochScope,
                stackSnapshot: effectivePayload.layerStack?.snapshot)
            // The「默认种子 + 载荷实例」base: seed ∪ oldBase (the seed
            // records shadowed by the OLD effective set come back — undo
            // to the pre-paste top then re-projects them byte-exactly).
            var seedPlusBase = seed
            for record in base
            where !seedPlusBase.contains(where: {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }) {
                seedPlusBase.append(record)
            }
            let newInstances = v50(union(seedPlusBase, recast))
            return PasteComposeResult(
                history: history,
                instances: newInstances,
                layerStack: effectivePayload.layerStack,
                pastedRecords: recast)

        case .merge:
            var history = targetHistory
            // ONE paste item (commitPaste owns the append + redo-tail
            // truncation). scope nil = a merge paste (normal global item).
            history.commitPaste(
                records: recast, label: label, timestamp: timestamp, scope: nil)
            // Merge keeps the target's base INTACT (undo-safe: the base
            // never loses a record; forward state resolves payload/base
            // tuple collisions in favor of the history-owned payload).
            let newEffective = history.effectiveInstances()
            let newInstances = v50(union(base, newEffective))
            // Merge v1 does not restructure layers: the target keeps its
            // own stack (execution decision D4).
            let targetLayerSnapshot = targetLayerStackRecord(
                history: history)
            return PasteComposeResult(
                history: history,
                instances: newInstances,
                layerStack: targetLayerSnapshot,
                pastedRecords: recast)
        }
    }

    /// The target's OWN layer-stack record, as far as the history can
    /// reconstruct it (the last structure item's snapshot ≤ position).
    /// The batch path needs this to keep the target's layers on a merge
    /// paste; the LIVE path reads EditorState.layerStack instead.
    public static func targetLayerStackRecord(
        history: HistoryStack
    ) -> SidecarLayerStackRecord? {
        guard history.position >= 0 else { return nil }
        let upTo = Array(history.items[0...history.position])
        // The structure slot rides either the layer-structure marker or a
        // paste-epoch item's stackSnapshot.
        if let idx = upTo.lastIndex(where: {
            $0.layerScope == EditorStructureScope.marker
                || $0.layerScope == HistoryStack.pasteEpochScope
        }), let snapshot = upTo[idx].stackSnapshot {
            return SidecarLayerStackRecord(snapshot)
        }
        return nil
    }
}

/// The layer-structure marker VALUE (a Core-side mirror of EditorState's
/// `layerStructureScope` — the App constant is the canonical definition;
/// this mirror exists only for the batch compose path and is asserted
/// equal in PasteSemanticsTests).
public enum EditorStructureScope {
    public static let marker = "__layerStack__"
}
