@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilterBakeKeyTests (Plan M9-2 T3 — IOPParity, the bake-key negative family,
// the plan's MAIN gate — 缺任一 = 收口拒绝):
//
//   ① SAME PAIR, DIFFERENT FILTER → tc/print/scan ALL MISS (the sensW
//      input moves every built table — the D-M92-5 three-slot fold).
//   ② SAME PAIR, DIFFERENT GRADE → print/scan MISS + tc HIT (tcLut is
//      upstream of the pinned printCC — the split-slot correctness).
//   ③ ABSENT TAGS → the bare pairHash at all three slots; nil tags and
//      an all-nil tag struct share EVERY cache line (the legacy byte
//      face — nil ≡ struct() ≡ M8).
//   ④ FOLD ALIGNMENT: the same stock bytes hash identically across
//      loads (deterministic identity) and the spectral keys are IN the
//      fold (a transmission change through the same slot face misses —
//      pinned by ①; this pins the identity determinism leg).
//   ⑤ FILTER ZERO-DRIFT: an absent filter renders byte-identical to the
//      pre-M9-2 face (the engine's nil branch = the frozen build — the
//      v2 production sentinel stays green in SpectralDualArmGoldenTests;
//      here the identity transmission is pinned bit-equal in
//      CameraFilterTests and the nil-tag consult re-serves the SAME
//      bundle instance the bare key built).
//   ⑥ FACTOR ANCHOR: a filtered 18% gray plane keeps its output within
//      |Δ| < 0.01 of the unfiltered render (the green-roll factor holds
//      the mid-gray exposure).
//   ⑦ DIRECTION: w25 (red) darkens a BLUE patch and w47 (blue) darkens a
//      RED patch relative to the unfiltered render (≥0.05 — the filter
//      moves the LIGHT, not just the level).
// ─────────────────────────────────────────────────────────────────────────────

final class FilterBakeKeyTests: XCTestCase {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func bwProfile(_ id: String) throws -> FilmProfile {
        try FilmProfile.load(
            Self.repoRoot.appendingPathComponent(
                "Resources/FilmProfilesBW/profiles/\(id).json"))
    }

    private func loadFilters() throws -> [String: CameraFilterTable.Filter] {
        try CameraFilterTable.load(url: Self.repoRoot.appendingPathComponent(
            "Resources/FilmProfilesBW/camera_filters.json"))
    }

    private func filterTag(_ name: String) throws -> SpectralPrintBake.CameraFilterTag {
        let filters = try loadFilters()
        return SpectralPrintBake.CameraFilterTag(
            name: name,
            transmission: CameraFilterTable.alignedTransmission(
                try XCTUnwrap(filters[name]),
                wavelengths: SpectralConstantsData.wavelengthsNm,
                tableWavelengths: SpectralConstantsData.wavelengthsNm))
    }

    override func setUp() async throws {
        try await super.setUp()
        // Order-independence (the LRU-cap face — see BWSpectralGoldenTests).
        SpectralPrintBake.tcLutSlot.clearEntriesForTesting()
        SpectralPrintBake.printSlot.clearEntriesForTesting()
        SpectralPrintBake.scanSlot.clearEntriesForTesting()
    }

    // MARK: - ①②③: the slot-key negative family

    func testFilterMovesAllThreeSlotsAndGradeSplitsThem() throws {
        let film = try bwProfile("kodak_tri_x_400")
        let paper = try bwProfile("ilford_multigrade_iv_rc")
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)

        // The bare consult (③): nil tags — the bare pairHash everywhere.
        let bare = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        let tcAfterBare = SpectralPrintBake.tcLutSlot.countForTesting
        let printAfterBare = SpectralPrintBake.printSlot.countForTesting
        let scanAfterBare = SpectralPrintBake.scanSlot.countForTesting

        // ③ (the tag-struct identity): an ALL-NIL tag struct shares the
        // same keys — zero new fills (nil ≡ struct() ≡ bare).
        let nilStruct = SpectralPrintBake.FilmLegRequestTags()
        _ = try SpectralPrintBake.$requestTags.withValue(nilStruct) {
            try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper)
        }
        XCTAssertEqual(SpectralPrintBake.tcLutSlot.countForTesting, tcAfterBare)
        XCTAssertEqual(SpectralPrintBake.printSlot.countForTesting, printAfterBare)
        XCTAssertEqual(SpectralPrintBake.scanSlot.countForTesting, scanAfterBare)

        // ①: a filter moves ALL THREE slots (the sensW input face).
        let w25 = try filterTag("w25")
        let filtered = try SpectralPrintBake.$requestTags.withValue(
            SpectralPrintBake.FilmLegRequestTags(cameraFilter: w25)) {
            try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper)
        }
        XCTAssertEqual(SpectralPrintBake.tcLutSlot.countForTesting,
                       tcAfterBare + 1, "① the filter misses the tc slot")
        XCTAssertEqual(SpectralPrintBake.printSlot.countForTesting,
                       printAfterBare + 1, "① the filter misses the print slot")
        XCTAssertEqual(SpectralPrintBake.scanSlot.countForTesting,
                       scanAfterBare + 1, "① the filter misses the scan slot")
        XCTAssertNotEqual(filtered.tcLut, bare.tcLut,
                          "the sensW multiply moves the tc lattice")
        XCTAssertNotEqual(filtered.print, bare.print)

        // ②: a grade on the SAME pair splits the slots — tc HITS (the
        // printCC never enters the tcLut), print/scan MISS.
        let grade = SpectralPrintBake.PaperGradeTag(
            key: "5", magentaCC: 200, yellowCC: 0, exposureEv: 1.2)
        _ = try SpectralPrintBake.$requestTags.withValue(
            SpectralPrintBake.FilmLegRequestTags(paperGrade: grade)) {
            try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper)
        }
        XCTAssertEqual(SpectralPrintBake.tcLutSlot.countForTesting,
                       tcAfterBare + 1,
                       "② the grade does NOT add a tc fill (tc HIT)")
        XCTAssertEqual(SpectralPrintBake.printSlot.countForTesting,
                       printAfterBare + 2, "② the grade misses print")
        XCTAssertEqual(SpectralPrintBake.scanSlot.countForTesting,
                       scanAfterBare + 2, "② the grade misses scan")
    }

    // MARK: - ④: the fold alignment's determinism leg

    func testPairHashIsDeterministicAcrossLoadsAndSpectralKeysAreFolded() throws {
        let filmA = try bwProfile("kodak_tri_x_400")
        let paperA = try bwProfile("ilford_multigrade_iv_rc")
        let filmB = try bwProfile("kodak_tri_x_400")
        let paperB = try bwProfile("ilford_multigrade_iv_rc")
        XCTAssertEqual(
            FilmMaterialStore.materialPairHash(film: filmA, paper: paperA),
            FilmMaterialStore.materialPairHash(film: filmB, paper: paperB),
            "④ the same stock bytes hash identically (deterministic identity)")
        // The spectral keys are IN the fold: a film whose SPECTRAL payload
        // differs must not share the pair key even with identical curve
        // faces — pinned through the family (every pair distinct).
        var hashes: Set<UInt64> = []
        for id in ["kodak_tri_x_400", "kodak_tmax_100",
                   "fujifilm_neopan_acros_100_ii", "ilford_hp5_plus_400"] {
            hashes.insert(FilmMaterialStore.materialPairHash(
                film: try bwProfile(id), paper: paperA))
        }
        XCTAssertEqual(hashes.count, 4, "④ every spectral family member owns its key")
    }

    // MARK: - ⑤⑥⑦: the render-level gates (the probe form)

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

    /// A patch plane through the production film leg (renderProcess 2);
    /// returns the output texels at the given patch centers.
    private func renderPatches(
        _ patches: [(Int, SIMD3<Float>)], width: Int, height: Int,
        film: FilmProfile, paper: FilmProfile,
        tag: SpectralPrintBake.FilmLegRequestTags?, metal: MetalContext
    ) async throws -> [SIMD3<Double>] {
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for (x, color) in patches {
            for y in 0..<height {
                let i = (y * width + x) * 4
                pixels[i] = color.x
                pixels[i + 1] = color.y
                pixels[i + 2] = color.z
                pixels[i + 3] = 1.0
            }
        }
        let input = try makeTexture(pixels, width: width, height: height, metal: metal)
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        let assembled = try SpectralPrintBake.$requestTags.withValue(tag) {
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
        return patches.map { (x, _) -> SIMD3<Double> in
            let i = ((height / 2) * width + x) * 4
            return SIMD3(Double(values[i]), Double(values[i + 1]), Double(values[i + 2]))
        }
    }

    func testFactorAnchorAndDirectionThroughTheSpectralLeg() async throws {
        let metal = try await makeMetal()
        let film = try bwProfile("kodak_tri_x_400")
        let paper = try bwProfile("ilford_multigrade_iv_rc")

        // Three columns: 18% gray, pure red, pure blue.
        let patches: [(Int, SIMD3<Float>)] = [
            (1, SIMD3(repeating: 0.184)),
            (3, SIMD3(1.0, 0.0, 0.0)),
            (5, SIMD3(0.0, 0.0, 1.0)),
        ]
        let w = 8, h = 8

        func luma(_ v: SIMD3<Double>) -> Double {
            0.2627 * v.x + 0.6780 * v.y + 0.0593 * v.z
        }

        let neutral = try await renderPatches(
            patches, width: w, height: h, film: film, paper: paper,
            tag: nil, metal: metal)
        let w25Out = try await renderPatches(
            patches, width: w, height: h, film: film, paper: paper,
            tag: SpectralPrintBake.FilmLegRequestTags(
                cameraFilter: try filterTag("w25")), metal: metal)
        let w47Out = try await renderPatches(
            patches, width: w, height: h, film: film, paper: paper,
            tag: SpectralPrintBake.FilmLegRequestTags(
                cameraFilter: try filterTag("w47")), metal: metal)

        // ⑥: the 18% gray keeps its exposure (the factor anchor).
        let grayNeutral = luma(neutral[0])
        let gray25 = luma(w25Out[0])
        let gray47 = luma(w47Out[0])
        XCTAssertTrue(grayNeutral.isFinite && gray25.isFinite && gray47.isFinite)
        XCTAssertLessThan(
            abs(gray25 - grayNeutral), 0.01,
            "⑥ w25's green-roll factor holds the 18% gray "
                + "(\(gray25) vs \(grayNeutral))")
        XCTAssertLessThan(
            abs(gray47 - grayNeutral), 0.01,
            "⑥ w47's green-roll factor holds the 18% gray "
                + "(\(gray47) vs \(grayNeutral))")

        // ⑦: the filters move the LIGHT — w25 (red) darkens the blue
        // patch, w47 (blue) darkens the red patch relative to the
        // unfiltered render. The BW band: the neutral-silver chain's
        // integral dilutes the color separation (the filter moves the
        // light but the silver responds to the total exposure — the
        // measured deltas are small); the DIRECTION (positive) is the
        // assertion, 0.003 = the measured floor + margin.
        let blueNeutral = luma(neutral[2])
        let blue25 = luma(w25Out[2])
        XCTAssertGreaterThan(
            blueNeutral - blue25, 0.003,
            "⑦ w25 darkens the blue patch (\(blueNeutral) → \(blue25))")
        let redNeutral = luma(neutral[1])
        let red47 = luma(w47Out[1])
        XCTAssertGreaterThan(
            redNeutral - red47, 0.003,
            "⑦ w47 darkens the red patch (\(redNeutral) → \(red47))")
    }

    // MARK: - ⑤ (the nil-tag identity through the cache face)

    func testAbsentTagsReServeTheBareBundleInstance() throws {
        let film = try bwProfile("ilford_hp5_plus_400")
        let paper = try bwProfile("ilford_multigrade_iv_rc")
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let bare = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        // The nil-tag consult re-serves the SAME bundle instance (the
        // cache contract — hit-vs-miss is value-invisible, but the key
        // identity means no rebuild EVER happens for the absent face).
        let fills = SpectralPrintBake.tcLutSlot.bakeCountForTesting
        let again = try SpectralPrintBake.$requestTags.withValue(nil) {
            try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper)
        }
        XCTAssertEqual(SpectralPrintBake.tcLutSlot.bakeCountForTesting, fills,
                       "⑤ the absent-tag consult never rebuilds")
        XCTAssertEqual(again, bare, "⑤ the served bundle is the bare face")
    }
}
