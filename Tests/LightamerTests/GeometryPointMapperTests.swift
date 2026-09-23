@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-03 T2 — the mask point mapper (D-06-CONTEXT-7 content
/// anchoring): per-module segments, reverse-order composition, roundtrip
/// precision (<0.1 px gate), identity passthrough for neutral/pointwise
/// modules, and the liquify identity reservation.
///
/// Every precision case is a REAL comparison loop over a point grid with a
/// `compared > 0` guard (L020 ③); the roundtrip errors are logged so the
/// numbers land in the test output (the plan's precision table).
final class GeometryPointMapperTests: XCTestCase {

    private let frame = SIMD2<Double>(6000, 4000) // decode frame, plane px

    private func roundtripError(
        _ mapper: GeometryPointMapper, grid n: Int = 9
    ) -> (maxPx: Double, compared: Int, maxAt: SIMD2<Double>) {
        var maxErr = 0.0
        var compared = 0
        var maxAt = SIMD2<Double>.zero
        for j in 0..<n {
            for i in 0..<n {
                let p = SIMD2(
                    Double(i) / Double(n - 1) * frame.x,
                    Double(j) / Double(n - 1) * frame.y)
                let back = mapper.inversePixel(mapper.forwardPixel(p))
                let d = back - p
                let err = (d.x * d.x + d.y * d.y).squareRoot()
                if err > maxErr { maxErr = err; maxAt = p }
                compared += 1
            }
        }
        return (maxErr, compared, maxAt)
    }

    private func assertRoundtrip(
        _ mapper: GeometryPointMapper, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = roundtripError(mapper)
        XCTAssertGreaterThan(result.compared, 0, "\(label): 防空转 guard", file: file, line: line)
        XCTAssertLessThan(
            result.maxPx, 0.1,
            "\(label): roundtrip \(result.maxPx) px at \(result.maxAt) (gate 0.1 px)",
            file: file, line: line)
        print("[06-03 T2] \(label): roundtrip max \(result.maxPx) px over \(result.compared) pts")
    }

    // ── identity ──

    func testEmptyChainIsIdentity() {
        let mapper = GeometryPointMapper.compose(boxes: [], frameSize: frame)
        XCTAssertTrue(mapper.segments.isEmpty)
        XCTAssertEqual(mapper.outputSize, frame)
        let p = SIMD2(1234.5, 2345.5)
        XCTAssertEqual(mapper.forwardPixel(p), p)
        XCTAssertEqual(mapper.inversePixel(p), p)
        let n = SIMD2(0.37, 0.61)
        XCTAssertEqual(mapper.forward(normalized: n), n)
        XCTAssertEqual(mapper.inverse(normalized: n), n)
    }

    /// Pointwise modules and neutral geometry are IDENTITY (omission, not
    /// a special case) — the common base chain maps masks 1:1.
    func testNeutralChainIsIdentity() {
        let gain = ModuleBox(module: TestGainModule())
        gain.setParams(TestGainModule.Params(gain: 2.0))
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params()) // full-frame = neutral
        let lens = ModuleBox(module: LensModule())
        lens.setParams(LensModule.Params(source: .manual)) // all-zero = neutral
        let ashift = ModuleBox(module: AshiftModule())
        ashift.setParams(AshiftModule.Params()) // neutral
        let mapper = GeometryPointMapper.compose(
            boxes: [gain, crop, lens, ashift], frameSize: frame)
        XCTAssertTrue(mapper.segments.isEmpty, "neutral/pointwise modules contribute NO segments")
        XCTAssertEqual(mapper.outputSize, frame)
    }

    // ── crop ──

    func testCropSegmentRoundtripAndCenterInvariance() {
        // Params are Float — derive every expectation from the STORED
        // values (Double(Float(0.2)) ≈ 0.20000000298), not the literals.
        let params = CropModule.Params(left: 0.25, top: 0.2, right: 0.8, bottom: 0.9)
        let crop = ModuleBox(module: CropModule())
        crop.setParams(params)
        let mapper = GeometryPointMapper.compose(boxes: [crop], frameSize: frame)
        guard case let .affine(a, _, outSize)? = mapper.segments.first else {
            return XCTFail("crop must produce an affine segment")
        }
        // Forward: p' = p − origin; output frame = span × frame.
        let origin = SIMD2(Double(params.left) * frame.x, Double(params.top) * frame.y)
        let span = SIMD2(Double(params.right - params.left) * frame.x,
                         Double(params.bottom - params.top) * frame.y)
        XCTAssertEqual(outSize.x, span.x, accuracy: 1e-9)
        XCTAssertEqual(outSize.y, span.y, accuracy: 1e-9)
        let p = SIMD2(3000.0, 2000.0)
        let q = mapper.forwardPixel(p)
        XCTAssertEqual(q.x, p.x - origin.x, accuracy: 1e-9)
        XCTAssertEqual(q.y, p.y - origin.y, accuracy: 1e-9)
        // The crop CENTER maps to the composite center (fractions are
        // relative to the same frame — the content anchor's base case).
        let center = SIMD2(span.x / 2 + origin.x, span.y / 2 + origin.y)
        let qCenter = mapper.forwardPixel(center)
        XCTAssertEqual(qCenter.x / outSize.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(qCenter.y / outSize.y, 0.5, accuracy: 1e-9)
        XCTAssertFalse(a.a00 == 0) // real transform guard (compared > 0 spirit)
        assertRoundtrip(mapper, "crop 55%x70%")
    }

    // ── flip ──

    func testFlipSegmentMatchesModuleRemap() {
        let flip = ModuleBox(module: FlipModule())
        flip.setParams(FlipModule.Params(orientation: .transpose))
        let mapper = GeometryPointMapper.compose(boxes: [flip], frameSize: frame)
        guard case let .affine(_, _, outSize)? = mapper.segments.first else {
            return XCTFail("flip must produce an affine segment")
        }
        XCTAssertEqual(outSize, SIMD2(frame.y, frame.x), "transpose swaps the frame")
        // Continuous forward must agree with the module's INTEGER remap on
        // pixel centers (center (i+0.5) → center (out−1−i) conventions).
        for (i, j) in [(0, 0), (3, 7), (5999, 3999)] {
            let out = mapper.forwardPixel(SIMD2(Double(i) + 0.5, Double(j) + 0.5))
            let expect = FlipOrientation.outputXY(
                x: i, y: j, w: Int(frame.x), h: Int(frame.y), orientation: .transpose)
            XCTAssertEqual(out.x, Double(expect.x) + 0.5, accuracy: 1e-9)
            XCTAssertEqual(out.y, Double(expect.y) + 0.5, accuracy: 1e-9)
        }
        assertRoundtrip(mapper, "flip transpose")
    }

    func testFlipRot180Roundtrip() {
        let flip = ModuleBox(module: FlipModule())
        flip.setParams(FlipModule.Params(orientation: .rot180))
        let mapper = GeometryPointMapper.compose(boxes: [flip], frameSize: frame)
        assertRoundtrip(mapper, "flip rot180")
    }

    // ── ashift ──

    func testAshiftSegmentRoundtripAndModuleAgreement() {
        let ashift = ModuleBox(module: AshiftModule())
        ashift.setParams(AshiftModule.Params(rotation: 5.0, shear: 0.02))
        let mapper = GeometryPointMapper.compose(boxes: [ashift], frameSize: frame)
        guard case let .homography(h, _, clip, _, outSpan)? = mapper.segments.first else {
            return XCTFail("ashift must produce a homography segment")
        }
        // Forward must equal the module's own ROI-forward math: the
        // input-frame center through H minus clip, in the output span.
        let c = frame / 2
        let q = mapper.forwardPixel(c)
        XCTAssertEqual(q.x, h.project(c.x, c.y).x - clip.x, accuracy: 1e-9)
        XCTAssertEqual(q.y, h.project(c.x, c.y).y - clip.y, accuracy: 1e-9)
        XCTAssertGreaterThan(outSpan.x, 0)
        assertRoundtrip(mapper, "ashift 5° + shear")
    }

    // ── lens ──

    func testLensSegmentRoundtripManualCoefficients() {
        let lens = ModuleBox(module: LensModule())
        lens.setParams(LensModule.Params(
            distortionK1: -0.2, distortionK2: 0.05, source: .manual))
        let mapper = GeometryPointMapper.compose(boxes: [lens], frameSize: frame)
        guard case let .radial(k1, k2, size)? = mapper.segments.first else {
            return XCTFail("lens must produce a radial segment")
        }
        // Params are Float — Float-precision equality (1e-6), not 1e-12.
        XCTAssertEqual(k1, -0.2, accuracy: 1e-6)
        XCTAssertEqual(k2, 0.05, accuracy: 1e-6)
        XCTAssertEqual(size, frame)
        // Center invariant (radial maps the center to itself).
        let q = mapper.forwardPixel(frame / 2)
        XCTAssertEqual(q, frame / 2)
        assertRoundtrip(mapper, "lens k1=−0.2 k2=0.05")
    }

    /// Extreme-distortion档单独测（plan T2.3）：the roundtrip is ITERATIVE
    /// here — the measured number IS the D-06-CONTEXT-7 evidence. If this
    /// gate ever fails, the answer is a RECORDED downgrade evaluation
    /// (never a silent switch to composite anchoring).
    func testLensExtremeDistortionRoundtripRecorded() {
        let lens = ModuleBox(module: LensModule())
        lens.setParams(LensModule.Params(
            distortionK1: -0.35, distortionK2: 0.10, source: .manual))
        let mapper = GeometryPointMapper.compose(boxes: [lens], frameSize: frame)
        let result = roundtripError(mapper)
        XCTAssertGreaterThan(result.compared, 0, "防空转 guard")
        XCTAssertLessThan(result.maxPx, 0.1,
                          "extreme lens roundtrip \(result.maxPx) px — D-06-CONTEXT-7 downgrade evaluation REQUIRED before any anchoring change")
        print("[06-03 T2] lens EXTREME k1=−0.35 k2=0.10: roundtrip max \(result.maxPx) px over \(result.compared) pts (evidence recorded)")
    }

    // ── composite chain (reverse-order composition) ──

    /// The plan's typical parameter set: crop 50% + rotate 5° + lens
    /// (manual default档) — the full reverse-order composition.
    func testCompositeChainRoundtrip() {
        let lens = ModuleBox(module: LensModule())
        lens.setParams(LensModule.Params(
            distortionK1: -0.15, distortionK2: 0.04, source: .manual))
        let ashift = ModuleBox(module: AshiftModule())
        ashift.setParams(AshiftModule.Params(rotation: 5.0))
        let flip = ModuleBox(module: FlipModule())
        flip.setParams(FlipModule.Params(orientation: .rotCCW90))
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        // A pointwise module in the middle must be transparent.
        let gain = ModuleBox(module: TestGainModule())
        gain.setParams(TestGainModule.Params(gain: 1.3))

        let mapper = GeometryPointMapper.compose(
            boxes: [crop, gain, flip, ashift, lens], frameSize: frame)
        XCTAssertEqual(mapper.segments.count, 4, "pointwise gain contributes no segment")
        assertRoundtrip(mapper, "chain lens→ashift→flip→crop (50% + 5° + rot90 + lens)")

        // Segment ORDER must be chain order (lens first): compose sorts.
        if case .radial = mapper.segments[0] {} else {
            XCTFail("first segment must be lens (v50 13.0)")
        }
        if case .affine = mapper.segments[3] {} else {
            XCTFail("last segment must be crop (v50 24.5)")
        }
    }

    /// Disabled geometry must not contribute (enabled=false = not in the
    /// chain for the mapper — same rule as the pipe walk).
    func testDisabledModulesContributeNothing() {
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        crop.enabled = false
        let flip = ModuleBox(module: FlipModule())
        flip.setParams(FlipModule.Params(orientation: .rot180))
        flip.enabled = false
        let mapper = GeometryPointMapper.compose(boxes: [crop, flip], frameSize: frame)
        XCTAssertTrue(mapper.segments.isEmpty)
        XCTAssertEqual(mapper.outputSize, frame)
    }


    // ═══ Plan 06-06 T3: the liquify segment (the 6-3 reservation realized) ═══

    /// A live (non-empty) liquify contributes ONE displacement segment; the
    /// roundtrip gate is the plan's 0.5 px (the field inverse-sampling tier —
    /// DECISIONS D-06-06-T3-1 records why it is wider than the 0.1 px of the
    /// exact geometry modules).
    func testLiquifySegmentRoundtrip() {
        let liquify = ModuleBox(module: LiquifyModule())
        liquify.setParams(LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.51, 0.5),
                radius: SIMD2(0.6, 0.5))
        ]))
        let mapper = GeometryPointMapper.compose(boxes: [liquify], frameSize: frame)
        XCTAssertEqual(mapper.segments.count, 1, "live liquify contributes one segment")
        guard case .liquify = mapper.segments[0] else {
            return XCTFail("segment must be .liquify")
        }
        XCTAssertEqual(mapper.outputSize, frame, "liquify preserves the frame")
        // The stamp center is a fixed point (F = 0 there).
        let center = mapper.forwardPixel(frame / 2)
        XCTAssertEqual(center.x, frame.x / 2, accuracy: 1e-6)
        XCTAssertEqual(center.y, frame.y / 2, accuracy: 1e-6)
        // The 0.5 px roundtrip gate over a dense grid (compared > 0).
        var maxErr = 0.0
        var compared = 0
        for j in 0..<21 {
            for i in 0..<21 {
                let p = SIMD2(
                    Double(i) / 20.0 * frame.x, Double(j) / 20.0 * frame.y)
                let back = mapper.inversePixel(mapper.forwardPixel(p))
                let d = back - p
                maxErr = max(maxErr, (d.x * d.x + d.y * d.y).squareRoot())
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
        XCTAssertLessThan(maxErr, 0.5, "liquify roundtrip \(maxErr) px (gate 0.5 px)")
        print("[06-06 T3] liquify roundtrip: max \(maxErr) px over \(compared) pts (gate 0.5)")
    }

    /// The full geometry chain WITH liquify at its v50 slot: lens(13) →
    /// ashift(15) → flip(16) → liquify(18) → crop(24.5) — five segments,
    /// roundtrip < 0.5 px.
    func testLiquifyChainRoundtrip() {
        // k2 0.04 keeps Rd(u) = u(1 + k1u² + k2u⁴) solvable at the corner
        // radii (k2 0 with k1 −0.15 has NO root beyond u ≈ 0.994 — the
        // lens-forward Newton legitimately diverges there; not a liquify
        // concern, learned live and pinned here).
        let lens = ModuleBox(module: LensModule())
        lens.setParams(LensModule.Params(
            distortionK1: -0.15, distortionK2: 0.04, source: .manual))
        let ashift = ModuleBox(module: AshiftModule())
        ashift.setParams(AshiftModule.Params(rotation: 5.0))
        let flip = ModuleBox(module: FlipModule())
        flip.setParams(FlipModule.Params(orientation: .rotCCW90))
        let liquify = ModuleBox(module: LiquifyModule())
        liquify.setParams(LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.51, 0.5),
                radius: SIMD2(0.6, 0.5))
        ]))
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        let mapper = GeometryPointMapper.compose(
            boxes: [crop, flip, liquify, ashift, lens], frameSize: frame)
        XCTAssertEqual(mapper.segments.count, 5)
        guard case .liquify = mapper.segments[3] else {
            return XCTFail("segment[3] must be liquify (v50 18.0, between flip and crop)")
        }
        if case .affine = mapper.segments[4] {} else {
            XCTFail("segment[4] must be crop")
        }
        var maxErr = 0.0
        var compared = 0
        for j in 0..<15 {
            for i in 0..<15 {
                let p = SIMD2(
                    Double(i) / 14.0 * frame.x, Double(j) / 14.0 * frame.y)
                let back = mapper.inversePixel(mapper.forwardPixel(p))
                let d = back - p
                maxErr = max(maxErr, (d.x * d.x + d.y * d.y).squareRoot())
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
        XCTAssertLessThan(maxErr, 0.5, "chain roundtrip \(maxErr) px (gate 0.5)")
        print("[06-06 T3] chain roundtrip: max \(maxErr) px over \(compared) pts")
    }

    /// An EMPTY liquify contributes NO segment (the reservation's identity
    /// semantics — the normal path).
    func testEmptyLiquifyIsNoSegment() {
        let liquify = ModuleBox(module: LiquifyModule())
        liquify.setParams(LiquifyModule.Params())
        let mapper = GeometryPointMapper.compose(boxes: [liquify], frameSize: frame)
        XCTAssertTrue(mapper.segments.isEmpty, "empty paths = no segment")
        XCTAssertEqual(mapper.outputSize, frame)
    }

    /// The staged GPU decomposition: with liquify + crop the `post` stage
    /// carries crop⁻¹ and `pre` the flip/ashift part; the staged pair must
    /// reproduce the exact per-segment inversePixel walk (the mask raster
    /// kernel consumes exactly this form).
    func testStagedDecompositionMatchesSegmentWalk() throws {
        let ashift = ModuleBox(module: AshiftModule())
        ashift.setParams(AshiftModule.Params(rotation: -7.5, lensShiftV: 0.3))
        let flip = ModuleBox(module: FlipModule())
        flip.setParams(FlipModule.Params(orientation: .rotCW90))
        let liquify = ModuleBox(module: LiquifyModule())
        liquify.setParams(LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.51, 0.5),
                radius: SIMD2(0.6, 0.5))
        ]))
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params(left: 0.1, top: 0.2, right: 0.9, bottom: 0.85))
        let mapper = GeometryPointMapper.compose(
            boxes: [ashift, flip, liquify, crop], frameSize: frame)
        let staged = mapper.stagedInverseComposite
        guard case .liquify(let field)? = mapper.segments.first(where: {
            if case .liquify = $0 { return true } else { return false }
        }) else { return XCTFail("expected a liquify segment") }
        XCTAssertNotNil(staged.field)


        var compared = 0
        for j in 0..<9 {
            for i in 0..<9 {
                // composite normalized → decode normalized through the
                // STAGES (post → liquify grid → pre; no lens in this chain)
                let qn = SIMD2(Double(i) / 8.0, Double(j) / 8.0)
                let qa = staged.post.applied(qn.x, qn.y)
                let midn = SIMD2(qa.x / qa.w, qa.y / qa.w)
                let midPx = SIMD2(midn.x * staged.mid.x, midn.y * staged.mid.y)
                let warped = midPx + field.sampleForward(midPx)
                let warpedN = SIMD2(warped.x / staged.mid.x, warped.y / staged.mid.y)
                let pb = staged.pre.applied(warpedN.x, warpedN.y)
                let decoded = SIMD2(pb.x / pb.w * frame.x, pb.y / pb.w * frame.y)
                let walked = mapper.inversePixel(SIMD2(
                    qn.x * mapper.outputSize.x, qn.y * mapper.outputSize.y))
                let dd = decoded - walked
                let err = (dd.x * dd.x + dd.y * dd.y).squareRoot()
                XCTAssertLessThan(err, 1e-9, "staged walk drift at (\(i),\(j))")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
    }

    // ── GPU uniform composite agreement (the rasterizer's math source) ──

    /// `projectiveInverseComposite` (crop∘flip∘ashift as ONE normalized
    /// 3×3) must agree with the per-segment inversePixel walk to float64
    /// machine precision — the MSL kernel will consume exactly this form.
    func testProjectiveCompositeMatchesSegmentWalk() {
        let ashift = ModuleBox(module: AshiftModule())
        ashift.setParams(AshiftModule.Params(rotation: -7.5, lensShiftV: 0.3))
        let flip = ModuleBox(module: FlipModule())
        flip.setParams(FlipModule.Params(orientation: .rotCW90))
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params(left: 0.1, top: 0.2, right: 0.9, bottom: 0.85))
        let mapper = GeometryPointMapper.compose(
            boxes: [ashift, flip, crop], frameSize: frame)
        let m = mapper.projectiveInverseComposite
        var compared = 0
        for j in 0..<7 {
            for i in 0..<7 {
                // Composite-normalized point → pre-lens normalized via the
                // matrix; must equal the walk with radial segments absent.
                let qn = SIMD2(Double(i) / 6.0, Double(j) / 6.0)
                let qpx = SIMD2(qn.x * mapper.outputSize.x, qn.y * mapper.outputSize.y)
                // Remove nothing — no lens in this chain, so walk and
                // matrix must agree exactly on the FULL inverse.
                let walked = mapper.inversePixel(qpx)
                let walkedN = SIMD2(walked.x / frame.x, walked.y / frame.y)
                let proj = m.applied(qn.x, qn.y)
                let projN = SIMD2(proj.x / proj.w, proj.y / proj.w)
                let dd = projN - walkedN
                let err = (dd.x * dd.x + dd.y * dd.y).squareRoot()
                XCTAssertLessThan(err, 1e-12, "matrix composite drift at (\(i),\(j))")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
    }

    /// 蒙版内容锚定端到端 (D-06-CONTEXT-7, Plan 06-06-T3): a drawn ellipse
    /// anchored to CONTENT — rasterized through the REAL GPU raster path —
    /// must hold the same value at the same content point whether or not a
    /// liquify warp displaces that content. The two planes must also differ
    /// (防空转: the liquify leg really moves the mask pattern).
    func testLiquifyMaskContentAnchorEndToEnd() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        let frame = SIMD2<Double>(320, 240)
        let crop = ModuleBox(module: CropModule())
        crop.setParams(CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75))
        let liquify = ModuleBox(module: LiquifyModule())
        // The stamp field must COVER the ellipse rim (the mask's only
        // gradient band — rim at ~140 decode px from center; radius
        // 0.5·320 = 160 px ✓; |F| at the rim ≈ 2.5 px) — a field smaller
        // than the rim displaces a CONSTANT region and the content anchor
        // degenerates (learned live, pinned by the maxPlaneDiff guard).
        liquify.setParams(LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.6, 0.5),
                radius: SIMD2(1.0, 0.5))
        ]))
        let mapperA = GeometryPointMapper.compose(boxes: [crop], frameSize: frame)
        let mapperB = GeometryPointMapper.compose(boxes: [crop, liquify], frameSize: frame)
        // CPU-leg probe: the two inverse walks must disagree at the same
        // window pixel (the liquify inverse displaces the decode point).

        // Ellipse centered on the stamp center, sized so the probe point
        // sits on the mid-feather band (a small anchor error moves the value
        // measurably).
        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5),
                radiusX: 0.2, radiusY: 0.2,
                rotationDegrees: 0, border: 0.3))),
        ]))
        let outW = Int(mapperA.outputSize.x), outH = Int(mapperA.outputSize.y)
        let window = ROI(x: 0, y: 0, width: outW, height: outH, scale: 1.0)

        func rasterize(_ mapper: GeometryPointMapper) async throws -> [Float] {
            let cache = PipeCache()
            let (plane, _) = try await DrawnMaskRasterizer.plane(
                spec: spec, layerOpacity: 1.0, window: window, mapper: mapper,
                metal: metal, cache: cache, imageID: UUID(), pipeType: .preview,
                layerID: UUID(), rowBands: 1)
            let fence = metal.commandQueue.makeCommandBuffer()
            fence?.commit()
            await fence?.completed() // L014 — drain BEFORE the readback
            var values = [Float](repeating: -1, count: plane.width * plane.height)
            values.withUnsafeMutableBytes {
                plane.getBytes(
                    $0.baseAddress!, bytesPerRow: plane.width * 4,
                    from: MTLRegionMake2D(0, 0, plane.width, plane.height),
                    mipmapLevel: 0)
            }
            return values
        }

        let planeA = try await rasterize(mapperA)
        let planeB = try await rasterize(mapperB)
        XCTAssertEqual(planeA.count, planeB.count)

        // Content preservation over a GRID of content points: each decode
        // point sampled through its own mapper's forward leg must hold the
        // same mask value with and without the liquify warp. Tolerance
        // 0.05 = the 0.5 px roundtrip gate × the feather slope (~1/19 px).
        var maxAnchor = 0.0
        var informative = 0
        for j in 0..<15 {
            for i in 0..<15 {
                let pNorm = SIMD2<Double>(Double(i) / 14.0, Double(j) / 14.0)
                let p = SIMD2(pNorm.x * frame.x, pNorm.y * frame.y)
                let wA = mapperA.forwardPixel(p)
                let wB = mapperB.forwardPixel(p)
                // Only points whose window positions land INSIDE the plane
                // (frame-edge points clamp to edge pixels — meaningless).
                func inside(_ w: SIMD2<Double>) -> Bool {
                    w.x >= 0 && w.y >= 0 && w.x < Double(outW) && w.y < Double(outH)
                }
                guard inside(wA), inside(wB) else { continue }
                let vA = Double(planeA[Int(wA.y) * outW + Int(wA.x)])
                let vB = Double(planeB[Int(wB.y) * outW + Int(wB.x)])
                guard max(vA, vB) > 0.001 else { continue }  // outside the mask
                informative += 1
                maxAnchor = max(maxAnchor, abs(vA - vB))
            }
        }
        XCTAssertGreaterThan(informative, 20, "防空转: grid must cross the mask")
        XCTAssertLessThan(
            maxAnchor, 0.05,
            "content anchor: max value drift \(maxAnchor) over \(informative) content pts")
        // 防空转: the liquify warp really moved the mask pattern.
        var maxDiff = 0.0
        for (a, b) in zip(planeA, planeB) { maxDiff = max(maxDiff, abs(Double(a - b))) }
        XCTAssertGreaterThan(maxDiff, 0.03, "the warp must displace the mask plane")
        print("[06-06 T3] content anchor: maxDrift=\(maxAnchor) over \(informative) pts, "
            + "maxPlaneDiff=\(maxDiff)")
    }
}
