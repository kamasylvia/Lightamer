import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// AIMaskResample (Plan 07-1 T4) — the AI mask's bake-time reshape leg.
//
// BOUNDARY (pinned, do not blur): this BILINEAR upsample is the LOW-RES
// AI-MASK leg ONLY (layer B's quality-level mask → the decode-frame
// resolution before bake). It is INDEPENDENT of — and does NOT replace —
// `RasterMaskStore.load`'s per-scale NEAREST resample (`MaskCombiner.
// resample`), which exists for the opposite direction: an ALREADY-BAKED
// high-resolution PNG shrunk to a smaller composite window. Nearest on a
// soft-edged low-res AI mask blockifies; bilinear on a windowing
// downscale of an exact PNG loses nothing that matters. Two legs, two
// kernels' worth of rationale — see 07-RESEARCH §1.2 / Risks 3.
//
// ALIGNMENT: row 0 = image TOP on BOTH sides (buffer coordinates — no
// flip; the geometry test's alignment assertion is the guard).
//
// Layer A needs no upsample (`generateScaledMask` already produces the
// source resolution — the plan's preferred leg).
// ─────────────────────────────────────────────────────────────────────────────

public enum AIMaskResample {

    /// Bilinear-resample `plane` to `toWidth × toHeight` (identity copy
    /// when the sizes already match). Pixel-center mapping:
    /// `src = (dst + 0.5) · srcSize / dstSize − 0.5`, clamped at the
    /// borders (the standard half-texel convention — output row/column 0
    /// samples the source's row/column 0 center, preserving alignment).
    public static func bilinear(
        _ plane: AIMaskPlane, toWidth: Int, toHeight: Int
    ) -> AIMaskPlane {
        precondition(toWidth > 0 && toHeight > 0, "target size must be positive")
        if plane.width == toWidth && plane.height == toHeight {
            return plane
        }
        let sx = Double(plane.width) / Double(toWidth)
        let sy = Double(plane.height) / Double(toHeight)
        var out = [Float](repeating: 0, count: toWidth * toHeight)
        for dy in 0..<toHeight {
            // Row 0 (image top) maps to the source's row 0 — no flip.
            let fy = (Double(dy) + 0.5) * sy - 0.5
            let y0 = Int(fy.rounded(.down))
            let y1 = min(y0 + 1, plane.height - 1)
            let wy = Float(fy - Double(max(y0, 0)))
            let cy0 = max(y0, 0), cy1 = max(y1, 0)
            for dx in 0..<toWidth {
                let fx = (Double(dx) + 0.5) * sx - 0.5
                let x0 = Int(fx.rounded(.down))
                let x1 = min(x0 + 1, plane.width - 1)
                let wx = Float(fx - Double(max(x0, 0)))
                let cx0 = max(x0, 0), cx1 = max(x1, 0)
                let top = plane.floats[cy0 * plane.width + cx0] * (1 - wx)
                    + plane.floats[cy0 * plane.width + cx1] * wx
                let bottom = plane.floats[cy1 * plane.width + cx0] * (1 - wx)
                    + plane.floats[cy1 * plane.width + cx1] * wx
                out[dy * toWidth + dx] = top * (1 - wy) + bottom * wy
            }
        }
        return AIMaskPlane(width: toWidth, height: toHeight, floats: out)
    }

    /// Resample to the decode-frame resolution when (and only when) the
    /// mask is SMALLER — the bake entry's normalize step (a larger or
    /// equal mask passes through untouched; layer A's scaled mask and any
    /// equal-size layer-B mask skip the reshape entirely).
    public static func upsampleToDecodeFrame(
        _ plane: AIMaskPlane, decodeWidth: Int, decodeHeight: Int
    ) -> AIMaskPlane {
        if plane.width >= decodeWidth && plane.height >= decodeHeight {
            return plane
        }
        return bilinear(plane, toWidth: decodeWidth, toHeight: decodeHeight)
    }

    /// Upload the plane into a fresh r32Float texture (the bake input —
    /// `RasterMaskStore.bake` takes `any MTLTexture`).
    public static func texture(
        from plane: AIMaskPlane, metal: MetalContext
    ) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: plane.width, height: plane.height,
            mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: d) else {
            throw MetalError.bufferAllocationFailed(plane.width * plane.height * 4)
        }
        var floats = plane.floats
        floats.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, plane.width, plane.height),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: plane.width * 4)
        }
        return texture
    }
}
