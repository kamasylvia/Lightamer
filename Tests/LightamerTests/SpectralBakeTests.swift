@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralBakeTests (Plan M8-2 T3 — IOPParity) — the spectral bake cache
// family's mechanism face (X7's tc_lut slot + the print/scan PCHIP slots):
//
//   1. THE DETERMINISM GATE (the double-consult bit face): two consults of
//      the same pair return the SAME bundle — bit-identical tables, the
//      tc slot holds ONE entry, and the bakeCount stays at one fill (the
//      second consult HIT).
//   2. THE PER-PAIR KEYING: a different pair misses and fills its own
//      entries (pair 变 → miss) — the materialPairHash is the only key.
//   3. THE LRU EVICTION: a slot with capacity 2 evicts its LRU tail on the
//      third fill (the mechanism shape, exercised on a fresh slot — the
//      shared slots' capacities are DECISIONS-declared).
//   4. THE BAKECOUNT OBSERVABLE: fills count, touches do not.
//   5. THE CLAMP FACES: the stored PCHIP slices are BIT-IDENTICAL to the
//      bundle's own sets and carry the cmin/cmax clamp faces with the
//      lattice ordering (cmin ≤ cmax per cell, the counts line up with
//      the (steps−1)³ × 3 face).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralBakeTests: XCTestCase {

    // MARK: - Fixtures

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func profile(_ id: String) throws -> FilmProfile {
        try XCTUnwrap(try FilmMaterialStore(
            profilesDirectory: profilesDirectory()
        ).profile(id: id))
    }

    /// The bundle memo box (the class-instance form — Swift 6 strict
    /// concurrency rejects static mutable globals; ONE build is shared by
    /// the whole suite — the slots hold their own copies of the slices).
    private static let bundleBox = BakeFixtureBox()

    private final class BakeFixtureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SpectralFilmTables?
        func tables(make: () throws -> SpectralFilmTables) throws -> SpectralFilmTables {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            lock.unlock()
            let made = try make()
            lock.lock()
            value = made
            lock.unlock()
            return made
        }
    }

    /// The deterministic pair identity for the fixture pair (the same fold
    /// the production keys use — the 01 identity single source).
    private func fixturePairHash() throws -> UInt64 {
        FilmMaterialStore.materialPairHash(
            film: try profile("kodak_portra_400"),
            paper: try profile("kodak_portra_endura"))
    }

    private func secondPairHash() throws -> UInt64 {
        FilmMaterialStore.materialPairHash(
            film: try profile("kodak_ektar_100"),
            paper: try profile("kodak_portra_endura"))
    }

    // MARK: - 1: the determinism gate (the double-consult bit face)

    func testSamePairDoubleConsultHitsWithBitIdenticalBundle() throws {
        let film = try profile("kodak_portra_400")
        let paper = try profile("kodak_portra_endura")
        let pairHash = try fixturePairHash()
        // Relative accounting (the slots are process-wide shared — other
        // tests in this suite may have filled their own pairs already).
        let countBefore = SpectralPrintBake.tcLutSlot.countForTesting
        let first = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        let countAfterFirst = SpectralPrintBake.tcLutSlot.countForTesting
        let fillsAfterFirst = SpectralPrintBake.tcLutSlot.bakeCountForTesting
        let second = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        let countAfterSecond = SpectralPrintBake.tcLutSlot.countForTesting

        // The tc slot: exactly ONE new entry, no new fill on the repeat
        // consult (the second consult HIT).
        XCTAssertEqual(countAfterFirst, countBefore + 1,
                       "the first consult fills exactly one tc entry")
        XCTAssertEqual(countAfterSecond, countAfterFirst,
                       "the same pair consults the same tc slot entry")
        XCTAssertEqual(SpectralPrintBake.tcLutSlot.bakeCountForTesting,
                       fillsAfterFirst,
                       "the second consult must HIT — no rebuild (X7: 禁每 run 重建)")

        // The bundle face: bit-identical through the shared instance (the
        // bundle type's Equatable is the bit face — Float bit patterns).
        XCTAssertEqual(first, second)
        // The PCHIP slices landed from the same build (bit-identical to
        // the bundle's own sets).
        let printSlice = try XCTUnwrap(SpectralPrintBake.printSlot.consult(pairHash))
        let scanSlice = try XCTUnwrap(SpectralPrintBake.scanSlot.consult(pairHash))
        XCTAssertEqual(printSlice, first.print, "the print slice IS the bundle's")
        XCTAssertEqual(scanSlice, first.scan, "the scan slice IS the bundle's")
    }

    // MARK: - 2: the per-pair keying

    func testDifferentPairMissesAndFillsItsOwnEntries() throws {
        let pairHash = try fixturePairHash()
        let otherHash = try secondPairHash()
        XCTAssertNotEqual(pairHash, otherHash,
                          "the fixture pairs must key differently")

        let film = try profile("kodak_ektar_100")
        let paper = try profile("kodak_portra_endura")
        let tcCountBefore = SpectralPrintBake.tcLutSlot.countForTesting
        let built = try SpectralPrintBake.tables(
            forPairHash: otherHash, film: film, paper: paper)
        _ = built

        XCTAssertEqual(SpectralPrintBake.tcLutSlot.countForTesting,
                       tcCountBefore + 1,
                       "the different pair filled its own tc entry (miss)")
        XCTAssertNotNil(SpectralPrintBake.tcLutSlot.consult(otherHash))
        XCTAssertNotNil(SpectralPrintBake.printSlot.consult(otherHash))
        XCTAssertNotNil(SpectralPrintBake.scanSlot.consult(otherHash))
    }

    // MARK: - 3: the LRU eviction (the mechanism shape)

    func testSlotEvictsItsLRUTailBeyondCapacity() {
        let slot = SpectralPrintBake.Slot<Int>(capacity: 2)
        slot.store(1, for: 100)
        slot.store(2, for: 200)
        slot.consult(100)  // touch 100 → 200 becomes the LRU tail
        slot.store(3, for: 300)  // evicts 200
        XCTAssertNil(slot.consult(200), "the LRU tail was evicted")
        XCTAssertEqual(slot.consult(100), 1, "the touched entry survived")
        XCTAssertEqual(slot.consult(300), 3, "the fresh entry survives")
        XCTAssertEqual(slot.countForTesting, 2, "capacity holds")
    }

    // MARK: - 4: the bakeCount observable

    func testBakeCountCountsFillsNotTouches() {
        let slot = SpectralPrintBake.Slot<Int>(capacity: 4)
        XCTAssertEqual(slot.bakeCountForTesting, 0)
        slot.store(1, for: 10)
        slot.store(2, for: 20)
        XCTAssertEqual(slot.bakeCountForTesting, 2, "two fills")
        _ = slot.consult(10)
        _ = slot.consult(20)
        XCTAssertEqual(slot.bakeCountForTesting, 2,
                       "consults touch, never count")
        slot.store(3, for: 10)  // a re-fill of an existing key counts
        XCTAssertEqual(slot.bakeCountForTesting, 3,
                       "a re-fill replaced the slot's content — it counts")
    }

    // MARK: - 5: the clamp faces

    func testStoredPchipSlicesCarryTheClampFaces() throws {
        let pairHash = try fixturePairHash()
        let film = try profile("kodak_portra_400")
        let paper = try profile("kodak_portra_endura")
        let bundle = try SpectralPrintBake.tables(
            forPairHash: pairHash, film: film, paper: paper)
        let steps = SpectralFilmPchipSet.steps
        let cells = (steps - 1) * (steps - 1) * (steps - 1) * 3

        for (name, slice, reference) in [
            ("print", try XCTUnwrap(SpectralPrintBake.printSlot.consult(pairHash)),
             bundle.print),
            ("scan", try XCTUnwrap(SpectralPrintBake.scanSlot.consult(pairHash)),
             bundle.scan),
        ] {
            XCTAssertEqual(slice.lut.count, steps * steps * steps * 3,
                           "\(name): the lattice count")
            XCTAssertEqual(slice.cmin.count, cells,
                           "\(name): the clamp-face count (steps−1)³ × 3")
            XCTAssertEqual(slice.cmax.count, cells, "\(name): the clamp-face count")
            XCTAssertEqual(slice.cmin, reference.cmin,
                           "\(name): the clamp faces ride the bit-identical slice")
            // Per-cell ordering: cmin ≤ cmax everywhere (the monotone
            // preparation's clamp bounds).
            for i in 0..<cells {
                XCTAssertLessThanOrEqual(slice.cmin[i], slice.cmax[i],
                                         "\(name): clamp cell \(i) ordering")
            }
        }
    }
}
