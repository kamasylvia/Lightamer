@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Metal
import XCTest

// DenoiseProfileParityTests (Plan 05-07-T5) — the SC#2 formal verification
// closed loop + the golden parity legs:
//
//   TRACK A (8 case × 3 fixture): the T1 Python float64 references vs the
//   live pipe (FULL scale 1 → in_scale 1, max_scale from the 20% rule) at
//   the denoise family tolerance <1e-3 rel. Wavelets 5 cases (default
//   Y0U0V0 / RGB / strong / shaped force / AUTO-infer) + NLMeans leg 3
//   cases (defaults / scattering+central-weight / AUTO). 防空转: compared>0
//   + cross-fixture reference difference (non-vacuous).
//
//   SC#2 (the Phase 1 spike's quantified close-out): profile-matched
//   denoising beats the generic profile (SNR direction ①) and the
//   MISMATCHED profile under-denoises (residual ≥ correct-profile, ②) —
//   both on the live pipe with the seeded Poisson-Gaussian fixtures.
//
//   TILING: 分块==整幅 <1e-3 with band-count stability (halo 2^max_scale)
//   and the NLMeans leg halo P+K_scattered; FULL Δfootprint <3GB.
final class DenoiseProfileParityTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: NLMeansKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: DenoiseProfileKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
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

    // MARK: - golden access

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
                    + "`python3 input/golden/fixtures/gen_fixtures.py refs-denoiseprofile input/golden/fixtures`")
        }
        return url
    }

    // MARK: - case table (mirrors gen_fixtures DENOISEPROFILE_*_CASES)

    /// Swift `Double`/`Int` in `[String: Any]` do NOT bridge through
    /// `as? Float` (the cast returns nil) — every numeric override must go
    /// through this explicit conversion (the dp-helper self-check pins it).
    private static func f(_ any: Any?) -> Float? {
        if let v = any as? Float { return v }
        if let v = any as? Double { return Float(v) }
        if let v = any as? Int { return Float(v) }
        return nil
    }

    private static func dp(_ over: [String: Any]) -> DenoiseProfileModule.Params {
        var p = DenoiseProfileModule.Params()
        if let v = over["mode"] as? Int { p.mode = DenoiseProfileModule.Mode(rawValue: v)! }
        if let v = f(over["strength"]) { p.strength = v }
        if let v = f(over["shadows"]) { p.shadows = v }
        if let v = f(over["bias"]) { p.bias = v }
        if let v = f(over["scattering"]) { p.scattering = v }
        if let v = f(over["centralPixelWeight"]) { p.centralPixelWeight = v }
        if let v = f(over["radius"]) { p.radius = v }
        if let v = f(over["nbhood"]) { p.nbhood = v }
        if let v = over["colorMode"] as? Int {
            p.waveletColorMode = DenoiseProfileModule.WaveletColorMode(rawValue: v)!
        }
        if let v = over["a"] as? SIMD3<Float> { p.a = v }
        if let v = over["b"] as? SIMD3<Float> { p.b = v }
        // force-row overrides (the Y0/U0V0 shaped rows for dp_wave_force)
        if let rows = over["yOverride"] as? [[Float]] { p.y = rows }
        return p
    }

    private static let iso125a = SIMD3<Float>(
        7.65705497686894e-06, 1.54601975602981e-06, 2.30077680147848e-06)
    private static let iso125b = SIMD3<Float>(
        2.00608030560566e-09, 3.03636277807135e-09, 4.74823179066283e-09)
    private static let iso1600a = SIMD3<Float>(
        2.99037019802356e-05, 8.86355041404361e-06, 1.37779541937624e-05)
    private static let iso1600b = SIMD3<Float>(
        4.43124422276964e-08, 2.60617465248865e-08, 3.62731233591954e-08)

    /// 5 wavelets cases — AUTO resolves at commit (effectiveParams); the
    /// golden EXRs were baked with the same resolution (T1 _dp_case_with_infer).
    /// NOTE: overrides are Float literals — `Int as? Float` in `[String: Any]`
    /// fails on Swift and would silently drop the override (the dp-helper
    /// self-check pins this).
    /// dp_wave_force rows — a typed [[Float]] constant (an untyped literal
    /// inside `[String: Any]` bridges as Double and the `as? [[Float]]`
    /// cast would silently DROP the override; a short row would crash
    /// catmullRomTangents — x always has 7 anchors). Channel order
    /// all/r/g/b/y0/u0v0; rows 4+5 overridden (gen_fixtures y_override).
    private static let forceRows: [[Float]] = [
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
        [1.0, 0.9, 0.7, 0.5, 0.3, 0.2, 0.1],
        [0.9, 0.8, 0.6, 0.4, 0.2, 0.1, 0.0],
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
    ]

    private static let waveCases: [(String, DenoiseProfileModule.Params)] = [
        ("dp_wave_default", dp(["mode": 1])),
        ("dp_wave_rgb", dp(["mode": 1, "colorMode": 0])),
        ("dp_wave_strong", dp(["mode": 1, "strength": 3, "shadows": 1.2, "bias": -2])),
        ("dp_wave_force", dp(["mode": 1, "strength": 1.5, "yOverride": forceRows])),
        ("dp_wave_auto", dp(["mode": 4, "a": iso1600a, "b": iso1600b])),
    ]

    private static let nlmCases: [(String, DenoiseProfileModule.Params)] = [
        ("dp_nlm_default", dp(["mode": 0, "nbhood": Float(5)])),
        ("dp_nlm_scatter", dp(["mode": 0, "radius": Float(2), "nbhood": Float(5),
                               "strength": Float(2), "bias": Float(-1),
                               "scattering": 0.5, "centralPixelWeight": 0.3])),
        ("dp_nlm_auto", dp(["mode": 3, "a": iso1600a, "b": iso1600b])),
    ]

    private static let parityFixtures = [
        "delta_impulse",
        "ramp_8ev__noisy_iso125_s20260921",
        "gray_staircase__noisy_iso1600_s20260921",
    ]

    /// dp() helper self-check (Double/Int in Any do NOT cast through
    /// `as? Float` — the f() conversion must apply every override).
    func testDpHelperAppliesOverrides() {
        let p = Self.dp(["mode": 0, "radius": 2, "nbhood": 5, "strength": 2,
                         "bias": -1, "scattering": 0.5, "centralPixelWeight": 0.3])
        XCTAssertEqual(p.mode, .nlmeans)
        XCTAssertEqual(p.radius, 2)
        XCTAssertEqual(p.nbhood, 5)
        XCTAssertEqual(p.strength, 2)
        XCTAssertEqual(p.bias, -1)
        XCTAssertEqual(p.scattering, 0.5)
        XCTAssertEqual(p.centralPixelWeight, 0.3)
    }

    private func runPipe(
        image: DecodedImage, params: DenoiseProfileModule.Params,
        metal: MetalContext, maxTileWorkingBytes: Int? = nil
    ) async throws -> [Float] {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: DenoiseProfileModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<DenoiseProfileModule>)
        box.setParams(params)
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil, maxTileWorkingBytes: maxTileWorkingBytes)
        return readRGB(texture, metal: metal)
    }

    // MARK: - TRACK A: wavelets golden parity (5 × 3)

    func testWaveletsGoldenParity() async throws {
        let metal = try await makeMetal()
        var compared = 0
        var maxRel: Float = 0
        for fixture in Self.parityFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in Self.waveCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let pipe = try await runPipe(image: image, params: params, metal: metal)
                let n = golden.width * golden.height
                XCTAssertEqual(pipe.count / 3, n, "\(caseName)×\(fixture)")
                var local: Float = 0
                for i in 0..<n {
                    for c in 0..<3 {
                        compared += 1
                        local = max(local, abs(pipe[i * 3 + c] - golden.rgb[i * 3 + c])
                            / max(abs(golden.rgb[i * 3 + c]), 1e-3))
                    }
                }
                if local > 0.005 {
                    // dump the worst offenders (coords, golden, pipe)
                    var pairs: [(Float, Int, Int, Int, Float, Float)] = []
                    for i in 0..<n {
                        for c in 0..<3 {
                            let gV = golden.rgb[i * 3 + c]
                            let pV = pipe[i * 3 + c]
                            let rel = abs(pV - gV) / max(abs(gV), 1e-3)
                            if rel > 0.005 {
                                pairs.append((rel, i % golden.width, i / golden.width, c, gV, pV))
                            }
                        }
                    }
                    pairs.sort { $0.0 > $1.0 }
                    for pr in pairs.prefix(6) {
                        print("DENOISE OFFENDER rel=\(pr.0) at (\(pr.1),\(pr.2)) ch\(pr.3) golden=\(pr.4) pipe=\(pr.5)")
                    }
                    print("DENOISE offender count: \(pairs.count)/\(n * 3)")
                }
                var psum: Double = 0
                for v in pipe { psum += Double(v) }
                print("DENOISE wave pipe sum \(caseName)×\(fixture): \(psum)")
                print("DENOISE wavelets \(caseName)×\(fixture): maxRel=\(local)")
                maxRel = max(maxRel, local)
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        // 非空转：两 fixture 的参考必须不同（输出随输入变化）。
        let delta = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/dp_wave_default__delta_impulse.exr"))
        let noisy = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/dp_wave_default__ramp_8ev__noisy_iso125_s20260921.exr"))
        XCTAssertNotEqual(delta.rgb, noisy.rgb, "参考不随输入变化 — vacuous")
        XCTAssertLessThan(maxRel, 1e-3, "wavelets parity exceeded 1e-3 (max \(maxRel))")
    }

    // MARK: - TRACK A: NLMeans leg golden parity (3 × 3)

    func testNLMeansLegGoldenParity() async throws {
        let metal = try await makeMetal()
        var compared = 0
        var maxRel: Float = 0
        for fixture in Self.parityFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in Self.nlmCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let pipe = try await runPipe(image: image, params: params, metal: metal)
                let n = golden.width * golden.height
                var local: Float = 0
                for i in 0..<n {
                    for c in 0..<3 {
                        compared += 1
                        local = max(local, abs(pipe[i * 3 + c] - golden.rgb[i * 3 + c])
                            / max(abs(golden.rgb[i * 3 + c]), 1e-3))
                    }
                }
                if local > 0.005 {
                    var pairs: [(Float, Int, Int, Int, Float, Float)] = []
                    for i in 0..<n {
                        for c in 0..<3 {
                            let gV = golden.rgb[i * 3 + c]
                            let pV = pipe[i * 3 + c]
                            let rel = abs(pV - gV) / max(abs(gV), 1e-3)
                            if rel > 0.005 {
                                pairs.append((rel, i % golden.width, i / golden.width, c, gV, pV))
                            }
                        }
                    }
                    pairs.sort { $0.0 > $1.0 }
                    for pr in pairs.prefix(4) {
                        print("DENOISE NLM-OFFENDER rel=\(pr.0) at (\(pr.1),\(pr.2)) ch\(pr.3) golden=\(pr.4) pipe=\(pr.5)")
                    }
                    print("DENOISE nlm offender count: \(pairs.count)/\(n * 3)")
                }
                var psum: Double = 0
                for v in pipe { psum += Double(v) }
                print("DENOISE nlm pipe sum \(caseName)×\(fixture): \(psum)")
                print("DENOISE nlm \(caseName)×\(fixture): maxRel=\(local)")
                maxRel = max(maxRel, local)
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxRel, 1e-3, "NLMeans leg parity exceeded 1e-3 (max \(maxRel))")
    }

    // MARK: - SC#2 ①②: profile correctness + mismatch direction

    /// ① 正确剖面 > generic：ISO 1600 剖面去噪 ISO 1600 加噪 ramp 的
    /// RMS-to-truth 严格低于 generic 剖面（量化 SNR 提升方向）。
    /// ② 错配方向：ISO 125 剖面（小 a）去噪 ISO 1600 噪声 → 欠去噪
    /// （残差 ≥ 正确档）——Phase 1 spike 的量化收口。
    func testSC2ProfileDirections() async throws {
        let metal = try await makeMetal()
        // truth = the CLEAN ramp fixture; input = the SEEDED iso-1600 noisy
        // variant (the noisy pixels are the pipe INPUT, never the baseline —
        // an identity pipe run against itself is 0 by construction).
        let truthURL = try requireGolden("fixtures/ramp_8ev.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(
            requireGolden("fixtures/ramp_8ev__noisy_iso1600_s20260921.exr"))
        let truth = try GoldenParityTests.UncompressedEXR.load(truthURL)
        let n = truth.width * truth.height

        func rmsToTruth(_ rgb: [Float]) -> Float {
            var acc: Float = 0
            for i in 0..<n {
                for c in 0..<3 {
                    let d = rgb[i * 3 + c] - truth.rgb[i * 3 + c]
                    acc += d * d
                }
            }
            return (acc / Float(n * 3)).squareRoot()
        }
        // correct profile (iso 1600), generic, mismatched (iso 125)
        var correct = DenoiseProfileModule.Params()
        correct.a = Self.iso1600a
        correct.b = Self.iso1600b
        var mismatch = DenoiseProfileModule.Params()
        mismatch.a = Self.iso125a
        mismatch.b = Self.iso125b
        var generic = DenoiseProfileModule.Params() // a = 1e-4 (dt generic)
        generic.a = SIMD3(repeating: 1e-4)
        generic.b = SIMD3(repeating: 0)

        let outCorrect = try await runPipe(image: image, params: correct, metal: metal)
        let outMismatch = try await runPipe(image: image, params: mismatch, metal: metal)
        let outGeneric = try await runPipe(image: image, params: generic, metal: metal)
        let noisyRGB = try await pipeIdentity(image: image, metal: metal)

        let rNoisy = rmsToTruth(noisyRGB)
        let rCorrect = rmsToTruth(outCorrect)
        let rMismatch = rmsToTruth(outMismatch)
        let rGeneric = rmsToTruth(outGeneric)
        print(String(
            format: "SC#2 directions: noisy=%.5f correct=%.5f generic=%.5f mismatch=%.5f",
            rNoisy, rCorrect, rGeneric, rMismatch))
        XCTAssertLessThan(rCorrect, rNoisy, "去噪向 truth 移动")
        // ① profile-matched beats generic
        XCTAssertLessThan(rCorrect, rGeneric, "正确剖面残差 < generic 剖面")
        // ② mismatch under-denoises (direction, not magnitude)
        XCTAssertGreaterThanOrEqual(rMismatch, rCorrect, "ISO125 剖面去 ISO1600 噪声 → 欠去噪")
    }

    private func pipeIdentity(image: DecodedImage, metal: MetalContext) async throws -> [Float] {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
        return readRGB(texture, metal: metal)
    }

    // MARK: - ③ generic 回落链 + ④ Auto(EXIF) vs 手动 ISO

    /// Unknown camera → generic 生效（reloadDefaults 无 sentinel，具体
    /// a/b = 1e-4）；手动 ISO 覆盖改变 auto 插值结果（isoOverride 1600
    /// → 高 ISO 剖面，a[1] > EXIF 低 ISO 档）。
    func testGenericFallbackAndManualISOOverride() async {
        let store = NoiseProfileStore()
        let module = DenoiseProfileModule(profiles: store)
        // ③ unknown camera
        var capture = CaptureMetadata()
        capture.cameraMake = "Ghost"
        capture.cameraModel = "Phantom-X"
        capture.iso = 800
        let unknown = DecodedImage(
            ciImage: CIImage.empty(), rawTech: RAWTechnicalParams(),
            capture: capture, segmentationSkyMatte: nil, decoderVersionUsed: .v8)
        let defaults = await module.reloadDefaults(image: unknown)
        XCTAssertNotEqual(defaults.a.x, -1, "无命中 → 无 sentinel")
        XCTAssertEqual(defaults.a.x, Float(1e-4), accuracy: 1e-12, "generic a")
        // ④ Auto(EXIF) vs manual ISO：ISO 125 exact vs override 1600
        let sony = DenoiseProfileDerivationTests.decodedImage(
            make: "Sony", model: "ILCE-9M3", iso: 125)
        let at125 = await module.resolveAutoProfile(image: sony, isoOverride: nil, compensate: false)
        let at1600 = await module.resolveAutoProfile(image: sony, isoOverride: 1600, compensate: false)
        XCTAssertEqual(at125.iso, 125)
        XCTAssertEqual(at1600.iso, 1600)
        XCTAssertGreaterThan(at1600.a[1], at125.a[1], "高 ISO 剖面 a 更大")
    }

    // MARK: - tiling 承重（分块==整幅 + band 数稳定 + FULL footprint）

    /// 波列：强制分块（grid >1）== 整幅 <1e-3；halo = 2^max_scale 且
    /// dscIn/iscale run 级 stamp 在 tile 内不变（L021 承重断言）。
    func testWaveletsTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let width = 512, height = 384
        let image = try GoldenParityTests.decodeFixtureEXR(
            requireGolden("fixtures/ramp_8ev__noisy_iso1600_s20260921.exr"))

        let module = DenoiseProfileModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: width, height: height)
        module.commitParams(DenoiseProfileModule.Params(), into: &piece)
        let halo = module.tileHalo(
            roi: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0), piece: piece)
        // 512×384: supp0 = min(257, 102.4) → i0 = log2(50.7) ≈ 5.66 → the
        // band loop increments while (ms + 0.5) ≤ i0 → max_scale 6 (the
        // 64×64 golden fixtures resolve 3 — same formula, smaller i0).
        XCTAssertEqual(halo, 64, "512×384 级 max_scale=6 → halo 2^6")
        let bpx = module.tileWorkingSetBytesPerPixel(piece: piece)
        XCTAssertEqual(bpx, 152, "(3.5 + max_scale 6) × 16")

        func run(maxTileBytes: Int?) async throws -> [Float] {
            try await runPipe(
                image: image, params: DenoiseProfileModule.Params(),
                metal: metal, maxTileWorkingBytes: maxTileBytes)
        }
        let whole = try await run(maxTileBytes: nil)
        let tiled = try await run(maxTileBytes: 512 << 20)
        XCTAssertEqual(whole.count, tiled.count)
        var compared = 0
        var maxRel: Float = 0
        for i in 0..<whole.count {
            compared += 1
            let diff = abs(whole[i] - tiled[i])
            maxRel = max(maxRel, diff / max(abs(whole[i]), 1e-4))
        }
        XCTAssertGreaterThan(compared, 0)
        print("DENOISE wavelets tiling: maxRel=\(maxRel)")
        XCTAssertLessThan(maxRel, 1e-3, "分块 == 整幅：maxRel=\(maxRel)")
    }

    /// NLMeans 腿分块==整幅（halo P+K_scattered；strength 大 → 权重集中，
    /// 边界差异容差同族 1e-3）。
    func testNLMeansLegTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let image = try GoldenParityTests.decodeFixtureEXR(
            requireGolden("fixtures/ramp_8ev__noisy_iso1600_s20260921.exr"))
        var params = DenoiseProfileModule.Params()
        params.mode = .nlmeans
        params.nbhood = 5
        params.strength = 2

        let module = DenoiseProfileModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: 64, height: 64)
        module.commitParams(params, into: &piece)
        let halo = module.tileHalo(
            roi: ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0), piece: piece)
        XCTAssertEqual(halo, 1 + 5, "P=1, K_scattered=5 (scattering 0)")

        func run(maxTileBytes: Int?) async throws -> [Float] {
            try await runPipe(image: image, params: params, metal: metal,
                              maxTileWorkingBytes: maxTileBytes)
        }
        let whole = try await run(maxTileBytes: nil)
        let tiled = try await run(maxTileBytes: 512 << 20)
        var compared = 0
        var maxRel: Float = 0
        for i in 0..<whole.count {
            compared += 1
            let diff = abs(whole[i] - tiled[i])
            maxRel = max(maxRel, diff / max(abs(whole[i]), 1e-4))
        }
        XCTAssertGreaterThan(compared, 0)
        print("DENOISE nlm tiling: maxRel=\(maxRel)")
        XCTAssertLessThan(maxRel, 1e-3, "分块 == 整幅：maxRel=\(maxRel)")
    }

    /// FULL Δfootprint <3GB（MemoryBudget 门）：100MP @168 B/px ≈ 16.8GB
    /// → 必然分块；每 tile halo 扩展工作集 <3GB。
    func testFullFootprintBudget() {
        let fullW = 11648, fullH = 8736
        let budget = 3.0e9
        let bpx = (3.5 + 7.0) * 16 // 168 @ max_scale 7
        XCTAssertGreaterThan(
            Double(fullW * fullH) * bpx, budget, "100MP FULL 波列必分块")
        let tiles = TilingPlan.tiles(
            forWidth: fullW, height: fullH, maxTileBytes: 512 << 20,
            bytesPerPixel: Int(bpx), overlap: 128)
        XCTAssertGreaterThan(tiles.count, 1, "分块真的发生（grid \(tiles.count) >1）")
        var compared = 0
        var worst: Double = 0
        for tile in tiles {
            let bytes = Double((tile.width + 256) * (tile.height + 256)) * 16
            worst = max(worst, bytes)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        print("DENOISE 100MP tiles=\(tiles.count) worst-read-plane=\(worst / 1e9)GB")
        // Δfootprint 门 = tiling 驱动下的峰值工作集（单 tile 读平面），
        // 16.8GB 的未分块账面值被 TilingPlan 强制分块封顶。
        XCTAssertLessThan(worst, budget, "单 tile 读平面 <3GB（FULL Δfootprint 门）")
    }
}
