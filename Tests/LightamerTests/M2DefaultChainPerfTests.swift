@testable import LightamerCore
import CoreGraphics
import Metal
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// M2DefaultChainPerfTests (Plan M2-11-02 T1) — the M2 DEFAULT-FACE PERF-01
// bench (OQ-5-A chain face, the M2-10 handover item ① re-measurement).
//
// Chain face (KD-1): `ModuleRegistry.makeDefaultChain()` (the terminal trio,
// ChainBuilderHelpers same-source, committed displayP3) + ONE Grade node =
// the `GradeCatalog.defaultLook` trio (+1.5 EV / contrast +15 / saturation
// 1.3, decoded through each module's own Codable face — the mint path) +
// the DRT tail (`terminalTail: .drt(DrtTailParams(record: DrtRecord()))`,
// SDR default record). NO dt editing-seed iops in the chain (M2-1 feature
// flag semantics — the bench face IS the new-architecture face).
//
// Samples (KD-1, checker E5): the 100MP column carries the OQ-5-A "100MP 级
// 真样张" letter = `Fixtures.raf100MP` (GFX100S 100MP, in-library local
// fixture, NOT tracked); the 60.2MP cross column = `input/RAW/DSC00012.ARW`
// (A7R V, DefaultLookTests/GUI22UndoWarmColdTests same repo-relative path).
// Both skip-gated (machines without the fixtures skip; the skip-count
// reconciliation is per "有样张机器").
//
// Protocol (KD-1): L009 SSD samples, PSO startup pre-warm BEFORE the timed
// frames, per-frame exposure tick (+0.001 — the drag shape: stable imageID,
// every frame a full-chain miss), L014 drain before every clock stop,
// cold ×1 + warm ×3 (median). The 16.6ms/60fps judgment lives in
// perf.md + the M2-11-04 restatement batch — the test asserts ONLY the
// Debug/Release noise bounds (no 16.6ms hard line — the plan's KD-1
// "判定不在测试内断言" discipline).
// ─────────────────────────────────────────────────────────────────────────────

final class M2DefaultChainPerfTests: XCTestCase {

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

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Sample columns (KD-1, checker E5)

    /// The 100MP column (OQ-5-A letter carrier) — the in-library local
    /// fixture (Fixtures search order; NOT tracked).
    private var raf100MP: URL { Fixtures.raf100MP }

    /// The 60.2MP cross column — repo-root `input/RAW/DSC00012.ARW`
    /// (DefaultLookTests/GUI22UndoWarmColdTests same path shape).
    private var dsc00012: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("input/RAW/DSC00012.ARW")
    }

    // MARK: - The M2 default-face chain (KD-1)

    /// Terminal trio (committed displayP3 — ChainBuilderHelpers same-source)
    /// + the GradeCatalog.defaultLook trio (params decoded through each
    /// module's own Codable face — the EditorState mint path verbatim).
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

    /// One PREVIEW-2560 frame of the M2 default face (the DRT SDR tail on).
    private func frame(
        image: DecodedImage, chain: [any ModuleBoxing], imageID: UUID,
        cache: PipeCache, metal: MetalContext
    ) async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await RenderPipeline.process(
            image: image, instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal,
            longEdge: 2560, terminalTail: .drt(DrtTailParams(record: DrtRecord())))
        drain(metal)
        return Double((clock.now - start).components.attoseconds) / 1e18 * 1000.0
    }

    /// Per-frame exposure tick (the drag shape: stable imageID, per-frame
    /// full-chain miss). The exposure box IS the grade-look instance — a
    /// +0.001 drift per frame keeps every downstream hash invalidated.
    private func tickExposure(_ chain: [any ModuleBoxing], _ value: Float) {
        if let exposure = chain.first(where: { $0.opName == ExposureModule.opName })
            as? ModuleBox<ExposureModule> {
            exposure.setParams(.init(exposure: value))
        }
    }

    // MARK: - T1: the warm bench (PERF-01, OQ-5-A / handover ①)

    func testM2DefaultChainPreviewWarm() async throws {
        let samples: [(label: String, url: URL)] = [
            ("100MP GFX100S RAF", raf100MP),
            ("60MP A7R V ARW", dsc00012),
        ]
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

        var lines: [String] = []
        for sample in samples {
            // Decode twice BEFORE timing: the first decode carries the RAW9
            // CoreML one-time compile (cold), the second is the warm decode
            // the open→first-frame leg rides (context columns only here).
            let decodeColdStart = ContinuousClock.now
            let image = try await RAWDecoder().decode(sample.url)
            let decodeCold = Double((ContinuousClock.now - decodeColdStart).components.attoseconds) / 1e18
            let decodeWarmStart = ContinuousClock.now
            _ = try await RAWDecoder().decode(sample.url)
            let decodeWarm = Double((ContinuousClock.now - decodeWarmStart).components.attoseconds) / 1e18

            // Cold: the FIRST pipe run (cache cold; PSOs pre-warmed above).
            let imageID = UUID()
            let cache = PipeCache()
            var tick: Float = 1.5 // the grade-look EV anchor
            tickExposure(chain, tick)
            let cold = try await frame(
                image: image, chain: chain, imageID: imageID, cache: cache, metal: metal)

            // Warm ×3 → median (settle ×2 first: allocator/PSO variants).
            tick = 1.5
            for i in 0..<5 {
                tick += 0.001
                tickExposure(chain, tick)
                if i < 2 {
                    _ = try await frame(
                        image: image, chain: chain, imageID: imageID,
                        cache: cache, metal: metal)
                }
            }
            var warms: [Double] = []
            for _ in 0..<3 {
                tick += 0.001
                tickExposure(chain, tick)
                warms.append(try await frame(
                    image: image, chain: chain, imageID: imageID,
                    cache: cache, metal: metal))
            }
            let warmMedian = warms.sorted()[1]
            let line = String(
                format: "PERF| m2-default-chain preview-2560 %@ (%@): cold %.1f ms, warm %.1f/%.1f/%.1f ms, warm median %.1f ms | decode cold %.3f s warm %.3f s",
                sample.label, isReleaseBuild ? "Release" : "Debug",
                cold, warms[0], warms[1], warms[2], warmMedian, decodeCold, decodeWarm)
            print(line)
            lines.append(line)

            // Noise bounds only — the 16.6ms/60fps judgment lives in perf.md
            // (KD-1: no hard gate line inside the test).
            if isReleaseBuild {
                XCTAssertLessThan(warmMedian, 500, "Release regression bound")
            } else {
                XCTAssertLessThan(warmMedian, 2000, "Debug pathological bound")
            }
        }
        _ = lines
    }
}
