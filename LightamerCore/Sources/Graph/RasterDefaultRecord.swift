import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// RasterDefaultRecord — the raster document's default DRT record derivation
// (Plan M4-1-01 T10, KD-9; the OQ-1 effective ruling = the Alcedo D2 form:
// the raster document opens WITH an aces20 DRT whose limiting/peak/EOTF
// mirror the source description — no defaultLook mint, the RGC off).
//
// THE JOINT RULE (the M3-4 validateCoreOrder single-source precedent): the
// derived (encodingSpace, encodingEotf) pair MUST sit inside
// `legalEOTFs(encodingSpace)` — the two tables stay SEPARATE:
//   • limitingSpace keeps the SOURCE domain (the seven-value set —
//     AdobeRGB/ProPhoto legal here);
//   • encodingSpace is the DISPLAY-encoding domain (six values —
//     AdobeRGB/ProPhoto map to rec709 with a reason).
//
// THE FALLBACK CHAINS (per space, miss → the chain head + a reason):
//   rec709: srgbPiecewise > gamma22 > bt1886
//   p3d65:  gamma22 > st2084 > srgbPiecewise
//   p3d60 / p3dci / xyz: gamma26 (the single-value sets)
//   rec2020: st2084 > hlg
// The `gamma18` value is never produced (it sits in no legal set — the
// model layer keeps it persistable, the derivation never offers it).
//
// THE LINEAR SPECIAL CASE (explicit): display-referred linear (the
// LUT-ICC arm) and scene-linear linear → (rec709, srgbPiecewise) + a
// reason — the legal sets are not widened. The ONE exception is the
// scene-linear probe branch: referral == .sceneLinear with a content probe
// > 1.0 → (rec2020, st2084) — the only legal pair that can arm the
// existing DRT-HDR viewport face (an SDR-labeled document must not ride
// rec2020's all-HDR set, so a Rec2020-primary SDR linear source falls back
// to rec709 with a reason).
//
// RGC POLICY (OQ-3): the raster document runs the aces20 arm with RGC OFF
// in BOTH directions (`Aces2Reference.params(..., rgcOn: false)` — the
// render-side policy, NOT a record field: DrtRecord stays zero-field, zero
// hash face). `isRasterDocument` is the single source the EotfBox/arm
// assembly consumes (M4-1-02 wires the call sites; this plan lands the
// pure function + tests).
// ─────────────────────────────────────────────────────────────────────────────

public enum RasterDefaultRecord {

    /// The derivation product: the record + why a default landed (the
    /// walkthrough observation face — DrtRecord carries no reason field).
    public struct Derivation: Sendable, Equatable {
        public let record: DrtRecord
        /// nil = the source described itself into the record without a
        /// fallback; non-nil = the fallback/special-case reason.
        public let defaultReason: String?
    }

    // MARK: - The HDR flag (OQ-4)

    /// `transfer ∈ {st2084, hlg}` OR (scene-linear ∧ content probe > 1.0).
    /// The scene-linear referral IS the float32 marker (both ②/①′ halves
    /// require float storage); the probe is the decode-time deterministic
    /// subsampled channel max (T6's `RasterNativePixels.contentProbeMax`).
    public static func isHdrRaster(
        _ description: RasterColorDescription, contentProbeMax: Float
    ) -> Bool {
        switch description.transfer {
        case .st2084, .hlg: return true
        default: break
        }
        return description.referral == .sceneLinear && contentProbeMax > 1.0
    }

    // MARK: - The RGC policy (the render-side single source)

    /// The raster-document predicate (the description rides `DecodedImage`
    /// only on the native leg — nil = every pre-existing path).
    public static func isRasterDocument(
        _ rasterColor: RasterColorDescription?
    ) -> Bool {
        rasterColor != nil
    }

    /// The aces20-arm RGC switch for a document (the OQ-3 effective value:
    /// raster documents run RGC OFF in both directions; RAW documents keep
    /// the forward's default ON).
    public static func rgcOn(rasterColor: RasterColorDescription?) -> Bool {
        !isRasterDocument(rasterColor)
    }

    // MARK: - The derivation

    /// Derive the default aces20 record for one description. Pure; the
    /// (space, eotf) pair is invariantly inside `legalEOTFs(space)` (the
    /// T10 joint-rule negative tests pin it row by row).
    public static func derive(
        from description: RasterColorDescription, contentProbeMax: Float
    ) -> Derivation {
        var reasons: [String] = []

        // ── the scene-linear probe branch FIRST (the HDR exception) ──
        if description.referral == .sceneLinear, contentProbeMax > 1.0 {
            let record = assemble(
                encodingSpace: .rec2020, encodingEotf: .st2084,
                limitingSpace: nearestLimitingSpace(description.primariesXY).space,
                peak: description.peakLuminanceNits)
            reasons.append(
                "scene-linear float32 with content probe > 1.0 → the DRT-HDR pair (rec2020, st2084)")
            return Derivation(
                record: record, defaultReason: reasons.joined(separator: "; "))
        }

        // ── the encoding space (the display-encoding domain table) ──
        let limiting = nearestLimitingSpace(description.primariesXY)
        if limiting.reason != nil {
            reasons.append(limiting.reason!)
        }
        let encoding: (space: DrtEncodingSpace, reason: String?)
        switch limiting.space {
        case .rec709:
            encoding = (.rec709, nil)
        case .p3d65:
            encoding = (.p3d65, nil)
        case .adobeRGB:
            encoding = (.rec709,
                "AdobeRGB is not a display-encoding space — encoding falls back to rec709 (the source domain rides limitingSpace)")
        case .proPhoto:
            encoding = (.rec709,
                "ProPhoto is not a display-encoding space — encoding falls back to rec709 (the source domain rides limitingSpace)")
        case .rec2020:
            // rec2020's legal set is ALL HDR — an SDR source must not ride
            // it; the TRC check below decides.
            encoding = (.rec2020, nil)
        case .p3d60, .p3dci:
            encoding = (.rec709,
                "the source primaries map to \(limiting.space.rawValue) — encoding falls back to rec709")
        }

        // ── the encoding EOTF (the nearest legal neighbor of the TRC) ──
        let eotf: (DrtEotf, reason: String?)
        switch description.transfer {
        case .linear:
            // The linear special case: no SDR-legal near neighbor exists —
            // the sRGB piecewise approximates the display mapping. A
            // rec2020 encoding with an SDR linear source would mislabel
            // the document HDR (rec2020's set is all-HDR) → rec709.
            eotf = (.srgbPiecewise,
                "source linear transfer has no SDR-legal near neighbor — the display pair approximates with the sRGB piecewise")
            if encoding.space == .rec2020 {
                let r = eotf.reason!
                    + "; Rec2020 primaries with an SDR linear source must not ride rec2020's all-HDR legal set — encoding falls back to rec709"
                return Derivation(
                    record: assemble(
                        encodingSpace: .rec709, encodingEotf: .srgbPiecewise,
                        limitingSpace: limiting.space,
                        peak: description.peakLuminanceNits),
                    defaultReason: reasons.joined(separator: "; ") + r)
            }
        case .srgbPiecewise:
            eotf = (.srgbPiecewise, nil)
        case .st2084:
            eotf = (.st2084, nil)
        case .hlg:
            eotf = (.hlg, nil)
        case .bt1886:
            eotf = (.bt1886, nil)
        case .gamma(let g):
            eotf = nearestLegalGamma(
                g, encodingSpace: encoding.space)
        case .iccParametric(let type, let params):
            if type == 0, let g = params.first {
                // The type-0 parametric IS a pure gamma.
                eotf = nearestLegalGamma(g, encodingSpace: encoding.space)
            } else {
                eotf = (fallbackHead(encoding.space),
                    "the parametric TRC (type \(type)) has no analytic near neighbor — the space's fallback head stands in")
            }
        case .iccSampled:
            // A sampled table that did NOT canonicalize matched no analytic
            // form within the gates — the fallback head stands in.
            eotf = (fallbackHead(encoding.space),
                "the sampled TRC matched no analytic form within the canonicalization gates — the space's fallback head stands in")
        }

        var encodingSpace = encoding.space
        var encodingReason = encoding.reason
        // The TRC legality check: the eotf must sit in the encoding space's
        // legal set (e.g. st2084 with rec709-encoding — illegal → the
        // space changes to the TRC's home or the fallback head lands).
        let legal = legalEOTFs(for: encoding.space)
        if !legal.contains(eotf.0) {
            // Try the TRC's natural home space first (st2084/hlg → rec2020,
            // everything else → rec709), else the fallback head of the
            // ORIGINAL encoding space.
            let home: DrtEncodingSpace
            switch eotf.0 {
            case .st2084, .hlg: home = .rec2020
            default: home = .rec709
            }
            if legalEOTFs(for: home).contains(eotf.0) {
                reasons.append(
                    "the TRC \(eotf.0.rawValue) is illegal for \(encoding.space.rawValue) — the encoding space follows the TRC home (\(home.rawValue))")
                encodingSpace = home
                if encodingReason == nil {
                    encodingReason = "the encoding space followed the TRC's legal home"
                }
            } else {
                let head = fallbackHead(encoding.space)
                if eotf.reason != nil { reasons.append(eotf.reason!) }
                reasons.append(
                    "the TRC \(eotf.0.rawValue) is illegal for \(encoding.space.rawValue) — the fallback head (\(head.rawValue)) stands in")
                return Derivation(
                    record: assemble(
                        encodingSpace: encoding.space, encodingEotf: head,
                        limitingSpace: limiting.space,
                        peak: description.peakLuminanceNits),
                    defaultReason: reasons.joined(separator: "; "))
            }
        }
        if let r = eotf.reason { reasons.append(r) }
        if let r = encodingReason, eotf.reason == nil { reasons.append(r) }

        return Derivation(
            record: assemble(
                encodingSpace: encodingSpace, encodingEotf: eotf.0,
                limitingSpace: limiting.space,
                peak: description.peakLuminanceNits),
            defaultReason: reasons.isEmpty
                ? nil : reasons.joined(separator: "; "))
    }

    // MARK: - The mapping helpers

    /// The nearest of the five known chromaticity sets (the distance = the
    /// summed per-component offset). Beyond the match gate the source is
    /// "unknown" → the limiting rec2020 + a reason (the KD-9 else-row).
    static func nearestLimitingSpace(
        _ primaries: SIMD8<Float>
    ) -> (space: DrtLimitingSpace, reason: String?) {
        let candidates: [(DrtLimitingSpace, SIMD8<Float>)] = [
            (.rec709, RasterColorResolver.sRGBPrimaries),
            (.p3d65, RasterColorResolver.displayP3Primaries),
            (.adobeRGB, RasterColorResolver.adobeRGBPrimaries),
            (.rec2020, RasterColorResolver.rec2020Primaries),
            (.proPhoto, RasterColorResolver.proPhotoPrimaries),
        ]
        var best = candidates[0]
        var bestDistance = Double.greatestFiniteMagnitude
        for candidate in candidates {
            var distance = 0.0
            for i in 0..<8 {
                distance += abs(Double(candidate.1[i] - primaries[i]))
            }
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        // The gate: a per-component mean above ~0.002 means "unknown
        // primaries" (the synthetic/arbitrary ICC case).
        if bestDistance / 8.0 > 0.002 {
            return (.rec2020,
                "the source primaries match no known space — the limiting gamut falls back to rec2020")
        }
        return (best.0, nil)
    }

    /// The gamma → legal-EOTF nearest neighbor. The pinned fits: 2.6 →
    /// gamma26, 2.4 → bt1886, 2.2 → gamma22, 1.8 → gamma22 + a reason
    /// (gamma18 sits in NO legal set — the model layer keeps it persistable,
    /// the derivation never offers it). Other gammas → the nearest legal
    /// member of the space; a miss → the space's fallback head.
    static func nearestLegalGamma(
        _ g: Double, encodingSpace: DrtEncodingSpace
    ) -> (DrtEotf, reason: String?) {
        let legal = legalEOTFs(for: encodingSpace)
        // The pinned fits.
        let pinned: (DrtEotf, Double) =
            abs(g - 2.6) <= 0.05 ? (.gamma26, abs(g - 2.6))
            : abs(g - 2.4) <= 0.05 ? (.bt1886, abs(g - 2.4))
            : abs(g - 2.2) <= 0.1 ? (.gamma22, abs(g - 2.2))
            : abs(g - 1.8) <= 0.1 ? (.gamma22, abs(g - 1.8))
            : (fallbackHead(encodingSpace), .greatestFiniteMagnitude)
        if pinned.1 != .greatestFiniteMagnitude {
            if legal.contains(pinned.0) {
                let reason: String? = abs(g - 1.8) <= 0.1 && abs(g - 2.2) > 0.05
                    ? "gamma \(g) snaps to gamma22 — gamma18 sits in no legal set (the derivation never offers it)"
                    : nil
                return (pinned.0, reason)
            }
            // The pinned fit is illegal for this space → the nearest legal
            // member by exponent distance.
            return nearestByExponent(g, legal: legal, encodingSpace: encodingSpace)
        }
        return nearestByExponent(g, legal: legal, encodingSpace: encodingSpace)
    }

    private static func nearestByExponent(
        _ g: Double, legal: [DrtEotf], encodingSpace: DrtEncodingSpace
    ) -> (DrtEotf, reason: String?) {
        let exponents: [(DrtEotf, Double)] = [
            (.gamma26, 2.6), (.bt1886, 2.4), (.gamma22, 2.2),
        ]
        var best = exponents[0]
        for candidate in exponents where legal.contains(candidate.0) {
            if abs(candidate.1 - g) < abs(best.1 - g) || !legal.contains(best.0) {
                best = candidate
            }
        }
        if legal.contains(best.0) {
            return (best.0,
                "gamma \(g) snaps to the nearest legal member (\(best.0.rawValue)) of \(encodingSpace.rawValue)")
        }
        let head = fallbackHead(encodingSpace)
        return (head,
            "gamma \(g) has no legal near neighbor in \(encodingSpace.rawValue) — the fallback head (\(head.rawValue)) stands in")
    }

    /// The per-space fallback chain head (the KD-9 chains).
    static func fallbackHead(_ space: DrtEncodingSpace) -> DrtEotf {
        legalEOTFs(for: space)[0]
    }

    /// The record assembly (method aces20, peak = the description peak,
    /// the remaining fields at the document defaults).
    private static func assemble(
        encodingSpace: DrtEncodingSpace, encodingEotf: DrtEotf,
        limitingSpace: DrtLimitingSpace, peak: Float
    ) -> DrtRecord {
        var record = DrtRecord()
        record.method = .aces20
        record.encodingSpace = encodingSpace
        record.encodingEotf = encodingEotf
        record.limitingSpace = limitingSpace
        record.peakLuminance = peak
        return record
    }
}
