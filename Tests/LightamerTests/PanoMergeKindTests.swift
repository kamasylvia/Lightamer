@testable import LightamerCore
import CoreImage
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoMergeKindTests (Plan M5-3-01 T4; KD-6/KD-7) — the additive vocabulary
// face for the `pano` kind (raw value / provenance mirror / defaultTag /
// stepTotal 3N+6 / the done==total constant up to the typed failure point /
// the typed stub failure / the 32-source kind-conditional gate), plus the
// SIX existing kinds' unchanged snapshots (the G5 negative) and the
// MergeParams additive fields' nil-default + round-trip.
// ─────────────────────────────────────────────────────────────────────────────

final class PanoMergeKindTests: XCTestCase {

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
            .appendingPathComponent("pano-kind-\(UUID().uuidString)",
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

    // MARK: - The kind vocabulary (KD-6)

    func testPanoKindRawValueAndCaseCount() {
        XCTAssertEqual(StackMergeService.MergeKind.pano.rawValue, "pano-merge")
        XCTAssertEqual(
            StackMergeService.MergeKind(rawValue: "pano-merge"), .pano)
        // CaseIterable +1 (six existing + the additive case).
        XCTAssertEqual(StackMergeService.MergeKind.allCases.count, 7)
    }

    func testProvenanceKindMirrorAcrossAllCases() {
        for kind in StackMergeService.MergeKind.allCases {
            XCTAssertEqual(
                kind.provenanceKind.rawValue, kind.rawValue,
                "provenance mirror broke at \(kind.rawValue)")
        }
        XCTAssertEqual(SidecarProvenance.Kind.allCases.count, 7)
    }

    // MARK: - The tag vocabulary (KD-6)

    func testDefaultTagVocabularyIncludingPano() {
        // The six existing tags verbatim (the G5 snapshot face) + pano.
        XCTAssertEqual(StackMergeService.defaultTag(for: .hdrMerge), "hdr")
        XCTAssertEqual(StackMergeService.defaultTag(for: .focusStack), "fstack")
        XCTAssertEqual(StackMergeService.defaultTag(for: .stackAverage), "stack_avg")
        XCTAssertEqual(StackMergeService.defaultTag(for: .stackMedian), "stack_med")
        XCTAssertEqual(StackMergeService.defaultTag(for: .stackSigma), "stack_sig")
        XCTAssertEqual(StackMergeService.defaultTag(for: .hdrMertens), "mertens")
        XCTAssertEqual(StackMergeService.defaultTag(for: .pano), "pano")
    }

    // MARK: - The step totals (KD-6)

    func testStepTotalPanoThreeNPlusSixAndExistingSnapshots() {
        var params = StackMergeService.MergeParams()
        params.deGhost = false
        // Pano: 3N+6 regardless of the (HDR-only) deGhost knob.
        for sources in [2, 3, 5] {
            XCTAssertEqual(
                StackMergeService.stepTotal(for: sources, params: params, kind: .pano),
                sources * 3 + 6, "at N=\(sources)")
        }
        // The six existing kinds' declared totals unchanged (snapshots):
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
        XCTAssertEqual(
            StackMergeService.stepTotal(for: 3, params: params, kind: .hdrMertens), 15)
    }

    // MARK: - The typed stub (KD-6)

    func testPanoStubTypedFailure() async throws {
        let (dir, sources) = try makeSources(count: 2)
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() }, mergeLeg: nil)
        _ = try await service.enqueue(
            kind: .pano, sources: sources, params: .init(tag: nil),
            sessionRoot: dir)
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
            message.contains("M5-3-02"),
            "the stub names the plan that swaps the leg body: \(message)")
    }

    /// The KD-6 constant: with a synthetic leg bumping the pano duty
    /// (2N+5 = features N + fusion N + the 6-tail minus its own settle)
    /// before the typed failure, the window still closes EXACTLY —
    /// decode N (service) + 2N+5 (leg bumps) + 1 (the failed settle)
    /// == 3N+6.
    func testPanoDoneEqualsTotalUpToTypedFailure() async throws {
        let (dir, sources) = try makeSources(count: 3)
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { work in
                for _ in 0..<(work.sources.count * 2 + 5) {
                    await work.progress.step()
                }
                throw AppError.invalidParameter(
                    "pano-merge production leg lands in M5-3-02")
            })
        _ = try await service.enqueue(
            kind: .pano, sources: sources, params: .init(tag: nil),
            sessionRoot: dir)
        // The window was declared AT enqueue: total = 3N+6 = 15.
        let declared = await service.progress()
        XCTAssertEqual(declared.total, 3 * 3 + 6)
        let terminal = await Self.awaitTerminal(service)
        guard case .failed = terminal?.state else {
            XCTFail("expected .failed, got \(String(describing: terminal?.state))")
            return
        }
        let final = await service.progress()
        XCTAssertEqual(final.done, final.total, "the declared 3N+6 must close exactly")
        XCTAssertEqual(final.done, 15)
    }

    // MARK: - The 2..32 gate (KD-6 / OQ-4)

    func testPano32SourceGateKindConditional() async throws {
        // .pano with 33 sources → the typed refusal AT enqueue.
        let (_, panoSources) = try makeSources(count: 33)
        let panoService = try makeService()
        do {
            _ = try await panoService.enqueue(
                kind: .pano, sources: panoSources, params: .init(tag: nil))
            XCTFail("expected the 32-source gate to refuse 33 pano sources")
        } catch {
            guard case .invalidParameter(let message) = AppError(error) else {
                XCTFail("expected invalidParameter, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("at most 32"))
        }
        // The kind-CONDITIONAL shape: .hdrMerge with the same 33 sources
        // still enqueues (the six existing kinds' path byte-identical).
        let (_, hdrSources) = try makeSources(count: 33)
        let hdrService = try makeService()
        _ = try await hdrService.enqueue(
            kind: .hdrMerge, sources: hdrSources,
            params: .init(deGhost: false, tag: nil))
        let progress = await hdrService.progress()
        XCTAssertEqual(progress.total, 33 * 2 + 3, "the HDR formula verbatim")
        await hdrService.cancelAll()
    }

    // MARK: - The MergeParams additive fields (KD-7)

    func testMergeParamsPanoFieldsNilByDefaultAndRoundTrip() throws {
        let defaults = StackMergeService.MergeParams()
        XCTAssertNil(defaults.panoCanvas)
        XCTAssertNil(defaults.panoGains)
        XCTAssertNil(defaults.panoCrop)
        var set = StackMergeService.MergeParams()
        set.panoCanvas = [8000, 6000]
        set.panoGains = [1.0, 1.24, 0.87]
        set.panoCrop = [12, 8, 7988, 5992]
        let data = try JSONEncoder().encode(set)
        let back = try JSONDecoder().decode(StackMergeService.MergeParams.self, from: data)
        XCTAssertEqual(back, set)
        XCTAssertEqual(back.panoCanvas, [8000, 6000])
        XCTAssertEqual(back.panoGains, [1.0, 1.24, 0.87])
        XCTAssertEqual(back.panoCrop, [12, 8, 7988, 5992])
        // A single set field appears; the others stay absent.
        var one = StackMergeService.MergeParams()
        one.panoCanvas = [10, 5]
        let oneJSON = String(
            decoding: try JSONEncoder().encode(one), as: UTF8.self)
        XCTAssertTrue(oneJSON.contains("\"panoCanvas\""))
        XCTAssertFalse(oneJSON.contains("panoGains"))
        XCTAssertFalse(oneJSON.contains("panoCrop"))
    }
}
