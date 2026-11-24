// m2-product-shape — product-shaped M2 control for issue #24.
//
// Why this file exists (rerun finding): `bench edit` applies the exposure
// downstream (CIColorMatrix on `f.outputImage`) but never freezes the decoded
// plane, so every render re-executes CIRAW (P0 fit = 738 ms). The product
// does NOT do that: `CIContextPool.renderToTexture(longEdge:dedupeKey:)`
// memoises the FIRST input-plane render and edits re-run the pipe on that
// frozen texture (GUI-22 render-once memo). This probe reproduces the product
// shape: render the decoded image once to a 2560-long-edge bitmap, then apply
// the same downstream exposure multiplication on the frozen plane.
//
// It also measures the unfrozen control (one edit on `f.outputImage`) so the
// difference is attributable to the freeze, not to the filter.
//
// usage: m2-product-shape <arw|dng> [--target fit] [--reps 10]
//        (only fit is meaningful; 100% ROI is already ROI-tiled by CI)
//
// Timing: edit -> CPU-readable bitmap only. The bitmap hash is computed after
// the timestamp (same rule as bench.swift).

import CoreImage
import Foundation
import Metal

let fitLongEdge = 2560

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func fnv(_ p: UnsafeRawBufferPointer) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in p { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

nonisolated(unsafe) var gContext: CIContext!

func arg(_ n: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: n), i + 1 < a.count { return a[i + 1] }
    return nil
}

struct Shot {
    let ms: Double
    let hash: UInt64
    let w: Int
    let h: Int
}

/// Render `image` to a CPU-readable sRGB RGBA8 bitmap at `w`x`h`.
/// t0 starts immediately before `CIContext.render`; the hash runs after tEnd.
func renderBitmap(_ image: CIImage, w: Int, h: Int) -> Shot {
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let t0 = now()
    buf.withUnsafeMutableBytes { raw in
        gContext.render(image, toBitmap: raw.baseAddress!, rowBytes: w * 4,
                        bounds: CGRect(x: 0, y: 0, width: w, height: h),
                        format: .RGBA8, colorSpace: cs)
    }
    let tEnd = now()
    let hsh = buf.withUnsafeBytes { fnv($0) }
    return Shot(ms: tEnd - t0, hash: hsh, w: w, h: h)
}

func gainImage(_ base: CIImage, _ gain: CGFloat) -> CIImage {
    let m = CIFilter(name: "CIColorMatrix")!
    m.setValue(base, forKey: kCIInputImageKey)
    m.setValue(CIVector(x: gain, y: 0, z: 0, w: 0), forKey: "inputRVector")
    m.setValue(CIVector(x: 0, y: gain, z: 0, w: 0), forKey: "inputGVector")
    m.setValue(CIVector(x: 0, y: 0, z: gain, w: 0), forKey: "inputBVector")
    m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
    return m.outputImage!
}

@main
struct M2ProductShape {
    static func main() {
        let a = CommandLine.arguments
        guard a.count >= 2 else {
            FileHandle.standardError.write(Data("usage: m2-product-shape <arw|dng> [--reps N]\n".utf8))
            exit(2)
        }
        let path = a[1]
        let reps = Int(arg("--reps") ?? "10") ?? 10
        let isDNG = path.lowercased().hasSuffix(".dng")

        guard let dev = MTLCreateSystemDefaultDevice() else { exit(3) }
        // Product CIContext shape: cacheIntermediates = false (CIContextPool).
        gContext = CIContext(mtlDevice: dev, options: [.cacheIntermediates: false])

        let tOpen = now()
        guard let f = CIRAWFilter(imageURL: URL(fileURLWithPath: path)) else { exit(4) }
        f.decoderVersion = isDNG ? CIRAWDecoderVersion.version8DNG : CIRAWDecoderVersion.version8
        guard let base = f.outputImage else { exit(5) }
        let openMs = now() - tOpen
        let ext = base.extent
        let scale = min(1.0, CGFloat(fitLongEdge) / max(ext.width, ext.height))
        let w = max(1, Int((ext.width * scale).rounded()))
        let h = max(1, Int((ext.height * scale).rounded()))
        let scaled = base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // ── the product's "render once, memoise the input plane" leg ──
        let tFreeze = now()
        guard let cg = gContext.createCGImage(
            scaled, from: CGRect(x: 0, y: 0, width: w, height: h),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        else { exit(6) }
        let frozenMs = now() - tFreeze
        let frozen = CIImage(cgImage: cg)
        let frozenBase = renderBitmap(frozen, w: w, h: h)

        // ── control: one edit on the UNFROZEN CIRAW output (bench edit shape) ──
        let unfrozen = renderBitmap(gainImage(base, 1.4142135623730951), w: w, h: h)

        // ── product shape: downstream exposure on the frozen input plane ──
        var edits: [Double] = []
        var lastHash = frozenBase.hash
        for r in 0..<reps {
            // NEW exposure every rep (same 0.5 EV + 2% ladder as benchrun.py).
            let gain = CGFloat(pow(2.0, 0.5 + 0.02 * Double(r)))
            let shot = renderBitmap(gainImage(frozen, gain), w: w, h: h)
            edits.append(shot.ms)
            if shot.hash == frozenBase.hash {
                print("ERROR: bitmap unchanged after edit")
                exit(7)
            }
            lastHash = shot.hash
        }
        let sorted = edits.sorted()
        let med = sorted[sorted.count / 2]
        let mn = sorted.first!
        let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
        print(String(format: "mode=m2-product-shape path=%@ target=fit open_ms=%.2f freeze_ms=%.2f frozen_base_hash=0x%016llx unfrozen_edit_ms=%.2f edit_med_ms=%.2f edit_min_ms=%.2f edit_p90_ms=%.2f last_hash=0x%016llx reps=%d",
                     (path as NSString).lastPathComponent, openMs, frozenMs, frozenBase.hash,
                     unfrozen.ms, med, mn, p90, lastHash, reps))
    }
}
