import CoreImage
import Foundation
import CoreGraphics

let url = URL(fileURLWithPath: "Resources/TestFixtures/NeutralTarget.tif")
guard let ci = CIImage(contentsOf: url) else { fatalError("CIImage") }
let srgbLinear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
let ctx = CIContext(options: [.workingColorSpace: srgbLinear, .outputColorSpace: srgbLinear])
let w = Int(ci.extent.width), h = Int(ci.extent.height)
var buf = [Float](repeating: 0, count: w * h * 4)
ctx.render(ci, toBitmap: &buf, rowBytes: w * 16, bounds: ci.extent, format: CIFormat.RGBAf, colorSpace: srgbLinear)
func sample(_ gx: Int, _ gy: Int) -> String {
    let px = gx * 341 + 170, py = gy * 341 + 170
    let i = (py * w + px) * 4
    return String(format: "(%.4f,%.4f,%.4f)", buf[i], buf[i+1], buf[i+2])
}
for gy in 0..<3 { var parts: [String] = []; for gx in 0..<3 { parts.append(sample(gx, gy)) }; print(parts.joined(separator: " ")) }
print("expected LINEAR: white 1.0 | 0.75 | 0.5 | 0.18 | 0.0 | red(1,0,0) | green(0,1,0) | blue(0,0,1) | 0.09")
