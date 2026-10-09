@testable import LightamerCore
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RasterInputPlaneTests (Plan M4-1-01 T7/T8, KD-6/KD-7 — IOPP bundle) — the
// input leg's assembly face, driven straight (no PixelPipe wiring — that is
// M4-1-02):
//
//   • T7: the two kernel entries build and produce planes (geometry/format
//     asserts); the uniform ABI probe pins the Swift plane against the
//     Metal struct; the typed failure face (peak ≤ 0 → invalidParameter).
//   • T8 (this file's cache section): the develop-output slot keys on
//     description ⊕ geometry ⊕ bucket — a repeat run HITS (the same
//     texture instance identity), a slider-neutral mutation misses, and
//     the bucket tags split (KD-7; the bucket-uniform VALUE equality is
//     RasterKernelParityTests' face).
// ─────────────────────────────────────────────────────────────────────────────

final class RasterInputPlaneTests: XCTestCase {

    private func makeMetal() throws -> MetalContext {
        try MetalContext()
    }

    /// A synthetic 16×16 sRGB description (the ③ default).
    private func srgbDescription() -> RasterColorDescription {
        RasterColorResolver.resolve(iccData: nil, colorSpaceName: nil, isFloat: false)
    }

    /// A synthetic u8 payload: an 8-code ramp with channel offsets.
    private func rampNative(width: Int = 16, height: Int = 16) -> RasterNativePixels {
        var data = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 3
                let v = UInt8((x * 255) / (width - 1))
                data[i] = v
                data[i + 1] = v
                data[i + 2] = v
            }
        }
        return RasterNativePixels(
            data: data, width: width, height: height,
            channelLayout: .rgb8, contentProbeMax: 1.0)
    }

    private func readback(_ texture: any MTLTexture, metal: MetalContext) async -> [Float] {
        // The L014 fence: the queue drain before getBytes.
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var pixels = [Float](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &pixels, bytesPerRow: texture.width * 16,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - T7: the plane faces

    func testDisplayLegProducesWorkingPlane() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        let texture = try await stage.run(
            description: srgbDescription(), native: rampNative(), bucket: .full)
        XCTAssertEqual(texture.width, 16)
        XCTAssertEqual(texture.height, 16)
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
        let pixels = await readback(texture, metal: metal)
        // The plane is finite and non-degenerate (the ramp survives the leg).
        for v in pixels where v.isNaN {
            XCTFail("NaN in the working plane")
            break
        }
        // The response face: the leg output is FINITE and MONOTONE over
        // the ramp (the ramp columns carry increasing codes). NOTE: the
        // ramp's white end (code 1.0 = peak nits) legitimately inverts
        // ABOVE the ACES scene-white — the forward saturates near
        // 8·r_hit nits, so display-peak inverts to a super-bright scene
        // value (the probed ~129 face); the smoke asserts monotonicity,
        // not scene-range membership.
        func columnValue(_ x: Int) -> Float {
            pixels[(8 * texture.width + x) * 4]
        }
        let low = columnValue(3)
        let mid = columnValue(8)
        let high = columnValue(13)
        XCTAssertGreaterThan(low, 0, "the ramp must survive the inverse leg")
        XCTAssertLessThanOrEqual(low, mid)
        XCTAssertLessThanOrEqual(mid, high)
        for v in [low, mid, high] {
            XCTAssertTrue(v.isFinite, "the leg output must stay finite")
        }
    }

    func testSceneLinearLegProducesWorkingPlane() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        var description = srgbDescription()
        description.referral = .sceneLinear
        description.transfer = .linear
        description.origin = .tiffNoIccFloatLinear
        // The u8 ramp rides the matrix branch (a numeric smoke — the parity
        // is the T8 Float64 twin's face).
        let texture = try await stage.run(
            description: description, native: rampNative(), bucket: .full)
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
        let pixels = await readback(texture, metal: metal)
        for v in pixels where v.isNaN {
            XCTFail("NaN in the scene-linear plane")
            break
        }
    }

    func testUniformABIPin() async throws {
        let metal = try makeMetal()
        let out = metal.device.makeBuffer(length: MemoryLayout<UInt32>.stride)!
        let session = try await metal.makeEncoder(
            functionName: "raster_input_uniforms_size_probe")
        session.encoder.setBuffer(out, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()
        let gpuSize = out.contents().bindMemory(to: UInt32.self, capacity: 1).pointee
        XCTAssertEqual(Int(gpuSize), RasterInputUniforms.float4Count * 16,
                       "the input-leg uniform ABI must be identical on both sides")
    }

    func testNonPositivePeakIsTypedRejected() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        var description = srgbDescription()
        description.peakLuminanceNits = 0
        do {
            _ = try await stage.run(
                description: description, native: rampNative(), bucket: .full)
            XCTFail("peak 0 must be typed-rejected")
        } catch let error as AppError {
            guard case .invalidParameter = error else {
                return XCTFail("unexpected error case: \(error)")
            }
        }
    }

    // MARK: - T8: the develop-output cache

    func testCacheRepeatRunHitsSameTexture() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        let native = rampNative()
        let first = try await stage.run(
            description: srgbDescription(), native: native, bucket: .full)
        let second = try await stage.run(
            description: srgbDescription(), native: native, bucket: .full)
        XCTAssertTrue(first === second, "the develop-output slot must HIT")
        XCTAssertEqual(stage.cachedCount, 1)
    }

    func testCacheDescriptionChangeMisses() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        let native = rampNative()
        _ = try await stage.run(
            description: srgbDescription(), native: native, bucket: .full)
        // A peak change (the user-facing slider face) flips the key.
        var hdr = srgbDescription()
        hdr.transfer = .st2084
        hdr.peakLuminanceNits = 1000
        _ = try await stage.run(
            description: hdr, native: native, bucket: .full)
        XCTAssertEqual(stage.cachedCount, 2, "the description flip must MISS")
    }

    func testCacheBucketSplits() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        let native = rampNative()
        let full = try await stage.run(
            description: srgbDescription(), native: native, bucket: .full)
        let preview = try await stage.run(
            description: srgbDescription(), native: native, bucket: .preview)
        let thumbnail = try await stage.run(
            description: srgbDescription(), native: native, bucket: .thumbnail)
        XCTAssertFalse(full === preview)
        XCTAssertFalse(preview === thumbnail)
        XCTAssertEqual(stage.cachedCount, 3, "the bucket tags split the slots")
        stage.clear()
        XCTAssertEqual(stage.cachedCount, 0)
    }

    /// The cache key is field-explicit (L013): equal descriptions/geometry
    /// fold equal keys; a peak or transfer change flips it.
    func testCacheKeyFieldExplicit() {
        let native = rampNative()
        let a = RasterInputStage.cacheKey(
            description: srgbDescription(), native: native, bucket: .full)
        let b = RasterInputStage.cacheKey(
            description: srgbDescription(), native: native, bucket: .full)
        XCTAssertEqual(a, b)
        let c = RasterInputStage.cacheKey(
            description: srgbDescription(), native: native, bucket: .preview)
        XCTAssertNotEqual(a, c)
        var d = srgbDescription()
        d.transfer = .gamma(2.4)
        XCTAssertNotEqual(a, RasterInputStage.cacheKey(
            description: d, native: native, bucket: .full))
    }
}
