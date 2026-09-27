@testable import Lightamer
@testable import LightamerCore
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// StackAggregateTests (Plan 08-3 T3/T4) — the three-mode aggregation set:
// the analytic goldens (known values → exact mean/median/clipped re-mean),
// the sigma-clip star-field fixture (satellite-trail rejection), the N-value
// stack constant-memory lock, the N=3 degenerate note, and the SERVICE-SEG
// end-to-end faces: the four kinds through the real production leg (product
// landing + provenance kind + tag vocabulary + collision increment) and the
// EXIF precheck stack-variant matrix.
//
// Fixtures are synthetic and LOCAL-disk only (L009).
// ─────────────────────────────────────────────────────────────────────────────

final class StackAggregateTests: XCTestCase {

    // MARK: - Analytic goldens

    func testAnalyticGoldenAverage() {
        let samples: [Float] = [0.5, 0.25, 0.75, 0.5, 0.4, 0.6, 0.3, 0.7]
        let expected = samples.reduce(0, +) / 8
        XCTAssertEqual(
            StackAggregate.aggregate(samples, mode: .average), expected,
            accuracy: 1e-6)
        // NaN samples drop out of the mean (the alignment-edge semantics).
        let withHole: [Float] = [0.5, .nan, 0.75, 0.5, .nan, 0.6, 0.3, 0.7]
        let valid = withHole.filter { $0.isFinite }
        XCTAssertEqual(
            StackAggregate.aggregate(valid, mode: .average),
            StackAggregate.aggregate(withHole.compactMap { $0.isFinite ? $0 : nil },
                mode: .average), accuracy: 1e-6)
        XCTAssertTrue(StackAggregate.aggregate([.nan, .nan], mode: .average).isNaN)
    }

    func testAnalyticGoldenMedian() {
        // Odd count: the central order statistic.
        XCTAssertEqual(
            StackAggregate.aggregate([4, 1, 3, 5, 2].map(Float.init), mode: .median),
            3, accuracy: 1e-6)
        // Even count: the mean of the two central statistics (D-08-3-T3-2).
        XCTAssertEqual(
            StackAggregate.aggregate([4, 1, 3, 2].map(Float.init), mode: .median),
            2.5, accuracy: 1e-6)
        // The outlier rejection: a satellite pass in the median vanishes.
        XCTAssertEqual(
            StackAggregate.aggregate([0.5, 0.5, 0.5, 0.5, 8.0], mode: .median),
            0.5, accuracy: 1e-6)
    }

    func testAnalyticGoldenSigmaClip() {
        // A clean cluster + one gross outlier: the clip recovers the exact
        // clean mean. N=6 carries a population-σ max z of √5 ≈ 2.24 (a
        // single outlier can never exceed k=2.5 at this N), so the
        // analytic pin runs at k=2.0 — the star-field E2E pins the N=8
        // default-k face (D-08-3-T3-1: population σ).
        let clean: [Float] = [1.0, 1.1, 0.9, 1.05, 0.95]
        let cleanMean = clean.reduce(0, +) / 5
        let clipped = StackAggregate.aggregate(
            clean + [4.0], mode: .sigmaClip, sigmaK: 2.0)
        XCTAssertEqual(clipped, cleanMean, accuracy: 1e-5,
            "the 4.0 outlier must be rejected and the clean mean recovered")
        // No outlier → the plain mean (nothing rejected).
        XCTAssertEqual(
            StackAggregate.aggregate(clean, mode: .sigmaClip), cleanMean,
            accuracy: 1e-6)
        // A flat field (σ = 0) stays the flat value.
        XCTAssertEqual(
            StackAggregate.aggregate([0.5, 0.5, 0.5, 0.5], mode: .sigmaClip),
            0.5, accuracy: 1e-6)
        // A tighter k rejects milder outliers.
        let mild: [Float] = [1.0, 1.0, 1.0, 1.0, 1.3]
        XCTAssertEqual(
            StackAggregate.aggregate(mild, mode: .sigmaClip, sigmaK: 1.0),
            1.0, accuracy: 1e-6, "k=1 must reject the 1.3 tail")
    }

    // MARK: - The star-field fixture (sigma-clip's reason to exist)

    /// N=8 star subframes; source 6 drags a satellite TRAIL (a bright
    /// diagonal streak) across the frame. The sigma-clip aggregate must
    /// reject the trail's contribution; the plain average visibly smears.
    func testSigmaClipStarFieldRejectsSatelliteTrail() {
        let width = 96, height = 64
        var rng: UInt64 = 0x57A7
        func nextUniform() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFF) / Float(0xFFFF)
        }
        // The star field: faint sky + a few Gaussian-ish stars (as bright
        // bumps) + noise; the truth = the mean of the CLEAN frames.
        var cleanMean = [Float](repeating: 0, count: width * height)
        var frames: [[Float]] = []
        for frame in 0..<8 {
            var gray = [Float](repeating: 0, count: width * height)
            for index in gray.indices {
                gray[index] = 0.02 + 0.01 * nextUniform()
            }
            // Two "stars".
            gray[16 * width + 24] += 0.6
            gray[40 * width + 70] += 0.35
            frames.append(gray)
            for index in cleanMean.indices where frame < 7 {
                cleanMean[index] += gray[index] / 7
            }
        }
        // Frame 7: the satellite trail — a bright diagonal streak.
        for pixel in 0..<min(width, height) {
            frames[7][pixel * width + pixel] += 3.0
        }

        // Per-pixel aggregation over the N-stack (the band operator's shape).
        var clipped = [Float](repeating: 0, count: width * height)
        var averaged = [Float](repeating: 0, count: width * height)
        for index in cleanMean.indices {
            let stack = frames.map { $0[index] }
            clipped[index] = StackAggregate.aggregate(stack, mode: .sigmaClip)
            averaged[index] = StackAggregate.aggregate(stack, mode: .average)
        }
        // Along the trail: the sigma-clip recovers the clean truth within
        // the noise floor; the plain average is visibly polluted.
        var worstClip = 0.0 as Float
        var worstAverage = 0.0 as Float
        for pixel in 0..<min(width, height) {
            let index = pixel * width + pixel
            worstClip = max(worstClip, abs(clipped[index] - cleanMean[index]))
            worstAverage = max(worstAverage, abs(averaged[index] - cleanMean[index]))
        }
        XCTAssertLessThan(worstClip, 0.02,
            "the trail must be rejected; worst residual \(worstClip)")
        XCTAssertGreaterThan(worstAverage, 0.1,
            "the plain average must visibly smear the trail (sanity)")
        // Off-trail: both modes agree with the truth.
        var offTrail = 0.0 as Float
        for index in cleanMean.indices
        where abs(clipped[index] - cleanMean[index]) > abs(offTrail) {
            offTrail = clipped[index] - cleanMean[index]
        }
        XCTAssertLessThan(abs(offTrail), 0.02)
    }

    // MARK: - The N=3 degenerate (R6)

    func testSigmaClipN3DegeneratesToAverage() {
        // (N−1)/√N ≈ 1.155 < k=2.5 — no 3-sample set can ever reject; the
        // mode honestly equals the average (the service warns, R6).
        XCTAssertLessThan(
            StackAggregate.maxZScore(sampleCount: 3),
            StackAggregate.defaultSigmaK)
        let samples: [Float] = [0.2, 0.5, 9.0]
        XCTAssertEqual(
            StackAggregate.aggregate(samples, mode: .sigmaClip),
            StackAggregate.aggregate(samples, mode: .average),
            accuracy: 1e-6, "N=3 sigma-clip must degenerate to the average")
    }

    // MARK: - The band operators + the R3 memory lock

    func testAggregateBandStackAndConstantMemory() {
        // A 3-source band of 2 rows × 2 px (interleaved RGB): the stack
        // walk aggregates per float and honors NaN holes.
        let band0: [Float] = [0.1, 0.1, 0.1, 0.2, 0.2, 0.2,
                              0.3, 0.3, 0.3, .nan, 0, 0]
        let band1: [Float] = [0.5, 0.5, 0.5, 0.2, 0.2, 0.2,
                              .nan, 0, 0, .nan, 0, 0]
        let band2: [Float] = [0.9, 0.9, 0.9, 0.2, 0.2, 0.2,
                              0.7, 0.7, 0.7, .nan, 0, 0]
        let average = StackAggregate.aggregateBand([band0, band1, band2], mode: .average)
        XCTAssertEqual(average[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(average[3], 0.2, accuracy: 1e-6) // all equal
        XCTAssertEqual(average[6], 0.5, accuracy: 1e-6) // NaN skipped
        XCTAssertTrue(average[9].isNaN) // every source NaN → hole

        let median = StackAggregate.aggregateBand([band0, band1, band2], mode: .median)
        XCTAssertEqual(median[0], 0.5, accuracy: 1e-6)
        XCTAssertTrue(median[9].isNaN) // the hole stays NaN (→ holeFraction)
        let sigma = StackAggregate.aggregateBand([band0, band1, band2], mode: .sigmaClip)
        XCTAssertEqual(sigma[0], 0.5, accuracy: 1e-6)

        // The R3 lock: the N-value stack formula is EXACTLY
        // N × band rows × width × RGB float32, and at the plan's reference
        // point (N=8 · 256 rows · 11656 px) it lands at ≈286 MB — NOT the
        // N×full-frame ~9.7 GB residency.
        XCTAssertEqual(
            StackAggregate.bandStackBytes(width: 11656, bandHeight: 256, sources: 8),
            8 * 256 * 11656 * 3 * MemoryLayout<Float>.size)
        let bytes = StackAggregate.bandStackBytes(width: 11656, bandHeight: 256, sources: 8)
        let referenceMB = 286.0 // DECIMAL MB: 8×256×11656×3×4 = 286,457,856 B
        XCTAssertLessThan(
            abs(Double(bytes) / 1_000_000 - referenceMB) / referenceMB, 0.01,
            "the reference point drifted: \(bytes) B")
        let fullResidency = 8 * 11656 * 8742 * 3 * MemoryLayout<Float>.size
        XCTAssertLessThan(Double(bytes), Double(fullResidency) * 0.04,
            "the stack must be O(band), never O(height)")
    }

    // MARK: - T4: the service dispatch (the four kinds through the REAL
    // production leg)

    /// Synthetic float-TIFF sources (the ProvenanceV4Tests fixture shape):
    /// a 96×72 gray field with SOME TEXTURE (the MTB median needs spread
    /// and the SML needs gradient) + optional per-source shift.
    private func writeStackSource(
        directory: URL, name: String, seed: UInt64, dx: Int = 0, dy: Int = 0
    ) throws -> URL {
        // Textured float TIFF sources on the RASTER decode path (.tif —
        // stacking consumes any raster; the CIRAW legs are 08-1's face).
        // The texture (histogram spread) is load-bearing: the MTB median
        // and the SML measure need gradient content.
        let width = 96, height = 72
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        var gray = [Float](repeating: 0, count: width * height)
        for index in gray.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            gray[index] = 0.05 + 0.85 * Float((state >> 33) & 0xFFFFF) / Float(0xFFFFF)
        }
        // Pin the MAX where the shift's clamp cannot drop it (the
        // MTBAlignTests normalization lesson — a lost max speckles the
        // median-threshold bitmaps).
        gray[(height / 2) * width + width / 2] = 1.5
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let sx = max(0, min(x - dx, width - 1))
                let sy = max(0, min(y - dy, height - 1))
                let value = gray[sy * width + sx]
                let base = (y * width + x) * 4
                rgba[base] = value; rgba[base + 1] = value
                rgba[base + 2] = value; rgba[base + 3] = 1
            }
        }
        let url = directory.appendingPathComponent(name)
        try BandStreamer.writeFloatTIFF(rgba, width: width, height: height, to: url)
        return url
    }

    private func makeStackSession() throws -> (root: URL, sources: [URL]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stack-session-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let sources = [
            try writeStackSource(directory: root, name: "STACK0001.tif", seed: 0x5A1),
            try writeStackSource(directory: root, name: "STACK0002.tif", seed: 0x5A2),
            try writeStackSource(directory: root, name: "STACK0003.tif", seed: 0x5A3),
        ]
        return (root, sources)
    }

    private func makeRealService() throws -> StackMergeService {
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
            if let latest = snapshots.max(by: { $0.seq < $1.seq }),
               latest.state.isTerminal {
                return latest
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await service.snapshots().max(by: { $0.seq < $1.seq })
    }

    /// The four non-HDR kinds run the REAL production leg end to end: the
    /// products land with the kind's tag vocabulary, the v4 provenance
    /// carries the kind + the mode-specific params snapshot, the re-merge
    /// increments (never overwrites), and the warnings ride the outcome.
    func testStackAndFocusKindsEndToEnd() async throws {
        let (root, sources) = try makeStackSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeRealService()

        let cases: [(kind: StackMergeService.MergeKind,
                     product: String,
                     params: StackMergeService.MergeParams)] = [
            (.focusStack, "STACK0001_fstack.tif", .init(deGhost: false, tag: nil)),
            (.stackAverage, "STACK0001_stack_avg.tif", .init(deGhost: false, tag: nil)),
            (.stackMedian, "STACK0001_stack_med.tif", .init(deGhost: false, tag: nil)),
            (.stackSigma, "STACK0001_stack_sig.tif",
             .init(deGhost: false, tag: nil, sigmaClipK: 2.5)),
        ]
        for entry in cases {
            _ = try await service.enqueue(
                kind: entry.kind, sources: sources, params: entry.params,
                sessionRoot: root)
            guard let terminal = await Self.awaitTerminal(service) else {
                XCTFail("\(entry.kind.rawValue) never settled")
                continue
            }
            guard case .done(let url) = terminal.state else {
                XCTFail("\(entry.kind.rawValue) failed: \(terminal.state)")
                continue
            }
            XCTAssertEqual(url.lastPathComponent, entry.product,
                "the kind's tag vocabulary must name the product")
            // The birth sidecar: provenance kind + params snapshot.
            let sidecarURL = LightamerSidecar.sidecarURL(for: url)
            let data = try Data(contentsOf: sidecarURL)
            let sidecar = try JSONDecoder().decode(LightamerSidecar.self, from: data)
            guard let provenance = sidecar.provenance else {
                XCTFail("\(entry.kind.rawValue) product has no provenance")
                continue
            }
            XCTAssertEqual(provenance.kind.rawValue, entry.kind.rawValue)
            XCTAssertEqual(provenance.sources.count, sources.count)
            XCTAssertEqual(provenance.alignment.first, "full")
            XCTAssertTrue(provenance.exposureRatioVerified.allSatisfy { $0 })
            if entry.kind == .focusStack {
                XCTAssertEqual(provenance.algorithm.name, "sml-pyramid-fusion")
                XCTAssertEqual(provenance.algorithm.params.pyramidLevels, 5)
                XCTAssertNotNil(provenance.algorithm.params.nccMeasuredMin)
            } else {
                XCTAssertEqual(provenance.algorithm.name, "band-aggregate")
            }
            if entry.kind == .stackSigma {
                XCTAssertEqual(provenance.algorithm.params.sigmaClipK, 2.5)
            }
        }

        // A re-merge of the same sources INCREMENTS — never overwrites
        // (the D-08-CONTEXT-11 posture through the stack kinds too).
        _ = try await service.enqueue(
            kind: .stackAverage, sources: sources,
            params: .init(deGhost: false, tag: nil), sessionRoot: root)
        guard let second = await Self.awaitTerminal(service) else {
            XCTFail("second merge never settled")
            return
        }
        guard case .done(let url) = second.state else {
            XCTFail("expected .done, got \(second.state)")
            return
        }
        XCTAssertEqual(url.lastPathComponent, "STACK0001_stack_avg-1.tif",
            "the collision increment rides the stack tags too")
    }

    /// The displaced focus rail through the REAL leg: the MTB shift hits
    /// exactly and the fusion lands a clean combined product (the SC#2
    /// literal: correct alignment + clean combined output).
    func testDisplacedFocusRailAlignsAndFuses() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-rail-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ref = try writeStackSource(directory: root, name: "RAIL0001.tif", seed: 0xD1)
        // The comparison frame carries a KNOWN (3, -2) content shift —
        // inside the 96×72 pyramid's ±4 px reach (bottom level 24×18).
        let cmp = try writeStackSource(
            directory: root, name: "RAIL0002.tif", seed: 0xD1, dx: 3, dy: -2)
        let service = try makeRealService()
        _ = try await service.enqueue(
            kind: .focusStack, sources: [ref, cmp],
            params: .init(deGhost: false, tag: nil), sessionRoot: root)
        guard let terminal = await Self.awaitTerminal(service) else {
            XCTFail("the focus merge never settled")
            return
        }
        guard case .done(let url) = terminal.state else {
            XCTFail("expected .done, got \(terminal.state)")
            return
        }
        let sidecar = try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: url)))
        XCTAssertEqual(
            sidecar.provenance?.alignment, ["full", "full"],
            "the displaced rail must align without degradation")
        // The product decodes (a clean combined float document).
        let product = try await RAWDecoder().decode(url)
        XCTAssertEqual(product.ciImage.extent.width, 96)
    }

    /// The EXIF precheck stack-variant matrix (T4): the aperture stays
    /// STRICT (a rejection unless overridden) while the shutter/ISO drift
    /// is only a warning — the HDR bracket's "must differ" rule does NOT
    /// apply to stacks.
    func testPrecheckStackVariantMatrix() {
        var reference = CaptureMetadata()
        reference.cameraModel = "Test Cam"
        reference.lensModel = "Test Lens"
        reference.focalLength = 50
        reference.aperture = 8.0
        reference.iso = 100
        reference.shutterSpeed = 0.01

        var same = reference
        same.shutterSpeed = 0.01
        guard case .ok = ExifPrecheck.precheckStack(
            reference: reference, candidate: same, allowOverrides: false)
        else {
            XCTFail("an identical-settings stack frame must be admitted")
            return
        }

        var driftedShutter = reference
        driftedShutter.shutterSpeed = 0.02
        guard case .admittedWithWarning(_, let reasons) = ExifPrecheck.precheckStack(
            reference: reference, candidate: driftedShutter, allowOverrides: false)
        else {
            XCTFail("a shutter drift is a stack WARNING, not a rejection")
            return
        }
        XCTAssertTrue(reasons.contains { $0.contains("shutter drift") })

        // The contrast face: IDENTICAL shutters are the HDR bracket's
        // rejection ("not a bracket") while the stack admits them.
        guard case .rejected = ExifPrecheck.precheck(
            reference: reference, candidate: reference, allowOverrides: false)
        else {
            XCTFail("the HDR precheck must reject identical exposures")
            return
        }
        guard case .ok = ExifPrecheck.precheckStack(
            reference: reference, candidate: reference, allowOverrides: false)
        else {
            XCTFail("the stack precheck must admit identical settings")
            return
        }

        var driftedISO = reference
        driftedISO.iso = 200
        guard case .admittedWithWarning = ExifPrecheck.precheckStack(
            reference: reference, candidate: driftedISO, allowOverrides: false)
        else {
            XCTFail("an ISO drift is a stack WARNING, not a rejection")
            return
        }

        var stopped = reference
        stopped.aperture = 11.0
        guard case .rejected(let reasons) = ExifPrecheck.precheckStack(
            reference: reference, candidate: stopped, allowOverrides: false)
        else {
            XCTFail("an aperture mismatch stays a stack REJECTION (DoF premise)")
            return
        }
        XCTAssertTrue(reasons.contains { $0.contains("aperture mismatch") })
        // ... and the override admits it with a warning.
        guard case .admittedWithWarning = ExifPrecheck.precheckStack(
            reference: reference, candidate: stopped, allowOverrides: true)
        else {
            XCTFail("the aperture override must admit the stack frame")
            return
        }
    }

    // MARK: - T4: the App-layer seam (menu → coordinator → service)

    /// The same wiring shape LightamerApp installs for the stacking
    /// entries (the handler IS the menu→service leg; the SwiftUI menu half
    /// is declarative — the dialog + mode Picker ride the view).
    @MainActor
    func testCoordinatorStackSeamsReachService() async throws {
        let (root, sources) = try makeStackSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try makeRealService()
        let coordinator = SessionCoordinator()
        coordinator.stackMergeService = service
        coordinator.focusStackHandler = { relPaths in
            let urls = relPaths.map { root.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: .focusStack, sources: urls,
                params: StackMergeService.MergeParams(deGhost: false, tag: nil),
                sessionRoot: root)
        }
        coordinator.stackDenoiseHandler = { relPaths, mode in
            let kind: StackMergeService.MergeKind
            switch mode {
            case .average: kind = .stackAverage
            case .median: kind = .stackMedian
            case .sigmaClip: kind = .stackSigma
            }
            let urls = relPaths.map { root.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: kind, sources: urls,
                params: StackMergeService.MergeParams(deGhost: false, tag: nil),
                sessionRoot: root)
        }
        await coordinator.focusStackHandler?(sources.map(\.lastPathComponent))
        guard let focus = await Self.awaitTerminal(service) else {
            XCTFail("the focus seam job never settled")
            return
        }
        guard case .done(let focusURL) = focus.state else {
            XCTFail("expected .done, got \(focus.state)")
            return
        }
        XCTAssertEqual(focusURL.lastPathComponent, "STACK0001_fstack.tif")

        await coordinator.stackDenoiseHandler?(
            sources.map(\.lastPathComponent), .sigmaClip)
        guard let sigma = await Self.awaitTerminal(service) else {
            XCTFail("the denoise seam job never settled")
            return
        }
        guard case .done(let sigmaURL) = sigma.state else {
            XCTFail("expected .done, got \(sigma.state)")
            return
        }
        XCTAssertEqual(sigmaURL.lastPathComponent, "STACK0001_stack_sig.tif")
    }
}
