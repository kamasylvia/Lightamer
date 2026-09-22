@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Foundation
import Metal
import XCTest

/// MonochromeGridTests (Plan 05-05-T2) — bilateral grid 腿接线：
/// grid==直接窗口小半径交叉（float64 参考，路径断言防 vacuous）+
/// TilingPlan 第三消费者断言（强制分块 vs 整幅）+ tileHalo/摊销定值 pin。
///
/// 防空转：真实比较循环 + compared>0；grid 路径断言（grid 腿输出 ≠
/// bypass 输出——grid 真实触发）。
final class MonochromeGridTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: MonochromeKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    /// 512×384 合成工作域 RGB（R/G 梯度 + B 棋盘——Lab 域空间变化，
    /// filter 非平场，grid 真实触发）。
    private func makeGradientImage() throws -> DecodedImage {
        let width = 512, height = 384
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = 0.05 + 0.9 * Float(x) / Float(width - 1)
                rgba[i + 1] = 0.05 + 0.9 * Float(y) / Float(height - 1)
                rgba[i + 2] = ((x / 32 + y / 32) % 2 == 0) ? 0.15 : 0.6
                rgba[i + 3] = 1.0
            }
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
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    /// monochrome 单件 pipe（LocalContrastTests.runBilatPipe 模式——工作域
    /// 合成图直驱，无 colorin；分块/整幅双腿同链，比较自洽）。
    private func runMonoPipe(
        image: DecodedImage, params: MonochromeModule.Params, metal: MetalContext,
        maxTileBytes: Int? = nil
    ) async throws -> [Float] {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: MonochromeModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<MonochromeModule>)
        box.setParams(params)
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil, maxTileWorkingBytes: maxTileBytes
        )
        await drain(metal) // L014
        XCTAssertEqual(texture.width, 512)
        XCTAssertEqual(texture.height, 384)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        var rgb = [Float](repeating: 0, count: texture.width * texture.height * 3)
        for i in 0..<(texture.width * texture.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return rgb
    }

    /// 64×64 Lab 内容（L 梯度 + 高斯斑点——BilateralGrid3DTests 同分布）→
    /// float64 直接窗口（3×3 高斯 σ=1 近似 grid 小半径行为）vs grid 参考
    /// 全链：两者皆平滑（相对输入移动），且 grid 输出有界确定。
    /// 这是「grid==直接窗口小半径交叉」的 in-test 形态（grid 离散化容差档
    /// ——plan T2；float64 grid 参考 = BilateralGridReference；逐值 parity
    /// 由 T3 轨 A 钉）。
    func testGridVsDirectWindowSmallRadiusCrossing() {
        let w = 64, h = 64
        var luma = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let blob = 20.0 * exp(-(pow(Double(x) - 32, 2) + pow(Double(y) - 32, 2)) / 100.0)
                luma[y * w + x] = min(20.0 + 60.0 * Double(x) / 63.0 + blob, 100.0)
            }
        }
        // grid 腿（σ_s=20/σ_r=250/detail=−1——monochrome 值）。
        var grid = BilateralGridReference.makeGrid(width: w, height: h, sigmaS: 20, sigmaR: 250)
        BilateralGridReference.splat(&grid, luma: luma, width: w, height: h)
        BilateralGridReference.blur(&grid)
        let gridOut = BilateralGridReference.slice(grid, luma: luma, width: w, height: h, detail: -1)
        // 直接窗口：3×3 高斯平滑（σ=1，归一化）。
        let k: [Double] = [1, 2, 1, 2, 4, 2, 1, 2, 1].map { $0 / 16 }
        var direct = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var acc = 0.0
                for ky in -1...1 {
                    for kx in -1...1 {
                        let xx = min(max(x + kx, 0), w - 1)
                        let yy = min(max(y + ky, 0), h - 1)
                        acc += luma[yy * w + xx] * k[(ky + 1) * 3 + (kx + 1)]
                    }
                }
                direct[y * w + x] = acc
            }
        }
        // 交叉：两者都相对输入移动（平滑真实发生），输出皆有界；
        // grid vs 直接窗口在 interior 上形状一致（同为平滑器；逐值 parity
        // 由 T3 轨 A 钉，此处只钉形状 + 非 vacuous）。
        var compared = 0
        var gridMoved = 0, directMoved = 0
        var worst: Double = 0
        for y in 2..<(h - 2) {
            for x in 2..<(w - 2) {
                let i = y * w + x
                compared += 1
                if abs(gridOut[i] - luma[i]) / max(abs(luma[i]), 1e-9) > 1e-4 { gridMoved += 1 }
                if abs(direct[i] - luma[i]) / max(abs(luma[i]), 1e-9) > 1e-4 { directMoved += 1 }
                XCTAssertGreaterThanOrEqual(gridOut[i], 0)
                XCTAssertLessThan(gridOut[i], 200)
                worst = max(worst, abs(gridOut[i] - direct[i]) / max(abs(direct[i]), 1e-9))
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertGreaterThan(gridMoved, 100, "grid 平滑真实发生")
        XCTAssertGreaterThan(directMoved, 100, "直接窗口平滑真实发生")
        XCTAssertLessThan(worst, 1.0, "grid vs 直接窗口形状门（同为平滑器）")
    }

    /// GPU grid 腿路径断言：monochrome 全链（filter→grid→apply）vs bypass
    /// （filter→apply）：两者输出不同（grid 真实触发——路径非 vacuous），
    /// 且 grid 腿输出单色（R==G==B）有界非 NaN。
    func testGPUGridPathActuallyEngages() async throws {
        let metal = try await makeMetal()
        let image = try makeGradientImage()
        let params = MonochromeModule.Params(a: 32, b: 64, size: 2.3, highlights: 0)
        // grid 腿 vs bypass：同一模块经 useGridSmoothing 开关双跑。
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        func run(useGrid: Bool) async throws -> [Float] {
            let made = await registry.makeBox(opName: MonochromeModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<MonochromeModule>)
            box.module.useGridSmoothing = useGrid
            box.setParams(params)
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
                resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil)
            await drain(metal) // L014
            var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
            floats.withUnsafeMutableBytes {
                texture.getBytes(
                    $0.baseAddress!, bytesPerRow: texture.width * 16,
                    from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
            return floats
        }
        let g = try await run(useGrid: true)
        let b = try await run(useGrid: false)
        var compared = 0
        var diffCount = 0
        var maxMonoDev: Float = 0
        for i in stride(from: 0, to: g.count, by: 4) {
            compared += 1
            // 单色断言（grid 腿输出 R==G==B——monochrome 输出语义）。
            maxMonoDev = max(maxMonoDev, abs(g[i] - g[i + 1]))
            maxMonoDev = max(maxMonoDev, abs(g[i + 1] - g[i + 2]))
            XCTAssertFalse(g[i].isNaN, "grid 输出非 NaN @\(i / 4)")
            var pxDiff: Float = 0
            for c in 0..<3 {
                pxDiff = max(pxDiff, abs(g[i + c] - b[i + c]) / max(abs(b[i + c]), 1e-9))
            }
            if pxDiff > 1e-5 { diffCount += 1 }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxMonoDev, 1e-4, "grid 腿输出单色（R==G==B）maxDev=\(maxMonoDev)")
        XCTAssertGreaterThan(diffCount, 100, "grid 腿真实触发（≠bypass，diff=\(diffCount))")
    }

    /// TilingPlan 第三消费者（LocalContrastTests 模式——强制分块 vs 整幅；
    /// grid 腿离散化容差档 <1e-3，plan T2）。
    /// 512×384 FULL：默认预算整幅 vs 1MB 预算强制分块（tile ~256px >
    /// halo=80——无反转；每 tile 独立 grid → 缝即超差）。
    func testForcedTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let image = try makeGradientImage()
        let params = MonochromeModule.Params(a: 32, b: 64, size: 2.3, highlights: 0)
        let whole = try await runMonoPipe(image: image, params: params, metal: metal)
        let tiled = try await runMonoPipe(
            image: image, params: params, metal: metal, maxTileBytes: 1 << 20)
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<whole.count {
            compared += 1
            maxDiff = max(maxDiff, abs(tiled[i] - whole[i]))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxDiff, 1e-3, "force-tiled FULL must match whole-plane <1e-3")
        // tile 声明 pin（第三消费者值——DECISIONS 定值表）：
        // halo = ceil(4·20) = 80（dt :315）；B/px = 16 + grid 摊销。
        let module = MonochromeModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: 512, height: 384)
        module.commitParams(MonochromeModule.Params(), into: &piece)
        let halo = module.tileHalo(
            roi: ROI(width: 512, height: 384, scale: 1.0), piece: piece)
        XCTAssertEqual(halo, 80, "tileHalo = ceil(4·σ_s=20) = 80（dt :315）")
        let bpx = module.tileWorkingSetBytesPerPixel(piece: piece)
        // 512×384@σ_s=20：grid 27×20×5=2700 cells ×2 buffers ×4B = 21600B；
        // 21600/196608 <1 ⇒ 16 + 0 = 16（FULL 小网格摊销归零；100MP 定值
        // 见 DECISIONS 定值表）。
        XCTAssertEqual(bpx, 16)
    }
}
