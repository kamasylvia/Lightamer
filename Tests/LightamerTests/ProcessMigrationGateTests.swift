@testable import Lightamer
@testable import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// ProcessMigrationGateTests (Plan M9-4 T2, D-M9SP-7 — the migration UX
// generalization's APP-domain gates):
//
//   (1) the evaluate FIVE-STATE table (film-only / colorWheels-only /
//       both / neither / editing-in-flight) — the generalized two-source
//       gate with the M8-3-era call shape preserved (the defaulted
//       hasColorWheelsEdits input compiles the old callers untouched);
//   (2) the marker's TWO FORMS through a real EditorState: the film form
//       rides `commitFilm` (the M8-3 semantics verbatim — the filmRecord
//       slot, document-scope), the colorWheels form commits the params
//       VERBATIM as a plain item under the same
//       `history_process_migrate` label (zero params diff — the marker
//       rides the label);
//   (3) the panel fork's read projection: the v3 view consumes
//       `effective(params)` (the offset-absent shape converts — the
//       first edit materializes the offset) and the v1/v2 resolution
//       never resolves to the .v3 arm (the frozen view's discriminator).
// ─────────────────────────────────────────────────────────────────────────

@MainActor
final class ProcessMigrationGateTests: XCTestCase {

    // MARK: - The five-state evaluate table

    func testEvaluateFiveStates() {
        // film-only (the M8-3 shape — the defaulted CW input absent).
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: 1, hasFilmRecord: true, editingInFlight: false),
            .migrate(targetRawValue: 3), "film-only migrates")
        // colorWheels-only (the M9-4 new audience — the second gate source).
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: 0, hasFilmRecord: false,
                hasColorWheelsEdits: true, editingInFlight: false),
            .migrate(targetRawValue: 3),
            "a colorWheels-only legacy document earns the row")
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: 2, hasFilmRecord: false,
                hasColorWheelsEdits: true, editingInFlight: false),
            .migrate(targetRawValue: 3),
            "a colorWheels-only v2 document earns the row too")
        // both — same migrate (single row, single action).
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: 1, hasFilmRecord: true,
                hasColorWheelsEdits: true, editingInFlight: false),
            .migrate(targetRawValue: 3), "both sources → the same single row")
        // neither — the identity-both-arms document is not applicable.
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: 1, hasFilmRecord: false,
                hasColorWheelsEdits: false, editingInFlight: false),
            .notApplicable,
            "a both-absent document renders the arms bit-identically — no row")
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: nil, hasFilmRecord: false,
                hasColorWheelsEdits: true, editingInFlight: false),
            .notApplicable, "no image — nothing to migrate even with CW edits")
        // editing-in-flight wins over every other state (the D-H1 guard).
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: 1, hasFilmRecord: true,
                hasColorWheelsEdits: true, editingInFlight: true),
            .editingInFlight, "an open drag window refuses the migration")
        // alreadyCurrent for the current generation (both sources on).
        XCTAssertEqual(
            FilmMigrationAction.evaluate(
                processRawValue: 3, hasFilmRecord: true,
                hasColorWheelsEdits: true, editingInFlight: false),
            .alreadyCurrent, "a v3 document never re-migrates")
    }

    // MARK: - The marker's two forms (real EditorState)

    /// The colorWheels form: the params ride the item's snapshot VERBATIM
    /// (byte-equal paramsData) under the shared migrate label — zero
    /// params diff, the marker is the label.
    func testColorWheelsMarkerCommitsVerbatimParams() throws {
        let editorState = EditorState()
        let params = ColorWheelsModule.Params(
            lift: ColorWheelControl(
                colorOffset: SIMD3(0.05, -0.02, 0.01), luminanceOffset: 0.01))
        let cw = ModuleInstance(
            module: ColorWheelsModule.self, multiPriority: 0,
            multiName: "", params: params)
        editorState.commitProcessMigrationMarker(
            colorWheels: cw, label: String(localized: "history_process_migrate"))
        let last = try XCTUnwrap(editorState.history.items.last)
        XCTAssertEqual(String(localized: "history_process_migrate"), last.label)
        // VERBATIM: the committed snapshot's params bytes equal the
        // instance's (a zero-diff commit — the marker semantics).
        XCTAssertEqual(last.snapshot.paramsData, cw.paramsData)
        XCTAssertEqual(last.snapshot.opName, ColorWheelsModule.opName)
    }

    /// The film form stays the M8-3 face (the filmRecord slot,
    /// document-scope) — the generalization changed nothing there.
    func testFilmMarkerKeepsTheM83Face() throws {
        let editorState = EditorState()
        // The film form's placeholder slot takes the current top global
        // record — seed one via the load face (internal, @testable).
        let placeholder = ModuleInstance(
            module: ExposureModule.self, multiPriority: 0,
            multiName: "", params: ExposureModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [placeholder])
        var record = FilmRecord()
        record.filmStock = "portra400"
        record.paperStock = "kodak_2302"
        editorState.commitProcessMigrationMarker(
            record: record, label: String(localized: "history_process_migrate"))
        let last = try XCTUnwrap(editorState.history.items.last)
        XCTAssertEqual(last.filmRecord, record)
        XCTAssertEqual(
            last.layerScope, HistoryStack.filmDocumentScope,
            "the film marker stays document-scoped (the M8-3 semantics)")
    }

    // MARK: - The panel fork's read projection

    /// The v3 view's editing base is `effective(params)`: an offset-absent
    /// legacy shape converts (the offset MATERIALIZES — the discriminator
    /// flips at the first edit); an offset-present shape reads through
    /// byte-identically.
    func testPanelForkReadProjection() throws {
        // The legacy shape converts: the lift becomes the offset exactly.
        var legacy = ColorWheelsModule.Params()
        legacy.lift = ColorWheelControl(
            colorOffset: SIMD3(0.05, -0.02, 0.01), luminanceOffset: 0.01)
        let projected = ColorWheelsModule.effectiveToneWheelParams(legacy)
        XCTAssertNotNil(projected.offset, "the first edit materializes the offset")
        // The ACEScc B constant (17.52 — the ColorWheels module's
        // internal literal; the APP bundle cannot reach IOP internals).
        let b = Double(Float(17.52))
        let stops = ColorWheelsModule.controlChannelStops(projected.offset!)
        XCTAssertEqual(Double(stops.x), 0.06 * b, accuracy: 1.0e-4)
        // A v2 shape reads through (no re-conversion, byte-identical).
        let v2 = projected
        XCTAssertEqual(
            ColorWheelsModule.effectiveToneWheelParams(v2), v2,
            "an offset-present shape is read through verbatim")
        // The panel fork discriminator: v1/v2 documents never resolve to
        // the .v3 arm (the frozen three-wheel view).
        XCTAssertNotEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 1)!), .v3)
        XCTAssertNotEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 2)!), .v3)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 3)!), .v3)
    }
}
