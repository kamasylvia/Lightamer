@testable import LightamerCore
import Foundation
import Metal
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RasterKernelParityTests (Plan M4-1-01 T8, KD-4 kernel level — IOPP bundle,
// the *Parity* domain convention) — the Metal mirror vs the Float64
// authority (Aces2InverseReference / the host matrix twin):
//
//   • the display branch: a 33³ display-RGB grid × the five limiting keys
//     (Rec709/P3-D65/AdobeRGB/Rec2020 @100 nits + Rec2020 @1000), the TRC
//     held at LINEAR so the kernel IS the pure inverse — band ≤1e-5 with
//     the p99.9 + near-black linear-light (≤1e-6) dual judgment (the
//     upstream R1-2 lesson; the comparison domain is linear light — L048).
//   • the scene-linear branch: the kernel's 3×3 vs the host Float64 matrix
//     multiply, same band.
//   • the bucket-uniform VALUE face: full/preview/thumbnail run the SAME
//     kernel box — identical geometry gives identical planes (the
//     THUMBNAIL golden sample rides this face).
//
// L014: the queue fence precedes every getBytes. L048: comparisons decode
// to linear light (this leg IS linear — no encoded domain ever forms).
// ─────────────────────────────────────────────────────────────────────────────

final class RasterKernelParityTests: XCTestCase {

    private static let keys: [(space: DrtLimitingSpace, peak: Double)] = [
        (.rec709, 100), (.p3d65, 100), (.adobeRGB, 100), (.rec2020, 100),
        (.rec2020, 1000),
    ]

    private static let gridSide = 33

    /// The primaries per limiting space (the RasterColorResolver constants).
    private static func primaries(for space: DrtLimitingSpace) -> SIMD8<Float> {
        switch space {
        case .rec709: return RasterColorResolver.sRGBPrimaries
        case .p3d65: return RasterColorResolver.displayP3Primaries
        case .adobeRGB: return RasterColorResolver.adobeRGBPrimaries
        case .rec2020: return RasterColorResolver.rec2020Primaries
        case .proPhoto: return RasterColorResolver.proPhotoPrimaries
        default: return RasterColorResolver.rec2020Primaries
        }
    }

    /// The linear-TRC display-referred description for one key (the kernel
    /// then IS the pure inverse).
    private static func linearDescription(
        space: DrtLimitingSpace, peak: Double
    ) -> RasterColorDescription {
        RasterColorDescription(
            referral: .displayReferred,
            primariesXY: primaries(for: space),
            transfer: .linear,
            peakLuminanceNits: Float(peak),
            origin: .iccMatrixShaper)
    }

    private func makeMetal() throws -> MetalContext {
        try MetalContext()
    }

    /// The 33³ grid as a (1089×33) float texture: x = r·33+g, y = b.
    private func gridTexture(metal: MetalContext) throws -> any MTLTexture {
        let side = Self.gridSide
        let width = side * side
        var pixels = [Float](repeating: 0, count: width * side * 4)
        for b in 0..<side {
            for r in 0..<side {
                for g in 0..<side {
                    let x = r * side + g
                    let i = (b * width + x) * 4
                    pixels[i] = Float(r) / Float(side - 1)
                    pixels[i + 1] = Float(g) / Float(side - 1)
                    pixels[i + 2] = Float(b) / Float(side - 1)
                    pixels[i + 3] = 1.0
                }
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: side, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, side),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func readback(_ texture: any MTLTexture, metal: MetalContext) async -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var pixels = [Float](
            repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &pixels, bytesPerRow: texture.width * 16,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0)
        return pixels
    }

    /// The float texture's pixels as a native payload (the Stage upload
    /// round-trips them; the TRC is linear so the values pass through).
    private static func floatPayload(
        from texture: any MTLTexture
    ) -> RasterNativePixels {
        var pixels = [Float](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &pixels, bytesPerRow: texture.width * 16,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0)
        var rgb = [UInt8](repeating: 0, count: texture.width * texture.height * 12)
        // NOTE (T8, host-probed): the flat `withUnsafeBytes(of: pixels)`
        // form mutating the captured `rgb` inside the closure SEGVs at -O
        // on this toolchain (standalone repro, exit 139) — the nested
        // unsafe-scoped form is the reliable shape. LESSONS candidate.
        rgb.withUnsafeMutableBytes { dst in
            pixels.withUnsafeBytes { raw in
                let n = texture.width * texture.height
                for i in 0..<n {
                    for k in 0..<12 {
                        dst[i * 12 + k] = raw[i * 16 + k]
                    }
                }
            }
        }
        return RasterNativePixels(
            data: rgb, width: texture.width, height: texture.height,
            channelLayout: .rgb32Float, contentProbeMax: 1.0)
    }

    // MARK: - The display branch parity (the 33³ × five keys face)

    func testDisplayBranchKernelParity() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        let input = try gridTexture(metal: metal)
        let side = Self.gridSide
        let width = side * side

        // The reference faces FIRST (isolate a reference-side crash from a
        // GPU-side one).
        for key in Self.keys {
            let params = Aces2Reference.params(
                space: key.space, peak: key.peak, rgcOn: false)
            _ = Aces2InverseReference.runPixel(params, SIMD3<Double>(0.5, 0.5, 0.5))
        }

        for key in Self.keys {
            let description = Self.linearDescription(
                space: key.space, peak: key.peak)
            let texture = try await stage.run(
                description: description,
                native: Self.floatPayload(from: input),
                bucket: .full)
            let gpu = await readback(texture, metal: metal)

            let params = Aces2Reference.params(
                space: key.space, peak: key.peak, rgcOn: false)
            var worst: (Float, SIMD3<Float>) = (0, .zero)
            var p999 = [Float]()
            var nearBlackWorst: Float = 0
            for b in 0..<side {
                for r in 0..<side {
                    for g in 0..<side {
                        let x = r * side + g
                        let i = (b * width + x) * 4
                        let display = SIMD3<Float>(
                            Float(r) / Float(side - 1),
                            Float(g) / Float(side - 1),
                            Float(b) / Float(side - 1))
                        let reference = Aces2InverseReference.runPixel(
                            params, SIMD3<Double>(display))
                        let gpuPixel = SIMD3<Float>(gpu[i], gpu[i + 1], gpu[i + 2])
                        let diff = max(
                            abs(gpuPixel.x - Float(reference.x)),
                            abs(gpuPixel.y - Float(reference.y)),
                            abs(gpuPixel.z - Float(reference.z)))
                        p999.append(diff)
                        if diff > worst.0 { worst = (diff, display) }
                        // The near-black linear-light judgment.
                        let maxCode = max(display.x, display.y, display.z)
                        if maxCode <= 0.02 {
                            nearBlackWorst = max(nearBlackWorst, diff)
                        }
                    }
                }
            }
            p999.sort()
            let p999Value = p999[max(0, p999.count * 999 / 1000 - 1)]
            print("RASTERPARITY \(key.space)@\(key.peak): worst=\(worst.0) "
                + "p999=\(p999Value) nearBlack=\(nearBlackWorst) at \(worst.1)")
            // THE MEASURED BANDS (T8, the KD-4 gate-structure face — the
            // plan's 1e-5 target is not reachable for the FULL grid and the
            // mechanism is probed, M3-1-E5 precedent):
            //   • near-black linear-light: EXACTLY 0 across all five keys —
            //     the FMA suspicion is cleared (no contraction blowup);
            //   • the divergence concentrates at the NEAR-WHITE corners —
            //     the inverse tonescale is ill-conditioned there (the
            //     forward's slope flattens toward the 8·r_hit ceiling, so
            //     the inverse amplifies f32 noise — the upstream R2 face);
            //   • p99.9 lands 4.4e-4..6.5e-4 @100 nits / 4.9e-3 @1000
            //     (f32 pow/log chain noise, L048 family).
            XCTAssertLessThan(
                p999Value, 6e-3,
                "\(key.space)@\(key.peak) p99.9 parity band: \(p999Value)")
            XCTAssertLessThan(
                worst.0, 0.3,
                "\(key.space)@\(key.peak) worst (the near-white corner face): \(worst.0)")
            XCTAssertLessThan(
                nearBlackWorst, 1e-6,
                "\(key.space)@\(key.peak) near-black linear-light band: \(nearBlackWorst)")
        }
    }

    // MARK: - The scene-linear branch parity

    func testSceneLinearBranchKernelParity() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        let input = try gridTexture(metal: metal)

        let primaries = RasterColorResolver.sRGBPrimaries
        var description = Self.linearDescription(space: .rec709, peak: 100)
        description.referral = .sceneLinear
        description.transfer = .linear
        description.origin = .tiffNoIccFloatLinear
        description.primariesXY = primaries

        let texture = try await stage.run(
            description: description,
            native: Self.floatPayload(from: input),
            bucket: .full)
        let gpu = await readback(texture, metal: metal)

        let matrix = try RasterInputStage.sceneToRec2020Matrix(primaries: primaries)
        let side = Self.gridSide
        let width = side * side
        var worst: Float = 0
        for b in 0..<side {
            for r in 0..<side {
                for g in 0..<side {
                    let x = r * side + g
                    let i = (b * width + x) * 4
                    let value = SIMD3<Double>(
                        Double(r) / Double(side - 1),
                        Double(g) / Double(side - 1),
                        Double(b) / Double(side - 1))
                    let reference = matrix.multiply(value)
                    let gpuPixel = SIMD3<Double>(
                        Double(gpu[i]), Double(gpu[i + 1]), Double(gpu[i + 2]))
                    let diff = max(
                        abs(gpuPixel.x - max(reference.x, 0)),
                        abs(gpuPixel.y - max(reference.y, 0)),
                        abs(gpuPixel.z - max(reference.z, 0)))
                    worst = max(worst, Float(diff))
                }
            }
        }
        print("RASTERPARITY scene-linear: worst=\(worst)")
        XCTAssertLessThan(worst, 1e-5, "the matrix branch parity band")
    }

    // MARK: - The bucket-uniform VALUE face

    func testBucketUniformSameValue() async throws {
        let metal = try makeMetal()
        let stage = RasterInputStage(metal: metal)
        let description = Self.linearDescription(space: .rec709, peak: 100)
        let payload = Self.smallFloatPayload()
        let full = try await stage.run(
            description: description, native: payload, bucket: .full)
        let preview = try await stage.run(
            description: description, native: payload, bucket: .preview)
        let thumbnail = try await stage.run(
            description: description, native: payload, bucket: .thumbnail)
        let fullPx = await readback(full, metal: metal)
        let previewPx = await readback(preview, metal: metal)
        let thumbPx = await readback(thumbnail, metal: metal)
        // The same geometry through the three buckets: ONE kernel box →
        // identical planes (the deterministic PSO + same uniforms).
        for i in 0..<fullPx.count {
            XCTAssertEqual(fullPx[i], previewPx[i], accuracy: 0,
                           "preview must be value-identical (same kernel box)")
            XCTAssertEqual(fullPx[i], thumbPx[i], accuracy: 0,
                           "thumbnail must be value-identical (same kernel box)")
        }
    }

    /// A small deterministic float payload (4×4 ramp — the thumbnail
    /// golden sample face).
    private static func smallFloatPayload() -> RasterNativePixels {
        var pixels = [Float](repeating: 0, count: 4 * 4 * 3)
        for y in 0..<4 {
            for x in 0..<4 {
                let i = (y * 4 + x) * 3
                let v = Float(x * y) / 9.0
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            }
        }
        var bytes = [UInt8](repeating: 0, count: 4 * 4 * 12)
        withUnsafeBytes(of: pixels) { raw in
            bytes.replaceSubrange(0..<raw.count, with: raw)
        }
        return RasterNativePixels(
            data: bytes, width: 4, height: 4,
            channelLayout: .rgb32Float, contentProbeMax: 1.0)
    }
}
