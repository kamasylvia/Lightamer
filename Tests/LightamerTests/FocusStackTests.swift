@testable import LightamerCore
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FocusStackTests (Plan 08-3 T1/T2) — the focus-stacking verification set.
//
// T1 (the SML measure): the defocus-proxy separation (P5's 59× order),
// the half-precision round-trip tolerance against the float64 CPU mirror,
// the content-level zero/impulse anchors, the L014 drain correctness under
// a loaded queue, the no-drain stale-race demonstration (the proof shape
// D-08-3-T1-3), and the tenengrad additive slot.
//
// T2 (the pyramid fusion): the clear-region attribution MAE (P5's PASS
// shape ≈0.004), the band-streamed constant-memory footprint, and the
// NCC scale-drift warning that never blocks the merge.
//
// Fixtures are synthetic, LOCAL-disk only (L009 — never the workspace).
// ─────────────────────────────────────────────────────────────────────────────

final class FocusStackTests: XCTestCase {

    // MARK: - Fixture machinery

    /// Fixed-seed LCG texture — the sharp (in-focus) proxy: white-noise
    /// texture is all high frequency, so any real blur collapses its SML
    /// (the P5 defocus-proxy shape at fixture scale).
    private static func texture(
        _ width: Int, _ height: Int, seed: UInt64, low: Float = 0.05, high: Float = 0.95
    ) -> [Float] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        var pixels = [Float](repeating: 0, count: width * height)
        for index in pixels.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let uniform = Float((state >> 33) & 0xFFFFF) / Float(0xFFFFF)
            pixels[index] = low + (high - low) * uniform
        }
        return pixels
    }

    /// One RGBA float32 plane from gray luma values (channel-equal triple).
    private static func rgbaPlane(
        gray: [Float], width: Int, height: Int
    ) -> [Float] {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            rgba[index * 4] = gray[index]
            rgba[index * 4 + 1] = gray[index]
            rgba[index * 4 + 2] = gray[index]
            rgba[index * 4 + 3] = 1
        }
        return rgba
    }

    /// Scope the plane's raw buffer (the pointer never escapes — validity
    /// rides the array's lifetime inside `body`).
    private func withPlane<T>(
        _ rgba: [Float], _ body: (UnsafeRawBufferPointer) throws -> T
    ) rethrows -> T {
        try rgba.withUnsafeBufferPointer {
            try body(UnsafeRawBufferPointer($0))
        }
    }

    /// In-place separable box blur (one pass, radius r, clamp edges) over a
    /// gray luma — three passes approximate the Gaussian defocus proxy.
    private static func boxBlur(
        _ source: [Float], width: Int, height: Int, radius: Int
    ) -> [Float] {
        var current = source
        for _ in 0..<3 {
            var horizontal = [Float](repeating: 0, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    var sum: Float = 0
                    var count = 0
                    for dx in -radius...radius {
                        let sx = x + dx
                        guard sx >= 0, sx < width else { continue }
                        sum += current[y * width + sx]
                        count += 1
                    }
                    horizontal[y * width + x] = sum / Float(count)
                }
            }
            var vertical = [Float](repeating: 0, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    var sum: Float = 0
                    var count = 0
                    for dy in -radius...radius {
                        let sy = y + dy
                        guard sy >= 0, sy < height else { continue }
                        sum += horizontal[sy * width + x]
                        count += 1
                    }
                    vertical[y * width + x] = sum / Float(count)
                }
            }
            current = vertical
        }
        return current
    }

    private struct GPU {
        let device: any MTLDevice
        let queue: any MTLCommandQueue
        static func make() throws -> GPU {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else {
                throw XCTSkip("no Metal device")
            }
            return GPU(device: device, queue: queue)
        }
    }

    private func halfToFloat(_ bits: [UInt16]) -> [Float] {
        bits.map { Float(Float16(bitPattern: $0)) }
    }

    // MARK: - T1: the SML separation (P5's 59× order)

    func testSMLSeparationSharpVersusBlurred() throws {
        let gpu = try GPU.make()
        let width = 256, height = 192
        let sharp = Self.texture(width, height, seed: 0xF0C0)
        let blurred = Self.boxBlur(sharp, width: width, height: height, radius: 4)
        let sharpRGBA = Self.rgbaPlane(gray: sharp, width: width, height: height)
        let blurredRGBA = Self.rgbaPlane(gray: blurred, width: width, height: height)

        let sharpMap = try withPlane(sharpRGBA) { plane in
            try halfToFloat(FocusMeasure.qualityMap(
                plane: plane, width: width, height: height, bytesPerRow: width * 16,
                device: gpu.device, queue: gpu.queue))
        }
        let blurredMap = try withPlane(blurredRGBA) { plane in
            try halfToFloat(FocusMeasure.qualityMap(
                plane: plane, width: width, height: height, bytesPerRow: width * 16,
                device: gpu.device, queue: gpu.queue))
        }

        let sharpMean = sharpMap.reduce(0, +) / Float(sharpMap.count)
        let blurredMean = blurredMap.reduce(0, +) / Float(blurredMap.count)
        XCTAssertGreaterThan(sharpMean, 0, "a sharp texture must carry focus energy")
        // The P5 probe measured 59× on its defocus proxy; the assertion is
        // the ORDER of magnitude (≥ 20×), not the exact probe fixture.
        let ratio = sharpMean / max(blurredMean, 1e-6)
        XCTAssertGreaterThan(ratio, 20, "sharp/blurred SML ratio \(ratio) below the separation floor")
    }

    // MARK: - T1: half round-trip + content anchors

    func testSMLMatchesCPUReferenceWithinHalfTolerance() throws {
        let gpu = try GPU.make()
        let width = 96, height = 64
        let values = Self.texture(width, height, seed: 0x51A1)
        let rgba = Self.rgbaPlane(gray: values, width: width, height: height)
        let gpuMap = try withPlane(rgba) { plane in
            try halfToFloat(FocusMeasure.qualityMap(
                plane: plane, width: width, height: height, bytesPerRow: width * 16,
                device: gpu.device, queue: gpu.queue))
        }
        let reference = withPlane(rgba) { plane in
            FocusMeasure.qualityMapCPU(
                plane, width: width, height: height, bytesPerRow: width * 16)
        }
        XCTAssertEqual(gpuMap.count, reference.count)
        var worstRelative: Float = 0
        for index in reference.indices {
            let expected = reference[index]
            let actual = gpuMap[index]
            // Half storage (11-bit mantissa) + float32 kernel accumulation —
            // the round-trip tolerance is 1% relative with a tiny absolute
            // floor for near-zero cells (D-08-3-T1-4).
            let tolerance = max(abs(expected) * 0.01, 1e-4)
            worstRelative = max(worstRelative, abs(actual - expected) / tolerance)
            XCTAssertEqual(actual, expected, accuracy: tolerance, "at \(index)")
        }
        XCTAssertLessThanOrEqual(worstRelative, 1.0)
    }

    func testSMLConstantFieldIsZeroAndImpulseLocalizes() throws {
        let gpu = try GPU.make()
        let width = 64, height = 64
        var values = [Float](repeating: 0.4, count: width * height)
        // A constant field is perfectly in-focus per SML (no gradient) —
        // the map must be exactly zero; the impulse lights its own window.
        let impulse = (y: 20, x: 30)
        values[impulse.y * width + impulse.x] = 0.9
        let rgba = Self.rgbaPlane(gray: values, width: width, height: height)
        let map = try withPlane(rgba) { plane in
            try halfToFloat(FocusMeasure.qualityMap(
                plane: plane, width: width, height: height, bytesPerRow: width * 16,
                device: gpu.device, queue: gpu.queue))
        }
        let center = map[impulse.y * width + impulse.x]
        XCTAssertGreaterThan(center, 0, "the impulse must carry SML energy")
        let farCorner = map[(height - 3) * width + (width - 3)]
        XCTAssertEqual(farCorner, 0, accuracy: 1e-6,
            "a constant field's SML must be exactly zero away from the impulse")
        let neighbor = map[impulse.y * width + impulse.x + 2]
        XCTAssertLessThan(neighbor, center,
            "the impulse window must dominate its outside neighborhood")
    }

    // MARK: - T1: the L014 drain (correctness + the race demonstration)

    /// With the drain in place, a QUEUED heavy kernel in front of the SML
    /// dispatch cannot corrupt the readback — parity with the CPU reference
    /// holds across repeated runs.
    func testDrainReadbackCorrectUnderQueuedLoad() throws {
        let gpu = try GPU.make()
        let width = 64, height = 48
        let values = Self.texture(width, height, seed: 0xD1A1)
        let rgba = Self.rgbaPlane(gray: values, width: width, height: height)
        let reference = withPlane(rgba) { plane in
            FocusMeasure.qualityMapCPU(
                plane, width: width, height: height, bytesPerRow: width * 16)
        }
        // A heavy GHOST job first (a long-spin SML dispatch whose output is
        // discarded), then the real one — the drain orders behind both.
        _ = try withPlane(rgba) { plane in
            try FocusMeasure.qualityMap(
                plane: plane, width: width, height: height, bytesPerRow: width * 16,
                device: gpu.device, queue: gpu.queue, spinIterations: 200_000)
        }
        for _ in 0..<3 {
            let map = try withPlane(rgba) { plane in
                try halfToFloat(FocusMeasure.qualityMap(
                    plane: plane, width: width, height: height, bytesPerRow: width * 16,
                    device: gpu.device, queue: gpu.queue))
            }
            for index in reference.indices {
                XCTAssertEqual(
                    map[index], reference[index],
                    accuracy: max(abs(reference[index]) * 0.01, 1e-4),
                    "drained readback diverged at \(index) — stale-plane race")
            }
        }
    }

    /// The negative control (D-08-3-T1-3, the proof shape): a stalled
    /// dispatch read WITHOUT the drain observes the PREVIOUS plane's output
    /// — the race the production wait eliminates. The stall (spin ≈ ms)
    /// makes the window deterministic: the GPU is far from completion when
    /// the CPU read lands microseconds after commit. The stale face is the
    /// PRIOR dispatch's map (texture energy) where the new input (a
    /// constant field) must produce all zeros — no reliance on fresh-buffer
    /// zero-init.
    func testNoDrainReadDemonstratesStaleRace() throws {
        let gpu = try GPU.make()
        let width = 64, height = 48
        let textureValues = Self.texture(width, height, seed: 0xBEEF)
        let constantValues = [Float](repeating: 0.4, count: width * height)
        let textureRGBA = Self.rgbaPlane(gray: textureValues, width: width, height: height)
        let constantRGBA = Self.rgbaPlane(gray: constantValues, width: width, height: height)

        // ① A drained texture dispatch into the SHARED buffer first — the
        // buffer now provably holds the TEXTURE's map (nonzero energy).
        guard let sharedOutput = gpu.device.makeBuffer(
            length: width * height * MemoryLayout<UInt16>.size,
            options: .storageModeShared)
        else { throw XCTSkip("no shared MTLBuffer") }
        try withPlane(textureRGBA) { plane in
            try FocusMeasure.dispatch(
                into: sharedOutput, plane: plane, width: width, height: height,
                bytesPerRow: width * 16, device: gpu.device, queue: gpu.queue,
                spinIterations: 0, waitsCompletion: true)
        }
        let firstBits = sharedOutput.contents()
            .bindMemory(to: UInt16.self, capacity: width * height)
        let firstMap = Array(UnsafeBufferPointer(start: firstBits, count: width * height))
        XCTAssertFalse(firstMap.map(Float.init).allSatisfy { $0 == 0 })

        // ② The stalled CONSTANT-FIELD dispatch into the SAME buffer, read
        // without the drain — the CPU observes the texture's stale map, not
        // the zeros the new input produces.
        try withPlane(constantRGBA) { plane in
            try FocusMeasure.dispatch(
                into: sharedOutput, plane: plane, width: width, height: height,
                bytesPerRow: width * 16, device: gpu.device, queue: gpu.queue,
                spinIterations: 4_000_000, waitsCompletion: false)
        }
        let staleBits = sharedOutput.contents()
            .bindMemory(to: UInt16.self, capacity: width * height)
        let staleMap = Array(UnsafeBufferPointer(start: staleBits, count: width * height))
        XCTAssertFalse(staleMap.map(Float.init).allSatisfy { $0 == 0 },
            "the un-waited read of a stalled dispatch must observe the STALE (previous) map")

        // ③ The drained control on the SAME constant input is all zeros —
        // a constant field carries no modified-Laplacian energy. (The
        // stalled dispatch ② has meanwhile completed into the shared
        // buffer; the control re-runs it drained and reads the same face.)
        let drainedConstant = try withPlane(constantRGBA) { plane in
            try halfToFloat(FocusMeasure.qualityMap(
                plane: plane, width: width, height: height, bytesPerRow: width * 16,
                device: gpu.device, queue: gpu.queue))
        }
        XCTAssertTrue(drainedConstant.allSatisfy { $0 == 0 })
    }

    // MARK: - T1: the additive operator slot

    func testTenengradSlotThrowsNotImplemented() throws {
        let gpu = try GPU.make()
        let width = 32, height = 32
        let values = Self.texture(width, height, seed: 0x7E)
        let rgba = Self.rgbaPlane(gray: values, width: width, height: height)
        XCTAssertThrowsError(try withPlane(rgba) { plane in
            try FocusMeasure.qualityMap(
                plane: plane, width: width, height: height, bytesPerRow: width * 16,
                device: gpu.device, queue: gpu.queue, op: .tenengrad)
        }) { error in
            guard case AppError.notImplemented = error else {
                XCTFail("expected notImplemented, got \(error)")
                return
            }
        }
        // The slot is registered (CaseIterable) without second-operator math.
        XCTAssertEqual(FocusMeasure.Operator.allCases.count, 2)
    }
}
