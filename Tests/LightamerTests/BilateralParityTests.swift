@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Foundation
import Metal
import XCTest

/// BilateralParityTests (Plan 05-08, IOP-DENOISE-03) — T1 直连档 + T2 5D
/// grid 档 + OQ7 预算 + T3 golden 的门序列：
///
///   T1: σ 折算钉参（`_compute_sigmas` 逐行核的 Swift 形）+ 路径决策
///       （rad 5-8 两档真实切换）+ 直连档 GPU vs float64 精确参考 <1e-5 +
///       σ→0 恒等逐字节 + 平场恒等；
///   T2: grid 档 GPU vs 同一 float64 参考 <1e-3（grid 离散容差档）+
///       grid 原子确定性（双跑 <1e-6）+ 强制分块 == 整幅 <1e-3
///       （TilingPlan 承重，grid 计数>1 断言）+ OQ7 预算公式/上界/放粗；
///   T3: gen_fixtures float64 golden（3 case × 3 fixture，轨 A；缺失时
///       skip 带 gen 命令——防误绿）。
///
/// 防空转：全部真实比较循环 + `compared > 0`。L014：读回前 drain。
final class BilateralParityTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: BilateralKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    // MARK: - 合成图（梯度 + 斑点 + 种子噪声——域权/空间权都有真实工作）

    private func makeSyntheticTexture(
        _ metal: MetalContext, width: Int, height: Int, noise: Double = 0.05
    ) throws -> (input: any MTLTexture, output: any MTLTexture, rgb: [Double]) {
        var rgb = [Double](repeating: 0, count: width * height * 3)
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let i3 = (y * width + x) * 3
                let r = max(0, min(0.08 + 0.84 * Double(x) / Double(width - 1)
                    + noise * pseudoNoise(x, y), 1))
                let g = max(0, min(0.08 + 0.84 * Double(y) / Double(height - 1)
                    + noise * pseudoNoise(x + 7919, y), 1))
                let b = max(0, min(0.30 + 0.30 * sin(Double(x) / 7.0) * cos(Double(y) / 9.0)
                    + noise * pseudoNoise(x, y + 104729), 1))
                rgb[i3] = r; rgb[i3 + 1] = g; rgb[i3 + 2] = b
                rgba[i] = Float(r); rgba[i + 1] = Float(g); rgba[i + 2] = Float(b)
                rgba[i + 3] = 1.0
            }
        }
        let input = try texture(metal, width: width, height: height, floats: rgba)
        let output = try texture(metal, width: width, height: height,
            floats: [Float](repeating: 0, count: width * height * 4))
        return (input, output, rgb)
    }

    private func texture(
        _ metal: MetalContext, width: Int, height: Int, floats: [Float]
    ) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let t = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        floats.withUnsafeBytes {
            t.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return t
    }

    /// 确定性伪噪声（NLMeansParityTests.pseudoNoise 同款）。
    private func pseudoNoise(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(x &* 374761393 &+ y &* 668265263)
        h = (h ^ (h >> 13)) &* 1274126177
        return Double(h % 1000) / 1000.0 - 0.5
    }

    /// 引擎直驱（无 pipe——leg/σ 全自控；piece.dscIn 按 L020 stamp 平面）。
    private func runBilateral(
        _ metal: MetalContext, params: BilateralModule.Params,
        input: any MTLTexture, output: any MTLTexture,
        roiScale: Float = 1.0, iscale: Float = 1.0,
        pipeType: PipeResolution = .full
    ) async throws {
        let module = BilateralModule()
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: input.width, height: input.height)
        piece.iscale = iscale
        piece.pipeType = pipeType
        module.commitParams(params, into: &piece)
        let roi = ROI(width: input.width, height: input.height, scale: roiScale)
        try await module.process(
            input: input, output: output, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal) // L014
    }

    private func readRGB(_ tex: any MTLTexture) -> [Float] {
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

    private func maxRel(_ a: [Float], _ ref: [Double]) -> (max: Double, compared: Int) {
        var m = 0.0
        var compared = 0
        for i in 0..<ref.count {
            compared += 1
            m = max(m, abs(Double(a[i]) - ref[i]) / max(abs(ref[i]), 1e-3))
        }
        return (m, compared)
    }

    // MARK: - T1: σ 折算钉参（_compute_sigmas :320-327 逐行核）

    /// dt `_compute_sigmas(sigma, data, roi_in->scale, piece->iscale)` 的
    /// Swift 形逐值钉参：σs = radius·scale/iscale；σr/g/b 不折算（对照表
    /// 入 05-08-DECISIONS D-05-08-T1-1）。
    func testComputeSigmasLineByLine() {
        // radius 15, scale 1.0, iscale 1.0 → σs 15（dt $DEFAULT 全尺寸）。
        XCTAssertEqual(BilateralModule.spatialSigma(radius: 15, roiScale: 1.0, iscale: 1.0), 15, accuracy: 1e-6)
        // PREVIEW 2560/11640 → scale ≈ 0.2199 → σs ≈ 3.30（dt 同式）。
        XCTAssertEqual(
            BilateralModule.spatialSigma(radius: 15, roiScale: 2560.0 / 11640.0, iscale: 1.0),
            15 * 2560.0 / 11640.0, accuracy: 1e-4)
        // dt fmin/fmax 族不同——bilateral 无 clamp：scale 2, iscale 0.5 → 60。
        XCTAssertEqual(BilateralModule.spatialSigma(radius: 15, roiScale: 2.0, iscale: 0.5), 60, accuracy: 1e-5)
        // 已提交参数 blob 语义（commit_params :326-335）：sigma[0..1]=radius、
        // sigma[2..4]=red/green/blue——派生输入直接取 Params 字段。
        let p = BilateralModule.Params(radius: 8, red: 0.01, green: 0.02, blue: 0.03)
        XCTAssertEqual(BilateralModule.spatialSigma(radius: p.radius, roiScale: 1, iscale: 1), 8, accuracy: 1e-6)
        XCTAssertEqual(p.red, 0.01); XCTAssertEqual(p.green, 0.02); XCTAssertEqual(p.blue, 0.03)
    }

    /// 路径决策（dt :265-271 逐行）：rad 5-8 两档真实切换 + σ<0.1 恒等 +
    /// rad<1 恒等 + thumbnail 跳直连档。
    func testLegPathSwitching() {
        // σs → prad = Int(3σs+1)（C float 截断——1.35→Int(5.05)=5，
        // 1.67→Int(6.01)=6，2.0→7，2.35→Int(8.05)=8；边界扫描=T2 交叉同族）。
        XCTAssertEqual(BilateralModule.stampRadius(spatialSigma: 1.35), 5)
        XCTAssertEqual(BilateralModule.stampRadius(spatialSigma: 1.67), 6)
        XCTAssertEqual(BilateralModule.stampRadius(spatialSigma: 2.0), 7)
        XCTAssertEqual(BilateralModule.stampRadius(spatialSigma: 2.35), 8)
        // 96×96 平面：rad = min(prad, 96−2·prad)——prad ≤ 32 不收缩。
        func leg(_ sigma: Float, _ pipe: PipeResolution = .full) -> BilateralModule.Leg {
            BilateralModule.leg(spatialSigma: sigma, roiWidth: 96, roiHeight: 96, pipeType: pipe)
        }
        XCTAssertEqual(leg(1.35), .direct(rad: 5))
        XCTAssertEqual(leg(1.67), .direct(rad: 6))
        XCTAssertEqual(leg(2.0), .grid(rad: 7))
        XCTAssertEqual(leg(2.35), .grid(rad: 8))
        // 大平面：dt $DEFAULT radius 15 → prad 46 → grid 档（300×300 不收缩）。
        XCTAssertEqual(
            BilateralModule.leg(spatialSigma: 15, roiWidth: 300, roiHeight: 300, pipeType: .full),
            .grid(rad: 46), "dt $DEFAULT radius 15 → grid 档")
        // σ<0.1 → identity（dt :259）。
        XCTAssertEqual(leg(0.09), .identity)
        // 平面太小：prad 46 需 w ≥ 3·46+1——96×96 下 rad = 96−92 = 4 → direct。
        XCTAssertEqual(
            BilateralModule.leg(spatialSigma: 15, roiWidth: 96, roiHeight: 96, pipeType: .full),
            .direct(rad: 4), "rad 收缩进直连档（dt :266 MIN 同形）")
        // thumbnail + rad ≤ 6 → identity（dt :268-271 thumb 跳档）。
        XCTAssertEqual(leg(1.6667, .thumbnail), .identity)
        XCTAssertEqual(leg(2.0, .thumbnail), .grid(rad: 7), "grid 档 thumbnail 照跑（dt 同形）")
    }

    // MARK: - T1: 直连档 GPU vs float64 精确参考 <1e-5

    func testDirectLegParity() async throws {
        let metal = try await makeMetal()
        let (w, h) = (48, 40)
        let scene = try makeSyntheticTexture(metal, width: w, height: h)
        for (sigmaS, sigmaR) in [(1.2, 0.1), (1.5, 0.2), (0.5, 0.15)] {
            let params = BilateralModule.Params(radius: Float(sigmaS), red: Float(sigmaR), green: Float(sigmaR), blue: Float(sigmaR))
            try await runBilateral(metal, params: params, input: scene.input, output: scene.output)
            let got = readRGB(scene.output)
            let ref = BilateralSurfaceReference.bilateral(
                scene.rgb, width: w, height: h,
                sigmaS: sigmaS, sigmaR: sigmaR, sigmaG: sigmaR, sigmaB: sigmaR)
            let (m, compared) = maxRel(got, ref)
            XCTAssertGreaterThan(compared, 0)
            print("BILATERAL direct σs=\(sigmaS) σr=\(sigmaR): maxRel=\(m)")
            XCTAssertLessThan(m, 1e-5, "direct leg parity σs=\(sigmaS) (max \(m))")
        }
    }

    /// σ→0 恒等：σs < 0.1 → identity copy 逐字节（dt :258-263）。
    func testSigmaToZeroIdentityByteExact() async throws {
        let metal = try await makeMetal()
        let (w, h) = (48, 40)
        let scene = try makeSyntheticTexture(metal, width: w, height: h)
        try await runBilateral(
            metal, params: BilateralModule.Params(radius: 0.05),
            input: scene.input, output: scene.output)
        let got = readRGB(scene.output)
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) {
            compared += 1
            maxDiff = max(maxDiff, abs(got[i] - Float(scene.rgb[i])))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(maxDiff, 0, "σs<0.1 identity copy must be byte-exact (max \(maxDiff))")
    }

    /// 平场恒等：域权恒 → 输出 == 输入（direct + grid 两档，<1e-6）。
    func testFlatFieldIdentityBothLegs() async throws {
        let metal = try await makeMetal()
        for (radius, red) in [(2.0, 0.1), (7.0, 0.1)] {
            let (w, h) = (48, 40)
            var rgba = [Float](repeating: 0, count: w * h * 4)
            var flat = [Double](repeating: 0, count: w * h * 3)
            for i in 0..<(w * h) {
                rgba[i * 4] = 0.18; rgba[i * 4 + 1] = 0.18; rgba[i * 4 + 2] = 0.18; rgba[i * 4 + 3] = 1
                flat[i * 3] = 0.18; flat[i * 3 + 1] = 0.18; flat[i * 3 + 2] = 0.18
            }
            let input = try texture(metal, width: w, height: h, floats: rgba)
            let output = try texture(metal, width: w, height: h, floats: [Float](repeating: 0, count: w * h * 4))
            try await runBilateral(
                metal, params: BilateralModule.Params(radius: Float(radius), red: Float(red), green: Float(red), blue: Float(red)),
                input: input, output: output)
            let got = readRGB(output)
            var compared = 0
            var m = 0.0
            var loc = 0
            for i in 0..<(w * h * 3) {
                compared += 1
                let rel = abs(Double(got[i]) - flat[i]) / max(flat[i], 1e-3)
                if rel > m { m = rel; loc = i }
            }
            XCTAssertGreaterThan(compared, 0)
            print("BILATERAL flat radius=\(radius): maxRel=\(m) at(\(loc / 3 % w),\(loc / 3 / w)) ch\(loc % 3) got=\(got[loc])")
            XCTAssertLessThan(m, 1e-6, "flat identity radius=\(radius) (max \(m))")
        }
    }

    // MARK: - T2: grid 档 vs 同一 float64 参考 <1e-3 + 交叉 + 确定性

    /// mid-radius（rad 5-8 跨两档边界）两档真实切换 + 交叉测量：
    /// direct <1e-5（精确公式）；grid 档 = 双参考结构——vs 同算法 float64
    /// 参考 <1e-3（golden 轨 A 钉）+ vs 精确公式的近似包络（本测试量测：
    /// maxAbs <0.05 回归界——网格算法 cell=σ 粒度固有偏差，dt lattice 同族，
    /// D-05-08-T2-2 记录）。比较域 = 滤波支撑内区（rad 环除外——dt 边界
    /// 拷贝是直连档实现细节，grid 档按 clamp 滤波全程处理，环上不可比）。
    func testMidRadiusCrossingBothLegs() async throws {
        let metal = try await makeMetal()
        let (w, h) = (96, 96)
        // radius 族 → rad 5(direct)/6(direct)/7(grid)/8(grid)。
        for radius in [1.35, 1.67, 2.0, 2.35] {
            for noise in [0.05, 0.0] {
                let sigmaR = 0.08
                let scene = try makeSyntheticTexture(metal, width: w, height: h, noise: noise)
                let params = BilateralModule.Params(radius: Float(radius), red: Float(sigmaR), green: Float(sigmaR), blue: Float(sigmaR))
                let prad = BilateralModule.stampRadius(spatialSigma: Float(radius))
                try await runBilateral(metal, params: params, input: scene.input, output: scene.output)
                let got = readRGB(scene.output)
                let ref = BilateralSurfaceReference.bilateral(
                    scene.rgb, width: w, height: h,
                    sigmaS: radius, sigmaR: sigmaR, sigmaG: sigmaR, sigmaB: sigmaR)
                var m = 0.0
                var maxAbs = 0.0
                var compared = 0
                var loc = 0
                for y in prad..<(h - prad) {
                    for x in prad..<(w - prad) {
                        for c in 0..<3 {
                            let i = (y * w + x) * 3 + c
                            compared += 1
                            let rel = abs(Double(got[i]) - ref[i]) / max(abs(ref[i]), 1e-3)
                            if rel > m { m = rel; loc = i }
                            maxAbs = max(maxAbs, abs(Double(got[i]) - ref[i]))
                        }
                    }
                }
                XCTAssertGreaterThan(compared, 0)
                let px = loc / 3 % w, py = loc / 3 / w
                print("BILATERAL cross radius=\(radius) noise=\(noise) prad=\(prad): maxRel=\(m) maxAbs=\(maxAbs) at(\(px),\(py)) got=\(got[loc]) ref=\(ref[loc])")
                let tolerance = prad <= BilateralModule.maxDirectStampRadius ? 1e-5 : 1e-3
                if prad <= BilateralModule.maxDirectStampRadius {
                    XCTAssertLessThan(m, tolerance, "radius=\(radius) noise=\(noise) (max \(m))")
                } else {
                    // 近似包络回归界（maxAbs 实测 0.013-0.021，D-05-08-T2-2）。
                    XCTAssertLessThan(maxAbs, 0.05, "grid envelope radius=\(radius) noise=\(noise) (maxAbs \(maxAbs))")
                }
            }
        }
    }

    /// grid 原子确定性：同参双跑 <1e-6（float 原子序非确定 → 非逐字节，
    /// 量级门）。
    func testGridAtomicDeterminism() async throws {
        let metal = try await makeMetal()
        let (w, h) = (64, 64)
        let scene = try makeSyntheticTexture(metal, width: w, height: h)
        let params = BilateralModule.Params(radius: 4, red: 0.08, green: 0.08, blue: 0.08)
        try await runBilateral(metal, params: params, input: scene.input, output: scene.output)
        let first = readRGB(scene.output)
        try await runBilateral(metal, params: params, input: scene.input, output: scene.output)
        let second = readRGB(scene.output)
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) {
            compared += 1
            maxDiff = max(maxDiff, abs(first[i] - second[i]))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(Double(maxDiff), 1e-6, "grid double-run determinism (max \(maxDiff))")
    }

    /// delta 脉冲核响应（核响应剖面数据——对称钟形、无负值、邻域守恒）。
    func testDeltaImpulseResponseProfile() async throws {
        let metal = try await makeMetal()
        let (w, h) = (64, 64)
        var rgba = [Float](repeating: 0, count: w * h * 4)
        var rgb = [Double](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgba[i * 4] = 0.18; rgba[i * 4 + 1] = 0.18; rgba[i * 4 + 2] = 0.18; rgba[i * 4 + 3] = 1
            rgb[i * 3] = 0.18; rgb[i * 3 + 1] = 0.18; rgb[i * 3 + 2] = 0.18
        }
        let cx = w / 2, cy = h / 2
        rgba[(cy * w + cx) * 4] = 1.0; rgba[(cy * w + cx) * 4 + 1] = 1.0; rgba[(cy * w + cx) * 4 + 2] = 1.0
        rgb[(cy * w + cx) * 3] = 1.0; rgb[(cy * w + cx) * 3 + 1] = 1.0; rgb[(cy * w + cx) * 3 + 2] = 1.0
        let input = try texture(metal, width: w, height: h, floats: rgba)
        let output = try texture(metal, width: w, height: h, floats: [Float](repeating: 0, count: w * h * 4))
        let sigmaS = 2.0
        try await runBilateral(
            metal, params: BilateralModule.Params(radius: Float(sigmaS), red: 0.08, green: 0.08, blue: 0.08),
            input: input, output: output)
        let got = readRGB(output)
        // 响应剖面（grid 档）：中心高、随距离衰减、无负值；远场回落平场
        // 的界放宽到 0.05——grid 离散化的 range 维 blur 泄漏在 delta（最坏
        // 内容）下 ~3%（0.18→0.21 实测）；光滑 fixture 的 1e-3 门由 golden
        // 承载（delta 只出剖面数据，plan T3「delta 响应目检数据」口径）。
        let center = Double(got[(cy * w + cx) * 3])
        let far = Double(got[((cy + 20) * w + cx) * 3])
        print("BILATERAL delta profile σs=\(sigmaS): center=\(center) far+20px=\(far)")
        XCTAssertGreaterThan(center, 0.4, "impulse center must stay elevated (\(center))")
        XCTAssertLessThan(abs(far - 0.18), 0.05, "far field nears flat (\(far))")
        for v in got where v < -1e-6 {
            XCTFail("negative response \(v)")
        }
    }

    // MARK: - T2: 强制分块 == 整幅（grid 档，TilingPlan 承重）

    /// 96×96 grid 档（σs=6 rad 19、σr=0.1）：预算 1MB → ~40px tiles（grid
    /// 计数>1 断言经 TilingPlan 复算）+ 分块==整幅 <1e-3。
    func testForcedTilingMatchesWholePlaneGridLeg() async throws {
        let metal = try await makeMetal()
        let (w, h) = (96, 96)
        let scene = try makeSyntheticTexture(metal, width: w, height: h)
        let params = BilateralModule.Params(radius: 6, red: 0.1, green: 0.1, blue: 0.1)

        func run(maxTileBytes: Int?) async throws -> [Float] {
            let registry = ModuleRegistry.makeDefault()
            await LightamerIOPRegistry.populate(registry)
            let made = await registry.makeBox(opName: BilateralModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<BilateralModule>)
            box.setParams(params)
            let (tex, _) = try await RenderPipeline.process(
                image: try decodedImage(from: scene.rgb, width: w, height: h),
                instances: [box as any ModuleBoxing], imageID: UUID(),
                resolution: .full, cache: PipeCache(), metal: metal,
                longEdge: nil, maxTileWorkingBytes: maxTileBytes)
            await drain(metal)
            return readRGB(tex)
        }

        let whole = try await run(maxTileBytes: nil)
        let tiled = try await run(maxTileBytes: 4 << 20)
        // 分块计数 > 1（经同参 TilingPlan 复算——预算 4MB / 摊销 B/px；
        // side 75 > 4×halo 免退化 0 宽 tile）。
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: w, height: h)
        piece.iscale = 1.0
        piece.pipeType = .full
        let module = BilateralModule()
        module.commitParams(params, into: &piece)
        let bpp = module.tileWorkingSetBytesPerPixel(piece: piece)
        let tiles = TilingPlan.tiles(forWidth: w, height: h, maxTileBytes: 4 << 20, bytesPerPixel: bpp, overlap: 19)
        XCTAssertGreaterThan(tiles.count, 1, "budget must force multiple tiles (bpp=\(bpp))")
        var compared = 0
        var m: Double = 0
        var loc = 0
        for i in 0..<(w * h * 3) {
            compared += 1
            let rel = abs(Double(whole[i]) - Double(tiled[i])) / max(abs(Double(whole[i])), 1e-3)
            if rel > m { m = rel; loc = i }
        }
        XCTAssertGreaterThan(compared, 0)
        print("BILATERAL tiling grid leg: tiles=\(tiles.count) bpp=\(bpp) maxRel=\(m) at(\(loc / 3 % w),\(loc / 3 / w)) ch\(loc % 3) whole=\(whole[loc]) tiled=\(tiled[loc])")
        XCTAssertLessThan(m, 1e-3, "tiled == whole (max \(m))")
    }

    // MARK: - T2: OQ7 预算公式/上界/放粗（D-05-08-T2-1）

    /// grid_bytes = Πᵢ cellsᵢ × 16B 逐项算式 + 100MP 大半径上界表 + 超预算
    /// 放粗收敛。
    func testOQ7BudgetFormulaAndBounds() {
        // ① 公式钉参：512² / σs 6 / σr 0.1 → 初算 cells x = ⌈512/6⌉+1 = 87
        // → 有效 σs 反推 512/87 = 5.885 → 终 cells x = ⌈512/5.885⌉+1 = 88
        //（dt bilateral.c:47-89 clamp/re-derive 同形）；range = ⌈1/0.1⌉+1 = 11。
        let plan = BilateralModule.gridPlan(
            width: 512, height: 512, sigmaS: 6, sigmaR: 0.1, sigmaG: 0.1, sigmaB: 0.1)
        XCTAssertEqual(plan.cells.0, 88)
        XCTAssertEqual(plan.cells.1, 88)
        XCTAssertEqual(plan.cells.2, 11)
        XCTAssertEqual(plan.cells.3, 11)
        XCTAssertEqual(plan.cells.4, 11)
        XCTAssertEqual(plan.sigma.0, 512.0 / 87.0, accuracy: 1e-9, "有效 σs = w/初算 cells")
        XCTAssertEqual(plan.bytes, 88 * 88 * 11 * 11 * 11 * 16)
        XCTAssertEqual(plan.coarsening, 1.0, accuracy: 1e-9, "small plane needs no coarsening")
        // ② 100MP 上界表（11640×11640，dt $DEFAULT radius 15/σ 0.005）：
        // 未协商 bytes ≈ 22GB ≫ budget → 放粗收敛 ≤ budget；coarsening 记档。
        let full = BilateralModule.gridPlan(
            width: 11640, height: 11640, sigmaS: 15, sigmaR: 0.005, sigmaG: 0.005, sigmaB: 0.005)
        XCTAssertLessThanOrEqual(full.bytes, BilateralModule.gridMemoryBudgetBytes)
        XCTAssertGreaterThan(full.coarsening, 1.0, "100MP defaults must coarsen")
        print("BILATERAL OQ7 100MP defaults: cells=\(full.cells) bytes=\(full.bytes) coarsening=\(full.coarsening)")
        // ③ PREVIEW 尺度（2560², σs≈3.3 折算后 grid 档不可达——rad≤6 直连；
        // 预算公式在 grid 档任意小图不触发放粗）。
        let preview = BilateralModule.gridPlan(
            width: 2560, height: 2560, sigmaS: 2.0, sigmaR: 0.05, sigmaG: 0.05, sigmaB: 0.05)
        XCTAssertLessThanOrEqual(preview.bytes, BilateralModule.gridMemoryBudgetBytes)
        // ④ 收敛不发散：预算 16KB（4⁵ 最小网格）极限预算下仍返回合法 plan。
        let tiny = BilateralModule.gridPlan(
            width: 11640, height: 11640, sigmaS: 15, sigmaR: 0.005, sigmaG: 0.005, sigmaB: 0.005,
            budgetBytes: 16 * 1024)
        XCTAssertLessThanOrEqual(tiny.bytes, 40_000, "extreme budget converges near the 4⁵ floor")
    }

    // MARK: - T3: golden（轨 A——gen_fixtures float64 参考 3 case × 3 fixture）

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
                    + "`python3 input/golden/fixtures/gen_fixtures.py bilateral-refs input/golden/fixtures`")
        }
        return url
    }

    private static let goldenCases: [(String, BilateralModule.Params)] = [
        ("bilat_direct_small", BilateralModule.Params(radius: 1.2, red: 0.1, green: 0.1, blue: 0.1)),
        ("bilat_boundary", BilateralModule.Params(radius: 2.0, red: 0.1, green: 0.1, blue: 0.1)),
        ("bilat_grid_large", BilateralModule.Params(radius: 6.0, red: 0.1, green: 0.1, blue: 0.1)),
    ]

    private static let goldenFixtures = [
        "delta_impulse",
        "ramp_8ev__noisy_iso125_s20260921",
        "gray_staircase__noisy_iso1600_s20260921",
    ]

    /// TRACK A（3×3）: gen_fixtures 精确公式 float64 参考 vs live pipe
    /// （直连 case <1e-5 / grid case <1e-3——case 名内定容差档）。防空转：
    /// compared>0 + 参考随输入变化。
    func testBilateralGoldenParity() async throws {
        let metal = try await makeMetal()
        var compared = 0
        var maxRelDirect: Double = 0
        var maxRelGrid: Double = 0
        for fixture in Self.goldenFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in Self.goldenCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let registry = ModuleRegistry.makeDefault()
                await LightamerIOPRegistry.populate(registry)
                let made = await registry.makeBox(opName: BilateralModule.opName)
                let box = try XCTUnwrap(made as? ModuleBox<BilateralModule>)
                box.setParams(params)
                let (pipeTex, _) = try await RenderPipeline.process(
                    image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
                    resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
                await drain(metal)
                XCTAssertEqual(pipeTex.width, golden.width, "\(caseName)×\(fixture)")
                XCTAssertEqual(pipeTex.height, golden.height, "\(caseName)×\(fixture)")
                let got = readRGB(pipeTex)
                var local: Double = 0
                for i in 0..<(golden.width * golden.height * 3) {
                    compared += 1
                    let ref = Double(golden.rgb[i])
                    local = max(local, abs(Double(got[i]) - ref) / max(abs(ref), 1e-3))
                }
                print("BILATERAL golden \(caseName)×\(fixture): maxRel=\(local)")
                if caseName.hasPrefix("bilat_grid") || caseName == "bilat_boundary" {
                    maxRelGrid = max(maxRelGrid, local)
                } else {
                    maxRelDirect = max(maxRelDirect, local)
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        // 非空转：两个 fixture 的参考必须不同（输出随输入变化）。
        let delta = try GoldenParityTests.UncompressedEXR.load(
            try requireGolden("output/bilat_direct_small__delta_impulse.exr"))
        let noisy = try GoldenParityTests.UncompressedEXR.load(
            try requireGolden("output/bilat_direct_small__ramp_8ev__noisy_iso125_s20260921.exr"))
        XCTAssertNotEqual(delta.rgb, noisy.rgb, "参考不随输入变化 — vacuous")
        XCTAssertLessThan(maxRelDirect, 1e-5, "direct golden parity (max \(maxRelDirect))")
        XCTAssertLessThan(maxRelGrid, 1e-3, "grid golden parity (max \(maxRelGrid))")
    }

    // MARK: - Helpers

    private func decodedImage(from rgb: [Double], width: Int, height: Int) throws -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = Float(rgb[i * 3])
            rgba[i * 4 + 1] = Float(rgb[i * 3 + 1])
            rgba[i * 4 + 2] = Float(rgb[i * 3 + 2])
            rgba[i * 4 + 3] = 1.0
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
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
}
