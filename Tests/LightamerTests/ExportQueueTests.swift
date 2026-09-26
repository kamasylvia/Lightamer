import Foundation
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportQueue behavior suite (Plan 11-04 T2) — the TEN queue-semantics cases
// from the plan, all millisecond-cheap through injected legs (the 9-3
// SessionThumbnailProviderTests trick): no decode, no GPU, no real encoder.
//
//   ① enqueue→done FIFO order        ② cancel(pending)
//   ③ cancel(in-flight) discards     ④ cancelAll + generation gate
//   ⑤ retry re-queues at the tail    ⑥ progress (done,total) — N variants
//   ⑦ concurrency = 1 probe          ⑧ failure does not poison the queue
//   ⑨ session scope (new generation accepts work)
//   ⑩ out-of-order durations → correct done/total
//
// metal: nil throughout — injected legs never touch MetalContext; the
// production legs are not wired in this suite.
// ─────────────────────────────────────────────────────────────────────────────

final class ExportQueueTests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exportqueue-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = tempDirectory.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func variant(_ format: ExportFormatSpec = .jpeg(quality: 0.9)) -> ExportVariant {
        ExportVariant(format: format, colorSpace: .sRGB)
    }

    private func makeQueue(
        renderLeg: ExportRenderLeg? = nil,
        encodeLeg: ExportEncodeLeg? = nil,
        occupiedNames: (@Sendable (URL) -> Set<String>)? = nil
    ) -> ExportQueue {
        ExportQueue(
            metal: nil,
            registry: ModuleRegistry.makeDefault(),
            renderLeg: renderLeg,
            encodeLeg: encodeLeg,
            occupiedNamesProvider: occupiedNames)
    }

    /// The default injected legs: render returns a synthetic artifact
    /// tagged with the job's seq; encode maps it to /synthetic-<seq>.jpg.
    private static let defaultRenderLeg: ExportRenderLeg = { snapshot, _ in
        ExportRenderArtifact(token: snapshot.seq, width: 100, height: 80)
    }
    private static let defaultEncodeLeg: ExportEncodeLeg = { artifact, _ in
        URL(fileURLWithPath: "/synthetic-\(artifact.token).jpg")
    }

    /// A gate the tests hold a job's render leg on (the in-flight window).
    private final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func wait() { semaphore.wait() }
        func open() { semaphore.signal() }
    }

    /// A thread-safe counter (never captures the test case — the legs are
    /// @Sendable closures).
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        @discardableResult
        func increment() -> Int {
            lock.lock(); value += 1; defer { lock.unlock() }; return value
        }
        func decrement() { lock.lock(); value -= 1; defer { lock.unlock() } }
    }

    /// A thread-safe max recorder (the concurrency probe's peak).
    private final class Peak: @unchecked Sendable {
        private let lock = NSLock()
        private var maxValue = 0
        var max: Int { lock.lock(); defer { lock.unlock() }; return maxValue }
        func bump(_ candidate: Int) {
            lock.lock()
            maxValue = Swift.max(maxValue, candidate)
            lock.unlock()
        }
    }

    /// A thread-safe collection box (Swift 6: no captured-var mutation in
    /// @Sendable closures).
    private final class Log<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
        func append(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    }

    /// Poll until the queue reports idle with `total` settled jobs.
    private func waitUntilIdle(
        _ queue: ExportQueue, total: Int, timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let progress = await queue.progress()
            let snapshots = await queue.snapshots()
            let allSettled = snapshots.allSatisfy { $0.state.isTerminal }
            if progress.done == total, progress.total == total, progress.activePhase == nil,
               allSettled {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    // MARK: ① enqueue→done order (FIFO by seq)

    func testEnqueueRunsFIFOAndSettlesInOrder() async throws {
        let completionOrder = Log<Int>()
        let encode: ExportEncodeLeg = { artifact, _ in
            completionOrder.append(artifact.token)
            return URL(fileURLWithPath: "/synthetic-\(artifact.token).jpg")
        }
        let queue = makeQueue(renderLeg: Self.defaultRenderLeg, encodeLeg: encode)
        let snapshots = await queue.enqueue(
            images: [
                (URL(fileURLWithPath: "/s/a.arw"), "a.arw"),
                (URL(fileURLWithPath: "/s/b.arw"), "b.arw"),
                (URL(fileURLWithPath: "/s/c.arw"), "c.arw"),
            ],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots.map(\.seq), [1, 2, 3], "seq assigns in arrival order")

        let idle = await waitUntilIdle(queue, total: 3)
        XCTAssertTrue(idle, "queue never went idle")
        XCTAssertEqual(
            completionOrder.all, [1, 2, 3], "concurrency 1 ⇒ settle order == seq")
        let finals = await queue.snapshots()
        for job in finals {
            guard case .done(let url) = job.state else {
                return XCTFail("job \(job.seq) not done: \(job.state)")
            }
            XCTAssertEqual(url.path, "/synthetic-\(job.seq).jpg")
        }
    }

    // MARK: ② cancel(pending)

    func testCancelPendingJobRemovesItBeforeStart() async throws {
        let gate = Gate()
        let enteredRender = Counter()
        let render: ExportRenderLeg = { snapshot, _ in
            enteredRender.increment()
            if snapshot.seq == 1 { gate.wait() } // job 1 parks the worker
            return ExportRenderArtifact(token: snapshot.seq, width: 1, height: 1)
        }
        let queue = makeQueue(renderLeg: render, encodeLeg: Self.defaultEncodeLeg)
        let snapshots = await queue.enqueue(
            images: [
                (URL(fileURLWithPath: "/s/a.arw"), "a.arw"),
                (URL(fileURLWithPath: "/s/b.arw"), "b.arw"),
            ],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        // Wait for job 1 to enter its render leg (the worker is occupied).
        while enteredRender.count < 1 { try await Task.sleep(nanoseconds: 2_000_000) }
        await queue.cancel(jobID: snapshots[1].id)

        gate.open()
        let idle = await waitUntilIdle(queue, total: 2)
        XCTAssertTrue(idle)
        let finals = await queue.snapshots()
        XCTAssertEqual(finals.count, 2)
        guard case .done = finals[0].state else {
            return XCTFail("job 1 should be done, got \(finals[0].state)")
        }
        guard case .cancelled = finals[1].state else {
            return XCTFail(
                "cancelled pending job must read .cancelled, got \(finals[1].state)")
        }
        let progress = await queue.progress()
        XCTAssertEqual(progress.done, 2, "cancelled pending settles the tally")
        XCTAssertEqual(progress.total, 2)
    }

    // MARK: ③ cancel(in-flight) — artifact discarded, NOTHING written

    func testCancelInFlightDiscardsArtifactBeforeEncode() async throws {
        let gate = Gate()
        let enteredRender = Counter()
        let encodeCalls = Log<Int>()
        let render: ExportRenderLeg = { _, _ in
            enteredRender.increment()
            gate.wait()
            return ExportRenderArtifact(token: 99, width: 1, height: 1)
        }
        let encode: ExportEncodeLeg = { artifact, _ in
            encodeCalls.append(artifact.token)
            return URL(fileURLWithPath: "/synthetic-99.jpg")
        }
        let queue = makeQueue(renderLeg: render, encodeLeg: encode)
        let snapshots = await queue.enqueue(
            images: [(URL(fileURLWithPath: "/s/a.arw"), "a.arw")],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        while enteredRender.count < 1 { try await Task.sleep(nanoseconds: 2_000_000) }

        await queue.cancel(jobID: snapshots[0].id)
        gate.open()
        let idle = await waitUntilIdle(queue, total: 1)
        XCTAssertTrue(idle)
        // The boundary gate discarded the artifact — the encode leg NEVER
        // ran (the injected face of "nothing on disk, no tmp residue").
        XCTAssertTrue(
            encodeCalls.all.isEmpty, "encode must not run after the boundary cancel")
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            atPath: outputDirectory.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "the output directory must stay empty")
        let finals = await queue.snapshots()
        guard case .cancelled = finals[0].state else {
            return XCTFail("in-flight cancel must read .cancelled, got \(finals[0].state)")
        }
    }

    // MARK: ④ cancelAll + the generation gate (stale results never land)

    func testCancelAllGatesStaleGenerationResults() async throws {
        let gate = Gate()
        let encodeCalls = Log<Int>()
        let render: ExportRenderLeg = { _, _ in
            gate.wait()
            return ExportRenderArtifact(token: 7, width: 1, height: 1)
        }
        let encode: ExportEncodeLeg = { _, _ in
            encodeCalls.append(0)
            return URL(fileURLWithPath: "/synthetic-7.jpg")
        }
        let queue = makeQueue(renderLeg: render, encodeLeg: encode)
        let snapshots = await queue.enqueue(
            images: [
                (URL(fileURLWithPath: "/s/a.arw"), "a.arw"),
                (URL(fileURLWithPath: "/s/b.arw"), "b.arw"),
            ],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        // One worker runs; the other waits in pending.
        await queue.cancelAll()

        // Release everything — the stale render may finish into the void.
        gate.open()
        // Give the detached task a beat to collide with the new epoch.
        try await Task.sleep(nanoseconds: 150_000_000)

        for snapshot in snapshots {
            let fresh = await queue.snapshots().first { $0.id == snapshot.id }
            guard case .cancelled = fresh?.state else {
                return XCTFail(
                    "stale job must read .cancelled, got \(String(describing: fresh?.state))")
            }
        }
        XCTAssertTrue(
            encodeCalls.all.isEmpty, "no stale artifact may reach the encode leg")
        let progress = await queue.progress()
        XCTAssertEqual(progress.total, 0, "cancelAll resets the progress window")
        XCTAssertEqual(progress.done, 0)
    }

    // MARK: ⑤ retry re-queues at the tail (no automatic retry)

    func testFailedJobExplicitRetryRunsAtTail() async throws {
        let attempts = Counter()
        let render: ExportRenderLeg = { snapshot, _ in
            // seq 1 fails ONCE (its first attempt), succeeds on retry.
            if snapshot.seq == 1 && attempts.increment() == 1 {
                throw AppError.encodeFailed("first attempt explodes")
            }
            return ExportRenderArtifact(token: snapshot.seq, width: 1, height: 1)
        }
        let queue = makeQueue(renderLeg: render, encodeLeg: Self.defaultEncodeLeg)
        let snapshots = await queue.enqueue(
            images: [
                (URL(fileURLWithPath: "/s/a.arw"), "a.arw"),
                (URL(fileURLWithPath: "/s/b.arw"), "b.arw"),
            ],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        var idle = await waitUntilIdle(queue, total: 2)
        XCTAssertTrue(idle)
        var finals = await queue.snapshots()
        guard case .failed(let error) = finals[0].state else {
            return XCTFail("job 1 should be failed, got \(finals[0].state)")
        }
        XCTAssertTrue(error.localizedDescription.contains("explodes"))
        guard case .done = finals[1].state else {
            return XCTFail("job 2 must be done (failures don't block), got \(finals[1].state)")
        }

        // retry: back to pending at the TAIL (fresh seq), then done.
        try await queue.retry(jobID: snapshots[0].id)
        let retried = await queue.snapshots().first { $0.id == snapshots[0].id }
        XCTAssertEqual(retried?.seq, 3, "retry lands at the tail with a fresh seq")
        XCTAssertEqual(retried?.generation, 0)
        idle = await waitUntilIdle(queue, total: 2)
        XCTAssertTrue(idle)
        finals = await queue.snapshots()
        guard case .done = finals.first(where: { $0.id == snapshots[0].id })?.state else {
            return XCTFail("retried job must be done")
        }
        // progress unwinds the failed tally on retry and re-settles:
        // done == total == 2 holds at the end.
        let progress = await queue.progress()
        XCTAssertEqual(progress.done, 2)
        XCTAssertEqual(progress.total, 2)
    }

    /// retry on a non-failed (or unknown) job throws — the failed-only
    /// contract.
    func testRetryRejectsNonFailedJobs() async throws {
        let queue = makeQueue(
            renderLeg: Self.defaultRenderLeg, encodeLeg: Self.defaultEncodeLeg)
        let snapshots = await queue.enqueue(
            images: [(URL(fileURLWithPath: "/s/a.arw"), "a.arw")],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        _ = await waitUntilIdle(queue, total: 1)
        do {
            try await queue.retry(jobID: snapshots[0].id)
            XCTFail("retry on a done job must throw")
        } catch {
            // expected — the typed invalidParameter
        }
        do {
            try await queue.retry(jobID: UUID())
            XCTFail("retry on an unknown job must throw")
        } catch {
            // expected
        }
    }

    // MARK: ⑥ progress (done,total) — N images × M variants = N×M jobs

    func testProgressCountsEveryVariantAsAJob() async throws {
        let queue = makeQueue(
            renderLeg: Self.defaultRenderLeg, encodeLeg: Self.defaultEncodeLeg)
        let seen = Log<(done: Int, total: Int)>()
        await queue.setProgressHook { [weak queue] in
            guard let queue else { return }
            let progress = await queue.progress()
            seen.append((progress.done, progress.total))
        }
        _ = await queue.enqueue(
            images: [
                (URL(fileURLWithPath: "/s/a.arw"), "a.arw"),
                (URL(fileURLWithPath: "/s/b.arw"), "b.arw"),
            ],
            variants: [variant(.jpeg(quality: 0.8)), variant(.png(bitDepth: .eight))],
            destinationDirectory: outputDirectory)
        let idle = await waitUntilIdle(queue, total: 4)
        XCTAssertTrue(idle)
        await queue.setProgressHook(nil)
        let all = seen.all
        XCTAssertEqual(all.map(\.total).max(), 4, "2 images × 2 variants = 4 jobs")
        XCTAssertEqual(all.map(\.done).max(), 4)
        let snapshots = await queue.snapshots()
        XCTAssertEqual(snapshots.count, 4)
        // The per-variant jobs keep the variant order within each image.
        XCTAssertEqual(
            snapshots.map { $0.variants[0].format.formatName },
            ["jpeg", "png", "jpeg", "png"])
    }

    // MARK: ⑦ concurrency = 1 probe

    func testConcurrencyIsExactlyOne() async throws {
        let active = Counter()
        let peak = Peak()
        let render: ExportRenderLeg = { _, _ in
            peak.bump(active.increment())
            try? await Task.sleep(nanoseconds: 5_000_000)
            active.decrement()
            return ExportRenderArtifact(token: 1, width: 1, height: 1)
        }
        let queue = makeQueue(renderLeg: render, encodeLeg: Self.defaultEncodeLeg)
        _ = await queue.enqueue(
            images: (0..<6).map { (URL(fileURLWithPath: "/s/img\($0).arw"), "img\($0).arw") },
            variants: [variant()],
            destinationDirectory: outputDirectory)
        let idle = await waitUntilIdle(queue, total: 6)
        XCTAssertTrue(idle)
        XCTAssertEqual(peak.max, 1, "the in-flight probe must never exceed 1")
        let inFlight = await queue.inFlightCountForTesting()
        XCTAssertEqual(inFlight, 0, "idle queue holds no in-flight slot")
    }

    // MARK: ⑧ failure does not poison the queue

    func testFailureDoesNotPoisonFollowingJobs() async throws {
        let render: ExportRenderLeg = { snapshot, _ in
            if snapshot.seq == 2 {
                throw AppError.decodeFailed("poison")
            }
            return ExportRenderArtifact(token: snapshot.seq, width: 1, height: 1)
        }
        let queue = makeQueue(renderLeg: render, encodeLeg: Self.defaultEncodeLeg)
        _ = await queue.enqueue(
            images: [
                (URL(fileURLWithPath: "/s/a.arw"), "a.arw"),
                (URL(fileURLWithPath: "/s/b.arw"), "b.arw"),
                (URL(fileURLWithPath: "/s/c.arw"), "c.arw"),
            ],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        let idle = await waitUntilIdle(queue, total: 3)
        XCTAssertTrue(idle)
        let finals = await queue.snapshots()
        guard case .done = finals[0].state else {
            return XCTFail("job 1: \(finals[0].state)")
        }
        guard case .failed = finals[1].state else {
            return XCTFail("job 2: \(finals[1].state)")
        }
        guard case .done = finals[2].state else {
            return XCTFail("job 3: \(finals[2].state)")
        }
        let progress = await queue.progress()
        XCTAssertEqual(progress.done, 3, "failed still settles the tally")
    }

    // MARK: ⑨ session scope — a fresh generation accepts work again

    func testNewGenerationAcceptsJobsAfterCancelAll() async throws {
        let queue = makeQueue(
            renderLeg: Self.defaultRenderLeg, encodeLeg: Self.defaultEncodeLeg)
        let first = await queue.enqueue(
            images: [(URL(fileURLWithPath: "/s/a.arw"), "a.arw")],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        _ = await waitUntilIdle(queue, total: 1)
        await queue.cancelAll()

        let second = await queue.enqueue(
            images: [(URL(fileURLWithPath: "/s/b.arw"), "b.arw")],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        let fresh = await queue.snapshots().first { $0.id == second[0].id }
        XCTAssertEqual(fresh?.generation, 1, "post-cancelAll jobs ride the NEW epoch")
        XCTAssertNotEqual(first[0].id, second[0].id)
        let idle = await waitUntilIdle(queue, total: 1)
        XCTAssertTrue(idle)
        let finals = await queue.snapshots().first { $0.id == second[0].id }
        guard case .done = finals?.state else {
            return XCTFail(
                "new-generation job must complete, got \(String(describing: finals?.state))")
        }
    }

    // MARK: ⑩ out-of-order durations → correct done/total

    func testUnevenEncodeDurationsKeepProgressCorrect() async throws {
        let settled = Log<Int>()
        let render: ExportRenderLeg = { snapshot, _ in
            // Deterministic per-job leg durations (uneven — the done tally
            // must still climb monotonically to total).
            let ms: UInt64 = [2, 40, 10, 25][min(snapshot.seq - 1, 3)]
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            return ExportRenderArtifact(token: snapshot.seq, width: 1, height: 1)
        }
        let encode: ExportEncodeLeg = { artifact, _ in
            settled.append(artifact.token)
            return URL(fileURLWithPath: "/synthetic-\(artifact.token).jpg")
        }
        let queue = makeQueue(renderLeg: render, encodeLeg: encode)
        _ = await queue.enqueue(
            images: (0..<4).map { (URL(fileURLWithPath: "/s/img\($0).arw"), "img\($0).arw") },
            variants: [variant()],
            destinationDirectory: outputDirectory)
        let idle = await waitUntilIdle(queue, total: 4)
        XCTAssertTrue(idle)
        let samples = settled.all
        // Concurrency 1: starts are ordered even when legs take unequal
        // time — each job settles exactly once.
        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(Set(samples).count, 4, "each job settles exactly once")
        let progress = await queue.progress()
        XCTAssertEqual(progress.done, 4)
        XCTAssertEqual(progress.total, 4)
        XCTAssertNil(progress.activePhase)
    }

    // MARK: - Occupancy + context face (the dequeue-time contract)

    /// The context carries the occupancy snapshot + destination at DEQUEUE
    /// time — each job gets its own enumeration (the 11-03 collision
    /// lesson: occupancy read at execution time, never at enqueue time).
    func testContextCarriesDestinationAndDequeueTimeOccupancy() async throws {
        let occupied = Log<Set<String>>()
        let destinations = Log<URL>()
        let render: ExportRenderLeg = { _, context in
            occupied.append(context.occupiedNames)
            destinations.append(context.destinationDirectory)
            return ExportRenderArtifact(token: 1, width: 1, height: 1)
        }
        let queue = makeQueue(
            renderLeg: render, encodeLeg: Self.defaultEncodeLeg,
            occupiedNames: { directory in
                // A live enumeration face: whatever the directory holds at
                // THIS instant.
                Set(
                    (try? FileManager.default.contentsOfDirectory(
                        atPath: directory.path)) ?? [])
            })
        // Seed one file so the first dequeue sees it; the SECOND dequeue
        // would also see anything the first promoted (nothing here, but
        // the enumeration ORDER proves per-dequeue reads).
        try? Data("x".utf8).write(
            to: outputDirectory.appendingPathComponent("seed.jpg"))
        _ = await queue.enqueue(
            images: [
                (URL(fileURLWithPath: "/s/a.arw"), "a.arw"),
                (URL(fileURLWithPath: "/s/b.arw"), "b.arw"),
            ],
            variants: [variant()],
            destinationDirectory: outputDirectory)
        let idle = await waitUntilIdle(queue, total: 2)
        XCTAssertTrue(idle)
        XCTAssertEqual(occupied.all.count, 2, "each dequeue gets its own snapshot")
        XCTAssertEqual(destinations.all, [outputDirectory, outputDirectory])
        for snapshot in occupied.all {
            XCTAssertEqual(snapshot, ["seed.jpg"], "the seed file is enumerated")
        }
    }

    /// The DEFAULT provider enumerates the real directory (the production
    /// occupancy face).
    func testDefaultOccupiedNamesProviderListsDirectory() throws {
        try? Data("x".utf8).write(to: outputDirectory.appendingPathComponent("a.jpg"))
        try? Data("y".utf8).write(to: outputDirectory.appendingPathComponent("b.png"))
        try? FileManager.default.createDirectory(
            at: outputDirectory.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let names = ExportQueue.defaultOccupiedNames(in: outputDirectory)
        XCTAssertEqual(names, ["a.jpg", "b.png", "sub"])
        let missing = ExportQueue.defaultOccupiedNames(
            in: tempDirectory.appendingPathComponent("does-not-exist"))
        XCTAssertTrue(missing.isEmpty, "a missing directory enumerates empty")
    }
}
