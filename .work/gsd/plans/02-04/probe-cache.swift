import CoreImage
import Foundation
import LightamerCore

// Reproduce the display-change invalidation chain outside XCTest.
let metal = try MetalContext()
let registry = ModuleRegistry.makeDefault()
let chain = await TerminalChain.chain(registry: registry) // commits .display explicit
let colorout = chain.first { $0.opName == ColorOutModule.opName } as! ModuleBox<ColorOutModule>
colorout.module.displayProfileOverride = .displayP3
await colorout.setParams(.init(outputProfile: .display))
print("pinned .displayP3: paramsHash = \(colorout.paramsHash)")
let ci = CIImage(color: CIColor(red: 0.42, green: 0.51, blue: 0.63)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
let image = DecodedImage(ciImage: ci, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(), segmentationSkyMatte: nil, decoderVersionUsed: .v8)
let cache = PipeCache()
let imageID = UUID()
func run() async -> RenderPipeline.PipeRunStats {
    try! await RenderPipeline.process(image: image, instances: chain, imageID: imageID, resolution: .preview, cache: cache, metal: metal, longEdge: 256).1
}
let s1 = await run(); print("run1", s1)
let s2 = await run(); print("run2", s2)
colorout.module.displayProfileOverride = .sRGB
await colorout.setParams(.init(outputProfile: .display))
print("after override .sRGB recommit: paramsHash = \(colorout.paramsHash)")
let s3 = await run(); print("run3", s3)
colorout.module.displayProfileOverride = .displayP3
await colorout.setParams(.init(outputProfile: .display))
print("after override back .displayP3: paramsHash = \(colorout.paramsHash)")
let s4 = await run(); print("run4", s4)
enum TerminalChain {
    static func chain(registry: ModuleRegistry) async -> [any ModuleBoxing] {
        let chain = await registry.makeDefaultChain()
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName }) as? ModuleBox<ColorOutModule> {
            await colorout.setParams(.init(outputProfile: .display))
        }
        if let colorin = chain.first(where: { $0.opName == ColorInModule.opName }) as? ModuleBox<ColorInModule> {
            await colorin.setParams(.init())
        }
        if let gamma = chain.first(where: { $0.opName == GammaModule.opName }) as? ModuleBox<GammaModule> {
            await gamma.setParams(.init())
        }
        return chain
    }
}
