import Foundation
import LightamerCore

// C200-build probe: run the spectral build for the Fuji pair and print the
// solved neutral CC + mid-gray anchor. A clamped (250,250) pair or a
// degenerate anchor = the BW-paper-class build failure on a color paper.
let dir = URL(fileURLWithPath: "/Volumes/UNITEK/Documents/Development/Lightamer/Resources/FilmProfiles/profiles")
let store = try FilmMaterialStore(profilesDirectory: dir)
let film = store.profile(id: "fujifilm_c200")!
let paper = store.profile(id: "fujifilm_crystal_archive_typeii")!
let t0 = Date()
let tables = try SpectralBuildEngine.build(film: film, paper: paper, parameters: .init())
let dt = Date().timeIntervalSince(t0)
print("build_seconds=\(dt)")
print("solvedPrintCC=\(tables.solvedPrintCC)")
print("midgrayFactor=\(tables.midgrayFactor)")
print("midgrayPrintRaw=\(tables.midgrayPrintRaw)")
print("log10PrintExposure=\(tables.log10PrintExposure)")
print("filmDmax=\(tables.filmDmax) filmDmin=\(tables.filmDmin)")
print("enlLo=\(tables.enlLo) enlHi=\(tables.enlHi)")
print("scanLo=\(tables.scanLo) scanHi=\(tables.scanHi)")
