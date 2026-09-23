@testable import LightamerCore
import CoreGraphics
import Metal
@testable import LightamerIOP
import XCTest

/// Plan 06-05 T5 — the LAYER-dimension performance records (05-08 PERF-5
/// 口径: measured numbers + honest gates, no silent放宽):
///
/// 1. **10-layer steady-state drag gate** (the SC drag criterion's layer
///    dimension): 10 ENABLED adjustment layers (each a TestGain record —
///    the cheap-kernel steady state), a params tick on layer K per frame
///    → the incremental composite (K's chain re-run + K..N prefix blends,
///    <K chains all-hit). Median recorded into `.work/06/perf.md`; the
///    60fps verdict lands in 06-05-DECISIONS (Debug numbers are the
///    recorded evidence — the Release regression bound is the only gate).
/// 2. **FULL policy benchmark** (D-06-CONTEXT-8's data-driven fallback
///    point): fit view (NO window) N-layer full-frame re-render under
///    `fullColdLayer` vs `fullCacheAll`, plus the windowed (roiHint)
///    scene — the numbers decide cold-layer vs cache-all; sanity
///    assertions only (this is a benchmark, not a gate).
final class LayerDragPerfTests: XCTestCase {

    private var isReleaseBuild: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

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

    /// 2048×1536 synthetic (native ≤ the 2560 PREVIEW bucket ⇒ scale 1 —
    /// the same frame shape as PERF-5's PreviewChainPerfTests).
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

    /// 10 enabled adjustment layers, each one TestGain record (cheap
    /// kernel — the steady state isolates the COMPOSITE cost, not the
    /// module cost; PERF-5 already owns the heavy-chain number).
    private func makeTenLayerStack() -> LayerStack {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        for index in 0..<10 {
            let layer = AdjustmentLayer(
                name: "L\(index)", opacity: 1.0,
                chain: [ModuleInstance(
                    module: TestGainModule.self,
                    params: TestGainModule.Params(gain: 1.0 + Float(index) * 0.01))])
            stack.addAdjustment(layer)
        }
        return stack
    }

    /// THE 10-layer steady-state drag gate: tick layer K=4's gain per
    /// frame → K's chain re-run + K..N prefix re-blends; layers <K and
    /// >K chain outputs all-hit (the 06-1 incremental semantics).
    func testTenLayerSteadyStateDrag() async throws {
        let metal = try await makeMetal()
        let image = try makeSynthetic()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        let stack = makeTenLayerStack()
        let editedID = try XCTUnwrap(stack.compositeLayers[4].id)

        await metal.prewarmPipelineStates(
            functionNames: LightamerIOPRegistry.prewarmFunctionNames)

        let imageID = UUID()
        let cache = PipeCache()
        var gain = 1.5
        func tickFrame() async throws -> LayerCompositeResult {
            if let layer = stack.compositeLayers.first(where: { $0.id == editedID }),
               let box = layer.chain.first {
                var record = box
                let params = try record.params(of: TestGainModule.self)
                var next = params
                next.gain = Float(gain)
                gain += 0.001
                try record.setParams(next, as: TestGainModule.self)
                layer.chain = [record]
            }
            return try await LayerCompositeDriver.composite(
                image: image, imageID: imageID, baseInstances: base,
                layerStack: stack, registry: registry, resolution: .preview,
                cache: cache, metal: metal, longEdge: 2560, policy: .preview,
                hotLayerID: editedID)
        }

        // Warm-up (PSOs + the cold composite so the steady state is what
        // the frames measure).
        for _ in 0..<4 { _ = try await tickFrame() }
        drain(metal)

        var timings: [Double] = []
        for _ in 0..<12 {
            let result = try await tickFrame()
            drain(metal)
            XCTAssertGreaterThan(result.layerStats.count, 0, "防空转: layers composited")
        }
        // The tick loop above re-ran the composite; measure a fresh batch
        // (the previous loop's timings were discarded — keep it simple:
        // measure here).
        timings.removeAll()
        for _ in 0..<12 {
            let clock = ContinuousClock()
            let start = clock.now
            _ = try await tickFrame()
            drain(metal)
            let elapsed = clock.now - start
            timings.append(Double(elapsed.components.attoseconds) / 1e18 * 1000.0)
        }

        let sorted = timings.sorted()
        let median = sorted[sorted.count / 2]
        let warm = Array(sorted.dropFirst(2))
        let warmMedian = warm[warm.count / 2]
        print("PERF6 10-layer steady drag frame ms (\(isReleaseBuild ? "Release" : "Debug")): "
            + timings.map { String(format: "%.1f", $0) }.joined(separator: ", ")
            + String(format: " — median %.2f, warm median %.2f", median, warmMedian))

        // Gate: the REGRESSION bound only (PERF-5 口径). The 60fps verdict
        // for the Debug evidence is a DECISIONS record, not a silent gate.
        if isReleaseBuild {
            XCTAssertLessThan(warmMedian, 20.0,
                String(format: "Release regression bound: warm median %.2fms", warmMedian))
        } else {
            XCTAssertLessThan(warmMedian, 120.0, "Debug pathological bound")
        }
    }

    // MARK: - FULL policy benchmark (D-06-CONTEXT-8 fallback point)

    /// Fit-view FULL (NO window): 5 layers, full-frame re-render per frame
    /// under BOTH cache policies + the windowed scene. The numbers land in
    /// perf.md; the conclusion (维持 fullColdLayer vs 回退 fullCacheAll)
    /// is D-06-05-T5-1's decision input.
    func testFullLayerPolicyBenchmark() async throws {
        let metal = try await makeMetal()
        let image = try makeSynthetic()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        let stack = makeTenLayerStack()
        let editedID = try XCTUnwrap(stack.compositeLayers[4].id)
        let imageID = UUID()

        func run(_ policy: LayerCachePolicy, roiHint: ROI?, cache: PipeCache) async throws
            -> Double
        {
            // Warm ONE frame (PSOs; the cold-layer policy evicts per run —
            // that IS the measured behavior).
            _ = try await LayerCompositeDriver.composite(
                image: image, imageID: imageID, baseInstances: base,
                layerStack: stack, registry: registry, resolution: .full,
                cache: cache, metal: metal, longEdge: nil, roiHint: roiHint,
                policy: policy, hotLayerID: editedID)
            drain(metal)
            let clock = ContinuousClock()
            let start = clock.now
            _ = try await LayerCompositeDriver.composite(
                image: image, imageID: imageID, baseInstances: base,
                layerStack: stack, registry: registry, resolution: .full,
                cache: cache, metal: metal, longEdge: nil, roiHint: roiHint,
                policy: policy, hotLayerID: editedID)
            drain(metal)
            let elapsed = clock.now - start
            return Double(elapsed.components.attoseconds) / 1e18 * 1000.0
        }

        // Synthetic is 2048×1536 — the "window" scene = a 1024×768 roiHint
        // (the zoom-in viewing window; O(viewport) vs O(full frame)).
        let window = ROI(x: 512, y: 384, width: 1024, height: 768, scale: 1.0)

        let coldFit = try await run(.fullColdLayer, roiHint: nil, cache: PipeCache())
        let allFit = try await run(.fullCacheAll, roiHint: nil, cache: PipeCache())
        let coldWindow = try await run(.fullColdLayer, roiHint: window, cache: PipeCache())
        let allWindow = try await run(.fullCacheAll, roiHint: window, cache: PipeCache())

        print("PERF6 FULL policy benchmark ms (Debug ×~3-5 vs Release): "
            + String(
                format: "fit cold=%.0f fit cacheAll=%.0f window cold=%.0f window cacheAll=%.0f",
                coldFit, allFit, coldWindow, allWindow))

        // Sanity (防空转): every scene rendered in bounded time.
        XCTAssertGreaterThan(coldFit, 0)
        XCTAssertGreaterThan(allFit, 0)
        XCTAssertGreaterThan(coldWindow, 0)
        XCTAssertGreaterThan(allWindow, 0)
        // The windowed scene must not cost MORE than the fit scene under
        // the same policy (strictly less work; loose 2× bound for noise).
        XCTAssertLessThan(coldWindow, coldFit * 2.0,
            "windowed re-render must not exceed the fit scene (O(viewport) ≤ O(full))")
    }

    /// T5.3 — the 10-layer windowed-FULL memory ledger re-check (PERF-2
    /// 前瞻; the FORMAL gate stays 6-7 签核): after a windowed FULL
    /// composite with the cold-layer policy, the cache holds ONLY planes
    /// bounded by the window (plus the hot layer's output) — the 06-1
    /// 2-layer ledger scaled to 10 layers; the per-plane bound is the
    /// window, never the full frame.
    func testTenLayerWindowedFullMemoryLedger() async throws {
        let metal = try await makeMetal()
        let image = try makeSynthetic()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        let stack = makeTenLayerStack()
        let editedID = try XCTUnwrap(stack.compositeLayers[4].id)
        let cache = PipeCache()
        let window = ROI(x: 512, y: 384, width: 1024, height: 768, scale: 1.0)

        _ = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: stack, registry: registry, resolution: .full,
            cache: cache, metal: metal, longEdge: nil, roiHint: window,
            policy: .fullColdLayer, hotLayerID: editedID)

        // The window plane bound: 1024×768 float32 = 3MB; the full-frame
        // plane would be 12.6MB. Every retained line must carry ≤ the
        // window bound (the roiHint sub-domain rendered per layer).
        let totalCold = await cache.totalBytes
        // The base leg (pre-geometry input + colorin) is full-frame by
        // nature; the LAYER leg (chains/prefixes/mask) is windowed.
        let baseLeg = 2048 * 1536 * 16 * 2
        let windowPlane = 1024 * 768 * 16
        XCTAssertLessThan(totalCold, baseLeg + windowPlane * 10,
            "windowed FULL: the layer leg must stay O(viewport) (base leg is full-frame by nature)")

        // The DECISION input: cacheAll retains strictly MORE (every layer's
        // chain output) than coldLayer in the same scene.
        let allCache = PipeCache()
        _ = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: stack, registry: registry, resolution: .full,
            cache: allCache, metal: metal, longEdge: nil, roiHint: window,
            policy: .fullCacheAll, hotLayerID: editedID)
        let totalAll = await allCache.totalBytes
        XCTAssertGreaterThan(totalAll, totalCold,
            "cacheAll must retain more than coldLayer (the cold-layer sweep works)")
        print("PERF6 windowed FULL ledger: coldLayer "
            + String(totalCold) + " B vs cacheAll " + String(totalAll) + " B")
    }
}
