@testable import LightamerCore
import Metal
import XCTest

/// Plan M2-7-1 T1/T2 (M2MASK-01/02) — the Radial dual-feather goldens and
/// the LinearGradient↔Alcedo mapping goldens.
///
/// T1 (KD-1): the Alcedo linear-band leg (grade_mask_coverage.cpp:150-153,
/// GPL numeric reference only) vs the legacy quadratic leg — float64
/// parity ≤1e-6, the three band anchors (1 / 0.5 / 0), the dual-nil
/// legacy zero-drift routing, and the fallback matrix (dual-nil → legacy;
/// either set → Alcedo with the nil partner folded to 0 INSIDE the leg;
/// explicit (0,0) → the Alcedo hard edge, never a legacy fall-back).
/// The pre-existing 06-03 analytic goldens re-running untouched are the
/// byte-level zero-drift witness for v4-era documents.
///
/// T2 (KD-2): the Alcedo LinearGradient mapping — rotation = atan2(nx, ny)
/// (sign pinned by plane-sampled pairs) and compression = τ/(2·√2) on the
/// square reference window (derivation in M2-7-1-DECISIONS), pinned at the
/// Alcedo default band τ=0.2 and the τ=1.0 scale档.
final class MaskFeatherAlignTests: XCTestCase {

    // ── float64 references ──

    /// The legacy quadratic leg (DrawnMaskRasterTests.refEllipse verbatim —
    /// the pre-M2-7 ellipse formula).
    private func refLegacyEllipse(
        _ p: SIMD2<Double>, center: SIMD2<Double>, rx: Double, ry: Double,
        rotationDeg: Double, border: Double, aspect: Double
    ) -> Double {
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

    /// The Alcedo linear-band leg verbatim (grade_mask_coverage.cpp:150-153):
    /// rho = the normalized elliptical radius; inner/outer are the NIL-FOLDED
    /// feather values (the caller folds nil→0 — the kernel receives them
    /// pre-folded in form2).
    private func refAlcedoBand(
        _ p: SIMD2<Double>, center: SIMD2<Double>, rx: Double, ry: Double,
        rotationDeg: Double, innerFeather: Double, outerFeather: Double,
        aspect: Double
    ) -> Double {
        let c = SIMD2(center.x, center.y * aspect)
        let d = SIMD2(p.x, p.y * aspect) - c
        let alpha = rotationDeg * .pi / 180
        let ca = cos(alpha), sa = sin(alpha)
        let dx = d.x * ca + d.y * sa
        let dy = -d.x * sa + d.y * ca
        let q = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
        let rho = q.squareRoot()
        let inner = max(0.0, 1.0 - innerFeather)
        let outer = 1.0 + max(0.0, outerFeather)
        return 1.0 - min(max((rho - inner) / max(outer - inner, 1e-6), 0.0), 1.0)
    }

    /// The dt linear gradient (MaskRasterKernels gradient段 verbatim,
    /// curvature 0, linear state).
    private func refGradient(
        _ p: SIMD2<Double>, anchor: SIMD2<Double>, rotationDeg: Double,
        compression: Double, frameW: Double, frameH: Double
    ) -> Double {
        let px = p.x * frameW, py = p.y * frameH
        let hwscale = 1.0 / (frameW * frameW + frameH * frameH).squareRoot()
        let v = -rotationDeg * .pi / 180
        let sinv = sin(v), cosv = cos(v)
        let xoff = cosv * anchor.x * frameW + sinv * anchor.y * frameH
        let yoff = sinv * anchor.x * frameW - cosv * anchor.y * frameH
        let comp = max(compression, 0.001)
        let x0 = (cosv * px + sinv * py - xoff) * hwscale
        let y0 = (sinv * px - cosv * py - yoff) * hwscale
        return min(max(0.5 + 0.5 * (y0 / comp), 0), 1)
    }

    // ── GPU helpers ──

    private func makeMetal() throws -> MetalContext {
        try MetalContext()
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

    private func rasterize(
        _ form: MaskForm, window: ROI, mapper: GeometryPointMapper,
        metal: MetalContext
    ) async throws -> (values: [Float], w: Int, h: Int) {
        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [form]))
        let cache = PipeCache()
        let (plane, _) = try await DrawnMaskRasterizer.plane(
            spec: spec, layerOpacity: 1, window: window, mapper: mapper,
            metal: metal, cache: cache, imageID: UUID(), pipeType: .preview,
            layerID: UUID())
        return (readPlane(plane, metal: metal), plane.width, plane.height)
    }

    private func assertPlane(
        _ got: [Float], w: Int, h: Int, mapper: GeometryPointMapper,
        window: ROI, aspect: Double,
        expect: (SIMD2<Double>) -> Double, gate: Double, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var maxErr = 0.0
        var compared = 0
        for y in 0..<h {
            for x in 0..<w {
                let wn = SIMD2(
                    (Double(x) + 0.5) / Double(w), (Double(y) + 0.5) / Double(h))
                let cn = (wn * SIMD2(Double(window.width), Double(window.height))
                    + SIMD2(Double(window.x), Double(window.y)))
                    / mapper.outputSize
                let p = mapper.inverse(normalized: cn)
                let err = abs(Double(got[y * w + x]) - expect(p))
                if err > maxErr { maxErr = err }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "\(label): 防空转 guard", file: file, line: line)
        XCTAssertLessThan(maxErr, gate, "\(label): max err \(maxErr) (gate \(gate))",
                          file: file, line: line)
        print("[M2-7-1] \(label): compared=\(compared) maxErr=\(maxErr) gate=\(gate)")
    }

    private func ellipse(
        _ center: SIMD2<Double>, _ rx: Double, _ ry: Double, _ rot: Double,
        _ border: Double, inner: Float? = nil, outer: Float? = nil
    ) -> MaskForm {
        MaskForm(kind: .ellipse(EllipseForm(
            center: MaskPoint(x: center.x, y: center.y),
            radiusX: Float(rx), radiusY: Float(ry),
            rotationDegrees: Float(rot), border: Float(border),
            innerFeather: inner, outerFeather: outer)))
    }

    // ═══ T1 · KD-1: the Alcedo leg parity (both feathers set + variants) ═══

    func testAlcedoDualFeatherParityFloat64() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 160, h = 121 // odd height: pixel row 60 hits y = 0.5 exactly
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)
        let center = SIMD2(0.5, 0.5)

        let cases: [(Float?, Float?, Double, String)] = [
            (0.25, 0.6041667, 0, "both set (anchor geometry)"),
            (0.1, 0.4, 30, "both set rotated 30°"),
            (0.3, nil, 0, "inner only — outer folds to 0"),
            (nil, 0.35, -20, "outer only — inner folds to 0"),
        ]
        for (inner, outer, rot, label) in cases {
            let (values, gw, gh) = try await rasterize(
                ellipse(center, 0.3, 0.3, rot, 0.3, inner: inner, outer: outer),
                window: window, mapper: mapper, metal: metal)
            XCTAssertEqual(gw, w)
            XCTAssertEqual(gh, h)
            assertPlane(
                values, w: w, h: h, mapper: mapper, window: window, aspect: aspect,
                expect: { p in
                    self.refAlcedoBand(
                        p, center: center, rx: 0.3, ry: 0.3, rotationDeg: rot,
                        innerFeather: Double(inner ?? 0),
                        outerFeather: Double(outer ?? 0), aspect: aspect)
                }, gate: 1e-6, "alcedo band [\(label)]")
        }
    }

    // ═══ T1 · KD-1: the three band anchors (1 / 0.5±1e-6 / 0) ═══

    func testLinearBandAnchors() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 160, h = 121
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)
        // Geometry: circle r=0.3 at (0.5, 0.5); inner 0.25 → inner edge
        // 0.75; outer 0.6041667 → outer edge 1.6041667. Band midpoint
        // rho = 1.1770833 = (56.5/48) lands EXACTLY on pixel x=136
        // (px = 79.5 + 48·rho); row y=60 gives p.y = 0.5 exactly (dy = 0).
        let innerF: Float = 0.25
        let outerF: Float = 0.6041667
        let (values, _, _) = try await rasterize(
            ellipse(SIMD2(0.5, 0.5), 0.3, 0.3, 0, 0.3, inner: innerF, outer: outerF),
            window: window, mapper: mapper, metal: metal)

        func sample(_ px: Int, _ py: Int) -> Double {
            Double(values[py * w + px])
        }
        let innerAnchor = sample(98, 60)   // rho ≈ 0.385 < 0.75 → 1
        let midAnchor = sample(136, 60)    // rho = 1.1770833 → 0.5
        let outerAnchor = sample(157, 60)  // rho ≈ 1.615 > 1.6042 → 0
        XCTAssertEqual(innerAnchor, 1.0, accuracy: 1e-6, "inner-band anchor")
        XCTAssertEqual(midAnchor, 0.5, accuracy: 1e-6, "band-midpoint anchor")
        XCTAssertEqual(outerAnchor, 0.0, accuracy: 1e-6, "outer-band anchor")
        print("[M2-7-1] anchors: inner=\(innerAnchor) mid=\(midAnchor) outer=\(outerAnchor)")
    }

    // ═══ T1 · KD-1: dual-nil legacy zero-drift + routing predicate ═══

    func testDualNilRoutesToLegacyLegZeroDrift() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 160, h = 121
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)
        let center = SIMD2(0.5, 0.5)

        // Dual-nil (border 0.3): parity with the UNTOUCHED legacy quadratic
        // leg — the gate follows the 06-03 precedent (the ROTATED feather
        // band pays an intrinsic float32 floor; DrawnMaskRasterTests pins
        // 5e-6 for this exact family, everything else holds 1e-6).
        let (values, _, _) = try await rasterize(
            ellipse(center, 0.3, 0.3, 15, 0.3), window: window,
            mapper: mapper, metal: metal)
        assertPlane(
            values, w: w, h: h, mapper: mapper, window: window, aspect: aspect,
            expect: { p in
                self.refLegacyEllipse(
                    p, center: center, rx: 0.3, ry: 0.3, rotationDeg: 15,
                    border: 0.3, aspect: aspect)
            }, gate: 5e-6, "dual-nil legacy leg")

        // Routing proof: the same form through the Alcedo hard-edge reading
        // would be a completely different plane — assert the legacy render
        // is FAR from it (the flag routed on nil-ness, not on values).
        var alcedoDiff = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let wn = SIMD2(
                    (Double(x) + 0.5) / Double(w), (Double(y) + 0.5) / Double(h))
                let p = mapper.inverse(normalized: wn)
                let a = refAlcedoBand(
                    p, center: center, rx: 0.3, ry: 0.3, rotationDeg: 15,
                    innerFeather: 0, outerFeather: 0, aspect: aspect)
                alcedoDiff = max(alcedoDiff, abs(Double(values[y * w + x]) - a))
            }
        }
        XCTAssertGreaterThan(alcedoDiff, 0.1, "dual-nil must NOT ride the Alcedo leg")
    }

    // ═══ T1 · KD-1: the fallback matrix (explicit (0,0) = hard edge) ═══

    func testFallbackMatrixExplicitZeroIsAlcedoHardEdge() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 160, h = 121
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let aspect = Double(h) / Double(w)
        let center = SIMD2(0.5, 0.5)

        // Explicit (0, 0): the Alcedo leg with inner=1, outer=1 — the hard
        // edge (rho < 1 → 1, rho > 1 → 0). NOT the legacy border leg.
        let (values, _, _) = try await rasterize(
            ellipse(center, 0.3, 0.3, 0, 0.3, inner: 0, outer: 0),
            window: window, mapper: mapper, metal: metal)
        assertPlane(
            values, w: w, h: h, mapper: mapper, window: window, aspect: aspect,
            expect: { p in
                self.refAlcedoBand(
                    p, center: center, rx: 0.3, ry: 0.3, rotationDeg: 0,
                    innerFeather: 0, outerFeather: 0, aspect: aspect)
            }, gate: 1e-6, "explicit (0,0) Alcedo hard edge")
    }

    // ═══ T1 · facade: the mode-aware read convention (checker E7) ═══

    func testResolvedOuterFeatherModeAware() {
        var form = EllipseForm(
            center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.3, radiusY: 0.3,
            rotationDegrees: 0, border: 0.3)
        // Dual-nil → the legacy leg: outer reads border.
        XCTAssertEqual(form.resolvedOuterFeather, 0.3)
        XCTAssertFalse(form.hasDualFeather)
        // Inner set, outer nil → the Alcedo leg: outer folds to 0.
        form.innerFeather = 0.25
        XCTAssertTrue(form.hasDualFeather)
        XCTAssertEqual(form.resolvedOuterFeather, 0)
        // Outer set → its own value (either leg state).
        form.outerFeather = 0.4
        XCTAssertEqual(form.resolvedOuterFeather, 0.4)
        // Inner back to nil, outer present → still the outer value.
        form.innerFeather = nil
        XCTAssertEqual(form.resolvedOuterFeather, 0.4)
    }

    // ═══ T1 · nil canonical-bytes absence (the ONE-WAY additive rule) ═══

    func testNilFeathersKeepCanonicalBytesAbsent() throws {
        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
            ellipse(SIMD2(0.5, 0.5), 0.3, 0.3, 0, 0.3),
        ]))
        let bytes = try JSONEncoder().encode(spec)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let forms = try XCTUnwrap(
            ((object["drawn"] as? [String: Any])?["forms"] as? [[String: Any]]))
        XCTAssertFalse(forms[0].keys.contains("innerFeather"))
        XCTAssertFalse(forms[0].keys.contains("outerFeather"))
        // Round-trip stability (encode → decode → encode, same hash).
        let hash = spec.stableHash()
        let decoded = try JSONDecoder().decode(MaskSpec.self, from: bytes)
        XCTAssertEqual(decoded.stableHash(), hash)
        // Setting either feather moves the hash (mask-domain params).
        var setForm = spec
        setForm.drawn?.forms[0] = ellipse(
            SIMD2(0.5, 0.5), 0.3, 0.3, 0, 0.3, inner: 0.25)
        XCTAssertNotEqual(setForm.stableHash(), hash)
    }

    // ═══ T2 · KD-2: the Alcedo LinearGradient mapping goldens ═══

    func testGradientAlcedoMappingBandGoldens() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 128, h = 128 // the SQUARE reference window (KD-2 derivation)
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)

        // Alcedo default: origin 0.5/0.5, normal (0,1), τ=0.2, start 1 →
        // end 0. Ours: anchor 0.5/0.5, rotation = atan2(0, 1) = 0,
        // compression = τ/(2√2) — the default档 consumes the Core single
        // source MaskGradientDefaults.compressionDefault directly.
        XCTAssertEqual(
            MaskGradientDefaults.compressionDefault,
            Float(0.2 / (2.0 * 2.0.squareRoot())),
            accuracy: 1e-7, "the single-source default encodes τ=0.2")
        for (tau, compression, label) in [
            (0.2, MaskGradientDefaults.compressionDefault, "alcedo default τ=0.2"),
            (1.0, Float(1.0 / (2.0 * 2.0.squareRoot())), "scale档 τ=1.0"),
        ] {
            let (values, gw, gh) = try await rasterize(
                MaskForm(kind: .gradient(GradientForm(
                    anchor: MaskPoint(x: 0.5, y: 0.5), rotationDegrees: 0,
                    compression: compression, state: .linear))),
                window: window, mapper: mapper, metal: metal)
            XCTAssertEqual(gw, w)
            XCTAssertEqual(gh, gh)

            // The Alcedo reference on the SAME pixels: nx = px/w,
            // ny = py/h; d = (n − origin)·n̂; value = 1 − clamp(d/τ + 0.5).
            assertPlane(
                values, w: w, h: h, mapper: mapper, window: window, aspect: 1,
                expect: { p in
                    let d = p.y - 0.5 // normal (0,1): d = ny − origin_y
                    let t = min(max(d / tau + 0.5, 0), 1)
                    return 1 - t
                }, gate: 1e-6, "gradient mapping [\(label)]")
        }
    }

    func testGradientDirectionSignAnchors() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 128, h = 128
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)

        // Direction sign: normal (0,1) ⇔ rotation 0 (the 1-side is
        // −n̂ = up): above the anchor the plane saturates to 1.
        let compression = MaskGradientDefaults.compressionDefault
        let (values, _, _) = try await rasterize(
            MaskForm(kind: .gradient(GradientForm(
                anchor: MaskPoint(x: 0.5, y: 0.5), rotationDegrees: 0,
                compression: compression, state: .linear))),
            window: window, mapper: mapper, metal: metal)
        let up = Double(values[(20 * w) + 64])    // y = 0.160 → d = −0.34
        let down = Double(values[(110 * w) + 64]) // y = 0.859 → d = +0.359
        XCTAssertEqual(up, 1.0, accuracy: 1e-6, "normal (0,1): 1-side is up")
        XCTAssertEqual(down, 0.0, accuracy: 1e-6, "normal (0,1): 0-side is down")

        // normal (1,0) ⇔ rotation = atan2(1, 0) = +90°: the 1-side is
        // −n̂ = left. (The plan's draft "−90" is corrected by this pin —
        // the atan2(nx, ny) formula in the mapping table is the authority;
        // deviation recorded in M2-7-1-DECISIONS.)
        let (values90, _, _) = try await rasterize(
            MaskForm(kind: .gradient(GradientForm(
                anchor: MaskPoint(x: 0.5, y: 0.5), rotationDegrees: 90,
                compression: compression, state: .linear))),
            window: window, mapper: mapper, metal: metal)
        let left = Double(values90[(64 * w) + 20])
        let right = Double(values90[(64 * w) + 110])
        XCTAssertEqual(left, 1.0, accuracy: 1e-6, "normal (1,0): 1-side is left")
        XCTAssertEqual(right, 0.0, accuracy: 1e-6, "normal (1,0): 0-side is right")

        // Full-plane parity for the +90 reading against the Alcedo linear
        // reference with normal (1,0).
        assertPlane(
            values90, w: w, h: h, mapper: mapper, window: window, aspect: 1,
            expect: { p in
                let d = p.x - 0.5
                let t = min(max(d / 0.2 + 0.5, 0), 1)
                return 1 - t
            }, gate: 1e-6, "gradient mapping [normal (1,0) ⇔ rot +90]")
    }

    func testGradientAnchorSideDirectionAnchor() async throws {
        // start 1 → end 0: the ANCHOR side saturates to 1, the far side to
        // 0 (the dt fixed direction the mapping table's fourth row pins).
        // Covered plane-wise above; this test pins the anchor VALUE itself:
        // value(anchor) = 0.5 in both formulations (d = 0 → t = 0.5).
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try makeMetal()
        let w = 129, h = 129 // odd → pixel 64 hits 0.5 exactly
        let window = ROI(x: 0, y: 0, width: w, height: h, scale: 1.0)
        let mapper = identityMapper(width: w, height: h)
        let compression = MaskGradientDefaults.compressionDefault
        let (values, _, _) = try await rasterize(
            MaskForm(kind: .gradient(GradientForm(
                anchor: MaskPoint(x: 0.5, y: 0.5), rotationDegrees: 0,
                compression: compression, state: .linear))),
            window: window, mapper: mapper, metal: metal)
        let atAnchor = Double(values[(64 * w) + 64])
        XCTAssertEqual(atAnchor, 0.5, accuracy: 1e-6, "value(origin) = 0.5 both sides")
    }
}
