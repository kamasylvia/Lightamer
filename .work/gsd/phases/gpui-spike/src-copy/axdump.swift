// axdump: dump the accessibility tree of an app or a window, with frames.
// usage: axdump <pid> [window_index] [max_depth]

import ApplicationServices
import AppKit

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef? = nil
    let e = AXUIElementCopyAttributeValue(el, name as CFString, &v)
    return e == .success ? v : nil
}

func s(_ el: AXUIElement, _ name: String) -> String {
    if let v = attr(el, name) { return "\(v)" }
    return ""
}

func frame(_ el: AXUIElement) -> String {
    var pos = CGPoint.zero, size = CGSize.zero
    if let p = attr(el, kAXPositionAttribute) { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
    if let z = attr(el, kAXSizeAttribute) { AXValueGetValue(z as! AXValue, .cgSize, &size) }
    return String(format: "%.0f,%.0f %.0fx%.0f", pos.x, pos.y, size.width, size.height)
}

func dump(_ el: AXUIElement, _ depth: Int, _ maxDepth: Int) {
    let role = s(el, kAXRoleAttribute)
    let sub = s(el, kAXSubroleAttribute)
    let title = s(el, kAXTitleAttribute)
    let desc = s(el, kAXDescriptionAttribute)
    let value = s(el, kAXValueAttribute)
    var line = String(repeating: "  ", count: depth) + role
    if !sub.isEmpty { line += "/\(sub)" }
    if !title.isEmpty { line += " title=\"\(title)\"" }
    if !desc.isEmpty { line += " desc=\"\(desc)\"" }
    if !value.isEmpty { line = line.replacingOccurrences(of: "\n", with: " ") + " value=\"\(value.prefix(40))\"" }
    line += " [\(frame(el))]"
    print(line)
    guard depth < maxDepth else { return }
    if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for k in kids { dump(k, depth + 1, maxDepth) }
    }
}

let args = CommandLine.arguments
guard args.count > 1, let pid = pid_t(args[1]) else {
    print("usage: axdump <pid> [window_index] [max_depth]")
    exit(2)
}
let app = AXUIElementCreateApplication(pid)
let maxDepth = args.count > 3 ? Int(args[3]) ?? 6 : 6
if args.count > 2, let idx = Int(args[2]) {
    if let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement], idx < wins.count {
        dump(wins[idx], 0, maxDepth)
    }
} else {
    dump(app, 0, maxDepth)
}
