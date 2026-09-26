// Plan 01-05 Spike B supplement — the two measurements the main harness is
// missing, in a memory-lean process (one file per run, clearCaches between
// phases to avoid the CI tile-render crash seen after many 100MP decodes):
//   1. float32 RGBA native-res plane test (the D-20 working-set number)
//   2. CACHED-frame cost: decode ONCE into a full-size RGBA8 bitmap, wrap it
//      as a CIImage, then per-frame aspect-fit/pan transforms at 2560x1440 —
//      the real app architecture (decode→texture cache→blit) vs the main
//      harness's uncached re-decode-per-frame path.
//   perf-extra <file>
import Foundation
import CoreImage
import CoreGraphics
import Metal
import os

setbuf(stdout, nil)
let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer.spikeb", category: "perf-extra")

func mb(_ b: Int64) -> String { String(format: "%.0f MB", Double(b) / 1048576.0) }
func footprint() -> Int64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
}
func msSince(_ s: ContinuousClock.Instant) -> Double {
    let d = s.duration(to: ContinuousClock.now)
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

final class Peak: @unchecked Sendable {
    private var peak: Int64 = 0
    private var base: Int64 = 0
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    func start() { base = footprint(); lock.lock(); peak = base; lock.unlock()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        t.schedule(deadline: .now(), repeating: .milliseconds(10))
        t.setEventHandler { [weak self] in guard let self else { return }
            let v = self.foot(); self.lock.lock(); self.peak = max(self.peak, v); self.lock.unlock() }
        t.resume(); timer = t }
    @discardableResult func stop() -> Int64 { timer?.cancel(); timer = nil
        lock.lock(); defer { lock.unlock() }; return peak - base }
    func foot() -> Int64 { footprint() }
}
let peak = Peak()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let device = MTLCreateSystemDefaultDevice()!
let rec2020 = CGColorSpace(name: CGColorSpace.linearITUR_2020)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: rec2020])

print("## EXTRA: \(url.lastPathComponent)")
guard let probe = CIRAWFilter(imageURL: url), let pimg = probe.outputImage else { print("INIT FAIL"); exit(1) }
let native = probe.nativeSize
let w = Int(native.width), h = Int(native.height)
print("nativeSize: \(w)x\(h) (\(String(format: "%.1f", Double(w * h) / 1e6)) MP)  float32 plane ≈ \(mb(Int64(w * h * 16)))  supported=[\(probe.supportedDecoderVersions.map(\.rawValue).joined(separator: ","))]")

// warm decode (v8) once — also proves the file decodes in this process
var bitmap: UnsafeMutableRawPointer?
posix_memalign(&bitmap, 64, w * h * 4)
let start = ContinuousClock.now
context.render(pimg, toBitmap: bitmap!, rowBytes: w * 4, bounds: CGRect(origin: .zero, size: native), format: .RGBA8, colorSpace: rec2020)
print("warm full decode (v8): \(String(format: "%.0f", msSince(start))) ms")

// 1. float32 plane test
var fbuf: UnsafeMutableRawPointer?
posix_memalign(&fbuf, 64, w * h * 16)
if let fbuf, let f2 = CIRAWFilter(imageURL: url), let i2 = f2.outputImage {
    f2.decoderVersion = .version8
    peak.start()
    let s = ContinuousClock.now
    context.render(i2, toBitmap: fbuf, rowBytes: w * 16, bounds: CGRect(origin: .zero, size: native), format: .RGBAf, colorSpace: rec2020)
    let ms = msSince(s)
    let p = peak.stop()
    print("float32 RGBA native render: \(String(format: "%.0f", ms)) ms  footprintPeak=+\(mb(p))  end=\(mb(footprint()))")
}
free(fbuf)
context.clearCaches()

// 2. CACHED-frame test: the decoded RGBA8 plane wrapped as a CIImage, then
//    viewport-res transforms per frame (aspect-fit + pan simulation).
if let bitmap {
    let data = Data(bytesNoCopy: bitmap, count: w * h * 4, deallocator: .none)
    let cached = CIImage(bitmapData: data, bytesPerRow: w * 4, size: native,
                         format: .RGBA8, colorSpace: rec2020)
    let vw = 2560, vh = 1440
    var vbuf: UnsafeMutableRawPointer?
    posix_memalign(&vbuf, 64, vw * vh * 4)
    var frameTimes = [Double]()
    let scale = min(Double(vw) / native.width, Double(vh) / native.height)
    let dw = native.width * scale, dh = native.height * scale
    for phase in 0..<60 {
        // pan drift: translate by up to ±(dw-vw)/2 over 60 frames, aspect-fit base
        let t = max(0, (dw - Double(vw)) / 2) * sin(Double(phase) / 60 * .pi)
        let tf = CGAffineTransform(translationX: (Double(vw) - dw) / 2 - t, y: (Double(vh) - dh) / 2).scaledBy(x: scale, y: scale)
        let s = ContinuousClock.now
        context.render(cached.transformed(by: tf), toBitmap: vbuf!, rowBytes: vw * 4,
                       bounds: CGRect(x: 0, y: 0, width: vw, height: vh), format: .RGBA8, colorSpace: srgb)
        frameTimes.append(msSince(s))
    }
    let sorted = frameTimes.sorted()
    let med = sorted[sorted.count / 2]
    let over = frameTimes.filter { $0 > 16.67 }.count
    print("CACHED viewport 2560x1440 (decode-once + per-frame transform) n=60: med \(String(format: "%.2f", med)) ms/frame (min \(String(format: "%.2f", sorted.first!)) / max \(String(format: "%.2f", sorted.last!)))  est fps=\(String(format: "%.0f", 1000 / med))  frames>16.67ms: \(over)/60")
    free(vbuf)
    free(bitmap)
}
print("footprint at end: \(mb(footprint()))")
