// raw9-probe — CIRAW9 x A7R5 truthfulness probe (issue #24).
//
// info     : per-file EXIF identity + per-file supportedDecoderVersions + class-list matches
// models   : class-level version8/version9 camera lists, matched against a model string
// compare  : render one file at v7/v8/v9 (or *DNG variants), time each, pixel-diff pairs
//
// Render target is always float32 RGBA (RGBAf) in extended linear sRGB: no tone
// curve, no 8-bit quantisation, so a "silent downgrade" shows up as memcmp-equal
// buffers and a real RAW 9 run shows up as a multi-second render.
//
// Build: swiftc -O -o /tmp/raw9probe raw9-probe.swift

import Accelerate
import CoreImage
import Foundation
import ImageIO
import Metal
import ObjectiveC

func nowMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func med(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    return s[s.count / 2]
}

func fmt(_ x: Double, _ p: Int = 6) -> String { String(format: "%.\(p)f", x) }

// MARK: - version helpers

let knownVersions: [(String, CIRAWDecoderVersion)] = [
    ("v6", .version6), ("v6dng", .version6DNG),
    ("v7", .version7), ("v7dng", .version7DNG),
    ("v8", .version8), ("v8dng", .version8DNG),
    ("v9", .version9), ("v9dng", .version9DNG),
]

func version(named name: String) -> CIRAWDecoderVersion? {
    knownVersions.first { $0.0.lowercased() == name.lowercased() }?.1
}

func versionName(_ v: CIRAWDecoderVersion) -> String {
    knownVersions.first { $0.1.rawValue == v.rawValue }?.0 ?? "raw(\(v.rawValue))"
}

// MARK: - metadata

struct Identity {
    var make = ""
    var model = ""
    var software = ""
    var compression = ""
    var width = 0
    var height = 0
    var bytes = 0
}

func identity(_ url: URL) -> Identity {
    var id = Identity()
    id.bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else {
        return id
    }
    if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
        id.make = tiff[kCGImagePropertyTIFFMake as String] as? String ?? ""
        id.model = tiff[kCGImagePropertyTIFFModel as String] as? String ?? ""
        id.software = tiff[kCGImagePropertyTIFFSoftware as String] as? String ?? ""
        if let c = tiff[kCGImagePropertyTIFFCompression as String] as? Int { id.compression = String(c) }
    }
    if id.software.isEmpty, let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
        id.software = exif["Software"] as? String ?? ""
    }
    if let w = props[kCGImagePropertyPixelWidth as String] as? Int { id.width = w }
    if let h = props[kCGImagePropertyPixelHeight as String] as? Int { id.height = h }
    return id
}

func norm(_ s: String) -> String {
    let up = s.uppercased()
    let scalars = up.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
    return String(String.UnicodeScalarView(scalars))
}

func strictHits(_ list: [String], _ model: String) -> [String] {
    list.filter { $0 == model }
}

func looseHits(_ list: [String], _ model: String) -> [String] {
    let n = norm(model)
    guard !n.isEmpty else { return [] }
    return list.filter {
        let e = norm($0)
        return e == n || e.contains(n) || n.contains(e)
    }
}

// MARK: - buffers

struct Buf {
    let p: UnsafeMutablePointer<Float>
    let pixels: Int
    let w: Int
    let h: Int
    var bytes: Int { pixels * 16 }
}

func allocBuf(_ w: Int, _ h: Int) -> Buf {
    let pixels = w * h
    let p = UnsafeMutablePointer<Float>.allocate(capacity: pixels * 4)
    p.initialize(repeating: 0, count: pixels * 4)
    return Buf(p: p, pixels: pixels, w: w, h: h)
}

func freeBuf(_ b: Buf) { b.p.deallocate() }

/// Bit-identical via memcmp; otherwise chunked vDSP max/mean absolute difference.
func diff(_ a: Buf, _ b: Buf) -> (bitEqual: Bool, maxAD: Double, meanAD: Double) {
    precondition(a.pixels == b.pixels)
    if memcmp(UnsafeRawPointer(a.p), UnsafeRawPointer(b.p), a.bytes) == 0 { return (true, 0, 0) }
    let chunk = 1 << 20
    var tmp = [Float](repeating: 0, count: chunk)
    var maxAD: Float = 0
    var sum: Double = 0
    var off = 0
    let n = a.pixels * 4
    while off < n {
        let c = min(chunk, n - off)
        tmp.withUnsafeMutableBufferPointer { t in
            vDSP_vsub(b.p + off, 1, a.p + off, 1, t.baseAddress!, 1, vDSP_Length(c))
            vDSP_vabs(t.baseAddress!, 1, t.baseAddress!, 1, vDSP_Length(c))
            var m: Float = 0
            vDSP_maxv(t.baseAddress!, 1, &m, vDSP_Length(c))
            if m > maxAD { maxAD = m }
            var s: Float = 0
            vDSP_sve(t.baseAddress!, 1, &s, vDSP_Length(c))
            sum += Double(s)
        }
        off += c
    }
    return (false, Double(maxAD), sum / Double(n))
}

func means(_ b: Buf) -> (r: Double, g: Double, bl: Double, a: Double) {
    var out = [Double](repeating: 0, count: 4)
    let chunkPixels = 1 << 18
    var off = 0
    while off < b.pixels {
        let n = min(chunkPixels, b.pixels - off)
        let base = b.p + off * 4
        for c in 0..<4 {
            var acc: Float = 0
            vDSP_sve(base + c, 4, &acc, vDSP_Length(n))
            out[c] += Double(acc)
        }
        off += n
    }
    return (out[0] / Double(b.pixels), out[1] / Double(b.pixels),
            out[2] / Double(b.pixels), out[3] / Double(b.pixels))
}

// MARK: - render

struct RenderResult {
    var ms = 0.0
    var initMs = 0.0
    var before = ""
    var after = ""
    var extent = CGSize.zero
    var nilOutput = false
    var error = ""
}

nonisolated(unsafe) var gCtx: CIContext!

func renderInto(url: URL, version v: CIRAWDecoderVersion, fitLongEdge: Int?,
                buf: Buf, cs: CGColorSpace) -> RenderResult {
    var r = RenderResult()
    let tInit0 = nowMs()
    guard let filter = CIRAWFilter(imageURL: url) else {
        r.error = "CIRAWFilter init failed"; return r
    }
    filter.decoderVersion = v
    r.before = filter.decoderVersion.rawValue
    guard let out = filter.outputImage else {
        r.nilOutput = true; r.after = filter.decoderVersion.rawValue
        r.initMs = nowMs() - tInit0
        return r
    }
    r.extent = out.extent.size
    var image = out
    if let le = fitLongEdge {
        let scale = min(1.0, CGFloat(le) / max(out.extent.width, out.extent.height))
        if scale < 1 { image = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
    }
    let bounds = CGRect(x: 0, y: 0, width: buf.w, height: buf.h)
    r.initMs = nowMs() - tInit0
    let t0 = nowMs()
    buf.p.withMemoryRebound(to: UInt8.self, capacity: buf.bytes) { raw in
        gCtx.render(image, toBitmap: UnsafeMutableRawPointer(raw), rowBytes: buf.w * 16,
                    bounds: bounds, format: .RGBAf, colorSpace: cs)
    }
    r.ms = nowMs() - t0
    r.after = filter.decoderVersion.rawValue
    return r
}

// MARK: - commands

func dumpProperties(_ url: URL) {
    guard let filter = CIRAWFilter(imageURL: url) else { return }
    let props = filter.properties
    let keys = props.keys.sorted { String(describing: $0) < String(describing: $1) }
    print("PROPS_KEYS\t" + keys.map { String(describing: $0) }.joined(separator: ","))
    for k in keys {
        let ks = String(describing: k)
        if ks.lowercased().contains("version") || ks.lowercased().contains("decoder") {
            print("PROPS_HIT\t\(ks)\t\(String(describing: props[k]))")
        }
    }
}


func describeFilter(_ label: String, _ filter: CIRAWFilter, cs: CGColorSpace) {
    let cls = String(cString: object_getClassName(filter))
    let hasDecoder = filter.responds(to: NSSelectorFromString("decoderVersion"))
    let hasSupported = filter.responds(to: NSSelectorFromString("supportedDecoderVersions"))
    let supp = hasSupported ? filter.supportedDecoderVersions.map { versionName($0) }.joined(separator: ",") : "NO_SELECTOR"
    let def = hasDecoder ? versionName(filter.decoderVersion) : "NO_SELECTOR"
    print("PATH\t\(label)\tclass=\(cls)\tdecoderSelector=\(hasDecoder)\tsupported=\(supp)\tdefault=\(def)")
    guard hasDecoder else { return }
    filter.decoderVersion = .version9
    let rb = filter.decoderVersion.rawValue
    guard let out = filter.outputImage else { print("PATH\t\(label)\tv9_nil_output=true"); return }
    let scale = min(1.0, 512.0 / max(out.extent.width, out.extent.height))
    let w = Int((out.extent.width * scale).rounded()), h = Int((out.extent.height * scale).rounded())
    let b = allocBuf(w, h)
    defer { freeBuf(b) }
    let img = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let t0 = nowMs()
    b.p.withMemoryRebound(to: UInt8.self, capacity: b.bytes) { raw in
        gCtx.render(img, toBitmap: UnsafeMutableRawPointer(raw), rowBytes: w * 16,
                    bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: cs)
    }
    print("PATH\t\(label)\treadback=\(rb)\tv9_render_ms=\(fmt(nowMs() - t0, 3))\textent=\(w)x\(h)")
}

func cmdPaths(_ path: String) {
    let url = URL(fileURLWithPath: path)
    let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    gCtx = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [.cacheIntermediates: false])
    if let f = CIRAWFilter(imageURL: url) { describeFilter("url", f, cs: cs) }
    if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
        if let f = CIRAWFilter(imageData: data) { describeFilter("data", f, cs: cs) }
        if let f = CIRAWFilter(imageData: data, identifierHint: "com.sony.arw-raw-image") {
            describeFilter("datahint", f, cs: cs)
        }
    }
}

func cmdInfo(_ paths: [String]) {
    let v8 = CIRAWFilter.supportedCameraModels(with: .version8)
    let v9 = CIRAWFilter.supportedCameraModels(with: .version9)
    print("CLASS\tversion8_count\t\(v8.count)")
    print("CLASS\tversion9_count\t\(v9.count)")
    for path in paths {
        let url = URL(fileURLWithPath: path)
        let id = identity(url)
        let line = "FILE\t\(url.lastPathComponent)\tbytes=\(id.bytes)\tmake=\(id.make)\tmodel=\(id.model)\tsoftware=\(id.software)\tcompression=\(id.compression)\tpixels=\(id.width)x\(id.height)"
        guard let filter = CIRAWFilter(imageURL: url) else {
            print(line + "\tSUPPORTED=INIT_FAILED")
            continue
        }
        let vs = filter.supportedDecoderVersions.map { versionName($0) }.joined(separator: ",")
        let raw = filter.supportedDecoderVersions.map { $0.rawValue }.joined(separator: ",")
        let s8 = strictHits(v8, id.model)
        let l8 = looseHits(v8, id.model)
        let s9 = strictHits(v9, id.model)
        let l9 = looseHits(v9, id.model)
        let sub8 = v8.filter { !id.model.isEmpty && $0.contains(id.model) }
        let sub9 = v9.filter { !id.model.isEmpty && $0.contains(id.model) }
        print(line + "\tsupported=\(vs)\tsupported_raw=\(raw)\tdefault=\(versionName(filter.decoderVersion))")
        print("MATCH\t\(url.lastPathComponent)\tv8_strict=\(s8.joined(separator: "|"))\tv8_substr=\(sub8.joined(separator: "|"))\tv8_loose=\(l8.joined(separator: "|"))\tv9_strict=\(s9.joined(separator: "|"))\tv9_substr=\(sub9.joined(separator: "|"))\tv9_loose=\(l9.joined(separator: "|"))")
    }
}

func cmdModels(_ model: String) {
    let v8 = CIRAWFilter.supportedCameraModels(with: .version8)
    let v9 = CIRAWFilter.supportedCameraModels(with: .version9)
    print("model=\(model)")
    let sub8 = v8.filter { $0.contains(model) }
    let sub9 = v9.filter { $0.contains(model) }
    print("v8_count=\(v8.count) eq=\(strictHits(v8, model).joined(separator: "|")) substr=\(sub8.joined(separator: "|")) loose=\(looseHits(v8, model).joined(separator: "|"))")
    print("v9_count=\(v9.count) eq=\(strictHits(v9, model).joined(separator: "|")) substr=\(sub9.joined(separator: "|")) loose=\(looseHits(v9, model).joined(separator: "|"))")
}

func cmdCompare(_ path: String, versions: [CIRAWDecoderVersion], reps: Int, fit: Int?, rec2020: Bool = false) {
    let url = URL(fileURLWithPath: path)
    let id = identity(url)
    print("COMPARE\t\(url.lastPathComponent)\tmodel=\(id.model)\tbytes=\(id.bytes)\treps=\(reps)\tfit=\(fit.map(String.init) ?? "full")")
    guard let probe = CIRAWFilter(imageURL: url) else { print("ERROR\tinit failed"); return }
    let supported = probe.supportedDecoderVersions.map { versionName($0) }.joined(separator: ",")
    print("SUPPORTED\t\(supported)")
    guard let out = probe.outputImage else {
        print("ERROR\tno output image on default decoder"); return
    }
    var extent = out.extent
    if let le = fit {
        let scale = min(1.0, CGFloat(le) / max(extent.width, extent.height))
        extent = CGRect(origin: .zero, size: CGSize(width: (extent.width * scale).rounded(),
                                                    height: (extent.height * scale).rounded()))
    }
    let w = Int(extent.width), h = Int(extent.height)
    print("EXTENT\t\(w)x\(h)")
    let cs = CGColorSpace(name: rec2020 ? CGColorSpace.linearITUR_2020 : CGColorSpace.extendedLinearSRGB)!
    var ctxOptions: [CIContextOption: Any] = [.cacheIntermediates: false]
    if rec2020 {
        // The product CIContextPool shape (working/output = linear Rec2020,
        // CI-internal half): the shape the v9 green-skew defect was seen in.
        ctxOptions[.workingColorSpace] = cs
        ctxOptions[.outputColorSpace] = cs
        ctxOptions[.workingFormat] = CIFormat.RGBAh
    }
    let ctx = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: ctxOptions)
    gCtx = ctx
    let a = allocBuf(w, h)
    let b = allocBuf(w, h)
    defer { freeBuf(a); freeBuf(b) }

    var results: [CIRAWDecoderVersion: (ms: [Double], initMs: [Double], before: String, after: String, nilOut: Bool)] = [:]
    // Warm up the whole pipeline (model load + PSO compile) once per process.
    for v in versions {
        _ = renderInto(url: url, version: v, fitLongEdge: fit, buf: a, cs: cs)
    }
    for v in versions {
        var ms: [Double] = [], ims: [Double] = []
        var before = "", after = "", nilOut = false
        for _ in 0..<reps {
            ctx.clearCaches()
            let r = renderInto(url: url, version: v, fitLongEdge: fit, buf: a, cs: cs)
            ms.append(r.ms); ims.append(r.initMs)
            before = r.before; after = r.after; nilOut = r.nilOutput
            if !r.error.isEmpty { print("ERROR\t\(versionName(v))\t\(r.error)") }
        }
        results[v] = (ms, ims, before, after, nilOut)
    }

    // Pairwise diff with only two full-resolution buffers:
    // v0->a, v1->b, diff; v2->a, diff(v2,v1); v0->b again, diff(v2,v0).
    if versions.count >= 1 {
        _ = renderInto(url: url, version: versions[0], fitLongEdge: fit, buf: a, cs: cs)
    }
    if versions.count >= 2 {
        _ = renderInto(url: url, version: versions[1], fitLongEdge: fit, buf: b, cs: cs)
        let d = diff(a, b)
        print("DIFF\t\(versionName(versions[0]))\t\(versionName(versions[1]))\tbitEqual=\(d.bitEqual)\tmaxAD=\(fmt(d.maxAD, 9))\tmeanAD=\(fmt(d.meanAD, 9))\tmaxAD255=\(fmt(d.maxAD * 255, 6))")
        let ma = means(a), mb = means(b)
        print("MEANS\t\(versionName(versions[0]))\tR=\(fmt(ma.r))\tG=\(fmt(ma.g))\tB=\(fmt(ma.bl))\tA=\(fmt(ma.a))\tGoverR=\(fmt(ma.g / ma.r, 4))")
        print("MEANS\t\(versionName(versions[1]))\tR=\(fmt(mb.r))\tG=\(fmt(mb.g))\tB=\(fmt(mb.bl))\tA=\(fmt(mb.a))\tGoverR=\(fmt(mb.g / mb.r, 4))")
    }
    if versions.count >= 3 {
        _ = renderInto(url: url, version: versions[2], fitLongEdge: fit, buf: a, cs: cs)
        let d = diff(a, b)
        print("DIFF\t\(versionName(versions[2]))\t\(versionName(versions[1]))\tbitEqual=\(d.bitEqual)\tmaxAD=\(fmt(d.maxAD, 9))\tmeanAD=\(fmt(d.meanAD, 9))\tmaxAD255=\(fmt(d.maxAD * 255, 6))")
        let ma = means(a)
        print("MEANS\t\(versionName(versions[2]))\tR=\(fmt(ma.r))\tG=\(fmt(ma.g))\tB=\(fmt(ma.bl))\tA=\(fmt(ma.a))\tGoverR=\(fmt(ma.g / ma.r, 4))")
        _ = renderInto(url: url, version: versions[0], fitLongEdge: fit, buf: b, cs: cs)
        let d2 = diff(a, b)
        print("DIFF\t\(versionName(versions[2]))\t\(versionName(versions[0]))\tbitEqual=\(d2.bitEqual)\tmaxAD=\(fmt(d2.maxAD, 9))\tmeanAD=\(fmt(d2.meanAD, 9))\tmaxAD255=\(fmt(d2.maxAD * 255, 6))")
    }
    for v in versions {
        guard let r = results[v] else { continue }
        print("TIME\t\(versionName(v))\tmed_ms=\(fmt(med(r.ms), 3))\tmin_ms=\(fmt(r.ms.min() ?? 0, 3))\tmax_ms=\(fmt(r.ms.max() ?? 0, 3))\tmed_init_ms=\(fmt(med(r.initMs), 3))\treadback_before=\(r.before)\treadback_after=\(r.after)\tnil_output=\(r.nilOut)\treps=\(r.ms.count)")
    }
    dumpProperties(url)
}

// MARK: - main

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: raw9probe info <file...> | models <model> | compare <file> --versions v7,v8,v9 [--reps 5] [--fit 2560]")
    exit(2)
}
args.removeFirst()
switch cmd {
case "info":
    cmdInfo(args)
case "paths":
    guard let p = args.first else { exit(2) }
    cmdPaths(p)
case "models":
    guard let m = args.first else { exit(2) }
    cmdModels(m)
case "compare":
    guard let path = args.first else { exit(2) }
    var versionsSpec = "v7,v8,v9"
    var reps = 5
    var fit: Int? = nil
    var rec2020 = false
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--versions": versionsSpec = args[i + 1]; i += 2
        case "--reps": reps = Int(args[i + 1]) ?? 5; i += 2
        case "--fit": fit = Int(args[i + 1]); i += 2
        case "--rec2020": rec2020 = true; i += 1
        default: i += 1
        }
    }
    var versions: [CIRAWDecoderVersion] = []
    for name in versionsSpec.split(separator: ",") {
        if let v = version(named: String(name)) { versions.append(v) }
        else { print("ERROR\tunknown version \(name)"); exit(2) }
    }
    cmdCompare(path, versions: versions, reps: reps, fit: fit, rec2020: rec2020)
default:
    print("unknown command \(cmd)")
    exit(2)
}
