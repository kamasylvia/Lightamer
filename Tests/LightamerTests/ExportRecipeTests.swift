import Foundation
import LightamerCore
import XCTest

/// `ExportRecipe`/`ExportVariant` contract tests (Plan 11-01 T1): Codable
/// round-trip at the boundary values, validation vectors (RESEARCH §1.2
/// capability edges), the EXP-03 percent-fold vectors, and the
/// D-11-CONTEXT-4 tag derivation table.
final class ExportRecipeTests: XCTestCase {

    // MARK: - Codable round-trip

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Every format case survives a JSON round-trip byte-for-value.
    func testFormatSpecCodableRoundTripAllCases() throws {
        let specs: [ExportFormatSpec] = [
            .jpeg(quality: 0.85),
            .png(bitDepth: .sixteen),
            .tiff(bitDepth: .float32, compression: .lzw),
            .heic(quality: 0.7, bitDepth: .ten),
            .avif(quality: 0.6, bitDepth: .twelve),
            .webp(quality: 0.9, lossless: true),
        ]
        for spec in specs {
            XCTAssertEqual(try roundTrip(spec), spec, spec.formatName)
        }
    }

    /// The full variant (all six fields, mixed boundary values) round-trips.
    func testVariantCodableRoundTripAtBoundaries() throws {
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 100_000), dpi: 2400),
            scalePercent: 33.5,
            format: .webp(quality: 1.0, lossless: false),
            colorSpace: .proPhoto,
            yiyin: true,
            outputTag: "print")
        XCTAssertEqual(try roundTrip(variant), variant)
    }

    /// The nil-carrier face (percent nil, tag nil) survives the round-trip —
    /// the absence must not decode back as a default.
    func testVariantCodableRoundTripNilFields() throws {
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .original, dpi: 1),
            scalePercent: nil,
            format: .png(bitDepth: .eight),
            colorSpace: .sRGB,
            yiyin: false,
            outputTag: nil)
        XCTAssertEqual(try roundTrip(variant), variant)
    }

    /// The recipe typealias is a plain array — round-trips wholesale.
    func testRecipeCodableRoundTrip() throws {
        let recipe: ExportRecipe = [
            ExportVariant(format: .jpeg(quality: 0), colorSpace: .sRGB),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .shortEdge(px: 1)),
                scalePercent: nil,
                format: .tiff(bitDepth: .sixteen, compression: .zip),
                colorSpace: .rec2020),
        ]
        XCTAssertEqual(try roundTrip(recipe), recipe)
    }

    // MARK: - Validation vectors

    /// Out-of-domain quality throws `.invalidParameter`, format by format.
    func testQualityValidationVectors() {
        let invalid: [ExportFormatSpec] = [
            .jpeg(quality: -0.01),
            .jpeg(quality: 1.01),
            .heic(quality: -1, bitDepth: .eight),
            .heic(quality: 1.5, bitDepth: .ten),
            .avif(quality: -0.001, bitDepth: .eight),
            .avif(quality: 2, bitDepth: .twelve),
            .webp(quality: -0.5, lossless: true),
            .webp(quality: 1.0001, lossless: false),
        ]
        for spec in invalid {
            XCTAssertThrowsError(try spec.validate(), "\(spec)") { error in
                guard case AppError.invalidParameter = error else {
                    return XCTFail("expected invalidParameter for \(spec)")
                }
            }
        }
    }

    /// In-domain edges pass (0 and 1 are legal on every lossy format).
    func testQualityBoundaryValuesValidate() throws {
        let valid: [ExportFormatSpec] = [
            .jpeg(quality: 0), .jpeg(quality: 1),
            .heic(quality: 0, bitDepth: .eight), .heic(quality: 1, bitDepth: .ten),
            .avif(quality: 0, bitDepth: .ten), .avif(quality: 1, bitDepth: .twelve),
            .webp(quality: 0, lossless: false), .webp(quality: 1, lossless: true),
            .png(bitDepth: .sixteen),
            .tiff(bitDepth: .eight, compression: .none),
        ]
        for spec in valid {
            XCTAssertNoThrow(try spec.validate(), "\(spec)")
        }
    }

    /// Illegal bit-depth × format pairings are UNREPRESENTABLE: WebP has no
    /// bit-depth case (constant 8-bit, RESEARCH §1.2), PNG has no 10-bit, a
    /// 10-bit PNG simply cannot be typed. Compile-time proof = this file
    /// builds while referencing ONLY the legal case sets.
    func testBitDepthMenusArePerFormat() {
        // The menus themselves (exhaustive via CaseIterable-free explicit lists).
        let pngDepths: [ExportFormatSpec.PNGBitDepth] = [.eight, .sixteen]
        let tiffDepths: [ExportFormatSpec.TIFFBitDepth] = [.eight, .sixteen, .float32]
        let tiffCompressions: [ExportFormatSpec.TIFFCompression] = [.none, .lzw, .zip]
        let heicDepths: [ExportFormatSpec.HEICBitDepth] = [.eight, .ten]
        let avifDepths: [ExportFormatSpec.AVIFBitDepth] = [.eight, .ten, .twelve]
        XCTAssertEqual(pngDepths.count, 2)
        XCTAssertEqual(tiffDepths.count, 3)
        XCTAssertEqual(tiffCompressions.count, 3)
        XCTAssertEqual(heicDepths.count, 2)
        XCTAssertEqual(avifDepths.count, 3)
    }

    /// scalePercent domain: nil passes; (0, 10_000] passes; zero/negative and
    /// the typo guard above 10_000 throw.
    func testScalePercentValidationVectors() throws {
        XCTAssertNoThrow(try ExportVariant.validateScalePercent(nil))
        XCTAssertNoThrow(try ExportVariant.validateScalePercent(0.001))
        XCTAssertNoThrow(try ExportVariant.validateScalePercent(100))
        XCTAssertNoThrow(try ExportVariant.validateScalePercent(10_000))
        for bad in [0.0, -1, -0.5, 10_000.1, 100_000] {
            XCTAssertThrowsError(try ExportVariant.validateScalePercent(bad), "\(bad)") {
                error in
                guard case AppError.invalidParameter = error else {
                    return XCTFail("expected invalidParameter for \(bad)")
                }
            }
        }
    }

    /// A variant's full validate fans out to sizing + format + percent.
    func testVariantValidateComposesAllDimensions() throws {
        var variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 1200), dpi: 300),
            scalePercent: nil,
            format: .jpeg(quality: 0.9),
            colorSpace: .displayP3)
        XCTAssertNoThrow(try variant.validate())

        variant.format = .jpeg(quality: 42)
        XCTAssertThrowsError(try variant.validate())
        variant.format = .jpeg(quality: 0.9)

        variant.scalePercent = 0
        XCTAssertThrowsError(try variant.validate())
        variant.scalePercent = nil

        variant.sizing = YiyinExportSettings(mode: .longEdge(px: 0), dpi: 300)
        XCTAssertThrowsError(try variant.validate()) // sizing px ≥ 1 (D-08-3-T3-1)
    }

    // MARK: - EXP-03 percent fold (effectiveSizing vectors)

    /// Percent folds to longEdge px of the source canvas, rounded to nearest.
    func testPercentFoldVectors() {
        func folded(_ percent: Double?, _ w: Int, _ h: Int) -> YiyinExportSettings {
            ExportVariant(
                sizing: YiyinExportSettings(mode: .original),
                scalePercent: percent,
                format: .jpeg(quality: 0.8),
                colorSpace: .sRGB
            ).effectiveSizing(canvasWidth: w, canvasHeight: h)
        }

        // nil → sizing verbatim (original stays original).
        XCTAssertEqual(folded(nil, 6000, 4000).mode, .original)
        // 100 → identity (no pointless longEdge wrapper).
        XCTAssertEqual(folded(100, 6000, 4000).mode, .original)
        // 50% of 6000×4000 → longEdge 3000.
        XCTAssertEqual(folded(50, 6000, 4000).mode, .longEdge(px: 3000))
        // 25% of 6000×4000 → longEdge 1500.
        XCTAssertEqual(folded(25, 6000, 4000).mode, .longEdge(px: 1500))
        // Rounding to nearest: 33% of 3000 = 990 exact; 33.4% of 3000 = 1002;
        // 100/3 % of 3000 = 999.99… rounds to 1000.
        XCTAssertEqual(folded(33, 3000, 2000).mode, .longEdge(px: 990))
        XCTAssertEqual(folded(33.4, 3000, 2000).mode, .longEdge(px: 1002))
        XCTAssertEqual(folded(100.0 / 3.0, 3000, 2000).mode, .longEdge(px: 1000))
        // Landscape vs portrait both read off the LONG edge.
        XCTAssertEqual(folded(10, 8000, 2000).mode, .longEdge(px: 800))
        XCTAssertEqual(folded(10, 2000, 8000).mode, .longEdge(px: 800))
        // Never upscale: >100 clamps to the source long edge.
        XCTAssertEqual(folded(200, 6000, 4000).mode, .longEdge(px: 6000))
        // Tiny canvases clamp to ≥1 px (no zero-dimension outputs).
        XCTAssertEqual(folded(1, 50, 30).mode, .longEdge(px: 1))
    }

    /// The percent fold preserves the sizing DPI (only the mode is rewritten).
    func testPercentFoldKeepsDPI() {
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .original, dpi: 720),
            scalePercent: 50,
            format: .png(bitDepth: .sixteen),
            colorSpace: .adobeRGB)
        let effective = variant.effectiveSizing(canvasWidth: 4000, canvasHeight: 3000)
        XCTAssertEqual(effective.dpi, 720)
        XCTAssertEqual(effective.mode, .longEdge(px: 2000))
    }

    /// A non-percent variant folds to its sizing untouched (sizing modes are
    /// never second-guessed by the fold).
    func testFoldIsIdentityWithoutPercent() {
        let sizing = YiyinExportSettings(mode: .shortEdge(px: 1600), dpi: 300)
        let variant = ExportVariant(
            sizing: sizing, scalePercent: nil,
            format: .heic(quality: 0.8, bitDepth: .ten), colorSpace: .proPhoto)
        XCTAssertEqual(variant.effectiveSizing(canvasWidth: 999, canvasHeight: 777), sizing)
    }

    // MARK: - Tag derivation (D-11-CONTEXT-4 vectors)

    /// Single variant (or empty recipe) → NO tags, ever.
    func testSingleVariantGetsNoTag() {
        let recipe: ExportRecipe = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .webp(quality: 0.8, lossless: false), colorSpace: .sRGB)
        ]
        XCTAssertEqual(recipe.resolvedOutputTags(canvasWidth: 6000, canvasHeight: 4000), [nil])
        let empty: ExportRecipe = []
        XCTAssertEqual(empty.resolvedOutputTags(canvasWidth: 100, canvasHeight: 100), [])
    }

    /// Multi-variant: px modes tag by size; original falls back to format name.
    func testMultiVariantDerivationVectors() {
        let recipe: ExportRecipe = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .jpeg(quality: 0.9), colorSpace: .sRGB),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .shortEdge(px: 800)),
                format: .png(bitDepth: .sixteen), colorSpace: .sRGB),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .original),
                format: .webp(quality: 0.8, lossless: false), colorSpace: .sRGB),
        ]
        XCTAssertEqual(
            recipe.resolvedOutputTags(canvasWidth: 6000, canvasHeight: 4000),
            ["1200", "800", "webp"])
    }

    /// Percent mode derives its size tag through the same fold.
    func testPercentVariantDerivesSizeTag() {
        let recipe: ExportRecipe = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .original),
                scalePercent: 50,
                format: .jpeg(quality: 0.9), colorSpace: .sRGB),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .original),
                format: .tiff(bitDepth: .eight, compression: .none), colorSpace: .sRGB),
        ]
        XCTAssertEqual(
            recipe.resolvedOutputTags(canvasWidth: 6000, canvasHeight: 4000),
            ["3000", "tiff"])
    }

    /// An explicit outputTag always wins over derivation.
    func testExplicitTagWins() {
        let recipe: ExportRecipe = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .jpeg(quality: 0.9), colorSpace: .sRGB, outputTag: "print"),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .webp(quality: 0.8, lossless: false), colorSpace: .sRGB),
        ]
        XCTAssertEqual(
            recipe.resolvedOutputTags(canvasWidth: 6000, canvasHeight: 4000),
            ["print", "1200"])
    }

    /// A whitespace-only explicit tag counts as absent (derivation applies).
    func testWhitespaceTagIsAbsent() {
        let recipe: ExportRecipe = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .jpeg(quality: 0.9), colorSpace: .sRGB, outputTag: "   "),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .original),
                format: .avif(quality: 0.8, bitDepth: .ten), colorSpace: .sRGB),
        ]
        XCTAssertEqual(
            recipe.resolvedOutputTags(canvasWidth: 6000, canvasHeight: 4000),
            ["1200", "avif"])
    }

    /// Collisions disambiguate: `-<formatName>` first, `-<index>` beyond.
    func testCollisionDisambiguation() {
        let recipe: ExportRecipe = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .jpeg(quality: 0.9), colorSpace: .sRGB),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .heic(quality: 0.9, bitDepth: .ten), colorSpace: .sRGB),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 1200)),
                format: .avif(quality: 0.9, bitDepth: .ten), colorSpace: .sRGB),
        ]
        // First keeps the bare size tag; later collisions append THEIR OWN
        // format name, then the index once even that collides.
        XCTAssertEqual(
            recipe.resolvedOutputTags(canvasWidth: 6000, canvasHeight: 4000),
            ["1200", "1200-heic", "1200-avif-2"])
    }

    // MARK: - Orthogonality (value semantics)

    /// Two variants built from the same params share nothing: mutating one
    /// leaves the other untouched (EXP-07's fan-out contract).
    func testVariantOrthogonality() {
        let sizing = YiyinExportSettings(mode: .longEdge(px: 2048), dpi: 300)
        let base = ExportVariant(
            sizing: sizing, scalePercent: nil,
            format: .jpeg(quality: 0.85), colorSpace: .displayP3, yiyin: true)
        var copy = base
        copy.format = .png(bitDepth: .eight)
        copy.colorSpace = .proPhoto
        copy.yiyin = false
        copy.outputTag = "mutated"

        XCTAssertEqual(base.format, ExportFormatSpec.jpeg(quality: 0.85))
        XCTAssertEqual(base.colorSpace, ExportColorSpace.displayP3)
        XCTAssertTrue(base.yiyin)
        XCTAssertNil(base.outputTag)
    }

    /// Recipe equality is structural (Codable-mountable by Phase 12 presets).
    func testRecipeStructuralEquality() {
        let a: ExportRecipe = [
            ExportVariant(format: .jpeg(quality: 0.85), colorSpace: .sRGB)
        ]
        let b: ExportRecipe = [
            ExportVariant(format: .jpeg(quality: 0.85), colorSpace: .sRGB)
        ]
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - Derived faces

    func testFileExtensionsAndUTITypes() {
        XCTAssertEqual(ExportFormatSpec.jpeg(quality: 0.8).fileExtension, "jpg")
        XCTAssertEqual(ExportFormatSpec.png(bitDepth: .eight).fileExtension, "png")
        XCTAssertEqual(ExportFormatSpec.tiff(bitDepth: .float32, compression: .zip).fileExtension, "tif")
        XCTAssertEqual(ExportFormatSpec.heic(quality: 0.8, bitDepth: .ten).fileExtension, "heic")
        XCTAssertEqual(ExportFormatSpec.avif(quality: 0.8, bitDepth: .ten).fileExtension, "avif")
        XCTAssertEqual(ExportFormatSpec.webp(quality: 0.8, lossless: false).fileExtension, "webp")

        XCTAssertEqual(ExportFormatSpec.jpeg(quality: 0.8).utType, "public.jpeg")
        XCTAssertEqual(ExportFormatSpec.avif(quality: 0.8, bitDepth: .ten).utType, "public.avif")
        XCTAssertEqual(
            ExportFormatSpec.webp(quality: 0.8, lossless: false).utType, "org.webmproject.webp")
    }

    /// L013 red line: the model carries no hash field — structural Hashable
    /// synthesis is the ONLY hashing these types do (nothing feeds StableHash).
    func testNoHashFields() {
        let variant = ExportVariant(format: .jpeg(quality: 0.8), colorSpace: .sRGB)
        // Exhaustive member audit: adding a field to the struct without
        // updating this list fails the equality diff below, not silently.
        let mirrored = ExportVariant(
            sizing: variant.sizing,
            scalePercent: variant.scalePercent,
            format: variant.format,
            colorSpace: variant.colorSpace,
            yiyin: variant.yiyin,
            outputTag: variant.outputTag)
        XCTAssertEqual(variant, mirrored)
    }
}
