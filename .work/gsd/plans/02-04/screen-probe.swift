import AppKit
func describe(_ cs: NSColorSpace?, tag: String) {
    guard let cs else { print("\(tag): nil"); return }
    let cg = cs.cgColorSpace
    let cgName = cg?.name as String?
    let icc = cs.iccProfileData
    let matchesP3 = cs == .displayP3
    let matchesSRGB = cs == .sRGB
    print("\(tag): localized=\(cs.localizedName) components=\(cs.numberOfColorComponents) model=\(cs.colorSpaceModel.rawValue)")
    print("   cg.name=\(cgName ?? "nil") bytesPerPixel? model check: matchesNSP3=\(matchesP3) matchesNSSRGB=\(matchesSRGB) iccBytes=\(icc?.count ?? -1)")
    // compare ICC profile data with the system P3/sRGB profiles
    if let icc, let p3icc = NSColorSpace.displayP3.iccProfileData, icc == p3icc { print("   icc == displayP3 icc") }
    if let icc, let srgbicc = NSColorSpace.sRGB.iccProfileData, icc == srgbicc { print("   icc == sRGB icc") }
}
for (i, screen) in NSScreen.screens.enumerated() {
    describe(screen.colorSpace, tag: "screen \(i)")
}
describe(NSColorSpace.displayP3, tag: "NSColorSpace.displayP3")
describe(NSColorSpace.sRGB, tag: "NSColorSpace.sRGB")
print("CGColorSpace(name: displayP3).name = \(CGColorSpace(name: CGColorSpace.displayP3)?.name as String? ?? "nil")")
print("CGColorSpace(name: extendedSRGB).name = \(CGColorSpace(name: CGColorSpace.extendedSRGB)?.name as String? ?? "nil")")
print("extendedLinearDisplayP3 present = \(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) != nil)")
print("extendedLinearSRGB present = \(CGColorSpace(name: CGColorSpace.extendedLinearSRGB) != nil)")
