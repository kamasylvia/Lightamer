import Foundation

// LensAutoCrop — the auto-scale bisection (Plan LENS-02 T3, D-LENS-5).
//
// Portions Copyright (C) 2026 RawLab contributors.
// Source: RawLab `lutools/src/core/lens_correction.cpp` (the auto-crop
// scale-compensation search: `inside()` + the zoom coarse probe + the
// 18-round bisection), GPL-3.0. Ported to Swift for Lightamer.
// Modified by Lightamer (2026-10-21): the LibRaw/lensfun modifier call
// sites are replaced by an INJECTED edge-map closure (the caller owns the
// per-channel forward map — the projection fold lands there in LENS-03
// T1); the cropScale report face becomes `minimumScale` returning nil for
// the UnsupportedInput verdict. See NOTICE ("RawLab") for the provenance
// ledger. This file is GPL-3.0 as part of Lightamer.
//
// SEMANTICS (the upstream contract, preserved):
// - "auto-crop" is a ZOOM-IN (scale compensation) that hides the invalid
//   border, NOT a geometric crop rectangle — the framing truth stays in
//   the Crop module (24.5, downstream).
// - inside(): EVERY output-frame border pixel must forward-map (all THREE
//   channel footprints — not just the green distortion model) to finite
//   input-frame coordinates inside [0, width-1] × [0, height-1].
// - The search: scale=1 inside → 1.0 (no compensation). Else coarse-probe
//   zoom from 1.05 by ×1.25 up to 8; exceeding 8 = unsupported input (nil).
//   Then 18 bisection rounds between low=1 and the first inside probe;
//   the result carries a ×1.00001 margin.
//
// L020 frame note: the edge-map closure receives OUTPUT-FRAME pixels and
// returns INPUT-FRAME sample coordinates (the kernel's sampling map
// semantics) — the same convention as LensModule.forwardPoint.

/// The auto-scale bisection (RawLab port — see the file header).
public enum LensAutoCrop {

    /// The coarse-probe zoom factor (upstream 1.25).
    static let coarseFactor: Float = 1.25
    /// The coarse-probe start (upstream 1.05 — the first candidate above 1).
    static let coarseStart: Float = 1.05
    /// The zoom cap (exceeding = UnsupportedInput → nil).
    static let zoomCap: Float = 8
    /// The bisection rounds (upstream 18).
    static let bisectionRounds = 18
    /// The safety margin (upstream ×1.00001).
    static let margin: Float = 1.00001

    /// The minimal scale whose warp keeps every border pixel's full RGB
    /// footprint inside the input frame; nil = unsupported input (even
    /// zoom 8 leaves the frame). `edgeMap(x, y, scale)` returns the THREE
    /// per-channel (R, G, B) input-frame sample coordinates for the
    /// output-frame border pixel — the projection/distortion fold lives
    /// entirely in the caller's closure.
    public static func minimumScale(
        width: Int, height: Int,
        edgeMap: (_ x: Float, _ y: Float, _ scale: Float) -> [(x: Float, y: Float)]
    ) -> Float? {
        guard width >= 2, height >= 2 else { return nil }
        if inside(width: width, height: height, edgeMap: edgeMap, scale: 1) {
            return 1
        }
        // Coarse probe: ×1.25 from 1.05 up to the cap (upstream order).
        var high = coarseStart
        var found = false
        while high <= zoomCap {
            if inside(width: width, height: height, edgeMap: edgeMap, scale: high) {
                found = true
                break
            }
            high *= coarseFactor
        }
        guard found else { return nil }
        // 18 bisection rounds between low=1 and the first inside probe.
        var low: Float = 1
        for _ in 0..<bisectionRounds {
            let middle = (low + high) * 0.5
            if inside(width: width, height: height, edgeMap: edgeMap, scale: middle) {
                high = middle
            } else {
                low = middle
            }
        }
        return high * margin
    }

    /// The upstream `inside()` — every border pixel (all four edges, every
    /// pixel — no striding here: the closure is cheap and the bisection
    /// total stays millisecond-class) must map all three channels inside.
    static func inside(
        width: Int, height: Int,
        edgeMap: (_ x: Float, _ y: Float, _ scale: Float) -> [(x: Float, y: Float)],
        scale: Float
    ) -> Bool {
        let maxX = Float(width - 1), maxY = Float(height - 1)
        func valid(_ x: Float, _ y: Float) -> Bool {
            let coords = edgeMap(x, y, scale)
            guard coords.count == 3 else { return false }
            for c in coords {
                if !c.x.isFinite || !c.y.isFinite { return false }
                if c.x < 0 || c.x > maxX || c.y < 0 || c.y > maxY { return false }
            }
            return true
        }
        for x in 0..<width {
            let fx = Float(x)
            if !valid(fx, 0) || !valid(fx, maxY) { return false }
        }
        for y in 1..<(height - 1) {
            let fy = Float(y)
            if !valid(0, fy) || !valid(maxX, fy) { return false }
        }
        return true
    }
}
