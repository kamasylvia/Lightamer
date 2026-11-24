// bench — issue #24 experience-speed harness (P0 CIRAW vs P1 rawspeed->DNG->CIRAW).
//
// One metric family, measured from the user action to a CPU-readable bitmap:
//   M1  open  -> fit-screen preview (long edge 2560) | full resolution
//   M2  edit  (exposure +0.5 EV) -> preview bitmap updated (fit | 100% ROI)
//
// "Cold" is enforced by the driver (one process per measurement); this binary
// reports in-process e2e_ms and the decode split for the explanation column.
//
// usage:
//   bench raw <arw>  --target fit|full [--scale-factor] [--draft] [--decoder v8|v9|auto]
//                    [--reps N] [--clear]           (P0: CIRAW on the original file)
//   bench dng <dng>  --target fit|full [--decoder none|v8|v9] [--reps N] [--clear]
//   bench edit <arw|dng> --target fit|roi [--dng] [--reps N]
//   bench info <arw|dng>
//
// --clear  : CIContext.clearCaches() between reps (the project's clearCICaches shape)
// --scale-factor : P0 variant using CIRAWFilter.scaleFactor (Apple's preview hint)

import CoreImage
import Foundation
import ImageIO
import Metal

let fitLongEdge = 2560

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

nonisolated(unsafe) var gDevice: MTLDevice!
nonisolated(unsafe) var gContext: CIContext!

func makeContext() -> CIContext {
    guard let dev = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
    gDevice = dev
    return CIContext(mtlDevice: dev, options: [.cacheIntermediates: true])
}

func fnv(_ p: UnsafeRawBufferPointer) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in p { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

struct Bitmap {
    let w: Int, h: Int
    var hash: UInt64 = 0
    var ms: Double = 0          // render-only duration
    var endMs: Double = 0       // absolute monotonic time when the render finished
    var hashMs: Double = 0      // verification hash cost (never inside a timed window)
}

/// Render `image` so the long edge lands on `longEdge` (nil = native size).
/// Synchronous CPU-readable bitmap: `CIContext.render(toBitmap:)` — the timed
/// window covers exactly "render until the bytes are in our buffer".
/// Destination allocation and the verification hash stay outside the window.
func render(_ image: CIImage, longEdge: Int?) -> Bitmap {
    let ext = image.extent
    var scale: CGFloat = 1
    if let le = longEdge {
        scale = min(1.0, CGFloat(le) / max(ext.width, ext.height))
    }
    let w = max(1, Int((ext.width * scale).rounded()))
    let h = max(1, Int((ext.height * scale).rounded()))
    let scaled = scale == 1 ? image : image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let bounds = CGRect(x: 0, y: 0, width: w, height: h)
    let t0 = now()
    buf.withUnsafeMutableBytes { raw in
        gContext.render(scaled, toBitmap: raw.baseAddress!, rowBytes: w * 4,
                        bounds: bounds, format: .RGBA8, colorSpace: cs)
    }
    let tEnd = now()
    var bmp = Bitmap(w: w, h: h)
    bmp.ms = tEnd - t0
    bmp.endMs = tEnd
    let h0 = now()
    bmp.hash = buf.withUnsafeBytes { fnv($0) }
    bmp.hashMs = now() - h0
    return bmp
}

/// Render a fixed 1024x768 ROI at 100% (centre), the M2 zoomed tier.
func renderROI(_ image: CIImage) -> Bitmap {
    let ext = image.extent
    let roiW: CGFloat = 1024, roiH: CGFloat = 768
    let x = max(0, (ext.width - roiW) / 2)
    let y = max(0, (ext.height - roiH) / 2)
    let rect = CGRect(x: x, y: y, width: min(roiW, ext.width), height: min(roiH, ext.height))
    let w = Int(rect.width), h = Int(rect.height)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let t0 = now()
    buf.withUnsafeMutableBytes { raw in
        gContext.render(image, toBitmap: raw.baseAddress!, rowBytes: w * 4,
                        bounds: rect, format: .RGBA8, colorSpace: cs)
    }
    let tEnd = now()
    var bmp = Bitmap(w: w, h: h)
    bmp.ms = tEnd - t0
    bmp.endMs = tEnd
    let h0 = now()
    bmp.hash = buf.withUnsafeBytes { fnv($0) }
    bmp.hashMs = now() - h0
    return bmp
}

func decoderFor(_ name: String) -> CIRAWDecoderVersion? {
    switch name {
    case "v8": return CIRAWDecoderVersion.version8
    case "v9": return CIRAWDecoderVersion.version9
    case "v8dng": return CIRAWDecoderVersion.version8DNG
    case "v9dng": return CIRAWDecoderVersion.version9DNG
    case "auto": return nil
    default: return nil
    }
}

func openFilter(_ path: String, decoder: String) -> (CIRAWFilter, Double) {
    let t0 = now()
    let url = URL(fileURLWithPath: path)
    guard let f = CIRAWFilter(imageURL: url) else { fatalError("CIRAWFilter init failed for \(path)") }
    if let v = decoderFor(decoder) { f.decoderVersion = v }
    return (f, now() - t0)
}

func supported(_ f: CIRAWFilter) -> String {
    f.supportedDecoderVersions.map { v in
        if v == CIRAWDecoderVersion.version9 { return "v9" }
        if v == CIRAWDecoderVersion.version9DNG { return "v9DNG" }
        if v == CIRAWDecoderVersion.version8 { return "v8" }
        if v == CIRAWDecoderVersion.version8DNG { return "v8DNG" }
        if v == CIRAWDecoderVersion.version7 { return "v7" }
        if v == CIRAWDecoderVersion.version7DNG { return "v7DNG" }
        if v == CIRAWDecoderVersion.version6 { return "v6" }
        if v == CIRAWDecoderVersion.version6DNG { return "v6DNG" }
        return v.rawValue
    }.joined(separator: ",")
}

func argValue(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}
func hasFlag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }

@main
struct Bench {
    static func main() {
        let tMain = now()
        let a = CommandLine.arguments
        guard a.count >= 3 else {
            FileHandle.standardError.write(Data("usage: bench <raw|dng|edit|info> <path> [options]\n".utf8))
            exit(2)
        }
        let mode = a[1]
        let path = a[2]
        let reps = Int(argValue("--reps") ?? "1") ?? 1
        let clear = hasFlag("--clear")

        gContext = makeContext()
        let ctxInit = now() - tMain

        let isDNG = mode == "dng" || (mode == "edit" && hasFlag("--dng"))
        let decName = argValue("--decoder") ?? (isDNG ? "none" : "v8")

        if mode == "info" {
            let (f, ms) = openFilter(path, decoder: "none")
            print("supported=\(supported(f)) decoder_ms=\(String(format: "%.2f", ms)) native=\(Int(f.nativeSize.width))x\(Int(f.nativeSize.height)) draft_supported=true")
            return
        }

        if mode == "raw" || mode == "dng" {
            let target = argValue("--target") ?? "fit"
            var le: Int?
            switch target {
            case "full": le = nil
            default: le = fitLongEdge
            }
            if let ov = argValue("--long-edge") { le = Int(ov) }
            var rows: [(Double, Double, Double, UInt64, Int, Int, Double)] = []  // e2e, open, render, hash, w, h, hashMs
            for r in 0..<reps {
                // A "hot" rep is a full re-open with the device/context retained but the
                // decode caches dropped (the project's clearCICaches shape).
                if clear { gContext.clearCaches() }
                let (f, openMs) = openFilter(path, decoder: decName)
                if hasFlag("--draft") { f.isDraftModeEnabled = true }
                if hasFlag("--scale-factor"), let l = le {
                    let s = min(1.0, Float(l) / Float(max(f.nativeSize.width, f.nativeSize.height)))
                    f.scaleFactor = s
                }
                let t0 = now()
                guard let out = f.outputImage else { fatalError("no outputImage (decoder unavailable?)") }
                let bmp = render(out, longEdge: le)
                // e2e stops at render end; the verification hash runs after the timestamp
                rows.append((bmp.endMs - t0, openMs, bmp.ms, bmp.hash, bmp.w, bmp.h, bmp.hashMs))
            }
            func med(_ xs: [Double]) -> Double { let s2 = xs.sorted(); return s2[s2.count / 2] }
            func p90(_ xs: [Double]) -> Double { let s2 = xs.sorted(); return s2[min(s2.count - 1, Int(Double(s2.count) * 0.9))] }
            let e2e = rows.map { $0.0 }
            let last = rows.last!
            print("mode=\(mode) target=\(target) med_e2e_ms=\(String(format: "%.2f", med(e2e))) min_e2e_ms=\(String(format: "%.2f", e2e.min()!)) p90_e2e_ms=\(String(format: "%.2f", p90(e2e))) open_ms=\(String(format: "%.2f", med(rows.map { $0.1 }))) render_ms=\(String(format: "%.2f", med(rows.map { $0.2 }))) hash_ms=\(String(format: "%.2f", med(rows.map { $0.6 }))) ctx_init_ms=\(String(format: "%.2f", ctxInit)) w=\(last.4) h=\(last.5) hash=\(String(format: "0x%016llx", last.3)) inproc_from_main_ms=\(String(format: "%.2f", now() - tMain)) reps=\(reps)")
            return
        }

        if mode == "edit" {
            let target = argValue("--target") ?? "fit"
            let (f, openMs) = openFilter(path, decoder: decName)
            guard let base = f.outputImage else { fatalError("no outputImage") }
            // warm: first preview ready (the user-visible open state)
            let b0 = target == "roi" ? renderROI(base) : render(base, longEdge: fitLongEdge)
            var rows: [(Double, UInt64, Double)] = []
            var lastHash = b0.hash
            var edit = 0.0
            for r in 0..<reps {
                if clear { gContext.clearCaches() }
                // the edit: exposure +0.5 EV on the first rep, then +2% steps — a NEW
                // edit every rep, so the retained caches cannot serve the same result
                // (an edit the render never re-runs would be a fake measurement).
                let t0 = now()
                let gain = CGFloat(pow(2.0, 0.5 + 0.02 * Double(r)))
                let m = CIFilter(name: "CIColorMatrix")!
                m.setValue(base, forKey: kCIInputImageKey)
                m.setValue(CIVector(x: gain, y: 0, z: 0, w: 0), forKey: "inputRVector")
                m.setValue(CIVector(x: 0, y: gain, z: 0, w: 0), forKey: "inputGVector")
                m.setValue(CIVector(x: 0, y: 0, z: gain, w: 0), forKey: "inputBVector")
                m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                guard let edited = m.outputImage else { fatalError("edit output missing") }
                let bmp = target == "roi" ? renderROI(edited) : render(edited, longEdge: fitLongEdge)
                edit = bmp.endMs - t0
                rows.append((edit, bmp.hash, bmp.hashMs))
                // self-proof: the edited bitmap must differ from the PRE-EDIT bitmap
                if bmp.hash == b0.hash { print("ERROR: bitmap unchanged after edit") ; exit(3) }
                lastHash = bmp.hash
            }
            let e = rows.map { $0.0 }.sorted()
            print("mode=edit target=\(target) edit_to_bitmap_ms=\(String(format: "%.2f", e[e.count / 2])) min_e2e_ms=\(String(format: "%.2f", e.first!)) p90_e2e_ms=\(String(format: "%.2f", e[min(e.count - 1, Int(Double(e.count) * 0.9))])) hash_ms=\(String(format: "%.2f", rows.map { $0.2 }.max() ?? 0)) open_ms=\(String(format: "%.2f", openMs)) reps=\(reps) base_hash=\(String(format: "0x%016llx", b0.hash)) edited_hash=\(String(format: "0x%016llx", lastHash)) inproc_from_main_ms=\(String(format: "%.2f", now() - tMain))")
            return
        }

        if mode == "cmp" {
            // cmp <rawPath> <dngPath> — coarse diff of the two previews (fit render, sRGB RGBA8)
            guard a.count >= 4 else { exit(2) }
            let other = a[3]
            let (f0, _) = openFilter(path, decoder: "v8")
            let (f1, _) = openFilter(other, decoder: "v8dng")
            guard let o0 = f0.outputImage, let o1 = f1.outputImage else { exit(3) }
            let b0 = render(o0, longEdge: fitLongEdge)
            let b1 = render(o1, longEdge: fitLongEdge)
            print("cmp dims \(b0.w)x\(b0.h) vs \(b1.w)x\(b1.h)")
            // re-render into buffers for the pixel diff
            func bytes(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
                var buf = [UInt8](repeating: 0, count: w * h * 4)
                let s = min(1.0, CGFloat(w) / img.extent.width)
                let scaled = s == 1 ? img : img.transformed(by: CGAffineTransform(scaleX: s, y: s))
                buf.withUnsafeMutableBytes { raw in
                    gContext.render(scaled, toBitmap: raw.baseAddress!, rowBytes: w * 4,
                                    bounds: CGRect(x: 0, y: 0, width: w, height: h),
                                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                }
                return buf
            }
            let n = min(b0.w, b1.w), m = min(b0.h, b1.h)
            let p0 = bytes(o0, n, m), p1 = bytes(o1, n, m)
            var sum = 0.0, mx = 0.0
            var cnt = 0
            for i in stride(from: 0, to: n * m * 4, by: 4) {
                for c in 0..<3 {
                    let d = abs(Double(p0[i + c]) - Double(p1[i + c]))
                    sum += d; if d > mx { mx = d }; cnt += 1
                }
            }
            func mean(_ b: [UInt8]) -> (Double, Double, Double) {
                var r = 0.0, g = 0.0, b2 = 0.0
                var n2 = 0
                for i in stride(from: 0, to: b.count, by: 4) { r += Double(b[i]); g += Double(b[i + 1]); b2 += Double(b[i + 2]); n2 += 1 }
                return (r / Double(n2), g / Double(n2), b2 / Double(n2))
            }
            let m0 = mean(p0), m1 = mean(p1)
            print(String(format: "mean_rgb_A=%.1f/%.1f/%.1f  mean_rgb_B=%.1f/%.1f/%.1f", m0.0, m0.1, m0.2, m1.0, m1.1, m1.2))
            print(String(format: "mean_abs_diff=%.3f max_abs_diff=%.1f samples=%d (0..255 scale)", sum / Double(cnt), mx, cnt))
            return
        }

        FileHandle.standardError.write(Data("unknown mode \(mode)\n".utf8))
        exit(2)
    }
}
