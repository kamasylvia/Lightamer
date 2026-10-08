@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmDeterminismTests (Plan M3-3-03 T2, KD-2 — LAYERS bundle) — the FSIM-01b
// DETERMINISM GATE SUITE: same statistics + same material pair + same mode →
// the same solution, end to end through the real pipe.
//
//   1. SOLVE bit-identity: FilmRuntimeSolve.solve ×2 on the same inputs is
//      bit-identical (bitPattern compare — Float64 channel math, fixed
//      ladders), across fresh store instances too.
//   2. CACHE-KEY FOLD (the L013 canonical face): the key is EXACTLY an
//      independent FNV-1a double-write over (materialPairHash ⊕ statsHash ⊕
//      mode tag) in that fold order — an exact-value pin, not merely a
//      discrimination pin — plus the four-direction flip matrix.
//   3. CROSS-ROI SEAMLESSNESS (the 02 KD-2 red line's end-to-end pin): the
//      same image rendered FULL vs two different ROI windows (the 04-01
//      roiHint test seam) produces ONE solve-cache entry and BYTE-IDENTICAL
//      overlapping output regions. The windows are PERIODIC-slices of the
//      fixture (identical histograms — the 02 semantics scope the statistics
//      at the run's full plane, so window-independence is pinned where it is
//      defined: equal statistics → equal solution → seamless face; the
//      window-scoped-stats face is registered in M3-3-03-DECISIONS).
//   4. INTEGER-RANK percentiles: hand-computed ranks on known count
//      distributions (exact Int equality — no float interpolation path).
//   5. CROSS-VERSION STABILITY SENTINEL: the film output plane hash for a
//      fixed input set is a compile-time constant (FilmGoldenConsts) — any
//      intentional model-math change re-pins it through the DECISIONS
//      process (never silently).
// ─────────────────────────────────────────────────────────────────────────────

/// The cross-version stability constants (KD-2). Re-pin process: register the
/// intentional math change in M3-3-03-DECISIONS (or its successor), recompute
/// the constant, re-pin in the SAME commit — an unregistered flip is a defect.
private enum FilmGoldenConsts {
    /// FNV-1a over the raw bytes of the film output plane for: the periodic
    /// ramp fixture (48×32), portra_400 × portra_endura, strength 1.0, no
    /// shifts, no content-adaptive shift, exposureEv 0, the statistics seam
    /// UNINSTALLED (the gain rides 2^0 = 1), the .edrLinear terminal policy
    /// with an empty main chain (the final plane = the film output, float32),
    /// a fresh PipeCache, and the fixed fixture image ID below.
    static let filmRampPlaneHash: UInt64 = 14_365_179_805_968_017_957
}

final class FilmDeterminismTests: XCTestCase {

    private static let fixtureImageID = UUID(
        uuidString: "F11DA7E1-0000-4000-8000-00000000F11E")!

    // MARK: - Fixtures

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private var portra: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_400"))
        }
    }

    private var endura: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_endura"))
        }
    }

    /// A fresh store per call (the cross-instance determinism face).
    private func makeStore() throws -> FilmMaterialStore {
        try FilmMaterialStore(profilesDirectory: profilesDirectory())
    }

    /// The PERIODIC ramp fixture: 48×32, every column a fixed chroma value
    /// repeated down the column, the column pattern periodic with period 12
    /// (48 = 4 periods). Any width-24 window aligned to the period grid
    /// carries the SAME column histogram — the cross-ROI gate's
    /// equal-statistics construction.
    private func makePeriodicRampImage(width: Int = 48, height: Int = 32)
        -> DecodedImage
    {
        var seed: UInt64 = 0xA5A5_5A5A_1234_5678
        var columnValues = [SIMD3<Double>]()
        for _ in 0..<12 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = 0.02 + 6.0 * Double((seed >> 11) & 0xFFFFFF) / Double(0xFFFFFF)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let g = 0.02 + 6.0 * Double((seed >> 11) & 0xFFFFFF) / Double(0xFFFFFF)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let b = 0.02 + 6.0 * Double((seed >> 11) & 0xFFFFFF) / Double(0xFFFFFF)
            columnValues.append(SIMD3(r, g, b))
        }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                let v = columnValues[x % 12]
                pixels[o + 0] = Float(v.x)
                pixels[o + 1] = Float(v.y)
                pixels[o + 2] = Float(v.z)
                pixels[o + 3] = 1.0
            }
        }
        let bitmap = pixels.withUnsafeBytes { Data($0) }
        let ci = CIImage(
            bitmapData: bitmap,
            bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: WorkingSpace.colorSpace)
        return DecodedImage(
            ciImage: ci,
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// The terminal pair (colorout only — the .edrLinear row replays it
    /// post-film; gamma stays demoted and the final plane stays float32).
    private func makeColorOut(registry: ModuleRegistry) async throws
        -> [any ModuleBoxing]
    {
        let made = await registry.makeBox(opName: ColorOutModule.opName)
        let colorout = try XCTUnwrap(made as? ModuleBox<ColorOutModule>)
        colorout.setParams(ColorOutModule.Params(outputProfile: .sRGB))
        return [colorout]
    }

    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private static func readAllBytes(_ texture: any MTLTexture) -> [UInt8] {
        precondition(texture.pixelFormat == WorkingSpace.pixelFormat)
        let w = texture.width, h = texture.height
        let rowBytes = w * 16
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    private static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var h: UInt64 = 0xCBF29CE484222325
        for b in bytes {
            h ^= UInt64(b)
            h = h &* 0x100000001B3
        }
        return h
    }

    private func render(
        _ image: DecodedImage, chain: [any ModuleBoxing], filmTail: FilmTailPolicy?,
        roiHint: ROI? = nil, metal: MetalContext
    ) async throws -> any MTLTexture {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: Self.fixtureImageID,
            resolution: .preview, cache: PipeCache(), metal: metal,
            roiHint: roiHint, terminalTail: .edrLinear, filmTail: filmTail)
        await Self.drain(metal)
        return texture
    }

    private func makeFilmTail(
        record: FilmRecord? = nil, film: FilmProfile, paper: FilmProfile
    ) -> FilmTailPolicy {
        let r = record ?? {
            var r = FilmRecord()
            r.filmStock = film.info.stock ?? ""
            r.paperStock = paper.info.stock ?? ""
            return r
        }()
        return FilmTailParams(
            record: r, filmProfile: film, paperProfile: paper,
            materialPairHash: FilmMaterialStore.materialPairHash(film: film, paper: paper))
    }

    // MARK: - 1: solve bit-identity

    func testSolveIsBitIdenticalAcrossCallsAndStoreInstances() throws {
        let film = try portra
        let paper = try endura
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.mFilterShift = 7
        record.exposureEv = 0.25
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        var counts = [[UInt32]]()
        for channel in 0..<4 {
            var bins = [UInt32](repeating: 0, count: 256)
            for bin in 0..<256 {
                bins[bin] = UInt32((bin * 7 + channel * 13) % 97)
            }
            counts.append(bins)
        }
        let histogram = FilmStatsSeam.PlaneHistogram(perChannel: counts)
        let a = try FilmRuntimeSolve.solve(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: histogram)
        let b = try FilmRuntimeSolve.solve(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: histogram)
        XCTAssertEqual(
            a.magentaCC.bitPattern, b.magentaCC.bitPattern, "M bit-identical")
        XCTAssertEqual(
            a.yellowCC.bitPattern, b.yellowCC.bitPattern, "Y bit-identical")
        XCTAssertEqual(
            a.exposureGain.bitPattern, b.exposureGain.bitPattern,
            "the gain bit-identical (the FSIM-01b gate)")
        XCTAssertEqual(a, b)
        _ = try makeStore()   // a fresh store instance changes nothing
        let c = try FilmRuntimeSolve.solve(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: histogram)
        XCTAssertEqual(
            c.magentaCC.bitPattern, a.magentaCC.bitPattern,
            "cross-store-instance bit-identity")
    }

    // MARK: - 2: the cache-key fold (canonical FNV, order-pinned)

    func testCacheKeyIsCanonicalFNVInPinnedFoldOrder() {
        let pair: UInt64 = 0x1234_5678_9ABC_DEF0
        let stats: UInt64 = 0x0FED_CBA9_8765_4321
        for contentAdaptive in [false, true] {
            // The independent double-write: offset basis → the pair's bytes
            // (little-endian — the withUnsafeBytes memory order the
            // production fold uses) → the stats bytes → the mode tag's
            // UTF-8 bytes.
            var h: UInt64 = 0xCBF29CE484222325
            for shift in stride(from: 0, through: 56, by: 8) {
                h ^= (pair >> UInt64(shift)) & 0xFF
                h = h &* 0x100000001B3
            }
            for shift in stride(from: 0, through: 56, by: 8) {
                h ^= (stats >> UInt64(shift)) & 0xFF
                h = h &* 0x100000001B3
            }
            for byte in FilmRuntimeSolve.modeTag(contentAdaptive: contentAdaptive).utf8 {
                h ^= UInt64(byte)
                h = h &* 0x100000001B3
            }
            XCTAssertEqual(
                FilmRuntimeSolve.cacheKey(
                    materialPairHash: pair, statsHash: stats,
                    contentAdaptive: contentAdaptive),
                h,
                "the cache key IS fnv(pair ⊕ stats ⊕ tag) in the pinned fold "
                    + "order (exact-value pin, mode \(contentAdaptive))")
        }
        // The four-direction flip matrix (any term change → key change).
        let base = FilmRuntimeSolve.cacheKey(
            materialPairHash: 1, statsHash: 2, contentAdaptive: false)
        XCTAssertNotEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 9, statsHash: 2, contentAdaptive: false))
        XCTAssertNotEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 1, statsHash: 9, contentAdaptive: false))
        XCTAssertNotEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 1, statsHash: 2, contentAdaptive: true))
        XCTAssertEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 1, statsHash: 2, contentAdaptive: false),
            "identical terms → identical key (the determinism face)")
    }

    // MARK: - 3: cross-ROI seamlessness (the end-to-end red-line pin)

    func testCrossROIWindowsRenderOneSolveAndSeamlessOverlap() async throws {
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)   // installs the stats seam
        let film = try portra
        let paper = try endura
        let image = makePeriodicRampImage()
        let chain = try await makeColorOut(registry: registry)
        let filmTail = makeFilmTail(film: film, paper: paper)

        let windowA = ROI(x: 0, y: 0, width: 24, height: 32)
        let windowB = ROI(x: 12, y: 0, width: 24, height: 32)

        // The cache-entry accounting: the key's stats term is the RAW count
        // histogram, so the FULL render (48 columns) and the windows (24
        // columns) hold DIFFERENT keys — but the window pair (A, B) shares
        // one entry (identical 2-period counts), and the SOLUTION is
        // count-scale-invariant (the integer-rank percentile is
        // proportion-based), which the byte-identity checks below pin
        // end-to-end.
        let cacheBefore = FilmSolveCache.shared.countForTesting
        let full = try await render(image, chain: chain, filmTail: filmTail, metal: metal)
        let afterFull = FilmSolveCache.shared.countForTesting
        let a = try await render(
            image, chain: chain, filmTail: filmTail, roiHint: windowA, metal: metal)
        let afterA = FilmSolveCache.shared.countForTesting
        let b = try await render(
            image, chain: chain, filmTail: filmTail, roiHint: windowB, metal: metal)
        let afterB = FilmSolveCache.shared.countForTesting

        XCTAssertEqual(
            afterFull, cacheBefore + 1,
            "the first render stores exactly one solve entry")
        XCTAssertEqual(
            afterA, afterFull + 1,
            "window A stores its own entry (the counts differ from full's)")
        XCTAssertEqual(
            afterB, afterA,
            "window B HIT window A's entry — the CROSS-ROI pin: two different "
                + "ROI windows with equal statistics → ONE solution")

        // The overlapping columns are BYTE-IDENTICAL across all three
        // renders (the film face is seamless: same input pixel + same
        // solution → same output pixel; colorout is per-pixel pure).
        // full ∩ A = full columns 0..24; A ∩ B = source columns 12..24.
        let fullBytes = Self.readAllBytes(full)
        let aBytes = Self.readAllBytes(a)
        let bBytes = Self.readAllBytes(b)
        XCTAssertEqual(a.width, 24)
        XCTAssertEqual(b.width, 24)
        let rowBytesA = 24 * 16
        for y in 0..<32 {
            // A column j (j = 12..23) = source column 12 + j; B column
            // j−12 = the same source column.
            for j in 12..<24 {
                let offsetA = (y * 24 + j) * 16
                let offsetB = (y * 24 + (j - 12)) * 16
                XCTAssertEqual(
                    Array(aBytes[offsetA..<(offsetA + 16)]),
                    Array(bBytes[offsetB..<(offsetB + 16)]),
                    "the A∩B overlap column \(j) row \(y) is byte-identical")
            }
            // full column k (k = 0..23) = A column k.
            for k in 0..<24 {
                let offsetF = (y * full.width + k) * 16
                let offsetA = (y * 24 + k) * 16
                XCTAssertEqual(
                    Array(fullBytes[offsetF..<(offsetF + 16)]),
                    Array(aBytes[offsetA..<(offsetA + 16)]),
                    "the full∩A overlap column \(k) row \(y) is byte-identical")
            }
        }
    }

    // MARK: - 4: integer-rank percentiles (hand-computed)

    func testPercentileIntegerRankHandComputedDistributions() {
        // A single spike: 1000 counts in bin 200 — every fraction lands
        // there once the cumulative target is ≥ 1.
        var spike = [UInt32](repeating: 0, count: 256)
        spike[200] = 1000
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(spike, fraction: 0.5), 200)
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(spike, fraction: 0.001), 200)
        // Uniform 4-per-bin over 0..255: total 1024; P50 target = 512 → the
        // cumulative first reaches it at bin 127 (bins 0..127 hold 512).
        var uniform = [UInt32](repeating: 4, count: 256)
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(uniform, fraction: 0.5), 127)
        // P25: target 256 → the cumulative first reaches it at bin 63
        // (bins 0..63 hold 4×64 = 256). P75: target 768 → bin 191.
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(uniform, fraction: 0.25), 63)
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(uniform, fraction: 0.75), 191)
        // The boundary quirk: the target saturates at ≥1 (a fraction of an
        // all-but-empty channel still resolves the first occupied bin).
        var thin = [UInt32](repeating: 0, count: 256)
        thin[17] = 1
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(thin, fraction: 0.0001), 17)
        // The rank is monotone non-decreasing in the fraction (no float
        // interpolation can fold it back).
        var ramp = [UInt32](repeating: 0, count: 256)
        for b in 0..<256 { ramp[b] = UInt32(b + 1) }
        var previous = -1
        for step in 1...20 {
            let rank = FilmRuntimeSolve.percentileBin(ramp, fraction: Double(step) / 21)
            XCTAssertGreaterThanOrEqual(rank, previous, "monotone integer rank")
            previous = rank
        }
    }

    // MARK: - 5: the cross-version stability sentinel

    func testFilmOutputPlaneHashMatchesTheGoldenSentinel() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makePeriodicRampImage()
        // NO registry populate here: the statistics seam stays uninstalled —
        // the gain rides 2^exposureEv = 1 (the deterministic manual face),
        // pinning the sentinel to the pure model chain.
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let texture = try await render(
            image, chain: chain, filmTail: makeFilmTail(film: film, paper: paper),
            metal: metal)
        let hash = Self.fnv1a(Self.readAllBytes(texture))
        XCTAssertEqual(
            hash, FilmGoldenConsts.filmRampPlaneHash,
            "the film output plane hash drifted from the golden sentinel — an "
                + "unregistered model-math change (re-pin ONLY through the "
                + "DECISIONS process, in the same commit as the math change)")
    }
}
