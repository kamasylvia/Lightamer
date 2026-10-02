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
// ExportNamingE2ETests (Plan M2-9-03 T1 — EXPORT bundle) — the template-driven
// naming leg through the REAL render/encode chain:
//
//   1. Template render E2E: the pattern evaluates INSIDE renderStage against
//      the decoded capture facts + the disk sidecar's rating + the batch
//      sequence (KD-2), and the rendered stem lands on disk.
//   2. The three collision tiers (OQ-5): FAIL = typed job failure with zero
//      files, REPLACE = overwrite, INCREMENT = the historic face.
//   3. The subfolder seam (OQ-11): the join happens before the render, the
//      directory is created typed-fail-fast, and occupancy enumerates INSIDE
//      it.
//   4. The E6 DPI consumption (checker 回注): a capped physical export lands
//      the cap-corrected DPI in the product metadata (the physical print
//      size conserved).
// ─────────────────────────────────────────────────────────────────────────────

final class ExportNamingE2ETests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("export-naming-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Harness

    private func makeRegistryReady() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    /// A synthetic gradient PNG source (the DrtTailE2E shape).
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

    /// Persist a sidecar with a rating (the template's `{rating}` face source).
    private func writeSidecar(imageURL: URL, rating: Int?) throws {
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 0,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0),
            appVersion: "0.4.0-naming-e2e",
            rating: rating)
        let data = try JSONEncoder().encode(document)
        try data.write(to: LightamerSidecar.sidecarURL(for: imageURL))
    }

    /// The synthetic decode leg with INJECTED capture facts (the template's
    /// context material — no RAW decode, deterministic extents).
    private nonisolated static func syntheticDecode(
        url: URL, size: SIMD2<Int> = SIMD2(96, 64),
        capture: CaptureMetadata = CaptureMetadata()
    ) async throws -> DecodedImage {
        let width = size.x, height = size.y
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i + 0] = Float(x) / Float(max(width - 1, 1)) * 0.8
                rgba[i + 1] = Float(y) / Float(max(height - 1, 1)) * 0.6
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
            rawTech: RAWTechnicalParams(), capture: capture,
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// A fresh landing directory (the source PNG shares the temp root, so a
    /// landing never sees the source's name as occupancy).
    private func makeLanding(_ label: String) throws -> URL {
        let directory = tempDirectory.appendingPathComponent(
            "landing-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeRequest(
        source: URL, variant: ExportVariant, directory: URL,
        naming: ExportNamingRequest? = nil,
        collisionPolicy: ExportNamer.ExportCollisionPolicy = .increment,
        subfolder: String? = nil,
        occupiedNames: Set<String> = []
    ) -> ExportRenderer.Request {
        ExportRenderer.Request(
            imageURL: source,
            destinationDirectory: directory,
            occupiedNames: occupiedNames,
            variant: variant,
            naming: naming,
            collisionPolicy: collisionPolicy,
            subfolder: subfolder)
    }

    /// Wait until `count` jobs settle; returns the snapshots.
    @discardableResult
    private func waitSettled(_ queue: ExportQueue, count: Int) async throws -> [ExportJobSnapshot] {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let progress = await queue.progress()
            if progress.done == count, progress.total == count, progress.activePhase == nil {
                return await queue.snapshots()
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await queue.snapshots()
    }

    /// The product file names in a directory (sorted; dirs excluded).
    private func fileNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { name in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(name).path, isDirectory: &isDir)
                return !isDir.boolValue
            }
            .sorted()
    }

    /// The product's DPI metadata (the E6 face).
    private func dpiValues(_ url: URL) throws -> (width: Double, height: Double) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let w = props[kCGImagePropertyDPIWidth] as? Double ?? -1
        let h = props[kCGImagePropertyDPIHeight] as? Double ?? -1
        return (w, h)
    }

    private var pngVariant: ExportVariant {
        ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB)
    }

    // MARK: - 1: the template render face (KD-2 context material)

    /// A field-sampling pattern (12 faces sampled: source/date/make/model/
    /// lens/iso/aperture/shutter/focal/rating + literals) lands its rendered,
    /// sanitized stem. Absent faces render empty — the assertion pins the
    /// exact surviving face set for the injected capture.
    func testTemplateRenderedNameLandsFromDecodeCaptureAndSidecarRating() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "NAM_0001")
        try writeSidecar(imageURL: source, rating: 4)
        var injectedCapture = CaptureMetadata()
        injectedCapture.cameraModel = "TestCam R1"
        injectedCapture.iso = 800
        injectedCapture.aperture = 2.8
        injectedCapture.shutterSpeed = 1.0 / 500.0
        injectedCapture.focalLength = 50.0
        injectedCapture.lensModel = "Test 50mm"
        injectedCapture.captureTime = Date(timeIntervalSince1970: 1_761_235_200) // 2025-10-24 UTC
        let capture = injectedCapture

        let variant = pngVariant
        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant,
                directory: try makeLanding("tmpl"),
                naming: ExportNamingRequest(
                    pattern: "{cameramodel}_{iso}_{shutter}_{focal}_{rating}_{source}")),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url, capture: capture)
            })

        // cam model / iso / shutter (1-500) / focal (50.0mm) / rating (4)
        // / source stem, joined by the pattern's literal underscores.
        XCTAssertEqual(
            outcome.destination.lastPathComponent,
            "TestCam R1_800_1-500_50.0mm_4_NAM_0001.png")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outcome.destination.path))
    }

    /// An all-empty render falls back (Alcedo hpp:93) — the default "image"
    /// stem and a caller-supplied fallbackStem.
    func testEmptyRenderFallsBackToStem() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "FB_0001")

        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: pngVariant,
                directory: try makeLanding("fb1"),
                naming: ExportNamingRequest(pattern: "{iso}")),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        XCTAssertEqual(outcome.destination.lastPathComponent, "image.png")

        let custom = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: pngVariant,
                directory: try makeLanding("fb2"),
                naming: ExportNamingRequest(pattern: "{aperture}", fallbackStem: "job")),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        XCTAssertEqual(custom.destination.lastPathComponent, "job.png")
    }

    /// The queue stamps the batch ordinal: sequence increments ACROSS images
    /// and is SHARED by every variant of one image (OQ-4). Without tags the
    /// two formats' extensions keep the products apart.
    func testSequenceIncrementsAcrossBatchSharedAcrossVariants() async throws {
        try await makeRegistryReady()
        let sourceA = try writePNG(width: 96, height: 64, stem: "SEQ_A")
        let sourceB = try writePNG(width: 96, height: 64, stem: "SEQ_B")

        let jpegVariant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .jpeg(quality: 0.9), colorSpace: .sRGB)
        let directory = try makeLanding("seq")
        let queue = ExportQueue(
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        _ = await queue.enqueue(
            images: [(url: sourceA, relPath: "SEQ_A.png"), (url: sourceB, relPath: "SEQ_B.png")],
            variants: [pngVariant, jpegVariant],
            destinationDirectory: directory,
            naming: ExportNamingRequest(pattern: "frame{sequence:0000}"))
        _ = try await waitSettled(queue, count: 4)

        XCTAssertEqual(
            try fileNames(in: directory).sorted(),
            ["frame0001.jpg", "frame0001.png", "frame0002.jpg", "frame0002.png"],
            "the sequence is the IMAGE ordinal (1,1,2,2) — shared across variants")
    }

    /// The tag face survives the template path: two variants of the SAME
    /// template (no sequence) never overwrite each other.
    func testTagCoexistenceSameTemplateMultiVariant() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "TAG_0001")
        let jpegVariant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .jpeg(quality: 0.9), colorSpace: .sRGB, outputTag: "small")
        let pngTagged = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB, outputTag: "lossless")

        let directory = try makeLanding("tags")
        _ = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: jpegVariant, directory: directory,
                naming: ExportNamingRequest(pattern: "{source}")),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        _ = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: pngTagged, directory: directory,
                naming: ExportNamingRequest(pattern: "{source}")),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        XCTAssertEqual(
            try fileNames(in: directory),
            ["TAG_0001_lossless.png", "TAG_0001_small.jpg"],
            "the tag face keeps multi-variant batches collision-free")
    }

    // MARK: - 2: the collision tiers (OQ-5)

    /// FAIL: the renderer throws the typed error and NOTHING lands.
    func testFailPolicyThrowsTypedAndWritesNothing() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "FAIL_0001")
        let directory = try makeLanding("fail")

        do {
            _ = try await ExportRenderer.render(
                request: makeRequest(
                    source: source, variant: pngVariant, directory: directory,
                    naming: ExportNamingRequest(pattern: "{source}"),
                    collisionPolicy: .fail,
                    occupiedNames: ["FAIL_0001.png"]),
                metal: metal, registry: registry,
                decodeLeg: { url in
                    try await ExportNamingE2ETests.syntheticDecode(url: url)
                })
            XCTFail("expected BaseNameOccupiedError")
        } catch let error as ExportNamer.BaseNameOccupiedError {
            XCTAssertEqual(error.name, "FAIL_0001.png")
        }
        XCTAssertEqual(
            try fileNames(in: directory), [],
            "a FAIL-tier refusal leaves the landing zone empty")
    }

    /// FAIL through the QUEUE: the job settles `.failed` (the queue wraps
    /// the non-AppError into its typed encodeFailed face) and the batch's
    /// earlier jobs keep their files.
    func testFailPolicyFailsQueueJobWithoutWriting() async throws {
        try await makeRegistryReady()
        // The SAME source twice with a no-sequence template: the first job
        // lands the name, the second job's FAIL tier must refuse it.
        let source = try writePNG(width: 96, height: 64, stem: "DUP_0001")
        let directory = try makeLanding("failq")
        let queue = ExportQueue(
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        _ = await queue.enqueue(
            images: [(url: source, relPath: "DUP_0001.png"), (url: source, relPath: "DUP_0001.png")],
            variants: [pngVariant],
            destinationDirectory: directory,
            naming: ExportNamingRequest(pattern: "{source}"),
            collisionPolicy: .fail)
        let snapshots = try await waitSettled(queue, count: 2)

        var doneCount = 0
        var failedCount = 0
        for snapshot in snapshots {
            switch snapshot.state {
            case .done: doneCount += 1
            case .failed(let error):
                failedCount += 1
                XCTAssertTrue(
                    String(describing: error).contains("DUP_0001"),
                    "the typed occupancy error surfaces in the job's failure: \(error)")
            default: XCTFail("unexpected terminal state \(snapshot.state)")
            }
        }
        XCTAssertEqual(doneCount, 1, "the first job wins the name")
        XCTAssertEqual(failedCount, 1, "the second job FAILs loudly")
        XCTAssertEqual(
            try fileNames(in: directory), ["DUP_0001.png"],
            "exactly one product landed — no silent -N fan-out")
    }

    /// REPLACE: the occupied name is returned as-is and the product
    /// overwrites it.
    func testReplacePolicyOverwritesExistingProduct() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "REPL_0001")
        let directory = try makeLanding("replace")
        let stale = directory.appendingPathComponent("REPL_0001.png")
        // A STALE product with known-different bytes (flat red).
        var red = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for i in stride(from: 0, to: red.count, by: 4) { red[i] = 255; red[i + 3] = 255 }
        _ = try PNGEncoder().encode(ExportEncodeRequest(
            plane: ExportQuantizedPlane(
                data: Data(red), width: 8, height: 8, layout: .rgba8),
            spec: .png(bitDepth: .eight),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: stale))
        let staleBytes = try Data(contentsOf: stale)

        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: pngVariant, directory: directory,
                naming: ExportNamingRequest(pattern: "{source}"),
                collisionPolicy: .replace,
                occupiedNames: ["REPL_0001.png"]),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        XCTAssertEqual(outcome.destination.lastPathComponent, "REPL_0001.png")
        let freshBytes = try Data(contentsOf: stale)
        XCTAssertNotEqual(freshBytes, staleBytes, "the product replaced the stale file")
    }

    /// INCREMENT: the historic `-1` face through the template path (the
    /// default tier is behavior-identical to the legacy naming).
    func testIncrementPolicyKeepsHistoricFace() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "INC_0001")
        let directory = try makeLanding("increment")

        let first = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: pngVariant, directory: directory,
                naming: ExportNamingRequest(pattern: "{source}"),
                occupiedNames: []),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        XCTAssertEqual(first.destination.lastPathComponent, "INC_0001.png")
        let second = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: pngVariant, directory: directory,
                naming: ExportNamingRequest(pattern: "{source}"),
                occupiedNames: [source.lastPathComponent, "INC_0001.png"]),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        XCTAssertEqual(second.destination.lastPathComponent, "INC_0001-1.png")
    }

    /// The LEGACY dispatch: `naming == nil` ignores the tier — the byte-
    /// frozen stem+tag increment face (KD-1's anchor).
    func testNilNamingIgnoresCollisionPolicy() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "LGC_0001")
        let directory = try makeLanding("legacy")

        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: pngVariant, directory: directory,
                naming: nil,
                collisionPolicy: .fail,
                occupiedNames: ["LGC_0001.png"]),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        XCTAssertEqual(
            outcome.destination.lastPathComponent, "LGC_0001-1.png",
            "the legacy path keeps the increment face regardless of the tier")
    }

    // MARK: - 3: the subfolder seam (OQ-11)

    /// The subdirectory is created BEFORE the render and the occupancy
    /// enumerates INSIDE it (a same-template rerun increments within the
    /// subdirectory, not against the base).
    func testSubfolderJoinCreatesDirectoryAndEnumeratesInside() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "SUB_0001")
        let base = try makeLanding("sub-base")

        let queue = ExportQueue(
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(url: url)
            })
        _ = await queue.enqueue(
            images: [(url: source, relPath: "SUB_0001.png")],
            variants: [pngVariant],
            destinationDirectory: base,
            naming: ExportNamingRequest(pattern: "{source}"),
            subfolder: "Processed")
        _ = try await waitSettled(queue, count: 1)

        let subdirectory = base.appendingPathComponent("Processed", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: subdirectory.path),
            "the subdirectory was created before the render")
        XCTAssertEqual(try fileNames(in: subdirectory), ["SUB_0001.png"])
        XCTAssertEqual(try fileNames(in: base), [],
                       "no FILES land in the base itself (only the subdirectory)")

        // The rerun must see the first product (occupancy enumerated inside
        // the joined directory) → the increment lands in the SUBDIRECTORY.
        _ = await queue.enqueue(
            images: [(url: source, relPath: "SUB_0001.png")],
            variants: [pngVariant],
            destinationDirectory: base,
            naming: ExportNamingRequest(pattern: "{source}"),
            subfolder: "Processed")
        _ = try await waitSettled(queue, count: 2)
        XCTAssertEqual(
            try fileNames(in: subdirectory).sorted(),
            ["SUB_0001-1.png", "SUB_0001.png"],
            "the second job enumerated the subdirectory's occupancy")
    }

    // MARK: - 4: the E6 DPI consumption (checker 回注)

    /// Physical 10in × 6.6̄in @300dpi of a 3072×2048 source resolves
    /// 3000×2000; the 2000px cap re-fits to 2000×1333 and corrects the DPI
    /// by the width ratio (300 × 2000/3000 = 200). The PRODUCT metadata must
    /// carry 200 — the D-6 physical-print-size conservation, previously
    /// dropping the uncorrected 300 (E6's gap).
    func testCappedPhysicalExportLandsCorrectedDPI() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "DPI_0001")
        let variant = ExportVariant(
            sizing: YiyinExportSettings(
                mode: .physical(width: 10, height: 20.0 / 3.0, unit: .inches, dpi: 300),
                maximumEdgePixels: 2000),
            format: .jpeg(quality: 0.9), colorSpace: .sRGB)

        let outcome = try await ExportRenderer.render(
            request: makeRequest(
                source: source, variant: variant,
                directory: try makeLanding("dpi")),
            metal: metal, registry: registry,
            decodeLeg: { url in
                try await ExportNamingE2ETests.syntheticDecode(
                    url: url, size: SIMD2(3072, 2048))
            })
        XCTAssertEqual(outcome.outputWidth, 2000, "the cap re-fit the long edge")
        XCTAssertEqual(outcome.outputHeight, 1333)
        let dpi = try dpiValues(outcome.destination)
        XCTAssertEqual(dpi.width, 200, accuracy: 0.5,
                       "the width-ratio-corrected DPI must reach the product")
        XCTAssertEqual(dpi.height, 200, accuracy: 0.5)
    }
}
