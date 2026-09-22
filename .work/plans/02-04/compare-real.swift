import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal

// Our terminal chain vs CI direct render on a real RAW (both 1120), P3
// target. Channel-order correct per leg: pipe memory = BGRA (unswap);
// baseline bitmap = RGBA (as-is). Dumps both legs as PNG-inspectable PPM.

let fixture = URL(fileURLWithPath: "input/RAW/DSC09991.ARW")
nonisolated(unsafe) var exitCode = 0
let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    let metal = try MetalContext()
    let decoded = try await RAWDecoder().decode(fixture)
    let registry = ModuleRegistry.makeDefault()
    let chain = await DefaultChain.p3(registry: registry)
    let longEdge = 1120
    let (texture, _) = try await RenderPipeline.process(
        image: decoded, instances: chain, imageID: UUID(), resolution: .preview,
        cache: PipeCache(), metal: metal, longEdge: longEdge)
    let fence = metal.commandQueue.makeCommandBuffer()!
    let drained = DispatchSemaphore(value: 0)
    fence.addCompletedHandler { _ in drained.signal() }
    fence.commit(); drained.wait()
    let w = texture.width, h = texture.height
    var pipe = [UInt8](repeating: 0, count: w * h * 4)
    pipe.withUnsafeMutableBytes {
        texture.getBytes($0.baseAddress!, bytesPerRow: w * 4,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    }
    let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
    let extent = decoded.ciImage.extent
    let sc = min(CGFloat(longEdge) / extent.width, CGFloat(longEdge) / extent.height, 1.0)
    let scaled = decoded.ciImage.transformed(by: CGAffineTransform(scaleX: sc, y: sc))
    let ctx = CIContext(options: [.workingColorSpace: WorkingSpace.colorSpace,
                                  .outputColorSpace: p3])
    var base = [UInt8](repeating: 0, count: w * h * 4)
    base.withUnsafeMutableBytes {
        ctx.render(scaled, toBitmap: $0.baseAddress!, rowBytes: w * 4,
                   bounds: scaled.extent, format: CIFormat.RGBA8, colorSpace: p3)
    }
    var sumIn = 0.0, sumOut = 0.0, n = 0.0
    var lowEnd = 0, total = 0
    for i in stride(from: 0, to: w * h * 4, by: 4) {
        // pipe memory BGRA → true RGB; baseline memory RGBA → true RGB
        let pr = Int(pipe[i + 2]), pg = Int(pipe[i + 1]), pb = Int(pipe[i])
        let br = Int(base[i]), bg = Int(base[i + 1]), bb = Int(base[i + 2])
        sumIn += Double(abs(pr - br)); sumOut += Double(abs(pb - bb))
        n += 1
        total += 3
        if pr < 60 || pg < 60 || pb < 60 || br < 60 || bg < 60 || bb < 60 { lowEnd += 1 }
        _ = bg
    }
    let rIn = String(format: "%.2f", sumIn / n)
    let rOut = String(format: "%.2f", sumOut / n)
    let pct = String(format: "%.1f", 100.0 * Double(lowEnd) / Double(w * h))
    print("R meanAbsDiff (pipe vs CI): \(rIn)   B meanAbsDiff: \(rOut)")
    print("pixels with any channel <60 (ColorSync low-end zone): \(pct)%")
    func ppm(_ bytes: [UInt8], _ name: String, bgra: Bool) {
        var d = Data()
        d.append(Data("P6\n\(w) \(h)\n255\n".utf8))
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            if bgra { d.append(contentsOf: [bytes[i + 2], bytes[i + 1], bytes[i]]) }
            else { d.append(contentsOf: [bytes[i], bytes[i + 1], bytes[i + 2]]) }
        }
        try? d.write(to: URL(fileURLWithPath: ".work/02-04/\(name).ppm"))
    }
    ppm(pipe, "real-pipe", bgra: true)
    ppm(base, "real-baseline", bgra: false)
    exitCode = 0
}
semaphore.wait()
exit(Int32(exitCode))

enum DefaultChain {
    static func p3(registry: ModuleRegistry) async -> [any ModuleBoxing] {
        let chain = await registry.makeDefaultChain()
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            await colorout.setParams(.init(outputProfile: .displayP3))
        }
        for box in chain where box.opName == ColorInModule.opName {
            if let m = box as? ModuleBox<ColorInModule> { await m.setParams(.init()) }
        }
        for box in chain where box.opName == GammaModule.opName {
            if let m = box as? ModuleBox<GammaModule> { await m.setParams(.init()) }
        }
        return chain
    }
}
