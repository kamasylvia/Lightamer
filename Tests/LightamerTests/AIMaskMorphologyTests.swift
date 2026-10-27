@testable import LightamerCore
import XCTest

/// AIMaskMorphologyTests (M9-1 T2, D-M9A-9) — the Expand operator's five
/// golden faces:
/// ① the octagonal-distance ground truth: a single-pixel source dilated n
///    steps equals the kernel-cadence BFS reachability set (an
///    INDEPENDENT definition-level truth, pitted against both the vImage
///    leg and the host reference — near-border sources included);
/// ② random planes: vImage vs host, byte-for-byte, multiple sizes (odd
///    and even extents) and both signs;
/// ③ the erode/dilate duality: erode == invert∘dilate∘invert over the
///    same clamp-replicate policy (the boundary-contract pin);
/// ④ |px| == 0 identity (byte-identical, the neutral bake default);
/// ⑤ the monotone-quantization commutation (the R8 argument): max/min
///    commutes with any monotone map — expanding the quantized plane
///    equals quantizing the expanded plane, value-for-value.
final class AIMaskMorphologyTests: XCTestCase {

    /// The definition-level BFS truth: pixels reachable from the seed set
    /// through the step-cadence windows under clamp-replicate reads
    /// (`reached_k = {x : some W_k offset of x clamps into
    /// reached_{k-1}}` — the exact induction of the composed max-windows).
    private static func bfsReachable(
        width: Int, height: Int, seeds: Set<Int>, steps: Int
    ) -> Set<Int> {
        var reached = seeds
        for step in 1...steps {
            var next = Set<Int>()
            for index in 0..<(width * height) {
                let x = index % width, y = index / width
                for (dx, dy) in AIMaskMorphology.offsets(forStep: step) {
                    let sx = min(max(x + dx, 0), width - 1)
                    let sy = min(max(y + dy, 0), height - 1)
                    if reached.contains(sy * width + sx) {
                        next.insert(index)
                        break
                    }
                }
            }
            reached.formUnion(next)
        }
        return reached
    }

    private func plane(
        width: Int, height: Int, ones: Set<Int>
    ) -> AIMaskPlane {
        AIMaskPlane(
            width: width, height: height,
            floats: (0..<(width * height)).map { ones.contains($0) ? 1 : 0 })
    }

    private func positiveSet(_ plane: AIMaskPlane) -> Set<Int> {
        Set((0..<plane.floats.count).filter { plane.floats[$0] > 0 })
    }

    private func deterministicRandomPlane(
        width: Int, height: Int, seed: UInt64
    ) -> AIMaskPlane {
        // xorshift64* — a small deterministic generator (test-only).
        var state = seed
        func next() -> Float {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return Float((state &* 2685821657736338717) >> 40) / Float(1 << 24)
        }
        return AIMaskPlane(
            width: width, height: height,
            floats: (0..<(width * height)).map { _ in next() })
    }

    // MARK: ① octagonal ground truth

    /// Center sources and CORNER sources (the clamp-replicate border
    /// face), n = 1..4: the vImage leg AND the host reference both equal
    /// the BFS set exactly.
    func testSinglePixelDilationMatchesCadenceGroundTruth() {
        let cases: [(width: Int, height: Int, seed: Int)] = [
            (13, 9, 4 * 13 + 4),   // center, odd extents
            (16, 16, 7 * 16 + 7),  // center, even extents
            (7, 7, 0),             // the CORNER source (border clamp face)
            (11, 9, 5),            // on the top edge
        ]
        for testCase in cases {
            let seeds: Set<Int> = [testCase.seed]
            for steps in 1...4 {
                let truth = Self.bfsReachable(
                    width: testCase.width, height: testCase.height,
                    seeds: seeds, steps: steps)
                let source = plane(
                    width: testCase.width, height: testCase.height, ones: seeds)
                let vImage = AIMaskMorphology.expand(plane: source, px: steps)
                let host = AIMaskMorphology.expandHost(plane: source, px: steps)
                XCTAssertEqual(
                    positiveSet(vImage), truth,
                    "vImage n=\(steps) w=\(testCase.width) h=\(testCase.height) seed=\(testCase.seed)")
                XCTAssertEqual(
                    positiveSet(host), truth,
                    "host n=\(steps) w=\(testCase.width) h=\(testCase.height) seed=\(testCase.seed)")
                XCTAssertEqual(vImage.floats, host.floats, "vImage == host, n=\(steps)")
            }
        }
    }

    // MARK: ② vImage vs host over random planes

    /// Multiple odd/even extents, dilate and erode, radii 1..4 — the
    /// production leg equals the host reference byte-for-byte.
    func testVImageMatchesHostOnRandomPlanes() {
        let sizes = [(7, 5), (16, 16), (13, 9), (32, 8), (9, 31)]
        for (index, size) in sizes.enumerated() {
            let source = deterministicRandomPlane(
                width: size.0, height: size.1, seed: 0x9E37_79B9_7F4A_7C15 &+ UInt64(index))
            for px in [-4, -3, -2, -1, 1, 2, 3, 4] {
                let vImage = AIMaskMorphology.expand(plane: source, px: px)
                let host = AIMaskMorphology.expandHost(plane: source, px: px)
                // The vImage leg is a BIAS-kernel grayscale morphology:
                // participating cells carry ±1e-9 (the shape trick), so
                // the exact-agreement domain is the QUANTIZED bake grid
                // (v·65535 — one uint16 LSB dwarfs the 50-step bias
                // accumulation; the R8 argument), with a float epsilon
                // floor for the raw plane.
                for (v, h) in zip(vImage.floats, host.floats) {
                    XCTAssertEqual(Double(v), Double(h), accuracy: 1e-6,
                                   "vImage == host (float) px=\(px) size=\(size)")
                    XCTAssertEqual(
                        UInt32((min(max(v, 0), 1) * 65535).rounded()),
                        UInt32((min(max(h, 0), 1) * 65535).rounded()),
                        "vImage == host (uint16 bake grid) px=\(px) size=\(size)")
                }
                // The identity dimension stays put.
                XCTAssertEqual(vImage.width, source.width)
                XCTAssertEqual(vImage.height, source.height)
            }
        }
    }

    // MARK: ③ the erode/dilate duality

    /// erode(p) == 1 − dilate(1 − p) over the SAME clamp-replicate
    /// policy (both directions, radii 1..3) — the boundary-contract pin:
    /// an interior hole WIDENS under erode exactly as a solid island
    /// widens under dilate.
    func testErodeDilateDualityUnderClampReplicate() {
        let source = deterministicRandomPlane(
            width: 17, height: 11, seed: 0xD1B5_4A32_D192_ED2)
        func invert(_ plane: AIMaskPlane) -> AIMaskPlane {
            AIMaskPlane(
                width: plane.width, height: plane.height,
                floats: plane.floats.map { 1 - $0 })
        }
        for px in [-1, -2, -3] {
            let eroded = AIMaskMorphology.expand(plane: source, px: px)
            let dual = invert(AIMaskMorphology.expand(
                plane: invert(source), px: -px))
            for (a, b) in zip(eroded.floats, dual.floats) {
                XCTAssertEqual(Double(a), Double(b), accuracy: 1e-6,
                               "erode(p) == 1−dilate(1−p) at px=\(px)")
            }
        }
    }

    // MARK: ④ the neutral default

    /// px == 0 returns the plane byte-identical (the bake seam's default
    /// path — zero pixels differ, the pre-M9-1 behavior).
    func testZeroRadiusIsIdentity() {
        let source = deterministicRandomPlane(
            width: 10, height: 6, seed: 42)
        let expanded = AIMaskMorphology.expand(plane: source, px: 0)
        XCTAssertEqual(expanded.floats, source.floats)
        XCTAssertEqual(expanded.width, source.width)
        XCTAssertEqual(expanded.height, source.height)
        let hostExpanded = AIMaskMorphology.expandHost(plane: source, px: 0)
        XCTAssertEqual(hostExpanded.floats, source.floats)
    }

    // MARK: ⑤ the monotone-quantization commutation (R8)

    /// max/min commutes with ANY monotone map: expanding the quantized
    /// plane equals quantizing the expanded plane — the R8 value-domain
    /// argument (morphology never mixes values; the uint16 bake grid is a
    /// monotone image of the float plane).
    func testQuantizationMonotoneCommutation() {
        // A uint16-grid-valued plane (exactly representable bake values).
        let grid: [UInt16] = [0, 16384, 32768, 49152, 65535]
        var floats = [Float](repeating: 0, count: 11 * 7)
        var state: UInt64 = 7
        for i in 0..<floats.count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            floats[i] = Float(grid[Int((state >> 33) % UInt64(grid.count))]) / 65535
        }
        let source = AIMaskPlane(width: 11, height: 7, floats: floats)
        func monotone(_ x: Float) -> Float { x * 0.5 + 0.1 }

        func quantized(_ floats: [Float]) -> [UInt32] {
            floats.map { UInt32((Double(min(max($0, 0), 1)) * 65535).rounded()) }
        }
        for px in [-3, -1, 1, 2, 3] {
            let direct = AIMaskMorphology.expand(plane: source, px: px)
            let mapped = AIMaskMorphology.expand(
                plane: AIMaskPlane(
                    width: 11, height: 7, floats: source.floats.map(monotone)),
                px: px)
            // The bias kernel's ±1e-9 accumulates below one uint16 LSB —
            // the commutation is EXACT on the bake grid (the R8 argument).
            XCTAssertEqual(
                quantized(direct.floats.map(monotone)), quantized(mapped.floats),
                "q∘expand == expand∘q at px=\(px) (monotone commutation, bake grid)")

            // The QUANTIZED value domain stays CLOSED under the operation
            // (morphology selects, it never mixes — R8's exactness).
            let allowed = Set(quantized(source.floats))
            for value in quantized(direct.floats) {
                XCTAssertTrue(allowed.contains(value), "closed value domain (bake grid)")
            }
        }
    }
}
