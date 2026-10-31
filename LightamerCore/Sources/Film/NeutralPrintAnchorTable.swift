import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// NeutralPrintAnchorTable (Plan M8-3+ T1) — the read-only typed consumer of
// the vendored `neutral_print_filters.json` (the upstream MEASURED neutral
// print-filter table, CC BY-SA byte-verbatim — read, never embedded).
//
// The table's premises (the REAL dichroic head + enlarger + light) do NOT
// carry over to our self-approximated dichroics — the build keeps solving
// its OWN neutral pair (the M8-1a self-solve pivot). The measured table
// only supplies the Newton ladder's SEED (research §1.4's first stage):
// an anchored seed converges to the SAME pair in fewer rounds
// (14 safety pairs pinned bit-identical — the extraction's no-drift
// proof), and C200's basin is seed-insensitive (research evidence C —
// the seed is free acceleration, not the C200 fix).
//
// Lookup key: (paper stock, illuminant, film stock) → (m, y) dials (the
// table's C column stays neutral-fixed at 0 by pack convention and is not
// consumed). Absent entries (unknown paper/illuminant/film) return nil —
// the engine falls back to the legacy (50, 50) seed (the K1 stop-hand
// discipline: a moved safety convergence = stop, never silent).
// ─────────────────────────────────────────────────────────────────────────────

public enum NeutralPrintAnchorTable {

    /// The typed load errors (fail-closed at parse).
    public enum LoadError: Error, Equatable, Sendable {
        case malformed(String)
    }

    /// The parsed table: paper → illuminant → film → (C, M, Y) dials.
    public struct Table: Sendable, Equatable {
        /// The raw nested rows (C rides verbatim; consumers take M/Y).
        public let rows: [String: [String: [String: SIMD3<Double>]]]

        /// The anchor seed for one (paper, illuminant, film) triple —
        /// nil = absent (the caller falls back to (50, 50)).
        public func seed(
            paper: String, illuminant: String, film: String
        ) -> (m: Double, y: Double)? {
            guard let row = rows[paper]?[illuminant]?[film] else { return nil }
            return (m: row.y, y: row.z)
        }

        /// The triplet count (the coverage face: 8 papers × TH-KG3 ×
        /// 20 films = 160).
        public var tripletCount: Int {
            rows.values.reduce(0) { acc, byIllum in
                acc + byIllum.values.reduce(0) { $0 + $1.count }
            }
        }
    }

    /// Parse the table bytes (throws typed on malformed JSON or a row
    /// whose triple is not exactly 3 finite dials).
    public static func parse(_ data: Data) throws -> Table {
        guard
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            throw LoadError.malformed("neutral_print_filters: not a JSON object")
        }
        var rows: [String: [String: [String: SIMD3<Double>]]] = [:]
        for (paper, byIllumAny) in object {
            guard let byIllum = byIllumAny as? [String: Any] else {
                throw LoadError.malformed(
                    "neutral_print_filters: \(paper) is not an object")
            }
            var illumRows: [String: [String: SIMD3<Double>]] = [:]
            for (illum, byFilmAny) in byIllum {
                guard let byFilm = byFilmAny as? [String: Any] else {
                    throw LoadError.malformed(
                        "neutral_print_filters: \(paper)/\(illum) not an object")
                }
                var filmRows: [String: SIMD3<Double>] = [:]
                for (film, tripleAny) in byFilm {
                    guard let triple = tripleAny as? [Double],
                        triple.count == 3,
                        triple.allSatisfy({ $0.isFinite })
                    else {
                        throw LoadError.malformed(
                            "neutral_print_filters: \(paper)/\(illum)/\(film) "
                                + "is not a 3-finite triple")
                    }
                    filmRows[film] = SIMD3<Double>(
                        triple[0], triple[1], triple[2])
                }
                illumRows[illum] = filmRows
            }
            rows[paper] = illumRows
        }
        return Table(rows: rows)
    }

    /// Load from a file URL (the production caller resolves the bundle
    /// path; tests walk the repo root — the FilmMaterialStore twin).
    public static func load(url: URL) throws -> Table {
        guard let data = try? Data(contentsOf: url) else {
            throw LoadError.malformed(
                "neutral_print_filters unreadable at \(url.path)")
        }
        return try parse(data)
    }

    /// The session memo (the PaperGradeTable.cacheBox precedent — the
    /// anchored seed is a pure function of the stock triple, so one
    /// parse per session is value-invisible). Keyed by the table path.
    private static let cacheBox = AnchorCacheBox()
    private final class AnchorCacheBox: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [String: Table] = [:]
        func table(url: URL, make: () throws -> Table) throws -> Table {
            lock.lock()
            if let hit = tables[url.path] {
                lock.unlock()
                return hit
            }
            lock.unlock()
            let made = try make()
            lock.lock()
            tables[url.path] = made
            lock.unlock()
            return made
        }
    }

    /// The cached load (one parse per path per session; a reload after
    /// the asset changes needs a relaunch — the asset is vendored).
    public static func cachedTable(url: URL) throws -> Table {
        try cacheBox.table(url: url) { try load(url: url) }
    }
}
