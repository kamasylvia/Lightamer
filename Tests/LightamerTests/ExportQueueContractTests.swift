import Foundation
import LightamerCore
import XCTest

/// ExportQueue contract tests (Plan 11-01 T3): the transition-table vectors,
/// Sendable compile-time proofs, and the pinned constants. This is the
/// CONTRACT face only — the 11-04 actor gets its own behavior suite.
final class ExportQueueContractTests: XCTestCase {

    // MARK: - Legal transition vectors (pending → rendering → encoding → …)

    func testForwardPathTransitions() {
        XCTAssertTrue(ExportJobState.pending.canTransition(to: .rendering))
        XCTAssertTrue(ExportJobState.rendering.canTransition(to: .encoding))
        XCTAssertTrue(ExportJobState.encoding.canTransition(to: .done(URL(fileURLWithPath: "/o/a.jpg"))))
    }

    /// Every early-exit edge: cancel from each active phase, fail from the
    /// legs' phases.
    func testEarlyExitTransitions() {
        XCTAssertTrue(ExportJobState.pending.canTransition(to: .cancelled))
        XCTAssertTrue(ExportJobState.rendering.canTransition(to: .failed(.decodeFailed("x"))))
        XCTAssertTrue(ExportJobState.rendering.canTransition(to: .cancelled))
        XCTAssertTrue(ExportJobState.encoding.canTransition(to: .failed(.fileUnreadable("x"))))
        XCTAssertTrue(ExportJobState.encoding.canTransition(to: .cancelled))
    }

    // MARK: - Illegal transition vectors (runtime assertion table)

    func testSkipAndJumpTransitionsAreIllegal() {
        XCTAssertFalse(ExportJobState.pending.canTransition(to: .encoding))
        XCTAssertFalse(ExportJobState.pending.canTransition(to: .done(URL(fileURLWithPath: "/o/a.jpg"))))
        XCTAssertFalse(ExportJobState.pending.canTransition(to: .failed(.cancelled)))
        XCTAssertFalse(ExportJobState.rendering.canTransition(to: .done(URL(fileURLWithPath: "/o/a.jpg"))))
        XCTAssertFalse(ExportJobState.encoding.canTransition(to: .rendering))
    }

    func testNoTransitionsLeaveTerminalStates() {
        let terminals: [ExportJobState] = [
            .done(URL(fileURLWithPath: "/o/a.jpg")),
            .failed(.decodeFailed("x")),
            .cancelled,
        ]
        for terminal in terminals {
            for next in terminalNeighbors {
                XCTAssertFalse(
                    terminal.canTransition(to: next),
                    "\(terminal) must not transition to \(next)")
            }
            XCTAssertFalse(terminal.canTransition(to: terminal))
        }
    }

    func testSelfTransitionsAreIllegal() {
        XCTAssertFalse(ExportJobState.pending.canTransition(to: .pending))
        XCTAssertFalse(ExportJobState.rendering.canTransition(to: .rendering))
        XCTAssertFalse(ExportJobState.encoding.canTransition(to: .encoding))
    }

    func testTerminalityFlag() {
        XCTAssertFalse(ExportJobState.pending.isTerminal)
        XCTAssertFalse(ExportJobState.rendering.isTerminal)
        XCTAssertFalse(ExportJobState.encoding.isTerminal)
        XCTAssertTrue(ExportJobState.done(URL(fileURLWithPath: "/o/a.jpg")).isTerminal)
        XCTAssertTrue(ExportJobState.failed(.cancelled).isTerminal)
        XCTAssertTrue(ExportJobState.cancelled.isTerminal)
    }

    private var terminalNeighbors: [ExportJobState] {
        [
            .pending, .rendering, .encoding,
            .done(URL(fileURLWithPath: "/o/other.jpg")),
            .failed(.memoryExceeded(1)),
            .cancelled,
        ]
    }

    // MARK: - Sendable compile-time proofs

    /// Compile-time Sendable proofs: these generic constraints fail to
    /// compile if any contract type loses Sendable conformance.
    func assertSendable<T: Sendable>(_: T.Type) {}

    func testContractTypesAreSendable() {
        assertSendable(ExportJobState.self)
        assertSendable(ExportJobSnapshot.self)
        assertSendable(ExportJobPhase.self)
        assertSendable(ExportProgress.self)
        assertSendable(ExportRenderArtifact.self)
        assertSendable(ExportRenderLeg.self)
        assertSendable(ExportEncodeLeg.self)
        // The carrier types the contract composes:
        assertSendable(ExportVariant.self)
        assertSendable(YiyinExportSettings.self)
    }

    // MARK: - Snapshot & progress shapes

    func testSnapshotCarriesContractFields() {
        let id = UUID()
        let snapshot = ExportJobSnapshot(
            id: id,
            imageURL: URL(fileURLWithPath: "/s/Capture/a.arw"),
            relPath: "Capture/a.arw",
            variants: [ExportVariant(format: .jpeg(quality: 0.9), colorSpace: .sRGB)],
            seq: 7,
            generation: 2,
            state: .pending)
        XCTAssertEqual(snapshot.id, id)
        XCTAssertEqual(snapshot.relPath, "Capture/a.arw")
        XCTAssertEqual(snapshot.variants.count, 1)
        XCTAssertEqual(snapshot.seq, 7)
        XCTAssertEqual(snapshot.generation, 2)
        XCTAssertTrue(snapshot.state.isTerminal == false)
    }

    func testProgressTwoLayers() {
        let idle = ExportProgress(done: 3, total: 5, activePhase: nil)
        XCTAssertEqual(idle.done, 3)
        XCTAssertEqual(idle.total, 5)
        XCTAssertNil(idle.activePhase)

        let rendering = ExportProgress(done: 3, total: 5, activePhase: .rendering)
        XCTAssertEqual(rendering.activePhase, .rendering)
        let encoding = ExportProgress(done: 3, total: 5, activePhase: .encoding)
        XCTAssertEqual(encoding.activePhase, .encoding)
    }

    // MARK: - Pinned constants (D-11-CONTEXT-2 / OQ-11-8)

    /// The memory red line: exactly one job at a time (≈5 GB peak per job at
    /// 100 MP, RESEARCH §4.5 — two concurrent jobs break the budget).
    func testConcurrencyIsPinnedToOne() {
        XCTAssertEqual(ExportQueueContract.concurrency, 1)
    }

    /// OQ-11-8: the yield-to-editor switch exists as an interface slot but
    /// v1 keeps it OFF (fixed Utility QoS + concurrency 1).
    func testYieldsToEditorSlotIsOffInV1() {
        XCTAssertFalse(ExportQueueContract.yieldsToEditor)
    }

    /// The artifact handoff box is value-comparable (queue tests assert on
    /// the token they injected).
    func testRenderArtifactRoundTripsThroughLegs() async throws {
        let artifact = ExportRenderArtifact(token: 42, width: 1200, height: 800)
        let renderLeg: ExportRenderLeg = { _, _ in artifact }
        let encodeLeg: ExportEncodeLeg = { received, _ in
            XCTAssertEqual(received, artifact)
            return URL(fileURLWithPath: "/o/synthetic.jpg")
        }
        let snapshot = ExportJobSnapshot(
            id: UUID(), imageURL: URL(fileURLWithPath: "/s/a.arw"), relPath: "a.arw",
            variants: [], seq: 0, generation: 0, state: .pending)
        let rendered = try await renderLeg(
            snapshot,
            ExportJobContext(
                destinationDirectory: URL(fileURLWithPath: "/o"),
                occupiedNames: []))
        let url = try await encodeLeg(rendered, ExportVariant(
            format: .jpeg(quality: 0.9), colorSpace: .sRGB))
        XCTAssertEqual(url.path, "/o/synthetic.jpg")
    }
}
