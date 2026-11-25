import AppKit
let tMain = CFAbsoluteTimeGetCurrent()
print("T_MAIN \(tMain)")
fflush(stdout)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 800, height: 600),
                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
w.title = "appkit-control"
w.backgroundColor = .red
w.makeKeyAndOrderFront(nil)
print("T_SHOW \(CFAbsoluteTimeGetCurrent())")
fflush(stdout)
app.activate(ignoringOtherApps: true)
print("T_ACTIVE \(CFAbsoluteTimeGetCurrent())")
fflush(stdout)
app.run()
