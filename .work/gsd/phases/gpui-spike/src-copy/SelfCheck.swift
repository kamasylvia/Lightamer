// SelfCheck: known-motion window used to validate FrameProbe.
// - animates a bar on the display link (ground truth frame cadence, printed as stats)
// - on left mouse down, flashes the window and prints the timestamp at which the
//   flash frame was drawn, so the probe's measured input->change latency can be
//   compared against the app's own event->draw time.
// - prints its CG window id and top-left-origin bounds for scripted input.

import AppKit
import QuartzCore

final class CheckView: NSView {
    var phase: Double = 0
    var flashUntil: Double = 0
    var lastDraw: Double = 0
    var intervals: [Double] = []
    var isFlashing = false

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let t = CACurrentMediaTime()
        flashUntil = t + 0.5
        print(String(format: "click_recv %.6f", t))
        fflush(stdout)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let now = CACurrentMediaTime()
        if lastDraw > 0 { intervals.append((now - lastDraw) * 1000) }
        lastDraw = now
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 1).cgColor)
        ctx.fill(bounds)
        let flashing = now < flashUntil
        if flashing {
            ctx.setFillColor(NSColor.magenta.cgColor)
            ctx.fill(bounds)
            if !isFlashing {
                isFlashing = true
                print(String(format: "flash_wall %.6f", now))
                fflush(stdout)
            }
        } else {
            isFlashing = false
            let still = ProcessInfo.processInfo.environment["STATIC"] == "1";
            let phase: Double = still ? 0.5 : (sin(now * 6) + 1) / 2
            let x = 20 + (bounds.width - 80) * CGFloat(phase)
            ctx.setFillColor(NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.4, alpha: 1).cgColor)
            ctx.fill(CGRect(x: x, y: 120, width: 60, height: 160))
            ctx.setFillColor(NSColor(calibratedWhite: 0.9, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 20, y: 20, width: 200, height: 3))
        }
        if intervals.count >= 240 {
            let s = intervals.sorted()
            print(String(format: "inapp_frames=%d med=%.2fms p95=%.2fms", s.count, s[s.count / 2], s[Int(Double(s.count) * 0.95)]))
            fflush(stdout)
            intervals.removeAll()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: CheckView!
    var link: CADisplayLink?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 160, y: 240, width: 720, height: 420)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SelfCheck"
        view = CheckView(frame: NSRect(origin: .zero, size: rect.size))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        for info in CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [] {
            if (info[kCGWindowNumber as String] as? Int) == window.windowNumber {
                let b = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
                print("window_id=\(window.windowNumber) bounds_x=\(b["X"] ?? "?") bounds_y=\(b["Y"] ?? "?") w=\(b["Width"] ?? "?") h=\(b["Height"] ?? "?")")
                fflush(stdout)
            }
        }

        link = view.displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    @objc func tick() {
        NSEvent.mouseLocation
        view.needsDisplay = true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
