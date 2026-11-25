// FrameProbe: ScreenCaptureKit window frame-timing probe with synthetic input.
//
// Records, per delivered SCK frame: index, presentation timestamp (host clock, seconds),
// callback time, and a cheap in-memory frame difference against the previous frame.
// No images are written. A scripted input sequence is posted to the target PID and each
// event's emission time is written to the same stream, so latency = first changed frame
// after an event minus the event time.
//
// usage:
//   frameprobe run --pid <pid> --window-id <cgwindowid> --out <file> --script <file> [--activate]
//   frameprobe summary <file>
//   frameprobe list
//
// script grammar (one directive per line, '#' comments):
//   wait <ms>
//   move <x> <y>
//   down [x] [y]
//   drag <x0> <y0> <x1> <y1> <steps> <step_ms>   (posts N leftMouseDragged events)
//   up [x] [y]
//   click <x> <y>
//   key <left|right|up|down|space|escape|return>
//   scroll <pixels>
//   mark <name>

import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

let hostClock = CMClockGetHostTimeClock()

func hostNow() -> Double {
    CMTimeGetSeconds(CMClockGetTime(hostClock))
}

func hostTimeToSeconds(_ t: UInt64) -> Double {
    CMTimeGetSeconds(CMClockMakeHostTimeFromSystemUnits(t))
}

struct FrameRow {
    let idx: Int
    let pts: Double
    let cb: Double
    let diff: Double
    let maxd: Double
    let cells: Int
}

struct EventRow {
    let name: String
    let t: Double
    let detail: String
}

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let lock = NSLock()
    private var frames: [FrameRow] = []
    private var events: [EventRow] = []
    private var prevGrid: [UInt8]? = nil
    private let gridW = 80
    private let gridH = 45
    private let outPath: String
    private var stopped = false
    private let done = DispatchSemaphore(value: 0)

    init(outPath: String) {
        self.outPath = outPath
        super.init()
    }

    func addEvent(_ name: String, _ detail: String = "") {
        lock.lock()
        events.append(EventRow(name: name, t: hostNow(), detail: detail))
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid else { return }
        let cb = hostNow()
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let bpr = base.assumingMemoryBound(to: UInt8.self)

        var grid = [UInt8](repeating: 0, count: gridW * gridH)
        for gy in 0..<gridH {
            let sy = min(h - 1, max(0, gy * h / gridH + h / (2 * gridH)))
            let row = bpr + sy * stride
            for gx in 0..<gridW {
                let sx = min(w - 1, max(0, gx * w / gridW + w / (2 * gridW)))
                let p = row + sx * 4
                grid[gy * gridW + gx] = UInt8((Int(p[0]) + Int(p[1]) + Int(p[2])) / 3)
            }
        }

        var diff = 0.0
        var maxd = 0.0
        var cells = 0
        lock.lock()
        if let prev = prevGrid {
            var acc = 0
            for i in 0..<grid.count {
                let d = abs(Int(grid[i]) - Int(prev[i]))
                acc += d
                if Double(d) > maxd { maxd = Double(d) }
                if d > 10 { cells += 1 }
            }
            diff = Double(acc) / Double(grid.count) / 255.0
        } else {
            diff = 1.0
            maxd = 255.0
            cells = grid.count
        }
        prevGrid = grid
        let row = FrameRow(idx: frames.count, pts: pts, cb: cb, diff: diff, maxd: maxd, cells: cells)
        frames.append(row)
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write("stream stopped: \(error)\n".data(using: .utf8)!)
        stop(wait: false)
    }

    func stop(wait: Bool) {
        lock.lock()
        if stopped { lock.unlock(); return }
        stopped = true
        let frames = self.frames
        let events = self.events
        lock.unlock()

        var text = ""
        for f in frames {
            text += String(format: "F %d %.6f %.6f %.6f %.0f %d\n", f.idx, f.pts, f.cb, f.diff, f.maxd, f.cells)
        }
        for e in events {
            text += "E \(e.name) " + String(format: "%.6f", e.t) + (e.detail.isEmpty ? "" : " " + e.detail) + "\n"
        }
        try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
        if wait { done.signal() }
    }

    func waitDone(timeout: Double) {
        _ = done.wait(timeout: .now() + timeout)
    }
}

let mouseSource = CGEventSource(stateID: .hidSystemState)
var useGlobal = false

func send(_ e: CGEvent?, pid: pid_t) {
    if useGlobal { e?.post(tap: .cghidEventTap) } else { e?.postToPid(pid) }
}

func postMouse(_ type: CGEventType, _ x: Double, _ y: Double, pid: pid_t, button: CGMouseButton = .left) {
    let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: button)
    send(e, pid: pid)
}

let keyCodes: [String: CGKeyCode] = [
    "left": 123, "right": 124, "down": 125, "up": 126,
    "space": 49, "escape": 53, "return": 36, "tab": 48,
]

func postKey(_ name: String, pid: pid_t) {
    guard let code = keyCodes[name] else { return }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: mouseSource, virtualKey: code, keyDown: down)
        send(e, pid: pid)
    }
}

func listWindows() {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for w in content.windows {
                let app = w.owningApplication?.applicationName ?? "?"
                print("\(w.windowID)\t\(Int(w.frame.width))x\(Int(w.frame.height))\t\(Int(w.frame.minX)),\(Int(w.frame.minY))\t\(app)\t\(w.title ?? "")")
            }
        } catch {
            FileHandle.standardError.write("list failed: \(error)\n".data(using: .utf8)!)
        }
        sem.signal()
    }
    sem.wait()
}

func parseScript(_ path: String) -> [(String, [String])] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var out: [(String, [String])] = []
    for raw in text.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(separator: " ").map(String.init)
        out.append((parts[0], Array(parts.dropFirst())))
    }
    return out
}

func run(pid: pid_t, windowID: UInt32, outPath: String, scriptPath: String, activate: Bool, quitAfter: Double) {
    if activate {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        usleep(400_000)
    }
    let sem = DispatchSemaphore(value: 0)
    var target: SCWindow? = nil
    var screen0: SCDisplay? = nil
    var displayHz = 60
    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            target = content.windows.first(where: { $0.windowID == windowID })
            screen0 = content.displays.first
            if let screen = NSScreen.main { displayHz = screen.maximumFramesPerSecond }
        } catch {
            FileHandle.standardError.write("content failed: \(error)\n".data(using: .utf8)!)
        }
        sem.signal()
    }
    sem.wait()
    guard let window = target else {
        FileHandle.standardError.write("window \(windowID) not found\n".data(using: .utf8)!)
        exit(2)
    }

    let useDisplay = CommandLine.arguments.contains("--display")
    let filter: SCContentFilter
    let cfg = SCStreamConfiguration()
    if useDisplay, let d = screen0 {
        filter = SCContentFilter(display: d, excludingWindows: [])
        cfg.width = Int(d.width) * 2
        cfg.height = Int(d.height) * 2
    } else {
        filter = SCContentFilter(desktopIndependentWindow: window)
        cfg.width = Int(window.frame.width * 2)
        cfg.height = Int(window.frame.height * 2)
    }
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    cfg.queueDepth = 8
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.showsCursor = false
    cfg.capturesAudio = false
    cfg.scalesToFit = false

    let recorder = Recorder(outPath: outPath)
    let stream = SCStream(filter: filter, configuration: cfg, delegate: recorder)
    do {
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames", qos: .userInteractive))
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

    // Warm-up so the first captured frames are not counted as changes.
    usleep(350_000)
    recorder.addEvent("begin")

    let script = parseScript(scriptPath)
    let scriptStart = hostNow()
    for (cmd, args) in script {
        switch cmd {
        case "mark":
            recorder.addEvent("mark", args.first ?? "")
        case "wait":
            let ms = Double(args.first ?? "0") ?? 0
            Thread.sleep(forTimeInterval: ms / 1000.0)
        case "move":
            let x = Double(args[0])!, y = Double(args[1])!
            postMouse(.mouseMoved, x, y, pid: pid)
            recorder.addEvent("move", "\(x) \(y)")
        case "down":
            let x = args.count > 1 ? Double(args[0])! : 0
            let y = args.count > 1 ? Double(args[1])! : 0
            postMouse(args.count > 1 ? .leftMouseDown : .leftMouseDown, x, y, pid: pid)
            recorder.addEvent("down", "\(x) \(y)")
        case "up":
            let x = args.count > 1 ? Double(args[0])! : 0
            let y = args.count > 1 ? Double(args[1])! : 0
            postMouse(.leftMouseUp, x, y, pid: pid)
            recorder.addEvent("up", "\(x) \(y)")
        case "click":
            let x = Double(args[0])!, y = Double(args[1])!
            postMouse(.leftMouseDown, x, y, pid: pid)
            recorder.addEvent("click_down", "\(x) \(y)")
            usleep(40_000)
            postMouse(.leftMouseUp, x, y, pid: pid)
            recorder.addEvent("click_up", "\(x) \(y)")
        case "rclick":
            let x = Double(args[0])!, y = Double(args[1])!
            postMouse(.rightMouseDown, x, y, pid: pid, button: .right)
            recorder.addEvent("rclick_down", "\(x) \(y)")
            usleep(40_000)
            postMouse(.rightMouseUp, x, y, pid: pid, button: .right)
            recorder.addEvent("rclick_up", "\(x) \(y)")
        case "dblclick":
            let x = Double(args[0])!, y = Double(args[1])!
            for i in 0..<2 {
                for down in [true, false] {
                    let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
                    let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
                    e?.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
                    send(e, pid: pid)
                    if down { usleep(30_000) }
                }
                recorder.addEvent("dblclick", "\(x) \(y) #\(i+1)")
                usleep(60_000)
            }
        case "drag":
            let x0 = Double(args[0])!, y0 = Double(args[1])!
            let x1 = Double(args[2])!, y1 = Double(args[3])!
            let steps = Int(args[4])!
            let stepMs = Double(args[5])!
            postMouse(.leftMouseDown, x0, y0, pid: pid)
            recorder.addEvent("drag_down", "\(x0) \(y0)")
            for i in 1...steps {
                let f = Double(i) / Double(steps)
                let x = x0 + (x1 - x0) * f
                let y = y0 + (y1 - y0) * f
                postMouse(.leftMouseDragged, x, y, pid: pid)
                recorder.addEvent("drag_step", "\(x) \(y)")
                Thread.sleep(forTimeInterval: stepMs / 1000.0)
            }
            postMouse(.leftMouseUp, x1, y1, pid: pid)
            recorder.addEvent("drag_up", "\(x1) \(y1)")
        case "key":
            postKey(args[0], pid: pid)
            recorder.addEvent("key", args[0])
        case "type":
            let text = args.joined(separator: " ")
            for ch in text {
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: mouseSource, virtualKey: 0, keyDown: down)
                    var chars = Array(String(ch).utf16)
                    e?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
                    send(e, pid: pid)
                }
                usleep(15_000)
            }
            recorder.addEvent("type", text)
        case "scroll":
            let dy = Double(args[0])!
            let e = CGEvent(scrollWheelEvent2Source: mouseSource, units: .pixel, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0)
            send(e, pid: pid)
            recorder.addEvent("scroll", "\(dy)")
        case "scrollp":
            let dy = Double(args[0])!
            let ph = Int64(args[1])!
            let e = CGEvent(scrollWheelEvent2Source: mouseSource, units: .pixel, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0)
            e?.setIntegerValueField(.scrollWheelEventScrollPhase, value: ph)
            e?.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
            e?.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
            send(e, pid: pid)
            recorder.addEvent("scroll", "\(dy)p\(ph)")
        case "scrolllines":
            let dy = Double(args[0])!
            let e = CGEvent(scrollWheelEvent2Source: mouseSource, units: .line, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0)
            send(e, pid: pid)
            recorder.addEvent("scroll", "\(dy)l")
        default:
            break
        }
    }
    recorder.addEvent("end")
    let elapsed = hostNow() - scriptStart
    if elapsed < quitAfter { usleep(UInt32((quitAfter - elapsed) * 1_000_000)) }
    Task { try? await stream.stopCapture() }
    recorder.stop(wait: true)
    print("wrote \(outPath) display_hz=\(displayHz) window=\(Int(window.frame.width))x\(Int(window.frame.height))")
}

// MARK: - summary

func percentile(_ xs: [Double], _ p: Double) -> Double {
    if xs.isEmpty { return .nan }
    let s = xs.sorted()
    let idx = min(s.count - 1, max(0, Int(round(p * Double(s.count - 1)))))
    return s[idx]
}

func summary(_ path: String) {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("cannot read \(path)")
        return
    }
    var frames: [FrameRow] = []
    var events: [EventRow] = []
    for line in text.split(separator: "\n") {
        let p = line.split(separator: " ").map(String.init)
        if p.isEmpty { continue }
        if p[0] == "F", p.count >= 5 {
            frames.append(FrameRow(idx: Int(p[1])!, pts: Double(p[2])!, cb: Double(p[3])!, diff: Double(p[4])!, maxd: p.count > 5 ? Double(p[5])! : 0, cells: p.count > 6 ? Int(p[6])! : 0))
        } else if p[0] == "E", p.count >= 3 {
            events.append(EventRow(name: p[1], t: Double(p[2])!, detail: p.count > 3 ? p[3...].joined(separator: " ") : ""))
        }
    }
    frames.sort { $0.idx < $1.idx }

    let threshold = 0.0015
    let changed = frames.filter { $0.cells >= 1 && $0.maxd >= 10 }
    let begin = events.first(where: { $0.name == "begin" })?.t ?? frames.first?.pts ?? 0
    let end = events.first(where: { $0.name == "end" })?.t ?? frames.last?.pts ?? 0

    var lines: [String] = []
    lines.append(String(format: "frames=%d changed=%d span=%.3fs changed_fps=%.1f", frames.count, changed.count, end - begin, Double(changed.count) / max(0.001, end - begin)))

    // Latencies: each input event -> first changed frame at or after it.
    for e in events where ["move", "down", "click_down", "rclick_down", "key", "scroll", "drag_down", "drag_step", "drag_up", "up"].contains(e.name) {
        var best: Double? = nil
        var bestCb: Double? = nil
        for f in changed where f.pts >= e.t - 0.002 {
            best = f.pts - e.t
            bestCb = f.cb - e.t
            break
        }
        if let b = best {
            lines.append(String(format: "lat %@ %.1f ms (cb %.1f ms)", e.name, b * 1000, (bestCb ?? 0) * 1000))
        } else {
            lines.append("lat \(e.name) none")
        }
    }

    // Frame intervals inside each drag (drag_down .. drag_up), on changed frames only,
    // and on all frames for comparison.
    let downs = events.filter { $0.name == "drag_down" }
    let ups = events.filter { $0.name == "drag_up" }
    for (i, d) in downs.enumerated() {
        guard i < ups.count else { break }
        let u = ups[i]
        let seg = changed.filter { $0.pts > d.t && $0.pts < u.t + 0.05 }
        let iv = zip(seg.dropFirst(), seg).map { ($0.pts - $1.pts) * 1000 }
        let all = frames.filter { $0.pts > d.t && $0.pts < u.t + 0.05 }
        let allIv = zip(all.dropFirst(), all).map { ($0.pts - $1.pts) * 1000 }
        if !iv.isEmpty {
            let gt167 = iv.filter { $0 > 16.7 }.count
            let gt333 = iv.filter { $0 > 33.3 }.count
            lines.append(String(format: "drag%d changed=%d fps=%.1f med=%.2fms p95=%.2fms max=%.2fms >16.7=%d >33.3=%d (all frames med=%.2fms)", i, seg.count, 1000.0 / max(0.001, percentile(iv, 0.5)), percentile(iv, 0.5), percentile(iv, 0.95), iv.max() ?? 0, gt167, gt333, percentile(allIv, 0.5)))
        } else {
            lines.append("drag\(i) no changed frames")
        }
    }

    // Static-segment rate: frames delivered while nothing changed (SCK may still push duplicates).
    let frameIv = zip(frames.dropFirst(), frames).map { ($0.pts - $1.pts) * 1000 }
    if !frameIv.isEmpty {
        let over = frameIv.filter { $0 > 16.7 }.count
        lines.append(String(format: "all_frames=%d med_interval=%.2fms p95=%.2fms >16.7=%d", frames.count, percentile(frameIv, 0.5), percentile(frameIv, 0.95), over))
    }
    print(lines.joined(separator: "\n"))
}

// MARK: - main

let args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch args.first {
case "list":
    listWindows()
case "run":
    guard let pidS = opt("--pid"), let pid = pid_t(pidS), let wid = opt("--window-id"), let w = UInt32(wid),
          let out = opt("--out"), let script = opt("--script") else {
        print("usage: frameprobe run --pid <> --window-id <> --out <> --script <> [--activate] [--global] [--tail 0.5]")
        exit(2)
    }
    useGlobal = args.contains("--global")
    run(pid: pid, windowID: w, outPath: out, scriptPath: script, activate: args.contains("--activate"), quitAfter: Double(opt("--tail") ?? "0.6") ?? 0.6)
case "summary":
    guard let path = args.dropFirst().first else { exit(2) }
    summary(path)
default:
    print("usage: frameprobe list | run ... | summary <file>")
}
