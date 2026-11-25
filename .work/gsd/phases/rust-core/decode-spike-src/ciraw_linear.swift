 // ciraw_linear.swift — render CIRAW (ARW or DNG) to linear float32 RGBA dump + print props.
 // usage: swiftc -O ciraw_linear.swift -o ciraw_linear && ./ciraw_linear <input> <out.f32>
// Prints: supportedDecoderVersions, decoderVersion in effect, nativeSize,
// neutralChromaticity, and mean of rendered linear RGB (via downscaled readback).
import CoreImage
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: ciraw_linear <input> <out.exr>"); exit(2) }
let url = URL(fileURLWithPath: args[1])

guard let filter = CIRAWFilter(imageURL: url) else { print("CIRAW init failed"); exit(1) }
print("supportedDecoderVersions: \(filter.supportedDecoderVersions)")
filter.decoderVersion = CIRAWDecoderVersion.version8
print("decoderVersion: \(filter.decoderVersion)")
let ns = filter.nativeSize
print("nativeSize: \(Int(ns.width)) x \(Int(ns.height))")
let nc = filter.neutralChromaticity
print(String(format: "neutralChromaticity: (%.6f, %.6f)", nc.x, nc.y))
guard let img = filter.outputImage else { print("no output image"); exit(1) }
let ctx = CIContext(options: [.useSoftwareRenderer: false])
let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
let w = Int(img.extent.width), h = Int(img.extent.height)
print("extent: \(w) x \(h)")
let t0 = Date()
let rowBytes = w * 16
let ptr = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * h, alignment: 16)
ctx.render(img, toBitmap: ptr, rowBytes: rowBytes,
           bounds: CGRect(x: 0, y: 0, width: w, height: h),
           format: .RGBAf, colorSpace: cs)
print(String(format: "render_ms: %.1f", Date().timeIntervalSince(t0) * 1000))
let data = Data(bytesNoCopy: ptr, count: rowBytes * h, deallocator: .free)
do {
  try data.write(to: URL(fileURLWithPath: args[2]))
  print("dump: \(args[2]) bytes=\(rowBytes * h) (float32 RGBA, extended-linear-sRGB)")
} catch {
  print("dump write failed: \(error)"); exit(1)
}
// mean via small downscale readback (cheap sanity, not the comparison path)
let small = img.transformed(by: CGAffineTransform(scaleX: 256 / img.extent.width,
                                                  y: 256 / img.extent.height))
var buf = [UInt8](repeating: 0, count: 256 * 256 * 4)
let cs8 = CGColorSpace(name: CGColorSpace.sRGB)!
buf.withUnsafeMutableBytes { ptr in
  ctx.render(small, toBitmap: ptr.baseAddress!, rowBytes: 256 * 4,
             bounds: CGRect(x: 0, y: 0, width: 256, height: 256),
             format: .RGBA8, colorSpace: cs8)
}
var sr = 0.0, sg = 0.0, sb = 0.0
for i in 0 ..< (256 * 256) { sr += Double(buf[i*4]); sg += Double(buf[i*4+1]); sb += Double(buf[i*4+2]) }
let n = Double(256 * 256)
print(String(format: "thumb_mean_srgb8: %.2f %.2f %.2f", sr/n, sg/n, sb/n))
