@testable import LightamerCore
import CoreImage
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensMergeKindTests (Plan M5-2-01 T2/T3) — the additive vocabulary face:
// the `hdrMertens` kind (raw value / provenance mirror / defaultTag /
// stepTotal 4N+3 + the done==total constant on a synthetic leg / the typed
// stub failure / the five existing kinds' unchanged snapshots), the
// MergeParams additive fields (nil-default + encodeIfPresent round-trip +
// the nil→medium leg resolution), and the EV-FREE precheck
// (`mertensVerdicts` — zero rejections, warnings only, EV composed but never
// consumed, contrasted against the strict `precheck`).
// ─────────────────────────────────────────────────────────────────────────────

final class MertensMergeKindTests: XCTestCase {

    // MARK: - Stubs (the StackMergeServiceTests seam shape)

    private static func stubDecodedImage() -> DecodedImage {
        let ci = CIImage(color: CIColor.gray).cropped(
            to: CGRect(x: 0, y: 0, width: 4, height: 4))
        return DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    private func makeSources(count: Int = 3) throws -> (dir: URL, sources: [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mertens-kind-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        var sources: [URL] = []
        for index in 0..<count {
            let url = dir.appendingPathComponent("src\(index).tif")
            try Data("fixture-\(index)".utf8).write(to: url)
            sources.append(url)
        }
        return (dir, sources)
    }

    private func makeService(
        decodeLeg: StackDecodeLeg? = nil,
        mergeLeg: StackMergeLeg? = nil
    ) throws -> StackMergeService {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        return try StackMergeService(
            device: device, decodeLeg: decodeLeg, mergeLeg: mergeLeg)
    }

    private static func awaitTerminal(
        _ service: StackMergeService, timeout: TimeInterval = 10
    ) async -> StackMergeService.JobSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshots = await service.snapshots()
            if let first = snapshots.first, first.state.isTerminal {
                return first
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await service.snapshots().first
    }

    // MARK: - The kind vocabulary (KD-4)

    func testMertensKindRawValueAndCaseCount() {
        XCTAssertEqual(StackMergeService.MergeKind.hdrMertens.rawValue, "hdr-merge-mertens")
        XCTAssertEqual(
            StackMergeService.MergeKind(rawValue: "hdr-merge-mertens"), .hdrMertens)
        // CaseIterable +1 (five existing + the additive case).
        XCTAssertEqual(StackMergeService.MergeKind.allCases.count, 6)
    }

    func testProvenanceKindMirrorAcrossAllCases() {
        // The two enums' raw values align element-wise (the mirror
        // discipline) — the new case included.
        for kind in StackMergeService.MergeKind.allCases {
            XCTAssertEqual(
                kind.provenanceKind.rawValue, kind.rawValue,
                "provenance mirror broke at \(kind.rawValue)")
        }
        XCTAssertEqual(SidecarProvenance.Kind.allCases.count, 6)
    }

    func testDefaultTagVocabularyIncludingMertens() {
        // The five existing tags verbatim (the G5 snapshot face) + mertens.
        XCTAssertEqual(StackMergeService.defaultTag(for: .hdrMerge), "hdr")
        XCTAssertEqual(StackMergeService.defaultTag(for: .focusStack), "fstack")
        XCTAssertEqual(StackMergeService.defaultTag(for: .stackAverage), "stack_avg")
        XCTAssertEqual(StackMergeService.defaultTag(for: .stackMedian), "stack_med")
        XCTAssertEqual(StackMergeService.defaultTag(for: .stackSigma), "stack_sig")
        XCTAssertEqual(StackMergeService.defaultTag(for: .hdrMertens), "mertens")
    }

    func testStepTotalMertensFourNPlusThreeAndExistingSnapshots() {
        var params = StackMergeService.MergeParams()
        params.deGhost = false
        // Mertens: 4N+3 regardless of the (HDR-only) deGhost knob.
        for sources in [2, 3, 5] {
            XCTAssertEqual(
                StackMergeService.stepTotal(for: sources, params: params, kind: .hdrMertens),
                sources * 4 + 3, "at N=\(sources)")
        }
        // The five existing kinds' declared totals unchanged (snapshots):
        XCTAssertEqual(
            StackMergeService.stepTotal(for: 3, params: .init(deGhost: false), kind: .hdrMerge),
            3 * 2 + 3)
        XCTAssertEqual(
            StackMergeService.stepTotal(for: 3, params: .init(deGhost: true), kind: .hdrMerge),
            3 * 3 + 3)
        XCTAssertEqual(
            StackMergeService.stepTotal(for: 4, params: params, kind: .focusStack), 4 * 3 + 3)
        XCTAssertEqual(
            StackMergeService.stepTotal(for: 4, params: params, kind: .stackAverage), 15)
        XCTAssertEqual(
            StackMergeService.stepTotal(for: 4, params: params, kind: .stackMedian), 15)
        XCTAssertEqual(
            StackMergeService.stepTotal(for: 4, params: params, kind: .stackSigma), 15)
    }

    /// The KD-8 constant: with a synthetic N=3 leg the (done, total) window
    /// closes EXACTLY — decode N (service) + 3N+2 (leg's align/stage/fuse/
    /// write/sidecar duty) + 1 (settle) == 4N+3.
    func testMertensLegDoneEqualsTotalExactly() async throws {
        let (dir, sources) = try makeSources(count: 3)
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { work in
                // The leg's bump duty: 3N+2 (align N + stage N + fuse N +
                // write + sidecar); settle rides markTerminal.
                for _ in 0..<(work.sources.count * 3 + 2) {
                    await work.progress.step()
                }
                let product = dir.appendingPathComponent("merged_mertens.tif")
                try Data([0xDE, 0xAD]).write(to: product)
                return StackMergeOutcome(
                    productURL: product, holeFraction: 0,
                    alignment: Array(repeating: "full", count: work.sources.count),
                    exposureRatioVerified: Array(repeating: true, count: work.sources.count))
            })
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources,
            params: .init(tag: nil, mertensDeghost: "medium"), sessionRoot: dir)
        // The window was declared AT enqueue: total = 4N+3 = 15.
        let declared = await service.progress()
        XCTAssertEqual(declared.total, 3 * 4 + 3)
        let terminal = await Self.awaitTerminal(service)
        if case .done = terminal?.state {} else {
            XCTFail("expected .done, got \(String(describing: terminal?.state))")
        }
        let final = await service.progress()
        XCTAssertEqual(final.done, final.total, "the declared 4N+3 must close exactly")
        XCTAssertEqual(final.done, 15)
    }

    /// The production stub (KD-4): an enqueue of `.hdrMertens` with the
    /// PRODUCTION merge leg fails typed — `invalidParameter` naming the
    /// M5-2-02 landing plan (the M4-1-01 route-don't-switch shape).
    func testProductionStubFailsTypedNamingM5_2_02() async throws {
        let (dir, sources) = try makeSources(count: 2)
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: nil) // nil = the production leg = the Mertens stub
        _ = try await service.enqueue(
            kind: .hdrMertens, sources: sources, params: .init(), sessionRoot: dir)
        let terminal = await Self.awaitTerminal(service)
        guard case .failed(let error)? = terminal?.state else {
            XCTFail("expected .failed, got \(String(describing: terminal?.state))")
            return
        }
        guard case .invalidParameter(let message) = error else {
            XCTFail("expected invalidParameter, got \(error)")
            return
        }
        XCTAssertTrue(
            message.contains("M5-2-02"),
            "the stub must name its landing plan, got: \(message)")
    }

    // MARK: - The MergeParams additive fields (KD-4)

    func testMergeParamsMertensFieldsNilByDefaultAndRoundTrip() throws {
        let defaults = StackMergeService.MergeParams()
        XCTAssertNil(defaults.mertensDeghost)
        XCTAssertNil(defaults.mertensLevels)
        // Set fields survive a Codable round-trip.
        var set = StackMergeService.MergeParams()
        set.mertensDeghost = "high"
        set.mertensLevels = 6
        let data = try JSONEncoder().encode(set)
        let back = try JSONDecoder().decode(StackMergeService.MergeParams.self, from: data)
        XCTAssertEqual(back, set)
        XCTAssertEqual(back.mertensDeghost, "high")
        XCTAssertEqual(back.mertensLevels, 6)
    }

    func testResolvedDeghostNilAndUnknownFallBackToMedium() {
        XCTAssertEqual(MertensFusion.DeghostLevel.resolved(from: nil), .medium)
        XCTAssertEqual(MertensFusion.DeghostLevel.resolved(from: "off"), .off)
        XCTAssertEqual(MertensFusion.DeghostLevel.resolved(from: "low"), .low)
        XCTAssertEqual(MertensFusion.DeghostLevel.resolved(from: "medium"), .medium)
        XCTAssertEqual(MertensFusion.DeghostLevel.resolved(from: "high"), .high)
        XCTAssertEqual(MertensFusion.DeghostLevel.resolved(from: "bogus"), .medium)
        XCTAssertEqual(MertensFusion.DeghostLevel.allCases.count, 4)
    }

    // MARK: - The EV-free precheck (KD-6 / T3)

    private static func capture(
        shutter: Double? = nil, iso: Int? = nil, aperture: Double? = nil,
        focal: Double? = nil, body: String? = "X-T5", lens: String? = "23mm"
    ) -> CaptureMetadata {
        CaptureMetadata(
            cameraModel: body, lensModel: lens, focalLength: focal,
            aperture: aperture, shutterSpeed: shutter, iso: iso)
    }

    func testMertensVerdictsSameExposurePackAdmitsCleanly() {
        let captures = [
            Self.capture(shutter: 0.005, iso: 100, aperture: 8, focal: 23),
            Self.capture(shutter: 0.005, iso: 100, aperture: 8, focal: 23),
            Self.capture(shutter: 0.005, iso: 100, aperture: 8, focal: 23),
        ]
        let verdicts = ExifPrecheck.mertensVerdicts(captures: captures)
        XCTAssertEqual(verdicts.count, 3)
        for verdict in verdicts {
            guard case .ok(let ev) = verdict else {
                XCTFail("same-exposure pack must admit cleanly, got \(verdict)")
                continue
            }
            XCTAssertEqual(ev, 0)
        }
    }

    func testMertensVerdictsApertureAndISODifferencesWarnNotReject() {
        let captures = [
            Self.capture(shutter: 0.005, iso: 100, aperture: 8, focal: 23),
            Self.capture(shutter: 0.005, iso: 200, aperture: 5.6, focal: 23),
        ]
        let verdicts = ExifPrecheck.mertensVerdicts(captures: captures)
        guard case .admittedWithWarning(let ev, let reasons) = verdicts[1] else {
            XCTFail("a differing aperture/ISO must warn, got \(verdicts[1])")
            return
        }
        XCTAssertTrue(reasons.contains { $0.contains("aperture") })
        XCTAssertTrue(reasons.contains { $0.contains("ISO") })
        // The EV is STILL composed (shutter equal → 0; ISO 100→200 = +1EV)…
        XCTAssertEqual(ev, log2(200.0 / 100.0), accuracy: 1e-9)
        // …and never consumed: the verdict vocabulary has no reject path.
        for verdict in verdicts {
            if case .rejected = verdict {
                XCTFail("mertensVerdicts must never reject: \(verdict)")
            }
        }
    }

    /// The composed EV of a verdict (either admitted shape carries it).
    private static func ev(of verdict: ExifPrecheck.Verdict) -> Double {
        switch verdict {
        case .ok(let ev): return ev
        case .admittedWithWarning(let ev, _): return ev
        case .rejected: return Double.nan
        }
    }

    func testMertensVerdictsEVCompositionTable() {
        // shutter 1/50 vs 1/200 = 4× = +2EV; ISO 100→200 = +1EV → 3.0.
        let captures = [
            Self.capture(shutter: 0.005, iso: 100, aperture: 8, focal: 23),
            Self.capture(shutter: 0.02, iso: 200, aperture: 8, focal: 23),
        ]
        let verdicts = ExifPrecheck.mertensVerdicts(captures: captures)
        XCTAssertEqual(Self.ev(of: verdicts[0]), 0)
        XCTAssertEqual(Self.ev(of: verdicts[1]), 3.0, accuracy: 1e-9)
    }

    func testMertensVerdictsAllMetadataMissingYieldsZeroEVWithWarnings() {
        let captures = [CaptureMetadata(), CaptureMetadata()]
        let verdicts = ExifPrecheck.mertensVerdicts(captures: captures)
        guard case .admittedWithWarning(let ev, let reasons) = verdicts[1] else {
            XCTFail("missing metadata must warn, got \(verdicts[1])")
            return
        }
        XCTAssertEqual(ev, 0, "missing shutter/ISO compose a flat 0 (the placeholder)")
        XCTAssertFalse(reasons.isEmpty)
    }

    func testMertensVerdictsNeverRejectsWhereStrictPrecheckDoes() {
        // The same input: differing aperture WITHOUT override + identical
        // shutters — the strict Robertson02 precheck REJECTS on both
        // counts; the Mertens verdict admits with warnings (the OQ-5
        // fork-point contract, asserted as a negative pair).
        let reference = Self.capture(shutter: 0.005, iso: 100, aperture: 8, focal: 23)
        let candidate = Self.capture(shutter: 0.005, iso: 100, aperture: 5.6, focal: 23)
        let strict = ExifPrecheck.precheck(
            reference: reference, candidate: candidate, allowOverrides: false)
        guard case .rejected = strict else {
            XCTFail("the strict precheck must reject this pair, got \(strict)")
            return
        }
        let mertens = ExifPrecheck.mertensVerdicts(
            captures: [reference, candidate])
        guard case .admittedWithWarning = mertens[1] else {
            XCTFail("mertensVerdicts must admit this pair, got \(mertens[1])")
            return
        }
    }

    func testMertensVerdictsBodyMismatchWarns() {
        let captures = [
            Self.capture(shutter: 0.01, iso: 100, aperture: 8, body: "X-T5"),
            Self.capture(shutter: 0.02, iso: 100, aperture: 8, body: "X-H2"),
        ]
        let verdicts = ExifPrecheck.mertensVerdicts(captures: captures)
        guard case .admittedWithWarning(_, let reasons) = verdicts[1] else {
            XCTFail("a body mismatch must warn, got \(verdicts[1])")
            return
        }
        XCTAssertTrue(reasons.contains { $0.contains("camera") })
    }
}
