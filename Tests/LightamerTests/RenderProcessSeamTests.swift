@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RenderProcessSeamTests (Plan M6-2-01 T2, KD-5/KD-6 — LAYERS bundle, the
// DrtTailTests pipe harness + the IOPieceIscaleTests test-local probe form)
// — the run-scoped render process seam:
//
//   1. THE IOPiece STAMP (KD-5): forwardWalk stamps the pipe's
//      renderProcess onto every piece (the iscale/pipeType run-constant
//      family) — 0 and 1 each proven through a real run.
//   2. G3 ZERO-BEHAVIOR GATE (OQ-4): the REAL production chain (terminal
//      trio) renders process 0 vs 1 BIT-IDENTICAL (no fork exists yet).
//   3. G2 FROZEN GATE (①): the test-local fork double's legacy arm output
//      == the passthrough baseline, and STILL == after the double has
//      gained its ≥1 arm (the cross-simulation: a legacy value can never
//      reach the new arm — the freeze made executable).
//   4. G2 FORK-VISIBLE GATE (②): renderProcess 1 through the same double
//      diverges from the baseline (the seam is not decoration).
//   5. G2 MISSING-KEY = LEGACY ARM (③): a v10 document WITHOUT the key
//      decodes to nil → `.legacy` → the pipe runs the legacy arm (the
//      sidecar→pipe value flow, the LightCraft
//      settings_saved_before_process_versions_load_as_v1 analog).
//   6. THE CACHE-KEY FACE (KD-6): same chain + params, only the process
//      value different → identical keys (the second run ALL-HITS).
//   7. FORWARD NUMBERS (OQ-3): the pipe face stamps verbatim (7 stays 7 —
//      the clamp lives at the future `RenderProcess.resolving` consumption
//      point, never at the stamp).
//   8. DERIVED-PIPE INHERITANCE (KD-5/checker M3): the composite's
//      terminal-leg sub-run pipe inherits the composite's value (the
//      iopOrder ≥ 70 split leg).
// ─────────────────────────────────────────────────────────────────────────────

final class RenderProcessSeamTests: XCTestCase {

    // MARK: - The test-local fork double (the IscaleProbe form)

    /// Records the stamped `piece.renderProcess` per execution.
    private actor ProbeRecorder {
        struct Entry: Sendable {
            var tag: String
            var raw: Int
        }
        private(set) var entries: [Entry] = []
        func record(tag: String, raw: Int) {
            entries.append(Entry(tag: tag, raw: raw))
        }
    }

    /// Swift mirror of the MSL `TestGainUniforms` (16-byte stride).
    private struct ProbeGainUniforms {
        var gain: Float
        private var _pad: (Float, Float, Float) = (0, 0, 0)
        init(gain: Float) { self.gain = gain }
    }

    /// THE fork double (test registry only — never a production op): the
    /// legacy arm (raw 0) = blit passthrough (= the passthrough baseline);
    /// the v1 arm (raw ≥ 1) = the shared `test_gain` kernel at gain 2.0
    /// (a visible bit-level fork). Every execution records the raw value.
    /// The FORK ITSELF simulates a future iop semantic change — the whole
    /// point is that the legacy value provably cannot reach the v1 arm.
    private class ProcessProbeModule: IOPModule {
        struct Params: Codable, Hashable { var tag: String = "" }
        class var opName: String { "process_probe" }
        class var iopOrder: Float { 50.5 }
        static var flags: IOPFlags { [] }
        static var defaultColorspace: IOPColorspace { .RGB }
        let tag: String
        let recorder: ProbeRecorder
        init(tag: String, recorder: ProbeRecorder) {
            self.tag = tag
            self.recorder = recorder
        }
        func reloadDefaults(image: DecodedImage) async -> Params { Params(tag: tag) }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) { roi = input }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) { input = roi }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            await recorder.record(tag: tag, raw: piece.renderProcess.rawValue)
            if piece.renderProcess.rawValue > 0 {
                var uniforms = ProbeGainUniforms(gain: 2.0)
                try await metal.dispatch2DTexture(
                    functionName: TestGainKernel.functionName,
                    input: input, output: output) { encoder in
                        encoder.setBytes(
                            &uniforms,
                            length: MemoryLayout<ProbeGainUniforms>.stride,
                            index: 0)
                    }
                return
            }
            // The legacy arm: identity blit (the passthrough baseline).
            guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder()
            else {
                throw AppError.decodeFailed("ProcessProbe blit: no command buffer")
            }
            blit.copy(
                from: input, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(
                    x: roiOut.x - roiIn.x, y: roiOut.y - roiIn.y, z: 0),
                sourceSize: MTLSize(
                    width: roiOut.width, height: roiOut.height, depth: 1),
                to: output, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding() // L008
            commandBuffer.commit()
        }
    }

    /// The terminal-slot twin (iopOrder ≥ 70 → the composite's terminal
    /// chain — the splitTerminal seam) for the derived-pipe inheritance
    /// test. Same fork body, slot 75.
    private final class ProcessProbeTerminalModule: ProcessProbeModule {
        override class var opName: String { "process_probe_terminal" }
        override class var iopOrder: Float { 75.0 }
    }

    // MARK: - Fixtures (the DrtTailTests harness)

    private static let fixtureImageID = UUID(
        uuidString: "E4C5D6A7-0000-4000-8000-00000000E4C5")!

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeImage(width: Int = 48, height: Int = 32) -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o + 0] = 0.1 + 0.7 * Float(x) / Float(width - 1)
                pixels[o + 1] = 0.2 + 0.5 * Float(y) / Float(height - 1)
                pixels[o + 2] = 0.3 + 0.3 * Float(x + y) / Float(width + height - 2)
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
            decoderVersionUsed: .v8
        )
    }

    /// The REAL production terminal pair, committed (the D-COL4 display
    /// face) — the G3 zero-behavior gate's real chain.
    private func makeTerminalChain(
        registry: ModuleRegistry, outputProfile: ColorOutModule.OutputProfile = .sRGB
    ) async throws -> [any ModuleBoxing] {
        var chain = [any ModuleBoxing]()
        let coloroutMade = await registry.makeBox(opName: ColorOutModule.opName)
        let colorout = try XCTUnwrap(coloroutMade as? ModuleBox<ColorOutModule>)
        colorout.setParams(ColorOutModule.Params(outputProfile: outputProfile))
        chain.append(colorout)
        let gammaMade = await registry.makeBox(opName: GammaModule.opName)
        let gamma = try XCTUnwrap(gammaMade as? ModuleBox<GammaModule>)
        gamma.setParams(GammaModule.Params())
        chain.append(gamma)
        return chain
    }

    /// L014: never read a plane across in-flight encoders.
    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func render(
        _ image: DecodedImage, _ boxes: [any ModuleBoxing],
        renderProcess: RenderProcessVersion,
        resolution: PipeResolution = .preview,
        cache: PipeCache = PipeCache(), metal: MetalContext
    ) async throws -> (any MTLTexture, RenderPipeline.PipeRunStats) {
        let result = try await RenderPipeline.process(
            image: image, instances: boxes, imageID: Self.fixtureImageID,
            resolution: resolution, cache: cache, metal: metal,
            renderProcess: renderProcess)
        await Self.drain(metal)
        return result
    }

    private func readBytes(_ texture: any MTLTexture) -> [UInt8] {
        let bytesPerPx: Int
        switch texture.pixelFormat {
        case .rgba16Float: bytesPerPx = 8
        case .bgra8Unorm, .rgba8Unorm, .bgra8Unorm_srgb: bytesPerPx = 4
        default: bytesPerPx = 16
        }
        let w = texture.width, h = texture.height
        let rowBytes = w * bytesPerPx
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    // MARK: - 1: the IOPiece stamp (0 and 1, through real runs)

    func testIOPieceStampCarriesLegacyAndCurrent() async throws {
        let metal = try await makeMetal()
        let image = makeImage()
        for (version, want) in [(RenderProcessVersion.legacy, 0),
                                (RenderProcessVersion.current, 1)] {
            let recorder = ProbeRecorder()
            let probe = ModuleBox(
                module: ProcessProbeModule(tag: "p", recorder: recorder),
                multiPriority: 0, multiName: "p")
            probe.setParams(ProcessProbeModule.Params(tag: "p"))
            _ = try await render(
                image, [probe], renderProcess: version, metal: metal)
            let entries = await recorder.entries
            XCTAssertEqual(entries.count, 1, "\(want): probe executed once")
            XCTAssertEqual(entries.first?.raw, want, "the stamp rode the piece")
        }
    }

    // MARK: - 2: G3 — the real chain renders 0 vs 1 bit-identical

    func testRealChainRendersProcessZeroAndOneBitIdentical() async throws {
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let chain = try await makeTerminalChain(registry: registry)
        let image = makeImage()
        let legacy = try await render(image, chain, renderProcess: .legacy, metal: metal)
        let current = try await render(image, chain, renderProcess: .current, metal: metal)
        let legacyBytes = readBytes(legacy.0)
        let currentBytes = readBytes(current.0)
        XCTAssertEqual(legacyBytes.count, currentBytes.count)
        XCTAssertGreaterThan(legacyBytes.count, 100, "防空转: planes rendered")
        XCTAssertEqual(
            legacyBytes, currentBytes,
            "M6-2 has no semantic fork — 0 and 1 must render bit-identical")
    }

    // MARK: - 3: G2① — the frozen gate (the legacy arm stays on baseline)

    func testLegacyArmStaysOnTheBaselineAcrossTheSimulatedFork() async throws {
        let metal = try await makeMetal()
        let image = makeImage()

        // The passthrough baseline: a blit-only probe (the legacy arm, run
        // through the same pipe mechanics).
        let baselineRecorder = ProbeRecorder()
        let baselineProbe = ModuleBox(
            module: ProcessProbeModule(tag: "base", recorder: baselineRecorder),
            multiPriority: 0, multiName: "base")
        baselineProbe.setParams(ProcessProbeModule.Params(tag: "base"))
        let baseline = try await render(
            image, [baselineProbe], renderProcess: .legacy, metal: metal)
        let baselineBytes = readBytes(baseline.0)
        XCTAssertGreaterThan(baselineBytes.count, 100, "防空转")

        // The fork double ALREADY carries the ≥1 arm in this build (the
        // "semantic change has shipped" state). The legacy value STILL
        // renders exactly the baseline — the freeze made executable.
        let legacyRecorder = ProbeRecorder()
        let legacyProbe = ModuleBox(
            module: ProcessProbeModule(tag: "legacy", recorder: legacyRecorder),
            multiPriority: 0, multiName: "legacy")
        legacyProbe.setParams(ProcessProbeModule.Params(tag: "legacy"))
        let frozen = try await render(
            image, [legacyProbe], renderProcess: .legacy, metal: metal)
        XCTAssertEqual(
            readBytes(frozen.0), baselineBytes,
            "the legacy value can never reach the fork arm (G2①)")
    }

    // MARK: - 4: G2② — the fork-visible gate (the seam is not decoration)

    func testForkArmIsVisibleForTheCurrentProcess() async throws {
        let metal = try await makeMetal()
        let image = makeImage()

        let baselineRecorder = ProbeRecorder()
        let baselineProbe = ModuleBox(
            module: ProcessProbeModule(tag: "base", recorder: baselineRecorder),
            multiPriority: 0, multiName: "base")
        baselineProbe.setParams(ProcessProbeModule.Params(tag: "base"))
        let baseline = try await render(
            image, [baselineProbe], renderProcess: .legacy, metal: metal)
        let baselineBytes = readBytes(baseline.0)

        // The same double at process 1 diverges — the seam is real.
        let forkedRecorder = ProbeRecorder()
        let forkedProbe = ModuleBox(
            module: ProcessProbeModule(tag: "fork", recorder: forkedRecorder),
            multiPriority: 0, multiName: "fork")
        forkedProbe.setParams(ProcessProbeModule.Params(tag: "fork"))
        let forked = try await render(
            image, [forkedProbe], renderProcess: .current, metal: metal)
        let forkedBytes = readBytes(forked.0)
        XCTAssertEqual(forkedBytes.count, baselineBytes.count)
        XCTAssertNotEqual(
            forkedBytes, baselineBytes,
            "renderProcess 1 must take the fork arm (G2②)")
        let entries = await forkedRecorder.entries
        XCTAssertEqual(entries.first?.raw, 1, "the v1 arm ran (raw 1)")
    }

    // MARK: - 5: G2③ — a key-less document decodes legacy and runs the arm

    func testKeylessSidecarDocumentFlowsLegacyIntoThePipe() async throws {
        // A v10 document WITHOUT the key (the canonical legacy byte face).
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: Self.fixtureImageID, decoderVersionUsed: "v8",
            decodeParamsHash: 0x1234, instances: [], history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0x1234),
            appVersion: "test")
        let bytes = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertNil(decoded.process, "the key ABSENT decodes to nil")

        // nil ⇔ legacy — the exact value the coordinator carrier would
        // prime — flows into the pipe and takes the LEGACY arm.
        let carrier = decoded.process ?? .legacy
        XCTAssertEqual(carrier, .legacy)

        let metal = try await makeMetal()
        let image = makeImage()
        let recorder = ProbeRecorder()
        let probe = ModuleBox(
            module: ProcessProbeModule(tag: "p", recorder: recorder),
            multiPriority: 0, multiName: "p")
        probe.setParams(ProcessProbeModule.Params(tag: "p"))
        let baselineRecorder = ProbeRecorder()
        let baselineProbe = ModuleBox(
            module: ProcessProbeModule(tag: "b", recorder: baselineRecorder),
            multiPriority: 0, multiName: "b")
        baselineProbe.setParams(ProcessProbeModule.Params(tag: "b"))
        let withCarrier = try await render(
            image, [probe], renderProcess: carrier, metal: metal)
        let baseline = try await render(
            image, [baselineProbe], renderProcess: .legacy, metal: metal)
        XCTAssertEqual(readBytes(withCarrier.0), readBytes(baseline.0))
        let entries = await recorder.entries
        XCTAssertEqual(entries.first?.raw, 0, "the legacy arm ran (raw 0)")
    }

    // MARK: - 6: the cache-key face (KD-6 — process never keys)

    func testCacheKeyFaceIsUnchangedAcrossProcessValues() async throws {
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let chain = try await makeTerminalChain(registry: registry)
        let image = makeImage()
        let sharedCache = PipeCache()

        // Run 1: cold (misses render the planes).
        let first = try await render(
            image, chain, renderProcess: .legacy, cache: sharedCache, metal: metal)
        XCTAssertGreaterThan(first.1.misses, 0, "run 1 rendered")

        // Run 2: ONLY the process value differs. Identical keys → the run
        // is a full HIT (a key-carrying process would miss everything).
        let second = try await render(
            image, chain, renderProcess: .current, cache: sharedCache, metal: metal)
        XCTAssertGreaterThan(second.1.hits, 0, "run 2 hit the shared lines")
        XCTAssertEqual(
            second.1.misses, 0,
            "the process value must not enter any cache key (KD-6)")
    }

    // MARK: - 7: forward numbers stamp verbatim (no pipe-face clamp)

    func testForwardLargeNumberStampsVerbatim() async throws {
        let metal = try await makeMetal()
        let image = makeImage()
        let recorder = ProbeRecorder()
        let probe = ModuleBox(
            module: ProcessProbeModule(tag: "p", recorder: recorder),
            multiPriority: 0, multiName: "p")
        probe.setParams(ProcessProbeModule.Params(tag: "p"))
        let forward = try RenderProcessVersion(rawValue: 7)!
        _ = try await render(image, [probe], renderProcess: forward, metal: metal)
        let entries = await recorder.entries
        XCTAssertEqual(
            entries.first?.raw, 7,
            "the stamp is verbatim — the clamp lives at the resolving "
                + "consumption point (OQ-3)")
    }

    // MARK: - 8: the derived terminal sub-run inherits (checker M3 list)

    func testCompositeTerminalLegInheritsTheProcessValue() async throws {
        let metal = try await makeMetal()
        let image = makeImage()
        let recorder = ProbeRecorder()
        // iopOrder 75 ≥ 70 → the composite's TERMINAL chain (the split);
        // the terminal leg's pipe must carry the composite's value.
        let probe = ModuleBox(
            module: ProcessProbeTerminalModule(tag: "t", recorder: recorder),
            multiPriority: 0, multiName: "t")
        probe.setParams(ProcessProbeTerminalModule.Params(tag: "t"))

        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: Self.fixtureImageID, baseInstances: [probe],
            layerStack: LayerStack(baseLayer: BackgroundLayer()),
            registry: ModuleRegistry.makeDefault(), resolution: .preview,
            cache: PipeCache(), metal: metal, policy: .preview,
            renderProcess: .current)
        await Self.drain(metal)
        XCTAssertGreaterThan(result.terminalStats?.planesRendered ?? 0, 0,
                             "防空转: the terminal leg rendered")
        let entries = await recorder.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            entries.first?.raw, 1,
            "the composite's terminal sub-run pipe inherited the value")
    }
}
