import XCTest

@testable import Lightamer
@testable import LightamerCore
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────────
// RegistryFilmModuleTests (spektra-module P1 T1') — the spektraFilm
// registration + env-gate suite (AC-T1'-2/3/4):
//   - registration is UNCONDITIONAL (both faces resolve; M2 选 a);
//   - the env gate is a pure injectable predicate + a production wrapper;
//   - the catalog row + the E7 closure pin the 21st row;
//   - the default-face counting contracts stay byte-identical.
// ─────────────────────────────────────────────────────────────────────────────

final class RegistryFilmModuleTests: XCTestCase {

    /// AC-T1'-2 (i): `makeBox("spektraFilm")` resolves in BOTH faces —
    /// registration is unconditional; env gates only write/UI faces.
    func testSpektraFilmResolvesInBothFaces() async {
        for defaultFace in [false, true] {
            let registry = ModuleRegistry.makeDefault()
            await LightamerIOPRegistry.populate(registry, defaultFace: defaultFace)
            let box = await registry.makeBox(opName: SpektraFilmModule.opName)
            XCTAssertNotNil(box, "spektraFilm must resolve (defaultFace=\(defaultFace))")
        }
    }

    /// AC-T1'-2 (ii): the pure predicate's three-way split — absent → false,
    /// "0" → false, "1" → true (the LibraryLegacyGate KD-4 pin shape).
    func testFilmModulePredicateThreeWaySplit() {
        XCTAssertFalse(LightamerIOPRegistry.isFilmModuleRequested(environment: [:]))
        XCTAssertFalse(
            LightamerIOPRegistry.isFilmModuleRequested(
                environment: [LightamerIOPRegistry.filmModuleEnvironmentKey: "0"]))
        XCTAssertTrue(
            LightamerIOPRegistry.isFilmModuleRequested(
                environment: [LightamerIOPRegistry.filmModuleEnvironmentKey: "1"]))
    }

    /// AC-T1'-2 (iii): the production wrapper reads the process env — same
    /// value as the predicate fed the live environment (no second source).
    func testFilmModuleWrapperReadsProcessEnvironment() {
        XCTAssertEqual(
            LightamerIOPRegistry.isFilmModuleRequested(),
            LightamerIOPRegistry.isFilmModuleRequested(
                environment: ProcessInfo.processInfo.environment))
    }

    /// AC-T1'-3: the 21st row answers .grade + resolves + stays out of the
    /// editing seed (the CAT02/filmPlacement 注记同款 — the Film panel's
    /// enable entry is the seed moment, T6').
    func testSpektraFilmCatalogRowOwnerAndSeedAbsence() {
        XCTAssertEqual(
            GradeCatalog.item(opName: SpektraFilmModule.opName)?.owner, .grade)
        XCTAssertEqual(
            NodeOwnershipCatalog.owner(of: SpektraFilmModule.opName), .grade)
        XCTAssertFalse(
            LightamerIOPRegistry.editingDefaultInstances().map(\.opName)
                .contains(SpektraFilmModule.opName),
            "spektraFilm must not seed fresh images")
        XCTAssertFalse(
            LightamerIOPRegistry.editingDefaultInstances(defaultFace: true).map(\.opName)
                .contains(SpektraFilmModule.opName),
            "spektraFilm must not seed the default face either")
        XCTAssertFalse(
            LightamerIOPRegistry.defaultFaceDisabledOpNames
                .contains(SpektraFilmModule.opName),
            "spektraFilm is NOT a disabled op (default-face registered)")
    }

    /// AC-T1'-4: the default-face counting contracts stay byte-identical —
    /// IopCatalog.ops 19 (the table untouched), the terminal trio seed, and
    /// the face-count contract (full == default + 6). The MCP list_iops
    /// output pins (16/19) live in DefaultFaceTests (same bundle) and run
    /// green — the R-B2 zero-change face, split-pinned.
    func testDefaultFaceCountingContractsUnchanged() async {
        XCTAssertEqual(IopCatalog.ops.count, 19)
        let trioCount = await ModuleRegistry.makeDefault().makeDefaultInstances().count
        XCTAssertEqual(trioCount, 3, "the terminal trio")
        let full = LightamerIOPRegistry.editingDefaultInstances().count
        let narrow = LightamerIOPRegistry.editingDefaultInstances(defaultFace: true).count
        XCTAssertEqual(full, narrow + 6, "the D1/D2 six are the only seed delta")
    }

    // MARK: - spektra-module P1 T4' (AC-T4'-6): the env write-face gate

    /// The env-off face: the key spelled once + the default-off reading
    /// (the absent env answers false — the T4' environment gate).
    func testEnvOffIsTheDefaultFace() {
        XCTAssertEqual(
            LightamerIOPRegistry.filmModuleEnvironmentKey,
            "LIGHTAMER_FILM_MODULE")
        XCTAssertFalse(LightamerIOPRegistry.isFilmModuleRequested(
            environment: [:]))
    }

    /// Registration ignores the env (both faces resolve with the env
    /// absent — the M2-a render face, re-pinned at the gate level).
    func testRegistrationIgnoresTheEnv() async {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry, defaultFace: true)
        let box = await registry.makeBox(opName: "spektraFilm")
        XCTAssertNotNil(box)
    }
}
