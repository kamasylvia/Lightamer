@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-03 T4/T5/T8 — the drawn mask rasterization goldens: per-form
/// analytic gates (<1e-6 vs float64 references of the SAME closed forms
/// the MSL implements), brush hardness profiles + additive accumulation +
/// the eraser, and the tile-seam gate (forced band partition vs whole).
///
/// 防空转 (L020 ③): every gate is a real per-pixel comparison loop with a
/// `compared > 0` assertion; the measured max errors are printed so the
/// numbers land in the run log.
final class DrawnMaskRasterTests: XCTestCase {

    // ── float64 references (the MSL's formulas, Double precision) ──

    private struct RefUniforms {
        var frameW: Double
        var frameH: Double
        var winOrigin: SIMD2<Double>
        var winSize: SIMD2<Double>
        var aspect: Double
    }

    private func contentPoint(
        _ px: Int, _ py: Int, _ u: RefUniforms, mapper: GeometryPointMapper
    ) -> SIMD2<Double> {
        // composite-frame normalized: window pixel / the COMPOSITE frame
        let wn = SIMD2((Double(px) + 0.5) / u.winSize.x, (Double(py) + 0.5) / u.winSize.y)
        let cn = (wn * u.winSize + u.winOrigin) / mapper.outputSize
        return mapper.inverse(normalized: cn)
    }

    private func refEllipse(
        _ p: SIMD2<Double>, center: SIMD2<Double>, rx: Double, ry: Double,
        rotationDeg: Double, border: Double, aspect: Double
    ) -> Double {
        // The kernel's reformulated quadratic falloff (same dt shape).
        let c = SIMD2(center.x, center.y * aspect)
        let d = SIMD2(p.x, p.y * aspect) - c
        let alpha = rotationDeg * .pi / 180
        let ca = cos(alpha), sa = sin(alpha)
        let dx = d.x * ca + d.y * sa
        let dy = -d.x * sa + d.y * ca
        let q = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
        if border <= 1e-6 { return q <= 1 ? 1 : 0 }
        let k2 = (1 + border) * (1 + border)
        let f = min(max((k2 - q) / (k2 - 1), 0), 1)
        return f * f
    }

    private func refGradient(
        _ p: SIMD2<Double>, anchor: SIMD2<Double>, rotationDeg: Double,
        compression: Double, curvature: Double, sigmoidal: Bool,
        frameW: Double, frameH: Double
    ) -> Double {
        let px = p.x * frameW, py = p.y * frameH
        let wd = frameW, ht = frameH
        let hwscale = 1.0 / (wd * wd + ht * ht).squareRoot()
        let v = -rotationDeg * .pi / 180
        let sinv = sin(v), cosv = cos(v)
        let xoff = cosv * anchor.x * wd + sinv * anchor.y * ht
        let yoff = sinv * anchor.x * wd - cosv * anchor.y * ht
        let comp = max(compression, 0.001)
        let normf = 1.0 / comp
        let x0 = (cosv * px + sinv * py - xoff) * hwscale
        let y0 = (sinv * px - cosv * py - yoff) * hwscale
        let distance = y0 - curvature * x0 * x0
        let raw = 0.5 + 0.5 * (sigmoidal ? erf(distance / comp) : normf * distance)
        return min(max(raw, 0), 1)
    }

    private func refStamp(
        _ p: SIMD2<Double>, center: SIMD2<Double>, radius: Double,
        hardness: Double, flow: Double, aspect: Double
    ) -> Double {
        let dxu = p.x - center.x
        let dyu = (p.y - center.y) * aspect
        let d = (dxu * dxu + dyu * dyu).squareRoot()
        if d >= radius { return 0 }
        var w: Double
        if hardness >= 0.999 {
            w = 1
        } else {
            let core = hardness * radius
            w = d <= core ? 1 : 1 - (d - core) / (radius - core)
        }
        return flow * w
    }

    // ── GPU helpers ──

    private func makeMetal() throws -> MetalContext {
        let metal = try MetalContext()
        return metal
    }

    private func readPlane(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted() // L014
        var values = [Float](repeating: -1, count: texture.width * texture.height)
        values.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return values
    }

    private func identityMapper(width: Int, height: Int) -> GeometryPointMapper {
        GeometryPointMapper.compose(boxes: [], frameSize: SIMD2(Double(width), Double(height)))
    }

    /// Rasterize through the real cached path; returns the FOLDED plane.
    private func rasterize(
        _ spec: MaskSpec, window: ROI, mapper: GeometryPointMapper,
        metal: MetalContext, opacity: Float = 1.0, rowBands: Int = 1
    ) async throws -> (values: [Float], w: Int, h: Int) {
        let cache = PipeCache()
        let (plane, _) = try await DrawnMaskRasterizer.plane(
            spec: spec, layerOpacity: opacity, window: window, mapper: mapper,
            metal: metal, cache: cache, imageID: UUID(), pipeType: .preview,
            layerID: UUID(), rowBands: rowBands)
        return (readPlane(plane, metal: metal), plane.width, plane.height)
    }

    private func assertAnalytic(
        _ got: [Float], _ expect: (Int, Int) -> Double, w: Int, h: Int,
        gate: Double, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var maxErr = 0.0
        var compared = 0
        for y in 0..<h {
            for x in 0..<w {
                let v = Double(got[y * w + x])
                let e = expect(x, y)
                let err = abs(v - e)
                if err > maxErr { maxErr = err }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "\(label): 防空转 guard", file: file, line: line)
        XCTAssertLessThan(maxErr, gate, "\(label): max err \(maxErr) (gate \(gate))",
                          file: file, line: line)
        print("[06-03 T4/T5] \(label): compared=\(compared) maxErr=\(maxErr) gate=\(gate)")
    }

    // ═══ T4: ellipse ═══

    func testEllipseAnalyticGolden() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 160, h = 120
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)

        // 3 cases (plan: 每形态 ≥3 case 含 border/rotation 变体). The last
        // tuple member is the gate: the ROTATED FEATHER band pays an
        // intrinsic float32 floor — |d|·ulp(cos/sin) amplified by /rx and
        // ÷border through the band (L023/05-02 tiered-gate precedent; the
        // measured floor is printed every run). Everything else holds 1e-6.
        let cases: [(SIMD2<Double>, Double, Double, Double, Double, String, Double)] = [
            (SIMD2(0.5, 0.5), 0.3, 0.2, 0, 0.0, "axis-aligned no border", 1e-6),
            (SIMD2(0.5, 0.5), 0.3, 0.2, 30, 0.0, "rotated 30°", 1e-6),
            (SIMD2(0.4, 0.6), 0.25, 0.35, -15, 0.3, "rotated −15° + border 0.3", 5e-6),
        ]
        for (center, rx, ry, rot, border, label, gate) in cases {
            let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
                MaskForm(kind: .ellipse(EllipseForm(
                    center: MaskPoint(x: center.x, y: center.y),
                    radiusX: Float(rx), radiusY: Float(ry),
                    rotationDegrees: Float(rot), border: Float(border)))),
            ]))
            let (values, gw, gh) = try await rasterize(
                spec, window: window, mapper: mapper, metal: metal)
            XCTAssertEqual(gw, w)
            XCTAssertEqual(gh, h)
            assertAnalytic(values, { x, y in
                let p = self.contentPoint(
                    x, y, RefUniforms(
                        frameW: Double(w), frameH: Double(h),
                        winOrigin: .zero, winSize: SIMD2(Double(w), Double(h)),
                        aspect: aspect), mapper: mapper)
                return self.refEllipse(
                    p, center: center, rx: rx, ry: ry,
                    rotationDeg: rot, border: border, aspect: aspect)
            }, w: w, h: h, gate: gate, "ellipse [\(label)]")
        }
    }

    // ═══ T4: gradient (linear + sigmoidal) ═══

    func testGradientAnalyticGolden() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 128, h = 96
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let anchor = SIMD2(0.3, 0.4)

        for (state, rot, comp, label) in [
            (GradientState.linear, 0.0, 0.2, "linear 0°"),
            (GradientState.linear, 37.0, 0.15, "linear 37°"),
            (GradientState.sigmoidal, 20.0, 0.1, "sigmoidal 20°"),
            (GradientState.sigmoidal, -65.0, 0.05, "sigmoidal −65° steep"),
        ] {
            let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
                MaskForm(kind: .gradient(GradientForm(
                    anchor: MaskPoint(x: anchor.x, y: anchor.y),
                    rotationDegrees: Float(rot), compression: Float(comp),
                    state: state))),
            ]))
            let (values, _, _) = try await rasterize(
                spec, window: window, mapper: mapper, metal: metal)
            assertAnalytic(values, { x, y in
                let p = self.contentPoint(
                    x, y, RefUniforms(
                        frameW: Double(w), frameH: Double(h),
                        winOrigin: .zero, winSize: SIMD2(Double(w), Double(h)),
                        aspect: Double(h) / Double(w)), mapper: mapper)
                return self.refGradient(
                    p, anchor: anchor, rotationDeg: rot, compression: comp,
                    curvature: 0, sigmoidal: state == .sigmoidal,
                    frameW: Double(w), frameH: Double(h))
            }, w: w, h: h, gate: 1e-6, "gradient [\(label)]")
        }
    }

    // ═══ T4: path (SDF + border band) ═══

    func testPathFillAndBorderGolden() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 128, h = 128
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)

        // A centered square (0.3..0.7), straight edges (ctrl = corners).
        func squareNodes(border: Float) -> PathForm {
            let a = MaskPoint(x: 0.3, y: 0.3), b = MaskPoint(x: 0.7, y: 0.3)
            let c = MaskPoint(x: 0.7, y: 0.7), d = MaskPoint(x: 0.3, y: 0.7)
            func node(_ p: MaskPoint) -> PathNode {
                PathNode(corner: p, ctrl1: p, ctrl2: p)
            }
            return PathForm(nodes: [node(a), node(b), node(c), node(d)], border: border)
        }

        for (border, label) in [(Float(0), "hard edge"), (Float(0.1), "border 0.1")] {
            let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
                MaskForm(kind: .path(squareNodes(border: border))),
            ]))
            let (values, _, _) = try await rasterize(
                spec, window: window, mapper: mapper, metal: metal)

            // float64 reference: CPU SDF over the same flattened polyline.
            let polyline = DrawnMaskRasterizer.flattenPath(squareNodes(border: border), aspect: aspect)
            func refValue(_ px: Int, _ py: Int) -> Double {
                let p = SIMD2(
                    (Double(px) + 0.5) / Double(w),
                    (Double(py) + 0.5) / Double(h))
                let pu = SIMD2(p.x, p.y * aspect)
                var minD = Double(1e30)
                var crossings = 0
                for i in 0..<polyline.count {
                    let a = SIMD2<Double>(polyline[i])
                    let b = SIMD2<Double>(polyline[(i + 1) % polyline.count])
                    let ab = b - a, ap = pu - a
                    func dot(_ u: SIMD2<Double>, _ v: SIMD2<Double>) -> Double {
                        u.x * v.x + u.y * v.y
                    }
                    let t = min(max(dot(ap, ab) / max(dot(ab, ab), 1e-20), 0), 1)
                    let q = a + t * ab
                    let dd = pu - q
                    minD = min(minD, dot(dd, dd).squareRoot())
                    if (a.y > pu.y) != (b.y > pu.y) {
                        let xint = a.x + (pu.y - a.y) * (b.x - a.x) / (b.y - a.y)
                        if xint > pu.x { crossings += 1 }
                    }
                }
                let inside = crossings.isMultiple(of: 2) ? false : true
                let sd = inside ? -minD : minD
                if border <= 1e-6 { return sd <= 0 ? 1 : 0 }
                let tt = min(max(-sd / Double(border), 0), 1)
                return tt * tt * (3 - 2 * tt)
            }

            // Full-plane gate + interior/exterior probes (L020 ③ content).
            var maxErr = 0.0
            var compared = 0
            for y in 0..<h {
                for x in 0..<w {
                    let v = Double(values[y * w + x])
                    let e = refValue(x, y)
                    maxErr = max(maxErr, abs(v - e))
                    compared += 1
                }
            }
            XCTAssertGreaterThan(compared, 0, "防空转 guard")
            XCTAssertLessThan(maxErr, 1e-6, "path [\(label)]: max err \(maxErr)")
            print("[06-03 T4] path [\(label)]: compared=\(compared) maxErr=\(maxErr) gate=1e-6")

            // Interior/exterior content-level probes (记账测试免疫的兜底).
            let inner = values[(h / 2) * w + w / 2]
            let outer = values[2 * w + 2]
            if border == 0 {
                XCTAssertEqual(inner, 1.0, accuracy: 1e-6, "square interior = 1")
                XCTAssertEqual(outer, 0.0, accuracy: 1e-6, "corner exterior = 0")
            } else {
                XCTAssertGreaterThan(inner, 0.99, "deep interior ~1")
                XCTAssertLessThan(outer, 0.01, "outside ~0")
            }
        }
    }

    // ═══ T5: brush hardness profiles (0 / 0.5 / 1) ═══

    func testBrushHardnessProfilesGolden() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 96, h = 96
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)
        let center = SIMD2(0.5, 0.5)
        let radius = 0.25

        for (hardness, label) in [(0.0, "hardness 0 (cone)"), (0.5, "hardness 0.5"), (1.0, "hardness 1 (disc)")] {
            let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
                MaskForm(kind: .brush(BrushStroke(
                    points: [BrushPoint(
                        corner: MaskPoint(x: center.x, y: center.y),
                        ctrl1: MaskPoint(x: center.x, y: center.y),
                        ctrl2: MaskPoint(x: center.x, y: center.y))],
                    radius: Float(radius), hardness: Float(hardness),
                    density: 0.8, opacity: 1.0))),
            ]))
            let (values, _, _) = try await rasterize(
                spec, window: window, mapper: mapper, metal: metal)
            assertAnalytic(values, { x, y in
                let p = self.contentPoint(
                    x, y, RefUniforms(
                        frameW: Double(w), frameH: Double(h),
                        winOrigin: .zero, winSize: SIMD2(Double(w), Double(h)),
                        aspect: aspect), mapper: mapper)
                return self.refStamp(
                    p, center: center, radius: radius, hardness: hardness,
                    flow: 0.8, aspect: aspect)
            }, w: w, h: h, gate: 1e-6, "brush [\(label)]")
        }
    }

    // ═══ T5: N-stamp additive accumulation (解析和) ═══

    func testBrushStrokeAccumulationAnalyticSum() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 128, h = 64
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)
        let radius = 0.12
        let hardness = 0.5
        let density = 0.3

        // A straight 2-point stroke → stamps at 0.5r spacing along x.
        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .brush(BrushStroke(
                points: [
                    BrushPoint(
                        corner: MaskPoint(x: 0.15, y: 0.5),
                        ctrl1: MaskPoint(x: 0.2, y: 0.5),
                        ctrl2: MaskPoint(x: 0.3, y: 0.5)),
                    BrushPoint(
                        corner: MaskPoint(x: 0.85, y: 0.5),
                        ctrl1: MaskPoint(x: 0.7, y: 0.5),
                        ctrl2: MaskPoint(x: 0.6, y: 0.5)),
                ],
                radius: Float(radius), hardness: Float(hardness),
                density: Float(density), opacity: 1.0))),
        ]))

        // Reference: replicate the CPU stamp chain, sum in float64, clamp.
        guard case let .brush(refStroke) = spec.drawn!.forms[0].kind else {
            return XCTFail("fixture must be a brush stroke")
        }
        let stamps = DrawnMaskRasterizer.stampsForStroke(refStroke, aspect: aspect)
        XCTAssertGreaterThan(stamps.count, 4, "stamp chain must subdivide (compared > 0 base)")

        let (values, _, _) = try await rasterize(spec, window: window, mapper: mapper, metal: metal)
        assertAnalytic(values, { x, y in
            let p = self.contentPoint(
                x, y, RefUniforms(
                    frameW: Double(w), frameH: Double(h),
                    winOrigin: .zero, winSize: SIMD2(Double(w), Double(h)),
                    aspect: aspect), mapper: mapper)
            var sum = 0.0
            for stamp in stamps {
                sum += self.refStamp(
                    p, center: SIMD2<Double>(stamp.imagePos), radius: radius,
                    hardness: hardness, flow: density, aspect: aspect)
            }
            return min(max(sum, 0), 1)
        }, w: w, h: h, gate: 1e-5, "brush accumulation (\(stamps.count) stamps)")
    }

    // ═══ T5: eraser = negative-density stroke subtracts ═══

    func testEraserNegativeStrokeSubtracts() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 96, h = 96
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        func point(_ x: Double, _ y: Double) -> BrushPoint {
            BrushPoint(
                corner: MaskPoint(x: x, y: y), ctrl1: MaskPoint(x: x, y: y),
                ctrl2: MaskPoint(x: x, y: y))
        }
        // Base disc at (0.35, 0.5) density 1 + eraser disc at (0.6, 0.5)
        // density −1: between them the field sums toward 0 where the
        // eraser overlaps the base, exactly where both falloffs reach.
        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .brush(BrushStroke(
                points: [point(0.35, 0.5)], radius: 0.2, hardness: 1,
                density: 1, opacity: 1))),
            MaskForm(kind: .brush(BrushStroke(
                points: [point(0.6, 0.5)], radius: 0.2, hardness: 1,
                density: -1, opacity: 1))),
        ]))
        let (values, _, _) = try await rasterize(spec, window: window, mapper: mapper, metal: metal)

        var compared = 0
        for y in [h / 2, h / 2 + 8] {
            for x in 2..<(w - 2) {
                let p = SIMD2<Double>(
                    (Double(x) + 0.5) / Double(w), (Double(y) + 0.5) / Double(h))
                let v = Double(values[y * w + x])
                let expect = min(max(
                    self.refStamp(p, center: SIMD2<Double>(0.35, 0.5), radius: 0.2, hardness: 1, flow: 1, aspect: 1)
                        + self.refStamp(p, center: SIMD2<Double>(0.6, 0.5), radius: 0.2, hardness: 1, flow: -1, aspect: 1), 0), 1)
                XCTAssertEqual(v, expect, accuracy: 1e-6,
                               "eraser signed sum at (\(x),\(y))")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
        // Content-level: near the eraser core the mask is fully erased.
        let eraserCore = values[(h / 2) * w + Int(0.93 * Double(w))]
        XCTAssertLessThan(eraserCore, 0.4, "eraser core cuts the field down")
    }

    // ═══ T8 (early): tile seam — forced band partition vs whole ═══

    func testTileSeamBandedEqualsWhole() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 128, h = 100
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.3, radiusY: 0.25,
                rotationDegrees: 20, border: 0.25))),
        ]))
        let bands = 4
        let (whole, _, _) = try await rasterize(spec, window: window, mapper: mapper, metal: metal)
        let (banded, _, _) = try await rasterize(
            spec, window: window, mapper: mapper, metal: metal, rowBands: bands)
        var maxDiff = 0.0
        var compared = 0
        for i in 0..<whole.count {
            maxDiff = max(maxDiff, abs(Double(whole[i]) - Double(banded[i])))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
        XCTAssertGreaterThan(h / bands, 1, "强制分块计数 > 1 断言 (band height > 1)")
        XCTAssertLessThan(maxDiff, 1e-6, "banded vs whole \(maxDiff)")
        print("[06-03 T8] tile seam bands=\(bands): compared=\(compared) maxDiff=\(maxDiff) gate=1e-6")
    }

    // ═══ content anchoring through a crop+flip mapper ═══

    func testContentAnchoredThroughCropMapper() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let frameW = 200, frameH = 100
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        let mapper = GeometryPointMapper.compose(
            boxes: [crop], frameSize: SIMD2(Double(frameW), Double(frameH)))
        // window = the crop output frame
        let winW = mapper.outputSize.x, winH = mapper.outputSize.y
        let window = ROI(x: 0, y: 0, width: Int(winW), height: Int(winH), scale: 1.0)

        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.1, radiusY: 0.1,
                rotationDegrees: 0, border: 0.5))),
        ]))
        let (values, gw, gh) = try await rasterize(spec, window: window, mapper: mapper, metal: metal)
        // The mask MASS CENTROID must sit at the CONTENT position: decode
        // center (0.5, 0.5) maps through the crop to the window center
        // (symmetric shape → centroid == center; an argmax would degenerate
        // onto the plateau's top-left corner). Window px = decode px·0.5.
        let expectX = (Double(winW) - 1) / 2, expectY = (Double(winH) - 1) / 2
        var sx = 0.0, sy = 0.0, mass = 0.0
        for y in 0..<gh {
            for x in 0..<gw {
                let m = Double(values[y * gw + x])
                sx += m * Double(x); sy += m * Double(y); mass += m
            }
        }
        XCTAssertGreaterThan(mass, 0, "防空转 guard")
        XCTAssertEqual(sx / mass, expectX, accuracy: 1.0,
                       "content-anchored centroid x within a pixel")
        XCTAssertEqual(sy / mass, expectY, accuracy: 1.0,
                       "content-anchored centroid y within a pixel")
    }
}
