@testable import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// QuickLookFilmTests (spektra-module P1 T6' — EXPORT bundle) — the QL
// assembly face (AC-T6'-13):
//
//   1. the populated registry resolves spektraFilm (the populate
//      assertion — the appex calls the same populate; the Env wiring
//      itself rides the T8'-3 walkthrough);
//   2. the host-bundle resource helper resolves the store directories
//      (the Core helper with a Bundle parameter — the testable shape;
//      the appex path rides the same helper).
// ─────────────────────────────────────────────────────────────────────────────

final class QuickLookFilmTests: XCTestCase {

    /// The populated registry resolves spektraFilm (unknownOps never
    /// contains it once populated — the D-SM-15① face).
    func testPopulatedRegistryResolvesSpektraFilm() async {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: SpektraFilmModule.opName)
        XCTAssertNotNil(box, "the populate carries spektraFilm (D-SM-15①)")
    }

    /// The resource helper resolves the CC/BW directories from a Bundle
    /// (the helper carries the Bundle parameter — the appex passes its
    /// host bundle; the test passes a fixture bundle root).
    func testResourceHelperResolvesStoreDirectories() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helper = QuickLookFilmResources(bundleRoot: repoRoot)
        let directories = helper.storeDirectories()
        XCTAssertEqual(directories.count, 2, "the CC + BW pair")
        for directory in directories {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.path),
                "the store directory exists: \(directory.path)")
        }
        // The directories build a real store (the resolution face).
        let store = try FilmMaterialStore(profilesDirectories: directories)
        XCTAssertFalse(store.filmStocks().isEmpty)
    }
}
