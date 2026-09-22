@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// IOPieceIscaleTests (Plan 05-01-T2) — `IOPiece.iscale` 协议增量 +
/// pipe stamp + tile 不变性的常驻断言。
///
/// 语义（dt `piece->iscale`，`pixelpipe_hb.c:505` 同构）：iscale = 本 run
/// 的 ENTRY 缩放（scale-at-entry，与 dscIn 同源同一次性写入）；run 级常量
/// （每 piece 同值）；tile 驱动不得改写。denoise 半径补偿消费
/// `roi.scale ÷ iscale`（soften.c:141 先行同式），本 plan 只供标量。
///
/// 防空转：全部断言读真实 pipe 执行的记录值 + `compared > 0`。
final class IOPieceIscaleTests: XCTestCase {

    /// 记录各模块收到的 piece.iscale + roi.scale 的探针（file-local，
    /// ROINegotiationTests.HaloStub 同模式：identity 前向 + 记录）。
    private final class IscaleProbe: IOPModule {
        struct Params: Codable, Hashable {
            var tag: String = ""
        }
        static var opName: String { "iscale_probe" }
        static var iopOrder: Float { 50.5 }
        static var flags: IOPFlags { [] }
        static var defaultColorspace: IOPColorspace { .RGB }
        let tag: String
        let recorder: IscaleRecorder
        init(tag: String, recorder: IscaleRecorder) {
            self.tag = tag
            self.recorder = recorder
        }
        func reloadDefaults(image: DecodedImage) async -> Params { Params(tag: tag) }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            roi = input
        }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            input = roi
        }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            await recorder.record(
                tag: tag, iscale: piece.iscale,
                roiInScale: roiIn.scale, roiOutScale: roiOut.scale,
                pipeType: piece.pipeType)
            guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw AppError.decodeFailed("IscaleProbe blit: no command buffer")
            }
            blit.copy(
                from: input, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(
                    x: roiOut.x - roiIn.x, y: roiOut.y - roiIn.y, z: 0),
                sourceSize: MTLSize(width: roiOut.width, height: roiOut.height, depth: 1),
                to: output, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding() // L008
            commandBuffer.commit()
        }
    }

    private actor IscaleRecorder {
        struct Entry: Sendable {
            var tag: String
            var iscale: Float
            var roiInScale: Float
            var roiOutScale: Float
            var pipeType: PipeResolution
        }
        private(set) var entries: [Entry] = []
        func record(
            tag: String, iscale: Float, roiInScale: Float, roiOutScale: Float,
            pipeType: PipeResolution
        ) {
            entries.append(Entry(
                tag: tag, iscale: iscale,
                roiInScale: roiInScale, roiOutScale: roiOutScale,
                pipeType: pipeType))
        }
    }

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func testImage(width: Int = 128, height: Int = 96) -> DecodedImage {
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    /// PREVIEW（longEdge 48 → scale 0.375）/ FULL（scale 1.0）/ THUMBNAIL
    /// （默认 360 → 128×96 原生小于 360 → scale 1.0）三档：probe 收到的
    /// piece.iscale == 各档 entry 缩放 == roi.scale。
    func testThreeTiersStampEntryScale() async throws {
        let metal = try await makeMetal()
        struct Tier {
            var resolution: PipeResolution
            var longEdge: Int?
            var wantScale: Float
            var label: String
        }
        let tiers: [Tier] = [
            Tier(resolution: .preview, longEdge: 48, wantScale: 48.0 / 128.0, label: "PREVIEW@48"),
            Tier(resolution: .full, longEdge: nil, wantScale: 1.0, label: "FULL"),
            Tier(resolution: .thumbnail, longEdge: nil, wantScale: 1.0, label: "THUMBNAIL原生小图"),
        ]
        var compared = 0
        for tier in tiers {
            let recorder = IscaleRecorder()
            let probe = ModuleBox(
                module: IscaleProbe(tag: "p", recorder: recorder),
                multiPriority: 0, multiName: "p")
            probe.setParams(IscaleProbe.Params(tag: "p"))
            _ = try await RenderPipeline.process(
                image: testImage(), instances: [probe], imageID: UUID(),
                resolution: tier.resolution, cache: PipeCache(), metal: metal,
                longEdge: tier.longEdge)
            let entries = await recorder.entries
            XCTAssertEqual(entries.count, 1, "\(tier.label): probe 执行一次")
            for e in entries {
                compared += 1
                XCTAssertEqual(e.iscale, tier.wantScale, accuracy: 1e-6, "\(tier.label): iscale")
                XCTAssertEqual(e.roiInScale, tier.wantScale, accuracy: 1e-6, "\(tier.label): roiIn.scale")
                XCTAssertEqual(e.roiOutScale, tier.wantScale, accuracy: 1e-6, "\(tier.label): roiOut.scale")
            }
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// 既有全 1.0 路径（合成小图 @longEdge nil → PREVIEW 无缩放）：
    /// iscale == 1 恒等，不扰动。
    func testUnscaledPreviewStampsOne() async throws {
        let metal = try await makeMetal()
        let recorder = IscaleRecorder()
        let probe = ModuleBox(
            module: IscaleProbe(tag: "p", recorder: recorder),
            multiPriority: 0, multiName: "p")
        probe.setParams(IscaleProbe.Params(tag: "p"))
        _ = try await RenderPipeline.process(
            image: testImage(width: 64, height: 64), instances: [probe], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let entries = await recorder.entries
        XCTAssertEqual(entries.count, 1)
        var compared = 0
        for e in entries {
            compared += 1
            XCTAssertEqual(e.iscale, 1.0, accuracy: 1e-6, "iscale == 1 恒等")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// run 级常量：三探针同 run 收到的 iscale 全等（与 dscIn 同源一次性）。
    func testIscaleConstantAcrossPiecesInOneRun() async throws {
        let metal = try await makeMetal()
        let recorder = IscaleRecorder()
        var boxes: [any ModuleBoxing] = []
        for tag in ["a", "b", "c"] {
            let probe = ModuleBox(
                module: IscaleProbe(tag: tag, recorder: recorder),
                multiPriority: 0, multiName: tag)
            probe.setParams(IscaleProbe.Params(tag: tag))
            boxes.append(probe)
        }
        _ = try await RenderPipeline.process(
            image: testImage(), instances: boxes, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 48)
        let entries = await recorder.entries
        XCTAssertEqual(entries.count, 3)
        var compared = 0
        let first = try XCTUnwrap(entries.first).iscale
        for e in entries {
            compared += 1
            XCTAssertEqual(e.iscale, first, accuracy: 1e-9, "\(e.tag) 与首 piece 同值")
            XCTAssertEqual(e.iscale, 48.0 / 128.0, accuracy: 1e-6, "\(e.tag) == entry 缩放")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// tile 不变性：toneequal FULL 强制分块下，tile 内执行读到的
    /// piece.iscale 仍 == 整幅值（tile 驱动不得改写）。toneequal 的
    /// tileHalo 读 piece.data（Derived）——直接在 tileExecution 的 piece
    /// 上断言：用 IscaleProbe 串在 toneequal 下游，强制分块后 probe 的
    /// iscale 仍为 1.0（FULL entry 缩放）。
    func testForcedTilingPreservesIscale() async throws {
        let metal = try await makeMetal()
        let recorder = IscaleRecorder()
        let toneequal = ModuleBox(module: ToneEqualModule())
        toneequal.setParams(ToneEqualModule.Params())
        let probe = ModuleBox(
            module: IscaleProbe(tag: "p", recorder: recorder),
            multiPriority: 0, multiName: "p")
        probe.setParams(IscaleProbe.Params(tag: "p"))
        let image = testImage(width: 256, height: 256)
        _ = try await RenderPipeline.process(
            image: image, instances: [toneequal, probe], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal, longEdge: nil,
            maxTileWorkingBytes: 4096)
        let entries = await recorder.entries
        XCTAssertEqual(entries.count, 1, "下游 probe 执行一次")
        var compared = 0
        for e in entries {
            compared += 1
            XCTAssertEqual(e.iscale, 1.0, accuracy: 1e-9, "FULL tile 下 iscale 仍 == 整幅值")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// 05-06 pipeType stamp（dt `piece->pipe->type` 镜像）：三档 probe
    /// 收到的 piece.pipeType == 各 run 的 resolution——nlmeans 预览降载
    /// （K clamp + decimate）的挂点。防空转：compared>0。
    func testThreeTiersStampPipeType() async throws {
        let metal = try await makeMetal()
        struct Tier {
            var resolution: PipeResolution
            var longEdge: Int?
            var label: String
        }
        let tiers: [Tier] = [
            Tier(resolution: .preview, longEdge: 48, label: "PREVIEW@48"),
            Tier(resolution: .full, longEdge: nil, label: "FULL"),
            Tier(resolution: .thumbnail, longEdge: nil, label: "THUMBNAIL"),
        ]
        var compared = 0
        for tier in tiers {
            let recorder = IscaleRecorder()
            let probe = ModuleBox(
                module: IscaleProbe(tag: "p", recorder: recorder),
                multiPriority: 0, multiName: "p")
            probe.setParams(IscaleProbe.Params(tag: "p"))
            _ = try await RenderPipeline.process(
                image: testImage(), instances: [probe], imageID: UUID(),
                resolution: tier.resolution, cache: PipeCache(), metal: metal,
                longEdge: tier.longEdge)
            let entries = await recorder.entries
            XCTAssertEqual(entries.count, 1, "\(tier.label): probe 执行一次")
            for e in entries {
                compared += 1
                XCTAssertEqual(e.pipeType, tier.resolution, "\(tier.label): pipeType stamp")
            }
        }
        XCTAssertGreaterThan(compared, 0)
    }
}
