import AppKit
// Orchestrator's own control: splits the slow span into its three steps. No activate, exits by itself.
let t0 = CFAbsoluteTimeGetCurrent()
let app = NSApplication.shared
let t1 = CFAbsoluteTimeGetCurrent()
app.setActivationPolicy(.regular)
let t2 = CFAbsoluteTimeGetCurrent()
let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
let t3 = CFAbsoluteTimeGetCurrent()
w.title = "lightamer-launch-floor-check"
w.backgroundColor = .red
w.orderFrontRegardless()
let t4 = CFAbsoluteTimeGetCurrent()
print(String(format: "STEPS app=%.0f policy=%.0f nswindow=%.0f orderfront=%.0f ms", (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000, (t4 - t3) * 1000))
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
app.run()
