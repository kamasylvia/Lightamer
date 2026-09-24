import Foundation
import Vision

// ─────────────────────────────────────────────────────────────────────────────
// AIMaskTypes (Plan 07-1 T2/T3) — the type face of the AI mask service:
// seeds, quality levels, instance selection, refine points, the typed
// error surface, and the VIEW→VISION Y-flip conversion — ALL coordinate
// conversion lives here (D-07-CONTEXT 継承定案: Vision normalized coords
// are lower-left origin; the viewport is top-left origin).
//
// The Y-FLIP is the single seam (`y_vision = 1 − y_view_norm`) — pinned by
// a permanent unit test (07-RESEARCH §6 "mask 上采样/翻转" row). Mask
// BUFFERS never flip (they align with input pixels, row 0 = image top —
// the AIMaskResample alignment assertion is the second line of defense).
// ─────────────────────────────────────────────────────────────────────────────

/// A point in VIEW-normalized coordinates (origin TOP-LEFT, y down — the
/// viewport convention). Conversion to Vision's lower-left-origin space
/// happens ONLY through `visionPoint`.
public struct AIMaskPoint: Sendable, Equatable, Hashable {
    /// 0..1, left→right.
    public var x: Float
    /// 0..1, TOP→bottom (view convention).
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    /// The single Y-flip seam (lower-left origin → y grows upward). Every
    /// seed/refine point handed to Vision MUST pass through here.
    public var visionPoint: NormalizedPoint {
        NormalizedPoint(x: CGFloat(x), y: CGFloat(1.0 - y))
    }
}

/// An axis-aligned box in VIEW-normalized coordinates (origin top-left).
public struct AIMaskRect: Sendable, Equatable, Hashable {
    public var x: Float  // min corner, 0..1
    public var y: Float  // min corner, 0..1 (view convention: top → down)
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The Y-flip seam for boxes (same convention as `AIMaskPoint`): the
    /// view-space min-y corner becomes the max-y corner in Vision space.
    public var visionRect: NormalizedRect {
        let vy = CGFloat(1.0 - y - height)
        return NormalizedRect(
            x: CGFloat(x), y: vy, width: CGFloat(width), height: CGFloat(height))
    }
}

/// The layer-B seed (D-07-CONTEXT-4: v1 = tap point + ⇧-drag box ONLY).
public enum AISubjectSeed: Sendable, Equatable, Hashable {
    /// Single tap (view-normalized).
    case point(AIMaskPoint)
    /// ⇧-drag box (view-normalized).
    case box(AIMaskRect)
    /// UPGRADE SEAM (D-07-CONTEXT-4): scribble/lasso is deferred beyond v1.
    /// The case exists so 07-3's LayerEditingState seed-type switch can be
    /// written exhaustively from day one; constructing it in v1 throws
    /// `AIMaskError.scribbleNotSupported` (typed, not a crash).
    case scribble
}

/// One iterative-refinement point (layer B `addIncludedPoint` /
/// `addExcludedPoint`) in VIEW-normalized coordinates.
public struct AIRefinePoint: Sendable, Equatable, Hashable {
    public enum Role: Sendable, Equatable, Hashable { case included, excluded }

    public var point: AIMaskPoint
    public var role: Role

    public init(_ point: AIMaskPoint, _ role: Role) {
        self.point = point
        self.role = role
    }
}

/// The point-count budgets (07-RESEARCH §1.1: point/scribble seeds 13,
/// box seeds 11 — WWDC26/237). AIMaskService counts the SEED ITSELF for
/// point seeds plus every refine point against this budget and throws
/// `pointLimitExceeded` before Vision can (the SDK does not document
/// whether its own limit includes the seed; our gate is deterministic —
/// see 07-1-DECISIONS D-07-1-T3-1).
public enum AIPointBudget {
    /// point/scribble-seeded requests.
    public static let pointSeeded = 13
    /// box-seeded requests.
    public static let boxSeeded = 11
}

/// The generation quality (layer B `qualityLevel` — controls the produced
/// mask's resolution). `.accurate` is the v1 default (07-CONTEXT 継承定案).
public enum AIMaskQuality: String, Sendable, CaseIterable {
    case fast
    case balanced
    case accurate

    public var visionLevel: GenerateIterativeSegmentationRequest.QualityLevel {
        switch self {
        case .fast: return .fast
        case .balanced: return .balanced
        case .accurate: return .accurate
        }
    }
}

/// Layer-A instance selection (the 07-3 checkbox overlay's payload — the
/// service takes the selection, the UI keeps the instance list).
public enum AIInstanceSelection: Sendable, Equatable {
    /// Every detected instance (the one-tap "select subject" default).
    case all
    /// A hand-picked subset of the catalog's instance indices.
    case subset(Set<Int>)
}

/// The typed error face (07-1 T2 action 3). The GENERATION failure leg is
/// strict: no mask is produced, nothing degrades to an all-ones plane —
/// that semantic belongs to RasterMaskStore.load's three failure legs and
/// must never be conflated with a generation failure (D-07-CONTEXT 継承
/// 定案「生成失败 ≠ load 失败」).
public enum AIMaskError: Error, Equatable, Sendable {
    /// `perform` threw (handler/model/decode failure). Carries the
    /// underlying description.
    case inferenceFailed(String)
    /// The model ran but found no subject (`results` empty / nil
    /// observation) — the "no subject" toast, NOT an all-ones mask.
    case noSubject
    /// Layer B assets not downloaded (assetStatus not ready). The caller
    /// gates/disables the layer-B entry — layer A stays unaffected.
    case modelNotReady(String)
    /// The point budget (13/11) would be exceeded — UI counter's floor.
    case pointLimitExceeded(limit: Int)
    /// The reserved scribble seam constructed in v1 (D-07-CONTEXT-4).
    case scribbleNotSupported
    /// The produced mask buffer has an unexpected pixel format/layout.
    case invalidMask(String)
    /// The requested compute-device policy cannot be honored (e.g. no CPU
    /// device enumerated for the test pin).
    case deviceUnavailable(String)
    /// The input cannot back a Vision request (zero-extent, unreadable).
    case invalidInput(String)
}
