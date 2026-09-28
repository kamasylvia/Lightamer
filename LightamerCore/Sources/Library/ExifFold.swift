import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExifFold (Plan M2-2-1 T3) — the folded-search VOCABULARY 正本 (the
// correctness-load-bearing face of M2LIB-04's lexical retrieval, probe P2).
//
// THE PROBLEM IT SOLVES: users type `iso800`, `f2.8`, `35mm` — EXIF carries
// "ISO 800", "f/2.8", "35 mm". The DEFAULT unicode61 tokenizer splits on
// every non-alphanumeric (`f/2.8` → tokens f, 2, 8), so an UNfolded index
// can never answer `f2.8` and `iso800` misses "ISO 800" (different tokens).
// The fix is NOT tokenizer customization (probe P2: registering
// `.-/` as token chars folds `f/2.8` into ONE token and the `f2.8` query
// MISSES — worse) — it is MATERIALIZED NORMALIZATION: every images row
// stores BOTH the folded text (LIKE leg) and the folded word-variant
// string (FTS leg); queries fold the SAME way through `matchQueryToken`.
//
// THE TWO FACES:
//   • `foldedVariants(for:)` — document side: structured EXIF facts →
//     (text, words) for the `exif_search_text` / `exif_search_words`
//     materialized columns. `words` holds the space-joined variant set
//     (the FTS token source); `text` holds a human-grep-able superset
//     (the LIKE `%token%` leg).
//   • `matchQueryToken(_:)` — query side: ONE user token → the folded
//     variant set to MATCH against. Both sides derive from the SAME
//     vocabulary constants, so a variant added on one side exists on the
//     other (the双向 contract pinned by ExifFoldTests).
//
// PREFIX-SAFETY: `iso800` must NOT hit an `iso8000` row. FTS MATCH on the
// token `iso800` is exact-token (no prefix semantics), and the folded
// variants keep the number as a SEPARATE word (`iso 800`), so `iso8000`
// materializes `iso 800 0`-adjacent tokens, never an `iso800` token. The
// ExifFoldTests pin this against the REAL FTS index.
//
// Pure functions + constants — NO IO, doubly testable (the P2 正本).
// ─────────────────────────────────────────────────────────────────────────────

public enum ExifFold {

    // MARK: - Structured EXIF facts (the Indexer's input)

    /// The structured EXIF facts one images row folds from (the
    /// SessionIndexSchema v2 key set — camera/lens/iso/focal/aperture/stem
    /// — plus the capture date for the multi-spelling family).
    public struct Facts: Sendable, Equatable {
        public var fileStem: String?
        public var cameraMake: String?
        public var cameraModel: String?
        public var lensModel: String?
        public var iso: Int?
        public var focalLength: Double?      // mm
        public var aperture: Double?         // f-number
        public var exposure: Double?         // seconds
        public var captureDate: Date?

        public init(
            fileStem: String? = nil, cameraMake: String? = nil,
            cameraModel: String? = nil, lensModel: String? = nil,
            iso: Int? = nil, focalLength: Double? = nil,
            aperture: Double? = nil, exposure: Double? = nil,
            captureDate: Date? = nil
        ) {
            self.fileStem = fileStem
            self.cameraMake = cameraMake
            self.cameraModel = cameraModel
            self.lensModel = lensModel
            self.iso = iso
            self.focalLength = focalLength
            self.aperture = aperture
            self.exposure = exposure
            self.captureDate = captureDate
        }
    }

    /// The fold product: `text` for the LIKE leg, `words` for the FTS leg
    /// (space-joined variant tokens; the images_fts external-content
    /// column source).
    public typealias Folded = (text: String, words: String)

    // MARK: - Vocabulary (the freeze — both faces derive from these)

    /// Lowercase + whitespace-normalize (the base fold every variant rides).
    static func normalize(_ raw: String) -> String {
        let collapsed = raw.split(
            whereSeparator: { $0.isWhitespace || $0.isNewline }
        ).joined(separator: " ")
        return collapsed.lowercased()
    }

    /// Strip separator characters (the "everything-adjacent" fold):
    /// `f/2.8` → `f28`… — kept as an AUXILIARY variant.
    static func squashed(_ normalized: String) -> String {
        normalized.filter { $0.isLetter || $0.isNumber }
    }

    /// Separator→space fold: `f/2.8` → `f 2 8`, `35mm` → `35 mm`-adjacent
    /// (the unicode61-token-boundary-aligned variant family).
    static func spaced(_ normalized: String) -> String {
        String(normalized.map { character in
            character.isLetter || character.isNumber ? character : " "
        })
        .split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
    }

    /// The aperture spelling family: `aperture(FNumber)` 2.8 →
    /// {`f2.8`, `f 2 8`} — the spaced variant space-separates the DIGITS
    /// (the unicode61 token boundary alignment: tokens f/2/8), the raw
    /// form survives in `text` so the LIKE leg can answer a literal
    /// `f/2.8` paste.
    static func apertureVariants(_ aperture: Double) -> [String] {
        let number = Self.decimalString(aperture)
        let spaced = number.replacingOccurrences(of: ".", with: " ")
        return ["f\(number)", "f \(spaced)"]
    }

    /// The ISO spelling family: 800 → {`iso800`, `iso 800`}.
    static func isoVariants(_ iso: Int) -> [String] {
        ["iso\(iso)", "iso \(iso)"]
    }

    /// The focal-length spelling family: 35 → {`35mm`, `35 mm`}.
    static func focalVariants(_ focal: Double) -> [String] {
        let number = Self.integerString(focal)
        return ["\(number)mm", "\(number) mm"]
    }

    /// The exposure spelling family: 0.004 (1/250s) → the reciprocal form
    /// family {`1/250`, `1 250`} when a clean reciprocal exists; long
    /// exposures keep the decimal form (`0.5s` / `0 5`).
    static func exposureVariants(_ exposure: Double) -> [String] {
        var variants: [String] = []
        if exposure > 0, exposure < 1 {
            let reciprocal = Int((1.0 / exposure).rounded())
            // Only clean reciprocals (1/250 style); tolerance for the
            // EXIF APEX rounding drift.
            if abs(1.0 / Double(reciprocal) - exposure) < 0.000_001 {
                variants.append("1/\(reciprocal)")
                variants.append("1 \(reciprocal)")
            }
        }
        let decimal = Self.decimalString(exposure)
        variants.append("\(decimal)s")
        return variants
    }

    /// The date spelling family (probe P2's multi-format requirement):
    /// 2024-06-01 → {`20240601`, `2024 06 01`, `202406`, `2024 06`,
    /// `2024`} — year/month/day decompositions, so `202406`, `2024` and
    /// `06/01`-style partial queries have landing tokens. NO `2024-06-01`
    /// token form — unicode61 splits it identically to `2024 06 01`, and
    /// the hyphen form adds nothing but duplicate tokens.
    static func dateVariants(_ date: Date) -> [String] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = calendar.dateComponents(
            [.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month,
            let day = components.day
        else { return [] }
        let yearString = String(year)
        let monthString = String(format: "%02d", month)
        let dayString = String(format: "%02d", day)
        return [
            "\(yearString)\(monthString)\(dayString)",
            "\(yearString) \(monthString) \(dayString)",
            "\(yearString)\(monthString)",
            "\(yearString) \(monthString)",
            yearString,
        ]
    }

    // MARK: - Document face (the materialized columns)

    /// Fold structured EXIF facts into the `exif_search_text` /
    /// `exif_search_words` materialized column contents. `words` = the
    /// space-joined UNIQUE variant token set (FTS source); `text` = the
    /// same set PLUS the raw separator forms (`f/2.8`, `1/250`) for the
    /// LIKE leg. Deterministic order (facts order, variants in-family
    /// order) — byte-stable output for byte-stable input.
    public static func foldedVariants(for facts: Facts) -> Folded {
        var words: [String] = []

        // Names: normalized + squashed (Sony → sony; A7 IV → a7 iv / a7iv).
        for name in [facts.cameraMake, facts.cameraModel, facts.lensModel,
                     facts.fileStem] {
            guard let name, !name.isEmpty else { continue }
            let normalized = normalize(name)
            if !normalized.isEmpty { words.append(normalized) }
            let squash = squashed(normalized)
            if squash != normalized, !squash.isEmpty { words.append(squash) }
        }

        if let iso = facts.iso {
            words.append(contentsOf: isoVariants(iso))
        }
        if let focal = facts.focalLength, focal > 0 {
            words.append(contentsOf: focalVariants(focal))
        }
        if let aperture = facts.aperture, aperture > 0 {
            words.append(contentsOf: apertureVariants(aperture))
        }
        if let exposure = facts.exposure, exposure > 0 {
            words.append(contentsOf: exposureVariants(exposure))
        }
        if let date = facts.captureDate {
            words.append(contentsOf: dateVariants(date))
        }

        // Dedupe, keep first-seen order (byte-stable).
        var seen = Set<String>()
        let uniqueWords = words.filter { seen.insert($0).inserted }

        // The text leg adds the raw separator forms on top of the words.
        var text = uniqueWords
        if let aperture = facts.aperture, aperture > 0 {
            text.append("f/\(Self.decimalString(aperture))")
        }
        if let exposure = facts.exposure, exposure > 0, exposure < 1 {
            let reciprocal = Int((1.0 / exposure).rounded())
            if abs(1.0 / Double(reciprocal) - exposure) < 0.000_001 {
                text.append("1/\(reciprocal)")
            }
        }
        return (text: text.joined(separator: " "), words: uniqueWords.joined(separator: " "))
    }

    // MARK: - Query face (the双向 alignment)

    /// One user query token → the folded variant set to match against.
    /// `iso800` → {`iso800`, `iso 800`}; `f2.8` → {`f2.8`, `f 2 8`,
    /// `f/2.8`}; `f/2.8` (pasted raw) normalizes to the SAME set;
    /// `20240601` → the date family; plain words (`sony`) fold to
    /// {normalized, squashed}. The FTS consumer ANDs one variant set per
    /// query token; the LIKE consumer ORs them inside one `%v%` group.
    public static func matchQueryToken(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let normalized = normalize(trimmed)
        var variants: Set<String> = [normalized]
        let squash = squashed(normalized)
        if !squash.isEmpty { variants.insert(squash) }

        // ISO form (`iso800`, with or without the space).
        let isoPattern = /^iso\s*(\d+)$/
        if let match = normalized.firstMatch(of: isoPattern) {
            variants.formUnion(isoVariants(Int(match.1) ?? 0))
            return variants.sorted()
        }
        // Aperture form (`f2.8`, `f 2.8`, `f/2.8`).
        let aperturePattern = /^f[\s\/.]*(\d+)(?:[.](\d+))?$/
        if let match = normalized.firstMatch(of: aperturePattern) {
            let whole = String(match.1)
            let fraction = match.2.map { String($0) } ?? ""
            let number = Self.canonicalDecimal(whole: whole, fraction: fraction)
            variants.formUnion(apertureVariants(number))
            variants.insert("f/\(number)")
            return variants.sorted()
        }
        // Focal form (`35mm`, `35 mm`).
        let focalPattern = /^(\d+)\s*mm$/
        if let match = normalized.firstMatch(of: focalPattern) {
            let number = Double(String(match.1)) ?? 0
            variants.formUnion(focalVariants(number))
            return variants.sorted()
        }
        // Date form (`20240601`, `2024-06-01`, `202406`) → the family.
        let digits = squashed(normalized)
        if digits.allSatisfy(\.isNumber), digits.count >= 4, digits.count <= 8 {
            variants.formUnion(dateVariants(forDigits: digits))
        }
        return variants.sorted()
    }

    /// The date family for a PARTIAL digit query (`2024`, `202406`,
    /// `20240601`) — the query side of dateVariants' document family.
    static func dateVariants(forDigits digits: String) -> [String] {
        var variants: [String] = []
        switch digits.count {
        case 4: // year
            variants.append(digits)
        case 6: // year + month
            let year = String(digits.prefix(4))
            let month = String(digits.suffix(2))
            variants.append(contentsOf: [
                digits, "\(year) \(month)", year,
            ])
        case 8: // full date
            let year = String(digits.prefix(4))
            let month = String(digits.dropFirst(4).prefix(2))
            let day = String(digits.suffix(2))
            variants.append(contentsOf: [
                digits, "\(year) \(month) \(day)",
                "\(year)\(month)", "\(year) \(month)", year,
            ])
        default:
            break
        }
        return variants
    }

    // MARK: - Number spelling (byte-stable decimals)

    /// The canonical decimal spelling: minimal fraction digits (2.8 →
    /// "2.8", 2.0 → "2", 1.4 → "1.4"). The float→string face both sides
    /// share (a mismatch here would split the vocabulary).
    static func decimalString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1_000_000 {
            return String(Int(value))
        }
        return Self.trimDecimal(String(format: "%.1f", value))
    }

    static func integerString(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func canonicalDecimal(whole: String, fraction: String) -> Double {
        let spelling = whole + (fraction.isEmpty ? "" : "." + fraction)
        return Double(spelling) ?? 0
    }

    /// "2.80" → "2.8" (trailing zeros off; bare "2." → "2").
    static func trimDecimal(_ spelling: String) -> String {
        guard spelling.contains(".") else { return spelling }
        var trimmed = spelling
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }
}
