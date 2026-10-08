@testable import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmHistoryTests (Plan M3-3-01 T6, KD-6 — LAYERS/Core level, the
// DrtSidecarTests/HistoryStackTests discipline) — the history face of the
// film record:
//
//   1. commitFilm: ONE document-scoped item (filmDocumentScope marker),
//      the snapshot slot carries the caller's placeholder, and the
//      placeholder NEVER pollutes the global/layer projections.
//   2. The truncate-redo-tail + append + point discipline (the commit
//      twin).
//   3. effectiveFilmRecord follows the pointer (newest-wins, undo/redo/
//      jump time travel).
//   4. THE HASH FOLD: no film item → the anchor hashes BIT-IDENTICALLY to
//      the pre-M3-3-01 formula (the negative test, AC#5); a film edit
//      moves the anchor (set-fields-move); the film term ranks AFTER the
//      DRT term in the fold (order pinned); all existing call sites
//      compile unchanged (the filmRecord parameter defaults nil — pinned
//      by the 3-argument + drt 4-argument forms still existing).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmHistoryTests: XCTestCase {

    // MARK: - Fixtures

    private func makePlaceholder(priority: Int = 0) -> ModuleInstance {
        ModuleInstance(
            module: TestGainModule.self, multiPriority: priority,
            params: TestGainModule.Params(gain: 1.0))
    }

    private func filmRecord(shift: Float = 0) -> FilmRecord {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.yFilterShift = shift
        return record
    }

    private func drtRecord() -> DrtRecord {
        var record = DrtRecord()
        record.peakLuminance = 250.0
        return record
    }

    // MARK: - 1: the commit shape

    func testCommitFilmCreatesASingleDocumentScopedItem() {
        var stack = HistoryStack()
        let placeholder = makePlaceholder()
        stack.commitFilm(
            record: filmRecord(), placeholder: placeholder, label: "Film")
        XCTAssertEqual(stack.items.count, 1)
        XCTAssertEqual(stack.position, 0)
        let item = stack.items[0]
        XCTAssertEqual(item.label, "Film")
        XCTAssertEqual(item.layerScope, HistoryStack.filmDocumentScope)
        XCTAssertEqual(item.snapshot, placeholder, "the placeholder slot")
        XCTAssertEqual(item.filmRecord, filmRecord())
        XCTAssertNil(item.drtRecord)
        // The placeholder never pollutes the instance projections.
        XCTAssertTrue(
            stack.effectiveInstances().isEmpty,
            "a document-scoped item is excluded from the global projection")
    }

    func testCommitFilmTruncatesTheRedoTail() {
        var stack = HistoryStack()
        stack.commit(makePlaceholder(), label: "a")
        stack.commit(makePlaceholder(priority: 1), label: "b")
        _ = stack.undo() // position 0, "b" is redo-able
        stack.commitFilm(
            record: filmRecord(), placeholder: makePlaceholder(priority: 2),
            label: "Film")
        XCTAssertEqual(stack.items.count, 2, "the redo tail is gone")
        XCTAssertEqual(stack.position, 1)
        XCTAssertNil(stack.redo(), "nothing to redo after a commit")
        XCTAssertEqual(stack.items.last?.filmRecord, filmRecord())
    }

    // MARK: - 3: the pointer-faithful projection

    func testEffectiveFilmRecordFollowsThePointer() {
        var stack = HistoryStack()
        XCTAssertNil(stack.effectiveFilmRecord(), "empty stack → nil")

        stack.commit(makePlaceholder(), label: "base")
        XCTAssertNil(stack.effectiveFilmRecord(), "no film item yet")

        stack.commitFilm(
            record: filmRecord(shift: 1), placeholder: makePlaceholder(),
            label: "Film 1")
        stack.commitFilm(
            record: filmRecord(shift: 2), placeholder: makePlaceholder(),
            label: "Film 2")
        XCTAssertEqual(
            stack.effectiveFilmRecord()?.yFilterShift, 2.0, "newest wins")

        _ = stack.undo()
        XCTAssertEqual(stack.effectiveFilmRecord()?.yFilterShift, 1.0)
        _ = stack.undo()
        XCTAssertNil(
            stack.effectiveFilmRecord(),
            "the pointer before every film item → nil (pristine)")

        _ = stack.redo()
        XCTAssertEqual(stack.effectiveFilmRecord()?.yFilterShift, 1.0)

        stack.jump(to: stack.items.count - 1)
        XCTAssertEqual(stack.effectiveFilmRecord()?.yFilterShift, 2.0)
        stack.jump(to: -1)
        XCTAssertNil(stack.effectiveFilmRecord())
    }

    func testFilmProjectionCoexistsWithTheDrtProjection() {
        var stack = HistoryStack()
        stack.commitDrt(
            record: drtRecord(), placeholder: makePlaceholder(), label: "DRT")
        stack.commitFilm(
            record: filmRecord(), placeholder: makePlaceholder(priority: 1),
            label: "Film")
        XCTAssertNotNil(stack.effectiveDrtRecord())
        XCTAssertNotNil(stack.effectiveFilmRecord())
        XCTAssertTrue(
            stack.effectiveInstances().isEmpty,
            "both document-scoped markers stay out of the instance set")
    }

    // MARK: - 4: the hash fold

    func testFoldWithoutFilmItemsIsBitIdenticalToThePreV9Formula() {
        // A stack with plain + DRT commits only (the whole pre-M3-3-01
        // document space): passing the film projection (nil) must not
        // move a bit vs the 4-argument pre-v9 form.
        var stack = HistoryStack()
        stack.commit(makePlaceholder(), label: "a")
        stack.commitDrt(
            record: drtRecord(), placeholder: makePlaceholder(priority: 1),
            label: "DRT")
        let decodeHash = UInt64(0xDEAD_BEEF_CAFE_0001)

        let preV9 = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: stack.effectiveDrtRecord())
        let withFilmParameter = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: stack.effectiveDrtRecord(),
            filmRecord: stack.effectiveFilmRecord())
        XCTAssertEqual(
            preV9, withFilmParameter,
            "no film item folds NOTHING (the regression gate)")
    }

    func testFilmEditMovesTheAnchor() {
        var stack = HistoryStack()
        stack.commit(makePlaceholder(), label: "a")
        let decodeHash = UInt64(0xDEAD_BEEF_CAFE_0002)

        let before = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: nil, filmRecord: stack.effectiveFilmRecord())

        stack.commitFilm(
            record: filmRecord(), placeholder: makePlaceholder(priority: 1),
            label: "Film")
        let after = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: nil, filmRecord: stack.effectiveFilmRecord())
        XCTAssertNotEqual(
            before, after, "set-fields-move")

        // A second film edit moves it again (the payload, not the marker,
        // is what folds).
        stack.commitFilm(
            record: filmRecord(shift: 3), placeholder: makePlaceholder(priority: 2),
            label: "Film 2")
        let after2 = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: nil, filmRecord: stack.effectiveFilmRecord())
        XCTAssertNotEqual(after, after2)
    }

    func testFilmTermFoldsAfterTheDrtTerm() {
        var stack = HistoryStack()
        stack.commit(makePlaceholder(), label: "a")
        stack.commitDrt(
            record: drtRecord(), placeholder: makePlaceholder(priority: 1),
            label: "DRT")
        stack.commitFilm(
            record: filmRecord(), placeholder: makePlaceholder(priority: 2),
            label: "Film")
        let decodeHash = UInt64(0xDEAD_BEEF_CAFE_0003)

        let folded = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil,
            drtRecord: stack.effectiveDrtRecord(),
            filmRecord: stack.effectiveFilmRecord())

        // The documented tail order, re-derived independently:
        // base → drtRecord.stableHash → filmRecord.stableHash.
        var manual = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil)
        manual = withUnsafeBytes(of: drtRecord().stableHash()) {
            StableHash.combine(manual, $0)
        }
        manual = withUnsafeBytes(of: filmRecord().stableHash()) {
            StableHash.combine(manual, $0)
        }
        XCTAssertEqual(folded, manual)

        // The REVERSED order (film before drt) would differ — the rank is
        // load-bearing (a formula-order change = every anchor changes).
        var reversed = HistoryHash.hash(
            stack: stack, decodeParamsHash: decodeHash, layerSnapshot: nil)
        reversed = withUnsafeBytes(of: filmRecord().stableHash()) {
            StableHash.combine(reversed, $0)
        }
        reversed = withUnsafeBytes(of: drtRecord().stableHash()) {
            StableHash.combine(reversed, $0)
        }
        XCTAssertNotEqual(folded, reversed)
    }

    func testFilmItemRidesTheFrozenItemKeys() throws {
        // The HistoryItem's on-disk key set (through the sidecar record
        // pair) — the additive filmRecord key joins the frozen family.
        var stack = HistoryStack()
        stack.commitFilm(
            record: filmRecord(), placeholder: makePlaceholder(), label: "F")
        let item = stack.items[0]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(item))
                as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["id", "snapshot", "label", "timestamp", "layerScope", "filmRecord"],
            "the item writes the film face + its document scope marker over "
                + "the frozen base (stackSnapshot/pasteSet/drtRecord stay absent)")
        XCTAssertEqual(
            (object["filmRecord"] as? [String: Any])?["film_stock"] as? String,
            "kodak_portra_400")
    }
}
