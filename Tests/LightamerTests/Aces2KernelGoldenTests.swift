@testable import LightamerCore
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// Aces2KernelGoldenTests (Plan M2-6-2 T4, AC#5/#6 — IOPP bundle, Golden*
// convention) — the ACES 2.0 kernel vs the Float64 reference golden face.
//
//   • uniform ABI pin (the size-probe kernel vs the Swift plane count);
//   • golden: the deterministic probe triple × the parameter points (SDR /
//     HDR / P3 baselines, the RGC-off point, and all seven limiting
//     spaces on the grid probe) vs Aces2Reference.runPixel (KD-8 bands);
//   • bit-exact determinism (same PSO + same input = identical planes);
//   • the dispatch face: both DrtMethod cases are reachable and diverge;
//     the OpenDRT arm still matches its RGC-FREE reference (AC#3's
//     "OpenDRT 路径不经过 RGC" face — the P1 golden pins that parity
//     across the full matrix; one live check here).
//
// KD-6 复用判定 (DECISIONS §D7): the probe/compare helpers are a MINIMAL
// COPY of the M2-6-1 golden face (extracting shared helpers would have
// touched DrtKernelGoldenTests.swift beyond this plan's declared set —
// the copy is the smaller diff footprint; the probes are byte-identical
// generators).
// ─────────────────────────────────────────────────────────────────────────────

final class Aces2KernelGoldenTests: XCTestCase {

    private func makeMetal() throws -> MetalContext {
        try MetalContext()
    }

    // MARK: ABI pin

    func testUniformBridgeSizeMatchesTheMetalStruct() async throws {
        let metal = try makeMetal()
        let out = metal.device.makeBuffer(length: MemoryLayout<UInt32>.stride)!
        let session = try await metal.makeEncoder(functionName: "drt_aces2_uniforms_size_probe")
        session.encoder.setBuffer(out, offset: 0, index: 0)
        session.encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()
        let gpuSize = out.contents().bindMemory(to: UInt32.self, capacity: 1).pointee
        XCTAssertEqual(Int(gpuSize), Aces2Uniforms.float4Count * 16,
                       "the uniform ABI must be identical on both sides")
        XCTAssertEqual(Aces2Uniforms.float4Count, 588)
    }

    // MARK: probes (the M2-6-1 minimal-copy face — identical generators)

    private func probePixels(kind: String) -> (pixels: [Float], width: Int, height: Int) {
        switch kind {
        case "ramp":
            let w = 1024
            var px = [Float](repeating: 0, count: w * 4)
            for i in 0..<w {
                let x = 4.0 * Double(i) / Double(w - 1)
                px[i * 4 + 0] = Float(x); px[i * 4 + 1] = Float(x)
                px[i * 4 + 2] = Float(x); px[i * 4 + 3] = 1.0
            }
            return (px, w, 1)
        case "grid":
            let side = 8
            var px = [Float](repeating: 0, count: side * side * 4)
            for sy in 0..<side {
                for hx in 0..<side {
                    let theta = 2.0 * Double.pi * Double(hx) / Double(side)
                    let sat = Double(sy) / Double(side - 1)
                    var rgb = SIMD3(
                        0.5 + 0.5 * Foundation.cos(theta),
                        0.5 + 0.5 * Foundation.sin(theta),
                        0.5 + 0.5 * Foundation.cos(theta + 2.0943951))
                    rgb = SIMD3(
                        Swift.min(Swift.max(rgb.x, 0), 1),
                        Swift.min(Swift.max(rgb.y, 0), 1),
                        Swift.min(Swift.max(rgb.z, 0), 1))
                    rgb = 0.5 + (rgb - 0.5) * sat
                    let o = (sy * side + hx) * 4
                    px[o + 0] = Float(rgb.x); px[o + 1] = Float(rgb.y)
                    px[o + 2] = Float(rgb.z); px[o + 3] = 1.0
                }
            }
            return (px, side, side)
        case "extreme":
            let primaries = [
                SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 0, 1),
                SIMD3<Double>(1, 1, 0), SIMD3<Double>(1, 0, 1), SIMD3<Double>(0, 1, 1),
            ]
            let lums = (0..<16).map { lumIdx -> Double in
                let t = Double(lumIdx) / 15.0
                return 0.01 * Foundation.pow(10, 4 * t)
            }
            var px = [Float](repeating: 0, count: primaries.count * lums.count * 4)
            for (pIdx, primary) in primaries.enumerated() {
                for (lIdx, lum) in lums.enumerated() {
                    let rgb = primary * lum
                    let o = (pIdx * lums.count + lIdx) * 4
                    px[o + 0] = Float(rgb.x); px[o + 1] = Float(rgb.y)
                    px[o + 2] = Float(rgb.z); px[o + 3] = 1.0
                }
            }
            return (px, 16, primaries.count)
        default:
            fatalError("unknown probe \(kind)")
        }
    }

    // MARK: dispatch + reference + compare

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int
    ) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    private func dispatchAces2(
        _ metal: MetalContext, pixels: [Float], width: Int, height: Int,
        space: DrtLimitingSpace, peak: Double, rgcOn: Bool
    ) async throws -> [Float] {
        let input = makeTexture(metal, width: width, height: height)
        pixels.withUnsafeBytes {
            input.replace(region: MTLRegionMake2D(0, 0, width, height),
                          mipmapLevel: 0, withBytes: $0.baseAddress!,
                          bytesPerRow: width * 16)
        }
        let uniforms = Aces2Uniforms(
            params: Aces2Reference.params(space: space, peak: peak, rgcOn: rgcOn))
        let uniformBuffer = uniforms.floats.withUnsafeBufferPointer { rows in
            metal.device.makeBuffer(
                bytes: rows.baseAddress!, length: rows.count * 16,
                options: .storageModeShared)!
        }
        let output = makeTexture(metal, width: width, height: height)
        try await metal.dispatch2DTexture(
            functionName: "drt_aces2", input: input, output: output,
            configure: { encoder in
                encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
            })
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var readback = [Float](repeating: 0, count: width * height * 4)
        output.getBytes(&readback, bytesPerRow: width * 16,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return readback
    }

    private func reference(
        space: DrtLimitingSpace, peak: Double, rgcOn: Bool,
        pixels: [Float], width: Int, height: Int
    ) -> [Float] {
        let p = Aces2Reference.params(space: space, peak: peak, rgcOn: rgcOn)
        var out = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let linear = SIMD3<Double>(
                Double(pixels[i * 4]), Double(pixels[i * 4 + 1]), Double(pixels[i * 4 + 2]))
            let transformed = Aces2Reference.runPixel(p, linear)
            out[i * 4 + 0] = Float(transformed.x)
            out[i * 4 + 1] = Float(transformed.y)
            out[i * 4 + 2] = Float(transformed.z)
            out[i * 4 + 3] = pixels[i * 4 + 3]
        }
        return out
    }

    private func compare(
        _ gpu: [Float], _ reference: [Float], label: String
    ) -> (p999: Double, max: Double) {
        var errors: [Double] = []
        errors.reserveCapacity(gpu.count / 4 * 3)
        for i in stride(from: 0, to: gpu.count, by: 4) {
            for c in 0..<3 {
                errors.append(abs(Double(gpu[i + c]) - Double(reference[i + c])))
            }
        }
        errors.sort()
        let p999 = errors[min(errors.count - 1, Int(Double(errors.count - 1) * 0.999))]
        let maxErr = errors.last ?? 0
        print("ACES2-GOLDEN [\(label)] p99.9=\(p999) max=\(maxErr) band=1e-5 ceiling=5e-5")
        return (p999, maxErr)
    }

    // MARK: the golden matrix (KD-5)

    func testGoldenKernelAgainstReferenceAllParameterPoints() async throws {
        let metal = try makeMetal()
        var worstP999 = 0.0
        var worstMax = 0.0
        // ① the three baselines (ramp/grid/extreme probes each).
        let baselines: [(String, DrtLimitingSpace, Double)] = [
            ("sdr-rec709-g22-100", .rec709, 100),
            ("hdr-rec2020-st2084-1000", .rec2020, 1000),
            ("p3-p3d65-g22-100", .p3d65, 100),
        ]
        for (name, space, peak) in baselines {
            for probe in ["ramp", "grid", "extreme"] {
                let (pixels, w, h) = probePixels(kind: probe)
                let gpu = try await dispatchAces2(
                    metal, pixels: pixels, width: w, height: h,
                    space: space, peak: peak, rgcOn: true)
                let ref = self.reference(
                    space: space, peak: peak, rgcOn: true,
                    pixels: pixels, width: w, height: h)
                let (p999, maxErr) = compare(gpu, ref, label: "\(name)/\(probe)")
                worstP999 = max(worstP999, p999)
                worstMax = max(worstMax, maxErr)
                XCTAssertLessThanOrEqual(
                    p999, 1e-5, "\(name)/\(probe) p99.9 exceeded the KD-8 band")
                XCTAssertLessThanOrEqual(
                    maxErr, 5e-5, "\(name)/\(probe) max exceeded the hard ceiling")
            }
        }
        // ② the RGC-off point (KD-3's kernel golden face).
        do {
            let (pixels, w, h) = probePixels(kind: "grid")
            let gpu = try await dispatchAces2(
                metal, pixels: pixels, width: w, height: h,
                space: .rec709, peak: 100, rgcOn: false)
            let ref = self.reference(
                space: .rec709, peak: 100, rgcOn: false,
                pixels: pixels, width: w, height: h)
            let (p999, maxErr) = compare(gpu, ref, label: "rgc-off/grid")
            worstP999 = max(worstP999, p999)
            worstMax = max(worstMax, maxErr)
            XCTAssertLessThanOrEqual(p999, 1e-5)
            XCTAssertLessThanOrEqual(maxErr, 5e-5)
        }
        // ③ all seven limiting spaces (the grid probe — 探针小图).
        for space in DrtLimitingSpace.allCases {
            let (pixels, w, h) = probePixels(kind: "grid")
            let gpu = try await dispatchAces2(
                metal, pixels: pixels, width: w, height: h,
                space: space, peak: 100, rgcOn: true)
            let ref = self.reference(
                space: space, peak: 100, rgcOn: true,
                pixels: pixels, width: w, height: h)
            let (p999, maxErr) = compare(gpu, ref, label: "limit-\(space.rawValue)/grid")
            worstP999 = max(worstP999, p999)
            worstMax = max(worstMax, maxErr)
            XCTAssertLessThanOrEqual(p999, 1e-5)
            XCTAssertLessThanOrEqual(maxErr, 5e-5)
        }
        print("ACES2-GOLDEN WORST p99.9=\(worstP999) max=\(worstMax)")
    }

    func testGoldenIsBitExactAcrossRepeatedRuns() async throws {
        let metal = try makeMetal()
        let (pixels, w, h) = probePixels(kind: "grid")
        let first = try await dispatchAces2(
            metal, pixels: pixels, width: w, height: h,
            space: .rec709, peak: 100, rgcOn: true)
        let second = try await dispatchAces2(
            metal, pixels: pixels, width: w, height: h,
            space: .rec709, peak: 100, rgcOn: true)
        XCTAssertEqual(first, second, "same PSO + same input = bit-identical planes")
    }

    // MARK: the dispatch face (AC#6 / AC#3)

    func testBothMethodArmsAreReachableAndDiverge() async throws {
        let metal = try makeMetal()
        let (pixels, w, h) = probePixels(kind: "grid")
        let aces = try await dispatchAces2(
            metal, pixels: pixels, width: w, height: h,
            space: .rec709, peak: 100, rgcOn: true)
        // The OpenDRT arm (the existing P1 kernel, direct dispatch).
        let input = makeTexture(metal, width: w, height: h)
        pixels.withUnsafeBytes {
            input.replace(region: MTLRegionMake2D(0, 0, w, h),
                          mipmapLevel: 0, withBytes: $0.baseAddress!,
                          bytesPerRow: w * 16)
        }
        var uniforms = DrtUniforms(record: DrtRecord(), cwp: 2)
        let uniformBuffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<DrtUniforms>.stride)!
        let output = makeTexture(metal, width: w, height: h)
        try await metal.dispatch2DTexture(
            functionName: "drt_opendrt", input: input, output: output,
            configure: { encoder in
                encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
            })
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var open = [Float](repeating: 0, count: w * h * 4)
        output.getBytes(&open, bytesPerRow: w * 16,
                        from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        XCTAssertNotEqual(aces, open, "the two method arms must diverge")
    }

    func testOpenDRTPathNeverRunsTheRGC() async throws {
        // AC#3's dispatch face: the OpenDRT kernel output still matches its
        // RGC-FREE Float64 reference (a live single-probe check — the full
        // matrix lives in the P1 golden file; if the aces20 RGC leaked into
        // this path, this parity would break).
        let metal = try makeMetal()
        let (pixels, w, h) = probePixels(kind: "grid")
        let input = makeTexture(metal, width: w, height: h)
        pixels.withUnsafeBytes {
            input.replace(region: MTLRegionMake2D(0, 0, w, h),
                          mipmapLevel: 0, withBytes: $0.baseAddress!,
                          bytesPerRow: w * 16)
        }
        var uniforms = DrtUniforms(record: DrtRecord(), cwp: 2)
        let uniformBuffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<DrtUniforms>.stride)!
        let output = makeTexture(metal, width: w, height: h)
        try await metal.dispatch2DTexture(
            functionName: "drt_opendrt", input: input, output: output,
            configure: { encoder in
                encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
            })
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var gpu = [Float](repeating: 0, count: w * h * 4)
        output.getBytes(&gpu, bytesPerRow: w * 16,
                        from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var ref = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let linear = SIMD3<Double>(
                Double(pixels[i * 4]), Double(pixels[i * 4 + 1]), Double(pixels[i * 4 + 2]))
            let transformed = OpenDrtReference.run(
                record: DrtRecord(), linearRec2020: linear, cwp: 2)
            ref[i * 4 + 0] = Float(transformed.x)
            ref[i * 4 + 1] = Float(transformed.y)
            ref[i * 4 + 2] = Float(transformed.z)
            ref[i * 4 + 3] = pixels[i * 4 + 3]
        }
        let (p999, _) = compare(gpu, ref, label: "opendrt-no-rgc/grid")
        XCTAssertLessThanOrEqual(p999, 1e-5, "OpenDRT parity broke (RGC leak?)")
    }
}
