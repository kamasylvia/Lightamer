import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LayerStackProjection (Plan M2-8-2 T3, KD-5) — THE history → layer-stack
// projection as ONE Core pure function. This is `EditorState
// .rebuildLayerStack`'s rule EXTRACTED VERBATIM (the plan's single-path /
// single-source mandate):
//
//   • EditorState delegates its rebuild here (behavior ZERO-DIFF — the
//     existing Layers/App suites are the evidence);
//   • the Copy Adjustments transfer model enumerates a source chain's
//     layer stack through the SAME function (an external `.lra` chain has
//     NO EditorState in the room — the extraction's reason to exist).
//
// App code MUST NOT re-derive a second copy of this rule (the checker ④
// consumption-point single-source grep: `stackSnapshot` replay logic lives
// HERE and nowhere else).
// ─────────────────────────────────────────────────────────────────────────────

/// The layer twin of `HistoryStack.effectiveInstances` (the App's
/// `rebuildLayerStack` rule, home in Core since M2-8-2 KD-5).
public enum LayerStackProjection {

    /// History → layer state at `history.position`: the stack = the LAST
    /// structure item ≤ position's snapshot (none = no adjustment layers),
    /// then every in-scope param item ≤ position re-applies onto its
    /// layer's chain (newest-wins per the shared dedup tuple — items
    /// recorded AFTER a structure edit are already baked into that
    /// snapshot, so re-applying ALL in-scope items is idempotent and
    /// chronology-safe).
    ///
    /// - Parameters:
    ///   - history: the chain to project (the active version's live stack
    ///     for EditorState; a decoded sidecar chain for the transfer model).
    ///   - baseLayer: the always-present base (EditorState passes its live
    ///     stack's base; callers without one pass a fresh `BackgroundLayer`).
    public static func rebuild(
        history: HistoryStack, baseLayer: any Layer
    ) -> LayerStack {
        var stack = LayerStack(baseLayer: baseLayer)
        let upTo = history.position >= 0 ? Array(history.items[0...history.position]) : []
        // The structure slot: layer-structure items AND overwrite-paste
        // epochs (09-04) both carry a stackSnapshot to rebuild from.
        if let lastStructure = upTo.lastIndex(where: {
            $0.layerScope == EditorStructureScope.marker
                || $0.layerScope == HistoryStack.pasteEpochScope
        }), let snapshot = upTo[lastStructure].stackSnapshot {
            for layer in snapshot.makeLayers() { stack.addAdjustment(layer) }
        }
        // The in-scope param items re-apply onto their layer's chain. The
        // M2-6-3 DRT document items (drtDocumentScope) are not layer state —
        // excluded explicitly (the payload rides drtRecord, never a chain).
        for item in upTo
        where item.layerScope != nil
            && item.layerScope != EditorStructureScope.marker
            && item.layerScope != HistoryStack.drtDocumentScope {
            guard let layer = stack.compositeLayers.first(where: {
                $0.id.uuidString == item.layerScope
            }) as? AdjustmentLayer else { continue }
            layer.chain = HistoryStack.effectiveChain(layer.chain + [item.snapshot])
        }
        return stack
    }
}
