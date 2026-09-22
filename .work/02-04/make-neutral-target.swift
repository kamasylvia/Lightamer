import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Plan 02-04-06: one-off generator for the committed synthetic neutral
// golden fixture `Resources/TestFixtures/NeutralTarget.tif`.
//
// 1024×1024, 16-bit RGB TIFF, sRGB-tagged, 3×3 patch grid. Each patch's
// EXPECTED linear-Rec2020 value is documented in
// `Tests/LightamerTests/Fixtures.swift` (neutralPatches) and must stay in
// sync with the table below.
//
// Grays are channel-equal in sRGB → channel-equal in linear Rec2020 (the
// sRGB→Rec2020 matrix preserves D65 gray exactly) → channel-equal after the
// colorout gamut matrix (D65→D65: white maps to (1,1,1)) → channel-equal
// after gamma's sRGB TRC. The D-COL1 neutrality criterion rides on this.

let size = 1024
let cell = size / 3 // 341

// sRGB piecewise TRC (the encode; per IEC 61966-2-1).
func srgbEncode(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
}

// (linear Rec2020 triple, or sRGB-native color patch)
let linearGrayLevels: [Double?] = [nil, nil, nil] // placeholder; real layout below

// Grid (row-major, IMAGE space: row 0 = TOP of the image as viewed):
//  row0: white L=1.0 | gray L=0.75 | gray L=0.5
//  row1: gray L=0.18 | black L=0.0 | sRGB red
//  row2: sRGB green  | sRGB blue  | gray L=0.09
let grayL: [Double] = [1.0, 0.75, 0.5, 0.18, 0.0, 0.09]

var pixels = [UInt16](repeating: 0, count: size * size * 3)
for row in 0..<size {
    let gridRow = min(row / cell, 2)
    for col in 0..<size {
        let gridCol = min(col / cell, 2)
        let index = (row * size + col) * 3
        let r: UInt16, g: UInt16, b: UInt16
        switch (gridRow, gridCol) {
        case (0, 0): r = 65535; g = 65535; b = 65535 // white (L=1.0)
        case (0, 1): let v = UInt16((srgbEncode(0.75) * 65535).rounded()); (r, g, b) = (v, v, v)
        case (0, 2): let v = UInt16((srgbEncode(0.5) * 65535).rounded()); (r, g, b) = (v, v, v)
        case (1, 0): let v = UInt16((srgbEncode(0.18) * 65535).rounded()); (r, g, b) = (v, v, v)
        case (1, 1): r = 0; g = 0; b = 0 // black (L=0.0)
        case (1, 2): r = 65535; g = 0; b = 0 // sRGB red
        case (2, 0): r = 0; g = 65535; b = 0 // sRGB green
        case (2, 1): r = 0; g = 0; b = 65535 // sRGB blue
        case (2, 2): let v = UInt16((srgbEncode(0.09) * 65535).rounded()); (r, g, b) = (v, v, v)
        default: (r, g, b) = (0, 0, 0)
        }
        pixels[index] = r
        pixels[index + 1] = g
        pixels[index + 2] = b
    }
}
_ = linearGrayLevels
_ = grayL

let bytesPerRow = size * 3 * MemoryLayout<UInt16>.size
let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
guard let provider = CGDataProvider(data: data) else { fatalError("CGDataProvider") }
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("sRGB") }
guard let cgImage = CGImage(
    width: size, height: size,
    bitsPerComponent: 16, bitsPerPixel: 48,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    // 16bpc needs an explicit byte order — without it CGImage assumes
    // BIG-endian samples and every 16-bit value lands byte-swapped
    // (caught by the QA sampling: L0.75 read back as 125/255 ≈ 0.49 =
    // byteswap(0xE17D)/65535). Host arrays are little-endian (arm64).
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue
        | CGBitmapInfo.byteOrder16Little.rawValue),
    provider: provider,
    decode: nil, shouldInterpolate: false, intent: .perceptual
) else { fatalError("CGImage") }

let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/TestFixtures/NeutralTarget.tif")
guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL, UTType.tiff.identifier as CFString, 1, nil
) else { fatalError("destination \(outURL.path)") }
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("finalize") }
let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size]) ?? 0
print("wrote \(outURL.path) (\(sizeBytes ?? 0) bytes)")
