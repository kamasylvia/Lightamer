import CoreGraphics
import CoreImage
import LightamerCore
import Metal
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// Plan 11-05 T2 — the export PERF RECORD probes (只记不设门 — Phase 15 does
// the清算; RESEARCH §7-5). Debug-build numbers, temp-dir fixtures (L009: the
// built-in SSD, NEVER the USB volume). Every probe PRINTS an EXPORT-PERF line
// for `.work/11/perf.md` to transcribe:
//
//   EXPORT-PERF SEGMENT <fmt> renderStage=<ms> encodeStage=<ms>
//   EXPORT-PERF DECODE-ONLY <ms>
//   EXPORT-PERF FOOTPRINT-<mp>MP peakDeltaMB=<mb> projected100MPMB=<mb>
//   EXPORT-PERF TIFF32F-SIZE <bytes>
//
// The only assertions are anti-idle guards — no time gates.
// ─────────────────────────────────────────────────────────────────────────────
final class ExportPerfProbeTests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("export-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// The segmented timing: renderStage (decode → pipe render → exit leg →
    /// quantize) vs encodeStage (encode → atomic promote) per format, at a
    /// realistic 2560-long-edge full frame. The decode-only time is recorded
    /// separately so the render share can be read net of decode.
    func testSegmentedExportTimingPerFormat() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        let width = 2560, height = 1707
        let source = tempDirectory.appendingPathComponent("PERF_0001.png")
        try writePNGStub(width: 256, height: 171, to: source) // tiny stub; the DECODE is injected
        let decodeOnly = try await timeDecodeLeg(width: width, height: height)
        print("EXPORT-PERF DECODE-ONLY \(String(format: "%.1f", decodeOnly))ms")

        let cases: [(String, ExportVariant)] = [
            ("jpeg", ExportVariant(format: .jpeg(quality: 0.9), colorSpace: .sRGB)),
            ("png16", ExportVariant(format: .png(bitDepth: .sixteen), colorSpace: .sRGB)),
            ("tiff32f", ExportVariant(
                sizing: YiyinExportSettings(mode: .original, dpi: 300),
                format: .tiff(bitDepth: .float32, compression: .none),
                colorSpace: .rec2020)),
            ("heic10", ExportVariant(format: .heic(quality: 0.9, bitDepth: .ten), colorSpace: .displayP3)),
            ("avif10", ExportVariant(format: .avif(quality: 0.9, bitDepth: .ten), colorSpace: .sRGB)),
            ("webp", ExportVariant(format: .webp(quality: 0.85, lossless: false), colorSpace: .sRGB)),
        ]
        var tiff32fBytes = 0
        for (label, variant) in cases {
            // Warm pass (PSO + pool), then the recorded pass — the queue
            // amortizes PSO compilation across jobs, so the steady-state
            // number is the honest per-job share.
            _ = try await runSegmented(source: source, variant: variant, width: width, height: height)
            let (renderMs, encodeMs, bytes) = try await runSegmented(
                source: source, variant: variant, width: width, height: height)
            print(
                "EXPORT-PERF SEGMENT \(label) renderStage=\(String(format: "%.0f", renderMs))ms " +
                    "encodeStage=\(String(format: "%.0f", encodeMs))ms")
            if label == "tiff32f" { tiff32fBytes = bytes }
        }
        print("EXPORT-PERF TIFF32F-SIZE \(tiff32fBytes)")
        XCTAssertGreaterThan(tiff32fBytes, 0, "防空转: TIFF 32f size recorded")
    }

    /// The 100MP concurrency-1 red-line reconciliation (D-11-CONTEXT-2):
    /// render a 8192×5461 (~44.7MP) frame while sampling the process
    /// footprint, then project linearly to 100MP. The derivation claimed
    /// ≈5GB peak for ONE job; the projection is the measured witness.
    func testMemoryFootprintProjectionAtScale() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let width = 8192, height = 5461
        let megapixels = Double(width * height) / 1e6
        let source = tempDirectory.appendingPathComponent("PERF_BIG.png")
        try writePNGStub(width: 256, height: 171, to: source)

        let variant = ExportVariant(format: .png(bitDepth: .sixteen), colorSpace: .sRGB)
        _ = try await runSegmented(source: source, variant: variant, width: 512, height: 341) // warm

        let baseline = Self.physFootprint()
        let peak = PeakBox(initial: baseline)
        let sampling = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                peak.bump(Self.physFootprint())
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
        _ = try await runSegmented(source: source, variant: variant, width: width, height: height)
        sampling.cancel()
        let deltaMB = Double(peak.value - baseline) / (1024 * 1024)
        let projected = deltaMB * (100.0 / megapixels)
        print(
            "EXPORT-PERF FOOTPRINT-\(String(format: "%.1f", megapixels))MP " +
                "peakDeltaMB=\(String(format: "%.0f", deltaMB)) " +
                "projected100MPMB=\(String(format: "%.0f", projected))")
        XCTAssertGreaterThan(deltaMB, 0, "防空转: footprint sampled")
    }

    // MARK: - harness

    private func runSegmented(
        source: URL, variant: ExportVariant, width: Int, height: Int
    ) async throws -> (renderMs: Double, encodeMs: Double, bytes: Int) {
        let clock = ContinuousClock()
        let start = clock.now
        let stage = try await ExportRenderer.renderStage(
            request: ExportRenderer.Request(
                imageURL: source, destinationDirectory: tempDirectory,
                occupiedNames: [], variant: variant),
            metal: metal, registry: registry,
            decodeLeg: { _ in Self.syntheticDecodedImage(width: width, height: height) })
        let afterRender = clock.now
        let destination = try ExportRenderer.encodeStage(
            plane: stage.plane, formatSpec: stage.formatSpec,
            targetColorSpace: stage.targetColorSpace, dpi: stage.dpi,
            sourceURL: stage.sourceURL, editorSignature: stage.editorSignature,
            destination: stage.destination)
        let afterEncode = clock.now
        func ms(_ d: Duration) -> Double {
            Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        let bytes = (try? Data(contentsOf: destination).count) ?? 0
        try? FileManager.default.removeItem(at: destination)
        return (ms(afterRender - start), ms(afterEncode - afterRender), bytes)
    }

    /// The decode share, isolated (the RAWDecoder/ImageIO read the queue's
    /// render leg starts with).
    private func timeDecodeLeg(width: Int, height: Int) async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        _ = Self.syntheticDecodedImage(width: width, height: height)
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
    }

    /// A float32 linear-Rec2020 constant-ish gradient texture wrapped as a
    /// DecodedImage (the injected decode — deterministic, no disk read).
    private nonisolated static func syntheticDecodedImage(
        width: Int, height: Int
    ) -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = Float(x % 64) / 64.0 * 0.6
                rgba[i + 1] = Float(y % 64) / 64.0 * 0.6
                rgba[i + 2] = 0.25
                rgba[i + 3] = 1.0
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
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// A minimal PNG on disk (the renderer only needs a live file URL; the
    /// decode is injected above).
    private func writePNGStub(width: Int, height: Int, to url: URL) throws {
        let plane = ExportQuantizedPlane(
            data: Data([UInt8](repeating: 128, count: width * height * 4)),
            width: width, height: height, layout: .rgba8)
        _ = try PNGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .png(bitDepth: .eight),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
    }

    // MARK: footprint sampling

    /// Thread-safe peak recorder (the sampler Task and the test both touch
    /// the value — the ExportQueueTests.Peak shape).
    private final class PeakBox: @unchecked Sendable {
        private let lock = NSLock()
        private var peak: UInt64
        init(initial: UInt64) { peak = initial }
        func bump(_ candidate: UInt64) {
            lock.lock(); peak = Swift.max(peak, candidate); lock.unlock()
        }
        var value: UInt64 { lock.lock(); defer { lock.unlock() }; return peak }
    }

    private static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
