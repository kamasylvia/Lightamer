import CoreImage
import CoreGraphics
import Foundation

// Which CIContext configuration actually lands linear-Rec2020 in the bitmap?
let rec2020 = CGColorSpace(name: CGColorSpace.linearITUR_2020)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// A 1×3 sRGB-tagged image with pure R,G,B linear-encoded at 50%: use CGImage
// from raw bytes (sRGB-encoded values: red 255,0,0 etc.)
func makeSource() -> CIImage {
    let px: [UInt8] = [255, 0, 0, 255,   0, 255, 0, 255,   0, 0, 255, 255]
    var data = px
    let provider = CGDataProvider(data: Data(data) as CFData)!
    let cg = CGImage(width: 3, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                     bytesPerRow: 12, space: srgb,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: false, intent: .perceptual)!
    return CIImage(cgImage: cg)
}

func render(tag: String, options: [CIContextOption: Any], perRenderSpace: CGColorSpace?) {
    let ctx = CIContext(options: options)
    var buf = [Float](repeating: -1, count: 12)
    let ci = makeSource()
    ctx.render(ci, toBitmap: &buf, rowBytes: 48, bounds: ci.extent,
               format: CIFormat.RGBAf, colorSpace: perRenderSpace)
    let names: [String] = ["R", "G", "B"]
    for p in 0..<3 {
        let o = p * 4
        print("\(tag) \(names[p]): " + (0..<3).map { String(format: "%.4f", buf[o + $0]) }.joined(separator: ", "))
    }
    print("  expect Rec2020-linear: R=(0.7913,0.1185,0.0000) G=(0.0610,1.1919,-0.0405) B=(-0.0001,0.0000,1.1062)")
    print("  expect sRGB-linear:    R=(1,0,0) G=(0,1,0) B=(0,0,1)")
}

render(tag: "A working=Rec2020 output=Rec2020 perRender=Rec2020",
       options: [.workingColorSpace: rec2020, .outputColorSpace: rec2020], perRenderSpace: rec2020)
render(tag: "B default-context perRender=Rec2020",
       options: [:], perRenderSpace: rec2020)
render(tag: "C working=Rec2020 output=Rec2020 perRender=nil",
       options: [.workingColorSpace: rec2020, .outputColorSpace: rec2020], perRenderSpace: nil)
