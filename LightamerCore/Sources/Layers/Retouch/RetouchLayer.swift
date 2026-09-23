import Foundation

/// The retouch layer (Plan 06-07 T1; IOP-GEO-06; D-06-CONTEXT-4) — the
/// second concrete `Layer` kind: its "iop chain" is the STROKE LIST
/// (one parameter body), applied over the composite input in stroke order.
///
/// **Why a layer, not a base-chain module:** healing/cloning is an
/// independently toggleable edit step and multi-layer retouch stacks are a
/// common workflow (C1 semantics). The layer container's visibility /
/// opacity / blend mode / enabled flag come for FREE through the same
/// `LayerCompositeDriver` blend leg every adjustment layer uses — the
/// stroke pipeline only replaces the layer's SUB-RUN (chain render), the
/// composite triple is unchanged.
///
/// **NO_MASKS (dt retouch.c:221 semantics, pinned by this doc comment):**
/// each stroke's SHAPE is the layer's own mask; v1 does NOT stack a
/// parametric/drawn `MaskSpec` on top (D-06-CONTEXT-4 — deferred; the
/// optional field can arrive later as an additive extension). The layer's
/// `mask` stays nil by construction.
///
/// `@unchecked Sendable`: the same single-owner contract as
/// `AdjustmentLayer` (mutable value-type fields owned by one isolation
/// domain at a time). All stored fields are Sendable value types.
public final class RetouchLayer: Layer, @unchecked Sendable {

    public let id: UUID

    public var name: String

    public var isVisible: Bool = true

    public var opacity: Float = 1.0

    public var blendMode: BlendMode = .normal

    public var blendOptions: BlendOptions = []

    public var enabled: Bool = true

    public let kind: LayerKind = .retouch

    /// The stroke list = this layer's entire edit (applied in array order,
    /// dt form order retouch.c:248-261).
    public var strokes: [RetouchStroke]

    /// Retouch is dt `NO_MASKS` — the stroke shapes ARE the mask. Always
    /// nil in v1 (kept as an explicit constant so the contract is visible
    /// in code, not just comments).
    public var mask: MaskSpec? {
        get { nil }
        set { _ = newValue // NO_MASKS: accepting and dropping is the contract
        }
    }

    public init(
        id: UUID = UUID(),
        name: String = "Retouch",
        isVisible: Bool = true,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal,
        blendOptions: BlendOptions = [],
        enabled: Bool = true,
        strokes: [RetouchStroke] = []
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.opacity = opacity
        self.blendMode = blendMode
        self.blendOptions = blendOptions
        self.enabled = enabled
        self.strokes = strokes
    }

    /// Deep copy with fresh identity (duplicate semantics, NDE-1): NEW
    /// layer UUID AND fresh stroke UUIDs; the shape/algorithm/params
    /// payloads adopted verbatim.
    public func duplicated(name: String? = nil) -> RetouchLayer {
        RetouchLayer(
            id: UUID(),
            name: name ?? self.name,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode,
            blendOptions: blendOptions,
            enabled: enabled,
            strokes: strokes.map { stroke in
                var copy = stroke
                copy.id = UUID()
                return copy
            })
    }

    /// Append gate: only ellipse/path shapes are meaningful stroke masks
    /// (v1); other drawn kinds are rejected (the UI never offers them).
    @discardableResult
    public func append(stroke: RetouchStroke) -> Bool {
        guard RetouchStroke.isAllowedShape(stroke.form.kind) else {
            return false
        }
        strokes.append(stroke)
        return true
    }
}
