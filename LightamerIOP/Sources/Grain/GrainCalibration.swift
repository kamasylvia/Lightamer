import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// GrainCalibration (Plan M9-2 T4) — the per-film RECOMMENDED-strength layer.
//
// OQ-M9-8's station ruling: the grain OPERATOR stays frozen (GrainModule
// zero-diff — D-M8-4's spatial-family ledger stays closed); what ships is
// a thin CALIBRATION table mapping each BW stock's PUBLISHED diffuse RMS
// granularity (48 µm aperture, the T1 PDF-verified values) to a grain
// `strength` that reproduces the published graininess through OUR kernel
// at the default scale. The strength semantic is UNCHANGED — the table
// only fills the panel's readout row and the one-click apply (a plain
// params edit through the existing commit funnel).
//
// The recommended values were solved ONCE by the calibration probe (the
// LIGHTAMER_PERF_PROBE-gated test — a synthetic net-density-1.0 gray
// plane through the production kernel, a 48 µm-equivalent box-filter
// density scan, a sweep over the strength domain, and the inverse
// interpolation onto each published RMS); the curve and the band are
// registered in M9-2-DECISIONS.
// ─────────────────────────────────────────────────────────────────────────────

/// The calibration table face (pure functions over the JSON asset).
public enum GrainCalibration {

    /// One film's calibration row.
    public struct Entry: Sendable, Equatable {
        public let stockId: String
        /// The published diffuse RMS granularity (the 1000× scale, i.e.
        /// 17 ≡ RMS 0.017 density @ 48 µm). nil = the publisher prints
        /// no figure (HP5 — no recommendation; the readout hides).
        public let publishedRms: Int?
        /// The recommended grain strength (GrainModule.Params.strength
        /// domain [0,100]); solved by the calibration probe. nil = no
        /// recommendation.
        public let recommendedStrength: Double?
        /// The provenance note (SHEET/ASSUMED — surfaced for audits).
        public let note: String
    }

    private struct Document: Decodable {
        struct FilmRow: Decodable {
            let rms: Int?
            let recommended_strength: Double?
            let note: String?
        }
        let films: [String: FilmRow]
    }

    /// Parse the calibration table bytes (typed failure on malformed).
    public static func parse(_ data: Data) throws -> [String: Entry] {
        let doc = try JSONDecoder().decode(Document.self, from: data)
        var out: [String: Entry] = [:]
        for (id, row) in doc.films {
            out[id] = Entry(
                stockId: id,
                publishedRms: row.rms,
                recommendedStrength: row.rms == nil ? nil : row.recommended_strength,
                note: row.note ?? "")
        }
        return out
    }

    /// Load from a file URL.
    public static func load(url: URL) throws -> [String: Entry] {
        try parse(try Data(contentsOf: url))
    }

    /// The RECOMMENDED mapping (pure, table-driven; deterministic — the
    /// same table bytes answer the same entry for the same stock).
    /// Unknown stock → nil (the readout hides — D-M92-1's typed-degrade).
    public static func recommendedStrength(
        forStock stockId: String, in table: [String: Entry]
    ) -> Double? {
        table[stockId]?.recommendedStrength
    }

    /// The published RMS readout (nil = no published figure).
    public static func publishedRms(
        forStock stockId: String, in table: [String: Entry]
    ) -> Int? {
        table[stockId]?.publishedRms
    }

    /// The monotonicity premise the probe pinned: a HIGHER published RMS
    /// maps to a HIGHER-or-equal recommended strength (the kernel's
    /// strength axis is monotone in the output RMS — the calibration is
    /// an inverse of a monotone map, so it is itself monotone).
    public static func isMonotone(_ table: [String: Entry]) -> Bool {
        let pairs = table.values
            .compactMap { entry -> (Int, Double)? in
                guard let r = entry.publishedRms,
                    let s = entry.recommendedStrength else { return nil }
                return (r, s)
            }
            .sorted { $0.0 < $1.0 }
        for (a, b) in zip(pairs, pairs.dropFirst()) where b.1 < a.1 {
            return false
        }
        return true
    }
}
