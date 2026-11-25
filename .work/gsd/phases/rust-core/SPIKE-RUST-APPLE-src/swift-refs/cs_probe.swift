import Foundation
import ColorSync
import CoreFoundation

let kProfile = kColorSyncProfile!.takeUnretainedValue()
let kIntent = kColorSyncRenderingIntent!.takeUnretainedValue()
let kTag = kColorSyncTransformTag!.takeUnretainedValue()
let vRel = kColorSyncRenderingIntentRelative!.takeUnretainedValue()
let vDev2Pcs = kColorSyncTransformDeviceToPCS!.takeUnretainedValue()
let vPcs2Dev = kColorSyncTransformPCSToDevice!.takeUnretainedValue()

let srgb = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/sRGB Profile.icc")
let p3 = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/Display P3.icc")
var err: Unmanaged<CFError>?
guard let sU = ColorSyncProfileCreateWithURL(srgb as CFURL, &err) else { print("src profile nil"); exit(1) }
guard let dU = ColorSyncProfileCreateWithURL(p3 as CFURL, &err) else { print("dst profile nil"); exit(1) }
let s = sU.takeRetainedValue()
let d = dU.takeRetainedValue()
print("profiles ok")
func entry(_ p: ColorSyncProfile, _ tag: CFString) -> CFDictionary {
    let dict: [CFString: Any] = [kProfile: p, kIntent: vRel, kTag: tag]
    return dict as CFDictionary
}
let seq = [entry(s, vDev2Pcs), entry(d, vPcs2Dev)] as CFArray
guard let tU = ColorSyncTransformCreate(seq, nil) else { print("transform nil"); exit(2) }
let t = tU.takeRetainedValue()
print("transform ok")
var src = [Float](repeating: 0, count: 16*16*3)
for y in 0..<16 { for x in 0..<16 {
    src[(y*16+x)*3] = (Float(x)+0.5)/16
    src[(y*16+x)*3+1] = (Float(y)+0.5)/16
    src[(y*16+x)*3+2] = (Float(x+y)+0.5)/32
}}
var dst = [Float](repeating: 0, count: 16*16*3)
let ok = src.withUnsafeBytes { sp in
    dst.withUnsafeMutableBytes { dp in
        ColorSyncTransformConvert(t, 16, 16,
            dp.baseAddress!, ColorSyncDataDepth(rawValue: 7), 0, 16*12,
            sp.baseAddress!, ColorSyncDataDepth(rawValue: 7), 0, 16*12, nil)
    }
}
print("convert = \(ok) first=\(dst[0]) \(dst[1]) \(dst[2])")
dst.withUnsafeBytes { try! Data($0).write(to: URL(fileURLWithPath: "out/s3-cs-swift.bin")) }
src.withUnsafeBytes { try! Data($0).write(to: URL(fileURLWithPath: "out/s3-cs-src.bin")) }
