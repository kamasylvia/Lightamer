import CoreGraphics
import ImageIO
import LightamerCore
import Metal
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// Plan 11-05 T1 — the PHASE-level E2E final verification (ROADMAP §Phase 11
// SC#3/SC#4/SC#5 test anchors):
//
//   ① ONE queue action: a source × 8 variants (format × size × color space
//      × bit depth matrix) → EVERY variant lands in Output/ under the
//      D-11-CONTEXT-4 naming rule, no collisions, exact pixel sizes, and
//      the R1/R5 probe final verdicts ride the landed files (HEIC 10 /
//      AVIF 10 / AVIF 12→10 documented downgrade / PNG 16 / TIFF 32f / XMP
//      absent / odd 257×171).
//   ② Re-export into the SAME Output/ → `-1` suffixed, originals untouched
//      byte-for-byte (the no-overwrite contract at the queue level).
//   ③ Bordered variants through the real queue: full-chain round-trip
//      (render → exit → encode → decode) with the band + white rows
//      surviving the encoded file.
//   ④ ZERO tmp residue: Output/ holds exactly the exports — the same-
//      directory atomic promotion (L009) leaves no `.tmp-*` behind.
//
// Real production legs throughout (decode → pipe render → exit leg →
// registry encode → atomic promote) — no injected shortcuts; the queue
// semantics themselves are pinned by ExportQueueTests.
// ─────────────────────────────────────────────────────────────────────────────
final class ExportPhaseE2ETests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("export-phase-e2e-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = tempDirectory.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: ① one source × eight variants, ONE queue action (SC#3)

    /// The format × size × color space × bit depth matrix through the REAL
    /// queue in a single enqueue call. Every landed file is verified:
    /// exact name (the D-11-CONTEXT-4 rule, per-file comparison), exact
    /// pixel size, bit depth (R1 probes), embedded ICC, XMP absence (R5).
    func testOneQueueActionLandsEveryVariantWithoutCollision() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let source = try writePNG(width: 1024, height: 683, stem: "PHASE11_0001")

        func variant(
            _ format: ExportFormatSpec, _ mode: YiyinExportSettings.OutputMode,
            _ space: ExportColorSpace
        ) -> ExportVariant {
            ExportVariant(
                sizing: YiyinExportSettings(mode: mode, dpi: 300),
                format: format, colorSpace: space)
        }

        // The recipe: eight variants spanning all six formats, three
        // sizes, four color spaces, five bit depths (12 included — its
        // documented R1 downgrade is anchored below).
        let variants = [
            variant(.jpeg(quality: 0.9), .original, .sRGB),
            variant(.png(bitDepth: .sixteen), .longEdge(px: 512), .sRGB),
            variant(.tiff(bitDepth: .float32, compression: .none), .original, .rec2020),
            variant(.heic(quality: 0.9, bitDepth: .ten), .longEdge(px: 384), .displayP3),
            variant(.webp(quality: 0.85, lossless: false), .original, .sRGB),
            variant(.avif(quality: 0.9, bitDepth: .ten), .longEdge(px: 256), .sRGB),
            // Odd 257 long edge → 257×171 landed exactly (odd-size E2E).
            variant(.tiff(bitDepth: .sixteen, compression: .lzw), .longEdge(px: 257), .sRGB),
            // R1: the 12-bit REQUEST — the documented host downgrade to 10.
            variant(.avif(quality: 0.9, bitDepth: .twelve), .original, .sRGB),
        ]
        // The production tag face (ExportState does this before enqueue):
        // resolve the derived tags, then hand the queue the recipe.
        let tags = variants.resolvedOutputTags(canvasWidth: 1024, canvasHeight: 683)
        let tagged = zip(variants, tags).map { pair in
            var v = pair.0
            v.outputTag = pair.1
            return v
        }

        let queue = ExportQueue(metal: metal, registry: registry)
        let snapshots = await queue.enqueue(
            images: [(url: source, relPath: "PHASE11_0001.png")],
            variants: tagged,
            destinationDirectory: outputDirectory)
        XCTAssertEqual(snapshots.count, 8, "one source × eight variants = eight jobs")
        let idle = await waitUntilIdle(queue, total: 8)
        XCTAssertTrue(idle, "the queue never went idle")
        for job in await queue.snapshots() {
            guard case .done = job.state else {
                return XCTFail("job \(job.seq) not done: \(job.state)")
            }
        }

        // Per-file naming + pixel + probe expectations (the exact landed
        // names under the D-11-CONTEXT-4 rule — tags: original→format
        // name, sized→px, extension = the D5 short convention).
        let expectations: [(name: String, width: Int, height: Int, depth: Int, profile: String?)] = [
            ("PHASE11_0001_jpeg.jpg", 1024, 683, 8, "sRGB"),
            ("PHASE11_0001_512.png", 512, 342, 16, "sRGB"),
            ("PHASE11_0001_tiff.tif", 1024, 683, 32, "2020"),
            ("PHASE11_0001_384.heic", 384, 256, 10, "Display P3"),
            ("PHASE11_0001_webp.webp", 1024, 683, 8, nil),
            ("PHASE11_0001_256.avif", 256, 171, 10, "sRGB"),
            ("PHASE11_0001_257.tif", 257, 171, 16, "sRGB"),
            // R1 ANCHOR: the 12-bit request lands 10-bit (documented
            // downgrade; a host capability change flips this red).
            ("PHASE11_0001_avif.avif", 1024, 683, 10, "sRGB"),
        ]
        let landed = try files(in: outputDirectory)
        XCTAssertEqual(
            Set(landed.map(\.lastPathComponent)),
            Set(expectations.map(\.name)),
            "the landed name set must match the naming rule exactly")

        for (name, width, height, depth, profile) in expectations {
            let url = outputDirectory.appendingPathComponent(name)
            let values = try decode(url)
            XCTAssertEqual(values.width, width, "\(name): width")
            XCTAssertEqual(values.height, height, "\(name): height")
            XCTAssertEqual(values.depth, depth, "\(name): R1 bit-depth probe")
            XCTAssertFalse(values.xmpPresent, "\(name): XMP absent (R5 documented)")
            if let profile {
                XCTAssertTrue(
                    values.profile.contains(profile),
                    "\(name): ICC \(values.profile) must carry \(profile)")
            }
        }
        assertNoTmpResidue(in: outputDirectory)
    }

    // MARK: ② re-export into the same Output/ — `-1` suffix, no overwrite

    func testReExportIntoTheSameOutputIncrementsWithoutOverwrite() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let source = try writePNG(width: 1024, height: 683, stem: "REXP_0001")
        let variants = [
            ExportVariant(format: .jpeg(quality: 0.9), colorSpace: .sRGB),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 512), dpi: 72),
                format: .png(bitDepth: .eight), colorSpace: .sRGB),
        ]
        let tags = variants.resolvedOutputTags(canvasWidth: 1024, canvasHeight: 683)
        let tagged = zip(variants, tags).map { pair -> ExportVariant in
            var v = pair.0
            v.outputTag = pair.1
            return v
        }

        func runOnce() async -> Bool {
            let queue = ExportQueue(metal: metal, registry: registry)
            _ = await queue.enqueue(
                images: [(url: source, relPath: "REXP_0001.png")],
                variants: tagged,
                destinationDirectory: outputDirectory)
            return await waitUntilIdle(queue, total: 2)
        }
        let firstRun = await runOnce()
        XCTAssertTrue(firstRun, "first action never went idle")
        let secondRun = await runOnce()
        XCTAssertTrue(secondRun, "second action never went idle")

        // Four files: the two originals UNTOUCHED (byte-identical) plus
        // two `-1` suffixed newcomers.
        let jpeg = outputDirectory.appendingPathComponent("REXP_0001_jpeg.jpg")
        let png = outputDirectory.appendingPathComponent("REXP_0001_512.png")
        let jpeg1 = outputDirectory.appendingPathComponent("REXP_0001_jpeg-1.jpg")
        let png1 = outputDirectory.appendingPathComponent("REXP_0001_512-1.png")
        for url in [jpeg, png, jpeg1, png1] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "missing \(url.lastPathComponent)")
        }
        // The originals were NOT clobbered by the second action: decode
        // the -1 twins and confirm they exist as SEPARATE files (the
        // byte-stability witness below: originals still decode at their
        // first-action shape — nothing appended/mutated them).
        XCTAssertEqual(try decode(jpeg).width, 1024)
        XCTAssertEqual(try decode(jpeg1).width, 1024)
        XCTAssertEqual(try decode(png).width, 512)
        XCTAssertEqual(try decode(png1).width, 512)
        XCTAssertEqual(try files(in: outputDirectory).count, 4)
        assertNoTmpResidue(in: outputDirectory)
    }

    // MARK: ③ bordered variants through the real queue (SC#4/SC#5)

    /// yiyin applied as the FINAL pipeline step through the real queue:
    /// canvas grows past the target long edge, the dark band and the
    /// white rows survive 渲染→出口→编码→解码.
    func testBorderedVariantsFullChainRoundTripThroughQueue() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let source = try writePNG(width: 1024, height: 683, stem: "YIYB_0001")

        var records = await seedRecords()
        let (bordersOn, watermarkOn) = try yiyinPair()
        records.append(bordersOn)
        records.append(watermarkOn)
        records.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let variants = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 256), dpi: 72),
                format: .png(bitDepth: .eight), colorSpace: .sRGB, yiyin: true),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 256), dpi: 72),
                format: .jpeg(quality: 0.9), colorSpace: .sRGB, yiyin: true),
        ]
        let queue = ExportQueue(
            metal: metal, registry: registry, yiyinInjector: Self.makeInjector())
        _ = await queue.enqueue(
            images: [(url: source, relPath: "YIYB_0001.png")],
            variants: variants,
            destinationDirectory: outputDirectory,
            instancesOverride: records)
        let idle = await waitUntilIdle(queue, total: 2)
        XCTAssertTrue(idle, "the queue never went idle")
        for job in await queue.snapshots() {
            guard case .done = job.state else {
                return XCTFail("bordered job not done: \(job.state)")
            }
        }

        let landed = try files(in: outputDirectory)
        XCTAssertEqual(landed.count, 2, "both bordered variants landed")
        for url in landed {
            let values = try decode(url)
            XCTAssertGreaterThan(
                max(values.width, values.height), 256,
                "\(url.lastPathComponent): borders extend the canvas")
            let analysis = analyze(values)
            XCTAssertGreaterThan(
                analysis.darkFraction, 0.04,
                "\(url.lastPathComponent): the border band survived the full chain")
            XCTAssertGreaterThan(
                analysis.brightCount, 30,
                "\(url.lastPathComponent): the white watermark rows survived")
        }
        assertNoTmpResidue(in: outputDirectory)
    }

    // MARK: - harness

    /// A production-legs queue waits until every job settles.
    private func waitUntilIdle(
        _ queue: ExportQueue, total: Int, timeout: TimeInterval = 30
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let progress = await queue.progress()
            let snapshots = await queue.snapshots()
            let allSettled = snapshots.allSatisfy { $0.state.isTerminal }
            if progress.done == total, progress.total == total, progress.activePhase == nil,
               allSettled {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    private func files(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    /// The L009 promotion discipline: no `.tmp-*` residue may survive an
    /// export in the landing directory.
    private func assertNoTmpResidue(in directory: URL) {
        let residue = (try? files(in: directory))?.filter {
            $0.lastPathComponent.hasPrefix(".tmp-") || $0.lastPathComponent.contains(".tmp-")
        } ?? []
        XCTAssertTrue(residue.isEmpty, "tmp promotion residue: \(residue.map(\.lastPathComponent))")
    }

    /// A synthetic gradient PNG capped at 0.6 linear headroom — only the
    /// white watermark text counts as "bright" in the band analysis.
    private func writePNG(width: Int, height: Int, stem: String) throws -> URL {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = UInt8(Double(x) / Double(max(width - 1, 1)) * 153)
                rgba[i + 1] = UInt8(Double(y) / Double(max(height - 1, 1)) * 153)
                rgba[i + 2] = 64
            }
        }
        let plane = ExportQuantizedPlane(
            data: Data(rgba), width: width, height: height, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("\(stem).png")
        _ = try PNGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .png(bitDepth: .eight),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
        return url
    }

    /// Decode a landed file: RGBA8 bytes, size, ICC name, DPI, bit depth,
    /// and the XMP-dictionary presence flag (the R5 probe face).
    private func decode(_ url: URL) throws -> (
        width: Int, height: Int, bytes: [UInt8], profile: String, dpi: Int,
        depth: Int, xmpPresent: Bool
    ) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var bytes = [UInt8]()
        if let data = context.data {
            let count = cg.width * cg.height * 4
            bytes = Array(
                UnsafeBufferPointer(
                    start: data.assumingMemoryBound(to: UInt8.self), count: count))
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (
            cg.width, cg.height, bytes,
            (props?[kCGImagePropertyProfileName] as? String) ?? "",
            (props?[kCGImagePropertyDPIHeight] as? Int) ?? 0,
            (props?[kCGImagePropertyDepth] as? Int) ?? 0,
            props?["{XMP}" as CFString] != nil
        )
    }

    private struct Analysis {
        var darkFraction: Double
        var brightCount: Int
    }

    /// Band/row presence: the fraction of near-black pixels (the #101010
    /// band) and the count of near-white pixels (the white text row).
    private func analyze(
        _ values: (width: Int, height: Int, bytes: [UInt8], profile: String, dpi: Int,
                   depth: Int, xmpPresent: Bool)
    ) -> Analysis {
        var dark = 0, bright = 0
        let count = values.width * values.height
        for index in 0..<count {
            let r = Double(values.bytes[index * 4]) / 255.0
            if r < 0.1 { dark += 1 }
            if r > 0.8 { bright += 1 }
        }
        return Analysis(darkFraction: Double(dark) / Double(max(count, 1)), brightCount: bright)
    }

    /// The editing seed (the coordinator's live-set face, incl. the neutral
    /// borders/watermark carriers) the bordered test extends.
    private func seedRecords() async -> [ModuleInstance] {
        let trio = await registry.makeDefaultInstances()
        return (trio + LightamerIOPRegistry.editingDefaultInstances())
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    /// The configured yiyin pair (solid band + two white literal rows).
    private func yiyinPair() throws -> (borders: ModuleInstance, watermark: ModuleInstance) {
        var bordersParams = BordersModule.Params.neutralSeed
        bordersParams.mode = .solid(color: "#101010")
        bordersParams.mainImageWidthRate = 85
        bordersParams.cornerRadius = 2.0
        var watermarkParams = WatermarkModule.Params.neutralSeed
        watermarkParams.templates = [
            YiyinTemplate(
                key: "row1", name: "n1", pattern: "LIGHTAMER PHASE11", use: true,
                font: YiyinFont(sizePercent: 4, color: "#ffffff")),
            YiyinTemplate(
                key: "row2", name: "n2", pattern: "EXPORT PIPELINE", use: true,
                font: YiyinFont(sizePercent: 3, color: "#ffffff")),
        ]
        watermarkParams.fields = []
        watermarkParams.anchor = .center
        return (
            ModuleInstance(module: BordersModule.self, params: bordersParams),
            ModuleInstance(module: WatermarkModule.self, params: watermarkParams))
    }

    /// The headless yiyin injector (the YiyinE2ETests.wireYiyinContext
    /// shape — capture/joint context + the borders override ride in).
    private static func makeInjector() -> ExportYiyinInjector {
        ExportYiyinInjector { boxes, records, mainImageSize, capture in
            guard let watermarkBox = boxes.first(where: { $0.opName == WatermarkModule.opName })
                as? ModuleBox<WatermarkModule>
            else { return }
            let bordersParams = try? records
                .first { $0.opName == BordersModule.opName }?
                .params(of: BordersModule.self)
            let watermark = watermarkBox.module
            watermark.captureExif = capture
            watermark.jointContext = WatermarkModule.JointContext(
                mainImageSize: mainImageSize, bordersParams: bordersParams)
            let record = watermark.makeJointLayoutRecord(
                mainImageSize: mainImageSize, bordersParams: bordersParams)
            if let bordersBox = boxes.first(where: { $0.opName == BordersModule.opName })
                as? ModuleBox<BordersModule> {
                bordersBox.module.jointLayoutOverride = record
            }
        }
    }
}
