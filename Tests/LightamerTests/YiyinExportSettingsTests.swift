import LightamerCore
import Metal
@testable import LightamerIOP
import XCTest

/// Plan 08-3 T3 (YIYIN-08) — the export configuration model, the layout's
/// resolution independence, and the Phase 12 preset interface face.
///
/// Sections:
/// 1. `YiyinExportSettings` validation boundaries + the pure EXP-03
///    target-size math (the APPLICATION leg itself is Phase 11 —
///    D-08-CONTEXT-7; the model carries the spec).
/// 2. The layout-record resolution independence: PREVIEW(2560-derived) vs
///    a 2× full-res plane produce EQUAL normalized joint records
///    (真比较, compared > 0).
/// 3. The preset capture/apply equivalence: serialize the two yiyin
///    instances' paramsData (the instances-subset capture a Phase 12
///    `.lightamer-preset` performs — ZERO new API), re-apply into fresh
///    instances, render both chains — BYTE-EQUIVALENT output.
final class YiyinExportSettingsTests: XCTestCase {

    // MARK: - 1. validation + target-size math

    func testValidationBoundaries() throws {
        // Defaults validate (original / 300dpi).
        try YiyinExportSettings().validate()

        // original ignores any pixel notion — always valid with valid dpi.
        try YiyinExportSettings(mode: .original, dpi: 1).validate()
        try YiyinExportSettings(mode: .original, dpi: 2400).validate()
        XCTAssertThrowsError(try YiyinExportSettings(mode: .original, dpi: 0).validate())
        XCTAssertThrowsError(try YiyinExportSettings(mode: .original, dpi: 2401).validate())
        XCTAssertThrowsError(try YiyinExportSettings(mode: .original, dpi: -300).validate())

        // Pixel fit: ≥ 1, ≤ the 100_000 cap (D-08-3-T3-1).
        try YiyinExportSettings(mode: .longEdge(px: 1), dpi: 300).validate()
        try YiyinExportSettings(
            mode: .longEdge(px: YiyinExportSettings.maxTargetPixels), dpi: 300
        ).validate()
        XCTAssertThrowsError(try YiyinExportSettings(mode: .longEdge(px: 0), dpi: 300).validate())
        XCTAssertThrowsError(try YiyinExportSettings(mode: .shortEdge(px: 0), dpi: 300).validate())
        XCTAssertThrowsError(
            try YiyinExportSettings(
                mode: .longEdge(px: YiyinExportSettings.maxTargetPixels + 1), dpi: 300
            ).validate())
        XCTAssertThrowsError(try YiyinExportSettings(mode: .longEdge(px: -4096), dpi: 300).validate())
    }

    func testTargetSizePureMath() throws {
        // original = the source verbatim.
        let original = YiyinExportSettings(mode: .original, dpi: 300)
        XCTAssertEqual(original.targetSize(canvasWidth: 6000, canvasHeight: 4000).width, 6000)
        XCTAssertEqual(original.targetSize(canvasWidth: 6000, canvasHeight: 4000).height, 4000)

        // Long-edge fit preserves aspect (6000×4000 → 2000×1333, floor).
        let long = YiyinExportSettings(mode: .longEdge(px: 2000), dpi: 300)
        XCTAssertEqual(long.targetSize(canvasWidth: 6000, canvasHeight: 4000).width, 2000)
        XCTAssertEqual(long.targetSize(canvasWidth: 6000, canvasHeight: 4000).height, 1333)
        // Portrait source: the LONG edge is the height (4000×6000 → 1333×2000).
        XCTAssertEqual(long.targetSize(canvasWidth: 4000, canvasHeight: 6000).width, 1333)
        XCTAssertEqual(long.targetSize(canvasWidth: 4000, canvasHeight: 6000).height, 2000)

        // Short-edge fit (6000×4000 → short 1000 → 1500×1000).
        let short = YiyinExportSettings(mode: .shortEdge(px: 1000), dpi: 300)
        XCTAssertEqual(short.targetSize(canvasWidth: 6000, canvasHeight: 4000).width, 1500)
        XCTAssertEqual(short.targetSize(canvasWidth: 6000, canvasHeight: 4000).height, 1000)

        // NEVER upscale: a fit above the source dims clamps to the source.
        let huge = YiyinExportSettings(mode: .longEdge(px: 99999), dpi: 300)
        XCTAssertEqual(huge.targetSize(canvasWidth: 6000, canvasHeight: 4000).width, 6000)
        XCTAssertEqual(huge.targetSize(canvasWidth: 6000, canvasHeight: 4000).height, 4000)

        // The cap clamps an oversized px INSIDE the math too (defense in
        // depth — validate() rejects first); the never-upscale guard still
        // dominates: a 100_000-target on a 4000-short source returns the
        // source dims.
        XCTAssertEqual(
            YiyinExportSettings(mode: .shortEdge(px: 200_000), dpi: 300)
                .targetSize(canvasWidth: 6000, canvasHeight: 4000).height,
            4000, "never upscale dominates the clamp")
    }

    func testCodableRoundTripAndOrthogonality() throws {
        let settings = YiyinExportSettings(mode: .longEdge(px: 4096), dpi: 144)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(YiyinExportSettings.self, from: data)
        XCTAssertEqual(decoded, settings, "Codable round-trip is lossless")

        // The mode enum round-trips all three faces.
        for mode in [YiyinExportSettings.OutputMode.original, .longEdge(px: 1), .shortEdge(px: 2)] {
            let re = try JSONDecoder().decode(
                YiyinExportSettings.self,
                from: JSONEncoder().encode(YiyinExportSettings(mode: mode, dpi: 300)))
            XCTAssertEqual(re.mode, mode)
        }

        // ORTHOGONALITY (EXP-07): the settings are NOT module params —
        // mutating a settings value cannot move a yiyin instance's
        // paramsHash (the D-H4 atom digests paramsData only).
        var record = ModuleInstance(
            module: BordersModule.self, params: BordersModule.Params(
                mode: .solid(color: "#101010"), mainImageWidthRate: 85))
        let hashBefore = record.paramsHash
        _ = YiyinExportSettings(mode: .shortEdge(px: 2048), dpi: 72)
        XCTAssertEqual(record.paramsHash, hashBefore,
                       "export settings are orthogonal to module params")
        try record.setParams(BordersModule.Params(
            mode: .solid(color: "#101010"), mainImageWidthRate: 85), as: BordersModule.self)
        XCTAssertEqual(record.paramsHash, hashBefore)
    }

    // MARK: - 1b. four-mode resolution math (M2-9-01, KD-1 goldens)

    /// The four-mode goldens: original passthrough, longEdge/bounds
    /// fit-inside, physical pixel translation (unit × DPI) — the resolve
    /// face AND its targetSize delegation agree on every vector.
    func testFourModeResolutionGoldens() throws {
        let w = 6000, h = 4000

        // original: source verbatim, DPI passes through clamped.
        let original = YiyinExportSettings(mode: .original, dpi: 300)
        let originalResult = original.resolveExportResolution(canvasWidth: w, canvasHeight: h)
        XCTAssertTrue(originalResult.success)
        XCTAssertEqual(originalResult.width, 6000)
        XCTAssertEqual(originalResult.height, 4000)
        XCTAssertEqual(originalResult.dpi, 300)
        XCTAssertNil(originalResult.message)
        XCTAssertEqual(original.targetSize(canvasWidth: w, canvasHeight: h).width, 6000)

        // longEdge 2000 → 2000×1333 (llround of 4000/3).
        let long = YiyinExportSettings(mode: .longEdge(px: 2000), dpi: 300)
        let longResult = long.resolveExportResolution(canvasWidth: w, canvasHeight: h)
        XCTAssertTrue(longResult.success)
        XCTAssertEqual(longResult.width, 2000)
        XCTAssertEqual(longResult.height, 1333)

        // bounds 3000×1500 → the HEIGHT binds: min(3000/6000, 1500/4000) =
        // min(0.5, 0.375) = 0.375 → 2250×1500 (not 3000×1500 — the aspect
        // box keeps BOTH constraints).
        let bounds = YiyinExportSettings(mode: .bounds(w: 3000, h: 1500), dpi: 300)
        let boundsResult = bounds.resolveExportResolution(canvasWidth: w, canvasHeight: h)
        XCTAssertTrue(boundsResult.success)
        XCTAssertEqual(boundsResult.width, 2250)
        XCTAssertEqual(boundsResult.height, 1500)

        // physical 6in×4in @ 300dpi on a 6000×4000 source → 1800×1200 (the
        // pixel translation is physical/unitsPerInch × dpi; no upscale).
        let physical = YiyinExportSettings(
            mode: .physical(width: 6, height: 4, unit: .inches, dpi: 300), dpi: 300)
        let physicalResult = physical.resolveExportResolution(canvasWidth: w, canvasHeight: h)
        XCTAssertTrue(physicalResult.success)
        XCTAssertEqual(physicalResult.width, 1800)
        XCTAssertEqual(physicalResult.height, 1200)
        XCTAssertEqual(physicalResult.dpi, 300)

        // Unit translation: 152.4mm = 6in; 101.6mm = 4in — same goldens.
        let physicalMM = YiyinExportSettings(
            mode: .physical(width: 152.4, height: 101.6, unit: .millimeters, dpi: 300), dpi: 300)
        let mmResult = physicalMM.resolveExportResolution(canvasWidth: w, canvasHeight: h)
        XCTAssertTrue(mmResult.success)
        XCTAssertEqual(mmResult.width, 1800)
        XCTAssertEqual(mmResult.height, 1200)

        // 2.54cm = 1in: 5.08×5.08cm @ 300dpi on a 3000×3000 source → 600×600.
        let physicalCM = YiyinExportSettings(
            mode: .physical(width: 5.08, height: 5.08, unit: .centimeters, dpi: 300), dpi: 300)
        let cmResult = physicalCM.resolveExportResolution(canvasWidth: 3000, canvasHeight: 3000)
        XCTAssertTrue(cmResult.success)
        XCTAssertEqual(cmResult.width, 600)
        XCTAssertEqual(cmResult.height, 600)
    }

    /// The upscale clamp: default settings NEVER grow past the source (the
    /// historical clamp, Alcedo `allow_upscale_=false`); `allowUpscale`
    /// releases it mode-by-mode.
    func testUpscaleClampAndAllowUpscaleSwitch() throws {
        let w = 6000, h = 4000

        // Default (allowUpscale=false): oversized targets clamp to source.
        let clampedLong = YiyinExportSettings(mode: .longEdge(px: 12_000), dpi: 300)
        let clampedResult = clampedLong.resolveExportResolution(canvasWidth: w, canvasHeight: h)
        XCTAssertEqual(clampedResult.width, 6000)
        XCTAssertEqual(clampedResult.height, 4000)

        let clampedBounds = YiyinExportSettings(mode: .bounds(w: 12_000, h: 8000), dpi: 300)
        let clampedBoundsResult = clampedBounds.resolveExportResolution(
            canvasWidth: w, canvasHeight: h)
        XCTAssertEqual(clampedBoundsResult.width, 6000)
        XCTAssertEqual(clampedBoundsResult.height, 4000)

        // allowUpscale=true: the fit grows with aspect preserved.
        let upscaledLong = YiyinExportSettings(
            mode: .longEdge(px: 12_000), dpi: 300, allowUpscale: true)
        let upscaledResult = upscaledLong.resolveExportResolution(canvasWidth: w, canvasHeight: h)
        XCTAssertTrue(upscaledResult.success)
        XCTAssertEqual(upscaledResult.width, 12_000)
        XCTAssertEqual(upscaledResult.height, 8000)

        let upscaledBounds = YiyinExportSettings(
            mode: .bounds(w: 12_000, h: 8000), dpi: 300, allowUpscale: true)
        let upscaledBoundsResult = upscaledBounds.resolveExportResolution(
            canvasWidth: w, canvasHeight: h)
        XCTAssertEqual(upscaledBoundsResult.width, 12_000)
        XCTAssertEqual(upscaledBoundsResult.height, 8000)

        // Physical mode honors the switch too: 24in wide @ 300dpi = 7200px.
        let upscaledPhysical = YiyinExportSettings(
            mode: .physical(width: 24, height: 16, unit: .inches, dpi: 300),
            dpi: 300, allowUpscale: true)
        let physicalResult = upscaledPhysical.resolveExportResolution(
            canvasWidth: w, canvasHeight: h)
        XCTAssertEqual(physicalResult.width, 7200)
        XCTAssertEqual(physicalResult.height, 4800)
    }

    /// The maximumEdgePixels tail applies to EVERY mode and corrects the
    /// DPI by the width ratio (Alcedo cpp:74-78 — physical print size
    /// conservation). Goldens pinned per D-M2-9-CONTEXT-6.
    func testMaximumEdgeCapTailWithDPICorrection() throws {
        // The plan anchor: 3000×2000 source, physical 10×(20/3)in @ 300dpi
        // (→ 3000×2000 px), cap 2000 → width ratio 2/3 → DPI 300→200.
        let anchor = YiyinExportSettings(
            mode: .physical(width: 10, height: 20.0 / 3.0, unit: .inches, dpi: 300),
            dpi: 300, maximumEdgePixels: 2000)
        let anchorResult = anchor.resolveExportResolution(canvasWidth: 3000, canvasHeight: 2000)
        XCTAssertTrue(anchorResult.success)
        XCTAssertEqual(anchorResult.width, 2000)
        XCTAssertEqual(anchorResult.height, 1333)
        XCTAssertEqual(anchorResult.dpi, 200, "DPI follows the width ratio (300 × 2/3)")

        // Clean-integer variant: 6000×4000, physical 6×4in @ 300 → 1800×1200,
        // cap 1200 → ratio 1200/1800 = 2/3 → 1200×800 @ 200dpi.
        let clean = YiyinExportSettings(
            mode: .physical(width: 6, height: 4, unit: .inches, dpi: 300),
            dpi: 300, maximumEdgePixels: 1200)
        let cleanResult = clean.resolveExportResolution(canvasWidth: 6000, canvasHeight: 4000)
        XCTAssertEqual(cleanResult.width, 1200)
        XCTAssertEqual(cleanResult.height, 800)
        XCTAssertEqual(cleanResult.dpi, 200)

        // The cap tail reaches EVERY mode — including original and longEdge.
        let originalCapped = YiyinExportSettings(mode: .original, dpi: 300, maximumEdgePixels: 3000)
        let originalResult = originalCapped.resolveExportResolution(
            canvasWidth: 6000, canvasHeight: 4000)
        XCTAssertEqual(originalResult.width, 3000)
        XCTAssertEqual(originalResult.height, 2000)
        // longEdge carries the settings DPI → corrected 300 × 3000/6000 = 150.
        let longCapped = YiyinExportSettings(
            mode: .longEdge(px: 6000), dpi: 300, maximumEdgePixels: 3000)
        let longResult = longCapped.resolveExportResolution(canvasWidth: 6000, canvasHeight: 4000)
        XCTAssertEqual(longResult.width, 3000)
        XCTAssertEqual(longResult.dpi, 150)

        // Cap off (0) and a cap above the max edge are both no-ops.
        let capOff = YiyinExportSettings(mode: .original, dpi: 300)
        XCTAssertEqual(capOff.resolveExportResolution(canvasWidth: 60, canvasHeight: 40).width, 60)
        let capHigh = YiyinExportSettings(mode: .original, dpi: 300, maximumEdgePixels: 10_000)
        XCTAssertEqual(
            capHigh.resolveExportResolution(canvasWidth: 60, canvasHeight: 40).height, 40)
    }

    /// D-M2-9-CONTEXT-6: a physical mode with a missing/non-positive DPI is
    /// a typed `success=false` failure (message set, nothing throws), and
    /// `validate()` rejects it as `.invalidParameter`.
    func testPhysicalModeRequiresPositiveDpi() throws {
        for badDpi in [0, -1, -300] {
            let settings = YiyinExportSettings(
                mode: .physical(width: 6, height: 4, unit: .inches, dpi: badDpi), dpi: 300)
            let result = settings.resolveExportResolution(canvasWidth: 6000, canvasHeight: 4000)
            XCTAssertFalse(result.success, "dpi \(badDpi) must fail typed")
            XCTAssertNotNil(result.message, "typed failure carries a message")
            XCTAssertFalse(result.message!.isEmpty)
            XCTAssertThrowsError(try settings.validate())
        }
        // The settings-level DPI stays validated on its own domain too.
        XCTAssertThrowsError(
            try YiyinExportSettings(
                mode: .physical(width: 6, height: 4, unit: .inches, dpi: 300), dpi: 0
            ).validate())
        // The physical DPI inside the case is validated against dpiRange.
        XCTAssertThrowsError(
            try YiyinExportSettings(
                mode: .physical(width: 6, height: 4, unit: .inches, dpi: 0), dpi: 300
            ).validate())
    }

    /// The four-mode validation domains (KD: bounds 像素域 / physical 尺寸域
    /// 0.01...100_000 + dpi 域 / cap 非负).
    func testFourModeValidationDomains() throws {
        // bounds: both axes ≥ 1 and ≤ 100_000.
        try YiyinExportSettings(mode: .bounds(w: 1, h: 1), dpi: 300).validate()
        try YiyinExportSettings(
            mode: .bounds(w: YiyinExportSettings.maxTargetPixels, h: 1), dpi: 300
        ).validate()
        XCTAssertThrowsError(try YiyinExportSettings(mode: .bounds(w: 0, h: 10), dpi: 300).validate())
        XCTAssertThrowsError(try YiyinExportSettings(mode: .bounds(w: 10, h: -1), dpi: 300).validate())
        XCTAssertThrowsError(
            try YiyinExportSettings(
                mode: .bounds(w: YiyinExportSettings.maxTargetPixels + 1, h: 1), dpi: 300
            ).validate())

        // physical: both axes inside 0.01...100_000, dpi inside 1...2400.
        try YiyinExportSettings(
            mode: .physical(width: 0.01, height: 100_000, unit: .inches, dpi: 2400), dpi: 300
        ).validate()
        XCTAssertThrowsError(
            try YiyinExportSettings(
                mode: .physical(width: 0.009, height: 4, unit: .inches, dpi: 300), dpi: 300
            ).validate())
        XCTAssertThrowsError(
            try YiyinExportSettings(
                mode: .physical(width: 6, height: 100_000.1, unit: .inches, dpi: 300), dpi: 300
            ).validate())

        // The cap: 0 = off, positive = on, negative = invalid.
        try YiyinExportSettings(mode: .original, dpi: 300, maximumEdgePixels: 0).validate()
        try YiyinExportSettings(mode: .original, dpi: 300, maximumEdgePixels: 8192).validate()
        XCTAssertThrowsError(
            try YiyinExportSettings(mode: .original, dpi: 300, maximumEdgePixels: -1).validate())
    }

    /// KD-2: legacy payloads (three-mode JSON without the new keys) decode
    /// with the NEW fields at their defaults — the synthesized decoder
    /// would have thrown here.
    func testLegacyPayloadDecodeCompatibility() throws {
        // A hand-written v1 literal (mode + dpi only — exactly what
        // JSONEncoder produced before M2-9-01).
        let legacyJSON = #"{"mode":{"longEdge":{"px":4096}},"dpi":144}"#
        let decoded = try JSONDecoder().decode(
            YiyinExportSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.mode, .longEdge(px: 4096))
        XCTAssertEqual(decoded.dpi, 144)
        XCTAssertFalse(decoded.allowUpscale, "legacy payload decodes to the default clamp")
        XCTAssertEqual(decoded.maximumEdgePixels, 0, "legacy payload decodes with the cap off")
        XCTAssertEqual(decoded, YiyinExportSettings(mode: .longEdge(px: 4096), dpi: 144))

        // original mode literal too (case-name keyed, empty payload).
        let legacyOriginal = #"{"mode":{"original":{}},"dpi":300}"#
        let decodedOriginal = try JSONDecoder().decode(
            YiyinExportSettings.self, from: Data(legacyOriginal.utf8))
        XCTAssertEqual(decodedOriginal, YiyinExportSettings())

        // The new cases round-trip losslessly (case-name keyed containers).
        let newModes: [YiyinExportSettings.OutputMode] = [
            .bounds(w: 2048, h: 1536),
            .physical(width: 210, height: 297, unit: .millimeters, dpi: 300),
        ]
        for mode in newModes {
            let settings = YiyinExportSettings(mode: mode, dpi: 300)
            let data = try JSONEncoder().encode(settings)
            let roundTripped = try JSONDecoder().decode(YiyinExportSettings.self, from: data)
            XCTAssertEqual(roundTripped, settings, "\(mode)")
            XCTAssertEqual(roundTripped.allowUpscale, false)
            XCTAssertEqual(roundTripped.maximumEdgePixels, 0)
        }

        // New fields ride the round-trip when set.
        var withNewFields = YiyinExportSettings(mode: .original, dpi: 300)
        withNewFields.allowUpscale = true
        withNewFields.maximumEdgePixels = 8192
        let data = try JSONEncoder().encode(withNewFields)
        let roundTripped = try JSONDecoder().decode(YiyinExportSettings.self, from: data)
        XCTAssertEqual(roundTripped, withNewFields)
    }

    // MARK: - 2. layout resolution independence

    /// PREVIEW(2560-derived) vs 2× full-res: the SAME borders params +
    /// proportionally scaled row metrics produce EQUAL NORMALIZED joint
    /// records (真比较 — every record field compared, normalized by the
    /// canvas dims; the integer ceil/round band allows ~1-2px slack at the
    /// smaller scale).
    func testJointLayoutRecordResolutionIndependent() {
        let borders = BordersModule.Params(
            mode: .solid(color: "#101010"),
            mainImageWidthRate: 90,
            miniTopBottomMargin: 2,
            aspectRatio: BordersModule.AspectRatio(w: 3, h: 2),
            cornerRadius: 2.1,
            shadow: 6,
            adaptiveBackdrop: true)
        let rows = [
            YiyinLayout.TextRowMetrics(width: 1200, height: 90),
            YiyinLayout.TextRowMetrics(width: 900, height: 60),
        ]

        // PREVIEW face: the 2560-bucket plane of a 4272×2848 sensor image
        // (3:2) → 2560×1707; FULL face: the full plane. Row metrics scale
        // with bgHeight (the renderer's own proportionality — its absolute
        // 30px pad quirk is separately nailed in YiyinWatermarkTests).
        let smallSize = SIMD2(2560, 1707)
        let largeSize = SIMD2(5120, 3414)
        let largeRows = rows.map {
            YiyinLayout.TextRowMetrics(
                width: $0.width * 2, height: $0.height * 2)
        }
        let small = YiyinLayout.layout(imageSize: smallSize, borders: borders, rows: rows)
        let large = YiyinLayout.layout(imageSize: largeSize, borders: borders, rows: largeRows)

        // Normalize by the source image size (the layout input) and
        // compare — the resolution-independent face.
        func normalized(_ r: YiyinLayoutRecord, size: SIMD2<Int>) -> (Double, Double, Double, Double, Double, [(Double, Double, Double, Double)]) {
            let sw = Double(size.x)
            let sh = Double(size.y)
            let cw = Double(r.canvasSize.x)
            let ch = Double(r.canvasSize.y)
            return (
                Double(r.canvasSize.x) / sw,
                Double(r.canvasSize.y) / sh,
                Double(r.mainImageOrigin.x) / cw,
                Double(r.mainImageOrigin.y) / ch,
                r.textBottomOffsetPx / ch,
                r.rows.map { row in
                    (Double(row.left) / cw, Double(row.top) / ch,
                     Double(row.width) / cw, Double(row.height) / ch)
                }
            )
        }

        let nSmall = normalized(small, size: smallSize)
        let nLarge = normalized(large, size: largeSize)
        var compared = 0
        let tol = 2.0 / Double(smallSize.y) // ~2 small-scale px of rounding band

        XCTAssertLessThan(abs(nSmall.0 - nLarge.0), tol, "canvas width fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.1 - nLarge.1), tol, "canvas height fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.2 - nLarge.2), tol, "main origin x fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.3 - nLarge.3), tol, "main origin y fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.4 - nLarge.4), tol, "text offset fraction")
        compared += 1
        XCTAssertEqual(nSmall.5.count, nLarge.5.count)
        for (s, l) in zip(nSmall.5, nLarge.5) {
            XCTAssertLessThan(abs(s.0 - l.0), tol, "row left fraction")
            XCTAssertLessThan(abs(s.1 - l.1), tol, "row top fraction")
            XCTAssertLessThan(abs(s.2 - l.2), tol, "row width fraction")
            XCTAssertLessThan(abs(s.3 - l.3), tol, "row height fraction")
            compared += 4
        }
        XCTAssertGreaterThan(compared, 0, "防空转: normalized fields compared")

        // The rows reserved band: the small-scale content height fraction
        // matches too (the rows leg drove it).
        let contentFractionS = Double(small.contentHeight) / Double(smallSize.y)
        let contentFractionL = Double(large.contentHeight) / Double(largeSize.y)
        XCTAssertLessThan(abs(contentFractionS - contentFractionL), tol)
        compared += 1
        XCTAssertGreaterThan(compared, 6, "防空转: content fraction compared")
    }

    // MARK: - 3. preset capture/apply render equivalence

    /// Capture = the two yiyin instances' `paramsData` bytes (the
    /// instances-subset a Phase 12 `.lightamer-preset` stores — ZERO new
    /// API); apply = fresh records decode the SAME bytes; render = the
    /// two chains go through the real pipe with the joint context wired —
    /// outputs are BYTE-EQUIVALENT (and the box-level joint wiring itself
    /// is proven: the borders canvas reserves the rows band).
    func testPresetCaptureApplyRendersByteEquivalent() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let image = gradientImage(width: 96, height: 64)

        // The live face: non-trivial borders (canvas growth + radius +
        // shadow) + a literal watermark row, anchored center.
        var bordersParams = BordersModule.Params.neutralSeed
        bordersParams.mode = .solid(color: "#101010")
        bordersParams.mainImageWidthRate = 85
        bordersParams.cornerRadius = 3.0
        bordersParams.shadow = 5.0
        var watermarkParams = WatermarkModule.Params.neutralSeed
        watermarkParams.templates = [YiyinTemplate(
            key: "row", name: "n", pattern: "LIGHTAMER PRESET", use: true,
            font: YiyinFont(sizePercent: 4, color: "#ffffff"))]
        watermarkParams.fields = []
        watermarkParams.anchor = .center
        let bordersRecord = ModuleInstance(
            module: BordersModule.self, params: bordersParams)
        let watermarkRecord = ModuleInstance(
            module: WatermarkModule.self, params: watermarkParams)

        // CAPTURE: the params bytes (what a preset stores).
        let captured = ["borders": bordersRecord.paramsData,
                        "watermark": watermarkRecord.paramsData]

        // APPLY: fresh instances decode the captured bytes (a fresh
        // session/preset application).
        var appliedBorders = ModuleInstance(
            module: BordersModule.self, params: .neutralSeed)
        try appliedBorders.setParams(
            try JSONDecoder().decode(
                BordersModule.Params.self, from: captured["borders"]!),
            as: BordersModule.self)
        var appliedWatermark = ModuleInstance(
            module: WatermarkModule.self, params: .neutralSeed)
        try appliedWatermark.setParams(
            try JSONDecoder().decode(
                WatermarkModule.Params.self, from: captured["watermark"]!),
            as: WatermarkModule.self)
        XCTAssertEqual(appliedBorders.paramsData, bordersRecord.paramsData)
        XCTAssertEqual(appliedWatermark.paramsData, watermarkRecord.paramsData)

        // RENDER both chains (colorout → borders → watermark; no gamma —
        // the float32 sampling shape) with the same joint wiring the
        // coordinator performs (D-08-3-T3-2).
        let chainA = try await yiyinChain(
            borders: bordersRecord, watermark: watermarkRecord,
            image: image, metal: metal)
        let chainB = try await yiyinChain(
            borders: appliedBorders, watermark: appliedWatermark,
            image: image, metal: metal)
        let bytesA = readFloats(chainA, metal: metal)
        let bytesB = readFloats(chainB, metal: metal)
        XCTAssertEqual(bytesA.count, bytesB.count)
        var compared = 0
        var mismatched = 0
        for (x, y) in zip(bytesA, bytesB) {
            compared += 1
            if x != y { mismatched += 1 }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: pixels compared")
        XCTAssertEqual(mismatched, 0,
                       "preset capture → apply renders byte-equivalent (\(compared) floats)")

        // The applied chain's canvas actually grew (the reserve face —
        // the joint wiring landed): 85% rate → canvas wider than 96.
        XCTAssertGreaterThan(chainB.width, 96, "the borders canvas grew (rate 85)")
    }

    // MARK: - harness

    private func yiyinChain(
        borders: ModuleInstance, watermark: ModuleInstance,
        image: DecodedImage, metal: MetalContext
    ) async throws -> (any MTLTexture) {
        let colorout = ModuleBox(module: ColorOutModule())
        var coParams = ColorOutModule.Params()
        coParams.outputProfile = .sRGB
        colorout.setParams(coParams)
        let bordersBox = ModuleBox(module: BordersModule(), instanceID: borders.id)
        try bordersBox.apply(borders)
        let watermarkBox = ModuleBox(module: WatermarkModule(), instanceID: watermark.id)
        try watermarkBox.apply(watermark)

        // The coordinator's per-run wiring (D-08-3-T3-2 mirrored): EXIF +
        // logo faces + joint context + the record → borders override.
        watermarkBox.module.captureExif = image.capture
        let mainSize = SIMD2(Int(image.ciImage.extent.width),
                             Int(image.ciImage.extent.height))
        let borderParams = try? borders.params(of: BordersModule.self)
        watermarkBox.module.jointContext = WatermarkModule.JointContext(
            mainImageSize: mainSize, bordersParams: borderParams)
        let record = watermarkBox.module.makeJointLayoutRecord(
            mainImageSize: mainSize, bordersParams: borderParams)
        bordersBox.module.jointLayoutOverride = record

        let chain = [colorout as any ModuleBoxing, bordersBox as any ModuleBoxing,
                     watermarkBox as any ModuleBoxing]
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        return texture
    }

    private func readFloats(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return floats
    }

    private func gradientImage(width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i + 0] = Float(x) / Float(max(width - 1, 1))
                rgba[i + 1] = Float(y) / Float(max(height - 1, 1))
                rgba[i + 2] = 0.25
                rgba[i + 3] = 1.0
            }
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }
}
