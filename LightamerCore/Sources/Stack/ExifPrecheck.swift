import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// EXIF bracket precheck (Plan 08-1 T2; RESEARCH §2.4) — the linear-merge
// admissibility gate, evaluated from the ImageIO capture metadata BEFORE any
// decode work.
//
// The §2.4 table (row = field, tolerance):
//   • camera body / lens model  — STRICTLY equal (missing metadata on either
//     side → warning, never a rejection: synthetic/legacy files legitimately
//     lack lens reports — the execution decision recorded in DECISIONS)
//   • focal length              — STRICTLY equal (±0.5 mm; EXIF quantizes
//     to integer mm)
//   • aperture (f-number)       — STRICTLY equal; DIFFERING aperture = a
//     bracket outside the linear-merge premise → REJECT by default, the
//     user override admits WITH a warning (the aperture delta then rides
//     the runtime exposure-ratio self-check, §1.2)
//   • ISO                       — STRICTLY equal; differing = noise-weight
//     distortion → the same reject/override posture as aperture
//   • shutter                   — MUST DIFFER (the bracket itself); equal
//     exposures = not a bracket → reject
//
// ΔEV composition (the merge weight's exposure ratio): log2(t_ref / t_i) +
// log2(ISO_i / ISO_ref) — the aperture is assumed equal (override admits it
// as unknown error the self-check bounds).
//
// Runtime self-check (§1.2, R2 消解): the EXIF-expected ratio 2^ΔEV is
// compared against the MEASURED median ratio on the unclipped overlapping
// luma band; a >5% deviation flags the frame unverified (merge proceeds,
// provenance `exposureRatioVerified = false`).
// ─────────────────────────────────────────────────────────────────────────────

public enum ExifPrecheck {

    /// One candidate's verdict (the reference frame is implicitly `ok`).
    public enum Verdict: Sendable, Equatable {

        /// Admitted; carries the composed ΔEV (the merge weight's ratio).
        case ok(exposureEV: Double)

        /// Admitted WITH a warning (override pass or missing metadata);
        /// the warning strings join the provenance notes.
        case admittedWithWarning(exposureEV: Double, reasons: [String])

        /// Rejected — the merge is a hard failure with these reasons.
        case rejected(reasons: [String])
    }

    // MARK: - Per-candidate gate (research §2.4 row order)

    /// Check `candidate` against the `reference` capture metadata.
    /// - Parameters:
    ///   - allowOverrides: the user's aperture/ISO override (admit with
    ///     warnings instead of rejecting).
    public static func precheck(
        reference: CaptureMetadata,
        candidate: CaptureMetadata,
        allowOverrides: Bool
    ) -> Verdict {
        var rejections: [String] = []
        var warnings: [String] = []

        // Body (make+model): strictly equal.
        if !metadataMatches(reference.cameraModel, candidate.cameraModel) {
            rejections.append(
                "camera mismatch: \(reference.cameraModel ?? "?") vs "
                    + "\(candidate.cameraModel ?? "?")")
        }
        // Lens: strictly equal (missing on either side → warning only).
        if reference.lensModel != nil || candidate.lensModel != nil {
            if reference.lensModel != candidate.lensModel {
                if reference.lensModel == nil || candidate.lensModel == nil {
                    warnings.append(
                        "lens metadata missing on one side: "
                            + "\(reference.lensModel ?? "?") vs "
                            + "\(candidate.lensModel ?? "?")")
                } else {
                    rejections.append(
                        "lens mismatch: \(reference.lensModel ?? "?") vs "
                            + "\(candidate.lensModel ?? "?")")
                }
            }
        }
        // Focal length: strictly equal (integer-mm quantization → 0.5 mm).
        if let refFocal = reference.focalLength, let candFocal = candidate.focalLength {
            if abs(refFocal - candFocal) > 0.5 {
                rejections.append(
                    "focal length mismatch: \(refFocal)mm vs \(candFocal)mm")
            }
        } else {
            warnings.append("focal length metadata missing")
        }
        // Aperture: strictly equal; differing → reject unless overridden.
        let apertureDiffers: Bool
        if let refAperture = reference.aperture, let candAperture = candidate.aperture {
            apertureDiffers = abs(refAperture - candAperture) > 0.05
            if apertureDiffers {
                if allowOverrides {
                    warnings.append(
                        String(
                            format: "aperture override: f/%.1f vs f/%.1f",
                            refAperture, candAperture))
                } else {
                    rejections.append(
                        String(
                            format: "aperture mismatch: f/%.1f vs f/%.1f",
                            refAperture, candAperture))
                }
            }
        } else {
            apertureDiffers = true // unknown — the self-check must bound it
            warnings.append("aperture metadata missing")
        }
        // ISO: strictly equal; the same override posture.
        var isoRatio = 1.0
        if let refISO = reference.iso, let candISO = candidate.iso {
            if refISO != candISO {
                isoRatio = Double(candISO) / Double(refISO)
                if allowOverrides {
                    warnings.append("ISO override: \(refISO) vs \(candISO)")
                } else {
                    rejections.append("ISO mismatch: \(refISO) vs \(candISO)")
                }
            }
        } else {
            warnings.append("ISO metadata missing")
        }
        // Shutter: MUST differ (the bracket itself).
        if let refShutter = reference.shutterSpeed, let candShutter = candidate.shutterSpeed {
            if abs(refShutter - candShutter) < 1e-9 {
                rejections.append(
                    "identical exposures \(refShutter)s — not a bracket")
            }
        } else {
            warnings.append("shutter metadata missing")
        }

        // ΔEV composition (§2.4): shutter ratio + ISO ratio; the aperture
        // (overridden or missing) stays OUT — the runtime self-check bounds
        // whatever it contributes.
        var exposureEV = 0.0
        if let refShutter = reference.shutterSpeed, let candShutter = candidate.shutterSpeed,
           candShutter > 0 {
            exposureEV += log2(refShutter / candShutter)
        }
        exposureEV += log2(isoRatio)

        if !rejections.isEmpty {
            return .rejected(reasons: rejections)
        }
        if warnings.isEmpty {
            return .ok(exposureEV: exposureEV)
        }
        return .admittedWithWarning(exposureEV: exposureEV, reasons: warnings)
    }

    /// The run of the whole bracket (reference first). Returns per-frame
    /// verdicts in input order (the reference's own verdict is `.ok(0)`).
    public static func precheck(
        captures: [CaptureMetadata], allowOverrides: Bool
    ) -> [Verdict] {
        guard let reference = captures.first else { return [] }
        var verdicts: [Verdict] = [.ok(exposureEV: 0)]
        for index in captures.indices.dropFirst() {
            verdicts.append(
                precheck(
                    reference: reference, candidate: captures[index],
                    allowOverrides: allowOverrides))
        }
        return verdicts
    }

    /// nil on BOTH sides matches (absent metadata); nil vs present does not
    /// (the caller decides warning vs rejection per field).
    private static func metadataMatches(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case let (lhs?, rhs?): return lhs == rhs
        case (nil, nil): return true
        default: return false
        }
    }

    // MARK: - The STACK-variant precheck (Plan 08-3 T4; research §2.4
    // adapted — the criteria-difference table is D-08-3-T4-4)

    /// The focus-rail / stacking-denoise admissibility: the same STRICT
    /// body/lens/focal/aperture gates (the depth-of-field consistency
    /// premise needs the aperture equal), but the shutter and ISO are NOT
    /// required to DIFFER — a rail/stack keeps constant settings, and an
    /// auto-exposure drift is a WARNING, never a rejection. The exposureEV
    /// is a flat 0 (stacks carry no exposure weighting — the ΔEV
    /// composition only feeds the HDR merge weights).
    public static func precheckStack(
        reference: CaptureMetadata,
        candidate: CaptureMetadata,
        allowOverrides: Bool
    ) -> Verdict {
        var rejections: [String] = []
        var warnings: [String] = []

        if !metadataMatches(reference.cameraModel, candidate.cameraModel) {
            rejections.append(
                "camera mismatch: \(reference.cameraModel ?? "?") vs "
                    + "\(candidate.cameraModel ?? "?")")
        }
        if reference.lensModel != nil || candidate.lensModel != nil {
            if reference.lensModel != candidate.lensModel {
                if reference.lensModel == nil || candidate.lensModel == nil {
                    warnings.append(
                        "lens metadata missing on one side: "
                            + "\(reference.lensModel ?? "?") vs "
                            + "\(candidate.lensModel ?? "?")")
                } else {
                    rejections.append(
                        "lens mismatch: \(reference.lensModel ?? "?") vs "
                            + "\(candidate.lensModel ?? "?")")
                }
            }
        }
        if let refFocal = reference.focalLength, let candFocal = candidate.focalLength {
            if abs(refFocal - candFocal) > 0.5 {
                rejections.append(
                    "focal length mismatch: \(refFocal)mm vs \(candFocal)mm")
            }
        } else {
            warnings.append("focal length metadata missing")
        }
        if let refAperture = reference.aperture, let candAperture = candidate.aperture {
            if abs(refAperture - candAperture) > 0.05 {
                if allowOverrides {
                    warnings.append(
                        String(
                            format: "aperture override: f/%.1f vs f/%.1f",
                            refAperture, candAperture))
                } else {
                    rejections.append(
                        String(
                            format: "aperture mismatch: f/%.1f vs f/%.1f",
                            refAperture, candAperture))
                }
            }
        } else {
            warnings.append("aperture metadata missing")
        }
        // ISO / shutter: differing (when known) is a drift NOTE, never a
        // rejection — the bracket's "must differ" rule does NOT apply to
        // stacks (the constant-shutter premise is the norm here).
        if let refISO = reference.iso, let candISO = candidate.iso, refISO != candISO {
            warnings.append("ISO drift: \(refISO) vs \(candISO)")
        } else if reference.iso == nil || candidate.iso == nil {
            warnings.append("ISO metadata missing")
        }
        if let refShutter = reference.shutterSpeed,
           let candShutter = candidate.shutterSpeed,
           abs(refShutter - candShutter) >= 1e-9 {
            warnings.append(
                "shutter drift: \(refShutter)s vs \(candShutter)s")
        } else if reference.shutterSpeed == nil || candidate.shutterSpeed == nil {
            warnings.append("shutter metadata missing")
        }

        if !rejections.isEmpty {
            return .rejected(reasons: rejections)
        }
        if warnings.isEmpty {
            return .ok(exposureEV: 0)
        }
        return .admittedWithWarning(exposureEV: 0, reasons: warnings)
    }

    /// The run of the whole stack (reference first).
    public static func precheckStack(
        captures: [CaptureMetadata], allowOverrides: Bool
    ) -> [Verdict] {
        guard let reference = captures.first else { return [] }
        var verdicts: [Verdict] = [.ok(exposureEV: 0)]
        for index in captures.indices.dropFirst() {
            verdicts.append(
                precheckStack(
                    reference: reference, candidate: captures[index],
                    allowOverrides: allowOverrides))
        }
        return verdicts
    }

    // MARK: - The runtime exposure-ratio self-check (§1.2)

    /// Compare the MEASURED median ratio of the two frames' unclipped luma
    /// against the EXIF expectation `2^ΔEV`. Operates on the decimated
    /// UNNORMALIZED float surfaces (`AlignmentFrame.RatioLuma` — physical
    /// values, so the ratio is physical).
    ///
    /// - Returns: `(verified, measuredRatio)` — `verified == false` (a >5%
    ///   deviation) means the merge proceeds with
    ///   `exposureRatioVerified = false` in the provenance.
    public static func exposureRatioCheck(
        reference: AlignmentFrame.RatioLuma,
        candidate: AlignmentFrame.RatioLuma,
        expectedEV: Double,
        tolerance: Double = 0.05
    ) -> (verified: Bool, measuredRatio: Double) {
        let measured = Self.jointBandRatio(reference, candidate)
        let expected = pow(2.0, expectedEV)
        guard measured > 0, expected.isFinite, expected > 0 else {
            // Degenerate band (all-clipped or all-black) — cannot verify.
            return (false, 0)
        }
        let deviation = abs(measured / expected - 1)
        return (deviation <= tolerance, measured)
    }

    /// The §1.2 "overlapping band where NEITHER frame is clipped": pixels
    /// inside BOTH frames' gate windows (a per-frame band would truncate
    /// the brighter frame's distribution and bias the median ratio). The
    /// surfaces are the same decimation grid — index-aligned by
    /// construction. Returns median(cmp) / median(ref) over the joint
    /// band (0 = degenerate).
    static func jointBandRatio(
        _ reference: AlignmentFrame.RatioLuma,
        _ candidate: AlignmentFrame.RatioLuma
    ) -> Double {
        let clipGate: Float = 0.995
        let floorGate: Float = 0.001
        let count = min(reference.pixels.count, candidate.pixels.count)
        var referenceBand: [Float] = []
        var candidateBand: [Float] = []
        referenceBand.reserveCapacity(count / 4)
        for index in 0..<count {
            let r = reference.pixels[index]
            let c = candidate.pixels[index]
            if r > floorGate && r < clipGate && c > floorGate && c < clipGate {
                referenceBand.append(r)
                candidateBand.append(c)
            }
        }
        guard referenceBand.count >= 16 else { return 0 }
        referenceBand.sort()
        candidateBand.sort()
        let middle = referenceBand.count / 2
        let referenceMedian = referenceBand[middle]
        let candidateMedian = candidateBand[middle]
        guard referenceMedian > 0 else { return 0 }
        return Double(candidateMedian / referenceMedian)
    }
}
