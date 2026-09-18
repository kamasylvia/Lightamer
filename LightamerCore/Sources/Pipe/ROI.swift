/// A region of interest in the pixelpipe — the port of Darktable's
/// `dt_iop_roi_t` (pixels + the scale factor the pipe is running at).
///
/// `scale` is the pipe's downscale factor relative to the full image
/// (1.0 = full resolution; preview pipes run < 1.0). Multi-resolution
/// pipes that produce different ROIs per scale are Phase 2 (D-20/FOUND-04).
///
/// `Hashable` (02-02): `PipeCacheKey` embeds the ROI — synthesized over the
/// five fields (in-memory key only; never persisted).
public struct ROI: Equatable, Hashable, Sendable {

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
