import CoreImage
let v9 = CIRAWFilter.supportedCameraModels(with: CIRAWDecoderVersion.version9)
let v8 = CIRAWFilter.supportedCameraModels(with: CIRAWDecoderVersion.version8)
func hit(_ l: [String]) -> [String] { l.filter { $0.uppercased().contains("7RM5") || $0.uppercased().contains("ILCE-7R") } }
print("v9 camera count:", v9.count, " 7RM5-ish:", hit(v9))
print("v8 camera count:", v8.count, " 7RM5-ish:", hit(v8))
