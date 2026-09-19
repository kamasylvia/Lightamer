@testable import LightamerCore
import CoreGraphics
import Metal
@testable import LightamerIOP
import XCTest

// ToneEqualPerfTests (Plan 03-05-T7) — the PERF-5 PRE-VERIFICATION (the
// formal CI record lands in plan 03-06-T7): the FULL PREVIEW chain with
// every tone iop enabled (colorin + the 8 editing-seed iops INCLUDING
// toneequal) re-rendered per frame (a params tick per frame — the drag
// shape; every frame is a full-chain miss) at the D-C3 PREVIEW bucket.
//
// Budget (RESEARCH §8): toneequal 3-6ms + the rest 2-6ms + margin ⇒
// median frame < 16.6ms. A miss records the numbers and the plan's
// "超限先记录后优化" note applies (03-06 owns the formal gate).
final class ToneEqualPerfTests: XCTestCase {

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

    /// 2048×1536 synthetic (native ≤ the 2560 PREVIEW bucket ⇒ scale 1).
    private func makeSynthetic() throws -> DecodedImage {
        let width = 2048, height = 1536
        var data = Data(capacity: width * height * 16)
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(exp2(-6.0 + 5.0 * Double(x) / Double(width - 1)))
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

    func testPreviewFullChainFrameTime() async throws {
        let metal = try await makeMetal()
        let image = try makeSynthetic()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)

        // The editing seed (8 iops: temperature/exposure/sigmoid/colisa/
        // tonecurve/levels/shadhi/toneequal) + colorin.
        let maybeColorin = await registry.makeBox(opName: ColorInModule.opName)
        var chain: [any ModuleBoxing] = [try XCTUnwrap(maybeColorin)]
        for record in LightamerIOPRegistry.editingDefaultInstances() {
            let maybeBox = await registry.makeBox(opName: record.opName, instanceID: record.id)
            let box = try XCTUnwrap(maybeBox)
            try await box.apply(record)
            chain.append(box)
        }

        let cache = PipeCache()
        var timings: [Double] = []
        for frame in 0..<8 {
            // A tick per frame (the drag shape): nudge exposure so every
            // frame is a full-chain cache miss.
            if let exposureBox = chain.first(where: { $0.opName == "exposure" })
                as? ModuleBox<ExposureModule> {
                await exposureBox.setParams(.init(exposure: Float(frame) * 0.001))
            }
            let clock = ContinuousClock()
            let start = clock.now
            _ = try await RenderPipeline.process(
                image: image, instances: chain, imageID: UUID(),
                resolution: .preview, cache: cache, metal: metal,
                longEdge: 2560
            )
            drain(metal)
            let elapsed = clock.now - start
            timings.append(Double(elapsed.components.attoseconds) / 1e18 * 1000.0)
        }

        let sorted = timings.sorted()
        let median = sorted[sorted.count / 2]
        let warmup = Array(sorted.dropFirst(2))
        let warmMedian = warmup[warmup.count / 2]
        print("PREVIEW full-chain frame ms: \(timings.map { String(format: "%.1f", $0) }.joined(separator: ", ")) — median \(String(format: "%.2f", median)), warm median \(String(format: "%.2f", warmMedian))")
        // MEASURED (2026-09-19, M4, DEBUG -Onone build): 44-75ms warm per
        // full-chain frame — OVER the 16.6ms budget. Per the plan this is
        // RECORDED, not gated: the Debug-build kernel + per-dispatch
        // overhead dominates (10 modules x per-encoder commit; elementwise
        // bandwidth alone is ~15ms at this size), the formal PERF-5 gate
        // lands in 03-06-T7, and the optimization levers (Release
        // builds, PSO prewarm, per-module dispatch batching) are 03-06
        // work items. The bound here only guards against pathological
        // regression.
        XCTAssertLessThan(warmMedian, 120.0, "PREVIEW full-chain warm median (pathological-regression bound; measured Debug numbers recorded for 03-06's formal PERF-5 gate)")
    }
}
