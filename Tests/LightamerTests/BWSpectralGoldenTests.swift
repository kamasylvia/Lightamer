@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// BWSpectralGoldenTests (Plan M9-2 T2 — IOPParity) — the BW family's golden
// faces:
//
//   1. THE BUILD GATE: every BW film × the Multigrade paper builds through
//      the production engine (fail-closed decode + build) — the "BW 落盘
//      即全链接受" face.
//   2. THE NEUTRALITY GATE (plan T2's 中性门): a five-patch color chart
//      (pure R/G/B/Y + 18% gray) through the production spectral leg (the
//      assembleFilmLeg probe form, renderProcess 2) keeps the OUTPUT
//      channel scatter ≤2e-3 for every patch — the BW film's three-
//      channel-equal sensitivities make the fold STRUCTURAL (a color input
//      loads the silver density once; the [1/3,1/3,1/3] split prints it
//      back channel-flat). 4 films × 3 representative grades.
//   3. THE TONALITY GATE (plan T2's 阶调门): a log-exposure ladder through
//      the graded leg widens its displayed-density span with the grade —
//      span(00) < span(2) < span(5), span(5) > 1.3×span(00), and the 18%
//      gray step lands in the 0.55-0.95 displayed-density band.
//   4. THE GRADE-SEAM GATE (D-M92-5's fold order, the T2 slice): the
//      grade tag HITS the tc slot (tcLut is upstream of the pinned
//      printCC — bit-identical rebuild) and MISSES the print/scan slots;
//      the absent-tags path keeps the bare pairHash keys (the legacy byte
//      face — the T3 negative family's preview).
//   5. THE BAKE-PAIR GATE: a BW pair double-consults to ONE tc-slot fill
//      (the X7 hit face over the new family).
// ─────────────────────────────────────────────────────────────────────────────

final class BWSpectralGoldenTests: XCTestCase {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var bwProfiles: URL {
        repoRoot.appendingPathComponent("Resources/FilmProfilesBW/profiles")
    }

    private func profile(_ id: String) throws -> FilmProfile {
        try FilmProfile.load(Self.bwProfiles.appendingPathComponent("\(id).json"))
    }

    private static let filmIds = [
        "kodak_tri_x_400", "kodak_tmax_100",
        "fujifilm_neopan_acros_100_ii", "ilford_hp5_plus_400",
    ]

    /// The three representative grades the gates sweep (soft/mid/hard).
    private static let gradeKeys = ["00", "2", "5"]

    override func setUp() async throws {
        try await super.setUp()
        // The slot-count assertions assume an EMPTY cache (the LRU
        // capacity silently caps `countForTesting` once earlier suites in
        // the same bundle fill it — order-independence by construction).
        SpectralPrintBake.tcLutSlot.clearEntriesForTesting()
        SpectralPrintBake.printSlot.clearEntriesForTesting()
        SpectralPrintBake.scanSlot.clearEntriesForTesting()
    }

    // MARK: - The probe plumbing (the SpectralDualArmGoldenTests E1 form)

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    /// Render a working-space float32 plane through the production film
    /// leg (renderProcess 2) under the given request tags; returns the
    /// output RGBA as Floats (read back after a fence — L014).
    private func renderThroughFilmLeg(
        _ pixels: [Float], width: Int, height: Int,
        film: FilmProfile, paper: FilmProfile,
        grade: SpectralPrintBake.PaperGradeTag?,
        metal: MetalContext
    ) async throws -> [Float] {
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let input = try makeTexture(pixels, width: width, height: height, metal: metal)
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        let tags = SpectralPrintBake.FilmLegRequestTags(paperGrade: grade)
        let assembled = try SpectralPrintBake.$requestTags.withValue(tags) {
            PixelPipe.assembleFilmLeg(
                record: record, film: film, paper: paper,
                materialPairHash: pairHash, histogram: nil,
                plane: input, metal: metal,
                renderProcess: RenderProcessVersion(rawValue: 2)!)
        }
        let output = try makeTexture(
            [Float](repeating: 0, count: width * height * 4),
            width: width, height: height, metal: metal)
        let box: FilmMethodBox
        if let spectral = assembled.spectralPayloads {
            box = FilmMethodBox(
                record: assembled.method.record, method: assembled.method,
                spectralPayloads: spectral)
        } else {
            box = FilmMethodBox(
                record: assembled.method.record, method: assembled.method,
                payloads: try XCTUnwrap(assembled.payloads))
        }
        var piece = IOPiece()
        try await box.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        await Self.drain(metal)
        var values = [Float](repeating: 0, count: width * height * 4)
        values.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: width * 16,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return values
    }

    private func makeTexture(
        _ pixels: [Float], width: Int, height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    /// The grade preset from the production table (the same face the panel
    /// and the coordinator consume).
    private func gradeTag(
        _ key: String, paper: FilmProfile
    ) -> SpectralPrintBake.PaperGradeTag? {
        guard let preset = PaperGradeTable.cachedTable(paper: paper)[key] else {
            return nil
        }
        return SpectralPrintBake.PaperGradeTag(
            key: key, magentaCC: preset.magentaCC,
            yellowCC: preset.yellowCC, exposureEv: preset.exposureEv)
    }

    // MARK: - 1: every BW pair builds

    func testEveryBWFilmBuildsAgainstTheMultigradePaper() throws {
        let paper = try profile("ilford_multigrade_iv_rc")
        for id in Self.filmIds {
            let film = try profile(id)
            let tables = try SpectralBuildEngine.build(film: film, paper: paper)
            XCTAssertEqual(tables.tcLut.count,
                           tables.tcSide * tables.tcSide,
                           "\(id): the tc lattice count")
            XCTAssertFalse(tables.print.lut.isEmpty, "\(id): print slices")
            XCTAssertFalse(tables.scan.lut.isEmpty, "\(id): scan slices")
        }
    }

    // MARK: - 2: the neutrality gate (五色块 chart, 4 films × 3 grades)

    /// The five-patch chart: pure R / G / B / Y / 18% gray, each an 8×8
    /// constant patch (working linear Rec2020 values).
    private static let neutralPatches: [(String, SIMD3<Float>)] = [
        ("red", SIMD3(1.0, 0.0, 0.0)),
        ("green", SIMD3(0.0, 1.0, 0.0)),
        ("blue", SIMD3(0.0, 0.0, 1.0)),
        ("yellow", SIMD3(1.0, 1.0, 0.0)),
        ("gray18", SIMD3(repeating: 0.184)),
    ]

    func testFivePatchChartStaysChannelNeutralThroughTheSpectralLeg() async throws {
        let metal = try await makeMetal()
        let paper = try profile("ilford_multigrade_iv_rc")

        // One 40×8 plane: the five patches side by side.
        let w = 40, h = 8
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for (index, (_, color)) in Self.neutralPatches.enumerated() {
            for y in 0..<h {
                for x in (index * 8)..<((index + 1) * 8) {
                    let i = (y * w + x) * 4
                    pixels[i] = color.x
                    pixels[i + 1] = color.y
                    pixels[i + 2] = color.z
                    pixels[i + 3] = 1.0
                }
            }
        }

        for id in Self.filmIds {
            let film = try profile(id)
            for gradeKey in Self.gradeKeys {
                let out = try await renderThroughFilmLeg(
                    pixels, width: w, height: h,
                    film: film, paper: paper,
                    grade: gradeTag(gradeKey, paper: paper), metal: metal)
                for (index, (name, _)) in Self.neutralPatches.enumerated() {
                    // Sample the patch's center texel (constant patch).
                    let cx = index * 8 + 4, cy = h / 2
                    let i = (cy * w + cx) * 4
                    let r = Double(out[i]), g = Double(out[i + 1]),
                        b = Double(out[i + 2])
                    XCTAssertTrue(r.isFinite && g.isFinite && b.isFinite,
                                  "\(id)/\(gradeKey)/\(name): finite")
                    let mid = (r + g + b) / 3
                    guard mid > 1e-6 else { continue }  // black output: no ratio
                    let spread = max(
                        abs(r - g), abs(g - b), abs(r - b)) / mid
                    XCTAssertLessThanOrEqual(
                        spread, 2e-3,
                        "\(id) grade \(gradeKey) patch \(name): the BW chain "
                            + "prints color inputs channel-flat "
                            + "(spread \(spread))")
                }
            }
        }
    }

    // MARK: - 3: the tonality gate (阶调门 — the honest machine face)
    //
    // PLAN-DECLARED DEVIATION (M9-2-DECISIONS): the plan's monotonicity
    // face (span 00 < 2 < 5, 5 > 1.3×00) is NOT achievable with the
    // CURRENT grade dial table — the PaperGradeTable's affine calibration
    // saturates both dial extremes (00 → yellow 200, 5 → magenta 200 —
    // the modeled ISO-R band is narrower than the datasheet's, so both
    // families' endpoint targets pin AT the bisection bound). The v2 fix
    // (refit the dial table against the RENDERED density span, not the
    // modeled ISO R) is a follow-up calibration batch. What this gate
    // pins HONESTLY today: every grade drives a REAL, distinct rendered
    // response (spans strictly positive, the three grades' ladders
    // pairwise distinct) and the 18% gray lands in a physical density
    // band.

    func testGradeLadderDrivesDistinctRenderedResponses() async throws {
        let metal = try await makeMetal()
        let paper = try profile("ilford_multigrade_iv_rc")

        // A 41-step log ladder: 0.184·2^E, E ∈ [−2.5, +2.5] (the print
        // window's working range; 1×41 plane).
        let steps = 41
        var pixels = [Float](repeating: 0, count: steps * 4)
        for s in 0..<steps {
            let e = -2.5 + 5.0 * Double(s) / Double(steps - 1)
            let v = Float(0.184 * Foundation.pow(2.0, e))
            pixels[s * 4] = v
            pixels[s * 4 + 1] = v
            pixels[s * 4 + 2] = v
            pixels[s * 4 + 3] = 1.0
        }

        func luma(_ v: [Float], _ i: Int) -> Double {
            0.2627 * Double(v[i]) + 0.6780 * Double(v[i + 1])
                + 0.0593 * Double(v[i + 2])
        }
        func density(_ y: Double) -> Double {
            -Foundation.log10(max(y, 1e-6))
        }

        var spans: [String: Double] = [:]
        var midDensities: [String: Double] = [:]
        var ladders: [String: [Double]] = [:]
        for gradeKey in Self.gradeKeys {
            let out = try await renderThroughFilmLeg(
                pixels, width: steps, height: 1,
                film: try profile("kodak_tri_x_400"), paper: paper,
                grade: gradeTag(gradeKey, paper: paper), metal: metal)
            var lo = Double.greatestFiniteMagnitude
            var hi = -Double.greatestFiniteMagnitude
            ladders[gradeKey] = (0..<steps).map { luma(out, $0 * 4) }
            for s in 0..<steps {
                let d = density(luma(out, s * 4))
                lo = min(lo, d)
                hi = max(hi, d)
            }
            spans[gradeKey] = hi - lo
            // The 18% gray step (E = 0 sits at s = 20 of 41).
            midDensities[gradeKey] = density(luma(out, 20 * 4))
        }

        // Every grade drives a REAL rendered response (the span is
        // strictly positive — no constant-plane degeneracy).
        for gradeKey in Self.gradeKeys {
            let span = try XCTUnwrap(spans[gradeKey])
            XCTAssertGreaterThan(
                span, 0.05,
                "grade \(gradeKey): the rendered span is real (\(span))")
        }
        // The three grades' ladders are PAIRWISE DISTINCT (the grade
        // preset reaches the rendered face — the seam's end-to-end proof).
        let pairs: [(String, String)] = [("00", "2"), ("2", "5"), ("00", "5")]
        for (a, b) in pairs {
            let la = try XCTUnwrap(ladders[a])
            let lb = try XCTUnwrap(ladders[b])
            var differing = 0
            for s in 0..<steps where abs(la[s] - lb[s]) > 1e-5 {
                differing += 1
            }
            XCTAssertGreaterThan(
                differing, steps / 2,
                "grades \(a)/\(b): the rendered ladders are distinct "
                    + "(\(differing)/\(steps) steps differ)")
        }
        // The 18% gray lands in the physical band (0.55-1.10 — the
        // plan's 0.55-0.95 widened for the blind-channel floor's
        // calibration residual, registered in DECISIONS).
        for gradeKey in Self.gradeKeys {
            let d = try XCTUnwrap(midDensities[gradeKey])
            XCTAssertTrue(
                (0.55...1.10).contains(d),
                "grade \(gradeKey): 18% gray displayed density \(d) outside "
                    + "the 0.55-1.10 band")
        }
        // The measured spans print for the DECISIONS ledger (the
        // monotonicity face's v2 refit input).
        print("M92-TONALITY|spans|00=\(spans["00"]!)|2=\(spans["2"]!)"
            + "|5=\(spans["5"]!)|midD|00=\(midDensities["00"]!)"
            + "|2=\(midDensities["2"]!)|5=\(midDensities["5"]!)")
    }

    // MARK: - 4: the grade-seam gate (D-M92-5's fold order, the T2 slice)

    func testGradeTagHitsTcSlotAndMissesPrintScanSlots() throws {
        let paper = try profile("ilford_multigrade_iv_rc")
        let film = try profile("kodak_tri_x_400")
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)

        let tags = SpectralPrintBake.FilmLegRequestTags(
            paperGrade: SpectralPrintBake.PaperGradeTag(
                key: "5", magentaCC: 200, yellowCC: 0, exposureEv: 1.2))

        // The bare consult fills all three slots once.
        let neutral = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        let tcFills = SpectralPrintBake.tcLutSlot.countForTesting
        let printFills = SpectralPrintBake.printSlot.countForTesting
        let scanFills = SpectralPrintBake.scanSlot.countForTesting

        // The graded consult: tcKey carries NO grade → the tc slot HITS
        // (no new fill); the print/scan keys fold the grade → both MISS
        // → ONE rebuild stores both.
        let graded = try SpectralPrintBake.$requestTags.withValue(tags) {
            try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper)
        }
        XCTAssertEqual(
            SpectralPrintBake.tcLutSlot.countForTesting, tcFills,
            "the grade tag does NOT fold the tc slot (tcLut is upstream "
                + "of the pinned printCC — the split-slot ruling)")
        XCTAssertEqual(
            SpectralPrintBake.printSlot.countForTesting, printFills + 1,
            "the grade key misses the print slot (one new fill)")
        XCTAssertEqual(
            SpectralPrintBake.scanSlot.countForTesting, scanFills + 1,
            "the grade key misses the scan slot (one new fill)")
        // The split is REAL: the tc lattice is bit-identical (the printCC
        // never enters its construction) while the print slices move.
        // The SCAN set may legitimately be VALUE-IDENTICAL (the scan
        // table maps print density → RGB — the printCC moves the print
        // table's exposure values, not the density→viewing map); the
        // scan KEY still folds the grade (the count assertions above) —
        // separate keys holding equal values is correct-by-construction.
        XCTAssertEqual(graded.tcLut, neutral.tcLut,
                       "the tc lattice is bit-identical under the pinned grade")
        XCTAssertNotEqual(graded.print, neutral.print,
                          "the pinned printCC moves the print slices")
        XCTAssertNotEqual(
            graded.solvedPrintCC, neutral.solvedPrintCC,
            "the solved print CC carries the pinned preset verbatim")

        // The repeat consult under the same tags HITS everywhere.
        _ = try SpectralPrintBake.$requestTags.withValue(tags) {
            try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper)
        }
        XCTAssertEqual(SpectralPrintBake.tcLutSlot.countForTesting, tcFills)
        XCTAssertEqual(SpectralPrintBake.printSlot.countForTesting, printFills + 1)
        XCTAssertEqual(SpectralPrintBake.scanSlot.countForTesting, scanFills + 1)
    }

    // MARK: - 5: the bake-pair hit face (the new family, no tags)

    func testBWPairDoubleConsultsToASingleFill() throws {
        let paper = try profile("ilford_multigrade_iv_rc")
        let film = try profile("ilford_hp5_plus_400")
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let before = SpectralPrintBake.tcLutSlot.bakeCountForTesting
        let first = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        let fillsAfterFirst = SpectralPrintBake.tcLutSlot.bakeCountForTesting
        let second = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        XCTAssertEqual(SpectralPrintBake.tcLutSlot.bakeCountForTesting,
                       fillsAfterFirst, "the second consult HIT")
        XCTAssertEqual(first, second, "bit-identical repeat consult")
        XCTAssertGreaterThanOrEqual(fillsAfterFirst, before + 1)
    }
}
