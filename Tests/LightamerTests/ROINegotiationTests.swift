@testable import LightamerCore
import CoreImage
@testable import LightamerIOP
import Metal
import XCTest

/// SC#4 ROI negotiation harness (04-01; D-G5 / ROADMAP SC#4).
///
/// Driver mix (04-05): ①③④ run the REAL `CropModule` (04-02-T1); ② runs
/// BOTH the HaloStub (halo-3 bookkeeping net) AND the REAL `SharpenModule`
/// (04-05-T1 `testSharpenBackwardExpandsUpstream` — the stub retired for
/// the D-G5 main proof; the HaloStub class stays as the CPU-math minimal
/// reference). Stub process = size-exact / content-approximate：经
/// `commandQueue` blit 按 `(roiOut − roiIn)`
/// 偏移拷贝窗口（dt `dt_iop_copy_image_roi` 快路径语义）；halo 类 stub
/// 的采样对齐不是 harness 的断言对象。
///
/// History (04-01 TDD red → green):
/// - ① RED → T3（前向预计算 + 真协商）green；04-02 换真 crop 回归。
/// - ②-e2e GREEN (T4 `roiHint` + 子域渲染)；04-05 换真 sharpen 回归。
/// - ③④ GREEN（回归网：禁用穿越恒等、旧键保留回拖命中）。
/// - ROI.clamped/aabb 辅助单测 GREEN（T2 产物）。
final class ROINegotiationTests: XCTestCase {

    // ── Recording plumbing ──

    /// One process-call sighting: the ROIs the pipe handed the module.
    private struct ROISighting: Sendable {
        let roiIn: ROI
        let roiOut: ROI
    }

    /// Sendable sighting log (bumped inside stub `process`).
    private actor ROIRecorder {
        private var sightings: [String: [ROISighting]] = [:]
        func record(tag: String, roiIn: ROI, roiOut: ROI) {
            sightings[tag, default: []].append(ROISighting(roiIn: roiIn, roiOut: roiOut))
        }
        func sightings(for tag: String) -> [ROISighting] { sightings[tag] ?? [] }
    }

    /// Window copy the stubs share (dt `dt_iop_copy_image_roi` fast-path
    /// semantics): `out[0..<roiOut] = in[(roiOut − roiIn)..<]` via blit.
    /// Pre-negotiation (all-identity ROIs) this is a whole-plane copy.
    private static func roiBlitCopy(
        input: any MTLTexture, output: any MTLTexture,
        roiIn: ROI, roiOut: ROI, metal: MetalContext
    ) async throws {
        guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw AppError.decodeFailed("ROINegotiationTests stub blit: no command buffer")
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: roiOut.x - roiIn.x, y: roiOut.y - roiIn.y, z: 0),
            sourceSize: MTLSize(width: roiOut.width, height: roiOut.height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008
        commandBuffer.commit()
    }

    // ── Stub modules (protocol drivers until 04-02/04-05 land) ──

    /// 50%-capable crop stub (dt `crop.c:517-531` forward minus the export
    /// ratio-aligner, which is Phase 11; `:576-592` backward verbatim).
    /// `final class` so `commitParams` can park params for the ROI hooks
    /// (modifyROIOut/In only receive `piece`, not params).
    private final class CropStub: IOPModule {
        struct Params: Codable, Hashable {
            var cx: Float
            var cy: Float
            var cw: Float
            var ch: Float
        }
        static var opName: String { "crop_roi_stub" }
        static var iopOrder: Float { 24.5 } // the real crop slot
        static var flags: IOPFlags { [] }
        static var defaultColorspace: IOPColorspace { .RGB }
        let tag: String
        let recorder: ROIRecorder
        private var current = Params(cx: 0.25, cy: 0.25, cw: 0.75, ch: 0.75)
        init(tag: String, recorder: ROIRecorder) {
            self.tag = tag
            self.recorder = recorder
        }
        func reloadDefaults(image: DecodedImage) async -> Params { current }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            current = params
            piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            // dt `crop.c:517-531` verbatim (minus the Phase-11 export
            // aligner): `*roi_out = *roi_in`, then RELATIVE offsets —
            // x/y do NOT add the input origin.
            roi = input
            roi.x = max(0, Int(Float(input.width) * current.cx))
            roi.y = max(0, Int(Float(input.height) * current.cy))
            roi.width = max(4, Int(Float(input.width) * (current.cw - current.cx)))
            roi.height = max(4, Int(Float(input.height) * (current.ch - current.cy)))
        }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            // dt `crop.c:576-592` verbatim: `*roi_in = *roi_out` (KEEP the
            // downstream offset — that IS the window position), then add
            // the crop origin and clamp to [0, floor(iw/ih)] (dt CLAMP —
            // upper bound INCLUSIVE: a 64px edge window legitimately
            // addresses x=64 as its far edge).
            input = roi
            let iw = Double(piece.dscIn.width) * Double(roi.scale)
            let ih = Double(piece.dscIn.height) * Double(roi.scale)
            input.x += Int(iw * Double(current.cx))
            input.y += Int(ih * Double(current.cy))
            input.x = min(max(input.x, 0), Int(iw.rounded(.down)))
            input.y = min(max(input.y, 0), Int(ih.rounded(.down)))
            // Window far edge stays inside the frame (dt's process reads
            // `roi_in`-relative rows; the pipe guarantees containment by
            // clamping the SIZE against the upstream plane below).
            input.width = min(input.width, max(1, Int(iw.rounded(.down)) - input.x))
            input.height = min(input.height, max(1, Int(ih.rounded(.down)) - input.y))
        }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            await recorder.record(tag: tag, roiIn: roiIn, roiOut: roiOut)
            try await ROINegotiationTests.roiBlitCopy(
                input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
        }
    }

    /// Sharpen-class halo stub: identity forward, `halo`-pixel backward
    /// expansion (the D-G5 后向扩展语义；`ceil(3σ)` 起步值由 04-05 真模块定，
    /// 此处 halo 直接参数化）。Pipe 负责 clamp 到上游平面。
    private final class HaloStub: IOPModule {
        struct Params: Codable, Hashable {
            var halo: Int
        }
        static var opName: String { "sharpen_roi_stub" }
        static var iopOrder: Float { 35.0 } // the real sharpen slot
        static var flags: IOPFlags { [] }
        static var defaultColorspace: IOPColorspace { .RGB }
        let tag: String
        let recorder: ROIRecorder
        var halo: Int
        init(tag: String, recorder: ROIRecorder, halo: Int = 3) {
            self.tag = tag
            self.recorder = recorder
            self.halo = halo
        }
        func reloadDefaults(image: DecodedImage) async -> Params { Params(halo: halo) }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            halo = params.halo
            piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            roi = input
        }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            input = roi
            input.x -= halo
            input.y -= halo
            input.width += 2 * halo
            input.height += 2 * halo
        }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            await recorder.record(tag: tag, roiIn: roiIn, roiOut: roiOut)
            // minimal content proof (ROI geometry is the pipe's assert).
            guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw AppError.decodeFailed("HaloStub center blit: no command buffer")
            }
            blit.copy(
                from: input, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(
                    x: roiOut.x - roiIn.x + halo,
                    y: roiOut.y - roiIn.y + halo, z: 0),
                sourceSize: MTLSize(width: roiOut.width, height: roiOut.height, depth: 1),
                to: output, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding() // L008
            commandBuffer.commit()
        }
    }

    /// ROI-recording decorator over a pointwise module (proves pointwise
    /// modules receive the negotiated window, not just geometry stubs).
    private final class ROIRecording<Inner: IOPModule>: IOPModule {
        typealias Params = Inner.Params
        static var opName: String { Inner.opName }
        static var iopOrder: Float { Inner.iopOrder }
        static var flags: IOPFlags { Inner.flags }
        static var defaultColorspace: IOPColorspace { Inner.defaultColorspace }
        let tag: String
        let recorder: ROIRecorder
        let inner: Inner
        init(tag: String, recorder: ROIRecorder, inner: Inner) {
            self.tag = tag
            self.recorder = recorder
            self.inner = inner
        }
        func reloadDefaults(image: DecodedImage) async -> Params {
            await inner.reloadDefaults(image: image)
        }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            inner.commitParams(params, into: &piece)
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            inner.modifyROIOut(&roi, input: input, piece: piece)
        }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            inner.modifyROIIn(output: roi, input: &input, piece: piece)
        }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            await recorder.record(tag: tag, roiIn: roiIn, roiOut: roiOut)
            try await inner.process(
                input: input, output: output, roiIn: roiIn, roiOut: roiOut,
                piece: &piece, metal: metal)
        }
    }

    // ── Fixtures ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeImage(width: Int, height: Int) -> DecodedImage {
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: ci,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }
    /// 04-02: the REAL `CropModule` drives ①③④ (stub retired for crop —
    /// `CropStub` stays as the CPU-math reference below). The recorder
    /// wraps it so the harness keeps its ROI sightings.
    private func makeCrop50Chain(
        _ recorder: ROIRecorder, enabled: Bool = true
    ) async -> [any ModuleBoxing] {
        let crop = ModuleBox(
            module: ROIRecording(tag: "crop", recorder: recorder, inner: CropModule()),
            multiPriority: 0, multiName: "crop")
        crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        crop.enabled = enabled
        let gain = ModuleBox(
            module: ROIRecording(tag: "gain", recorder: recorder, inner: TestGainModule()),
            multiPriority: 1, multiName: "gain")
        gain.setParams(TestGainModule.Params(gain: 1.0))
        return [crop, gain]
    }

    // ── ① Crop forward shrink (T3 turns green; T4 tightens accounting) ──

    /// SC#4-①: `[crop50, gain]` run 后终帧 == 32×32 窗口；gain 收到的
    /// roiIn/roiOut == 32×32（相对坐标，标准 dt 管线语义）；crop 收到的
    /// roiIn == (16,16,32,32)——我们的 backward walk 从 forward 结果出发，
    /// xy 已是 modifyROIOut 记录的上游相对窗口原点（dt 的 `+= buf_in·cx`
    /// 再加只适用于其窗口相对 roi_out；双重相加会把窗口推到 [0.75..1] 角，
    /// golden parity 抓现行）。T4 前输入平面仍全幅渲染 —— 记账断言放宽，
    /// T4 后收紧为窗口组（见 T4 任务）。
    func testCropForwardShrinkDownstream() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let recorder = ROIRecorder()
        let image = makeImage(width: 64, height: 64)
        let chain = await makeCrop50Chain(recorder)

        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: nil)
        XCTAssertEqual(stats.misses, 3, "input + crop-out + gain-out, all miss on run1")
        XCTAssertEqual(texture.width, 32, "downstream planes are window-sized")
        XCTAssertEqual(texture.height, 32)

        let gainSights = await recorder.sightings(for: "gain")
        XCTAssertEqual(gainSights.count, 1, "gain processes exactly once")
        XCTAssertEqual(gainSights.first?.roiIn.width, 32, "gain must see the window, not the full frame")
        XCTAssertEqual(gainSights.first?.roiIn.height, 32)
        XCTAssertEqual(gainSights.first?.roiOut.width, 32)
        XCTAssertEqual(gainSights.first?.roiOut.height, 32)

        let cropSights = await recorder.sightings(for: "crop")
        XCTAssertEqual(cropSights.count, 1)
        XCTAssertEqual(cropSights.first?.roiIn, ROI(x: 16, y: 16, width: 32, height: 32, scale: 1.0),
                       "crop input = the window in upstream coords (our walk's frame convention)")
        XCTAssertEqual(cropSights.first?.roiOut, ROI(x: 16, y: 16, width: 32, height: 32, scale: 1.0))
    }

    // ── ② Backward halo expansion e2e (T4 turns green) ──

    /// SC#4-②: `[halo(halo=3), gain]` + `roiHint` 24×24 子窗口 → 终帧
    /// 24×24；halo 收到的 roiOut == 窗口、roiIn == 窗口 + 2·halo（30×30，
    /// ≪ 全图）；gain 收到的 roiIn/roiOut == 窗口；输入平面缓存记账 ==
    /// 30×30 窗口（数值 + 字节双断言）。
    func testHaloBackwardExpandsUpstream() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let recorder = ROIRecorder()
        let image = makeImage(width: 128, height: 128)
        let halo = 3
        // Execution order (sorted by iopOrder): [gain(50.5, upstream) →
        // halo(35.0, downstream)]. The hinted window hits the DOWNSTREAM
        // halo first; ITS expanded roiIn (window + 2·halo) drives the
        // negotiation through gain to the input plane. Gain's own
        // negotiation stays identity (it forwards the expanded window).
        let gain = ModuleBox(
            module: ROIRecording(tag: "gain", recorder: recorder, inner: TestGainModule()),
            multiPriority: 0, multiName: "gain")
        gain.setParams(TestGainModule.Params(gain: 1.0))
        let haloBox = ModuleBox(module: HaloStub(tag: "halo", recorder: recorder),
                                multiPriority: 0, multiName: "halo")
        haloBox.setParams(HaloStub.Params(halo: halo))
        let chain: [any ModuleBoxing] = [gain, haloBox]
        let hint = ROI(x: 40, y: 40, width: 24, height: 24, scale: 1.0)
        let expanded = ROI(x: 37, y: 37, width: 30, height: 30, scale: 1.0)

        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal,
            longEdge: nil, roiHint: hint)
        XCTAssertEqual(stats.misses, 3, "input + gain-out + halo-out at the hinted window")
        XCTAssertEqual(texture.width, 24)
        XCTAssertEqual(texture.height, 24)
        let haloSights = await recorder.sightings(for: "halo")
        XCTAssertEqual(haloSights.count, 1)
        XCTAssertEqual(haloSights.first?.roiOut, hint)
        XCTAssertEqual(
            haloSights.first?.roiIn, expanded,
            "halo input = window + 2·halo, numerically exact")

        // Negotiation-order note (dt `:2085-2096` + cache-probe order):
        // the walk probes TOP-DOWN, so gain's line is keyed on the HINTED
        // window (its negotiation runs before halo's miss expands the
        // region). Gain therefore consumes the window, halo consumes the
        // expansion — each module sees exactly its own negotiated pair.
        let gainSights = await recorder.sightings(for: "gain")
        XCTAssertEqual(gainSights.count, 1)
        XCTAssertEqual(gainSights.first?.roiIn, hint)
        XCTAssertEqual(gainSights.first?.roiOut, hint)

        let expandedBytes = 30 * 30 * WorkingSpace.bytesPerPixel
        let windowBytes = 24 * 24 * WorkingSpace.bytesPerPixel
        let totalAfter = await cache.totalBytes
        XCTAssertEqual(
            totalAfter, expandedBytes + 2 * windowBytes,
            "input plane (expanded) + gain-out (window) + halo-out (window)")
    }
    /// SC#4-②真模块版（04-05-T1 acceptance：stub → 真 sharpen 回归）：
    /// `[sharpen(r=2.0,a=0.5), gain]` + `roiHint` 24×24 → 终帧 24×24；
    /// sharpen roiIn == 窗口 + 2·ceil(3σ)=36×36（σ=2.0，halo=6，≪全图）；
    /// 上游平面（输入 + gain）记账 == 36×36 扩展窗口。HaloStub 版（上）
    /// 保留为 halo 语义的最小记账网。
    func testSharpenBackwardExpandsUpstream() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let recorder = ROIRecorder()
        let image = makeImage(width: 128, height: 128)
        let halo = SharpenModule.halo(radius: 2.0, scale: 1.0)
        XCTAssertEqual(halo, 6, "ceil(3·2.0) = 6 — the D-G5 constant")
        let gain = ModuleBox(
            module: ROIRecording(tag: "gain", recorder: recorder, inner: TestGainModule()),
            multiPriority: 0, multiName: "gain")
        gain.setParams(TestGainModule.Params(gain: 1.0))
        let sharpenBox = ModuleBox(
            module: ROIRecording(tag: "sharpen", recorder: recorder, inner: SharpenModule()),
            multiPriority: 0, multiName: "sharpen")
        sharpenBox.setParams(SharpenModule.Params(radius: 2.0, amount: 0.5, threshold: 0.5))
        let chain: [any ModuleBoxing] = [gain, sharpenBox]
        let hint = ROI(x: 40, y: 40, width: 24, height: 24, scale: 1.0)
        let expanded = ROI(x: 34, y: 34, width: 36, height: 36, scale: 1.0)

        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal,
            longEdge: nil, roiHint: hint)
        XCTAssertEqual(stats.misses, 3, "input + gain-out + sharpen-out at the hinted window")
        XCTAssertEqual(texture.width, 24)
        XCTAssertEqual(texture.height, 24)
        let sharpenSights = await recorder.sightings(for: "sharpen")
        XCTAssertEqual(sharpenSights.count, 1)
        XCTAssertEqual(sharpenSights.first?.roiOut, hint)
        XCTAssertEqual(
            sharpenSights.first?.roiIn, expanded,
            "sharpen input = window + 2·ceil(3σ), numerically exact (< 全图)")

        let gainSights = await recorder.sightings(for: "gain")
        XCTAssertEqual(gainSights.count, 1)
        XCTAssertEqual(gainSights.first?.roiIn, hint)
        XCTAssertEqual(gainSights.first?.roiOut, hint)

        let expandedBytes = 36 * 36 * WorkingSpace.bytesPerPixel
        let windowBytes = 24 * 24 * WorkingSpace.bytesPerPixel
        let totalAfter = await cache.totalBytes
        XCTAssertEqual(
            totalAfter, expandedBytes + 2 * windowBytes,
            "input plane (expanded) + gain-out (window) + sharpen-out (window)")
    }

    /// HaloStub 自身 `modifyROIIn` 数学（CPU，不经 pipe）：窗口外扩 halo。
    func testHaloStubExpandsInputByHalo() {
        let box = ModuleBox(module: HaloStub(tag: "h", recorder: ROIRecorder()))
        var input = ROI()
        box.modifyROIInErased(
            output: ROI(x: 20, y: 20, width: 24, height: 24, scale: 1.0),
            input: &input, piece: IOPiece())
        XCTAssertEqual(input, ROI(x: 17, y: 17, width: 30, height: 30, scale: 1.0))
    }

    /// CropStub 自身 `modifyROIOut` 数学（CPU）：50% 中心窗口 + min-4px。
    func testCropStubShrinksOutputToWindow() async {
        let box = ModuleBox(module: CropStub(tag: "c", recorder: ROIRecorder()))
        box.setParams(CropStub.Params(cx: 0.25, cy: 0.25, cw: 0.75, ch: 0.75))
        var out = ROI()
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0),
            piece: box.makeRunPiece())
        XCTAssertEqual(out, ROI(x: 16, y: 16, width: 32, height: 32, scale: 1.0))
    }

    // ── ashift warp AABB (04-03-T2: output grows, input stays bounded) ──

    /// SC#4 ROI 回归（ashift 30° 用例，plan 验收标准）：输出 AABB 变大
    /// （前向 64×64 → 87×87），输入 AABB 有界（clamp 到 bufIn 内）。
    /// 内容正确性由 AshiftParityTests 的 golden track A 兜底 — 此处只钉
    /// 协商记账（L020：记账绿 ≠ 内容对，但记账仍是缓存正确性的门）。
    func testAshiftWarpAABBGrowsOutputAndBoundsInput() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let recorder = ROIRecorder()
        let image = makeImage(width: 64, height: 64)
        let ashift = ModuleBox(
            module: ROIRecording(tag: "ashift", recorder: recorder, inner: AshiftModule()),
            multiPriority: 0, multiName: "ashift")
        ashift.setParams(AshiftModule.Params(rotation: 30))
        let gain = ModuleBox(
            module: ROIRecording(tag: "gain", recorder: recorder, inner: TestGainModule()),
            multiPriority: 1, multiName: "gain")
        gain.setParams(TestGainModule.Params(gain: 1.0))
        let chain: [any ModuleBoxing] = [ashift, gain]

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: nil)
        XCTAssertEqual(texture.width, 87, "rot30 forward AABB grows the frame")
        XCTAssertEqual(texture.height, 87)

        let ashiftSights = await recorder.sightings(for: "ashift")
        XCTAssertEqual(ashiftSights.count, 1)
        XCTAssertEqual(ashiftSights.first?.roiOut.width, 87)
        // 输入 AABB：逆变换 + 边距后 clamp 到 64 帧内。
        let roiIn = ashiftSights.first?.roiIn
        XCTAssertNotNil(roiIn)
        XCTAssertLessThanOrEqual((roiIn?.x ?? 0) + (roiIn?.width ?? 0), 64 + 1)
        XCTAssertLessThanOrEqual((roiIn?.y ?? 0) + (roiIn?.height ?? 0), 64 + 1)

        let gainSights = await recorder.sightings(for: "gain")
        XCTAssertEqual(gainSights.count, 1, "downstream sees the grown frame")
        XCTAssertEqual(gainSights.first?.roiOut.width, 87)
    }

    /// SC#4 ROI 回归（lens pincushion(dc2=−0.08)64×64，plan 验收标准）：
    /// modifyROIOut 恒等（输出 == 输入帧）；modifyROIIn 收缩为
    /// (0,0,63,63)——从 CLAMPED 原点起算的宽度（dt `:1791-1799` 字面；
    /// 旧式子从未 clamp 的 xm 起算会丢 2.56px，输入平面缺 tap 列，
    /// kernel 在 x0 处冻结——track-A golden 抓现行）。
    /// 内容正确性由 LensParityTests 兜底 — 此处只钉协商记账。
    func testLensShrinkNegotiationBoundsInput() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let recorder = ROIRecorder()
        let image = makeImage(width: 64, height: 64)
        let lens = ModuleBox(
            module: ROIRecording(tag: "lens", recorder: recorder, inner: LensModule()),
            multiPriority: 0, multiName: "lens")
        lens.setParams(LensModule.Params(distortionK1: -0.08, source: .manual))
        let gain = ModuleBox(
            module: ROIRecording(tag: "gain", recorder: recorder, inner: TestGainModule()),
            multiPriority: 1, multiName: "gain")
        gain.setParams(TestGainModule.Params(gain: 1.0))
        let chain: [any ModuleBoxing] = [lens, gain]

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: nil)
        XCTAssertEqual(texture.width, 64, "lens never resizes the frame")
        XCTAssertEqual(texture.height, 64)

        let lensSights = await recorder.sightings(for: "lens")
        XCTAssertEqual(lensSights.count, 1)
        XCTAssertEqual(lensSights.first?.roiOut, ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0))
        XCTAssertEqual(
            lensSights.first?.roiIn, ROI(x: 0, y: 0, width: 62, height: 62, scale: 1.0),
            "pincushion forward AABB [2.56..61.44] + 2px margin from the clamped origin, "
                + "intersected with the 64-frame by the pipe clamp")
    }

    /// T2 辅助 `clamped(to:)`：交集 + 空交集兜底 1×1。
    func testROIClampedToBounds() {
        let bounds = ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0)
        XCTAssertEqual(
            ROI(x: 17, y: 17, width: 30, height: 30, scale: 1.0).clamped(to: bounds),
            ROI(x: 17, y: 17, width: 30, height: 30, scale: 1.0))
        XCTAssertEqual(
            ROI(x: -5, y: -5, width: 20, height: 20, scale: 1.0).clamped(to: bounds),
            ROI(x: 0, y: 0, width: 15, height: 15, scale: 1.0))
        let empty = ROI(x: 100, y: 100, width: 4, height: 4, scale: 1.0).clamped(to: bounds)
        XCTAssertGreaterThanOrEqual(empty.width, 1)
        XCTAssertGreaterThanOrEqual(empty.height, 1)
    }

    /// T2 辅助 `aabb(of:)`：角点集 → floor/ceil 包围盒。
    func testROIAABBOfCorners() {
        let box = ROI.aabb(of: [(x: 1.2, y: 2.7), (x: 10.8, y: 3.1), (x: 9.5, y: 12.4)], scale: 1.0)
        XCTAssertEqual(box, ROI(x: 1, y: 2, width: 10, height: 11, scale: 1.0))
    }

    // ── ③ Disabled crop passes through (GREEN net) ──

    /// SC#4-③: crop disabled → 全链 roi 恒等（dt `_skip_piece_on_tags`
    /// 直通回归；T3 前向必须跳过 disabled 件——本用例前后皆绿）。
    func testDisabledCropPassesThrough() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let recorder = ROIRecorder()
        let image = makeImage(width: 64, height: 64)
        let chain = await makeCrop50Chain(recorder, enabled: false)

        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: nil)
        XCTAssertEqual(texture.width, 64)
        XCTAssertEqual(texture.height, 64)
        XCTAssertEqual(stats.misses, 2, "input + gain only; the disabled slot contributes no key step")
        let gainSights = await recorder.sightings(for: "gain")
        XCTAssertEqual(gainSights.count, 1)
        XCTAssertEqual(gainSights.first?.roiIn, ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0))
        let cropSights = await recorder.sightings(for: "crop")
        XCTAssertEqual(cropSights.count, 0, "disabled piece must not process")
    }

    // ── ④ Drag keeps old keys (GREEN net) ──

    /// SC#4-④: 拖动 crop rect（A→B→A）→ 每次新窗口做功、记账增长、
    /// 回拖旧窗口零功耗命中（旧键保留；D-C3 精神）。
    func testCropDragKeepsOldKeys() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let recorder = ROIRecorder()
        let image = makeImage(width: 64, height: 64)
        let imageID = UUID()
        let crop = ModuleBox(
            module: ROIRecording(tag: "crop", recorder: recorder, inner: CropModule()),
            multiPriority: 0, multiName: "crop")
        let gain = ModuleBox(
            module: ROIRecording(tag: "gain", recorder: recorder, inner: TestGainModule()),
            multiPriority: 1, multiName: "gain")
        gain.setParams(TestGainModule.Params(gain: 1.0))
        let chain: [any ModuleBoxing] = [crop, gain]
        func run() async throws -> RenderPipeline.PipeRunStats {
            try await RenderPipeline.process(
                image: image, instances: chain, imageID: imageID,
                resolution: .preview, cache: cache, metal: metal, longEdge: nil).1
        }
        crop.setParams(CropModule.Params(left: 0, top: 0, right: 0.5, bottom: 0.5))
        let statsA = try await run()
        XCTAssertEqual(statsA.misses, 3)
        let bytesA = await cache.totalBytes

        crop.setParams(CropModule.Params(left: 0.5, top: 0.5, right: 1.0, bottom: 1.0))
        let statsB = try await run()
        XCTAssertGreaterThanOrEqual(statsB.misses, 2, "new window = new keys downstream")
        let bytesAfterB = await cache.totalBytes
        XCTAssertGreaterThan(bytesAfterB, bytesA, "both key groups retained")

        crop.setParams(CropModule.Params(left: 0, top: 0, right: 0.5, bottom: 0.5))
        let bytesBeforeRevert = await cache.totalBytes
        let statsBack = try await run()
        XCTAssertEqual(statsBack.hits, 1, "back-drag hits the retained line, zero work")
        XCTAssertEqual(statsBack.misses, 0)
        XCTAssertEqual(statsBack.planesRendered, 0)
        let bytesAfterRevert = await cache.totalBytes
        XCTAssertEqual(bytesAfterRevert, bytesBeforeRevert, "revert builds nothing")
    }
}
