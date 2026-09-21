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
    /// XML carries no `<center>`).
    func uniforms(bufW: Int, bufH: Int, roiIn: ROI, roiOut: ROI) -> LensWarpUniforms {
        LensWarpUniforms(
            dc1: dc1, dc2: dc2, dc3: dc3, dc4: dc4,
            vr: vr, cr: cr, br: br, vb: vb, cb: cb, bb: bb,
            vk1: vk1, vk2: vk2, vk3: vk3,
            centerX: centerX == 0 && centerY == 0 ? Float(bufW) / 2 : centerX,
            centerY: centerY == 0 && centerX == 0 ? Float(bufH) / 2 : centerY,
            halfW: Float(bufW) / 2,
            oroiX: Float(roiOut.x), oroiY: Float(roiOut.y),
            iroiX: Int32(roiIn.x), iroiY: Int32(roiIn.y),
            inW: Int32(bufW), inH: Int32(bufH))
    }
}

enum LensfunMatch {

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
        imageWidth: Int, imageHeight: Int
    ) -> LensKernelParams? {
        // Non-rectilinear projections do not fit this kernel (D3 scope).
        if let t = entry.type?.lowercased(),
           t != "rectilinear" && t != "" { return nil }
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
    /// Install the store from a directory (app launch / settings change).
    /// Returns false when the directory holds no parseable XML.
    @discardableResult
    public static func install(directory: URL) -> Bool {
        let db = LensfunDBLoader.load(directory: directory)
        guard !db.lenses.isEmpty else { return false }
        lock.lock(); _db = db; lock.unlock()
        return true
    }

    /// Install directly from a parsed DB (tests + previews).
    static func install(db: LensfunDB) {
        lock.lock(); _db = db; lock.unlock()
    }

    /// Remove the store (data deleted / path unset).
    public static func uninstall() { lock.lock(); _db = nil; lock.unlock() }

    /// Snapshot predicate for the downgrade path (sync — no async hop).
    public static var isInstalled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _db != nil
    }

    /// Resolve committed params → kernel params (D6, sync snapshot read).
    public static func resolveCommitted(
        _ params: LensModule.Params, width: Int, height: Int
    ) -> LensKernelParams? {
        lock.lock(); let db = _db; lock.unlock()
        guard let db else { return nil }
        let focal = Double(params.focalLength ?? 0)
        guard focal > 0 else { return nil }
        let key = params.lensKey ?? ""
        let entry = LensfunMatch.match(
            maker: nil, model: nil, lens: key.isEmpty ? nil : key,
            imageCrop: 1.0, in: db)
            ?? fallbackEntry(key: key, db: db)
        guard let entry else { return nil }
        let crop = entry.cropfactor > 0 ? entry.cropfactor : 1.0
        return LensfunMatch.resolve(
            entry: entry, focal: focal,
            aperture: params.aperture.map(Double.init),
            distance: nil, crop: crop,
            imageWidth: width, imageHeight: height)
    }

    /// Second-chance match on the raw lens key (the match() lens-axis
    /// miss ledger path).
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
