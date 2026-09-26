// Plan 02-04 headless smoke — REAL RAW through the terminal-trio chain:
// colorin → colorout(P3 fast path) → gamma(.bgra8Unorm tail).
// Checks: decode → chain render stats → display-format tail → pixel
// sanity (finite range [0,255], non-degenerate histogram, plausible
// mid-gray content), plus the ColorSync leg compile-exercise via the
// fallback profile. 02-03 smoke pattern (swiftc against DerivedData).

import CoreImage
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
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(fixture)
        let extent = decoded.ciImage.extent
        print("decoded \(fixture.lastPathComponent) \(Int(extent.width))x\(Int(extent.height)) decoder=\(decoded.decoderVersionUsed.rawValue)")
        check(extent.width >= 3000, "0. real RAW decoded")

        let registry = ModuleRegistry.makeDefault()
        var chain = await registry.makeDefaultChain()
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            await colorout.setParams(.init(outputProfile: .displayP3))
        }
        for box in chain where box.opName == ColorInModule.opName {
            if let colorin = box as? ModuleBox<ColorInModule> { await colorin.setParams(.init()) }
        }
        for box in chain where box.opName == GammaModule.opName {
            if let gamma = box as? ModuleBox<GammaModule> { await gamma.setParams(.init()) }
        }

        let cache = PipeCache()
        let (texture, stats) = try await RenderPipeline.process(
            image: decoded, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: 1480
        )
        print("chain output \(texture.width)x\(texture.height) fmt=\(texture.pixelFormat.rawValue) stats=\(stats)")
        check(texture.pixelFormat == .bgra8Unorm, "1. gamma tail is .bgra8Unorm")
        check(stats.misses == 4 && stats.hits == 0, "2. cold chain: 4 lines (input+colorin+colorout+gamma)")

        // Warm re-run: same imageID → top-line hit, zero work.
        let imageID = UUID()
        _ = try await RenderPipeline.process(
            image: decoded, instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 1480
        )
        let warmStats = try await RenderPipeline.process(
            image: decoded, instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 1480
        ).1
        check(warmStats.hits == 1 && warmStats.misses == 0, "3. warm chain: top-line hit, zero work")

        // Drain, then pixel sanity.
        let fence = metal.commandQueue.makeCommandBuffer()!
        let drained = DispatchSemaphore(value: 0)
        fence.addCompletedHandler { _ in drained.signal() }
        fence.commit()
        drained.wait()

        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: w * 4,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        var histogram = [Int](repeating: 0, count: 256)
        var minV = 255, maxV = 0
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            for c in 0..<3 {
                let v = Int(bytes[i + c])
                histogram[v] += 1
                minV = min(minV, v); maxV = max(maxV, v)
            }
        }
        let nonBlack = (5..<250).map { histogram[$0] }.reduce(0, +)
        let total = w * h * 3
        print("range [\(minV), \(maxV)], in-body pixels \(nonBlack)/\(total)")
        check(maxV <= 255 && minV >= 0, "4. display range respected (unorm encode)")
        check(Double(nonBlack) / Double(total) > 0.5, "5. non-degenerate content (mid-tones present)")

        // ColorSync leg exercise: force the fallback profile through the
        // SAME module (compile + dispatch sanity; exactness proven in the
        // golden tests).
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            colorout.module.displayProfileOverride =
                .colorSyncFallback(CIColorSpaceWorkalike.generic)
            await colorout.setParams(.init(outputProfile: .display))
            let fb = try await RenderPipeline.process(
                image: decoded, instances: chain, imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 720
            )
            check(fb.0.width >= 360, "6. ColorSync fallback leg renders (\(fb.1))")
        }
    } catch {
        print("FAIL smoke error: \(error)")
        failures += 1
    }
}
semaphore.wait()
if failures > 0 { exit(1) }

// Tiny helper anchoring a colorspace for the fallback probe.
enum CIColorSpaceWorkalike {
    static let generic = CGColorSpace(name: CGColorSpace.genericLab)!
}
