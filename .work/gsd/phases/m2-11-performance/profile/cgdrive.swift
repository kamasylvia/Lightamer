import CoreGraphics
import Foundation

// cgdrive — minimal CGEvent driver for the M2-11-04 T1 GUI memory profile
// (double-click + scroll pan; buttons/sliders go through System Events AX).
// usage:
//   cgdrive click <x> <y>
//   cgdrive dclick <x> <y>
//   cgdrive scroll <x> <y> <dy_lines> [steps]

func move(to p: CGPoint) {
    let m = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: p, mouseButton: .left)!
    m.post(tap: .cghidEventTap)
    usleep(80_000)
}

func click(at p: CGPoint, count: Int) {
    move(to: p)
    for i in 1...count {
        usleep(70_000)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: p, mouseButton: .left)!
        down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
        down.post(tap: .cghidEventTap)
        usleep(40_000)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: p, mouseButton: .left)!
        up.setIntegerValueField(.mouseEventClickState, value: Int64(i))
        up.post(tap: .cghidEventTap)
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: cgdrive <click|dclick|scroll> ...\n".utf8))
    exit(2)
}
switch args[1] {
case "click", "dclick":
    guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else { exit(2) }
    click(at: CGPoint(x: x, y: y), count: args[1] == "dclick" ? 2 : 1)
case "scroll":
    guard args.count >= 5, let x = Double(args[2]), let y = Double(args[3]),
        let dy = Double(args[4]) else { exit(2) }
    let steps = args.count > 5 ? (Int(args[5]) ?? 10) : 10
    move(to: CGPoint(x: x, y: y))
    for _ in 0..<steps {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                        wheel1: Int32(dy), wheel2: 0, wheel3: 0)
        e?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
case "drag":
    // drag <x1> <y1> <x2> <y2> — press, 12-step move, release
    guard args.count >= 6, let x1 = Double(args[2]), let y1 = Double(args[3]),
        let x2 = Double(args[4]), let y2 = Double(args[5]) else { exit(2) }
    let p1 = CGPoint(x: x1, y: y1), p2 = CGPoint(x: x2, y: y2)
    move(to: p1)
    usleep(60_000)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: p1, mouseButton: .left)!
    down.post(tap: .cghidEventTap)
    usleep(80_000)
    for i in 1...12 {
        let t = Double(i) / 12.0
        let p = CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)
        let mv = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                         mouseCursorPosition: p, mouseButton: .left)!
        mv.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    usleep(80_000)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                     mouseCursorPosition: p2, mouseButton: .left)!
    up.post(tap: .cghidEventTap)
default:
    exit(2)
}
