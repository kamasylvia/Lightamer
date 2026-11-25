import Foundation
import Vision
for p in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: p)
    let req = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(url: url, options: [:])
    do {
        try handler.perform([req])
        let n = req.results?.count ?? 0
        print("\(url.lastPathComponent): \(n) faces")
        if let rs = req.results {
            for r in rs.prefix(3) { print("   \(r.boundingBox)") }
        }
    } catch { print("\(url.lastPathComponent): ERROR \(error)") }
}
