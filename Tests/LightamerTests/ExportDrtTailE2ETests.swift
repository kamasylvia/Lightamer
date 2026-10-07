import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import LightamerCore
import Metal
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportDrtTailE2ETests (Plan M2-9-02 T2, KD-4 — EXPORT bundle) — the DRT
// carrier through the RENDER stage and the QUEUE:
//
//   1. SDR DRT E2E (AC4): rec709+gamma22 → the tail renders (the export
//      differs from the legacy five-space export — the linkage is real),
//      the file lands with the unchanged destination name, and the
//      EMBEDDED ICC is the DRT encoding's profile (the desc label
//      round-trips through kCGImagePropertyProfileName).
//   2. HDR DRT E2E (AC4 + AC5): rec2020+st2084 through TIFF 32f — the
//      "输出编码即 DRT 编码" face (PQ-encoded values as float32) with the
//      OQ-8-A [0,1] quantizer clamp sealing the range.
//   3. The queue delivery seam (KD-4): `enqueue(drtTails:)` reaches the
//      render through `ExportRenderer.$jobDrtTail` — the queued job's
//      output is byte-equal to the direct render with the same payload.
//   4. The nil carrier is the zero path: a nil-carrier render is
//      byte-stable (the legacy suite staying green is the wider proof).
// ─────────────────────────────────────────────────────────────────────────────

final class ExportDrtTailE2ETests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("export-drt-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - harness

    private func makeRegistryReady() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    /// The full editing seed (trio + editing defaults — the sidecar truth).
    private func seedRecords() async -> [ModuleInstance] {
        let trio = await registry.makeDefaultInstances()
        return (trio + LightamerIOPRegistry.editingDefaultInstances())
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    /// A synthetic gradient PNG source.
    private func writePNG(width: Int, height: Int, stem: String) throws -> URL {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = UInt8(Double(x) / Double(max(width - 1, 1)) * 204)
                rgba[i + 1] = UInt8(Double(y) / Double(max(height - 1, 1)) * 204)
                rgba[i + 2] = 80
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

    /// Persist a sidecar beside the source.
    private func writeSidecar(imageURL: URL, records: [ModuleInstance]) async throws {
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 0,
            instances: records,
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0),
            appVersion: "0.3.0-drt-e2e")
        let store = SidecarStore(destination: LightamerSidecar.sidecarURL(for: imageURL))
        await store.scheduleWrite(document)
        try await store.flushNow()
    }

    /// The synthetic decode leg (the largeSyntheticImage shape — no RAW
    /// decode, deterministic content).
    private nonisolated static func syntheticDecode(url: URL) async throws -> DecodedImage {
        let width = 96, height = 64
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i + 0] = Float(x) / Float(width - 1) * 0.8
                rgba[i + 1] = Float(y) / Float(height - 1) * 0.6
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
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    private func makeRequest(
        source: URL, variant: ExportVariant, drtTail: DrtTailParams?,
        directory: URL? = nil
    ) -> ExportRenderer.Request {
        ExportRenderer.Request(
            imageURL: source,
            destinationDirectory: directory ?? tempDirectory,
            occupiedNames: [],
            variant: variant,
            drtTail: drtTail)
    }

    /// A fresh landing directory (the layer-test pattern — the source PNG
    /// shares the temp root, so every render lands in its own directory and
    /// the namer never sees a collision).
    private func makeLanding(_ label: String) throws -> URL {
        let directory = tempDirectory.appendingPathComponent(
            "landing-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Decode an encoded image: RGBA8 bytes, size, ICC profile name.
    private func decodedPNGValues(_ url: URL) throws -> (
        width: Int, height: Int, bytes: [UInt8], profile: String
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
        let profile = (props?[kCGImagePropertyProfileName] as? String) ?? ""
        return (cg.width, cg.height, bytes, profile)
    }

    /// The float32 TIFF readback (the golden suite's normalizing-context
    /// shape): RGBA float samples through the SAME profile space.
    private func decodedFloatTIFFValues(_ url: URL) throws -> (
        width: Int, height: Int, samples: [Float], profile: String
    ) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let w = cg.width, h = cg.height
        let bytesPerRow = w * 16
        var buffer = [Float](repeating: 0, count: w * h * 4)
        let info = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(
            data: &buffer, width: w, height: h, bitsPerComponent: 32,
            bytesPerRow: bytesPerRow, space: WorkingSpace.colorSpace,
            bitmapInfo: info.rawValue)
        else { throw AppError.decodeFailed("float readback context failed") }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let profile = (props?[kCGImagePropertyProfileName] as? String) ?? ""
        return (w, h, buffer, profile)
    }

    private func sdrDrtTail() -> DrtTailParams {
        DrtTailParams(record: DrtRecord())  // Rec709 + gamma22 (the default)
    }

    private func hdrDrtTail() -> DrtTailParams {
        var record = DrtRecord()
        record.encodingSpace = .rec2020
        record.encodingEotf = .st2084
        record.peakLuminance = 1000
        return DrtTailParams(record: record)
    }

    // MARK: - 1: the SDR DRT E2E

    func testSDRDrtExportRendersThroughTheTailWithTheDRTICC() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "DRTS_0001")
        try await writeSidecar(imageURL: source, records: await seedRecords())

        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB)
        let drtOutcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant, drtTail: sdrDrtTail(),
                directory: try makeLanding("drt")),
            metal: metal, registry: registry)

        // Destination naming unchanged (KD-4: the DRT carrier enters no
        // naming face — no tag, no suffix).
        XCTAssertEqual(
            drtOutcome.destination.lastPathComponent, "DRTS_0001.png",
            "the DRT carrier enters no naming face")
        // The file decodes at the target size with the DRT profile embedded.
        let values = try decodedPNGValues(drtOutcome.destination)
        XCTAssertEqual(values.width, 48)
        XCTAssertEqual(values.height, 32)
        XCTAssertGreaterThan(values.bytes.count, 0)
        XCTAssertTrue(
            values.profile.contains("Lightamer Rec709 Gamma 2.2"),
            "the embedded ICC is the DRT encoding's profile, got "
                + "\(values.profile)")
        XCTAssertTrue(
            values.profile.contains("Gamma 2.2"),
            "the ICC carries the record's EOTF")

        // The linkage is REAL: the same source through the legacy five-space
        // face renders DIFFERENT bytes (the DRT tail replaced gamma+colorout).
        let legacyOutcome = try await ExportRenderer.render(
            request: ExportRenderer.Request(
                imageURL: source,
                destinationDirectory: try makeLanding("legacy"),
                occupiedNames: [source.lastPathComponent],
                variant: variant),
            metal: metal, registry: registry)
        XCTAssertNotEqual(
            try Data(contentsOf: drtOutcome.destination),
            try Data(contentsOf: legacyOutcome.destination),
            "the DRT linkage must change the output (the tail replaced the "
                + "gamma+colorout pair)")
    }

    // MARK: - 2: the HDR DRT E2E (the OQ-8-A clamp + the TIFF 32f face)

    func testHDRDrtExportClampsToUnitRangeThroughTIFFFloat32() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "DRTH_0001")
        try await writeSidecar(imageURL: source, records: await seedRecords())

        // TIFF 32f on the DRT档 = the DRT EOTF-ENCODED values as float32
        // (KD-2's semantic boundary — NOT the legacy linear-variant face).
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .tiff(bitDepth: .float32, compression: .none), colorSpace: .sRGB)
        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant, drtTail: hdrDrtTail(),
                directory: try makeLanding("hdr")),
            metal: metal, registry: registry)

        let values = try decodedFloatTIFFValues(outcome.destination)
        XCTAssertEqual(values.width, 48)
        XCTAssertEqual(values.height, 32)
        XCTAssertTrue(
            values.profile.contains("BT.2100"),
            "the embedded ICC is the PQ encoding profile (the system "
                + "kCGColorSpaceITUR_2100_PQ desc), got \(values.profile)")
        // AC5 / OQ-8-A: the quantizer's [0,1] clamp seals the HDR range.
        var minVal = Float.greatestFiniteMagnitude, maxVal = -Float.greatestFiniteMagnitude
        var sawNonZero = false
        for index in stride(from: 0, to: values.samples.count, by: 4) {
            for channel in 0..<3 {
                let v = values.samples[index + channel]
                minVal = Swift.min(minVal, v)
                maxVal = Swift.max(maxVal, v)
                if v > 0.01 { sawNonZero = true }
                XCTAssertTrue(
                    v.isFinite, "PQ-encoded samples must be finite")
            }
        }
        XCTAssertGreaterThanOrEqual(minVal, 0.0, "the clamp seals the low end")
        XCTAssertLessThanOrEqual(maxVal, 1.0, "the clamp seals the high end (HDR ≤ SDR white)")
        XCTAssertTrue(sawNonZero, "the plane is not degenerate black")
        XCTAssertLessThan(minVal, maxVal, "the plane carries content (not flat)")
    }

    // MARK: - 3: the queue delivery seam (KD-4)

    func testQueueDrtTailsCarrierDeliversToTheRender() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "DRTQ_0001")
        try await writeSidecar(imageURL: source, records: await seedRecords())

        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB)

        // The direct-render reference (the request field) — the SAME
        // synthetic decode leg the queue uses (only the delivery face may
        // differ, never the pixels).
        let reference = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant, drtTail: sdrDrtTail(),
                directory: try makeLanding("ref")),
            metal: metal, registry: registry,
            decodeLeg: { url in try await ExportDrtTailE2ETests.syntheticDecode(url: url) })

        // The queue face (the TaskLocal seam through the frozen leg
        // signature). The queue's decode leg mirrors the synthetic one.
        let queueDirectory = try makeLanding("queue")
        let queue = ExportQueue(
            metal: metal, registry: registry,
            decodeLeg: { url in try await ExportDrtTailE2ETests.syntheticDecode(url: url) })
        let snapshots = await queue.enqueue(
            images: [(url: source, relPath: "DRTQ_0001.png")],
            variants: [variant],
            destinationDirectory: queueDirectory,
            drtTails: [sdrDrtTail()])
        // Wait for the job to settle.
        let deadline = Date().addingTimeInterval(60)
        var settled = false
        while Date() < deadline {
            let progress = await queue.progress()
            if progress.done == 1, progress.total == 1, progress.activePhase == nil {
                settled = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(settled, "the DRT queue job must settle")
        let state = await queue.snapshots().first?.state
        guard case .done(let queuedURL)? = state else {
            return XCTFail("expected a done job, got \(String(describing: state))")
        }
        XCTAssertEqual(
            queuedURL.lastPathComponent, "DRTQ_0001.png",
            "the queued DRT job keeps the destination name")
        // The TaskLocal seam delivered the payload: the queued output is
        // byte-equal to the direct render with the same DRT tail.
        let queuedBytes = try Data(contentsOf: queuedURL)
        let referenceBytes = try Data(contentsOf: reference.destination)
        let queuedProfile = try decodedPNGValues(queuedURL).profile
        let referenceProfile = try decodedPNGValues(reference.destination).profile
        XCTAssertEqual(
            queuedProfile, referenceProfile,
            "the ICC faces must match first (the delivery-seam diagnostic)")
        let queuedPixels = try decodedPNGValues(queuedURL).bytes
        let referencePixels = try decodedPNGValues(reference.destination).bytes
        var maxDiff = 0
        for (a, b) in zip(queuedPixels, referencePixels) {
            maxDiff = max(maxDiff, abs(Int(a) - Int(b)))
        }
        XCTAssertEqual(
            maxDiff, 0,
            "pixel parity first (the delivery-seam diagnostic, max diff \(maxDiff))")
        // NOTE: FILE bytes are deliberately NOT compared across the two
        // ICC-bearing exports — ImageIO/ColorSync re-serializes a CUSTOM
        // embedded profile on write (observed: equal-length, early-offset
        // drift inside the iCCP chunk, timing-dependent). The seam proof is
        // the exact pixel parity + the profile identity above; the ICC
        // payload itself is pinned deterministic by DrtOutputColorSpaceTests.
        XCTAssertFalse(snapshots.isEmpty)
    }

    // MARK: - 4: the nil carrier (the zero path)

    func testNilCarrierRendersAreByteStable() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "DRTN_0001")
        try await writeSidecar(imageURL: source, records: await seedRecords())
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB)

        let first = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant, drtTail: nil,
                directory: try makeLanding("nil1")),
            metal: metal, registry: registry,
            decodeLeg: { url in try await ExportDrtTailE2ETests.syntheticDecode(url: url) })
        let second = try await ExportRenderer.render(
            request: ExportRenderer.Request(
                imageURL: source,
                destinationDirectory: try makeLanding("nil2"),
                occupiedNames: [],
                variant: variant),
            metal: metal, registry: registry,
            decodeLeg: { url in try await ExportDrtTailE2ETests.syntheticDecode(url: url) })
        XCTAssertEqual(
            try Data(contentsOf: first.destination),
            try Data(contentsOf: second.destination),
            "the nil carrier is the zero path — byte-stable across entry shapes")
    }

    // MARK: - 5: the tail-format float override (T3, KD-3 + checker E8)

    /// The seam's mechanism face: the display `.drt` tail keeps the EOTF
    /// family format (SDR → bgra8, HDR → 16F); the override pins EVERY
    /// tail plane to the working float32 face (the quantizer owns the
    /// clamp + the tiers). Default false — the display face untouched.
    func testTailFormatOverrideKeepsTheWorkingPlaneFloat32() async throws {
        try await makeRegistryReady()
        let image = try await Self.syntheticDecode(url: URL(fileURLWithPath: "/ignored.png"))
        let records = await registry.makeDefaultInstances()
        let (chain, _) = await registry.materializeBoxes(for: records)

        // Display face (override off): the EOTF family decides.
        let (sdrDisplay, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .export, cache: PipeCache(), metal: metal,
            terminalTail: .drt(sdrDrtTail()))
        XCTAssertEqual(sdrDisplay.pixelFormat, .bgra8Unorm,
                       "the display SDR tail is the bgra8 face (zero drift)")
        let (hdrDisplay, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .export, cache: PipeCache(), metal: metal,
            terminalTail: .drt(hdrDrtTail()))
        XCTAssertEqual(hdrDisplay.pixelFormat, .rgba16Float,
                       "the display HDR tail is the 16F face (zero drift)")

        // Export face (override on): ALWAYS the working float32 plane.
        let (sdrExport, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .export, cache: PipeCache(), metal: metal,
            terminalTail: .drt(sdrDrtTail()), tailFormatFloatOverride: true)
        XCTAssertEqual(sdrExport.pixelFormat, WorkingSpace.pixelFormat,
                       "the export SDR tail plane is float32, not bgra8")
        let (hdrExport, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .export, cache: PipeCache(), metal: metal,
            terminalTail: .drt(hdrDrtTail()), tailFormatFloatOverride: true)
        XCTAssertEqual(hdrExport.pixelFormat, WorkingSpace.pixelFormat,
                       "the export HDR tail plane is float32, not 16F")
    }

    /// Checker E8's composite-path bit-depth: the driver builds its OWN
    /// terminal pipe (it never crosses RenderPipeline's static entry), so
    /// the override must ride the driver's pass-through or the layered
    /// export (the M2常态) would keep the display-format tail.
    func testCompositeTailFormatOverrideReachesTheDriverPlane() async throws {
        try await makeRegistryReady()
        let image = try await Self.syntheticDecode(url: URL(fileURLWithPath: "/ignored.png"))
        let records = await registry.makeDefaultInstances()
        let (chain, _) = await registry.materializeBoxes(for: records)
        let layerStack = LayerStack(baseLayer: BackgroundLayer())

        // Without the override the terminal leg carries the display face.
        let (display, _) = try await RenderPipeline.processComposite(
            image: image, instances: chain, layerStack: layerStack,
            registry: registry, imageID: UUID(), resolution: .export,
            cache: PipeCache(), metal: metal, policy: .export,
            terminalTail: .drt(sdrDrtTail()))
        XCTAssertEqual(display.pixelFormat, .bgra8Unorm,
                       "the composite display tail is the bgra8 face (zero drift)")
        // With the override the driver's terminal plane is float32.
        let (overridden, _) = try await RenderPipeline.processComposite(
            image: image, instances: chain, layerStack: layerStack,
            registry: registry, imageID: UUID(), resolution: .export,
            cache: PipeCache(), metal: metal, policy: .export,
            terminalTail: .drt(sdrDrtTail()), tailFormatFloatOverride: true)
        XCTAssertEqual(overridden.pixelFormat, WorkingSpace.pixelFormat,
                       "the composite export tail plane is float32 (the E8 pass-through)")
    }

    /// The E2E bit-depth: a DRT-SDR export through TIFF 32f carries
    /// FULL-precision encoded values — NOT the 8-bit lattice the display
    /// tail's bgra8 plane would have quantized to (the float values are
    /// continuous; a bgra8 intermediate pins every sample to k/255).
    func testDrtExportSDRToTIFF32fIsFullPrecision() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "DRTF_0001")
        try await writeSidecar(imageURL: source, records: await seedRecords())
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .tiff(bitDepth: .float32, compression: .none), colorSpace: .sRGB)
        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant, drtTail: sdrDrtTail(),
                directory: try makeLanding("float")),
            metal: metal, registry: registry,
            decodeLeg: { url in try await ExportDrtTailE2ETests.syntheticDecode(url: url) })
        let values = try decodedFloatTIFFValues(outcome.destination)
        // Count samples OFF the 8-bit lattice (|v - k/255| > 1/1024 — half
        // the bgra8 quantization step). A float32 tail produces continuous
        // values; an 8-bit tail produces lattice-exact ones.
        var offLattice = 0
        for index in stride(from: 0, to: values.samples.count, by: 4) {
            for channel in 0..<3 {
                let v = Double(values.samples[index + channel])
                let lattice = (v * 255.0).rounded() / 255.0
                if abs(v - lattice) > 1.0 / 1024.0 { offLattice += 1 }
            }
        }
        XCTAssertGreaterThan(
            offLattice, 16,
            "the export tail plane is float32 — continuous values, not the "
                + "bgra8 lattice (off-lattice samples: \(offLattice))")
    }

    // MARK: - 6: yiyin × DRT coexistence (T4 — the E2 order at export)

    /// The yiyin variant AND the DRT carrier in one export: the印框 replays
    /// AFTER the EOTF encode (the pipe tail's assembly), so the canvas band
    /// is display-white — never tone-mapped — while the content IS PQ-
    /// encoded (an HDR record makes the two distinguishable: a tone-mapped
    /// band would sit at the PQ code of white, well below the raw 1.0 the
    /// post-EOTF paint produces), the canvas grew (borders margin), and the
    /// ICC is still the DRT encoding's profile (the印框 never enters the
    /// color face).
    func testYiyinDrtCoexistenceBandIsPostEOTFWhite() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "DRTY_0001")
        // The configured pair: a 50%-rate EXPANDING solid border (canvas ×2
        // width) + the neutral watermark carrier.
        var records = await seedRecords().filter {
            $0.opName != BordersModule.opName && $0.opName != WatermarkModule.opName
        }
        records.append(ModuleInstance(
            module: BordersModule.self,
            params: BordersModule.Params(
                mode: .solid(color: "#ffffff"), mainImageWidthRate: 50,
                miniTopBottomMargin: 0, aspectRatio: nil, landscapeOutput: false,
                cornerRadius: nil, shadow: nil, textBottomOffset: 0.027,
                adaptiveBackdrop: false)))
        records.append(ModuleInstance(
            module: WatermarkModule.self, params: WatermarkModule.Params.neutralSeed))
        records.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        // The DISK truth (the renderer reads the sidecar — a missing one
        // would export pristine and the印框 would never appear).
        try await writeSidecar(imageURL: source, records: records)

        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB, yiyin: true)
        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant, drtTail: hdrDrtTail(),
                directory: try makeLanding("yiyin")),
            metal: metal, registry: registry,
            decodeLeg: { url in try await ExportDrtTailE2ETests.syntheticDecode(url: url) },
            yiyinInjector: ExportYiyinInjector { boxes, injectedRecords, mainImageSize, capture in
                guard let watermarkBox = boxes.first(where: {
                    $0.opName == WatermarkModule.opName
                }) as? ModuleBox<WatermarkModule> else { return }
                let bordersParams = try? injectedRecords
                    .first { $0.opName == BordersModule.opName }?
                    .params(of: BordersModule.self)
                let watermark = watermarkBox.module
                watermark.captureExif = capture
                watermark.jointContext = WatermarkModule.JointContext(
                    mainImageSize: mainImageSize, bordersParams: bordersParams)
                let record = watermark.makeJointLayoutRecord(
                    mainImageSize: mainImageSize, bordersParams: bordersParams)
                if let bordersBox = boxes.first(where: {
                    $0.opName == BordersModule.opName
                }) as? ModuleBox<BordersModule> {
                    bordersBox.module.jointLayoutOverride = record
                }
            })

        // The canvas grew (the borders margin rode the tail replay — the
        // entry plane was 48×32; the 50% rate doubles the width).
        XCTAssertGreaterThan(outcome.outputWidth, 48, "the canvas grew in the tail")
        let values = try decodedPNGValues(outcome.destination)
        XCTAssertEqual(values.width, outcome.outputWidth)
        XCTAssertEqual(values.height, outcome.outputHeight)
        XCTAssertTrue(
            values.profile.contains("BT.2100"),
            "the ICC stays the DRT encoding — the印框 never enters the color "
                + "face, got \(values.profile)")

        // The E2 outcome guard: the LEFT band column is display-white (the
        // borders painted AFTER the PQ encode — a tone-mapped white would
        // sit at its PQ code, well below the raw 1.0 the paint produces,
        // then clamped to the PNG's 255), while the content center is
        // PQ-encoded (well below the painted white).
        func sample(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * values.width + x) * 4
            return (Int(values.bytes[i]), Int(values.bytes[i + 1]), Int(values.bytes[i + 2]))
        }
        let band = sample(2, values.height / 2)
        XCTAssertGreaterThan(
            band.r, 250,
            "the canvas band is display-white (post-EOTF paint, never tone-mapped)")
        let content = sample(values.width / 2, values.height / 2)
        XCTAssertLessThan(
            content.r, 250,
            "the content side stayed PQ-encoded (the tail replaced the "
                + "gamma+colorout pair)")
    }
}
