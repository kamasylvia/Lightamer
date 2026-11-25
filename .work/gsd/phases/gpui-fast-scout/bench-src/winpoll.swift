// winpoll: spawn a child, activate it, poll CGWindowListCopyWindowInfo.
// Reports the first window of any size, and the first window with a real size.
import AppKit
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let sep = args.firstIndex(of: "--"), sep + 1 < args.count else {
    print("usage: winpoll -- <cmd> [args...]")
    exit(2)
}
let cmd = Array(args[(sep + 1)...])
let activate = !args.contains("--no-activate")
func numOpt(_ n: String, _ d: Double) -> Double {
    if let i = args.firstIndex(of: n), i + 1 < args.count, let v = Double(args[i + 1]) { return v }
    return d
}
let minW = numOpt("--min-w", 800), minH = numOpt("--min-h", 300)
let t0 = CFAbsoluteTimeGetCurrent()
let proc = Process()
proc.executableURL = URL(fileURLWithPath: cmd[0])
proc.arguments = Array(cmd.dropFirst())
proc.standardOutput = FileHandle.standardOutput
proc.standardError = FileHandle.nullDevice
try! proc.run()
let pid = proc.processIdentifier
var tAny: Double? = nil
var tReal: Double? = nil
var bounds = ""
var activated = false
while CFAbsoluteTimeGetCurrent() - t0 < 15 {
    if activate, !activated, let app = NSRunningApplication(processIdentifier: pid) {
        activated = app.activate(options: [])
    }
    if let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
        for w in list {
            if let owner = w[kCGWindowOwnerPID as String] as? pid_t, owner == pid {
                let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let wpx = (b["Width"] as? Double) ?? 0
                if tAny == nil { tAny = CFAbsoluteTimeGetCurrent() }
                let hpx = (b["Height"] as? Double) ?? 0
                if wpx >= minW, hpx >= minH, tReal == nil {
                    bounds = "\(b["X"] ?? "?"),\(b["Y"] ?? "?") \(b["Width"] ?? "?")x\(b["Height"] ?? "?")"
                    tReal = CFAbsoluteTimeGetCurrent()
                }
            }
        }
    }
    if tReal != nil { break }
    usleep(1_500)
}
let a = tAny.map { String(format: "%.1f", ($0 - t0) * 1000) } ?? "none"
let r = tReal.map { String(format: "%.1f", ($0 - t0) * 1000) } ?? "none"
print("FIRST_ANY \(a) ms  FIRST_REAL \(r) ms bounds=\(bounds) activated=\(activated)")
Thread.sleep(forTimeInterval: 0.5)
proc.terminate()
