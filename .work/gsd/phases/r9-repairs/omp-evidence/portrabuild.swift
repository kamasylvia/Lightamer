import Foundation
import LightamerCore

// Portra-build baseline: the same faces for the golden pair.
let dir = URL(fileURLWithPath: "/Volumes/UNITEK/Documents/Development/Lightamer/Resources/FilmProfiles/profiles")
let store = try FilmMaterialStore(profilesDirectory: dir)
let film = store.profile(id: "kodak_portra_400")!
let paper = store.profile(id: "kodak_portra_endura")!
let t0 = Date()
let tables = try SpectralBuildEngine.build(film: film, paper: paper, parameters: .init())
let dt = Date().timeIntervalSince(t0)
print("build_seconds=\(dt)")
print("solvedPrintCC=\(tables.solvedPrintCC)")
print("midgrayFactor=\(tables.midgrayFactor)")
print("midgrayPrintRaw=\(tables.midgrayPrintRaw)")
