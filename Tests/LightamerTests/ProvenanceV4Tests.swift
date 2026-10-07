@testable import Lightamer
@testable import LightamerCore
import CoreGraphics
import ImageIO
import LightamerIOP
import UniformTypeIdentifiers
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ProvenanceV4Tests (Plan 08-1 T5/T6) — the product-landing face (T5):
// the ExportNamer collision increment through the REAL production merge
// leg, the grid-visibility three-row alignment (research §3.1), and the
// zero-new-mechanism E2E (product → grid → decode → editable sidecar);
// and the provenance face (T6): the sidecar v4 round-trip, the v3
// zero-harm read, the source-drift dirty marking, and the replay
// idempotence.
// ─────────────────────────────────────────────────────────────────────────────

final class ProvenanceV4Tests: XCTestCase {

    // MARK: - Synthetic bracket fixtures (the REAL production-leg inputs)

    /// Write one synthetic float-TIFF source: a 64×64 gray field at the
    /// given exposure (pixel = L × t), through the PRODUCT writer itself
    /// (the round-trip band is the production path's own).
    private func writeSource(
        directory: URL, name: String, luminance: Float, exposure: Float
    ) throws -> URL {
        let width = 64, height = 64
        var plane = [Float](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: plane.count, by: 4) {
            let value = luminance * exposure
            plane[index] = value
            plane[index + 1] = value
            plane[index + 2] = value
            plane[index + 3] = 1
        }
        let url = directory.appendingPathComponent(name)
        try BandStreamer.writeFloatTIFF(plane, width: width, height: height, to: url)
        return url
    }

    /// A throwaway session root with a 3-source bracket.
    private func makeSession() throws -> (root: URL, sources: [URL]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-session-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        // A recognizable stem → the product lands as <stem>_hdr.tif.
        let sources = [
            try writeSource(directory: root, name: "DSC00001.NEF",
                luminance: 0.5, exposure: 0.25),
            try writeSource(directory: root, name: "DSC00002.NEF",
                luminance: 0.5, exposure: 1.0),
            try writeSource(directory: root, name: "DSC00003.NEF",
                luminance: 0.5, exposure: 2.0),
        ]
        return (root, sources)
    }

    /// Write one synthetic float-TIFF source WITH real shutter EXIF (the
    /// same plane shape as `writeSource`, plus the TIFF/EXIF dictionaries
    /// the ImageIO walk reads) — the EXIF-precheck leg's E2E fixture.
    private func writeSourceWithEXIF(
        directory: URL, name: String, luminance: Float, exposure: Float,
        shutterSeconds: Double
    ) throws -> URL {
        let width = 64, height = 64
        var plane = [Float](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: plane.count, by: 4) {
            let value = luminance * exposure
            plane[index] = value
            plane[index + 1] = value
            plane[index + 2] = value
            plane[index + 3] = 1
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        let provider = try XCTUnwrap(CGDataProvider(
            data: plane.withUnsafeBufferPointer { Data(buffer: $0) } as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32,
            bitsPerPixel: 128, bytesPerRow: width * 16,
            space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let url = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFCompression: 1,
                kCGImagePropertyTIFFMake: "Sony",
                kCGImagePropertyTIFFModel: "Sony ILCE-7RM5",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "FE 24-70mm F2.8 GM II",
                kCGImagePropertyExifFocalLength: 70.0,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifExposureTime: shutterSeconds,
                kCGImagePropertyExifISOSpeedRatings: [100],
            ] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// The 08-1 acceptance P1 sign erratum's E2E regression pin (Plan 08-5):
    /// a KNOWN-L scene (0.5) with REAL shutter EXIF must merge back to ≈L —
    /// the exposure ratios (2^ΔEV in BRIGHTNESS-multiple semantics,
    /// log2(t_cand/t_ref)) divide each frame's pixels into scene luminance,
    /// and the §1.2 self-check must VERIFY (the old inverted sign produced
    /// systematically wrong merge values and `exposureRatioVerified=false`).
    func testE2EEXIFBracketMergesToKnownLuminance() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-exif-session-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Reference at 1s; candidates at 0.25s (−2 EV) and 2s (+1 EV) —
        // the physical pixel values ride the same factors (p = L·t). L is
        // kept at 0.25 so EVERY frame's pixels stay inside the §1.2 joint
        // band gates (0.001 < p < 0.995: the +1 EV frame tops at 0.5 —
        // an L of 0.5 would clip that frame's band and void the check).
        let sources = [
            try writeSourceWithEXIF(directory: root, name: "DSC00001.NEF",
                luminance: 0.25, exposure: 1.0, shutterSeconds: 1.0),
            try writeSourceWithEXIF(directory: root, name: "DSC00002.NEF",
                luminance: 0.25, exposure: 0.25, shutterSeconds: 0.25),
            try writeSourceWithEXIF(directory: root, name: "DSC00003.NEF",
                luminance: 0.25, exposure: 2.0, shutterSeconds: 2.0),
        ]
        let service = try makeService()
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false, tag: "hdr"), sessionRoot: root)
        guard let terminal = await Self.awaitTerminal(service) else {
            XCTFail("merge never settled")
            return
        }
        guard case .done(let productURL) = terminal.state else {
            XCTFail("expected .done, got \(terminal.state)")
            return
        }

        // ① The provenance EV numerics: brightness-multiple semantics —
        // [0, −2, +1] for [1s, 0.25s, 2s] against the 1s reference.
        let sidecar = try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: productURL)))
        let provenance = try XCTUnwrap(sidecar.provenance)
        let evs = provenance.sources.map(\.exposureEV)
        XCTAssertEqual(evs[0], 0.0, accuracy: 1e-9)
        XCTAssertEqual(evs[1], -2.0, accuracy: 1e-9)
        XCTAssertEqual(evs[2], 1.0, accuracy: 1e-9)

        // ② The §1.2 self-check VERIFIES on every frame (the constant-L
        // fixture's measured median ratios are exactly the EXIF factors).
        XCTAssertEqual(
            provenance.exposureRatioVerified, [true, true, true],
            "the EXIF expectation must match the measured ratios: "
                + "\(provenance.exposureRatioVerified)")

        // ③ The merged product ≈ L (0.25): every frame's p/2^ΔEV = 0.25,
        // so the Robertson weighted mean reconstructs the scene luminance
        // (the research §1.4 golden tolerance, 1%).
        let decoded = try await RAWDecoder().decode(productURL)
        var bitmap = [Float](repeating: -1, count: 64 * 64 * 4)
        CIContext().render(
            decoded.ciImage, toBitmap: &bitmap, rowBytes: 64 * 16,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        let center = bitmap[(32 * 64 + 32) * 4]
        XCTAssertEqual(
            center, 0.25, accuracy: 0.0025,
            "the EXIF bracket must merge back to the known scene luminance")
    }

    private func makeService() throws -> StackMergeService {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        return try StackMergeService(device: device)
    }

    private static func awaitTerminal(
        _ service: StackMergeService, timeout: TimeInterval = 60
    ) async -> StackMergeService.JobSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshots = await service.snapshots()
            // The LATEST job (a second enqueue of the same sources must be
            // observed itself, not its identical predecessor).
            if let latest = snapshots.max(by: { $0.seq < $1.seq }),
               latest.state.isTerminal {
                return latest
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await service.snapshots().max(by: { $0.seq < $1.seq })
    }

    // MARK: - T5: the product landing + collision increment (real leg)

    func testProductLandsInSessionRootWithCollisionIncrement() async throws {
        let (root, sources) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService()

        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false, tag: "hdr"), sessionRoot: root)
        guard let first = await Self.awaitTerminal(service) else {
            XCTFail("merge never settled")
            return
        }
        guard case .done(let firstURL) = first.state else {
            XCTFail("expected .done, got \(first.state)")
            return
        }
        XCTAssertEqual(firstURL.lastPathComponent, "DSC00001_hdr.tif",
            "the stem case rides verbatim (only the extension is lowercase)")
        XCTAssertEqual(firstURL.deletingLastPathComponent().path, root.path,
            "the product lands in the SESSION ROOT (research §3.2)")

        // The SECOND merge of the same sources MUST increment — never
        // overwrite (D-08-CONTEXT-11; the ExportNamer -1 convention).
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false, tag: "hdr"), sessionRoot: root)
        guard let second = await Self.awaitTerminal(service) else {
            XCTFail("second merge never settled")
            return
        }
        guard case .done(let secondURL) = second.state else {
            XCTFail("expected .done, got \(second.state)")
            return
        }
        XCTAssertEqual(secondURL.lastPathComponent, "DSC00001_hdr-1.tif",
            "the collision increment: -1 (case-insensitive occupancy)")
        XCTAssertNotEqual(firstURL, secondURL)
        // Both products exist (nothing was overwritten).
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        // The sources are untouched (bytes + names intact).
        for source in sources {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testPrecheckRejectsIdenticalExposureBracket() async throws {
        // The §2.4 matrix through the REAL leg: an all-identical synthetic
        // bracket carries no shutter metadata (warning) but the raster
        // tiff decode also cannot fabricate one — the E2E-level rejection
        // face is pinned by the CAPTURE-less merged values; the strict
        // matrix itself lives in MTBAlignTests. Here: the merged product
        // of a metadata-less bracket still lands (warnings, not rejects).
        let (root, sources) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService()
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false), sessionRoot: root)
        let terminal = await Self.awaitTerminal(service)
        guard case .done = terminal?.state else {
            XCTFail("a metadata-less synthetic bracket must merge (warnings only), got \(String(describing: terminal?.state))")
            return
        }
    }

    // MARK: - T5: the grid-visibility three rows (research §3.1)

    func testGridVisibilityThreeRows() async throws {
        // Row 1: a session-root <base>_hdr.tif IS browsable.
        XCTAssertTrue(SessionTreeScanner.isBrowsableFile("dsc00001_hdr.tif"))
        // Row 2: .lra sidecars are NEVER browse rows.
        XCTAssertTrue(SessionTreeScanner.isExcludedFile("dsc00001_hdr.tif.lra"))
        // Row 3: the .tif extension rides rasterExtensions.
        XCTAssertTrue(SessionTreeScanner.rasterExtensions.contains("tif"))

        // The WALK alignment: a session root with a product + its sidecar +
        // a masks directory yields EXACTLY the product row.
        let (root, sources) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService()
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: true, tag: "hdr"), sessionRoot: root)
        _ = await Self.awaitTerminal(service)

        let (entries, orphans) = await SessionTreeScanner.collect(root: root)
        let expected = Set(sources.map { $0.lastPathComponent } + ["DSC00001_hdr.tif"])
        XCTAssertEqual(Set(entries.map(\.relPath)), expected,
            "the walk must surface the three sources + the product, and NOTHING else (no .lra, no masks PNG)")
        XCTAssertTrue(orphans.isEmpty)
    }

    // MARK: - T5: the zero-new-mechanism E2E (IOP-HDR-04 literal)

    func testE2EProductGridDecodeEditSidecar() async throws {
        let (root, sources) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService()

        // ① merge (the REAL production leg: raster decode → align → merge
        // → float TIFF product in the session root).
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false, tag: "hdr"), sessionRoot: root)
        guard let terminal = await Self.awaitTerminal(service) else {
            XCTFail("merge never settled")
            return
        }
        guard case .done(let productURL) = terminal.state else {
            XCTFail("expected .done, got \(terminal.state)")
            return
        }

        // ② the grid: the walk surfaces the product (the visibility rows).
        let (entries, _) = await SessionTreeScanner.collect(root: root)
        XCTAssertTrue(entries.contains { $0.relPath == productURL.lastPathComponent },
            "the product must be a grid row")

        // ③ the edit chain: the product decodes through the SAME
        // RAWDecoder raster leg with DEPTH preserved (the RAW-03 face).
        let decoded = try await RAWDecoder().decode(productURL)
        let extent = decoded.ciImage.extent
        XCTAssertEqual(Int(extent.width), 64)
        XCTAssertEqual(Int(extent.height), 64)
        var bitmap = [Float](repeating: -1, count: 64 * 64 * 4)
        CIContext().render(
            decoded.ciImage, toBitmap: &bitmap, rowBytes: 64 * 16,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        // A finite, bounded HDR document (the 0.25/1.0/2.0 bracket merged
        // WITHOUT the exposure ratios — metadata-less — averages ≈ the
        // midpoint; the load-bearing assertions are depth + finiteness).
        let center = bitmap[(32 * 64 + 32) * 4]
        XCTAssertTrue(center.isFinite, "the product decoded to NaN")
        XCTAssertGreaterThan(center, 0)
        XCTAssertLessThan(center, 8.0, "the product lost its float range")

        // ③-bis: the SERVICE-written birth sidecar (the v4 merged-document
        // record) — read BEFORE the hand-built plain sidecar below lands.
        let productSidecar = try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: productURL)))
        let provenance = try XCTUnwrap(productSidecar.provenance)
        XCTAssertEqual(provenance.kind, .hdrMerge)
        XCTAssertEqual(provenance.sources.count, 3)
        XCTAssertEqual(provenance.sources.first?.relPath, "DSC00001.NEF")
        XCTAssertEqual(productSidecar.schemaVersion,
            LightamerSidecar.schemaVersionCurrent)

        // ④ the sidecar: an ordinary document's .lra with a history item —
        // the user's first edit round-trips with zero drift (the HIST-04
        // face), proving the product rides the NORMAL document chain.
        let historyInstance = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params(gain: 1.5))
        let historyStack = HistoryStack(
            items: [HistoryStack.HistoryItem(
                id: UUID(), snapshot: historyInstance, label: "exposure",
                timestamp: Date())],
            position: 0)
        let sidecar = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: StableHash.hash("e2e"),
            instances: [historyInstance],
            history: historyStack,
            historyHash: HistoryHash.hash(stack: historyStack, decodeParamsHash: StableHash.hash("e2e")),
            appVersion: "test")
        let sidecarURL = LightamerSidecar.sidecarURL(for: productURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sidecar).write(to: sidecarURL)
        let restored = try JSONDecoder().decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertFalse(restored.driftDetected, "a written sidecar must read back clean")
        XCTAssertEqual(restored.history.items.count, 1, "the history item survives")
        // A plain (non-merge) document carries NO provenance — the nil face.
        XCTAssertNil(restored.provenance, "a hand-built plain sidecar has none")
    }

    // MARK: - T6: the sidecar v4 provenance face

    private func makeProvenance(sources: [SidecarProvenance.Source]) -> SidecarProvenance {
        SidecarProvenance(
            kind: .hdrMerge,
            algorithm: SidecarProvenance.Algorithm(
                name: ProvenanceReplay.hdrAlgorithmName,
                implementationVersion: ProvenanceReplay.hdrImplementationVersion,
                params: StackMergeService.MergeParams(deGhost: true)),
            sources: sources,
            alignment: ["full", "full", "full"],
            exposureRatioVerified: [true, true, true],
            holeFraction: 0.003,
            createdAt: Date(),
            appVersion: "test")
    }

    func testV4RoundTripByteCompatibility() throws {
        // A v4 document with provenance round-trips the WHOLE document —
        // and the decimal-String hash lock holds on the wire.
        let sources = [
            SidecarProvenance.Source(relPath: "a.NEF", stableHash: 0xDEADBEEFCAFEF00D, exposureEV: -2),
            SidecarProvenance.Source(relPath: "b.NEF", stableHash: 1, exposureEV: 0),
            SidecarProvenance.Source(relPath: "c.NEF", stableHash: 0xFFFFFFFFFFFFFFFF, exposureEV: 2),
        ]
        let decodeHash: UInt64 = 12_345_678_901_234_567_890
        let emptyStack = HistoryStack(items: [], position: 0)
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [], history: emptyStack,
            historyHash: HistoryHash.hash(stack: emptyStack, decodeParamsHash: decodeHash),
            appVersion: "test",
            provenance: makeProvenance(sources: sources))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let wire = String(decoding: data, as: UTF8.self)
        // The UInt64String lock: the hash is a DECIMAL STRING on the wire.
        XCTAssertTrue(wire.contains("\"stableHash\" : \""),
            "the stableHash must be a decimal STRING on the wire")
        let restored = try JSONDecoder().decode(LightamerSidecar.self, from: data)
        XCTAssertEqual(restored, document, "the whole v4 document round-trips")
        XCTAssertEqual(restored.provenance?.sources.first?.stableHash,
            0xDEADBEEFCAFEF00D)
        XCTAssertFalse(restored.driftDetected)
    }

    func testV3DocumentReadsCleanWithNilProvenance() throws {
        // A HAND-WRITTEN v3 document (schemaVersion 3, no provenance key)
        // reads with provenance nil — the zero-harm read; a RE-ENCODE
        // bumps it to v4 with the field absent (ONE-WAY additive).
        let v3JSON = """
        {
          "appVersion" : "old",
          "decodeParamsHash" : "123",
          "decoderVersionUsed" : "v8",
          "flag" : null,
          "colorLabel" : null,
          "history" : { "items" : [], "position" : 0 },
          "historyHash" : "456",
          "imageID" : "11111111-2222-3333-4444-555555555555",
          "instances" : [],
          "keywords" : null,
          "layerStack" : null,
          "note" : null,
          "rating" : null,
          "schemaVersion" : 3
        }
        """
        let restored = try JSONDecoder().decode(
            LightamerSidecar.self, from: Data(v3JSON.utf8))
        XCTAssertNil(restored.provenance)
        XCTAssertEqual(restored.schemaVersion, 3, "the on-disk version is preserved")
        XCTAssertNil(restored.layerStack)
        // The re-encode PRESERVES the on-disk version (a decode keeps the
        // document's own schemaVersion — no silent bump of an existing
        // document; the CURRENT version is only written by the value-init
        // path, i.e. by fresh writers like the merge service).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let reencoded = try JSONDecoder().decode(
            LightamerSidecar.self, from: encoder.encode(restored))
        XCTAssertEqual(reencoded.schemaVersion, 3)
        XCTAssertNil(reencoded.provenance)
    }

    func testSourceDriftMarksDirty() async throws {
        let (root, sources) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService()
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false), sessionRoot: root)
        guard let terminal = await Self.awaitTerminal(service),
              case .done(let productURL) = terminal.state else {
            XCTFail("merge never settled")
            return
        }
        let document = try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: productURL)))
        let provenance = try XCTUnwrap(document.provenance)
        let rootURL = root

        // CLEAN: the recorded hashes match the untouched sources.
        XCTAssertEqual(
            ProvenanceReplay.drift(provenance: provenance, sessionRoot: rootURL),
            [false, false, false])

        // DRIFT: one byte of ONE source changed → that source flips dirty.
        let drifted = try Data(contentsOf: sources[1]) + Data("x".utf8)
        try drifted.write(to: sources[1])
        XCTAssertEqual(
            ProvenanceReplay.drift(provenance: provenance, sessionRoot: rootURL),
            [false, true, false],
            "a one-byte source change must flip exactly that source")
    }

    func testReplaySameParamsEquivalentProvenance() async throws {
        let (root, sources) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeService()
        for _ in 0..<2 {
            _ = try await service.enqueue(
                kind: .hdrMerge, sources: sources,
                params: .init(deGhost: false, tag: "hdr"), sessionRoot: root)
            _ = await Self.awaitTerminal(service)
        }
        // Two products; their provenances are EQUIVALENT (same sources +
        // same params — the reuse-prompt predicate) while the FILES differ
        // (the ExportNamer increment = the filesystem idempotence).
        let products = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tif" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(products.count, 2, "two merges = two products (never an overwrite)")
        XCTAssertEqual(
            Set(products.map(\.lastPathComponent)),
            ["DSC00001_hdr.tif", "DSC00001_hdr-1.tif"])
        var provenances: [SidecarProvenance] = []
        for product in products {
            let document = try JSONDecoder().decode(
                LightamerSidecar.self,
                from: Data(contentsOf: LightamerSidecar.sidecarURL(for: product)))
            provenances.append(try XCTUnwrap(document.provenance))
        }
        XCTAssertTrue(
            ProvenanceReplay.equivalentProvenance(provenances[0], provenances[1]),
            "same sources + same params = the SAME merge identity")
        // The replay: the recorded params rehydrate verbatim.
        XCTAssertEqual(
            ProvenanceReplay.replayParams(provenances[0]).deGhost, false)
        // The identity EXCLUDES the timestamps: a freshly built equivalent
        // provenance hashes the same.
        XCTAssertEqual(
            ProvenanceReplay.provenanceHash(provenances[0]),
            ProvenanceReplay.provenanceHash(provenances[1]))
    }
}
