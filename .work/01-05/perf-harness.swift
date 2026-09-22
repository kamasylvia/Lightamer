// Plan 01-05 Spike B harness — 100MP Metal performance vertebra on macOS 27.0 GM.
// Self-contained (system frameworks only; NOT part of any build target).
// Headless measurement of the decode→CIContext→texture vertebra against the
// D-32 budgets: decode ≤2s, display ≤500ms, steady-state memory ≤4GB,
// frame ≤16ms at viewport res.
//
//   perf-harness <file> [runs=5]
//
// Measures per file (median/min/max of `runs`):
//   - full-size decode cost (CIRAW v8 vs v9 where both supported), forced via
//     a full-bounds RGBA8 bitmap render (the real pipeline cost)
//   - 100MP float32 RGBA working-set test (RGBA32Float bitmap @ native res)
//   - blit paths: CIContext.render to .rgba32Float MTLTexture (retest of the
//     Plan 03 GM-beta silent-empty finding) vs bitmap+texture.replace
//   - viewport-res (2560x1440) aspect-fit render ×60 → per-frame ms → 60fps proxy
// Memory: phys_footprint sampled at 10ms by a background timer (true peak).

import Foundation
import CoreImage
import CoreGraphics
import Metal
import os
import Darwin

let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer.spikeb", category: "perf")

// MARK: - memory sampler (true peak)

final class PeakFootprint: @unchecked Sendable {
    private var peak: Int64 = 0
    private var baseline: Int64 = 0
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    func start() {
        baseline = current()
        lock.lock(); peak = baseline; lock.unlock()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        t.schedule(deadline: .now(), repeating: .milliseconds(10))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let v = self.current()
            self.lock.lock(); self.peak = max(self.peak, v); self.lock.unlock()
        }
        t.resume()
        timer = t
    }
    func stopPeak() -> Int64 {
        timer?.cancel(); timer = nil
        lock.lock(); defer { lock.unlock() }
        return peak - baseline
    }
    func current() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
    }
}

func mb(_ b: Int64) -> String { String(format: "%.0f MB", Double(b) / 1048576.0) }

func msSince(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: ContinuousClock.now)
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func medianMinMax(_ v: [Double]) -> (med: Double, min: Double, max: Double) {
    let s = v.sorted()
    let n = s.count
    let med = n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    return (med, s.first ?? 0, s.last ?? 0)
}

let peak = PeakFootprint()

// MARK: - main

setbuf(stdout, nil) // line-buffered: partial results survive a crash
let path = CommandLine.arguments[1]
let runs = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 5 : 5
let url = URL(fileURLWithPath: path)

let device = MTLCreateSystemDefaultDevice()!
let rws = device.recommendedMaxWorkingSetSize
print("## PERF: \(url.lastPathComponent)")
print("device: \(device.name)  recommendedMaxWorkingSetSize: \(mb(Int64(rws)))  RAM: \(mb(Int64(ProcessInfo.processInfo.physicalMemory)))")
print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

// working space per FOUND-02: linear Rec2020 (scene-referred) at the context;
// display crops convert to sRGB at the render call.
let rec2020 = CGColorSpace(name: CGColorSpace.linearITUR_2020)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: rec2020])

// CIRAWFilter init + per-file supported versions
let (probeFilter, initMs) = { () -> (CIRAWFilter?, Double) in
    let c = ContinuousClock.now
    let f = CIRAWFilter(imageURL: url)
    return (f, msSince(c))
}()
guard let probeFilter else { print("INIT FAILED"); exit(1) }
print("init: \(String(format: "%.0f", initMs)) ms")
let versions = probeFilter.supportedDecoderVersions.map(\.rawValue)
let native = probeFilter.nativeSize
let mp = Double(native.width * native.height) / 1e6
print("supportedDecoderVersions: [\(versions.joined(separator: ", "))]")
print("nativeSize: \(Int(native.width))x\(Int(native.height)) (\(String(format: "%.1f", mp)) MP)  full RGBA32Float plane ≈ \(mb(Int64(native.width * native.height * 16)))")

let fullBounds = CGRect(origin: .zero, size: native)
let w = Int(native.width), h = Int(native.height)

func decodeAndRenderRGBA8(version: CIRAWDecoderVersion) -> (ms: Double, peak: Int64) {
    guard let f = CIRAWFilter(imageURL: url), let img = f.outputImage else { return (-1, 0) }
    f.decoderVersion = version
    var bitmap: UnsafeMutableRawPointer?
    posix_memalign(&bitmap, 64, w * h * 4)
    defer { free(bitmap) }
    let state = signposter.beginInterval("decode-full-rgba8")
    peak.start()
    let start = ContinuousClock.now
    context.render(img,
                   toBitmap: bitmap!,
                   rowBytes: w * 4,
                   bounds: fullBounds,
                   format: .RGBA8,
                   colorSpace: rec2020)
    let ms = msSince(start)
    signposter.endInterval("decode-full-rgba8", state)
    let p = peak.stopPeak()
    return (ms, p)
}

// viewport-res aspect-fit frame proxy
func viewportFrameCost(version: CIRAWDecoderVersion, frames: Int = 60) -> [Double] {
    guard let f = CIRAWFilter(imageURL: url), let img = f.outputImage else { return [] }
    f.decoderVersion = version
    let vw = 2560, vh = 1440
    let scale = min(Double(vw) / native.width, Double(vh) / native.height)
    let dw = native.width * scale, dh = native.height * scale
    let t = CGAffineTransform(translationX: (Double(vw) - dw) / 2, y: (Double(vh) - dh) / 2).scaledBy(x: scale, y: scale)
    let fitted = img.transformed(by: t)
    var out = [Double]()
    out.reserveCapacity(frames)
    var bitmap: UnsafeMutableRawPointer?
    posix_memalign(&bitmap, 64, vw * vh * 4)
    defer { free(bitmap) }
    let vpBounds = CGRect(x: 0, y: 0, width: vw, height: vh)
    for _ in 0..<frames {
        let start = ContinuousClock.now
        context.render(fitted, toBitmap: bitmap!, rowBytes: vw * 4, bounds: vpBounds, format: .RGBA8, colorSpace: srgb)
        out.append(msSince(start))
    }
    return out
}

// blit-path test: render to MTLTexture(.rgba32Float) vs bitmap+replace
func blitPathsTest(version: CIRAWDecoderVersion) {
    guard let f = CIRAWFilter(imageURL: url), let img = f.outputImage else { return }
    f.decoderVersion = version

    // A: direct render to texture (Plan 03 GM-beta silent-empty retest)
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 1024, height: 768, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .shared
    if let tex = device.makeTexture(descriptor: desc) {
        let crop = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let start = ContinuousClock.now
        context.render(img, to: tex, commandBuffer: nil, bounds: crop, colorSpace: rec2020)
        let ms = msSince(start)
        // checksum first 16KB
        let bytes = 16 * 1024
        var data = [UInt8](repeating: 0, count: bytes)
        tex.getBytes(&data, bytesPerRow: 1024 * 16, from: MTLRegionMake2D(0, 0, 1024, 64), mipmapLevel: 0)
        let nonzero = data.contains { $0 != 0 }
        print("blit-A render→MTLTexture(.rgba32Float) 1024x768 crop: \(String(format: "%.0f", ms)) ms  contentNonZero=\(nonzero)")
    }

    // B: bitmap then texture.replace (Plan 03 workaround)
    let bw = 1024, bh = 768
    var bitmap: UnsafeMutableRawPointer?
    posix_memalign(&bitmap, 64, bw * bh * 16)
    defer { free(bitmap) }
    let start = ContinuousClock.now
    context.render(img, toBitmap: bitmap!, rowBytes: bw * 16, bounds: CGRect(x: 0, y: 0, width: bw, height: bh), format: .RGBA8, colorSpace: rec2020)
    let renderMs = msSince(start)
    if let tex = device.makeTexture(descriptor: desc) {
        let s = ContinuousClock.now
        tex.replace(region: MTLRegionMake2D(0, 0, bw, bh), mipmapLevel: 0, withBytes: bitmap!, bytesPerRow: bw * 16)
        let replaceMs = msSince(s)
        print("blit-B bitmap render \(String(format: "%.0f", renderMs)) ms + texture.replace \(String(format: "%.2f", replaceMs)) ms = \(String(format: "%.0f", renderMs + replaceMs)) ms")
    }
}

// full float32 working-set test at native res (the D-20 number)
func float32PlaneTest(version: CIRAWDecoderVersion) {
    guard let f = CIRAWFilter(imageURL: url), let img = f.outputImage else { return }
    f.decoderVersion = version
    var bitmap: UnsafeMutableRawPointer?
    let allocRC = posix_memalign(&bitmap, 64, w * h * 16)
    guard allocRC == 0, let buf = bitmap else { print("float32 alloc FAILED (\(mb(Int64(w * h * 16))))"); return }
    defer { free(buf) }
    peak.start()
    let start = ContinuousClock.now
    context.render(img, toBitmap: buf, rowBytes: w * 16, bounds: fullBounds, format: .RGBAf, colorSpace: rec2020)
    let ms = msSince(start)
    let p = peak.stopPeak()
    print("float32 RGBA native-res render: \(String(format: "%.0f", ms)) ms  footprintPeak=+\(mb(p))")
}

// warmup (shader/PSO compile, IO cache) — measured runs below are steady-state
_ = decodeAndRenderRGBA8(version: .version8)

for v in versions {
    let version: CIRAWDecoderVersion = {
        switch v {
        case CIRAWDecoderVersion.version9.rawValue: return .version9
        case CIRAWDecoderVersion.version8.rawValue: return .version8
        default: return .version8
        }
    }()
    let tag = v

    // RAW 9 resources may need a first-time download
    if version == .version9 {
        let sem = DispatchSemaphore(value: 0)
        let prog = probeFilter.downloadResources(timeout: 300) { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 310)
        print("[\(tag)] downloadResources fractionCompleted=\(String(format: "%.2f", prog.fractionCompleted))")
    }

    var times = [Double](), peaks = [Int64]()
    for _ in 0..<runs {
        let r = decodeAndRenderRGBA8(version: version)
        times.append(r.ms); peaks.append(r.peak)
    }
    let t = medianMinMax(times), p = medianMinMax(peaks.map(Double.init))
    print("[\(tag)] decode+full RGBA8 render n=\(runs): med \(String(format: "%.0f", t.med)) ms (min \(String(format: "%.0f", t.min)) / max \(String(format: "%.0f", t.max)))  footprintPeak med +\(mb(Int64(p.med))) (max +\(mb(Int64(p.max))))")

    if version == .version8 || version == .version9 {
        blitPathsTest(version: version)
    }
}

// float32 working-set at native res (v8 always available for these files)
float32PlaneTest(version: .version8)

// viewport 60fps proxy on the fastest available version
let best: CIRAWDecoderVersion = versions.contains(CIRAWDecoderVersion.version9.rawValue) ? .version9 : .version8
let frames = viewportFrameCost(version: best)
if !frames.isEmpty {
    let f = medianMinMax(frames)
    let dropped = frames.filter { $0 > 16.67 }.count
    print("viewport 2560x1440 aspect-fit n=\(frames.count): med \(String(format: "%.1f", f.med)) ms/frame (min \(String(format: "%.1f", f.min)) / max \(String(format: "%.1f", f.max)))  est fps=\(String(format: "%.0f", 1000 / f.med))  frames>16.67ms: \(dropped)/\(frames.count)  [decoder \(best.rawValue)]")
}
print("footprint at end: \(mb(peak.current()))")
