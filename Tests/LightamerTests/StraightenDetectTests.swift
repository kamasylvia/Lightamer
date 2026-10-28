@testable import LightamerCore
import XCTest

/// StraightenDetectTests (Plan M9-3-T3) — the auto-straighten detector's
/// golden faces (upstream `tests_geometry.rs` reference parameters).
///
/// HAND VALUES:
/// - `segment_detector_finds_known_lines` face: three synthetic known-angle
///   dark lines on a light ground; every true line must be matched by a
///   detected segment within 0.7° of direction and ≥0.6× of its true
///   length (centred-normalized units).
/// - the guard gates (`auto_straighten_needs_more_than_one_line` +
///   `auto_straighten_leaves_steep_lines_alone` faces): ONE line answers
///   nothing (MIN_LINES=3); a horizon WITH parallel plank texture reads
///   −4°±0.5; a 20° family reads None (MAX_DEGREES=10); an 8° family reads
///   −8°±0.5; and the SIGN gate — a right-DROOPING horizon reads NEGATIVE
///   (−6°±0.5), the R-2 user-visible direction lock.
/// - determinism: the detector is a deterministic stack region-grow — a
///   second run is bitwise identical.
final class StraightenDetectTests: XCTestCase {

    /// A synthetic scene: light ground (0.15) + bright lines (1.0, ~2 px
    /// wide) at (angle° relative to +x, centre, length) in PIXEL coords
    /// (y-down — the image convention the detector consumes).
    private static func scene(
        width: Int, height: Int,
        lines: [(angle: Double, cx: Double, cy: Double, length: Double)]
    ) -> [Float] {
        var plane = [Float](repeating: 0.15, count: width * height)
        for line in lines {
            let a = line.angle * Double.pi / 180
            let ux = cos(a), uy = sin(a)
            let steps = Int(line.length * 2)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let px = line.cx + (t - 0.5) * line.length * ux
                let py = line.cy + (t - 0.5) * line.length * uy
                for dx in -1...1 {
                    for dy in -1...1 {
                        let x = Int(px.rounded()) + dx
                        let y = Int(py.rounded()) + dy
                        guard x >= 0, y >= 0, x < width, y < height else { continue }
                        plane[y * width + x] = 1.0
                    }
                }
            }
        }
        return plane
    }

    /// The direction of a segment relative to +x, folded to [0, 180).
    private static func directionDegrees(_ s: UprightMath.Segment) -> Double {
        var a = atan2(s.b.y - s.a.y, s.b.x - s.a.x) * 180 / Double.pi
        if a < 0 { a += 180 }
        if a >= 180 { a -= 180 }
        return a
    }

    // MARK: - the known-lines golden face

    func testSegmentDetectorFindsKnownLines() {
        let width = 400, height = 300
        // three known lines: horizontal (0°), 30°, near-vertical (90°)
        let trueLines: [(angle: Double, cx: Double, cy: Double, length: Double)] = [
            (0, 200, 60, 260),
            (30, 200, 150, 240),
            (90, 120, 150, 180),
        ]
        let plane = Self.scene(width: width, height: height, lines: trueLines)
        let segs = StraightenDetect.detectSegments(luminance: plane, width: width, height: height)
        XCTAssertFalse(segs.isEmpty, "the detector must find the drawn lines")
        // determinism: the deterministic region grow is bitwise identical
        let segs2 = StraightenDetect.detectSegments(luminance: plane, width: width, height: height)
        XCTAssertEqual(segs, segs2, "detection must be bitwise deterministic")

        // every true line matches SOME detected segment: direction <0.7°,
        // length ≥0.6× truth (greedy nearest-direction matching)
        for line in trueLines {
            let candidates = segs.map { (s: $0, d: Self.angularDistance(Self.directionDegrees($0), line.angle)) }
            guard let best = candidates.min(by: { $0.d < $1.d }) else {
                XCTFail("no segment for line \(line.angle)°")
                continue
            }
            XCTAssertLessThan(best.d, 0.7, "line \(line.angle)°: direction error \(best.d)°")
            let trueNormLength = line.length / Double(max(width, height)) * 2
            XCTAssertGreaterThan(best.s.length, 0.6 * trueNormLength,
                "line \(line.angle)°: recovered length \(best.s.length) vs truth \(trueNormLength)")
        }
    }

    /// Angular distance folded to [0, 90] (a segment's direction is mod π).
    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b).truncatingRemainder(dividingBy: 180)
        if d > 90 { d = 180 - d }
        return d
    }

    // MARK: - the guard gates

    /// A horizon family: a main line at `angle` + 8 plank-texture lines at
    /// angle ±0.3° (parallel texture — the wooden-planks case upstream
    /// calibrated against).
    private static func plankScene(
        width: Int, height: Int, angle: Double
    ) -> [Float] {
        var lines: [(angle: Double, cx: Double, cy: Double, length: Double)] = [
            (angle, Double(width) / 2, Double(height) / 2, Double(width) * 0.7)
        ]
        for i in 0..<8 {
            let jitter = (Double(i % 2) * 2 - 1) * 0.3
            lines.append((angle + jitter, Double(width) / 2, 40 + Double(i) * 28, Double(width) * 0.6))
        }
        return scene(width: width, height: height, lines: lines)
    }

    func testStraightenGuardGates() {
        let width = 400, height = 300

        // ONE line answers nothing (MIN_LINES = 3)
        let single = Self.scene(width: width, height: height, lines: [
            (4, 200, 150, 260)])
        XCTAssertNil(
            StraightenDetect.levelDegrees(luminance: single, width: width, height: height),
            "a single line must not answer")

        // horizon WITH parallel plank texture reads −4°±0.5
        let planks4 = Self.plankScene(width: width, height: height, angle: 4)
        let answered4 = StraightenDetect.levelDegrees(luminance: planks4, width: width, height: height)
        XCTAssertNotNil(answered4)
        XCTAssertEqual(answered4 ?? 999, -4.0, accuracy: 0.5, "the 4° plank family reads −4°±0.5")

        // a 20° family stays untouched (MAX_DEGREES = 10)
        let planks20 = Self.plankScene(width: width, height: height, angle: 20)
        XCTAssertNil(
            StraightenDetect.levelDegrees(luminance: planks20, width: width, height: height),
            "the 20° family must read None")

        // an 8° family reads −8°±0.5
        let planks8 = Self.plankScene(width: width, height: height, angle: 8)
        let answered8 = StraightenDetect.levelDegrees(luminance: planks8, width: width, height: height)
        XCTAssertNotNil(answered8)
        XCTAssertEqual(answered8 ?? 999, -8.0, accuracy: 0.5, "the 8° family reads −8°±0.5")

        // the SIGN gate: a right-DROOPING 6° horizon (y grows with x in
        // image coordinates) reads NEGATIVE −6°±0.5 (the R-2 lock)
        let planks6 = Self.plankScene(width: width, height: height, angle: 6)
        let answered6 = StraightenDetect.levelDegrees(luminance: planks6, width: width, height: height)
        XCTAssertNotNil(answered6)
        XCTAssertEqual(answered6 ?? 999, -6.0, accuracy: 0.5, "right-drooping horizon reads −6°±0.5")
    }
}
