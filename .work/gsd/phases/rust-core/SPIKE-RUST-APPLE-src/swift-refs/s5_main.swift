// S5 — Swift CLI exercising the Rust core through UniFFI:
// sync method, async method, event callback, and an MTLTexture passed as a
// raw pointer (used in place by Rust, no pixel copy).
import Foundation
import Metal

final class Listener: EventListener, @unchecked Sendable {
    let sem = DispatchSemaphore(value: 0)
    var got: String?
    func onEvent(msg: String) {
        got = msg
        sem.signal()
    }
}

@main
struct Main {
    static func main() async {
        let core = Core()
        print("sync:", core.ping(name: "swift"))

        let sum = await core.slowAdd(a: 20, b: 22)
        print("async:", sum)

        let listener = Listener()
        core.setListener(listener: listener)
        core.fireEvent(msg: "hello")
        _ = listener.sem.wait(timeout: .now() + 5)
        print("event:", listener.got ?? "<none>")

        guard let dev = MTLCreateSystemDefaultDevice() else { exit(3) }
        let W = 32, H = 16
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: W, height: H, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let tex = dev.makeTexture(descriptor: desc)!
        var zeros = [UInt8](repeating: 0, count: W * H * 4)
        tex.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: &zeros, bytesPerRow: W * 4)
        let ptr = UInt64(UInt(bitPattern: Unmanaged.passUnretained(tex).toOpaque()))
        print("textureInfo:", core.textureInfo(texturePtr: ptr))
        let ok = core.paintTexture(texturePtr: ptr, r: 12, g: 200, b: 77, a: 255)
        var out = [UInt8](repeating: 0, count: W * H * 4)
        tex.getBytes(&out, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)
        let first = Array(out.prefix(4))
        print("paint:", ok, "firstPixel:", first, "expected: [12, 200, 77, 255]")
        if first == [12, 200, 77, 255] {
            print("TEXTURE POINTER PATH OK (u64 across FFI, API copies only)")
        }
    }
}
