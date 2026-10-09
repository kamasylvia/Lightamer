import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ProfileLatitudeDescriptor (Plan M3-4-01 T2, KD-2) — the MEASURED medium
// face (RFC-023 §8.3: "a measurement, never a render parameter"). Produced
// ONLY by FilmDescriptorProbe (the neutral ramp through the REAL film
// sub-run — §8.1: no parallel second implementation of the chain); consumed
// by the latitude panel's read faces and the placement resolver's C anchors.
// The render parameters (knees) never derive implicitly from this — the App
// resolver solves at commit time and the RESOLVED values ride the params.
//
// The ISO 6846 reduction (the E1-corrected criteria, checker 2026-10-09):
// the useful boundaries are where the OUTPUT reaches a fixed distance from
// its own black and white —
//   useful_highlight_ev = the first E with Y ≥ Y_black + 0.9·(Y_white−Y_black)
//   useful_shadow_ev    = the LAST E (ascending) with D ≥ 0.9·D_black,
//                         D = −log10(Y/Y_white)  (D_black = the black
//                         plateau's density = max D)
// (§8.2's literal "Dmin + 0.04" shadow sentence degenerates to a constant
// predicate — D ≤ D_black holds for every E; the measured §15.2
// implementation form, `0.90·Dmax` at the shadow end, is the criterion this
// reduce pins; upstream cross-check window [−3.18, +2.49] = 5.66 stops.)
//
// CACHE: keyed by fnv(materialPairHash ⊕ probe config tag) — the profile
// bytes ride the pair hash (the 01 single source), the probe tag folds so a
// config change re-keys. NSLock + insertion-order LRU 4 (the FilmSolveCache
// shape; a SEPARATE cache — descriptor and solve are different value
// domains and never share keys).
// ─────────────────────────────────────────────────────────────────────────────

/// The measured medium descriptor (RFC-023 §8.3 field face). `response` is
/// the probe's T(E) luma on the uniform [evMin, evMax] grid; `slope` its
/// per-EV derivative (the diagnostic face — the Fit's raw material).
public struct ProfileLatitudeDescriptor: Sendable, Equatable {

    /// The probe domain (stops relative to mid-gray).
    public let evMin: Double
    public let evMax: Double
    /// The ISO 6846 useful boundaries (the Fit's C anchors).
    public let usefulShadowEV: Double
    public let usefulHighlightEV: Double
    /// The mid-anchor reading: the E whose output first reaches the paper
    /// mid density's linear value (≈ 0 by the K calibration — the sanity
    /// band |reference_ev| ≤ 0.5 is a test gate).
    public let referenceEV: Double
    /// T(E) luma (Rec2020) on the uniform grid (diagnostic + Fit input).
    public let response: [Float]
    /// dT/dE per grid point (central differences; the diagnostic face).
    public let slope: [Float]
    /// `FilmMaterialStore.materialPairHash` — the descriptor's identity.
    public let materialPairHash: UInt64

    public init(
        evMin: Double, evMax: Double,
        usefulShadowEV: Double, usefulHighlightEV: Double, referenceEV: Double,
        response: [Float], slope: [Float], materialPairHash: UInt64
    ) {
        self.evMin = evMin
        self.evMax = evMax
        self.usefulShadowEV = usefulShadowEV
        self.usefulHighlightEV = usefulHighlightEV
        self.referenceEV = referenceEV
        self.response = response
        self.slope = slope
        self.materialPairHash = materialPairHash
    }
}

/// The ISO 6846 reduction — pure functions over a measured response column
/// (LAYERS-testable against hand-computed fold lines; the probe supplies
/// the real chain's response, never a reimplementation).
public enum FilmLatitudeReduce {

    /// The density clamp floor: D = −log10(max(Y, ε·Y_white)/Y_white) caps
    /// D at −log10(ε) (a true zero output cannot poison the boundary walk).
    static let densityEpsilon: Double = 1e-6

    /// The grid EV for a response index (uniform grid convention — the
    /// probe's single source).
    public static func ev(_ index: Int, count: Int, evMin: Double, evMax: Double) -> Double {
        guard count > 1 else { return evMin }
        return evMin + (evMax - evMin) * Double(index) / Double(count - 1)
    }

    /// The interpolated E where the response first reaches `level` (nil =
    /// never reached — the panel shows "未到/不可用", never a fake value).
    public static func firstCrossingEV(
        _ response: [Double], evMin: Double, evMax: Double, level: Double
    ) -> Double? {
        guard response.count > 1 else { return nil }
        var previous = response[0]
        if previous >= level { return evMin }
        for index in 1..<response.count {
            let current = response[index]
            if current >= level {
                // Linear interpolation inside the grid cell (monotone
                // response assumed — the probe asserts it).
                let span = current - previous
                let fraction = span > 0 ? (level - previous) / span : 0
                let e0 = ev(index - 1, count: response.count, evMin: evMin, evMax: evMax)
                let e1 = ev(index, count: response.count, evMin: evMin, evMax: evMax)
                return e0 + (e1 - e0) * fraction
            }
            previous = current
        }
        return nil
    }

    /// The useful-highlight boundary (ISO: 90% of the way from Y_black to
    /// Y_white). Flat responses (Y_white ≤ Y_black) answer nil — a
    /// degenerate probe is "descriptor unavailable", never a fake number.
    public static func usefulHighlightEV(
        _ response: [Double], evMin: Double, evMax: Double
    ) -> Double? {
        guard let yWhite = response.max(), let yBlack = response.min(),
            yWhite > yBlack
        else { return nil }
        let level = yBlack + 0.9 * (yWhite - yBlack)
        return firstCrossingEV(response, evMin: evMin, evMax: evMax, level: level)
    }

    /// The useful-shadow boundary (the measured implementation form): the
    /// LAST E (ascending) with D ≥ 0.9·D_black, D = −log10(clamp(Y/Y_white)).
    /// Equivalent, for a non-decreasing response, to the first E with
    /// Y ≥ Y_white·10^(−0.9·D_black) (both faces pinned by the hand vector).
    public static func usefulShadowEV(
        _ response: [Double], evMin: Double, evMax: Double
    ) -> Double? {
        guard let yWhite = response.max(), let yBlack = response.min(),
            yWhite > yBlack
        else { return nil }
        let densityCap = -Foundation.log10(densityEpsilon)
        func density(_ y: Double) -> Double {
            min(-Foundation.log10(max(y, yWhite * densityEpsilon) / yWhite), densityCap)
        }
        let dBlack = density(yBlack)
        let threshold = 0.9 * dBlack
        var last: Int?
        for index in 0..<response.count where density(response[index]) >= threshold {
            last = index
        }
        guard let last else { return nil }
        return ev(last, count: response.count, evMin: evMin, evMax: evMax)
    }

    /// The diagnostic slope array: dT/dE per grid point (central
    /// differences, one-sided at the ends), EV units.
    public static func slopes(
        _ response: [Double], evMin: Double, evMax: Double
    ) -> [Float] {
        let count = response.count
        guard count > 1 else { return [] }
        let dE = (evMax - evMin) / Double(count - 1)
        guard dE > 0 else { return [Float](repeating: 0, count: count) }
        var out = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let previous = response[max(index - 1, 0)]
            let next = response[min(index + 1, count - 1)]
            out[index] = Float((next - previous) / (Double(min(index + 1, count - 1) - max(index - 1, 0)) * dE))
        }
        return out
    }
}

/// The descriptor cache (KD-2): key = fnv(materialPairHash ⊕ probe config
/// tag) — a probe-config change re-keys. NSLock + insertion-order LRU 4
/// (the FilmSolveCache shape; a separate cache — different value domain).
public final class FilmDescriptorCache: @unchecked Sendable {

    /// The process-wide cache (one per session — a descriptor is a pure
    /// function of its key's terms, so sharing is value-invisible).
    public static let shared = FilmDescriptorCache()

    private let lock = NSLock()
    private var descriptors: [UInt64: ProfileLatitudeDescriptor] = [:]
    private var order: [UInt64] = []
    private let capacity: Int

    public init(capacity: Int = 4) {
        self.capacity = capacity
    }

    /// The cache key: fnv(pairHash bytes ⊕ probe tag UTF-8) — the same
    /// canonical FNV-1a thread the film solve cache keys use (L013).
    public static func cacheKey(materialPairHash: UInt64) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: materialPairHash) { h = StableHash.combine(h, $0) }
        let tag = Array(FilmDescriptorProbe.probeTag.utf8)
        h = tag.withUnsafeBufferPointer {
            StableHash.combine(h, UnsafeRawBufferPointer($0))
        }
        return h
    }

    public func descriptor(for key: UInt64) -> ProfileLatitudeDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        guard let hit = descriptors[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    public func store(_ descriptor: ProfileLatitudeDescriptor, for key: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        descriptors[key] = descriptor
        order.append(key)
        while order.count > capacity {
            descriptors.removeValue(forKey: order.removeFirst())
        }
    }

    /// The session-level recompute face (the pair-change event's entry).
    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        descriptors.removeAll()
        order.removeAll()
    }

    public var countForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return descriptors.count
    }
}
