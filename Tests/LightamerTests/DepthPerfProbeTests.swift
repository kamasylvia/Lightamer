import CoreImage
import CoreML
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// DepthPerfProbeTests (M4-3-01 T7, KD-8) — the LIGHTAMER_PERF_PROBE=1-gated
// latency probe (the M2-5 convention: the default suite SKIPS this file; the
// probe run sets the env explicitly and the numbers are transcribed into
// .work/gsd/phases/m4-3-depth/perf.md).
//
// TIMING DISCIPLINE: every measurement is CPU wall-clock AROUND an awaited
// async session.run — the await is the completion fence (L014: an unfenced
// timer reads queue-async latency, not inference), so the numbers below are
// completion-to-completion.
//
// Budget reference: Apple's official ANE self-report 25-33 ms (M1/M3 Max).
// A >10× outlier is investigated (which rung actually served?) before it is
// accepted — never silently banked.
// ─────────────────────────────────────────────────────────────────────────────

final class DepthPerfProbeTests: XCTestCase {

    private static let profileID = "depth-anything-v2-small-f16"

    private static var fixtureDirectory: URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/DepthPrecision", isDirectory: true)
    }

    private static func resolvePackage() -> URL? {
        if let raw = ProcessInfo.processInfo.environment["LIGHTAMER_TEST_DEPTH_PACKAGE"],
           !raw.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: raw, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: raw, isDirectory: true)
            }
        }
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

    func testDepthInferenceLatencyProbe() async throws {
        guard ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1" else {
            throw XCTSkip("perf probe runs only under LIGHTAMER_PERF_PROBE=1")
        }
        try XCTSkipUnless(Self.resolvePackage() != nil, "depth package absent")

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("depth-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let input = Self.fixtureDirectory.appendingPathComponent("scene-soft-shapes.png")

        // ① The three compute-unit rungs: N=5 warm forwards, median.
        for (label, units) in [("all", MLComputeUnits.all),
                               ("cpuAndGPU", .cpuAndGPU),
                               ("cpuOnly", .cpuOnly)] {
            let session = try DepthSession(
                packageURL: Self.resolvePackage()!,
                manifest: ModelAssetCatalog.depthAnythingV2SmallF16,
                computeUnits: units,
                compileCacheDirectory: AIWorkerMain.compiledCacheDirectory(
                    profile: Self.profileID))
            let out = tmp.appendingPathComponent("probe-\(label).f32")
            // Warm-up (compilation + first-specialization) then N=5.
            try await session.run(inPath: input, outPath: out)
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = Date()
                try await session.run(inPath: input, outPath: out)
                samples.append(Date().timeIntervalSince(start) * 1000)
            }
            let sorted = samples.sorted()
            let median = sorted[sorted.count / 2]
            print("PERF|depth-forward|\(label)|median=\(String(format: "%.1f", median))ms|samples=\(samples.map { String(format: "%.1f", $0) }.joined(separator: ","))")
        }

        // ② One end-to-end production journey: preview JPEG → worker
        //    runDepth → float readback → four-stage pipeline (the bake
        //    rides the shared IOP-MASK-03 channel, not re-measured here).
        let client = AIWorkerClient(configuration: .init(
            record: CompatRecord(
                path: tmp.appendingPathComponent("ai-compat.json")),
            machineKey: "DepthPerf/TESTBUILD"))
        defer { Task { await client.stop() } }
        let preview = try DepthMaskService.writePreviewJPEG(
            from: AIMaskInput(ciImage: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                .cropped(to: CGRect(x: 0, y: 0, width: 3000, height: 2000))))
        defer { try? FileManager.default.removeItem(at: preview) }
        let out = tmp.appendingPathComponent("e2e.f32")
        let start = Date()
        _ = try await client.runDepth(
            Self.profileID, inPath: preview.path, outPath: out.path)
        let plane = try DepthMaskService.readDepthPlane(
            from: out, expectedWidth: 518, expectedHeight: 392)
        let alpha = try DepthMaskPipeline.nearMask(depth: plane)
        let e2e = Date().timeIntervalSince(start) * 1000
        print("PERF|depth-e2e|preview→workerRun→readback→pipeline|median=\(String(format: "%.1f", e2e))ms|alpha=\(alpha.width)x\(alpha.height)")
    }
}
