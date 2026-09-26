// Plan 02-01 headless spike — CIContext render-to-MTLTexture warm-up + decode-at-scale.
//
// Tests (02-01-PLAN Task 02-01-02):
//   A. Warm-up hypothesis (N=6 fresh CIContexts): direct render(_:toMTLTexture:)
//      on a FRESH context — Phase 1 found the first render writes NOTHING (6/6).
//      Measure empty-rate without warm-up (render #1) vs with one throwaway
//      warm-up render (render #2). Readback via blit → MTLBuffer.
//   B. Bitmap+replace baseline timing (CIContextPool's current path): 2560px
//      PREVIEW bucket and ≥60MP extent, n=3 medians, ContinuousClock.
//   C. Decode-at-scale (Open Question #3): RAWDecoder.decode(DSC09991.ARW),
//      then render the CIImage at FULL extent vs scaled to 2560px long edge.
//
// Compile/run (same pattern as .work/01-03/smoke.swift, against built Debug frameworks):
//   PROD=~/Library/Developer/Xcode/DerivedData/Lightamer-*/Build/Products/Debug
//   xcrun swiftc -o spike-render-leg spike-render-leg.swift -F "$PROD" -rpath "$PROD"
//   ./spike-render-leg <ARW path> <JPEG path>
// Not part of any build target (.work process-files convention).

import CoreImage
import Foundation
import LightamerCore
import Metal

nonisolated(unsafe) var failures = 0
nonisolated func check(_ ok: Bool, _ label: String) {
    print("\(ok ? "PASS" : "FAIL")  \(label)")
    if !ok { failures += 1 }
}

struct SpikeError: Error { let message: String; init(_ m: String) { message = m } }
func XCT<T>(_ value: T?, _ label: String) throws -> T {
    guard let value else { throw SpikeError(label) }
    return value
}

func ms(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}
func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
}

let semaphore = DispatchSemaphore(value: 0)
// Top-level code is MainActor-isolated; a plain Task would inherit that
// isolation and deadlock behind the blocking semaphore wait below.
Task.detached {
    defer { semaphore.signal() }
    do {
        let arwURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let jpgURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let metal = try MetalContext()
        let device = metal.device
        let queue = metal.commandQueue
        print("device: \(device.name)")

        func makeContext() -> CIContext {
            // Same option set as CIContextPool.init — the spike must exercise
            // the exact configuration the pool uses (WorkingSpace locks).
            CIContext(mtlDevice: device, options: [
                .workingColorSpace: WorkingSpace.colorSpace,   // linear Rec2020
                .outputColorSpace: WorkingSpace.colorSpace,
                .workingFormat: CIFormat.RGBAh,
                .cacheIntermediates: false,                    // CIRAW-4
            ])
        }

        // Direct render + GPU-side truth via blit→MTLBuffer readback.
        // Two sync modes:
        //   .owned — render(_:to:commandBuffer:) with an app-owned buffer,
        //            explicit commit + completed-wait BEFORE the readback blit
        //            (same queue → ordered; the honest app-viable pattern).
        //   .nilBuffer — commandBuffer:nil: CI enqueues on its INTERNAL queue
        //            and returns immediately; the readback blit on the app
        //            queue has NO ordering guarantee (documents the race the
        //            Phase 1 "first-render-empty" observation may have hit).
        // Returns (nonEmpty, elapsedMs — encode+GPU-completed for .owned).
        enum SyncMode { case owned, nilBuffer }
        func renderDirect(_ context: CIContext, _ image: CIImage, _ mode: SyncMode = .owned) async throws -> (Bool, Double) {
            let extent = image.extent
            let w = Int(extent.width), h = Int(extent.height)
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: WorkingSpace.pixelFormat, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .shared
            let texture = try XCT(device.makeTexture(descriptor: desc), "texture alloc")
            let rowBytes = w * WorkingSpace.bytesPerPixel

            let renderBuffer = try XCT(queue.makeCommandBuffer(), "render command buffer")
            let clock = ContinuousClock()
            let elapsed = try await clock.measure {
                context.render(image, to: texture, commandBuffer: mode == .owned ? renderBuffer : nil,
                               bounds: extent, colorSpace: WorkingSpace.colorSpace)
                if mode == .owned {
                    renderBuffer.commit()
                    _ = try await renderBuffer.completed()
                }
            }
            // Blit GPU→CPU and drain (same queue as .owned's render buffer →
            // ordered after it; for .nilBuffer this is intentionally racy).
            let buffer = try XCT(device.makeBuffer(length: rowBytes * h), "readback buffer")
            let cb = try XCT(queue.makeCommandBuffer(), "readback command buffer")
            let blit = try XCT(cb.makeBlitCommandEncoder(), "blit encoder")
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: buffer, destinationOffset: 0,
                      destinationBytesPerRow: rowBytes,
                      destinationBytesPerImage: rowBytes * h)
            blit.endEncoding()
            cb.commit()
            _ = try? await cb.completed()

            let p = buffer.contents().bindMemory(to: Float.self, capacity: w * h * 4)
            var nonZeroCount = 0
            for i in 0..<(w * h * 4) where p[i] != 0 { nonZeroCount += 1 }
            return (nonZeroCount > 0, ms(elapsed))
        }

        // ── TEST A: warm-up hypothesis, N=6 fresh contexts ──────────────
        print("── TEST A: direct render-to-texture (OWNED command buffer), fresh CIContext per round (N=6) ──")
        let decoder = RAWDecoder()
        let probeImage = CIImage(color: CIColor(red: 0.9, green: 0.5, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        var emptyCold = 0
        var emptyWarmed = 0
        for round in 1...6 {
            let context = makeContext()
            let (coldOK, coldMs) = try await renderDirect(context, probeImage, .owned)
            // Warm-up: ONE throwaway direct render on the same context.
            let (_, warmMs) = try await renderDirect(context, probeImage, .owned)
            let (warmedOK, _) = try await renderDirect(context, probeImage, .owned)
            if !coldOK { emptyCold += 1 }
            if !warmedOK { emptyWarmed += 1 }
            print("round \(round): cold=\(coldOK ? "OK" : "EMPTY") (\(String(format: "%.1f", coldMs))ms) warmup=\(String(format: "%.1f", warmMs))ms post-warmup=\(warmedOK ? "OK" : "EMPTY")")
        }
        print("TEST A RESULT: first-render-empty WITHOUT warm-up = \(emptyCold)/6; WITH warm-up = \(emptyWarmed)/6")
        check(emptyWarmed == 0, "A. post-warmup direct renders ALL non-empty (\(6 - emptyWarmed)/6)")

        // A0: the commandBuffer:nil variant on fresh contexts — CI returns in
        // ~0ms and the work lands on an internal queue our readback can race.
        // Documented for the spike report; NOT the app-viable pattern.
        print("── TEST A0: commandBuffer:nil variant (race documentation) ──")
        for round in 1...3 {
            let context = makeContext()
            let (nilOK, nilMs) = try await renderDirect(context, probeImage, .nilBuffer)
            print("round \(round): nil-cb render=\(String(format: "%.1f", nilMs))ms readback=\(nilOK ? "OK" : "EMPTY")")
        }

        // A2: same probe with a REAL image-backed CIImage (CIRAW chain), one
        // extra fresh context — the Phase 1 finding came from decoded images,
        // so the solid-color probe alone could miss a CIRAW-specific variant.
        let decodedJpg = try await decoder.decode(jpgURL)
        let smallScale = 512.0 / Double(max(decodedJpg.ciImage.extent.width, decodedJpg.ciImage.extent.height))
        let smallReal = decodedJpg.ciImage.transformed(by: CGAffineTransform(scaleX: smallScale, y: smallScale))
        let contextReal = makeContext()
        let (realCold, _) = try await renderDirect(contextReal, smallReal)
        _ = try await renderDirect(contextReal, smallReal)
        let (realWarmed, _) = try await renderDirect(contextReal, smallReal)
        print("TEST A2 (real CIRAW-backed CIImage, fresh ctx): cold=\(realCold ? "OK" : "EMPTY") post-warmup=\(realWarmed ? "OK" : "EMPTY")")
        check(realWarmed, "A2. real-image post-warmup direct render non-empty")

        // A3: DEFAULT CIContext (no custom options) + rgba8Unorm + deviceRGB —
        // rules our option set (linear Rec2020 / RGBAh working format /
        // cacheIntermediates:false) in or out as the no-op trigger.
        let defaultContext = CIContext(mtlDevice: device)
        do {
            let w = 8, h = 8
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .shared
            let texture = try XCT(device.makeTexture(descriptor: desc), "A3 texture")
            let cb = try XCT(queue.makeCommandBuffer(), "A3 cb")
            defaultContext.render(probeImage, to: texture, commandBuffer: cb,
                                  bounds: probeImage.extent,
                                  colorSpace: CGColorSpaceCreateDeviceRGB())
            cb.commit()
            _ = try? await cb.completed()
            let buffer = try XCT(device.makeBuffer(length: w * h * 4), "A3 buffer")
            let blitCB = try XCT(queue.makeCommandBuffer(), "A3 blit cb")
            let blit = try XCT(blitCB.makeBlitCommandEncoder(), "A3 blit")
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: buffer, destinationOffset: 0,
                      destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
            blit.endEncoding()
            blitCB.commit()
            _ = try? await blitCB.completed()
            let p = buffer.contents().bindMemory(to: UInt8.self, capacity: w * h * 4)
            var nonZero = 0
            for i in 0..<(w * h * 4) where p[i] != 0 { nonZero += 1 }
            print("TEST A3 (default CIContext, rgba8Unorm, deviceRGB): \(nonZero > 0 ? "OK — writes pixels (option set is the trigger!)" : "EMPTY — host-level no-op even with default context")")
        } catch {
            print("TEST A3 error: \(error)")
        }

        // ── TEST B: bitmap+replace baseline (CIContextPool's current path) ──
        func bitmapRenderTimed(_ context: CIContext, _ image: CIImage) throws -> Double {
            let extent = image.extent
            let w = Int(extent.width), h = Int(extent.height)
            let rowBytes = w * WorkingSpace.bytesPerPixel
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * h, alignment: 64)
            defer { buffer.deallocate() }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: WorkingSpace.pixelFormat, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .shared
            let texture = try XCT(device.makeTexture(descriptor: desc), "texture alloc")
            let clock = ContinuousClock()
            let elapsed = clock.measure {
                context.render(image, toBitmap: buffer, rowBytes: rowBytes, bounds: extent,
                               format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
                texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                                withBytes: buffer, bytesPerRow: rowBytes)
            }
            return ms(elapsed)
        }

        print("── TEST B: bitmap+replace timings (n=3, median reported) ──")
        let context = makeContext()
        let jpgCI = try XCT(CIImage(contentsOf: jpgURL), "JPEG CIImage")
        let jpgW = Int(jpgCI.extent.width), jpgH = Int(jpgCI.extent.height)
        let jpgMP = Double(jpgW * jpgH) / 1e6
        let previewScale = 2560.0 / Double(max(jpgW, jpgH))
        let previewCI = jpgCI.transformed(by: CGAffineTransform(scaleX: previewScale, y: previewScale))
            .cropped(to: CGRect(x: 0, y: 0, width: 2560, height: Int(2560.0 * Double(jpgH) / Double(jpgW))))
        print("fixture: \(jpgURL.lastPathComponent) \(jpgW)x\(jpgH) (\(String(format: "%.1f", jpgMP))MP); preview-scaled \(Int(previewCI.extent.width))x\(Int(previewCI.extent.height))")

        var previewTimes: [Double] = []
        var bFullTimes: [Double] = []
        for run in 1...3 {
            let t = try bitmapRenderTimed(context, previewCI)
            previewTimes.append(t)
            print("preview bitmap+replace run\(run): \(String(format: "%.1f", t))ms")
        }
        for run in 1...3 {
            let t = try bitmapRenderTimed(context, jpgCI)
            bFullTimes.append(t)
            print("full \(String(format: "%.0f", jpgMP))MP bitmap+replace run\(run): \(String(format: "%.1f", t))ms")
        }
        print("TEST B RESULT: preview-2560 median \(String(format: "%.1f", median(previewTimes)))ms; full-\(String(format: "%.0f", jpgMP))MP median \(String(format: "%.1f", median(bFullTimes)))ms")

        // ── TEST C: decode-at-scale (Open Question #3) ──────────────────
        print("── TEST C: decode + render, FULL extent vs scaled to 2560px long edge ──")
        let clock = ContinuousClock()
        let decodeTime = ms(try await clock.measure { _ = try await decoder.decode(arwURL) })
        let decoded = try await decoder.decode(arwURL)
        let srcW = Int(decoded.ciImage.extent.width), srcH = Int(decoded.ciImage.extent.height)
        let srcMP = Double(srcW * srcH) / 1e6
        print("fixture: \(arwURL.lastPathComponent) \(srcW)x\(srcH) (\(String(format: "%.1f", srcMP))MP); decode \(String(format: "%.0f", decodeTime))ms (n=1, CIRAW full)")

        let scaleFactor = 2560.0 / Double(max(srcW, srcH))
        let scaledCI = decoded.ciImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
            .cropped(to: CGRect(x: 0, y: 0, width: 2560, height: Int(2560.0 * Double(srcH) / Double(srcW))))

        // Warm the CIContextPool once so Test C measures steady-state render,
        // not pool/context creation.
        _ = try await metal.renderToTexture(probeImage)
        var cFullTimes: [Double] = []
        var cScaledTimes: [Double] = []
        for run in 1...3 {
            let tFull = ms(try await clock.measure { _ = try await metal.renderToTexture(decoded.ciImage) })
            let tScaled = ms(try await clock.measure { _ = try await metal.renderToTexture(scaledCI) })
            cFullTimes.append(tFull)
            cScaledTimes.append(tScaled)
            print("run\(run): FULL \(String(format: "%.1f", tFull))ms vs scaled-2560 \(String(format: "%.1f", tScaled))ms")
        }
        print("TEST C RESULT: FULL median \(String(format: "%.1f", median(cFullTimes)))ms vs scaled-2560 median \(String(format: "%.1f", median(cScaledTimes)))ms (bitmap leg, incl. texture alloc + replace)")

        print(failures == 0 ? "SPIKE PASS" : "SPIKE FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    } catch {
        print("SPIKE ERROR: \(error)")
        exit(2)
    }
}
semaphore.wait()
