// launchprobe: time from process spawn to the first pixels of its window on screen.
//
// Starts a low-rate ScreenCaptureKit capture of the main display first, waits
// until frames are flowing, records t0, spawns the child, and then reports:
//   - first frame after t0 whose cells inside the expected window rect changed
//   - first moment CGWindowListCopyWindowInfo reports a window for that pid
//   - the child's own stdout lines with host timestamps
//
// usage:
//   launchprobe --out <file> --rect x,y,w,h -- <executable> [args...]
//
// The child inherits the caller's environment.

import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

let hostClock = CMClockGetHostTimeClock()
func hostNow() -> Double { CMTimeGetSeconds(CMClockGetTime(hostClock)) }

struct Frame {
    let pts: Double
    let cb: Double
    let changedInRect: Int
    let changedAll: Int
    let totalInRect: Int
}

final class Rec: NSObject, SCStreamOutput, SCStreamDelegate {
    let gridW = 192
    let gridH = 108
    let rect: CGRect // in points, display coordinates
    let displayPoints: CGSize
    var prev: [UInt8]?
    var frames: [Frame] = []
    let lock = NSLock()
    let outPath: String

    init(outPath: String, rect: CGRect, displayPoints: CGSize) {
        self.outPath = outPath
        self.rect = rect
        self.displayPoints = displayPoints
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid else { return }
        let cb = hostNow()
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let bpr = base.assumingMemoryBound(to: UInt8.self)
        var grid = [UInt8](repeating: 0, count: gridW * gridH)
        for gy in 0..<gridH {
            let sy = min(h - 1, gy * h / gridH + h / (2 * gridH))
            let row = bpr + sy * stride
            for gx in 0..<gridW {
                let sx = min(w - 1, gx * w / gridW + w / (2 * gridW))
                let p = row + sx * 4
                grid[gy * gridW + gx] = UInt8((Int(p[0]) + Int(p[1]) + Int(p[2])) / 3)
            }
        }
        // window rect in grid cells
        let x0 = max(0, Int(rect.minX / displayPoints.width * Double(gridW)))
        let x1 = min(gridW, Int(rect.maxX / displayPoints.width * Double(gridW)) + 1)
        let y0 = max(0, Int(rect.minY / displayPoints.height * Double(gridH)))
        let y1 = min(gridH, Int(rect.maxY / displayPoints.height * Double(gridH)) + 1)
        var inRect = 0, totalInRect = 0, all = 0
        lock.lock()
        if let prev = prev {
            for gy in 0..<gridH {
                for gx in 0..<gridW {
                    let d = abs(Int(grid[gy * gridW + gx]) - Int(prev[gy * gridW + gx]))
                    if d > 10 {
                        all += 1
                        if gx >= x0 && gx < x1 && gy >= y0 && gy < y1 { inRect += 1 }
                    }
                    if gx >= x0 && gx < x1 && gy >= y0 && gy < y1 { totalInRect += 1 }
                }
            }
        }
        prev = grid
        frames.append(Frame(pts: pts, cb: cb, changedInRect: inRect, changedAll: all, totalInRect: totalInRect))
        lock.unlock()
    }

    func stop() {
        lock.lock()
        var text = ""
        for (i, f) in frames.enumerated() {
            text += String(format: "F %d %.6f %.6f %d %d %d\n", i, f.pts, f.cb, f.changedInRect, f.changedAll, f.totalInRect)
        }
        try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
        lock.unlock()
    }
}

let args = Array(CommandLine.arguments.dropFirst())
func opt(_ n: String) -> String? {
    guard let i = args.firstIndex(of: n), i + 1 < args.count else { return nil }
    return args[i + 1]
}
guard let out = opt("--out"), let rectS = opt("--rect"),
      let sep = args.firstIndex(of: "--"), sep + 1 < args.count else {
    print("usage: launchprobe --out <file> --rect x,y,w,h -- <cmd> [args...]")
    exit(2)
}
let comps = rectS.split(separator: ",").map { Double($0)! }
let rect = CGRect(x: comps[0], y: comps[1], width: comps[2], height: comps[3])
let cmd = Array(args[(sep + 1)...])

let main = NSScreen.main!
let displayPoints = main.frame.size

let sem = DispatchSemaphore(value: 0)
var display: SCDisplay?
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        display = content.displays.first
    } catch {
        FileHandle.standardError.write("content failed: \(error)\n".data(using: .utf8)!)
    }
    sem.signal()
}
sem.wait()
guard let d = display else { exit(3) }

let filter = SCContentFilter(display: d, excludingWindows: [])
let cfg = SCStreamConfiguration()
cfg.width = 384
cfg.height = 216
cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
cfg.queueDepth = 6
cfg.pixelFormat = kCVPixelFormatType_32BGRA
cfg.showsCursor = false
cfg.capturesAudio = false
let rec = Rec(outPath: out, rect: rect, displayPoints: displayPoints)
let stream = SCStream(filter: filter, configuration: cfg, delegate: rec)
do {
    try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "launchframes", qos: .userInteractive))
} catch {
    FileHandle.standardError.write("addStreamOutput failed: \(error)\n".data(using: .utf8)!)
    exit(3)
}
let started = DispatchSemaphore(value: 0)
Task {
    do { try await stream.startCapture() } catch {
        FileHandle.standardError.write("startCapture failed: \(error)\n".data(using: .utf8)!)
    }
    started.signal()
}
started.wait()
usleep(700_000)

let spawnT = hostNow()
let proc = Process()
proc.executableURL = URL(fileURLWithPath: cmd[0])
proc.arguments = Array(cmd.dropFirst())
proc.standardOutput = FileHandle.standardOutput
proc.standardError = FileHandle.standardError
Thread.sleep(forTimeInterval: 0.05)
do { try proc.run() } catch {
    FileHandle.standardError.write("spawn failed: \(error)\n".data(using: .utf8)!)
    exit(4)
}
let pid = proc.processIdentifier

var windowT: Double? = nil
var windowInfo: String = ""
let pollDeadline = Date().addingTimeInterval(6)
while Date() < pollDeadline {
    if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
        for w in list {
            if let owner = w[kCGWindowOwnerPID as String] as? pid_t, owner == pid {
                let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
                windowT = hostNow()
                windowInfo = "\(b["X"] ?? "?") ,\(b["Y"] ?? "?") \(b["Width"] ?? "?")x\(b["Height"] ?? "?")"
                break
            }
        }
    }
    if windowT != nil { break }
    usleep(2_000)
}

// let it live long enough for first content, then terminate
Thread.sleep(forTimeInterval: 3.0)
proc.terminate()
Thread.sleep(forTimeInterval: 0.3)
Task { try? await stream.stopCapture() }
Thread.sleep(forTimeInterval: 0.2)
rec.stop()

print(String(format: "SPAWN %.6f", spawnT))
if let wt = windowT {
    print(String(format: "WINDOW_LISTED %.6f (%.1f ms after spawn) bounds=%@", wt, (wt - spawnT) * 1000, windowInfo))
} else {
    print("WINDOW_LISTED none within 6 s")
}
print("FRAMES \(rec.frames.count)")
