// Plan 01-05 Spike A probe — CIRAW 9 capability boundary on macOS 27.0 GM.
// Self-contained (imports only system frameworks; NOT part of any build
// target, per the .work process-files convention). Same "public-API-driven"
// pattern as the Plan 01-03/01-04 smoke harnesses.
//
// Modes:
//   surface            — GM API-surface probe: supportedCameraModels total +
//                        per-decoder-version, sample-camera membership, ObjC
//                        runtime property/method dump of CIRAWFilter.
//   probe <file>...    — per-file behavior probe: supportedDecoderVersions,
//                        per-version `*Supported` flags (API-level no-op
//                        evidence), decode+render timing (os.signpost),
//                        phys_footprint memory, tunable-key pixel-diff
//                        (behavioral no-op evidence), mattes, preview.
//
// Output: markdown-ish text on stdout (tee to
// .work/01-05/spike-a-probe-output.txt by the caller).

import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import Metal
import UniformTypeIdentifiers
import os
import Darwin
import ObjectiveC

// MARK: - helpers

let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer.spikea", category: "decode")

func footprintBytes() -> Int64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
}

func mb(_ bytes: Int64) -> String { String(format: "%.0f MB", Double(bytes) / 1048576.0) }

func makeContext() -> CIContext {
    let device = MTLCreateSystemDefaultDevice()!
    // CIRAW-4 mitigation under test: cacheIntermediates false is the config
    // Plan 03's CIContextPool already uses.
    return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
}

/// Render a 1:1 crop of `image` to RGBA8 sRGB bytes.
func renderCrop(_ image: CIImage, rect: CGRect, context: CIContext) -> (bytes: [UInt8], ms: Double, footprintPeak: Int64)? {
    let w = Int(rect.width), h = Int(rect.height)
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let before = footprintBytes()
    let clock = ContinuousClock()
    let state = signposter.beginInterval("render-crop")
    var peak = before
    var ms = 0.0
    buf.withUnsafeMutableBytes { raw in
        let start = clock.now
        context.render(image,
                       toBitmap: raw.baseAddress!,
                       rowBytes: w * 4,
                       bounds: rect,
                       format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let dur = start.duration(to: clock.now)
        ms = Double(dur.components.seconds) * 1000 + Double(dur.components.attoseconds) / 1e15
        let now = footprintBytes()
        if now > peak { peak = now }
    }
    signposter.endInterval("render-crop", state)
    return (buf, ms, peak)
}

func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    var sum = 0
    for i in 0..<a.count { sum += abs(Int(a[i]) - Int(b[i])) }
    return Double(sum) / Double(a.count)
}

func savePNG(_ bytes: [UInt8], w: Int, h: Int, to url: URL) {
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return }
    var image: CGImage? = nil
    bytes.withUnsafeBufferPointer { raw in
        let ctx = CGContext(data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
                            width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        image = ctx?.makeImage()
    }
    guard let cg = image else { return }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
}

func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> (T, Double) {
    let clock = ContinuousClock()
    let start = clock.now
    let value = try body()
    let dur = start.duration(to: clock.now)
    let ms = Double(dur.components.seconds) * 1000 + Double(dur.components.attoseconds) / 1e15
    return (value, ms)
}

// MARK: - API-surface probe

func probeSurface() {
    print("## CIRAW GM API surface — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("chip: \(Sysctl.model) / \(Sysctl.chip) — RAM: \(mb(Int64(Sysctl.memSize)))")

    let all = CIRAWFilter.supportedCameraModels
    print("\n### supportedCameraModels (total): \(all.count)")

    let versions: [(String, CIRAWDecoderVersion)] = [
        ("version6", .version6), ("version7", .version7), ("version8", .version8),
        ("version9", .version9), ("version8DNG", .version8DNG), ("version9DNG", .version9DNG),
    ]
    print("\n### camera-model count per decoder version")
    print("| version | models |")
    print("|---|---|")
    for (name, v) in versions {
        let list = CIRAWFilter.supportedCameraModels(with: v)
        print("| \(name) | \(list.count) |")
    }

    let samples = ["GFX100S", "X-T5", "X100VI", "X-H2S", "Z 8", "ILCE-7RM5", "ILCE-6700",
                   "EOS R10", "OM-1 Mark II", "iPhone 12 Pro", "EOS 5D Mark III", "X2D", "IQ4"]
    print("\n### sample-camera membership (exact names found in the v8/v9 lists)")
    for s in samples {
        let in8 = CIRAWFilter.supportedCameraModels(with: .version8).filter { $0.contains(s) }
        let in9 = CIRAWFilter.supportedCameraModels(with: .version9).filter { $0.contains(s) }
        print("- \(s): v8=\(in8.isEmpty ? "ABSENT" : in8.joined(separator: "|")) v9=\(in9.isEmpty ? "ABSENT" : in9.joined(separator: "|"))")
    }

    // v9-only models (in v9 but not v8) — evidence of RAW-9-only coverage
    let set8 = Set(CIRAWFilter.supportedCameraModels(with: .version8))
    let only9 = CIRAWFilter.supportedCameraModels(with: .version9).filter { !set8.contains($0) }
    print("\n### models covered by v9 but NOT v8: \(only9.count)")
    print(only9.prefix(30).joined(separator: ", "))

    // ObjC runtime dump — the @objc-exposed surface actually linked at runtime
    let cls: AnyClass = CIRAWFilter.self
    var pcount: UInt32 = 0
    let props = class_copyPropertyList(cls, &pcount)
    print("\n### CIRAWFilter ObjC runtime properties (\(pcount))")
    if let props {
        for i in 0..<Int(pcount) {
            let name = String(cString: property_getName(props[i]))
            print("- \(name)")
        }
    }
    free(props)
}

// MARK: - per-file probe

let tunables: [(String, (CIRAWFilter) -> Bool, (CIRAWFilter, Float) -> Void)] = [
    ("luminanceNoiseReductionAmount", { $0.isLuminanceNoiseReductionSupported }, { $0.luminanceNoiseReductionAmount = $1 }),
    ("colorNoiseReductionAmount", { $0.isColorNoiseReductionSupported }, { $0.colorNoiseReductionAmount = $1 }),
    ("sharpnessAmount", { $0.isSharpnessSupported }, { $0.sharpnessAmount = $1 }),
    ("contrastAmount", { $0.isContrastSupported }, { $0.contrastAmount = $1 }),
    ("detailAmount", { $0.isDetailSupported }, { $0.detailAmount = $1 }),
    ("moireReductionAmount", { $0.isMoireReductionSupported }, { $0.moireReductionAmount = $1 }),
    ("despeckleAmount", { $0.isDespeckleSupported }, { $0.despeckleAmount = $1 }),
    ("localToneMapAmount", { $0.isLocalToneMapSupported }, { $0.localToneMapAmount = $1 }),
]

func probeFile(_ url: URL, context: CIContext, goldenDir: URL?) {
    let fileSize = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64) ?? 0
    print("\n---\n## FILE: \(url.lastPathComponent) (\(mb(fileSize)))")
    do {
        let before = footprintBytes()
        let (filter, initMs) = try timed("init") { CIRAWFilter(imageURL: url) }
        guard let filter else { print("INIT FAILED"); return }
        print("init: \(String(format: "%.0f", initMs)) ms")

        let versions = filter.supportedDecoderVersions.map(\.rawValue)
        print("supportedDecoderVersions: [\(versions.joined(separator: ", "))]")
        let native = filter.nativeSize
        print("nativeSize: \(Int(native.width))x\(Int(native.height)) (\(String(format: "%.1f", native.width * native.height / 1e6)) MP)")
        print("orientation: \(filter.orientation.rawValue)  draftModeEnabled: \(filter.isDraftModeEnabled)  properties.keys: \(filter.properties.keys.count)")

        // Embedded preview (thumbnail-path relevance)
        if let prev = filter.previewImage {
            print("previewImage: \(Int(prev.extent.width))x\(Int(prev.extent.height))")
        } else { print("previewImage: nil") }

        // Make/model from ImageIO
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let make = (props["Make"] as? String)
                ?? (exif?[kCGImagePropertyExifLensMake as String] as? String) ?? "?"
            let model = (props["Model"] as? String) ?? "?"
            print("Make/Model: \(make) / \(model)")
        }

        // Probe each relevant decoder version (limit to 8/9 + DNG variants)
        let probeVersions: [CIRAWDecoderVersion] = [.version8, .version9, .version8DNG, .version9DNG]
            .filter { versions.contains($0.rawValue) }

        for v in probeVersions {
            let vn = v.rawValue
            // fresh filter per decode (CIFilter not Sendable / single-use config)
            guard let f = CIRAWFilter(imageURL: url) else { print("[\(vn)] INIT FAILED"); continue }
            f.decoderVersion = v

            // RAW 9 on-demand resources (CoreML model) — first use may download
            if vn.contains("9") {
                let sem = DispatchSemaphore(value: 0)
                let progress = f.downloadResources(timeout: 300) { _ in sem.signal() }
                _ = sem.wait(timeout: .now() + 310)
                print("[\(vn)] downloadResources: fractionCompleted=\(String(format: "%.2f", progress.fractionCompleted)) cancelled=\(progress.isCancelled)")
            }

            // API-level capability flags under this version (no-op evidence)
            let flags = tunables.map { "\($0.0)=\($0.1(f) ? "supported" : "UNSUPPORTED")" }
            let lc = f.isLensCorrectionSupported ? "supported" : "UNSUPPORTED"
            let hr = f.isHighlightRecoverySupported ? "supported" : "UNSUPPORTED"
            print("[\(vn)] flags: \(flags.joined(separator: " "))  lensCorrection=\(lc)  highlightRecovery=\(hr)")

            guard let img = f.outputImage else { print("[\(vn)] outputImage nil"); continue }
            let ext = img.extent
            // center 320x240 1:1 crop
            let cw: CGFloat = 320, ch: CGFloat = 240
            let crop = CGRect(x: ext.midX - cw / 2, y: ext.midY - ch / 2, width: cw, height: ch)

            guard let base = renderCrop(img, rect: crop, context: context) else { print("[\(vn)] baseline render failed"); continue }
            let fpNow = footprintBytes()
            print("[\(vn)] baseline crop render: \(String(format: "%.0f", base.ms)) ms  footprint now=\(mb(fpNow)) (delta +\(mb(fpNow - before)))")

            if let gd = goldenDir, v == .version8 || v == .version9 {
                let tag = vn.replacingOccurrences(of: "version", with: "")
                savePNG(base.bytes, w: 320, h: 240, to: gd.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-center-\(tag).png"))
            }

            // Behavioral no-op evidence: max out each tunable, diff pixels
            var diffs: [String] = []
            for (name, isSupported, setKey) in tunables {
                guard let f2 = CIRAWFilter(imageURL: url), let i2 = f2.outputImage else { continue }
                f2.decoderVersion = v
                guard isSupported(f2) else { diffs.append("\(name):flag-unsupported"); continue }
                setKey(f2, 1.0)
                guard let img2 = f2.outputImage,
                      let r = renderCrop(img2, rect: crop, context: context) else { diffs.append("\(name):render-fail"); continue }
                let d = meanAbsDiff(base.bytes, r.bytes)
                diffs.append("\(name):\(String(format: "%.2f", d))\(d < 0.3 ? "(NO-OP)" : "")")
            }
            print("[\(vn)] tunable pixel-diff vs baseline (mean abs /255, <0.3 ≈ no-op): \(diffs.joined(separator: "  "))")

            // Lens-correction behavioral evidence
            if f.isLensCorrectionSupported {
                if let f3 = CIRAWFilter(imageURL: url) {
                    f3.decoderVersion = v
                    f3.isLensCorrectionEnabled = true
                    if let i3 = f3.outputImage, let r = renderCrop(i3, rect: crop, context: context) {
                        let d = meanAbsDiff(base.bytes, r.bytes)
                        print("[\(vn)] lensCorrection enabled diff: \(String(format: "%.2f", d))\(d < 0.3 ? " (no visible change at center crop)" : "")")
                    }
                }
            }
        }

        // Apple mattes (ProRAW only in practice)
        let mattes = ["portraitEffectsMatte": filter.portraitEffectsMatte,
                      "skinMatte": filter.semanticSegmentationSkinMatte,
                      "hairMatte": filter.semanticSegmentationHairMatte,
                      "glassesMatte": filter.semanticSegmentationGlassesMatte,
                      "skyMatte": filter.semanticSegmentationSkyMatte,
                      "teethMatte": filter.semanticSegmentationTeethMatte]
        let mstr = mattes.map { "\($0.key)=\($0.value != nil ? "present" : "nil")" }.joined(separator: " ")
        print("mattes: \(mstr)")
    } catch {
        print("PROBE ERROR: \(error)")
    }
}

// MARK: - main

// tiny sysctl helpers
enum Sysctl {
    static func str(_ name: String) -> String {
        var size = 0; sysctlbyname(name, nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }
    static func u64(_ name: String) -> UInt64 {
        var v: UInt64 = 0; var size = MemoryLayout<UInt64>.size
        sysctlbyname(name, &v, &size, nil, 0); return v
    }
    static var model: String { str("hw.model") }
    static var chip: String { str("machdep.cpu.brand_string") }
    static var memSize: UInt64 { u64("hw.memsize") }
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: ciraw-probe surface | probe <file>...\n".data(using: .utf8)!)
    exit(2)
}

let mode = CommandLine.arguments[1]
let context = makeContext()
print("CIContext: device=\(MTLCreateSystemDefaultDevice()?.name ?? "?") cacheIntermediates=false")

switch mode {
case "surface":
    probeSurface()
case "models":
    print("### FULL version9 model list (\(CIRAWFilter.supportedCameraModels(with: .version9).count))")
    for m in CIRAWFilter.supportedCameraModels(with: .version9) { print(m) }
    print("\n### FULL version8 model list (\(CIRAWFilter.supportedCameraModels(with: .version8).count))")
    for m in CIRAWFilter.supportedCameraModels(with: .version8) { print(m) }
case "probe":
    let goldenDir = URL(fileURLWithPath: CommandLine.arguments[2])
    try? FileManager.default.createDirectory(at: goldenDir, withIntermediateDirectories: true)
    for path in CommandLine.arguments.dropFirst(3) {
        probeFile(URL(fileURLWithPath: path), context: context, goldenDir: goldenDir)
    }
    print("\nfootprint at end: \(mb(footprintBytes()))")
default:
    print("unknown mode \(mode)"); exit(2)
}
