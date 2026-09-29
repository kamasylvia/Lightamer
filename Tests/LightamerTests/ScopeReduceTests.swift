import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// ScopeReduceTests (Plan M2-3-3 T3) — the GPU scope kernels' parity contract:
//
//   1. HISTOGRAM: synthetic textures of known distribution (solid / bimodal
//      / gradient) → the GPU bin counts match the CPU reference PER BIN,
//      exactly (the counting semantics: the four channels' sums each equal
//      the pixel count — nothing drops).
//   2. WAVEFORM: the per-column luma-band counts match the CPU reference
//      (total count = pixels; spot columns exact).
//   3. DETERMINISM: the same input twice → byte-identical results (the
//      integer-atomic accumulation is order-independent).
//   4. EMPTY texture (0×N) → graceful empty result, no dispatch, no crash.
//   5. THE THROTTLE (AC#6, the state machine): ≤15 Hz while renders stream,
//      the idle settle runs the newest deferred frame, disabled = skip.
// ─────────────────────────────────────────────────────────────────────────────

final class ScopeReduceTests: XCTestCase {

    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    /// The CPU reference: EXACTLY the kernel's binning contract (Float32
    /// truncation + the Rec.709 luma sequence — ScopeReduce mirrors).
    private func referenceHistogram(
        pixels: [Float], width: Int, height: Int
    ) -> [[UInt32]] {
        var bins = [[UInt32]](
            repeating: [UInt32](repeating: 0, count: 256), count: 4)
        for i in 0..<(width * height) {
            let r = pixels[i * 4], g = pixels[i * 4 + 1], b = pixels[i * 4 + 2]
            let luma = ScopeReduce.luma(SIMD3<Float>(r, g, b))
            bins[0][ScopeReduce.bin(r)] += 1
            bins[1][ScopeReduce.bin(g)] += 1
            bins[2][ScopeReduce.bin(b)] += 1
            bins[3][ScopeReduce.bin(luma)] += 1
        }
        return bins
    }

    private func makeTexture(
        width: Int, height: Int, pixels: [Float]
    ) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        if !pixels.isEmpty {
            pixels.withUnsafeBytes {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: width * 16)
            }
        }
        return texture
    }

    /// The pixel plane for a per-pixel generator (gray = r == g == b).
    private func plane(
        width: Int, height: Int, _ generator: (Int, Int) -> Float
    ) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let gray = generator(x, y)
                let i = (y * width + x) * 4
                pixels[i] = gray
                pixels[i + 1] = gray
                pixels[i + 2] = gray
                pixels[i + 3] = 1
            }
        }
        return pixels
    }

    private func assertHistogram(
        _ gpu: ScopeReduce.Histogram, matches reference: [[UInt32]],
        pixels width: Int, height: Int, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(gpu.perChannel.count, 4, file: file, line: line)
        for channel in 0..<4 {
            XCTAssertEqual(
                gpu.perChannel[channel], reference[channel],
                "channel \(channel) per-bin mismatch",
                file: file, line: line)
            XCTAssertEqual(
                gpu.perChannel[channel].reduce(0, +), UInt32(width * height),
                "channel \(channel) drops pixels",
                file: file, line: line)
        }
    }

    // MARK: - Case 1: solid color

    func testHistogramSolidColorPerBinParity() async throws {
        let width = 64, height = 48
        // Gray 0.5 → bin 127 for every channel (127.5 truncates to 127;
        // the ±1-ulp luma sum cannot cross the boundary).
        let pixels = plane(width: width, height: height) { _, _ in 0.5 }
        let texture = makeTexture(width: width, height: height, pixels: pixels)
        let histogram = try await ScopeReduce.histogram(of: texture, metal: metal)
        assertHistogram(
            histogram, matches: referenceHistogram(
                pixels: pixels, width: width, height: height),
            pixels: width, height: height)
        XCTAssertEqual(histogram.perChannel[3][127], UInt32(width * height))
    }

    // MARK: - Case 2: bimodal

    func testHistogramBimodalPerBinParity() async throws {
        let width = 32, height = 32
        // Left half 0.25 (bin 63), right half 0.75 (bin 191) — both grays
        // land far from any bin boundary under the luma sum's ulp.
        var pixels = plane(width: width, height: height) { x, _ in 0.25 }
        for y in 0..<height {
            for x in (width / 2)..<width {
                let i = (y * width + x) * 4
                pixels[i] = 0.75
                pixels[i + 1] = 0.75
                pixels[i + 2] = 0.75
            }
        }
        let texture = makeTexture(width: width, height: height, pixels: pixels)
        let histogram = try await ScopeReduce.histogram(of: texture, metal: metal)
        assertHistogram(
            histogram, matches: referenceHistogram(
                pixels: pixels, width: width, height: height),
            pixels: width, height: height)
        XCTAssertEqual(
            histogram.perChannel[3][63] + histogram.perChannel[3][191],
            UInt32(width * height))
    }

    // MARK: - Case 3: gradient

    func testHistogramGradientPerBinParity() async throws {
        let width = 64, height = 64
        // A horizontal gray gradient — (x + 0.5)/width keeps every value's
        // v×255 fractional part far from a bin boundary (the test-parity
        // contract in ScopeReduceKernels.metal's header).
        let pixels = plane(width: width, height: height) { x, _ in
            (Float(x) + 0.5) / Float(width)
        }
        let texture = makeTexture(width: width, height: height, pixels: pixels)
        let histogram = try await ScopeReduce.histogram(of: texture, metal: metal)
        assertHistogram(
            histogram, matches: referenceHistogram(
                pixels: pixels, width: width, height: height),
            pixels: width, height: height)
    }

    // MARK: - Waveform parity + determinism

    func testWaveformColumnParityAndDeterminism() async throws {
        let width = 40, height = 32
        let pixels = plane(width: width, height: height) { x, y in
            (Float((x + y) % 16) + 0.5) / 16.0
        }
        let texture = makeTexture(width: width, height: height, pixels: pixels)

        let outWidth = min(width, ScopeReduce.maxWaveformWidth)
        let wave1 = try await ScopeReduce.waveform(of: texture, metal: metal)
        let wave2 = try await ScopeReduce.waveform(of: texture, metal: metal)
        XCTAssertEqual(wave1.width, outWidth)
        XCTAssertEqual(wave1.height, ScopeReduce.waveformHeight)

        // Determinism: two runs byte-identical.
        let bytes1 = readWaveform(wave1)
        let bytes2 = readWaveform(wave2)
        XCTAssertEqual(bytes1, bytes2, "same input must reduce identically")

        // CPU reference: column × band counts (the kernel's mapping).
        // The texture is row-major [band][column] (rows = the 256 luma
        // bands — the getBytes de-stride face).
        var reference = [UInt16](
            repeating: 0, count: outWidth * ScopeReduce.waveformHeight)
        for x in 0..<width {
            let colOut = min(x * outWidth / width, outWidth - 1)
            for y in 0..<height {
                let i = (y * width + x) * 4
                let luma = ScopeReduce.luma(
                    SIMD3<Float>(pixels[i], pixels[i + 1], pixels[i + 2]))
                let band = ScopeReduce.bin(luma)
                reference[band * outWidth + colOut] += 1
            }
        }
        XCTAssertEqual(bytes1, reference, {
            let mismatches = zip(bytes1, reference).enumerated().filter {
                $0.1.0 != $0.1.1
            }
            let gpuNonZero = bytes1.enumerated().filter { $0.1 != 0 }
                .prefix(8).map { "\($0.0):\($0.1)" }
            let refNonZero = reference.enumerated().filter { $0.1 != 0 }
                .prefix(8).map { "\($0.0):\($0.1)" }
            return "per-column band counts mismatch — \(mismatches.count) cells; "
                + "gpuNonZero[0..8]=\(gpuNonZero) refNonZero[0..8]=\(refNonZero)"
        }())
        // Total: nothing dropped.
        XCTAssertEqual(
            reference.reduce(0, +), UInt16(width * height),
            "the waveform counts must sum to the pixel count")
    }

    private func readWaveform(_ texture: any MTLTexture) -> [UInt16] {
        // getBytes requires a 256-byte row alignment — read padded, then
        // de-stride.
        let rowBytes = (texture.width * 2 + 255) / 256 * 256
        var padded = [UInt8](
            repeating: 0, count: rowBytes * texture.height)
        padded.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        var out = [UInt16](repeating: 0, count: texture.width * texture.height)
        for y in 0..<texture.height {
            padded.withUnsafeBytes { raw in
                let row = raw.baseAddress!.advanced(by: y * rowBytes)
                    .assumingMemoryBound(to: UInt16.self)
                for x in 0..<texture.width {
                    out[y * texture.width + x] = row[x]
                }
            }
        }
        return out
    }

    // MARK: - Degenerate sizes

    func testDegenerateTexturesDontCrash() async throws {
        // Metal forbids zero-sized descriptors (the validation assertion),
        // so the "empty" degenerate case = the 1×1 minimum. Both passes
        // handle it without crashing and count the single pixel exactly.
        let pixels: [Float] = [0.5, 0.5, 0.5, 1]
        let texture = makeTexture(width: 1, height: 1, pixels: pixels)
        let histogram = try await ScopeReduce.histogram(of: texture, metal: metal)
        for channel in 0..<4 {
            XCTAssertEqual(
                histogram.perChannel[channel].reduce(0, +), 1,
                "channel \(channel) counts the single pixel")
        }
        let waveform = try await ScopeReduce.waveform(of: texture, metal: metal)
        XCTAssertEqual(waveform.width, 1)
        XCTAssertEqual(waveform.height, ScopeReduce.waveformHeight)
        let counts = readWaveform(waveform)
        XCTAssertEqual(counts.reduce(0, +), 1)
    }

    // MARK: - AC#6: the throttle state machine

    func testThrottleStreamsAtMostMinIntervalAndSettlesIdle() {
        let minInterval = 1.0 / 15.0
        var throttle = ScopeThrottle()

        // First request runs immediately.
        XCTAssertEqual(
            throttle.request(isEnabled: true, now: 10.0), .run)
        // A burst of renders within the window defers (≤15 Hz).
        XCTAssertEqual(
            throttle.request(isEnabled: true, now: 10.0 + 0.01), .deferForSettle)
        XCTAssertEqual(
            throttle.request(isEnabled: true, now: 10.0 + 0.03), .deferForSettle)
        // The idle settle runs once the window has passed.
        XCTAssertEqual(
            throttle.settleTick(now: 10.0 + 0.03 + 0.25), .run)
        // Nothing pending afterwards.
        XCTAssertEqual(
            throttle.settleTick(now: 10.0 + 0.03 + 0.25 + 0.25), .skip)
        // A fresh render past the interval runs directly.
        XCTAssertEqual(
            throttle.request(isEnabled: true, now: 10.0 + 0.4), .run)
    }

    func testThrottleDisabledMeansZeroTap() {
        var throttle = ScopeThrottle()
        XCTAssertEqual(
            throttle.request(isEnabled: false, now: 5.0), .skip)
        // A deferred request drops when the panel unmounts.
        _ = throttle.request(isEnabled: true, now: 5.0)
        _ = throttle.request(isEnabled: true, now: 5.0 + 0.01)
        XCTAssertTrue(throttle.hasPending)
        XCTAssertEqual(
            throttle.request(isEnabled: false, now: 5.0 + 0.02), .skip)
        XCTAssertFalse(throttle.hasPending, "disable drops the pending frame")
        XCTAssertEqual(
            throttle.settleTick(now: 5.0 + 0.3), .skip,
            "no settle run after disable")
    }
}
