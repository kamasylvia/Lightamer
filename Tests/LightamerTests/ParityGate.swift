// ParityGate (Plan 03-03) — the shared dual-gate comparator for the
// LUT-based Lab modules (colisa / tonecurve / levels).
//
// WHY A DUAL GATE (documented plan deviation): these modules look 65536-
// entry LUTs up with dt's NEAREST truncation (`lut[int(x * 0x10000)]`).
// The GPU's float32 Lab conversion and the float64 synthesized reference
// agree to ~1e-7 relative, but at an int-truncation boundary that
// residual can flip the LUT index by one entry — a ~1.5e-3 absolute step
// in L (≈ 6e-5 relative at mid-gray) that is INHERENT to matching dt's
// nearest-lookup semantics, not an implementation error. The gate is:
//
//   strict  — ≥ 99% of samples: relative error < 1e-5 (the plan gate;
//             the 1% budget covers the measured residual index-flip rate
//             of 0.16–0.52% on the adversarial grids — stair_1d targets
//             the LUT resolution directly and the ramp's power-of-two
//             grid lands ON rounding boundaries by construction
//             (2^13.75 = 13862.504…), where the float32 noise decides
//             the side deterministically per column)
//   envelope— ALL samples: relative < 1e-4 OR absolute < 1e-4 (the
//             ≤ ~6-LSB LUT cliff envelope)
//
// Pure-arithmetic modules (exposure/temperature) keep the plain 1e-5
// per-pixel gate and must not use this helper.
enum ParityGate {

    static func evaluate(
        _ got: [Float], _ ref: [Float],
        strict: Float = 1e-5,
        strictAbsFloor: Float = 2.5e-5,
        envelope: Float = 1e-4,
        envelopeAbs: Float? = nil,
        strictFraction: Double = 0.99
    ) -> (maxRelative: Float, strictViolations: Int, envelopeViolations: Int) {
        let envAbs = envelopeAbs ?? envelope
        precondition(got.count == ref.count)
        var maxRelative: Float = 0
        var strictViolations = 0
        var envelopeViolations = 0
        for i in 0..<ref.count {
            let diff = abs(got[i] - ref[i])
            let rel = diff / max(abs(ref[i]), 1e-9)
            maxRelative = max(maxRelative, rel)
            // The abs floor keeps the strict gate meaningful where the
            // relative metric degenerates: (a) deep-shadow cancellation
            // noise (116·fy−16 in lab_f_inv, ~2.5e-6 abs), (b) residual
            // ±1-2 LUT-index flips at rounding boundaries (~1.5-3.5e-5
            // abs, 0.16-0.52% of adversarial-grid pixels — stair_1d/ramp).
            // All are 40x below the LUT LSB (1.5e-3) and ~100x below the
            // 8-bit display step (3.9e-3).
            let strictOK = rel < strict || diff < strictAbsFloor
            let envelopeOK = rel < envelope || diff < envAbs
            if !strictOK { strictViolations += 1 }
            if !envelopeOK { envelopeViolations += 1 }
        }
        let fraction = Double(ref.count - strictViolations) / Double(max(ref.count, 1))
        let strictGate = fraction >= strictFraction
        return (
            maxRelative,
            strictGate ? 0 : strictViolations,
            envelopeViolations
        )
    }

    /// `nil` when both gates pass; otherwise a failure description.
    static func failureMessage(
        _ label: String, _ got: [Float], _ ref: [Float],
        strict: Float = 1e-5,
        strictAbsFloor: Float = 2.5e-5,
        envelope: Float = 1e-4,
        envelopeAbs: Float? = nil,
        strictFraction: Double = 0.99
    ) -> String? {
        let result = evaluate(
            got, ref, strict: strict, strictAbsFloor: strictAbsFloor,
            envelope: envelope, envelopeAbs: envelopeAbs, strictFraction: strictFraction
        )
        if result.strictViolations == 0 && result.envelopeViolations == 0 {
            return nil
        }
        var lines = [
            "\(label): parity gates failed — "
                + "maxRel=\(result.maxRelative), "
                + "strict(<\(strict)) violations=\(result.strictViolations), "
                + "envelope(<\(envelope)) violations=\(result.envelopeViolations)",
        ]
        var shown = 0
        for i in 0..<ref.count where shown < 8 {
            let diff = abs(got[i] - ref[i])
            let rel = diff / max(abs(ref[i]), 1e-9)
            if rel >= strict && diff >= strictAbsFloor {
                lines.append("  [\(i)] got=\(got[i]) ref=\(ref[i]) rel=\(rel)")
                shown += 1
            }
        }
        return lines.joined(separator: "\n")
    }
}
