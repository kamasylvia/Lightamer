import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The node-graph command set (Plan M2-4-1 T2, KD-2; D-M2-4-CONTEXT-2) — the
// seven Alcedo graph commands as a pure-data transform over `LayerStack`.
//
// LAYERING: Core carries the "graph semantics ↔ layer operation" mapping
// table in this ONE file (anti-scatter rule — the mapping knowledge must not
// leak into panels). `apply(to:)` is a pure function (LayerStack in →
// LayerStack out, value semantics, zero history side effects) so it is
// unit-testable without the app target; the App layer's `EditorState.apply`
// is the thin execution shell (reassign + EXACTLY ONE structure commit).
//
// EXHAUSTIVE-SWITCH DISCIPLINE (checker ①): every `switch` over
// `NodeGraphCommand` / `NodeGraphError` in the codebase must answer all
// cases with NO `default` arm. The known consumers: `EditorState.apply`
// (the sole execution entry) + `NodeGraphCommandTests`. P3 panels are pure
// producers and never switch on commands.
//
// UNDO: commands never touch history themselves — the app shell commits ONE
// structure history item (with a full `stackSnapshot`) per command, so
// undo/redo restore through the existing single `rebuildLayerStack` path
// (identity-preserving: layer UUIDs ride the snapshots verbatim, M2NODE-02).
// ─────────────────────────────────────────────────────────────────────────────

/// The seven node-graph commands (the Alcedo command face, OQ-2-A — no more,
/// no less; each maps to one UI gesture in the P3 panel).
public enum NodeGraphCommand: Sendable, Equatable {

    /// Insert an identity grade (empty chain, enabled, opacity 1, normal
    /// blend, single-source default name) below `before`'s position.
    /// nil = append on top. The 18-catalog items are an M2-5 non-goal —
    /// the M2-4 identity is the EMPTY chain.
    case addCleanGrade(before: UUID?)

    /// Remove a grade; the linear chain bridges structurally (removing a
    /// node from a linear chain IS the bridge — no rewiring data exists).
    case removeGradeAndBridge(id: UUID)

    /// Move a grade to a grade-index position (clamped into the chain).
    case reconnectGrade(id: UUID, toPosition: Int)

    /// Rename a grade (user data — no canonical-name enforcement).
    case renameGrade(id: UUID, to: String)

    /// Toggle a grade's processing gate (`AdjustmentLayer.enabled`).
    case setGradeEnabled(id: UUID, enabled: Bool)

    /// Set a grade's mix (writes `opacity`, clamped 0...1 — D5; mix 0 is
    /// pixel-identical to bypass, pinned by the E4 test).
    case setGradeMix(id: UUID, mix: Float)

    /// Restore a persisted layer record from its `SidecarLayerRecord` JSON
    /// (byte-exact payload convention: id/chain bytes/mask verbatim — the
    /// undo-of-remove shape and the M2-8 paste carrier). The record's
    /// identity is NEVER re-minted (the restore init guarantees it).
    case insertGradeFromJSON(data: Data, position: Int)
}

/// The typed graph-command failures (exhaustive; no default anywhere).
public enum NodeGraphError: Error, Equatable, Sendable {

    /// The command targeted a locked endpoint (develop / display transform
    /// — D-M2-4-CONTEXT-7). The App shell intercepts this SILENTLY (no
    /// toast — the lock is a visible affordance, not an error condition).
    case lockedNode(UUID)

    /// The node id is not part of the graph (develop/grades/drt).
    case nodeNotFound(UUID)

    /// The id belongs to a real layer that is not a grade (retouch layers
    /// never enter the graph — OQ-7-④).
    case notAGrade(UUID)

    /// The InsertFromJson payload is not an adjustment-layer record (a
    /// retouch payload is refused — retouch never rides the graph).
    case badPayload

    /// A negative InsertFromJson position (the upper bound clamps; a
    /// negative index is malformed input, not a clamp case).
    case badPosition(Int)
}

public extension NodeGraphCommand {

    /// The pure transform: apply the graph semantics to a COPY of `stack`
    /// and return it. The input value is never mutated (purity pinned by
    /// test); history/sidecars/cache are none of this function's business.
    func apply(to stack: LayerStack) throws -> LayerStack {
        var result = stack
        switch self {
        case let .addCleanGrade(before):
            let position = try insertionPosition(for: before, in: stack)
            let layer = AdjustmentLayer(
                name: stack.nextLayerName(base: Self.defaultGradeName),
                opacity: 1,
                enabled: true)
            result.insert(layer, at: Self.adjustmentIndex(composite: position, in: result))
            return result

        case let .removeGradeAndBridge(id):
            // Throws on locked endpoints / retouch ids / unknown ids.
            _ = try Self.gradeLayer(with: id, in: stack)
            // Linear chain: removal IS the bridge (the driver recomputes
            // C_k from the prefix — no rewiring data to maintain).
            result.remove(id: id)
            return result

        case let .reconnectGrade(id, toPosition):
            let layer = try Self.gradeLayer(with: id, in: stack)
            // Remove-then-insert (clamped) rather than `reorder`: the
            // target index is a GRAPH (composite) position, and remove+
            // insert in adjustment space keeps the conversion single-source
            // with `addCleanGrade`/`insertGradeFromJSON`.
            result.remove(id: id)
            let clamped = min(max(toPosition, 0), result.compositeLayers.count)
            result.insert(layer, at: Self.adjustmentIndex(composite: clamped, in: result))
            return result

        case let .renameGrade(id, name):
            var layer = Self.sameIdentityCopy(try Self.gradeLayer(with: id, in: stack))
            layer.name = name
            result.replace(layer)
            return result

        case let .setGradeEnabled(id, enabled):
            var layer = Self.sameIdentityCopy(try Self.gradeLayer(with: id, in: stack))
            layer.enabled = enabled
            result.replace(layer)
            return result

        case let .setGradeMix(id, mix):
            var layer = Self.sameIdentityCopy(try Self.gradeLayer(with: id, in: stack))
            layer.opacity = min(max(mix, 0), 1) // the D5 clamp
            result.replace(layer)
            return result

        case let .insertGradeFromJSON(data, position):
            guard position >= 0 else { throw NodeGraphError.badPosition(position) }
            let record: SidecarLayerRecord
            do {
                record = try JSONDecoder().decode(SidecarLayerRecord.self, from: data)
            } catch {
                throw NodeGraphError.badPayload
            }
            // Retouch (or any future kind) never rides the graph.
            guard record.kind == "adjustment" else { throw NodeGraphError.badPayload }
            let layer = record.layer // identity + params bytes + mask VERBATIM
            let clamped = min(position, stack.compositeLayers.count)
            result.insert(layer, at: Self.adjustmentIndex(composite: clamped, in: result))
            return result
        }
    }

    /// An IDENTITY-PRESERVING copy of a grade (the layer is a CLASS: a
    /// structural transform that mutated the shared object would corrupt
    /// the caller's input stack — the purity contract dies with aliasing).
    /// id/chain bytes/mask ride verbatim; nothing is re-minted.
    private static func sameIdentityCopy(_ layer: AdjustmentLayer) -> AdjustmentLayer {
        AdjustmentLayer(
            id: layer.id, name: layer.name, isVisible: layer.isVisible,
            opacity: layer.opacity, blendMode: layer.blendMode,
            blendOptions: layer.blendOptions, enabled: layer.enabled,
            chain: layer.chain, mask: layer.mask)
    }

    /// Resolve the graph node id → the backing grade layer. The endpoint
    /// ids (develop / display transform) are deletion/reconnect-LOCKED
    /// (D-M2-4-CONTEXT-7); a retouch layer id is a real layer that is not
    /// a graph node; anything else does not exist in the graph.
    private static func gradeLayer(with id: UUID, in stack: LayerStack) throws -> AdjustmentLayer {
        if id == stack.baseLayer.id || id == PipelineDocument.displayTransformNodeID {
            throw NodeGraphError.lockedNode(id)
        }
        if let grade = stack.compositeLayers.first(where: { $0.id == id }) {
            return grade
        }
        if stack.adjustmentLayers.contains(where: { $0.id == id }) {
            throw NodeGraphError.notAGrade(id) // a retouch layer — off-graph
        }
        throw NodeGraphError.nodeNotFound(id)
    }

    /// Resolve the `addCleanGrade(before:)` anchor to a composite-space
    /// insertion index. nil = top; the develop anchor = bottom; the drt
    /// anchor = top; a grade anchor = its own index; unknown = typed error.
    private func insertionPosition(for before: UUID?, in stack: LayerStack) throws -> Int {
        guard let before else { return stack.compositeLayers.count }
        if before == stack.baseLayer.id { return 0 }
        if before == PipelineDocument.displayTransformNodeID {
            return stack.compositeLayers.count
        }
        guard let index = stack.compositeLayers.firstIndex(where: { $0.id == before }) else {
            throw NodeGraphError.nodeNotFound(before)
        }
        return index
    }

    /// Composite-space position → `adjustmentLayers` insertion index (the
    /// retouch entries occupy adjustment slots but no graph positions; the
    /// walk counts only the composite narrowing).
    static func adjustmentIndex(composite position: Int, in stack: LayerStack) -> Int {
        guard position > 0 else { return 0 }
        var seen = 0
        for (index, layer) in stack.adjustmentLayers.enumerated() {
            if layer is AdjustmentLayer {
                if seen == position { return index }
                seen += 1
            }
        }
        return stack.adjustmentLayers.count
    }

    /// The identity grade's display-name base (the Alcedo "Color Grade"
    /// card label — plan M2-4-1 KD-2 pins「Color Grade N」). The name is
    /// minted through the Core single-source `LayerStack.nextLayerName
    /// (base:)`; the localization seam rides that extension's `base:`
    /// parameter (Core holds no localization keys — the M4 discipline).
    static let defaultGradeName = "Color Grade"
}
