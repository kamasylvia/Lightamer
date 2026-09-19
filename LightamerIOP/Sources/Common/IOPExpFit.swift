import Foundation

// ─────────────────────────────────────────────────────────────────────────
// IOPExpFit (Plan 03-03-T2/T3 shared; Common) — dt's power-law
// extrapolation fit used by colisa / tonecurve / levels for the
// "unbounded" LUT regions above 1.0 (and the mirrored left side of a/b
// curves in tonecurve).
//
// dt `dt_iop_estimate_exp` (develop/imageop_math.h:98-130) verbatim:
// fit f(x) = y0·(x/x0)^g with the LAST sample anchoring (x0, y0); g is
// the average of log(y/y0)/log(x/x0) over the other samples (1.0 when no
// sample qualifies). `dt_iop_eval_exp` = coeff[1]·pow(x·coeff[0],
// coeff[2]). Both the Float (module commit paths) and Double (LUT
// derivation / reference parity) variants share the op order.
// ─────────────────────────────────────────────────────────────────────────

public enum IOPExpFit {

    /// Float variant — `coeff = {1/x0, y0, g}`.
    public static func estimate(_ x: [Float], _ y: [Float]) -> [Float] {
        let count = x.count
        let x0 = x[count - 1], y0 = y[count - 1]
        var g: Float = 0
        var cnt = 0
        for k in 0..<(count - 1) {
            if y[k] > 0, x[k] > 0 {
                g += Foundation.log(y[k] / y0) / Foundation.log(x[k] / x0)
                cnt += 1
            }
        }
        if cnt > 0 {
            g *= 1.0 / Float(cnt)
        } else {
            g = 1.0
        }
        return [1.0 / x0, y0, g]
    }

    /// Double variant (tonecurve table derivation).
    public static func estimateD(_ x: [Double], _ y: [Double]) -> [Double] {
        let count = x.count
        let x0 = x[count - 1], y0 = y[count - 1]
        var g: Double = 0
        var cnt = 0
        for k in 0..<(count - 1) {
            if y[k] > 0, x[k] > 0 {
                g += Foundation.log(y[k] / y0) / Foundation.log(x[k] / x0)
                cnt += 1
            }
        }
        if cnt > 0 {
            g *= 1.0 / Double(cnt)
        } else {
            g = 1.0
        }
        return [1.0 / x0, y0, g]
    }

    /// dt `dt_iop_eval_exp`: `coeff[1] * powf(x * coeff[0], coeff[2])`.
    public static func eval(_ coeff: [Float], _ x: Float) -> Float {
        coeff[1] * Foundation.pow(x * coeff[0], coeff[2])
    }

    /// Double evaluation.
    public static func evalD(_ coeff: [Double], _ x: Double) -> Double {
        coeff[1] * Foundation.pow(x * coeff[0], coeff[2])
    }
}
