import CoreImage
import Foundation

// 8-bit QA sample of the 16-bit fixture (exact 16-bit values asserted in
// the unit tests via the pipe texture, which needs no CGContext).
let url = URL(fileURLWithPath: "Resources/TestFixtures/NeutralTarget.tif")
guard let ci = CIImage(contentsOf: url) else { fatalError("CIImage") }
let ctx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
let w = Int(ci.extent.width), h = Int(ci.extent.height)
var buf = [UInt8](repeating: 0, count: w * h * 4)
ctx.render(ci, toBitmap: &buf, rowBytes: w * 4, bounds: ci.extent, format: CIFormat.RGBA8, colorSpace: nil)
func sample(_ gx: Int, _ gy: Int) -> String {
    // NOTE: CI render keeps image orientation in the bitmap (row 0 = top).
    let px = gx * 341 + 170, py = gy * 341 + 170
    let i = (py * w + px) * 4
    return "(\(buf[i]),\(buf[i+1]),\(buf[i+2]))"
}
for gy in 0..<3 { var parts: [String] = []; for gx in 0..<3 { parts.append(sample(gx, gy)) }; print(parts.joined(separator: " ")) }
print("expect: white 255 | L0.75 → 225 | L0.5 → 188 | L0.18 → 118 | black 0 | red (255,0,0) | green (0,255,0) | blue (0,0,255) | L0.09 → 85")
