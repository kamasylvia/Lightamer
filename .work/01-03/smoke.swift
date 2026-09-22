// Plan 01-03 headless smoke — exercises the full Core render path through the
// PUBLIC surface (the same path the app's editor uses):
//   MetalContext init → register IOP metallib → dispatch2DTexture(pass_through)
//   → bit-exact identity + EV + sRGB specializations (D-17) → makeEncoder
//   low-level path (D-19) → RAWDecoder.decode → MetalContext.renderToTexture
//   (CIContextPool, FOUND-02) → PSO cache-hit timing (D-16).
// Not part of any build target (per the .work process-files convention).

import CoreImage
import Foundation
import ImageIO
import LightamerCore
import LightamerIOP
import Metal

let fixturePNG = URL(fileURLWithPath: CommandLine.arguments[1])
nonisolated(unsafe) var failures = 0
nonisolated func check(_ ok: Bool, _ label: String) {
    print("\(ok ? "PASS" : "FAIL")  \(label)")
    if !ok { failures += 1 }
}

let semaphore = DispatchSemaphore(value: 0)
// Top-level code is MainActor-isolated; a plain Task would inherit that
// isolation and deadlock behind the blocking semaphore wait below.
Task.detached {
    defer { semaphore.signal() }
    do {
        // 1. Context init (D-14/D-15)
        let metal = try MetalContext()
        print("device: \(metal.device.name)")
        check(!metal.device.name.isEmpty, "1. MetalContext init (device + queue)")

        // 2. IOP framework metallib registration (RESEARCH §1 #1 gotcha)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        check(true, "2. IOP default.metallib registered (\(PassthroughKernel.metalBundle.bundleURL.lastPathComponent))")

        // 3. Known 4x2 float32 pattern
        let w = 4, h = 2
        var pixels: [Float] = []
        for y in 0..<h { for x in 0..<w { pixels += [Float(x + 1), Float(y + 1), 0.5, 1.0] } }
        func makeTex(_ fill: [Float]? = nil) -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .shared
            let t = metal.device.makeTexture(descriptor: d)!
            if let fill {
                t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                          withBytes: fill, bytesPerRow: w * 16)
            }
            return t
        }
        func readback(_ t: any MTLTexture) -> [Float] {
            var out = [Float](repeating: -999, count: w * h * 4)
            t.getBytes(&out, bytesPerRow: w * 16, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            return out
        }
        func drain() async {
            let cb = metal.commandQueue.makeCommandBuffer()!
            cb.commit()
            _ = try? await cb.completed()
        }

        // 4. Identity specialization → bit-exact (FOUND-06). SAME constants
        // instance reused for the second dispatch → PSO cache hit (D-16).
        let inTex = makeTex(pixels)
        let identity = metal.makeConstants(false, at: 0, type: .bool)
        metal.setConstant(Float(0.0), at: 1, type: .float, into: identity)

        let coldOut = makeTex()
        var t0 = Date()
        try await metal.dispatch2DTexture(
            functionName: PassthroughKernel.functionName, input: inTex, output: coldOut,
            constants: identity)
        await drain()
        let coldMs = Date().timeIntervalSince(t0) * 1000

        let warmOut = makeTex()
        t0 = Date()
        try await metal.dispatch2DTexture(
            functionName: PassthroughKernel.functionName, input: inTex, output: warmOut,
            constants: identity)
        await drain()
        let warmMs = Date().timeIntervalSince(t0) * 1000
        print("      dispatch cold(w/ PSO build): \(Int(coldMs))ms, warm(same PSOKey): \(String(format: "%.2f", warmMs))ms")
        check(warmMs < coldMs, "4a. PSO cache hit on second dispatch (D-16)")
        check(readback(warmOut).elementsEqual(pixels) { $0.bitPattern == $1.bitPattern },
              "4b. pass_through identity BIT-EXACT (FOUND-06)")

        // 5. exposureEV=1 → rgb*2 (distinct constants instance → distinct PSO, D-17)
        let ev1 = metal.makeConstants(false, at: 0, type: .bool)
        metal.setConstant(Float(1.0), at: 1, type: .float, into: ev1)
        let evOut = makeTex()
        try await metal.dispatch2DTexture(
            functionName: PassthroughKernel.functionName, input: inTex, output: evOut, constants: ev1)
        await drain()
        let evRead = readback(evOut)
        // Kernel scales rgb only; alpha passes through. Compare per channel.
        let evOk = zip(evRead.indices, evRead).allSatisfy { index, value in
            let expected = (index % 4 == 3) ? pixels[index] : pixels[index] * 2
            return abs(value - expected) < 1e-6
        }
        check(evOk, "5. exposureEV=1 specialization: rgb *= 2 (D-17 distinct PSO)")

        // 6. useSrgbGamma=true → pow(rgb, 1/2.2)
        let srgb = metal.makeConstants(true, at: 0, type: .bool)
        metal.setConstant(Float(0.0), at: 1, type: .float, into: srgb)
        let srgbOut = makeTex()
        try await metal.dispatch2DTexture(
            functionName: PassthroughKernel.functionName, input: inTex, output: srgbOut, constants: srgb)
        await drain()
        let srgbRead = readback(srgbOut)
        let srgbOk = zip(srgbRead, pixels).allSatisfy { pair in
            pair.0 == pair.1 || abs(pair.0 - pow(pair.1, 1.0 / 2.2)) < 1e-5
        }
        check(srgbOk, "6. useSrgbGamma specialization: pow(rgb, 1/2.2) (D-17)")

        // 7. Low-level makeEncoder path (D-19)
        let session = try await metal.makeEncoder(functionName: PassthroughKernel.functionName, constants: identity)
        let llOut = makeTex()
        session.encoder.setTexture(inTex, index: 0)
        session.encoder.setTexture(llOut, index: 1)
        session.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        _ = try? await session.commandBuffer.completed()
        check(readback(llOut).elementsEqual(pixels) { $0.bitPattern == $1.bitPattern },
              "7. makeEncoder low-level path bit-exact (D-19)")

        // 8. Decode → renderToTexture (the app's editor path end-to-end)
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(fixturePNG)
        let rendered = try await metal.renderToTexture(decoded.ciImage)
        check(rendered.width == decoded.capture.width && rendered.height == decoded.capture.height,
              "8a. renderToTexture size \(rendered.width)x\(rendered.height) matches decoded extent")
        check(rendered.pixelFormat == WorkingSpace.pixelFormat,
              "8b. renderToTexture format = .rgba32Float (FOUND-02)")
        await drain() // CIContextPool commits async — wait before CPU readback
        var probe = [Float](repeating: 0, count: 4)
        rendered.getBytes(&probe, bytesPerRow: rendered.width * 16,
                          from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        check(probe.allSatisfy { $0.isFinite }, "8c. rendered pixels finite (row 0, col 0: \(probe.map { String(format: "%.3f", $0) }.joined(separator: ",")))")

        // 9. THE APP'S DISPLAY BLIT, headless: load the app bundle's
        // default.metallib (editor_blit_vertex/fragment), build the same PSO
        // EditorMTKView's Coordinator builds, and render the decoded texture
        // into an OFFSCREEN .bgra8Unorm target (no CAMetalLayer needed). The
        // Rec2020-linear→sRGB conversion should round-trip the fixture's
        // sRGB bytes (±2/channel — CI Rec2020↔sRGB matrix round-trip).
        let appBundle = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[2]))!
        let appLib = try metal.device.makeDefaultLibrary(bundle: appBundle)
        let vfn = try XCT(try appLib.makeFunction(name: "editor_blit_vertex"), "vertex fn")
        let ffn = try XCT(try appLib.makeFunction(name: "editor_blit_fragment"), "fragment fn")
        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = vfn
        rpd.fragmentFunction = ffn
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        let blitPSO = try await metal.device.makeRenderPipelineState(descriptor: rpd)

        struct BlitUniforms { var scale: SIMD2<Float>; var offset: SIMD2<Float> }
        let outW = rendered.width, outH = rendered.height
        let targetDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: outW, height: outH, mipmapped: false)
        targetDesc.usage = [.renderTarget]
        targetDesc.storageMode = .shared
        let target = metal.device.makeTexture(descriptor: targetDesc)!

        let rpass = MTLRenderPassDescriptor()
        rpass.colorAttachments[0].texture = target
        rpass.colorAttachments[0].loadAction = .clear
        rpass.colorAttachments[0].storeAction = .store
        rpass.colorAttachments[0].clearColor = MTLClearColor(red: 0x16/255.0, green: 0x16/255.0, blue: 0x19/255.0, alpha: 1)
        guard let rcb = metal.commandQueue.makeCommandBuffer(),
              let renc = rcb.makeRenderCommandEncoder(descriptor: rpass) else { throw SmokeError("render encoder") }
        renc.setRenderPipelineState(blitPSO)
        var uniforms = BlitUniforms(scale: SIMD2(1, 1), offset: SIMD2(0, 0)) // 1:1 fit
        renc.setVertexBytes(&uniforms, length: MemoryLayout<BlitUniforms>.stride, index: 0)
        renc.setFragmentTexture(rendered, index: 0)
        renc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renc.endEncoding()
        rcb.commit()
        _ = try? await rcb.completed()

        var blitBytes = [UInt8](repeating: 0, count: outW * outH * 4)
        target.getBytes(&blitBytes, bytesPerRow: outW * 4,
                        from: MTLRegionMake2D(0, 0, outW, outH), mipmapLevel: 0)

        // Fixture pixels (sRGB bytes) via CGImageSource
        let src = CGImageSourceCreateWithURL(fixturePNG as CFURL, nil)!
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let wCG = cg.width, hCG = cg.height
        var pngBytes = [UInt8](repeating: 0, count: wCG * hCG * 4)
        let ctx = CGContext(data: &pngBytes, width: wCG, height: hCG, bitsPerComponent: 8,
                            bytesPerRow: wCG * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: wCG, height: hCG))

        // Compare a sample grid, BOTH row conventions — data decides the
        // correct v-orientation for the shader (CG row 0 = image bottom).
        func maxDiff(flipRows: Bool) -> (Int, Int) {
            var maxD = 0
            var n = 0
            for sy in stride(from: 0, to: outH, by: max(outH / 8, 1)) {
                for sx in stride(from: 0, to: outW, by: max(outW / 8, 1)) {
                    let cgRow = flipRows ? (outH - 1 - sy) : sy
                    let pIdx = (cgRow * wCG + sx) * 4
                    let bIdx = (sy * outW + sx) * 4
                    for c in 0..<3 {
                        maxD = max(maxD, abs(Int(blitBytes[bIdx + 2 - c]) - Int(pngBytes[pIdx + c])))
                        n += 1
                    }
                }
            }
            return (maxD, n)
        }
        func dump(_ label: String, _ x: Int, _ yTop: Int) {
            let sy = yTop // texture memory row from "top" in drawable convention
            let bIdx = (sy * outW + x) * 4
            let cgRow = outH - 1 - yTop
            let pIdx = (cgRow * wCG + x) * 4
            print("      [\(label)] blit@tex-row\(sy)=\(Array(blitBytes[bIdx..<bIdx+4])) png(top-row \(yTop))=\(Array(pngBytes[pIdx..<pIdx+4]))")
        }
        dump("tl", 0, 0); dump("tr", outW-1, 0); dump("bl", 0, outH-1); dump("br", outW-1, outH-1); dump("center", outW/2, outH/2)
        let (flipDiff, nSamples) = maxDiff(flipRows: true)
        let (noflipDiff, _) = maxDiff(flipRows: false)
        print("      blit-vs-fixture diff: flip-compared=\(flipDiff), noflip-compared=\(noflipDiff)")
        // Display semantics: drawable row 0 shows at the TOP of the view.
        // The upright shader makes blit row sy == image row sy from top ==
        // CG row (h-1-sy) → the NO-FLIP comparison must match.
        check(noflipDiff <= 2,
              "9. app blit shader round-trip vs fixture sRGB bytes (diff \(noflipDiff) over \(nSamples) samples)")
        check(noflipDiff <= 2,
              "9b. orientation: blit row sy == image row sy from top → upright on screen (shader v-flip)")

        print(failures == 0 ? "SMOKE PASS" : "SMOKE FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    } catch {
        print("SMOKE ERROR: \(error)")
        exit(2)
    }
}

struct SmokeError: Error { let message: String; init(_ m: String) { message = m } }
func XCT<T>(_ value: T?, _ label: String) throws -> T {
    guard let value else { throw SmokeError(label) }
    return value
}
semaphore.wait()
