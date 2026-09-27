// yiyin-logo-convert — the ONE-TIME build tool that turns the yiyin brand
// logos (13 brands × light/dark = 26 SVGs, read-only spec source
// https://github.com/kamasylvia/yiyin web/public/logo/) into PDF
// vector assets bundled with LightamerIOP (Resources/Logos/). The runtime
// has ZERO web/SVG dependencies (RESEARCH §8.9 — no librsvg/WebView; the
// PDFs render through CG PDF).
//
// The converter parses the BOUNDED SVG subset the yiyin logo files use
// (verified by scanning all 26 files, 2026-09-25):
//   path data commands: m/l/c/s/h/v/z + the uppercase twins + implicit
//                       coordinate-pair repetition (SVG spec)
//   group transforms:   translate(tx[,ty]) scale(sx[,sy]) matrix(a b c d e f)
//   fills:              #rgb / #rrggbb on <g> (default #000, inherited)
//   fill-rule:          nonzero default; evenodd via fill-rule="evenodd"
// Everything else (gradients, masks, images, text, arcs) does not occur —
// the tool FAILS LOUDLY on unknown elements/commands rather than emitting
// a silently-wrong PDF.
//
// Usage: swift Scripts/yiyin-logo-convert/main.swift <src-dir> <dst-dir>

import CoreGraphics
import Foundation

// MARK: - errors

enum ConversionError: Error, CustomStringConvertible {
    case missingDimensions(String)
    case pathMissingD(String)
    case unsupportedElement(String)
    case unsupportedCommand(Character)
    case unsupportedTransform(String)

    var description: String {
        switch self {
        case .missingDimensions(let f): return "\(f): missing width/height"
        case .pathMissingD(let f): return "\(f): path without d"
        case .unsupportedElement(let e): return "unsupported element <\(e)>"
        case .unsupportedCommand(let c): return "unsupported path command '\(c)'"
        case .unsupportedTransform(let t): return "unsupported transform '\(t)'"
        }
    }
}

// MARK: - number scanning

struct Scanner {
    let s: [UInt8]
    var i = 0
    init(_ string: String) { s = Array(string.utf8) }

    mutating func skipSeparators() {
        while i < s.count {
            let c = s[i]
            if c == UInt8(ascii: " ") || c == UInt8(ascii: ",") || c == 10 || c == 13 || c == 9 {
                i += 1
            } else { break }
        }
    }

    mutating func scanNumber() -> Double? {
        skipSeparators()
        let start = i
        if i < s.count, s[i] == UInt8(ascii: "-") || s[i] == UInt8(ascii: "+") { i += 1 }
        var seenDot = false
        var seenDigit = false
        while i < s.count {
            let c = s[i]
            if c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") { seenDigit = true; i += 1 }
            else if c == UInt8(ascii: ".") && !seenDot { seenDot = true; i += 1 }
            else if (c == UInt8(ascii: "e") || c == UInt8(ascii: "E")), seenDigit {
                var j = i + 1
                if j < s.count, s[j] == UInt8(ascii: "-") || s[j] == UInt8(ascii: "+") { j += 1 }
                if j < s.count, s[j] >= UInt8(ascii: "0"), s[j] <= UInt8(ascii: "9") { i = j } else { break }
            } else { break }
        }
        guard seenDigit else { i = start; return nil }
        return Double(String(decoding: s[start..<i], as: UTF8.self))
    }

    mutating func scanCommand() -> UInt8? {
        skipSeparators()
        guard i < s.count else { return nil }
        let c = s[i]
        let isLetter =
            (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
            || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
        guard isLetter else { return nil }
        i += 1
        return c
    }

    mutating func peekIsNumber() -> Bool {
        skipSeparators()
        guard i < s.count else { return false }
        let c = s[i]
        return (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) || c == UInt8(ascii: "-")
            || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
    }
}

// MARK: - path data (SVG spec subset → absolute points)

/// One subpath: moveto point + segments (all absolute user coords).
struct Subpath {
    var start: (Double, Double)
    /// .point(x,y) | .cubic(c1,c2,p) | .close
    enum Segment {
        case point(Double, Double)
        case cubic((Double, Double), (Double, Double), (Double, Double))
        case close
    }
    var segments: [Segment]
}

func parsePathData(_ d: String) throws -> [Subpath] {
    var sc = Scanner(d)
    var current = (0.0, 0.0)
    var startPoint = current
    var previousC2: (Double, Double)? = nil
    var subpaths: [Subpath] = []
    var segments: [Subpath.Segment] = []
    var command: UInt8 = 0

    func absPoint(_ x: Double?, _ y: Double?, relative: Bool) -> (Double, Double)? {
        guard let x, let y else { return nil }
        return relative ? (current.0 + x, current.1 + y) : (x, y)
    }
    func flush() {
        if !segments.isEmpty {
            subpaths.append(Subpath(start: startPoint, segments: segments))
            segments = []
        }
    }

    // The SVG path loop: a command letter (re)assigns the command; extra
    // coordinate pairs repeat it (implicit repetition); the loop ends at
    // end-of-string — NOT at the next letter (that was the degenerate-
    // path bug: every glyph collapsed to its moveto).
    while true {
        sc.skipSeparators()
        guard sc.i < sc.s.count else { break }
        let position = sc.i
        if let c = sc.scanCommand() { command = c }
        let relative = command >= UInt8(ascii: "a")
        let base = relative ? command - 32 : command
        switch base {
        case UInt8(ascii: "M"):
            guard let p = absPoint(sc.scanNumber(), sc.scanNumber(), relative: relative)
            else { throw ConversionError.pathMissingD("truncated moveto") }
            flush()
            current = p
            startPoint = p
            segments = [.point(p.0, p.1)]
            // implicit lineto after the first moveto pair
            command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
        case UInt8(ascii: "L"):
            guard let p = absPoint(sc.scanNumber(), sc.scanNumber(), relative: relative)
            else { throw ConversionError.pathMissingD("truncated lineto") }
            current = p
            segments.append(.point(p.0, p.1))
        case UInt8(ascii: "C"):
            guard
                let c1 = absPoint(sc.scanNumber(), sc.scanNumber(), relative: relative),
                let c2 = absPoint(sc.scanNumber(), sc.scanNumber(), relative: relative),
                let p = absPoint(sc.scanNumber(), sc.scanNumber(), relative: relative)
            else { throw ConversionError.pathMissingD("truncated curveto") }
            current = p
            previousC2 = c2
            segments.append(.cubic(c1, c2, p))
        case UInt8(ascii: "S"):
            guard
                let c2 = absPoint(sc.scanNumber(), sc.scanNumber(), relative: relative),
                let p = absPoint(sc.scanNumber(), sc.scanNumber(), relative: relative)
            else { throw ConversionError.pathMissingD("truncated smooth curveto") }
            // the first control = the reflection of the previous c2
            let c1 = previousC2.map { (2 * current.0 - $0.0, 2 * current.1 - $0.1) } ?? current
            current = p
            previousC2 = c2
            segments.append(.cubic(c1, c2, p))
        case UInt8(ascii: "H"):
            guard let x = sc.scanNumber() else { throw ConversionError.pathMissingD("truncated h") }
            current.0 = relative ? current.0 + x : x
            previousC2 = nil
            segments.append(.point(current.0, current.1))
        case UInt8(ascii: "V"):
            guard let y = sc.scanNumber() else { throw ConversionError.pathMissingD("truncated v") }
            current.1 = relative ? current.1 + y : y
            previousC2 = nil
            segments.append(.point(current.0, current.1))
        case UInt8(ascii: "Z"):
            current = startPoint
            previousC2 = nil
            segments.append(.close)
        default:
            throw ConversionError.unsupportedCommand(Character(UnicodeScalar(command)))
        }
        if sc.i == position { break } // no progress → unknown byte, stop
    }
    flush()
    return subpaths
}

// MARK: - transforms

func applyTransform(_ t: [Double], _ p: (Double, Double)) -> (Double, Double) {
    guard t.count == 6 else { return p }
    let (a, b, c, d, e, f) = (t[0], t[1], t[2], t[3], t[4], t[5])
    return (a * p.0 + c * p.1 + e, b * p.0 + d * p.1 + f)
}

func parseTransformList(_ s: String) throws -> [Double] {
    var acc: [Double] = [1, 0, 0, 1, 0, 0]
    var rest = Substring(s)
    while let open = rest.firstIndex(of: "(") {
        // the function name = the identifier run immediately before "("
        var nameEnd = rest.index(before: open)
        while nameEnd > rest.startIndex,
            rest[rest.index(before: nameEnd)].isLetter || rest[rest.index(before: nameEnd)] == " "
        {
            nameEnd = rest.index(before: nameEnd)
            if nameEnd == rest.startIndex { break }
        }
        let name = rest[nameEnd..<open].trimmingCharacters(in: .whitespaces)
        guard let close = rest.firstIndex(of: ")") else { break }
        let args = rest[rest.index(after: open)..<close]
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " })
            .compactMap { Double($0) }
        let m: [Double]
        switch name {
        case "translate":
            m = [1, 0, 0, 1, args[0], args.count > 1 ? args[1] : 0]
        case "scale":
            let sy = args.count > 1 ? args[1] : args[0]
            m = [args[0], 0, 0, sy, 0, 0]
        case "matrix":
            guard args.count == 6 else { throw ConversionError.unsupportedTransform(s) }
            m = args
        default:
            throw ConversionError.unsupportedTransform(name)
        }
        // acc = acc ∘ m (m applies first, then acc)
        acc = [
            acc[0] * m[0] + acc[2] * m[1],
            acc[1] * m[0] + acc[3] * m[1],
            acc[0] * m[2] + acc[2] * m[3],
            acc[1] * m[2] + acc[3] * m[3],
            acc[0] * m[4] + acc[2] * m[5] + acc[4],
            acc[1] * m[4] + acc[3] * m[5] + acc[5],
        ]
        rest = rest[rest.index(after: close)...]
    }
    return acc
}

// MARK: - colors

func parseHexColor(_ s: String) -> (Double, Double, Double) {
    let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
    func hexDigit(_ c: Character) -> Double? { c.hexDigitValue.map(Double.init) }
    func one(_ a: Character, _ b: Character) -> Double {
        guard let hi = hexDigit(a), let lo = hexDigit(b) else { return 0 }
        return (hi * 16 + lo) / 255
    }
    let chars = Array(hex.lowercased())
    if chars.count == 3 {
        func half(_ c: Character) -> Double { (hexDigit(c) ?? 0) / 15 }
        return (half(chars[0]), half(chars[1]), half(chars[2]))
    }
    guard chars.count == 6 else { return (0, 0, 0) }
    return (one(chars[0], chars[1]), one(chars[2], chars[3]), one(chars[4], chars[5]))
}

// MARK: - the SVG document walk

struct Draw {
    var subpaths: [Subpath] // points ALREADY transformed to SVG user space
    var color: (Double, Double, Double)
    var evenOdd: Bool
}

func attr(_ name: String, in body: String) -> String? {
    guard let range = body.range(of: "\(name)=") else { return nil }
    var tail = body[range.upperBound...]
    guard let quote = tail.first else { return nil }
    if quote == "\"" || quote == "'" {
        tail = tail.dropFirst()
        guard let end = tail.firstIndex(of: quote) else { return nil }
        return String(tail[..<end])
    }
    // unquoted value
    let end = tail.firstIndex(where: { $0 == " " || $0 == "/" || $0 == ">" }) ?? tail.endIndex
    return String(tail[..<end])
}

func convert(svgURL: URL, pdfURL: URL) throws {
    let text = try String(contentsOf: svgURL, encoding: .utf8)

    // The ROOT svg tag only (scan from `<svg` to its closing bracket;
    // some files carry an XML declaration + DOCTYPE before it — fujifilm —
    // and pt units).
    let header: String
    if let svgStart = text.range(of: "<svg") {
        let tail = text[svgStart.lowerBound...]
        let end = tail.firstIndex(of: ">") ?? tail.endIndex
        header = String(tail[..<end])
    } else {
        header = text
    }
    func unitless(_ name: String) -> Double? {
        guard let raw = attr(name, in: header) else { return nil }
        var s = Substring(raw)
        if s.hasSuffix("pt") || s.hasSuffix("px") { s = s.dropLast(2) }
        return Double(s)
    }
    guard let w = unitless("width"), let h = unitless("height")
    else { throw ConversionError.missingDimensions(svgURL.lastPathComponent) }

    struct GroupState {
        var color: (Double, Double, Double) = (0, 0, 0)
        var transform: [Double] = []
        var evenOdd = false
    }
    var stack = [GroupState()]
    var draws: [Draw] = []

    var rest = Substring(text)
    while let lt = rest.firstIndex(of: "<") {
        guard let tagEnd = rest[lt...].firstIndex(of: ">") else { break }
        let rawTag = String(rest[rest.index(after: lt)..<tagEnd])
        let afterTag = rest.index(after: tagEnd)
        rest = rest[afterTag...]
        if rawTag.hasPrefix("?") || rawTag.hasPrefix("!") { continue }
        let selfClosing = rawTag.hasSuffix("/")
        let body = selfClosing ? String(rawTag.dropLast()) : rawTag
        if body.hasPrefix("/") { // closing tag
            if !stack.isEmpty { stack.removeLast() }
            continue
        }
        let name = body.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
        switch name {
        case "svg", "title", "metadata":
            continue
        case "g":
            let inherited = stack.last!
            var state = inherited
            if let f = attr("fill", in: body) {
                if f.hasPrefix("#") { state.color = parseHexColor(f) }
                // 'none' inherits nothing meaningful for the logos — fail
                // loudly rather than emitting a black blob.
                else if f == "none" { throw ConversionError.unsupportedElement("g fill=none") }
            }
            if let t = attr("transform", in: body) {
                // COMPOSE onto the inherited transform (the yiyin files
                // nest transforms).
                let local = try parseTransformList(t)
                var composed: [Double]
                let p = inherited.transform
                if p.count == 6 {
                    composed = [
                        p[0] * local[0] + p[2] * local[1],
                        p[1] * local[0] + p[3] * local[1],
                        p[0] * local[2] + p[2] * local[3],
                        p[1] * local[2] + p[3] * local[3],
                        p[0] * local[4] + p[2] * local[5] + p[4],
                        p[1] * local[4] + p[3] * local[5] + p[5],
                    ]
                } else {
                    composed = local
                }
                state.transform = composed
            }
            if attr("fill-rule", in: body) == "evenodd" { state.evenOdd = true }
            stack.append(state)
            if selfClosing { stack.removeLast() }
        case "path":
            guard let d = attr("d", in: body) else {
                throw ConversionError.pathMissingD(svgURL.lastPathComponent)
            }
            let state = stack.last!
            let subpaths = try parsePathData(d)
            let transformed = subpaths.map { sp -> Subpath in
                let start = applyTransform(state.transform, sp.start)
                let segments = sp.segments.map { seg -> Subpath.Segment in
                    switch seg {
                    case .point(let x, let y):
                        return .point(applyTransform(state.transform, (x, y)).0,
                            applyTransform(state.transform, (x, y)).1)
                    case .cubic(let c1, let c2, let p):
                        return .cubic(
                            applyTransform(state.transform, c1),
                            applyTransform(state.transform, c2),
                            applyTransform(state.transform, p))
                    case .close:
                        return .close
                    }
                }
                return Subpath(start: start, segments: segments)
            }
            draws.append(Draw(subpaths: transformed, color: state.color, evenOdd: state.evenOdd))
        default:
            throw ConversionError.unsupportedElement(name)
        }
    }

    // ── emit the PDF (CoreGraphics; y-down SVG → y-up PDF via a flip) ──
    var mediaBox = CGRect(x: 0, y: 0, width: w, height: h)
    guard let consumer = CGDataConsumer(url: pdfURL as CFURL),
        // The Swift overlay's third parameter is UNLABELED (probe-verified).
        let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        throw ConversionError.missingDimensions("pdf context: \(pdfURL.lastPathComponent)")
    }
    ctx.beginPDFPage(nil)
    // SVG y-down → PDF y-up.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    for draw in draws {
        ctx.saveGState()
        let color = draw.color
        ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        let path = CGMutablePath()
        for sp in draw.subpaths {
            path.move(to: CGPoint(x: sp.start.0, y: sp.start.1))
            for seg in sp.segments {
                switch seg {
                case .point(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
                case .cubic(let c1, let c2, let p):
                    path.addCurve(
                        to: CGPoint(x: p.0, y: p.1),
                        control1: CGPoint(x: c1.0, y: c1.1),
                        control2: CGPoint(x: c2.0, y: c2.1))
                case .close: path.closeSubpath()
                }
            }
        }
        ctx.addPath(path)
        ctx.drawPath(using: draw.evenOdd ? .eoFill : .fill)
        ctx.restoreGState()
    }
    ctx.endPDFPage()
    ctx.closePDF()
}

// MARK: - main

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: swift main.swift <src-dir> <dst-dir>\n".data(using: .utf8)!)
    exit(2)
}
let srcDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let dstDir = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

let svgs = try FileManager.default.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !svgs.isEmpty else {
    FileHandle.standardError.write("no svg files in \(srcDir.path)\n".data(using: .utf8)!)
    exit(1)
}
var converted = 0
for svg in svgs {
    let dst = dstDir.appendingPathComponent(svg.deletingPathExtension().lastPathComponent + ".pdf")
    try convert(svgURL: svg, pdfURL: dst)
    converted += 1
    print("✓ \(svg.lastPathComponent) → \(dst.lastPathComponent)")
}
print("converted \(converted) SVGs → \(dstDir.path)")
