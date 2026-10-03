import CoreML
import Foundation
import ImageIO
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// AIWorkerClientTests (Plan M2-10-05 T2, KD-3 / AC#3..5+7) — the worker
// lifecycle over REAL child processes (checker E1: no mock Process — every
// lifecycle test spawns the actual test-host binary with `--ai-worker`,
// crashes are real exit(9)s through the DEBUG crash-injection hook, and the
// pipe breakage is a real external SIGKILL).
//
// CRASH-HOOK DISCIPLINE: the hook env var is set/unset in the TEST process
// (the child inherits it); tearDown ALWAYS clears it so no later test case
// inherits a poisoned environment.
//
// RESOURCE GATE: the real-model probe (bundled assets present) XCTSkips in
// model-less environments — the toy-profile cases cover the full chain with
// zero model bytes (the open failure/error-frame paths carry the assertions).
// ─────────────────────────────────────────────────────────────────────────────

final class AIWorkerClientTests: XCTestCase {

    private var directory: URL!
    private static let machine = "WorkerTestMachine/TESTBUILD"
    /// The toy profile no bundle ever carries (纪律: 玩具模型名).
    private static let toyProfile = "compat-probe-profile"
    private static let hookEnv = "LIGHTAMER_TEST_AI_WORKER_CRASH"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightamer-worker-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // The hook must never leak into later test cases of this host.
        unsetenv(Self.hookEnv)
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private func makeRecord() -> CompatRecord {
        CompatRecord(path: directory.appendingPathComponent("ai-compat.json"))
    }

    private func makeClient(
        record: CompatRecord? = nil,
        executableURL: URL? = nil,
        openTimeout: TimeInterval = 120,
        pingTimeout: TimeInterval = 20
    ) -> AIWorkerClient {
        AIWorkerClient(configuration: .init(
            executableURL: executableURL,
            record: record ?? makeRecord(),
            machineKey: Self.machine,
            openTimeout: openTimeout,
            runTimeout: 120,
            pingTimeout: pingTimeout))
    }

    private func setHook(_ value: String) {
        setenv(Self.hookEnv, value, 1)
    }

    // MARK: - The real-subprocess lifecycle (E1)

    func testPingRoundTripThroughRealSubprocess() async throws {
        let client = makeClient()
        let pid = try await client.ping()
        XCTAssertGreaterThan(pid, 1, "the worker answered with its own pid")
        XCTAssertEqual(client.childProcessIdentifier, Int32(pid))
        // A second ping rides the SAME process (no respawn).
        let pid2 = try await client.ping()
        XCTAssertEqual(pid2, pid)
        XCTAssertEqual(client.currentGeneration, 1)
        // The graceful stop: exit 0, no leftover process.
        await client.stop()
        XCTAssertNil(client.childProcessIdentifier)
    }

    // MARK: - Crash injection (AC#3): a real exit(9) restarts the chain

    func testCrashInjectionRestartsGenerationAndRecordsNonCPUUnits() async throws {
        setHook(Self.toyProfile)  // every open of the toy profile exits 9
        let record = makeRecord()
        let client = makeClient(record: record)

        let error = await Self.error {
            try await client.embedText(
                Self.toyProfile, tokens: [101, 102], mask: [1, 1])
        }

        // The chain consumed [.all, .cpuAndGPU] (recorded) and crashed
        // .cpuOnly too (NOT recorded — the CPU floor has no next rung) →
        // the empty chain is the typed exhaustion.
        XCTAssertEqual(error, .workerExhausted)
        XCTAssertEqual(client.currentGeneration, 3, "one spawn per rung")
        XCTAssertTrue(
            record.excluded(machineKey: Self.machine, model: Self.toyProfile)
                .contains(.all))
        XCTAssertTrue(
            record.excluded(machineKey: Self.machine, model: Self.toyProfile)
                .contains(.cpuAndGPU))
        XCTAssertFalse(
            record.excluded(machineKey: Self.machine, model: Self.toyProfile)
                .contains(.cpuOnly),
            "a CPU crash must never enter the memo")
        // The two-model all-disable has NOT flipped (one model only).
        XCTAssertFalse(
            record.excluded(machineKey: Self.machine, model: "other-model")
                .contains(.all))
    }

    func testCrashSequenceTerminatesOnCPUWithTheProfileFailureSurfaced() async throws {
        setHook("\(Self.toyProfile)@all,cpuAndGPU")
        let record = makeRecord()
        let client = makeClient(record: record)

        let error = await Self.error {
            try await client.embedText(
                Self.toyProfile, tokens: [101], mask: [1])
        }

        // .all and .cpuAndGPU crashed (recorded); on .cpuOnly the hook does
        // not fire, the worker answers the assets-absent error frame WITHOUT
        // a culprit — the profile-level failure surfaces directly (终态 =
        // cpuOnly rung, honest error, no further respawn).
        guard case .requestFailed(let message)? = error else {
            return XCTFail("expected requestFailed, got \(String(describing: error))")
        }
        XCTAssertTrue(message.contains("assets absent"), message)
        // Three SPAWNS: .all (crash) → .cpuAndGPU (crash) → .cpuOnly (the
        // torn-down process must come back for the third open — the failure
        // there is a RESPONSE, not a crash).
        XCTAssertEqual(client.currentGeneration, 3)
        let excluded = record.excluded(
            machineKey: Self.machine, model: Self.toyProfile)
        XCTAssertEqual(excluded, [.all, .cpuAndGPU])
    }

    func testPreseededExclusionSkipsTheCrashedRungEntirely() async throws {
        // The memo already disables .all for this model (an earlier crash
        // session) — the chain must START at .cpuAndGPU.
        setHook("\(Self.toyProfile)@cpuAndGPU")
        let record = makeRecord()
        record.record(
            machineKey: Self.machine, model: Self.toyProfile, units: .all,
            detail: "pre-seeded from an earlier session")
        let client = makeClient(record: record)

        _ = await Self.error {
            try await client.embedText(
                Self.toyProfile, tokens: [101], mask: [1])
        }

        // Generation 2 = the first spawn went straight to .cpuAndGPU (crashed,
        // recorded), the second opened .cpuOnly (assets absent surfaced).
        XCTAssertEqual(client.currentGeneration, 2)
        let entry = try JSONDecoder().decode(
            [String: [String: CompatEntry]].self,
            from: Data(contentsOf: directory
                .appendingPathComponent("ai-compat.json")))
        let perUnits = try XCTUnwrap(entry[Self.machine])
        // The pre-excluded .all rung was never re-attempted: its entry is
        // EXACTLY the pre-seed (unchanged detail line).
        XCTAssertEqual(
            try XCTUnwrap(perUnits[AIComputeUnits.all.rawValue])
                .last?.detail, "pre-seeded from an earlier session")
        // The .cpuAndGPU crash landed a FRESH entry.
        XCTAssertEqual(
            try XCTUnwrap(perUnits[AIComputeUnits.cpuAndGPU.rawValue])
                .models, [Self.toyProfile])
        XCTAssertNil(perUnits[AIComputeUnits.cpuOnly.rawValue])
    }

    // MARK: - Timeout kill + pipe breakage (AC#4)

    func testTimeoutKillFoldsToWorkerCrashedAndRespawns() async throws {
        let client = makeClient()
        _ = try await client.ping()  // a healthy process exists
        XCTAssertEqual(client.currentGeneration, 1)

        // The injected (zero-budget) deadline fires the kill path.
        let error = await Self.error { try await client.ping(timeout: 0) }
        XCTAssertEqual(error, .workerCrashed("no response within 0 s"))
        XCTAssertNil(client.childProcessIdentifier, "the killed child was reaped")

        // The next request spawns a fresh generation (the Lumen restart).
        let pid = try await client.ping()
        XCTAssertGreaterThan(pid, 1)
        XCTAssertEqual(client.currentGeneration, 2)
    }

    func testExternalPipeBreakageFoldsIntoWorkerCrashed() async throws {
        let client = makeClient()
        let pid = try await client.ping()

        // A REAL external kill (the GPU-driver-fault simulation): the pump
        // hits EOF, the request loop folds the death into the typed crash.
        kill(Int32(pid), SIGKILL)
        try await Task.sleep(nanoseconds: 300_000_000)

        let error = await Self.error { try await client.ping() }
        guard case .workerCrashed(let detail)? = error else {
            return XCTFail("expected workerCrashed, got \(String(describing: error))")
        }
        XCTAssertTrue(detail.contains("exit code 9"), detail)
        XCTAssertNil(client.childProcessIdentifier)

        // The editor lives on: the next request respawns.
        let newPID = try await client.ping()
        XCTAssertNotEqual(newPID, pid)
    }

    // MARK: - The unavailable face (AC#7): never an in-process fallback

    func testMissingExecutableIsWorkerUnavailable() async throws {
        let client = makeClient(
            executableURL: URL(fileURLWithPath: "/nonexistent/lightamer"))
        let error = await Self.error {
            try await client.embedText(
                Self.toyProfile, tokens: [101], mask: [1])
        }
        guard case .workerUnavailable(let message)? = error else {
            return XCTFail("expected workerUnavailable, got \(String(describing: error))")
        }
        XCTAssertTrue(message.contains("not found"), message)
        XCTAssertEqual(client.currentGeneration, 0)
    }

    // MARK: - The real-model probe (resource gate: skip when assets absent)

    func testRealModelEmbedImageThroughWorkerProcess() async throws {
        let clip = ModelAssetCatalog.chineseClipViTB16Int8
        let locator = ModelLocator()
        guard locator.bundledAssetURL(clip.assetFileName, profileID: clip.profileID) != nil
        else {
            throw XCTSkip("bundled CLIP assets absent — the resource-gate skip")
        }
        let client = makeClient(openTimeout: 900)
        // A 224² CLIP-shaped input through the REAL open+run round trip.
        let image = try Self.solidImage(edge: 224)
        let jpeg = try SemanticEngine.preScaledJPEG(from: image, edge: 224)
        let vector = try await client.embedImage(clip.profileID, jpeg: jpeg)
        XCTAssertEqual(vector.count, clip.embeddingDim)
        XCTAssertTrue(vector.allSatisfy { $0.isFinite })
        // A second embed rides the SAME worker session (no respawn).
        XCTAssertEqual(client.currentGeneration, 1)
        await client.stop()
    }

    // MARK: - The IPC spike (T1 action 3 / OQ-10-C)

    /// The OQ-10-C microbenchmark through the REAL worker process: control
    /// ping RTT, the small-image BYTE channel (base64 through the pipe), the
    /// PATH channel (worker reads the file), and the 50MP TIFF path-channel
    /// leg. Numbers land in /tmp/lightamer-ipc-spike.json and the SUMMARY —
    /// they justify the 8MB boundary; the semantics do not move with them.
    func testIPCChannelSpikeBenchmark() async throws {
        let process = Process()
        process.executableURL = try XCTUnwrap(
            Bundle.main.executableURL, "test host binary missing")
        process.arguments = [AIWorkerMain.launchFlag]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let reader = AIWorkerFrameReader(handle: stdout.fileHandleForReading)
        func roundTrip(_ request: AIWorkerRequest) throws -> AIWorkerResponse {
            try stdin.fileHandleForWriting.write(
                contentsOf: AIWorkerFrameCodec.encode(request: request))
            guard case .frame(let payload) = try XCTUnwrap(reader.readFrame())
            else { throw AIWorkerFrameError.connectionClosed }
            return try AIWorkerFrameCodec.decodeResponse(payload)
        }
        func median(_ samples: [Double]) -> Double {
            let sorted = samples.sorted()
            return sorted[sorted.count / 2]
        }

        // The CLIP-shaped small image (256² JPEG ≈ the 02 pre-scale size).
        let smallJPEG = try SemanticEngine.preScaledJPEG(
            from: Self.solidImage(edge: 256), edge: 256)
        let base64 = smallJPEG.base64EncodedString()
        let smallPath = directory.appendingPathComponent("spike-small.jpg")
        try smallJPEG.write(to: smallPath)

        func bench(_ iterations: Int, _ make: @escaping (UInt64) -> AIWorkerRequest)
            throws -> Double
        {
            var samples: [Double] = []
            for index in 0..<(iterations + 5) {
                let request = make(UInt64(index + 1))
                let start = DispatchTime.now()
                let response = try roundTrip(request)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds
                    - start.uptimeNanoseconds) / 1_000_000
                XCTAssertTrue(response.ok, response.error ?? "spike failed")
                if index >= 5 { samples.append(elapsed) }  // warmup skip
            }
            return median(samples)
        }

        let pingMedian = try bench(50) {
            AIWorkerRequest(id: $0, op: AIWorkerOp.ping.rawValue)
        }
        let byteChannelMedian = try bench(50) {
            AIWorkerRequest(
                id: $0, op: AIWorkerMain.spikeOp,
                payload: AIWorkerPayload(jpegBase64: base64))
        }
        let pathChannelMedian = try bench(50) {
            AIWorkerRequest(
                id: $0, op: AIWorkerMain.spikeOp,
                payload: AIWorkerPayload(inPath: smallPath.path))
        }

        // The 50MP TIFF path-channel leg (the enhancement family's worst
        // case; RGBA8 ≈ 196MB on disk).
        let tiffPath = directory.appendingPathComponent("spike-50mp.tif")
        try Self.writeSolidTIFF(edge: 7000, to: tiffPath)
        let tiffMedian = try bench(10) {
            AIWorkerRequest(
                id: $0, op: AIWorkerMain.spikeOp,
                payload: AIWorkerPayload(inPath: tiffPath.path))
        }

        let report: [String: Double] = [
            "ping_rtt_ms_median": pingMedian,
            "small_jpeg_byte_channel_ms_median": byteChannelMedian,
            "small_jpeg_path_channel_ms_median": pathChannelMedian,
            "small_jpeg_base64_bytes": Double(base64.count),
            "tiff_50mp_path_channel_ms_median": tiffMedian,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/lightamer-ipc-spike.json"))
        print("IPC-SPIKE " + String(data: data, encoding: .utf8)!)
    }

    // MARK: - Helpers

    /// Captures the typed client error (or nil when the call unexpectedly
    /// succeeded) — `try?` would discard the error value.
    private static func error<R>(
        of body: () async throws -> R
    ) async -> AIWorkerClientError? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error as? AIWorkerClientError
        }
    }

    private static func solidImage(edge: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: edge, height: edge, bitsPerComponent: 8,
            bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
        return try XCTUnwrap(context.makeImage())
    }

    private static func writeSolidTIFF(edge: Int, to url: URL) throws {
        // A real TIFF container (uncompressed RGBA8): the transport-relevant
        // size is the pixel payload.
        let bitmap = try XCTUnwrap(CGContext(
            data: nil, width: edge, height: edge, bitsPerComponent: 8,
            bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
        let image = try XCTUnwrap(bitmap.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil as CFDictionary?)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
