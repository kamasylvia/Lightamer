import LightamerIOP
import XCTest

/// ChannelMixerCommonTests (Plan 05-03-T1) — illuminant/CAT 泛化 CPU 单测。
///
/// 手算向量（Python 独立计算，见 05-03-DECISIONS T1）：
///   - D65 (0.3127, 0.3290) → XYZ (0.950456, 1.0, 1.089058)
///   - D50 (0.34567, 0.35850) → XYZ (0.964212, 1.0, 0.825188)
///   - 黑体 6500K → (0.31349411, 0.32366254)
///   - daylight 5500K → (0.33250163, 0.34760768)
///   - camera 路径未移植（F4-b：运行时 behaviour，需 live RAW + 管线 WB 通道）
final class ChannelMixerCommonTests: XCTestCase {

    private func assertClose(_ a: Double, _ b: Double, _ tol: Double = 1e-6, _ msg: String = "") {
        XCTAssertLessThan(abs(a - b), tol, "\(msg): \(a) vs \(b)")
    }

    func testXYToXYZHandVectors() {
        // D65 手算 (0.3127/0.3290, 1, (1−x−y)/y)。
        let d65 = ChannelMixerMath.xyToXYZ(x: 0.3127, y: 0.3290)
        assertClose(d65.x, 0.950456, 1e-5, "D65 X")
        assertClose(d65.y, 1.0, 1e-12, "D65 Y")
        assertClose(d65.z, 1.089058, 1e-5, "D65 Z")
        // D50 手算。
        let d50 = ChannelMixerMath.xyToXYZ(x: 0.34567, y: 0.35850)
        assertClose(d50.x, 0.964212, 1e-5, "D50 X")
        assertClose(d50.z, 0.825188, 1e-5, "D50 Z")
        XCTAssertGreaterThan(d65.x + d65.y + d65.z, 0)
    }

    func testCCTModelsHandVectors() {
        let (bbX, bbY) = ChannelMixerMath.cctToXYBlackbody(6500)
        assertClose(bbX, 0.31349411, 1e-7, "BB6500 x")
        assertClose(bbY, 0.32366254, 1e-7, "BB6500 y")
        let (dX, dY) = ChannelMixerMath.cctToXYDaylight(5500)
        assertClose(dX, 0.33250163, 1e-7, "D5500 x")
        assertClose(dY, 0.34760768, 1e-7, "D5500 y")
        // 越界 → (0,0)（dt fallthrough 语义）。
        XCTAssertEqual(ChannelMixerMath.cctToXYDaylight(3000).x, 0)
        XCTAssertEqual(ChannelMixerMath.cctToXYBlackbody(1000).x, 0)
        // Lee 反解 D65 ≈ 6500K。
        let cct = ChannelMixerMath.xyToCCT(x: 0.3127, y: 0.3290)
        XCTAssertLessThan(abs(cct - 6500), 500, "D65 CCT ≈ 6500, got \(cct)")
    }

    func testIlluminantToXYFamilies() {
        XCTAssertEqual(
            ChannelMixerMath.illuminantToXY(.pipe, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0)!.x,
            0.34567, accuracy: 1e-9)
        let e = ChannelMixerMath.illuminantToXY(.e, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0)!
        assertClose(e.x, 1.0 / 3.0, 1e-12, "E x")
        let a = ChannelMixerMath.illuminantToXY(.a, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0)!
        assertClose(a.x, 0.44757, 1e-9, "A x")
        let f3 = ChannelMixerMath.illuminantToXY(.f, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0)!
        assertClose(f3.x, 0.40910, 1e-9, "F3 x")
        assertClose(f3.y, 0.39430, 1e-9, "F3 y")
        let b5 = ChannelMixerMath.illuminantToXY(.led, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0)!
        assertClose(b5.x, 0.3118, 1e-9, "B5 x")
        // custom 直通；detect/camera → nil（v1 未移植）。
        let c = ChannelMixerMath.illuminantToXY(.custom, fluo: .f3, led: .b5, temperature: 5003, customX: 0.4, customY: 0.35)!
        assertClose(c.x, 0.4, 1e-12, "custom x")
        XCTAssertNil(ChannelMixerMath.illuminantToXY(.detectEdges, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0))
        XCTAssertNil(ChannelMixerMath.illuminantToXY(.detectSurfaces, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0))
        XCTAssertNil(ChannelMixerMath.illuminantToXY(.camera, fluo: .f3, led: .b5, temperature: 5003, customX: 0, customY: 0))
        // D/BB 走温度模型（非零即有效）。
        XCTAssertNotNil(ChannelMixerMath.illuminantToXY(.d, fluo: .f3, led: .b5, temperature: 5500, customX: 0, customY: 0))
        XCTAssertNotNil(ChannelMixerMath.illuminantToXY(.blackbody, fluo: .f3, led: .b5, temperature: 3200, customX: 0, customY: 0))
    }

    func testBradfordAndCAT16RoundTrip() {
        // 源 == 目标 → 单位阵：illuminant 取目标白本身时 adapt 为恒等。
        let d50lms = ChannelMixerMath.mul(
            ChannelMixerMath.xyzToBradfordLMS,
            SIMD3<Double>(0.96421199, 1.0, 0.82518828))
        let back = ChannelMixerMath.bradfordAdapt(
            d50lms, illuminant: d50lms, p: 1.0, full: true, target: .d50)
        assertClose(back.x, ChannelMixerMath.bradfordD50.x, 1e-9, "Bradford roundtrip L")
        assertClose(back.y, ChannelMixerMath.bradfordD50.y, 1e-9, "Bradford roundtrip M")
        assertClose(back.z, ChannelMixerMath.bradfordD50.z, 1e-9, "Bradford roundtrip S")
        // CAT16 同理。
        let c50 = ChannelMixerMath.mul(
            ChannelMixerMath.xyzToCAT16LMS,
            SIMD3<Double>(0.96421199, 1.0, 0.82518828))
        let cback = ChannelMixerMath.cat16Adapt(c50, illuminant: c50, target: .d50)
        assertClose(cback.x, ChannelMixerMath.cat16D50.x, 1e-9, "CAT16 roundtrip L")
        // XYZ⇄LMS 往返（任意 adaptation）。门限 5e-4 absolute（输入 ~0.5 ⇒
        // rel ~1e-3）：dt 只发布 4 位小数矩阵，B·B⁻¹ 自身残差已 ~1e-4
        //（Python 独立算出 [1][1] = 1.00010082），残差是常量精度界不是代码错。
        let xyz = SIMD3<Double>(0.5, 0.4, 0.3)
        for adapt: ChannelMixerAdaptation in [.linearBradford, .cat16, .xyz, .rgb] {
            let lms = ChannelMixerMath.xyzToLMS(xyz, adaptation: adapt)
            let rt = ChannelMixerMath.lmsToXYZ(lms, adaptation: adapt)
            assertClose(rt.x, xyz.x, 5e-4, "XYZ roundtrip \(adapt)")
            assertClose(rt.z, xyz.z, 5e-4, "XYZ roundtrip \(adapt)")
        }
        // 常量矩阵互逆（dt 头文件 4 位小数的舍入上限内）。
        let bb = ChannelMixerMath.mul(
            ChannelMixerMath.xyzToBradfordLMS, ChannelMixerMath.bradfordLMSToXYZ)
        assertClose(bb[0][0], 1.0, 2e-4, "B*Bi[0][0]")
        assertClose(bb[1][1], 1.0, 2e-4, "B*Bi[1][1]")
        let cc = ChannelMixerMath.mul(
            ChannelMixerMath.xyzToCAT16LMS, ChannelMixerMath.cat16LMSToXYZ)
        assertClose(cc[0][0], 1.0, 1e-5, "C*Ci[0][0]")
    }

    func testLumaChromaAndGamutSmoke() {
        // 中性灰经 lumaChroma（零 sat/lightness）≈ 恒等。
        let g = SIMD3<Double>(0.5, 0.5, 0.5)
        let out = ChannelMixerMath.lumaChroma(
            g, saturation: SIMD3<Double>(0, 0, 0),
            lightness: SIMD3<Double>(0, 0, 0), version: .v3)
        assertClose(out.x, 0.5, 1e-9, "grey identity")
        // 黑输入保持黑（dt else 分支）。
        let black = ChannelMixerMath.lumaChroma(
            .zero, saturation: SIMD3<Double>(0.3, 0.3, 0.3),
            lightness: SIMD3<Double>(0.1, 0.1, 0.1), version: .v3)
        XCTAssertEqual(black, .zero)
        // gamut mapping 在 D50 白点处不动。
        let w = ChannelMixerMath.xyToXYZ(x: 0.34567, y: 0.35850)
        let mapped = ChannelMixerMath.gamutMapping(w, compression: 1.0, clip: true)
        assertClose(mapped.x, w.x, 1e-6, "gamut white X")
        // v1/v2/v3 三版 saturation 分支全覆盖（非 NaN 即覆盖）。
        for v: ChannelMixerVersion in [.v1, .v2, .v3] {
            let r = ChannelMixerMath.lumaChroma(
                SIMD3<Double>(0.8, 0.2, 0.1),
                saturation: SIMD3<Double>(0.3, -0.2, 0.1),
                lightness: SIMD3<Double>(0.05, 0, -0.05), version: v)
            XCTAssertTrue(r.x.isFinite && r.y.isFinite && r.z.isFinite, "\(v) finite")
        }
    }
}
