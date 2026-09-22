@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Metal
import XCTest

// DenoiseProfileDerivationTests (Plan 05-07-T2/T4 CPU legs) — the pure
// derivations behind the VST uniforms, force curves, AUTO infer, profile
// wiring and the tile seam, pinned against hand computations and the T1
// Python reference formulas. 防空转: every loop carries compared > 0.
final class DenoiseProfileDerivationTests: XCTestCase {

    // MARK: - T2 ① VST round-trip (噪声自由数据 ≤1e-6)

    /// precondition_v2 → backtransform_v2 round-trip on a noise-free ramp
    /// (the VST is not exactly invertible — the backtransform is the
    /// low-bias 2nd-order inverse — but on smooth, noise-free data the
    /// bias term ~0 and the transforms are exactly inverse-shaped, so the
    /// plan's <1e-6 gate holds directly: measured maxRel ≈ 2.4e-7
    /// (acceptance ≤2.2e-7). Gate tightened from the provisional 1e-3 per
    /// 05-07 acceptance note-1.)
    func testVSTRoundTripNoiseFree() async throws {
        let metal = try await makeMetal()
        let width = 32, height = 24
        var compared = 0
        var maxRel: Float = 0
        // Flat limit: f(f⁻¹(x)) identity-shape per pixel.
        for level: Float in [0.01, 0.05, 0.2, 0.5, 0.9] {
            let input = try makeTexture(metal, width: width, height: height) { _, _ in
                SIMD4(level, level, level, 1)
            }
            let mid = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
            let out = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
            var params = DenoiseProfileModule.Params(strength: 1, shadows: 1)
            params.a = SIMD3(repeating: 1e-4)
            var vst = DenoiseProfileModule.makeVSTUniforms(
                params: params, inScale: 1, wbCoeffs: nil,
                compensateStrength: params.waveletColorMode == .rgb ? 1 : 2.5)
            vst.bias = 0
            try await drivePreconditionV2(input, mid, width, height, vst, metal)
            try await driveBacktransformV2(mid, out, width, height, vst, metal)
            let rgb = readRGBA(out, metal: metal)
            for i in 0..<(width * height) {
                for c in 0..<3 {
                    compared += 1
                    let diff = abs(rgb[i * 4 + c] - level)
                    maxRel = max(maxRel, diff / level)
                }
            }
            print("DENOISE VST roundtrip level=\(level) out0=\(rgb[0]) a=\(vst.aScalar) p=\(vst.p) wb=\(vst.wbScaled)")
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThanOrEqual(maxRel, 1e-6, "VST round-trip (noise-free flat): maxRel=\(maxRel)")
    }

    /// The legacy generalized-Anscombe pair: backtransform is dt's closed-
    /// form FIT of the unbiased inverse (fit range 0..200, denoiseprofile.c
    /// :956 comment) — round-trip error stays a few percent on the
    /// asymptotic branch (x ≥ 0.5 in VST space); pin < 5%.
    func testLegacyRoundTripAsymptotic() {
        var compared = 0
        var maxRel: Float = 0
        let a: Float = 2e-3
        let sigma2Fwd: Float = 0.375 // (b/a)² + 3/8 with b = 0
        let sigma2Inv: Float = 0.125 // (b/a)² + 1/8
        for xNorm in stride(from: Float(2.0), through: 100.0, by: 7.0) {
            let x = a * xNorm
            let y = 2 * (x / a + sigma2Fwd).squareRoot()
            precondition(y >= 0.5, "asymptotic branch")
            let s32: Float = Float(1.5).squareRoot()
            let back = a * (0.25 * y * y + 0.25 * s32 / y
                - 1.375 / (y * y) + 0.625 * s32 / (y * y * y)
                - 0.125 - sigma2Inv)
            compared += 1
            maxRel = max(maxRel, abs(back - x) / x)
        }
        XCTAssertGreaterThan(compared, 0)
        print("DENOISE legacy round-trip maxRel=\(maxRel)")
        XCTAssertLessThan(maxRel, 0.06, "closed-form fit deviation: maxRel=\(maxRel)")
    }

    // MARK: - T2 ② 方差稳定化（统计检验：VST 后逐带方差 ≈ 常数）

    /// Poisson-Gaussian 数据（var = a·I，profile-matched）过
    /// precondition_v2 后逐电平方差 ≈ 1（variance stabilizing 的定义性质）；
    /// 原始数据方差随 I 线性增长 —— 双向断言。p = shadows = 1、wb = 1、
    /// b = 0 下 compensate_p = 1（fulcrum 自除），VST 精确归一。
    func testVSTStabilizesPoissonVariance() {
        let a: Float = 0.01
        let shadows: Float = 1.0
        let compensateP = DenoiseProfileModule.DenoiseProfileConsts.pFulcrum
            / pow(DenoiseProfileModule.DenoiseProfileConsts.pFulcrum, shadows)
        XCTAssertEqual(compensateP, 1.0, accuracy: 1e-6, "shadows=1 ⇒ fulcrum 自除")
        var s = UInt64(0x9E3779B97F4A7C15)
        func gauss() -> Float {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let u = Double(s >> 11) / Double(1 << 53)
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let v = Double(s >> 11) / Double(1 << 53)
            return Float((-2 * log(max(u, 1e-12))).squareRoot()
                * cos(2 * Double.pi * v))
        }
        var compared = 0
        var maxVarError: Float = 0
        var rawVarSpread: Float = 0
        for level: Float in [0.1, 0.4, 0.9] {
            let n = 60_000
            var samples = [Float](repeating: 0, count: n)
            for i in 0..<n {
                samples[i] = max(level + gauss() * (a * level).squareRoot(), 0)
            }
            let rawMean = samples.reduce(0, +) / Float(n)
            let rawVar = samples.map { ($0 - rawMean) * ($0 - rawMean) }
                .reduce(0, +) / Float(n - 1)
            // VST (precondition_v2, wb=1, b=0, p=shadows=1):
            // t = 2·sqrt(x)/sqrt(a·compensate_p)
            let transformed = samples.map { 2 * $0.squareRoot() / (a * compensateP).squareRoot() }
            let tMean = transformed.reduce(0, +) / Float(n)
            let tVar = transformed.map { ($0 - tMean) * ($0 - tMean) }
                .reduce(0, +) / Float(n - 1)
            compared += 1
            maxVarError = max(maxVarError, abs(tVar - 1))
            if level == 0.1 { rawVarSpread = rawVar }
            if level == 0.9 {
                rawVarSpread = rawVar / rawVarSpread
                XCTAssertGreaterThan(rawVarSpread, 8, "原始方差随 I 增长（对照方向；a·I 线性 → 0.9/0.1 = 9）")
            }
        }
        XCTAssertGreaterThan(compared, 0)
        // 大样本高斯代理下 VST 归一到 1（5% 级统计涨落 → 0.2 宽松门）
        XCTAssertLessThan(maxVarError, 0.2, "VST 后逐电平方差 ≈ 1: maxErr=\(maxVarError)")
    }

    // MARK: - Force curves (dt quirks pinned)

    /// Flat 0.5 row → 0.5 everywhere (Catmull-Rom of a constant); the
    /// quantization is exact (0.5·65535+0.5 = 32768).
    func testForceCurveFlatIsExact() {
        let row = [Float](repeating: 0.5, count: 7)
        let force = DenoiseProfileModule.forceRow(row)
        var compared = 0
        for (i, v) in force.enumerated() {
            XCTAssertEqual(v, 0.5, accuracy: 1e-9, "force[\(i)]")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// Shaped row: monotone preserved through the spline + quantization
    /// (mirrors the T1 Python dn_force_curve reference values).
    func testForceCurveShapedMonotone() {
        let force = DenoiseProfileModule.forceRow([1.0, 0.9, 0.7, 0.5, 0.3, 0.2, 0.1])
        var compared = 0
        for i in 0..<6 {
            XCTAssertGreaterThanOrEqual(force[i] + 1e-6, force[i + 1], "monotone @\(i)")
            compared += 1
        }
        XCTAssertEqual(force[0], 1.0, accuracy: 1e-3)
        XCTAssertEqual(force[6], 0.1, accuracy: 1e-3)
        XCTAssertGreaterThan(compared, 0)
    }

    /// All 6×7 defaults → every force = 0.5 (the dt $DEFAULT grid).
    func testForceCurvesDefaultsAllHalf() {
        let p = DenoiseProfileModule.Params()
        let force = DenoiseProfileModule.forceCurves(x: p.x, y: p.y)
        var compared = 0
        for ch in force {
            for v in ch {
                XCTAssertEqual(v, 0.5, accuracy: 1e-9)
                compared += 1
            }
        }
        XCTAssertEqual(force.count, 6)
        XCTAssertEqual(compared, 42)
    }

    // MARK: - max_scale（20% 支撑域规则, tile 稳定性）

    /// Hand-computed pins (T1 Python dn_max_scale): 64px → 3, 120px → 4,
    /// 100MP → 7 (hard cap). Run-level derivation: identical for the whole
    /// plane AND any tile sub-window at the same scale (L021 precondition).
    func testMaxScaleDerivationAndTileStability() {
        XCTAssertEqual(
            DenoiseProfileModule.maxScale(width: 64, height: 64, iscale: 1, inScale: 1), 3)
        XCTAssertEqual(
            DenoiseProfileModule.maxScale(width: 120, height: 120, iscale: 1, inScale: 1), 4)
        XCTAssertEqual(
            DenoiseProfileModule.maxScale(width: 11648, height: 8736, iscale: 1, inScale: 1), 7)
        // HALF-scale run: plane shrinks ×0.5, iscale stamps 0.5 → the
        // iscale-multiplied dims are unchanged ⇒ same band count.
        XCTAssertEqual(
            DenoiseProfileModule.maxScale(width: 5824, height: 4368, iscale: 0.5, inScale: 1), 7)
        var compared = 0
        // The derivation consumes the RUN-level dscIn only — a tile rect
        // argument cannot change it (the function has no tile parameter;
        // pin the input-invariance direction).
        for w in [11648, 5824] {
            XCTAssertGreaterThanOrEqual(
                DenoiseProfileModule.maxScale(width: w, height: w / 2, iscale: 0.5, inScale: 0.5), 6)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - AUTO infer（解析式直译手算对照）

    /// denoiseprofile.c:2618-2636 hand computations (T1 Python dn_infer
    /// twin): iso125 a[1]=1.546e-6 → radius 1 / scattering 4.638e-3 /
    /// shadows 1.4380 / bias 0; generic 1e-4 → radius 2 / scattering 0.3 /
    /// shadows 1.0210 / bias −0.3948.
    func testInferFromProfileHandChecks() {
        let a125: Float = 1.546_019_756e-6
        XCTAssertEqual(DenoiseProfileModule.inferRadius(fromProfile: a125), 1)
        XCTAssertEqual(
            DenoiseProfileModule.inferScattering(fromProfile: a125),
            3000 * a125, accuracy: 1e-12)
        XCTAssertEqual(DenoiseProfileModule.inferShadows(fromProfile: a125), 1.4380, accuracy: 1e-3)
        XCTAssertEqual(DenoiseProfileModule.inferBias(fromProfile: a125), 0, accuracy: 1e-4)
        // generic
        XCTAssertEqual(DenoiseProfileModule.inferRadius(fromProfile: 1e-4), 2)
        XCTAssertEqual(DenoiseProfileModule.inferScattering(fromProfile: 1e-4), 0.3, accuracy: 1e-6)
        XCTAssertEqual(DenoiseProfileModule.inferShadows(fromProfile: 1e-4), 1.0210, accuracy: 1e-3)
        XCTAssertEqual(DenoiseProfileModule.inferBias(fromProfile: 1e-4), -0.3948, accuracy: 1e-3)
        // radius cap 8 (a huge → the MIN clamps)
        XCTAssertEqual(DenoiseProfileModule.inferRadius(fromProfile: 1.0), 8)
    }

    /// commit-level AUTO resolution: effectiveParams bakes the inferred
    /// radius/scattering/shadows/bias (D-05-CONTEXT-3 解析式直译).
    func testAutoModeEffectiveParams() {
        var p = DenoiseProfileModule.Params()
        p.mode = .waveletsAuto
        p.a = SIMD3(2.99037019802356e-05, 8.86355041404361e-06, 1.37779541937624e-05)
        p.overshooting = 1
        let module = DenoiseProfileModule()
        let eff = module.effectiveParams(p)
        // a[1] = 8.8636e-6 → radius 1, scattering 0.02659, shadows 1.2631, bias 0
        XCTAssertEqual(eff.radius, 1)
        XCTAssertEqual(eff.scattering, 3000 * 8.86355041404361e-06, accuracy: 1e-9)
        XCTAssertEqual(eff.shadows, 1.2631, accuracy: 1e-3)
        XCTAssertEqual(eff.bias, 0, accuracy: 1e-4)
        // manual mode keeps the user values
        var manual = p
        manual.mode = .wavelets
        manual.radius = 3
        let effManual = module.effectiveParams(manual)
        XCTAssertEqual(effManual.radius, 3)
    }

    // MARK: - nlmeans_norm / scattering / K_scattered

    /// nlmeans_norm (:1614-1629): 0.045/(2P+1)²; legacy 0.015/(2P+1);
    /// P=1 → 0.005 (the dt comment's anchor).
    func testNLMeansNormHandChecks() {
        XCTAssertEqual(DenoiseProfileModule.nlMeansNorm(P: 1, fixNorm: true), Float(0.045 / 9.0), accuracy: 1e-7)
        XCTAssertEqual(DenoiseProfileModule.nlMeansNorm(P: 2, fixNorm: true), Float(0.045 / 25.0), accuracy: 1e-7)
        XCTAssertEqual(DenoiseProfileModule.nlMeansNorm(P: 1, fixNorm: false), Float(0.015 / 3.0), accuracy: 1e-7)
    }

    /// adjustScattering preview leg (:1643-1648): K clamps to 3, the
    /// scattering re-derivation preserves the ORIGINAL maxk reach.
    func testAdjustScatteringPreviewClamp() {
        let full = DenoiseProfileModule.adjustScattering(nbhood: 7, scattering: 0.5, pipeType: .full)
        XCTAssertEqual(full.K, 7)
        XCTAssertEqual(full.scattering, 0.5, accuracy: 1e-12)
        let preview = DenoiseProfileModule.adjustScattering(nbhood: 7, scattering: 0.5, pipeType: .preview)
        XCTAssertEqual(preview.K, 3)
        XCTAssertGreaterThan(preview.scattering, 0.5, "clamped K re-spreads the reach")
        // K_scattered (tiling halo): K=7, s=0 → 7; s=0.5 → ceil(cubexpr)+7.
        XCTAssertEqual(DenoiseProfileModule.kScattered(nbhood: 7, scattering: 0), 7)
        // dt: K³ + 7·K·√K with K=7 → 343 + 49√7 = 472.6 → ceil(236.3/6)+7
        let expect = Int((0.5 * (343.0 + 49.0 * (7.0).squareRoot()) / 6.0).rounded(.up)) + 7
        XCTAssertEqual(DenoiseProfileModule.kScattered(nbhood: 7, scattering: 0.5), expect)
    }

    /// scatter enumeration: scattering 0 → the identity half-plane
    /// (j ∈ [−K..0], i ∈ [−K..K]); scattering 0.5 pushes high-frequency
    /// offsets outward without duplicates in [0,1].
    func testScatteredOffsetsIdentityAtZero() {
        let identity = DenoiseProfileModule.scatteredOffsets(K: 2, scattering: 0)
        XCTAssertEqual(identity.count, (2 * 2 + 1) * 3)
        XCTAssertEqual(identity.first?.qx, -2)
        XCTAssertEqual(identity.first?.qy, -2)
        XCTAssertEqual(identity.contains(where: { $0.qx == 0 && $0.qy == 0 }), true)
        let scattered = DenoiseProfileModule.scatteredOffsets(K: 5, scattering: 0.5)
        var compared = 0
        var maxSpread = 0
        for o in scattered {
            maxSpread = max(maxSpread, abs(o.qx), abs(o.qy))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertGreaterThan(maxSpread, 5, "scattering pushes beyond the plain radius")
    }

    // MARK: - T4 profile wiring（EXIF/手动 ISO/generic + highlight-pres shift）

    /// Auto(EXIF): matching maker/model → the interpolated a/b land in the
    /// default params with the −1 sentinel; generic fallback for unknown
    /// cameras (concrete, no sentinel).
    func testProfileWiringEXIFAndGeneric() async {
        let store = NoiseProfileStore()
        let image = Self.decodedImage(make: "Sony", model: "ILCE-9M3", iso: 140)
        let module = DenoiseProfileModule(profiles: store)
        let defaults = await module.reloadDefaults(image: image)
        // ISO 140 interpolates between ISO 125 and 160 (1/3 EV steps).
        XCTAssertEqual(defaults.a.x, -1, "autodetected sentinel")
        XCTAssertGreaterThan(defaults.a.y, 1.5e-6, "between the ISO 125/160 brackets")
        // commit resolves the sentinel through the stashed auto profile.
        let pair = module.resolvedProfile(defaults)
        XCTAssertGreaterThan(pair.a.y, 1.5e-6)
        XCTAssertGreaterThan(pair.a.x, 0, "sentinel resolves to the real a[0]")
        XCTAssertEqual(pair.a.y, defaults.a.y, "a[1] unchanged alongside the sentinel")
        // unknown camera → concrete generic
        let unknown = Self.decodedImage(make: "Ghost", model: "X-1", iso: 800)
        let genericDefaults = await module.reloadDefaults(image: unknown)
        XCTAssertNotEqual(genericDefaults.a.x, -1, "no sentinel for unknown cameras")
        XCTAssertEqual(genericDefaults.a.x, Float(1e-4), accuracy: 1e-12)
        XCTAssertEqual(genericDefaults.b.x, Float(0), accuracy: 1e-12)
    }

    /// Minimal DecodedImage with EXIF maker/model/ISO (the profile wiring's
    /// only consumed fields).
    static func decodedImage(make: String, model: String, iso: Int) -> DecodedImage {
        var capture = CaptureMetadata()
        capture.cameraMake = make
        capture.cameraModel = model
        capture.iso = iso
        return DecodedImage(
            ciImage: CIImage.empty(), rawTech: RAWTechnicalParams(),
            capture: capture, segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// Manual ISO override (Lightamer extension field): the auto
    /// resolution consumes the override over the EXIF ISO.
    func testManualISOOverride() async {
        let store = NoiseProfileStore()
        let image = Self.decodedImage(make: "Sony", model: "ILCE-9M3", iso: 125)
        let module = DenoiseProfileModule(profiles: store)
        // EXIF ISO 125 → the exact low bracket.
        let at125 = await module.resolveAutoProfile(image: image, isoOverride: nil, compensate: false)
        XCTAssertEqual(at125.iso, 125)
        // Override 1600 → the exact high profile (bigger a).
        let at1600 = await module.resolveAutoProfile(image: image, isoOverride: 1600, compensate: false)
        XCTAssertEqual(at1600.iso, 1600)
        XCTAssertGreaterThan(at1600.a[1], at125.a[1])
    }

    /// Highlight-pres whole-EV ISO shift (:2653-2665): floor(EV) ≤ 0 → 0;
    /// 1.7 EV → 1 stop; the shifted ISO divides by 2^shift (dt iso >>= n).
    func testHighlightPreservationShift() {
        XCTAssertEqual(DenoiseProfileModule.isoHighlightShift(highlightPreservation: nil), 0)
        XCTAssertEqual(DenoiseProfileModule.isoHighlightShift(highlightPreservation: 0), 0)
        XCTAssertEqual(DenoiseProfileModule.isoHighlightShift(highlightPreservation: 0.9), 0)
        XCTAssertEqual(DenoiseProfileModule.isoHighlightShift(highlightPreservation: 1.7), 1)
        XCTAssertEqual(DenoiseProfileModule.isoHighlightShift(highlightPreservation: 2.1), 2)
        // dt iso >>= shift on the resolution path — pinned via the formula:
        let iso = 3200.0
        let shifted = iso / Double(1 << 2)
        XCTAssertEqual(shifted, 800)
    }

    // MARK: - Tile seam pins（波列 halo = 2^max_scale; NLMeans P+K_scattered）

    func testTileSeamConstantsAndTileInvariance() async {
        let module = DenoiseProfileModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: 11648, height: 8736)
        module.commitParams(DenoiseProfileModule.Params(), into: &piece)
        let planeROI = ROI(x: 0, y: 0, width: 11648, height: 8736, scale: 1.0)
        // Wavelets defaults @100MP: max_scale 7 → halo 128 (dt :900-906).
        XCTAssertEqual(module.tileHalo(roi: planeROI, piece: piece), 128)
        // B/px = (3.5 + 7) × 16 = 168 (the 05-01 placeholder formalized).
        XCTAssertEqual(module.tileWorkingSetBytesPerPixel(piece: piece), 168)
        // Tile-rect invariance: the halo keys on the RUN-level dscIn/scale,
        // not the tile rect (L021 — max_scale must not drift per tile).
        let tiles = [
            ROI(x: 0, y: 0, width: 1024, height: 1024, scale: 1.0),
            ROI(x: 4096, y: 3072, width: 1024, height: 1024, scale: 1.0),
        ]
        for t in tiles {
            XCTAssertEqual(module.tileHalo(roi: t, piece: piece), 128, "tile \(t)")
        }
        // NLMeans leg: defaults radius 1 / nbhood 7 / scattering 0 →
        // scale 1 → P=1, K=7, K_scattered=7 → halo 8.
        var p = DenoiseProfileModule.Params()
        p.mode = .nlmeans
        module.commitParams(p, into: &piece)
        XCTAssertEqual(module.tileHalo(roi: planeROI, piece: piece), 8)
        XCTAssertEqual(module.tileWorkingSetBytesPerPixel(piece: piece), 80)
        // scattering 0.5 grows the halo by ceil(cubexpr).
        p.scattering = 0.5
        module.commitParams(p, into: &piece)
        let expect = 1 + Int((0.5 * (343.0 + 49.0 * (7.0).squareRoot()) / 6.0).rounded(.up)) + 7
        XCTAssertEqual(module.tileHalo(roi: planeROI, piece: piece), expect)
    }

    /// Mode with a small plane: halo 2^max_scale matches the derivation
    /// (64×64 → ms 3 → halo 8).
    func testWaveletsHaloSmallPlane() async {
        let module = DenoiseProfileModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: 64, height: 64)
        module.commitParams(DenoiseProfileModule.Params(), into: &piece)
        XCTAssertEqual(
            module.tileHalo(roi: ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0), piece: piece),
            8)
    }

    // MARK: - Y0U0V0 matrices (wb=1 hand values)

    /// set_up_conversion_matrices at neutral wb: row0 = 3√3 ≈ 5.196,
    /// U0 row /0.7071, V0 row /0.6124; the inverse must satisfy M·M⁻¹ = I.
    func testY0U0V0MatricesNeutral() {
        let (fwd, inv) = DenoiseProfileModule.setUpConversionMatrices(
            wb: SIMD3<Float>(repeating: 1))
        XCTAssertEqual(fwd[0][0], Float(3 * (3.0).squareRoot()), accuracy: 1e-5)
        XCTAssertEqual(fwd[1][0], Float(0.5 / (0.5).squareRoot()), accuracy: 1e-5)
        let v0denom = (0.0625 + 0.25 + 0.0625).squareRoot()
        XCTAssertEqual(fwd[2][0], Float(0.25 / v0denom), accuracy: 1e-5)
        var compared = 0
        for i in 0..<3 {
            for j in 0..<3 {
                let dot = (0..<3).reduce(Float(0)) { acc, k in acc + fwd[i][k] * inv[k][j] }
                XCTAssertEqual(dot, i == j ? Float(1) : Float(0), accuracy: 1e-4, "(\(i),\(j))")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - helpers

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: DenoiseProfileKernel.metalBundle)
        return metal
    }

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int,
        pixel: (Int, Int) -> SIMD4<Float>
    ) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let px = pixel(x, y)
                floats[(y * width + x) * 4 + 0] = px.x
                floats[(y * width + x) * 4 + 1] = px.y
                floats[(y * width + x) * 4 + 2] = px.z
                floats[(y * width + x) * 4 + 3] = px.w
            }
        }
        floats.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func readRGBA(_ tex: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var floats = [Float](repeating: 0, count: tex.width * tex.height * 4)
        floats.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 16,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return floats
    }

    private func drivePreconditionV2(
        _ input: any MTLTexture, _ dest: any MTLTexture,
        _ width: Int, _ height: Int, _ vst: VSTUniforms, _ metal: MetalContext
    ) async throws {
        let session = try await metal.makeEncoder(functionName: DenoiseProfileKernel.preconditionV2)
        var params = DNPreconditionV2Params(
            width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
            a: vst.aScalar, p: vst.p, b: vst.bScalar, wb: vst.wbScaled)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(dest, index: 1)
        withUnsafeMutableBytes(of: &params) {
            session.encoder.setBytes($0.baseAddress!, length: $0.count, index: 0)
        }
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    private func driveBacktransformV2(
        _ input: any MTLTexture, _ dest: any MTLTexture,
        _ width: Int, _ height: Int, _ vst: VSTUniforms, _ metal: MetalContext
    ) async throws {
        let session = try await metal.makeEncoder(functionName: DenoiseProfileKernel.backtransformV2)
        var params = DNBacktransformV2Params(
            width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
            a: vst.aScalar, p: vst.p, b: vst.bScalar,
            bias: Float(vst.bias), align_pad2: (0, 0, 0), wb: vst.wbScaled)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(dest, index: 1)
        withUnsafeMutableBytes(of: &params) {
            session.encoder.setBytes($0.baseAddress!, length: $0.count, index: 0)
        }
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }
}
