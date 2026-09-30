@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// GradeEnvelopePerfProbeTests (Plan M2-5-3 T6, OQ-11 observation ②) — the
// ENV-GATED export-cost probe behind `LIGHTAMER_PERF_PROBE=1` (skipped in
// the default suite: this class measures GIGAPIXEL-scale work, it is an
// observation record, not a regression gate — KD-6 "超带才立项"):
//
// The same synthetic 100MP frame runs the FULL pipe composite twice —
// 0 grade layers vs 4 grade layers (one exposure instance each, the
// ACEScc envelope riders) — the script proxy for "FULL 100MP 导出时间
// 往返开/关对比 ±5%" (an export = this pipe leg + a constant encode, so
// the delta attributes the grade+envelope cost; method note per KD-6:
// 含/不含两栈对比归因，非 A/B 开关). Zero product code touched for
// measurement. Run manually:
//   LIGHTAMER_PERF_PROBE=1 Scripts/test-direct.sh 'GradeEnvelopePerfProbeTests'
final class GradeEnvelopePerfProbeTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ACESccKernel.metalBundle)
        return metal
    }

    /// 10000×10000 = 100MP (the FULL bucket; pattern-filled row-wise so
    /// construction stays memcpy-shaped — content is irrelevant to the
    /// timing question).
    private func make100MP() throws -> DecodedImage {
        let width = 10_000, height = 10_000
        var pixels = [Float](repeating: 0, count: width * 4 * height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for x in 0..<width {
                let o = x * 4
                buffer[o + 0] = 0.1 + 0.7 * Float(x) / Float(width - 1)
                buffer[o + 1] = 0.2
                buffer[o + 2] = 0.3
                buffer[o + 3] = 1.0
            }
            let rowBytes = width * 4 * MemoryLayout<Float>.stride
            for y in 1..<height {
                memcpy(
                    buffer.baseAddress! + y * width * 4,
                    buffer.baseAddress!, rowBytes)
            }
        }
        let bitmap = pixels.withUnsafeBytes { Data($0) }
        let ci = CIImage(
            bitmapData: bitmap,
            bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: WorkingSpace.colorSpace)
        return DecodedImage(
            ciImage: ci,
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    private func makeBase(registry: ModuleRegistry) async -> [any ModuleBoxing] {
        var chain = await makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3)
        chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        return chain
    }

    private func stackWithGradeLayers(_ count: Int, ev: Float) -> LayerStack {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        for index in 0..<count {
            let record = ModuleInstance(
                module: ExposureModule.self,
                params: ExposureModule.Params(exposure: ev))
            stack.addAdjustment(
                AdjustmentLayer(name: "Grade\(index)", opacity: 1.0, chain: [record]))
        }
        return stack
    }

    private func timedComposite(
        image: DecodedImage, base: [any ModuleBoxing], stack: LayerStack,
        registry: ModuleRegistry, metal: MetalContext, runs: Int
    ) async throws -> [Double] {
        var timings: [Double] = []
        for _ in 0..<runs {
            let cache = PipeCache()  // cold layer per run (the export shape)
            let start = DispatchTime.now()
            let result = try await LayerCompositeDriver.composite(
                image: image, imageID: UUID(), baseInstances: base,
                layerStack: stack, registry: registry, resolution: .full,
                cache: cache, metal: metal, longEdge: nil, roiHint: nil,
                policy: .fullColdLayer)
            // L014: the composite commits async GPU work — fence before
            // reading the clock or the blit-heavy shapes time at ~0.
            let fence = metal.commandQueue.makeCommandBuffer()
            fence?.commit()
            await fence?.completed()
            _ = result
            let end = DispatchTime.now()
            timings.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
        }
        return timings.sorted()
    }

    func testFullPipe100MPGradeLayerCostProbe() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "manual probe — set LIGHTAMER_PERF_PROBE=1 (OQ-11 observation ②)")
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let base = await makeBase(registry: registry)
        let image = try make100MP()

        // Warm one pass per shape (JIT/PSO/allocations settle), then 3
        // timed runs each; the median is the record.
        _ = try await timedComposite(
            image: image, base: base, stack: stackWithGradeLayers(0, ev: 0),
            registry: registry, metal: metal, runs: 1)
        _ = try await timedComposite(
            image: image, base: base, stack: stackWithGradeLayers(4, ev: 0.3),
            registry: registry, metal: metal, runs: 1)

        let without = try await timedComposite(
            image: image, base: base, stack: stackWithGradeLayers(0, ev: 0),
            registry: registry, metal: metal, runs: 3)
        let with = try await timedComposite(
            image: image, base: base, stack: stackWithGradeLayers(4, ev: 0.3),
            registry: registry, metal: metal, runs: 3)

        let baseline = without[without.count / 2]
        let graded = with[with.count / 2]
        let delta = graded - baseline
        let ratio = baseline > 0 ? delta / baseline * 100 : 0
        print(
            "PERF-PROBE|100MP|FULL|base=\(String(format: "%.1f", baseline))ms|" +
                "4grade=\(String(format: "%.1f", graded))ms|" +
                "delta=\(String(format: "%.1f", delta))ms|" +
                "delta=\(String(format: "%.1f", ratio))%")
        // Record-only: no gate (KD-6). The assertion merely pins the shape
        // (grade layers add work; the ±5% band judgment belongs to the
        // SUMMARY observation section).
        XCTAssertGreaterThan(graded, 0)
    }
}
