import Foundation
import LightamerCore

// Plan 02 smoke harness — drives RAWDecoder.decode through the public
// surface of the freshly built LightamerCore.framework.
@main struct Smoke {
    static func main() async {
        let decoder = RAWDecoder()
        let base = URL(fileURLWithPath: CommandLine.arguments[1])

        // ── raster path (RAW-04) ──
        for name in ["sample-gradient.jpg", "sample-gradient.heic", "sample-gradient.tiff"] {
            do {
                let d = try await decoder.decode(base.appendingPathComponent(name))
                print("OK \(name): extent=\(d.ciImage.extent) v=\(d.decoderVersionUsed)"
                    + " black=\(d.rawTech.blackLevel) white=\(d.rawTech.whiteLevel)"
                    + " matte=\(d.segmentationSkyMatte == nil ? "nil" : "present")"
                    + " w=\(d.capture.width ?? -1) h=\(d.capture.height ?? -1) dpi=\(d.capture.dpi ?? -1)")
            } catch {
                print("ERR \(name): \(error)")
            }
        }

        // ── corrupt RAW → typed AppError (D-25). NOT a fake sample — a
        //    deliberate garbage file that exists only for this run. ──
        let corrupt = base.appendingPathComponent("corrupt.cr3")
        try? Data(repeating: 0xDE, count: 512).write(to: corrupt)
        do {
            let d = try await decoder.decode(corrupt)
            print("FAIL corrupt.cr3 decoded?! extent=\(d.ciImage.extent)")
        } catch let e as AppError {
            print("OK corrupt.cr3 -> AppError.\(e)")
        } catch {
            print("FAIL corrupt.cr3 -> untyped \(type(of: error)): \(error)")
        }
        try? FileManager.default.removeItem(at: corrupt)

        // ── cancellation (D-34) ──
        let task = Task {
            try await decoder.decode(base.appendingPathComponent("sample-gradient.tiff"))
        }
        task.cancel()
        do {
            _ = try await task.value
            print("FAIL cancel: decode completed")
        } catch {
            print("OK cancel -> \(type(of: error)): \(error)")
        }
    }
}
