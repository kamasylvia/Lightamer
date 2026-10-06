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

        // ── PERF-05 open→first-frame segments (M2-11-02 T4, KD-4; checker
        // E3-a: the new分项 live INSIDE this single func — zero new test
        // funcs, zero skip delta on the default suite). This leg runs FIRST
        // so the first decode of the process carries the RAW9 CoreML
        // one-time compile for the A7R V column (the compile-cold single
        // column — NOTE: CoreML caches compiled models on disk across
        // processes, so a warm-disk run measures a cache-hit cold; the
        // in-case 2.62s was a fresh-cache first compile). The grid loop
        // below therefore starts decode-warm (its cold cells keep only the
        // per-cell PSO compile — annotate in the transcription).
        // Gate object (OQ-6-A): warm thumb-512 first frame total ≤ 0.500 s;
        // fit-2560 = the record column (in-case warm ~2.08s). Judgment is
        // NOT asserted here — the numbers land in perf.md (KD-4).
        var openRows: [String] = []
        openRows.append("")
        openRows.append("## open→first-frame segments (PERF-05, warm = in-process second)")
        openRows.append("")
        openRows.append("| sample | decode cold (s) | decode warm (s) | first frame 512 total (s) | first frame 2560 total (s) |")
        openRows.append("|---|---|---|---|---|")
        for sample in samples {
            let coldStart = DispatchTime.now()
            let decoded = try await RAWDecoder().decode(sample.url)
            let decodeCold = Self.seconds(since: coldStart)
            let warmStart = DispatchTime.now()
            _ = try await RAWDecoder().decode(sample.url)
            let decodeWarm = Self.seconds(since: warmStart)
            _ = decoded
            // PSO warm-up (the throwaway first pipe run — the process-global
            // PSO compile lands here, untimed).
            _ = try await Self.probeRender(
                url: sample.url, longEdge: 512, metal: metal, registry: registry)
            // Warm first frames (fresh imageID per run = full pipe miss; the
            // exit leg rides the export queue per the probeRender shape).
            let f512Start = DispatchTime.now()
            _ = try await Self.probeRender(
                url: sample.url, longEdge: 512, metal: metal, registry: registry)
            let first512 = Self.seconds(since: f512Start)
            let f2560Start = DispatchTime.now()
            _ = try await Self.probeRender(
                url: sample.url, longEdge: 2560, metal: metal, registry: registry)
            let first2560 = Self.seconds(since: f2560Start)
            print(String(
                format: "PERF05| open→first-frame %@: decodeCold=%.3f decodeWarm=%.3f first512=%.3f first2560=%.3f (gate: warm thumb-512 total ≤ 0.500 s)",
                sample.label, decodeCold, decodeWarm, first512, first2560))
            openRows.append("| \(sample.label) | "
                + String(format: "%.3f", decodeCold) + " | "
                + String(format: "%.3f", decodeWarm) + " | "
                + String(format: "%.3f", first512) + " | "
                + String(format: "%.3f", first2560) + " |")
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
            + openRows.joined(separator: "\n") + "\n"
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
