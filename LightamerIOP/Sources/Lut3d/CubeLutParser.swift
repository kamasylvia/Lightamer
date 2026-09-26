import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// CubeLutParser (Plan 12-5 T1, IOP-COLOR-08) — the pure-Swift `.cube`
// parser (1D + 3D + DOMAIN_MIN/MAX remap metadata).
//
// DARKTABLE RELATION (RESEARCH §6.1 / F4): dt's parser (`lut3d.c:701-751`
// tokenizer, `:782-791` domain gate) ONLY accepts DOMAIN 0..1 — DOMAIN_MIN≠0
// / DOMAIN_MAX≠1 is a hard error there. Lightamer's ruling requires honoring
// DOMAIN_MIN/MAX for float/HDR cubes (ROADMAP SC#4), so the remap is an
// INTENTIONAL CAPABILITY EXTENSION beyond dt, not a port gap. The 3D
// ordering, the CRLF/inline-comment tolerance and the "swallow foreign
// lines, fail on count mismatch" posture mirror `lut3d.c` verbatim.
//
// 3D DATA ORDER = RED FASTEST (lut3d.cl:45): file row k maps to
// (r = k % L, g = (k/L) % L, b = k / L²) — `data` is stored in exactly the
// kernel index order `r + g*L + b*L²` so sampling needs no swizzle.
// (dt's `_calculate_clut_3dl` has to re-index because .3dl is BLUE-fastest;
// .cube is red-fastest natively.)
//
// KEY SET (RESEARCH §6.1 verbatim):
//   TITLE <text…>            — whole-rest-of-line value (dt SKIPS it; we
//                              keep it as the display name — divergence 1)
//   LUT_3D_SIZE <n>          — mutually exclusive with LUT_1D_SIZE
//   LUT_1D_SIZE <n>          — per-channel ramp rows follow
//   DOMAIN_MIN <1|3 floats>  — 1 float broadcasts to all three channels
//   DOMAIN_MAX <1|3 floats>  — same
//   LUT_1D_INPUT_RANGE <2>   — 1D input domain (shaper min/max)
//   '#' starts a comment anywhere in a line (dt `_parse_cube_line` treats
//   '#' like EOL — inline comments tolerated); blank lines skipped;
//   CRLF (`\r`) residue stripped by the newline split.
// ─────────────────────────────────────────────────────────────────────────

/// The typed parse errors (plan T1: eight names, seven of which throw —
/// `titleAfterData` is a TOLERATED condition recorded as a warning).
public enum CubeLutError: Error, Equatable, Sendable {

    /// Data rows arrived before any LUT_*_SIZE key (dt `:840` "size is not
    /// defined"), or keys existed but no size was declared.
    case missingSize

    /// `LUT_3D_SIZE` and `LUT_1D_SIZE` both present (or one key re-declared
    /// with a different value — dt silently overwrites; we refuse, typed).
    case conflictingSizes(first: Int, second: Int)

    /// Size beyond the defensive bound. 3D bound 129 (plan literal — a 129³
    /// rgba16Float texture is ~17MB, the researched memory ceiling); 1D
    /// bound 65536 (real-world 1D ramps are 1024-4096 rows — the 3D bound
    /// would reject valid 1D files; DECISIONS D1).
    case sizeOutOfRange(size: Int)

    /// Row count after the size key ≠ size³ (3D) / size (1D).
    /// `expected`/`actual` count TABLE ROWS, not floats.
    case dataCountMismatch(expected: Int, actual: Int)

    /// A token in a data-row-shaped line failed to parse as a finite
    /// number (NaN/Inf included — dt `:855` rejects NaN likewise).
    /// `line` is 1-based.
    case nonNumericToken(line: Int)

    /// DOMAIN_MIN ≥ DOMAIN_MAX on any channel (degenerate domain).
    case domainInvalid(min: SIMD3<Double>, max: SIMD3<Double>)

    /// No content at all (empty input / comments only / whitespace only).
    case emptyFile
}

/// A tolerated-but-noted parse condition.
public enum CubeLutWarning: Equatable, Sendable {
    /// TITLE seen after the first data row (kept, but the file is
    /// non-canonical — some exporters emit it at the tail).
    case titleAfterData
    /// A key that makes no sense for the declared table shape was present
    /// and is ignored (e.g. `LUT_1D_INPUT_RANGE` in a 3D file).
    case ignoredKey(String)
}

/// One parsed `.cube` table.
public struct CubeLut: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        /// 3D cube — `size³` rows, red fastest.
        case lut3d(size: Int)
        /// 1D per-channel ramp — `size` rows.
        case lut1d(size: Int)

        public var size: Int {
            switch self {
            case .lut3d(let s), .lut1d(let s): return s
            }
        }
    }

    /// Display name from the TITLE key (nil = absent). One pair of matching
    /// surrounding quotes stripped (DECISIONS D2).
    public var title: String?

    public var kind: Kind

    /// The sampling domain, default (0,0,0)…(1,1,1). 1-float DOMAIN keys
    /// broadcast to all channels (RESEARCH §6.1).
    public var domainMin: SIMD3<Double>
    public var domainMax: SIMD3<Double>

    /// `LUT_1D_INPUT_RANGE` (2 floats, 1D-only metadata; nil = absent).
    /// The 1D kernel remaps with this instead of `domainMin/Max` (RESEARCH
    /// §6.3); DOMAIN keys still parse alongside.
    public var inputRange: SIMD2<Double>?

    /// The table entries in kernel index order: 3D = `r + g*L + b*L²`
    /// (red fastest), 1D = the row order (per-channel R,G,B per row).
    public var data: [SIMD3<Float>]

    public var warnings: [CubeLutWarning]

    public init(
        title: String? = nil, kind: Kind, domainMin: SIMD3<Double> = SIMD3(0, 0, 0),
        domainMax: SIMD3<Double> = SIMD3(1, 1, 1), inputRange: SIMD2<Double>? = nil,
        data: [SIMD3<Float>], warnings: [CubeLutWarning] = []
    ) {
        self.title = title
        self.kind = kind
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.inputRange = inputRange
        self.data = data
        self.warnings = warnings
    }
}

public enum CubeLutParser {

    /// The 3D defensive size bound (plan literal "＞129 防御").
    static let max3DSize = 129
    /// The 1D defensive size bound (DECISIONS D1).
    static let max1DSize = 65_536

    /// Parse `.cube` text (any newline convention) into a `CubeLut`.
    ///
    /// - Throws: `CubeLutError` (typed, eight-name surface above).
    public static func parse(_ text: String) throws -> CubeLut {
        var title: String?
        var titleAfterData = false
        var size3D: Int?
        var size1D: Int?
        var domainMin = SIMD3<Double>(0, 0, 0)
        var domainMax = SIMD3<Double>(1, 1, 1)
        var inputRange: SIMD2<Double>?
        var data: [SIMD3<Float>] = []
        var ignoredKeys: [String] = []
        var sawData = false
        var sawAnyContent = false

        // Split lines on any newline convention (\n, \r\n, lone \r — note
        // Swift's "\r\n" is ONE Character, so `== "\n"` misses it; use
        // Character.isNewline, the dt tokenizer's byte-level '\n'/'\r' stop
        // set equivalent, lut3d.c:713-716).
        let lines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline)

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            // '#' starts a comment anywhere (dt lut3d.c:713 — '#' is EOL
            // for tokenizing purposes; inline comments tolerated).
            let hashIndex = rawLine.firstIndex(of: "#")
            let content: Substring = hashIndex.map { rawLine[..<$0] } ?? rawLine[...]
            let tokens = content.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if tokens.isEmpty { continue }
            sawAnyContent = true

            switch tokens[0] {
            case "TITLE":
                // Divergence 1 (vs dt): dt SKIPS the TITLE line
                // (lut3d.c:807 `if(token[0][0] == 'T') continue;`); we take
                // the whole rest of the line as the display name.
                if sawData { titleAfterData = true }
                let rest = content[content.range(of: "TITLE")!.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                title = rest.isEmpty ? nil : Self.unquoted(rest)

            case "LUT_3D_SIZE":
                let n = try Self.intToken(tokens, lineNumber: lineNumber)
                if let existing = size3D, existing != n {
                    throw CubeLutError.conflictingSizes(first: existing, second: n)
                }
                if let existing = size1D {
                    throw CubeLutError.conflictingSizes(first: existing, second: n)
                }
                guard n >= 2, n <= Self.max3DSize else {
                    throw CubeLutError.sizeOutOfRange(size: n)
                }
                size3D = n

            case "LUT_1D_SIZE":
                let n = try Self.intToken(tokens, lineNumber: lineNumber)
                if let existing = size1D, existing != n {
                    throw CubeLutError.conflictingSizes(first: existing, second: n)
                }
                if let existing = size3D {
                    throw CubeLutError.conflictingSizes(first: existing, second: n)
                }
                guard n >= 2, n <= Self.max1DSize else {
                    throw CubeLutError.sizeOutOfRange(size: n)
                }
                size1D = n

            case "DOMAIN_MIN":
                let v = try Self.floatTokens(tokens, count: nil, lineNumber: lineNumber)
                domainMin = v.count == 1 ? SIMD3(repeating: v[0]) : SIMD3(v[0], v[1], v[2])

            case "DOMAIN_MAX":
                let v = try Self.floatTokens(tokens, count: nil, lineNumber: lineNumber)
                domainMax = v.count == 1 ? SIMD3(repeating: v[0]) : SIMD3(v[0], v[1], v[2])

            case "LUT_1D_INPUT_RANGE":
                let v = try Self.floatTokens(tokens, count: 2, lineNumber: lineNumber)
                inputRange = SIMD2(v[0], v[1])
                if size3D != nil { ignoredKeys.append("LUT_1D_INPUT_RANGE") }

            default:
                // Non-key line: a data row or a foreign key. dt's gate is
                // "exactly 3 tokens advance the table, everything else is
                // swallowed" (lut3d.c:838 `else if(nb_token == 3)`); we
                // widen to 2-3 numeric tokens for the 1D variant (D4) and
                // type the corrupt-row case instead of swallowing it.
                let parsed: [Double?] = tokens.map {
                    Double($0).flatMap { $0.isFinite ? $0 : nil }
                }
                let allNumeric = parsed.allSatisfy { $0 != nil }
                let expectedWidths: Set<Int> = size1D != nil ? [2, 3] : [3]
                if allNumeric {
                    guard size3D != nil || size1D != nil else {
                        throw CubeLutError.missingSize
                    }
                    guard expectedWidths.contains(parsed.count) else {
                        continue  // foreign numeric line (dt swallow posture;
                                  // the count check fails the file anyway)
                    }
                    sawData = true
                    let values = parsed.compactMap { $0 }
                    switch values.count {
                    case 3:
                        data.append(
                            SIMD3(Float(values[0]), Float(values[1]), Float(values[2])))
                    default:
                        // The 1D 2-float variant (value + secondary channel
                        // — no standard semantics; broadcast the first as
                        // the gray ramp, DECISIONS D4).
                        data.append(SIMD3(repeating: Float(values[0])))
                    }
                } else {
                    // Mixed/corrupt: a data-row-shaped line with a bad
                    // token (e.g. "0.1 x 0.3" or "0.1 nan 0.3") is typed;
                    // anything else is a foreign key line (swallowed).
                    if parsed.count <= 3, expectedWidths.contains(parsed.count),
                       parsed.contains(where: { $0 != nil }) {
                        throw CubeLutError.nonNumericToken(line: lineNumber)
                    }
                }
            }
        }

        guard size3D != nil || size1D != nil else {
            throw sawAnyContent ? CubeLutError.missingSize : CubeLutError.emptyFile
        }
        // Domain validity is judged AFTER all keys are collected: keys may
        // arrive in either order, and an ordered pair like
        // `DOMAIN_MIN 2.0 / DOMAIN_MAX 3.0` (a legal HDR domain) only becomes
        // valid once MAX lands — validating per-key would reject the MIN
        // line against the still-default 1.0 (acceptance-round fix; the
        // invalid-pair vectors below still throw, just later).
        try Self.validateDomain(min: domainMin, max: domainMax)
        let declaredSize = size3D ?? size1D!
        let expectedRows = size3D != nil ? declaredSize * declaredSize * declaredSize : declaredSize
        guard data.count == expectedRows else {
            throw CubeLutError.dataCountMismatch(expected: expectedRows, actual: data.count)
        }

        var warnings: [CubeLutWarning] = []
        if titleAfterData { warnings.append(.titleAfterData) }
        for key in ignoredKeys { warnings.append(.ignoredKey(key)) }

        return CubeLut(
            title: title,
            kind: size3D != nil ? .lut3d(size: declaredSize) : .lut1d(size: declaredSize),
            domainMin: domainMin, domainMax: domainMax, inputRange: inputRange,
            data: data, warnings: warnings)
    }

    /// Parse raw file bytes (the library import face).
    public static func parse(data: Data) throws -> CubeLut {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CubeLutError.emptyFile
        }
        return try parse(text)
    }

    // MARK: - Internals

    private static func validateDomain(min: SIMD3<Double>, max: SIMD3<Double>) throws {
        if min.x >= max.x || min.y >= max.y || min.z >= max.z {
            throw CubeLutError.domainInvalid(min: min, max: max)
        }
    }

    private static func intToken(_ tokens: [Substring], lineNumber: Int) throws -> Int {
        let v = try floatTokens(tokens, count: 1, lineNumber: lineNumber)
        // Clamp BEFORE the Int conversion — Int(Double) traps out of range.
        // Anything beyond ±1e9 is far past every size bound and the range
        // guard below reports it typed.
        let clamped = min(max(v[0], -1e9), 1e9)
        return Int(clamped)
    }

    /// Parse `tokens[1...]` as floats. `count == nil` accepts 1-3 tokens
    /// (DOMAIN broadcast forms); a fixed count demands exactly that.
    private static func floatTokens(
        _ tokens: [Substring], count: Int?, lineNumber: Int
    ) throws -> [Double] {
        let body = Array(tokens.dropFirst())
        if let count, body.count != count {
            throw CubeLutError.nonNumericToken(line: lineNumber)
        }
        if body.isEmpty || body.count > 3 {
            throw CubeLutError.nonNumericToken(line: lineNumber)
        }
        return try body.map { token in
            // Double(String) handles scientific notation natively (RESEARCH
            // §6.1); NaN/Inf strings also parse — reject them (dt :855).
            guard let v = Double(token), v.isFinite else {
                throw CubeLutError.nonNumericToken(line: lineNumber)
            }
            return v
        }
    }

    /// Strip one pair of matching surrounding quotes (DECISIONS D2).
    private static func unquoted(_ s: String) -> String {
        var t = Substring(s)
        if t.count >= 2, t.first == "\"", t.last == "\"" {
            t = t.dropFirst().dropLast()
        }
        return String(t)
    }
}
