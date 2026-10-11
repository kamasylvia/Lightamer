@testable import Lightamer
@testable import LightamerCore
import CoreImage
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensLegTests (Plan M5-2-02 T1) — the PRODUCTION Mertens merge leg driven
// through the service (synthetic decode legs + the REAL merge leg): the KD-1
// pipeline gates (happy path / deghost off / the 4N+3 progress constant /
// cancel / extent typing / alignment vocabulary / EV recording / G1 leg-level
// bit-identity / the additive-default zero-drift negative for the existing
// kinds) + the streaming internals (the separable-dilate identity, the grid
// LUT equivalence, the band-outer vs whole-frame bit-identity, the NaN
// sanitize, the band grid alignment).
//
// FIXTURE DISCIPLINE: synthetic 64×48 bracket planes with HALF-EXACT values
// (k/16 grid) — the CIContext working format is RGBAh, so only half-exact
// values survive the decode render bit-exactly (the bit-identity tests'
// precondition). Every fixture lives in the TEMP domain with `defer` cleanup
// (L072); sources are throwaway byte files (the provenance hash input).
// ─────────────────────────────────────────────────────────────────────────────

final class MertensLegTests: XCTestCase {

    private static let width = 64
    private static let height = 48

    // MARK: - Fixtures

    /// A deterministic half-exact bracket plane: a checker background (the
    /// MTB texture) + a coherent dark block that STEPS with the frame index
    /// (the 01 G3② lesson — the deghost detector needs coherent structure,
    /// not noise shifts) — all values k/16, the CI half working format
    /// passes them through unchanged.
    private static func bracketPlane(_ index: Int) -> Data {
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let base = (y * width + x) * 4
                let checker = ((x / 4) + (y / 4)) % 2 == 0
                var value: Float = checker ? 0.75 : 0.25
                if x >= 8 + index * 8, x < 20 + index * 8, y >= 16, y < 30 {
                    value = 0.0625
                }
                floats[base] = value
                floats[base + 1] = value
                floats[base + 2] = value
                floats[base + 3] = 1
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// The synthetic decode payload: a bitmap CIImage in the working space
    /// (the render pass-through is identity for the half-exact grid) +
    /// capture metadata with the given shutter (the EV verdicts' input).
    private final class PayloadKeep: @unchecked Sendable {
        var payloads: [Data] = []
    }

    private static func decodedShutter(
        _ index: Int, shutter: Double?, keep: PayloadKeep
    ) -> DecodedImage {
        let data = bracketPlane(index)
        keep.payloads.append(data)
        let ci = CIImage(
            bitmapData: data, bytesPerRow: width * 16,
            size: CGSize(width: width, height: height),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        var capture = CaptureMetadata()
        capture.cameraModel = "ILCE-7M4"
        capture.shutterSpeed = shutter
        capture.iso = 100
        return DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(), capture: capture,
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// A same-name SMALLER frame (the extent-mismatch fixture).
    private static func smallFrame(keep: PayloadKeep) -> DecodedImage {
        let data = bracketPlane(0)
        keep.payloads.append(data)
        let ci = CIImage(
            bitmapData: data, bytesPerRow: 32 * 16,
            size: CGSize(width: 32, height: 24),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        return DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// The EV-free bracket decode leg: shutters 1/125 → 1/250 → 1/500
    /// (ΔEV = 0/−1/−2 against the reference), identical apertures/ISO (no
    /// warnings). `keep` holds the bitmap payloads (the CIImages may alias).
    private static func bracketDecodeLeg() -> StackDecodeLeg {
        let shutters = [1.0 / 125.0, 1.0 / 250.0, 1.0 / 500.0]
        let keep = PayloadKeep()
        return { url in
            let stem = url.lastPathComponent
                .replacingOccurrences(of: "src", with: "")
                .replacingOccurrences(of: ".tif", with: "")
            let index = Int(stem) ?? 0
            return Self.decodedShutter(index, shutter: shutters[index], keep: keep)
        }
    }

    private func makeSources(_ count: Int) throws -> (dir: URL, sources: [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mertens-leg-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        var sources: [URL] = []
        for index in 0..<count {
            let url = dir.appendingPathComponent("src\(index).tif")
            try Data([UInt8(index), 0xCA, 0xFE]).write(to: url)
            sources.append(url)
        }
        return (dir, sources)
    }

    private func makeService(
        decodeLeg: StackDecodeLeg? = nil
    ) throws -> StackMergeService {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        // mergeLeg: nil = the PRODUCTION legs (the leg under test).
        return try StackMergeService(device: device, decodeLeg: decodeLeg)
    }

    /// Poll until the NEWEST job (highest seq) reaches a terminal state.
    private static func awaitTerminal(
        _ service: StackMergeService, timeout: TimeInterval = 30,
        file: StaticString = #filePath, line: UInt = #line
    ) async -> StackMergeService.JobSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshots = await service.snapshots()
            if let newest = snapshots.last, newest.state.isTerminal {
                return newest
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await service.snapshots().last
    }

    private static func assertDone(
        _ terminal: StackMergeService.JobSnapshot?,
        file: StaticString = #filePath, line: UInt = #line
    ) -> URL {
        guard case .done(let url)? = terminal?.state else {
            XCTFail(
                "expected .done, got \(String(describing: terminal?.state))",
                file: file, line: line)
            return URL(fileURLWithPath: "/nonexistent")
        }
        return url
    }

    private static func readSidecar(_ product: URL) throws -> LightamerSidecar {
        try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: product)))
    }

    // MARK: - The production leg gates

    /// Happy path (N=3, tier medium): the product lands under the
    /// `_mertens` tag; the provenance carries the mertens identity, the
    /// composed (unconsumed) EVs, the all-true ratio face and the Ghost
    /// Suppression raster layer (the landed substitution mask).
    func testHappyPathLandsMertensProductWithProvenance() async throws {
        let (dir, sources) = try makeSources(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = try makeService(decodeLeg: Self.bracketDecodeLeg())
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "medium"),
            sessionRoot: dir)
        let product = Self.assertDone(await Self.awaitTerminal(service))
        XCTAssertTrue(
            product.lastPathComponent.contains("_mertens"),
            "the mertens tag must split the ledger: \(product.lastPathComponent)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: product.path))

        let sidecar = try Self.readSidecar(product)
        XCTAssertEqual(sidecar.provenance?.kind, .hdrMertens)
        XCTAssertEqual(
            sidecar.provenance?.algorithm.name, ProvenanceReplay.mertensAlgorithmName)
        XCTAssertEqual(
            sidecar.provenance?.algorithm.implementationVersion,
            ProvenanceReplay.mertensImplementationVersion)
        // OQ-5: the composed ΔEV recorded (reference-relative), never a
        // rejection; the ratio face is the all-true exemption placeholder.
        let evs = sidecar.provenance?.sources.map(\.exposureEV)
        XCTAssertEqual(evs?.count, 3)
        XCTAssertEqual(evs?.first ?? 99, 0, accuracy: 1e-9)
        XCTAssertEqual(evs?[1] ?? 99, -1, accuracy: 1e-9)
        XCTAssertEqual(evs?[2] ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(
            sidecar.provenance?.exposureRatioVerified, [true, true, true])
        // The substitution mask landed as the Ghost Suppression layer.
        XCTAssertEqual(sidecar.layerStack?.layers.count, 1)
        XCTAssertNotNil(
            sidecar.layerStack?.layers.first,
            "the Ghost Suppression layer must ride the sidecar")
        // The mask PNG landed beside the product (the GhostMaskWriter seat).
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: product.path + ".lra.masks"),
            "the tier-medium run must land its ghost mask directory")
    }

    /// Deghost off: no mask channel work, no substitution, no ghost mask —
    /// the fusion still lands (the OQ-3 off-contract; the skipped segment
    /// is invisible in the landed artifact — zero mask IO).
    func testDeghostOffLandsWithoutMaskOrLayerStack() async throws {
        let (dir, sources) = try makeSources(2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = try makeService(decodeLeg: Self.bracketDecodeLeg())
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "off"),
            sessionRoot: dir)
        let product = Self.assertDone(await Self.awaitTerminal(service))
        let sidecar = try Self.readSidecar(product)
        XCTAssertNil(sidecar.layerStack, "off = no Ghost Suppression layer")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: product.path + ".lra.masks"),
            "off = zero mask IO — nothing lands beside the product")
    }

    /// The declared window closes EXACTLY through the REAL leg: decode N
    /// (service) + align N + stage N + fuse N + write + sidecar + settle =
    /// 4N+3 (tier off lands the SAME total — the skipped substitution is
    /// not a step, AC 10).
    func testProgressConstantDoneEqualsTotalThroughRealLeg() async throws {
        for tier in ["medium", "off"] {
            let (dir, sources) = try makeSources(3)
            defer { try? FileManager.default.removeItem(at: dir) }
            let service = try makeService(decodeLeg: Self.bracketDecodeLeg())
            _ = try await service.enqueue(
                kind: .hdrMertens, sources: sources,
                params: .init(deGhost: false, tag: nil, mertensDeghost: tier),
                sessionRoot: dir)
            let declared = await service.progress()
            XCTAssertEqual(declared.total, 3 * 4 + 3, "tier \(tier)")
            _ = Self.assertDone(await Self.awaitTerminal(service))
            let final = await service.progress()
            XCTAssertEqual(final.done, final.total, "tier \(tier)")
            XCTAssertEqual(final.done, 15, "tier \(tier)")
        }
    }

    /// Cancel during the decode/stage window settles `.cancelled` (the
    /// generation-epoch in-flight semantics ride the real leg unchanged).
    func testCancelMidFlightSettlesCancelled() async throws {
        let (dir, sources) = try makeSources(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = AsyncGate()
        let keep = PayloadKeep()
        let decodeLeg: StackDecodeLeg = { url in
            if url.lastPathComponent == "src1.tif" {
                await gate.wait()
            }
            return Self.decodedShutter(0, shutter: nil, keep: keep)
        }
        let service = try makeService(decodeLeg: decodeLeg)
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "off"),
            sessionRoot: dir)
        // Let the decode of source 1 block on the gate mid-flight.
        try await Task.sleep(nanoseconds: 200_000_000)
        await service.cancelAll()
        await gate.open()
        let terminal = await Self.awaitTerminal(service)
        guard case .cancelled? = terminal?.state else {
            XCTFail("expected .cancelled, got \(String(describing: terminal?.state))")
            return
        }
    }

    /// A bracket with mixed extents fails TYPED (invalidParameter) — the
    /// hard input-error face, unchanged from the sibling legs.
    func testExtentMismatchTypedFailure() async throws {
        let (dir, sources) = try makeSources(2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = PayloadKeep()
        let decodeLeg: StackDecodeLeg = { url in
            if url.lastPathComponent == "src0.tif" {
                return Self.decodedShutter(0, shutter: nil, keep: keep)
            }
            return Self.smallFrame(keep: keep)
        }
        let service = try makeService(decodeLeg: decodeLeg)
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "off"),
            sessionRoot: dir)
        let terminal = await Self.awaitTerminal(service)
        guard case .failed(let error)? = terminal?.state else {
            XCTFail("expected .failed, got \(String(describing: terminal?.state))")
            return
        }
        guard case .invalidParameter = error else {
            XCTFail("expected invalidParameter, got \(error)")
            return
        }
    }

    /// The alignment vocabulary rides the provenance: the reference is
    /// always "full" and every comparison label comes from the MTB
    /// vocabulary (zero shifts on near-identical frames, but the assertion
    /// pins the PASS-THROUGH + vocabulary, not the fixture's texture).
    func testAlignmentLabelsVocabularyPassesThrough() async throws {
        let (dir, sources) = try makeSources(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = try makeService(decodeLeg: Self.bracketDecodeLeg())
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "off"),
            sessionRoot: dir)
        let product = Self.assertDone(await Self.awaitTerminal(service))
        let sidecar = try Self.readSidecar(product)
        let labels = sidecar.provenance?.alignment ?? []
        XCTAssertEqual(labels.count, 3)
        XCTAssertEqual(labels.first, "full", "the reference is always full")
        let vocabulary: Set<String> = ["full", "degraded", "skipped-low-texture"]
        for label in labels {
            XCTAssertTrue(
                vocabulary.contains(label),
                "label \(label) is outside the MTB vocabulary")
        }
    }

    /// G1 at the LEG level: two runs of the same synthetic bracket produce
    /// byte-identical product TIFFs (fully sequential CPU; the mask path
    /// included via the medium tier).
    func testDoubleRunProductBitIdentity() async throws {
        let (dir, sources) = try makeSources(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = try makeService(decodeLeg: Self.bracketDecodeLeg())
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "medium"),
            sessionRoot: dir)
        let first = Self.assertDone(await Self.awaitTerminal(service))
        let firstBytes = try Data(contentsOf: first)
        // The second run re-queues at the tail (the collision increment
        // names it differently — the BYTES are the identity under test).
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(deGhost: false, tag: nil, mertensDeghost: "medium"),
            sessionRoot: dir)
        let second = Self.assertDone(await Self.awaitTerminal(service))
        XCTAssertNotEqual(first, second, "the namer must not collide")
        let secondBytes = try Data(contentsOf: second)
        XCTAssertEqual(firstBytes, secondBytes, "G1: bit-identical products")
    }

    /// The additive-default zero-drift negative: an existing kind (stack
    /// average) through the SAME landing path lands the pre-M5-2-02 shape —
    /// flat-zero EVs, no ghost mask, no layer stack, the band-aggregate
    /// identity (the nil arms of KD-4 are byte-invisible).
    func testExistingKindLandingByteZeroDriftWithDefaults() async throws {
        let (dir, sources) = try makeSources(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = try makeService(decodeLeg: Self.bracketDecodeLeg())
        _ = try await service.enqueue(
            kind: .stackAverage, sources: sources,
            params: .init(deGhost: false, tag: nil), sessionRoot: dir)
        let product = Self.assertDone(await Self.awaitTerminal(service))
        XCTAssertTrue(product.lastPathComponent.contains("_stack_avg"))
        let sidecar = try Self.readSidecar(product)
        XCTAssertEqual(sidecar.provenance?.kind, .stackAverage)
        XCTAssertEqual(
            sidecar.provenance?.algorithm.name,
            StackMergeService.stackAlgorithmName)
        XCTAssertEqual(
            sidecar.provenance?.algorithm.implementationVersion,
            ProvenanceReplay.hdrImplementationVersion,
            "the nil implementationVersion arm keeps the historical value")
        XCTAssertEqual(
            sidecar.provenance?.sources.map(\.exposureEV), [0, 0, 0],
            "the nil exposureEVs arm keeps the flat-zero face")
        XCTAssertNil(sidecar.layerStack, "the nil ghostUnion arm keeps nil")
    }

    // MARK: - The streaming internals

    /// The separable dilate is output-IDENTICAL to the golden naive face
    /// (the max filter decomposes exactly over its axes) — the production
    /// size escape hatch without touching the golden face.
    func testSeparableDilateMatchesGoldenNaive() {
        let width = 53, height = 37
        var seed: UInt64 = 0x9E3779B97F4A7C15
        var plane = [Float](repeating: 0, count: width * height)
        for index in plane.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            plane[index] = (seed >> 33) % 7 == 0 ? 1 : 0
        }
        for radius in [1, 3, 9] {
            let naive = MertensFusion.dilate(
                plane, radius: radius, width: width, height: height)
            let separable = StackMergeService.mertensSeparableDilate(
                plane, radius: radius, width: width, height: height)
            XCTAssertEqual(
                naive, separable, "radius \(radius): the forms must coincide")
        }
    }

    /// The staged grid-row LUTs equal the whole-frame face on the same
    /// inputs (the 01 golden consumption face vs the streaming IO form).
    func testGridRowSubstituteLUTsMatchWholeFrameFace() throws {
        let width = 1024, height = 32
        let step = MertensFusion.decimationStep(width: width, height: height)
        XCTAssertEqual(step, 2, "the fixture must exercise row skipping")
        var seed: UInt64 = 0xDEADBEEFCAFEBABE
        func noise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 40) % 1000) / 1000
        }
        var reference = [Float](repeating: 0, count: width * height * 4)
        var frame = reference
        var motion = [Float](repeating: 0, count: width * height)
        for pixel in 0..<(width * height) {
            let base = pixel * 4
            reference[base] = noise(); reference[base + 1] = noise()
            reference[base + 2] = noise(); reference[base + 3] = 1
            frame[base] = noise(); frame[base + 1] = noise()
            frame[base + 2] = noise(); frame[base + 3] = 1
            motion[pixel] = pixel % 61 == 0 ? 0.9 : 0
        }
        let staging = StackMergeService.StagedSet(count: 2, width: width, height: height)
        defer { staging.cleanUp() }
        for (index, plane) in [reference, frame].enumerated() {
            try staging.writePlaneForProbe(plane, index: index)
        }
        // The static grid from the SAME motion plane (the leg's mask cells).
        let gridWidth = (width + step - 1) / step
        let gridHeight = (height + step - 1) / step
        var staticGrid = [Bool](repeating: false, count: gridWidth * gridHeight)
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                staticGrid[gy * gridWidth + gx] =
                    motion[min(gy * step, height - 1) * width + min(gx * step, width - 1)]
                        < 0.01
            }
        }
        let streamed = try StackMergeService.mertensStageSubstituteLUTs(
            staging: staging, width: width, height: height, step: step,
            referenceIndex: 0, frameIndex: 1,
            staticGrid: staticGrid, gridWidth: gridWidth, gridHeight: gridHeight)
        let wholeFrame = MertensFusion.substituteLUTs(
            reference: reference, frame: frame, motion: motion,
            width: width, height: height)
        XCTAssertEqual(streamed, wholeFrame, "the grid IO form is the golden form")
    }

    /// The band-outer driver reproduces the whole-frame golden fusion
    /// BIT-EXACTLY: multi-band runs coincide on every output row
    /// (grid-aligned starts + the halo cover the whole receptive field —
    /// the 01 G3④ property through the production driver).
    func testBandOuterFuseMatchesWholeFrameGolden() async throws {
        let width = 64
        let height = 600 // three 256-row bands at levels 2
        var seed: UInt64 = 0x0123456789ABCDEF
        func noise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return 0.125 + Float((seed >> 40) % 512) / 1024
        }
        var frames: [[Float]] = []
        for source in 0..<3 {
            var plane = [Float](repeating: 0, count: width * height * 4)
            for pixel in 0..<(width * height) {
                let base = pixel * 4
                plane[base] = min(noise() + Float(source) * 0.0625, 0.9375)
                plane[base + 1] = noise()
                plane[base + 2] = noise() - Float(source) * 0.0625
                plane[base + 3] = 1
            }
            frames.append(plane)
        }
        let levels = MertensFusion.adaptiveLevels(minEdge: width)
        let halo = MertensFusion.haloRows(levels: levels)
        let staging = StackMergeService.StagedSet(count: 3, width: width, height: height)
        defer { staging.cleanUp() }
        for (index, plane) in frames.enumerated() {
            try staging.writePlaneForProbe(plane, index: index)
        }
        let bands = StackMergeService.mertensAlignedBands(
            height: height, width: width, levels: levels)
        XCTAssertGreaterThanOrEqual(bands.count, 3, "the fixture must be multi-band")
        var ghostUnion: [UInt8]? = nil // tier off
        let fused = try await StackMergeService.mertensBandOuterFuse(
            staging: staging, width: width, height: height, sources: 3,
            levels: levels, halo: halo, tier: .off, luts: [],
            shifts: [(0, 0), (0, 0), (0, 0)],
            ghostUnion: &ghostUnion,
            progress: StackMergeProgress {},
            bumpBudget: 3)
        let golden = MertensFusion.fuse(
            frames: frames, width: width, height: height, deghost: .off,
            levels: levels)
        var mismatches = 0
        var worst: Float = 0
        for pixel in 0..<(width * height) {
            let rgbaBase = pixel * 4
            let rgbBase = pixel * 3
            for channel in 0..<3 {
                let difference = abs(fused[rgbaBase + channel] - golden[rgbBase + channel])
                worst = max(worst, difference)
                if fused[rgbaBase + channel] != golden[rgbBase + channel] {
                    mismatches += 1
                }
            }
        }
        XCTAssertEqual(mismatches, 0, "worst diff \(worst) — bit-identity broke")
    }

    /// Out-of-alignment-overlap samples (the shifted read's NaN margin)
    /// sanitize to 0 and never leak NaN into the fused output.
    func testShiftedStagedSourceStaysFinite() async throws {
        let width = 48, height = 64
        var planes: [[Float]] = []
        for source in 0..<2 {
            var plane = [Float](repeating: 0.25, count: width * height * 4)
            for pixel in 0..<(width * height) {
                plane[pixel * 4] = 0.25 + Float(source) * 0.125
                plane[pixel * 4 + 3] = 1
            }
            planes.append(plane)
        }
        let levels = MertensFusion.adaptiveLevels(minEdge: min(width, height))
        let halo = MertensFusion.haloRows(levels: levels)
        let staging = StackMergeService.StagedSet(count: 2, width: width, height: height)
        defer { staging.cleanUp() }
        for (index, plane) in planes.enumerated() {
            try staging.writePlaneForProbe(plane, index: index)
        }
        var ghostUnion: [UInt8]? = nil
        let fused = try await StackMergeService.mertensBandOuterFuse(
            staging: staging, width: width, height: height, sources: 2,
            levels: levels, halo: halo, tier: .off, luts: [],
            shifts: [(0, 0), (0, 5)], // the second source shifts down 5 rows
            ghostUnion: &ghostUnion,
            progress: StackMergeProgress {},
            bumpBudget: 2)
        for value in fused where value.isNaN {
            XCTFail("NaN leaked through the sanitize")
            break
        }
    }

    /// The band starts ride the 2^(L−1) grid (the 01 DECISIONS §6 constraint
    /// — the deepest reduce grid) at every depth, and the bands tile the
    /// frame exactly.
    func testAlignedBandStartsDivisibleByDeepestReduceGrid() {
        for levels in [1, 2, 5, 9, 12] {
            let align = 1 << max(0, levels - 1)
            let bands = StackMergeService.mertensAlignedBands(
                height: 8642, width: 11584, levels: levels)
            XCTAssertFalse(bands.isEmpty)
            for band in bands {
                XCTAssertEqual(
                    band.y % align, 0,
                    "levels \(levels): band start \(band.y) off the grid")
            }
            XCTAssertEqual(bands[0].y, 0)
            for index in 1..<bands.count {
                XCTAssertEqual(
                    bands[index].y,
                    bands[index - 1].y + bands[index - 1].height)
            }
            XCTAssertEqual(bands.last!.y + bands.last!.height, 8642)
        }
    }
}

// MARK: - Helpers

/// An async one-shot gate (the StackMergeServiceTests shape).
private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

extension StackMergeService.StagedSet {

    /// Probe-side staged write from a plain RGBA array (wraps the plane in
    /// a transient StackRenderedPlane — the tests never hold CIImages; the
    /// plane OWNS the buffer and deallocates in deinit, so no manual free).
    func writePlaneForProbe(_ plane: [Float], index: Int) throws {
        let width = self.width
        let height = self.height
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: width * height * 16, alignment: 64)
        plane.withUnsafeBufferPointer { source in
            buffer.copyMemory(
                from: UnsafeRawPointer(source.baseAddress!),
                byteCount: width * height * 16)
        }
        try writePixels(
            StackRenderedPlane(
                pointer: buffer, width: width, height: height,
                bytesPerRow: width * 16),
            index: index)
    }
}
