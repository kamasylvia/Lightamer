import Foundation

// ─────────────────────────────────────────────────────────────────────────
// YiyinExifFormat (Plan 08-2 T1/T2) — the yiyin EXIF display-value layer:
// 15 watermark template fields formatted from `CaptureMetadata`, plus the
// brand normalization (α / ℤ / roman numerals / the mathematical-letter
// filter) — a 1:1 port of the yiyin v1.7.1 sources (read-only spec source
// at https://github.com/kamasylvia/yiyin):
//
//   common/const/def-fields.ts:1-17      15 field keys + zh names
//   common/modules/exif-format/index.ts  CORPORATION strip + brand dispatch
//   common/modules/exif-format/base.ts   per-field format methods
//   common/modules/exif-format/nikon.ts  ℤ + underscore split + roman
//   common/modules/exif-format/sony.ts   ILCE- → α + lowercase
//   electron/src/modules/exiftool/index.ts:82-168  the format table
//     (fraction shutter / date strip / program letters / metering zh /
//      white balance) — the NUMERIC (exif-parser) branch is our spec,
//     because the 08-3 walk reads ImageIO numeric enums, not exiftool
//     strings; the STRING branch is ported verbatim alongside as the
//     documentation-grade reference surface.
//   electron/src/utils/date.ts:8-44      formatDate engine (y/M/d/h/m/s/q/S)
//   web/util/util.ts:3-30,32-54          toRoman / charToNumberChar
//   web/util/model-map.ts                the filter-table surface (NOTE:
//     dead code in yiyin v1.7.1 — imported by nothing; ported for parity,
//     NOT wired into the display chain, decision D-08-2-2)
//
// LIGHTAMER DIVERSIONS (all recorded in 08-2-DECISIONS):
// - Input = typed `CaptureMetadata` (the 08-3 ImageIO walk's product), not
//   an exiftool string record. Sub-second/time-zone stripping happens at
//   the walk; this layer formats from a `Date` + capture-local `TimeZone`.
// - Metering mode maps the EXIF numeric enum 0...6 onto the yiyin zh
//   strings (the string table IS ported verbatim too).
// - Position: Decode/ (co-located with CaptureMetadata — the compile
//   dependency direction; D-08-2-1).
// ─────────────────────────────────────────────────────────────────────────

/// The 15 watermark template fields (yiyin `def-fields.ts` order verbatim).
public enum YiyinExifField: String, CaseIterable, Sendable {
    case personalSign = "PersonalSign"
    case make = "Make"
    case model = "Model"
    case lensMake = "LensMake"
    case lensModel = "LensModel"
    case exposureTime = "ExposureTime"
    case fNumber = "FNumber"
    case iso = "ISO"
    case focalLength = "FocalLength"
    case focalLength35mm = "FocalLengthIn35mmFormat"
    case exposureProgram = "ExposureProgram"
    case dateTimeOriginal = "DateTimeOriginal"
    case exposureCompensation = "ExposureCompensation"
    case meteringMode = "MeteringMode"
    case whiteBalance = "WhiteBalance"

    /// The zh display names (yiyin `def-fields.ts` — the panel's field
    /// inserter labels; kept as data so Core carries one source of truth).
    public var zhName: String {
        switch self {
        case .personalSign: return "个性签名"
        case .make: return "Logo"
        case .model: return "型号"
        case .lensMake: return "镜头Logo"
        case .lensModel: return "镜头型号"
        case .exposureTime: return "快门"
        case .fNumber: return "光圈"
        case .iso: return "ISO"
        case .focalLength: return "焦距"
        case .focalLength35mm: return "等效焦距"
        case .exposureProgram: return "档位"
        case .dateTimeOriginal: return "拍摄日期"
        case .exposureCompensation: return "曝光补偿"
        case .meteringMode: return "测光模式"
        case .whiteBalance: return "白平衡"
        }
    }
}

public enum YiyinExifFormat {

    // MARK: - JS number spelling (the yiyin `+record.X` / `${v}` faces)

    /// JS-style number → string: integral doubles print WITHOUT the
    /// trailing `.0` (`+exiftool-float 8` → `"8"`), non-integral keep the
    /// shortest round-trip decimal. The yiyin `${+record.FNumber}` face.
    public static func jsNumber(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 {
            return String(Int(v))
        }
        return "\(v)"
    }

    // MARK: - Per-field format methods (base.ts verbatim shapes)

    /// 快门 (base.ts:32-41): `v < 1 → "1/{round(1/v)}"`, else the seconds
    /// number. nil/0 → "".
    public static func exposureTime(_ v: Double?) -> String {
        guard let v, v != 0 else { return "" }
        if v < 1 {
            return "1/\(Int((1 / v).rounded()))" // Math.round(1/v)
        }
        return jsNumber(v)
    }

    /// 光圈 (the `${+record.FNumber}` face): `2.8` → `"2.8"`, `8` → `"8"`.
    public static func fNumber(_ v: Double?) -> String {
        guard let v else { return "" }
        return jsNumber(v)
    }

    /// 焦距 / 等效焦距 (base.ts:57-70): `Math.round(v)`, nil/0 → "".
    public static func focalLength(_ v: Double?) -> String {
        guard let v, v != 0 else { return "" }
        return String(Int(v.rounded()))
    }

    /// ISO (base.ts:72-74): `v || ''`.
    public static func iso(_ v: Int?) -> String {
        guard let v, v != 0 else { return "" }
        return String(v)
    }

    /// 档位 (exiftool/index.ts:106-113 numeric branch): 0→Auto, 1→M,
    /// 2→P, 3→A, 4→S, other values keep their decimal string (the yiyin
    /// `switch` default `break` leaves the parsed number).
    public static func exposureProgram(_ v: Int?) -> String {
        guard let v else { return "" }
        switch v {
        case 0: return "Auto"
        case 1: return "M"
        case 2: return "P"
        case 3: return "A"
        case 4: return "S"
        default: return String(v)
        }
    }

    /// 白平衡 (exiftool/index.ts:131-138 numeric branch): 0→Auto,
    /// 1→手动, else the number string.
    public static func whiteBalance(_ v: Int?) -> String {
        guard let v else { return "" }
        switch v {
        case 0: return "Auto"
        case 1: return "手动"
        default: return String(v)
        }
    }

    /// 测光模式 — the yiyin zh table (exiftool/index.ts:140-165), keyed by
    /// the EXIF numeric enum the 08-3 ImageIO walk produces:
    /// 1 average → 平均测光, 2 center-weighted → 中央重点测光,
    /// 3 spot → 点测光, 5 pattern/multi-segment → 评价测光,
    /// 6 partial → 局部测光; 0 unknown and 4 multi-spot have NO yiyin
    /// entry (the switch default → "").
    public static func meteringMode(_ v: Int?) -> String {
        guard let v else { return "" }
        switch v {
        case 1: return "平均测光"
        case 2: return "中央重点测光"
        case 3: return "点测光"
        case 5: return "评价测光"
        case 6: return "局部测光"
        default: return ""
        }
    }

    /// 测光模式 — the yiyin exiftool STRING table verbatim (the
    /// documentation-grade reference face of `meteringMode(_:)`; the
    /// numeric mapping above is its 08-3 contract). Unknown → "".
    public static func meteringMode(fromExiftoolString raw: String) -> String {
        switch raw.lowercased() {
        case "evaluative", "multi-segment", "multi-zone": return "评价测光"
        case "spot": return "点测光"
        case "partial": return "局部测光"
        case "average": return "平均测光"
        case "center-weighted": return "中央重点测光"
        case "highlight-weighted": return "斑马测光"
        default: return ""
        }
    }

    /// 曝光补偿 (the `${record.ExposureCompensation || ''}` face).
    public static func exposureCompensation(_ v: Double?) -> String {
        guard let v else { return "" }
        return jsNumber(v)
    }

    // MARK: - Date (electron/src/utils/date.ts formatDate 直译)

    /// The `formatDate(rule, date)` engine — rules `y` 年 `M` 月 `d` 日
    /// `h` 时 `m` 分 `s` 秒 `q` 季 `S` 毫秒: a run of the same rule letter
    /// pads to that width (zero-padded from the left, `00`+value
    /// suffix-sliced) except `y+` which right-aligns by chopping the full
    /// year from the left, and single letters which print unpadded.
    /// `hh` in the default pattern is HOURS (the yiyin date.ts h rule —
    /// 24h clock), NOT the locale AM/PM face.
    public static func formatDate(
        _ rule: String, _ date: Date, timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let year = c.year ?? 0
        let month = c.month ?? 0
        let day = c.day ?? 0
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        let second = c.second ?? 0
        let quarter = (month + 2) / 3 // Math.floor((month+3)/3) for 1-based
        let millis = (c.nanosecond ?? 0) / 1_000_000 // positive wall-clock ms

        var out = rule
        // y+ run: replace with the FULL year, keeping only the LAST
        // len digits (yiyin `substring(4 - len)`).
        if let match = out.firstRun(of: "y") {
            let full = String(year)
            let keep = min(match.count, full.count)
            out = out.replacingCharacters(
                in: match.range, with: String(full.suffix(keep)))
        }
        // The value runs (pad-to-width, yiyin `("00"+v).substring((""+v).length)`).
        func padded(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            if width <= 1 || s.count >= width { return s }
            return String(repeating: "0", count: width - s.count) + s
        }
        for (letter, value) in [
            ("M", month), ("d", day), ("h", hour), ("m", minute),
            ("s", second), ("q", quarter), ("S", millis),
        ] as [(Character, Int)] {
            while let match = out.firstRun(of: letter) {
                out = out.replacingCharacters(
                    in: match.range, with: padded(value, match.count))
            }
        }
        return out
    }
    /// 拍摄日期 (exiftool/index.ts:115-129): the default
    /// `yyyy/MM/dd hh:mm:ss` face over the capture-local wall clock.
    public static func dateTimeOriginal(
        _ date: Date?, format: String = "yyyy/MM/dd hh:mm:ss",
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else { return "" }
        return formatDate(format, date, timeZone: timeZone)
    }

    // MARK: - Brand normalization (exif-format/{index,base,nikon,sony}.ts)

    /// Make normalization (index.ts:34 + base.ts:11-13): strip
    /// `CORPORATION`, then `v[0] + v.slice(1).toLowerCase()` (first letter
    /// upper, rest lower). Empty → "".
    public static func make(_ raw: String?) -> String {
        guard var v = raw else { return "" }
        v = v.replacingOccurrences(of: "CORPORATION", with: "").trimmingCharacters(
            in: .whitespaces)
        guard !v.isEmpty else { return "" }
        return v.prefix(1).uppercased() + v.dropFirst().lowercased()
    }

    /// The brand dispatch key (index.ts:27-45): the CORPORATION-stripped
    /// make selects the brand formatter; only NIKON and SONY diverge.
    /// Dispatch is on the uppercased stripped make (yiyin looks the raw
    /// stripped make up EXACTLY — "NIKON"/"SONY"; the uppercased lookup is
    /// the robust superset, D-08-2-3).
    public static func model(_ raw: String?, make rawMake: String?) -> String {
        let key = strippedMake(rawMake).uppercased()
        switch key {
        case "NIKON":
            return nikonModel(raw, make: rawMake)
        case "SONY":
            return sonyModel(raw)
        default:
            // base.ts:19-23 Model(): plain lowercase.
            return (raw ?? "").lowercased()
        }
    }

    /// yiyin `init()`: strip `CORPORATION` + trim (NO case normalization —
    /// that happens only in the display `Make()`).
    private static func strippedMake(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw.replacingOccurrences(of: "CORPORATION", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Sony (sony.ts:4-6 base + model-map.ts:38-41 variant): `Model.replace
    /// ('ILCE-', 'α ').toLowerCase()` — the SPACED 'α ' form per the plan's
    /// test vector (`ILCE-7M4 → α 7m4`; sony.ts itself substitutes the bare
    /// 'α', a typographic quirk the spaced model-map face fixes,
    /// D-08-2-4).
    public static func sonyModel(_ raw: String?) -> String {
        let v = raw ?? ""
        return v.replacingOccurrences(of: "ILCE-", with: "α ").lowercased()
    }

    /// Nikon (nikon.ts:6-20): strip the RAW MAKE uppercased (`Model.replace
    /// (Make.toUpperCase(), '')` — note NO lowercase step in nikon.ts, the
    /// base.ts Model() lowercase does NOT apply), `Z → ℤ` (all cases),
    /// then split on `_`: a trailing NUMERIC segment becomes a roman
    /// numeral (`Z_6_II` → `ℤ 6 II` shape — the split tail joins with
    /// spaces, the numeric tail romanizes); otherwise the tail appends
    /// verbatim; no underscore → the replaced string as-is. Leading/
    /// trailing spaces survive HERE — the template engine's slot `.trim()`
    /// removes them (genTextImg slot face).
    public static func nikonModel(_ raw: String?, make rawMake: String? = nil) -> String {
        let v = (raw ?? "")
            .replacingOccurrences(of: strippedMake(rawMake).uppercased(), with: "")
            .replacingOccurrences(of: "Z", with: "ℤ")
            .replacingOccurrences(of: "z", with: "ℤ")
        let arr = v.components(separatedBy: "_")
        guard arr.count > 1 else { return v }
        var segments = arr
        let tail = segments.removeLast()
        if let n = Int(tail) {
            return "\(segments.joined(separator: " ")) \(toRoman(n))"
        }
        return "\(segments.joined(separator: " ")) \(tail)"
    }

    /// Roman numerals (web/util/util.ts:3-30 — the subtractive table
    /// verbatim). 0 and negatives → "".
    public static func toRoman(_ num: Int) -> String {
        let table: [(value: Int, numeral: String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var n = num
        var roman = ""
        for entry in table {
            while n >= entry.value {
                roman += entry.numeral
                n -= entry.value
            }
        }
        return roman
    }

    /// The mathematical-letter filter (web/util/util.ts:32-54 — VERBATIM,
    /// D-08-CONTEXT-8 retained-for-parity). ASCII letters map into the
    /// Mathematical Alphanumeric block starting at 0x1D63C (uppercase at
    /// the base, lowercase at base+26); every other code point passes
    /// through untouched. The CoreText system cascade renders whichever
    /// glyph family the OS resolves — golden notes the system dependency.
    public static func charToNumberChar(_ origin: String, mathematicalFontStart: Int = 0x1D63C)
        -> String
    {
        let a = UnicodeScalar(UInt8(97)) // 'a'
        let capA = UnicodeScalar(UInt8(65)) // 'A'
        var out = String()
        out.reserveCapacity(origin.count)
        for scalar in origin.unicodeScalars {
            let value = Int(scalar.value)
            let lowerOffset = value - Int(a.value)
            let upperOffset = value - Int(capA.value)
            if lowerOffset >= 0, lowerOffset <= 25 {
                out.unicodeScalars.append(
                    UnicodeScalar(mathematicalFontStart + 26 + lowerOffset)!)
            } else if upperOffset >= 0, upperOffset <= 25 {
                out.unicodeScalars.append(
                    UnicodeScalar(mathematicalFontStart + upperOffset)!)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// The model-map filter-table surface (web/util/model-map.ts VERBATIM —
    /// dead code in yiyin v1.7.1, ported for parity, NOT wired into the
    /// display chain, D-08-2-2). `brand` selects INIT/DEF/NIKON/SONY.
    public static func modelMapFilter(brand: String, make: String) -> String {
        switch brand {
        case "INIT":
            return make.replacingOccurrences(of: "CORPORATION", with: "")
        case "DEF":
            let v = make.replacingOccurrences(of: "CORPORATION", with: "")
            guard let first = v.first else { return "" }
            return charToNumberChar(String(first) + v.dropFirst().lowercased())
        default:
            return make
        }
    }

    /// The model-map MODEL filter face (same dead-code surface).
    public static func modelMapFilter(brand: String, model raw: String) -> String {
        switch brand {
        case "DEF":
            return charToNumberChar(raw.lowercased())
        case "NIKON":
            return nikonModel(raw)
        case "SONY":
            return sonyModel(raw)
        default:
            return raw
        }
    }

    // MARK: - The 15-field fill (the template engine's value provider)

    /// Fill all 15 display values from the capture metadata (the
    /// `ExifFormat` value provider the template engine consumes,
    /// temp-field/index.ts:58-107's value face). `personalSign` carries
    /// the user's 个性签名 free text (yiyin keeps it in the field config's
    /// forceUse custom value; there is no EXIF source — the parameter
    /// exists so the panel's single fill point stays symmetric).
    /// `dateFormat` is the user-editable pattern (default
    /// `yyyy/MM/dd hh:mm:ss`); `timeZone` the capture-local zone.
    public static func fields(
        from meta: CaptureMetadata?,
        personalSign: String? = nil,
        dateFormat: String = "yyyy/MM/dd hh:mm:ss",
        timeZone: TimeZone = .current
    ) -> [YiyinExifField: String] {
        guard let meta else {
            var empty: [YiyinExifField: String] = [:]
            for key in YiyinExifField.allCases { empty[key] = "" }
            return empty
        }
        let normalizedMake = make(meta.cameraMake)
        return [
            .personalSign: personalSign ?? "",
            .make: normalizedMake,
            .model: model(meta.cameraModel, make: meta.cameraMake),
            .lensMake: meta.lensMake ?? "",
            .lensModel: meta.lensModel ?? "",
            .exposureTime: exposureTime(meta.shutterSpeed),
            .fNumber: fNumber(meta.aperture),
            .iso: iso(meta.iso),
            .focalLength: focalLength(meta.focalLength),
            .focalLength35mm: focalLength(
                meta.focalLength35mm ?? meta.focalLength),
            .exposureProgram: exposureProgram(meta.exposureProgram),
            .dateTimeOriginal: dateTimeOriginal(
                meta.captureTime, format: dateFormat, timeZone: timeZone),
            .exposureCompensation: exposureCompensation(meta.exposureCompensation),
            .meteringMode: meteringMode(meta.meteringMode),
            .whiteBalance: whiteBalance(meta.whiteBalance),
        ]
    }
}

// MARK: - small helpers

extension String {
    /// The first run of `letter` (1+ consecutive occurrences) — the
    /// formatDate rule scanner (`/(y+)/`-family matches). Returns the run
    /// length and its range.
    fileprivate func firstRun(of letter: Character) -> (count: Int, range: Range<Index>)? {
        guard let start = self.firstIndex(of: letter) else { return nil }
        var end = self.index(after: start)
        while end < endIndex, self[end] == letter {
            end = self.index(after: end)
        }
        return (distance(from: start, to: end), start..<end)
    }
}
