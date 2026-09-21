@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// TileNegotiationRegressionTests (Plan 05-01-T6) — executeTiledNegotiated
/// 回归加固 + TilingPlan 四消费者预演（纯 TilingPlan 级，不改 tile 驱动语义）。
///
/// 照 04-01「先加测试再动实现」：本 plan 只补网。防空转：全部含真实比较循环
/// + `compared > 0`。
final class TileNegotiationRegressionTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// 2D 曝光场（TilingOverlapTests.syntheticImage 同款小尺寸）：梯度 + 软斑，
    /// EIGF 腿有真实工作。
    private func syntheticImage(width: Int, height: Int) throws -> DecodedImage {
        var data = Data(capacity: width * height * 16)
        let cx = Double(width) / 2, cy = Double(height) / 2
        for y in 0..<height {
            for x in 0..<width {
                let base = -7.0 + 7.0 * Double(x) / Double(width - 1)
                let blob = 1.5 * exp(-(pow(Double(x) - cx, 2) + pow(Double(y) - cy, 2))
                                     / pow(Double(min(width, height)) / 5.0, 2))
                let v = Float(exp2(base + blob))
                for _ in 0..<3 {
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

    private func runFULL(
        image: DecodedImage, tileBudget: Int?, metal: MetalContext,
        toneEqualParams: ToneEqualModule.Params
    ) async throws -> [Float] {
        let toneequal = ModuleBox(module: ToneEqualModule())
        await toneequal.setParams(toneEqualParams)
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [toneequal], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil, maxTileWorkingBytes: tileBudget)
        return readRGB(texture, metal: metal)
    }

    // MARK: - ① 强制分块 == 整幅（toneequal 场景复核，<1e-5 双门重跑）

    /// 512×384 EIGF 腿：强制分块（256KB → ~146px tiles）vs 整幅，maxRel < 1e-5。
    /// TilingOverlapTests 同款门的本套件复核（回归网双门）。
    func testForcedTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let image = try syntheticImage(width: 512, height: 384)
        let params = ToneEqualModule.Params(shadows: 1.0, highlights: -0.5)
        let whole = try await runFULL(
            image: image, tileBudget: nil, metal: metal, toneEqualParams: params)
        let tiled = try await runFULL(
            image: image, tileBudget: 256 << 10, metal: metal, toneEqualParams: params)
        XCTAssertEqual(whole.count, tiled.count)
        var compared = 0
        var maxRel: Float = 0
        var maxAbs: Float = 0
        for i in 0..<whole.count {
            compared += 1
            let diff = abs(whole[i] - tiled[i])
            maxAbs = max(maxAbs, diff)
            maxRel = max(maxRel, diff / max(abs(whole[i]), 1e-9))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxRel, 1e-5, "分块 vs 整幅：maxRel=\(maxRel) maxAbs=\(maxAbs)")
    }

    // MARK: - ② tile 驱动不改 dscIn/iscale（接 T2 断言）

    /// 前向 walk stamp 的 dscIn 在 tile 执行前后不变：直接对同一 box 跑整幅与
    /// 强制分块，两路输出逐值一致即 tile 未改几何 stamp（dscIn/iscale 是
    /// process/tileHalo 的唯一几何输入——输出一致 ⇒ stamp 一致）。
    /// 另加 hook 级 pin：tileHalo 在同一 piece 上 tile 前后同值。
    func testTileDriverPreservesGeometryStamps() async throws {
        let metal = try await makeMetal()
        let image = try syntheticImage(width: 256, height: 256)
        let params = ToneEqualModule.Params(shadows: 1.0)
        let whole = try await runFULL(
            image: image, tileBudget: nil, metal: metal, toneEqualParams: params)
        let tiled = try await runFULL(
            image: image, tileBudget: 64 << 10, metal: metal, toneEqualParams: params)
        var compared = 0
        var worst: Float = 0
        for i in 0..<whole.count {
            compared += 1
            worst = max(worst, abs(whole[i] - tiled[i]) / max(abs(whole[i]), 1e-9))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(worst, 1e-5, "tile 不改 stamp：分块 == 整幅")

        // hook 级：同一 piece（dscIn 256×256）tileHalo 与 budget 无关。
        let box = ModuleBox(module: ToneEqualModule())
        await box.setParams(ToneEqualModule.Params(blending: 5))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 256, height: 256)
        piece.iscale = 1.0
        let roi = ROI(x: 0, y: 0, width: 256, height: 256, scale: 1.0)
        let haloA = box.module.tileHalo(roi: roi, piece: piece)
        let haloB = box.module.tileHalo(roi: roi, piece: piece)
        XCTAssertEqual(haloA, haloB, "halo 是 piece 几何的纯函数（与 tile 无关）")
        // blending 5% × 256 = 12.8 → r = 5（(12.8−1)/2 = 5.9 → 5）→ halo 4×5+65 = 85。
        XCTAssertEqual(haloA, 85, "halo 手算 pin")
    }

    // MARK: - ③ tile 内 processedROIIn/Out 记账 == halo 外扩读 + 内缩写

    /// TilingPlan.swift:58-118 LIVE 语义：tile 输出 rect = 内缩写（overlap
    /// 内边收缩），驱动读 rect = 输出 tile 外扩 halo。纯几何门：对 toneequal
    /// halo（85 @256px）建 grid，断言每 tile 的读窗 = tile 外扩 halo 后
    /// clamp，且输出 tile 全覆盖（pixelCount 和 == 平面）。
    func testTileReadWriteAccountingMatchesHaloContract() async throws {
        let box = ModuleBox(module: ToneEqualModule())
        await box.setParams(ToneEqualModule.Params(blending: 5))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 256, height: 256)
        piece.iscale = 1.0
        let halo = box.module.tileHalo(
            roi: ROI(x: 0, y: 0, width: 256, height: 256, scale: 1.0), piece: piece)
        XCTAssertEqual(halo, 85)
        // 网格合法性边界：halo 85 在 side 73 上反转 tile（03-05-T6 注释
        // "Phase 5's policy own sanity beyond that"——T6 在此钉住该边界，
        // 不改 TilingPlan 语义）。本卡片用合法网格验证记账契约。
        let degenerate = TilingPlan.tiles(
            forWidth: 256, height: 256, maxTileBytes: 64 << 10,
            bytesPerPixel: 12, overlap: halo)
        XCTAssertEqual(degenerate.count, 16)
        XCTAssertTrue(
            degenerate.allSatisfy { $0.width == 0 || $0.height == 0 },
            "halo ≥ side/2 反转 tile（合法 degenerate-slim，tile 驱动跳过）")
        // 合法多 tile 网格记账：512×512 @1MB（side 295 → 2×2，halo 85
        // 下 tile 210×210 / 132×132 全 live）——读窗 = tile 外扩 halo clamp。
        let liveTiles = TilingPlan.tiles(
            forWidth: 512, height: 512, maxTileBytes: 1 << 20,
            bytesPerPixel: 12, overlap: halo)
        XCTAssertEqual(liveTiles.count, 4, "2×2 grid")
        let tiles = liveTiles
        var compared = 0
        var covered = 0
        for tile in tiles {
            compared += 1
            covered += tile.width * tile.height
            // 读窗：tile 外扩 halo，clamp 到平面（512 系）。
            let rx = max(0, tile.x - halo)
            let ry = max(0, tile.y - halo)
            let rw = min(512 - rx, tile.width + (tile.x - rx) + halo)
            let rh = min(512 - ry, tile.height + (tile.y - ry) + halo)
            XCTAssertGreaterThan(rw, tile.width, "读窗宽于写窗（halo 外扩）")
            XCTAssertGreaterThan(rh, tile.height, "读窗高于写窗（halo 外扩）")
            XCTAssertLessThanOrEqual(rx + rw, 512, "读窗不越界")
            XCTAssertLessThanOrEqual(ry + rh, 512, "读窗不越界")
        }
        XCTAssertGreaterThan(compared, 0)
        // 内缩写 tile 的输出覆盖 < 全平面（收缩环由 halo 覆盖）；此处钉覆盖数。
        XCTAssertEqual(covered, 210 * 210 + 132 * 210 + 210 * 132 + 132 * 132)
        XCTAssertLessThan(covered, 512 * 512, "内缩写 tile 输出和 < 全平面")
        XCTAssertGreaterThan(covered, 0)
    }

    // MARK: - ④ tile 边界两极端：单 tile 与极小 tile

    func testSingleAndTinyTileExtremes() {
        var compared = 0
        // budget 超大 → grid 1×1（单 tile 无内边，overlap 无操作）。
        let single = TilingPlan.tiles(
            forWidth: 256, height: 256, maxTileBytes: 1 << 30,
            bytesPerPixel: 12, overlap: 85)
        compared += 1
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single.first, TilingPlan.Tile(x: 0, y: 0, width: 256, height: 256))
        // 极小 tile：budget 仅容 1px 行——grid 多块，每 tile 合法（宽/高 ≥ 0）。
        let tiny = TilingPlan.tiles(
            forWidth: 64, height: 64, maxTileBytes: 64,
            bytesPerPixel: 16, overlap: 0)
        XCTAssertGreaterThan(tiny.count, 1, "极小 budget → 多块")
        for tile in tiny {
            compared += 1
            XCTAssertGreaterThanOrEqual(tile.width, 0)
            XCTAssertGreaterThanOrEqual(tile.height, 0)
        }
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - 四消费者预演（纯 TilingPlan 级，占位常量）

    /// 注入 nlmeans（halo=P+K、80B/px）、denoiseprofile 波列
    /// （halo=2^max_scale≤128、(3.5+max_scale)×16 B/px 上界）、monochrome 3D
    /// grid（halo≈2σ_s、16+摊销 B/px——值待 05-05 定，占位常量）、bilateral
    /// （halo=rad、32 B/px）四组 seam 值 → TilingPlan 网格 sane（tile 数、
    /// halo 不重叠越界、100MP FULL 网格预算 <3GB/tile）。
    /// 占位值与真实声明的替换责任：05-05/06/07/08 各 plan。
    func testFourConsumerGridPreview() {
        struct Consumer {
            var name: String
            var halo: Int
            var bytesPerPixel: Int
        }
        // nlmeans：P=2, K=7 → halo 9；5.0×16 = 80 B/px（RESEARCH §3.3）。
        // denoiseprofile 波列：max_scale=3 → halo 8；(3.5+3)×16 = 104 B/px。
        // monochrome grid：σ_s=20 → halo 40（占位）；16 + 摊销 8 = 24 B/px（占位）。
        // bilateral：rad=6 → halo 6（占位）；直连 32 B/px。
        let consumers: [Consumer] = [
            Consumer(name: "nlmeans", halo: 9, bytesPerPixel: 80),
            Consumer(name: "denoiseprofile-wavelets", halo: 8, bytesPerPixel: 104),
            Consumer(name: "monochrome-grid", halo: 40, bytesPerPixel: 24),
            Consumer(name: "bilateral", halo: 6, bytesPerPixel: 32),
        ]
        let fullW = 11648, fullH = 8736 // 100MP FULL
        let budget = 512 << 20 // pipe 默认 tile budget
        var compared = 0
        for c in consumers {
            let tiles = TilingPlan.tiles(
                forWidth: fullW, height: fullH, maxTileBytes: budget,
                bytesPerPixel: c.bytesPerPixel, overlap: c.halo)
            compared += 1
            XCTAssertGreaterThan(tiles.count, 0, "\(c.name): 非空 grid")
            // 每 tile 预算：tile 面积 × B/px < 3GB（FULL 网格预算门）。
            var maxTileBytes = 0
            for tile in tiles {
                compared += 1
                maxTileBytes = max(maxTileBytes, tile.width * tile.height * c.bytesPerPixel)
                // halo 不致 tile 反转（宽/高 > 0——内缩写合法）。
                XCTAssertGreaterThan(tile.width, 0, "\(c.name): tile 宽合法")
                XCTAssertGreaterThan(tile.height, 0, "\(c.name): tile 高合法")
            }
            XCTAssertLessThan(
                Double(maxTileBytes), 3.0e9, "\(c.name): tile 预算 <3GB（实际 \(maxTileBytes)）")
            print("\(c.name): tiles=\(tiles.count) maxTileBytes=\(maxTileBytes) halo=\(c.halo)")
        }
        XCTAssertGreaterThan(compared, 0)
    }
}
