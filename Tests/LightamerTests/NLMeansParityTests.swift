@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// NLMeansParityTests (Plan 05-06) — T1 kernel-group gates first, T3/T4
// golden + tiling + chroma legs layered on top:
//
//   T1 (this file's scan/smoke half):
//   - workgroup size scan {64,128,256,512}: all combinations byte-identical
//     (correctness gate BEFORE locking the threadgroup block size — plan
//     纪律 "scan 不过不锁定参数"; dt probes dt_opencl_local_buffer_opt with
//     a 2^16-cell budget, Metal pins an explicit value in DECISIONS);
//   - flat-field → flat-field identity smoke (noise-free flat ⇒ dist=0 ⇒
//     w=gh(0)=fast_mexp2f(0)=1.0 exactly ⇒ out = neighborhood mean = in,
//     within the Lab powr-chain + box-sum rounding);
//   - noise direction probe: seeded noise IS smoothed (non-vacuous).
//
// L014: every readback drains the queue first. 防空转: all loops carry
// `compared > 0` assertions.
final class NLMeansParityTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: NLMeansKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Texture helpers (direct engine drives — no pipe)

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int,
        pixel: (Int, Int) -> SIMD4<Float>
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let px = pixel(x, y)
                floats[(y * width + x) * 4 + 0] = px.x
                floats[(y * width + x) * 4 + 1] = px.y
                floats[(y * width + x) * 4 + 2] = px.z
                floats[(y * width + x) * 4 + 3] = px.w
            }
        }
        floats.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func readRGBA(_ tex: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal) // L014
        var floats = [Float](repeating: 0, count: tex.width * tex.height * 4)
        floats.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 16,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return floats
    }

    /// Deterministic pseudo-noise in [−0.5, 0.5) (hash flow — same input
    /// every scan leg; NOT the golden noise fixture, just scan fodder).
    private func pseudoNoise(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 73856093 ^ y &* 19349663)
        h = h &* 2654435761 &+ 0x9E3779B9
        return Float(h >> 9) / Float(UInt32.max >> 9) - 0.5
    }

    /// Gradient + pseudo-noise field (linear Rec2020-ish, [0,1]).
    private func makeNoisyTexture(
        _ metal: MetalContext, width: Int, height: Int, noiseAmp: Float
    ) throws -> any MTLTexture {
        try makeTexture(metal, width: width, height: height) { x, y in
            let base = 0.05 + 0.85 * Float(x) / Float(max(width - 1, 1))
            let v = max(min(base + noiseAmp * pseudoNoise(x, y), 1), 0)
            return SIMD4(v, v, v, 1)
        }
    }

    private func makeScratch(
        _ metal: MetalContext, width: Int, height: Int
    ) throws -> NLMeansModule.Scratch {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let planeBytes = width * height * MemoryLayout<Float>.size
        return NLMeansModule.Scratch(
            lab: try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor)),
            u2: try XCTUnwrap(
                metal.device.makeBuffer(length: width * height * 16, options: .storageModeShared)),
            buckets: try XCTUnwrap(
                metal.device.makeBuffer(length: planeBytes * 4, options: .storageModeShared)),
            planeBytes: planeBytes)
    }

    private func denoise(
        _ metal: MetalContext, input: any MTLTexture, blockSize: Int
    ) async throws -> [Float] {
        let output = try makeTexture(metal, width: input.width, height: input.height) { _, _ in
            SIMD4(0, 0, 0, 1)
        }
        let scratch = try makeScratch(metal, width: input.width, height: input.height)
        try await NLMeansModule.denoise(
            input: input, output: output,
            radius: 2, strength: 50, luma: 0.5, chroma: 1,
            roiScale: 0.4, iscale: 1.0,  // P=1, K=3 → 28 offsets (scan keeps it fast)
            pipeType: .full, metal: metal, blockSize: blockSize, scratch: scratch)
        return readRGBA(output, metal: metal)
    }

    // MARK: - T1 ① workgroup size scan

    /// threadgroup block size ∈ {64,128,256,512} on the SAME input: all
    /// four outputs BYTE-identical (the sliding-window wings must produce
    /// exactly the same box sums at every workgroup shape — a correctness
    /// gate, not a tolerance gate).
    func testWorkgroupSizeScanAllByteIdentical() async throws {
        let metal = try await makeMetal()
        let width = 96, height = 64
        let input = try makeNoisyTexture(metal, width: width, height: height, noiseAmp: 0.05)

        var baseline: [Float]?
        var compared = 0
        var mismatchBytes = 0
        for blockSize in [64, 128, 256, 512] {
            let out = try await denoise(metal, input: input, blockSize: blockSize)
            compared += 1
            if let baseline {
                XCTAssertEqual(out.count, baseline.count)
                for i in 0..<out.count where out[i].bitPattern != baseline[i].bitPattern {
                    mismatchBytes += 1
                }
            } else {
                baseline = out
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(mismatchBytes, 0, "scan legs must be byte-identical (got \(mismatchBytes) diffs)")
    }

    // MARK: - T1 ② flat-field identity smoke

    /// Noise-free flat ⇒ dist=0 ⇒ w=gh(0)=fast_mexp2f(0)=1.0 EXACTLY ⇒
    /// out = box mean = in (within Lab powr-chain ~2ulp + box-sum rounding;
    /// gate 1e-4 rel — far inside the denoise 1e-3 family tier).
    func testFlatFieldIdentitySmoke() async throws {
        let metal = try await makeMetal()
        let width = 64, height = 48
        let input = try makeTexture(metal, width: width, height: height) { _, _ in
            SIMD4(0.18, 0.18, 0.18, 1)
        }
        let out = try await denoise(metal, input: input, blockSize: 128)
        var compared = 0
        var maxRel: Float = 0
        for i in 0..<(width * height) {
            for c in 0..<3 {
                compared += 1
                let o = out[i * 4 + c]
                maxRel = max(maxRel, abs(o - 0.18) / 0.18)
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxRel, 1e-4, "flat identity smoke: maxRel=\(maxRel)")
    }

    // MARK: - T1 ③ noise direction probe (non-vacuous)

    /// Seeded noise IS smoothed: output closer to the noise-free ramp than
    /// the noisy input is (RMS-to-truth strictly decreases).
    func testNoiseIsSmoothedTowardTruth() async throws {
        let metal = try await makeMetal()
        let width = 96, height = 64
        var truth = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                truth[y * width + x] = 0.05 + 0.85 * Float(x) / Float(width - 1)
            }
        }
        let noisy = try makeNoisyTexture(metal, width: width, height: height, noiseAmp: 0.08)
        let out = try await denoise(metal, input: noisy, blockSize: 128)

        func rmsToTruth(_ values: [Float]) -> Float {
            var acc: Float = 0
            for y in 0..<height {
                for x in 0..<width {
                    let v = values[(y * width + x) * 4]
                    let d = v - truth[y * width + x]
                    acc += d * d
                }
            }
            return (acc / Float(width * height)).squareRoot()
        }
        let noisyRGBA = readRGBA(noisy, metal: metal)
        let rmsIn = rmsToTruth(noisyRGBA)
        let rmsOut = rmsToTruth(out)
        XCTAssertGreaterThan(rmsIn, 0.01, "fixture must actually carry noise")
        XCTAssertLessThan(
            rmsOut, rmsIn * 0.8,
            "denoise must move toward truth: rmsIn=\(rmsIn) rmsOut=\(rmsOut)")
    }

    // MARK: - T2 preview-downgrade constants (DECISIONS pins)

    /// K clamp 3 + decimate on PREVIEW/THUMBNAIL, full K=7 on FULL:
    /// the derivation table pinned at multiple scales (nlmeans.c:171-172
    /// dt shapes; clamp = denoiseprofile.c:1626-1631 shape; decimate skip
    /// parity = nlmeans_core.c:103-118).
    func testPreviewDowngradeDerivations() {
        var compared = 0
        // FULL: K = ceil(7·scale) at several scales; P = ceil(radius·scale).
        for (roiScale, iscale) in [(Float(1.0), Float(1.0)), (Float(0.5), Float(1.0)), (Float(1.0), Float(0.25)), (Float(2.0), Float(1.0)), (Float(0.3), Float(1.0))] {
            let kFull = NLMeansModule.fullSearchRadius(roiScale: roiScale, iscale: iscale)
            XCTAssertEqual(
                kFull, Int((7 * NLMeansModule.radiusScale(roiScale: roiScale, iscale: iscale)).rounded(.up)),
                "FULL K formula @scale \(roiScale)/\(iscale)")
            let kPipe = NLMeansModule.searchRadius(roiScale: roiScale, iscale: iscale, pipeType: .full)
            XCTAssertEqual(kPipe, kFull, "FULL keeps the formula K")
            compared += 1
            // PREVIEW/THUMBNAIL clamp to 3.
            for tier in [PipeResolution.preview, .thumbnail] {
                XCTAssertEqual(
                    NLMeansModule.searchRadius(roiScale: roiScale, iscale: iscale, pipeType: tier),
                    min(3, kFull), "clamp K=3 @\(tier) scale \(roiScale)/\(iscale)")
                XCTAssertTrue(NLMeansModule.decimates(pipeType: tier), "\(tier) decimates")
                compared += 1
            }
            XCTAssertFalse(NLMeansModule.decimates(pipeType: .full), "FULL never decimates")
        }
        // 手算 pins：FULL scale1 → K=7 → 120 offsets；PREVIEW scale1 →
        // K=3 → 28 raw → decimate → 14（跳双留单——首偏移保留）。
        XCTAssertEqual(NLMeansModule.offsets(K: 7, decimate: false).count, 120)
        XCTAssertEqual(NLMeansModule.offsets(K: 3, decimate: false).count, 28)
        let decimated = NLMeansModule.offsets(K: 3, decimate: true)
        XCTAssertEqual(decimated.count, 14)
        XCTAssertEqual(decimated.first?.qx, -3, "first offset kept")
        XCTAssertEqual(decimated.first?.qy, -3, "first offset kept")
        // FULL 满血趟数：120×4 + finish = 481；PREVIEW 降载：14×4+1 = 57。
        XCTAssertEqual(NLMeansModule.offsets(K: 7, decimate: false).count * 4 + 1, 481)
        XCTAssertEqual(decimated.count * 4 + 1, 57)
        // sharpness = 3000/(1+strength)（nlmeans.c:173）。
        XCTAssertEqual(NLMeansModule.sharpness(strength: 0), 3000, accuracy: 1e-4)
        XCTAssertEqual(NLMeansModule.sharpness(strength: 50), 3000.0 / 51.0, accuracy: 1e-5)

        XCTAssertGreaterThan(compared, 0)
    }

    /// Tile seam pins (L020/L021): halo = P+K from the RUN-level
    /// roi.scale ÷ piece.iscale — identical for plane-level and any tile
    /// ROI at the same scale (K/P are run constants, not tile functions);
    /// working set = 80 B/px (factor 5.0 × 16 — dt 4.0 + the module-local
    /// Lab plane dt gets for free from its pipeline).
    func testTileSeamConstantsAndTileInvariance() async throws {
        let module = NLMeansModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: 512, height: 384)
        module.commitParams(NLMeansModule.Params(), into: &piece)

        let planeROI = ROI(x: 0, y: 0, width: 512, height: 384, scale: 1.0)
        let halo = module.tileHalo(roi: planeROI, piece: piece)
        // P = ceil(2·1) = 2, K = ceil(7·1) = 7 → halo 9 (dt tiling :339).
        XCTAssertEqual(halo, 9)
        XCTAssertEqual(module.tileWorkingSetBytesPerPixel(piece: piece), 80)

        // K/P 由 iscale 派生不随 tile 变：任意 tile 子窗 ROI（同 scale）
        // 的 halo 与整幅一致——分块==整幅门的几何前提。
        let tileROIs = [
            ROI(x: 128, y: 96, width: 128, height: 96, scale: 1.0),
            ROI(x: 0, y: 0, width: 100, height: 64, scale: 1.0),
            ROI(x: 384, y: 288, width: 128, height: 96, scale: 1.0),
        ]
        for tile in tileROIs {
            XCTAssertEqual(
                module.tileHalo(roi: tile, piece: piece), 9,
                "halo must not depend on the tile rect")
        }
        // scale 补偿：roi.scale 2 / iscale 1 → scale=min(2,2)/1 = 2 →
        // P=4, K=14 → halo 18；entry iscale 0.5 被 dt 公式的 fmax(·,1)
        // 钳到 1（half-scale run 不放大半径）。
        XCTAssertEqual(NLMeansModule.patchRadius(radius: 2, roiScale: 2, iscale: 1), 4)
        XCTAssertEqual(NLMeansModule.fullSearchRadius(roiScale: 2, iscale: 1), 14)
        let scaledPiece = IOPiece()
        var scaledPieceMut = scaledPiece
        scaledPieceMut.iscale = 0.5
        scaledPieceMut.dscIn = IOPBufferDesc(width: 1024, height: 768)
        module.commitParams(NLMeansModule.Params(), into: &scaledPieceMut)
        XCTAssertEqual(
            module.tileHalo(roi: ROI(x: 0, y: 0, width: 1024, height: 768, scale: 2.0), piece: scaledPieceMut),
            18, "scale = min(2,2)/max(0.5,1) = 2 → P=4, K=14")
    }

    /// 100MP FULL budget preview (the 05-01 placeholder formalized):
    /// 11648×8736 @80 B/px ≈ 8.14GB > 512MB → the tile grid must engage
    /// with >1 tiles and every tile within the 3GB budget.
    func testFullResolutionTileGridEngages() {
        let fullW = 11648, fullH = 8736
        let budget = 512 << 20
        // Untiled working set: 100MP × 80 = 8.14GB > 3GB budget — tiling
        // is MANDATORY (the TilingPlan first heavy consumer).
        XCTAssertGreaterThan(
            Double(fullW * fullH * 80), 3.0e9, "100MP FULL must exceed the budget")
        let tiles = TilingPlan.tiles(
            forWidth: fullW, height: fullH, maxTileBytes: budget,
            bytesPerPixel: 80, overlap: 9)
        var compared = 0
        var maxTileBytes = 0
        XCTAssertGreaterThan(tiles.count, 1, "分块真的发生（grid >1）")
        for tile in tiles {
            compared += 1
            XCTAssertGreaterThan(tile.width, 0)
            XCTAssertGreaterThan(tile.height, 0)
            maxTileBytes = max(maxTileBytes, (tile.width + 2 * 9) * (tile.height + 2 * 9) * 16)
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(
            Double(maxTileBytes), 3.0e9,
            "tile working set (halo-widened read planes) <3GB: \(maxTileBytes)")
    }

    // MARK: - T3 tiling 承重双门

    /// 分块==整幅（<1e-3，denoise 族档）：512×384 noise field, FULL +
    /// 1MB budget → grid >1（真分块断言，TilingPlan 同参纯函数）→
    /// 逐值一致。halo=P+K=9 @defaults（05-05 MonochromeGridTests 同型）。
    func testForcedTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let width = 512, height = 384
        let image = try noisyDecodedImage(width: width, height: height)

        let module = NLMeansModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: width, height: height)
        module.commitParams(NLMeansModule.Params(), into: &piece)
        let halo = module.tileHalo(
            roi: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0), piece: piece)
        XCTAssertEqual(halo, 9)
        let tiles = TilingPlan.tiles(
            forWidth: width, height: height, maxTileBytes: 1 << 20,
            bytesPerPixel: 80, overlap: halo)
        XCTAssertGreaterThan(tiles.count, 1, "分块真的发生（grid \(tiles.count) >1）")

        func run(maxTileBytes: Int?) async throws -> [Float] {
            let registry = ModuleRegistry.makeDefault()
            await LightamerIOPRegistry.populate(registry)
            let made = await registry.makeBox(opName: NLMeansModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<NLMeansModule>)
            box.setParams(NLMeansModule.Params(strength: 120))
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
                resolution: .full, cache: PipeCache(), metal: metal,
                longEdge: nil, maxTileWorkingBytes: maxTileBytes)
            return readRGB(texture, metal: metal)
        }
        let whole = try await run(maxTileBytes: nil)
        let tiled = try await run(maxTileBytes: 1 << 20)
        XCTAssertEqual(whole.count, tiled.count)
        var compared = 0
        var maxRel: Float = 0
        for i in 0..<whole.count {
            compared += 1
            let diff = abs(whole[i] - tiled[i])
            maxRel = max(maxRel, diff / max(abs(whole[i]), 1e-4))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxRel, 1e-3, "分块 == 整幅：maxRel=\(maxRel)")
    }

    // MARK: - T3 golden parity（轨 A，4 case × 3 fixture <1e-3 真循环）

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden", isDirectory: true)

    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/\(path) — run "
                    + "`python3 input/golden/fixtures/gen_fixtures.py cases input/golden/fixtures`")
        }
        return url
    }

    private static let parityCases: [(String, NLMeansModule.Params)] = [
        ("nlmeans_default", NLMeansModule.Params(radius: 2, strength: 50, luma: 0.5, chroma: 1)),
        ("nlmeans_strong", NLMeansModule.Params(radius: 3, strength: 200, luma: 0.8, chroma: 0.6)),
        ("nlmeans_chroma", NLMeansModule.Params(radius: 2, strength: 50, luma: 0.1, chroma: 1)),
        ("nlmeans_patch4", NLMeansModule.Params(radius: 4, strength: 10, luma: 0.5, chroma: 1)),
    ]

    private static let parityFixtures = [
        "delta_impulse",
        "ramp_8ev__noisy_iso125_s20260921",
        "gray_staircase__noisy_iso1600_s20260921",
    ]

    /// TRACK A（4×3）: gen_fixtures Goossens float64 reference vs the live
    /// pipe (FULL scale 1 → P=ceil(radius), K=7, no decimate — 与参考同一
    /// 派生). 容差 = denoise 族档 <1e-3 rel（累加顺序差 + float32/64 差 +
    /// fast_mexp2f 位截断边界；注释引 05-CONTEXT 容差档）。防空转：
    /// compared>0 + 参考随输入变化（noisy ≠ delta）。
    func testNLMeansGoldenParity() async throws {
        let metal = try await makeMetal()
        var compared = 0
        var maxRel: Float = 0
        for fixture in Self.parityFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in Self.parityCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, w, h) = try await runNLMeansPipe(
                    image: image, params: params, metal: metal)
                XCTAssertEqual(w, golden.width, "\(caseName)×\(fixture)")
                XCTAssertEqual(h, golden.height, "\(caseName)×\(fixture)")
                let n = golden.width * golden.height
                var local: Float = 0
                for i in 0..<n {
                    for c in 0..<3 {
                        compared += 1
                        local = max(local, abs(pipe[i * 3 + c] - golden.rgb[i * 3 + c])
                            / max(abs(golden.rgb[i * 3 + c]), 1e-3))
                    }
                }
                print("NLMEANS parity \(caseName)×\(fixture): maxRel=\(local)")
                maxRel = max(maxRel, local)
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        // 非空转：同一 case 的两个 fixture 参考必须不同（输出随输入变化）。
        let delta = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/nlmeans_default__delta_impulse.exr"))
        let noisy = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/nlmeans_default__ramp_8ev__noisy_iso125_s20260921.exr"))
        XCTAssertNotEqual(delta.rgb, noisy.rgb, "参考不随输入变化 — vacuous")
        XCTAssertLessThan(maxRel, 1e-3, "nlmeans parity exceeded 1e-3 (max \(maxRel))")
    }

    private func runNLMeansPipe(
        image: DecodedImage, params: NLMeansModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: NLMeansModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<NLMeansModule>)
        box.setParams(params)
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
        return (readRGB(texture, metal: metal), texture.width, texture.height)
    }

    /// 512×384 gradient + deterministic noise as a DecodedImage (pipe leg).
    private func noisyDecodedImage(width: Int, height: Int) throws -> DecodedImage {
        var data = Data(capacity: width * height * 16)
        for y in 0..<height {
            for x in 0..<width {
                let base = 0.05 + 0.85 * Float(x) / Float(width - 1)
                // Per-channel INDEPENDENT noise — chroma noise must exist
                // or the chroma half-edge gates have nothing to smooth
                // (LabLab a/b stay 0 on channel-equal noise — the
                // LabMath neutral anchoring).
                let r = max(min(base + 0.08 * pseudoNoise(x, y), 1), 0)
                let g = max(min(base + 0.08 * pseudoNoise(x + 7919, y), 1), 0)
                let b = max(min(base + 0.08 * pseudoNoise(x, y + 104729), 1), 0)
                for v in [r, g, b] {
                    var le = v.bitPattern.littleEndian
                    data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
                }
                var one = Float(1.0).bitPattern.littleEndian
                data.append(contentsOf: withUnsafeBytes(of: &one) { Data($0) })
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return DecodedImage(
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    private func readRGB(_ tex: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal) // L014
        var floats = [Float](repeating: 0, count: tex.width * tex.height * 4)
        floats.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 16,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        var rgb = [Float](repeating: 0, count: tex.width * tex.height * 3)
        for i in 0..<(tex.width * tex.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return rgb
    }

    // MARK: - T3 极限门 + T4 IOP-DENOISE-04 chroma 半边

    /// Horizontal gradient energy (high-frequency proxy).
    private func gradientEnergy(_ rgb: [Float], width: Int, height: Int) -> Float {
        var acc: Float = 0
        var count = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let i = (y * width + x) * 3
                let d = rgb[i] - rgb[i + 3]
                acc += d * d
                count += 1
            }
        }
        return (acc / Float(max(count, 1))).squareRoot()
    }

    /// strength 极限门（plan T3；D-05-06-T2-1 记录的偏离：strength=0 非
    /// 恒等——dt sharpness=3000 仍平滑相似 patch，且 luma/chroma clamp
    /// 0.0001 下限——故本门钉「方向」而非「恒等」）：
    /// ① 平场 strength=0 恒等 <1e-4（dist=0 → w=1 → out=均值=in）；
    /// ② 噪场高频能量随 strength 单调下降（0 → 50 → 1e5）；
    /// ③ strength→∞（1e5）邻域均值语义：高频能量 < 输入的 25%。
    func testStrengthLimitGates() async throws {
        let metal = try await makeMetal()
        let width = 128, height = 96

        // ① flat + strength 0。
        let flat = try makeTexture(metal, width: 64, height: 48) { _, _ in
            SIMD4(0.3, 0.3, 0.3, 1)
        }
        let flatOut = try makeTexture(metal, width: 64, height: 48) { _, _ in
            SIMD4(0, 0, 0, 1)
        }
        let flatScratch = try makeScratch(metal, width: 64, height: 48)
        try await NLMeansModule.denoise(
            input: flat, output: flatOut, radius: 2, strength: 0,
            luma: 0.5, chroma: 1, roiScale: 1, iscale: 1, pipeType: .full,
            metal: metal, scratch: flatScratch)
        let flatOutRGB = readRGBA(flatOut, metal: metal)
        var compared = 0
        var maxRel: Float = 0
        for i in 0..<(64 * 48) {
            for c in 0..<3 {
                compared += 1
                maxRel = max(maxRel, abs(flatOutRGB[i * 4 + c] - 0.3) / 0.3)
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxRel, 1e-4, "平场 strength=0 恒等 maxRel=\(maxRel)")

        // ②③ 噪场单调 + 邻域均值方向（pipe 腿，strength 经 params）。
        let image = try noisyDecodedImage(width: width, height: height)
        func runPipe(strength: Float) async throws -> [Float] {
            let registry = ModuleRegistry.makeDefault()
            await LightamerIOPRegistry.populate(registry)
            let made = await registry.makeBox(opName: NLMeansModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<NLMeansModule>)
            box.setParams(NLMeansModule.Params(strength: strength))
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
                resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
            return readRGB(texture, metal: metal)
        }
        let noisyRGB = try await pipeIdentity(image: image, metal: metal)
        let energyIn = gradientEnergy(noisyRGB, width: width, height: height)
        let e0 = try await runPipe(strength: 0)
        let e50 = try await runPipe(strength: 50)
        let eMax = try await runPipe(strength: 100_000)
        let g0 = gradientEnergy(e0, width: width, height: height)
        let g50 = gradientEnergy(e50, width: width, height: height)
        let gMax = gradientEnergy(eMax, width: width, height: height)
        print("NLMEANS strength gates: in=\(energyIn) s0=\(g0) s50=\(g50) s1e5=\(gMax)")
        XCTAssertLessThanOrEqual(g0, energyIn * 1.05, "strength 0 仍低于输入高频")
        XCTAssertLessThan(g50, g0, "strength 50 < strength 0（单调）")
        XCTAssertLessThan(gMax, g50, "strength 1e5 < strength 50（单调）")
        // 邻域均值语义的方向门：均匀权重的 ±7 box 均值保留 ramp 斜率
        // （0.0067）且残留相邻盒相关噪声（不相交 tap 30/225 → √30/15 ≈
        // 0.37×σ）——理论残留 ≈ 0.0135，实测 0.018 同量级；门钉 0.7×
        // （"显著去高频"而非"归零"——box 均值的数学下限非零）。
        XCTAssertLessThan(gMax, energyIn * 0.7, "strength→∞ → 邻域均值方向")
    }

    /// luma=0（clamp 后 1e-4）：L 腿不动（|ΔL| < 0.05 Lab），a/b 腿强平滑
    /// （RMS Δab > 1.0 且 ≥ 10× maxΔL）——finish 权重向量 (luma,chroma,chroma)
    /// 的通道分离语义（nlmeans.c:213）。
    func testLumaZeroChromaOnlySmoothing() async throws {
        let metal = try await makeMetal()
        let width = 128, height = 96
        let image = try noisyDecodedImage(width: width, height: height)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        func run(_ params: NLMeansModule.Params) async throws -> [Float] {
            let made = await registry.makeBox(opName: NLMeansModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<NLMeansModule>)
            box.setParams(params)
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
                resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
            return readRGB(texture, metal: metal)
        }
        // 基线 = 输入平面本身（strength=0 非恒等——D-05-06-T2-1；
        // 空链读回，MonochromeParityTests.inputRGB 模式）。
        let input = try await pipeIdentity(image: image, metal: metal)
        let output = try await run(NLMeansModule.Params(strength: 50, luma: 0.0001, chroma: 1))
        var maxDL: Float = 0
        var abAcc: Float = 0
        var compared = 0
        for i in 0..<(width * height) {
            compared += 1
            let li = LabRoundTrip.rec2020ToLabF(SIMD3(input[i * 3], input[i * 3 + 1], input[i * 3 + 2]))
            let lo = LabRoundTrip.rec2020ToLabF(SIMD3(output[i * 3], output[i * 3 + 1], output[i * 3 + 2]))
            maxDL = max(maxDL, abs(lo.x - li.x))
            let dab = hypot(lo.y - li.y, lo.z - li.z)
            abAcc += dab * dab
        }
        XCTAssertGreaterThan(compared, 0)
        let rmsDab = (abAcc / Float(width * height)).squareRoot()
        print("NLMEANS luma=0 gate: maxDL=\(maxDL) rmsDab=\(rmsDab)")
        XCTAssertLessThan(maxDL, 0.05, "luma=0 → L 不动（clamp 1e-4 残差内）")
        XCTAssertGreaterThan(rmsDab, 1.0, "chroma 腿强平滑（噪声场）")
        XCTAssertGreaterThan(rmsDab, 10 * maxDL, "Δab 压倒性大于 ΔL（通道分离）")
    }

    /// T4 IOP-DENOISE-04 chroma 半边记账（05-08 VALIDATION 引用本测试）：
    /// chroma=0（clamp 1e-4）→ a/b 不动、L 平滑（与 luma=0 门镜像对称）。
    func testChromaZeroLumaOnlySmoothing() async throws {
        let metal = try await makeMetal()
        let width = 128, height = 96
        let image = try noisyDecodedImage(width: width, height: height)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        func run(_ params: NLMeansModule.Params) async throws -> [Float] {
            let made = await registry.makeBox(opName: NLMeansModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<NLMeansModule>)
            box.setParams(params)
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
                resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
            return readRGB(texture, metal: metal)
        }
        // 基线 = 输入平面本身（同 luma=0 门——strength=0 非恒等）。
        let baseline = try await pipeIdentity(image: image, metal: metal)
        let output = try await run(NLMeansModule.Params(strength: 50, luma: 1, chroma: 0.0001))
        var maxDab: Float = 0
        var lAcc: Float = 0
        var compared = 0
        for i in 0..<(width * height) {
            compared += 1
            let li = LabRoundTrip.rec2020ToLabF(SIMD3(baseline[i * 3], baseline[i * 3 + 1], baseline[i * 3 + 2]))
            let lo = LabRoundTrip.rec2020ToLabF(SIMD3(output[i * 3], output[i * 3 + 1], output[i * 3 + 2]))
            maxDab = max(maxDab, max(abs(lo.y - li.y), abs(lo.z - li.z)))
            let dl = abs(lo.x - li.x)
            lAcc += dl * dl
        }
        XCTAssertGreaterThan(compared, 0)
        let rmsDl = (lAcc / Float(width * height)).squareRoot()
        print("NLMEANS chroma=0 gate: maxDab=\(maxDab) rmsDL=\(rmsDl)")
        XCTAssertLessThan(maxDab, 0.05, "chroma=0 → a/b 不动（clamp 1e-4 残差内）")
        XCTAssertGreaterThan(rmsDl, 1.0, "luma 腿平滑（噪声场）")
        XCTAssertGreaterThan(rmsDl, 10 * maxDab, "ΔL 压倒性大于 Δab（通道分离）")
    }

    /// 空链 pipe 跑一遍读回输入平面（MonochromeParityTests.inputRGB 模式）。
    private func pipeIdentity(image: DecodedImage, metal: MetalContext) async throws -> [Float] {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
        return readRGB(texture, metal: metal)
    }
}
