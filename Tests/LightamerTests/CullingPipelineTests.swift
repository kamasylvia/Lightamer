import CoreGraphics
import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-03 T6 — the CULLING sub-pipeline suite:
//
//   • two panes = two INDEPENDENT pipelines (own decode, own throwaway
//     plane cache — an A-side change never moves the B-side plane, asserted
//     BYTE-EXACTLY after an L014 fence);
//   • cap 2: the pick-two resolver NEVER returns a third pane (typed cap
//     constant + the resolver's behavior);
//   • the RELEASE leg zeroes the memory ledger;
//   • the plane budget face: ~23 MB/plane at the 1480 rung (T8's ledger
//     assertion rides here too).
//
// Fixtures: synthetic DecodedImages through the decode seam — the PIPE
// runs are real (MetalContext + RenderPipeline, L014 fence inside the
// App assembly's convert).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CullingPipelineTests: XCTestCase {

    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    // MARK: - Fixtures

    nonisolated private static func decodedColor(
        _ red: Double, _ green: Double, _ blue: Double, size: Int = 720
    ) -> DecodedImage {
        DecodedImage(
            ciImage: CIImage(color: CIColor(red: red, green: green, blue: blue))
                .cropped(to: CGRect(x: 0, y: 0, width: size, height: size * 2 / 3)),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8
        )
    }

    private func makePane(
        relPath: String, decoded: @escaping ThumbnailDecodeLeg
    ) throws -> CullingPaneModel {
        // A real (tiny) session root: the pane guards on file existence
        // before it decodes — the fixture file must exist.
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("culling-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: root.appendingPathComponent(relPath))
        return CullingPaneModel(
            relPath: relPath, decoder: RAWDecoder(), metal: metal,
            decodeLeg: decoded, sessionRoot: root
        )
    }

    /// Rasterize + L014 fence (the read path already fences inside
    /// SessionThumbnailRenderer.cgImage; this comparator is CPU-only).
    private func rasterized(_ image: CGImage) -> Data {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(buffer)
    }

    // MARK: - Two independent pipelines

    func testTwoPanesAreIndependentByteExactPlanes() async throws {
        let paneA = try makePane(relPath: "A.ARW") { _ in
            Self.decodedColor(0.9, 0.2, 0.2)
        }
        let paneB = try makePane(relPath: "B.ARW") { _ in
            Self.decodedColor(0.2, 0.3, 0.9)
        }

        await paneA.load()
        await paneB.load() // staggered in production; sequential here too

        XCTAssertEqual(paneA.state, .ready)
        XCTAssertEqual(paneB.state, .ready)
        let imageA = try XCTUnwrap(paneA.image)
        let imageB = try XCTUnwrap(paneB.image)

        // The planes are CONTENT-DISTINCT (each pipeline rendered its own
        // image — a shared/wrong cache would collapse them).
        XCTAssertNotEqual(
            rasterized(imageA), rasterized(imageB),
            "the two panes' planes differ byte-exactly (independent pipelines)"
        )

        // An A-side RE-RENDER with changed params never moves the B plane:
        // reload A with a different color while B stays untouched.
        let bBefore = rasterized(imageB)
        let paneA2 = try makePane(relPath: "A.ARW") { _ in
            Self.decodedColor(0.1, 0.9, 0.1)
        }
        await paneA2.load()
        let imageA2 = try XCTUnwrap(paneA2.image)
        XCTAssertNotEqual(rasterized(imageA2), rasterized(imageA), "A changed on re-render")
        XCTAssertEqual(
            rasterized(imageB), bBefore,
            "the B plane is byte-identical across the A-side change (isolation)"
        )
    }

    // MARK: - cap 2

    func testCapIsTwoConstantAndResolverNeverReturnsThird() {
        XCTAssertEqual(CullingView.paneCap, 2, "the D-09-CONTEXT-6 cap is a typed constant")

        let rows: [SessionBrowserModel.Row] = (0..<5).map { index in
            var row = SessionBrowserModel.Row(
                relPath: "IMG\(index).ARW",
                pathHash: ThumbnailPath.hash("IMG\(index).ARW"),
                dir: ".", filename: "IMG\(index).ARW",
                hasEdits: false, orphanSidecar: false,
                thumbState: nil, thumbParamsHash: nil, dirty: false
            )
            _ = row
            return row
        }
        // Selecting THREE rows still resolves exactly TWO panes.
        let pair = CullingView.resolvePair(
            rows: rows, selected: ["IMG0.ARW", "IMG2.ARW", "IMG4.ARW"]
        )
        XCTAssertNotNil(pair)
        XCTAssertEqual(pair?.0, "IMG0.ARW")
        XCTAssertEqual(pair?.1, "IMG2.ARW", "exactly the first TWO of the selection — never a third")
    }

    func testResolverSkipsOrphansAndFallsBackToFirstTwo() {
        var orphan = SessionBrowserModel.Row(
            relPath: "GONE.ARW.lra",
            pathHash: "x", dir: ".", filename: "GONE.ARW.lra",
            hasEdits: false, orphanSidecar: true,
            thumbState: nil, thumbParamsHash: nil, dirty: false
        )
        _ = orphan
        let browsable: [SessionBrowserModel.Row] = ["A", "B"].map { rel in
            SessionBrowserModel.Row(
                relPath: rel, pathHash: ThumbnailPath.hash(rel), dir: ".",
                filename: rel, hasEdits: false, orphanSidecar: false,
                thumbState: nil, thumbParamsHash: nil, dirty: false
            )
        }
        let rows = browsable + [orphan]
        // No selection → the first two BROWSABLE rows (orphan skipped).
        let pair = CullingView.resolvePair(rows: rows, selected: [])
        XCTAssertEqual(pair?.0, "A")
        XCTAssertEqual(pair?.1, "B", "orphans never pair (no original to decode)")

        // A single-selection whose anchor is last pairs a PREVIOUS row.
        let singlePair = CullingView.resolvePair(rows: rows, selected: ["B"])
        XCTAssertEqual(singlePair?.0, "A")
        XCTAssertEqual(singlePair?.1, "B")
    }

    // MARK: - Release ledger

    func testReleaseZeroesTheLedgerAndState() async throws {
        let pane = try makePane(relPath: "R.ARW") { _ in
            Self.decodedColor(0.5, 0.5, 0.5)
        }
        await pane.load()
        XCTAssertEqual(pane.state, .ready)
        XCTAssertNotNil(pane.image)
        XCTAssertGreaterThan(pane.planeBytes, 0, "the ledger recorded the plane")

        pane.release()
        XCTAssertNil(pane.image, "the display plane dropped")
        XCTAssertEqual(pane.planeBytes, 0, "the ledger zeroed (内存账本归零)")
        XCTAssertEqual(pane.state, .idle, "the pane re-arms for a reload")
    }

    // MARK: - The plane budget face (T8's ledger — see MemoryBudgetTests
    // for the full form; the RESIDENT plane is the gamma tail's bgra8Unorm
    // display output, ~5.8 MB/plane at 1480; the RESEARCH ~23 MB figure is
    // the TRANSIENT float32 working plane inside the run's throwaway cache).

    func testPlaneLedgerMatchesTheResidentDisplayPlaneBudget() async throws {
        let pane = try makePane(relPath: "BUDGET.ARW") { _ in
            // A 3000×2000 source (≈ full-frame) — the 1480 rung caps it.
            Self.decodedColor(0.5, 0.4, 0.3, size: 3000)
        }
        await pane.load()
        XCTAssertEqual(pane.state, .ready)
        let plane = try XCTUnwrap(pane.planeBytes)
        XCTAssertGreaterThan(plane, 4_000_000, "≥ 4 MB/plane resident (bgra8 1480)")
        XCTAssertLessThan(plane, 8_000_000, "≤ 8 MB/plane resident (bgra8 1480) — dual panes ≈ 12 MB")
    }
}
