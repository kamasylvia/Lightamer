import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import LightamerCore
import Metal
import UniformTypeIdentifiers
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportGainMapTests (Plan M6-3-01, KD-7 — EXPORT bundle) — the ALCE-03
// UltraHDR gain map JPEG export tier:
//
//   T1: the six validate gates (KD-1) + the additive decode zero-drift + the
//       capture two-state seam (KD-2) + the box lifecycle leak probe (KD-3).
//   T2: container byte face + aux readback dictionary + rewrap survival +
//       the post-processing double-bypass gate + the fail-loud guard (KD-4/5).
//   T4: base-plane fidelity + the gain semantic band + the reimport
//       compatibility (KD-7 tail).
//
// Golden discipline (KD-7): the CI write path is a THIRD-PARTY BLACK BOX —
// the goldens pin the CONTAINER STRUCTURE + the READBACK DICTIONARY + band
// assertions, NEVER a byte-level full comparison (an OS upgrade would fake-red
// the suite). All planes are small synthetic surfaces (≤256px).
// ─────────────────────────────────────────────────────────────────────────────

final class ExportGainMapTests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gainmap-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = tempDirectory.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if MTLCreateSystemDefaultDevice() == nil {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Fixtures (KD-1/KD-7)

    /// A legal gain map record: SDR encoding (rec709 + gamma22) with a peak
    /// above the SDR reference white (headroom > 1).
    private func gainRecord(peak: Float = 1000) -> DrtRecord {
        var record = DrtRecord()
        record.peakLuminance = peak
        return record
    }

    /// The legal base variant every gate test mutates ONE dimension of.
    private func gainVariant(
        format: ExportFormatSpec = .jpeg(quality: 0.9),
        record: DrtRecord? = gainRecordStatic(),
        embedICC: Bool = true,
        yiyin: Bool = false,
        gainMapHDR: Bool = true,
        sizing: YiyinExportSettings = YiyinExportSettings()
    ) -> ExportVariant {
        ExportVariant(
            sizing: sizing, format: format, yiyin: yiyin, drtOutput: record,
            embedICC: embedICC, gainMapHDR: gainMapHDR)
    }

    private nonisolated static func gainRecordStatic() -> DrtRecord {
        var record = DrtRecord()
        record.peakLuminance = 1000
        return record
    }

    // MARK: - T1: the six validate gates (KD-1)

    /// Gate ① + the additive decode zero-drift double assertion: a non-JPEG
    /// format is typed-refused, and a payload WITHOUT the gainMapHDR key
    /// decodes to `false` (the pre-M6-3 bytes never drift).
    func testGainMapGateOneRejectsNonJPEGAndAdditiveDecodeIsZeroDrift() throws {
        // ① non-jpeg refusal
        XCTAssertThrowsError(try gainVariant(format: .png(bitDepth: .eight)).validate()) {
            error in
            guard case AppError.invalidParameter = error else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
        XCTAssertThrowsError(try gainVariant(format: .tiff(bitDepth: .float32, compression: .zip)).validate())

        // additive decode: an old payload (no gainMapHDR key) decodes false
        // AND its pre-existing validate face is unchanged. (The ENCODE face
        // stays synthesized and emits the additive key — the zero-drift
        // contract is DECODE-side: decodeIfPresent ?? false.)
        let legacyVariant = ExportVariant(
            format: .jpeg(quality: 0.9), drtOutput: gainRecord())
        let encoder = JSONEncoder()
        let legacyData = try encoder.encode(legacyVariant)
        let decodedLegacy = try JSONDecoder().decode(
            ExportVariant.self, from: legacyData)
        XCTAssertFalse(decodedLegacy.gainMapHDR)
        XCTAssertNoThrow(try decodedLegacy.validate())

        // a payload WITH the key decodes true (the additive face works).
        var object = try JSONSerialization.jsonObject(with: legacyData)
            as! [String: Any]
        object["gainMapHDR"] = true
        let payload = try JSONSerialization.data(withJSONObject: object)
        let decodedNew = try JSONDecoder().decode(ExportVariant.self, from: payload)
        XCTAssertTrue(decodedNew.gainMapHDR)
        XCTAssertNoThrow(try decodedNew.validate())
    }

    /// Gate ②: no DRT record → no HDR plane source → typed refusal.
    func testGainMapGateTwoRejectsMissingDrtOutput() throws {
        var variant = gainVariant()
        variant.drtOutput = nil
        XCTAssertThrowsError(try variant.validate()) { error in
            guard case AppError.invalidParameter = error else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
    }

    /// Gate ③: the peak must clear the SDR reference white (headroom =
    /// peak/203 ≥ 1) — the shared `sdrReferenceWhite` constant is the single
    /// source the refusal message quotes.
    func testGainMapGateThreeRejectsPeakBelowSDRReferenceWhite() throws {
        // the DEFAULT record (peak 100) sits below the reference white.
        XCTAssertThrowsError(try gainVariant(record: DrtRecord()).validate())
        // finite-but-low
        XCTAssertThrowsError(try gainVariant(record: gainRecord(peak: 202.9)).validate())
        // non-finite
        XCTAssertThrowsError(try gainVariant(record: gainRecord(peak: .nan)).validate())
        // the boundary: exactly 203 passes (headroom = 1.0).
        XCTAssertNoThrow(try gainVariant(record: gainRecord(peak: 203)).validate())
        // the constant IS the single source (203) — quoted, not re-derived.
        XCTAssertEqual(ExportGainMapEncoder.sdrReferenceWhite, 203)
    }

    /// Gate ④ (RESEARCH §8.4): the ICC strip would invalidate the MPF
    /// subimage absolute offsets — the tier only exists in the embed form.
    func testGainMapGateFourRejectsOmittedICC() throws {
        XCTAssertThrowsError(try gainVariant(embedICC: false).validate()) { error in
            guard case AppError.invalidParameter = error else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
    }

    /// Gate ⑤ (D-M6-3-7): st2084/hlg bases are not SDR renditions — the E4
    /// forbidden shape's base-side projection, typed-refused.
    func testGainMapGateFiveRejectsHDREncodingEOTF() throws {
        for eotf in [DrtEotf.st2084, .hlg] {
            var record = gainRecord()
            record.encodingSpace = .rec2020
            record.encodingEotf = eotf
            XCTAssertThrowsError(try gainVariant(record: record).validate()) { error in
                guard case AppError.invalidParameter = error else {
                    return XCTFail("\(eotf): expected invalidParameter, got \(error)")
                }
            }
        }
    }

    /// Gate ⑥ (review E1): the yiyin face replays borders/watermark after
    /// the EotfBox — the SDR base canvas can exceed the captured plane.
    /// Validate-only (the M2 page cannot reach it).
    func testGainMapGateSixRejectsYiyin() throws {
        XCTAssertThrowsError(try gainVariant(yiyin: true).validate()) { error in
            guard case AppError.invalidParameter = error else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
        // the same shape WITHOUT the gain flag stays legal (the gate is
        // gain-conditional).
        var plain = gainVariant(yiyin: true)
        plain.gainMapHDR = false
        XCTAssertNoThrow(try plain.validate())
    }

    // MARK: - T1: the capture two-state seam (KD-2)

    // (harness shared with the T2/T4 faces — see below)

    /// The synthetic gradient PNG source (the ExportDrtTailE2ETests shape).
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

    private func makeRegistryReady() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    private func seedRecords() async -> [ModuleInstance] {
        let trio = await registry.makeDefaultInstances()
        return (trio + LightamerIOPRegistry.editingDefaultInstances())
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    private func writeSidecar(imageURL: URL, records: [ModuleInstance]) async throws {
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 0,
            instances: records,
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0),
            appVersion: "0.3.0-gainmap")
        let store = SidecarStore(destination: LightamerSidecar.sidecarURL(for: imageURL))
        await store.scheduleWrite(document)
        try await store.flushNow()
    }

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
        source: URL, variant: ExportVariant, drtTail: DrtTailParams?
    ) -> ExportRenderer.Request {
        ExportRenderer.Request(
            imageURL: source,
            destinationDirectory: outputDirectory,
            occupiedNames: [],
            variant: variant,
            drtTail: drtTail)
    }

    private func sdrGainTail() -> DrtTailParams {
        DrtTailParams(record: gainRecord())  // rec709 + gamma22, peak 1000
    }

    /// State ①: the flag ∧ tail job captures the pre-EOTF linear plane —
    /// the owned carrier arrives with the ENTRY plane's size and the
    /// `peak/203` headroom (KD-2).
    func testGainMapCaptureArmsForFlagAndTailJobs() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "GAIN_0001")
        try await writeSidecar(imageURL: source, records: await seedRecords())

        // the entry plane rides longEdge 48 (96×64 source → 48×32 entry) —
        // the capture rides the SAME entry plane the yiyin layout saw.
        let variant = gainVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)))
        let stage = try await ExportRenderer.renderStage(
            request: makeRequest(source: source, variant: variant, drtTail: sdrGainTail()),
            metal: metal, registry: registry,
            decodeLeg: { try await Self.syntheticDecode(url: $0) })

        let plane = try XCTUnwrap(
            stage.hdrGainPlane, "the armed job must capture the linear plane")
        // the capture rides the ENTRY plane (longEdge 48 on a 96×64 source).
        XCTAssertEqual(plane.width, 48)
        XCTAssertEqual(plane.height, 32)
        XCTAssertEqual(plane.texture.width, 48)
        XCTAssertEqual(plane.texture.height, 32)
        // the headroom IS the record's peak over the single-source constant.
        XCTAssertEqual(
            plane.headroom, ExportGainMapEncoder.headroom(peakLuminance: 1000),
            accuracy: 0.0001)
        XCTAssertEqual(plane.headroom, 1000.0 / 203.0, accuracy: 0.0001)
    }

    /// State ②: non-flag jobs (and a flag job WITHOUT a tail) leave the
    /// stage carrier nil — the zero path (KD-2's byte-unchanged discipline).
    func testNonGainMapStageCarriesNoPlane() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "GAIN_0002")
        try await writeSidecar(imageURL: source, records: await seedRecords())

        // non-flag job with a tail: the DRT tail renders, the capture does not.
        let plainVariant = gainVariant(gainMapHDR: false)
        let plainStage = try await ExportRenderer.renderStage(
            request: makeRequest(source: source, variant: plainVariant, drtTail: sdrGainTail()),
            metal: metal, registry: registry,
            decodeLeg: { try await Self.syntheticDecode(url: $0) })
        XCTAssertNil(plainStage.hdrGainPlane, "the zero path captures nothing")

        // flag job without a tail: the capture stays unarmed (the two
        // carriers are API-independent — the encode leg's fail-loud guard
        // owns the split, the render face simply captures nothing).
        let flagOnly = gainVariant()
        let flagOnlyStage = try await ExportRenderer.renderStage(
            request: makeRequest(source: source, variant: flagOnly, drtTail: nil),
            metal: metal, registry: registry,
            decodeLeg: { try await Self.syntheticDecode(url: $0) })
        XCTAssertNil(flagOnlyStage.hdrGainPlane)
    }

    // MARK: - T1: the box lifecycle leak probe (KD-3/M1)

    /// A settled (failed/cancelled) gain-map job must leave the box EMPTY —
    /// the actor cleanup paths (finish/finishCancelled/retry) clear the
    /// residue under the OLD seq (a retry re-keys fresh; nothing overwrites
    /// the old key). Proxy planes are tiny 4×4 textures — the assertion is
    /// the COUNT (a real plane would be ~1.6 GB at 100MP).
    func testSettledGainMapJobsLeaveTheBoxEmpty() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal GPU")
        }
        final class BoxHolder: @unchecked Sendable {
            weak var box: ExportQueue.ExportGainMapPlaneBox?
        }
        let holder = BoxHolder()
        let encodeLeg: ExportEncodeLeg = { _, _ in
            throw AppError.encodeFailed("gain-map leak probe")
        }
        let renderLeg: ExportRenderLeg = { snapshot, _ in
            if snapshot.variants.first?.gainMapHDR == true, let box = holder.box {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba32Float, width: 4, height: 4, mipmapped: false)
                descriptor.usage = [.shaderRead, .shaderWrite]
                descriptor.storageMode = .shared
                if let texture = device.makeTexture(descriptor: descriptor),
                    let queue = device.makeCommandQueue() {
                    box.stash(
                        ExportGainMapHDRPlane(
                            texture: texture, commandQueue: queue,
                            width: 4, height: 4, headroom: 2),
                        for: snapshot.seq)
                }
            }
            return ExportRenderArtifact(token: snapshot.seq, width: 4, height: 4)
        }
        let queue = ExportQueue(
            metal: nil, registry: ModuleRegistry.makeDefault(),
            renderLeg: renderLeg, encodeLeg: encodeLeg)
        holder.box = await queue.gainMapBoxForTesting()

        let source = try writePNG(width: 8, height: 8, stem: "GAINBOX_0001")
        let failed = await queue.enqueue(
            images: [(url: source, relPath: "GAINBOX_0001")],
            variants: [gainVariant()],
            destinationDirectory: outputDirectory)
        let failedState = try await awaitTerminal(queue, jobID: failed[0].id)
        guard case .failed = failedState.state else {
            return XCTFail("expected a failed job, got \(failedState.state)")
        }
        let box = await queue.gainMapBoxForTesting()
        XCTAssertEqual(box.countForTesting, 0, "the failed job's plane must clear")

        // the cancel path: an in-flight (render-leg-blocked) job cancelled —
        // the gate exit routes through finishCancelled and clears too.
        let gate = RenderGate()
        let blockingQueue = ExportQueue(
            metal: nil, registry: ModuleRegistry.makeDefault(),
            renderLeg: { snapshot, _ in
                if snapshot.variants.first?.gainMapHDR == true, let box = holder.box {
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba32Float, width: 4, height: 4, mipmapped: false)
                    descriptor.usage = [.shaderRead, .shaderWrite]
                    descriptor.storageMode = .shared
                    if let texture = device.makeTexture(descriptor: descriptor),
                        let q = device.makeCommandQueue() {
                        box.stash(
                            ExportGainMapHDRPlane(
                                texture: texture, commandQueue: q,
                                width: 4, height: 4, headroom: 2),
                            for: snapshot.seq)
                    }
                }
                await gate.awaitRelease()
                return ExportRenderArtifact(token: snapshot.seq, width: 4, height: 4)
            },
            encodeLeg: encodeLeg)
        // a fresh queue owns a fresh box; bind the holder to THIS queue's box
        // for the blocking probe.
        holder.box = await blockingQueue.gainMapBoxForTesting()
        let second = await blockingQueue.enqueue(
            images: [(url: source, relPath: "GAINBOX_0002")],
            variants: [gainVariant()],
            destinationDirectory: outputDirectory)
        // wait until the stash landed (the box counts ONE while blocked).
        var stashed = false
        for _ in 0..<500 {
            if holder.box?.countForTesting == 1 { stashed = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(stashed, "the blocked render leg must have stashed")
        await blockingQueue.cancel(jobID: second[0].id)
        await gate.release()
        _ = try await awaitTerminal(blockingQueue, jobID: second[0].id)
        let box2 = await blockingQueue.gainMapBoxForTesting()
        XCTAssertEqual(box2.countForTesting, 0, "the cancelled job's plane must clear")
    }

    /// The async-friendly render gate (Swift 6: no DispatchSemaphore.wait in
    /// async contexts — the blocked leg polls the actor flag instead).
    private actor RenderGate {
        private var released = false
        func release() { released = true }
        func awaitRelease() async {
            while !released {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    /// Poll a job to its terminal state (the ExportQueueTests shape).
    private func awaitTerminal(
        _ queue: ExportQueue, jobID: UUID, timeout: TimeInterval = 15
    ) async throws -> ExportJobSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshots = await queue.snapshots()
            if let snapshot = snapshots.first(where: { $0.id == jobID }),
                snapshot.state.isTerminal {
                return snapshot
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("job \(jobID) never settled")
        throw AppError.encodeFailed("gain-map probe: job never settled")
    }
}
