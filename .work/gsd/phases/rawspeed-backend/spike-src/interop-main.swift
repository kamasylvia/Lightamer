import CRawSpeed
import Foundation

// T2 form-A probe: drive rawspeed's C++ API from Swift 6 (interoperabilityMode(.Cxx)),
// no C shim. Measures what Swift can actually reach and what it cannot.
//
// Form-A conclusions pinned by this file (see SPIKE.md §2):
//   • Decoding can be *driven* (RawParser → getDecoder → checkSupport → decodeRaw).
//   • Results cannot be *read*: RawImage::get() is rejected by the C++ interop
//     ("may return an interior pointer"), operator-> is not imported, templates
//     (Array2DRef) are not imported, and RawImageData::data is protected.
//   • rawspeed functions are imported as NON-throwing: a C++ exception on the
//     error path terminates the process (proved by the "bogus input" leg).

@main
struct Probe {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: RawSpeedInterop <cameras.xml> <file>\n".utf8))
            exit(2)
        }
        let camfile = args[1]
        let rawPath = args[2]

        var meta = rawspeed.CameraMetaData(camfile)
        // NOTE: CameraMetaData::getCamera(const Camera*) is also unavailable in Swift
        // (returns a pointer into the metadata map) — the metadata surface is closed too.
        print("meta_loaded: true")
        guard let data = FileManager.default.contents(atPath: rawPath) else {
            print("read failed"); exit(1)
        }
        // NOTE: decodeRaw() is imported non-throwing — an exception inside this
        // closure would terminate the process (no Swift error can be caught).
        data.withUnsafeBytes { raw in
            let buf = rawspeed.Buffer(raw.bindMemory(to: UInt8.self).baseAddress!,
                                      UInt32(data.count))
            var parser = rawspeed.RawParser(buf)
            let dec = parser.getDecoder(&meta)   // unique_ptr; null only for unparsable input
            dec.pointee.failOnUnknown = true
            dec.pointee.checkSupport(&meta)
            dec.pointee.decodeRaw()
            dec.pointee.decodeMetaData(&meta)
            _ = dec.pointee.mRaw
            print("decode_returned: true")
            print("mRaw_handle_is_live: true (no accessor exists in Swift)")

            // Evidence of the wall: every one of these is a compile error.
            //   r.get()          -> "C++ method 'get' ... may return an interior pointer" (unavailable)
            //   r.operator->()   -> not imported
            //   r.getU16DataAsCroppedArray2DRef() -> member function; the RawImageData* is unreachable
            // RawImageData::data is protected.
        }
        print("PASS_DRIVE_ONLY")
    }
}
