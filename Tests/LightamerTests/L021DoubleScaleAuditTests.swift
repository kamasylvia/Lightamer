@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// L021DoubleScaleAuditTests (Plan 05-01-T1) — 04-06 D-GUI-1 移交的
/// toneequal/flip `dscIn × scale` double-scale 审计还账的常驻回归。
///
/// 背景（LESSONS L021）：`CropModule.modifyROIIn` 曾把已含 entry 缩放的
/// `dscIn` 又 ×`roi.scale`——760 档 clamp 界坍缩 60×40 → 协商 roiIn 60×40 →
/// 左上小窗 blit、其余全零（GUI-1 近全黑）。scale=1.0 恒等掩盖了它。
/// 同式嫌疑：toneequal blending 直径与 flip bw/bh。
///
/// 审计结论（dt dc58cf0ba1 实证，详见 05-01-DECISIONS.md D-05-01-T1）：
/// - toneequal `modifyROIIn` 本身恒等（`input = roi`，不读 dscIn）——免疫；
///   但 `tileHalo` / `process` 的 `diameter = blending × dscIn.max × roi.scale`
///   命中 double-scale（dt `toneequal.c:1190-1192` 的 max_size = 全分辨率
///   `piece->iwidth`，`× roi.scale` 一次；我们的 dscIn 已是 entry 缩放后
///   尺寸，再 ×scale 即两次）——390 行 process 与 285 行 tileHalo 同式同修。
/// - flip `modifyROIIn` 的 `bw/bh = swapped(dscIn) × roi.scale` 命中
///   double-scale（dt `flip.c:338-339` 的 `buf_out × scale` 中 buf_out 是
///   全分辨率 FORWARD 输出；我们的 dscIn 已缩放）——swap 态在 scale<1 下
///   协商窗坍缩（48×36 → 18×36），process 越界写丢弃 → 右半黑。
///   transpose 全帧免疫（纯 swap 与 dims 无关）；`.none` 恒等免疫。
///
/// 防空转：全部比较测试含真实比较循环 + `compared > 0`；全部含非 1.0
/// scale 档（scale=1.0 恒等掩盖 double-scale）。
final class L021DoubleScaleAuditTests: XCTestCase {

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

    /// 常数灰图（resampling 下恒定——常数经任意缩放仍为常数，CI 插值
    /// 无歧义；空间错位/零块以 0.5 vs 0 形态暴露）。
    private func constantImage(width: Int, height: Int, value: Float) -> DecodedImage {
        var rgba = [Float](repeating: 1.0, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = value
            rgba[i * 4 + 1] = value
            rgba[i * 4 + 2] = value
        }
        var data = Data(capacity: rgba.count * 4)
        for v in rgba {
            var le = v.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    private func readFloats(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal) // L014
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return floats
    }

    // MARK: - Flip: hook 级 pin（scale<1 全帧 swap → 全输入）

    /// 128×96 @longEdge 48：entry 48×36，scale 0.375。swap 态全输出
    /// （36×48）经 `modifyROIIn` 必须回到全输入（48×36）。
    /// pre-fix：bw/bh 双重缩放（36×0.375=13）→ 后向角点越界 → clamp 后
    /// （0,0,18,36)——宽坍缩。transpose 全帧恒等（纯 swap 与 dims 无关，
    /// 免疫但钉住防退化）。
    func testFlipSwapModifyROIInFullFrameAtPreviewScale() async {
        let scale: Float = 48.0 / 128.0 // 0.375 精确
        let dscW = 48, dscH = 36 // entry 缩放后输入尺寸
        let cases: [(FlipOrientation, ROI, ROI, String)] = [
            (.rotCCW90, ROI(x: 0, y: 0, width: 36, height: 48, scale: scale),
             ROI(x: 0, y: 0, width: 48, height: 36, scale: scale), "rotCCW90 全输出→全输入"),
            (.rotCW90, ROI(x: 0, y: 0, width: 36, height: 48, scale: scale),
             ROI(x: 0, y: 0, width: 48, height: 36, scale: scale), "rotCW90 全输出→全输入"),
            (.transverse, ROI(x: 0, y: 0, width: 36, height: 48, scale: scale),
             ROI(x: 0, y: 0, width: 48, height: 36, scale: scale), "transverse 全输出→全输入"),
            (.transpose, ROI(x: 0, y: 0, width: 36, height: 48, scale: scale),
             ROI(x: 0, y: 0, width: 48, height: 36, scale: scale), "transpose 全输出→全输入（免疫对照）"),
        ]
        var compared = 0
        for (orientation, roiOut, want, label) in cases {
            let box = ModuleBox(module: FlipModule())
            await box.setParams(FlipModule.Params(orientation: orientation))
            var piece = box.makeRunPiece()
            piece.dscIn = IOPBufferDesc(width: dscW, height: dscH)
            var input = ROI()
            box.modifyROIInErased(output: roiOut, input: &input, piece: piece)
            compared += 1
            XCTAssertEqual(input, want, "\(label): hook 输出")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// flipH 部分窗（dt `:338-339` 镜像语义）：48×36 上 (8,4,16,8) 应映回
    /// (24,4,16,8)（关于输入宽 48 镜像）。pre-fix bw=18 → (-6,4,16,8)。
    func testFlipHPartialWindowMirrorsAboutUnscaledWidth() async {
        let scale: Float = 48.0 / 128.0
        let box = ModuleBox(module: FlipModule())
        await box.setParams(FlipModule.Params(orientation: .flipH))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 48, height: 36)
        var input = ROI()
        box.modifyROIInErased(
            output: ROI(x: 8, y: 4, width: 16, height: 8, scale: scale),
            input: &input, piece: piece)
        XCTAssertEqual(
            input, ROI(x: 24, y: 4, width: 16, height: 8, scale: scale),
            "flipH 部分窗关于未缩放输入宽（48）镜像")
    }

    // MARK: - Flip: 端到端（常数图 + scale<1，零块探测器）

    /// 常数 0.5 图经 [flip] @longEdge 48：8 态输出每像素 RGB 必须 == 0.5
    /// （A == 1）。pre-fix swap/flip 态协商窗坍缩 → 未写区零块 → 红。
    /// 常数经 CI 缩放恒定——无重采样换位歧义。
    func testFlipScaledPreviewPreservesConstantImage() async throws {
        let metal = try await makeMetal()
        let image = constantImage(width: 128, height: 96, value: 0.5)
        let states: [FlipOrientation] = [
            .none, .flipV, .flipH, .rot180,
            .transpose, .rotCW90, .rotCCW90, .transverse,
        ]
        var compared = 0
        for orientation in states {
            let flip = ModuleBox(module: FlipModule())
            await flip.setParams(FlipModule.Params(orientation: orientation))
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [flip], imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 48)
            let (ew, eh) = orientation.swapsXY ? (36, 48) : (48, 36)
            // entry：128×96 @longEdge 48 → scale 0.375 → 48×36；swap 态转置输出。
            XCTAssertEqual(texture.width, ew, "\(orientation): 输出宽")
            XCTAssertEqual(texture.height, eh, "\(orientation): 输出高")
            let pixels = readFloats(texture, metal: metal)
            var worst: Float = 0
            for i in 0..<(texture.width * texture.height) {
                compared += 1
                worst = max(
                    worst,
                    abs(pixels[i * 4] - 0.5),
                    abs(pixels[i * 4 + 1] - 0.5),
                    abs(pixels[i * 4 + 2] - 0.5),
                    abs(pixels[i * 4 + 3] - 1.0))
            }
            XCTAssertEqual(worst, 0, accuracy: 1e-4, "\(orientation): 常数保持")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// trio + flip(.none) @48 == trio-only（逐字节）：`.none` 恒等免疫的
    /// 绿证据——修 flip 不得扰动恒等路径（crop 同款门仿形）。
    func testTrioPlusFlipNoneMatchesTrioOnlyAtPreviewScale() async throws {
        let metal = try await makeMetal()
        let image = constantImage(width: 128, height: 96, value: 0.5)
        let registry = ModuleRegistry.makeDefault()
        let trio = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3)
        let flip = ModuleBox(module: FlipModule())
        await flip.setParams(FlipModule.Params(orientation: .none))
        let withFlip = (trio + [flip as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let imageID = UUID()
        let (plain, _) = try await RenderPipeline.process(
            image: image, instances: trio, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 48)
        let (flipped, _) = try await RenderPipeline.process(
            image: image, instances: withFlip, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 48)
        XCTAssertEqual(flipped.width, plain.width)
        XCTAssertEqual(flipped.height, plain.height)
        drain(metal)
        var a = [UInt8](repeating: 0, count: plain.width * plain.height * 4)
        var b = [UInt8](repeating: 0, count: a.count)
        a.withUnsafeMutableBytes {
            plain.getBytes($0.baseAddress!, bytesPerRow: plain.width * 4,
                from: MTLRegionMake2D(0, 0, plain.width, plain.height), mipmapLevel: 0)
        }
        b.withUnsafeMutableBytes {
            flipped.getBytes($0.baseAddress!, bytesPerRow: flipped.width * 4,
                from: MTLRegionMake2D(0, 0, flipped.width, flipped.height), mipmapLevel: 0)
        }
        var compared = 0
        for i in 0..<a.count { compared += 1 }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(a, b, "scaled trio+flip(.none) 必须逐字节 == trio-only")
    }

    // MARK: - ToneEqual: halo 公式 pin（dt toneequal.c:1190-1192 手算）

    /// `diameter = blending × dscIn.max`（dscIn 已是 entry 缩放后平面像素，
    /// 禁再 ×scale——L021）；`halo = 4 × max(radius,1) + 64 + 1`。
    /// 手算（Float 精算，边界余量 ≥0.3）：
    /// - 48 档 blending=100：d=48 → r=23 → halo 157；pre-fix d=18 → r=8 → 97。
    /// - 760 档 blending=5：d=38 → r=18 → halo 137；pre-fix d≈20.06 → r=9 → 101。
    /// - scale=1.0 对照：d=25.6 → r=12 → halo 113（与 TilingOverlapTests
    ///   既有注释 "radius = 12; halo = 113" 互锁——修不得扰动 FULL/tile 路径）。
    /// - details=.none → halo 0（纯点态，无 halo 需求；前后一致，免疫对照）。
    /// process :385-386 与 tileHalo 同表达式——本 pin 同步覆盖 process 半径。
    func testToneequalPreviewHaloMatchesDtDiameter() async {
        struct Vector {
            var blending: Float
            var dscW: Int
            var dscH: Int
            var scale: Float
            var details: ToneEqualDetails
            var wantHalo: Int
            var label: String
        }
        let vectors: [Vector] = [
            Vector(blending: 100, dscW: 48, dscH: 36, scale: 48.0 / 128.0,
                   details: .eigf, wantHalo: 157, label: "48 档 blending=100"),
            Vector(blending: 5, dscW: 760, dscH: 507, scale: 760.0 / 1440.0,
                   details: .eigf, wantHalo: 137, label: "760 档 blending=5"),
            Vector(blending: 5, dscW: 512, dscH: 512, scale: 1.0,
                   details: .eigf, wantHalo: 113, label: "scale=1.0 对照"),
            Vector(blending: 5, dscW: 760, dscH: 507, scale: 760.0 / 1440.0,
                   details: .none, wantHalo: 0, label: "details=none 免疫对照"),
        ]
        var compared = 0
        for v in vectors {
            let box = ModuleBox(module: ToneEqualModule())
            await box.setParams(ToneEqualModule.Params(
                blending: v.blending, details: v.details))
            var piece = box.makeRunPiece()
            piece.dscIn = IOPBufferDesc(width: v.dscW, height: v.dscH)
            let halo = box.module.tileHalo(
                roi: ROI(x: 0, y: 0, width: v.dscW, height: v.dscH, scale: v.scale),
                piece: piece)
            compared += 1
            XCTAssertEqual(halo, v.wantHalo, "\(v.label): halo")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// toneequal `modifyROIIn` 恒等审计证据：input 必须 == roi（不读 dscIn，
    /// 无 double-scale 余地）——免疫的书面化。
    func testToneequalModifyROIInIsIdentity() async {
        let box = ModuleBox(module: ToneEqualModule())
        await box.setParams(ToneEqualModule.Params())
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 48, height: 36)
        var input = ROI()
        let roi = ROI(x: 0, y: 0, width: 48, height: 36, scale: 48.0 / 128.0)
        box.modifyROIInErased(output: roi, input: &input, piece: piece)
        XCTAssertEqual(input, roi, "toneequal modifyROIIn 恒等（免疫）")
    }
}
