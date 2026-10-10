import CoreML
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// DepthGoldenTests (M4-3-01 T6, KD-7, OQ-6) — the golden three gates over the
// REAL F16 package. All model-present tests XCTSkipUnless the package
// resolves (env `LIGHTAMER_TEST_DEPTH_PACKAGE` injection first, then the
// installed Application Support root) — a model-less CI environment skips
// with zero failures; the acceptance machine (package installed) runs them
// for real (DECISIONS §5 records the install command).
//
// Gates:
//   ① precision   abs-rel ≤ 0.01 + max-abs ≤ 0.02 over the three in-gate
//                 fixtures (the ramp is excluded by domain — see the
//                 fixture README's measured distribution; NOT a lowered
//                 gate).
//   ② determinism same package + same compute units → byte-identical
//                 outPath (the gpuPinned precedent: same-device only, no
//                 cross-device promise).
//   ③ end-to-end  the real worker subprocess open+run round trip (header
//                 + finite + variance) — the m5 open-shape difference is
//                 asserted here too (depth open carries NO facts).
// ─────────────────────────────────────────────────────────────────────────────

final class DepthGoldenTests: XCTestCase {

    private static let profileID = "depth-anything-v2-small-f16"

    /// 518×392 (the D-4 spike pin).
    private static let shape = (width: 518, height: 392)

    /// In-gate fixtures: soft-shapes / texture / edges (CPU-device-matched
    /// leg; edges matched-pipeline = 0.0036). The fixtures are sRGB-ICC-
    /// tagged by the generator so the runtime decode is byte-exact against
    /// the reference pipeline (probed: CG row bytes == PIL row bytes).
    /// horizon + ramp stay in the fixture set for the END-TO-END leg only —
    /// horizon matched-pipeline sits at 0.0092 (92% of gate; margin
    /// hygiene), ramp is a structure-less OOD input (README's measured
    /// table).
    private static let gateFixtures = [
        "scene-soft-shapes.png", "scene-texture.png", "target-edges.png",
    ]

    private static var fixtureDirectory: URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/DepthPrecision", isDirectory: true)
    }

    /// The F16 package: env injection first, then the installed root.
    private static func resolvePackage() -> URL? {
        if let raw = ProcessInfo.processInfo.environment["LIGHTAMER_TEST_DEPTH_PACKAGE"],
           !raw.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: raw, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: raw, isDirectory: true)
            }
        }
        // The installed root (the walkthrough machine's package location).
        var name = ModelAssetCatalog.depthAnythingV2SmallF16.assetFileName
        if name.hasSuffix(".zip") { name = String(name.dropLast(4)) }
        guard let installed = try? ModelLocator().installedProfileURL(profileID) else {
            return nil
        }
        let candidate = installed.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: candidate.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return candidate
    }

    private func makeSession(units: MLComputeUnits = .all) throws -> DepthSession {
        let package = try XCTUnwrap(Self.resolvePackage(), "depth package absent")
        return try DepthSession(
            packageURL: package,
            manifest: ModelAssetCatalog.depthAnythingV2SmallF16,
            computeUnits: units,
            compileCacheDirectory: AIWorkerMain.compiledCacheDirectory(
                profile: Self.profileID))
    }

    /// The reference block order = the GENERATOR's INPUTS order (five
    /// blocks) — never the gate list's indices (the T6 self-catch: an
    /// edges-output-vs-horizon-reference comparison measured 0.16 abs-rel
    /// and exposed the mis-mapping).
    private static let referenceOrder = [
        "scene-soft-shapes.png", "scene-texture.png", "scene-horizon.png",
        "target-ramp.png", "target-edges.png",
    ]

    /// The per-fixture reference block from ref-f32.bin.
    private func referenceBlock(_ fixture: String) throws -> [Float] {
        let index = try XCTUnwrap(
            Self.referenceOrder.firstIndex(of: fixture),
            "fixture missing from the reference order")
        let url = Self.fixtureDirectory.appendingPathComponent("ref-f32.bin")
        let data = try Data(contentsOf: url)
        let stride = 8 + Self.shape.width * Self.shape.height * 4
        let offset = index * stride
        let width = data.withUnsafeBytes {
            UInt32(littleEndian: $0.load(fromByteOffset: offset, as: UInt32.self))
        }
        let height = data.withUnsafeBytes {
            UInt32(littleEndian: $0.load(fromByteOffset: offset + 4, as: UInt32.self))
        }
        XCTAssertEqual(Int(width), Self.shape.width)
        XCTAssertEqual(Int(height), Self.shape.height)
        let count = Self.shape.width * Self.shape.height
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            (0..<count).map { raw.load(fromByteOffset: offset + 8 + $0 * 4, as: Float32.self) }
        }
    }

    // MARK: ① Precision gate (abs-rel ≤ 0.01 + max-abs ≤ 0.02)

    /// The SHIPPED leg: the `.all` (ANE-first) session against the CPU_ONLY
    /// F32 reference. (The T6 debugging detour proved the session output
    /// byte-identical to the coremltools CPU predict on the same input —
    /// an earlier "ANE numerics" suspicion was the reference mis-index.)
    func testPrecisionGateAgainstF32Reference() async throws {
        try XCTSkipUnless(Self.resolvePackage() != nil, "depth package absent")
        let session = try makeSession(units: .all)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("depth-golden-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        for fixture in Self.gateFixtures {
            let input = Self.fixtureDirectory.appendingPathComponent(fixture)
            let output = tmp.appendingPathComponent("out-\(fixture).f32")
            try await session.run(inPath: input, outPath: output)
            let plane = try DepthMaskService.readDepthPlane(
                from: output,
                expectedWidth: Self.shape.width,
                expectedHeight: Self.shape.height)
            let reference = try referenceBlock(fixture)

            var absSum = 0.0, maxAbs = 0.0
            for (value, ref) in zip(plane.floats, reference) {
                let difference = abs(Double(value) - Double(Float(ref)))
                absSum += difference / max(abs(Double(ref)), 1e-3)
                maxAbs = max(maxAbs, difference)
            }
            let absRel = absSum / Double(plane.floats.count)
            XCTAssertLessThanOrEqual(
                absRel, 0.01,
                "\(fixture) abs-rel \(absRel) (the OQ-6 conversion gate)")
            XCTAssertLessThanOrEqual(
                maxAbs, 0.02,
                "\(fixture) max-abs \(maxAbs) (the T6-pinned ceiling)")
        }
    }

    // MARK: ② Determinism gate (same package + units → byte-identical)

    func testDeterminismDoubleRunByteIdentical() async throws {
        try XCTSkipUnless(Self.resolvePackage() != nil, "depth package absent")
        let session = try makeSession()
        let input = Self.fixtureDirectory.appendingPathComponent("scene-soft-shapes.png")
        let first = FileManager.default.temporaryDirectory
            .appendingPathComponent("depth-det-a-\(UUID().uuidString).f32")
        let second = FileManager.default.temporaryDirectory
            .appendingPathComponent("depth-det-b-\(UUID().uuidString).f32")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try await session.run(inPath: input, outPath: first)
        try await session.run(inPath: input, outPath: second)
        XCTAssertEqual(
            try Data(contentsOf: first), try Data(contentsOf: second),
            "same device + units must be byte-identical (no cross-device promise)")
    }

    // MARK: ③ Worker end-to-end (the real subprocess round trip)

    func testWorkerLoopEndToEndDepthRoundTrip() async throws {
        // The WORKER resolves through its own default locator — this test
        // needs the package INSTALLED (not env-injected).
        guard let installed = try? ModelLocator().installedProfileURL(Self.profileID),
              let package = DepthSession.resolvePackage(
                profile: Self.profileID,
                manifest: ModelAssetCatalog.depthAnythingV2SmallF16,
                locator: ModelLocator())
        else {
            throw XCTSkip("depth package not installed (worker resolvable root)")
        }
        _ = package

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("depth-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = AIWorkerClient(configuration: .init(
            record: CompatRecord(
                path: directory.appendingPathComponent("ai-compat.json")),
            machineKey: "DepthGolden/TESTBUILD",
            openTimeout: 900, runTimeout: 600))
        defer { Task { await client.stop() } }

        let input = Self.fixtureDirectory.appendingPathComponent("scene-soft-shapes.png")
        let output = directory.appendingPathComponent("out.f32")
        let returned = try await client.runDepth(
            Self.profileID, inPath: input.path, outPath: output.path)
        XCTAssertEqual(returned, output.path, "the PATH-channel echo")

        let plane = try DepthMaskService.readDepthPlane(
            from: output,
            expectedWidth: Self.shape.width,
            expectedHeight: Self.shape.height)
        XCTAssertTrue(plane.floats.allSatisfy { $0.isFinite }, "finite all (m3 face)")
        let minV = plane.floats.min() ?? 0, maxV = plane.floats.max() ?? 0
        XCTAssertLessThan(minV, maxV, "a real inference carries variance")

        // m5: the depth open carries NO model facts — the client's
        // enhancement-facts memo stays nil through the depth open (the
        // two-leg open-shape difference; the enhancement open returns
        // tileEdges/scale).
        XCTAssertNil(
            client.lastEnhancementModelFacts,
            "a depth open must not populate the enhancement facts memo")
    }
}
