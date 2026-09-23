@testable import LightamerCore
import LightamerIOP
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
}
