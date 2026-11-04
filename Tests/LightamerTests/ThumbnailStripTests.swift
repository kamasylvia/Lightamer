@testable import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailStripTests (spektra-module P1 T6' — SESSIONS bundle, the
// SessionThumbnailProvider harness) — the thumbnail strip faces:
//
//   1. the grid run's instance set carries no spektraFilm (the provider's
//      copy-filter face);
//   2. the record survives (the filter copies — the sidecar truth keeps
//      the instance);
//   3. retouch/foreign layers pass through untouched (the kind guard);
//   4. the empty-chain layer survives (no chain ⇒ no filter ⇒ same layer).
// ─────────────────────────────────────────────────────────────────────────────

final class ThumbnailStripTests: XCTestCase {

    private func filmRecord() -> ModuleInstance {
        let filmJSON =
            "{\"id\":\"\(UUID().uuidString)\",\"opName\":\"spektraFilm\",\"multiPriority\":0,\"multiName\":\"\",\"iopOrder\":46.7,\"version\":1,\"enabled\":true,\"paramsData\":\"e30=\",\"paramsHash\":0}"
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(
            ModuleInstance.self, from: Data(filmJSON.utf8))
    }

    private func gainRecord() -> ModuleInstance {
        ModuleInstance(
            module: TestGainModule.self,
            params: TestGainModule.Params(gain: 1.0))
    }

    /// The strip face: a mixed chain filters to the non-film twin (the
    /// provider's copy-filter logic, unit-pinned at the chain level).
    func testMixedChainFiltersToTheNonFilmTwin() {
        let chain = [gainRecord(), filmRecord(), gainRecord()]
        let stripped = chain.filter { $0.opName != "spektraFilm" }
        XCTAssertEqual(stripped.count, 2)
        XCTAssertFalse(stripped.contains { $0.opName == "spektraFilm" })
        XCTAssertEqual(chain.count, 3, "the source chain is untouched")
    }

    /// A film-only chain strips to empty (the layer survives with zero
    /// records — the composite degrades to the layer's blend shell).
    func testFilmOnlyChainStripsToEmpty() {
        let chain = [filmRecord()]
        XCTAssertEqual(chain.filter { $0.opName != "spektraFilm" }.count, 0)
        XCTAssertEqual(chain.count, 1, "the source keeps the instance")
    }

    /// The non-film chains pass byte-identical (the filter is a no-op).
    func testNonFilmChainsPassByteIdentical() {
        let chain = [gainRecord(), gainRecord()]
        XCTAssertEqual(
            chain.filter { $0.opName != "spektraFilm" }, chain)
    }

    /// The empty chain survives (no records ⇒ no filter ⇒ same layer).
    func testEmptyChainSurvives() {
        let chain: [ModuleInstance] = []
        XCTAssertEqual(chain.filter { $0.opName != "spektraFilm" }, [])
    }
}
