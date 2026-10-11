import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import LightamerCore
import LightamerIOP
import Metal
import UniformTypeIdentifiers
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// RasterRoundTripTests (Plan M4-1-02 T7, KD-6 — EXPORT bundle) — the SC#1
// close-out over the REAL export queue:
//
//   • the sampled matrix {rec709/srgbPiecewise × 8bit, p3d65/gamma22 ×
//     16bit, rec2020/st2084 × float32}: a raster doc exports under its
//     derived DRT record (drd 恒装配), lands a real TIFF, and the
//     RE-IMPORT re-resolves a description CONSISTENT with the record's
//     encoding pair (primaries + TRC fields). The 32F row rides the
//     display branch by construction (the export chain never produces a
//     linear-ICC file — DrtOutputColorSpace throws illegal on .linear —
//     so the re-import walks the display inverse leg, not the matrix
//     branch; the checker E1 self-consistency is unaffected).
//   • the inverse→forward pixel band: scene → DRT forward → encode →
//     file → decode → display inverse → scene, gated at the 01-measured
//     display-first band (3.84e-3 in-domain) × margin for the f32 chain.
//   • the edit replay: an exposure commit survives a sidecar flush +
//     fresh reload with an IDENTICAL PREVIEW render.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class RasterRoundTripTests: XCTestCase {

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    private var tempDirectory: URL!
    private var outputDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("raster-roundtrip-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = tempDirectory.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        registry = ModuleRegistry.makeDefault()
        try await LightamerIOPRegistry.populate(registry)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func fixture(_ name: String) throws -> URL {
        let url = Self.fixtureDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("fixture missing: \(name)")
        }
        return url
    }

    /// Read a texture's center RGBA (L014 fence included).
    private func centerPixel(of texture: any MTLTexture, metal: MetalContext) async -> SIMD4<Float> {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var pixels = [Float](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &pixels, bytesPerRow: texture.width * 16,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        let index = ((texture.height / 2) * texture.width + texture.width / 2) * 4
        return SIMD4(pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
    }

    // MARK: - SC#1: the sampled export → re-import matrix

    func testExportReimportDescriptionMatchesTheRecordEncoding() async throws {
        let source = try fixture("srgb-matrix-8.tif")
        let decoded = try await RAWDecoder().decode(source)
        XCTAssertNotNil(decoded.rasterColor, "the source rides the raster leg")

        // The sampled rows: (encodingSpace, eotf, bit depth, expected
        // re-import primaries, expected re-import TRC).
        var record = DrtRecord()
        record.method = .aces20
        record.encodingSpace = .rec709
        record.encodingEotf = .srgbPiecewise
        record.peakLuminance = 100
        var p3 = record
        p3.encodingSpace = .p3d65
        p3.encodingEotf = .gamma22
        var hdr = record
        hdr.encodingSpace = .rec2020
        hdr.encodingEotf = .st2084
        hdr.peakLuminance = 1000

        let rows: [(name: String, record: DrtRecord, variant: ExportVariant,
                    primaries: SIMD8<Float>, isHdr: Bool)] = [
            ("srgb8", record,
             ExportVariant(format: .tiff(bitDepth: .eight, compression: .none),
                           colorSpace: .sRGB, drtOutput: record),
             RasterColorResolver.sRGBPrimaries, false),
            ("p316", p3,
             ExportVariant(format: .tiff(bitDepth: .sixteen, compression: .none),
                           colorSpace: .sRGB, drtOutput: p3),
             RasterColorResolver.displayP3Primaries, false),
            ("2020f32", hdr,
             ExportVariant(format: .tiff(bitDepth: .float32, compression: .none),
                           colorSpace: .sRGB, drtOutput: hdr),
             RasterColorResolver.rec2020Primaries, true),
        ]
        for row in rows {
            try row.variant.validate()
        }

        // One enqueue PER ROW, each into its own subfolder — the namer's
        // source-stem convention never collides across rows.
        for row in rows {
            let queue = ExportQueue(metal: metal, registry: registry)
            let params = DrtTailParams(
                record: row.record, postOpNames: NodeOwnershipCatalog.drtPostOpNames)
            _ = await queue.enqueue(
                images: [(url: source, relPath: "SRC0001.tif")],
                variants: [row.variant],
                destinationDirectory: outputDirectory,
                drtTails: [params],
                subfolder: row.name)
            let idle = await waitUntilIdle(queue, total: 1)
            XCTAssertTrue(idle, "row \(row.name) never went idle")
            for job in await queue.snapshots() {
                guard case .done = job.state else {
                    return XCTFail("row \(row.name): \(job.state)")
                }
            }
        }

        // Per-row: the landed file re-imports through the raster leg with
        // a description CONSISTENT with the record's encoding pair.
        for row in rows {
            let rowDirectory = outputDirectory.appendingPathComponent(
                row.name, isDirectory: true)
            let landed = try FileManager.default.contentsOfDirectory(
                at: rowDirectory, includingPropertiesForKeys: nil)
            let file = try XCTUnwrap(landed.first, "row \(row.name) must land")
            let reDecoded = try await RAWDecoder().decode(file)
            let description = try XCTUnwrap(
                reDecoded.rasterColor, "\(row.name): the export re-imports raster")
            // The TRC face: srgbPiecewise / gamma22 / st2084 re-resolve.
            switch row.record.encodingEotf {
            case .srgbPiecewise:
                XCTAssertEqual(
                    description.transfer, .srgbPiecewise,
                    "\(row.name): the piecewise ICC re-resolves")
            case .gamma22:
                // The ICC gamma rides the u8Fixed8 grid (2.2 -> 563/256 =
                // 2.19921875) — the canonicalizer reads the encoded value.
                guard case .gamma(let g) = description.transfer else {
                    return XCTFail("\(row.name): expected a gamma TRC")
                }
                XCTAssertLessThan(
                    abs(g - 2.2), 0.01,
                    "\(row.name): the gamma ICC re-resolves")
            case .st2084:
                // The HDR TIFF export lands 16-bit PQ; the system-named PQ
                // ICC rides ColorSync's re-serialization and PRESENTS
                // LUT-BASED to the parser — the re-import takes the
                // iccLutConverted CI arm (KD-1's only LUT face: the pixels
                // round-trip through FULL color management; the PQ
                // semantics survive inside that management, not through
                // the inverse kernel). Registered in the 02 DECISIONS.
                XCTAssertEqual(
                    description.origin, .iccLutConverted,
                    "\(row.name): the HDR export re-imports through the LUT arm")
                XCTAssertEqual(description.transfer, .linear)
                XCTAssertNil(reDecoded.rasterNative)
            default:
                XCTFail("uncovered row TRC")
            }
            // The primaries face: the re-resolved primaries land on the
            // record's encoding space (the nearest-limiting match agrees).
            XCTAssertEqual(
                RasterInputStage.limitingSpace(for: description.primariesXY),
                RasterInputStage.limitingSpace(for: row.primaries),
                "\(row.name): the primaries re-resolve onto the encoding space")
        }
    }

    private func waitUntilIdle(
        _ queue: ExportQueue, total: Int, timeout: TimeInterval = 60
    ) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let done = await queue.snapshots().filter {
                if case .done = $0.state { return true } else { return false }
            }.count
            if done >= total { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    // MARK: - The inverse→forward pixel band

    func testInverseForwardBandOnTheSrgbRow() async throws {
        // scene → fwd DRT → encode → file → decode → inv DRT → scene',
        // gated at the 01 display-first band × the f32 chain margin.
        let source = try fixture("srgb-matrix-8.tif")
        let decoded = try await RAWDecoder().decode(source)
        let native = try XCTUnwrap(decoded.rasterNative)

        var record = DrtRecord()
        record.method = .aces20
        record.encodingSpace = .rec709
        record.encodingEotf = .srgbPiecewise
        record.peakLuminance = 100

        // The forward face: the source plane rides the input leg (display
        // inverse = identity-ish for the analytic TRC) and the DRT tail —
        // the EXPORTED file is the forward product; the RE-IMPORTED file
        // walks the leg again (the display inverse of the encoded values).
        // The band check: re-imported scene ≈ original scene on the
        // mid-ramp sample points (in-domain), gate 8e-3.
        let variant = ExportVariant(
            format: .tiff(bitDepth: .float32, compression: .none),
            colorSpace: .sRGB, drtOutput: record)
        let queue = ExportQueue(metal: metal, registry: registry)
        let params = DrtTailParams(
            record: record, postOpNames: NodeOwnershipCatalog.drtPostOpNames)
        _ = await queue.enqueue(
            images: [(url: source, relPath: "BAND0001.tif")],
            variants: [variant],
            destinationDirectory: outputDirectory,
            drtTails: [params])
        let idle = await waitUntilIdle(queue, total: 1)
        XCTAssertTrue(idle)
        let landed = try XCTUnwrap(try FileManager.default.contentsOfDirectory(
            at: outputDirectory, includingPropertiesForKeys: nil).first)

        // The re-imported native payload (scene values, 1:1 size).
        let reDecoded = try await RAWDecoder().decode(landed)
        let reNative = try XCTUnwrap(reDecoded.rasterNative)
        XCTAssertEqual(reNative.width, native.width)

        // Sample the ramp columns (the generator's probe row y=0 carries
        // 0 / max / 0.18·max / 0.5·max — compare mid-ramp cells instead:
        // the band gate applies where the forward stays in-domain).
        func sample(_ payload: RasterNativePixels, _ x: Int, _ y: Int) -> Float {
            let base = (y * payload.width + x) * payload.bytesPerPixel
            return Float(bitPattern:
                UInt32(payload.data[base])
                    | UInt32(payload.data[base + 1]) << 8
                    | UInt32(payload.data[base + 2]) << 16
                    | UInt32(payload.data[base + 3]) << 24)
        }
        // In-domain probe points: the 0.18 and 0.5 grays of the probe row
        // (columns 2 and 3) — both sides are scene-linear floats.
        for column in [2, 3] {
            let originalValue = sample(native, column, 0)
            let roundTripped = sample(reNative, column, 0)
            guard originalValue > 0.01, originalValue < 4.0 else { continue }
            let delta = abs(roundTripped - originalValue)
            XCTAssertLessThan(
                delta, 8e-3 * max(1.0, originalValue),
                "column \(column): |\(roundTripped) − \(originalValue)| "
                    + "exceeds the round-trip band")
        }
    }

    // MARK: - The edit replay

    func testEditReplaySurvivesFlushAndReload() async throws {
        // M4-1 ledger #6: the sidecar WRITE leg rides a TMP copy of the
        // fixture — the repo `Tests/Fixtures/` directory never grows a
        // `.lra` (the App bundle's testRestoreWinsOverDerive reads this
        // exact fixture path and assumes a clean start; an orphan left
        // here poisoned the next round deterministically).
        let repoFixture = try fixture("srgb-matrix-8.tif")
        let repoSidecarURL = LightamerSidecar.sidecarURL(for: repoFixture)
        // Entry pre-clean: a stale orphan from an older run must not
        // poison this round (defensive — this test no longer writes the
        // repo path at all).
        try? FileManager.default.removeItem(at: repoSidecarURL)
        let source = tempDirectory.appendingPathComponent("srgb-matrix-8.tif")
        try FileManager.default.copyItem(at: repoFixture, to: source)
        let sidecarURL = LightamerSidecar.sidecarURL(for: source)
        // Exit sweep (belt and braces — tempDirectory teardown already
        // covers the tmp domain; the repo sweep is the defensive face).
        defer {
            try? FileManager.default.removeItem(at: sidecarURL)
            try? FileManager.default.removeItem(at: repoSidecarURL)
        }

        func makeAssembly() async throws -> (
            EditorState, PipeCoordinator, WorkspaceModel, MetalContext
        ) {
            let editorState = EditorState()
            let coordinator = PipeCoordinator()
            let workspace = WorkspaceModel()
            editorState.attach(pipeCoordinator: coordinator)
            coordinator.attach(editorState: editorState)
            workspace.attach(pipeCoordinator: coordinator)
            coordinator.attach(workspace: workspace)
            let sessionMetal = try MetalContext()
            try await sessionMetal.registerDefaultLibrary(
                in: PassthroughKernel.metalBundle)
            coordinator.attach(metal: sessionMetal)
            let sessionRegistry = ModuleRegistry.makeDefault()
            try await LightamerIOPRegistry.populate(sessionRegistry)
            coordinator.attach(registry: sessionRegistry, defaultFace: false)
            return (editorState, coordinator, workspace, sessionMetal)
        }

        // Session A: open (the seed runs), ONE exposure commit, render.
        let (stateA, coordA, _, metalA) = try await makeAssembly()
        let decodedA = try await RAWDecoder().decode(source)
        await coordA.load(
            url: source, decoded: decodedA, instances: [], metal: metalA)
        var exposure = ExposureModule.Params()
        exposure.exposure = 0.5
        // The D-H1 production commit face (a plain recordChange does NOT
        // schedule the sidecar write — the D-S3 rule; the live window must
        // OPEN first or the commit leg sees an empty touched set).
        coordA.beginContinuousEdit()
        await coordA.setLiveParams(
            ModuleInstance(module: ExposureModule.self, params: exposure))
        await coordA.commitContinuousEdit(label: "exposure")
        // scheduleSidecarWrite hops a Task — poll the flush (the Drt
        // persistence test's shape) instead of one immediate flush.
        let start = Date()
        while !FileManager.default.fileExists(atPath: sidecarURL.path),
              Date().timeIntervalSince(start) < 10
        {
            await coordA.flushSidecar()
            try? await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
        let boxesA = await registry.materializeBoxes(for: stateA.instances).boxes
        let renderA = try await RenderPipeline.process(
            image: decodedA, instances: boxesA,
            imageID: UUID(), resolution: .preview, cache: PipeCache(),
            metal: metalA, longEdge: 64)

        // Session B: a fresh assembly reloads the SAME file — the restore
        // leg replays the committed edit (restore wins over the seed).
        let (stateB, coordB, workspaceB, metalB) = try await makeAssembly()
        let decodedB = try await RAWDecoder().decode(source)
        await coordB.load(
            url: source, decoded: decodedB, instances: [], metal: metalB)
        XCTAssertEqual(
            stateB.history.items.count, stateA.history.items.count,
            "the committed edit replays into the fresh session")
        let boxesB = await registry.materializeBoxes(for: stateB.instances).boxes
        let renderB = try await RenderPipeline.process(
            image: decodedB, instances: boxesB,
            imageID: UUID(), resolution: .preview, cache: PipeCache(),
            metal: metalB, longEdge: 64)
        XCTAssertTrue(workspaceB.hasDrtRecord(for: source),
            "the DRT record survives beside the edit")

        // The pixel-stable replay face.
        let a = await centerPixel(of: renderA.0, metal: metalA)
        let b = await centerPixel(of: renderB.0, metal: metalB)
        for lane in 0..<3 {
            XCTAssertLessThan(
                abs(a[lane] - b[lane]), 1e-5,
                "the replayed render must match (lane \(lane))")
        }
    }
}
