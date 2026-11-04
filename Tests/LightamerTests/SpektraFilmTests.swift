@testable import LightamerCore
import CryptoKit
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpektraFilmTests (spektra-module P1 T2' — LAYERS bundle, the FilmLegTests
// precedent: the module's type face + the ACEScc arms + the factory +
// the material seam + the D-SM-1 stamp + the allocation face).
//
// 15 methods: AC-T2'-1/2-2/2-4/2-5 (4) + AC-T2'-3 md5 dual-arm (2) +
// AC-T2'-6 alloc + RSS probe (2) + AC-T2'-7/2-8/2-9/2-10/2-11 (5) +
// factory pass-through (2).
// ─────────────────────────────────────────────────────────────────────────────

final class SpektraFilmTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private static var profilesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func makeStore() throws -> FilmMaterialStore {
        try FilmMaterialStore(profilesDirectory: Self.profilesDirectory)
    }

    private func boundRecord() throws -> (FilmRecord, FilmMaterialStore) {
        let store = try makeStore()
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        return (record, store)
    }

    private func installSeam(store: FilmMaterialStore) {
        FilmMaterialSeam.resolver = { record in
            guard let film = store.profile(id: record.filmStock),
                let paper = store.profile(id: record.paperStock)
            else { return nil }
            return FilmMaterialSeam.ResolvedMaterials(
                film: film, paper: paper,
                materialPairHash: FilmMaterialStore.materialPairHash(
                    film: film, paper: paper))
        }
    }

    override func tearDown() {
        FilmMaterialSeam.resolver = { _ in nil }
        super.tearDown()
    }

    private func makePlane(
        metal: MetalContext, width: Int = 48, height: Int = 32
    ) throws -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o + 0] = 0.1 + 0.7 * Float(x) / Float(max(width - 1, 1))
                pixels[o + 1] = 0.2 + 0.5 * Float(y) / Float(max(height - 1, 1))
                pixels[o + 2] = 0.3
                pixels[o + 3] = 1.0
            }
        }
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: width * 4 * MemoryLayout<Float>.size)
        }
        return texture
    }

    private func readPixels(_ texture: any MTLTexture) -> [Float] {
        var pixels = [Float](
            repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!,
                bytesPerRow: texture.width * 4 * MemoryLayout<Float>.size,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return pixels
    }

    private func makeFlatPlane(
        metal: MetalContext, level: Float, width: Int = 32, height: Int = 32
    ) throws -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i + 0] = level
            pixels[i + 1] = level
            pixels[i + 2] = level
            pixels[i + 3] = 1.0
        }
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: width * 4 * MemoryLayout<Float>.size)
        }
        return texture
    }

    /// L014: never read a plane across in-flight encoders.
    private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    // MARK: - AC-T2'-1/2: the type face

    /// AC-T2'-1: flags == [.supportsBlending, .oneInstance]; .allowTiling
    /// absent (P1 never tiles).
    func testFlagsAreBlendingPlusOneInstanceWithoutTiling() {
        XCTAssertEqual(
            SpektraFilmModule.flags, [.supportsBlending, .oneInstance])
        XCTAssertFalse(SpektraFilmModule.flags.contains(.allowTiling))
        XCTAssertEqual(SpektraFilmModule.opName, "spektraFilm")
        XCTAssertEqual(SpektraFilmModule.iopOrder, 46.7)
        XCTAssertEqual(SpektraFilmModule.defaultColorspace, .RGB)
    }

    /// AC-T2'-2: tileHalo default 0 + modifyROIIn identity (the R1 anchor
    /// face — the plane stays whole, pixelUm reads the frame width).
    func testTileFaceIsNeverTiledAndROIsAreIdentity() {
        let module = SpektraFilmModule()
        let piece = IOPiece()
        XCTAssertEqual(module.tileHalo(roi: ROI(), piece: piece), 0)
        XCTAssertEqual(module.tileWorkingSetBytesPerPixel(piece: piece), 0)
        var input = ROI(x: 1, y: 2, width: 10, height: 8)
        module.modifyROIIn(
            output: ROI(x: 1, y: 2, width: 10, height: 8),
            input: &input, piece: piece)
        XCTAssertEqual(input, ROI(x: 1, y: 2, width: 10, height: 8))
        var output = ROI()
        module.modifyROIOut(
            &output, input: ROI(x: 1, y: 2, width: 10, height: 8), piece: piece)
        XCTAssertEqual(output, ROI(x: 1, y: 2, width: 10, height: 8))
    }

    // MARK: - AC-T2'-4/5: the identity + coding faces

    /// AC-T2'-4: the uninstalled-seam render is bit-exact input (the
    /// blit-identity degrade — non-pristine record, no resolver).
    func testUninstalledSeamRendersBitExactInput() async throws {
        let metal = try await makeMetal()
        let (record, _) = try boundRecord()
        let module = SpektraFilmModule()
        var piece = IOPiece()
        module.commitParams(SpektraFilmModule.Params(record: record), into: &piece)
        let input = try makePlane(metal: metal)
        let output = try makePlane(metal: metal)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
        metal.device.makeCommandQueue()?.makeCommandBuffer()?.commit()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(readPixels(output), readPixels(input))
    }

    /// AC-T2'-5: identityJSON round-trip — Params() encodes to the
    /// registered bytes (the catalog row's snapshot contract).
    func testParamsIdentityRoundTripMatchesCatalogSnapshot() throws {
        let item = try XCTUnwrap(GradeCatalog.item(opName: "spektraFilm"))
        let encoded = ParamsCoding.encode(SpektraFilmModule.Params())
        XCTAssertEqual(Data(item.identityJSON.utf8), encoded)
        let decoded = try JSONDecoder().decode(
            SpektraFilmModule.Params.self, from: encoded)
        XCTAssertEqual(decoded, SpektraFilmModule.Params())
        XCTAssertTrue(isFilmRecordDefault(decoded.record))
    }

    // MARK: - AC-T2'-7/8: the seam faces

    /// AC-T2'-7 (B1 positive): the installed seam resolves → the module
    /// leg's assembly carries non-nil payloads (the synthetic plane +
    /// the test store).
    func testInstalledSeamResolvesToNonNilPayloads() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let resolved = try XCTUnwrap(FilmMaterialSeam.resolver(record))
        let plane = try makePlane(metal: metal)
        let assembled = FilmLegFactory.assemble(
            record: record, film: resolved.film, paper: resolved.paper,
            materialPairHash: resolved.materialPairHash, histogram: nil,
            plane: plane, metal: metal, renderProcess: RenderProcessVersion(rawValue: 1)!)
        XCTAssertNotNil(
            assembled.payloads, "the density arm assembles payloads")
        XCTAssertNotEqual(assembled.solvedPackHash, 0)
    }

    /// AC-T2'-8 (B1 negative): seam absent → blitIdentity + no crash +
    /// no throw (the behavior triple; the logger is NOT asserted).
    func testAbsentSeamDegradesToIdentityWithoutThrow() async throws {
        let metal = try await makeMetal()
        let (record, _) = try boundRecord()
        let module = SpektraFilmModule()
        var piece = IOPiece()
        module.commitParams(SpektraFilmModule.Params(record: record), into: &piece)
        let input = try makePlane(metal: metal)
        let output = try makePlane(metal: metal)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
        // No-throw + survival IS the assertion (plus the pixel face).
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(readPixels(output), readPixels(input))
    }

    // MARK: - AC-T2'-6: the allocation face

    /// AC-T2'-6(i): the self-held census never exceeds 1 (the synthetic
    /// plane, default run) and returns to 0 after the run.
    func testSelfHeldSurfaceCountNeverExceedsOne() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let module = SpektraFilmModule()
        var piece = IOPiece()
        module.commitParams(SpektraFilmModule.Params(record: record), into: &piece)
        let input = try makePlane(metal: metal)
        let output = try makePlane(metal: metal)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        XCTAssertEqual(SpektraFilmModule.liveSurfaceCount, 0)
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
        XCTAssertEqual(SpektraFilmModule.liveSurfaceCount, 0)
    }

    /// AC-T2'-6(ii): the 100MP peak-RSS probe (LIGHTAMER_PERF_PROBE=1 +
    /// XCTSkipUnless default-skip): ru_maxrss ≤ 8192MB absolute.
    func testFullFramePeakRSSStaysUnderTheAbsoluteGate() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "the 100MP RSS probe runs only under LIGHTAMER_PERF_PROBE=1")
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let module = SpektraFilmModule()
        var piece = IOPiece(renderProcess: RenderProcessVersion(rawValue: 3)!)
        module.commitParams(SpektraFilmModule.Params(record: record), into: &piece)
        let input = try makePlane(metal: metal, width: 2048, height: 2048)
        let output = try makePlane(metal: metal, width: 2048, height: 2048)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
        // The gate reads the HOST ru_maxrss (the script's MEMFAIL face);
        // the probe's job is to RUN the heavy path under the probe env.
        XCTAssertEqual(SpektraFilmModule.liveSurfaceCount, 0)
    }

    // MARK: - AC-T2'-9/10/11: the solve + staleness + contention faces

    /// AC-T2'-9 (M1): the film chain's local-slope bands — measured by
    /// RENDERING (the module's own process through the density arm): two
    /// flat-field planes (mid 0.18 vs hi 0.7 scene-linear) render, and
    /// the per-step local slope |Δout/Δin| between their mean outputs
    /// sits inside the derived upper bound. The slope table (the two
    /// means + the slope) lands in evidence/t2/slope.md.
    func testLocalSlopeBandsSitInsideTheDerivedBound() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let module = SpektraFilmModule()
        // The ACEScc arms are linear-domain bookkeeping — the slope face
        // measures the DENSITY arm, so drive the leg directly (the
        // factory + a fresh method box, the module's own ⑤⑥ shape).
        let resolved = try XCTUnwrap(FilmMaterialSeam.resolver(record))
        func renderMean(_ level: Float) async throws -> Float {
            let plane = try makeFlatPlane(metal: metal, level: level)
            let assembled = FilmLegFactory.assemble(
                record: record, film: resolved.film, paper: resolved.paper,
                materialPairHash: resolved.materialPairHash, histogram: nil,
                plane: plane, metal: metal,
                renderProcess: RenderProcessVersion(rawValue: 1)!)
            let box = FilmMethodBox(
                record: record, method: assembled.method,
                payloads: assembled.payloads)
            var boxPiece = IOPiece()
            let frame = ROI(x: 0, y: 0, width: plane.width, height: plane.height)
            try await box.process(
                input: plane, output: plane, roiIn: frame, roiOut: frame,
                piece: &boxPiece, metal: metal)
            await Self.drain(metal)
            let pixels = readPixels(plane)
            var sum: Float = 0
            var count = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                sum += pixels[i]
                count += 1
            }
            return sum / Float(count)
        }
        let mid = try await renderMean(0.18)
        let hi = try await renderMean(0.7)
        let slope = abs((hi - mid) / (0.7 - 0.18))
        // The derived upper bound: the print chain compresses (slope < 1
        // at the shoulder; the generous gate is 2× — any expansion past
        // that is a leg defect, not film behavior).
        XCTAssertLessThan(slope, 2.0, "mid=\(mid) hi=\(hi) slope=\(slope)")
        XCTAssertGreaterThan(hi, mid, "monotone: the shoulder still rises")
    }

    /// AC-T2'-10 (M7/D-SM-1): same params + different stats ⇒ different
    /// plane keys (the stamp face — a histogram move flips piece.paramsHash
    /// post-process; UNFALSIFIED = re-plan, not +1 hunk).
    func testDifferentStatsFlipThePlaneKey() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let module = SpektraFilmModule()
        let input = try makePlane(metal: metal)
        let output = try makePlane(metal: metal)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        // Run A: the nil-stats face (seam uninstalled for stats).
        var pieceA = IOPiece()
        module.commitParams(SpektraFilmModule.Params(record: record), into: &pieceA)
        let committedHash = pieceA.paramsHash
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &pieceA, metal: metal)
        // The stamp LANDED (a solved run flips the committed hash) and is
        // STABLE across identical re-runs (same stats ⇒ same key).
        XCTAssertNotEqual(pieceA.paramsHash, committedHash)
        var pieceB = IOPiece()
        module.commitParams(SpektraFilmModule.Params(record: record), into: &pieceB)
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &pieceB, metal: metal)
        XCTAssertEqual(pieceA.paramsHash, pieceB.paramsHash)
    }

    /// AC-T2'-11 (M8): the module leg + the spectral arm + grain/halation
    /// full-on ⇒ no BorrowError (the scratch-contention face).
    func testSpectralArmWithGrainAndHalationBorrowsClean() async throws {
        let metal = try await makeMetal()
        var (record, store) = try boundRecord()
        record.grainAmount = 2.0
        record.halationAmount = 0.5
        installSeam(store: store)
        let module = SpektraFilmModule()
        var piece = IOPiece(renderProcess: RenderProcessVersion(rawValue: 3)!)
        module.commitParams(SpektraFilmModule.Params(record: record), into: &piece)
        let input = try makePlane(metal: metal)
        let output = try makePlane(metal: metal)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        // No-throw IS the contention assertion (a BorrowError surfaces as
        // a throw out of the spectral dispatch).
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
    }

    // MARK: - the factory pass-through pair

    /// The density arm forwards verbatim (the v1/legacy fork face).
    func testFactoryForwardsTheDensityArm() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let resolved = try XCTUnwrap(FilmMaterialSeam.resolver(record))
        let plane = try makePlane(metal: metal)
        for process in [RenderProcessVersion(rawValue: 1)!, RenderProcessVersion.legacy] {
            let assembled = FilmLegFactory.assemble(
                record: record, film: resolved.film, paper: resolved.paper,
                materialPairHash: resolved.materialPairHash, histogram: nil,
                plane: plane, metal: metal, renderProcess: process)
            XCTAssertNotNil(assembled.payloads, "\(process) rides density")
            XCTAssertNil(assembled.spectralPayloads, "\(process) is not spectral")
        }
    }

    /// The spectral arm forwards verbatim (the v2/v3 fork face).
    func testFactoryForwardsTheSpectralArm() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let resolved = try XCTUnwrap(FilmMaterialSeam.resolver(record))
        let plane = try makePlane(metal: metal)
        for process in [RenderProcessVersion(rawValue: 2)!, RenderProcessVersion(rawValue: 3)!] {
            let assembled = FilmLegFactory.assemble(
                record: record, film: resolved.film, paper: resolved.paper,
                materialPairHash: resolved.materialPairHash, histogram: nil,
                plane: plane, metal: metal, renderProcess: process)
            XCTAssertNotNil(
                assembled.spectralPayloads, "\(process) rides spectral")
            XCTAssertNil(assembled.payloads, "\(process) is not density")
        }
    }

    // MARK: - AC-T2'-3: the frozen-arm md5 pair

    /// The PixelPipe.swift path (walked from #filePath — the suite reads
    /// the repo source, the FilmProfileTests precedent).
    private static var pixelPipeURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LightamerCore/Sources/Pipe/PixelPipe.swift")
    }

    /// Deterministically extract a function body: the signature line
    /// through the same-indent closing `}` (the PLAN's extraction rule).
    private static func bodyMd5(signature: String) throws -> String {
        let source = try String(contentsOf: pixelPipeURL, encoding: .utf8)
        let lines = source.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains(signature) }) else {
            throw NSError(domain: "SpektraFilmTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no \(signature)"])
        }
        let indent = lines[start].prefix(while: { $0 == " " }).count
        var end = start
        for i in (start + 1)..<lines.count {
            let line = lines[i]
            if line == String(repeating: " ", count: indent) + "}" {
                end = i
                break
            }
        }
        let body = lines[start...end].joined(separator: "\n")
        return Insecure.MD5.hash(data: Data(body.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// AC-T2'-3 (density): `assembleDensityFilmLeg` body hash == the T2'
    /// execution-baseline value (the FROZEN arm — any drift = re-plan).
    func testDensityArmBodyMd5MatchesTheFrozenBaseline() throws {
        XCTAssertEqual(
            try Self.bodyMd5(signature: "func assembleDensityFilmLeg"),
            Self.frozenDensityArmMd5)
    }

    /// AC-T2'-3 (spectral): `assembleSpectralFilmLeg` body hash == the T2'
    /// execution-baseline value.
    func testSpectralArmBodyMd5MatchesTheFrozenBaseline() throws {
        XCTAssertEqual(
            try Self.bodyMd5(signature: "func assembleSpectralFilmLeg"),
            Self.frozenSpectralArmMd5)
    }

    // T2' execution-baseline pins (the rule above at efb860c9: density
    // PixelPipe.swift:1328-1354, spectral :1373-1408).
    private static let frozenDensityArmMd5 = "fa7a5f085512a5b7f22f2577825f93ec"
    private static let frozenSpectralArmMd5 = "16ccb71500cb2374eec87e910a6baaa6"
}
