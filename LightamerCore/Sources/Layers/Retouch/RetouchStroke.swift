import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The retouch stroke model (Plan 06-07 T1; IOP-GEO-06; 06-RESEARCH §5.2).
//
// dt shape: `dt_iop_retouch_form_data_t` (retouch.c:74-88) — one form
// (the stroke shape, a mask form) + algorithm + algorithm-specific
// parameters, applied in form order over the image. Lightamer's retouch
// layer "iop chain" IS this stroke list (D-06-CONTEXT-4 — the layer's
// strokes are its own mask, dt `NO_MASKS` retouch.c:221 semantics; the
// parametric-mask overlay is explicitly OUT of v1 scope).
//
// Reuse decisions (D-06-07-T1-2):
// - The stroke SHAPE reuses the FROZEN 06-03 drawn-mask spellings
//   (`MaskForm` → ellipse/path kinds) — no second shape vocabulary to
//   freeze; the sidecar payload composes already-frozen spellings.
// - `RetouchAlgorithm` raw values are the dt slots VERBATIM
//   (retouch.c:66-71: clone=1/heal=2/blur=3/fill=4; NONE=0 unused) — the
//   same "raw value = dt slot" discipline as BlendMode (D-06-CONTEXT-2).
//
// v1 simplifications (documented, dt-faithful where it matters):
// - `source` is a single normalized POINT (the patch center); the sampled
//   region = the stroke shape TRANSLATED so its center lands on `source`
//   (dt allows an arbitrary source form; translation-only covers the
//   clone/heal workflow and keeps the ROI extension exact).
// - blur is GAUSSIAN only (dt also offers bilateral — deferred; the
//   Phase 5 bilateral grid is reusable later as a second leg).
// - fill is COLOR only (dt's erase mode deferred).
// ─────────────────────────────────────────────────────────────────────────────

/// One retouch stroke's algorithm (dt `dt_iop_retouch_algo_type_t`,
/// retouch.c:66-71 — raw values are the frozen dt slots).
public enum RetouchAlgorithm: Int, Codable, Sendable, Hashable {

    /// Copy the source region over the stroke (dt DT_IOP_RETOUCH_CLONE).
    case clone = 1

    /// Seamlessly blend the source patch's TEXTURE with the stroke's
    /// lighting (dt DT_IOP_RETOUCH_HEAL — iterative Laplacian, heal.c:354).
    case heal = 2

    /// Blur the underlying image inside the stroke (dt DT_IOP_RETOUCH_BLUR).
    case blur = 3

    /// Paint a constant color inside the stroke (dt DT_IOP_RETOUCH_FILL).
    case fill = 4
}

/// One retouch stroke — a shape (the per-stroke mask), the algorithm, the
/// clone/heal source, and the per-stroke parameters (retouch.c:248-261
/// parameterized record, Lightamer spelling).
///
/// Coordinates are FULL-DECODE-FRAME NORMALIZED [0,1]² (the 06-03 mask
/// convention, D-06-CONTEXT-7 content anchoring — the composite
/// rasterizes through `GeometryPointMapper`, so strokes follow image
/// content across crop/flip/lens).
public struct RetouchStroke: Codable, Sendable, Equatable, Hashable, Identifiable {

    /// Stable stroke identity (NDE-1 — history/panel reference by UUID).
    public var id: UUID

    public var algorithm: RetouchAlgorithm

    /// The stroke shape = the per-stroke mask (dt NO_MASKS semantics).
    /// v1 kinds: `.ellipse` (a circle when radiusX == radiusY) and
    /// `.path` (the freehand/bezier lasso). Other drawn kinds are
    /// meaningless here and rejected at the layer's `append` gate.
    public var form: MaskForm

    /// Clone/heal source patch CENTER (normalized). The sampled region is
    /// this stroke's shape translated so its center sits on `source`.
    /// nil for blur/fill.
    public var source: MaskPoint?

    /// Per-stroke opacity in [0,1] (dt rides it on the form's mask-group
    /// opacity — `rt_get_mask_point_group` retouch.c:427).
    public var opacity: Float

    /// Blur sigma for `.blur` strokes (dt `blur_radius`; gaussian leg only).
    public var blurRadius: Float?

    /// Fill color (linear Rec2020 0-1 RGB) for `.fill` strokes
    /// (dt `fill_color[3]`; brightness offset folded into the color).
    public var fillColor: SIMD3<Float>?

    public init(
        id: UUID = UUID(),
        algorithm: RetouchAlgorithm,
        form: MaskForm,
        source: MaskPoint? = nil,
        opacity: Float = 1.0,
        blurRadius: Float? = nil,
        fillColor: SIMD3<Float>? = nil
    ) {
        self.id = id
        self.algorithm = algorithm
        self.form = form
        self.source = source
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.fillColor = fillColor
    }

    /// The stroke-shape gate: the only drawn kinds a stroke may carry
    /// (v1 — ellipse/path; other drawn kinds rejected at the layer gate).
    public static func isAllowedShape(_ kind: MaskForm.Kind) -> Bool {
        switch kind {
        case .ellipse, .path: true
        case .brush, .gradient: false
        }
    }
}
