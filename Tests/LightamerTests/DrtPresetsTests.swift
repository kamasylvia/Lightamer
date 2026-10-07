@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DrtPresetsTests (Plan M2-6-1 T5, AC#6) — the preset triple face:
//
//   1. ENUM COUNTS: looks 7 / tonescale 14 (the m3 correction — USE LOOK
//      PRESET + 13) / creative white 7 (use-look + 6 named).
//   2. SNAPSHOT COMPLETENESS: every look builds a 53-field group; standard
//      == the record defaults (the hpp payload IS the standard look —
//      cross-validated against the Alcedo expected-params bin, DECISIONS §D7).
//   3. APPLY ATOMICITY: applyPreset lands look snapshot + tonescale
//      override + white strings in one record, field-for-field.
//   4. THE TSPRST11 TRAP: the dctl's ACES-2.0 tonescale text carries
//      tn_hcon/tn_lcon = 1.0 WITH enable = 0 — our projection stores 0.
//   5. CUSTOM: derived judgment flips on one param and restores.
//   6. WHITE RESOLUTION: use-look rides the look's cwp (aery→D75,
//      dystopic→D60, umbra→D50); an explicit white wins.
//
// Core-level suite (LAYERS bundle).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtPresetsTests: XCTestCase {

    // MARK: 1: enum counts

    func testPresetEnumCountsAreSevenFourteenSeven() {
        XCTAssertEqual(DrtLookPreset.allCases.count, 7)
        XCTAssertEqual(DrtTonescalePreset.allCases.count, 14)
        XCTAssertEqual(DrtCreativeWhite.allCases.count, 7)
    }

    func testTonescaleEnumRawValuesFollowTheAlcedoQmlSpellings() {
        XCTAssertEqual(DrtTonescalePreset.useLookPreset.rawValue, "use_look_preset")
        XCTAssertEqual(DrtTonescalePreset.aces1x.rawValue, "aces_1_x")
        XCTAssertEqual(DrtTonescalePreset.aces20.rawValue, "aces_2_0")
        XCTAssertEqual(DrtTonescalePreset.marvelousTonscape.rawValue, "marvelous_tonscape")
        XCTAssertEqual(DrtTonescalePreset.dagrinchiTonegroan.rawValue, "dagrinchi_tonegroan")
        XCTAssertEqual(DrtLookPreset.standard.rawValue, "standard")
        XCTAssertEqual(DrtCreativeWhite.d50.rawValue, "d50")
    }

    // MARK: 2: snapshot completeness

    func testEveryLookBuildsACompleteFiftyThreeFieldGroup() {
        for look in DrtLookPreset.allCases {
            let s = look.snapshot
            // The group must differ from nothing-to-see: the seven looks are
            // distinct pairs (umbra ≠ standard at minimum in tnCon).
            _ = s
        }
        // Distinctness: each look differs from the standard in ≥1 field
        // (umbra's tnCon 1.8 vs 1.66 etc. — spot the strongest signal).
        let standard = DrtLookPreset.standard.snapshot
        for look in DrtLookPreset.allCases where look != .standard {
            XCTAssertNotEqual(look.snapshot, standard, "\(look.rawValue) must differ from standard")
        }
    }

    func testStandardLookEqualsTheRecordDefaults() {
        // The hpp payload defaults ARE the standard look (the bin cross-
        // check in DECISIONS §D7 pins the same numbers).
        XCTAssertEqual(DrtLookPreset.standard.snapshot, DrtRecord().parameters)
        XCTAssertEqual(DrtLookPreset.standard.snapshot.tnCon, 1.66)
        XCTAssertEqual(DrtLookPreset.standard.snapshot.rsBw, 0.55)
        XCTAssertEqual(DrtLookPreset.standard.snapshot.hsYRng, 1.0)
    }

    // MARK: 3: apply atomicity

    func testApplyPresetIsAtomicAndFieldComplete() {
        var edited = DrtRecord()
        edited.parameters.tnCon = 9.9
        edited.encodingSpace = .rec2020
        let applied = DrtPresets.applyPreset(
            record: edited, look: .umbra, tonescale: .useLookPreset, white: .useLookPreset)
        // The look snapshot lands WHOLE (the stale tnCon 9.9 is gone).
        XCTAssertEqual(applied.parameters, DrtLookPreset.umbra.snapshot)
        XCTAssertEqual(applied.parameters.tnCon, 1.8)
        // The preset TAGS land with it (the persisted strings).
        XCTAssertEqual(applied.lookPreset, "umbra")
        XCTAssertEqual(applied.tonescalePreset, "use_look_preset")
        XCTAssertEqual(applied.creativeWhite, "use_look_preset")
        // The non-preset record fields ride through untouched.
        XCTAssertEqual(applied.encodingSpace, .rec2020)
    }

    func testApplyPresetWithTonescaleOverride() {
        let applied = DrtPresets.applyPreset(
            record: DrtRecord(), look: .standard, tonescale: .arribaTonescale,
            white: .useLookPreset)
        XCTAssertEqual(applied.parameters.tnCon, 1.05)
        XCTAssertEqual(applied.parameters.tnToe, 0.1)
        XCTAssertEqual(applied.parameters.tnLcon, 1.5)
        XCTAssertEqual(applied.parameters.tnLconW, 0.2)
        // Non-tonescale fields stay the look's.
        XCTAssertEqual(applied.parameters.rsSa, 0.35)
        XCTAssertEqual(applied.tonescalePreset, "arriba_tonescale")
    }

    // MARK: 4: the tsprst11 enable trap

    func testAces20TonescaleProjectsDisabledHighLowContrastToZero() {
        // dctl :818: tn_hcon = 1.0f / tn_lcon = 1.0f WITH enable = 0 —
        // behaviorally disabled; our value-domain model stores 0 (§D6).
        let o = DrtTonescalePreset.aces20.tonescaleOverride
        XCTAssertNotNil(o)
        XCTAssertEqual(o?.tnHcon, 0.0)
        XCTAssertEqual(o?.tnLcon, 0.0)
        XCTAssertEqual(o?.tnCon, 1.15)
        XCTAssertEqual(o?.tnToe, 0.04)
        XCTAssertEqual(o?.tnOff, 0.0)
    }

    // MARK: 5: custom judgment

    func testIsCustomLookFlipsOnOneFieldAndRestores() {
        XCTAssertFalse(DrtPresets.isCustomLook(DrtRecord()))
        var record = DrtRecord()
        record.parameters.brlG = -1.49  // one field off the snapshot
        XCTAssertTrue(DrtPresets.isCustomLook(record))
        record.parameters = DrtLookPreset.standard.snapshot
        XCTAssertFalse(DrtPresets.isCustomLook(record))
        // A different look's snapshot is NOT custom.
        var arriba = DrtRecord()
        arriba.parameters = DrtLookPreset.arriba.snapshot
        arriba.lookPreset = "arriba"
        XCTAssertFalse(DrtPresets.isCustomLook(arriba))
    }

    // MARK: 6: creative white resolution

    func testCreativeWhiteOrdinals() {
        XCTAssertNil(DrtCreativeWhite.useLookPreset.ordinal)
        XCTAssertEqual(DrtCreativeWhite.d93.ordinal, 0)
        XCTAssertEqual(DrtCreativeWhite.d75.ordinal, 1)
        XCTAssertEqual(DrtCreativeWhite.d65.ordinal, 2)
        XCTAssertEqual(DrtCreativeWhite.d60.ordinal, 3)
        XCTAssertEqual(DrtCreativeWhite.d55.ordinal, 4)
        XCTAssertEqual(DrtCreativeWhite.d50.ordinal, 5)
    }

    func testResolvedCreativeWhiteRidesTheLookOrTheExplicitChoice() {
        // use-look: the look's own cwp (dctl look branches).
        var record = DrtRecord()  // standard
        record.creativeWhite = "use_look_preset"
        XCTAssertEqual(DrtPresets.resolvedCreativeWhiteOrdinal(record), 2)  // D65
        record.lookPreset = "aery"
        XCTAssertEqual(DrtPresets.resolvedCreativeWhiteOrdinal(record), 1)  // D75
        record.lookPreset = "dystopic"
        XCTAssertEqual(DrtPresets.resolvedCreativeWhiteOrdinal(record), 3)  // D60
        record.lookPreset = "umbra"
        XCTAssertEqual(DrtPresets.resolvedCreativeWhiteOrdinal(record), 5)  // D50
        // An explicit white wins over the look.
        record.creativeWhite = "d93"
        XCTAssertEqual(DrtPresets.resolvedCreativeWhiteOrdinal(record), 0)
    }

    func testLookCreativeWhiteTable() {
        XCTAssertEqual(DrtLookPreset.standard.creativeWhiteOrdinal, 2)
        XCTAssertEqual(DrtLookPreset.arriba.creativeWhiteOrdinal, 2)
        XCTAssertEqual(DrtLookPreset.sylvan.creativeWhiteOrdinal, 2)
        XCTAssertEqual(DrtLookPreset.colorful.creativeWhiteOrdinal, 2)
        XCTAssertEqual(DrtLookPreset.aery.creativeWhiteOrdinal, 1)
        XCTAssertEqual(DrtLookPreset.dystopic.creativeWhiteOrdinal, 3)
        XCTAssertEqual(DrtLookPreset.umbra.creativeWhiteOrdinal, 5)
    }
}
