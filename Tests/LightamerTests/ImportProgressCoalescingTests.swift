import LightamerCore
import XCTest

@testable import Lightamer

/// FIX2 T2 (D-7): the progress-delivery coalescer's four semantics —
/// leading delivery immediate / in-window coalescing (latest-wins) / the
/// trailing delivery never drops the tail / terminal bypass + supersede.
/// The clock is injected; real sleeps only on the consumer side with wide
/// margins. The controller-nil terminal carrier (runImport's direct
/// `importProgress = nil` write) is NOT routed through the coalescer by
/// construction (the run tail writes it after `importFolder` returns) —
/// the service-side `.completed`/`.cancelled` snapshots asserted here are
/// the second carrier; both carriers reach the UI unchanged.
final class ImportProgressCoalescingTests: XCTestCase {

    // MARK: fixtures

    private let interval: Duration = .milliseconds(150)

    private func snapshot(
        _ processed: Int, _ phase: ImportProgress.Phase = .importing
    ) -> ImportProgress {
        ImportProgress(phase: phase, total: 6, processed: processed)
    }

    /// A thread-safe clock the tests steer by hand.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: ContinuousClock.Instant = ContinuousClock.now
        var now: ContinuousClock.Instant {
            lock.lock(); defer { lock.unlock() }
            return current
        }
        func advance(_ d: Duration) {
            lock.lock()
            current = current + d
            lock.unlock()
        }
    }

    /// Delivered snapshots, thread-safe (deliveries hop the main actor).
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ImportProgress] = []
        func append(_ p: ImportProgress) {
            lock.lock(); items.append(p); lock.unlock()
        }
        var read: [ImportProgress] {
            lock.lock(); defer { lock.unlock() }
            return items
        }
    }

    override func setUp() async throws {
        await MainActor.run {}   // ensure the main actor is pumpable
    }

    // MARK: leading + in-window coalescing + trailing tail (three semantics)

    func testLeadingImmediateWindowCoalescingAndTrailingTailNotDropped() async throws {
        let clock = TestClock()
        let sink = Sink()
        let coalescer = ImportProgressCoalescer(
            interval: interval,
            now: { clock.now },
            deliver: { sink.append($0) })

        // 1. LEADING: the first submission delivers immediately (no window).
        coalescer.submit(snapshot(1))
        await waitMain()
        XCTAssertEqual(sink.read.map(\.processed), [1],
                       "the first submission must deliver immediately")

        // 2. IN-WINDOW: two submissions inside the open window coalesce —
        // nothing delivers while the window is open.
        coalescer.submit(snapshot(2))
        coalescer.submit(snapshot(3))
        await waitMain()
        XCTAssertEqual(sink.read.map(\.processed), [1],
                       "in-window submissions must coalesce (no delivery)")

        // 3. TRAILING: the armed drain (sleeping the remaining window) wakes
        // and delivers the LATEST snapshot — the tail is never dropped.
        try await waitUntil(timeout: .seconds(3)) {
            sink.read.map(\.processed) == [1, 3]
        }
        XCTAssertEqual(sink.read.map(\.processed), [1, 3],
                       "the window edge delivers the LATEST pending snapshot")
    }

    // MARK: terminal bypass + supersede (the service-side carrier)

    func testTerminalBypassesWindowAndSupersedesPendingInterim() async throws {
        let clock = TestClock()
        let sink = Sink()
        let coalescer = ImportProgressCoalescer(
            interval: interval,
            now: { clock.now },
            deliver: { sink.append($0) })

        // Arm a window with an interim pending inside it.
        coalescer.submit(snapshot(1))
        await waitMain()
        coalescer.submit(snapshot(2))
        await waitMain()
        XCTAssertEqual(sink.read.map(\.processed), [1])

        // TERMINAL: lands immediately despite the open window, superseding
        // the pending interim (latest-wins single slot) — the visual tail
        // can never hang on a swallowed terminal.
        coalescer.submit(snapshot(6, .completed))
        try await waitUntil(timeout: .seconds(3)) {
            sink.read.map(\.processed) == [1, 6]
        }
        XCTAssertEqual(sink.read.last?.phase, .completed,
                       "the .completed terminal must reach the sink")
        // Past the window edge nothing more arrives: the superseded interim
        // is gone (the armed window drain finds an empty slot).
        clock.advance(interval + .milliseconds(50))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sink.read.map(\.processed), [1, 6],
                       "the superseded interim must not deliver after the terminal")
    }

    // MARK: the pure decision seam

    func testWindowDecisionPureSeam() {
        let t0 = ContinuousClock.now
        XCTAssertFalse(
            ImportProgressCoalescer.isWindowOpen(
                lastDelivery: nil, now: t0, interval: interval),
            "nil last delivery = the leading face, window never open")
        XCTAssertFalse(
            ImportProgressCoalescer.isWindowOpen(
                lastDelivery: t0 - interval, now: t0, interval: interval),
            "at the window edge the window is closed (a new lead may fire)")
        XCTAssertTrue(
            ImportProgressCoalescer.isWindowOpen(
                lastDelivery: t0 - interval + .milliseconds(1), now: t0,
                interval: interval),
            "inside the window the window is open")
    }

    // MARK: R6 (import zero-row) — the run-tail invalidation

    /// The R5-2 / omp obs-4 root cause, deterministically interleaved: the
    /// run tail's DIRECT `importProgress = nil` write races the coalescer's
    /// QUEUED delivery jobs (leading drain / window drain / terminal flush
    /// all hop the main queue). A delivery that lands after the nil write
    /// resurrects the published progress with no writer behind it — the
    /// onChange consumer's nil-finish branch (the grid's reloadFirstPage)
    /// never fires, and the committed DB rows never reach the grid page.
    /// `invalidate()` is the run tail's coordination move BEFORE the nil
    /// write: here it is issued with all three delivery jobs still queued,
    /// and NOTHING may deliver afterwards.
    func testInvalidationDropsPendingAndEveryQueuedDelivery() async throws {
        let clock = TestClock()
        let sink = Sink()
        let coalescer = ImportProgressCoalescer(
            interval: interval,
            now: { clock.now },
            deliver: { sink.append($0) })

        // Queue the leading drain (immediate delivery job), an in-window
        // interim, and the terminal flush — then have the "run tail" win
        // the race BEFORE the main queue drains any of them.
        coalescer.submit(snapshot(1))            // leading drain job queued
        coalescer.submit(snapshot(2))            // in-window pending
        coalescer.submit(snapshot(6, .completed)) // terminal flush job queued
        coalescer.invalidate()                   // the run tail, pre-nil
        await waitMain()
        try await Task.sleep(for: .milliseconds(300))  // let any straggler job run
        XCTAssertTrue(
            sink.read.isEmpty,
            "an invalidated coalescer must deliver NOTHING; a post-invalidate "
                + "delivery resurrects the controller's nil terminal (the zero-row phenotype)")

        // A late submit (a straggler emission) is a no-op too.
        coalescer.submit(snapshot(7))
        await waitMain()
        XCTAssertTrue(sink.read.isEmpty, "post-invalidation submits must drop")
    }

    /// Already-delivered snapshots are NOT retracted — only the future
    /// dies. The leading delivery landed before the invalidation must stay
    /// visible (the bar's history is honest), while the queued window
    /// drain and any pending slot die with the invalidation.
    func testInvalidationKeepsDeliveredHistoryAndKillsTheQueuedWindow() async throws {
        let clock = TestClock()
        let sink = Sink()
        let coalescer = ImportProgressCoalescer(
            interval: interval,
            now: { clock.now },
            deliver: { sink.append($0) })

        coalescer.submit(snapshot(1))
        await waitMain()                          // the leading delivery landed
        XCTAssertEqual(sink.read.map(\.processed), [1])

        coalescer.submit(snapshot(2))             // arms the window drain
        coalescer.invalidate()                    // the run tail, pre-nil
        clock.advance(interval + .milliseconds(50))  // the drain's sleep expires
        await waitMain()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(
            sink.read.map(\.processed), [1],
            "the queued window drain must not deliver after the invalidation; "
                + "the delivered leading snapshot stays")
    }

    // MARK: helpers

    private func waitMain() async {
        await MainActor.run {}
        try? await Task.sleep(for: .milliseconds(10))
        await MainActor.run {}
    }

    private func waitUntil(
        timeout: Duration, _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
