import LightamerCore
import LightamerIOP
import XCTest

// ColorZonesCommitTests (Plan 05-04-T2) — V2 verdict pins + LUT build
// gates + commit uniformity + CPU reference smoke. The full GPU parity
// (dual gate + hue sweep) lands in T3's ColorZonesParityTests.
final class ColorZonesCommitTests: XCTestCase {

    // MARK: - V2 verdict (a): cubic / catmull delegate to V1 identically

    /// V2 CUBIC nonperiodic == V1 natural spline on asymmetric nodes
    /// (verdict: identical by construction — delegation, not duplication).
    func testCubicV2MatchesV1() {
        let xs = [0.0, 0.2, 0.55, 0.8, 1.0]
        let ys = [0.1, 0.35, 0.3, 0.7, 0.9]
        let v1 = ToneCurveLUT.cubicSplineSecondDerivatives(x: xs, y: ys)
        let v2 = ColorZonesLUT.cubicTangents(x: xs, y: ys)
        XCTAssertNotNil(v1)
        XCTAssertNotNil(v2)
        // Re-derive V1 tangents from V1 ypp through the same ypp→dy
        // conversion and compare against V2's direct output.
        for xk in stride(from: 0.0, through: 1.0, by: 0.05) {
            let a = ToneCurveLUT.splineVal(x: xs, y: ys, ypp: v1!, tval: xk)
            let b = ColorZonesLUT.evaluateNonperiodic(x: xs, y: ys, tangents: v2!, xval: xk)
            XCTAssertEqual(a, b, accuracy: 1e-12, "cubic V2 vs V1 at \(xk)")
        }
    }

    /// V2 CATMULL nonperiodic == V1 central differences (same delegation).
    func testCatmullV2MatchesV1() {
        let xs = [0.0, 0.3, 0.6, 1.0]
        let ys = [0.0, 0.5, 0.4, 1.0]
        let v1 = ToneCurveLUT.catmullRomTangents(x: xs, y: ys)
        let v2 = ColorZonesLUT.catmullRomTangents(x: xs, y: ys)
        XCTAssertNotNil(v1)
        XCTAssertNotNil(v2)
        XCTAssertEqual(v1!, v2!)
    }

    // MARK: - V2 verdict (a): monotone VARIANT differs from V1

    /// V2 MONOTONE (G-variant) DIFFERS from V1 (arithmetic-mean +
    /// clamp) on asymmetric nodes — the verdict's delta, pinned so a
    /// future "simplification" back to V1 cannot pass silently.
    /// Hand check per code order (nodes (0,0),(0.3,0.8),(1,1)):
    /// Δ0 = 2.6667, Δ1 = 0.2857. V1 starts m = [2.6667, 1.4762, 0.2857];
    /// segment 0 τ = 1.31 < 9 (no clamp); segment 1 τ = 27.69 > 9 →
    /// m[1] = 3·5.1667·0.2857/√27.69 = 0.8416, m[2] = 3·1·0.2857/√27.69
    /// = 0.1629. VARIANT interior = G(Δ0,Δ1,h0=0.3,h1=0.7) with
    /// α = (0.3+1.4)/3 = 0.5667 → G = 0.7619/1.3175 = 0.5783. Must differ.
    func testMonotoneVariantDiffersFromV1() {
        let xs = [0.0, 0.3, 1.0]
        let ys = [0.0, 0.8, 1.0]
        let v1 = ToneCurveLUT.monotoneHermiteTangents(x: xs, y: ys)
        let v2 = ColorZonesLUT.monotoneVariantTangents(x: xs, y: ys)
        XCTAssertNotNil(v1)
        XCTAssertNotNil(v2)
        XCTAssertEqual(v1![1], 0.84158, accuracy: 1e-4)
        XCTAssertEqual(v1![2], 0.16289, accuracy: 1e-4)
        XCTAssertEqual(v2![1], 0.57831, accuracy: 1e-4)
        XCTAssertEqual(v2![2], 0.28571, accuracy: 1e-4)
        XCTAssertNotEqual(v1![1], v2![1])
        // Leading endpoint agrees (both one-sided secants); the trailing
        // endpoint differs exactly because V1's segment-1 clamp rescaled
        // m[2] while the variant keeps the secant.
        XCTAssertEqual(v1![0], v2![0], accuracy: 1e-12)
        XCTAssertNotEqual(v1![2], v2![2])
    }

    // MARK: - Periodic leg (select h)

    /// Periodic evaluation wraps: f(0) == f(1) for every type (the
    /// select-h LUT has no seam).
    func testPeriodicWrapsSeamlessly() {
        let nodes = [(x: 0.1, y: 0.2), (x: 0.4, y: 0.8), (x: 0.7, y: 0.3)]
        let xs = nodes.map(\.x), ys = nodes.map(\.y)
        let solvers: [[Double]?] = [
            ColorZonesLUT.periodicCatmullRomTangents(x: xs, y: ys),
            ColorZonesLUT.periodicMonotoneVariantTangents(x: xs, y: ys),
            ColorZonesLUT.periodicCubicTangents(x: xs, y: ys),
        ]
        for (i, t) in solvers.enumerated() {
            guard let t else { XCTFail("solver \(i) nil"); continue }
            let a = ColorZonesLUT.evaluatePeriodic(x: xs, y: ys, tangents: t, xval: 0.0)
            let b = ColorZonesLUT.evaluatePeriodic(x: xs, y: ys, tangents: t, xval: 1.0)
            XCTAssertEqual(a, b, accuracy: 1e-12, "solver \(i) seam")
        }
    }

    /// Periodic evaluation interpolates (passes through knots).
    func testPeriodicPassesThroughKnots() {
        let nodes = [(x: 0.0, y: 0.3), (x: 0.5, y: 0.9), (x: 0.8, y: 0.1)]
        let xs = nodes.map(\.x), ys = nodes.map(\.y)
        for t in [
            ColorZonesLUT.periodicCatmullRomTangents(x: xs, y: ys)!,
            ColorZonesLUT.periodicMonotoneVariantTangents(x: xs, y: ys)!,
            ColorZonesLUT.periodicCubicTangents(x: xs, y: ys)!,
        ] {
            for (x, y) in nodes {
                XCTAssertEqual(
                    ColorZonesLUT.evaluatePeriodic(x: xs, y: ys, tangents: t, xval: x),
                    y, accuracy: 1e-9)
            }
        }
    }

    // MARK: - Table build

    /// Identity curves → identity LUT (max deviation < 1e-9 — T2 evidence).
    /// Default select-h nodes (0.25,0.5)-(0.75,0.5) folded at strength 0:
    /// periodic catmull through two knots is the straight line 0.5.
    func testIdentityTablesBuild() {
        let p = ColorZonesModule.Params()
        let tables = (
            l: ColorZonesLUT.buildTable(
                nodes: p.curveL.map { (Double($0.x), Double($0.y)) },
                type: p.typeL, strength: 0, periodic: false),
            c: ColorZonesLUT.buildTable(
                nodes: p.curveC.map { (Double($0.x), Double($0.y)) },
                type: p.typeC, strength: 0, periodic: false),
            h: ColorZonesLUT.buildTable(
                nodes: p.curveH.map { (Double($0.x), Double($0.y)) },
                type: p.typeH, strength: 0, periodic: true))
        for (name, t, expect) in [
            ("L", tables.l, nil as Double?), ("C", tables.c, nil),
        ] {
            _ = name
            for v in t {
                XCTAssertEqual(v, 0.5, accuracy: 1e-9, "\(name) identity")
            }
            _ = expect
        }
        for v in tables.h {
            XCTAssertEqual(v, 0.5, accuracy: 1e-9, "H periodic identity")
        }
    }

    /// Strength folds y toward/away from 0.5 BEFORE sampling
    /// (colorzones.c:421-425): strength +100 maps y → 2y−0.5.
    func testStrengthFold() {
        XCTAssertEqual(ColorZonesLUT.foldedY(0.7, strength: 100), 0.9, accuracy: 1e-12)
        XCTAssertEqual(ColorZonesLUT.foldedY(0.7, strength: 0), 0.7, accuracy: 1e-12)
        XCTAssertEqual(ColorZonesLUT.foldedY(0.7, strength: -100), 0.5, accuracy: 1e-12)
    }

    // MARK: - Commit + reference smoke

    /// Commit writes 3×0x10000 tables + channel uniform; identity params
    /// ⇒ all-0.5 tables (separate loop, compared > 0).
    func testCommitWritesUniformTables() async {
        let module = ColorZonesModule()
        var piece = IOPiece()
        module.commitParams(ColorZonesModule.Params(), into: &piece)
        let buffer = try! XCTUnwrap(piece.data)
        XCTAssertEqual(
            buffer.length,
            3 * ColorZonesLUT.resolution * MemoryLayout<Float>.size + 16)
        let floats = buffer.contents().assumingMemoryBound(to: Float.self)
        var compared = 0
        for k in stride(from: 0, to: 3 * ColorZonesLUT.resolution, by: 997) {
            XCTAssertEqual(floats[k], 0.5, accuracy: 1e-6, "table entry \(k)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        let channel = buffer.contents().advanced(by: ColorZonesModule.uniformOffset)
            .assumingMemoryBound(to: Int32.self).pointee
        XCTAssertEqual(channel, 2, "default select = hue")
    }

    /// Reference smoke: identity tables ⇒ in == out (Lab round-trip
    /// through the v3 math with Lm = hm = 0, Cm = 1).
    func testReferenceIdentityTables() {
        let half = [Double](repeating: 0.5, count: ColorZonesLUT.resolution)
        let lab = SIMD3<Double>(50, 20, -30)
        for ch in ColorZonesLUT.SelectChannel.allCases {
            let out = ColorZonesModule.reference(
                lab: lab, tables: (half, half, half), selectChannel: ch)
            XCTAssertEqual(out.x, lab.x, accuracy: 1e-9, "\(ch) L")
            XCTAssertEqual(out.y, lab.y, accuracy: 1e-9, "\(ch) a")
            XCTAssertEqual(out.z, lab.z, accuracy: 1e-9, "\(ch) b")
        }
    }

    /// Reference smoke: hue-mode low-saturation blend suppresses the
    /// effect near gray (blend → 1 ⇒ LUT contribution → 0.5 ⇒ Lm/hm → 0).
    func testReferenceHueLowSaturationSuppression() {
        // C-curve pulled hard: tables.c = 0.0 everywhere except LUT shape
        // is flat, so Cm = 0 kills chroma regardless; use L-table tilt
        // instead: L LUT ramps 0→1, gray pixel must move less than a vivid
        // pixel at the same select.
        var ramp = [Double](repeating: 0, count: ColorZonesLUT.resolution)
        for k in 0..<ColorZonesLUT.resolution {
            ramp[k] = Double(k) / Double(ColorZonesLUT.resolution - 1)
        }
        let half = [Double](repeating: 0.5, count: ColorZonesLUT.resolution)
        let gray = ColorZonesModule.reference(
            lab: SIMD3(50, 0.5, 0.2), tables: (ramp, half, half), selectChannel: .hue)
        let vivid = ColorZonesModule.reference(
            lab: SIMD3(50, 60, 0.0), tables: (ramp, half, half), selectChannel: .hue)
        XCTAssertLessThan(abs(gray.x - 50), abs(vivid.x - 50))
    }

    /// V50 slot assertion for colorzones 60.0.
    func testColorZonesSlot() {
        XCTAssertEqual(V50Order.order(for: "colorzones"), 60.0)
        XCTAssertEqual(ColorZonesModule.iopOrder, 60.0)
    }
}
