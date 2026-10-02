import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExportFileNameTemplate — the M2EXP-03 file-name template engine (Plan
// M2-9-01 T2, OQ-4/KD-3). Alcedo `{token:arg}` syntax, self-written (GPL
// sources are READ-ONLY behavioral references — semantics transcribed, no
// code copied).
//
//   pattern := (literal | escape | token)*
//   escape  := "{{" | "}}"        → a single "{" / "}" literal
//   token   := "{" name (":" arg)? "}"
//
// The 11 named fields + literal (12 faces): {source} {date:fmt}
// {cameramake} {cameramodel} {lens} {iso} {aperture} {shutter} {focal}
// {rating} {sequence:0000}. Token names are CASE-INSENSITIVE. The sequence
// argument must be ALL-ZERO digits (the zero COUNT is the pad width). The
// date argument is a token string over yyyy/MM/dd/HH/mm/ss plus filename-
// safe separators — ICU-compatible passthrough (KD-3).
//
// Parse and render are SEPARATE (the panel parses once to gate startExport
// with a typed error; render runs per job). Rendering ends in the template
// sanitize (Windows-conservative: control chars and <>:"/\|?* → "_",
// edges trimmed, reserved stems suffixed, 200-char cap) with the "image"
// fallback when nothing renders. The APFS-lenient ExportNamer.sanitizedStem
// is a DIFFERENT policy for a different job (in-place stems) — the two
// coexist by namespace (KD-3).
// ─────────────────────────────────────────────────────────────────────────────

/// One parsed pattern part: the literal/token two-state face (KD-3). The
/// eleven token cases carry exactly the argument the field consumes.
public enum ExportFileNamePart: Hashable, Sendable {
    case literal(String)
    case sourceStem
    case captureDate(format: String)
    case cameraMake
    case cameraModel
    case lensModel
    case iso
    case aperture
    case shutter
    case focal
    case rating
    case sequence(width: Int)
}

/// The typed parse errors (OQ-4: no silent tolerance — the panel disables
/// startExport and shows the reason).
public enum ExportFileNameTemplateError: Error, Equatable, Sendable {
    /// The pattern produced no parts (empty or whitespace-degenerate).
    case empty
    /// A `{` without its closing `}`.
    case unmatchedOpeningBrace
    /// A bare `}` outside a token (and not part of a `}}` escape).
    case unmatchedClosingBrace
    /// The token name is not one of the eleven fields (carries the text).
    case unknownField(String)
    /// `{sequence:...}` with an argument that is not all-zero digits.
    case invalidSequenceArgument(String)
    /// `{date:...}` with an argument outside the token+separator alphabet.
    case invalidDateArgument(String)
}

/// The per-job evaluation context (KD-3). Optional metadata faces render as
/// empty strings when absent (the Alcedo face: ISO 0 → empty, shutter
/// non-positive → empty, …).
public struct ExportFileNameContext: Sendable {

    /// The source file stem (the `{source}` face).
    public var sourceStem: String
    /// The capture instant (EXIF DateTimeOriginal lineage). nil = no date
    /// face renders.
    public var captureDate: Date?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    /// nil or 0 → the ISO face renders empty.
    public var iso: Int?
    /// ≤ 0 → empty; otherwise one decimal ("2.8").
    public var aperture: Double?
    /// Shutter exposure seconds; ≤ 0 → empty; < 1 s renders "1-<den>"
    /// (1/500 → "1-500" — "/" is illegal in a file name, "-" is the
    /// Alcedo-correct form), ≥ 1 s renders "<n>-1".
    public var shutterSeconds: Double?
    /// ≤ 0 → empty; otherwise one decimal + "mm" ("50.0mm").
    public var focalLengthMM: Double?
    /// nil → "0"; otherwise clamped to 0...5.
    public var rating: Int?
    /// The per-queue ordinal (1-based; the pad width lives in the token).
    public var sequence: Int

    public init(
        sourceStem: String,
        captureDate: Date? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        iso: Int? = nil,
        aperture: Double? = nil,
        shutterSeconds: Double? = nil,
        focalLengthMM: Double? = nil,
        rating: Int? = nil,
        sequence: Int = 1
    ) {
        self.sourceStem = sourceStem
        self.captureDate = captureDate
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.iso = iso
        self.aperture = aperture
        self.shutterSeconds = shutterSeconds
        self.focalLengthMM = focalLengthMM
        self.rating = rating
        self.sequence = sequence
    }
}

public enum ExportFileNameTemplate {

    /// The fallback stem when a pattern renders to nothing (Alcedo hpp:93).
    public static let fallbackStem = "image"

    /// The stem-length cap for TEMPLATE-RENDERED names (the Windows-
    /// conservative policy; MAX_PATH headroom). The APFS-lenient
    /// `ExportNamer.sanitizedStem` deliberately has no cap.
    public static let maximumStemLength = 200

    /// The date-argument alphabet: the six field tokens' letters plus the
    /// filename-safe separators the built-ins use (space, dash, underscore,
    /// dot). Anything else is a typed parse error (OQ-4's "date 实参非法
    /// token" — Alcedo instead passes unknown chars through; we reject so
    /// the panel can disable startExport with a reason, DECISIONS).
    private static let dateFormatAllowed: Set<Character> = [
        "y", "M", "d", "H", "m", "s", " ", "-", "_", ".",
    ]

    // MARK: - Parse

    /// Parse a user pattern into render parts. Typed failures carry the
    /// reason; nothing is silently dropped.
    public static func parse(
        _ pattern: String
    ) -> Result<[ExportFileNamePart], ExportFileNameTemplateError> {
        var parts: [ExportFileNamePart] = []
        var literal = ""

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            // Adjacent literals merge (one escape run next to text is one
            // part — keeps the parse product tidy for equality tests).
            if case .literal(let existing)? = parts.last {
                parts[parts.count - 1] = .literal(existing + literal)
            } else {
                parts.append(.literal(literal))
            }
            literal = ""
        }

        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            let next = pattern.index(after: index)

            // Escapes: "{{" → "{", "}}" → "}".
            if character == "{", next < pattern.endIndex, pattern[next] == "{" {
                literal.append("{")
                index = pattern.index(after: next)
                continue
            }
            if character == "}", next < pattern.endIndex, pattern[next] == "}" {
                literal.append("}")
                index = pattern.index(after: next)
                continue
            }

            if character != "{" {
                if character == "}" {
                    return .failure(.unmatchedClosingBrace)
                }
                literal.append(character)
                index = next
                continue
            }

            // Token: from "{" to the next "}" (escapes do NOT nest here —
            // Alcedo's find("}") face; a "{{" inside a token stays raw).
            flushLiteral()
            guard let closing = pattern[index...].firstIndex(of: "}"), closing > index else {
                return .failure(.unmatchedOpeningBrace)
            }
            let tokenText = String(pattern[pattern.index(after: index)..<closing])
            switch parseToken(tokenText) {
            case .success(let part):
                parts.append(part)
            case .failure(let error):
                return .failure(error)
            }
            index = pattern.index(after: closing)
        }
        flushLiteral()

        guard !parts.isEmpty else { return .failure(.empty) }
        return .success(parts)
    }

    /// One token body → a part. The name is case-insensitive; `sequence`
    /// demands an all-zero-digit argument (width = zero count); `date`
    /// validates its format argument against the token alphabet; every
    /// other field demands NO argument.
    private static func parseToken(
        _ tokenText: String
    ) -> Result<ExportFileNamePart, ExportFileNameTemplateError> {
        let separator = tokenText.firstIndex(of: ":")
        let rawName = separator.map { String(tokenText[..<$0]) } ?? tokenText
        let argument = separator.map { String(tokenText[tokenText.index(after: $0)...]) } ?? ""
        let name = rawName.lowercased()

        switch name {
        case "source":
            return argument.isEmpty ? .success(.sourceStem) : .failure(.unknownField(tokenText))
        case "date":
            guard argument.allSatisfy({ dateFormatAllowed.contains($0) }) else {
                return .failure(.invalidDateArgument(argument))
            }
            return .success(.captureDate(format: argument))
        case "cameramake":
            return argument.isEmpty ? .success(.cameraMake) : .failure(.unknownField(tokenText))
        case "cameramodel":
            return argument.isEmpty ? .success(.cameraModel) : .failure(.unknownField(tokenText))
        case "lens":
            return argument.isEmpty ? .success(.lensModel) : .failure(.unknownField(tokenText))
        case "iso":
            return argument.isEmpty ? .success(.iso) : .failure(.unknownField(tokenText))
        case "aperture":
            return argument.isEmpty ? .success(.aperture) : .failure(.unknownField(tokenText))
        case "shutter":
            return argument.isEmpty ? .success(.shutter) : .failure(.unknownField(tokenText))
        case "focal":
            return argument.isEmpty ? .success(.focal) : .failure(.unknownField(tokenText))
        case "rating":
            return argument.isEmpty ? .success(.rating) : .failure(.unknownField(tokenText))
        case "sequence":
            // The width is encoded in the zero count: all-zero digits (or
            // no argument at all). Any non-zero digit is a typed error.
            guard argument.allSatisfy({ $0 == "0" }) else {
                return .failure(.invalidSequenceArgument(argument))
            }
            return .success(.sequence(width: argument.count))
        default:
            return .failure(.unknownField(tokenText))
        }
    }

    // MARK: - Render

    /// Render the parsed parts against a job context. Every absent
    /// metadata face renders empty — an all-empty render yields "" and the
    /// caller falls back (`resolvedStem` does this in one step).
    public static func render(
        _ parts: [ExportFileNamePart], context: ExportFileNameContext
    ) -> String {
        parts.map { partText($0, context: context) }.joined()
    }

    /// Parse + render + sanitize + fallback in one call (the queue's per-
    /// job face). Never fails: an empty render falls back to `fallbackStem`
    /// (itself sanitized), so the stem is always non-empty.
    public static func resolvedStem(
        pattern: String,
        context: ExportFileNameContext,
        fallback: String = fallbackStem
    ) -> String {
        let parts: [ExportFileNamePart]
        switch parse(pattern) {
        case .success(let parsed):
            parts = parsed
        case .failure:
            parts = []
        }
        let stem = sanitizedStem(render(parts, context: context))
        if !stem.isEmpty { return stem }
        return sanitizedStem(fallback)
    }

    private static func partText(
        _ part: ExportFileNamePart, context: ExportFileNameContext
    ) -> String {
        switch part {
        case .literal(let text):
            return text
        case .sourceStem:
            return context.sourceStem
        case .captureDate(let format):
            return captureDateText(context.captureDate, format: format)
        case .cameraMake:
            return context.cameraMake ?? ""
        case .cameraModel:
            return context.cameraModel ?? ""
        case .lensModel:
            return context.lensModel ?? ""
        case .iso:
            guard let iso = context.iso, iso > 0 else { return "" }
            return String(iso)
        case .aperture:
            return decimalText(context.aperture, precision: 1, suffix: "")
        case .shutter:
            return shutterText(context.shutterSeconds)
        case .focal:
            return decimalText(context.focalLengthMM, precision: 1, suffix: "mm")
        case .rating:
            let clamped = min(max(context.rating ?? 0, 0), 5)
            return String(clamped)
        case .sequence(let width):
            let value = max(context.sequence, 0)
            let digits = String(value)
            guard digits.count < width else { return digits }
            return String(repeating: "0", count: width - digits.count) + digits
        }
    }

    /// The fixed-point face (Alcedo FormatNumber): non-finite or ≤ 0 →
    /// empty; otherwise the precision digits + suffix. Locale-pinned to
    /// POSIX so the decimal separator is "." on every machine.
    private static func decimalText(
        _ value: Double?, precision: Int, suffix: String
    ) -> String {
        guard let value, value.isFinite, value > 0 else { return "" }
        return String(format: "%.\(precision)f", locale: Locale(identifier: "en_US_POSIX"), value)
            + suffix
    }

    /// The shutter face (OQ-4 correction): the EXIF rational rendered with
    /// "-" as the numerator/denominator separator — "/" is ILLEGAL in a
    /// macOS file name, so "1/500" renders "1-500" (Alcedo cpp:157 form).
    /// Sub-second exposures reduce to "1-<den>" (the camera convention);
    /// whole-and-above seconds render "<n>-1".
    private static func shutterText(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "" }
        if seconds >= 1.0 {
            let whole = Int(seconds.rounded())
            return "\(whole)-1"
        }
        let denominator = max(1, Int((1.0 / seconds).rounded()))
        return "1-\(denominator)"
    }

    /// The date face: the six tokens are ICU-compatible letters, so the
    /// format string rides a fixed POSIX/Gregorian/UTC formatter directly
    /// (KD-3 "ICU 兼容直通"). Empty format = the Alcedo default `yyyyMMdd`.
    /// nil date → empty.
    private static func captureDateText(_ date: Date?, format: String) -> String {
        guard let date else { return "" }
        let effectiveFormat = format.isEmpty ? "yyyyMMdd" : format
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = effectiveFormat
        return formatter.string(from: date)
    }

    // MARK: - Sanitize (the template's Windows-conservative policy)

    /// Sanitize a RENDERED STEM for cross-platform exchange (Alcedo
    /// SanitizeFileStem semantics): control characters and the Windows
    /// reserved set `<>:"/\|?*` → "_"; trailing spaces/dots and LEADING
    /// spaces trimmed; a Windows reserved stem (case-insensitive) gains a
    /// trailing "_"; capped at 200 characters. Deliberately distinct from
    /// the APFS-lenient `ExportNamer.sanitizedStem` (which serves in-place
    /// source stems) — two policies, two jobs (KD-3, DECISIONS).
    public static func sanitizedStem(_ value: String) -> String {
        let reserved: Set<String> = [
            "CON", "PRN", "AUX", "NUL",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        ]
        let illegal: Set<Character> = [
            "<", ">", ":", "\"", "/", "\\", "|", "?", "*",
        ]

        var sanitized = String(value.map { character in
            (character.unicodeScalars.allSatisfy { $0.value < 32 } || illegal.contains(character))
                ? "_" : character
        })

        // Trailing spaces and dots go (Windows ignores them — a stem ending
        // in dots is un-addressable there); leading spaces go too.
        while let last = sanitized.last, last == " " || last == "." {
            sanitized.removeLast()
        }
        while let first = sanitized.first, first == " " {
            sanitized.removeFirst()
        }

        if reserved.contains(sanitized.uppercased()) {
            sanitized += "_"
        }
        if sanitized.count > maximumStemLength {
            sanitized = String(sanitized.prefix(maximumStemLength))
        }
        return sanitized
    }
}

// MARK: - Naming template preset model (KD-3/KD-4; the store lives in App)

/// One naming-template preset (the OQ-9 face): three BUILT-IN constants
/// (App-side store, never persisted) + user-saved presets (UserDefaults
/// JSON array under `export.namingTemplates`). `isBuiltIn` is false for
/// everything the store persists — the built-ins live only as constants.
public struct NamingTemplate: Codable, Hashable, Identifiable, Sendable {

    public var id: UUID
    public var name: String
    public var pattern: String
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, pattern: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isBuiltIn = isBuiltIn
    }
}
