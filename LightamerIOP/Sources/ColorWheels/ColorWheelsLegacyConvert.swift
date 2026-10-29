//  Ported from Alcedo Studio `color_wheel_tone.hpp` / `color_wheel_tone.cpp`
//  (commit e1effd8, read via `git show`; upstream working tree is stale).
//
//  Copyright 2026 Yurun Zi
//  SPDX-License-Identifier: GPL-3.0-only
//  Additional permission under GPLv3 section 7 applies; see the LICENSE file.
//
//  Modifications (Lightamer adaptation, GPL-3.0 as part of this repository,
//  marked per the relicensing NOTICE): Swift re-expression in the Float64
//  domain; the legacy input is our existing v1 `ColorWheelsModule.Params`
//  shape (lift all-zero, gamma/gain neutral (1,1,1) — no separate
//  LegacyColorWheelValues type); the output quad rides the additive
//  `Params.offset` optional (D-M9SP-2) instead of the upstream
//  `version_one_json` persistence round-trip (our conversion exists only in
//  the render pre-resolve and the panel edit projection — nothing is written
//  to history/sidecar until the user edits on the v3 arm).

import Foundation
import LightamerCore

/// The v3 tone-wheel conversion face (Plan M9-4 T1, X2 / D-M9SP-2):
/// converts a legacy (pre-tone-wheel, v1-semantic) `Params` into the full
/// four-wheel tone-wheel shape. The v1 lift becomes the Offset exactly
/// (a v1 lift adds to ACEScc — the same change in stops for every tone);
/// the v1 gamma and gain become Lift / Gamma / Gain values from a
/// least-squares fit of the per-channel change in stops from
/// `kToneBlackEv` to `kToneWhiteEv`. Pure functions, Float64 (Gauss-Newton
/// transliteration of the upstream fit).
public enum ColorWheelsLegacyConvert {

    // Constants mirror upstream color_wheel_tone.cpp anonymous namespace.
    static let toneRangeEv = Double(ColorWheelsModule.toneWhiteEv)
        - Double(ColorWheelsModule.toneBlackEv)
    /// The smallest 0.5 + K / R in the Gamma exponent, so that p stays
    /// finite and positive.
    static let minGammaBase = 0.05
    static let fitSampleCount = 25
    static let fitMaxIteration = 20
    /// The numerical-Jacobian step (upstream `kStep`).
    static let jacobianStep = 1.0e-4
    /// The Gauss-Newton convergence threshold on |ΔK| (sum of absolutes).
    static let convergenceThreshold = 1.0e-9

    // MARK: - Public conversion entry (X2 consumer single source)

    /// Converts the legacy (offset-absent) shape to the tone-wheel quad.
    /// The output carries `offset` PRESENT (the v2-semantic discriminator,
    /// D-M9SP-2 补强①) — call sites are the v3 render pre-resolve and the
    /// v3 panel's edit projection (first edit materializes the offset).
    public static func convertLegacyColorWheel(
        _ legacy: ColorWheelsModule.Params
    ) -> ColorWheelsModule.Params {
        let liftStops = ColorWheelsModule.controlChannelStops(legacy.lift)
        let gammaStops = ColorWheelsModule.controlChannelStops(legacy.gamma)
        let gainStops = ColorWheelsModule.controlChannelStops(legacy.gain)

        var offsetStops = SIMD3<Double>.zero
        var liftFitted = SIMD3<Double>.zero
        var gammaFitted = SIMD3<Double>.zero
        var gainFitted = SIMD3<Double>.zero
        for ch in 0..<3 {
            // A version 1 lift adds to ACEScc: the same change in stops for
            // every tone (the Offset definition).
            let legacyLift = Double(liftStops[ch])
            let legacyGamma = max(Double(gammaStops[ch]), 1.0e-4)
            let legacyGain = Double(gainStops[ch])
            offsetStops[ch] = legacyLift * Double(ColorWheelsModule.acesccB)
            if legacyGamma == 1.0 && legacyGain == 1.0 { continue }
            let fit = fitLegacyGammaGain(
                legacyLift: legacyLift, legacyGamma: legacyGamma,
                legacyGain: legacyGain)
            liftFitted[ch] = fit.lift
            gammaFitted[ch] = fit.gamma
            gainFitted[ch] = fit.gain
        }

        var out = ColorWheelsModule.Params()
        // The fitted wheels keep the raw stops in colorOffset/luminance
        // (NO truncation — the disc is clamped to the unit circle as UI
        // state only; the rendering consumes colorOffset + luminance, so
        // what renders IS the fitted value).
        out.offset = wheelControlFromStops(offsetStops)
        out.lift = wheelControlFromStops(liftFitted)
        out.gamma = wheelControlFromStops(gammaFitted)
        out.gain = wheelControlFromStops(gainFitted)
        return out
    }

    // MARK: - Fit (upstream FitLegacyGammaGain, Float64)

    /// Lift, Gamma, and Gain stops that best match the version 1 operation
    /// `c' = sign(c) · |c + lift|^gamma · gain` on one channel, in stops,
    /// for inputs c from kToneBlackEv to kToneWhiteEv. The version 1 lift
    /// is the Offset, which the tone wheels apply first.
    static func fitLegacyGammaGain(
        legacyLift: Double, legacyGamma: Double, legacyGain: Double
    ) -> (lift: Double, gamma: Double, gain: Double) {
        let grey = Double(ColorWheelsModule.acesccMiddleGrey)
        let b = Double(ColorWheelsModule.acesccB)
        let black = grey + Double(ColorWheelsModule.toneBlackEv) / b
        let range = toneRangeEv / b

        var input = [Double](repeating: 0, count: fitSampleCount)
        var target = [Double](repeating: 0, count: fitSampleCount)
        for i in 0..<fitSampleCount {
            let ev = Double(ColorWheelsModule.toneBlackEv)
                + toneRangeEv * Double(i) / Double(fitSampleCount - 1)
            let c = grey + ev / b
            input[i] = c + legacyLift
            // copysign rides the ORIGINAL c sign (upstream detail — not the
            // shifted input's sign).
            target[i] = copysign(pow(abs(input[i]), legacyGamma), c) * legacyGain
        }

        // Residuals in stops of the Lift / Gamma / Gain stops k.
        func residuals(_ k: SIMD3<Double>) -> [Double] {
            var r = [Double](repeating: 0, count: fitSampleCount)
            for i in 0..<fitSampleCount {
                let out = applyLiftGammaGainFloat64(
                    acescc: input[i], black: black, range: range,
                    liftScale: k.x / toneRangeEv,
                    gammaExponent: ColorWheelsModule.gammaExponent(stops: k.y),
                    gainScale: k.z / toneRangeEv)
                r[i] = (out - target[i]) * b
            }
            return r
        }

        var k = SIMD3<Double>.zero
        for _ in 0..<fitMaxIteration {
            let r = residuals(k)
            // Jacobian[p][i] = ∂r_i/∂k_p (numerical, upstream kStep).
            var jacobian = [[Double]](repeating: [], count: 3)
            for p in 0..<3 {
                var shifted = k
                shifted[p] += jacobianStep
                let rs = residuals(shifted)
                var column = [Double](repeating: 0, count: fitSampleCount)
                for i in 0..<fitSampleCount {
                    column[i] = (rs[i] - r[i]) / jacobianStep
                }
                jacobian[p] = column
            }
            var normal = [[Double]](repeating: [0, 0, 0], count: 3)
            var gradient = SIMD3<Double>.zero
            for p in 0..<3 {
                for q in 0..<3 {
                    var sum = 0.0
                    for i in 0..<fitSampleCount {
                        sum += jacobian[p][i] * jacobian[q][i]
                    }
                    normal[p][q] = sum
                }
                for i in 0..<fitSampleCount {
                    gradient[p] -= jacobian[p][i] * r[i]
                }
            }
            let delta = solve3(normal, gradient)
            k += delta
            if abs(delta.x) + abs(delta.y) + abs(delta.z) < convergenceThreshold {
                break
            }
        }
        return (lift: k.x, gamma: k.y, gain: k.z)
    }

    /// Lift, Gamma, and Gain on one ACEScc value (Float64 mirror of the
    /// upstream `ApplyLiftGammaGain`; Offset is applied before this).
    /// Exposed on the module for the convert face; the render pre-resolve
    /// has its own Float32 CPU form (`applyToneWheels`).
    static func applyLiftGammaGainFloat64(
        acescc: Double, black: Double, range: Double,
        liftScale: Double, gammaExponent: Double, gainScale: Double
    ) -> Double {
        var t = (acescc - black) / range
        t += liftScale * min(max(1 - t, 0), 1)
        if t > 0 && t < 1 {
            t = pow(t, gammaExponent)
        }
        t += gainScale * max(t, 0)
        return black + t * range
    }

    /// Upstream `GammaExponent` lives on the module (single source —
    /// `ColorWheelsModule.gammaExponent(stops:)`); the fit consumes it
    /// through that path.

    // MARK: - Stops → wheel control (upstream anonymous `WheelControlFromStops`)

    /// Splits the per-channel stops into the wheel control: the mean rides
    /// luminance, the zero-mean part rides colorOffset, and the disc is the
    /// `ChannelStopsToDisc` inversion of the zero-mean part (clamped onto
    /// the unit circle — UI state only).
    static func wheelControlFromStops(_ stops: SIMD3<Double>) -> ColorWheelControl {
        let master = (stops.x + stops.y + stops.z) / 3
        var control = ColorWheelControl()
        control.strength = ColorWheelsModule.discMaxStops
        control.luminanceOffset = Float(master)
        let zeroMean = SIMD3<Float>(
            Float(stops.x - master), Float(stops.y - master), Float(stops.z - master))
        control.colorOffset = zeroMean
        control.disc = ColorWheelsModule.channelStopsToDisc(
            zeroMean, strength: control.strength)
        return control
    }

    // MARK: - 3×3 solve (upstream `Solve3` — Gaussian elimination, partial pivoting)

    /// Solves the 3×3 system `a · x = b` with Gaussian elimination and
    /// partial pivoting; a degenerate pivot returns zero.
    static func solve3(
        _ a: [[Double]], _ b: SIMD3<Double>
    ) -> SIMD3<Double> {
        var m = a
        var rhs = [b.x, b.y, b.z]
        for col in 0..<3 {
            var pivot = col
            for row in (col + 1)..<3 where abs(m[row][col]) > abs(m[pivot][col]) {
                pivot = row
            }
            m.swapAt(col, pivot)
            rhs.swapAt(col, pivot)
            if abs(m[col][col]) < 1.0e-15 { return .zero }
            for row in (col + 1)..<3 {
                let factor = m[row][col] / m[col][col]
                for k in col..<3 {
                    m[row][k] -= factor * m[col][k]
                }
                rhs[row] -= factor * rhs[col]
            }
        }
        var x = SIMD3<Double>.zero
        for row in stride(from: 2, through: 0, by: -1) {
            var sum = rhs[row]
            for k in (row + 1)..<3 {
                sum -= m[row][k] * x[k]
            }
            x[row] = sum / m[row][row]
        }
        return x
    }
}
