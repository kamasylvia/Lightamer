import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// DrtPostMigrationTests (Plan M2-6-3 T5, AC#5 — LAYERS bundle) — the Post-four
// migration into the DRT tail (M2DRT-05: Clarity/Sharpen/Halation/FilmGrain
// run ONCE after the display transform, on the display-referred plane):
//
//   1. THE ASSEMBLY SLOTS: the enabled Post-four replay BETWEEN DrtMethodBox
//      (74.0) and EotfBox (75.0) through the tail-internal slot orders
//      (74.1+), params forwarded verbatim; an EMPTY post set assembles the
//      EXACT P1 chain and the P1 seed formula (bit-identical).
//   2. THE SEED FOLD (E5): the injected set's identity folds into the tail
//      seed (sorted, order-insensitive); an empty set folds NOTHING.
//   3. THE MAIN-CHAIN SKIP: under .drt the four boxes demote out of the main
//      chain and replay in the tail (bytes move vs the post-less tail);
//      under .sdrGamma they stay in the main chain (the zero-regression
//      face).
//   4. THE KEY LOCALITY: a Post param change re-runs ONLY the tail planes
//      at/after that box — the method plane and the whole main chain HIT
//      (AC#5's 键局部性).
//   5. THE DISPLAY-DOMAIN ANCHORS (重钉 face): each module soloed in the
//      tail pins its display-referred response (the [0,1] linear domain the
//      migration moved them to) — the kernels are byte-identical to their
//      scene-domain suites; the domain anchors recorded in DECISIONS.
// ─────────────────────────────────────────────────────────────────────────────

final class DrtPostMigrationTests: XCTestCase {

    private static let fixtureImageID = UUID(
        uuidString: "D2A9C3E1-0000-4000-8000-00000000D2A9")!

    private static let postSet = NodeOwnershipCatalog.drtPostOpNames

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeRegistry() async throws -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
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

    private func makePostBoxes(
        registry: ModuleRegistry, sharpenAmount: Float = 0.0
    ) async throws -> [any ModuleBoxing] {
        // The v50 natural order: equalizer(27) → sharpen(35) → bloom(61) →
        // grain(65) — the tail replay preserves it through the slots.
        var chain = [any ModuleBoxing]()
        let eqMade = await registry.makeBox(opName: EqualizerModule.opName)
        let eq = try XCTUnwrap(eqMade as? ModuleBox<EqualizerModule>)
        eq.setParams(EqualizerModule.Params(g0: 0.5))
        chain.append(eq)
        let sharpenMade = await registry.makeBox(opName: SharpenModule.opName)
        let sharpen = try XCTUnwrap(sharpenMade as? ModuleBox<SharpenModule>)
        sharpen.setParams(SharpenModule.Params(radius: 2.0, amount: sharpenAmount))
        chain.append(sharpen)
        let bloomMade = await registry.makeBox(opName: BloomModule.opName)
        let bloom = try XCTUnwrap(bloomMade as? ModuleBox<BloomModule>)
        bloom.setParams(BloomModule.Params()) // the non-neutral defaults
        chain.append(bloom)
        let grainMade = await registry.makeBox(opName: GrainModule.opName)
        let grain = try XCTUnwrap(grainMade as? ModuleBox<GrainModule>)
        grain.setParams(GrainModule.Params()) // the non-neutral defaults
        chain.append(grain)
        return chain
    }

    /// The terminal pair (committed; both demoted under .drt).
    private func makeTerminalChain(
        registry: ModuleRegistry
    ) async throws -> [any ModuleBoxing] {
        var chain = [any ModuleBoxing]()
        let coloroutMade = await registry.makeBox(opName: ColorOutModule.opName)
        let colorout = try XCTUnwrap(coloroutMade as? ModuleBox<ColorOutModule>)
        colorout.setParams(ColorOutModule.Params(outputProfile: .sRGB))
        chain.append(colorout)
        let gammaMade = await registry.makeBox(opName: GammaModule.opName)
        let gamma = try XCTUnwrap(gammaMade as? ModuleBox<GammaModule>)
        gamma.setParams(GammaModule.Params())
        chain.append(gamma)
        return chain
    }

    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func render(
        _ image: DecodedImage, _ boxes: [any ModuleBoxing],
        policy: TerminalTailPolicy, cache: PipeCache = PipeCache(),
        metal: MetalContext
    ) async throws -> (any MTLTexture, RenderPipeline.PipeRunStats) {
        let result = try await RenderPipeline.process(
            image: image, instances: boxes, imageID: Self.fixtureImageID,
            resolution: .preview, cache: cache, metal: metal,
            terminalTail: policy)
        await Self.drain(metal)
        return result
    }

    /// The bgra8 reader (the SDR tail's final format).
    private func readBGRA(_ texture: any MTLTexture) -> [UInt8] {
        precondition(texture.pixelFormat == .bgra8Unorm)
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        texture.getBytes(
            &bytes, bytesPerRow: w * 4,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    private var sdrRecord: DrtRecord { DrtRecord() }

    // MARK: - 1: the assembly slots

    func testAssemblyInsertsPostSlotsBetweenMethodAndEotf() async throws {
        let registry = try await makeRegistry()
        let post = try await makePostBoxes(registry: registry)
        let assembled = DrtTailAssembly.instances(
            params: DrtTailParams(
                record: sdrRecord, postOpNames: Self.postSet),
            residents: post)
        let orders = assembled.map(\.iopOrder)
        XCTAssertEqual(orders.count, 6)
        XCTAssertEqual(orders[0], 74.0, "DrtMethodBox first")
        XCTAssertEqual(orders[1], 74.1, "the first post slot (v50-natural order)")
        XCTAssertEqual(orders[2], 74.2)
        XCTAssertEqual(orders[3], 74.3)
        XCTAssertEqual(orders[4], 74.4)
        XCTAssertEqual(orders[5], 75.0, "EotfBox AFTER the post slots")
        // The v50 natural order is preserved through the slots.
        XCTAssertEqual(
            Array(assembled[1...4].map(\.opName)),
            [EqualizerModule.opName, SharpenModule.opName,
             BloomModule.opName, GrainModule.opName])
        // The wrapper forwards the payload VERBATIM (原样复用).
        for (slot, original) in zip(assembled[1...4], post.sorted(by: {
            ($0.iopOrder, $0.multiPriority, $0.opName)
                < ($1.iopOrder, $1.multiPriority, $1.opName)
        })) {
            XCTAssertEqual(slot.instanceID, original.instanceID)
            XCTAssertEqual(slot.paramsData, original.paramsData)
            XCTAssertEqual(slot.paramsHash, original.paramsHash)
            XCTAssertEqual(slot.multiPriority, original.multiPriority)
            XCTAssertEqual(slot.enabled, original.enabled)
        }
    }

    func testEmptyPostAssemblyAndSeedMatchTheP1Face() async throws {
        let registry = try await makeRegistry()
        let post = try await makePostBoxes(registry: registry)
        let assembled = DrtTailAssembly.instances(
            params: DrtTailParams(record: sdrRecord), residents: post)
        XCTAssertEqual(
            assembled.map(\.iopOrder), [74.0, 75.0],
            "an empty post set assembles the EXACT P1 chain")
        // The seed: an empty set folds NOTHING — bit-identical to the P1
        // formula (recordHash ⊕ policyTag ⊕ upstream).
        let upstream = UInt64(0x1234_5678_9ABC_DEF0)
        let params = DrtTailParams(record: sdrRecord)
        let seeded = DrtTailAssembly.seed(upstream: upstream, params: params)
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: params.recordHash) { h = StableHash.combine(h, $0) }
        let tag = Array("lightamer.drt.tail.v1".utf8)
        h = tag.withUnsafeBufferPointer { StableHash.combine(h, UnsafeRawBufferPointer($0)) }
        withUnsafeBytes(of: upstream) { h = StableHash.combine(h, $0) }
        XCTAssertEqual(seeded, h, "the P1 seed formula, bit-for-bit")
    }

    // MARK: - 2: the seed fold (E5)

    func testPostSetIdentityFoldsIntoTheSeed() {
        let upstream = UInt64(0x0FF1_CE_0_1234_5678)
        let bare = DrtTailAssembly.seed(
            upstream: upstream, params: DrtTailParams(record: sdrRecord))
        let withPost = DrtTailAssembly.seed(
            upstream: upstream,
            params: DrtTailParams(record: sdrRecord, postOpNames: Self.postSet))
        XCTAssertNotEqual(
            bare, withPost, "the post set identity must move the tail seed")
        // Order-insensitive (the fold sorts).
        let shuffled = DrtTailAssembly.seed(
            upstream: upstream,
            params: DrtTailParams(
                record: sdrRecord, postOpNames: Self.postSet.reversed()))
        XCTAssertEqual(withPost, shuffled)
        // A different set moves the seed.
        let subset = DrtTailAssembly.seed(
            upstream: upstream,
            params: DrtTailParams(
                record: sdrRecord, postOpNames: [SharpenModule.opName]))
        XCTAssertNotEqual(withPost, subset)
    }

    // MARK: - 3: the main-chain skip + the tail replay

    func testPostFourSkipTheMainChainAndReplayInTheTail() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let terminal = try await makeTerminalChain(registry: registry)
        let postBoxes = try await makePostBoxes(registry: registry, sharpenAmount: 0.8)
        let drtChain = terminal + postBoxes

        // The tail WITHOUT the post set: sharpen never runs anywhere.
        let (bare, _) = try await render(
            image, drtChain,
            policy: .drt(DrtTailParams(record: sdrRecord)), metal: metal)
        // The tail WITH the post set: the four replay after the method —
        // the bytes MUST move (the sharpen amount 0.8 alone guarantees it).
        let (migrated, _) = try await render(
            image, drtChain,
            policy: .drt(DrtTailParams(
                record: sdrRecord, postOpNames: Self.postSet)), metal: metal)
        XCTAssertEqual(bare.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(migrated.pixelFormat, .bgra8Unorm)
        XCTAssertNotEqual(
            readBGRA(bare), readBGRA(migrated),
            "the post replay must move the display bytes")

        // The ZERO-REGRESSION face: under .sdrGamma the four stay in the
        // main chain (the gamma tail runs LAST — the bytes differ from both
        // drt faces; the pre-M2-6 behavior).
        let (legacy, _) = try await render(
            image, drtChain, policy: .sdrGamma, metal: metal)
        XCTAssertEqual(legacy.pixelFormat, .bgra8Unorm)
        XCTAssertNotEqual(readBGRA(legacy), readBGRA(migrated))
    }

    // MARK: - 4: the key locality (AC#5)

    func testPostParamChangeReRunsOnlyTheTailDownstream() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let cache = PipeCache()
        let terminal = try await makeTerminalChain(registry: registry)
        let postBoxes = try await makePostBoxes(registry: registry, sharpenAmount: 0.8)
        let chain = terminal + postBoxes
        let policy = DrtTailParams(record: sdrRecord, postOpNames: Self.postSet)

        _ = try await render(image, chain, policy: .drt(policy), cache: cache, metal: metal)
        // The same run: everything hits.
        let (_, sameStats) = try await render(
            image, chain, policy: .drt(policy), cache: cache, metal: metal)
        XCTAssertEqual(
            sameStats.misses, 0, "the identical run re-hits the entire tail")

        // The sharpen param change: the tail planes AT/AFTER sharpen miss
        // (sharpen → bloom → grain → eotf = 4); the method plane, the
        // equalizer plane (upstream of sharpen in the tail) and the whole
        // main chain HIT.
        let sharpen = try XCTUnwrap(
            chain.first { $0.opName == SharpenModule.opName }
                as? ModuleBox<SharpenModule>)
        sharpen.setParams(SharpenModule.Params(radius: 3.0, amount: 0.8))
        let (_, changedStats) = try await render(
            image, chain, policy: .drt(policy), cache: cache, metal: metal)
        XCTAssertEqual(
            changedStats.misses, 4,
            "sharpen + the downstream post planes + the EOTF re-run")
        XCTAssertGreaterThan(changedStats.hits, 0)
    }

    // MARK: - 5: the display-domain anchors (重钉 face)

    /// Each module soloed in the tail: the display-referred response is
    /// DETERMINISTIC across fresh-cache runs (the migration contract) and
    /// the measured center-pixel anchors land in M2-6-3-DECISIONS. The
    /// kernels are byte-identical to their scene-domain suites (零新 kernel
    /// — the visual-strength walk stays a gui-acceptance observation,
    /// discipline 11); these anchors pin the MIGRATION domain.
    func testDisplayReferredAnchorsPerModule() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let commits: [(String, (any ModuleBoxing) -> Void)] = [
            (SharpenModule.opName, { box in
                (box as! ModuleBox<SharpenModule>).setParams(
                    SharpenModule.Params(radius: 2.0, amount: 0.8, threshold: 0.0))
            }),
            (EqualizerModule.opName, { box in
                (box as! ModuleBox<EqualizerModule>).setParams(
                    EqualizerModule.Params(g0: 0.5))
            }),
            (BloomModule.opName, { box in
                (box as! ModuleBox<BloomModule>).setParams(BloomModule.Params())
            }),
            (GrainModule.opName, { box in
                (box as! ModuleBox<GrainModule>).setParams(GrainModule.Params())
            }),
        ]
        for (op, commit) in commits {
            let chain = try await makeTerminalChain(registry: registry)
            let made = await registry.makeBox(opName: op)
            let box = try XCTUnwrap(made)
            commit(box)
            let policy = DrtTailParams(record: sdrRecord, postOpNames: [op])
            let (a, _) = try await render(
                image, chain + [box], policy: .drt(policy), metal: metal)
            let (b, _) = try await render(
                image, chain + [box], policy: .drt(policy), metal: metal)
            let bytesA = readBGRA(a)
            let bytesB = readBGRA(b)
            XCTAssertEqual(
                bytesA, bytesB, "\(op): the display-domain anchor is deterministic")
            let center = (16 * 48 + 24) * 4 // (x=24, y=16) in BGRA bytes
            print(
                "ANCHOR \(op): center BGRA = [\(bytesA[center]), \(bytesA[center + 1]), "
                    + "\(bytesA[center + 2]), \(bytesA[center + 3])]")
        }
    }

    // MARK: - 6: the OQ-10 bench observation (non-gating)

    /// The full-DRT-tail wall clock at the PREVIEW cap bucket (2560) and a
    /// small FULL render — the OQ-10 observation row (60fps 复验归 M2-11).
    /// NO hard gate: the asserts only sanity the shapes; the numbers land
    /// in M2-6-3-SUMMARY.
    func testDrtTailBenchObservation() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let policy = DrtTailParams(
            record: sdrRecord, postOpNames: Self.postSet)

        // PREVIEW cap bucket: 2560-px long edge synthetic.
        let previewImage = makeImage(width: 1920, height: 2560)
        let terminal = try await makeTerminalChain(registry: registry)
        let postBoxes = try await makePostBoxes(registry: registry, sharpenAmount: 0.8)
        let previewChain = terminal + postBoxes
        var start = Date()
        _ = try await render(
            previewImage, previewChain, policy: .drt(policy), metal: metal)
        let coldPreview = Date().timeIntervalSince(start)
        start = Date()
        _ = try await render(
            previewImage, previewChain, policy: .drt(policy), metal: metal)
        let warmPreview = Date().timeIntervalSince(start)

        // FULL small image (the 100MP full-frame bench is NOT a gate).
        let fullImage = makeImage(width: 1024, height: 640)
        start = Date()
        let (fullPlane, _) = try await RenderPipeline.process(
            image: fullImage, instances: previewChain,
            imageID: Self.fixtureImageID, resolution: .full,
            cache: PipeCache(), metal: metal, longEdge: nil,
            terminalTail: .drt(policy))
        await Self.drain(metal)
        let fullSeconds = Date().timeIntervalSince(start)
        XCTAssertEqual(fullPlane.pixelFormat, .bgra8Unorm)
        print(
            String(
                format: "BENCH drt-tail: preview2560 cold=%.0fms warm=%.0fms; full1024x640=%.0fms",
                coldPreview * 1000, warmPreview * 1000, fullSeconds * 1000))
    }
}
