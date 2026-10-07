import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExifSearchParser (Plan M2-2-3 T1, KD-1) — the ONE free-text → structured
// search plan face for the library domain's EXIF lexical retrieval.
//
// A user search box mixes three vocabularies in ONE string:
//   "sony iso800 f/2.8 2024-06"
//     └ fts   └ iso eq   └ aperture   └ month range
// The parser decomposes it into a typed THREE-SEGMENT plan that the query
// face (LibraryQueries, KD-2) translates ONCE:
//   • ftsTerms    — plain words for the images_fts MATCH leg (each term is
//     folded at QUERY time through ExifFold.matchQueryToken — the SAME
//     vocabulary both faces share; a trailing `*` passes through for FTS5
//     phrase-prefix matching).
//   • structured  — iso/focal/aperture eq·range terms over the MATERIALIZED
//     columns. Aperture equality is spelled as a ±0.05 tolerance RANGE by
//     KD ruling: the REAL f-number column is a rounded float — direct `=`
//     loses (2.8 vs 2.79999…); the tolerance band is the honest equality.
//   • dateRange   — the multi-spelling date family → one capture_date
//     between. EXIF DateTimeOriginal carries whole SECONDS, so the range
//     closes at `next-period start − 1s` — exact for the stored data.
//
// AND SEMANTICS: every token is one more ANDed predicate — segments combine
// among themselves and with each other (`sony` AND iso==800 AND f≈2.8 AND
// June-2024). There is NO OR between tokens in v1 (the plan's matrix).
//
// ERROR FACE: a token that LOOKS like a structured query but does not fully
// parse (`isoabc`, `iso:abc`) is a TYPED error (the M2-3 dialog renders it)
// — never a silent degradation that would match nothing. Plain words always
// degrade to FTS terms.
//
// PURE FUNCTION — zero IO, zero clock (dates derive from Calendar UTC
// components). Fully table-driven testable (ExifSearchParserTests).
// ─────────────────────────────────────────────────────────────────────────────

/// The typed failure face (KD-1: unrecognized structured-looking tokens).
public enum ExifSearchParserError: Error, Equatable, Sendable {
    /// A token started like a structured query (`iso…`) but no grammar
    /// matched it — the dialog surfaces it verbatim.
    case unrecognizedToken(String)
    /// Two date tokens whose AND-intersection is empty (the plan carries
    /// ONE `dateRange`; a disjoint pair can never match a row).
    case disjointDateRanges
}

/// One structured materialized-column term (KD-1's second segment).
public struct StructuredTerm: Equatable, Sendable {
    public enum Field: String, Equatable, Sendable {
        case iso
        case focalLength
        case aperture
    }

    public enum Constraint: Equatable, Sendable {
        case equals(Double)
        case greaterThan(Double)
        case greaterThanOrEqual(Double)
        case lessThan(Double)
        case lessThanOrEqual(Double)
        case between(lower: Double, upper: Double)
    }

    public let field: Field
    public let constraint: Constraint

    public init(field: Field, constraint: Constraint) {
        self.field = field
        self.constraint = constraint
    }
}

/// The parse product (KD-1): three segments, translated once, consumed by
/// `LibraryQueries.searchPage`.
public struct ExifSearchPlan: Equatable, Sendable {
    /// Plain words for the FTS MATCH leg (lowercase-folded; a trailing `*`
    /// passes through as the FTS5 phrase-prefix marker).
    public var ftsTerms: [String]
    /// Materialized-column eq/range terms (ANDed).
    public var structured: [StructuredTerm]
    /// The date family's capture_date between (ANDed with everything).
    public var dateRange: ClosedRange<Date>?

    public init(
        ftsTerms: [String] = [], structured: [StructuredTerm] = [],
        dateRange: ClosedRange<Date>? = nil
    ) {
        self.ftsTerms = ftsTerms
        self.structured = structured
        self.dateRange = dateRange
    }

    /// The always-true plan (empty string input) — the query face omits
    /// every leg.
    public var isEmpty: Bool {
        ftsTerms.isEmpty && structured.isEmpty && dateRange == nil
    }
}

public enum ExifSearchParser {

    /// The aperture equality tolerance (KD ruling): REAL f-numbers round —
    /// `f2.8` matches `[2.75, 2.85]`.
    static let apertureTolerance = 0.05

    // MARK: - Entry

    /// Parse one search box string into the typed plan. Empty/whitespace
    /// input → the empty (always-true) plan.
    public static func parse(_ raw: String) throws -> ExifSearchPlan {
        var plan = ExifSearchPlan()
        let tokens = raw.split(
            whereSeparator: { $0.isWhitespace || $0.isNewline }
        ).map(String.init)
        guard !tokens.isEmpty else { return plan }

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lowered = token.lowercased()
            let next = index + 1 < tokens.count
                ? tokens[index + 1].lowercased() : nil

            // 1. ISO family (`iso800` / `iso 800` / `ISO-800` / ranges) —
            //    any `iso…` token that fails the grammar is a typed error.
            if lowered.hasPrefix("iso") {
                let consumed = try consumeISO(
                    lowered, next: next)
                apply(consumed.term, to: &plan.structured)
                index += consumed.tokens
                continue
            }
            // 2. Aperture family (`f/2.8` / `f2.8` / `f 2.8`).
            if let consumed = try consumeAperture(lowered, next: next) {
                plan.structured.append(consumed.term)
                index += consumed.tokens
                continue
            }
            // 3. Focal family (`35mm` / `35 mm`).
            if let consumed = consumeFocal(lowered, next: next) {
                plan.structured.append(consumed.term)
                index += consumed.tokens
                continue
            }
            // 4. Date family (`2024` / `2024-06` / `2024-06-01` /
            //    `2024/06/01` / `202406` / `20240601`).
            if let range = try consumeDate(lowered) {
                try merge(range, into: &plan.dateRange)
                index += 1
                continue
            }
            // 5. Plain word → the FTS leg (lowercase-folded; trailing `*`
            //    rides through for prefix matching).
            plan.ftsTerms.append(ExifFold.normalize(token))
            index += 1
        }
        return plan
    }

    // MARK: - ISO family

    /// `iso` + (`800` | `-800` | `>800` | `>=800` | `<800` | `<=800` |
    /// `:800-1600`), all optionally split across TWO tokens (`iso 800`).
    /// Any `iso…` token that parses nowhere throws (KD-1: `isoabc` errors).
    private static func consumeISO(
        _ lowered: String, next: String?
    ) throws -> (term: StructuredTerm, tokens: Int) {
        let prefix = String(lowered.dropFirst(3))  // after "iso"
        // Same-token forms.
        if let constraint = isoConstraint(from: prefix) {
            return (
                StructuredTerm(field: .iso, constraint: constraint), 1)
        }
        // Two-token forms: the bare head consumes the next token.
        if prefix.isEmpty, let next, let constraint = isoConstraint(from: next) {
            return (
                StructuredTerm(field: .iso, constraint: constraint), 2)
        }
        throw ExifSearchParserError.unrecognizedToken(lowered)
    }

    /// The constraint grammar for one ISO tail (`800`, `-800`, `>800`,
    /// `>=800`, `<800`, `<=800`, `:800-1600`).
    private static func isoConstraint(from tail: String) -> StructuredTerm.Constraint? {
        var rest = tail
        if rest.hasPrefix("-"), rest.dropFirst().allSatisfy(\.isNumber),
           let value = Double(rest.dropFirst()), value > 0 {
            return .equals(value)  // `iso-800` → the separator spelling
        }
        if rest.hasPrefix(":") {
            // `:800-1600` → between (the ONLY colon form).
            let range = String(rest.dropFirst())
            let parts = range.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let lower = Double(parts[0]), let upper = Double(parts[1]),
                  lower <= upper
            else { return nil }
            return .between(lower: lower, upper: upper)
        }
        if rest.hasPrefix(">="), let value = Double(rest.dropFirst(2)) {
            return .greaterThanOrEqual(value)
        }
        if rest.hasPrefix("<="), let value = Double(rest.dropFirst(2)) {
            return .lessThanOrEqual(value)
        }
        if rest.hasPrefix(">"), let value = Double(rest.dropFirst()) {
            return .greaterThan(value)
        }
        if rest.hasPrefix("<"), let value = Double(rest.dropFirst()) {
            return .lessThan(value)
        }
        if !rest.isEmpty, rest.allSatisfy(\.isNumber),
           let value = Double(rest) {
            return .equals(value)
        }
        return nil
    }

    // MARK: - Aperture family

    /// `f/2.8` / `f2.8` (one token) or `f` + `2.8` (two tokens) — the KD
    /// tolerance RANGE, never a direct REAL equality.
    private static func consumeAperture(
        _ lowered: String, next: String?
    ) throws -> (term: StructuredTerm, tokens: Int)? {
        if lowered == "f" {
            guard let next, let number = apertureNumber(next) else {
                // `f` + a non-numeric next token: the user typed something
                // like "f stop" — the head alone is meaningless → error.
                throw ExifSearchParserError.unrecognizedToken(lowered)
            }
            return (apertureTerm(number), 2)
        }
        // One-token forms: f + optional separator run + number.
        if lowered.hasPrefix("f") {
            var rest = String(lowered.dropFirst())
            if rest.hasPrefix("/") || rest.hasPrefix(".") { rest.removeFirst() }
            if let number = apertureNumber(rest) {
                return (apertureTerm(number), 1)
            }
            if rest.isEmpty { return nil }  // a bare "f"-prefixed word? no
            // `f` + junk that is not a word start → looks like a broken
            // aperture (`f/2.8.5`) → typed error; a letter continuation
            // (`fstop`) is a plain word → FTS.
            if rest.first!.isNumber {
                throw ExifSearchParserError.unrecognizedToken(lowered)
            }
            return nil
        }
        return nil
    }

    /// `2.8` / `28`-style whole.fraction → the f-number (`28` ≠ 28.0 for
    /// apertures — `f28` is NOT a common spelling; require the fraction
    /// form or a single digit).
    private static func apertureNumber(_ lowered: String) -> Double? {
        guard !lowered.isEmpty, !lowered.contains("-"),
              lowered.allSatisfy({ $0.isNumber || $0 == "." }),
              lowered.split(separator: ".").count <= 2,
              let value = Double(lowered), value > 0
        else { return nil }
        return value
    }

    private static func apertureTerm(_ number: Double) -> StructuredTerm {
        StructuredTerm(
            field: .aperture,
            constraint: .between(
                lower: rounded4(number - apertureTolerance),
                upper: rounded4(number + apertureTolerance)))
    }

    /// Snap a tolerance-band bound to 4 decimals so the bound IS the
    /// decimal literal (2.8 + 0.05 = 2.8499…96 in raw IEEE — the snapped
    /// value binds the canonical 2.85 and Equatable tests stay exact).
    private static func rounded4(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    // MARK: - Focal family

    /// `35mm` (one token) or `35` + `mm` (two tokens) → focal == 35.
    private static func consumeFocal(
        _ lowered: String, next: String?
    ) -> (term: StructuredTerm, tokens: Int)? {
        if lowered.hasSuffix("mm"),
           let value = Double(lowered.dropLast(2)),
           value > 0, value <= 10_000 {
            return (
                StructuredTerm(field: .focalLength, constraint: .equals(value)),
                1)
        }
        if let next, next == "mm",
           let value = Double(lowered), value > 0, value <= 10_000,
           lowered.allSatisfy(\.isNumber) {
            return (
                StructuredTerm(field: .focalLength, constraint: .equals(value)),
                2)
        }
        return nil
    }

    // MARK: - Date family

    /// The five date spellings (KD-1) → one capture_date between. Invalid
    /// calendar values (`2024-13`, `2024-02-30`) are typed errors — the
    /// digits LOOK like a date, so silence would hide a typo.
    private static func consumeDate(_ lowered: String) throws -> ClosedRange<Date>? {
        // 2024 (4 digits) → the whole year.
        if lowered.count == 4, lowered.allSatisfy(\.isNumber),
           let year = Int(lowered) {
            return yearRange(year)
        }
        // 202406 / 20240601 → the 6/8-digit spellings.
        if (lowered.count == 6 || lowered.count == 8),
           lowered.allSatisfy(\.isNumber) {
            let year = Int(lowered.prefix(4)) ?? 0
            let month = Int(lowered.dropFirst(4).prefix(2)) ?? 0
            let day: Int? = lowered.count == 8
                ? Int(lowered.suffix(2)) : nil
            return try componentRange(
                year: year, month: month, day: day, token: lowered)
        }
        // 2024-06 / 2024-06-01 / 2024/06/01.
        let parts = lowered.split(whereSeparator: { $0 == "-" || $0 == "/" })
        if parts.count == 2 || parts.count == 3,
           lowered.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "/" }) {
            let year = Int(parts[0]) ?? 0
            let month = Int(parts[1]) ?? 0
            let day: Int? = parts.count == 3 ? Int(parts[2]) : nil
            return try componentRange(
                year: year, month: month, day: day, token: lowered)
        }
        return nil
    }

    /// Components → the inclusive whole-second range (EXIF dates carry no
    /// sub-second precision). Round-trip re-decomposition rejects overflow
    /// spellings (`2024-02-30` would otherwise wrap to March 1).
    private static func componentRange(
        year: Int, month: Int, day: Int?, token: String
    ) throws -> ClosedRange<Date> {
        let calendar = utcCalendar
        var start = DateComponents(
            year: year, month: month, day: day ?? 1,
            hour: 0, minute: 0, second: 0)
        start.timeZone = TimeZone(identifier: "UTC")
        guard let startDate = calendar.date(from: start) else {
            throw ExifSearchParserError.unrecognizedToken(token)
        }
        var roundTrip = calendar.dateComponents(
            [.year, .month, .day], from: startDate)
        roundTrip.timeZone = TimeZone(identifier: "UTC")
        guard roundTrip.year == year, roundTrip.month == month,
              roundTrip.day == (day ?? 1)
        else {
            throw ExifSearchParserError.unrecognizedToken(token)
        }
        if let day {
            let end = startDate.addingTimeInterval(86_400 - 1)
            return startDate...end
        }
        // Month: the first second of the next month − 1s.
        let nextMonth = month == 12
            ? dateOrThrow(year: year + 1, month: 1, day: 1, token: token)
            : dateOrThrow(year: year, month: month + 1, day: 1, token: token)
        return startDate...(nextMonth.addingTimeInterval(-1))
    }

    private static func yearRange(_ year: Int) -> ClosedRange<Date> {
        let start = dateOrThrow(year: year, month: 1, day: 1, token: String(year))
        let next = dateOrThrow(
            year: year + 1, month: 1, day: 1, token: String(year))
        return start...(next.addingTimeInterval(-1))
    }

    private static func dateOrThrow(
        year: Int, month: Int, day: Int, token: String
    ) -> Date {
        var components = DateComponents(
            year: year, month: month, day: day, hour: 0, minute: 0, second: 0)
        components.timeZone = TimeZone(identifier: "UTC")
        guard let date = utcCalendar.date(from: components) else {
            // Unreachable for the validated call sites; typed anyway.
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private static let utcCalendar = Calendar(identifier: .iso8601)

    /// AND-merge a second date token: intersection; disjoint = typed error
    /// (a single `dateRange` field cannot carry a disjoint AND).
    private static func merge(
        _ range: ClosedRange<Date>, into target: inout ClosedRange<Date>?
    ) throws {
        guard let existing = target else {
            target = range
            return
        }
        let lower = max(existing.lowerBound, range.lowerBound)
        let upper = min(existing.upperBound, range.upperBound)
        guard lower <= upper else {
            throw ExifSearchParserError.disjointDateRanges
        }
        target = lower...upper
    }

    // MARK: - AND-composition helper

    private static func apply(
        _ term: StructuredTerm, to list: inout [StructuredTerm]
    ) {
        list.append(term)
    }
}
