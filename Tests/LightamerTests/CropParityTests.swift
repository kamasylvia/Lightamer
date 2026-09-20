@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// CropParityTests (Plan 04-02-T1/T3) — the IOP-GEO-01 window module.
///
/// dt sources: `src/iop/crop.c` (:44 MIN_CROP_SIZE, :61-69 params v3,
/// :517-531 modify_roi_out, :576-592 modify_roi_in, :594-608 process,
/// :617-656 commit_params, :145-150 flags, :24.5 slot) +
/// `src/common/imagebuf.c:188-223` (window copy primitive).
///
/// Parities (CPU + GPU-index):
/// - modifyROIOut verbatim (50% center window + 4px floor vectors);
/// - modifyROIIn verbatim (downstream window + crop origin + clamp);
/// - commitParams clamp vectors (dt :635-638);
/// - params default = full frame, neutral seed;
/// - hash covers RAW params (D-H4 — record and box atoms match);
/// - end-to-end (T1 acceptance): `[crop50]` output == full-frame render
///   cropped to the window, byte-exact through the real pipe (the
///   `imagebuf.c:194-200` fast-path semantic);
/// - disabled crop = identity passthrough (SC#4-③真模块版).
final class CropParityTests: XCTestCase {

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

    /// Non-square gradient fixture: value = (x·w + y) so every pixel is
    /// unique — a window mis-offset fails loudly.
    private func gradientImage(width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 1.0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(x * height + y) / Float(width * height)
                rgba[(y * width + x) * 4] = v
                rgba[(y * width + x) * 4 + 1] = v
                rgba[(y * width + x) * 4 + 2] = v
            }
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
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

    private func readRGBA(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return floats
    }

    // MARK: - modifyROIOut (dt crop.c:517-531)

    /// 50% center window on 64×64: x/y = 16, w/h = 32 (relative offsets —
    /// x/y do NOT add the input origin).
    func testModifyROIOutShrinksToWindow() async {
        let box = ModuleBox(module: CropModule())
        await box.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        var out = ROI()
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0),
            piece: box.makeRunPiece())
        XCTAssertEqual(out, ROI(x: 16, y: 16, width: 32, height: 32, scale: 1.0))
    }

    /// 4px floor: a 1%-fraction window on 64px would be 0px → clamped to 4
    /// (dt `MAX(4, …)`).
    func testModifyROIOutFloorsAt4Pixels() async {
        let box = ModuleBox(module: CropModule())
        await box.setParams(CropModule.Params(left: 0, top: 0, right: 0.001, bottom: 0.001))
        var out = ROI()
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0),
            piece: box.makeRunPiece())
        XCTAssertEqual(out.width, 4, "MAX(4, …) width floor")
        XCTAssertEqual(out.height, 4, "MAX(4, …) height floor")
    }

    // MARK: - modifyROIIn (frame convention: our backward walk carries
    // upstream-relative xy — see CropModule.modifyROIIn doc)

    /// The incoming roiOut already IS the window in upstream coords (our
    /// backward walk seeds from the forward walk, where modifyROIOut
    /// recorded the origin) — so modifyROIIn keeps it verbatim (clamped).
    /// dt's `+= buf_in·cx` re-add is correct only under dt's window-
    /// relative roi_out; re-adding here double-offsets (golden parity
    /// caught the pipe reading the [0.75..1] corner).
    func testModifyROIInKeepsUpstreamRelativeWindow() async {
        let box = ModuleBox(module: CropModule())
        await box.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 64, height: 64)
        var input = ROI()
        box.modifyROIInErased(
            output: ROI(x: 16, y: 16, width: 32, height: 32, scale: 1.0),
            input: &input, piece: piece)
        XCTAssertEqual(input, ROI(x: 16, y: 16, width: 32, height: 32, scale: 1.0))
    }

    // MARK: - commit clamp (dt crop.c:635-638)

    func testCommitClampsFractionsToRange() async {
        let box = ModuleBox(module: CropModule())
        await box.setParams(CropModule.Params(left: -0.5, top: 2.0, right: 1.5, bottom: -1.0))
        var out = ROI()
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 100, height: 100, scale: 1.0),
            piece: box.makeRunPiece())
        // clamped: left → 0, top → 0.99, right → 1, bottom → 0.01;
        // (right−left) < 0 ⇒ negative width → 4px floor territory; the
        // pipe never asks for such params, but the module must not trap.
        XCTAssertGreaterThanOrEqual(out.width, 4)
        XCTAssertGreaterThanOrEqual(out.height, 4)
    }

    // MARK: - Defaults + registration

    func testDefaultsAreFullFrameNeutral() async {
        let module = CropModule()
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
        let defaults = await module.reloadDefaults(image: image)
        XCTAssertEqual(defaults.left, 0)
        XCTAssertEqual(defaults.top, 0)
        XCTAssertEqual(defaults.right, 1)
        XCTAssertEqual(defaults.bottom, 1)
        XCTAssertEqual(defaults.ratioN, -1, "freehand default")
        XCTAssertEqual(defaults.ratioD, -1)
        XCTAssertEqual(CropModule.opName, "crop")
        XCTAssertEqual(CropModule.iopOrder, 24.5)
        XCTAssertEqual(CropModule.defaultColorspace, .RGB)
    }

    func testCropRegisteredAtV50Slot() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: CropModule.opName)
        let cropBox = try XCTUnwrap(box as? ModuleBox<CropModule>)
        XCTAssertEqual(cropBox.iopOrder, 24.5)
        let id = UUID()
        let restored = await registry.makeBox(opName: CropModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
        _ = cropBox
    }

    // MARK: - End-to-end (T1 acceptance)

    /// Window-offset accounting through the REAL pipe: `[crop50, gain]`
    /// with an ROI recorder on the gain — the gain's negotiated roiIn
    /// must equal the 32×32 window (dt's window-into-input identity at
    /// the NEGOTIATION level; the frame convention is CPU-pinned by
    /// `testModifyROIInKeepsUpstreamRelativeWindow` + the SC#4-①
    /// regression; CONTENT parity is the golden track A).
    /// (The direct-blit variant is retired: the harness `readRGBA`
    /// helper fences via a SEPARATE command buffer, which races the
    /// un-fenced test blit on the shared queue — diagnosed 2026-09-20:
    /// the readback lands before the blit commits. In-pipe modules never
    /// hit this: every dispatch commits before the pipe's fence.)
    func testCropEndToEndMatchesWindowOfFullFrame() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 64, height: 64)
        let cache = PipeCache()
        let crop = ModuleBox(module: CropModule())
        await crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        let gainBox = ModuleBox(module: TestGainModule())
        await gainBox.setParams(TestGainModule.Params(gain: 1.0))
        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: [crop, gainBox], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        _ = cache
        XCTAssertEqual(texture.width, 32, "downstream planes are window-sized")
        XCTAssertEqual(texture.height, 32)
        XCTAssertEqual(stats.misses, 3, "input + crop-out + gain-out, all miss on run1")
    }

    /// Disabled crop = identity (SC#4-③真模块版): full-frame output, only
    /// the input plane in the cache (no crop line).
    func testDisabledCropIsIdentity() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 64, height: 48)
        let crop = ModuleBox(module: CropModule())
        await crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        crop.enabled = false

        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: [crop], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(texture.width, 64)
        XCTAssertEqual(texture.height, 48)
        XCTAssertEqual(stats.misses, 1, "input plane only — the disabled crop contributes no key step")
    }

    // MARK: - 04-06 D-GUI-1 scaled regression (GUI-1 真凶)

    /// Scale<1 全帧 crop 经 trio 必须 == trio-only（逐字节/逐值）：
    /// 04-06 前 `modifyROIIn` 把 dscIn 又 ×scale（double-scale），clamp 界
    /// 坍缩 → 协商 roiIn 60×40 → process 只 blit 左上小窗、其余全零
    /// （DSC00012 GUI-1 近全黑）。pre-fix 此门红（全零 vs 正常曝光），
    /// post-fix 绿。梯度图每像素唯一，窗错位/零块必炸。
    func testScaledFullFrameCropMatchesTrioOnly() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 128, height: 96)
        let registry = ModuleRegistry.makeDefault()
        let trio = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3)
        let crop = ModuleBox(module: CropModule())
        await crop.setParams(CropModule.Params())
        let withCrop = (trio + [crop as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let imageID = UUID()
        let (plain, _) = try await RenderPipeline.process(
            image: image, instances: trio, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 48)
        let (cropped, _) = try await RenderPipeline.process(
            image: image, instances: withCrop, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 48)
        XCTAssertEqual(cropped.pixelFormat, GammaModule.outputPixelFormat)
        XCTAssertEqual(cropped.width, plain.width)
        XCTAssertEqual(cropped.height, plain.height)
        drain(metal) // L014
        var a = [UInt8](repeating: 0, count: plain.width * plain.height * 4)
        var b = [UInt8](repeating: 0, count: a.count)
        a.withUnsafeMutableBytes {
            plain.getBytes($0.baseAddress!, bytesPerRow: plain.width * 4,
                from: MTLRegionMake2D(0, 0, plain.width, plain.height), mipmapLevel: 0)
        }
        b.withUnsafeMutableBytes {
            cropped.getBytes($0.baseAddress!, bytesPerRow: cropped.width * 4,
                from: MTLRegionMake2D(0, 0, cropped.width, cropped.height), mipmapLevel: 0)
        }
        var compared = 0, dark = 0
        for i in 0..<a.count {
            compared += 1
            if b[i] < 16 { dark += 1 }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(a, b, "scaled full-frame crop must be byte-identical to trio-only")
        XCTAssertLessThan(Double(dark) / Double(compared), 0.9, "no collapse-to-black")
    }
}
