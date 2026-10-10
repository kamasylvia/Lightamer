import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// DepthWorkerLegTests (M4-3-01 T3, KD-2) — the worker-process depth leg over
// REAL child processes (the AIWorkerClientTests discipline: the host binary
// with `--ai-worker`, real exit(9)s through the DEBUG crash hook).
//
// NO-ASSET DISCIPLINE: the crash-chain and envelope tests need NO model
// bytes (the hook fires BEFORE asset resolution). The absent-assets typed
// face is gated XCTSkipUnless — on a machine where the depth package IS
// installed (the acceptance machine post-T8) it skips; the model-present
// behaviors live in DepthGoldenTests (env-gated there).
//
// m5's routing钉 is two-legged by design: (a) the family discriminant's
// six-profile exhaustiveness lives in ModelAssetCatalogTests (T1); (b) the
// env-gated real-model open SHAPE difference (depth open = no
// tileEdges/scale, enhancement open = both) lives in DepthGoldenTests. In
// a no-asset environment both legs answer the same "profile assets absent"
// frame — nothing is assertable here beyond "no culprit, no chain cost",
// which the gated test below pins.
// ─────────────────────────────────────────────────────────────────────────────

final class DepthWorkerLegTests: XCTestCase {

    private var directory: URL!
    private static let machine = "DepthLegTestMachine/TESTBUILD"
    private static let depthProfile = "depth-anything-v2-small-f16"
    private static let hookEnv = "LIGHTAMER_TEST_AI_WORKER_CRASH"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightamer-depth-leg-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        unsetenv(Self.hookEnv)
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    private func makeClient(record: CompatRecord? = nil) -> AIWorkerClient {
        AIWorkerClient(configuration: .init(
            record: record ?? CompatRecord(
                path: directory.appendingPathComponent("ai-compat.json")),
            machineKey: Self.machine,
            openTimeout: 120, runTimeout: 120, pingTimeout: 20))
    }

    private static func depthPackageInstalled() -> Bool {
        let locator = ModelLocator()
        if locator.bundledProfileURL(depthProfile) != nil { return true }
        guard let installed = try? locator.installedProfileURL(depthProfile) else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: installed.appendingPathComponent(
                "depth-anything-v2-small-f16.mlpackage").path,
            isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: Crash injection — the hook fires for depth profiles for free

    /// Hook = the bare profile name (crash EVERY open; the `@units` form
    /// restricts to the listed rungs). The chain consumes [.all,
    /// .cpuAndGPU] (recorded) and crashes .cpuOnly (never recorded — the
    /// CPU floor) → typed exhaustion, one spawn per rung. The hook sits
    /// BEFORE asset resolution in the open path, so this needs no model
    /// bytes and proves the depth client leg drives the SAME fallback
    /// machinery (KD-2's "free effectiveness").
    func testCrashInjectionOnDepthProfileRunsTheChain() async throws {
        setenv(Self.hookEnv, Self.depthProfile, 1)
        let record = CompatRecord(
            path: directory.appendingPathComponent("ai-compat.json"))
        let client = makeClient(record: record)

        let inPath = directory.appendingPathComponent("in.jpg").path
        let outPath = directory.appendingPathComponent("out.f32").path
        let error = await Self.error {
            try await client.runDepth(Self.depthProfile, inPath: inPath, outPath: outPath)
        }

        XCTAssertEqual(error, .workerExhausted)
        XCTAssertEqual(client.currentGeneration, 3, "one spawn per rung")
        XCTAssertTrue(record.excluded(
            machineKey: Self.machine, model: Self.depthProfile).contains(.all))
        XCTAssertTrue(record.excluded(
            machineKey: Self.machine, model: Self.depthProfile).contains(.cpuAndGPU))
        XCTAssertFalse(record.excluded(
            machineKey: Self.machine, model: Self.depthProfile).contains(.cpuOnly))
        await client.stop()
    }

    // MARK: Envelope round-trip — PATH-channel field reuse, zero new fields

    /// The depth frame is the EXISTING envelope shape: `inPath`/`outPath`
    /// (the M2-10-05 PATH channel), no depth-specific keys, no new
    /// envelope fields (the AIWorkerProtocol wire is untouched).
    func testDepthEnvelopeRoundTripReusesPathChannel() throws {
        let payload = AIWorkerPayload(
            inPath: "/tmp/in.jpg", outPath: "/tmp/out.f32")
        let request = AIWorkerRequest(
            id: 42, op: AIWorkerOp.run.rawValue,
            profile: Self.depthProfile, units: AIComputeUnits.all.rawValue,
            payload: payload)
        let data = try AIWorkerFrameCodec.encode(request: request)
        let decoded = try AIWorkerFrameCodec.decodeRequest(data.dropFirst(4))

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.payload?.inPath, "/tmp/in.jpg")
        XCTAssertEqual(decoded.payload?.outPath, "/tmp/out.f32")
        XCTAssertNil(decoded.payload?.tile)
        XCTAssertNil(decoded.payload?.jpegBase64)
        XCTAssertNil(decoded.payload?.tokens)
        // Zero-new-fields: the payload JSON carries ONLY the established
        // keys (mask/jpegBase64/inPath/outPath/tile/tokens).
        let json = String(data: data.dropFirst(4), encoding: .utf8) ?? ""
        let knownKeys: Set<String> = [
            "id", "op", "profile", "units", "payload",
            "tokens", "mask", "jpegBase64", "inPath", "outPath", "tile",
        ]
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for key in object.keys {
            XCTAssertTrue(knownKeys.contains(key), "unexpected envelope key: \(key)")
        }
        let payloadObject = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(
            Set(payloadObject.keys), ["inPath", "outPath"],
            "the depth frame populates exactly the PATH channel")
    }

    // MARK: Absent assets — profile-level typed failure, no culprit

    /// On a machine WITHOUT the depth package: the open leg answers
    /// "profile assets absent" WITHOUT a culprit → the client surfaces
    /// typed `.requestFailed`, the chain is NOT consumed (record stays
    /// empty, no respawn). This is the honest install-gate face (D-2's
    /// modelNotReady semantic at the worker boundary).
    func testDepthProfileWithoutAssetsSurfacesTypedWithoutCulprit() async throws {
        try XCTSkipUnless(
            !Self.depthPackageInstalled(),
            "depth package installed on this machine — the absent-assets face is unreachable")

        let record = CompatRecord(
            path: directory.appendingPathComponent("ai-compat.json"))
        let client = makeClient(record: record)

        let inPath = directory.appendingPathComponent("in.jpg").path
        let outPath = directory.appendingPathComponent("out.f32").path
        let error = await Self.error {
            try await client.runDepth(Self.depthProfile, inPath: inPath, outPath: outPath)
        }

        guard case .requestFailed(let message) = error else {
            return XCTFail("expected requestFailed, got \(error)")
        }
        XCTAssertTrue(
            message.contains("profile assets absent"),
            "the profile-level message, got: \(message)")
        XCTAssertTrue(
            record.excluded(machineKey: Self.machine, model: Self.depthProfile).isEmpty,
            "no culprit → no degradation bookkeeping")
        XCTAssertEqual(client.currentGeneration, 1, "no respawn")
        await client.stop()
    }

    // MARK: Error folding

    private static func error(
        _ body: () async throws -> some Sendable
    ) async -> AIWorkerClientError {
        do {
            _ = try await body()
            fatalError("expected a throw")
        } catch let error as AIWorkerClientError {
            return error
        } catch {
            fatalError("unexpected error type: \(error)")
        }
    }
}
