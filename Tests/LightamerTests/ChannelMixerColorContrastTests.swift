import LightamerCore
import LightamerIOP
import XCTest

/// ChannelMixerColorContrastTests (Plan 05-03-T3) — legacy mixer 4-mode
/// derivation + CPU reference smoke + colorcontrast reference + V50 slots.
final class ChannelMixerColorContrastTests: XCTestCase {

    // MARK: - Legacy mixer commit derivation

    func testDefaultParamsSelectRGBIdentity() {
        let d = ChannelMixerModule.derive(ChannelMixerModule.Params())
        XCTAssertEqual(d.mode, .rgb)
        XCTAssertEqual(d.rgbMatrix, [1, 0, 0, 0, 1, 0, 0, 0, 1])
    }

    func testV1ForcesHSLV1() {
        var p = ChannelMixerModule.Params()
        p.algorithm = .v1
        XCTAssertEqual(ChannelMixerModule.derive(p).mode, .hslV1)
    }

    func testHSLMixSelectsV2() {
        var p = ChannelMixerModule.Params()
        p.red[0] = 0.5
        XCTAssertEqual(ChannelMixerModule.derive(p).mode, .hslV2)
    }

    func testGrayMixFoldsRows() {
        var p = ChannelMixerModule.Params()
        p.red[6] = 0.3; p.green[6] = 0.5; p.blue[6] = 0.2
        let d = ChannelMixerModule.derive(p)
        XCTAssertEqual(d.mode, .gray)
        // Every RGB row becomes the gray-mixed row (dt :536-545).
        XCTAssertEqual(d.rgbMatrix[0], d.rgbMatrix[3], accuracy: 1e-9)
        XCTAssertEqual(d.rgbMatrix[0], d.rgbMatrix[6], accuracy: 1e-9)
    }

    // MARK: - Legacy CPU reference smoke (all 4 modes finite)

    func testReferenceAllModesFinite() {
        let probes = [
            SIMD3<Double>(0.8, 0.2, 0.1),
            SIMD3<Double>(0.25, 0.25, 0.25),
            SIMD3<Double>(0.0, 0.5, 1.0),
        ]
        var pRGB = ChannelMixerModule.Params()
        pRGB.red = [0, 0, 0, 1.1, -0.1, 0.2, 0]
        let modes: [ChannelMixerModule.Params] = [
            pRGB,
            { var q = ChannelMixerModule.Params()
              q.red[6] = 0.3; q.green[6] = 0.5; q.blue[6] = 0.2; return q }(),
            { var q = ChannelMixerModule.Params()
              q.algorithm = .v1; q.red[0] = 0.5; return q }(),
            { var q = ChannelMixerModule.Params()
              q.red[1] = 0.5; return q }(),
        ]
        XCTAssertEqual(modes.map { ChannelMixerModule.derive($0).mode },
                       [.rgb, .gray, .hslV1, .hslV2])
        var compared = 0
        for m in modes {
            let d = ChannelMixerModule.derive(m)
            for probe in probes {
                let out = ChannelMixerModule.reference(probe, derived: d)
                XCTAssertTrue(out.x.isFinite && out.y.isFinite && out.z.isFinite)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0)
    }

    func testHSLRoundTripIdentity() {
        // rgb→hsl→rgb round-trips the primaries through the reference.
        for rgb in [SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0),
                    SIMD3<Double>(0, 0, 1), SIMD3<Double>(0.5, 0.5, 0.5)] {
            let (h, s, l) = ChannelMixerModule.rgbToHSL(rgb.x, rgb.y, rgb.z)
            let (r, g, b) = ChannelMixerModule.hslToRGB(h: h, s: s, l: l)
            XCTAssertLessThan(abs(r - rgb.x) + abs(g - rgb.y) + abs(b - rgb.z), 1e-9)
        }
    }

    // MARK: - ColorContrast reference

    func testColorContrastDefaultsIdentity() {
        let p = ColorContrastModule.Params()
        for lab in [SIMD3<Double>(50, 10, -20), SIMD3<Double>(80, 0, 0)] {
            let out = ColorContrastModule.reference(lab: lab, params: p)
            XCTAssertEqual(out.x, lab.x, accuracy: 1e-12)
            XCTAssertEqual(out.y, lab.y, accuracy: 1e-12)
            XCTAssertEqual(out.z, lab.z, accuracy: 1e-12)
        }
    }

    func testColorContrastClampVsUnbound() {
        var p = ColorContrastModule.Params()
        p.aSteepness = 5; p.aOffset = 100; p.unbound = false
        let clamped = ColorContrastModule.reference(
            lab: SIMD3<Double>(50, 30, 0), params: p)
        XCTAssertEqual(clamped.y, 128, accuracy: 1e-9)
        p.unbound = true
        let free = ColorContrastModule.reference(
            lab: SIMD3<Double>(50, 30, 0), params: p)
        XCTAssertEqual(free.y, 250, accuracy: 1e-9)
    }

    // MARK: - V50 slots

    func testLegacyAndContrastSlots() {
        XCTAssertEqual(V50Order.order(for: "channelmixer"), 39.0)
        XCTAssertEqual(ChannelMixerModule.iopOrder, 39.0)
        XCTAssertEqual(V50Order.order(for: "colorcontrast"), 56.0)
        XCTAssertEqual(ColorContrastModule.iopOrder, 56.0)
    }
}
