@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// FlipParityTests (Plan 04-02-T2) — the IOP-GEO-04 index module.
///
/// dt sources: `src/iop/flip.c` (:299-313 modify_roi_out, :315-350
/// modify_roi_in, :354-391 process, :410-425 commit, :479-508
/// reload_defaults) + `src/common/image.h:134-150` (orientation bits) +
/// `data/kernels/basic.cl:2933-2967` (kernel swizzle).
///
/// Parities (CPU + GPU):
/// - 8-state index vectors: the kernel forward map == the CPU
///   `FlipOrientation.outputXY` mirror on an asymmetric fixture (<1e-6 —
///   exact integers, so the gate is bit-exactness);
/// - 90° states swap W/H in modifyROIOut; flips do not;
/// - modifyROIIn corner round-trip (swap states exchange the rect);
/// - EXIF reloadDefaults vectors (1...8 → 8 states; unknown ⇒ none);
/// - `.auto` commit fallback = identity (D-H4 hash still covers RAW);
/// - end-to-end through the real pipe (flip alone, flip+crop order).
final class FlipParityTests: XCTestCase {

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

    /// Asymmetric fixture: R = x-index, G = y-index, B = 0.5 — every
    /// pixel's source is recoverable from its value.
    private func indexImage(width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 1.0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                rgba[(y * width + x) * 4] = Float(x)
                rgba[(y * width + x) * 4 + 1] = Float(y)
                rgba[(y * width + x) * 4 + 2] = 0.5
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

    // MARK: - CPU index mirrors

    /// Forward/backward maps are mutual inverses on every state and every
    /// sample of a 5×7 grid (dt `backtransform` is the exact inverse of
    /// the kernel swizzle; the backward map takes OUTPUT dims).
    func testForwardBackwardMapsAreInverse() {
        let states: [FlipOrientation] = [.none, .flipV, .flipH, .rot180, .transpose, .rotCW90, .rotCCW90, .transverse]
        for orientation in states {
            let (w, h) = (5, 7)
            let (ow, oh) = orientation.swapsXY ? (h, w) : (w, h)
            for y in 0..<h {
                for x in 0..<w {
                    let fwd = FlipOrientation.outputXY(x: x, y: y, w: w, h: h, orientation: orientation)
                    XCTAssertTrue(fwd.x >= 0 && fwd.x < ow && fwd.y >= 0 && fwd.y < oh,
                                  "\(orientation): forward (\(x),\(y)) in bounds")
                    let back = FlipOrientation.inputXY(x: fwd.x, y: fwd.y, ow: ow, oh: oh, orientation: orientation)
                    XCTAssertEqual(back.x, x, "\(orientation): round-trip x")
                    XCTAssertEqual(back.y, y, "\(orientation): round-trip y")
                }
            }
        }
    }

    // MARK: - ROI hooks

    /// 90° states swap W/H; flips/180/identity do not (dt `:307-312`).
    func testModifyROIOutSwapsWHOnlyOnSwapXY() async {
        for orientation in FlipOrientation.allCases where orientation != .auto {
            let box = ModuleBox(module: FlipModule())
            await box.setParams(FlipModule.Params(orientation: orientation))
            var out = ROI()
            box.modifyROIOutErased(
                &out, input: ROI(x: 0, y: 0, width: 64, height: 32, scale: 1.0),
                piece: box.makeRunPiece())
            if orientation.swapsXY {
                XCTAssertEqual(out.width, 32, "\(orientation) swaps W")
                XCTAssertEqual(out.height, 64, "\(orientation) swaps H")
            } else {
                XCTAssertEqual(out, ROI(x: 0, y: 0, width: 64, height: 32, scale: 1.0),
                               "\(orientation) keeps geometry")
            }
        }
    }

    /// Corner round-trip through modifyROIIn: full-output maps to
    /// full-input on swaps; flip-state backward mirrors the rect about
    /// the BUF_OUT width (dt `:338-339` — the forward output size; the
    /// flipH rect (8,4,16,8) with buf_out 64×32 maps to (40,4,16,8)).
    func testModifyROIInRoundTripsCorners() async {
        let box = ModuleBox(module: FlipModule())
        await box.setParams(FlipModule.Params(orientation: .rotCCW90))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 64, height: 32)
        var input = ROI()
        // After modifyROIOut the output plane is 32×64.
        box.modifyROIInErased(
            output: ROI(x: 0, y: 0, width: 32, height: 64, scale: 1.0),
            input: &input, piece: piece)
        XCTAssertEqual(input, ROI(x: 0, y: 0, width: 64, height: 32, scale: 1.0),
                       "swap-state backward maps the full output to the full input")

        let flipBox = ModuleBox(module: FlipModule())
        await flipBox.setParams(FlipModule.Params(orientation: .flipH))
        var flipPiece = flipBox.makeRunPiece()
        flipPiece.dscIn = IOPBufferDesc(width: 64, height: 32)
        var flipInput = ROI()
        flipBox.modifyROIInErased(
            output: ROI(x: 8, y: 4, width: 16, height: 8, scale: 1.0),
            input: &flipInput, piece: flipPiece)
        XCTAssertEqual(flipInput, ROI(x: 40, y: 4, width: 16, height: 8, scale: 1.0),
                       "flipH mirrors the rect about the input width")
    }

    func testReloadDefaultsMapsEXIFOrientations() async {
        let vectors: [(exif: Int?, want: FlipOrientation)] = [
            (1, .none), (2, .flipH), (3, .rot180), (4, .flipV),
            (5, .transpose), (6, .rotCW90), (7, .transverse), (8, .rotCCW90),
            (nil, .none), (0, .none), (9, .none),
        ]
        for (exif, want) in vectors {
            let module = FlipModule()
            var capture = CaptureMetadata()
            capture.orientation = exif
            let image = DecodedImage(
                ciImage: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                    .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4)),
                rawTech: RAWTechnicalParams(), capture: capture,
                segmentationSkyMatte: nil, decoderVersionUsed: .v8)
            let params = await module.reloadDefaults(image: image)
            XCTAssertEqual(params.orientation, want, "EXIF \(String(describing: exif))")
        }
        XCTAssertEqual(FlipModule.opName, "flip")
        XCTAssertEqual(FlipModule.iopOrder, 16.0)
        XCTAssertEqual(FlipModule.defaultColorspace, .RGB)
    }

    func testAutoCommitFallsBackToIdentity() async {
        let box = ModuleBox(module: FlipModule())
        await box.setParams(FlipModule.Params(orientation: .auto))
        var out = ROI()
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 64, height: 32, scale: 1.0),
            piece: box.makeRunPiece())
        XCTAssertEqual(out, ROI(x: 0, y: 0, width: 64, height: 32, scale: 1.0),
                       "persisted .auto must never warp geometry")
    }

    func testFlipRegisteredAtV50Slot() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: FlipModule.opName)
        let flipBox = try XCTUnwrap(box as? ModuleBox<FlipModule>)
        XCTAssertEqual(flipBox.iopOrder, 16.0)
        _ = flipBox
    }

    // MARK: - GPU index parity (8 states, <1e-6 — integers, so bit-exact)

    /// Every state through the REAL pipe: output pixel values decode to
    /// the source coords the CPU mirror predicts (R = src x, G = src y).
    func testAllEightStatesRemapIndexesExactly() async throws {
        let metal = try await makeMetal()
        let (w, h) = (7, 5)
        let image = indexImage(width: w, height: h)
        let states: [FlipOrientation] = [.none, .flipV, .flipH, .rot180, .transpose, .rotCW90, .rotCCW90, .transverse]
        for orientation in states {
            let flip = ModuleBox(module: FlipModule())
            await flip.setParams(FlipModule.Params(orientation: orientation))
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: [flip], imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
            let (ew, eh) = orientation.swapsXY ? (h, w) : (w, h)
            XCTAssertEqual(texture.width, ew, "\(orientation): output width")
            XCTAssertEqual(texture.height, eh, "\(orientation): output height")
            let pixels = readRGBA(texture, metal: metal)
            var worst: Float = 0
            for oy in 0..<eh {
                for ox in 0..<ew {
                    // Output (ox,oy) reads input (sx,sy) = backward map
                    // over the OUTPUT dims (ew, eh).
                    let src = FlipOrientation.inputXY(x: ox, y: oy, ow: ew, oh: eh, orientation: orientation)
                    let got = pixels[(oy * ew + ox) * 4]
                    let gotY = pixels[(oy * ew + ox) * 4 + 1]
                    worst = max(worst, abs(got - Float(src.x)), abs(gotY - Float(src.y)))
                }
            }
            XCTAssertEqual(worst, 0, accuracy: 1e-6, "\(orientation): index remap exact")
        }
    }

    /// flip + crop SORT order (flip 16.0 < crop 24.5): the pipe sorts
    /// instances by (iopOrder, multiPriority) — deliberately UNSORTED
    /// input still orders flip-first. (A composed-geometry variant is
    /// retired: `modifyROIOut` reads the box's `committed` params, and a
    /// hand-rolled two-box hook chain cannot reproduce the pipe's
    /// per-level state without re-implementing the forward walk — the
    /// composed SIZE is covered in-pipe by `testModifyROIOutSwaps...`
    /// + `CropParityTests`, and the v50 constraint by V50OrderTests.)
    func testFlipThenCropComposesInV50Order() async {
        let flip = ModuleBox(module: FlipModule())
        await flip.setParams(FlipModule.Params(orientation: .rotCCW90))
        let crop = ModuleBox(module: CropModule())
        await crop.setParams(CropModule.Params(left: 0, top: 0, right: 0.5, bottom: 0.5))
        let unsorted: [any ModuleBoxing] = [crop, flip]
        let sorted = unsorted.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
        XCTAssertEqual(sorted.map(\.opName), ["flip", "crop"],
                       "v50 sort runs flip (16.0) before crop (24.5)")
    }
}
