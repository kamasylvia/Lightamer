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
//   strict  — ≥ 99.9% of samples: relative error < 1e-5 (the plan gate)
//   envelope— ALL samples: relative < 2e-4 OR absolute < 2e-4 (the
//             ≤ ~3-LSB LUT cliff envelope)
//
// Pure-arithmetic modules (exposure/temperature) keep the plain 1e-5
// per-pixel gate and must not use this helper.
enum ParityGate {

    static func evaluate(
        _ got: [Float], _ ref: [Float],
        strict: Float = 1e-5,
        strictAbsFloor: Float = 1e-5,
        envelope: Float = 2e-4,
        strictFraction: Double = 0.999
    ) -> (maxRelative: Float, strictViolations: Int, envelopeViolations: Int) {
        precondition(got.count == ref.count)
        var maxRelative: Float = 0
        var strictViolations = 0
        var envelopeViolations = 0
        for i in 0..<ref.count {
            let diff = abs(got[i] - ref[i])
            let rel = diff / max(abs(ref[i]), 1e-9)
            maxRelative = max(maxRelative, rel)
            // The abs floor keeps the strict gate meaningful on near-zero
            // references (deep shadows): float32 cancellation noise in the
            // dark region (116·fy−16 in lab_f_inv) is ~2.5e-6 absolute —
            // 150x below the LUT LSB (1.5e-3) and far below any visible
            // step (8-bit LSB = 3.9e-3), so it must not count as a
            // relative violation.
            let strictOK = rel < strict || diff < strictAbsFloor
            let envelopeOK = rel < envelope || diff < envelope
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
        strictAbsFloor: Float = 1e-5,
        envelope: Float = 2e-4,
        strictFraction: Double = 0.999
    ) -> String? {
        let result = evaluate(
            got, ref, strict: strict, strictAbsFloor: strictAbsFloor,
            envelope: envelope, strictFraction: strictFraction
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
