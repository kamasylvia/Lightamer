/// A region of interest in the pixelpipe — the port of Darktable's
/// `dt_iop_roi_t` (pixels + the scale factor the pipe is running at).
///
/// `scale` is the pipe's downscale factor relative to the full image
/// (1.0 = full resolution; preview pipes run < 1.0). Multi-resolution
/// pipes that produce different ROIs per scale are Phase 2 (D-20/FOUND-04).
///
/// `Hashable` (02-02): `PipeCacheKey` embeds the ROI — synthesized over the
/// five fields (in-memory key only; never persisted).
public struct ROI: Equatable, Hashable, Sendable, CustomStringConvertible {

    public var description: String {
        "ROI(x:\(x) y:\(y) w:\(width) h:\(height) s:\(scale))"
    }
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    /// Pipe scale factor (1.0 = full resolution).
    public var scale: Float

    public init(x: Int = 0, y: Int = 0, width: Int = 0, height: Int = 0, scale: Float = 1.0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.scale = scale
    }
}

/// 04-01 ROI negotiation helpers (internal — Core Pipe layer only).
///
/// dt semantics (`pixelpipe_hb.c` backward leg + crop/lens modify_roi_in):
/// after a module widens/shifts the requested input region, the pipe
/// clamps it to the upstream plane so recursion never asks for pixels
/// that do not exist. Scale rides along unchanged (same pipe run).
internal extension ROI {
    /// Clamp this region into `bounds` (intersection; empty → 1×1 at the
    /// bounds origin — the pipe never renders a zero-size plane).
    func clamped(to bounds: ROI) -> ROI {
        let x0 = max(x, bounds.x)
        let y0 = max(y, bounds.y)
        let x1 = min(x + width, bounds.x + bounds.width)
        let y1 = min(y + height, bounds.y + bounds.height)
        return ROI(
            x: bounds.x + max(0, x0 - bounds.x),
            y: bounds.y + max(0, y0 - bounds.y),
            width: max(1, x1 - x0),
            height: max(1, y1 - y0),
            scale: scale
        )
    }

    /// Bounding union of two regions (04-03 rotation fix: the backward
    /// clamp bound must legitimize downstream growth — see `PixelPipe`
    /// `processRec`). Scale rides from `self` (same pipe run).
    func union(_ other: ROI) -> ROI {
        let x0 = min(x, other.x)
        let y0 = min(y, other.y)
        let x1 = max(x + width, other.x + other.width)
        let y1 = max(y + height, other.y + other.height)
        return ROI(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0), scale: scale)
    }
    /// Axis-aligned bounding box of `corners` (04-03/04-04 warp modules:
    /// transformed quad → output/input AABB, `ashift.c` forward/inverse
    /// corner mapping pattern). Floors the min corner, ceils the max.
    static func aabb(of corners: [(x: Double, y: Double)], scale: Float) -> ROI {
        guard let first = corners.first else { return ROI(scale: scale) }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for corner in corners.dropFirst() {
            minX = min(minX, corner.x); minY = min(minY, corner.y)
            maxX = max(maxX, corner.x); maxY = max(maxY, corner.y)
        }
        let ix = Int(minX.rounded(.down)), iy = Int(minY.rounded(.down))
        return ROI(
            x: ix, y: iy,
            width: max(1, Int(maxX.rounded(.up)) - ix),
            height: max(1, Int(maxY.rounded(.up)) - iy),
            scale: scale
        )
    }
}
