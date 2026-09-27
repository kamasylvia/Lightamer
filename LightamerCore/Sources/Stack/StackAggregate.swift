import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// StackAggregate (Plan 08-3 T3; RESEARCH §6, D-08-CONTEXT-3) — the three
// stacking-denoise aggregation operators over ONE band's N-value stack.
//
// The three modes are the SAME band iterator with a swapped operator
// (the service's kind dispatch picks the operator; the alignment/exposure
// segments are shared with 08-1):
//   • average      — the linear-domain arithmetic mean (√N noise gain, the
//                    physical expectation unchanged; the DEFAULT mode),
//   • median       — the per-pixel median of the valid values (motion
//                    robust; even counts average the two central order
//                    statistics — D-08-3-T3-2),
//   • sigma-clipped— mean μ → population σ → reject |x−μ| > k·σ → re-mean
//                    of the survivors (star trails / satellite passes).
//                    The σ estimator is the POPULATION standard deviation
//                    about the mean, k default 2.5 (D-08-3-T3-1).
//
// BAND SHAPE (research §6): the N-value stack exists ONLY within one band
// (N=8 · 256 rows · RGB ≈ 286 MB) — a single in-band pass computes the
// aggregate; NO second full pass and NO sliding window. Anything that
// holds N full planes at once violates R3 — `bandStackBytes` is the
// regression lock's formula and the tests pin it.
//
// DEGENERATE N (research R6): with N = 3 the σ-clip can NEVER reject (the
// maximal z-score of a 3-sample set is (N−1)/√N ≈ 1.155 < k) — the mode
// honestly degrades to the average and the service warns (same posture as
// the HDR de-ghost N=3 note).
//
// MISSING SAMPLES (alignment edges): NaN entries are skipped; a pixel with
// zero valid contributors aggregates to NaN (the driver folds those into
// the holeFraction — the HOLE vocabulary of 08-1).
// ─────────────────────────────────────────────────────────────────────────────

public enum StackAggregate {

    /// The stacking-denoise operators (kind-mapped: stack-average /
    /// stack-median / stack-sigma).
    public enum Mode: String, Sendable, CaseIterable {
        case average
        case median
        case sigmaClip = "sigma-clip"
    }

    /// The sigma-clip rejection threshold (|dev| > k·σ ⇒ rejected; the
    /// default 2.5 sits between the siril/dcr conventions of 2 and 3 —
    /// D-08-3-T3-1).
    public static let defaultSigmaK: Float = 2.5

    // MARK: - Memory accounting (the R3 regression lock's formula)

    /// ONE band's N-value stack: N sources × band rows × width × RGB
    /// float32. The plan's reference point: N=8 · 256 rows · 11656 px =
    /// 286 MB. O(band), never O(height).
    public static func bandStackBytes(
        width: Int, bandHeight: Int, sources: Int
    ) -> Int {
        sources * bandHeight * width * 3 * MemoryLayout<Float>.size
    }

    // MARK: - The operators

    /// Aggregate one pixel's valid (non-NaN) samples. `stack` holds the N
    /// values at `stride` offsets from `base` (the band stack is
    /// source-major: source i's value lives at `base + i * stride`).
    /// Returns NaN when no sample is valid.
    @inline(__always)
    public static func aggregatePixel(
        _ stack: [Float], base: Int, stride: Int, count: Int,
        mode: Mode, sigmaK: Float = StackAggregate.defaultSigmaK
    ) -> Float {
        var valid: [Float] = []
        valid.reserveCapacity(count)
        for index in 0..<count {
            let value = stack[base + index * stride]
            if value.isFinite { valid.append(value) }
        }
        guard !valid.isEmpty else { return Float.nan }
        return aggregate(valid, mode: mode, sigmaK: sigmaK)
    }

    /// Aggregate a whole band stack (source-major: `stack[i]` holds source
    /// i's band rows as interleaved RGB). Returns interleaved RGB band rows.
    public static func aggregateBand(
        _ stack: [[Float]], mode: Mode,
        sigmaK: Float = StackAggregate.defaultSigmaK
    ) -> [Float] {
        precondition(!stack.isEmpty, "aggregateBand needs ≥ 1 source plane")
        let rowFloats = stack[0].count
        for plane in stack {
            precondition(plane.count == rowFloats, "band stack plane size mismatch")
        }
        var result = [Float](repeating: 0, count: rowFloats)
        for index in 0..<rowFloats {
            var valid: [Float] = []
            valid.reserveCapacity(stack.count)
            for plane in stack where plane[index].isFinite {
                valid.append(plane[index])
            }
            guard !valid.isEmpty else {
                result[index] = Float.nan
                continue
            }
            result[index] = aggregate(valid, mode: mode, sigmaK: sigmaK)
        }
        return result
    }

    /// The operator over an already-gathered valid sample set (the
    /// `aggregatePixel` core without the stride gathering).
    @inline(__always)
    public static func aggregate(
        _ valid: [Float], mode: Mode,
        sigmaK: Float = StackAggregate.defaultSigmaK
    ) -> Float {
        switch mode {
        case .average:
            return valid.reduce(0, +) / Float(valid.count)
        case .median:
            let sorted = valid.sorted()
            let middle = sorted.count / 2
            if sorted.count & 1 == 1 {
                return sorted[middle]
            }
            return (sorted[middle - 1] + sorted[middle]) / 2
        case .sigmaClip:
            let mean = valid.reduce(0, +) / Float(valid.count)
            var squared = 0.0 as Float
            for value in valid {
                let deviation = value - mean
                squared += deviation * deviation
            }
            let sigma = (squared / Float(valid.count)).squareRoot()
            if sigma == 0 {
                return mean
            }
            var sum: Float = 0
            var survivors = 0
            for value in valid where abs(value - mean) <= sigmaK * sigma {
                sum += value
                survivors += 1
            }
            guard survivors > 0 else { return mean }
            return sum / Float(survivors)
        }
    }

    /// The maximal possible |z| of an N-sample set under the POPULATION σ
    /// (ddof=0): √(N−1) — the proof anchor of the degenerate notes. The
    /// default k=2.5 cannot reject anything below N=8 (k ≥ √7); the tests
    /// pin it.
    public static func maxZScore(sampleCount: Int) -> Float {
        guard sampleCount > 1 else { return 0 }
        return (Float(sampleCount) - 1).squareRoot()
    }
}
