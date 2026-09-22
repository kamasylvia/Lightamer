import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal

// Visualize the terminal-chain output for the golden fixture (02-04 debug
// harness). Writes an unambiguous P6 PPM + prints the 9 patch samples.

let repo = URL(fileURLWithPath: "Resources/TestFixtures/NeutralTarget.tif")
nonisolated(unsafe) var exitCode = 0

let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    do {
        let metal = try MetalContext()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(repo)
        let registry = ModuleRegistry.makeDefault()
        let chain = await TerminalChain.chain(registry: registry)
        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 512
        )
        print("out: \(texture.width)x\(texture.height) fmt=\(texture.pixelFormat.rawValue) \(stats)")
        // L008 sibling: handler before commit; sync wait.
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
        // Patch samples (512-space cell centers, image-space grid).
        for gy in 0..<3 {
            for gx in 0..<3 {
                let px = min(gx * 171 + 85, w - 1), py = min(gy * 171 + 85, h - 1)
                let o = (py * w + px) * 4
                print("cell(\(gx),\(gy)) rgb=(\(bytes[o + 2]),\(bytes[o + 1]),\(bytes[o]))")
            }
        }
        // P6 PPM (RGB, no byte-order ambiguity).
        var ppm = Data()
        ppm.append(Data("P6\n\(w) \(h)\n255\n".utf8))
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            ppm.append(contentsOf: [bytes[i + 2], bytes[i + 1], bytes[i]])
        }
        try ppm.write(to: URL(fileURLWithPath: ".work/02-04/chain-output.ppm"))
        print("wrote .work/02-04/chain-output.ppm")
    } catch {
        print("FAIL \(error)")
        exitCode = 1
    }
}
semaphore.wait()
exit(Int32(exitCode))

enum TerminalChain {
    static func chain(registry: ModuleRegistry) async -> [any ModuleBoxing] {
        let chain = await registry.makeDefaultChain()
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            await colorout.setParams(.init(outputProfile: .displayP3))
        }
        if let colorin = chain.first(where: { $0.opName == ColorInModule.opName })
            as? ModuleBox<ColorInModule> {
            await colorin.setParams(.init())
        }
        if let gamma = chain.first(where: { $0.opName == GammaModule.opName })
            as? ModuleBox<GammaModule> {
            await gamma.setParams(.init())
        }
        return chain
    }
}
