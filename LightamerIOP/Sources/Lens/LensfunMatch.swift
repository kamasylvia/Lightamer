import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// LensfunMatch — EXIF match + focal resolve + coefficient normalization
// (Plan 04-04-T2, IOP-GEO-03 (c) → (b) unified exit).
//
// Pipeline: `match(metadata:in:)` → `LensEntry?`, then
// `resolve(entry:focal:aperture:distance:crop:imageWidth:imageHeight:)`
// → `LensKernelParams` (kernel-unit coefficients feeding the SAME
// `lens_manual_warp` kernel as the manual sliders — D-G1's literal demand).
//
// LENSFUN SEMANTICS (GitHub lensfun/lensfun master, read 2026-09-20):
// - Cropfactor calibration-set choice (`lens.cpp Interpolate*`): the set
//   with the closest cropfactor where `imageCrop/setCrop ≥ 0.96`.
// - Distortion/TCA focal interpolation: 4-point Catmull-Rom-ish Hermite
//   (`_lf_interpolate`, `auxfun.cpp`) over sorted focal rows; exact focal
//   → direct take; single bracketing row → nearest take; `__parameter_
//   scales` is IDENTITY for poly3/poly5/ptlens/linear/poly3-TCA/pa
//   (non-ACM only — v1 carries no ACM rows, so no focal pre-scaling).
// - Vignetting: inverse-distance weighting p=3.5 over the (focal,
//   aperture, distance) grid (`__vignetting_dist`: focal LINEAR in the
//   lens's [MinFocal..MaxFocal] span, aperture → 4/a, distance → 0.1/d).
//   Exact (dist < 1e-4) → direct take; min-dist > 1 → NO correction.
// - Distortion d-factor (`mod-coord.cpp` header): poly3 k1' = k1/d³ with
//   d = 1−k1; ptlens a' = a/d⁴, b' = b/d³, c' = c/d², d = 1−a−b−c.
// - Hugin rescale (`rescale_polynomial_coefficients`):
//     huginMM_dist = 21.633/Crop/hypot(Aspect,1)   [half-height in mm]
//     huginMM_vig  = 21.633/Crop                    [corner in mm]
//     huginScaling = RealFocal/huginMM  (× the (NS·HW) kernel-unit fold)
//   distortion: poly3 k1×s²; poly5 k1×s²,k2×s⁴; ptlens a×s³,b×s²,c×s
//   TCA poly3: cr,cb×s; br,bb×s² (vr/vb/linear untouched)
//   vig pa: k1×s², k2×s⁴, k3×s⁶
//   with s = huginScaling·NS·HW (NS·HW folds the normalized→kernel-unit
//   step: kernel r=1 at halfW pixels, lensfun normalized r=1 at
//   1/NS "pixels" — ratio NS·HW).
//
// This file implements distortion/TCA/VIGNETTING resolve EXACTLY per the
// above, except the vignetting focal axis: lensfun normalizes the focal
// distance by the LENS's global [MinFocal..MaxFocal] span; v1 derives the
// span from the lens's own vignetting rows (min/max focal present —
// recorded approximation, 04-04-DECISIONS D-04-04-T0-3).
//
// REFUSALS (never silent wrongness): non-rectilinear `<type>`; mixed
// distortion models in one lens (lensfun warns + takes the first — v1
// takes the first too); no distortion AND no TCA AND no vignette rows → nil.
// ─────────────────────────────────────────────────────────────────────────

/// Kernel-unit resolved coefficients (the (c)→(b) unified exit — feeds
/// `LensWarpUniforms` exactly like the manual path).
public struct LensKernelParams: Sendable {
    /// The SOURCE projection carried from the entry `<type>` (LENS-03 T1 —
    /// the kernel fold reads it; empty/nil = rectilinear identity).
    var sourceProjection: String?
    /// The run-time projection spellings the uniforms stamp carries
    /// (decoded leniently at the resolveUniforms seam; nil = rectilinear).
    var targetProjectionRaw: String?
    var sourceProjectionRaw: String?
    var dc1: Float = 0
    var dc2: Float = 0
    var dc3: Float = 0
    var dc4: Float = 0
    var vr: Float = 1
    var cr: Float = 0
    var br: Float = 0
    var vb: Float = 1
    var cb: Float = 0
    var bb: Float = 0
    var vk1: Float = 0
    var vk2: Float = 0
    var vk3: Float = 0
    var centerX: Float = 0
    var centerY: Float = 0

    /// Stamp the run geometry (center defaults to frame center when the
    /// XML carries no `<center>`); `scale` = the LENS-02 T3 resolved
    /// scale (1.0 default = the pre-L2 face).
    func uniforms(
        bufW: Int, bufH: Int, roiIn: ROI, roiOut: ROI, scale: Float = 1.0
    ) -> LensWarpUniforms {
        LensWarpUniforms(
            dc1: dc1, dc2: dc2, dc3: dc3, dc4: dc4,
            vr: vr, cr: cr, br: br, vb: vb, cb: cb, bb: bb,
            vk1: vk1, vk2: vk2, vk3: vk3,
            centerX: centerX == 0 && centerY == 0 ? Float(bufW) / 2 : centerX,
            centerY: centerY == 0 && centerX == 0 ? Float(bufH) / 2 : centerY,
            halfW: Float(bufW) / 2,
            oroiX: Float(roiOut.x), oroiY: Float(roiOut.y),
            iroiX: Int32(roiIn.x), iroiY: Int32(roiIn.y),
            inW: Int32(bufW), inH: Int32(bufH),
            scale: scale,
            sourceProjection: LensProjection.decodeLenient(
                sourceProjectionRaw ?? sourceProjection).rawValue,
            targetProjection: LensProjection.decodeLenient(
                targetProjectionRaw).rawValue)
    }
}

/// The matched-profile display face (public — the App panel readout
/// consumes the outcome through `LensfunStore.matchOutcome`; the resolve
/// face reaches the underlying entry through the INTERNAL index, valid
/// within one store stamp).
public struct LensMatchedProfile: Sendable {
    public let maker: String
    /// The first model variant (the display name).
    public let model: String
    public let cropFactor: Double
    /// The entry slot in the installed db (internal — NOT a stable id;
    /// every consumer re-resolves through the store in the same stamp).
    let entryIndex: Int
    /// The entry `<type>` (LENS-03 T1 — the no-target refusal face; empty
    /// = the rectilinear default).
    let projectionHint: String?

    public init(maker: String, model: String, cropFactor: Double, entryIndex: Int) {
        self.maker = maker
        self.model = model
        self.cropFactor = cropFactor
        self.entryIndex = entryIndex
        self.projectionHint = nil
    }

    init(maker: String, model: String, cropFactor: Double, entryIndex: Int,
         projectionHint: String?) {
        self.maker = maker
        self.model = model
        self.cropFactor = cropFactor
        self.entryIndex = entryIndex
        self.projectionHint = projectionHint
    }

    /// The type spelling for the refusal face (nil/empty = rectilinear).
    var modelProjectionHint: String? { projectionHint }
    var sourceProjectionRaw: String? { projectionHint }
}

/// The resolved-coefficient snapshot (LENS-04 T1, D-LENS-3 / X3): baked
/// at the match commit, the render face reads THIS with ZERO database
/// dependence. The dbTag is the AUDIT field — strip-on-hash (the
/// paramsHash input strips it, so a DB update never shifts the cache
/// key; the value itself changes only via an explicit Re-match commit).
struct LensCoefficientSnapshot: Codable, Hashable, Sendable {
    // ── The RESOLUTION-INDEPENDENT calibration extract (the matched
    // entry's rows + the resolve parameters) — the consumption face
    // re-runs the resolve math at the CURRENT resolution, so a baked
    // document renders identically at ANY plane size and ANY database
    // state (the H-L2 gate).
    var distortionRows: [DistortionCalib]?
    var tcaRows: [TCACalib]?
    var vignetteRows: [VignetteCalib]?
    var realFocalRows: [LensCalibrations.RealFocalRow]?
    var aspectRatio: Double = 1.5
    var entryCrop: Double = 1.5
    var center: LensEntry.CenterPoint?
    var lensType: String?
    // The resolve parameters (focal/aperture ride the top-level fields
    // already; the distance stays unknown = the nearest-distance face).
    var profileMaker: String?
    var profileModel: String?
    var profileMount: String?
    var profileCrop: Float?
    var matchScore: Int?
    /// The audit stamp (X3: strip-on-hash — see LensModule.commitParams).
    var dbTag: String?

    init() {}



    /// Rebuild the VIRTUAL entry the consumption face re-resolves through
    /// (only the calibration subset — identity/matching never touch it).
    func virtualEntry() -> LensEntry {
        var e = LensEntry(maker: profileMaker ?? "")
        e.models = [profileModel ?? ""]
        e.cropfactor = entryCrop
        e.aspectRatio = aspectRatio
        e.type = lensType
        e.center = center
        var cal = LensCalibrations()
        cal.distortions = distortionRows ?? []
        cal.tcas = tcaRows ?? []
        cal.vignettes = vignetteRows ?? []
        cal.realFocals = realFocalRows ?? []
        e.calibrations = cal
        return e
    }
}

/// One scored library row for the profile browser (LENS-02 T4; the
/// ordering/confidence annotation lives in the App-side model).
public struct LensCandidateRow: Sendable, Equatable {
    public let maker: String
    public let model: String
    public let score: Int

    public init(maker: String, model: String, score: Int) {
        self.maker = maker
        self.model = model
        self.score = score
    }
}

/// The hardened-match result (NOT a persisted face — the panel readout
/// consumes it through `LensfunStore.matchOutcome`). Mirrors the RawLab
/// state machine: ambiguous = same-top-score multiple candidates
/// REJECTED, never guessed (D-LENS-4). Top-level (shared by
/// `LensfunMatch` and `LensfunStore`).
public enum LensMatchOutcome: Sendable {
    case matched(LensMatchedProfile, score: Int)
    /// Multiple entries tie at the top score — refuse (RawLab
    /// `FindLenses` semantics; wrong correction beats no correction).
    case ambiguous(score: Int)
    /// No candidate reached the auto-apply threshold (includes the
    /// crop-gated-out and 40-tier cases).
    case noLens
    /// The caller carries no lens EXIF string at all.
    case missingFocal
    // `noDatabase` is the store-level state (LensfunStore.isInstalled
    // == false) — the readout maps it before matching is attempted.
}

enum LensfunMatch {

    /// The auto/committed auto-apply match threshold (D-LENS-4): the
    /// contains tier (60) and up qualifies for the AUTOMATIC channel; the
    /// word-overlap tier (40) stays visible in the profile browser as a
    /// low-confidence ordering hint but NEVER auto-selects. Single
    /// declaration point (the acceptance grep pins this).
    static let autoApplyThreshold = 60

    /// Full-scan counter for the memo tests (LENS-01 T4): incremented once
    /// per `matchHardened` invocation — a memo hit must NOT touch it.
    /// Test-only observability (never read on production paths).
    nonisolated(unsafe) static var scanCounter = 0

    // MARK: - Normalization (04-RESEARCH §4c)

    /// Lowercase + trim + collapse whitespace + strip the aperture
    /// `f/…` segment + strip a leading maker token.
    static func normalizeModel(_ s: String, maker: String? = nil) -> String {
        var out = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Strip "f/2.8"-style aperture segments.
        out = out.replacingOccurrences(of: "f/\\S+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let maker, !maker.isEmpty {
            let m = maker.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if out.hasPrefix(m + " ") { out = String(out.dropFirst(m.count + 1)) }
            else if out == m { out = "" }
        }
        return out
    }

    /// Score for one (exif, candidate) pair: 100 = exact, 60+ = contains
    /// either way, 0 = no hit. Brand-prefix-insensitive on both sides.
    static func modelScore(exif: String, candidate: String, maker: String? = nil) -> Int {
        let e = normalizeModel(exif, maker: maker)
        let c = normalizeModel(candidate, maker: maker)
        guard !e.isEmpty, !c.isEmpty else { return 0 }
        if e == c { return 100 }
        if e.contains(c) || c.contains(e) { return 60 }
        // Word-overlap fallback: every EXIF word present in the candidate.
        let ew = Set(e.split(separator: " ").map(String.init))
        let cw = Set(c.split(separator: " ").map(String.init))
        if !ew.isEmpty && ew.isSubset(of: cw) { return 40 }
        return 0
    }

    // MARK: - Match

    /// Best lens for the EXIF metadata (nil = miss — NOT a failure; the
    /// caller degrades to the manual layer and the match-ledger records it).
    /// Crop gate: `imageCrop/entryCrop ≥ 0.96` (lensfun `Interpolate*`
    /// calibration-set choice); entries with cropfactor ≤ 0 never match.
    static func match(
        maker: String?, model: String?, lens: String?,
        imageCrop: Double, in db: LensfunDB
    ) -> LensEntry? {
        var best: (entry: LensEntry, score: Int)?
        for entry in db.lenses {
            guard entry.cropfactor > 0, imageCrop > 0 else { continue }
            guard imageCrop / entry.cropfactor >= 0.96 else { continue }
            var score = 0
            if let lens, !lens.isEmpty {
                for m in entry.models {
                    score = max(score, modelScore(exif: lens, candidate: m, maker: entry.maker))
                }
                // Maker agreement bonus (lensfun FindLenses weighs maker).
                if let maker, !maker.isEmpty,
                   entry.maker.lowercased().contains(maker.lowercased())
                    || maker.lowercased().contains(entry.maker.lowercased()) {
                    if score > 0 { score += 5 }
                }
            } else if let model, !model.isEmpty {
                // No lens string: fall back to camera-model substring (weak).
                for m in entry.models {
                    let c = normalizeModel(m, maker: entry.maker)
                    if c.contains(normalizeModel(model)) { score = max(score, 20) }
                }
            }
            if score > (best?.score ?? 0) { best = (entry, score) }
        }
        return best?.entry
    }

    /// The HARDENED auto-channel match (D-LENS-4, LENS-01 T3): the full
    /// parameter path (maker/model/imageCrop real values — the pre-T3
    /// `resolveCommitted` passed nil/nil/1.0, so the crop gate never
    /// bit), the ≥60 threshold tier (40 word-overlap NEVER auto-selects),
    /// and the RawLab ambiguity refusal (top-score ties REJECTED).
    static func matchHardened(
        maker: String?, model: String?, lens: String?,
        imageCrop: Double, in db: LensfunDB
    ) -> LensMatchOutcome {
        LensfunMatch.scanCounter += 1
        guard lens != nil && !(lens ?? "").isEmpty else { return .missingFocal }
        var best: (profile: LensMatchedProfile, score: Int)?
        var bestCount = 0
        for (entryIndex, entry) in db.lenses.enumerated() {
            guard entry.cropfactor > 0, imageCrop > 0 else { continue }
            // The CROP GATE — with a real camera imageCrop this actually
            // rejects full-frame lens strings against APS-C calibration
            // sets (the pre-T3 1.0 hardcode disabled it de facto).
            guard imageCrop / entry.cropfactor >= 0.96 else { continue }
            var score = 0
            if let lens, !lens.isEmpty {
                for m in entry.models {
                    score = max(score, modelScore(exif: lens, candidate: m, maker: entry.maker))
                }
                if let maker, !maker.isEmpty,
                   entry.maker.lowercased().contains(maker.lowercased())
                    || maker.lowercased().contains(entry.maker.lowercased()) {
                    if score > 0 { score += 5 }
                }
            }
            if score > (best?.score ?? 0) {
                best = (
                    LensMatchedProfile(
                        maker: entry.maker, model: entry.models.first ?? "",
                        cropFactor: entry.cropfactor, entryIndex: entryIndex,
                        projectionHint: entry.type?.lowercased()),
                    score)
                bestCount = 1
            } else if score == best?.score, score > 0 {
                bestCount += 1
            }
        }
        guard let best else { return .noLens }
        // Threshold tier: below 60 = the word-overlap (40) / weak (20)
        // bands — browser-ordering hints only, never auto-selected.
        guard best.score >= autoApplyThreshold else { return .noLens }
        if bestCount > 1 { return .ambiguous(score: best.score) }
        return .matched(best.profile, score: best.score)
    }

    /// RawLab `FindCameras` semantics (D-LENS-4): the camera entry must be
    /// UNIQUE — zero hits or multiple hits both yield nil (the imageCrop
    /// priority chain then falls through to 1.0 at the resolve site).
    static func uniqueCameraCrop(
        maker: String?, model: String?, in db: LensfunDB
    ) -> Double? {
        var hits: [CameraEntry] = []
        for cam in db.cameras {
            guard cam.cropfactor > 0 else { continue }
            var makerOK = true
            if let maker, !maker.isEmpty {
                makerOK = cam.maker.lowercased().contains(maker.lowercased())
                    || maker.lowercased().contains(cam.maker.lowercased())
            }
            guard makerOK else { continue }
            guard let model, !model.isEmpty else { continue }
            let modelHit = cam.models.contains { m in
                modelScore(exif: model, candidate: m, maker: cam.maker) >= autoApplyThreshold
            }
            guard modelHit else { continue }
            hits.append(cam)
        }
        guard hits.count == 1, let cam = hits.first else { return nil }
        return cam.cropfactor
    }

    // MARK: - Focal interpolation (Hermite, auxfun.cpp)

    /// `_lf_interpolate` verbatim (FLT_MAX-missing-edge Hermite).
    static func hermite(y1: Double, y2: Double, y3: Double, y4: Double, t: Double) -> Double {
        let m1 = y1.isInfinite ? y3 - y2 : (y3 - y1) * 0.5
        let m2 = y4.isInfinite ? y3 - y2 : (y4 - y2) * 0.5
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * y2 + (t3 - 2 * t2 + t) * m1
            + (-2 * t3 + 3 * t2) * y3 + (t3 - t2) * m2
    }

    /// 4-point spline row selection over sorted focal rows (lens.cpp
    /// `InterpolateDistortion` pattern): exact → the row; below/above all
    /// rows → nearest; else Hermite between the bracketing pair with
    /// outer neighbors (or ±∞ edges).
    static func splineRows<T>(
        _ rows: [(focal: Double, value: T)], focal: Double
    ) -> (lower: (focal: Double, value: T), upper: (focal: Double, value: T)?, t: Double) {
        let sorted = rows.sorted { $0.focal < $1.focal }
        if let exact = sorted.first(where: { $0.focal == focal }) {
            return (exact, nil, 0)
        }
        guard let lo = sorted.last(where: { $0.focal < focal }) else {
            return (sorted[0], nil, 0)
        }
        guard let hi = sorted.first(where: { $0.focal > focal }) else {
            return (sorted.last!, nil, 0)
        }
        return (lo, hi, (focal - lo.focal) / (hi.focal - lo.focal))
    }

    // MARK: - Resolve

    /// Full resolve → kernel-unit params (nil = refuse: fisheye type /
    /// no usable rows / vignette grid too far).
    /// - `distance`: meters; nil/NaN/≤0 = unknown → nearest-distance rows.
    /// - `imageCrop`: the camera's cropfactor (EXIF camera match or 1.0).
    static func resolve(
        entry: LensEntry, focal: Double, aperture: Double?,
        distance: Double?, crop imageCrop: Double,
        imageWidth: Int, imageHeight: Int,
        targetProjection: String? = nil
    ) -> LensKernelParams? {
        // LENS-03 T1 (D-LENS-8): the non-rectilinear REFUSAL is lifted —
        // an entry `<type>` folds into the kernel's sourceProjection (the
        // projection fold handles the re-mapping); the CALLER decides via
        // targetProjection (unset = the conservative rectilinear-only
        // face, enforced in resolveCommitted — no target set means a
        // non-rectilinear source has nowhere to land, and the old blit-
        // identity refusal stands).
        if let t = entry.type?.lowercased(), t != "rectilinear" && t != "" {
            guard targetProjection != nil else { return nil }
        }
        let aspect = entry.aspectRatio > 0 ? entry.aspectRatio : 1.5
        let realFocal = realFocalFor(entry: entry, focal: focal)
        // NS·HW: normalized→kernel-unit fold (resolution-free).
        let w = Double(max(imageWidth, 1)), h = Double(max(imageHeight, 1))
        let normScale = 43.2666153056 / imageCrop / ((w + 1) * (w + 1) + (h + 1) * (h + 1)).squareRoot() / realFocal
        let nshw = normScale * (w / 2)
        var out = LensKernelParams()
        var haveAny = false

        if let d = interpolateDistortion(entry: entry, focal: focal) {
            // d-factor + hugin rescale (mod-coord.cpp), folded with NS·HW.
            let huginMM = 43.2666153056 / entry.cropfactor / (aspect * aspect + 1).squareRoot()
            let s = (realFocal / huginMM) * nshw
            switch d.model {
            case .poly3:
                let k1 = d.terms[0]
                let df = 1 - k1
                guard abs(df) > 1e-9 else { return nil }
                out.dc2 = Float(k1 * s * s / (df * df * df))
            case .poly5:
                out.dc2 = Float(d.terms[0] * s * s)
                out.dc4 = Float(d.terms[1] * s * s * s * s)
            case .ptlens:
                let (a, b, c) = (d.terms[0], d.terms[1], d.terms[2])
                let df = 1 - a - b - c
                guard abs(df) > 1e-9 else { return nil }
                out.dc3 = Float(a * s * s * s / pow(df, 4))
                out.dc2 = Float(b * s * s / (df * df * df))
                out.dc1 = Float(c * s / (df * df))
            }
            haveAny = true
        }
        if let t = interpolateTCA(entry: entry, focal: focal) {
            let huginMM = 43.2666153056 / entry.cropfactor / (aspect * aspect + 1).squareRoot()
            let s = (realFocal / huginMM) * nshw
            switch t.model {
            case .linear:
                out.vr = Float(t.kr); out.vb = Float(t.kb)
            case .poly3:
                out.vr = Float(t.vr); out.vb = Float(t.vb)
                out.cr = Float(t.cr * s); out.cb = Float(t.cb * s)
                out.br = Float(t.br * s * s); out.bb = Float(t.bb * s * s)
            }
            haveAny = true
        }
        if let v = interpolateVignetting(
            entry: entry, focal: focal, aperture: aperture ?? 0,
            distance: distance, crop: imageCrop) {
            let huginMM = 43.2666153056 / entry.cropfactor
            let s = (realFocal / huginMM) * nshw
            out.vk1 = Float(v.k1 * s * s)
            out.vk2 = Float(v.k2 * s * s * s * s)
            out.vk3 = Float(v.k3 * pow(s, 6))
            haveAny = true
        }
        guard haveAny else { return nil }
        out.sourceProjection = entry.type?.lowercased()
        if let c = entry.center {
            // XML center is in lensfun normalized units → kernel pixels.
            out.centerX = Float(c.x / normScale + w / 2)
            out.centerY = Float(c.y / normScale + h / 2)
        }
        return out
    }

    /// `<real-focal-length>` row at/nearest the focal, else nominal.
    static func realFocalFor(entry: LensEntry, focal: Double) -> Double {
        guard !entry.calibrations.realFocals.isEmpty else { return focal }
        var best = entry.calibrations.realFocals[0]
        for r in entry.calibrations.realFocals.dropFirst() {
            if abs(r.focal - focal) < abs(best.focal - focal) { best = r }
        }
        return best.real
    }

    /// Distortion focal interpolation (first model wins on mixed — the
    /// lensfun warning path). Rows of OTHER models are ignored.
    static func interpolateDistortion(entry: LensEntry, focal: Double) -> DistortionCalib? {
        let rows = entry.calibrations.distortions
        guard let first = rows.first else { return nil }
        let model = first.model
        let terms = rows.filter { $0.model == model }.map { (focal: $0.focal, value: $0.terms) }
        guard !terms.isEmpty else { return nil }
        let sel = splineRows(terms, focal: focal)
        guard let hi = sel.upper else { return DistortionCalib(model: model, focal: focal, terms: sel.lower.value) }
        // Outer neighbors for the Hermite edges (±∞ when missing).
        let sorted = terms.sorted { $0.focal < $1.focal }
        let loIdx = sorted.firstIndex(where: { $0.focal == sel.lower.focal })!
        let hiIdx = sorted.firstIndex(where: { $0.focal == hi.focal })!
        var out: [Double] = []
        for i in 0..<sel.lower.value.count {
            let y1 = loIdx > 0 ? sorted[loIdx - 1].value[i] : .infinity
            let y4 = hiIdx + 1 < sorted.count ? sorted[hiIdx + 1].value[i] : .infinity
            out.append(hermite(y1: y1, y2: sel.lower.value[i], y3: hi.value[i], y4: y4, t: sel.t))
        }
        return DistortionCalib(model: model, focal: focal, terms: out)
    }

    /// TCA focal interpolation (same spline; linear rows carry kr/kb).
    static func interpolateTCA(entry: LensEntry, focal: Double) -> TCACalib? {
        let rows = entry.calibrations.tcas
        guard let first = rows.first else { return nil }
        let model = first.model
        let same = rows.filter { $0.model == model }
        func vec(_ r: TCACalib) -> [Double] {
            model == .linear ? [r.kr, r.kb] : [r.vr, r.vb, r.cr, r.cb, r.br, r.bb]
        }
        let terms = same.map { (focal: $0.focal, value: vec($0)) }
        let sel = splineRows(terms, focal: focal)
        func pack(_ v: [Double]) -> TCACalib {
            if model == .linear {
                return TCACalib(model: .linear, focal: focal, kr: v[0], kb: v[1])
            }
            return TCACalib(model: .poly3, focal: focal,
                            vr: v[0], vb: v[1], cr: v[2], cb: v[3], br: v[4], bb: v[5])
        }
        guard let hi = sel.upper else { return pack(sel.lower.value) }
        let sorted = terms.sorted { $0.focal < $1.focal }
        let loIdx = sorted.firstIndex(where: { $0.focal == sel.lower.focal })!
        let hiIdx = sorted.firstIndex(where: { $0.focal == hi.focal })!
        var out: [Double] = []
        for i in 0..<sel.lower.value.count {
            let y1 = loIdx > 0 ? sorted[loIdx - 1].value[i] : .infinity
            let y4 = hiIdx + 1 < sorted.count ? sorted[hiIdx + 1].value[i] : .infinity
            out.append(hermite(y1: y1, y2: sel.lower.value[i], y3: hi.value[i], y4: y4, t: sel.t))
        }
        return pack(out)
    }

    /// Vignetting IDW p=3.5 (`InterpolateVignetting` verbatim incl. the
    /// focal-span normalization from the lens's own rows).
    static func interpolateVignetting(
        entry: LensEntry, focal: Double, aperture: Double,
        distance: Double?, crop imageCrop: Double
    ) -> VignetteCalib? {
        let rows = entry.calibrations.vignettes
        guard !rows.isEmpty else { return nil }
        let focals = rows.map(\.focal)
        let minF = focals.min()!, maxF = focals.max()!
        let span = maxF - minF
        let dist = distance.flatMap { $0.isNaN || $0 <= 0 ? nil : $0 }
        func gridDist(_ r: VignetteCalib) -> Double {
            var f1 = focal - minF, f2 = r.focal - minF
            if span != 0 { f1 /= span; f2 /= span }
            let a1 = aperture > 0 ? 4.0 / aperture : 0
            let a2 = 4.0 / r.aperture
            // Unknown distance: compare against the row's own distance
            // (nearest-distance rows win — the missing-axis fallback).
            let d1 = dist.map { 0.1 / $0 } ?? 0.1 / r.distance
            let d2 = 0.1 / r.distance
            let df = f2 - f1, da = a2 - a1, dd = d2 - d1
            return (df * df + da * da + dd * dd).squareRoot()
        }
        // Exact hit.
        if let exact = rows.first(where: { gridDist($0) < 1e-4 }) { return exact }
        let power = 3.5
        var num = (k1: 0.0, k2: 0.0, k3: 0.0)
        var denom = 0.0
        var smallest = Double.infinity
        for r in rows {
            let d = gridDist(r)
            smallest = min(smallest, d)
            let wgt = abs(1.0 / pow(d, power))
            num.k1 += wgt * r.k1; num.k2 += wgt * r.k2; num.k3 += wgt * r.k3
            denom += wgt
        }
        guard smallest <= 1, denom > 0, smallest.isFinite else { return nil }
        return VignetteCalib(
            focal: focal, aperture: aperture, distance: dist ?? 0,
            k1: num.k1 / denom, k2: num.k2 / denom, k3: num.k3 / denom)
    }
}

/// The app-wide Lensfun library (D6 — loaded once, read concurrently).
/// `shared` is nil when no database is on disk (the (c)-absent downgrade).
/// A plain struct behind an NSLock (not an actor — the module's
/// `resolveUniforms` runs on the caller's executor and only needs a
/// synchronous snapshot lookup; actor isolation would force async hops
/// through the pipe's Sendable boundary).
public struct LensfunStore: Sendable {
    /// The installed snapshot (nil = absent → downgrade to manual).
    private static let lock: NSLock = NSLock()
    private static nonisolated(unsafe) var _db: LensfunDB?
    // ── The match memo (LENS-01 T4, hazard H-L1 first stage) ──
    // process used to re-run the full-library linear scan EVERY render
    // (LensModule.resolveUniforms → resolveCommitted → matchHardened over
    // ~thousands of entries × string scoring per slider tick). The memo
    // caches the MATCH RESULT (entry identity + score + failure state) —
    // NOT the resolved coefficients: the resolve polynomial evaluation is
    // cheap and size-free (review M4), while the memo key deliberately
    // carries NO width/height (the result is size-independent by
    // construction; the center-resolution coupling dies with the
    // result-level memo). Invalidated wholesale on install/uninstall.
    private static nonisolated(unsafe) var _memo: [UInt64: MemoOutcome] = [:]
    private static nonisolated(unsafe) var _memoOrder: [UInt64] = []
    /// The DB instance identity — bumped on every install/uninstall so a
    /// DB swap can never serve entries from the previous library.
    private static nonisolated(unsafe) var _dbStamp: UInt64 = 0
    private static nonisolated(unsafe) var _dbTag: String?
    /// LRU capacity (the LutLibraryStore precedent).
    static let memoCapacity = 32

    /// The memoized outcome face (entry identity = the lens INDEX in the
    /// installed db — valid within one stamp).
    private enum MemoOutcome {
        case matched(index: Int, score: Int)
        case ambiguous(score: Int)
        case noLens
        case missingFocal
    }

    /// The ACTIVE database's dbTag (LENS-04 T1, X3): the sorted per-file
    /// (name, SHA-256) manifest's SHA-256, first 16 hex — the snapshot
    /// AUDIT face (never a render face, never folded into paramsHash).
    /// Computed at install; nil = the test-injected face (install(db:)).
    public static var currentDBTag: String? {
        lock.lock(); defer { lock.unlock() }
        return _dbTag
    }

    /// Install the store from a directory (app launch / settings change).
    /// Returns false when the directory holds no parseable XML.
    @discardableResult
    public static func install(directory: URL) -> Bool {
        let db = LensfunDBLoader.load(directory: directory)
        guard !db.lenses.isEmpty else { return false }
        let tag = Self.computeDBTag(directory: directory)
        lock.lock(); _db = db; _dbStamp &+= 1; _memo = [:]; _memoOrder = []
        _dbTag = tag
        lock.unlock()
        return true
    }

    /// The manifest-hash dbTag (sorted per-file name:SHA-256 lines).
    private static func computeDBTag(directory: URL) -> String? {
        let fm = FileManager.default
        guard let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter({ $0.pathExtension == "xml" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
            !files.isEmpty
        else { return nil }
        var manifest = ""
        for file in files {
            guard let data = try? Data(contentsOf: file) else {
            manifest += file.lastPathComponent + ":unreadable\n"
                continue
            }
        manifest += file.lastPathComponent + ":" + sha256Hex(data) + "\n"
        }
        return String(sha256Hex(Data(manifest.utf8)).prefix(16))
    }

    /// The test-injected dbTag (install(db:) companions).
    static func installForTesting(db: LensfunDB, dbTag: String?) {
        install(db: db)
        lock.lock(); _dbTag = dbTag; lock.unlock()
    }

    /// Install directly from a parsed DB (tests + previews).
    static func install(db: LensfunDB) {
        lock.lock(); _db = db; _dbStamp &+= 1; _memo = [:]; _memoOrder = []; lock.unlock()
    }

    /// Remove the store (data deleted / path unset).
    public static func uninstall() {
        lock.lock(); _db = nil; _dbStamp &+= 1; _memo = [:]; _memoOrder = []
        _dbTag = nil
        lock.unlock()
    }

    /// Snapshot predicate for the downgrade path (sync — no async hop).
    public static var isInstalled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _db != nil
    }

    // MARK: - The memo (matching-input-keyed, size-independent)

    /// The memo key: FNV-1a over the MATCHING INPUT face (maker/model/
    /// lensKey/imageCrop/focal — the fields matchHardened reads). Deliberate
    /// exclusions: aperture/distance only feed the resolve, never the
    /// match; width/height never (the result is size-independent).
    private static func memoKey(_ params: LensModule.Params) -> UInt64 {
        var h = StableHash.hash("lightamer.lensfun.memo.v1")
        for s in [params.cameraMaker, params.cameraModel, params.lensKey] {
            h = Data((s ?? "").utf8).withUnsafeBytes { StableHash.combine(h, $0) }
        }
        for v in [params.imageCrop ?? -1, Double(params.focalLength ?? -1)] {
            var bits = v.bitPattern
            h = withUnsafeBytes(of: &bits) { StableHash.combine(h, $0) }
        }
        return h
    }

    /// The store-path match face: memo-hit → the cached outcome; miss →
    /// the full-library scan (matchHardened bumps the scan counter) →
    /// memo store. The scoring runs OUTSIDE the lock (the NSLock discipline:
    /// no heavy work under the lock — only table reads/writes).
    public static func matchOutcome(_ params: LensModule.Params) -> LensMatchOutcome? {
        lock.lock()
        let db = _db
        let stamp = _dbStamp
        lock.unlock()
        guard let db else { return nil }
        let key = memoKey(params)
        // Hit probe (lock inside; LRU touch).
        if let cached = memoRead(key, stamp: stamp) {
            return materialize(cached, db: db)
        }
        let outcome = matchCommitted(params, in: db)
        let memoValue: MemoOutcome
        switch outcome {
        case .matched(let profile, let score):
            memoValue = .matched(index: profile.entryIndex, score: score)
        case .ambiguous(let score): memoValue = .ambiguous(score: score)
        case .noLens: memoValue = .noLens
        case .missingFocal: memoValue = .missingFocal
        }
        memoWrite(key, memoValue, stamp: stamp)
        return outcome
    }

    private static func memoRead(_ key: UInt64, stamp: UInt64) -> MemoOutcome? {
        lock.lock(); defer { lock.unlock() }
        guard stamp == _dbStamp, let value = _memo[key] else { return nil }
        _memoOrder.removeAll { $0 == key }
        _memoOrder.append(key)
        return value
    }

    private static func memoWrite(_ key: UInt64, _ value: MemoOutcome, stamp: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard stamp == _dbStamp else { return }
        _memo[key] = value
        _memoOrder.removeAll { $0 == key }
        _memoOrder.append(key)
        while _memoOrder.count > memoCapacity {
            let evicted = _memoOrder.removeFirst()
            _memo[evicted] = nil
        }
    }

    private static func materialize(_ memo: MemoOutcome, db: LensfunDB) -> LensMatchOutcome {
        switch memo {
        case .matched(let index, let score):
            guard db.lenses.indices.contains(index) else { return .noLens }
            let entry = db.lenses[index]
            return .matched(
                LensMatchedProfile(
                    maker: entry.maker, model: entry.models.first ?? "",
                    cropFactor: entry.cropfactor, entryIndex: index,
                    projectionHint: entry.type?.lowercased()),
                score: score)
        case .ambiguous(let score): return .ambiguous(score: score)
        case .noLens: return .noLens
        case .missingFocal: return .missingFocal
        }
    }

    /// The RE-MATCH face (LENS-04 T1): drop the snapshot, re-run the
    /// match against the CURRENT database, and stamp the fresh snapshot —
    /// ONE params copy for the caller's single commit; nil = the miss
    /// (snapshot cleared, the live memo path renders).
    public static func rematch(_ params: LensModule.Params) -> LensModule.Params? {
        var cleared = params
        cleared.snapshot = nil
        return bakeCommitted(cleared)
    }

    /// The snapshot-clear face (the miss arm).
    public static func clearSnapshot(_ params: LensModule.Params) -> LensModule.Params {
        var cleared = params
        cleared.snapshot = nil
        return cleared
    }

    /// The BAKE face (LENS-04 T1, D-LENS-3): resolve the committed
    /// params and stamp the snapshot into a COPY of them (the caller
    /// commits it — the bake lives at the match-commit sites, never in
    /// the render path). nil = the match/resolve miss (the caller keeps
    /// the snapshot-free params; the live memo path still renders).
    public static func bakeCommitted(_ params: LensModule.Params) -> LensModule.Params? {
        guard case .matched(let profile, let score) = matchOutcome(params) else { return nil }
        lock.lock(); let db = _db; lock.unlock()
        guard let db, db.lenses.indices.contains(profile.entryIndex) else { return nil }
        let entry = db.lenses[profile.entryIndex]
        var snap = LensCoefficientSnapshot()
        snap.distortionRows = entry.calibrations.distortions
        snap.tcaRows = entry.calibrations.tcas
        snap.vignetteRows = entry.calibrations.vignettes
        snap.realFocalRows = entry.calibrations.realFocals
        snap.aspectRatio = entry.aspectRatio
        snap.entryCrop = entry.cropfactor
        snap.center = entry.center.map { LensEntry.CenterPoint(x: $0.x, y: $0.y) }
        snap.lensType = entry.type
        snap.profileMaker = profile.maker
        snap.profileModel = profile.model
        snap.profileCrop = Float(profile.cropFactor)
        snap.matchScore = score
        lock.lock(); let tag = _dbTag; lock.unlock()
        snap.dbTag = tag
        var out = params
        out.snapshot = snap
        out.sourceProjection = entry.type?.lowercased()
        return out
    }

    /// The whole-library scored rows for the profile browser (LENS-02 T4):
    /// every lens entry's best model score against the search term (rows
    /// with score > 0 only, UNSORTED — the App-side model owns the
    /// ordering/confidence annotation). nil = no database installed.
    public static func candidateRows(search: String) -> [LensCandidateRow]? {
        lock.lock(); let db = _db; lock.unlock()
        guard let db else { return nil }
        var rows: [LensCandidateRow] = []
        for entry in db.lenses {
            var score = 0
            for m in entry.models {
                score = max(score, LensfunMatch.modelScore(exif: search, candidate: m, maker: entry.maker))
            }
            if score > 0 {
                rows.append(LensCandidateRow(
                    maker: entry.maker, model: entry.models.first ?? "", score: score))
            }
        }
        return rows
    }

    /// Camera cropfactor lookup (LENS-01 T3, X4 priority tier 2): unique
    /// camera hit only (RawLab `FindCameras`); nil = absent/ambiguous/absent
    /// DB — the caller falls through the priority chain.
    public static func cameraCrop(maker: String?, model: String?) -> Double? {
        lock.lock(); let db = _db; lock.unlock()
        guard let db else { return nil }
        return LensfunMatch.uniqueCameraCrop(maker: maker, model: model, in: db)
    }

    /// The hardened match face for the committed params (LENS-01 T3): the
    /// full-parameter auto channel with the ≥60 tier and the ambiguity
    /// refusal. The panel readout consumes the outcome; the resolve face
    /// consumes only the matched entry.
    static func matchCommitted(
        _ params: LensModule.Params, in db: LensfunDB
    ) -> LensMatchOutcome {
        let focal = Double(params.focalLength ?? 0)
        guard focal > 0 else { return .missingFocal }
        let key = params.lensKey ?? ""
        return LensfunMatch.matchHardened(
            maker: params.cameraMaker, model: params.cameraModel,
            lens: key.isEmpty ? nil : key,
            imageCrop: params.imageCrop ?? 1.0, in: db)
    }

    /// Resolve committed params → kernel params (D6, sync snapshot read;
    /// LENS-01 T3 hardening: the FULL parameter path — maker/model/
    /// imageCrop read from the params (nil = the 1.0 status-quo fallback
    /// ONLY after the earlier priority tiers came up empty), the ≥60
    /// threshold tier, the ambiguity refusal, and the resolve crop
    /// argument is the CAMERA imageCrop (review m5: the pre-T3 code passed
    /// `entry.cropfactor` — the LENS calibration crop — where resolve's
    /// contract self-documents the camera cropfactor; the wrong crop
    /// mis-scaled the NS·HW fold).
    public static func resolveCommitted(
        _ params: LensModule.Params, width: Int, height: Int
    ) -> LensKernelParams? {
        guard case .matched(let profile, _) = matchOutcome(params) else { return nil }
        // LENS-03 T1: no target projection set + a non-rectilinear entry =
        // the conservative refusal (the pre-L3 face, blit identity).
        if params.targetProjection == nil,
           let t = profile.sourceProjectionRaw ?? profile.modelProjectionHint,
           t != "rectilinear", t != "" {
            return nil
        }
        // The profile's INTERNAL index is valid within this stamp (the
        // outcome was produced against the same captured db).
        lock.lock(); let currentDB = _db; lock.unlock()
        guard let currentDB, currentDB.lenses.indices.contains(profile.entryIndex) else { return nil }
        let entry = currentDB.lenses[profile.entryIndex]
        let focal = Double(params.focalLength ?? 0)
        let cameraCrop = params.imageCrop ?? 1.0
        return LensfunMatch.resolve(
            entry: entry, focal: focal,
            aperture: params.aperture.map(Double.init),
            distance: nil, crop: cameraCrop,
            imageWidth: width, imageHeight: height,
            targetProjection: params.targetProjection)
    }

    /// BROWSER-ORDERING ONLY (D-LENS-4, LENS-01 T3): the 40-tier second
    /// chance survives ONLY as the profile browser's low-confidence
    /// ordering hint (LENS-02 T4) — it has LOST its auto-selection
    /// qualification (no production caller; the resolveCommitted path now
    /// goes through `matchHardened`, which floors the auto channel at 60).
    private static func fallbackEntry(key: String, db: LensfunDB) -> LensEntry? {
        guard !key.isEmpty else { return nil }
        var best: (entry: LensEntry, score: Int)?
        for entry in db.lenses {
            var score = 0
            for m in entry.models {
                score = max(score, LensfunMatch.modelScore(
                    exif: key, candidate: m, maker: entry.maker))
            }
            if score > (best?.score ?? 0) { best = (entry, score) }
        }
        guard let best, best.score >= 40 else { return nil }
        return best.entry
    }
}


import CryptoKit

/// The SHA-256 hex face (IOP-local — the App Session domain's SHA256Hex
/// is unreachable from here; both wrap CryptoKit.SHA256).
func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
