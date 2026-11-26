// crop.swift: crop a PNG to a pixel rect. No dependencies, AppKit only.
// usage: crop <in.png> <x> <y> <w> <h> <out.png>   (pixels, top-left origin)
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 6,
      let x = Double(args[1]), let y = Double(args[2]),
      let w = Double(args[3]), let h = Double(args[4]) else {
    print("usage: crop <in.png> <x> <y> <w> <h> <out.png>")
    exit(2)
}
guard let image = NSImage(contentsOfFile: args[0]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("crop: cannot read \(args[0])")
    exit(1)
}
// CoreGraphics `cropping(to:)` takes top-left-origin pixel rects: no flip.
let rect = CGRect(x: x, y: y, width: w, height: h)
guard let part = cg.cropping(to: rect) else {
    print("crop: rect out of range")
    exit(1)
}
let out = NSImage(cgImage: part, size: NSSize(width: w, height: h))
guard let tiff = out.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("crop: encode failed")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: args[5]))
print("crop: wrote \(args[5]) \(Int(w))x\(Int(h))")
