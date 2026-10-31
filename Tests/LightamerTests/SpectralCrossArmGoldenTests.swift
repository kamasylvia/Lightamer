@testable import LightamerCore
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralCrossArmGoldenTests (M8-3+ fix round m-A — IOPParity) — the
// CROSS-ARM end-to-end golden the acceptance probe ② proved missing: the
// unit trio golden pins each arm's arithmetic, but the DISPATCH face
// (blurPlane's threshold routing) plus the wide arm's real-kernel chain
// had zero hash monitoring (σpx<16 fixtures all fell into the exact arm,
// and the wide plan itself refuses σ<16px).
//
// The matrix (2 tests, wide on/off × transpose):
//
//   1. THE DISPATCH FACE: a 1024×768 frame (pitch 35.2µm/px) with the
//      threshold test double pinned at 16px (the lock-box setter —
//      restored in defer): cinebloom's bloom quartet (σpx 20–123 —
//      ABOVE the pinned mark) routes wide through the REAL kernel chain
//      (rows/down/low/up), its core pair + halo trio (σpx ≤ 5) stay
//      exact. The two sides render DIFFERENT bytes from the all-exact
//      twin (threshold = +∞), both finite, both deterministic; the wide
//      side re-renders bit-identical.
//   2. THE TRANSPOSE FACE: the same dispatch pair on the TRANSPOSED frame
//      (768×1024 — the grid anchor's non-square leg): bloom σpx 15–92
//      straddles the mark (partial wide), still finite + deterministic +
//      off-twin-divergent.
//
// The σpx pins come from bank()/pixelUm (the test DERIVES them, never
// hardcodes — the bank table stays the single source). The all-exact
// twin pays the direct-convolution cost of the largest σ (r≈370); the
// wide side pays the抽稀 chain — the wall-time asymmetry is the test's
// own evidence that the arms differ.
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralCrossArmGoldenTests: XCTestCase {

    // The REGISTERED wide-arm hashes (fix round 2, m-fix-1: without these
    // the "Golden" in the class name is a lie — the original pair pinned
    // no constant, monitoring determinism only). Measured on the
    // 2026-11-01 registration run (M-series GPU, same payload
    // construction as these tests); the exact twin's hash is expected to
    // move with the kernel math and stays UNPINNED by design (the
    // divergence assertion monitors dispatch routing, not bytes).
    private static let dispatchWideHash: UInt64 = 15571136022812571430
    private static let transposeWideHash: UInt64 = 12304591439955305968
    // MARK: - Fixtures

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        return metal
    }

    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private static let fixtureBox = CrossArmFixtureBox()

    private final class CrossArmFixtureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SpectralFilmTables?
        func tables(make: () throws -> SpectralFilmTables) throws -> SpectralFilmTables {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            lock.unlock()
            let made = try make()
            lock.lock()
            value = made
            lock.unlock()
            return made
        }
    }

    private func spectralTables() throws -> SpectralFilmTables {
        try Self.fixtureBox.tables {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let profiles = root.appendingPathComponent("Resources/FilmProfiles/profiles")
            let film = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_400.json"))
            let paper = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_endura.json"))
            return try SpectralBuildEngine.build(film: film, paper: paper)
        }
    }

    private func makePlaneTexture(
        _ metal: MetalContext, width: Int, height: Int
    ) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        return try XCTUnwrap(metal.device.makeTexture(descriptor: desc))
    }

    private static func fillRamp(_ texture: any MTLTexture) {
        let w = texture.width, h = texture.height
        var px = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                px[i + 0] = 0.12 + 0.6 * Float(x) / Float(max(w - 1, 1))
                px[i + 1] = 0.18 + 0.4 * Float(y) / Float(max(h - 1, 1))
                px[i + 2] = 0.25
                px[i + 3] = 1.0
            }
        }
        px.withUnsafeBytes {
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(),
                                  size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: w * 4 * MemoryLayout<Float>.stride)
        }
    }

    private static func readback(_ texture: any MTLTexture) -> [Float] {
        let w = texture.width, h = texture.height
        var data = [Float](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * 4 * MemoryLayout<Float>.stride,
                from: MTLRegion(origin: MTLOrigin(),
                                size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0)
        }
        return data
    }

    private static func hash(_ floats: [Float]) -> UInt64 {
        var h: UInt64 = 14_695_981_039_346_656_037
        for f in floats {
            h ^= UInt64(f.bitPattern)
            h &*= 1_099_511_628_211
        }
        return h
    }

    /// The bank's σpx split at one frame width (derived, not hardcoded).
    private func splitSigmaPx(
        familyId: String, width: Int, threshold: Float
    ) throws -> (below: Int, above: Int) {
        let family = try XCTUnwrap(SpectralSpatialTables.family(id: familyId))
        let bank = SpectralSpatialTables.bank(family: family)
        let pitch = SpectralGPUPayloads.pixelUm(frameWidth: width)
        var below = 0, above = 0
        for component in bank {
            if component.sigmaUm / pitch >= Double(threshold) {
                above += 1
            } else {
                below += 1
            }
        }
        return (below, above)
    }

    private func renderDiffusion(
        payloads: SpectralGPUPayloads, plane: any MTLTexture,
        familyId: String, metal: MetalContext
    ) async throws {
        let family = try XCTUnwrap(SpectralSpatialTables.family(id: familyId))
        try await payloads.dispatchTakingDiffusion(
            plane: plane, family: family, strength: 2.0, metal: metal)
        await Self.drain(metal)
    }

    private static func assertFinite(_ floats: [Float], label: String) {
        for i in stride(from: 0, to: floats.count, by: 64) {
            XCTAssertTrue(
                floats[i].isFinite && floats[i + 1].isFinite
                    && floats[i + 2].isFinite, "\(label) texel \(i / 4) finite")
        }
    }

    // MARK: - 1: the dispatch face (wide on vs all-exact)

    func testDispatchRoutesBloomWideAndCoreExact() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let tables = try spectralTables()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables, couplers: .neutral,
            decimation: 4, frameWidth: 1024, frameHeight: 768)
        // The bank split at 1024px wide (pitch 35.2µm/px): cinebloom's
        // bloom quartet σpx 20–123 ≥ 16 (wide through the real chain),
        // its core pair + halo trio σpx ≤ 5 (exact) — both arms engaged
        // in ONE leg.
        let split = try splitSigmaPx(
            familyId: "cinebloom", width: 1024, threshold: 16.0)
        XCTAssertGreaterThan(split.above, 0, "bloom components route wide")
        XCTAssertGreaterThan(split.below, 0, "core components stay exact")
        let saved = SpectralGPUPayloads.wideEffectThreshold
        defer { SpectralGPUPayloads.wideEffectThreshold = saved }
        // The wide-ON side (pinned 16px mark = the plan's own min face).
        SpectralGPUPayloads.wideEffectThreshold = 16.0
        let widePlane = try makePlaneTexture(metal, width: 1024, height: 768)
        Self.fillRamp(widePlane)
        try await renderDiffusion(
            payloads: payloads, plane: widePlane,
            familyId: "cinebloom", metal: metal)
        let wideFloats = Self.readback(widePlane)
        Self.assertFinite(wideFloats, label: "wide")
        // The all-EXACT twin (threshold = +∞ — every component exact,
        // paying the direct-convolution cost).
        SpectralGPUPayloads.wideEffectThreshold = Float.greatestFiniteMagnitude
        let exactPlane = try makePlaneTexture(metal, width: 1024, height: 768)
        Self.fillRamp(exactPlane)
        try await renderDiffusion(
            payloads: payloads, plane: exactPlane,
            familyId: "cinebloom", metal: metal)
        let exactFloats = Self.readback(exactPlane)
        Self.assertFinite(exactFloats, label: "exact")
        // The dispatch moves the render (the wide kernel chain is NOT the
        // exact kernel — different math, different bytes).
        XCTAssertNotEqual(
            Self.hash(wideFloats), Self.hash(exactFloats),
            "the wide arm renders different bytes from the exact arm")
        // The wide side re-renders bit-identically (deterministic).
        SpectralGPUPayloads.wideEffectThreshold = 16.0
        let widePlane2 = try makePlaneTexture(metal, width: 1024, height: 768)
        Self.fillRamp(widePlane2)
        try await renderDiffusion(
            payloads: payloads, plane: widePlane2,
            familyId: "cinebloom", metal: metal)
        XCTAssertEqual(
            Self.hash(Self.readback(widePlane2)), Self.hash(wideFloats),
            "the wide arm re-renders bit-identically")
        // The PINNED golden: the wide arm's bytes are the registered
        // constant (drift = the dispatch or the kernel chain moved).
        XCTAssertEqual(
            Self.hash(wideFloats), Self.dispatchWideHash,
            "the dispatch wide hash matches the registered golden")
    }

    // MARK: - 2: the transpose face (non-square grid anchor)

    func testDispatchTransposeRendersFiniteAndDeterministic() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let tables = try spectralTables()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables, couplers: .neutral,
            decimation: 4, frameWidth: 768, frameHeight: 1024)
        // The transposed split (768px wide → pitch 46.9µm/px): bloom σpx
        // 15–92 — straddles the 16px mark (partial wide).
        let split = try splitSigmaPx(
            familyId: "cinebloom", width: 768, threshold: 16.0)
        XCTAssertGreaterThan(split.above, 0, "some components route wide")
        XCTAssertGreaterThan(split.below, 0, "some components stay exact")
        let saved = SpectralGPUPayloads.wideEffectThreshold
        defer { SpectralGPUPayloads.wideEffectThreshold = saved }
        SpectralGPUPayloads.wideEffectThreshold = 16.0
        let plane = try makePlaneTexture(metal, width: 768, height: 1024)
        Self.fillRamp(plane)
        try await renderDiffusion(
            payloads: payloads, plane: plane,
            familyId: "cinebloom", metal: metal)
        let floats = Self.readback(plane)
        Self.assertFinite(floats, label: "transposed wide")
        let plane2 = try makePlaneTexture(metal, width: 768, height: 1024)
        Self.fillRamp(plane2)
        try await renderDiffusion(
            payloads: payloads, plane: plane2,
            familyId: "cinebloom", metal: metal)
        XCTAssertEqual(
            Self.hash(Self.readback(plane2)), Self.hash(floats),
            "the transposed wide arm re-renders bit-identically")
        // The PINNED golden (transpose grid anchor — the registered
        // constant from the same registration run).
        XCTAssertEqual(
            Self.hash(floats), Self.transposeWideHash,
            "the transposed wide hash matches the registered golden")
        // The off-twin (all-exact) diverges — the dispatch is live on the
        // transposed grid too.
        SpectralGPUPayloads.wideEffectThreshold = Float.greatestFiniteMagnitude
        let exactPlane = try makePlaneTexture(metal, width: 768, height: 1024)
        Self.fillRamp(exactPlane)
        try await renderDiffusion(
            payloads: payloads, plane: exactPlane,
            familyId: "cinebloom", metal: metal)
        XCTAssertNotEqual(
            Self.hash(Self.readback(exactPlane)), Self.hash(floats),
            "the transposed wide arm differs from its exact twin")
    }
}
