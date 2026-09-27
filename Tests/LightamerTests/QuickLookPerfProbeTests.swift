import CoreGraphics
import XCTest
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// QuickLookPerfProbeTests (Plan 13-1 T2) — the QL render-latency probe.
//
// GATED: runs only with `LA_QL_PERF=1` in the environment (a probe, NOT a
// resident-suite member — it decodes two real camera RAWs 24× and takes
// minutes). This file is also the PROTOTYPE of the T3 `QuickLookRenderer`
// seam: sidecar-truth records → ExportChainBuilder (sRGB display-terminal,
// gamma stripped — the reduction twin of ExportRenderer minus
// yiyin/sizing/quantize-encode) → routed pipe run → export-queue exit leg →
// packed RGBA8 → CGImage. T3 moves this body into LightamerCore.
//
// Grid: 2 samples (100 MP GFX100S RAF + mid-size A7R V ARW) × 3 long edges
// (512 thumbnail / 1440 mid preview / 2560 QL fit preview) × (1 cold + 3
// warm, median). Cold/warm are SEPARATE columns per plan — the very first
// render of the process additionally carries the global PSO compilation
// (noted in the table).
//
// Output: a markdown table on stdout AND /tmp/la-ql-perf.md (probe
// artifacts live in /tmp and die there — L009; nothing lands in the repo).
// The numbers and the TIMEOUT verdict are transcribed by hand into
// .work/gsd/phases/13-system-integration-distribution/perf.md.
// ─────────────────────────────────────────────────────────────────────────────

final class QuickLookPerfProbeTests: XCTestCase {

    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["LA_QL_PERF"] == "1" else {
            throw XCTSkip("QL perf probe gated — set LA_QL_PERF=1 to run")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    // MARK: - The probe grid

    private static let edges: [(label: String, longEdge: Int)] = [
        ("512 (thumb)", 512),
        ("1440 (mid)", 1440),
        ("2560 (fit)", 2560),
    ]

    func testQLRenderLatencyGrid() async throws {
        let samples: [(label: String, url: URL)] = [
            ("100MP GFX100S RAF", Fixtures.raf100MP),
            ("A7R V ARW (mid)", Fixtures.arw),
        ]
        for sample in samples {
            try Fixtures.require(sample.url)
        }

        var rows: [String] = []
        rows.append("| sample | long edge | cold (s) | warm median (s) | warm ×3 (s) | out px |")
        rows.append("|---|---|---|---|---|---|")

        for sample in samples {
            for edge in Self.edges {
                // Cold: the FIRST render at this grid cell (the very first
                // cell also carries the global PSO compilation — annotated
                // in the table by hand).
                let coldStart = DispatchTime.now()
                let image = try await Self.probeRender(
                    url: sample.url, longEdge: edge.longEdge,
                    metal: metal, registry: registry)
                let cold = Self.seconds(since: coldStart)
                let coldNote = (sample.label == samples[0].label
                    && edge.label == Self.edges[0].label) ? " (PSO)" : ""

                // Warm ×3 → median.
                var warms: [Double] = []
                var lastSize = ""
                for _ in 0..<3 {
                    let start = DispatchTime.now()
                    let warm = try await Self.probeRender(
                        url: sample.url, longEdge: edge.longEdge,
                        metal: metal, registry: registry)
                    warms.append(Self.seconds(since: start))
                    lastSize = "\(warm.width)×\(warm.height)"
                }
                let median = warms.sorted()[1]
                let row = "| \(sample.label) | \(edge.label) | "
                    + String(format: "%.3f", cold) + coldNote + " | "
                    + String(format: "%.3f", median) + " | "
                    + warms.map { String(format: "%.3f", $0) }.joined(separator: " / ")
                    + " | " + lastSize + " |"
                rows.append(row)
                _ = image // (cold image already consumed via the size print)
            }
        }

        let report = rows.joined(separator: "\n") + "\n"
        print("\n===== QL RENDER LATENCY PROBE =====\n\(report)=====\n")
        let out = URL(fileURLWithPath: "/tmp/la-ql-perf.md")
        try? report.write(to: out, atomically: true, encoding: .utf8)
    }

    // MARK: - The probe render (the T3 QuickLookRenderer prototype body)

    /// Decode → default-chain sRGB display-terminal render @ `longEdge` →
    /// packed RGBA8 → CGImage. EXACTLY the reduction-twin path (no yiyin,
    /// no export sizing, no quantize-to-file): the L031 routing
    /// (`$routesToExportQueue`) wraps the pipe run; the exit leg hangs its
    /// fence on the export queue (L014 discipline rides the pool).
    static func probeRender(
        url: URL, longEdge: Int, metal: MetalContext, registry: ModuleRegistry
    ) async throws -> CGImage {
        let decodeStart = DispatchTime.now()
        let decoded = try await RAWDecoder().decode(url)
        let decodeSeconds = Self.seconds(since: decodeStart)
        let records = await registry.makeDefaultInstances()
        let built = try ExportChainBuilder.exportChain(
            from: records, target: .sRGB, linearVariant: false)
        let (boxes, _) = await registry.materializeBoxes(for: built.instances)
        // The colorout override socket (the ExportRenderer shape): set AFTER
        // materialization, then re-commit the params so the folded hash
        // carries it.
        for box in boxes {
            guard let colorout = box as? ModuleBox<ColorOutModule> else { continue }
            colorout.module.exportTargetOverride = built.exportTargetOverride
            if let record = built.instances.first(where: {
                $0.opName == ColorOutModule.opName && $0.id == box.instanceID
            }) {
                let params = (try? record.params(of: ColorOutModule.self))
                    ?? ColorOutModule.Params()
                colorout.setParams(params)
            }
        }

        let renderStart = DispatchTime.now()
        let (texture, _) = try await MetalContext.$routesToExportQueue.withValue(true) {
            try await RenderPipeline.process(
                image: decoded, instances: boxes, imageID: UUID(),
                resolution: .export, cache: PipeCache(), metal: metal,
                longEdge: longEdge)
        }
        let pool = CIContextPool(device: metal.device, commandQueue: metal.exportCommandQueue)
        let sourceColorSpace =
            built.coloroutOverridden ? built.exportTargetOverride : WorkingSpace.colorSpace
        let encoded = try await pool.renderToEncodedBitmap(
            TextureBox(texture: texture),
            sourceColorSpace: sourceColorSpace,
            toSpace: built.exportTargetOverride)
        let samples = encoded.data.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        let packed = try ExportQuantizer.packedRGBA8(
            rgba: samples, width: encoded.width, height: encoded.height)
        let plane = ExportQuantizedPlane(
            data: packed, width: encoded.width, height: encoded.height, layout: .rgba8)
        let image = try ImageIOEncodeCore.makeCGImage(
            from: plane, colorSpace: built.exportTargetOverride)
        print(
            "probe: \(longEdge)px decode=\(String(format: "%.3f", decodeSeconds))s pipe+exit=\(String(format: "%.3f", Self.seconds(since: renderStart)))s"
        )
        return image
    }

    private static func seconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
    }
}
