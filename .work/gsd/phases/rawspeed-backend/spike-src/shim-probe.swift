import CRawSpeedShim
import Foundation

@main
struct ShimProbe {
    static func main() {
        let a = CommandLine.arguments
        let camfile = a.count > 1 ? a[1] : "/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/rawspeed/data/cameras.xml"
        let rawPath = a.count > 2 ? a[2] : "/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/samples/7RM5-LosslessCompressedLarge.ARW"
        var err = rs_error()
        guard let img = rs_open(rawPath, camfile, &err) else {
            let message = withUnsafePointer(to: &err.message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
            }
            print("open_failed code=\(err.code) msg=\(message)")   // no exception, no crash
            return
        }
        defer { rs_free(img) }
        var info = rs_image_info()
        guard rs_fill_info(img, &info, &err) == 0 else { print("info failed"); return }
        var make = info.make, model = info.model
        print("make=\(withUnsafePointer(to: &make) { $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) } })")
        print("model=\(withUnsafePointer(to: &model) { $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) } })")
        print("dim=\(info.width)x\(info.height) uncropped=\(info.uncropped_width)x\(info.uncropped_height)")
        print("crop=\(info.crop_left),\(info.crop_top),\(info.crop_right),\(info.crop_bottom) cpp=\(info.cpp) pitch_elems=\(info.pitch_elems) cfa=\(info.is_cfa) xtrans=\(info.is_xtrans)")
        print("cfa_filter=0x\(String(info.cfa_dcraw_filter, radix: 16)) pattern=\(info.cfa_pattern)")
        print("black=\(info.black_level) sep=\(info.black_level_separate) white=\(info.white_level)")
        print("wb=\(info.wb_coeffs) has_wb=\(info.has_wb)")
        print("matrix=\(info.color_matrix) has_matrix=\(info.has_color_matrix)")
        if let p = rs_mosaic(img) {
            var first: [UInt16] = []
            for i in 0..<8 { first.append(p[i]) }
            print("mosaic_first8=\(first)")
        }
        print("hash=\(String(rs_mosaic_hash(img), radix: 16))")
    }
}
