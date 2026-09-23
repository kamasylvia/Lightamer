import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The per-layer mask record (LAYER-03) — the 06-01 shell with the 06-03
// DRAWN payload frozen (brush/path/ellipse/gradient + the MaskGroup shell).
//
// Coordinates are CONTENT-ANCHORED (D-06-CONTEXT-7): every point is a
// full-decode-frame normalized pair (dt's model, `masks.h` forms), and the
// rasterizer converts to the composite plane through GeometryPointMapper
// (plan 06-03 T2). Radii are normalized WIDTH units (isotropic in the
// width frame; the rasterizer carries the aspect). Angles are degrees.
//
// ONE-WAY format lock: the drawn payload below is FROZEN from 06-03 ship.
// Later payload (6-4 parametric/raster/combine rules) arrives ONLY as
// optional decodeIfPresent fields — v1/v2 documents stay mutually readable
// (06-CONTEXT specifics). All floats are plain Float (no UInt64 hashing
// lives in the payload; the mask identity hash is a DERIVED StableHash,
// never persisted — the decimal-String lock does not apply here).
//
// dt form references (06-RESEARCH §3.1 table): brush `masks.h:183-191`,
// path `:173-181`, ellipse `:154-163`, gradient `:195-204` +
// `:91-95` states, group `:206-211` + state bits `:52-68`.
// ─────────────────────────────────────────────────────────────────────────────

/// The 2-D point of every drawn form (normalized decode-frame coords).
public struct MaskPoint: Codable, Sendable, Equatable, Hashable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    public init(x: Double, y: Double) {
        self.x = Float(x)
        self.y = Float(y)
    }
}

/// One cubic-bézier segment of a brush stroke (dt `corner + ctrl1 + ctrl2`
/// per point, `masks.h:183-191` — the next node's corner closes the span).
public struct BrushPoint: Codable, Sendable, Equatable, Hashable {
    public var corner: MaskPoint
    public var ctrl1: MaskPoint
    public var ctrl2: MaskPoint

    public init(corner: MaskPoint, ctrl1: MaskPoint, ctrl2: MaskPoint) {
        self.corner = corner
        self.ctrl1 = ctrl1
        self.ctrl2 = ctrl2
    }
}

/// brush: a bézier-chained stroke with stroke-level falloff parameters
/// (D-06-03-T5-1: radius in width units, hardness = solid-core fraction
/// 0..1, density/flow = per-stamp weight, opacity = the stroke's ceiling
/// multiplier applied in the fold pass). dt keeps density/hardness per
/// POINT (`masks.h:186-187`); v1 freezes them per STROKE (the panel edits
/// one brush at a time — recorded in 06-03-DECISIONS).
public struct BrushStroke: Codable, Sendable, Equatable, Hashable {
    public var points: [BrushPoint]
    public var radius: Float
    public var hardness: Float
    public var density: Float
    public var opacity: Float

    public init(
        points: [BrushPoint], radius: Float, hardness: Float,
        density: Float, opacity: Float
    ) {
        self.points = points
        self.radius = radius
        self.hardness = hardness
        self.density = density
        self.opacity = opacity
    }
}

/// One cubic node of a path (dt `dt_masks_point_path_t`, `masks.h:173-181`).
public struct PathNode: Codable, Sendable, Equatable, Hashable {
    public var corner: MaskPoint
    public var ctrl1: MaskPoint
    public var ctrl2: MaskPoint

    public init(corner: MaskPoint, ctrl1: MaskPoint, ctrl2: MaskPoint) {
        self.corner = corner
        self.ctrl1 = ctrl1
        self.ctrl2 = ctrl2
    }
}

/// path: a closed bézier polygon with a feathered border inset (width
/// units; the fill is 1 inside by more than the border, fading to 0 at
/// the edge — analytic SDF, plan 06-03 T4).
public struct PathForm: Codable, Sendable, Equatable, Hashable {
    public var nodes: [PathNode]
    public var border: Float

    public init(nodes: [PathNode], border: Float) {
        self.nodes = nodes
        self.border = border
    }
}

/// ellipse: dt `dt_masks_point_ellipse_t` (`masks.h:154-163`) minus the
/// GUI flags — center normalized, radii in width units (the record is
/// aspect-free; the rasterizer maps through the frame aspect), rotation
/// in degrees, border = feather fraction of the radius.
public struct EllipseForm: Codable, Sendable, Equatable, Hashable {
    public var center: MaskPoint
    public var radiusX: Float
    public var radiusY: Float
    public var rotationDegrees: Float
    public var border: Float

    public init(
        center: MaskPoint, radiusX: Float, radiusY: Float,
        rotationDegrees: Float, border: Float
    ) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.rotationDegrees = rotationDegrees
        self.border = border
    }
}

/// dt `dt_masks_gradient_states_t` (`masks.h:91-95`).
public enum GradientState: String, Codable, Sendable, Equatable, Hashable {
    case linear
    case sigmoidal
}

/// gradient: dt `dt_masks_point_gradient_t` (`masks.h:195-204`) — anchor
/// normalized, rotation degrees (dt sign convention preserved: the raster
/// evaluates deg2rad(−rotation)), compression ≥ 0.001 (profile width),
/// curvature (the parabolic bend term; dt default 0), and the profile
/// state. The profile formulas are gradient.c:1201 (linear) / the erff
/// branch (sigmoidal) — direct translations in the analytic kernel.
public struct GradientForm: Codable, Sendable, Equatable, Hashable {
    public var anchor: MaskPoint
    public var rotationDegrees: Float
    public var compression: Float
    public var curvature: Float
    public var state: GradientState

    public init(
        anchor: MaskPoint, rotationDegrees: Float, compression: Float,
        curvature: Float = 0, state: GradientState
    ) {
        self.anchor = anchor
        self.rotationDegrees = rotationDegrees
        self.compression = compression
        self.curvature = curvature
        self.state = state
    }
}

/// One drawn form (tagged by id — MaskGroup items reference forms by id,
/// NDE-1 style).
public struct MaskForm: Codable, Sendable, Equatable, Hashable {
    public enum Kind: Codable, Sendable, Equatable, Hashable {
        case brush(BrushStroke)
        case path(PathForm)
        case ellipse(EllipseForm)
        case gradient(GradientForm)
    }

    public var id: UUID
    public var kind: Kind

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

/// dt combine state bits (`masks.h:52-68`) — the v1 subset that maps onto
/// the group combine formulas (group.c:487-630, plan 06-04).
public enum MaskCombineOp: String, Codable, Sendable, Equatable, Hashable {
    case union
    case intersect
    case difference
    case exclusion
    case sum
}

/// One MaskGroup entry (dt `dt_masks_point_group_t`, `masks.h:206-211` —
/// formid/parentid/state/opacity; the parent tree collapses to a flat list
/// in v1). SHELL only: the combine SEMANTICS land in 06-04; 06-03
/// rasterizes single forms and treats a nil/empty group as "first form".
///
/// 06-04 additive optional: `child` = a NESTED group (组内组, IOP-MASK-04)
/// — when set, the item's plane is the recursive evaluation of the child
/// and `formID` is ignored. decodeIfPresent: documents written before
/// 06-04 decode with nil (ONE-WAY additive rule).
public struct MaskGroupItem: Codable, Sendable, Equatable, Hashable {
    public var formID: UUID
    public var op: MaskCombineOp
    public var inverted: Bool
    public var opacity: Float
    public var child: MaskGroupSpec?

    public init(
        formID: UUID, op: MaskCombineOp, inverted: Bool, opacity: Float,
        child: MaskGroupSpec? = nil
    ) {
        self.formID = formID
        self.op = op
        self.inverted = inverted
        self.opacity = opacity
        self.child = child
    }
}

/// The group shell (`items` reference `DrawnMaskSpec.forms` by id).
public struct MaskGroupSpec: Codable, Sendable, Equatable, Hashable {
    public var items: [MaskGroupItem]

    public init(items: [MaskGroupItem]) {
        self.items = items
    }
}

/// The 06-03 drawn payload (frozen spelling).
public struct DrawnMaskSpec: Codable, Sendable, Equatable, Hashable {
    public var forms: [MaskForm]
    public var group: MaskGroupSpec?

    public init(forms: [MaskForm], group: MaskGroupSpec? = nil) {
        self.forms = forms
        self.group = group
    }
}

/// The per-layer mask record (06-01 shell + 06-03 drawn payload + the
/// 06-04 parametric/raster payloads).
public struct MaskSpec: Codable, Sendable, Equatable, Hashable {

    /// Form version (NDE-3) — 1 until a payload shape migrates.
    public var version: Int

    /// The drawn payload (06-03; nil = no drawn mask).
    public var drawn: DrawnMaskSpec?

    /// The parametric payload (06-04 additive optional — decodeIfPresent;
    /// documents written before 06-04 decode with nil, ONE-WAY rule).
    public var parametric: ParametricMask?

    /// The raster payload (06-04 additive optional — a sidecar PNG
    /// reference; pixels never enter this JSON, 06-RESEARCH §6).
    public var raster: RasterMaskRef?

    public init(
        version: Int = 1,
        drawn: DrawnMaskSpec? = nil,
        parametric: ParametricMask? = nil,
        raster: RasterMaskRef? = nil
    ) {
        self.version = version
        self.drawn = drawn
        self.parametric = parametric
        self.raster = raster
    }

    /// True when the spec carries rasterizable drawn content.
    public var hasDrawnForms: Bool { !(drawn?.forms.isEmpty ?? true) }

    /// True when the spec carries a drawn GROUP with items (the 06-04
    /// combine path; a group-less spec rides the 06-03 single-form path).
    public var hasDrawnGroup: Bool {
        guard let items = drawn?.group?.items else { return false }
        return !items.isEmpty
    }

    /// True when the parametric payload has any active channel.
    public var hasParametric: Bool { parametric?.hasActiveChannels ?? false }

    /// True when a raster reference is present.
    public var hasRaster: Bool { raster != nil }

    /// True when ANY mask payload is present (the mask-plane cache key
    /// participates only when this holds).
    public var hasAnyPayload: Bool { hasDrawnForms || hasParametric || hasRaster }

    /// The mask identity hash (L013 discipline): canonical (sortedKeys)
    /// JSON of the whole spec folded through StableHash — the ONLY legal
    /// generator. This value keys the mask-plane cache (position
    /// `maskPosition`, upstream hash slot) and folds into the composite
    /// prefix hash; it is DERIVED, never persisted. Equal specs → equal
    /// hashes across processes and machines (FNV-1a 64 over sorted-keys
    /// bytes — no keyed-container order dependence). Additive-optional
    /// fields encode with `encodeIfPresent`, so pre-06-04 specs hash to
    /// the SAME bytes as before (06-03 documents keep their cache keys).
    public func stableHash() -> UInt64 {
        StableHash.hash(ParamsCoding.encode(self))
    }
}
