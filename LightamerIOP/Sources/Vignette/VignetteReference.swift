import simd

// ─────────────────────────────────────────────────────────────────────────
// VignetteReference — Plan 08-2 T1 golden authority (the CPU float64 twin
// of `vignette_apply`; the 12-5 遗留#5 double-write doctrine: the reference
// is the port of dt's math in full precision, the kernel is checked
// against it).
//
// Mirrors `extended.cl:308-349` (the OpenCL form — unconditional cosine
// smoothing; research §17.3) + the module's `uniforms` scale setup
// (vignette.c:719-786). Same formula, Double precision — the kernel is
// compared at 1e-6 absolute (pow/cos agree across libm/MSL air to ~1e-7
// relative; the |weight| ≤ 1 and |brightness| ≤ 1 domains keep the
// absolute bound meaningful).
// ─────────────────────────────────────────────────────────────────────────

public enum VignetteReference {

    /// One pixel of the vignette (float64). `uniforms` is the module's
    /// `Uniforms` shape spelled in Double (`x`/`y` are ROI-local buffer
    /// pixel coordinates — the kernel's `gid`).
    public static func pixel(
        _ rgb: SIMD3<Double>, x: Double, y: Double, u: Uniforms
    ) -> SIMD3<Double> {
        // extended.cl:326 — the per-axis abs distance.
        let pvx = abs(x * u.xscale - u.roiCenterScaledX)
        let pvy = abs(y * u.yscale - u.roiCenterScaledY)
        // extended.cl:328 — the cplen power distance.
        let cplen = pow(pow(pvx, u.exp1) + pow(pvy, u.exp1), u.exp2)

        // extended.cl:330-337 — the falloff weight; cosine smoothing
        // UNCONDITIONAL (the OpenCL form).
        var weight = 0.0
        if cplen >= u.dscale {
            weight = (cplen - u.dscale) / u.fscale
            if weight >= 1.0 {
                weight = 1.0
            } else if weight <= 0.0 {
                weight = 0.0
            } else {
                weight = 0.5 - cos(Double.pi * weight) / 2.0
            }
        }

        guard weight > 0.0 else { return rgb }

        // brightness leg — the ± branch fork (vignette.c:799-806).
        var out: SIMD3<Double>
        if u.brightness < 0.0 {
            let falloff = 1.0 + weight * u.brightness
            out = rgb * falloff
        } else {
            let falloff = weight * u.brightness
            out = rgb + falloff
        }
        if !u.unbound {
            out = simd_clamp(out, SIMD3<Double>(repeating: 0), SIMD3<Double>(repeating: 1))
        }

        // saturation leg — mean-desaturation (vignette.c:809-815).
        let mv = (out.x + out.y + out.z) / 3.0
        let wss = weight * u.saturation
        out = out - (SIMD3<Double>(repeating: mv) - out) * wss
        if !u.unbound {
            out = simd_clamp(out, SIMD3<Double>(repeating: 0), SIMD3<Double>(repeating: 1))
        }
        return out
    }

    /// The Double spelling of the kernel uniforms (`VignetteModule
    /// .uniforms` feeds these through the Float narrowing at dispatch).
    public struct Uniforms {
        public var xscale: Double
        public var yscale: Double
        public var roiCenterScaledX: Double
        public var roiCenterScaledY: Double
        public var exp1: Double
        public var exp2: Double
        public var dscale: Double
        public var fscale: Double
        public var brightness: Double
        public var saturation: Double
        public var unbound: Bool

        public init(
            xscale: Double, yscale: Double,
            roiCenterScaledX: Double, roiCenterScaledY: Double,
            exp1: Double, exp2: Double, dscale: Double, fscale: Double,
            brightness: Double, saturation: Double, unbound: Bool
        ) {
            self.xscale = xscale
            self.yscale = yscale
            self.roiCenterScaledX = roiCenterScaledX
            self.roiCenterScaledY = roiCenterScaledY
            self.exp1 = exp1
            self.exp2 = exp2
            self.dscale = dscale
            self.fscale = fscale
            self.brightness = brightness
            self.saturation = saturation
            self.unbound = unbound
        }
    }
}
