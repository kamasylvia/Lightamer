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
        sizing: YiyinExportSettings = YiyinExportSettings(),
        policy: ExportMetadataPolicy = .standard
    ) -> ExportVariant {
        ExportVariant(
            sizing: sizing, format: format, yiyin: yiyin, drtOutput: record,
            metadataPolicy: policy, embedICC: embedICC, gainMapHDR: gainMapHDR)
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

    // MARK: - T2: the CI encode leg (KD-4/KD-5)

    /// The full gain map render→encode through `ExportRenderer.render` (the
    /// production face), with the EXIF Software carrier scoped in.
    private func renderGainMapJPEG(
        stem: String, policy: ExportMetadataPolicy = .standard,
        software: String? = "Lightamer 0.4.0-gainmap-probe",
        longEdge: Int = 48
    ) async throws -> URL {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: stem)
        try await writeSidecar(imageURL: source, records: await seedRecords())
        let variant = gainVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: longEdge)),
            policy: policy)
        let request = makeRequest(
            source: source, variant: variant, drtTail: sdrGainTail())
        return try await ExportRenderer.$jobExifSoftware.withValue(software) {
            try await ExportRenderer.render(
                request: request, metal: metal, registry: registry,
                decodeLeg: { try await Self.syntheticDecode(url: $0) })
        }.destination
    }

    private func jpegBytes(_ url: URL) throws -> [UInt8] {
        try Data(contentsOf: url).map { $0 }
    }

    /// The MPF APP2 index segment payload: `"MPF\0MM\0*"` — the scan is on
    /// the PAYLOAD (the segment's 2-byte length sits between the FF E2
    /// marker and the payload, so the marker+payload concatenation never
    /// matches; probed on a real CI product).
    private func hasMPF(_ bytes: [UInt8]) -> Bool {
        Self.contains(bytes, Array("MPF\0MM\0*".utf8))
    }

    /// The ISO 21496-1 URN version marker (an APP2 payload).
    private func hasISOURN(_ bytes: [UInt8]) -> Bool {
        Self.contains(bytes, Array("urn:iso:std:iso:ts:21496".utf8))
    }

    private static func contains(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= bytes.count else { return false }
        outer: for i in 0...(bytes.count - needle.count) {
            for j in 0..<needle.count where bytes[i + j] != needle[j] {
                continue outer
            }
            return true
        }
        return false
    }

    private func auxGainMapDict(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let dict = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeISOGainMap)
        return try XCTUnwrap(dict as? [CFString: Any], "no ISO gain map aux")
    }

    /// The container byte face ①: the MPF APP2 index segment is present
    /// (the multi-picture container's spine).
    func testGainMapContainerMPFIndexSegmentIsPresent() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINMPF_0001")
        XCTAssertTrue(hasMPF(try jpegBytes(url)), "the MPF index must be present")
    }

    /// The container byte face ②: the ISO 21496-1 URN version marker rides
    /// its own APP2 (the D1 spike dump's layout).
    func testGainMapContainerISO21496URNMarkerIsPresent() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINISO_0001")
        XCTAssertTrue(
            hasISOURN(try jpegBytes(url)),
            "the ISO 21496-1 URN marker must be present")
    }

    /// The container byte face ③: a trailing gain map subimage EXISTS (the
    /// MPF-indexed second complete JPEG — two SOIs and two EOIs in the file).
    func testGainMapContainerCarriesTrailingSubimage() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINTAIL_0001")
        let bytes = try jpegBytes(url)
        let soi: [UInt8] = [0xFF, 0xD8]
        let eoi: [UInt8] = [0xFF, 0xD9]
        func count(_ needle: [UInt8]) -> Int {
            var count = 0
            outer: for i in 0...(bytes.count - needle.count) {
                for j in 0..<needle.count where bytes[i + j] != needle[j] {
                    continue outer
                }
                count += 1
            }
            return count
        }
        XCTAssertGreaterThanOrEqual(
            count(soi), 2, "the primary SOI plus the subimage SOI")
        XCTAssertGreaterThanOrEqual(
            count(eoi), 2, "the primary EOI plus the subimage EOI")
        // the LAST EOI closes the file (the subimage trails the primary).
        XCTAssertEqual(Array(bytes.suffix(2)), eoi, "the file ends on an EOI")
    }

    /// The container byte face ④ (L009): the promotion leaves NO tmp
    /// residue in the landing directory.
    func testGainMapPromotionLeavesNoTmpResidue() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINTMP_0001")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: outputDirectory.path)
        let residues = entries.filter { $0.contains(".tmp") }
        XCTAssertTrue(
            residues.isEmpty, "tmp residue in the landing zone: \(residues)")
    }

    /// The aux readback ①: the ISO gain map aux dict carries the
    /// single-channel luminance format 'L008' (OQ-4 — `hdrGainMapAsRGB` is
    /// NOT set) with BytesPerRow == width. (The description dict's keys are
    /// PLAIN STRINGS — "PixelFormat"/"Width"/"Height"/"BytesPerRow",
    /// probed; no CFString constants exist for them.)
    func testAuxReadbackReportsL008SingleChannel() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINAUX_0001")
        let dict = try auxGainMapDict(url)
        let description = try XCTUnwrap(
            dict[kCGImageAuxiliaryDataInfoDataDescription] as? [CFString: Any])
        let format = try XCTUnwrap(description["PixelFormat" as CFString] as? UInt32)
        let fourCC = String(
            decoding: withUnsafeBytes(of: format.bigEndian) { [UInt8]($0) },
            as: UTF8.self)
        XCTAssertEqual(fourCC, "L008", "the gain map must be single-channel")
        let bytesPerRow = try XCTUnwrap(
            description["BytesPerRow" as CFString] as? UInt32)
        let width = try XCTUnwrap(description["Width" as CFString] as? UInt32)
        XCTAssertEqual(Int(bytesPerRow), Int(width), "single channel: 1 byte/px")
        let data = try XCTUnwrap(dict[kCGImageAuxiliaryDataInfoData] as? Data)
        let height = try XCTUnwrap(description["Height" as CFString] as? UInt32)
        XCTAssertEqual(
            data.count, Int(width) * Int(height),
            "full-resolution L008 bitmap (\(width)×\(height))")
    }

    /// The aux readback ②: the gain map dimensions MATCH the base plane
    /// (the entry plane the CI gain computation rode).
    func testAuxReadbackDimensionsMatchTheBasePlane() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINAUX2_0001")
        let dict = try auxGainMapDict(url)
        let description = try XCTUnwrap(
            dict[kCGImageAuxiliaryDataInfoDataDescription] as? [CFString: Any])
        let width = try XCTUnwrap(description["Width" as CFString] as? UInt32)
        let height = try XCTUnwrap(description["Height" as CFString] as? UInt32)
        XCTAssertEqual(Int(width), 48)
        XCTAssertEqual(Int(height), 32)
    }

    /// The rewrap survival (F5 gate) + the hdrgm:Version mount + the
    /// policy-.none arm (one method, double assertion per KD-7): the
    /// standard-policy product carries the primary XMP `hdrgm:Version` AND
    /// the aux readback SURVIVES the rewrap; the `.none` product has no XMP
    /// but the container stays UltraHDR.
    func testRewrapSurvivesAndPolicyNoneStaysUltraHDR() async throws {
        // standard policy: hdrgm:Version + aux survival.
        let url = try await renderGainMapJPEG(stem: "GAINRW_0001")
        let bytes = try jpegBytes(url)
        XCTAssertTrue(
            Self.contains(bytes, Array("hdrgm:Version".utf8)),
            "the primary XMP must carry hdrgm:Version")
        XCTAssertTrue(
            Self.contains(bytes, Array("Lightamer 0.4.0-gainmap-probe".utf8)),
            "the Software signature must ride the XMP")
        _ = try auxGainMapDict(url)  // the F5 gate: the aux survives the rewrap
        XCTAssertTrue(hasMPF(bytes), "the MPF survives the rewrap")

        // .none policy: no XMP at all, the container stays UltraHDR.
        let noneURL = try await renderGainMapJPEG(
            stem: "GAINRW2_0001", policy: .none, software: nil)
        let noneBytes = try jpegBytes(noneURL)
        XCTAssertFalse(
            Self.contains(noneBytes, Array("hdrgm:Version".utf8)),
            "the .none policy mounts no XMP")
        XCTAssertTrue(hasMPF(noneBytes), "the .none container stays UltraHDR")
        XCTAssertTrue(hasISOURN(noneBytes))
        _ = try auxGainMapDict(noneURL)
    }

    /// The post-processing gate ①: the gain map arm skips the ICC strip —
    /// the product keeps its embedded profile (the MPF survives, which a
    /// strip would have broken).
    func testGainMapArmSkipsTheICCStrip() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINICC_0001")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let profile = props[kCGImagePropertyProfileName] as? String
        XCTAssertFalse(
            (profile ?? "").isEmpty,
            "the embedded profile must survive (the strip never ran)")
        XCTAssertTrue(hasMPF(try jpegBytes(url)))
    }

    /// The post-processing gate ②: the gain map arm skips mountXMP — the
    /// product carries EXACTLY ONE XMP packet (the rewrap's; a second APP1
    /// injection would corrupt the offsets). The scan rides `<x:xmpmeta`
    /// (the packet is robust across the two APP1 header spellings).
    func testGainMapArmDoesNotDoubleInjectXMP() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINXMP_0001")
        let bytes = try jpegBytes(url)
        let packet = Array("<x:xmpmeta".utf8)
        var packetCount = 0
        outer: for i in 0...(bytes.count - packet.count) {
            for j in 0..<packet.count where bytes[i + j] != packet[j] {
                continue outer
            }
            packetCount += 1
        }
        XCTAssertEqual(
            packetCount, 1, "exactly one XMP packet (the rewrap's) — no double inject")
    }

    /// The post-processing gate ③ (zero-diff negative): a NON-gain-map job
    /// keeps the existing post-encode face — with the DEFAULT policy the XMP
    /// mount skips (the editing-history gate closes it, M2-9-03's fixed
    /// posture), and with embedICC=false the strip runs; NO MPF exists.
    func testNonGainMapPostProcessingRunsAsBefore() async throws {
        try await makeRegistryReady()
        let source = try writePNG(width: 96, height: 64, stem: "GAINNEG_0001")
        try await writeSidecar(imageURL: source, records: await seedRecords())
        let variant = ExportVariant(
            format: .jpeg(quality: 0.9), drtOutput: gainRecord(), embedICC: false)
        XCTAssertFalse(variant.gainMapHDR)
        let outcome = try await ExportRenderer.render(
            request: makeRequest(source: source, variant: variant, drtTail: sdrGainTail()),
            metal: metal, registry: registry,
            decodeLeg: { try await Self.syntheticDecode(url: $0) })
        let bytes = try jpegBytes(outcome.destination)
        XCTAssertFalse(hasMPF(bytes), "a plain JPEG carries no MPF")
        XCTAssertFalse(
            Self.contains(bytes, Array("ICC_PROFILE\0".utf8)),
            "the strip ran (embedICC=false)")
        XCTAssertFalse(
            Self.contains(bytes, Array("<x:xmpmeta".utf8)),
            "the default policy's editing-history gate keeps the XMP unmounted")
    }

    /// The fail-loud guard (M4): an armed encode WITHOUT a captured plane
    /// is a typed refusal — never a silently-plain JPEG.
    func testEncodeStageFailsLoudWhenArmedWithoutPlane() throws {
        let plane = ExportQuantizedPlane(
            data: Data(repeating: 128, count: 8 * 8 * 4), width: 8, height: 8,
            layout: .rgba8)
        let destination = outputDirectory.appendingPathComponent("fail-loud.jpg")
        XCTAssertThrowsError(
            try ExportRenderer.encodeStage(
                plane: plane, formatSpec: .jpeg(quality: 0.9),
                targetColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                dpi: 72, sourceURL: outputDirectory, editorSignature: nil,
                destination: destination, gainMapHDR: true, hdrGainPlane: nil)
        ) { error in
            guard case AppError.invalidParameter = error else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.path),
            "the refusal leaves nothing on disk")
    }

    /// The quality knob rides the CI write path (E3 form): explicit quality
    /// values finalize fine; the size face responds in the expected
    /// direction (0.95 ≥ 0.5 — band-safe, no byte equality).
    func testQualityKnobReachesTheCIWritePath() async throws {
        try await makeRegistryReady()
        let lowSource = try writePNG(width: 96, height: 64, stem: "GAINQLOW_0001")
        try await writeSidecar(imageURL: lowSource, records: await seedRecords())
        let variant = gainVariant(
            format: .jpeg(quality: 0.5),
            sizing: YiyinExportSettings(mode: .longEdge(px: 96)))
        let low = try await ExportRenderer.render(
            request: makeRequest(source: lowSource, variant: variant, drtTail: sdrGainTail()),
            metal: metal, registry: registry,
            decodeLeg: { try await Self.syntheticDecode(url: $0) })
        .destination
        let highSource = try writePNG(width: 96, height: 64, stem: "GAINQHIGH_0001")
        try await writeSidecar(imageURL: highSource, records: await seedRecords())
        let highVariant = gainVariant(
            format: .jpeg(quality: 0.95),
            sizing: YiyinExportSettings(mode: .longEdge(px: 96)))
        let high = try await ExportRenderer.render(
            request: makeRequest(
                source: highSource, variant: highVariant, drtTail: sdrGainTail()),
            metal: metal, registry: registry,
            decodeLeg: { try await Self.syntheticDecode(url: $0) })
        .destination
        let lowSize = try Data(contentsOf: low).count
        let highSize = try Data(contentsOf: high).count
        XCTAssertGreaterThan(lowSize, 0)
        XCTAssertGreaterThanOrEqual(
            highSize, lowSize, "higher quality never shrinks the product")
    }

    /// The promotion face: the destination file decodes AT the entry size
    /// (the sips-level sanity — the promoted artifact is a real image).
    func testPromotedFileDecodesAtTheEntrySize() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINPROMO_0001")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(cg.width, 48)
        XCTAssertEqual(cg.height, 32)
    }

    // MARK: - T4: base fidelity + the gain semantic band + reimport (KD-7 tail)

    /// A small synthetic rgba8 gradient plane (the fidelity fixture).
    private func fidelityPlane(size: Int = 32) -> ExportQuantizedPlane {
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                rgba[i] = UInt8(x * 7 % 256)
                rgba[i + 1] = UInt8(y * 7 % 256)
                rgba[i + 2] = UInt8((x + y) * 3 % 256)
                rgba[i + 3] = 255
            }
        }
        return ExportQuantizedPlane(
            data: Data(rgba), width: size, height: size, layout: .rgba8)
    }

    /// An rgba32Float texture filled with `fill` (the capture carrier face).
    private func makeFloatTexture(
        _ width: Int, _ height: Int, fill: (Int, Int) -> (Float, Float, Float)
    ) throws -> (any MTLTexture, any MTLCommandQueue) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = fill(x, y)
                let i = (y * width + x) * 4
                floats[i] = r
                floats[i + 1] = g
                floats[i + 2] = b
                floats[i + 3] = 1
            }
        }
        floats.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, width, height, 1), mipmapLevel: 0,
                slice: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 16,
                bytesPerImage: width * 16)
        }
        return (texture, queue)
    }

    /// Decode a JPEG into RGBA8 bytes (the fidelity readback face).
    private func decodedRGBA8(_ url: URL) throws -> (
        bytes: [UInt8], width: Int, height: Int
    ) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let data = try XCTUnwrap(context.data)
        let count = cg.width * cg.height * 4
        let bytes = Array(
            UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self), count: count))
        return (bytes, cg.width, cg.height)
    }

    /// The base-plane fidelity (KD-7 ①, the E2 method): the gain map
    /// product's SDR base decodes to the SAME samples as a plain
    /// JPEGEncoder product of the SAME plane — CI does not rewrite our
    /// base pixels. S1 漂移伞: two BLACK-BOX encoders (CI's internal JPEG
    /// vs ImageIO's JPEGEncoder) equaling is a single-host observation —
    /// the standing assertion is the ±1 LSB per-point band (the DECISIONS
    /// entry pre-registers the fallback; a macOS upgrade may retune either
    /// encoder and only this band prevents a fake red).
    func testBasePlaneFidelityMatchesPlainJPEGEncoder() throws {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let plane = fidelityPlane()
        let (texture, queue) = try makeFloatTexture(32, 32) { x, y in
            (Float(x * 7 % 256) / 255 * 4, Float(y * 7 % 256) / 255 * 4, 0.9)
        }
        let hdrPlane = ExportGainMapHDRPlane(
            texture: texture, commandQueue: queue, width: 32, height: 32,
            headroom: 4)
        let gainURL = outputDirectory.appendingPathComponent("fidelity-gain.jpg")
        _ = try ExportGainMapEncoder.encode(
            plane: plane, hdrPlane: hdrPlane, targetColorSpace: srgb, quality: 0.9,
            destination: gainURL, sourceURL: nil, exifSoftware: nil,
            metadataPolicy: .standard)
        let plainURL = outputDirectory.appendingPathComponent("fidelity-plain.jpg")
        _ = try JPEGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .jpeg(quality: 0.9), colorSpace: srgb,
            destination: plainURL))

        let gain = try decodedRGBA8(gainURL)
        let plain = try decodedRGBA8(plainURL)
        XCTAssertEqual(gain.width, plain.width)
        XCTAssertEqual(gain.height, plain.height)
        // sample points: corners + center, all four channels, ±1 LSB.
        let size = 32
        for (x, y) in [(0, 0), (size - 1, 0), (size / 2, size / 2), (0, size - 1), (size - 1, size - 1)] {
            for c in 0..<4 {
                let i = (y * size + x) * 4 + c
                let delta = abs(Int(gain.bytes[i]) - Int(plain.bytes[i]))
                XCTAssertLessThanOrEqual(
                    delta, 1,
                    "base fidelity at (\(x),\(y)) ch\(c): "
                        + "\(gain.bytes[i]) vs \(plain.bytes[i])")
            }
        }
    }

    /// The gain semantic band (KD-7 ②, the E4 counter-proof): a UNIFORM SDR
    /// plane with HDR = SDR × 2^k yields GainMapMin == GainMapMax ≈ k — the
    /// gain ratios were taken over LINEAR LIGHT (PQ/HLG code values would
    /// produce a wildly different face; the capture point + validate gate ⑤
    /// structurally exclude it). The band tolerates the CI black box (the
    /// measured value lands in DECISIONS).
    func testGainSemanticBandProvesLinearLightFeed() throws {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let k: Float = 2
        var base = [UInt8](repeating: 0, count: 32 * 32 * 4)
        for i in stride(from: 0, to: base.count, by: 4) {
            base[i] = 128; base[i + 1] = 128; base[i + 2] = 128; base[i + 3] = 255
        }
        let plane = ExportQuantizedPlane(
            data: Data(base), width: 32, height: 32, layout: .rgba8)
        // the HDR plane must carry the base's LINEAR-DECODED value × 2^k —
        // the sRGB-encoded 128/255 would be the E4-adjacent wrong face (the
        // first probe run measured 3.2167 = log2(encoded×4/linear) exactly,
        // which incidentally PROVES CI decodes the base before the ratio).
        let sdrLinear = pow(((Float(128) / 255 + 0.055) / 1.055), 2.4)
        let (texture, queue) = try makeFloatTexture(32, 32) { _, _ in
            (sdrLinear * pow(2, k), sdrLinear * pow(2, k), sdrLinear * pow(2, k))
        }
        let hdrPlane = ExportGainMapHDRPlane(
            texture: texture, commandQueue: queue, width: 32, height: 32,
            headroom: pow(2, k))
        let url = outputDirectory.appendingPathComponent("semantic-band.jpg")
        _ = try ExportGainMapEncoder.encode(
            plane: plane, hdrPlane: hdrPlane, targetColorSpace: srgb, quality: 0.9,
            destination: url, sourceURL: nil, exifSoftware: nil,
            metadataPolicy: .standard)

        let dict = try auxGainMapDict(url)
        let metadataBox = try XCTUnwrap(dict[kCGImageAuxiliaryDataInfoMetadata])
        let metadata = unsafeDowncast(metadataBox as AnyObject, to: CGImageMetadata.self)
        let xmp = (CGImageMetadataCreateXMPData(metadata, nil)! as CFData) as Data
        let xmpString = String(decoding: xmp, as: UTF8.self)

        func gainMapValue(_ key: String) -> Float? {
            guard let keyRange = xmpString.range(of: key) else { return nil }
            guard let open = xmpString.range(of: ">", range: keyRange.upperBound..<xmpString.endIndex)
            else { return nil }
            guard let close = xmpString.range(of: "<", range: open.upperBound..<xmpString.endIndex)
            else { return nil }
            return Float(xmpString[open.upperBound..<close.lowerBound])
        }
        let gainMax = try XCTUnwrap(gainMapValue("GainMapMax"), "no GainMapMax in the XMP")
        let gainMin = try XCTUnwrap(gainMapValue("GainMapMin"), "no GainMapMin in the XMP")
        XCTAssertEqual(gainMax, k, accuracy: 0.5, "uniform ×2^k → max gain ≈ k")
        XCTAssertEqual(gainMin, k, accuracy: 0.5, "uniform plane → min == max ≈ k")
    }

    /// The row-order directionality (M6-5 T4, the D2 ledger fix): the
    /// texture→CIImage bridge's `.oriented(.downMirrored)`
    /// (ExportGainMapEncoder.swift:137) is the ONLY carrier of the
    /// HDR-plane/base row alignment — every pre-existing test face feeds
    /// symmetric (uniform or per-axis-gradient) surfaces a vertical flip
    /// cannot disturb. This test feeds a NON-uniform gain plane
    /// (image-top ≈ ×2 / image-bottom ≈ ×4) over an ASYMMETRIC base
    /// (top mid-gray, bottom highlight) and asserts the DIRECTION of the
    /// product's gain map: the base-highlight half must carry the larger
    /// gain. Dropping the down-mirror swaps the pairing and flips the
    /// product's direction (gain_top ≈ log2(4·0.956/0.216) ≈ 4.15 /
    /// gain_bottom ≈ -1.15) — a one-way trip this assertion catches.
    ///
    /// Orientation notes: the texture follows the PIPE convention (memory
    /// row 0 = image top — exactly what `.downMirrored` validates, since
    /// CIImage(mtlTexture:) reads memory row 0 as the image BOTTOM); the
    /// aux bitmap readback is asserted in the top-down frame (readback row
    /// 0 = image top). The GainMapMin/Max XMP anchors are orientation-free
    /// and pin the two-decade face independently.
    func testGainMapRowOrderIsTheDownMirroredAlignment() throws {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let width = 32, height = 32

        // The ASYMMETRIC base: top half mid-gray (sRGB 128), bottom half
        // highlight (sRGB 250) — rgba8 row 0 = image TOP (the quantized-
        // plane convention).
        var base = [UInt8](repeating: 0, count: width * height * 4)
        var baseLinear = [Float](repeating: 0, count: height)
        for y in 0..<height {
            let encoded: Float = y < height / 2 ? 128 : 250
            let linear = pow((encoded / 255 + 0.055) / 1.055, 2.4)
            baseLinear[y] = linear
            for x in 0..<width {
                let i = (y * width + x) * 4
                base[i] = UInt8(encoded)
                base[i + 1] = UInt8(encoded)
                base[i + 2] = UInt8(encoded)
                base[i + 3] = 255
            }
        }
        let plane = ExportQuantizedPlane(
            data: Data(base), width: width, height: height, layout: .rgba8)

        // The HDR plane, image-top = ×2^1 (gain 1.0), image-bottom = ×2^2
        // (gain 2.0) — the expected DOWN-MIRRORED product.
        let kTop: Float = 1
        let kBottom: Float = 2
        let (texture, queue) = try makeFloatTexture(width, height) { _, y in
            let v = baseLinear[y] * pow(2, y < height / 2 ? kTop : kBottom)
            return (v, v, v)
        }
        let hdrPlane = ExportGainMapHDRPlane(
            texture: texture, commandQueue: queue, width: width, height: height,
            headroom: pow(2, kBottom))
        let url = outputDirectory.appendingPathComponent("row-order.jpg")
        _ = try ExportGainMapEncoder.encode(
            plane: plane, hdrPlane: hdrPlane, targetColorSpace: srgb, quality: 0.9,
            destination: url, sourceURL: nil, exifSoftware: nil,
            metadataPolicy: .standard)

        // Readback: the aux bitmap + the GainMapMin/Max XMP anchors.
        let dict = try auxGainMapDict(url)
        let data = try XCTUnwrap(dict[kCGImageAuxiliaryDataInfoData] as? Data)
        XCTAssertEqual(data.count, width * height, "full-resolution L008 bitmap")
        let metadataBox = try XCTUnwrap(dict[kCGImageAuxiliaryDataInfoMetadata])
        let metadata = unsafeDowncast(metadataBox as AnyObject, to: CGImageMetadata.self)
        let xmpString = String(
            decoding: (CGImageMetadataCreateXMPData(metadata, nil)! as CFData) as Data,
            as: UTF8.self)
        func gainMapValue(_ key: String) -> Float? {
            guard let keyRange = xmpString.range(of: key) else { return nil }
            guard let open = xmpString.range(
                of: ">", range: keyRange.upperBound..<xmpString.endIndex)
            else { return nil }
            guard let close = xmpString.range(
                of: "<", range: open.upperBound..<xmpString.endIndex)
            else { return nil }
            return Float(xmpString[open.upperBound..<close.lowerBound])
        }
        let gainMin = try XCTUnwrap(gainMapValue("GainMapMin"), "no GainMapMin")
        let gainMax = try XCTUnwrap(gainMapValue("GainMapMax"), "no GainMapMax")
        // The two-decade face (orientation-free): min ≈ 1.0 (the ×2 half),
        // max ≈ 2.0 (the ×4 half).
        XCTAssertEqual(gainMin, kTop, accuracy: 0.4, "min gain anchors the ×2 half")
        XCTAssertEqual(gainMax, kBottom, accuracy: 0.4, "max gain anchors the ×4 half")
        XCTAssertGreaterThan(gainMax - gainMin, 0.5, "the asymmetric feed survived")

        // The DIRECTION: in the top-down readback frame, the base-highlight
        // half (image BOTTOM = the bitmap's second half) carries the larger
        // gain. Band means over each half's middle third (JPEG bleed at the
        // half boundary and the frame edges stays out).
        func bandMean(rows: Range<Int>) -> Float {
            var total: Float = 0
            var count: Float = 0
            for y in rows {
                for x in (width / 4)..<(3 * width / 4) {
                    total += Float(data[data.startIndex + y * width + x])
                    count += 1
                }
            }
            return total / count
        }
        let topMean = bandMean(rows: height / 6..<(height / 2 - 3))
        let bottomMean = bandMean(rows: (height / 2 + 3)..<(5 * height / 6))
        XCTAssertLessThan(
            topMean, 64,
            "the ×2 half sits at the min anchor (byte ≈ 0): measured \(topMean)")
        XCTAssertGreaterThan(
            bottomMean, 192,
            "the ×4 half sits at the max anchor (byte ≈ 255): measured \(bottomMean)")
        XCTAssertGreaterThan(
            bottomMean - topMean, 128,
            "the base-highlight half must carry the larger gain — the "
                + "down-mirrored alignment's one-way direction")
        // The derived semantic face: map the band means back through the
        // min/max anchors — image top ≈ kTop, image bottom ≈ kBottom.
        let derivedTop = gainMin + (gainMax - gainMin) * topMean / 255
        let derivedBottom = gainMin + (gainMax - gainMin) * bottomMean / 255
        XCTAssertEqual(derivedTop, kTop, accuracy: 0.45)
        XCTAssertEqual(derivedBottom, kBottom, accuracy: 0.45)
    }

    /// The reimport compatibility (KD-7 ③): the product re-enters through
    /// the M4-1 raster chain — `decodeRaster` succeeds, the size matches,
    /// the SDR base is what decodes (the gain ignored = the correct
    /// degrade; the future HDR-aware face rides kCIImageAuxiliaryHDRGainMap
    /// and is out of scope).
    func testReimportThroughTheRasterChainDecodesTheBase() async throws {
        let url = try await renderGainMapJPEG(stem: "GAINREIMP_0001")
        let decoded = try await RAWDecoder().decode(url)
        XCTAssertEqual(Int(decoded.ciImage.extent.width), 48)
        XCTAssertEqual(Int(decoded.ciImage.extent.height), 32)
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
