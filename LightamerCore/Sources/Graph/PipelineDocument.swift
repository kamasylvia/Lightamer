import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The node-graph projection (Plan M2-4-1 T1, KD-1; D-M2-4-CONTEXT-1/6/7) —
// the Alcedo linear chain "Develop → Color Grade×N → Display Transform" as
// a READ-ONLY VIEW over the persisted `LayerStack`.
//
// PURE-DERIVED FACADE — NO STORAGE STATE. Do not add any var cache, identity
// field, or bidirectional sync point here: the document is rebuilt by
// `init(_:)` on every read and is a pure function of the stack (drift is
// structurally impossible; the tests pin projection INVARIANTS — order/id/
// lock/mix equality with the stack — not synchronization). The layer stack
// stays the single source of truth; sidecar/history/cache identities are
// untouched (UUID identity carries over — no `grade.*` string ids, OQ-1-A).
//
// Semantic mapping (D-M2-4-CONTEXT-1/7):
//   develop          = the base layer's projection (undeletable, first);
//   grade×N          = `compositeLayers` bottom-to-top (retouch layers are
//                      excluded by that narrowing — they never enter the
//                      graph, OQ-7-④);
//   displayTransform = a fixed placeholder endpoint (grayed "DRT arrives
//                      with M2-6"; undeletable, always terminal).
// mix = opacity projection with zero new fields (D-M2-4-CONTEXT-6); the
// endpoints read mix 1 and never expose a blend mode (OQ-6-A).
// ─────────────────────────────────────────────────────────────────────────────

/// The read-only node-graph document (KD-1). Value type; equality compares
/// the three segments' nodes (projection equivalence — two stacks projecting
/// equal nodes are equal documents).
public struct PipelineDocument: Sendable, Equatable {

    /// The fixed identity of the Display Transform endpoint node. A
    /// compile-time constant (never minted per stack) so panel selection and
    /// command targets stay stable across sessions. The hex spells
    /// "DRT00000-0000-0000-0001" — human-recognizable, collision-free
    /// against minted layer UUIDs in practice (and the graph never persists
    /// node ids: the stack UUIDs ARE the identity, OQ-1-A).
    public static let displayTransformNodeID = UUID(
        uuid: (0x44, 0x52, 0x54, 0x30, 0x00, 0x00, 0x00, 0x00,
               0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))

    /// The node kind (exhaustive — every `switch` over this enum must answer
    /// all three cases with NO `default` arm, the M2 checker discipline).
    public enum NodeKind: Sendable, Equatable {
        case develop
        case grade
        case displayTransform
    }

    /// One node of the linear chain (the Alcedo node card's data face).
    public struct Node: Identifiable, Sendable, Equatable {

        /// develop = the base layer's UUID; grade = the layer UUID (the
        /// history/sidecar/cache anchor — NDE-1); displayTransform = the
        /// fixed `displayTransformNodeID`.
        public let id: UUID

        public let kind: NodeKind

        /// Display name (develop = the base layer's name; grade = the layer
        /// name; drt = the fixed placeholder label).
        public let name: String

        /// The processing gate (grade = `AdjustmentLayer.enabled`).
        public let isEnabled: Bool

        /// The mix projection (D-M2-4-CONTEXT-6): grade = the layer's
        /// opacity; the endpoints are constant 1.
        public let mix: Float

        /// The deletion lock (D-M2-4-CONTEXT-7): the develop/drt endpoints
        /// are structurally locked (the base layer has no remove API;
        /// `grade.primary`'s lock IS that invariant projected).
        public let isDeletionLocked: Bool

        /// The backing layer UUID for grade nodes (panel edit routing);
        /// nil on the endpoints (nothing to route to).
        public let layerID: UUID?

        init(
            id: UUID, kind: NodeKind, name: String, isEnabled: Bool,
            mix: Float, isDeletionLocked: Bool, layerID: UUID?
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.isEnabled = isEnabled
            self.mix = mix
            self.isDeletionLocked = isDeletionLocked
            self.layerID = layerID
        }
    }

    /// The Develop endpoint (the base layer's projection — always first).
    public let develop: Node

    /// The Color Grade chain, bottom-to-top (= `compositeLayers` order,
    /// which is the graph order). Retouch layers never appear here (the
    /// narrowing skips them — OQ-7-④'s structural guarantee).
    public let grades: [Node]

    /// The Display Transform endpoint (the fixed grayed placeholder —
    /// M2-6 brings the real DRT).
    public let displayTransform: Node

    /// Project the document from a stack (the ONLY construction face —
    /// pure derivation, no state captured).
    public init(_ stack: LayerStack) {
        develop = Node(
            id: stack.baseLayer.id,
            kind: .develop,
            name: stack.baseLayer.name,
            isEnabled: stack.baseLayer.enabled,
            mix: 1,
            isDeletionLocked: true,
            layerID: nil)
        let gradeNodes = stack.compositeLayers.map { layer in
            Node(
                id: layer.id,
                kind: .grade,
                name: layer.name,
                isEnabled: layer.enabled,
                mix: layer.opacity,
                isDeletionLocked: false,
                layerID: layer.id)
        }
        grades = gradeNodes
        maskGroups = zip(gradeNodes, stack.compositeLayers).map { node, layer in
            MaskGroup(
                gradeNode: node,
                masks: (layer.mask?.maskItems ?? []).map(MaskItemSummary.init))
        }
        displayTransform = Node(
            id: Self.displayTransformNodeID,
            kind: .displayTransform,
            name: "Display Transform",
            isEnabled: true,
            mix: 1,
            isDeletionLocked: true,
            layerID: nil)
    }

    /// The full linear chain: develop → grades → displayTransform (the
    /// panel's top-to-bottom render order).
    public var nodes: [Node] { [develop] + grades + [displayTransform] }

    // ── M2-7 data face + the selection mapping (Plan M2-4-2 T2, KD-3) ──

    /// One mask of a group (the M2-7 Mask Groups panel's row data face) —
    /// the `MaskSpec.maskItems` read view frozen into an Equatable summary
    /// so projections stay comparable.
    public struct MaskItemSummary: Sendable, Equatable {

        /// The item's form id (the panel's row anchor).
        public let id: UUID

        /// The stored display name; nil = DERIVED at the display site (the
        /// derivation consumes the Core single source
        /// `LayerStack.nextLayerName(base:)` — never persisted).
        public let name: String?

        /// The v5 enabled gate (nil folded to true).
        public let isEnabled: Bool

        public let opacity: Float

        public let isInverted: Bool

        init(_ item: (id: UUID, name: String?, enabled: Bool, opacity: Float, inverted: Bool)) {
            id = item.id
            name = item.name
            isEnabled = item.enabled
            opacity = item.opacity
            isInverted = item.inverted
        }
    }

    /// One grade's mask group (the M2-7 panel's card): the grade node +
    /// its masks in group order. Every grade projects exactly one group
    /// (empty `masks` = the grade carries no mask).
    public struct MaskGroup: Sendable, Equatable {

        public let gradeNode: Node

        public let masks: [MaskItemSummary]
    }

    /// The mask groups in GRADE ORDER — D-M2-4-CONTEXT-9's data semantics
    /// (组序 = grade 序 = 层序; the M2-7 panel's drag-to-reorder rides the
    /// Reconnect command and this projection FOLLOWS, pure derivation with
    /// zero sync points). Computed in `init` alongside the other segments
    /// — the same per-read rebuild as `grades`, not a cache.
    public let maskGroups: [MaskGroup]

    /// The selection mapping (the panels' seam — nil = nothing selected;
    /// the develop-segment semantics for nil are the VIEW layer's call).
    /// The develop/drt ids resolve their endpoints, a grade UUID resolves
    /// its node, and an unknown id (e.g. a retouch layer, off-graph)
    /// resolves nil.
    public func node(for id: UUID?) -> Node? {
        guard let id else { return nil }
        return nodes.first { $0.id == id }
    }

    /// The node header's display title — the EXHAUSTIVE branch table (no
    /// default arm; the checker discipline):
    ///
    ///   nil (unselected) → the M2-3-3 constant face "Color Grade" (the
    ///                      SAME localization key, byte-identical render);
    ///   develop          → "Develop" (`editor_node_develop`);
    ///   grade            → the layer name (user data);
    ///   displayTransform → "Display Transform" (`editor_node_drt`).
    ///
    /// `EditorNodeHeaderView` consumes ONLY this function for the title.
    public func displayTitle(for id: UUID?) -> String {
        switch node(for: id)?.kind {
        case .develop:
            String(localized: "editor_node_develop", defaultValue: "Develop")
        case .grade:
            node(for: id)?.name
                ?? String(localized: "editor_node_name", defaultValue: "Color Grade")
        case .displayTransform:
            String(localized: "editor_node_drt", defaultValue: "Display Transform")
        case nil:
            String(localized: "editor_node_name", defaultValue: "Color Grade")
        }
    }
}
