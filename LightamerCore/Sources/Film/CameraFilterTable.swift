import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CameraFilterTable (Plan M9-2 T3) — the Wratten taking-filter face.
//
// Loads the self-digitized `camera_filters.json` (T1: 8 filters on the
// 380-780/5 nm grid, dual-source policy — the W2 vector curves as the
// asset base, the B-3 transcription as the cross-check). The filter's
// ENGINE seat is the build-time sensW multiply (X-M92-1) — this table
// only resolves names to transmissions and validates the typed face; the
// factor normalization math lives in SpectralBuildEngine (the green-
// channel full-roll factor, keeping the 18% gray anchored).
//
// The table is OPEN over the JSON's key set (the picker walks the file's
// keys); `isValid` still gates the RECORD face (an unknown name degrades
// typed at THIS layer, never inside the engine).
// ─────────────────────────────────────────────────────────────────────────────

public enum CameraFilterTable {

    /// The typed load errors (fail-closed at parse).
    public enum LoadError: Error, Equatable, Sendable {
        case malformed(String)
    }

    /// One taking filter: the name ("w25") + the transmission spectrum
    /// (0...1 per wavelength, the JSON's percent / 100) + the dual-source
    /// note the panel surfaces for w58.
    public struct Filter: Sendable, Equatable {
        public let name: String
        public let transmission: [Double]
        /// The dual-source divergence note (nil = the two sources agreed
        /// within policy) — surfaced as the panel's w58 caption.
        public let crossCheckNote: String?
    }

    /// The JSON document's shape (schemaVersion 1).
    private struct Document: Decodable {
        struct FilterEntry: Decodable {
            let name: String?
            let source: String?
            let wavelengths_nm: [Double]
            let transmittance_pct: [Double]
            let cross_check: CrossCheck?
            struct CrossCheck: Decodable {
                let second_source: String?
                let shared_points: Int?
                let divergent_points_over_2pp: Int?
            }
        }
        let filters: [String: FilterEntry]
    }

    /// Parse the table bytes (throws typed on malformed JSON or any
    /// filter whose arrays disagree in length).
    public static func parse(_ data: Data) throws -> [String: Filter] {
        let doc = try JSONDecoder().decode(Document.self, from: data)
        var out: [String: Filter] = [:]
        for (key, entry) in doc.filters {
            guard entry.wavelengths_nm.count == entry.transmittance_pct.count,
                !entry.wavelengths_nm.isEmpty else {
                throw LoadError.malformed(
                    "camera_filters: \(key) length mismatch")
            }
            var note: String? = nil
            if let cross = entry.cross_check,
                let divergent = cross.divergent_points_over_2pp, divergent > 0 {
                note = "\(cross.second_source ?? "?") diverges on "
                    + "\(divergent) points >2pp"
            }
            out[key] = Filter(
                name: entry.name ?? key,
                transmission: entry.transmittance_pct.map { max(0, min(1, $0 / 100.0)) },
                crossCheckNote: note)
        }
        return out
    }

    /// Load from a file URL (the App assembles the bundle path; tests
    /// walk the repo root — the FilmMaterialStore dual-directory twin).
    public static func load(url: URL) throws -> [String: Filter] {
        try parse(try Data(contentsOf: url))
    }

    /// The filter's transmission aligned onto the ENGINE axis (the asset
    /// already rides the 380-780/5 nm grid; a foreign axis resamples
    /// linearly, clamped at the ends).
    public static func alignedTransmission(
        _ filter: Filter, wavelengths: [Double], tableWavelengths: [Double]
    ) -> [Double] {
        guard !tableWavelengths.isEmpty else {
            return [Double](repeating: 1, count: wavelengths.count)
        }
        return wavelengths.map { wl in
            if wl <= tableWavelengths.first! {
                return filter.transmission.first ?? 1
            }
            if wl >= tableWavelengths.last! {
                return filter.transmission.last ?? 1
            }
            var lo = 0, hi = tableWavelengths.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if tableWavelengths[mid] <= wl { lo = mid } else { hi = mid }
            }
            let x0 = tableWavelengths[lo], x1 = tableWavelengths[hi]
            let t = (wl - x0) / max(x1 - x0, 1e-12)
            let v0 = filter.transmission[lo], v1 = filter.transmission[hi]
            return v0 + (v1 - v0) * t
        }
    }

    /// The typed gate for the record face (nil/"" and unknown names are
    /// NOT valid filter tags — the record's degradation happens earlier,
    /// at the coordinator's degrade-to-nil).
    public static func isValid(name: String, in filters: [String: Filter]) -> Bool {
        filters[name] != nil
    }
}
