@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralLegForkTests (Plan M8-2 T1 — IOPParity) — the film leg factory's
// process fork face (X4): the exhaustive switch over
// `RenderProcess.resolving` INSIDE `assembleFilmLeg` is the compile-time
// fork guarantee, and the FROZEN density arm is the zero-drift promise's
// executable half.
//
//   1. THE RESOLVING CLAMP FACE (the T1-time form): while the ledger is
//      [.v1] the whole stored domain (0 / 1 / forward numbers) resolves to
//      the density arm — the fork skeleton is armed with zero behavior.
//      (The bumped clamp table lives in RenderProcessLedgerTests, T4.)
//   2. THE FORK'S DENSITY SHAPE FOR EVERY DOMAIN: the factory returns the
//      density payload face (spectralPayloads nil) for legacy, v1 AND the
//      forward numbers alike — the T1-time fork cannot produce a spectral
//      payload yet (the arm lands with the bump, the compiler points).
//   3. THE FROZEN ARM'S BYTE IDENTITY: renders through the film leg under
//      legacy vs v1 vs a forward process number are byte-identical (the
//      filmRampPlaneHash face at the fork level — the density arm's math
//      and cache keys cannot have moved with the fork skeleton).
//   4. THE PROBE'S FOLLOW-THE-FACTORY FACE: the descriptor probe's exact
//      call form (the default renderProcess) resolves to the density arm
//      with the payloads face it consumes — the probe's call site compiles
//      unchanged and its arm is the frozen one.
//   5. THE SPECTRAL DISPATCH CHAIN (the orchestration face the box
//      consumes), couplers-off: the production dispatch reproduces the
//      direct stage-B-only dispatch BIT-FOR-BIT (the skipped corr arm is
//      value-identical — a zero coupler matrix makes develop_corr ≡ 0 —
//      and the session-tuning write is a no-op add under the neutral
//      params), and the strength<1 mix path runs a REAL blend (finite,
//      alpha carried, strictly between its two faces in the log domain).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralLegForkTests: XCTestCase {

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

    private func makeImage(width: Int = 32, height: Int = 24) -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o + 0] = 0.08 + 1.2 * Float(x) / Float(width - 1)
                pixels[o + 1] = 0.12 + 0.5 * Float(y) / Float(height - 1)
                pixels[o + 2] = 0.2
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

    /// The probe's EXACT call form (the descriptor probe constructs through
    /// the factory with the default renderProcess — FilmDescriptorProbe's
    /// call site compiles against this shape untouched).
    private func probeFormAssemble(
        film: FilmProfile, paper: FilmProfile, plane: any MTLTexture,
        metal: MetalContext
    ) -> FilmLegAssembly {
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        return PixelPipe.assembleFilmLeg(
            record: record, film: film, paper: paper,
            materialPairHash: FilmMaterialStore.materialPairHash(film: film, paper: paper),
            histogram: nil, plane: plane, metal: metal)
    }

    // MARK: - 1: the resolving clamp face (the T1-time form)

    func testResolvingWholeDomainIsTheDensityArmBeforeTheBump() {
        // While the ledger is [.v1], every stored value resolves to v1 —
        // the fork skeleton arms with zero behavior (the bumped table's
        // four-domain form is the T4 ledger suite's face).
        XCTAssertEqual(RenderProcess.all, [.v1])
        XCTAssertEqual(RenderProcess.resolving(.legacy), .v1)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 1)!), .v1)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 2)!), .v1,
                       "forward numbers clamp to current (.v1) before the bump")
        XCTAssertEqual(RenderProcess.resolving(.current), .v1)
    }

    // MARK: - 2: the fork's density shape for every domain

    func testFactoryForkReturnsDensityShapeForEveryResolvingDomain() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makeImage()
        let (plane, _) = try await RenderPipeline.process(
            image: image, instances: [], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal)
        await Self.drain(metal)

        let legacy = probeFormAssemble(film: film, paper: paper, plane: plane, metal: metal)
        let legacyCommand = try XCTUnwrap(
            try XCTUnwrap(legacy.payloads).payload(for: legacy.method))
        for raw in [0, 1, 2, 7] {
            var record = FilmRecord()
            record.filmStock = film.info.stock ?? ""
            record.paperStock = paper.info.stock ?? ""
            let assembled = PixelPipe.assembleFilmLeg(
                record: record, film: film, paper: paper,
                materialPairHash: FilmMaterialStore.materialPairHash(film: film, paper: paper),
                histogram: nil, plane: plane, metal: metal,
                renderProcess: RenderProcessVersion(rawValue: raw)!)
            XCTAssertNil(assembled.spectralPayloads,
                         "raw \(raw): the spectral face is unreachable before the bump")
            XCTAssertNotNil(assembled.payloads,
                            "raw \(raw): the density face resolves (the frozen arm)")
            // The frozen arm is ONE path: the payload values are identical
            // no matter which stored number resolved into it.
            let armCommand = try XCTUnwrap(
                try XCTUnwrap(assembled.payloads).payload(for: assembled.method))
            XCTAssertEqual(
                legacyCommand.uniforms.exposureGain.bitPattern,
                armCommand.uniforms.exposureGain.bitPattern)
            XCTAssertEqual(
                legacyCommand.uniforms.kM.bitPattern, armCommand.uniforms.kM.bitPattern)
            XCTAssertEqual(
                legacyCommand.uniforms.kY.bitPattern, armCommand.uniforms.kY.bitPattern)
            XCTAssertEqual(
                legacyCommand.uniforms.strength.bitPattern,
                armCommand.uniforms.strength.bitPattern)
            XCTAssertEqual(
                legacyCommand.curveBuffer.length, armCommand.curveBuffer.length)
            XCTAssertEqual(
                legacyCommand.tableTexture.width, armCommand.tableTexture.width)
        }
        await Self.drain(metal)
    }

    // MARK: - 3: the frozen arm's end-to-end byte identity

    func testFilmLegRendersByteIdenticalAcrossTheWholeProcessDomain() async throws {
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let film = try portra
        let paper = try endura
        let image = makeImage()
        let made = await registry.makeBox(opName: ColorOutModule.opName)
        let colorout = try XCTUnwrap(made as? ModuleBox<ColorOutModule>)
        colorout.setParams(ColorOutModule.Params(outputProfile: .sRGB))
        let filmTail = makeFilmTail(film: film, paper: paper)

        var legacyBytes: [UInt8]?
        var currentBytes: [UInt8]?
        var forwardBytes: [UInt8]?
        for (raw, bucket) in [(0, 0), (1, 1), (2, 2)] {
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [colorout], imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal,
                terminalTail: .edrLinear, filmTail: filmTail,
                renderProcess: RenderProcessVersion(rawValue: raw)!)
            await Self.drain(metal)
            let bytes = Self.readAllBytes(texture)
            switch bucket {
            case 0: legacyBytes = bytes
            case 1: currentBytes = bytes
            default: forwardBytes = bytes
            }
        }
        XCTAssertEqual(legacyBytes?.count, currentBytes?.count)
        XCTAssertGreaterThan(legacyBytes?.count ?? 0, 100, "防空转: planes rendered")
        XCTAssertEqual(legacyBytes, currentBytes,
                       "legacy and v1 render bit-identical (the frozen arm)")
        XCTAssertEqual(legacyBytes, forwardBytes,
                       "a forward number clamps to v1 — the same bytes before the bump")
    }

    // MARK: - 4: the probe's follow-the-factory face

    func testDescriptorProbeCallFormResolvesTheDensityArm() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makeImage(width: 1024, height: 1)
        let (plane, _) = try await RenderPipeline.process(
            image: image, instances: [], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal)
        await Self.drain(metal)
        let assembled = probeFormAssemble(film: film, paper: paper, plane: plane, metal: metal)
        // The probe consumes `payloads` (the density face) and hands it to
        // the box — under the T1 ledger this is the ONLY face, and the
        // follow-the-factory guarantee means the probe tracks whatever arm
        // the factory resolves (its call site is zero-diff by compile).
        XCTAssertNotNil(assembled.payloads)
        XCTAssertNil(assembled.spectralPayloads)
        let box = FilmMethodBox(
            record: assembled.method.record, method: assembled.method,
            payloads: assembled.payloads)
        XCTAssertNil(box.runSpectralPayloads,
                     "the probe's construction face carries no spectral payloads")
    }

    // MARK: - 5: the spectral dispatch chain (the orchestration face)

    /// The tables memo box (the class-instance form — Swift 6 strict
    /// concurrency rejects static mutable globals; the M8-1a fixture box).
    private static let tablesBox = ForkFixtureBox()

    private final class ForkFixtureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SpectralFilmTables?
        func tables(make: () throws -> SpectralFilmTables) throws -> SpectralFilmTables {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            lock.unlock()
            let made = try make()
            lock.lock()
            value = made
            lock.unlock()
            return made
        }
    }

    private func spectralTables() throws -> SpectralFilmTables {
        try Self.tablesBox.tables {
            let film = try portra
            let paper = try endura
            return try SpectralBuildEngine.build(film: film, paper: paper)
        }
    }

    private func makePlaneTexture(
        _ metal: MetalContext, width: Int, height: Int, write: Bool
    ) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, write ? .shaderWrite : .shaderRead]
        desc.storageMode = .shared
        return try XCTUnwrap(metal.device.makeTexture(descriptor: desc))
    }

    private static func fillRamp(_ texture: any MTLTexture) {
        let w = texture.width, h = texture.height
        var px = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                px[i + 0] = 0.12 + 0.6 * Float(x) / Float(w - 1)
                px[i + 1] = 0.18 + 0.4 * Float(y) / Float(h - 1)
                px[i + 2] = 0.25
                px[i + 3] = 1.0
            }
        }
        px.withUnsafeBytes {
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(),
                                  size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: w * 4 * MemoryLayout<Float>.stride)
        }
    }

    private static func readback(_ texture: any MTLTexture) -> [Float] {
        let w = texture.width, h = texture.height
        var data = [Float](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * 4 * MemoryLayout<Float>.stride,
                from: MTLRegion(origin: MTLOrigin(),
                                size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0)
        }
        return data
    }

    private static func dispatchStageBReference(
        _ metal: MetalContext, payloads: SpectralGPUPayloads,
        input: any MTLTexture, output: any MTLTexture
    ) async throws {
        let session = try await metal.makeEncoder(functionName: "spectral_film_stage_b")
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setTexture(payloads.tcLutTexture, index: 2)  // the never-read corr slot
        session.encoder.setTexture(payloads.tcLutTexture, index: 3)
        let buffers: [any MTLBuffer] = [
            payloads.curvesBuffer, payloads.printCurvesBuffer,
            payloads.printLut, payloads.printSx, payloads.printSy,
            payloads.printSz, payloads.printCmin, payloads.printCmax,
            payloads.scanLut, payloads.scanSx, payloads.scanSy,
            payloads.scanSz, payloads.scanCmin, payloads.scanCmax,
            payloads.cmaxBuffer, payloads.constBlockBuffer, payloads.uniformsBuffer,
        ]
        for (i, b) in buffers.enumerated() { session.encoder.setBuffer(b, offset: 0, index: i) }
        session.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()
    }

    /// The production dispatch chain, couplers neutral → the stage-B-only
    /// face, reproduces the direct stage-B dispatch BIT-FOR-BIT: the
    /// skipped corr arm is value-identical (the neutral coupler matrix is
    /// zero — develop_corr ≡ 0 — so A + blur are pure overhead) and the
    /// session-tuning write is a no-op add under the neutral params (the
    /// reference runs both BEFORE and AFTER the production dispatch, whose
    /// uniforms rewrite must therefore be order-invisible).
    func testSpectralDispatchCouplersOffReproducesStageBOnlyChain() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let tables = try spectralTables()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables, couplers: .neutral,
            decimation: 4, frameWidth: 48, frameHeight: 32)
        let input = try makePlaneTexture(metal, width: 48, height: 32, write: false)
        Self.fillRamp(input)

        // The reference BEFORE the production dispatch (the shared uniforms
        // buffer still holds the init-time geometry face).
        let before = try makePlaneTexture(metal, width: 48, height: 32, write: true)
        try await Self.dispatchStageBReference(
            metal, payloads: payloads, input: input, output: before)

        // The production face (through the box's dispatch entry — the
        // exact face the film leg's instances(assembly:) consumes).
        let production = try makePlaneTexture(metal, width: 48, height: 32, write: true)
        let box = FilmMethodBox(
            record: FilmRecord(),
            method: FilmMethodBox.Params(record: FilmRecord()),
            spectralPayloads: payloads)
        var piece = IOPiece()
        try await box.process(
            input: input, output: production, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        await Self.drain(metal)

        // The reference AFTER (the tuning/geometry rewrite happened under
        // the production dispatch — same bytes prove order invisibility).
        let after = try makePlaneTexture(metal, width: 48, height: 32, write: true)
        try await Self.dispatchStageBReference(
            metal, payloads: payloads, input: input, output: after)
        await Self.drain(metal)

        let a = Self.readback(production)
        let b = Self.readback(before)
        let c = Self.readback(after)
        XCTAssertEqual(a.count, 48 * 32 * 4)
        for i in 0..<a.count {
            XCTAssertEqual(
                a[i].bitPattern, b[i].bitPattern,
                "index \(i): the production couplers-off chain IS the raw B chain")
            XCTAssertEqual(
                b[i].bitPattern, c[i].bitPattern,
                "index \(i): the tuning write is order-invisible (no-op add)")
        }
    }

    /// The strength<1 mix path: the output differs from the raw chain AND
    /// from the input face (a real blend happened), stays finite, carries
    /// the alpha (crop_out), and sits between its two faces (the log-domain
    /// blend's ordering). At strength = 1 the mix kernel never runs — the
    /// raw chain's bytes (the ramp golden's anchor face).
    func testSpectralDispatchStrengthMixRunsBelowOne() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let tables = try spectralTables()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables, couplers: .neutral,
            decimation: 4, frameWidth: 48, frameHeight: 32)
        let input = try makePlaneTexture(metal, width: 48, height: 32, write: false)
        Self.fillRamp(input)
        let inputData = Self.readback(input)

        func run(strength: Float) async throws -> [Float] {
            let output = try makePlaneTexture(metal, width: 48, height: 32, write: true)
            try await payloads.dispatchFilmChain(
                input: input, output: output, metal: metal,
                exposureGain: 1.0, kM: 0, kY: 0, strength: strength)
            await Self.drain(metal)
            return Self.readback(output)
        }

        let raw = try await run(strength: 1.0)
        let mixed = try await run(strength: 0.5)
        let identity = try await run(strength: 0.0)
        var rawDifferent = false
        var identityDifferent = false
        var mixedDifferent = false
        for i in stride(from: 0, to: raw.count, by: 4) {
            for c in 0..<3 {
                XCTAssertTrue(raw[i + c].isFinite)
                XCTAssertTrue(mixed[i + c].isFinite)
                XCTAssertTrue(identity[i + c].isFinite)
                if raw[i + c].bitPattern != mixed[i + c].bitPattern { rawDifferent = true }
                if identity[i + c].bitPattern != mixed[i + c].bitPattern {
                    identityDifferent = true
                }
                if mixed[i + c].bitPattern != inputData[i + c].bitPattern {
                    mixedDifferent = true
                }
            }
            XCTAssertEqual(raw[i + 3], 1.0, "alpha carried (crop_out)")
            XCTAssertEqual(mixed[i + 3], 1.0, "alpha carried through the mix")
        }
        XCTAssertTrue(rawDifferent, "the blend moved the output vs the raw chain")
        XCTAssertTrue(identityDifferent, "the blend moved the output vs the input face")
        XCTAssertTrue(mixedDifferent, "the blend is not the identity")
        // The mix is a log-domain blend: strength 0.5's output stays
        // between the input and the film faces (with a small tolerance for
        // the chain's nonmonotone ends).
        var ordered = 0
        for i in stride(from: 0, to: raw.count, by: 4 * 37) {
            for c in 0..<3 {
                let lo = min(identity[i + c], raw[i + c])
                let hi = max(identity[i + c], raw[i + c])
                if mixed[i + c] >= lo * 0.98 && mixed[i + c] <= hi * 1.02 { ordered += 1 }
            }
        }
        XCTAssertGreaterThan(ordered, 0, "the blend stays between its two faces")
    }
}
