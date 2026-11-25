// S4 Swift reference host — same input, same shaders, same constants/dispatch.
import Foundation
import Metal

let W = 257, H = 193
let shaderDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "shaders"
guard let device = MTLCreateSystemDefaultDevice() else { FileHandle.standardError.write("no Metal device\n".data(using: .utf8)!); exit(2) }
print("device: \(device.name)")

let src = try String(contentsOfFile: shaderDir + "/Passthrough.metal", encoding: .utf8)
    + "\n" + (try String(contentsOfFile: shaderDir + "/ExposureKernels.metal", encoding: .utf8)) + "\n"
let lib = try device.makeLibrary(source: src, options: nil)

var useSrgb = false
var ev: Float = 0.5
let consts = MTLFunctionConstantValues()
consts.setConstantValue(&useSrgb, type: .bool, index: 0)
consts.setConstantValue(&ev, type: .float, index: 1)
let fPass = try lib.makeFunction(name: "pass_through", constantValues: consts)
let pPass = try device.makeComputePipelineState(function: fPass)
let fExp = lib.makeFunction(name: "exposure_apply")!
let pExp = try device.makeComputePipelineState(function: fExp)

let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: W, height: H, mipmapped: false)
desc.usage = [.shaderRead, .shaderWrite]
desc.storageMode = .shared
let texIn = device.makeTexture(descriptor: desc)!
let texMid = device.makeTexture(descriptor: desc)!
let texOut = device.makeTexture(descriptor: desc)!

let region = MTLRegionMake2D(0, 0, W, H)
let input = try Data(contentsOf: URL(fileURLWithPath: "out/s4-input.bin"))
precondition(input.count == W * H * 16)
input.withUnsafeBytes { texIn.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: W * 16) }

let queue = device.makeCommandQueue()!
let cb = queue.makeCommandBuffer()!
let enc = cb.makeComputeCommandEncoder()!
enc.setComputePipelineState(pPass)
enc.setTexture(texIn, index: 0)
enc.setTexture(texMid, index: 1)
let tg = MTLSize(width: 16, height: 16, depth: 1)
let groups = MTLSize(width: (W + 15) / 16, height: (H + 15) / 16, depth: 1)
enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
enc.endEncoding()

var u: (Float, Float) = (0.02, 1.35)
let enc2 = cb.makeComputeCommandEncoder()!
enc2.setComputePipelineState(pExp)
enc2.setTexture(texMid, index: 0)
enc2.setTexture(texOut, index: 1)
withUnsafeBytes(of: &u) { enc2.setBytes($0.baseAddress!, length: 8, index: 0) }
enc2.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
enc2.endEncoding()
cb.commit()
cb.waitUntilCompleted()

var out = [UInt8](repeating: 0, count: W * H * 16)
texOut.getBytes(&out, bytesPerRow: W * 16, from: region, mipmapLevel: 0)
try Data(out).write(to: URL(fileURLWithPath: "out/s4-swift.bin"))
let f = out.withUnsafeBytes { $0.bindMemory(to: Float.self) }
print(String(format: "first texel rgba = [%.6f, %.6f, %.6f, %.1f]", f[0], f[1], f[2], f[3]))
print("wrote out/s4-swift.bin (\(out.count) bytes)")
