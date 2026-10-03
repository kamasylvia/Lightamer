import Foundation
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// CompatRecordTests (Plan M2-10-05 T3, KD-4 / AC#5+6) — the crash-memo
// face over an INJECTED temp path (never the real Application Support):
// bookkeeping, the two-model all-disable flip, the CPU-never-recorded rule,
// the atomic write terminal state, corrupt-JSON tolerance, reset, and the
// injectable machineKey composition.
// ─────────────────────────────────────────────────────────────────────────────

final class CompatRecordTests: XCTestCase {

    private var directory: URL!
    private var path: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightamer-compat-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("ai-compat.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private static let machine = "TestMacModel/27A999"
    private static let otherMachine = "TestMacModel/27B001"

    // MARK: - Bookkeeping + the excluded query

    func testRecordedModelUnitsAreExcludedForThatModel() {
        let record = CompatRecord(path: path)
        record.record(
            machineKey: Self.machine, model: "clip-a", units: .all,
            detail: "sigfault in ANE compiler")
        record.record(
            machineKey: Self.machine, model: "clip-a", units: .cpuAndGPU,
            detail: "gpu hang")

        XCTAssertEqual(
            record.excluded(machineKey: Self.machine, model: "clip-a"),
            [.all, .cpuAndGPU])
        // A different model only sees the all-disable (none yet — single
        // model per units is model-scoped).
        XCTAssertEqual(
            record.excluded(machineKey: Self.machine, model: "clip-b"),
            [])
        // Another machine (different OS build) shares nothing.
        XCTAssertEqual(
            record.excluded(machineKey: Self.otherMachine, model: "clip-a"),
            [])
    }

    func testTwoDifferentModelsOnSameUnitsDisableTheUnitsForEveryone() {
        let record = CompatRecord(path: path)
        record.record(machineKey: Self.machine, model: "clip-a", units: .all, detail: "x")
        record.record(machineKey: Self.machine, model: "clip-b", units: .all, detail: "y")

        // Lumen ai_worker.py:132: len(models) >= 2 → all = true → the units
        // are excluded for ANY model on this machine.
        XCTAssertEqual(
            record.excluded(machineKey: Self.machine, model: "clip-c"), [.all])
        // The SAME model recorded twice never flips the switch.
        let single = CompatRecord(path: directory
            .appendingPathComponent("single.json"))
        single.record(machineKey: Self.machine, model: "clip-a", units: .all, detail: "1")
        single.record(machineKey: Self.machine, model: "clip-a", units: .all, detail: "2")
        XCTAssertEqual(
            single.excluded(machineKey: Self.machine, model: "clip-b"), [])
    }

    func testCPUCrashIsNeverRecorded() throws {
        let record = CompatRecord(path: path)
        record.record(
            machineKey: Self.machine, model: "clip-a", units: .cpuOnly,
            detail: "even cpu crashed")
        // Nothing on disk, nothing excluded — the CPU floor has nowhere left
        // to degrade to, so it can never enter the memo.
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(
            record.excluded(machineKey: Self.machine, model: "clip-a"), [])
    }

    func testDetailIsTruncatedToThreeHundredCharacters() throws {
        let record = CompatRecord(path: path)
        record.record(
            machineKey: Self.machine, model: "clip-a", units: .all,
            detail: String(repeating: "x", count: 1000))
        let entry = try storedEntry(machine: Self.machine, units: "all")
        XCTAssertEqual(entry.last?.detail.count, CompatRecord.detailLimit)
    }

    // MARK: - The atomic write terminal state (E4)

    func testAtomicWriteLeavesValidTerminalFileAndNoTempResidue() throws {
        let record = CompatRecord(path: path)
        record.record(machineKey: Self.machine, model: "clip-a", units: .cpuAndGPU, detail: "d")
        record.record(machineKey: Self.machine, model: "clip-b", units: .cpuAndGPU, detail: "e")

        // The terminal file parses and carries BOTH models under one entry.
        let entry = try storedEntry(machine: Self.machine, units: "cpuAndGPU")
        XCTAssertEqual(entry.models, ["clip-a", "clip-b"])
        XCTAssertTrue(entry.all)
        XCTAssertEqual(entry.last?.model, "clip-b")
        XCTAssertFalse(entry.last?.time.isEmpty ?? true)
        // No `.tmp` residue survives the promotion.
        let residue = try FileManager.default.contentsOfDirectory(
            atPath: directory.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(residue.isEmpty, "tmp residue: \(residue)")
    }

    // MARK: - Corrupt-JSON tolerance

    func testCorruptJSONIsToleratedAsEmptyAndRebuiltByNextWrite() throws {
        try Data("{{{ this is not json".utf8).write(to: path)
        let record = CompatRecord(path: path)
        XCTAssertEqual(
            record.excluded(machineKey: Self.machine, model: "clip-a"), [],
            "a broken memo reads as empty, never as a failure")
        // The next bookkeeping write rebuilds the file.
        record.record(machineKey: Self.machine, model: "clip-a", units: .all, detail: "fresh")
        let entry = try storedEntry(machine: Self.machine, units: "all")
        XCTAssertEqual(entry.models, ["clip-a"])
    }

    // MARK: - Reset

    func testResetAllDeletesTheFileAndClearsExclusions() throws {
        let record = CompatRecord(path: path)
        record.record(machineKey: Self.machine, model: "clip-a", units: .all, detail: "d")
        XCTAssertNotNil(try? Data(contentsOf: path))
        record.resetAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(
            record.excluded(machineKey: Self.machine, model: "clip-a"), [])
        // Reset on an absent file is a no-op (the M2-10-07 button presses it
        // regardless of state).
        record.resetAll()
    }

    // MARK: - The machineKey composition (injectable, no sysctl in tests)

    func testMachineKeyIsStablePerMachineAndSensitiveToOSBuild() {
        let a1 = CompatRecord.machineKey(hwModel: "Mac15,6", osBuild: "27A123")
        let a2 = CompatRecord.machineKey(hwModel: "Mac15,6", osBuild: "27A123")
        let b = CompatRecord.machineKey(hwModel: "Mac15,6", osBuild: "27B456")
        let c = CompatRecord.machineKey(hwModel: "Mac16,1", osBuild: "27A123")
        XCTAssertEqual(a1, a2, "same machine + build → the same key")
        XCTAssertNotEqual(a1, b, "an OS update starts a fresh slate")
        XCTAssertNotEqual(a1, c, "a different machine never shares a key")
        XCTAssertTrue(a1.contains("/"))
    }

    // MARK: - Storage helper

    private func storedEntry(machine: String, units: String) throws -> CompatEntry {
        let data = try Data(contentsOf: path)
        let table = try JSONDecoder().decode(
            [String: [String: CompatEntry]].self, from: data)
        return try XCTUnwrap(table[machine]?[units])
    }
}
