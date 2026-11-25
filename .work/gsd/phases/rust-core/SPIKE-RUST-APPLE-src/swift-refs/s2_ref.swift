// S2 Swift reference — same image, same two requests, canonical dump.
import Foundation
import Vision

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : (NSHomeDirectory() + "/Library/Application Support/Lightamer/TestRAW/ColorChecker.ARW")
print("image: \(path)")
let url = URL(fileURLWithPath: path)

func fmt(_ r: CGRect) -> String {
    String(format: "%.6f,%.6f,%.6f,%.6f", Double(r.origin.x), Double(r.origin.y), Double(r.size.width), Double(r.size.height))
}

let faceReq = VNDetectFaceRectanglesRequest()
let rectReq = VNDetectRectanglesRequest()
let handler = VNImageRequestHandler(url: url, options: [:])
try handler.perform([faceReq, rectReq])

var faces = (faceReq.results ?? []).map { fmt($0.boundingBox) }.sorted()
var rects = (rectReq.results ?? []).map { fmt($0.boundingBox) }.sorted()
print("faces \(faces.count), rects \(rects.count)")

var out = "faces \(faces.count)\n"
faces.forEach { out += "face \($0)\n" }
out += "rects \(rects.count)\n"
rects.forEach { out += "rect \($0)\n" }
try out.write(toFile: "out/s2-swift.txt", atomically: true, encoding: .utf8)
print("wrote out/s2-swift.txt")
