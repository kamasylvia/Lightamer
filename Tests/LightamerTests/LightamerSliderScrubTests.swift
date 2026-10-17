import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// LightamerSliderScrubTests (Plan M7-6-01 T3, UQ-L1 — APP domain) — the
// readout scrub's golden family, driven by the PURE session value type (the
// M3-1-02 YiyinSheetDragSession seam shape: the interaction discipline is
// asserted against the session/harness, never the UI):
//
//   • the travel→value map (zero travel = identity, forward/backward, the
//     range clamps both ends);
//   • the Shift ×0.1 family (including the clamp and the mid-scrub toggle
//     re-scaling the whole travel from the start point);
//   • the begin/end pairing (one scrub = exactly one onDragBegin + one
//     onDragEnd + a non-empty onChange sequence — the one-continuous-commit
//     semantic via the D-H1 three-callback face, never a bypass).
// ─────────────────────────────────────────────────────────────────────────────

final class LightamerSliderScrubTests: XCTestCase {

    // MARK: - The travel→value map

    func testTravelValueMappingFamily() {
        let range = 0.0...1.0

        // Zero travel = identity (the drag sat still).
        var session = LightamerSliderScrubSession(
            startValue: 0.5, startX: 0, range: range, trackWidth: 200)
        XCTAssertEqual(session.tick(atX: 0, shiftActive: false), 0.5)

        // Forward: full-row travel (200pt) spans the range.
        session = LightamerSliderScrubSession(
            startValue: 0.5, startX: 0, range: range, trackWidth: 200)
        XCTAssertEqual(session.tick(atX: 100, shiftActive: false), 1.0)

        // Backward: the same travel in the negative direction.
        session = LightamerSliderScrubSession(
            startValue: 0.5, startX: 0, range: range, trackWidth: 200)
        XCTAssertEqual(session.tick(atX: -100, shiftActive: false), 0.0)

        // A partial travel lands proportionally.
        session = LightamerSliderScrubSession(
            startValue: 0.5, startX: 0, range: range, trackWidth: 200)
        XCTAssertEqual(session.tick(atX: 50, shiftActive: false), 0.75)

        // The range clamps BOTH ends (the overshoot never escapes).
        session = LightamerSliderScrubSession(
            startValue: 0.5, startX: 0, range: range, trackWidth: 200)
        XCTAssertEqual(session.tick(atX: 5000, shiftActive: false), 1.0)
        session = LightamerSliderScrubSession(
            startValue: 0.5, startX: 0, range: range, trackWidth: 200)
        XCTAssertEqual(session.tick(atX: -5000, shiftActive: false), 0.0)

        // A start inside a non-zero range keeps the offset anchor.
        var offset = LightamerSliderScrubSession(
            startValue: 7.5, startX: 0, range: 0.0...10.0, trackWidth: 100)
        XCTAssertEqual(offset.tick(atX: 10, shiftActive: false), 8.5)
    }

    // MARK: - The Shift ×0.1 family

    func testShiftSlowdownAndClampFamily() {
        let range = 0.0...10.0

        // Plain tick: 20pt of a 100pt row moves 2.0 units.
        var session = LightamerSliderScrubSession(
            startValue: 5, startX: 0, range: range, trackWidth: 100)
        XCTAssertEqual(session.tick(atX: 20, shiftActive: false), 7.0)

        // Shift ticks run 1/10 speed from the SAME start.
        session = LightamerSliderScrubSession(
            startValue: 5, startX: 0, range: range, trackWidth: 100)
        XCTAssertEqual(session.tick(atX: 20, shiftActive: true), 5.2)

        // The clamp still governs under Shift.
        session = LightamerSliderScrubSession(
            startValue: 5, startX: 0, range: range, trackWidth: 100)
        XCTAssertEqual(session.tick(atX: 10_000, shiftActive: true), 10.0)

        // The mid-scrub toggle re-scales the whole travel from the START
        // point (the lightcraft semantic — not a per-tick slowdown).
        session = LightamerSliderScrubSession(
            startValue: 5, startX: 0, range: range, trackWidth: 100)
        XCTAssertEqual(session.tick(atX: 40, shiftActive: false), 9.0)
        XCTAssertEqual(session.tick(atX: 40, shiftActive: true), 5.4)
    }

    // MARK: - The begin/end pairing (one scrub = one continuous commit)

    /// The view's callback mapping replayed as a harness: begin →
    /// onDragBegin, per-tick → onChange, end → onDragEnd. The harness is
    /// the machine-checkable seam — the production view maps the SAME
    /// three calls verbatim (the D-H1 face), so pairing behavior here is
    /// the pairing behavior on screen.
    private struct ScrubHarness {
        private(set) var beginCalls = 0
        private(set) var endCalls = 0
        private(set) var changes: [Double] = []
        private var session: LightamerSliderScrubSession?

        mutating func begin(
            startValue: Double, range: ClosedRange<Double>, trackWidth: CGFloat
        ) {
            session = LightamerSliderScrubSession(
                startValue: startValue, startX: 0, range: range,
                trackWidth: trackWidth)
            beginCalls += 1
        }

        mutating func tick(atX x: CGFloat, shift: Bool) {
            guard let value = session?.tick(atX: x, shiftActive: shift) else {
                return
            }
            changes.append(value)
        }

        mutating func end() {
            session?.end()
            session = nil
            endCalls += 1
        }
    }

    func testScrubBeginEndPairingIsExactlyOneContinuousCommit() {
        var harness = ScrubHarness()
        harness.begin(startValue: 0.5, range: 0.0...1.0, trackWidth: 200)
        harness.tick(atX: 40, shift: false)
        harness.tick(atX: 80, shift: false)
        harness.tick(atX: 60, shift: false)
        harness.end()

        XCTAssertEqual(harness.beginCalls, 1, "one scrub = one begin")
        XCTAssertEqual(harness.endCalls, 1, "one scrub = one end")
        XCTAssertEqual(harness.changes.count, 3, "the per-tick sequence rides")
        XCTAssertEqual(
            harness.changes.last, 0.8, "the settled value is the last tick")

        // A zero-tick scrub (a stray ≥3pt nudge) is still exactly one pair.
        harness = ScrubHarness()
        harness.begin(startValue: 0.5, range: 0.0...1.0, trackWidth: 200)
        harness.end()
        XCTAssertEqual(harness.beginCalls, 1)
        XCTAssertEqual(harness.endCalls, 1)
        XCTAssertTrue(harness.changes.isEmpty, "no phantom tick rides a nudge")
    }
}
