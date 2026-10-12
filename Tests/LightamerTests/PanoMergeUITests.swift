@testable import Lightamer
@testable import LightamerCore
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoMergeUITests (Plan M5-3-03 T2, KD-1/KD-2/KD-3) — the UI seam face for
// the panorama merge entry (the MertensMergeUITests idiom: the handler IS
// the menu→service leg, the SwiftUI menu half is declarative):
//
//   • seam existence + the visibility gate — `panoMergeHandler` defaults
//     nil (nil = the menu item stays hidden, the onHDRMertens shape);
//   • handler parameter mapping — the app-root wiring shape enqueues
//     `.pano` with the explicit deGhost false (not consumed by the pano
//     leg) and the nil tag (→ `defaultTag(.pano)` = "pano", the `_pano`
//     split-account name);
//   • the typed three-state zh mapping (KD-3) — the pure prefix table
//     maps the three Core canonical prefixes both ways (non-prefix =
//     passthrough, the existing error face's zero-change invariant);
//   • the sibling merge seams ride unchanged beside the third option
//     (OQ-7: three merge options coexist; no automatic preference).
// ─────────────────────────────────────────────────────────────────────────────

final class PanoMergeUITests: XCTestCase {

    private static func stubDecodedImage() -> DecodedImage {
        let ci = CIImage(color: CIColor.gray).cropped(
            to: CGRect(x: 0, y: 0, width: 4, height: 4))
        return DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    private func makeSources() throws -> (dir: URL, sources: [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pano-ui-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        var sources: [URL] = []
        for index in 0..<2 {
            let url = dir.appendingPathComponent("src\(index).tif")
            try Data("fixture-\(index)".utf8).write(to: url)
            sources.append(url)
        }
        return (dir, sources)
    }

    private static func awaitTerminal(
        _ service: StackMergeService, timeout: TimeInterval = 10
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

    /// The visibility gate is the nil-default: an unwired coordinator
    /// hides the entry (the same shape as onHDRMerge/onHDRMertens/
    /// focusStackHandler). Wiring flips it visible.
    @MainActor
    func testPanoSeamDefaultsNilAndAcceptsWiring() {
        let coordinator = SessionCoordinator()
        XCTAssertNil(
            coordinator.panoMergeHandler,
            "nil = the menu item stays hidden (the existing gate shape)")
        coordinator.panoMergeHandler = { _ in }
        XCTAssertNotNil(coordinator.panoMergeHandler)
    }

    /// The parameter mapping contract: the handler enqueues `.pano` with
    /// the explicit deGhost false and the nil tag — the exact payload
    /// LightamerApp's wiring builds (captured through the merge leg) —
    /// and the split-account name consumes `defaultTag(.pano)` = "pano".
    @MainActor
    func testPanoHandlerMapsEnqueueParamsAndDefaultTag() async throws {
        let (dir, sources) = try makeSources()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        XCTAssertEqual(
            StackMergeService.defaultTag(for: .pano), "pano",
            "the nil tag resolves to the _pano split-account name")
        let service = try StackMergeService(
            device: device,
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { work in
                // The captured contract (the leg sees exactly what the
                // handler enqueued).
                XCTAssertEqual(work.kind, .pano)
                XCTAssertFalse(
                    work.params.deGhost,
                    "deGhost is not consumed by the pano leg — the explicit false")
                XCTAssertNil(work.params.tag, "nil tag = the pano default tag")
                for _ in 0..<(work.sources.count * 2 + 5) {
                    await work.progress.step()
                }
                let product = dir.appendingPathComponent("captured_pano.tif")
                try Data([0xAB]).write(to: product)
                return StackMergeOutcome(
                    productURL: product, holeFraction: 0,
                    alignment: Array(repeating: "full", count: work.sources.count),
                    exposureRatioVerified: Array(repeating: true, count: work.sources.count))
            })
        let coordinator = SessionCoordinator()
        coordinator.stackMergeService = service
        // The same wiring shape LightamerApp installs (KD-2's chain:
        // menu → coordinator handler → enqueue + toast).
        coordinator.panoMergeHandler = { relPaths in
            let urls = relPaths.map { dir.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: .pano, sources: urls,
                params: StackMergeService.MergeParams(
                    deGhost: false, tag: nil),
                sessionRoot: dir)
        }
        await coordinator.panoMergeHandler?(sources.map(\.lastPathComponent))
        let terminal = await Self.awaitTerminal(service)
        guard case .done = terminal?.state else {
            XCTFail(
                "the seam-wired job must complete, got "
                    + "\(String(describing: terminal?.state))")
            return
        }
    }

    /// The typed three-state mapping (KD-3): each canonical Core prefix
    /// resolves to its catalog key — bare, AppError-wrapped, and with a
    /// typed detail tail — while non-pano messages resolve to nil.
    func testPanoFailureKeyMapsThreePrefixesBothWays() {
        let cases: [(message: String, key: String?)] = [
            (PanoMatch.FailurePrefix.alignment, "pano_error_alignment"),
            (
                "Invalid setting: \(PanoMatch.FailurePrefix.alignment)path pair",
                "pano_error_alignment"
            ),
            (PanoMatch.FailurePrefix.disconnected, "pano_error_disconnected"),
            (
                "Invalid setting: "
                    + "\(PanoMatch.FailurePrefix.disconnected)src3 ↔ src0",
                "pano_error_disconnected"
            ),
            (PanoMatch.FailurePrefix.canvas, "pano_error_canvas"),
            (
                "Invalid setting: \(PanoMatch.FailurePrefix.canvas)8 rounds",
                "pano_error_canvas"
            ),
            // Non-prefix messages pass through (nil = no mapping).
            ("stack merge needs ≥ 2 sources, got 1", nil),
            ("pano merge accepts at most 32 sources, got 40", nil),
            ("Failed to decode. truncated The file may be corrupted.", nil),
            ("", nil),
        ]
        for (message, expected) in cases {
            XCTAssertEqual(
                PanoFailureCopy.failureKey(for: message), expected,
                "prefix-table miss for: \(message)")
        }
    }

    /// The consumption face: a non-pano message is byte-identical
    /// (passthrough); a matched message drops the canonical prefix, keeps
    /// the typed detail and never leaks the English canonical phrase.
    func testPanoFailureMessagePassthroughAndSubstitution() {
        // Passthrough — the existing error face zero-change invariant.
        let unrelated = "stack merge needs ≥ 2 sources, got 1"
        XCTAssertEqual(PanoFailureCopy.failureMessage(for: unrelated), unrelated)

        // Substitution keeps the typed detail (locale-agnostic tail) and
        // drops both the AppError head and the canonical phrase.
        let detail = "no edge between src0 and src1"
        let raw = "Invalid setting: "
            + "\(PanoMatch.FailurePrefix.disconnected)\(detail)"
        let mapped = PanoFailureCopy.failureMessage(for: raw)
        XCTAssertNotEqual(mapped, raw)
        XCTAssertTrue(
            mapped.hasSuffix(detail), "the typed detail survives: \(mapped)")
        XCTAssertFalse(
            mapped.contains(PanoMatch.FailurePrefix.disconnected),
            "the English canonical phrase never leaks: \(mapped)")

        // The empty-detail form still maps (no trailing separator).
        let bare = "Invalid setting: \(PanoMatch.FailurePrefix.canvas)"
        let bareMapped = PanoFailureCopy.failureMessage(for: bare)
        XCTAssertFalse(bareMapped.isEmpty)
        XCTAssertFalse(bareMapped.contains("panorama"))
    }

    /// The sibling merge seams ride unchanged beside the third option
    /// (OQ-7: three merge options coexist): with the pano handler wired,
    /// the Mertens handler still drives its own kind through the same
    /// service (no interference, no preference).
    @MainActor
    func testSiblingMertensSeamCoexistsBesidePano() async throws {
        let (dir, sources) = try makeSources()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        final class KindLog: @unchecked Sendable {
            private let lock = NSLock()
            private var kinds: [StackMergeService.MergeKind] = []
            func append(_ kind: StackMergeService.MergeKind) {
                lock.lock(); kinds.append(kind); lock.unlock()
            }
            func snapshot() -> [StackMergeService.MergeKind] {
                lock.lock(); defer { lock.unlock() }
                return kinds
            }
        }
        let log = KindLog()
        let service = try StackMergeService(
            device: device,
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { work in
                log.append(work.kind)
                let steps = work.kind == .pano
                    ? work.sources.count * 2 + 5
                    : work.sources.count * 4 + 2
                for _ in 0..<steps { await work.progress.step() }
                let product = dir.appendingPathComponent(
                    work.kind == .pano ? "p.tif" : "m.tif")
                try Data([0x11]).write(to: product)
                return StackMergeOutcome(
                    productURL: product, holeFraction: 0,
                    alignment: Array(repeating: "full", count: work.sources.count),
                    exposureRatioVerified: Array(repeating: true, count: work.sources.count))
            })
        let coordinator = SessionCoordinator()
        coordinator.stackMergeService = service
        // Both handlers wired — the coexistence face.
        coordinator.panoMergeHandler = { relPaths in
            let urls = relPaths.map { dir.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: .pano, sources: urls,
                params: StackMergeService.MergeParams(deGhost: false, tag: nil),
                sessionRoot: dir)
        }
        coordinator.mertensMergeHandler = { relPaths in
            let urls = relPaths.map { dir.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: .hdrMertens, sources: urls,
                params: StackMergeService.MergeParams(
                    deGhost: false, tag: nil, mertensDeghost: "medium"),
                sessionRoot: dir)
        }
        await coordinator.panoMergeHandler?(sources.map(\.lastPathComponent))
        await coordinator.mertensMergeHandler?(sources.map(\.lastPathComponent))
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, log.snapshot().count < 2 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(
            Set(log.snapshot()), [.pano, .hdrMertens],
            "both kinds ran through the shared service unchanged")
    }
}
