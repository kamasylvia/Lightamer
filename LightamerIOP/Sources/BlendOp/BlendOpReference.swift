import Foundation
import LightamerCore
import simd

// ─────────────────────────────────────────────────────────────────────────
// BlendOpReference (Plan 06-02 T1) — the float64 per-mode reference of the
// blendop composite engine, written BEFORE the kernel (the filmicrgb F1
// three-party-gate pattern): every function here is the transliteration of
// one dt formula with its blendop.cl / blend.c line cited inline, and
// `BlendOpKernels.metal` mirrors the SAME table in MSL float32.
// BlendOpParityTests asserts GPU ≙ this reference <1e-5 rel per mode.
//
// DOMAIN (06-RESEARCH §4.1 + D-06-CONTEXT-2): the working space is LINEAR
// Rec2020, scene-referred, UNBOUNDED (HDR > 1 allowed — the parity fixtures
// carry >1 values). The dt formula families come from the MODERN kernel
// branches (blendop.cl:513-800 = the normalized-domain LCh/RGB shapes with
// min=0/max=1) evaluated in the linear domain WITHOUT output clamping
// except where the formula itself clamps (linearBurn's lmin=0 — dt clamps
// the same lower bound in every kernel family). The gamma-encoded PS
// variants are deliberately NOT implemented (v1 pins dt linear-domain
// semantics, parity-verifiable — 06-CONTEXT "PS 期望 vs 线性域观感分歧").
//
// PERCEPTUAL DEVIATION NOTE (recorded in 06-02-DECISIONS): dt's RGB_SCENE
// path (`blends/blendif_rgb_jzczhz.c:_choose_blend_func`, :703-761) has NO
// hue/color/colorAdjust cases (they fall back to normal) and implements
// lightness/chromaticity as RGB-vector norm rescaling. The plan (T3 +
// 06-CONTEXT §4.1) pins the JzCzhz-domain formula family instead (the
// blendop.cl:695-733 LCh-mode shapes transposed to JzCzhz — "parity 源
// 唯一性优先 JzCzhz"): hue = shortest-path hz mix, luminosity = Jz mix,
// saturation = Cz mix, color = Cz+hz mix, colorAdjust = Jz-from-b. That is
// a deliberate Lightamer semantic, parity-tested against THIS reference.
//
// OPACITY: `opacity` is the per-pixel EFFECTIVE opacity (dt's mask plane
// value = CLIP(gopacity) × mask form — blend.c:458 CLIP + :530 fold). The
// kernel contract passes the same effective value (see BlendOpKernels.metal
// header). `opacity2 = opacity²` (dt fsquare) rides overlay/soft/hard.
//
// REVERSE (blend.h:89): swaps a/b BEFORE the mode dispatch (dt blend.c
// pointer swap) — handled once at the top, never inside the modes.
//
// ALPHA: dt overwrites o.w with the effective opacity; Lightamer blends
// alpha as data (a.w·(1−op) + b.w·op) because the working space is opaque
// imagery with the alpha=1 invariant pinned by the identity triples — the
// deviation is recorded in 06-02-DECISIONS and handled by the dispatcher
// (this file returns RGB only).
// ─────────────────────────────────────────────────────────────────────────
public enum BlendOpReference {

    /// The dt-style blend parameter p = exp2(blend_parameter)
    /// (blend.c:1301 — the host folds exp2 BEFORE the kernel sees it).
    public static func blendParameterP(_ blendParameter: Double) -> Double {
        exp2(blendParameter)
    }

    /// The full dispatch: mode → formula. `a` = below/composite plane,
    /// `b` = this layer's output (dt blend.c:458 semantics).
    public static func blend(
        _ mode: BlendMode, a: SIMD3<Double>, b: SIMD3<Double>,
        opacity: Double, p: Double = 1.0, reverse: Bool = false
    ) -> SIMD3<Double> {
        let (a, b) = reverse ? (b, a) : (a, b)
        switch mode {
        case .normal: return normal(a, b, opacity)
        case .lighten: return lighten(a, b, opacity)
        case .darken: return darken(a, b, opacity)
        case .multiply: return multiply(a, b, opacity, p)
        case .linearBurn: return linearBurn(a, b, opacity)
        case .screen: return screen(a, b, opacity)
        case .overlay: return overlay(a, b, opacity)
        case .softLight: return softLight(a, b, opacity)
        case .hardLight: return hardLight(a, b, opacity)
        case .difference: return difference(a, b, opacity)
        case .psColorDodge: return psColorDodge(a, b, opacity)
        case .psColorBurn: return psColorBurn(a, b, opacity)
        case .luminosity: return luminosity(a, b, opacity)
        case .saturation: return saturation(a, b, opacity)
        case .hue: return hue(a, b, opacity)
        case .color: return color(a, b, opacity)
        case .colorAdjust: return colorAdjust(a, b, opacity)
        }
    }

    // MARK: - Arithmetic modes (linear Rec2020, per channel)

    /// NORMAL2 modern formula (blendop.cl:646-650 `default:`/NORMAL2 branch;
    /// D-06-CONTEXT-2: raw 0x01 implements this, no legacy clamping).
    public static func normal(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        a * (1.0 - op) + b * op
    }

    /// DEVELOP_BLEND_LIGHTEN (blendop.cl:594-597 RGB shape: max(a,b) mix;
    /// the Lab kernel's L-chroma legs are Lab-specific and do not transpose).
    public static func lighten(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        a * (1.0 - op) + max(a, b) * op
    }

    /// DEVELOP_BLEND_DARKEN (blendop.cl:598-601: min(a,b) mix).
    public static func darken(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        a * (1.0 - op) + min(a, b) * op
    }

    /// DEVELOP_BLEND_MULTIPLY (dt scene _blend_multiply,
    /// blendif_rgb_jzczhz.c:427 = `a·(1−op) + a·b·p·op`; blendop.cl:1344).
    public static func multiply(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double, _ p: Double) -> SIMD3<Double> {
        a * (1.0 - op) + a * b * p * op
    }

    /// DEVELOP_BLEND_SUBTRACT — the PS linear-burn analog (blendop.cl:637-639
    /// Lab shape `a+b−|min+max|` = a+b−1; lmin = 0 lower clamp — the one
    /// arithmetic formula whose output can go negative from non-negative
    /// inputs, dt clamps it at lmin in every kernel family).
    public static func linearBurn(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        max(a * (1.0 - op) + (a + b - 1.0) * op, SIMD3(repeating: 0))
    }

    /// DEVELOP_BLEND_SCREEN (blendop.cl:612-615 shape with lmax = 1:
    /// `1−(1−a)(1−b)`; unbounded generalization keeps the unit constants,
    /// no output clamp — HDR-safe).
    public static func screen(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        a * (1.0 - op) + (SIMD3(repeating: 1.0) - (1.0 - a) * (1.0 - b)) * op
    }

    /// DEVELOP_BLEND_OVERLAY (blendop.cl:618-621: keyed on la —
    /// `la>halfmax ? 1−2(1−la)(1−lb) : 2·la·lb` with opacity²).
    public static func overlay(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let op2 = op * op
        let f = SIMD3(
            a.x > 0.5 ? 1.0 - 2.0 * (1.0 - a.x) * (1.0 - b.x) : 2.0 * a.x * b.x,
            a.y > 0.5 ? 1.0 - 2.0 * (1.0 - a.y) * (1.0 - b.y) : 2.0 * a.y * b.y,
            a.z > 0.5 ? 1.0 - 2.0 * (1.0 - a.z) * (1.0 - b.z) : 2.0 * a.z * b.z)
        return a * (1.0 - op2) + f * op2
    }

    /// DEVELOP_BLEND_SOFTLIGHT (blendop.cl:633-636: keyed on lb —
    /// `lb>halfmax ? 1−(1−la)(1.5−lb) : la·(lb+halfmax)` with opacity²).
    public static func softLight(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let op2 = op * op
        let f = SIMD3(
            b.x > 0.5 ? 1.0 - (1.0 - a.x) * (1.5 - b.x) : a.x * (b.x + 0.5),
            b.y > 0.5 ? 1.0 - (1.0 - a.y) * (1.5 - b.y) : a.y * (b.y + 0.5),
            b.z > 0.5 ? 1.0 - (1.0 - a.z) * (1.5 - b.z) : a.z * (b.z + 0.5))
        return a * (1.0 - op2) + f * op2
    }

    /// DEVELOP_BLEND_HARDLIGHT (blendop.cl:648-651: overlay shape keyed on
    /// lb with opacity²).
    public static func hardLight(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let op2 = op * op
        let f = SIMD3(
            b.x > 0.5 ? 1.0 - 2.0 * (1.0 - a.x) * (1.0 - b.x) : 2.0 * a.x * b.x,
            b.y > 0.5 ? 1.0 - 2.0 * (1.0 - a.y) * (1.0 - b.y) : 2.0 * a.y * b.y,
            b.z > 0.5 ? 1.0 - 2.0 * (1.0 - a.z) * (1.0 - b.z) : 2.0 * a.z * b.z)
        return a * (1.0 - op2) + f * op2
    }

    /// DEVELOP_BLEND_DIFFERENCE2 — the scene-referred unbounded shape
    /// (`_blend_difference`, blendif_rgb_jzczhz.c:503 = `|a−b|` mix; the
    /// Lab kernel's /|max−min| chroma legs are Lab-only).
    public static func difference(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        a * (1.0 - op) + abs(a - b) * op
    }

    /// PS color dodge (NEW raw value 0x2A — dt has no slot; W3C
    /// Compositing-1 §color-dodge, linear-domain, per channel):
    ///   Cb == 0 → 0;  Cs == 1 → 1;  else min(1, Cb/(1−Cs)).
    public static func psColorDodge(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        func dodge(_ cb: Double, _ cs: Double) -> Double {
            if cb == 0 { return 0 }
            if cs >= 1 { return 1 }
            return min(1.0, cb / (1.0 - cs))
        }
        let f = SIMD3(dodge(a.x, b.x), dodge(a.y, b.y), dodge(a.z, b.z))
        return a * (1.0 - op) + f * op
    }

    /// PS color burn (NEW raw value 0x2B; W3C Compositing-1 §color-burn):
    ///   Cb == 1 → 1;  Cs == 0 → 0;  else 1 − min(1, (1−Cb)/Cs).
    public static func psColorBurn(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        func burn(_ cb: Double, _ cs: Double) -> Double {
            if cb >= 1 { return 1 }
            if cs <= 0 { return 0 }
            return 1.0 - min(1.0, (1.0 - cb) / cs)
        }
        let f = SIMD3(burn(a.x, b.x), burn(a.y, b.y), burn(a.z, b.z))
        return a * (1.0 - op) + f * op
    }

    // MARK: - Perceptual modes (JzCzhz round trip — see the header note)

    /// DEVELOP_BLEND_LIGHTNESS as Jz-Cz-hz L-component swap
    /// (plan T3: "L 分量直接换" — the blendop.cl:683-687 Lab LCh shape
    /// transposed to JzCzhz: Jz mixes, Cz/hz ride a).
    public static func luminosity(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        return JzCzhz.toRGB(SIMD3(ja.x * (1.0 - op) + jb.x * op, ja.y, ja.z))
    }

    /// DEVELOP_BLEND_CHROMATICITY — Cz mixes, Jz/hz ride a
    /// (blendop.cl:688-694 LCh CHROMA shape transposed).
    public static func saturation(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        return JzCzhz.toRGB(SIMD3(ja.x, ja.y * (1.0 - op) + jb.y * op, ja.z))
    }

    /// DEVELOP_BLEND_HUE — shortest-path hz mix, Jz/Cz ride a
    /// (blendop.cl:709-719 HUE shape transposed).
    public static func hue(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        let h = JzCzhz.mixedHue(ja.z, jb.z, opacity: op)
        return JzCzhz.toRGB(SIMD3(ja.x, ja.y, h))
    }

    /// DEVELOP_BLEND_COLOR — Cz mixes + shortest-path hz mix, Jz rides a
    /// (blendop.cl:721-731 COLOR shape transposed).
    public static func color(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        let h = JzCzhz.mixedHue(ja.z, jb.z, opacity: op)
        return JzCzhz.toRGB(SIMD3(ja.x, ja.y * (1.0 - op) + jb.y * op, h))
    }

    /// DEVELOP_BLEND_COLORADJUST — dt's "blend in the ADJUSTED color only"
    /// (blendop.cl:733-743: to.x = tb.x — the lightness comes from **b**;
    /// Cz mixes + hz mix). D-06-CONTEXT-2: raw 0x16 implements THIS.
    public static func colorAdjust(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ op: Double) -> SIMD3<Double> {
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        let h = JzCzhz.mixedHue(ja.z, jb.z, opacity: op)
        return JzCzhz.toRGB(SIMD3(jb.x, ja.y * (1.0 - op) + jb.y * op, h))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ParametricReference (Plan 06-04 T1) — the float64 reference of the
// blendif parametric mask + the mask tone curve, written BEFORE/ALONGSIDE
// the kernels (the 6-2 three-party-gate pattern). Every function is the
// transliteration of one dt formula with its source line cited:
//   - factor        = blendif_rgb_jzczhz.c:64-94 `_blendif_compute_factor`
//                     (the blendop.cl:386-412 inline trapezoid, same math)
//   - blendifFactor = blendop.cl:329-408 `blendif_factor_rgb_jzczhz`
//   - maskPixel     = blendop.cl:1131-1145 `blendop_mask_rgb_jzczhz` body
//   - toneCurve     = blendop.cl:1309-1449 `blendop_mask_tone_curve`
// The channel scaling (luma / JzCzhz) rides the SAME-SOURCE float64 chain
// (JzAzBz.swift) — the kernel's duplicated MSL constants are pinned
// against THIS by ParametricMaskParityTests.
// ─────────────────────────────────────────────────────────────────────────────
public enum ParametricReference {

    /// dt blend.h:120-176 — slot ids and masks (mirror of the MSL block).
    public static let rgbMask: Int = 0x77FF
    public static let maxSlot = 14

    /// The Rec2020 luminance row (dt `get_rgb_matrix_luminance` with the
    /// work profile = the Y row of the same Rec2020→XYZ matrix the Jz
    /// chain uses — SAME-SOURCE constants).
    public static let lumaRow = SIMD3<Double>(0.262700, 0.678009, 0.059291)

    /// The scaled channel table (blendop.cl:336-364): 15 slots, gray/luma +
    /// RGB always, JzCzhz only when the high slots participate.
    public static func scaledChannels(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, blendif: UInt32
    ) -> [Double] {
        var scaled = [Double](repeating: 0, count: maxSlot + 1)
        scaled[0] = dot(lumaRow, a) // GRAY_in
        scaled[4] = dot(lumaRow, b) // GRAY_out
        scaled[1] = a.x; scaled[2] = a.y; scaled[3] = a.z
        scaled[5] = b.x; scaled[6] = b.y; scaled[7] = b.z
        if blendif & 0x7f00 != 0 {
            let jchIn = JzCzhz.fromRGB(a)
            let jchOut = JzCzhz.fromRGB(b)
            scaled[8] = jchIn.x   // Jz_in
            scaled[9] = jchIn.y   // Cz_in
            scaled[10] = jchIn.z  // hz_in
            scaled[12] = jchOut.x // Jz_out
            scaled[13] = jchOut.y // Cz_out
            scaled[14] = jchOut.z // hz_out
        }
        return scaled
    }

    /// The pointwise trapezoid (blendop.cl:386-412 — no inversion inside).
    public static func factor(_ value: Double, _ p: [Double]) -> Double {
        if value <= p[0] {
            return 0
        } else if value < p[1] {
            return (value - p[0]) * p[4]
        } else if value <= p[2] {
            return 1
        } else if value < p[3] {
            return 1 - (value - p[2]) * p[5]
        }
        return 0
    }

    /// `blendif_factor_rgb_jzczhz` (blendop.cl:329-408) in Double.
    /// `combineINCL` = dt DEVELOP_COMBINE_INCL.
    public static func blendifFactor(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, blendif: UInt32,
        parameters: [Double], combineINCL: Bool = false
    ) -> Double {
        let scaled = scaledChannels(a, b, blendif: blendif)
        let combineFlags: UInt32 = combineINCL ? 0x02 : 0
        let invertMask = (blendif >> 16)
            ^ (combineFlags & 0x02 != 0 ? UInt32(rgbMask) : 0)
        var result = 1.0
        for ch in 0...maxSlot where Int(rgbMask) & (1 << ch) != 0 {
            var factor: Double
            if blendif & (1 << UInt32(ch)) == 0 {
                factor = 1
            } else if result <= 0.000001 {
                break
            } else {
                let base = 6 * ch
                factor = Self.factor(scaled[ch], Array(parameters[base..<base + 6]))
            }
            result *= invertMask & (1 << UInt32(ch)) != 0 ? 1 - factor : factor
        }
        return combineINCL ? 1 - result : result
    }

    /// `blendop_mask_rgb_jzczhz` body (blendop.cl:1131-1145): the effective
    /// mask value for one pixel — gopacity · opacity.
    /// `form` = the drawn/form plane value (1 when no form plane).
    /// `combineINV` = dt DEVELOP_COMBINE_INV (the mask-level invert).
    public static func maskPixel(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, form: Double,
        blendif: UInt32, parameters: [Double],
        combineINCL: Bool = false, combineINV: Bool = false,
        gopacity: Double
    ) -> Double {
        let conditional = blendifFactor(
            a, b, blendif: blendif, parameters: parameters, combineINCL: combineINCL)
        var opacity = combineINCL
            ? 1 - (1 - form) * (1 - conditional)
            : form * conditional
        if combineINV { opacity = 1 - opacity }
        return gopacity * opacity
    }

    /// `blendop_mask_tone_curve` (blendop.cl:1309-1449) in Double.
    public static func toneCurve(
        _ opacity: Double, e: Double, brightness: Double, gopacity: Double
    ) -> Double {
        let maskEpsilon = 16.0 * Double.ulpOfOne
        var scaled = 2.0 * opacity / gopacity - 1.0
        if 1 - brightness <= 0 {
            scaled = opacity <= maskEpsilon ? -1 : 1
        } else if 1 + brightness <= 0 {
            scaled = opacity >= 1 - maskEpsilon ? 1 : -1
        } else if brightness > 0 {
            scaled = min((scaled + brightness) / (1 - brightness), 1)
        } else {
            scaled = max((scaled + brightness) / (1 + brightness), -1)
        }
        let cval = 0.5 * (scaled * e / (1 + (e - 1) * abs(scaled))) + 0.5
        let mval = cval > 1e-6 ? cval : 0.0
        return min(max(mval, 0), 1) * gopacity
    }
}
