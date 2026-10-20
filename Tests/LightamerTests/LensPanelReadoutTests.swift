@testable import Lightamer
import LightamerIOP
import XCTest

/// LensPanelReadoutTests (Plan LENS-01 T5) — the §1 readout pure model.
///
/// The App-side `LensPanelReadout` maps the params' mutex judgment (X1:
/// read from the params, no second seam) + the hardened match outcome
/// onto display states with STATIC copy keys. Table-driven over all four
/// embedded faces (incl. the nil "undetermined" neutral) and all match
/// faces; the frozen copy-key set is pinned (the localization ledger —
/// static literals only, the interpolated-key trap M2-9 F-2 banned).
///
/// The model lives in the App target (LensPanelView.swift) — the App
/// bundle is the plan-mandated domain (test_bundles: APP).
final class LensPanelReadoutTests: XCTestCase {

    private func params(lensKey: String? = "E 16mm f/2.8") -> LensModule.Params {
        var p = LensModule.Params(source: .lensfun, focalLength: 16, lensKey: lensKey)
        return p
    }

    // MARK: - Embedded-geometry faces (incl. the nil undetermined)

    func testEmbeddedFacesTable() {
        XCTAssertEqual(LensPanelReadout.embedded(.detected), .embeddedDetected)
        XCTAssertEqual(LensPanelReadout.embedded(.unknown), .embeddedUnknown)
        XCTAssertEqual(LensPanelReadout.embedded(.notApplicable), .embeddedNotApplicable)
        XCTAssertEqual(LensPanelReadout.embedded(nil), .embeddedUndetermined,
                       "nil judgment = the neutral undetermined face, never a conclusion")
    }

    func testEmbeddedCopyKeysAreStaticLiterals() {
        XCTAssertEqual(LensPanelReadout.embeddedDetected.copyKey, "panel_lens_embedded_detected")
        XCTAssertEqual(LensPanelReadout.embeddedUnknown.copyKey, "panel_lens_embedded_unknown")
        XCTAssertEqual(LensPanelReadout.embeddedNotApplicable.copyKey, "panel_lens_embedded_notapplicable")
        // The undetermined face REUSES the pre-existing note key (zero
        // historical-key touching — the tail-block insert discipline).
        XCTAssertEqual(LensPanelReadout.embeddedUndetermined.copyKey, "panel_lens_embedded_note")
    }

    // MARK: - Match faces

    private func profile(maker: String = "Sony", model: String = "E 16mm f/2.8") -> LensMatchedProfile {
        LensMatchedProfile(maker: maker, model: model, cropFactor: 1.534, entryIndex: 0)
    }

    func testMatchFacesTable() {
        // No database BEFORE any matching.
        XCTAssertEqual(
            LensPanelReadout.match(params: params(), hasData: false, outcome: nil),
            .noDatabase)
        // Missing lens EXIF → idle (even when an outcome sneaks in).
        XCTAssertEqual(
            LensPanelReadout.match(
                params: params(lensKey: nil), hasData: true,
                outcome: .matched(profile(), score: 100)),
            .idle)
        // Missing focal degrades to the idle/exif-missing face.
        XCTAssertEqual(
            LensPanelReadout.match(params: params(), hasData: true, outcome: .missingFocal),
            .idle)
        // nil outcome with data = noDatabase (the store face returned nil).
        XCTAssertEqual(
            LensPanelReadout.match(params: params(), hasData: true, outcome: nil),
            .noDatabase)
        // Matched carries maker + first model + score.
        XCTAssertEqual(
            LensPanelReadout.match(
                params: params(), hasData: true,
                outcome: .matched(profile(), score: 105)),
            .matched(name: "Sony E 16mm f/2.8", score: 105))
        XCTAssertEqual(LensPanelReadout.match(params: params(), hasData: true, outcome: .ambiguous(score: 60)), .ambiguous)
        XCTAssertEqual(LensPanelReadout.match(params: params(), hasData: true, outcome: .noLens), .noLens)
    }

    func testMatchedNameHandlesEmptyMaker() {
        let anonymous = LensPanelReadout.match(
            params: params(), hasData: true,
            outcome: .matched(profile(maker: ""), score: 60))
        XCTAssertEqual(anonymous, .matched(name: "E 16mm f/2.8", score: 60))
    }

    // MARK: - The frozen copy-key ledger

    func testAllCopyKeysFrozenSet() {
        XCTAssertEqual(LensPanelReadout.allCopyKeys.count, 9)
        // Every state's key is inside the frozen set (no orphan keys).
        let states: [LensPanelReadout] = [
            .embeddedDetected, .embeddedUnknown, .embeddedNotApplicable,
            .embeddedUndetermined, .matched(name: "x", score: 1),
            .ambiguous, .noLens, .noDatabase, .idle,
        ]
        for state in states {
            XCTAssertTrue(LensPanelReadout.allCopyKeys.contains(state.copyKey),
                          "orphan copy key: \(state.copyKey)")
        }
        // Static-literal shape only: no whitespace/interpolation residue
        // (M2-9 F-2 — the interpolated dynamic lookup key is banned).
        for key in LensPanelReadout.allCopyKeys {
            XCTAssertFalse(key.contains(" "), key)
            XCTAssertFalse(key.contains("("), key)
        }
    }
}
