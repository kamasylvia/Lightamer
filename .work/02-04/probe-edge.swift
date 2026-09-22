import CoreImage
import CoreGraphics
import Foundation

// Diff localization: WHERE do the two legs differ at scale 1.0?
// Expectation: only the 4 patch-grid SEAM lines (x≈341/682, y≈341/682).
let rec2020 = CGColorSpace(name: CGColorSpace.linearITUR_2020)!
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let url = URL(fileURLWithPath: "Resources/TestFixtures/NeutralTarget.tif")
let ci = CIImage(contentsOf: url)!

// Leg B (baseline): CI direct to P3 8-bit.
let ctxB = CIContext(options: [.workingColorSpace: rec2020, .outputColorSpace: p3])
var b = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
b.withUnsafeMutableBytes { ctxB.render(ci, toBitmap: $0.baseAddress!, rowBytes: 4096, bounds: ci.extent, format: CIFormat.RGBA8, colorSpace: p3) }

// Leg A emulation: CI to linear-Rec2020 float (the pool leg), then the same
// matrix + TRC in Swift (CPU mirror of the kernels).
let ctxA = CIContext(options: [.workingColorSpace: rec2020, .outputColorSpace: rec2020])
var a = [Float](repeating: 0, count: 1024 * 1024 * 4)
ctxA.render(ci, toBitmap: &a, rowBytes: 16384, bounds: ci.extent, format: CIFormat.RGBAf, colorSpace: rec2020)
let m: [[Double]] = [[1.343930183, -0.282585998, -0.061344185],
                     [-0.066855841, 1.077337009, -0.010481169],
                     [0.003750840, -0.019626716, 1.015875875]]
func trc(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : min(1.055 * pow(max(c, 0), 1 / 2.4) - 0.055, 1) }

var maxD = 0; var worst = (0, 0); var count = 0
var seamsOnly = true
for y in 0..<1024 {
    for x in 0..<1024 {
        let o = (y * 1024 + x) * 4
        var out = [UInt8](repeating: 0, count: 3)
        for ch in 0..<3 {
            let lin = m[ch][0] * Double(a[o]) + m[ch][1] * Double(a[o + 1]) + m[ch][2] * Double(a[o + 2])
            out[ch] = UInt8((min(max(trc(lin), 0), 1) * 255).rounded())
        }
        let d = max(abs(Int(out[0]) - Int(b[o])), abs(Int(out[1]) - Int(b[o + 1])), abs(Int(out[2]) - Int(b[o + 2])))
        if d > maxD { maxD = d; worst = (x, y) }
        if d >= 2 {
            count += 1
            let seam = (abs(x - 341) <= 1 || abs(x - 682) <= 1 || abs(y - 341) <= 1 || abs(y - 682) <= 1)
            if !seam && seamsOnly { print("non-seam diff at (\(x),\(y)) d=\(d)"); seamsOnly = false }
        }
    }
}
print("max=\(maxD) at \(worst), pixels≥2: \(count), all-on-seams=\(seamsOnly)")
print("around worst: pipe-emulated vs baseline:")
for dy in -1...1 { for dx in -1...1 {
    let x = worst.0 + dx, y = worst.1 + dy
    let o = (y * 1024 + x) * 4
    let lin0 = m[0][0] * Double(a[o]) + m[0][1] * Double(a[o + 1]) + m[0][2] * Double(a[o + 2])
    print("  (\(x),\(y)) emu=\(Int((trc(lin0) * 255).rounded())) base=\(b[o]) floatIn=\(String(format: "%.6f", a[o]))")
} }

// Deep dive: red patch interior (700,500) + green/blue interiors.
for (tag, px_) in [("red", (700, 500)), ("green", (170, 830)), ("blue", (510, 830))] {
    let o = (px_.1 * 1024 + px_.0) * 4
    let lin = [0,1,2].map { ch in m[ch][0] * Double(a[o]) + m[ch][1] * Double(a[o + 1]) + m[ch][2] * Double(a[o + 2]) }
    let enc = lin.map { Int((trc($0) * 255).rounded()) }
    print("\(tag) @\(px_): floatIn=(\(a[o]),\(a[o+1]),\(a[o+2])) mirrorLin=(\(lin.map { String(format: "%.4f", $0) }.joined(separator: ","))) mirror8=\(enc) baseline8=(\(b[o]),\(b[o+1]),\(b[o+2]))")
}
