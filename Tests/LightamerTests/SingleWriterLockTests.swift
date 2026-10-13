import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T1 (KD-8 golden gate 1): the Core single-writer lock's five
// flock states round-trip. L009: every fixture lives on NSTemporaryDirectory
// (the boot volume), never the UNITEK volume.
// ─────────────────────────────────────────────────────────────────────────────

final class SingleWriterLockTests: XCTestCase {

    private var tempDirectory: URL!
    private var lockURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("single-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        lockURL = tempDirectory.appendingPathComponent("test.lalb.lock")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    /// States ①②: acquire wins; a SECOND independent open() in the SAME
    /// process EWOULDBLOCKs (flock arbiters per open file description —
    /// checker o1).
    func testAcquireSuccessThenSecondAcquireHeldByOther() throws {
        let first = try XCTUnwrap(
            SingleWriterLock.acquire(at: lockURL).get(),
            "first acquire must win on a fresh path")
        defer { first.unlock() }
        let second = SingleWriterLock.acquire(at: lockURL)
        guard case .failure(.heldByOther) = second else {
            return XCTFail("second independent fd must be heldByOther, got \(second)")
        }
    }

    /// State ③ (the interlock): unlock releases through the kernel; the
    /// next acquirer wins — the mutual-exclusion handover.
    func testUnlockReleasesAndSecondAcquireWins() throws {
        let first = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        first.unlock()
        let second = try XCTUnwrap(
            SingleWriterLock.acquire(at: lockURL).get(),
            "acquire after unlock must win")
        second.unlock()
    }

    /// State ⑤: the probe's three answers — free = true, held = false,
    /// and a stale payload on disk NEVER flips the verdict (flock is the
    /// sole arbiter).
    func testProbeFreeHeldAndResiduePayloadIrrelevant() throws {
        XCTAssertTrue(
            SingleWriterLock.probeLockAvailable(at: lockURL),
            "probe on a free path = available")
        // Residue: a payload without a live holder does not matter for the
        // FREE verdict (probe still succeeds).
        let lock = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        lock.writePayload(
            SingleWriterLockPayload(
                role: .gui, pid: getpid(),
                startedAt: SingleWriterLockPayload.nowISO8601()))
        XCTAssertFalse(
            SingleWriterLock.probeLockAvailable(at: lockURL),
            "probe under a live holder = not available")
        lock.unlock()
        XCTAssertTrue(
            SingleWriterLock.probeLockAvailable(at: lockURL),
            "stale payload + free lock must still probe available")
    }

    /// Payload round-trip + the frozen v1 spelling negative (a JSON missing
    /// a field refuses to decode — the additive-only schema discipline).
    func testPayloadRoundTripFrozenSpelling() throws {
        let lock = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        defer { lock.unlock() }
        let started = "2026-10-16T00:00:00Z"
        lock.writePayload(
            SingleWriterLockPayload(role: .headless, pid: 4242, startedAt: started))
        let read = try XCTUnwrap(SingleWriterLock.readPayload(at: lockURL))
        XCTAssertEqual(read.schemaVersion, 1)
        XCTAssertEqual(read.role, "headless")
        XCTAssertEqual(read.pid, 4242)
        XCTAssertEqual(read.startedAt, started)
        // Frozen-spelling negative: drop one field → decode refuses.
        let truncated = try XCTJSONDropKey(
            of: read, key: "startedAt")
        XCTAssertNil(
            try? JSONDecoder().decode(SingleWriterLockPayload.self, from: truncated),
            "a v1 payload missing a field must refuse to decode")
    }

    /// The holder summary falls back to「pid 未知」when the payload is
    /// absent (crash between acquire and the payload write) — diagnostics
    /// never become a criterion.
    func testHolderSummaryFallsBackWhenPayloadAbsent() throws {
        let lock = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        defer { lock.unlock() }
        // No writePayload call: the lock file is empty.
        XCTAssertEqual(
            SingleWriterLock.holderSummary(at: lockURL), "pid 未知 / pid unknown")
        lock.writePayload(
            SingleWriterLockPayload(
                role: .gui, pid: 777, startedAt: "2026-10-16T01:00:00Z"))
        let summary = SingleWriterLock.holderSummary(at: lockURL)
        XCTAssertTrue(summary.contains("pid=777"), "summary carries the pid: \(summary)")
        XCTAssertTrue(summary.contains("role=gui"), "summary carries the role: \(summary)")
    }

    /// A real I/O failure surfaces as .ioError (a path whose parent is a
    /// regular FILE — mkdir with intermediate directories cannot succeed).
    func testIOErrorOnBadParentPath() throws {
        let fileAsDirectory = tempDirectory.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: fileAsDirectory)
        let badURL = fileAsDirectory
            .appendingPathComponent("sub", isDirectory: true)
            .appendingPathComponent("x.lalb.lock")
        let result = SingleWriterLock.acquire(at: badURL)
        guard case .failure(.ioError) = result else {
            return XCTFail("acquire under a file-parent must ioError, got \(result)")
        }
    }

    /// The L009 directory leg: acquire over a nested, not-yet-existing
    /// directory path creates the intermediates (the session.lock shape
    /// `<root>/.lightamer/session.lock` needs this).
    func testAcquireCreatesParentDirectory() throws {
        let nested = tempDirectory
            .appendingPathComponent("root", isDirectory: true)
            .appendingPathComponent(".lightamer", isDirectory: true)
            .appendingPathComponent("session.lock")
        let lock = try XCTUnwrap(
            SingleWriterLock.acquire(at: nested).get(),
            "acquire must create the intermediate directories")
        defer { lock.unlock() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    /// unlock() idempotence through the fd lifecycle + the exposed path.
    func testUnlockIdempotentAndPathExposed() throws {
        let lock = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        XCTAssertEqual(lock.lockPath, lockURL.path)
        lock.unlock()
        // A second unlock must not trap (the fd lifecycle discipline — the
        // close() path may double-call through the idempotent store leg).
        lock.unlock()
        XCTAssertTrue(
            SingleWriterLock.probeLockAvailable(at: lockURL),
            "double unlock leaves the lock free")
    }
}

// MARK: - Test helpers

/// Re-encodes `value` as JSON, drops `key`, and returns the raw bytes (the
/// frozen-spelling negative's builder).
private func XCTJSONDropKey<T: Encodable>(of value: T, key: String) throws -> Data {
    let object = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(value))
    var dictionary = try XCTUnwrap(object as? [String: Any])
    dictionary.removeValue(forKey: key)
    return try JSONSerialization.data(withJSONObject: dictionary)
}
