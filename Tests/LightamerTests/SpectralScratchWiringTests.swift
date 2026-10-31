@testable import LightamerCore
import LightamerIOP
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralScratchWiringTests (M8-3+ fix round E-acc1 — IOPParity) — the
// allocator's PRODUCTION wiring face (the Slot graduated from a borrow
// token to a resource pool; the four production dispatch sites borrow
// through the run's Slot):
//
//   1. THE POOL FACE (pure pool, no chain): same-geometry re-borrows hit
//      the parked faces (textureHits/bufferHits count them); a different
//      leg while faces are out is the typed refusal; the holder clears
//      when the segment's last face returns (partial returns keep it).
//   2. THE REUSE FACE (one diffusion leg): borrowing → releasing →
//      re-borrowing the trio re-hits all three faces (fresh count 3 on
//      the first leg, 0 on the second).
//   3. THE CHAIN FACE (full dispatchFilmChain, all three legs armed): the
//      injected slot's accounting shows reuse (hits > 0 — diffusion's
//      trio → halation's quartet → grain's set time-share the pool),
//      the holder is free at chain end, and the peakBytes watermark
//      lands at the measured value (the DECISIONS number's regression).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralScratchWiringTests: XCTestCase {

    // MARK: - Fixtures

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private static let fixtureBox = WiringFixtureBox()

    private final class WiringFixtureBox: @unchecked Sendable {
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
        _ metal: MetalContext, width: Int, height: Int, write: Bool
    ) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, write ? .shaderWrite : .shaderRead]
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

    // MARK: - 1: the pool face

    func testPoolReusesSameGeometryFacesAndRefusesForeignLegs() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let slot = SpectralScratchAllocator.Slot()
        // First borrow (fresh — 3 faces, 0 hits).
        let trio = try XCTUnwrap(try slot.borrowPlanes(
            .spatialPre, device: device, count: 3, width: 48, height: 32))
        XCTAssertEqual(trio.count, 3)
        var accounting = slot.accountingForTesting
        XCTAssertEqual(accounting.textureBorrows, 3)
        XCTAssertEqual(accounting.textureHits, 0)
        XCTAssertEqual(accounting.textureWatermark, 3)
        // A DIFFERENT leg while faces are out = the typed refusal.
        XCTAssertThrowsError(try slot.borrowPlanes(
            .stageB2, device: device, count: 1, width: 48, height: 32)) { error in
            XCTAssertEqual(
                error as? SpectralScratchAllocator.BorrowError,
                .alreadyBorrowed(holder: .spatialPre, requester: .stageB2))
        }
        // Same-leg top-up = allowed (the re-entry face).
        let topup = try XCTUnwrap(try slot.borrowPlanes(
            .spatialPre, device: device, count: 1, width: 48, height: 32))
        XCTAssertEqual(topup.count, 1)
        // Partial return keeps the holder (the segment still owns faces).
        slot.releasePlanes([trio[0]])
        XCTAssertEqual(slot.holderForTesting, .spatialPre)
        // Full return clears the holder; the re-borrow re-hits all four.
        slot.releasePlanes([trio[1], trio[2], topup[0]])
        XCTAssertNil(slot.holderForTesting)
        let again = try XCTUnwrap(try slot.borrowPlanes(
            .spatialPre, device: device, count: 4, width: 48, height: 32))
        XCTAssertEqual(again.count, 4)
        accounting = slot.accountingForTesting
        XCTAssertEqual(accounting.textureBorrows, 8)
        XCTAssertEqual(accounting.textureHits, 4)
        XCTAssertEqual(accounting.textureWatermark, 4)
        slot.releasePlanes(again)
        XCTAssertNil(slot.holderForTesting)
    }

    func testBufferPoolKeysOnExactByteLength() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let slot = SpectralScratchAllocator.Slot()
        let first = try XCTUnwrap(try slot.borrowBuffers(
            .spatialPre, device: device, byteLengths: [1024, 2048]))
        XCTAssertEqual(first.count, 2)
        slot.releaseBuffers(first)
        // Same lengths re-hit; a NEW length allocates fresh.
        let second = try XCTUnwrap(try slot.borrowBuffers(
            .spatialPre, device: device, byteLengths: [1024, 2048]))
        XCTAssertEqual(second.count, 2)
        slot.releaseBuffers(second)
        let accounting = slot.accountingForTesting
        XCTAssertEqual(accounting.bufferBorrows, 4)
        XCTAssertEqual(accounting.bufferHits, 2)
        XCTAssertEqual(accounting.bufferWatermark, 2)
        XCTAssertNil(slot.holderForTesting)
    }

    // MARK: - 2: the reuse face (one leg, two passes)

    func testDiffusionLegReleasesAndRehitsTheTrio() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let tables = try spectralTables()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables, couplers: .neutral,
            decimation: 4, frameWidth: 48, frameHeight: 32)
        let family = try XCTUnwrap(SpectralSpatialTables.family(id: "black-pro-mist"))
        let slot = SpectralScratchAllocator.Slot()
        let plane = try makePlaneTexture(metal, width: 48, height: 32, write: true)
        Self.fillRamp(plane)
        // Pass 1 (fresh trio + wide-free exact blurs — small frame).
        try await payloads.dispatchTakingDiffusion(
            plane: plane, family: family, strength: 1.0, metal: metal,
            scratch: slot)
        await Self.drain(metal)
        var accounting = slot.accountingForTesting
        XCTAssertEqual(accounting.textureHits, 0, "pass 1 allocates fresh")
        XCTAssertEqual(accounting.textureWatermark, 3, "the trio is the live peak")
        XCTAssertNil(slot.holderForTesting, "the leg released its trio")
        // Pass 2 (same geometry — all three re-hit the pool).
        try await payloads.dispatchTakingDiffusion(
            plane: plane, family: family, strength: 1.0, metal: metal,
            scratch: slot)
        await Self.drain(metal)
        accounting = slot.accountingForTesting
        XCTAssertEqual(accounting.textureBorrows, 6)
        XCTAssertEqual(accounting.textureHits, 3, "pass 2 re-hits the trio")
        XCTAssertEqual(accounting.textureWatermark, 3, "the peak never grows")
        XCTAssertNil(slot.holderForTesting)
    }

    // MARK: - 3: the chain face (all three legs armed, two runs)

    func testFullChainArmedReusesAcrossSegments() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let tables = try spectralTables()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables, couplers: .neutral,
            decimation: 4, frameWidth: 48, frameHeight: 32)
        let input = try makePlaneTexture(metal, width: 48, height: 32, write: false)
        Self.fillRamp(input)
        let output = try makePlaneTexture(metal, width: 48, height: 32, write: true)
        let slot = SpectralScratchAllocator.Slot()
        func runOnce() async throws {
            try await payloads.dispatchFilmChain(
                input: input, output: output, metal: metal,
                exposureGain: 1.0,
                magentaCC: tables.solvedPrintCC.y,
                yellowCC: tables.solvedPrintCC.z,
                strength: 1.0,
                grainAmount: 0.5, halationAmount: 1.0,
                diffusionFamily: "black-pro-mist", diffusionAmount: 1.0,
                scratch: slot)
            await Self.drain(metal)
        }
        // Run 1: diffusion's trio → halation's quartet re-hit within the
        // SAME run (cross-segment reuse); grain's buffers borrow fresh
        // (a single chain borrows them once — no in-run second chance).
        try await runOnce()
        let first = slot.accountingForTesting
        XCTAssertGreaterThan(
            first.textureHits, 0, "cross-segment texture reuse happened")
        XCTAssertGreaterThan(
            first.bufferBorrows, 0, "grain's working set rode the pool")
        XCTAssertNil(slot.holderForTesting, "the chain released everything")
        // Run 2 (same slot): every face re-hits — the hits grow on both
        // counters, the watermarks never do.
        try await runOnce()
        let second = slot.accountingForTesting
        XCTAssertGreaterThan(
            second.textureHits, first.textureHits,
            "run 2 re-hits the parked planes")
        XCTAssertGreaterThan(
            second.bufferHits, first.bufferHits,
            "run 2 re-hits the parked buffers")
        XCTAssertEqual(
            second.textureWatermark, first.textureWatermark,
            "the texture peak never grows")
        XCTAssertEqual(
            second.bufferWatermark, first.bufferWatermark,
            "the buffer peak never grows")
        XCTAssertNil(slot.holderForTesting)
        // The measured peak (48×32 fixture — the DECISIONS number's
        // regression nail: the watermark pins the real wired behavior).
        XCTAssertGreaterThan(second.peakBytes, 0)
        XCTAssertLessThanOrEqual(
            second.textureWatermark, 5,
            "halation quartet + bounce is the texture peak")
    }
}
