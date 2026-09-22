// 复现 app 真实序列：同一 MetalContext 先后渲染 ARW → JPEG（尺寸互换）
import Foundation
import LightamerCore
import LightamerIOP
import Metal

let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    do {
        let metal = try MetalContext()
        try? await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let layerStack = LayerStack(baseLayer: BackgroundLayer())
        let decoder = RAWDecoder()
        func sample(_ tex: any MTLTexture) -> Int {
            let w = tex.width, h = tex.height
            var px = [UInt8](repeating: 0, count: 16 * 4)
            var region = MTLRegionMake2D(w/2, h/2, 4, 1)
            tex.getBytes(&px, bytesPerRow: 64, from: region, mipmapLevel: 0)
            var sum = 0
            for i in stride(from: 0, to: px.count, by: 4) { sum += Int(px[i]) + Int(px[i+1]) + Int(px[i+2]) }
            return sum / 12
        }
        // 第一次：ARW（app 里先加载的）
        let arw = try await decoder.decode(URL(fileURLWithPath: CommandLine.arguments[1]))
        let t1 = try await RenderPipeline.render(image: arw, layerStack: layerStack, metal: metal)
        print("1st ARW: \(t1.width)x\(t1.height) avg=\(sample(t1))")
        // 第二次：JPEG（同一上下文！）
        let jpg = try await decoder.decode(URL(fileURLWithPath: CommandLine.arguments[2]))
        let t2 = try await RenderPipeline.render(image: jpg, layerStack: layerStack, metal: metal)
        print("2nd JPEG: \(t2.width)x\(t2.height) avg=\(sample(t2))")
        // 第三次：再渲染 ARW（确认可逆）
        let arw2 = try await decoder.decode(URL(fileURLWithPath: CommandLine.arguments[1]))
        let t3 = try await RenderPipeline.render(image: arw2, layerStack: layerStack, metal: metal)
        print("3rd ARW: \(t3.width)x\(t3.height) avg=\(sample(t3))")
    } catch {
        print("ERROR: \(error)")
    }
}
semaphore.wait()
