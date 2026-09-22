import CoreImage
import ImageIO
import Foundation
let url = URL(fileURLWithPath: "Resources/TestFixtures/NeutralTarget.tif")
let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
    print("props profile:", props[kCGImagePropertyProfileName as String] ?? "nil")
}
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
print("cg colorspace:", img.colorSpace?.name as String? ?? img.colorSpace.map { "unnamed-\($0.model.rawValue)" } ?? "nil")
let ci = CIImage(cgImage: img)
print("ciImage colorspace:", ci.colorSpace.map { $0.name as String? ?? "unnamed model \($0.model.rawValue)" } ?? "nil")
let grad = CGImageSourceCreateWithURL(URL(fileURLWithPath: "Resources/TestFixtures/sample-gradient.tiff") as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
print("gradient cg colorspace:", grad.colorSpace?.name as String? ?? "unnamed")
let ciGrad = CIImage(cgImage: grad)
print("gradient ci colorspace:", ciGrad.colorSpace.map { $0.name as String? ?? "unnamed model \($0.model.rawValue)" } ?? "nil")
