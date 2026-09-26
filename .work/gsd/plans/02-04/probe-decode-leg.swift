import CoreImage
import Foundation
import LightamerCore
import Metal

// Isolate: does the PIPE's decode leg (pool renderToTexture) produce the
// same linear-Rec2020 plane as a CI direct render? (real RAW, 1120)
nonisolated(unsafe) var exitCode = 0
let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    let metal = try MetalContext()
    let decoded = try await RAWDecoder().decode(URL(fileURLWithPath: "input/RAW/DSC09991.ARW"))
    let longEdge = 1120
    let extent = decoded.ciImage.extent
    let sc = min(CGFloat(longEdge) / extent.width, CGFloat(longEdge) / extent.height, 1.0)
    let scaled = decoded.ciImage.transformed(by: CGAffineTransform(scaleX: sc, y: sc))
    let w = Int(scaled.extent.width), h = Int(scaled.extent.height)
    print("plane \(w)x\(h)")

    // Leg 1: the pool path (what the pipe uses)
    let pipeInput = try await metal.renderToTexture(decoded.ciImage, longEdge: longEdge)
    let fence = metal.commandQueue.makeCommandBuffer()!
    let drained = DispatchSemaphore(value: 0)
    fence.addCompletedHandler { _ in drained.signal() }
    fence.commit(); drained.wait()
    var a = [Float](repeating: 0, count: w * h * 4)
    a.withUnsafeMutableBytes {
        pipeInput.getBytes($0.baseAddress!, bytesPerRow: w * 16,
                           from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    }

    // Leg 2: CI direct float render in linear Rec2020 (twice, same context)
    let ctx = CIContext(options: [.workingColorSpace: WorkingSpace.colorSpace,
                                  .outputColorSpace: WorkingSpace.colorSpace])
    var b = [Float](repeating: 0, count: w * h * 4)
    var c = [Float](repeating: 0, count: w * h * 4)
    ctx.render(scaled, toBitmap: &b, rowBytes: w * 16, bounds: scaled.extent, format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
    ctx.render(scaled, toBitmap: &c, rowBytes: w * 16, bounds: scaled.extent, format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)

    func stats(_ x: [Float], _ y: [Float], tag: String) {
        var mad: Double = 0; var mx: Float = 0
        for i in 0..<x.count { let d = abs(x[i] - y[i]); mad += Double(d); mx = max(mx, d) }
        print("\(tag): meanAbsDiff \(String(format: "%.6f", mad / Double(x.count))) max \(mx)")
    }
    stats(b, c, tag: "CI-direct run1 vs run2 (same context)")
    stats(a, b, tag: "pool-leg vs CI-direct")
    // channel means
    for (tag, arr) in [("pool", a), ("ci", b)] {
        var m = [Double](repeating: 0, count: 4)
        for i in stride(from: 0, to: arr.count, by: 4) { for ch in 0..<4 { m[ch] += Double(arr[i + ch]) } }
        let n = Double(w * h)
        print("\(tag) channel means RGBA: " + m.map { String(format: "%.4f", $0 / n) }.joined(separator: ", "))
    }
    exitCode = 0
}
semaphore.wait()
exit(Int32(exitCode))
