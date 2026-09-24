@testable import LightamerCore
import Foundation
import XCTest

/// Plan 08-2 T1/T2 — the YiyinExifFormat suite (NO GPU dependencies — the
/// pure table-driven face).
///
/// T1 sections: the 15-field formatting table (yiyin
/// `electron/src/modules/exiftool/index.ts:82-168` NUMERIC branch + the
/// base.ts methods as the spec sources) and the additive-CaptureMetadata
/// six-field Codable compatibility (old archives without the keys decode).
///
/// T2 sections: brand normalization per yiyin
/// `common/modules/exif-format/{index,base,nikon,sony}.ts` — α / ℤ / roman
/// / CORPORATION — plus the RETAINED `charToNumberChar` mathematical-letter
/// filter (D-08-CONTEXT-8) asserted PER CODE POINT, and the formatDate
/// engine (electron/src/utils/date.ts).
final class YiyinExifFormatTests: XCTestCase {

    // ── T1: per-field formatting (edge values included) ──

    func testExposureTimeFractionAndSeconds() {
        // < 1 s → `1/{Math.round(1/v)}` (base.ts:36-39).
        XCTAssertEqual(YiyinExifFormat.exposureTime(0.005), "1/200")
        XCTAssertEqual(YiyinExifFormat.exposureTime(1.0 / 3.0), "1/3")
        XCTAssertEqual(YiyinExifFormat.exposureTime(1.0 / 250.0), "1/250")
        XCTAssertEqual(YiyinExifFormat.exposureTime(0.0001), "1/10000")
        // ≥ 1 s → the seconds number (JS `${v}` face — no trailing .0).
        XCTAssertEqual(YiyinExifFormat.exposureTime(1), "1")
        XCTAssertEqual(YiyinExifFormat.exposureTime(2), "2")
        XCTAssertEqual(YiyinExifFormat.exposureTime(30), "30")
        // nil / 0 → "".
        XCTAssertEqual(YiyinExifFormat.exposureTime(nil), "")
        XCTAssertEqual(YiyinExifFormat.exposureTime(0), "")
    }

    func testFNumberJSNumberFace() {
        // `${+record.FNumber}` — integral values print WITHOUT `.0`.
        XCTAssertEqual(YiyinExifFormat.fNumber(2.8), "2.8")
        XCTAssertEqual(YiyinExifFormat.fNumber(8), "8")
        XCTAssertEqual(YiyinExifFormat.fNumber(1.4), "1.4")
        XCTAssertEqual(YiyinExifFormat.fNumber(22), "22")
        XCTAssertEqual(YiyinExifFormat.fNumber(nil), "")
    }

    func testFocalLengthAnd35mmRounds() {
        // base.ts:57-70 Math.round + nil/0 → "" (焦距 AND 等效焦距 share
        // the same method face — the 35mm key differs only at the fill).
        XCTAssertEqual(YiyinExifFormat.focalLength(24.0), "24")
        XCTAssertEqual(YiyinExifFormat.focalLength(24.6), "25")
        XCTAssertEqual(YiyinExifFormat.focalLength(0), "")
        XCTAssertEqual(YiyinExifFormat.focalLength(nil), "")
        XCTAssertEqual(YiyinExifFormat.focalLength(35.4), "35")
    }

    func testISO() {
        XCTAssertEqual(YiyinExifFormat.iso(100), "100")
        XCTAssertEqual(YiyinExifFormat.iso(0), "")
        XCTAssertEqual(YiyinExifFormat.iso(nil), "")
    }

    func testExposureProgramLetters() {
        // Numeric branch (exiftool/index.ts:106-113's parser twin,
        // `formatExifParserInfo` switch): 0→Auto 1→M 2→P 3→A 4→S.
        XCTAssertEqual(YiyinExifFormat.exposureProgram(0), "Auto")
        XCTAssertEqual(YiyinExifFormat.exposureProgram(1), "M")
        XCTAssertEqual(YiyinExifFormat.exposureProgram(2), "P")
        XCTAssertEqual(YiyinExifFormat.exposureProgram(3), "A")
        XCTAssertEqual(YiyinExifFormat.exposureProgram(4), "S")
        // The switch default `break` keeps the number string.
        XCTAssertEqual(YiyinExifFormat.exposureProgram(5), "5")
        XCTAssertEqual(YiyinExifFormat.exposureProgram(8), "8")
        XCTAssertEqual(YiyinExifFormat.exposureProgram(nil), "")
    }

    func testWhiteBalance() {
        XCTAssertEqual(YiyinExifFormat.whiteBalance(0), "Auto")
        XCTAssertEqual(YiyinExifFormat.whiteBalance(1), "手动")
        XCTAssertEqual(YiyinExifFormat.whiteBalance(2), "2")
        XCTAssertEqual(YiyinExifFormat.whiteBalance(nil), "")
    }

    func testMeteringModeNumericContract() {
        // The 08-3 ImageIO-walk contract: EXIF enum 0...6 → yiyin zh.
        XCTAssertEqual(YiyinExifFormat.meteringMode(1), "平均测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(2), "中央重点测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(3), "点测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(5), "评价测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(6), "局部测光")
        // No yiyin entry → the switch-default "".
        XCTAssertEqual(YiyinExifFormat.meteringMode(0), "")
        XCTAssertEqual(YiyinExifFormat.meteringMode(4), "")
        XCTAssertEqual(YiyinExifFormat.meteringMode(nil), "")
    }

    func testMeteringModeStringTableVerbatim() {
        // The exiftool STRING table (index.ts:140-165) — the reference face.
        XCTAssertEqual(YiyinExifFormat.meteringMode(fromExiftoolString: "Evaluative"), "评价测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(fromExiftoolString: "Multi-segment"), "评价测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(fromExiftoolString: "Multi-zone"), "评价测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(fromExiftoolString: "Spot"), "点测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(fromExiftoolString: "Partial"), "局部测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(fromExiftoolString: "Average"), "平均测光")
        XCTAssertEqual(
            YiyinExifFormat.meteringMode(fromExiftoolString: "Center-weighted"), "中央重点测光")
        XCTAssertEqual(
            YiyinExifFormat.meteringMode(fromExiftoolString: "Highlight-weighted"), "斑马测光")
        XCTAssertEqual(YiyinExifFormat.meteringMode(fromExiftoolString: "Unknown"), "")
    }

    func testExposureCompensation() {
        XCTAssertEqual(YiyinExifFormat.exposureCompensation(-1.5), "-1.5")
        XCTAssertEqual(YiyinExifFormat.exposureCompensation(0), "0")
        XCTAssertEqual(YiyinExifFormat.exposureCompensation(nil), "")
    }

    func testFormatDateRules() throws {
        // date.ts engine: y/M/d/h/m/s/q/S runs — zero-pad to run width,
        // y right-aligns by chopping. Fixed zone + fixed wall clock.
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 5
        comps.hour = 9; comps.minute = 7; comps.second = 3
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try XCTUnwrap(calendar.date(from: comps))

        XCTAssertEqual(
            YiyinExifFormat.formatDate("yyyy/MM/dd hh:mm:ss", date, timeZone: zone),
            "2024/01/05 09:07:03")
        // Single-letter runs print unpadded; single 'y' keeps the LAST
        // digit (substring(4 - 1)) — the yiyin/date.ts face.
        XCTAssertEqual(
            YiyinExifFormat.formatDate("y/M/d h:m:s", date, timeZone: zone),
            "4/1/5 9:7:3")
        // 'yy' keeps the LAST two digits (substring(4 - len)).
        XCTAssertEqual(YiyinExifFormat.formatDate("yy", date, timeZone: zone), "24")
        // Quarter (date.ts Math.floor((monthIndex + 3) / 3), 0-based month):
        // January (index 0) → floor(3/3) = 1.
        XCTAssertEqual(YiyinExifFormat.formatDate("q", date, timeZone: zone), "1")
        // October (index 9) → floor(12/3) = 4.
        comps.month = 10
        let october = try XCTUnwrap(calendar.date(from: comps))
        XCTAssertEqual(YiyinExifFormat.formatDate("q", october, timeZone: zone), "4")
        // 'S' milliseconds.
        let coarse = date.timeIntervalSince1970.rounded(.down)
        let exact = Date(timeIntervalSince1970: coarse + 0.456)
        XCTAssertEqual(YiyinExifFormat.formatDate("S", exact, timeZone: zone), "456")
    }

    func testFieldsFillAllFifteenKeys() throws {
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        var comps = DateComponents()
        comps.year = 2023; comps.month = 12; comps.day = 31
        comps.hour = 23; comps.minute = 58; comps.second = 59
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let when = try XCTUnwrap(calendar.date(from: comps))

        let meta = CaptureMetadata(
            cameraMake: "NIKON CORPORATION",
            cameraModel: "NIKON Z 6_2",
            lensModel: "NIKKOR Z 24-70mm f/2.8 S",
            focalLength: 24.0,
            aperture: 2.8,
            shutterSpeed: 1.0 / 500.0,
            iso: 400,
            captureTime: when,
            orientation: 1,
            width: 6000, height: 4000,
            focalLength35mm: 36,
            exposureProgram: 3,
            exposureCompensation: -0.5,
            meteringMode: 3,
            whiteBalance: 0,
            lensMake: "NIKON"
        )
        let fields = YiyinExifFormat.fields(
            from: meta, personalSign: "by Sylvia",
            dateFormat: "yyyy/MM/dd hh:mm:ss", timeZone: zone)
        // compared > 0 (防空转) + the 15-key shape.
        XCTAssertEqual(fields.count, 15)
        XCTAssertEqual(fields[.personalSign], "by Sylvia")
        XCTAssertEqual(fields[.make], "Nikon")
        // Verbatim yiyin: "NIKON Z 6_2".replace("NIKON", "") leaves the
        // leading space, and the roman tail joins — the format layer keeps
        // " ℤ 6 II" VERBATIM; the template engine's slot `.trim()` turns it
        // into "ℤ 6 II" at display (genTextImg slot face).
        XCTAssertEqual(fields[.model], " ℤ 6 II")
        XCTAssertEqual(fields[.lensMake], "NIKON")
        XCTAssertEqual(fields[.lensModel], "NIKKOR Z 24-70mm f/2.8 S")
        XCTAssertEqual(fields[.exposureTime], "1/500")
        XCTAssertEqual(fields[.fNumber], "2.8")
        XCTAssertEqual(fields[.iso], "400")
        XCTAssertEqual(fields[.focalLength], "24")
        XCTAssertEqual(fields[.focalLength35mm], "36")
        XCTAssertEqual(fields[.exposureProgram], "A")
        XCTAssertEqual(fields[.dateTimeOriginal], "2023/12/31 23:58:59")
        XCTAssertEqual(fields[.exposureCompensation], "-0.5")
        XCTAssertEqual(fields[.meteringMode], "点测光")
        XCTAssertEqual(fields[.whiteBalance], "Auto")
        // The 35mm FALLBACK (yiyin `record.FocalLengthIn35mmFormat ||
        // record.FocalLength`).
        var no35 = meta
        no35.focalLength35mm = nil
        XCTAssertEqual(
            YiyinExifFormat.fields(from: no35)[.focalLength35mm], "24")
    }

    func testFieldsFromNilMetaAreAllEmpty() {
        let fields = YiyinExifFormat.fields(from: nil)
        XCTAssertEqual(fields.count, 15)
        XCTAssertTrue(fields.values.allSatisfy { $0.isEmpty })
    }

    func testFieldKeyTableMatchesYiyinDefFields() {
        // def-fields.ts order + zh names (the panel's field-inserter data).
        let keys = YiyinExifField.allCases.map(\.rawValue)
        XCTAssertEqual(
            keys,
            [
                "PersonalSign", "Make", "Model", "LensMake", "LensModel",
                "ExposureTime", "FNumber", "ISO", "FocalLength",
                "FocalLengthIn35mmFormat", "ExposureProgram",
                "DateTimeOriginal", "ExposureCompensation", "MeteringMode",
                "WhiteBalance",
            ])
        XCTAssertEqual(YiyinExifField.make.zhName, "Logo")
        XCTAssertEqual(YiyinExifField.dateTimeOriginal.zhName, "拍摄日期")
    }

    // ── T1: additive-Codable compatibility (old archives) ──

    func testSixFieldsDecodableFromLegacyArchive() throws {
        // A pre-08-2 CaptureMetadata JSON (no new keys) decodes; the new
        // fields surface as nil.
        let legacy =
            #"{"cameraMake":"Canon","cameraModel":"Canon EOS R5","iso":100}"#
        let decoded = try JSONDecoder().decode(CaptureMetadata.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.cameraMake, "Canon")
        XCTAssertNil(decoded.focalLength35mm)
        XCTAssertNil(decoded.exposureProgram)
        XCTAssertNil(decoded.exposureCompensation)
        XCTAssertNil(decoded.meteringMode)
        XCTAssertNil(decoded.whiteBalance)
        XCTAssertNil(decoded.lensMake)
    }

    func testSixFieldsRoundTrip() throws {
        let meta = CaptureMetadata(
            focalLength35mm: 50, exposureProgram: 1, exposureCompensation: 0.3,
            meteringMode: 2, whiteBalance: 1, lensMake: "Canon")
        let data = try JSONEncoder().encode(meta)
        let back = try JSONDecoder().decode(CaptureMetadata.self, from: data)
        XCTAssertEqual(back.focalLength35mm, 50)
        XCTAssertEqual(back.exposureProgram, 1)
        XCTAssertEqual(back.exposureCompensation, 0.3)
        XCTAssertEqual(back.meteringMode, 2)
        XCTAssertEqual(back.whiteBalance, 1)
        XCTAssertEqual(back.lensMake, "Canon")
    }

    // ── T2: brand normalization ──

    func testMakeStripsCorporationAndCapitalizes() {
        // index.ts:34 + base.ts:11-13.
        XCTAssertEqual(YiyinExifFormat.make("NIKON CORPORATION"), "Nikon")
        XCTAssertEqual(YiyinExifFormat.make("Canon"), "Canon")
        XCTAssertEqual(YiyinExifFormat.make("CANON"), "Canon")
        XCTAssertEqual(YiyinExifFormat.make("sony"), "Sony")
        XCTAssertEqual(YiyinExifFormat.make("  SONY "), "Sony")
        XCTAssertEqual(YiyinExifFormat.make("CORPORATION"), "")
        XCTAssertEqual(YiyinExifFormat.make(nil), "")
    }

    func testSonyAlphaSubstitution() {
        // sony.ts:4-6 — the plan's table vector `ILCE-7M4 → α 7m4`.
        XCTAssertEqual(YiyinExifFormat.sonyModel("ILCE-7M4"), "α 7m4")
        XCTAssertEqual(YiyinExifFormat.sonyModel("ILCE-7RM5"), "α 7rm5")
        XCTAssertEqual(YiyinExifFormat.sonyModel("ILCE-1"), "α 1")
        // Dispatched through the brand table too.
        XCTAssertEqual(YiyinExifFormat.model("ILCE-7M4", make: "SONY"), "α 7m4")
        // A Sony body without the ILCE prefix: base lowercase (sony.ts
        // replaces only the prefix).
        XCTAssertEqual(YiyinExifFormat.model("DSC-RX1", make: "SONY"), "dsc-rx1")
    }

    func testNikonZAndRomanNumerals() {
        // nikon.ts:6-20 + the plan's table (`Z_6_II→ℤ 6 II`, `Z 30→ℤ 30`).
        XCTAssertEqual(YiyinExifFormat.nikonModel("Z_6_II", make: "NIKON"), "ℤ 6 II")
        XCTAssertEqual(YiyinExifFormat.nikonModel("Z 30", make: "NIKON"), "ℤ 30")
        XCTAssertEqual(YiyinExifFormat.nikonModel("Z 8", make: "NIKON CORPORATION"), "ℤ 8")
        XCTAssertEqual(YiyinExifFormat.nikonModel("Zf", make: "NIKON"), "ℤf")
        // No underscore → the replaced string as-is (nikon.ts has NO
        // lowercase step — base.ts's Model() lowercase does not apply).
        XCTAssertEqual(YiyinExifFormat.nikonModel("D850", make: "NIKON"), "D850")
        // A non-numeric tail appends verbatim (the nikon.ts `else` join).
        XCTAssertEqual(YiyinExifFormat.nikonModel("Z_fc", make: "NIKON"), "ℤ fc")
        // Dispatched through the brand table (CORPORATION-stripped make).
        XCTAssertEqual(YiyinExifFormat.model("Z 9", make: "NIKON CORPORATION"), "ℤ 9")
        // VERBATIM quirk: when the Model repeats the make as a DIFFERENT
        // string ("NIKON Z 6_2" vs make "NIKON CORPORATION"), the prefix
        // strip is a no-op — yiyin shows "NIKON ℤ 6 II" (see the fill
        // test). Pinned here so the quirk is a decision, not an accident.
        XCTAssertEqual(
            YiyinExifFormat.nikonModel("NIKON Z 6_2", make: "NIKON CORPORATION"),
            " ℤ 6 II")
    }

    func testToRomanTable() {
        // util.ts:3-30 subtractive table.
        XCTAssertEqual(YiyinExifFormat.toRoman(1), "I")
        XCTAssertEqual(YiyinExifFormat.toRoman(2), "II")
        XCTAssertEqual(YiyinExifFormat.toRoman(4), "IV")
        XCTAssertEqual(YiyinExifFormat.toRoman(5), "V")
        XCTAssertEqual(YiyinExifFormat.toRoman(6), "VI")
        XCTAssertEqual(YiyinExifFormat.toRoman(9), "IX")
        XCTAssertEqual(YiyinExifFormat.toRoman(10), "X")
        XCTAssertEqual(YiyinExifFormat.toRoman(14), "XIV")
        XCTAssertEqual(YiyinExifFormat.toRoman(40), "XL")
        XCTAssertEqual(YiyinExifFormat.toRoman(90), "XC")
        XCTAssertEqual(YiyinExifFormat.toRoman(400), "CD")
        XCTAssertEqual(YiyinExifFormat.toRoman(900), "CM")
        XCTAssertEqual(YiyinExifFormat.toRoman(1994), "MCMXCIV")
        XCTAssertEqual(YiyinExifFormat.toRoman(2024), "MMXXIV")
        XCTAssertEqual(YiyinExifFormat.toRoman(0), "")
        XCTAssertEqual(YiyinExifFormat.toRoman(-3), "")
    }

    func testBaseModelLowercaseForOtherBrands() {
        // base.ts:19-23 — Canon/Fujifilm/Leica/… plain lowercase.
        XCTAssertEqual(YiyinExifFormat.model("Canon EOS R5", make: "Canon"), "canon eos r5")
        XCTAssertEqual(YiyinExifFormat.model("X-T5", make: "FUJIFILM"), "x-t5")
        XCTAssertEqual(YiyinExifFormat.model("M11", make: "Leica"), "m11")
        XCTAssertEqual(YiyinExifFormat.model(nil, make: "Canon"), "")
    }

    func testCharToNumberCharPerCodePoint() {
        // util.ts:32-54 — every ASCII letter maps into the 0x1D63C block
        // (uppercase at the base, lowercase at base+26); non-letters pass.
        let start = 0x1D63C
        for offset in 0..<26 {
            let upper = UnicodeScalar(UInt32(65 + offset))!
            let lower = UnicodeScalar(UInt32(97 + offset))!
            let gotUpper = Array(YiyinExifFormat.charToNumberChar(String(upper)).unicodeScalars)
            let gotLower = Array(YiyinExifFormat.charToNumberChar(String(lower)).unicodeScalars)
            XCTAssertEqual(gotUpper.count, 1)
            XCTAssertEqual(gotLower.count, 1)
            XCTAssertEqual(
                gotUpper[0].value, UInt32(start + offset),
                "uppercase \(upper) → base + \(offset)")
            XCTAssertEqual(
                gotLower[0].value, UInt32(start + 26 + offset),
                "lowercase \(lower) → base + 26 + \(offset)")
        }
        // Digits / symbols / non-ASCII pass through untouched.
        XCTAssertEqual(YiyinExifFormat.charToNumberChar("7-30"), "7-30")
        XCTAssertEqual(YiyinExifFormat.charToNumberChar("α"), "α")
        XCTAssertEqual(YiyinExifFormat.charToNumberChar(""), "")
        // Mixed word (the shape the model-map DEF filter would produce).
        XCTAssertEqual(
            Array(YiyinExifFormat.charToNumberChar("aB9").unicodeScalars).map(\.value),
            [UInt32(start + 26 + 0), UInt32(start + 1), 57])
    }

    func testModelMapFilterSurfaceParity() {
        // web/util/model-map.ts faces (dead code in yiyin v1.7.1 — ported
        // for parity, NOT wired into the display chain, D-08-2-2).
        XCTAssertEqual(
            YiyinExifFormat.modelMapFilter(brand: "INIT", make: "NIKON CORPORATION"), "NIKON ")
        let defMake = YiyinExifFormat.modelMapFilter(brand: "DEF", make: "Canon")
        // s[0] + s.slice(1).lowercase() through charToNumberChar.
        let expected = YiyinExifFormat.charToNumberChar("C" + "anon")
        XCTAssertEqual(defMake, expected)
        XCTAssertEqual(YiyinExifFormat.modelMapFilter(brand: "SONY", model: "ILCE-7M4"), "α 7m4")
        XCTAssertEqual(YiyinExifFormat.modelMapFilter(brand: "NIKON", model: "Z_6_II"), "ℤ 6 II")
    }

    func testJsNumberFace() {
        XCTAssertEqual(YiyinExifFormat.jsNumber(8), "8")
        XCTAssertEqual(YiyinExifFormat.jsNumber(2.8), "2.8")
        XCTAssertEqual(YiyinExifFormat.jsNumber(-0.5), "-0.5")
        XCTAssertEqual(YiyinExifFormat.jsNumber(0), "0")
    }
}
