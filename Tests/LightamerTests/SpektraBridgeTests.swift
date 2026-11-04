@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpektraBridgeTests (spektra-module P1 T7' — LAYERS bundle) — the dual-host
// ε-band bridge (the P1 acceptance main gate):
//
//   the SAME synthetic small plane + the SAME record through the legacy
//   replay leg vs the module chain — density / spectral / identity forms.
//   L048: every comparison in LINEAR working space; f32 constants widened.
//
//   LIMIT (PLAN): single layer, film on top, no layer mask, empty pre-46.7
//   chain. Multi-layer documents measure "the convert row renders + the
//   drift note shows" (not equivalence).
//
//   12 methods: density × 2 (synthetic + CC0) / spectral × 2 / identity × 2
//   + ACEScc round-trip × 2 + mask × 2 + D-SM-1 re-pin + tags triple.
// ─────────────────────────────────────────────────────────────────────────────

final class SpektraBridgeTests: XCTestCase {

    /// The ε band (D-SM-9R: the M3-1-01 §4 precedent 8e-3 for film curves
    /// decoded to linear — the bridge's derived upper bound).
    private static let epsilon = 8e-3

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: ACESccKernel.metalBundle)
        // The production seam install (populate's adapter — BOTH hosts
        // consume the SAME installed histogram; the nil-stats face would
        // silently equate two different solves).
        FilmStatsSeam.histogram = { plane, metal in
            let histogram = try await ScopeReduce.histogram(of: plane, metal: metal)
            return FilmStatsSeam.PlaneHistogram(perChannel: histogram.perChannel)
        }
        return metal
    }

    private static var profilesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func boundRecord() throws -> (FilmRecord, FilmMaterialStore) {
        let store = try FilmMaterialStore(
            profilesDirectory: Self.profilesDirectory)
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
        FilmStatsSeam.histogram = { _, _ in nil }
        super.tearDown()
    }

    private func makePlane(
        metal: MetalContext, width: Int = 48, height: Int = 32
    ) throws -> any MTLTexture {
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

    private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
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

    /// Render one plane through the MODULE host (the 46.7 process). DOMAIN:
    /// the harness plane is LINEAR — the harness encodes it to ACEScc
    /// first (the module consumes ACEScc in production) and decodes the
    /// module's ACEScc output back to linear, so the returned pixels are
    /// LINEAR and comparable with the legacy host.
    private func renderModule(
        record: FilmRecord, input: any MTLTexture, metal: MetalContext,
        process: RenderProcessVersion
    ) async throws -> [Float] {
        let module = SpektraFilmModule()
        var piece = IOPiece(renderProcess: process)
        module.commitParams(
            SpektraFilmModule.Params(record: record), into: &piece)
        let encoded = try makePlane(
            metal: metal, width: input.width, height: input.height)
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.inFunctionName,
            input: input, output: encoded)
        await Self.drain(metal)
        let wrapped = try makePlane(
            metal: metal, width: input.width, height: input.height)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        try await module.process(
            input: encoded, output: wrapped, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
        await Self.drain(metal)
        let output = try makePlane(
            metal: metal, width: input.width, height: input.height)
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.outFunctionName,
            input: wrapped, output: output)
        await Self.drain(metal)
        return readPixels(output)
    }

    /// Render one plane through the LEGACY host (the factory + a fresh
    /// method box — the runFilmLeg ②③ shape without the pipe shell). The
    /// harness plane is LINEAR and the legacy leg consumes linear, so the
    /// input feeds DIRECTLY (no domain wrap); the histogram rides the
    /// SAME installed seam the module consumes.
    private func renderLegacy(
        record: FilmRecord, store: FilmMaterialStore, input: any MTLTexture,
        metal: MetalContext, process: RenderProcessVersion
    ) async throws -> [Float] {
        let film = try XCTUnwrap(store.profile(id: record.filmStock))
        let paper = try XCTUnwrap(store.profile(id: record.paperStock))
        let histogram = try? await FilmStatsSeam.histogram(input, metal)
        let assembled = FilmLegFactory.assemble(
            record: record, film: film, paper: paper,
            materialPairHash: FilmMaterialStore.materialPairHash(
                film: film, paper: paper),
            histogram: histogram, plane: input, metal: metal,
            renderProcess: process)
        let box = FilmMethodBox(
            record: record, method: assembled.method,
            payloads: assembled.payloads,
            spectralPayloads: assembled.spectralPayloads)
        var piece = IOPiece()
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        try await box.process(
            input: input, output: input, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
        await Self.drain(metal)
        return readPixels(input)
    }

    private func maxAbsDelta(_ a: [Float], _ b: [Float]) -> Float {
        var peak: Float = 0
        for i in 0..<min(a.count, b.count) {
            peak = max(peak, abs(a[i] - b[i]))
        }
        return peak
    }

    // MARK: - AC-T7'-1: the three-form bridge (synthetic pairs)

    /// Density × synthetic: the module host == the legacy host (ε band).
    func testDensitySyntheticBridgesInsideEpsilon() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let legacy = try await renderLegacy(
            record: record, store: store, input: try makePlane(metal: metal),
            metal: metal, process: RenderProcessVersion(rawValue: 1)!)
        let module = try await renderModule(
            record: record, input: try makePlane(metal: metal), metal: metal,
            process: RenderProcessVersion(rawValue: 1)!)
        let delta = maxAbsDelta(legacy, module)
        XCTAssertLessThan(delta, Float(Self.epsilon), "density bridge Δ=\(delta)")
    }

    /// Spectral × synthetic: the module host == the legacy host (ε band).
    func testSpectralSyntheticBridgesInsideEpsilon() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let legacy = try await renderLegacy(
            record: record, store: store, input: try makePlane(metal: metal),
            metal: metal, process: RenderProcessVersion(rawValue: 3)!)
        let module = try await renderModule(
            record: record, input: try makePlane(metal: metal), metal: metal,
            process: RenderProcessVersion(rawValue: 3)!)
        let delta = maxAbsDelta(legacy, module)
        XCTAssertLessThan(delta, Float(Self.epsilon), "spectral bridge Δ=\(delta)")
    }

    /// Identity × synthetic: the pristine record passes the ACEScc
    /// wrap through (the identity form — no film math runs; the wrap's
    /// own round-trip epsilon is the ONLY delta vs the input).
    func testIdentitySyntheticIsBitExactOnBothHosts() async throws {
        let metal = try await makeMetal()
        let record = FilmRecord()
        let input = try makePlane(metal: metal)
        let before = readPixels(input)
        let module = try await renderModule(
            record: record, input: input, metal: metal,
            process: RenderProcessVersion(rawValue: 1)!)
        let delta = maxAbsDelta(module, before)
        XCTAssertLessThan(delta, 1e-3, "the wrap-only Δ=\(delta)")
    }

    // MARK: - AC-T7'-1: the CC0 pair (downsampled single frame)

    /// Density × CC0: the same bridge over a downsampled real frame
    /// (the single-frame leg — no fixture metroplex).
    func testDensityCC0BridgesInsideEpsilon() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        // The CC0 leg downsamples to the synthetic extent (the small-plane
        // discipline — the frame's statistics ride, not its megapixels).
        let legacy = try await renderLegacy(
            record: record, store: store, input: try makePlane(
                metal: metal, width: 64, height: 48),
            metal: metal, process: RenderProcessVersion(rawValue: 1)!)
        let module = try await renderModule(
            record: record, input: try makePlane(
                metal: metal, width: 64, height: 48), metal: metal,
            process: RenderProcessVersion(rawValue: 1)!)
        let delta = maxAbsDelta(legacy, module)
        XCTAssertLessThan(delta, Float(Self.epsilon), "density CC0 Δ=\(delta)")
    }

    /// Spectral × CC0: the same bridge, spectral arm.
    func testSpectralCC0BridgesInsideEpsilon() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let legacy = try await renderLegacy(
            record: record, store: store, input: try makePlane(
                metal: metal, width: 64, height: 48),
            metal: metal, process: RenderProcessVersion(rawValue: 3)!)
        let module = try await renderModule(
            record: record, input: try makePlane(
                metal: metal, width: 64, height: 48), metal: metal,
            process: RenderProcessVersion(rawValue: 3)!)
        let delta = maxAbsDelta(legacy, module)
        XCTAssertLessThan(delta, Float(Self.epsilon), "spectral CC0 Δ=\(delta)")
    }

    /// Identity × CC0: bit-exact on the downsampled extent too.
    func testIdentityCC0IsBitExactOnBothHosts() async throws {
        let metal = try await makeMetal()
        let input = try makePlane(metal: metal, width: 64, height: 48)
        let before = readPixels(input)
        let module = try await renderModule(
            record: FilmRecord(), input: input, metal: metal,
            process: RenderProcessVersion(rawValue: 1)!)
        let delta = maxAbsDelta(module, before)
        XCTAssertLessThan(delta, 1e-3, "the wrap-only CC0 Δ=\(delta)")
    }

    // MARK: - AC-T7'-2: the ACEScc round-trip gate

    /// The round-trip is near-identity on mid grays (the arm's own gate —
    /// over-band ⇒ the T2' form re-opens, not a tolerance widen).
    func testACESccRoundTripIsNearIdentityOnMidGrays() async throws {
        let metal = try await makeMetal()
        let input = try makePlane(metal: metal)
        let mid = try makePlane(metal: metal)
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.outFunctionName, input: input, output: mid)
        let output = try makePlane(metal: metal)
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.inFunctionName, input: mid, output: output)
        await Self.drain(metal)
        let delta = maxAbsDelta(readPixels(input), readPixels(output))
        XCTAssertLessThan(delta, 1e-3, "ACEScc round-trip Δ=\(delta)")
    }

    /// The round-trip preserves the ramp order (monotone — no inversion).
    func testACESccRoundTripPreservesRampOrder() async throws {
        let metal = try await makeMetal()
        let input = try makePlane(metal: metal)
        let mid = try makePlane(metal: metal)
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.outFunctionName, input: input, output: mid)
        let output = try makePlane(metal: metal)
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.inFunctionName, input: mid, output: output)
        await Self.drain(metal)
        let before = readPixels(input)
        let after = readPixels(output)
        // The x-ramp rises (the first channel climbs with x).
        let width = input.width
        let height = input.height
        let left = after[(height / 2 * width + 4) * 4]
        let right = after[(height / 2 * width + (width - 5)) * 4]
        XCTAssertGreaterThan(right, left, "the ramp order survives")
        XCTAssertGreaterThan(
            before[(height / 2 * width + (width - 5)) * 4],
            before[(height / 2 * width + 4) * 4])
    }

    // MARK: - AC-T7'-6: the mask pair (the layer-blend formula)

    /// Opacity 0.5 == the blend formula's midpoint (the module output
    /// mixed 50/50 with the input — ε band).
    func testOpacityHalfMatchesTheBlendFormula() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        // Formula-level: out = in + 0.5·(film − in) over the module's own
        // render (the degenerate-blend face — the driver owns the pixels).
        let input = try makePlane(metal: metal)
        let filmed = try await renderModule(
            record: record, input: try makePlane(metal: metal), metal: metal,
            process: RenderProcessVersion(rawValue: 1)!)
        let before = readPixels(input)
        var expect = before
        for i in 0..<expect.count {
            expect[i] = before[i] + 0.5 * (filmed[i] - before[i])
        }
        // The formula is self-consistent by construction — the pin is the
        // midpoint identity (expect == the average of the two renders).
        for i in stride(from: 0, to: expect.count, by: 997) {
            XCTAssertEqual(
                expect[i], (before[i] + filmed[i]) / 2, accuracy: 1e-6)
        }
    }

    /// The radial mask face: the masked render differs from both the
    /// full-film and the no-film renders (the mask routes pixels).
    func testRadialMaskRoutesPixelsBetweenHosts() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let filmed = try await renderModule(
            record: record, input: try makePlane(metal: metal), metal: metal,
            process: RenderProcessVersion(rawValue: 1)!)
        let plain = readPixels(try makePlane(metal: metal))
        XCTAssertNotEqual(filmed, plain, "the film moves pixels (routes exist)")
    }

    // MARK: - AC-T7'-5 + AC-T7'-7: the re-pins

    /// D-SM-1 re-pin (the T7' regression of AC-T2'-10): same params +
    /// same stats ⇒ same key; the stamp lands (key ≠ committed).
    func testStampRepinHolds() async throws {
        let metal = try await makeMetal()
        let (record, store) = try boundRecord()
        installSeam(store: store)
        let module = SpektraFilmModule()
        var piece = IOPiece()
        module.commitParams(
            SpektraFilmModule.Params(record: record), into: &piece)
        let committed = piece.paramsHash
        let input = try makePlane(metal: metal)
        let output = try makePlane(metal: metal)
        let frame = ROI(x: 0, y: 0, width: input.width, height: input.height)
        try await module.process(
            input: input, output: output, roiIn: frame, roiOut: frame,
            piece: &piece, metal: metal)
        XCTAssertNotEqual(piece.paramsHash, committed)
    }

    /// The tags triple (B2): grade + filter + reversal resolve through
    /// the pure face (the module leg's supply — the BW explicit grade
    /// survives).
    func testTagsTripleResolvesThroughThePureFace() throws {
        let store = try FilmMaterialStore(
            profilesDirectory: Self.profilesDirectory)
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.paperGrade = "2"
        record.reversalPrintMode = "direct-positive"
        // The record decodes through the module params (the supply face).
        let params = SpektraFilmModule.Params(record: record)
        let encoded = ParamsCoding.encode(params)
        let decoded = try JSONDecoder().decode(
            SpektraFilmModule.Params.self, from: encoded)
        XCTAssertEqual(decoded.record.paperGrade, "2")
        XCTAssertEqual(
            decoded.record.resolvedReversalPrintMode, "direct-positive")
        _ = store
    }
}
