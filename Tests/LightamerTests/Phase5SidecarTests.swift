@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// Phase5SidecarTests (Plan 05-08-T5) — sidecar mechanism for the 11 Phase-5
/// ops (colorbalancergb / channelmixerrgb / channelmixer / colorzones /
/// monochrome / vibrance / velvia / colorcontrast / denoiseprofile / nlmeans
/// / bilateral): the sidecar is op-AGNOSTIC (it persists `paramsData` +
/// `paramsHash` bytes + identity tuple — 02-06 design), so this suite proves
/// the MECHANISM covers all 11 by construction:
/// (1) every op's non-default Params survive canonical encode→decode
/// (ModuleInstance JSON round-trip — the exact bytes the .lra carries);
/// (2) the records restore into live boxes through the real registry
/// (`makeBox(op) + apply(record)` — the coordinator's rematerialize path);
/// (3) the restored params decode back to the originating values.
/// Unknown-op degrade stays covered by
/// SidecarRoundTripTests.testUnknownOpDegradesDisabledWithParamsPreserved
/// (复核于 testUnknownOpDegradeRegressionStillGreen).
final class Phase5SidecarTests: XCTestCase {

    private func roundTrip<M: IOPModule>(_ record: ModuleInstance, as type: M.Type) throws -> M.Params {
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ModuleInstance.self, from: data)
        XCTAssertEqual(decoded, record, "\(M.opName) record must survive JSON verbatim")
        return try decoded.params(of: type)
    }

    private func restoreViaRegistry(_ record: ModuleInstance) async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: record.opName, instanceID: record.id)
        let box = try XCTUnwrap(made, "\(record.opName) must materialize through the real registry")
        XCTAssertEqual(box.instanceID, record.id, "identity-restoring init wired")
        try box.apply(record)
    }

    func testColorBalanceRGBSidecarRoundTrip() async throws {
        let params = ColorBalanceRGBModule.Params(
            shadowsY: 0.1, shadowsC: 0.02, shadowsH: 30,
            midtonesY: -0.05, highlightsC: 0.03,
            chromaGlobal: 0.08, saturationMidtones: 0.12,
            vibrance: 0.2, contrast: 0.05)
        let record = ModuleInstance(module: ColorBalanceRGBModule.self, params: params)
        let back: ColorBalanceRGBModule.Params = try roundTrip(record, as: ColorBalanceRGBModule.self)
        XCTAssertEqual(back.shadowsY, 0.1, accuracy: 1e-6)
        XCTAssertEqual(back.highlightsC, 0.03, accuracy: 1e-6)
        XCTAssertEqual(back.saturationMidtones, 0.12, accuracy: 1e-6)
        XCTAssertEqual(back.vibrance, 0.2, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testChannelMixerRGBSidecarRoundTrip() async throws {
        let params = ChannelMixerRGBModule.Params(
            red: SIMD4(1.1, 0.05, -0.05, 0),
            green: SIMD4(0.02, 0.98, 0.0, 0),
            blue: SIMD4(0.0, 0.03, 1.05, 0))
        let record = ModuleInstance(module: ChannelMixerRGBModule.self, params: params)
        let back: ChannelMixerRGBModule.Params = try roundTrip(record, as: ChannelMixerRGBModule.self)
        XCTAssertEqual(back.red.x, 1.1, accuracy: 1e-6)
        XCTAssertEqual(back.blue.z, 1.05, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testChannelMixerLegacySidecarRoundTrip() async throws {
        var red = [Float](repeating: 0, count: 7); red[0] = 1.1; red[6] = 1
        var green = [Float](repeating: 0, count: 7); green[4] = 1.05
        var blue = [Float](repeating: 0, count: 7); blue[6] = 0.95
        let params = ChannelMixerModule.Params(red: red, green: green, blue: blue, algorithm: .v2)
        let record = ModuleInstance(module: ChannelMixerModule.self, params: params)
        let back: ChannelMixerModule.Params = try roundTrip(record, as: ChannelMixerModule.self)
        XCTAssertEqual(back.red[0], 1.1, accuracy: 1e-6)
        XCTAssertEqual(back.green[4], 1.05, accuracy: 1e-6)
        XCTAssertEqual(back.blue[6], 0.95, accuracy: 1e-6)
        XCTAssertEqual(back.algorithm, .v2)
        try await restoreViaRegistry(record)
    }

    func testColorZonesSidecarRoundTrip() async throws {
        let params = ColorZonesModule.Params(
            channel: .lightness,
            curveL: [ColorZonesModule.Node(x: 0, y: 0), ColorZonesModule.Node(x: 0.5, y: 0.65), ColorZonesModule.Node(x: 1, y: 1)],
            strength: 0.8)
        let record = ModuleInstance(module: ColorZonesModule.self, params: params)
        let back: ColorZonesModule.Params = try roundTrip(record, as: ColorZonesModule.self)
        XCTAssertEqual(back.channel, .lightness)
        XCTAssertEqual(back.curveL.map(\.x), params.curveL.map(\.x), "L curve nodes survive verbatim")
        XCTAssertEqual(back.curveL.map(\.y), params.curveL.map(\.y))
        XCTAssertEqual(back.strength, 0.8, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testMonochromeSidecarRoundTrip() async throws {
        let params = MonochromeModule.Params(a: 0.35, b: -0.22, size: 1.4, highlights: 0.25)
        let record = ModuleInstance(module: MonochromeModule.self, params: params)
        let back: MonochromeModule.Params = try roundTrip(record, as: MonochromeModule.self)
        XCTAssertEqual(back.a, 0.35, accuracy: 1e-6)
        XCTAssertEqual(back.b, -0.22, accuracy: 1e-6)
        XCTAssertEqual(back.size, 1.4, accuracy: 1e-6)
        XCTAssertEqual(back.highlights, 0.25, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testVibranceSidecarRoundTrip() async throws {
        let params = VibranceModule.Params(amount: -0.35)
        let record = ModuleInstance(module: VibranceModule.self, params: params)
        let back: VibranceModule.Params = try roundTrip(record, as: VibranceModule.self)
        XCTAssertEqual(back.amount, -0.35, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testVelviaSidecarRoundTrip() async throws {
        let params = VelviaModule.Params(strength: 65, bias: 0.7)
        let record = ModuleInstance(module: VelviaModule.self, params: params)
        let back: VelviaModule.Params = try roundTrip(record, as: VelviaModule.self)
        XCTAssertEqual(back.strength, 65, accuracy: 1e-4)
        XCTAssertEqual(back.bias, 0.7, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testColorContrastSidecarRoundTrip() async throws {
        let params = ColorContrastModule.Params(aSteepness: 1.25, aOffset: 0.08, bSteepness: 1.1, bOffset: -0.02, unbound: false)
        let record = ModuleInstance(module: ColorContrastModule.self, params: params)
        let back: ColorContrastModule.Params = try roundTrip(record, as: ColorContrastModule.self)
        XCTAssertEqual(back.aSteepness, 1.25, accuracy: 1e-6)
        XCTAssertEqual(back.bOffset, -0.02, accuracy: 1e-6)
        XCTAssertEqual(back.unbound, false)
        try await restoreViaRegistry(record)
    }

    func testDenoiseProfileSidecarRoundTrip() async throws {
        let params = DenoiseProfileModule.Params(
            radius: 2.0, nbhood: 5, strength: 1.8, shadows: 1.2, bias: -1.0,
            scattering: 0.5, centralPixelWeight: 0.3, mode: .nlmeans)
        let record = ModuleInstance(module: DenoiseProfileModule.self, params: params)
        let back: DenoiseProfileModule.Params = try roundTrip(record, as: DenoiseProfileModule.self)
        XCTAssertEqual(back.radius, 2.0, accuracy: 1e-6)
        XCTAssertEqual(back.strength, 1.8, accuracy: 1e-6)
        XCTAssertEqual(back.scattering, 0.5, accuracy: 1e-6)
        XCTAssertEqual(back.mode, .nlmeans)
        try await restoreViaRegistry(record)
    }

    func testNLMeansSidecarRoundTrip() async throws {
        let params = NLMeansModule.Params(radius: 3.5, strength: 120, luma: 0.8, chroma: 0.6)
        let record = ModuleInstance(module: NLMeansModule.self, params: params)
        let back: NLMeansModule.Params = try roundTrip(record, as: NLMeansModule.self)
        XCTAssertEqual(back.radius, 3.5, accuracy: 1e-6)
        XCTAssertEqual(back.strength, 120, accuracy: 1e-4)
        XCTAssertEqual(back.chroma, 0.6, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testBilateralSidecarRoundTrip() async throws {
        let params = BilateralModule.Params(radius: 8.5, reserved: 15, red: 0.02, green: 0.03, blue: 0.04)
        let record = ModuleInstance(module: BilateralModule.self, params: params)
        let back: BilateralModule.Params = try roundTrip(record, as: BilateralModule.self)
        XCTAssertEqual(back.radius, 8.5, accuracy: 1e-6)
        XCTAssertEqual(back.reserved, 15, accuracy: 1e-6, "20B blob reserved slot preserved")
        XCTAssertEqual(back.red, 0.02, accuracy: 1e-6)
        XCTAssertEqual(back.blue, 0.04, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    /// 未知 op 透传降级回归复核（02-06 机制在 11 新 op 入册后仍成立）。
    func testUnknownOpDegradeRegressionStillGreen() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: "no_such_op_05_08")
        XCTAssertNil(made, "unknown op must not materialize a box (degrade path)")
    }
}
