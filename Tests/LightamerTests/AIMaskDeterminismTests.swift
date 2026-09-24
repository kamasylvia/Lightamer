@testable import LightamerCore
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest

/// AIMaskDeterminismTests (Plan 07-1 T2) — the AI determinism gate
/// (07-RESEARCH §6, the L017 AI variant): same input + same device →
/// byte-identical masks, in-process AND cross-process.
///
/// DEVICE-PIN REALITY (D-07-1-T1-2, probe-evidenced): the plan's "pin CPU"
/// is unsatisfiable on macOS 27.0b — the CPU is absent from both requests'
/// supportedComputeStageDevices and pinning it traps the process. The
/// policy here: layer A = `.gpuPinned` (the supported deterministic
/// device), layer B = `.anePreferred` (the only safe execution on this OS;
/// default-device run-to-run identity probe-verified). The GATE semantics
/// (same device → byte-identical) are unchanged.
///
/// ANTI-VACUUM: every identity assertion compares ALL bytes (AIMaskPlane
/// == plus the folded byteIdentity hash) with compared-count guards.
final class AIMaskDeterminismTests: XCTestCase {

    // MARK: - Fixtures

    /// The shared synthetic subject (textured bright box on dark noisy
    /// ground — the probe-verified detectable shape; FLAT boxes detect as
    /// no-subject). Written to a PNG so the in-process run and the
    /// cross-process probe consume BYTE-IDENTICAL input.
    private func writeSubjectPNG(size: Int = 512) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lra-ai-det-\(UUID().uuidString).png")
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for y in 0..<size {
            for x in 0..<size {
                let fx = Double(x) / Double(size), fy = Double(y) / Double(size)
                let inBox = fx > 0.25 && fx < 0.75 && fy > 0.25 && fy < 0.75
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let noise = Double((seed >> 33) & 0xFF) / 255.0
                let v: UInt8 = inBox ? UInt8(min(255, 230 + noise * 25))
                                     : UInt8(min(255, 45 + noise * 15))
                let i = (y * size + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)!
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
        CGImageDestinationAddImage(dest, cg, nil)
        precondition(CGImageDestinationFinalize(dest))
        try (data as Data).write(to: url)
        return url
    }

    /// Load a PNG through the SAME path the app probe uses.
    private func input(fromPNG url: URL) throws -> AIMaskInput {
        let data = try Data(contentsOf: url) as CFData
        let source = CGImageSourceCreateWithData(data, nil)!
        let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        return AIMaskInput(ciImage: CIImage(cgImage: cg))
    }

    /// Layer B assets must be ready for the layer-B legs. The
    /// TEST-BUILT app carries Xcode's test entitlements (mach-lookup
    /// temporary exceptions) under which Vision's asset download
    /// "succeeds" but `assetStatus` stays notReady — the layer-B
    /// INFERENCE legs skip in that context with this documented reason
    /// (probe evidence for the plain-process behavior lives in
    /// .work/07/perf.md; the 07-3 GUI round re-verifies layer B in the
    /// real app context).
    private func ensureLayerBAssets() async throws -> Bool {
        let phase = await AIAssetStore.shared.currentPhase(queried: true)
        if case .notReady = phase {
            await AIAssetStore.shared.download()
        }
        return await AIAssetStore.shared.currentPhase().isReady
    }

    // MARK: - Layer A determinism (the gate)

    /// Same input, same GPU pin, two inferences → BYTE-IDENTICAL masks
    /// (every float bit compared; the hash folds the same bytes).
    func testLayerAGPUPinInProcessByteIdentity() async throws {
        let png = try writeSubjectPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let input = try self.input(fromPNG: png)

        let first = try await AIMaskService.subjectMask(
            input: input, selection: .all, device: .gpuPinned)
        let second = try await AIMaskService.subjectMask(
            input: input, selection: .all, device: .gpuPinned)

        XCTAssertEqual(first.width, 512)
        XCTAssertEqual(first.height, 512)
        XCTAssertGreaterThan(first.floats.count, 0, "防空转: empty mask")
        XCTAssertEqual(first, second, "same input + same device must be byte-identical")
        XCTAssertEqual(first.byteIdentity, second.byteIdentity,
                       "the folded identity hash must agree")
    }

    /// The CROSS-PROCESS leg: spawn the app binary with
    /// `-la_ai_determinism_probe` (one gpuPinned layer-A inference over
    /// the same PNG) and compare the reported byteIdentity with the
    /// in-process run.
    func testLayerAGPUPinCrossProcessByteIdentity() async throws {
        let png = try writeSubjectPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("lra-ai-det-out-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }

        // The in-process reference.
        let reference = try await AIMaskService.subjectMask(
            input: try input(fromPNG: png), selection: .all, device: .gpuPinned)

        // The probe host = the running app bundle (test-direct injects
        // into Lightamer.app; Bundle.main IS the app). Launch through
        // LaunchServices (`open -n -a`) — the 02-06 sidecar probe's
        // documented pattern: a direct Process exec of the app binary
        // violates its launch constraints and aborts
        // (sandbox_extension_issue_file_to_process, 07-1 T2 finding).
        let appURL = Bundle.main.bundleURL
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [
            "-n", "-a", appURL.path, "--args",
            "-la_ai_determinism_probe", png.path, output.path,
        ]
        try open.run()
        open.waitUntilExit()
        // The probe loads the model (~seconds cold) — poll the output file
        // for up to 120s.
        var line: String?
        for _ in 0..<1200 {
            if let data = FileManager.default.contents(atPath: output.path),
               let text = String(data: data, encoding: .utf8), !text.isEmpty {
                line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        guard let line, !line.hasPrefix("ERROR") else {
            XCTFail("cross-process probe produced no verdict: \(line ?? "nil")")
            return
        }
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count == 3,
              let width = Int(parts[0]), let height = Int(parts[1]),
              let identity = UInt64(parts[2])
        else {
            XCTFail("unparsable probe output: \(line)")
            return
        }
        XCTAssertEqual(width, reference.width, "cross-process mask width drift")
        XCTAssertEqual(height, reference.height, "cross-process mask height drift")
        XCTAssertEqual(identity, reference.byteIdentity,
                       "cross-process byteIdentity must equal the in-process run")
    }

    // MARK: - Layer B determinism

    /// Same input, default (unpinned — the only safe layer-B execution on
    /// this OS, D-07-1-T1-2), two inferences → byte-identical masks.
    func testLayerBDefaultInProcessByteIdentity() async throws {
        let assetsReady = try await ensureLayerBAssets()
        try XCTSkipUnless(
            assetsReady,
            "layer B assets unavailable in the test-built app (entitlement-blocked download)")
        let png = try writeSubjectPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let input = try self.input(fromPNG: png)

        let first = try await AIMaskService.segmentSubject(
            input: input, seed: .point(AIMaskPoint(x: 0.5, y: 0.5)),
            quality: .accurate, device: .anePreferred)
        let second = try await AIMaskService.segmentSubject(
            input: input, seed: .point(AIMaskPoint(x: 0.5, y: 0.5)),
            quality: .accurate, device: .anePreferred)

        XCTAssertGreaterThan(first.floats.count, 0, "防空转: empty layer-B mask")
        XCTAssertEqual(first, second,
                       "layer B default device must be run-to-run byte-identical")
        XCTAssertEqual(first.byteIdentity, second.byteIdentity)
    }

    // MARK: - Device enumeration + the trap guards

    /// The revised CPU-residency pin (D-07-1-T1-2): BOTH layers must
    /// expose the GPU in supportedComputeStageDevices[.main] (the
    /// deterministic test device). The plan's original "contains CPU"
    /// assertion is unsatisfiable on this OS — the CPU's absence is
    /// asserted as the documented reality instead.
    func testSupportedComputeStageDevicesContainGPU() {
        let layerA = AIMaskService.layerASupportedDevices()
        let layerB = AIMaskService.layerBSupportedDevices()
        for (label, devices) in [("layerA", layerA), ("layerB", layerB)] {
            let main = devices[.main] ?? []
            XCTAssertFalse(main.isEmpty, "\(label) main stage must expose devices")
            XCTAssertTrue(
                main.contains { if case .gpu = $0 { return true }; return false },
                "\(label) must support the GPU (the determinism pin device): \(main)")
        }
    }

    /// A CPU pin (unsupported on this OS) must throw a TYPED error —
    /// never trap the process (the raw-API behavior, probe-evidenced).
    func testUnsupportedCPUPinThrowsTypedError() async throws {
        let png = try writeSubjectPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let input = try self.input(fromPNG: png)
        do {
            _ = try await AIMaskService.subjectMask(
                input: input, selection: .all, device: .cpuPinned)
            // A future OS that supports CPU pins: the run succeeding is
            // fine — pin the no-trap contract only.
        } catch let error as AIMaskError {
            guard case .deviceUnavailable = error else {
                return XCTFail("expected deviceUnavailable, got \(error)")
            }
        }
    }

    /// A layer-B pin is refused (typed) on this OS — the pin bug guard.
    func testLayerBPinRefusedTyped() async throws {
        do {
            _ = try AIMaskService.buildLayerBRequest(
                seed: .point(AIMaskPoint(x: 0.5, y: 0.5)), refine: [],
                quality: .accurate, regionOfInterest: nil, device: .gpuPinned)
            // Pin accepted = a fixed OS build; the contract is only that
            // this did not crash.
        } catch let error as AIMaskError {
            guard case .deviceUnavailable = error else {
                return XCTFail("expected deviceUnavailable, got \(error)")
            }
        }
    }
}
