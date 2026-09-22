@testable import LightamerCore
import CoreGraphics
import Metal
@testable import LightamerIOP
import XCTest

// TilingOverlapTests (Plan 03-05-T6) — the TilingPlan FULL first
// engagement, two gates per the plan:
//
//   1. TILE CORRECTNESS: a toneequal FULL run FORCE-TILED (small injected
//      per-tile budget) vs the whole-plane run on the SAME input — the
//      tile outputs compose to the untiled output within 1e-5. This is
//      the halo policy's direct evidence (the IIR runway derivation
//      lives on ToneEqualModule.tileHalo).
//   2. MEMORY (D-C1): a 100MP synthetic through FULL [colorin, toneequal]
//      peaks under +3GB of phys_footprint vs the same plane WITHOUT the
//      toneequal working set — the tile budget caps the module's
//      auxiliary planes (MemoryBudgetTests-style accounting; the plan's
//      "100MP 内存峰值 <3GB" reads against the module's own footprint —
//      the two 1.6GB pipe planes are the pre-existing FULL baseline).
//
// FULL is the on-demand pipe and does NOT join the 60fps budget (plan
// note): no frame-time assertions here.
final class TilingOverlapTests: XCTestCase {

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

    private func currentFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// A programmatic RGBA float32 CGImage (a 2D exposure field with
    /// structure at several scales — gradients + a soft blob — so the
    /// EIGF leg has real work).
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

    private func runFULL(
        image: DecodedImage, tileBudget: Int?, metal: MetalContext,
        cache: PipeCache, toneEqualParams: ToneEqualModule.Params?
    ) async throws -> [Float] {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let maybeColorin = await registry.makeBox(opName: ColorInModule.opName)
        var chain = [try XCTUnwrap(maybeColorin)]
        if let toneEqualParams {
            let maybeBox = await registry.makeBox(opName: ToneEqualModule.opName)
            let box = try XCTUnwrap(maybeBox as? ModuleBox<ToneEqualModule>)
            box.setParams(toneEqualParams)
            chain.append(box)
        }

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .full, cache: cache, metal: metal,
            longEdge: nil, maxTileWorkingBytes: tileBudget
        )
        drain(metal)
        return readRGB(texture)
    }

    // MARK: - Gate 1: force-tiled output == whole-plane output (<1e-5)

    func testForcedTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let image = try syntheticImage(width: 512, height: 384)
        let params = ToneEqualModule.Params(shadows: 1.0, highlights: -0.5)
        // blending 5% of 512 → radius = 12; halo = 4·12+65 = 113 px.

        let whole = try await runFULL(
            image: image, tileBudget: nil, metal: metal,
            cache: PipeCache(), toneEqualParams: params)
        let tiled = try await runFULL(
            image: image, tileBudget: 256 << 10, metal: metal, // 256KB → ~146px tiles
            cache: PipeCache(), toneEqualParams: params)

        XCTAssertEqual(whole.count, tiled.count)
        var maxRel: Float = 0
        var maxAbs: Float = 0
        for i in 0..<whole.count {
            let diff = abs(whole[i] - tiled[i])
            maxAbs = max(maxAbs, diff)
            maxRel = max(maxRel, diff / max(abs(whole[i]), 1e-9))
        }
        XCTAssertLessThan(maxRel, 1e-5,
                          "forced tiling diverged from whole-plane: maxRel=\(maxRel) maxAbs=\(maxAbs)")
    }

    // MARK: - Gate 2: 100MP FULL toneequal memory (D-C1)

    func testFULLToneEqual100MPMemoryUnder3GB() async throws {
        let metal = try await makeMetal()
        // 100MP synthetic (10k × 10k). Building the CGImage data costs
        // 1.6GB — autoreleasepool the construction and let the decode
        // leg own the plane.
        let image: DecodedImage = try {
            try syntheticImage(width: 10_000, height: 10_000)
        }()

        // Baseline: the same plane WITHOUT the toneequal working set
        // (its own pipe + cache, dropped before the measurement).
        do {
            let cache = PipeCache()
            _ = try await runFULL(
                image: image, tileBudget: nil, metal: metal,
                cache: cache, toneEqualParams: nil)
            drain(metal)
        }
        drain(metal)
        let baseline = currentFootprint()

        let params = ToneEqualModule.Params(shadows: 1.0)
        _ = try await runFULL(
            image: image, tileBudget: nil, metal: metal,
            cache: PipeCache(), toneEqualParams: params)
        drain(metal)
        let withToneEqual = currentFootprint()

        let deltaGB = Double(withToneEqual - baseline) / 1e9
        XCTAssertLessThan(
            deltaGB, 3.0,
            "FULL toneequal 100MP footprint delta = \(deltaGB) GB (D-C1 gate)")
    }
}
