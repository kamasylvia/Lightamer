import Foundation

/// The per-layer mask record SHELL (Plan 06-01 T2 placeholder — LAYER-03).
///
/// 6-1 freezes only the container: `version` follows the NDE-3 form-version
/// discipline (a mask point-structure evolution bumps the version). The
/// payload freezes in stages as OPTIONAL field additions (non-destructive
/// `decodeIfPresent` — v1/v2 documents stay mutually readable, 06-CONTEXT
/// specifics):
/// - **6-3** — drawn forms (brush/path/ellipse/gradient/group point lists)
/// - **6-4** — parametric (luma + JzCzhz, D-06-CONTEXT-3) + raster refs
///   (sidecar旁挂 PNG, decimal-String hash) + combine rules
///
/// The RENDERING half (rasterization + the composite mask leg) is 6-3/6-4
/// work; the 6-1 composite treats an absent/empty mask as the constant-1
/// passthrough (the degenerate triple: full mask + normal + opacity).
public struct MaskSpec: Codable, Sendable, Equatable, Hashable {

    /// Form version (NDE-3) — 1 until a payload shape migrates.
    public var version: Int

    public init(version: Int = 1) {
        self.version = version
    }
}
