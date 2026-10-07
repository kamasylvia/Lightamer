@testable import LightamerCore
import CoreGraphics
import Metal
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FullRenderBenchmarkTests (Plan M2-11-03 T1) — the SpektraLab gate ① bench:
// the FULL-bucket whole-chain render of the M2 default face on real RAW
// samples, warm < 1s (OQ-2-A①, the ROADMAP M2-11 "45MP full render <1s"
// line; in-library 60.2MP = the STRICTER-than-45MP letter, 100MP added as a
// column when the local fixture is present).
//
// Semantics (KD-1, RESEARCH §B.1): SpektraLab 45MP full render = a
// full-resolution print → ours = CIRAW decode (warm, in-process second
// decode) → FULL bucket whole chain (the M2 default face = terminal trio +
// GradeCatalog.defaultLook trio + the DRT SDR tail — the M2-11-02 T1 chain
// construction reused verbatim) rendering ONE frame end-to-end.
//
// Frame shape = the M2-11-02 T1 warm shape (per-frame exposure tick — every
// frame a full-chain miss; the "print after a tweak" cost). The DECOMPOSITION
// probes ride along (KD-4 attribution input, always collected): the decode
// leg (context columns), the .sdrGamma FULL control frame (main chain +
// colorout+gamma soft-encoded tail), and the tail-plane cache-hit leg
// (same-record second render, all hits — the cache floor).
//
// Gate (KD-1/OQ-2-A①): Release asserts warm median < 1000ms (the hard gate
// ITSELF); Debug only samples + carries a loose pathological bound (the
// number is dominated by FULL-bucket pixel count × GPU bandwidth — the
// Debug kernel overhead distorts it, the m2-10 perf.md §A.3 dual-column
// note applies). If the Release number lands > 1s: STOP per discipline 4 —
// the KD-4 decomposition table + a DECISIONS downgrade/postpone ruling land
// BEFORE any threshold change (no silent widening).
//
// Samples (KD-1, checker E5): 60.2MP `input/RAW/DSC00012.ARW` (repo-relative,
// DefaultLookTests/GUI22 same shape) is the PRIMARY column; the 100MP GFX
// fixture (`Fixtures.raf100MP`) rides when present. Both skip-gated (the
// skip-count reconciliation is per "有样张机器"; the 16-skip baseline is
// untouched on sample machines). L009: timed numbers only from the internal
// SSD-hosted fixtures.
// ─────────────────────────────────────────────────────────────────────────────

final class FullRenderBenchmarkTests: XCTestCase {

    /// true when the test binary carries optimization (no DEBUG flag).
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

    /// L014: the clock never stops before the queue drains — every timed
    /// frame fences inside the timing window (conservative-correct).
    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Sample columns (KD-1, checker E5)

    /// The 100MP column — the in-library local fixture (NOT tracked).
    private var raf100MP: URL { Fixtures.raf100MP }

    /// The 60.2MP PRIMARY column — repo-root `input/RAW/DSC00012.ARW`.
    private var dsc00012: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("input/RAW/DSC00012.ARW")
    }

    // MARK: - The M2 default-face chain (KD-1 — M2DefaultChainPerfTests same
    // construction, committed displayP3 terminal trio + defaultLook trio)

    private func makeM2DefaultChain(
        registry: ModuleRegistry
    ) async throws -> [any ModuleBoxing] {
        var chain = await makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3)
        for entry in GradeCatalog.defaultLook {
            guard let box = await registry.makeBox(opName: entry.opName) else { continue }
            switch entry.opName {
            case ExposureModule.opName:
                if let params = try? JSONDecoder().decode(
                    ExposureModule.Params.self, from: Data(entry.paramsJSON.utf8)) {
                    (box as? ModuleBox<ExposureModule>)?.setParams(params)
                }
            case ContrastModule.opName:
                if let params = try? JSONDecoder().decode(
                    ContrastModule.Params.self, from: Data(entry.paramsJSON.utf8)) {
                    (box as? ModuleBox<ContrastModule>)?.setParams(params)
                }
            case SaturationModule.opName:
                if let params = try? JSONDecoder().decode(
                    SaturationModule.Params.self, from: Data(entry.paramsJSON.utf8)) {
                    (box as? ModuleBox<SaturationModule>)?.setParams(params)
                }
            default:
                continue
            }
            chain.append(box)
        }
        return chain.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    private func tickExposure(_ chain: [any ModuleBoxing], _ value: Float) {
        if let exposure = chain.first(where: { $0.opName == ExposureModule.opName })
            as? ModuleBox<ExposureModule> {
            exposure.setParams(.init(exposure: value))
        }
    }

    /// One FULL-bucket frame of the whole chain (the DRT SDR tail on), timed
    /// with the drain inside the window (L014).
    private func fullFrame(
        image: DecodedImage, chain: [any ModuleBoxing], imageID: UUID,
        tail: TerminalTailPolicy, cache: PipeCache, metal: MetalContext
    ) async throws -> Double {
        let start = ContinuousClock.now
        _ = try await RenderPipeline.process(
            image: image, instances: chain, imageID: imageID,
            resolution: .full, cache: cache, metal: metal,
            terminalTail: tail)
        drain(metal)
        return Double((ContinuousClock.now - start).components.attoseconds) / 1e18 * 1000.0
    }

    private func mach_footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    // MARK: - T1: the FULL warm gate (SpektraLab ①, OQ-2-A①)

    func testFullRenderWarmGate() async throws {
        var samples: [(label: String, url: URL)] = [
            ("60MP A7R V ARW", dsc00012),
        ]
        if FileManager.default.fileExists(atPath: raf100MP.path) {
            samples.append(("100MP GFX100S RAF", raf100MP))
        } else {
            print("PERF| full-render note: 100MP GFX fixture absent — single 60MP column (DECISIONS stricter-letter note)")
        }
        for sample in samples {
            guard FileManager.default.fileExists(atPath: sample.url.path) else {
                throw XCTSkip("M2 bench fixture missing: \(sample.url.lastPathComponent)")
            }
        }

        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let chain = try await makeM2DefaultChain(registry: registry)
        await metal.prewarmPipelineStates(
            functionNames: LightamerIOPRegistry.prewarmFunctionNames)

        let sdrTail = TerminalTailPolicy.drt(DrtTailParams(record: DrtRecord()))
        var tick: Float = 1.5 // the grade-look EV anchor

        for sample in samples {
            // Decode cold/warm BEFORE timing (context columns — the decode
            // leg of the KD-4 decomposition).
            let decodeColdStart = ContinuousClock.now
            let image = try await RAWDecoder().decode(sample.url)
            let decodeCold = Double((ContinuousClock.now - decodeColdStart).components.attoseconds) / 1e18
            let decodeWarmStart = ContinuousClock.now
            _ = try await RAWDecoder().decode(sample.url)
            let decodeWarm = Double((ContinuousClock.now - decodeWarmStart).components.attoseconds) / 1e18

            let imageID = UUID()
            let cache = PipeCache()

            // Cold: the FIRST FULL pipe run (cache cold; PSOs pre-warmed).
            tickExposure(chain, tick)
            let cold = try await fullFrame(
                image: image, chain: chain, imageID: imageID,
                tail: sdrTail, cache: cache, metal: metal)

            // Warm ×3 (settle ×2 first): per-frame exposure tick — every
            // frame a full-chain miss at the FULL bucket.
            tick = 1.5
            for i in 0..<5 {
                tick += 0.001
                tickExposure(chain, tick)
                if i < 2 {
                    _ = try await fullFrame(
                        image: image, chain: chain, imageID: imageID,
                        tail: sdrTail, cache: cache, metal: metal)
                }
            }
            var warms: [Double] = []
            for _ in 0..<3 {
                tick += 0.001
                tickExposure(chain, tick)
                warms.append(try await fullFrame(
                    image: image, chain: chain, imageID: imageID,
                    tail: sdrTail, cache: cache, metal: metal))
            }
            let warmMedian = warms.sorted()[1]

            // Decomposition probe — the .sdrGamma FULL control (main chain +
            // colorout + gamma; the DRT-tail delta = warm − control) and the
            // tail-plane HIT leg (same-record second render, all hits — the
            // cache floor). Fresh tick counter to keep the control's shape
            // identical (per-frame full-chain miss on the main chain).
            var sdrWarms: [Double] = []
            var controlTick: Float = 1.5
            for _ in 0..<3 {
                controlTick += 0.001
                tickExposure(chain, controlTick)
                sdrWarms.append(try await fullFrame(
                    image: image, chain: chain, imageID: imageID,
                    tail: .sdrGamma, cache: cache, metal: metal))
            }
            let sdrMedian = sdrWarms.sorted()[1]

            // Observation leg (NOT the KD-2 gate — that lives in
            // DrtTailTests at the preview-2560 bucket): the same-record
            // FULL re-render. FULL caches input + final planes ONLY
            // (PixelPipe lock #4 — intermediates ping-pong by design), so
            // this leg re-renders the tail method box every time; its stats
            // are recorded for the decomposition table, never asserted.
            tickExposure(chain, tick) // settle back onto the sdrTail seed
            _ = try await fullFrame(
                image: image, chain: chain, imageID: imageID,
                tail: sdrTail, cache: cache, metal: metal)
            var hitWarms: [Double] = []
            var hitStatsLine = "n/a"
            for _ in 0..<3 {
                let start = ContinuousClock.now
                let (_, stats) = try await RenderPipeline.process(
                    image: image, instances: chain, imageID: imageID,
                    resolution: .full, cache: cache, metal: metal,
                    terminalTail: sdrTail)
                drain(metal)
                hitWarms.append(Double((ContinuousClock.now - start).components.attoseconds) / 1e18 * 1000.0)
                hitStatsLine = "hits=\(stats.hits) misses=\(stats.misses)"
            }
            let hitMedian = hitWarms.sorted()[1]
            print("PERF| full-render \(sample.label) same-record FULL re-render: \(hitStatsLine) (observation only — FULL caches input+final only)")

            let footprintDeltaMB = Double(mach_footprint()) / 1048576
            let line = String(
                format: "PERF| full-render %@ (%@): cold %.1f ms, warm %.1f/%.1f/%.1f ms, warm median %.1f ms | decode cold %.3f s warm %.3f s | sdrGamma control median %.1f ms | same-record FULL re-render median %.1f ms | footprint-now %.0f MB",
                sample.label, isReleaseBuild ? "Release" : "Debug",
                cold, warms[0], warms[1], warms[2], warmMedian,
                decodeCold, decodeWarm, sdrMedian, hitMedian, footprintDeltaMB)
            print(line)

            // The gate (KD-1/OQ-2-A①): Release asserts the warm hard gate
            // ITSELF; Debug carries only a pathological bound. A Release
            // miss = STOP per discipline 4 (KD-4 decomposition BEFORE any
            // threshold edit).
            if isReleaseBuild {
                XCTAssertLessThan(
                    warmMedian, 1000,
                    String(format: "SpektraLab gate ① FULL warm: median %.1f ms ≥ 1000 ms", warmMedian))
            } else {
                XCTAssertLessThan(warmMedian, 10000, "Debug pathological bound")
            }
        }
    }
}
