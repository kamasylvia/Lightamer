// Sample a screenshot PNG region: max channel + bright-pixel count, to
// distinguish "dark night photo displayed" from "canvas mat only".
// Usage: swift sample-png.swift <png> <x> <y> <w> <h>
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 6, let image = NSImage(contentsOfFile: args[1]) else {
    print("usage: sample-png <png> <x> <y> <w> <h>"); exit(2)
}
let x = Int(args[2])!, y = Int(args[3])!, w = Int(args[4])!, h = Int(args[5])!
let rect = NSRect(x: x, y: y, width: w, height: h)
guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?
    .cropping(to: CGRect(x: x, y: y, width: w, height: h))
else { print("crop failed"); exit(2) }
// NSImage cgImage origin is top-left after cropping? CGImage cropping uses
// top-left origin pixel space — matches screencapture output.
let width = cg.width, height = cg.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                          bytesPerRow: width * 4, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { print("ctx failed"); exit(2) }
ctx.interpolationQuality = .none
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
var maxV: UInt8 = 0
var bright = 0
var sum = 0
for i in stride(from: 0, to: pixels.count, by: 4) {
    let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
    let m = max(r, max(g, b))
    if m > maxV { maxV = m }
    if m > 100 { bright += 1 }
    sum += Int(m)
}
print("region \(width)x\(height): max=\(maxV) bright(>100)=\(bright)/\(width * height) avgMax=\(sum / (width * height))")
print(bright > 500 ? "VERDICT: CONTENT DISPLAYED" : "VERDICT: CANVAS/EMPTY")
