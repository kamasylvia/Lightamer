@testable import Lightamer
@testable import LightamerCore
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensMergeUITests (Plan M5-2-02 T3, KD-5) — the UI seam face for the
// Mertens quick-merge entry (the StackMergeServiceTests coordinator-seam
// idiom: the handler IS the menu→service leg, the SwiftUI menu half is
// declarative):
//
//   • seam existence — `mertensMergeHandler` defaults nil (the menu-item
//     visibility gate: nil = the item stays hidden, the onHDRMerge shape);
//   • handler parameter mapping — the app-root wiring shape enqueues
//     `.hdrMertens` with the EXPLICIT tier ("medium"), the Robertson02
//     deGhost knob off and the nil tag (the `_mertens` default tag);
//   • the sibling Robertson02 seam rides unchanged (the two options
//     coexist; no automatic preference — OQ-4's zero auto-selection face).
// ─────────────────────────────────────────────────────────────────────────────

final class MertensMergeUITests: XCTestCase {

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
            .appendingPathComponent("mertens-ui-\(UUID().uuidString)",
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

    /// The visibility gate is the nil-default: an unwired coordinator hides
    /// the entry (the same shape as onHDRMerge/focusStackHandler).
    @MainActor
    func testMertensSeamDefaultsNilAndAcceptsWiring() {
        let coordinator = SessionCoordinator()
        XCTAssertNil(
            coordinator.mertensMergeHandler,
            "nil = the menu item stays hidden (the existing gate shape)")
        coordinator.mertensMergeHandler = { _ in }
        XCTAssertNotNil(coordinator.mertensMergeHandler)
    }

    /// The parameter mapping contract: the handler enqueues `.hdrMertens`
    /// with the explicit "medium" tier, deGhost off and the nil tag — the
    /// exact payload LightamerApp's wiring builds (captured through the
    /// merge leg).
    @MainActor
    func testMertensHandlerMapsEnqueueParamsExplicitMedium() async throws {
        let (dir, sources) = try makeSources()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        let service = try StackMergeService(
            device: device,
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { work in
                // The captured contract (the leg sees exactly what the
                // handler enqueued).
                XCTAssertEqual(work.kind, .hdrMertens)
                XCTAssertFalse(work.params.deGhost, "the Robertson02 knob stays off")
                XCTAssertNil(work.params.tag, "nil tag = the mertens default tag")
                XCTAssertEqual(
                    work.params.mertensDeghost, "medium",
                    "the UI passes the tier EXPLICITLY (OQ-3's default)")
                for _ in 0..<(work.sources.count * 3 + 2) {
                    await work.progress.step()
                }
                let product = dir.appendingPathComponent("captured_mertens.tif")
                try Data([0xCA]).write(to: product)
                return StackMergeOutcome(
                    productURL: product, holeFraction: 0,
                    alignment: Array(repeating: "full", count: work.sources.count),
                    exposureRatioVerified: Array(repeating: true, count: work.sources.count))
            })
        let coordinator = SessionCoordinator()
        coordinator.stackMergeService = service
        // The same wiring shape LightamerApp installs (KD-5's three-segment
        // chain: menu → coordinator handler → enqueue + toast).
        coordinator.mertensMergeHandler = { relPaths in
            let urls = relPaths.map { dir.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: .hdrMertens, sources: urls,
                params: StackMergeService.MergeParams(
                    deGhost: false, tag: nil, mertensDeghost: "medium"),
                sessionRoot: dir)
        }
        await coordinator.mertensMergeHandler?(sources.map(\.lastPathComponent))
        let terminal = await Self.awaitTerminal(service)
        guard case .done = terminal?.state else {
            XCTFail(
                "the seam-wired job must complete, got "
                    + "\(String(describing: terminal?.state))")
            return
        }
    }

    /// The sibling Robertson02 entry rides unchanged beside the new option
    /// (OQ-4: two menu items coexist; the default item's payload shape is
    /// byte-for-byte the 08-1 contract).
    @MainActor
    func testExistingHDRMergeSeamUnchangedBesideMertens() async throws {
        let (dir, sources) = try makeSources()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        let service = try StackMergeService(
            device: device,
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { work in
                XCTAssertEqual(work.kind, .hdrMerge, "the sibling kind unchanged")
                XCTAssertTrue(work.params.deGhost, "the de-ghost toggle face unchanged")
                for _ in 0..<(work.sources.count * 2 + 2) {
                    await work.progress.step()
                }
                let product = dir.appendingPathComponent("captured_hdr.tif")
                try Data([0xFE]).write(to: product)
                return StackMergeOutcome(
                    productURL: product, holeFraction: 0,
                    alignment: Array(repeating: "full", count: work.sources.count),
                    exposureRatioVerified: Array(repeating: true, count: work.sources.count))
            })
        let coordinator = SessionCoordinator()
        coordinator.stackMergeService = service
        coordinator.hdrMergeHandler = { relPaths, deGhost in
            let urls = relPaths.map { dir.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: .hdrMerge, sources: urls,
                params: StackMergeService.MergeParams(deGhost: deGhost),
                sessionRoot: dir)
        }
        await coordinator.hdrMergeHandler?(sources.map(\.lastPathComponent), true)
        let terminal = await Self.awaitTerminal(service)
        guard case .done = terminal?.state else {
            XCTFail(
                "the sibling seam must complete, got "
                    + "\(String(describing: terminal?.state))")
            return
        }
    }
}
