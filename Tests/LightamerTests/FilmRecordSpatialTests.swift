@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmRecordSpatialTests (Plan M8-3+ T3 — LAYERS) — the five spatial legs'
// record contract (R-M83P-2's pin face):
//
//   1. THE THREE FACES: CodingKeys/decode/encode/hash move in ONE batch
//      (MIN-6's discipline — each field flips the recordHash; nil keeps
//      the absent key out of the JSON bytes).
//   2. THE NIL ABSENT-IDENTITY: a nil-legs record serializes WITHOUT the
//      five keys (nil = omitted, not null — the v9 pristine discipline).
//   3. THE SEED AUTO-FOLD: the recordHash folds the film sub-run seed
//      (FilmTailParams.recordHash) — nil-legs records share the legacy
//      seed bit-identically; each set leg moves it (the per-field flip).
//   4. THE DIFFUSION PRIORITY: diffusionAmount with the family absent is
//      IGNORED at the resolved face (nil-family = the leg off); family
//      set + amount absent = 1.0 (the default face).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmRecordSpatialTests: XCTestCase {

    // MARK: - 1+2: the three faces + the absent identity

    func testFiveLegsEncodeDecodeHashInOneBatch() throws {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // The nil face: all five keys absent.
        let nilBytes = try encoder.encode(record)
        let nilText = String(decoding: nilBytes, as: UTF8.self)
        for key in ["grain_amount", "halation_amount", "diffusion_family",
                    "diffusion_amount", "reversal_print_mode"] {
            XCTAssertFalse(nilText.contains(key),
                           "nil legs omit \(key) (the absent identity)")
        }
        let nilHash = record.stableHash()

        // Each leg flips the hash (the per-field movement face).
        var grain = record
        grain.grainAmount = 2.5
        XCTAssertNotEqual(grain.stableHash(), nilHash)
        XCTAssertTrue(String(decoding: try encoder.encode(grain), as: UTF8.self)
            .contains("\"grain_amount\":2.5"))

        var halation = record
        halation.halationAmount = 0.75
        XCTAssertNotEqual(halation.stableHash(), nilHash)

        var family = record
        family.diffusionFamily = "pro-mist"
        XCTAssertNotEqual(family.stableHash(), nilHash)

        var amount = record
        amount.diffusionAmount = 0.5
        XCTAssertNotEqual(amount.stableHash(), nilHash)

        var mode = record
        mode.reversalPrintMode = SpectralNeutralSolve.directPositiveMode
        XCTAssertNotEqual(mode.stableHash(), nilHash)

        // The decode face: every key round-trips verbatim.
        let decoded = try JSONDecoder().decode(
            FilmRecord.self, from: try encoder.encode(grain))
        XCTAssertEqual(decoded.grainAmount, 2.5)
        XCTAssertNil(decoded.halationAmount)
    }

    // MARK: - 3: the seed auto-fold

    func testRecordHashFoldsTheFilmSeed() throws {
        let store = try FilmMaterialStore(profilesDirectory: URL(
            fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles"))
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)

        var nilRecord = FilmRecord()
        nilRecord.filmStock = "kodak_portra_400"
        nilRecord.paperStock = "kodak_portra_endura"
        let nilParams = FilmTailParams(
            record: nilRecord, filmProfile: film, paperProfile: paper,
            materialPairHash: pairHash)
        let nilSeed = FilmTailAssembly.seed(
            upstream: 0xABCD, params: nilParams, solvedPackHash: 0x1234,
            renderProcess: .legacy)

        // Each set leg moves the seed (the auto-fold face).
        var grain = nilRecord
        grain.grainAmount = 2.5
        let grainSeed = FilmTailAssembly.seed(
            upstream: 0xABCD,
            params: FilmTailParams(
                record: grain, filmProfile: film, paperProfile: paper,
                materialPairHash: pairHash),
            solvedPackHash: 0x1234, renderProcess: .legacy)
        XCTAssertNotEqual(grainSeed, nilSeed,
                           "grainAmount folds the film seed")

        var family = nilRecord
        family.diffusionFamily = "pro-mist"
        let familySeed = FilmTailAssembly.seed(
            upstream: 0xABCD,
            params: FilmTailParams(
                record: family, filmProfile: film, paperProfile: paper,
                materialPairHash: pairHash),
            solvedPackHash: 0x1234, renderProcess: .legacy)
        XCTAssertNotEqual(familySeed, nilSeed,
                           "diffusionFamily folds the film seed")
    }

    // MARK: - 4: the diffusion priority

    func testDiffusionAmountWithoutFamilyIsIgnored() throws {
        // The priority face lives at the CONSUMPTION layer (T5's leg
        // reads the family first): this test pins the record face's
        // premise — the amount key rides the record even when the family
        // is absent (no record-level coercion), so the consumer's
        // family-first read is the single priority gate.
        var record = FilmRecord()
        record.diffusionAmount = 0.5
        XCTAssertNil(record.diffusionFamily)
        let data = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(
            object["diffusion_amount"],
            "the amount key rides the record (the consumer gates it)")
        XCTAssertNil(object["diffusion_family"])
        // Family set + amount absent: the key stays absent (the consumer
        // defaults it to 1.0 — the default face's premise).
        var familyOnly = FilmRecord()
        familyOnly.diffusionFamily = "pro-mist"
        let familyData = try JSONEncoder().encode(familyOnly)
        let familyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: familyData) as? [String: Any])
        XCTAssertNil(familyObject["diffusion_amount"])
    }

    // MARK: - 5: the bake no-fold negative (T3 A4)

    func testSpatialLegsFoldNoBakeSlotKey() throws {
        // The structural proof: NO spatial leg folds any bake slot key
        // (the legs are runtime uniforms — only the plane seed moves).
        // Proved at the SOURCE face: the consult's key-fold sites fold
        // ONLY the filter/grade/reversal tags (the M9-2/T2 faces) — the
        // spatial legs have no tag, no fold, no slot term. This test
        // pins the fold-call census at the consult (three foldTag call
        // sites, three tag names — a fourth fold fails here).
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()     // Tests/LightamerTests
                .deletingLastPathComponent()     // Tests
                .deletingLastPathComponent()     // repo root
                .appendingPathComponent(
                    "LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift"),
            encoding: .utf8)
        let folds = source.components(separatedBy: "\n").filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return $0.contains("foldTag(") && !trimmed.hasPrefix("//")
                && !trimmed.hasPrefix("static func foldTag")
        }
        XCTAssertEqual(
            folds.count, 3,
            "the consult folds exactly three tags (filter/grade/reversal)")
        XCTAssertTrue(folds.joined().contains("\"filter:"))
        XCTAssertTrue(folds.joined().contains("\"grade:"))
        XCTAssertTrue(folds.joined().contains("\"reversal:"))
        XCTAssertFalse(
            folds.joined().contains("grain")
                || folds.joined().contains("halation")
                || folds.joined().contains("diffusion"),
            "no spatial leg folds a bake slot key")
    }
}
