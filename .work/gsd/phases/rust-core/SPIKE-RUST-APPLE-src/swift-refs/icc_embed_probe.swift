import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let w = 8, h = 8
var px = [UInt8](repeating: 128, count: w*h*4)
for i in 0..<(w*h) { px[i*4+3] = 255 }
let iccURL = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/ROMM RGB.icc")
let iccData = try! Data(contentsOf: iccURL) as CFData
let cs = CGColorSpace(iccData: iccData)!
let provider = CGDataProvider(data: Data(px) as CFData)!
let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w*4,
                  space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
for (uti, ext) in [(UTType.jpeg.identifier, "jpg"), (UTType.heic.identifier, "heic")] {
    let data = NSMutableData()
    let dst = CGImageDestinationCreateWithData(data, uti as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    print(uti, "finalize", CGImageDestinationFinalize(dst), "bytes", data.length)
    let bytes = data as Data
    let hasICC = bytes.range(of: Data("ICC_PROFILE".utf8)) != nil
    let hasProf = bytes.range(of: Data("prof".utf8)) != nil
    let hasNclx = bytes.range(of: Data("nclx".utf8)) != nil
    print("  APP2/ICC_PROFILE:", hasICC, " prof:", hasProf, " nclx:", hasNclx)
    try! bytes.write(to: URL(fileURLWithPath: "out/icc-\(ext).bin"))
}
