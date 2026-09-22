import Foundation
import LightamerCore
import LightamerIOP
import Metal

let file = URL(fileURLWithPath: CommandLine.arguments[1])
let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    do {
        let decoder = RAWDecoder()
        let metal = try MetalContext()
        try? await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        print("decoding \(file.lastPathComponent) …")
        let img = try await decoder.decode(file)
        print("decoded: \(img.ciImage.extent) colorSpace=\(img.ciImage.colorSpace.map { $0.name as String? ?? "unnamed" } ?? "nil") decoderVersion=\(img.decoderVersionUsed)")
        let rendered = try await RenderPipeline.render(image: img, layerStack: LayerStack(baseLayer: BackgroundLayer()), metal: metal)
        print("rendered texture: \(rendered.width)x\(rendered.height) pixelFormat=\(rendered.pixelFormat)")
        // 采样中心 5x5 像素
        let w = rendered.width, h = rendered.height
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let region = MTLRegionMake2D(w / 2, h / 2, 4, 4)
        rendered.getBytes(&pixels, bytesPerRow: 64, from: region, mipmapLevel: 0)
        var sum = 0
        for i in stride(from: 0, to: pixels.count, by: 4) { sum += Int(pixels[i]) + Int(pixels[i+1]) + Int(pixels[i+2]) }
        print("center 4x4 avg channel value: \(sum / (16 * 3)) (0=black)")
    } catch {
        print("ERROR: \(error)")
    }
}
semaphore.wait()
