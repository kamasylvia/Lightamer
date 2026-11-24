// v9-breakdown — per-rep RAW 9 (v9DNG) timing, same seam as benchlive.
//
// Purpose (rerun): the report's 3.18 s is a cold median and the "first process
// pays 6.1 s of model preparation" claim needs the cold-vs-steady split. This
// probe prints EVERY rep so rep 0 (resource preparation included) and reps
// 1..N (steady) are separable inside one process, and repeated one-rep
// processes show the per-process component.
//
// usage: v9-breakdown <cameras.xml> <arw> [--downsample N] [--target fit|full]
//                     [--decoder v8dng|v9dng] [--reps N] [--clear]

import CoreImage
import CRawSpeedShim
import Foundation
import Metal

nonisolated(unsafe) var gContext: CIContext!
let fitLongEdge = 2560

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func fnv(_ p: UnsafeRawBufferPointer) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in p { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

func render(_ image: CIImage, longEdge: Int?) -> (ms: Double, end: Double, hash: UInt64, hashMs: Double) {
    let ext = image.extent
    let scale = longEdge.map { min(1.0, CGFloat($0) / max(ext.width, ext.height)) } ?? 1
    let w = max(1, Int((ext.width * scale).rounded()))
    let h = max(1, Int((ext.height * scale).rounded()))
    let scaled = scale == 1 ? image : image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let t0 = now()
    buf.withUnsafeMutableBytes { raw in
        gContext.render(scaled, toBitmap: raw.baseAddress!, rowBytes: w * 4,
                        bounds: CGRect(x: 0, y: 0, width: w, height: h),
                        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    let tEnd = now()
    let h0 = now()
    let hsh = buf.withUnsafeBytes { fnv($0) }
    return (tEnd - t0, tEnd, hsh, now() - h0)
}

func arg(_ n: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: n), i + 1 < a.count { return a[i + 1] }
    return nil
}
func flag(_ n: String) -> Bool { CommandLine.arguments.contains(n) }

func message(_ e: inout rs_error) -> String {
    withUnsafePointer(to: &e.message) {
        $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
    }
}

@main
struct V9Breakdown {
    static func main() {
        let tMain = now()
        let a = CommandLine.arguments
        guard a.count >= 3 else { exit(2) }
        let camfile = a[1], rawPath = a[2]
        let ds = Int32(arg("--downsample") ?? "0") ?? 0
        let target = arg("--target") ?? "fit"
        let decName = arg("--decoder") ?? "v9dng"
        let reps = Int(arg("--reps") ?? "5") ?? 5
        let clear = flag("--clear")

        guard let dev = MTLCreateSystemDefaultDevice() else { exit(3) }
        gContext = CIContext(mtlDevice: dev, options: [.cacheIntermediates: true])

        for r in 0..<reps {
            if r > 0 && clear { gContext.clearCaches() }
            var err = rs_error()
            let t0 = now()
            guard let img = rs_open(rawPath, camfile, &err) else {
                print("open_failed code=\(err.code) msg=\(message(&err))")
                exit(4)
            }
            let tDec = now()
            var bytes: UnsafeMutablePointer<UInt8>?
            var len = 0
            guard rs_build_dng(img, ds, &bytes, &len, &err) == 0 else { exit(5) }
            let tDng = now()
            let data = Data(bytes: bytes!, count: len)
            rs_free_bytes(bytes)
            rs_free(img)
            guard let f = CIRAWFilter(imageData: data, identifierHint: "dng") else { exit(6) }
            f.decoderVersion = decName == "v9dng" ? CIRAWDecoderVersion.version9DNG
                                                : CIRAWDecoderVersion.version8DNG
            guard let out = f.outputImage else { exit(7) }
            let tCI = now()
            let bmp = render(out, longEdge: target == "full" ? nil : fitLongEdge)
            let total = bmp.end - t0
            print(String(format: "rep=%d e2e_ms=%.2f decode_ms=%.2f dng_ms=%.2f ci_init_ms=%.2f render_ms=%.2f hash_ms=%.2f hash=0x%016llx",
                         r, total, tDec - t0, tDng - tDec, tCI - tDng, bmp.ms, bmp.hashMs, bmp.hash))
            if r == 0 { print(String(format: "  process_before_first_open_ms=%.2f", tMain - 0)) }
        }
    }
}
