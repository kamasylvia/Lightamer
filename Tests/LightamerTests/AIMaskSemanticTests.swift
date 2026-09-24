@testable import LightamerCore
import CoreImage
import Vision
import XCTest

/// AIMaskSemanticTests (Plan 07-1 T2/T3/T5) — the SYNTHETIC SEMANTIC gate
/// (07-RESEARCH §6 AI-01 rows): direction assertions against known truth —
/// IoU ≥ 0.9 / background ≤ 0.1 / multi-instance subset separation /
/// no-subject typed error / layer-B excluded-point drop. "Produced an
/// output" alone NEVER passes (anti-vacuum).
final class AIMaskSemanticTests: XCTestCase {

    // MARK: - Fixtures

    /// One textured bright box (subject) on dark noisy ground. `gpuPinned`
    /// keeps the suite deterministic (D-07-1-T1-2).
    private func subjectImage(size: Int = 512) -> AIMaskInput {
        cgInput(
            { x, y in
                let inBox = x > 0.25 && x < 0.75 && y > 0.25 && y < 0.75
                return inBox ? 1.0 : 0.1
            }, size: size)
    }

    /// TWO separated boxes (the multi-instance probe shape: 768×512,
    /// label map verified to split them into 2 instances).
    private func twoSubjectImage() -> AIMaskInput {
        cgInput(
            { x, y in
                let left = x > 0.12 && x < 0.36 && y > 0.3 && y < 0.7
                let right = x > 0.64 && x < 0.88 && y > 0.3 && y < 0.7
                return (left || right) ? 1.0 : 0.1
            }, size: 768, height: 512)
    }

    /// A flat mid-gray field (NO subject — the probe-verified noSubject leg).
    private func blankImage(size: Int = 256) -> AIMaskInput {
        cgInput({ _, _ in 0.5 }, size: size)
    }

    private func cgInput(
        _ value: (Double, Double) -> Double, size: Int, height: Int? = nil
    ) -> AIMaskInput {
        let h = height ?? size
        var pixels = [UInt8](repeating: 0, count: size * h * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for y in 0..<h {
            for x in 0..<size {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let noise = Double((seed >> 33) & 0xFF) / 255.0
                let base = value(Double(x) / Double(size), Double(y) / Double(h))
                let bright = base > 0.5
                let v: UInt8 = bright
                    ? UInt8(min(255, 230 + noise * 25))
                    : UInt8(min(255, 45 + noise * 15))
                let i = (y * size + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(
            width: size, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
        return AIMaskInput(ciImage: CIImage(cgImage: cg))
    }

    /// IoU of a soft mask (0..1) against a hard truth box, both in
    /// normalized coordinates (`box = x0, y0, x1, y1`).
    private func iou(_ plane: AIMaskPlane, box: (Double, Double, Double, Double)) -> Double {
        var inter = 0.0, union = 0.0
        for y in 0..<plane.height {
            for x in 0..<plane.width {
                let fx = Double(x) / Double(plane.width)
                let fy = Double(y) / Double(plane.height)
                let truth = fx > box.0 && fx < box.2 && fy > box.1 && fy < box.3
                let mask = plane.floats[y * plane.width + x] > 0.5
                if truth && mask { inter += 1 }
                if truth || mask { union += 1 }
            }
        }
        return union > 0 ? inter / union : 0
    }

    /// Mean mask value inside a normalized region.
    private func mean(_ plane: AIMaskPlane, box: (Double, Double, Double, Double)) -> Double {
        var sum = 0.0, n = 0.0
        for y in 0..<plane.height {
            for x in 0..<plane.width {
                let fx = Double(x) / Double(plane.width)
                let fy = Double(y) / Double(plane.height)
                if fx > box.0 && fx < box.2 && fy > box.1 && fy < box.3 {
                    sum += Double(plane.floats[y * plane.width + x])
                    n += 1
                }
            }
        }
        return n > 0 ? sum / n : -1
    }

    /// See AIMaskDeterminismTests.ensureLayerBAssets: the test-built
    /// app's entitlements can block the asset download — the layer-B
    /// INFERENCE legs skip with that documented reason.
    @discardableResult
    private func ensureLayerBAssets() async throws -> Bool {
        let phase = await AIAssetStore.shared.currentPhase(queried: true)
        if case .notReady = phase {
            await AIAssetStore.shared.download()
        }
        return await AIAssetStore.shared.currentPhase().isReady
    }

    // MARK: - Layer A: single subject (the semantic gate)

    /// IoU ≥ 0.9 vs the truth box; background (the outer 15% ring)
    /// ≤ 0.1 — BOTH directions, or it fails.
    func testLayerASingleSubjectIoUAndBackground() async throws {
        let plane = try await AIMaskService.subjectMask(
            input: subjectImage(), selection: .all, device: .gpuPinned)
        XCTAssertEqual(plane.width, 512)
        let iou = iou(plane, box: (0.25, 0.25, 0.75, 0.75))
        XCTAssertGreaterThanOrEqual(iou, 0.9, "subject IoU below gate")
        let bg = mean(plane, box: (0.0, 0.0, 0.15, 1.0))
        XCTAssertLessThanOrEqual(bg, 0.1, "background leakage above gate")
        let bg2 = mean(plane, box: (0.85, 0.0, 1.0, 1.0))
        XCTAssertLessThanOrEqual(bg2, 0.1, "background leakage above gate (right)")
    }

    /// No subject (flat field) → the TYPED noSubject error, NO mask —
    /// never an all-ones plane (the load-degrade semantic is a different
    /// leg, D-07-CONTEXT 継承定案).
    func testLayerANoSubjectThrowsTypedError() async {
        do {
            _ = try await AIMaskService.subjectMask(
                input: blankImage(), selection: .all, device: .gpuPinned)
            XCTFail("a flat field must not produce a subject mask")
        } catch let error as AIMaskError {
            XCTAssertEqual(error, .noSubject, "the typed no-subject face, got: \(error)")
        } catch {
            XCTFail("untyped error leaked: \(error)")
        }
    }

    // MARK: - Layer A: multi-instance subset (the checkbox payload)

    /// Two separated subjects → ≥2 instances; EACH singleton subset mask
    /// is non-empty, spatially separated (left- vs right-heavy), and its
    /// IoU against ITS OWN box clears 0.9 while covering <5% of the OTHER
    /// box (subset direction assertions — a subset bug that returned the
    /// all-mask fails these).
    func testLayerAMultiInstanceSubsetSelection() async throws {
        let catalog = try await AIMaskService.detectInstances(
            input: twoSubjectImage(), device: .gpuPinned)
        XCTAssertGreaterThanOrEqual(
            catalog.instances.count, 2,
            "the two-box scene must detect ≥2 instances (probe-verified shape)")
        let subsets = try catalog.instances.map { instance -> (Int, AIMaskPlane) in
            (instance, try AIMaskService.subjectMask(
                from: catalog, selection: .subset([instance])))
        }
        var compared = 0
        for (instance, plane) in subsets {
            XCTAssertGreaterThan(plane.floats.count, 0)
            let leftMass = mass(plane, x0: 0.0, x1: 0.5)
            let rightMass = mass(plane, x0: 0.5, x1: 1.0)
            // Which side this instance lives on (orientation-free).
            let ownBox: (Double, Double, Double, Double)
            let otherBox: (Double, Double, Double, Double)
            if leftMass >= rightMass {
                ownBox = (0.12, 0.3, 0.36, 0.7); otherBox = (0.64, 0.3, 0.88, 0.7)
            } else {
                ownBox = (0.64, 0.3, 0.88, 0.7); otherBox = (0.12, 0.3, 0.36, 0.7)
            }
            let ownIoU = iou(plane, box: ownBox)
            XCTAssertGreaterThanOrEqual(
                ownIoU, 0.9, "instance \(instance) IoU vs its own box: \(ownIoU)")
            let otherCoverage = mean(plane, box: otherBox)
            XCTAssertLessThanOrEqual(
                otherCoverage, 0.05,
                "instance \(instance) leaks onto the other box: \(otherCoverage)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
    }

    /// Subset with an unknown instance index → typed invalidInput (never
    /// a silent drop).
    func testLayerAUnknownSubsetIndexThrows() async throws {
        let catalog = try await AIMaskService.detectInstances(
            input: twoSubjectImage(), device: .gpuPinned)
        let unknown = (catalog.instances.max() ?? 0) + 7
        do {
            _ = try AIMaskService.subjectMask(from: catalog, selection: .subset([unknown]))
            XCTFail("unknown instance index must throw")
        } catch let error as AIMaskError {
            guard case .invalidInput = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
        }
    }

    private func mass(_ plane: AIMaskPlane, x0: Double, x1: Double) -> Double {
        var sum = 0.0
        for y in 0..<plane.height {
            for x in 0..<plane.width {
                let fx = Double(x) / Double(plane.width)
                if fx >= x0 && fx < x1 { sum += Double(plane.floats[y * plane.width + x]) }
            }
        }
        return sum
    }

    // MARK: - Layer B: seed + refine semantics

    /// seedPoint on the subject → a NON-EMPTY mask; adding an excluded
    /// point INSIDE the subject DROPS the subject-region mean (the
    /// direction assertion — probe margin 0.35 → 0.32).
    func testLayerBSeedNonEmptyAndExcludedPointDrops() async throws {
        let assetsReady = try await ensureLayerBAssets()
        try XCTSkipUnless(
            assetsReady,
            "layer B assets unavailable in the test-built app (entitlement-blocked download)")
        let input = subjectImage()
        let seed = AIMaskPoint(x: 0.5, y: 0.5)
        let base = try await AIMaskService.segmentSubject(
            input: input, seed: .point(seed), quality: .accurate, device: .anePreferred)
        XCTAssertGreaterThan(base.floats.count, 0)
        let subjectBox = (0.3, 0.3, 0.7, 0.7)
        let baseMean = mean(base, box: subjectBox)
        XCTAssertGreaterThan(baseMean, 0.3, "seed on subject must light the subject (got \(baseMean))")

        let excluded = try await AIMaskService.segmentSubject(
            input: input, seed: .point(seed),
            refine: [AIRefinePoint(AIMaskPoint(x: 0.5, y: 0.5), .excluded)],
            quality: .accurate, device: .anePreferred)
        let excludedMean = mean(excluded, box: subjectBox)
        XCTAssertLessThan(
            excludedMean, baseMean - 0.02,
            "excluded point must DROP the subject mask (base \(baseMean) → \(excludedMean))")
    }

    /// The point budgets: point-seed 13 (seed counts 1 → 12 adds), box
    /// seed 11 — exceeding throws the TYPED error BEFORE Vision.
    func testLayerBPointLimitsThrowTyped() throws {
        // Pure request-assembly — no inference, no assets needed.
        // Point seed: 1 + 13 adds > 13.
        let tooManyPoints = (0..<13).map {
            AIRefinePoint(AIMaskPoint(x: 0.3, y: 0.3 + Float($0) * 0.001), .included)
        }
        do {
            _ = try AIMaskService.buildLayerBRequest(
                seed: .point(AIMaskPoint(x: 0.5, y: 0.5)), refine: tooManyPoints,
                quality: .accurate, regionOfInterest: nil, device: .anePreferred)
            XCTFail("13 refine points on a point seed must throw")
        } catch let error as AIMaskError {
            XCTAssertEqual(error, .pointLimitExceeded(limit: 13), "got \(error)")
        }
        // Box seed: 12 adds > 11.
        let tooManyBox = (0..<12).map {
            AIRefinePoint(AIMaskPoint(x: 0.3, y: 0.3 + Float($0) * 0.001), .included)
        }
        do {
            _ = try AIMaskService.buildLayerBRequest(
                seed: .box(AIMaskRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
                refine: tooManyBox,
                quality: .accurate, regionOfInterest: nil, device: .anePreferred)
            XCTFail("12 refine points on a box seed must throw")
        } catch let error as AIMaskError {
            XCTAssertEqual(error, .pointLimitExceeded(limit: 11), "got \(error)")
        }
        // AT the limit does NOT throw (12 point-seed adds, 11 box-seed).
        XCTAssertNoThrow(try AIMaskService.buildLayerBRequest(
            seed: .point(AIMaskPoint(x: 0.5, y: 0.5)),
            refine: Array(tooManyPoints.dropLast()),
            quality: .accurate, regionOfInterest: nil, device: .anePreferred))
        XCTAssertNoThrow(try AIMaskService.buildLayerBRequest(
            seed: .box(AIMaskRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            refine: Array(tooManyBox.dropLast()),
            quality: .accurate, regionOfInterest: nil, device: .anePreferred))
    }

    /// The scribble upgrade seam: constructing the reserved case throws
    /// the typed error (D-07-CONTEXT-4 — v1 does not wire scribble).
    func testScribbleSeamThrowsTyped() {
        do {
            _ = try AIMaskService.buildLayerBRequest(
                seed: .scribble, refine: [], quality: .accurate,
                regionOfInterest: nil, device: .anePreferred)
            XCTFail("scribble must be refused in v1")
        } catch let error as AIMaskError {
            XCTAssertEqual(error, .scribbleNotSupported)
        } catch {
            XCTFail("untyped: \(error)")
        }
    }

    /// Layer B gated by assets: a NOT-READY store refuses with the typed
    /// modelNotReady error (scripted probe injected into the service — no
    /// real download involved; no silent fallback, and layer A is
    /// untouched by layer-B state).
    func testLayerBGatedWhenModelNotReady() async throws {
        let store = AIAssetStore(
            statusProbe: { .notReady },
            downloader: { _ in })
        let phase = await store.currentPhase(queried: true)
        XCTAssertEqual(phase, .notReady)
        do {
            _ = try await AIMaskService.segmentSubject(
                input: subjectImage(), seed: .point(AIMaskPoint(x: 0.5, y: 0.5)),
                quality: .accurate, device: .anePreferred, assets: store)
            XCTFail("layer B must refuse when assets are not ready")
        } catch let error as AIMaskError {
            guard case .modelNotReady = error else {
                return XCTFail("expected modelNotReady, got \(error)")
            }
        }
        // Layer A runs regardless (the double-backend boundary — the gate
        // is entry-level, never a service-internal switch):
        let plane = try await AIMaskService.subjectMask(
            input: subjectImage(), selection: .all, device: .gpuPinned)
        XCTAssertGreaterThan(plane.floats.count, 0, "layer A is never gated by layer B assets")
    }

    // MARK: - AIAssetStatus state machine (T3)

    /// The scripted-probe transition matrix: unknown → notReady →
    /// downloading (observed mid-flight) → ready; failure → failed →
    /// RETRY → ready (no terminal states); ready + download = no-op.
    func testAssetStoreStateMachineTransitions() async throws {
        // 1. unknown → notReady (probe).
        let store = AIAssetStore(
            statusProbe: { .notReady },
            downloader: { _ in })
        var phase = await store.currentPhase(queried: true)
        XCTAssertEqual(phase, .notReady)

        // 2. notReady → downloading (observed DURING the download via a
        // held gate) → ready.
        // Simpler, deterministic gate: the downloader flips a box the test
        // polls — no continuations needed.
        final class Flags: @unchecked Sendable {
            var downloaderStarted = false
            var releaseDownloader = false
        }
        let flags = Flags()
        final class ProbeBox: @unchecked Sendable { var calls = 0 }
        let calls = ProbeBox()
        let store2 = AIAssetStore(
            statusProbe: { calls.calls += 1; return .ready },
            downloader: { _ in
                flags.downloaderStarted = true
                while !flags.releaseDownloader {
                    try? await Task.sleep(for: .milliseconds(5))
                }
            })
        async let walk: Void = store2.download()
        // wait until the downloader has started, then read the phase
        for _ in 0..<2000 where !flags.downloaderStarted {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(flags.downloaderStarted, "downloader must start")
        let mid = await store2.currentPhase()
        guard case .downloading = mid else {
            flags.releaseDownloader = true
            _ = await walk
            return XCTFail("mid-download phase must be .downloading (got \(mid))")
        }
        flags.releaseDownloader = true
        _ = await walk
        let after = await store2.currentPhase()
        XCTAssertEqual(after, .ready)

        // 3. failure → failed → retry (success) → ready.
        final class Flaky: @unchecked Sendable { var fail = true }
        let flaky = Flaky()
        final class Probe3: @unchecked Sendable { var calls = 0 }
        let probe3 = Probe3()
        let store3 = AIAssetStore(
            statusProbe: {
                probe3.calls += 1
                return probe3.calls <= 1 ? .notReady : .ready
            },
            downloader: { _ in
                if flaky.fail { throw NSError(domain: "test", code: 1) }
            })
        await store3.refreshStatus()
        await store3.download()
        let failedPhase = await store3.currentPhase()
        guard case .failed = failedPhase else {
            return XCTFail("failed download must surface .failed (got \(failedPhase))")
        }
        flaky.fail = false
        await store3.download()
        let retried = await store3.currentPhase()
        XCTAssertEqual(retried, .ready,
                       "retry after failure must succeed (no terminal states)")

        // 4. ready + download = idempotent no-op.
        await store3.download()
        let stillReady = await store3.currentPhase()
        XCTAssertEqual(stillReady, .ready)
    }

    /// The first-launch policy: offered ONCE (unanswered + not ready);
    /// never after answered; never when already ready.
    func testFirstLaunchPromptPolicy() {
        let suiteName = "lra-ai-prompt-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        XCTAssertTrue(AIAssetStore.shouldOfferFirstLaunchDownload(
            choice: .unanswered, phase: .notReady, defaults: suite))
        XCTAssertFalse(AIAssetStore.shouldOfferFirstLaunchDownload(
            choice: .unanswered, phase: .ready, defaults: suite),
            "ready assets never prompt")
        // Decline persists — no nagging.
        AIAssetStore.recordPromptChoice(.declined, defaults: suite)
        XCTAssertFalse(AIAssetStore.shouldOfferFirstLaunchDownload(
            choice: .unanswered, phase: .notReady, defaults: suite),
            "a recorded decline must suppress the prompt")
        // Accept persists the same way (the download itself is the action).
        AIAssetStore.recordPromptChoice(.accepted, defaults: suite)
        XCTAssertFalse(AIAssetStore.shouldOfferFirstLaunchDownload(
            choice: .unanswered, phase: .notReady, defaults: suite))
    }
}
