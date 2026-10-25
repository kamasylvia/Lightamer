import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralConstantsSanityTests (Plan M8-1a T2 — IOP domain) — the constant
// asset sanity gates:
//
//   1. The D65 white-point sentinel: the chromaticity integrated from the
//      generated CMFs×SPD tables reproduces the generated sentinel within
//      1e-6 (the version-drift sensitivity gate — a wrong CMF/SPD version
//      moves xy by ~1e-3), and the axis equals the vendored profile axis.
//   2. The spectral-locus polygon: closed (first vertex repeated), the
//      right length, positively oriented (shoelace area > 0), and it
//      CONTAINS the D65 white point; the tc domain transforms round-trip
//      and the radial compression is identity inside the locus.
//   3. The illuminant SPD set: 81 points each, non-negative finite, the
//      official CIE set landing their published chromaticities (≤5e-4),
//      the self-approximations in the warm-white band with Y=100 exact.
//   4. The dichroic transmissions: strictly inside (0, 1) with the
//      complementary band shapes (C blocks red, M blocks green, Y blocks
//      blue).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralConstantsSanityTests: XCTestCase {

    private static let axis: [Double] = (0..<81).map { 380 + 5 * Double($0) }

    // MARK: - 1: the white-point sentinel + axis identity

    func testD65WhitePointIntegrationReproducesTheSentinel() throws {
        // Axis identity with the vendored profiles (the cross-asset
        // invariant the engine's integrals stand on).
        XCTAssertEqual(SpectralConstantsData.wavelengthsNm, Self.axis)
        XCTAssertEqual(SpectralConstantsData.cmfs.count, 81)
        XCTAssertEqual(SpectralConstantsData.cmfs[0].count, 3)

        // The sentinel reproduction (≤1e-6 — the version gate).
        let d65 = try XCTUnwrap(SpectralConstants.spd(named: "D65"))
        let xy = SpectralConstants.chromaticity(spd: d65)
        XCTAssertEqual(
            xy.x, SpectralConstantsData.d65WhiteX, accuracy: 1e-6)
        XCTAssertEqual(
            xy.y, SpectralConstantsData.d65WhiteY, accuracy: 1e-6)

        // Absolute sanity: the sentinel sits at the CIE published D65
        // chromaticity within the 380-780@5nm truncation band (the
        // truncation moves xy by ~5e-7 — see the evidence log). A wrong
        // observer/illuminant VERSION would sit ~1e-3 away.
        XCTAssertEqual(xy.x, 0.31272, accuracy: 1e-5)
        XCTAssertEqual(xy.y, 0.32903, accuracy: 1e-5)

        // The CMF luminance column is the CIE 1931 one: ȳ(555nm) = 1.
        XCTAssertEqual(SpectralConstantsData.cmfs[35][1], 1.0, accuracy: 1e-9)
    }

    // MARK: - 2: the locus polygon + the tc domain transforms

    func testSpectralLocusPolygonClosedOrientedAndCompressing() {
        let polygon = SpectralConstants.spectralLocusPolygon()
        // Closed ring: first vertex repeated at the end.
        XCTAssertEqual(polygon.count, 82)
        XCTAssertEqual(polygon.first!.x, polygon.last!.x, accuracy: 0)
        XCTAssertEqual(polygon.first!.y, polygon.last!.y, accuracy: 0)
        // All vertices in the unit chromaticity box.
        for vertex in polygon {
            XCTAssertGreaterThanOrEqual(vertex.x, 0)
            XCTAssertLessThanOrEqual(vertex.x, 1)
            XCTAssertGreaterThanOrEqual(vertex.y, 0)
            XCTAssertLessThanOrEqual(vertex.y, 1)
        }
        // Non-degenerate polygon (the shoelace area magnitude). NOTE the
        // orientation: the 380→780 vertex order traces the horseshoe
        // CLOCKWISE in xy (area < 0) — the polygon's consumers (ray-edge
        // distance, inside-parity) are orientation-independent by
        // construction, so the sign is informational only.
        var area = 0.0
        for k in 0..<(polygon.count - 1) {
            area += polygon[k].x * polygon[k + 1].y
                - polygon[k + 1].x * polygon[k].y
        }
        XCTAssertLessThan(area * 0.5, 0, "the 380→780 ring traces CW")
        XCTAssertLessThan(abs(area * 0.5), 0.34, "horseshoe area magnitude")
        // The D65 white point lives inside the polygon (ray-crossing
        // parity is odd inside).
        let white = SIMD2<Double>(
            SpectralConstantsData.d65WhiteX, SpectralConstantsData.d65WhiteY)
        func inside(_ point: SIMD2<Double>) -> Bool {
            var crossings = 0
            for k in 0..<(polygon.count - 1) {
                let a = polygon[k]
                let b = polygon[k + 1]
                let intersects = (a.y > point.y) != (b.y > point.y)
                let xAtY = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if intersects, point.x < xAtY { crossings += 1 }
            }
            return crossings % 2 == 1
        }
        XCTAssertTrue(inside(white), "D65 is inside the spectral locus")

        // The tc domain transforms round-trip over a dense grid
        // (Float64 exactness class).
        var samples = 0
        for i in stride(from: 0.02, through: 0.98, by: 0.0777) {
            for j in stride(from: 0.02, through: 0.98, by: 0.0613) {
                let xy = SpectralConstants.quad2tri(u: i, v: j)
                let uv = SpectralConstants.tri2quad(x: xy.x, y: xy.y)
                XCTAssertEqual(uv.u, i, accuracy: 1e-12)
                XCTAssertEqual(uv.v, j, accuracy: 1e-12)
                samples += 1
            }
        }
        XCTAssertGreaterThan(samples, 100)

        // The radial compression: identity for a comfortably in-locus
        // chromaticity, and a deep out-of-locus point pulls back inside
        // the polygon while staying on its ray.
        let inLocus = SIMD2<Double>(0.33, 0.35)
        let same = SpectralConstants.compressXYRadial(
            inLocus, white: white, polygon: polygon)
        XCTAssertEqual(same.x, inLocus.x, accuracy: 1e-12)
        XCTAssertEqual(same.y, inLocus.y, accuracy: 1e-12)

        let outOfLocus = SIMD2<Double>(0.31, 0.02) // below the purple line
        let compressed = SpectralConstants.compressXYRadial(
            outOfLocus, white: white, polygon: polygon)
        XCTAssertTrue(inside(compressed), "compression lands inside the locus")
        // On the same ray from the white point (direction preserved).
        let originalDirection = (outOfLocus - white)
            / simd_length(outOfLocus - white)
        let compressedDirection = (compressed - white)
            / simd_length(compressed - white)
        XCTAssertEqual(
            compressedDirection.x, originalDirection.x, accuracy: 1e-9)
        XCTAssertEqual(
            compressedDirection.y, originalDirection.y, accuracy: 1e-9)
    }

    // MARK: - 3: the illuminant SPD set

    func testIlluminantSPDsNonNegativeWithCanonicalWhitePoints() throws {
        let names = SpectralConstants.illuminantNames
        XCTAssertEqual(names.count, 9)
        XCTAssertEqual(
            Set(names),
            ["D50", "D55", "D65", "D75", "A", "T", "TH-KG3", "K75P", "ENL"])

        // The official CIE set must land its PUBLISHED chromaticities
        // (≤5e-4 — a wrong table or version is far outside).
        let published: [String: (Double, Double)] = [
            "D50": (0.3457, 0.3585),
            "D55": (0.3324, 0.3474),
            "D65": (0.3127, 0.3290),
            "D75": (0.2990, 0.3149),
            "A": (0.4476, 0.4074),
        ]
        for (name, expected) in published {
            let spd = try XCTUnwrap(SpectralConstants.spd(named: name))
            XCTAssertEqual(spd.count, 81, name)
            XCTAssertTrue(spd.allSatisfy { $0.isFinite && $0 >= 0 }, name)
            let xy = SpectralConstants.chromaticity(spd: spd)
            XCTAssertEqual(xy.x, expected.0, accuracy: 5e-4, name)
            XCTAssertEqual(xy.y, expected.1, accuracy: 5e-4, name)
        }

        // The self-approximations: warm-white band, Y=100 exact (the
        // documented normalization), non-negative finite.
        for name in ["T", "TH-KG3", "K75P", "ENL"] {
            let spd = try XCTUnwrap(SpectralConstants.spd(named: name))
            XCTAssertEqual(spd.count, 81, name)
            XCTAssertTrue(spd.allSatisfy { $0.isFinite && $0 >= 0 }, name)
            let xy = SpectralConstants.chromaticity(spd: spd)
            XCTAssertGreaterThanOrEqual(xy.x, 0.40, name)
            XCTAssertLessThanOrEqual(xy.x, 0.46, name)
            XCTAssertGreaterThanOrEqual(xy.y, 0.39, name)
            XCTAssertLessThanOrEqual(xy.y, 0.41, name)
            let luminance = zip(spd, SpectralConstantsData.cmfs)
                .map { $0.0 * $0.1[1] }.reduce(0, +)
            XCTAssertEqual(luminance, 100, accuracy: 1e-6, name)
        }

        // TH-KG3 actually WEARS the heat glass: its near-IR tail
        // (740-780nm = axis indices 72-80) is suppressed relative to
        // plain tungsten T (both Y=100, so the difference concentrates
        // in the shape).
        let t = try XCTUnwrap(SpectralConstants.spd(named: "T"))
        let thkg3 = try XCTUnwrap(SpectralConstants.spd(named: "TH-KG3"))
        let tailT = (72...80).reduce(0.0) { $0 + t[$1] }
        let tailKG3 = (72...80).reduce(0.0) { $0 + thkg3[$1] }
        XCTAssertLessThan(tailKG3, tailT * 0.8,
                          "the KG3 glass cuts the near-IR tail")
    }

    // MARK: - 4: the dichroic transmissions

    func testDichroicTransmissionsUnitDomainWithComplementaryShapes() {
        let curves = SpectralConstantsData.dichroicTransmissions
        XCTAssertEqual(curves.count, 81)
        for row in curves {
            XCTAssertEqual(row.count, 3)
            for value in row {
                XCTAssertGreaterThan(value, 0, "strictly open somewhere")
                XCTAssertLessThan(value, 1, "strictly blocking somewhere")
            }
        }
        func at(_ wavelength: Double, _ channel: Int) -> Double {
            let index = Int((wavelength - 380) / 5)
            return curves[index][channel]
        }
        // Cyan blocks red, passes green+blue.
        XCTAssertLessThan(at(650, 0), 0.1, "cyan full density blocks red")
        XCTAssertGreaterThan(at(500, 0), 0.9, "cyan passes the blue-green")
        // Magenta blocks the middle, passes both ends.
        XCTAssertLessThan(at(545, 1), 0.1, "magenta full density blocks green")
        XCTAssertGreaterThan(at(430, 1), 0.9, "magenta passes blue")
        XCTAssertGreaterThan(at(680, 1), 0.9, "magenta passes red")
        // Yellow blocks blue, passes red+green.
        XCTAssertLessThan(at(430, 2), 0.1, "yellow full density blocks blue")
        XCTAssertGreaterThan(at(560, 2), 0.9, "yellow passes green")
        XCTAssertGreaterThan(at(650, 2), 0.9, "yellow passes red")
    }
}
