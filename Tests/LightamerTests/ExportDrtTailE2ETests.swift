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
        XCTAssertEqual(
            queuedBytes, referenceBytes,
            "the queue's drtTails carrier must render identically to the "
                + "direct request field (the frozen-leg delivery seam)")
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
}
