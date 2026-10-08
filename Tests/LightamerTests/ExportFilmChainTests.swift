@testable import Lightamer
import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportFilmChainTests (Plan M3-3-02 T6, KD-7 — EXPORT bundle, the
// ExportDrtChainTests/ExportQueueTests harness) — the $jobFilmTail seam:
//
//   1. NO-FILM ZERO DRIFT: a job without a film carrier renders the legacy
//      face (the TaskLocal nil consult — the request field absent).
//   2. ASSEMBLY→RENDER DELIVERY (the E1 proof): the queue's detached
//      render leg sees the job's OWN film carrier through
//      `ExportRenderer.jobFilmTail` (the injected leg captures it — the
//      three-edit-point seam works across the detached-task boundary).
//   3. PER-IMAGE FAN-OUT: two images with DIFFERENT carriers — each job's
//      leg observes its own (the enqueue indexing).
//   4. THE REQUEST FIELD WINS: an explicit Request.filmTail overrides the
//      TaskLocal (the drtTail consult's twin).
//   5. COUNT GATE: a mismatched filmTails array = the typed rejection
//      BEFORE any environment lookup (the O-2 posture).
// ─────────────────────────────────────────────────────────────────────────────

final class ExportFilmChainTests: XCTestCase {

    private func makeParams(strength: Float) -> FilmTailParams {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.strength = strength
        return FilmTailParams(
            record: record, filmProfile: nil, paperProfile: nil,
            materialPairHash: 0)
    }

    private func makeImageURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).tif")
    }

    /// An injected render leg that CAPTURES the TaskLocal the queue scoped
    /// around it (the E1 proof's observation face) and fails the job.
    private final class CaptureBox: @unchecked Sendable {
        var values: [FilmTailParams?] = []
        var naming: [UUID] = []
    }

    @MainActor
    func testQueueDeliversTheFilmCarrierAcrossTheDetachedLeg() async throws {
        let box = CaptureBox()
        let queue = ExportQueue(
            metal: nil, registry: ModuleRegistry.makeDefault(),
            renderLeg: { snapshot, _ in
                box.values.append(ExportRenderer.jobFilmTail)
                throw AppError.cancelled  // fail fast — the capture is the point
            },
            encodeLeg: { _, _ in throw AppError.cancelled })
        let imageA = makeImageURL("film-export-a")
        let imageB = makeImageURL("film-export-b")
        let carrierA = makeParams(strength: 0.4)
        let carrierB = makeParams(strength: 0.9)
        _ = await queue.enqueue(
            images: [(url: imageA, relPath: "a.tif"), (url: imageB, relPath: "b.tif")],
            variants: [Self.makeVariant()],
            destinationDirectory: FileManager.default.temporaryDirectory,
            filmTails: [carrierA, carrierB])
        // Settle: the jobs fail fast (cancelled) — poll the capture.
        let start = Date()
        while box.values.count < 2, Date().timeIntervalSince(start) < 10 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(box.values.count, 2, "both render legs ran (capture proof)")
        let first = try XCTUnwrap(box.values.min { $0?.record.strength ?? 0 < $1?.record.strength ?? 0 })
        let last = try XCTUnwrap(box.values.max { $0?.record.strength ?? 0 < $1?.record.strength ?? 0 })
        XCTAssertEqual(first?.record.strength, 0.4, "image A's carrier reached ITS leg")
        XCTAssertEqual(last?.record.strength, 0.9, "image B's carrier reached ITS leg (the per-image fan-out)")
        _ = (carrierB, imageB) // silence unused warnings in narrow configs
    }

    @MainActor
    func testNoFilmJobKeepsTheLegacyFace() async throws {
        let box = CaptureBox()
        let queue = ExportQueue(
            metal: nil, registry: ModuleRegistry.makeDefault(),
            renderLeg: { _, _ in
                box.values.append(ExportRenderer.jobFilmTail)
                throw AppError.cancelled
            },
            encodeLeg: { _, _ in throw AppError.cancelled })
        _ = await queue.enqueue(
            images: [(url: makeImageURL("film-legacy"), relPath: "l.tif")],
            variants: [Self.makeVariant()],
            destinationDirectory: FileManager.default.temporaryDirectory)
        let start = Date()
        while box.values.count < 1, Date().timeIntervalSince(start) < 10 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(box.values, [nil], "no carrier = the zero-path legacy face")
    }

    func testRequestCarriesTheFilmTailFieldAndConsultPrefersIt() {
        // The Request field (additive, the drtTail slot's twin) stores;
        // renderStage's consult is `request.filmTail ?? jobFilmTail` — the
        // explicit field wins over the TaskLocal (nil request + a nil
        // TaskLocal = the legacy face).
        let explicit = makeParams(strength: 0.7)
        let request = ExportRenderer.Request(
            imageURL: makeImageURL("film-explicit"),
            destinationDirectory: FileManager.default.temporaryDirectory,
            occupiedNames: [],
            variant: Self.makeVariant(),
            filmTail: explicit)
        XCTAssertEqual(request.filmTail?.record.strength, 0.7)
        XCTAssertEqual(request.filmTail ?? nil, explicit)
        XCTAssertNil(ExportRenderer.Request(
            imageURL: makeImageURL("film-legacy"),
            destinationDirectory: FileManager.default.temporaryDirectory,
            occupiedNames: [],
            variant: Self.makeVariant()).filmTail, "the default = the legacy face")
    }

    @MainActor
    func testMismatchedFilmTailsCountIsTypedRejected() async throws {
        let state = ExportState()
        await state.installQueueForTesting(ExportQueue(
            metal: nil, registry: ModuleRegistry.makeDefault(),
            renderLeg: { _, _ in throw AppError.cancelled },
            encodeLeg: { _, _ in throw AppError.cancelled }))
        do {
            try await state.enqueueExportM2(
                images: [makeImageURL("a"), makeImageURL("b")],
                instancesOverrides: [nil, nil],
                drtRecord: DrtRecord(),
                variant: Self.makeVariant(),
                destination: FileManager.default.temporaryDirectory,
                subfolder: nil,
                namingPattern: "{stem}",
                filmTails: [makeParams(strength: 0.5)])
            XCTFail("the count mismatch must throw typed")
        } catch let error as AppError {
            XCTAssertTrue(
                String(describing: error).contains("filmTails"),
                "the typed rejection names the carrier (the O-2 posture)")
        }
    }

    // MARK: - fixtures

    private static func makeVariant() -> ExportVariant {
        ExportVariant(format: .jpeg(quality: 0.9), colorSpace: .sRGB)
    }
}
