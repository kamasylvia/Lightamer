// Plan 02-03 headless smoke — the multi-resolution vertebra through the
// PUBLIC surface, on a REAL RAW fixture:
//   PREVIEW at D-C3 bucket 2560 (scale-at-entry, sized plane, non-black)
//   FULL on-demand (scale 1.0, extent-sized, non-black)
//   THUMBNAIL fixed 360 (scaled plane)
//   EXPORT typed .notImplemented stub
// Same imageID + shared PipeCache across runs (cross-resolution namespace).
// Not part of any build target (per the .work process-files convention).

import Foundation
import LightamerCore
import LightamerIOP
import Metal

let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
nonisolated(unsafe) var failures = 0
nonisolated func check(_ ok: Bool, _ label: String) {
    print("\(ok ? "PASS" : "FAIL")  \(label)")
    if !ok { failures += 1 }
}

let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    do {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(fixture)
        let extent = decoded.ciImage.extent
        print("decoded \(fixture.lastPathComponent) \(Int(extent.width))x\(Int(extent.height)) decoder=\(decoded.decoderVersionUsed.rawValue)")
        check(Int(extent.width) >= 6000, "0. 60MP-class fixture decoded")

        let cache = PipeCache()
        let imageID = UUID()
        let gain = ModuleBox(module: TestGainModule(), multiPriority: 0, multiName: "g")
        await gain.setParams(TestGainModule.Params(gain: 1.0))
        let instances: [any ModuleBoxing] = [gain]

        func probe(_ texture: any MTLTexture) -> (finite: Bool, mean: Float) {
            // The pipe COMMITS its dispatches without waiting (same-queue
            // ordering is the only pipe-side guarantee) — drain the queue
            // before reading pixels (01-04 pattern).
            let drain = metal.commandQueue.makeCommandBuffer()!
            let semaphore = DispatchSemaphore(value: 0)
            drain.addCompletedHandler { _ in semaphore.signal() } // BEFORE commit
            drain.commit()
            semaphore.wait()
            var samples: [Float] = []
            let stride = max(texture.width / 4, 1)
            for py in 0..<4 {
                for px in 0..<4 {
                    var pixel = [Float](repeating: 0, count: 4)
                    texture.getBytes(
                        &pixel, bytesPerRow: texture.width * WorkingSpace.bytesPerPixel,
                        from: MTLRegionMake2D(
                            min(px * stride, texture.width - 1), min(py * stride, texture.height - 1), 1, 1
                        ),
                        mipmapLevel: 0
                    )
                    samples += pixel
                }
            }
            let finite = samples.allSatisfy { $0.isFinite }
            let mean = samples.reduce(0, +) / Float(samples.count)
            return (finite, mean)
        }

        // 1. PREVIEW at the D-C3 bucket — scale-at-entry, NEVER a 60MP plane.
        let (preview, _) = try await RenderPipeline.process(
            image: decoded, instances: instances, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 2560
        )
        check(max(preview.width, preview.height) == 2560,
              "1a. PREVIEW long edge == 2560 (\(preview.width)x\(preview.height))")
        let p = probe(preview)
        check(p.finite, "1b. PREVIEW pixels finite")
        check(p.mean > 0.001, "1c. PREVIEW non-black (mean \(p.mean))")

        // 2. FULL on-demand — scale 1.0, extent-sized.
        let (full, fullStats) = try await RenderPipeline.process(
            image: decoded, instances: instances, imageID: imageID,
            resolution: .full, cache: cache, metal: metal, longEdge: nil
        )
        check(full.width == Int(extent.width) && full.height == Int(extent.height),
              "2a. FULL == extent (\(full.width)x\(full.height))")
        let f = probe(full)
        check(f.finite && f.mean > 0.001, "2b. FULL finite + non-black (mean \(f.mean))")
        check(fullStats.misses == 2, "2c. FULL caches input+final only (misses \(fullStats.misses))")

        // 3. THUMBNAIL — fixed 360.
        let (thumb, _) = try await RenderPipeline.process(
            image: decoded, instances: instances, imageID: imageID,
            resolution: .thumbnail, cache: cache, metal: metal, longEdge: nil
        )
        check(max(thumb.width, thumb.height) == 360,
              "3. THUMBNAIL long edge == 360 (\(thumb.width)x\(thumb.height))")

        // 4. EXPORT — typed placeholder.
        do {
            _ = try await RenderPipeline.process(
                image: decoded, instances: instances, imageID: imageID,
                resolution: .export, cache: cache, metal: metal, longEdge: nil
            )
            check(false, "4. EXPORT should have thrown")
        } catch let error as AppError {
            if case .notImplemented = error {
                check(true, "4. EXPORT typed .notImplemented")
            } else {
                check(false, "4. EXPORT threw wrong error \(error)")
            }
        }

        let total = await cache.totalBytes
        check(total > 0, "5. cache byte-accounting live (\(total) bytes)")

        print(failures == 0 ? "SMOKE PASS" : "SMOKE FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    } catch {
        print("SMOKE ERROR: \(error)")
        exit(2)
    }
}
struct SmokeError: Error { let message: String; init(_ m: String) { message = m } }
semaphore.wait()
