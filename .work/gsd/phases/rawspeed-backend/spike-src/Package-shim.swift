// swift-tools-version:6.0
import PackageDescription
let rawspeed = "/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike"
let package = Package(
    name: "RawSpeedShim",
    platforms: [.macOS("27.0")],
    targets: [
        .target(
            name: "CRawSpeedShim",
            path: "Sources/CRawSpeedShim",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I", "\(rawspeed)/rawspeed/src/librawspeed",
                    "-I", "\(rawspeed)/build/rawspeed/src",
                    "-isystem", "\(rawspeed)/rawspeed/src/external",
                    "-I", "/opt/homebrew/opt/libomp/include",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(rawspeed)/build/rawspeed", "-lrawspeed",
                    "-L", "/opt/homebrew/opt/libomp/lib", "-lomp",
                    "-L", "/opt/homebrew/opt/pugixml/lib", "-lpugixml",
                    "-L", "/opt/homebrew/opt/libjpeg-turbo/lib", "-ljpeg", "-lz",
                ])
            ]
        ),
        .executableTarget(name: "RSShimProbe", dependencies: ["CRawSpeedShim"], path: "Sources/RSShimProbe"),
    ],
    cxxLanguageStandard: .cxx20
)
