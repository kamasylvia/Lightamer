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

    // MARK: - T2: the quality-weighted pyramid fusion

    /// The P5 PASS shape: a synthetic focus rail (A sharp on top, B sharp
    /// on the bottom — the defocus proxy everywhere else) fuses to the
    /// known sharp composite with a two-way MAE at the ≈0.004 order.
    func testClearRegionAttributionMAE() throws {
        let width = 256, height = 192
        let sharp = Self.texture(width, height, seed: 0xABCD)
        let blurred = Self.boxBlur(sharp, width: width, height: height, radius: 4)
        let half = height / 2

        func rail(sharpTop: Bool) -> (rgb: [Float], quality: [Float]) {
            var rgb = [Float](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                let rowSharp = (y < half) == sharpTop
                for x in 0..<width {
                    let value = rowSharp ? sharp[y * width + x] : blurred[y * width + x]
                    let base = (y * width + x) * 4
                    rgb[base] = value; rgb[base + 1] = value; rgb[base + 2] = value
                    rgb[base + 3] = 1
                }
            }
            // The quality strips are what the SML leg produces — emulate
            // with the CPU mirror of the rail (sharp rows carry energy).
            let map = FocusMeasure.qualityMapCPU(
                UnsafeRawBufferPointer(rgb.withUnsafeBufferPointer { $0 }),
                width: width, height: height, bytesPerRow: width * 16)
            return (rgb, map)
        }

        let sourceA = rail(sharpTop: true)
        let sourceB = rail(sharpTop: false)
        let fused = FocusStackMerge.fuseStrip(
            width: width, height: height, sources: 2) { index in
            index == 0 ? sourceA : sourceB
        }
        // The ideal composite picks the sharp source per row.
        var total = 0.0 as Double
        var count = 0.0 as Double
        for y in 0..<height {
            let rowSharp = y < half ? sourceA.rgb : sourceB.rgb
            for x in 0..<width {
                let ideal = rowSharp[(y * width + x) * 4]
                for channel in 0..<3 {
                    let delta = fused[(y * width + x) * 3 + channel] - ideal
                    total += Double(abs(delta))
                    count += 1
                }
            }
        }
        let mae = total / count
        XCTAssertLessThan(mae, 0.01,
            "clear-region attribution MAE \(mae) above the P5 order (≈0.004)")
    }

    /// The Burt-Adelson pair's consistency: TWO IDENTICAL sources with
    /// uniform quality must fuse back to the source (den = 2·w, num =
    /// 2·w·L, reconstruction telescopes exactly).
    func testFuseStripIdenticalSourcesReconstructExactly() {
        let width = 130, height = 96 // odd width exercises the expand path
        let values = Self.texture(width, height, seed: 0x1234)
        var rgb = [Float](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            rgb[index * 4] = values[index]
            rgb[index * 4 + 1] = values[index] * 0.8
            rgb[index * 4 + 2] = values[index] * 0.6
            rgb[index * 4 + 3] = 1
        }
        let quality = [Float](repeating: 1, count: width * height)
        let fused = FocusStackMerge.fuseStrip(
            width: width, height: height, sources: 2) { _ in (rgb, quality) }
        var worst: Float = 0
        for index in 0..<(width * height) {
            for (channel, scale) in [(0, Float(1)), (1, Float(0.8)), (2, Float(0.6))] {
                worst = max(worst, abs(
                    fused[index * 3 + channel] - values[index] * scale))
            }
        }
        XCTAssertLessThan(worst, 1e-3,
            "identical-source fusion must reconstruct the source, worst \(worst)")
    }

    /// Weightless regions (NaN-shifted-out pixels arrive at quality 0 with
    /// every source) fuse to BLACK — the ε guard, not NaN.
    func testFuseStripWeightlessRegionGoesBlack() {
        let width = 64, height = 48
        let values = Self.texture(width, height, seed: 0x999)
        var rgb = [Float](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            rgb[index * 4] = values[index]
            rgb[index * 4 + 1] = values[index]
            rgb[index * 4 + 2] = values[index]
            rgb[index * 4 + 3] = 1
        }
        // Every source weightless EVERYWHERE → the ε guard blends black at
        // EVERY level, so the reconstruction is exactly black (a local hole
        // only dims — the coarse scales legitimately flood it, which is
        // enfuse's own soft-fusion semantics, D-08-3-T2-3).
        let zeroQuality = [Float](repeating: 0, count: width * height)
        let fused = FocusStackMerge.fuseStrip(
            width: width, height: height, sources: 2) { _ in (rgb, zeroQuality) }
        let center = (24 * width + 32) * 3
        for channel in 0..<3 {
            XCTAssertLessThan(abs(fused[center + channel]), 1e-4,
                "weightless fusion must be black")
            XCTAssertFalse(fused[center + channel].isNaN)
        }
        // With REAL quality the fusion reconstructs the source.
        let realQuality = [Float](repeating: 1, count: width * height)
        let fusedReal = FocusStackMerge.fuseStrip(
            width: width, height: height, sources: 2) { _ in (rgb, realQuality) }
        let corner = (4 * width + 4) * 3
        XCTAssertEqual(fusedReal[corner], values[4 * width + 4], accuracy: 1e-3)
    }

    /// The 5×5 box soften: a uniform field is a fixed point; a center
    /// impulse spreads exactly over the ±2 window.
    func testSoftenQualityBoxShape() {
        let width = 32, height = 32
        let uniform = FocusStackMerge.softenQuality(
            [Float](repeating: 0.5, count: width * height), width: width, height: height)
        XCTAssertEqual(uniform.max()!, 0.5, accuracy: 1e-6)
        XCTAssertEqual(uniform.min()!, 0.5, accuracy: 1e-6)

        var impulse = [Float](repeating: 0, count: width * height)
        impulse[16 * width + 16] = 25 // box area 25 → softened peak = 1
        let softened = FocusStackMerge.softenQuality(impulse, width: width, height: height)
        XCTAssertEqual(softened[16 * width + 16], 1.0, accuracy: 1e-5)
        // The separable box spreads the impulse UNIFORMLY over the 5×5
        // window (mean of mean — the whole window reads 1.0); 3 away is 0.
        XCTAssertEqual(softened[14 * width + 16], 1.0, accuracy: 1e-5)
        XCTAssertEqual(softened[14 * width + 14], 1.0, accuracy: 1e-5)
        XCTAssertEqual(softened[13 * width + 16], 0, accuracy: 1e-6)
    }

    /// The band-streamed footprint: the working-set formula is O(band) —
    /// the N=8 focus working set at 100 MP scale is the band strip (NOT
    /// N×full-frame residency, which would be ~80× larger).
    func testFocusFusionBandWorkingSetIsConstant() {
        let width = 11656, bandHeight = 256, halo = 32, sources = 8
        let band = FocusStackMerge.bandWorkingSetBytes(
            width: width, bandHeight: bandHeight, halo: halo, sources: sources)
        let fullResidency = sources * width * 8742 * 4 * MemoryLayout<Float>.size
        // The formula's strip term (the accumulator term is bounded by the
        // strip rows too — the whole working set scales with band+2·halo,
        // never with the frame height).
        let stripTerm = sources * (bandHeight + 2 * halo) * width * 5
            * MemoryLayout<Float>.size
        XCTAssertGreaterThan(band, stripTerm)
        XCTAssertLessThan(band, stripTerm * 3, "accumulator term must stay strip-bounded")
        // O(band) vs O(height): the band working set must stay under ONE
        // full frame's residency (a single decoded plane) — strictly
        // sub-frame, and 10×+ under the forbidden N×full-frame residency.
        XCTAssertLessThan(Double(band), Double(fullResidency / sources),
            "band working set \(band) vs one frame \(fullResidency / sources)")
    }

    /// The NCC scale-drift self-check: an upscaled-cropped duplicate
    /// decorrelates (NCC < 0.9) while the aligned pair correlates (≈1).
    func testNCCDetectsScaleDrift() {
        let width = 192, height = 144
        let ref = Self.texture(width, height, seed: 0xC0DE)
        func ratioLuma(_ gray: [Float], _ w: Int, _ h: Int) -> AlignmentFrame.RatioLuma {
            AlignmentFrame.RatioLuma(width: w, height: h, pixels: gray)
        }
        // Scale 1.05×: crop the center of the 1.05× stretched copy.
        let scale = 1.05
        var drifted = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sx = Int(Double(x) / scale)
                let sy = Int(Double(y) / scale)
                drifted[y * width + x] = ref[
                    min(sy, height - 1) * width + min(sx, width - 1)]
            }
        }
        let nccAligned = FocusStackMerge.normalizedCrossCorrelation(
            reference: ratioLuma(ref, width, height),
            candidate: ratioLuma(ref, width, height), dx: 0, dy: 0)
        XCTAssertGreaterThan(nccAligned, 0.99)
        let nccDrift = FocusStackMerge.normalizedCrossCorrelation(
            reference: ratioLuma(ref, width, height),
            candidate: ratioLuma(drifted, width, height), dx: 0, dy: 0)
        XCTAssertLessThan(nccDrift, FocusStackMerge.nccWarnThreshold,
            "a 5% scale drift must warn (NCC \(nccDrift))")
    }
}
