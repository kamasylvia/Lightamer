@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// Phase4SidecarTests (Plan 04-07-T2) — sidecar mechanism for the 9 Phase-4
/// ops (crop/flip/ashift/lens/sharpen/bilat/highpass/soften/equalizer):
/// the sidecar is op-AGNOSTIC (it persists `paramsData` + `paramsHash`
/// bytes + identity tuple, never per-op fields — 02-06 design), so this
/// suite proves the MECHANISM covers all 9 by construction:
/// (1) every op's non-default Params survive canonical encode→decode
/// (ModuleInstance round-trip, the exact bytes the .lra carries);
/// (2) the records restore into live boxes through the real registry
/// (`makeBox(op) + apply(record)` — the coordinator's rematerialize path);
/// (3) the restored params decode back to the originating values.
/// Unknown-op degrade stays covered by
/// SidecarRoundTripTests.testUnknownOpDegradesDisabledWithParamsPreserved.
final class Phase4SidecarTests: XCTestCase {

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
        try await box.apply(record)
    }

    func testCropSidecarRoundTrip() async throws {
        let params = CropModule.Params(left: 0.25, top: 0.2, right: 0.75, bottom: 0.8, ratioN: 2, ratioD: 3)
        let record = ModuleInstance(module: CropModule.self, params: params)
        let back: CropModule.Params = try roundTrip(record, as: CropModule.self)
        XCTAssertEqual(back.left, 0.25, accuracy: 1e-6)
        XCTAssertEqual(back.bottom, 0.8, accuracy: 1e-6)
        XCTAssertEqual(back.ratioN, 2)
        XCTAssertEqual(back.ratioD, 3)
        try await restoreViaRegistry(record)
    }

    func testFlipSidecarRoundTrip() async throws {
        let params = FlipModule.Params(orientation: .rotCCW90)
        let record = ModuleInstance(module: FlipModule.self, params: params)
        let back: FlipModule.Params = try roundTrip(record, as: FlipModule.self)
        XCTAssertEqual(back.orientation, .rotCCW90)
        try await restoreViaRegistry(record)
    }

    func testAshiftSidecarRoundTrip() async throws {
        let params = AshiftModule.Params(rotation: 8, lensShiftV: 0.1, lensShiftH: -0.05, shear: 0.02)
        let record = ModuleInstance(module: AshiftModule.self, params: params)
        let back: AshiftModule.Params = try roundTrip(record, as: AshiftModule.self)
        XCTAssertEqual(back.rotation, 8, accuracy: 1e-6)
        XCTAssertEqual(back.lensShiftV, 0.1, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testLensSidecarRoundTrip() async throws {
        let params = LensModule.Params(
            distortionK1: 0.05, distortionK2: -0.01, tcaR: 0.0015, tcaB: -0.0015,
            vignetteK1: -0.3, vignetteK2: 0.1, vignetteK3: -0.02,
            source: .manual, focalLength: 16, aperture: 2.8, lensKey: "E 16mm f/2.8")
        let record = ModuleInstance(module: LensModule.self, params: params)
        let back: LensModule.Params = try roundTrip(record, as: LensModule.self)
        XCTAssertEqual(back.distortionK1, 0.05, accuracy: 1e-6)
        XCTAssertEqual(back.tcaR, 0.0015, accuracy: 1e-7)
        XCTAssertEqual(back.vignetteK1, -0.3, accuracy: 1e-6)
        XCTAssertEqual(back.source, .manual)
        XCTAssertEqual(back.focalLength, 16)
        XCTAssertEqual(back.lensKey, "E 16mm f/2.8")
        try await restoreViaRegistry(record)
    }

    func testSharpenSidecarRoundTrip() async throws {
        let params = SharpenModule.Params(radius: 2.0, amount: 0.5, threshold: 0.5)
        let record = ModuleInstance(module: SharpenModule.self, params: params)
        let back: SharpenModule.Params = try roundTrip(record, as: SharpenModule.self)
        XCTAssertEqual(back.amount, 0.5, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testLocalContrastSidecarRoundTrip() async throws {
        let params = LocalContrastModule.Params(detail: 1.0, sigmaS: 20.0, sigmaR: 0.5)
        let record = ModuleInstance(module: LocalContrastModule.self, params: params)
        let back: LocalContrastModule.Params = try roundTrip(record, as: LocalContrastModule.self)
        XCTAssertEqual(back.detail, 1.0, accuracy: 1e-6)
        XCTAssertEqual(LocalContrastModule.opName, "bilat")
        try await restoreViaRegistry(record)
    }

    func testHighpassSidecarRoundTrip() async throws {
        let record = ModuleInstance(module: HighpassModule.self, params: HighpassModule.Params(sharpness: 80, contrast: 80))
        let back: HighpassModule.Params = try roundTrip(record, as: HighpassModule.self)
        XCTAssertEqual(back.contrast, 80, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testSoftenSidecarRoundTrip() async throws {
        let record = ModuleInstance(module: SoftenModule.self, params: SoftenModule.Params(size: 80, saturation: 80, brightness: 0.5, amount: 80))
        let back: SoftenModule.Params = try roundTrip(record, as: SoftenModule.self)
        XCTAssertEqual(back.amount, 80, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }

    func testEqualizerSidecarRoundTrip() async throws {
        let record = ModuleInstance(module: EqualizerModule.self, params: EqualizerModule.Params(g0: 0.5, g4: 0.5))
        let back: EqualizerModule.Params = try roundTrip(record, as: EqualizerModule.self)
        XCTAssertEqual(back.g0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(back.g4, 0.5, accuracy: 1e-6)
        try await restoreViaRegistry(record)
    }
}
