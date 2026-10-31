import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SpectralGrainSublayer (Plan M8-3+ T4) — the single-sublayer table
// derivation (the upstream `_sf_build_grain_layers` nl==1 arm's port —
// dt spektrafilm `4d1fb6a95b:src/common/spektra_sim.c:2569-2592`,
// GPL-3.0, (C) darktable developers; the multi-sublayer arm stays
// parked — our 28 profiles carry no per-stock curve-model layer fits,
// so nl==1 is the data-honest face, not an approximation).
//
// Per channel c, from the film profile's RAW stock curves + the
// published diffuse RMS granularity (the M9-2 T4 calibration face —
// nil RMS = typed degrade, no invented interpolation):
//
//   curve  = the stock's normalized develop curve (minus the floor —
//            the engine's curvesNorm twin, Float64 here)
//   dmin   = the curve floor (density_min)
//   dmax   = max(curve) + dmin
//   npart  = pix_ref / max(a_grain, 1e-4), with
//            a_grain = sig² · A48 / max(d_ref·(dmax − u·d_ref), 1e-6)
//            d_ref   = 1.0 + dmin, sig = rms/1000,
//            A48     = π·24² (the 48 µm aperture),
//            pix_ref = SF_GRAIN_REF_UM² (upstream's fixed reference scale;
//            the LIVE pixel_um rescale rides the dispatch's npart_scale,
//            never this table).
//
// The uniformity arm rides u == 1.0 (the neutral face — our profiles
// carry no per-stock uniformity figure; the pack default).
// ─────────────────────────────────────────────────────────────────────────────

public enum SpectralGrainSublayer {

    /// Upstream's fixed reference scale (µm — `SF_GRAIN_REF_UM`).
    public static let referenceUm = 47.0
    /// The 48 µm microdensitometer aperture area (π·24²).
    public static let aperture48Area = Double.pi * 24.0 * 24.0

    /// One channel's derived sublayer row.
    public struct ChannelRow: Sendable, Equatable {
        public let dmax: Double
        public let npart: Double
        public let dmin: Double
        /// The normalized curve (minus the floor — 256 points).
        public let curve: [Double]
    }

    /// The derivation errors (typed degrade — fail-closed).
    public enum DeriveError: Error, Equatable, Sendable {
        /// No published RMS figure for this stock (no invented data).
        case noPublishedRms(String)
        /// The stock curves are empty (the profile face degraded).
        case emptyCurves(String)
    }

    /// Derive the single-sublayer table for one film profile.
    ///
    /// - Parameters:
    ///   - film: the film profile (RAW stock curves).
    ///   - publishedRms: the per-channel published diffuse RMS (the
    ///     1000× scale — 17 ≡ RMS 0.017 @ 48 µm; nil channel = typed
    ///     degrade for that channel's npart only if ALL nil throws).
    ///   - uniformity: the per-channel uniformity (default ones — the
    ///     neutral face; the pack default).
    public static func derive(
        film: FilmProfile, publishedRms: [Int?],
        uniformity: [Double] = [1.0, 1.0, 1.0]
    ) throws -> [ChannelRow] {
        let stock = film.info.stock ?? "?"
        guard !film.densityCurves.isEmpty else {
            throw DeriveError.emptyCurves(stock)
        }
        guard publishedRms.contains(where: { $0 != nil }) else {
            throw DeriveError.noPublishedRms(stock)
        }
        let pixRef = referenceUm * referenceUm
        return try (0..<3).map { c in
            var floor = Double.infinity
            var ceil = -Double.infinity
            for row in film.densityCurves {
                let v = Double(row[c])
                floor = min(floor, v)
                ceil = max(ceil, v)
            }
            let curve = film.densityCurves.map { Double($0[c]) - floor }
            let dmax = ceil
            let dRef = 1.0 + floor
            // A nil RMS channel degrades that channel's npart to the
            // NEUTRAL density (npart = pix_ref — the a_grain floor's own
            // face; the sampler still runs, the grain is fine).
            let sig: Double
            if let rms = publishedRms[c] {
                sig = Double(rms) / 1000.0
            } else {
                sig = 0.0
            }
            let u = c < uniformity.count ? uniformity[c] : 1.0
            let denom = max(dRef * (dmax - u * dRef), 1e-6)
            let aGrain = sig * sig * aperture48Area / denom
            let npart = pixRef / max(aGrain, 1e-4)
            return ChannelRow(
                dmax: dmax, npart: npart, dmin: floor, curve: curve)
        }
    }

    /// The per-film RMS broadcast (the M9-2 calibration face prints ONE
    /// achromatic figure — the three channels share it; nil = all-nil —
    /// the caller resolves the figure through GrainCalibration, Core
    /// never imports LightamerIOP (D-03: IOP → Core only)).
    public static func broadcastRms(_ rms: Int?) -> [Int?] {
        [rms, rms, rms]
    }
}

/// The legacy↔upstream amount bridge (M8-3+ T4): the legacy strength
/// ∈ [0, 100] ($DEFAULT 25) ↔ the upstream amount ∈ [0, 8] ($DEFAULT
/// 1.0). The bridge anchors the two DEFAULTS to each other (25 ↔ 1.0)
/// and scales linearly (amount = strength / 25 — the default-anchored
/// face; the calibration probe's own curve is the legacy-domain
/// figure, the B track inherits it through this bridge).
public enum SpectralGrainBridge {
    /// The default anchor (legacy 25 ≡ upstream 1.0).
    public static let legacyDefault = 25.0

    /// Legacy strength → upstream amount (linear through the anchor).
    public static func amount(legacyStrength: Double) -> Double {
        legacyStrength / legacyDefault
    }

    /// Upstream amount → legacy strength (the inverse face).
    public static func legacyStrength(amount: Double) -> Double {
        amount * legacyDefault
    }
}
