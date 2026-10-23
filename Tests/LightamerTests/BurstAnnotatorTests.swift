import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// BurstAnnotatorTests (Plan LUMEN-A T6, X4/review m-3/m-5) — the query-time
// burst annotation golden face. Upstream vectors are ABSENT (v2.0.1 tests/
// carry no annotate_bursts fixture — the plan's verified fact), so the
// golden = the NumPy REFERENCE implementation (Scripts/gen-burst-golden.py —
// the Lumen library_db code verbatim plus the review m-5 ① comparator pin)
// run over the deterministic 10-row dataset the Swift test weaves
// byte-identically (the shared integer LCG):
//
//   rows 1-3  one camera, 0.5s steps, one signature → burst 1 (best = the
//             widest-open eye 0.35 — the D-LU-4 threshold-free arm)
//   row 4     a DIFFERENT serial → never joins
//   row 5     a dissimilar signature (MAD 1.10 > 0.6) → ends burst 1
//   row 6/7   the copy pair at the same moment — '-' sorts before '.', so
//             the EXPORT name enters first and the ORIGINAL excludes as ITS
//             copy (Lumen's symmetric _copy, faithfully reproduced)
//   rows 8-9  the exact 2.0s gap boundary chain → burst 2 (best = sharpest;
//             row 9 blurry by the absolute floor, row 3 by the group delta)
//   row 10    no timestamp → never groups
//
// Plus the m-5 pins: ② nil signatures group on time alone, ③ the group id =
// the L013 StableHash decimal string (deterministic across runs, no Swift
// Hasher), and the 2.0s/2.0001s boundary pair.
// ─────────────────────────────────────────────────────────────────────────────

final class BurstAnnotatorTests: XCTestCase {

    // MARK: - The dataset weave (mirrors the generator)

    private func lcgBytes(seed: UInt64, count: Int = 256) -> Data {
        var state = seed
        var out = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            out[index] = UInt8((state >> 56) & 0xFF)
        }
        return Data(out)
    }

    private func makeRow(
        _ id: Int64, ts: Double?, _ sig: Data?, _ sharpness: Double?,
        _ ratio: Double?, _ name: String, serial: String = "S1"
    ) -> BurstRow {
        BurstRow(
            imageID: id, make: "Canon", model: "EOS R5", serial: serial,
            capturedTS: ts, signature: sig, eyesRatio: ratio,
            sharpness: sharpness, filename: name)
    }

    private func dataset() -> [BurstRow] {
        let s1 = lcgBytes(seed: 0xA1B2)
        let s2 = lcgBytes(seed: 0xC3D4)
        return [
            makeRow(1, ts: 1000.000, s1, 60, 0.30, "IMG_0001.ARW"),
            makeRow(2, ts: 1000.500, s1, 80, 0.10, "IMG_0002.ARW"),
            makeRow(3, ts: 1001.000, s1, 50, 0.35, "IMG_0003.ARW"),
            makeRow(4, ts: 1000.200, s1, 70, 0.40, "IMG_0004.ARW", serial: "S2"),
            makeRow(5, ts: 1001.500, s2, 65, 0.20, "IMG_0005.ARW"),
            makeRow(6, ts: 1002.000, s1, 55, 0.25, "IMG_0006.ARW"),
            makeRow(7, ts: 1002.000, s1, 58, 0.22, "IMG_0006-Lumen.jpg"),
            makeRow(8, ts: 1004.000, s1, 65, nil, "IMG_0008.ARW"),
            makeRow(9, ts: 1006.000, s1, 20, nil, "IMG_0009.ARW"),
            makeRow(10, ts: nil, s1, 90, nil, "IMG_0010.ARW"),
        ]
    }

    // MARK: - Golden (Lumen 同输入对照 — the m-3 double-implementation path)

    func testGoldenMatchesNumPyReference() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/burst_golden.json")
        struct Golden: Decodable {
            let madS1S2: Double
            let groups: [[Int64]]
            let bestIds: [Int64]
            let annotations: [String: Annotation]

            struct Annotation: Decodable {
                let burst: Int
                let index: Int
                let size: Int
                let best: Bool
                let blurry: Bool
            }
            enum CodingKeys: String, CodingKey {
                case groups, annotations
                case madS1S2 = "mad_s1_s2"
                case bestIds = "best_ids"
            }
        }
        let golden = try JSONDecoder().decode(
            Golden.self, from: Data(contentsOf: url))

        // The reference's signature dissimilarity claim (the grouping lever).
        let s1 = lcgBytes(seed: 0xA1B2)
        let s2 = lcgBytes(seed: 0xC3D4)
        let mad = BurstAnnotator.signatureDifference(s1, s2)
        XCTAssertEqual(mad, golden.madS1S2, accuracy: 1e-9)
        XCTAssertGreaterThan(mad, BurstAnnotator.burstDifference)

        // The groups: membership AND order must equal the reference.
        let formed = BurstAnnotator.groups(for: dataset())
        XCTAssertEqual(formed.map(\.imageIDs), golden.groups)

        // The full annotation face.
        let annotations = BurstAnnotator.annotate(rows: dataset())
        XCTAssertEqual(annotations.count, 10)
        for (key, expected) in golden.annotations {
            let annotation = try XCTUnwrap(annotations[Int64(key)!])
            XCTAssertEqual(annotation.burst, expected.burst, "row \(key) burst")
            XCTAssertEqual(annotation.burstIndex, expected.index, "row \(key) index")
            XCTAssertEqual(annotation.burstSize, expected.size, "row \(key) size")
            XCTAssertEqual(annotation.best, expected.best, "row \(key) best")
            XCTAssertEqual(annotation.blurry, expected.blurry, "row \(key) blurry")
        }
        XCTAssertEqual(
            formed.compactMap { group -> Int64? in
                group.imageIDs.first(where: { annotations[$0]?.best == true })
            },
            golden.bestIds, "one best per group, matching the reference")
    }

    // MARK: - The m-5 ③ group-identity pin (L013)

    func testGroupIDIsStableHashDecimalAndDeterministic() {
        let formed = BurstAnnotator.groups(for: dataset())
        XCTAssertEqual(formed.count, 2)
        for group in formed {
            // Decimal string (L013 — never hex/never Swift Hasher).
            XCTAssertNotNil(UInt64(group.id), "the id parses as a decimal UInt64")
            XCTAssertEqual(String(group.id.filter(\.isNumber)), group.id)
        }
        // Deterministic across runs AND row-order permutations? The canonical
        // string rides GROUP ORDER, which the sort key fixes — the same
        // dataset in a shuffled input order lands the same ids.
        let shuffled = dataset().reversed()
        let again = BurstAnnotator.groups(for: Array(shuffled))
        XCTAssertEqual(again.map(\.id), formed.map(\.id))
        XCTAssertEqual(again.map(\.imageIDs), formed.map(\.imageIDs))
    }

    // MARK: - The boundary + exclusion semantics

    func testGapBoundaryCopyAndNilSignatureSemantics() {
        let s1 = lcgBytes(seed: 0xA1B2)

        // The gap boundary: exactly 2.0 groups, 2.0001 does not.
        let exact = BurstAnnotator.groups(for: [
            makeRow(1, ts: 100.0, s1, 60, nil, "A.ARW"),
            makeRow(2, ts: 102.0, s1, 60, nil, "B.ARW"),
        ])
        XCTAssertEqual(exact.count, 1)
        let over = BurstAnnotator.groups(for: [
            makeRow(1, ts: 100.0, s1, 60, nil, "A.ARW"),
            makeRow(2, ts: 102.0001, s1, 60, nil, "B.ARW"),
        ])
        XCTAssertTrue(over.isEmpty)

        // The ±1e-3 copy face: same ts + same stem = excluded; same ts +
        // DIFFERENT stem = a genuine second frame (the negative arm).
        let copyPair = BurstAnnotator.groups(for: [
            makeRow(1, ts: 100.0, s1, 60, nil, "A.ARW"),
            makeRow(2, ts: 100.0005, s1, 60, nil, "A-Lumen.jpg"),
        ])
        XCTAssertTrue(copyPair.isEmpty, "the export copy never groups")
        let distinctPair = BurstAnnotator.groups(for: [
            makeRow(1, ts: 100.0, s1, 60, nil, "A.ARW"),
            makeRow(2, ts: 100.0, s1, 60, nil, "B.ARW"),
        ])
        XCTAssertEqual(distinctPair.count, 1, "distinct stems at one moment group")

        // The m-5 ② pin: NIL signatures are "similar" — time alone groups.
        let nilSigs = BurstAnnotator.groups(for: [
            makeRow(1, ts: 100.0, nil, 60, nil, "A.ARW"),
            makeRow(2, ts: 100.5, nil, 60, nil, "B.ARW"),
        ])
        XCTAssertEqual(nilSigs.count, 1)

        // A nil timestamp NEVER groups (even adjacent + same camera).
        let noTS = BurstAnnotator.groups(for: [
            makeRow(1, ts: nil, s1, 60, nil, "A.ARW"),
            makeRow(2, ts: 100.0, s1, 60, nil, "B.ARW"),
        ])
        XCTAssertTrue(noTS.isEmpty)
    }

    // MARK: - The constants face (D-LU-10 family: no recalibration)

    func testConstantsMatchLumen() {
        XCTAssertEqual(BurstAnnotator.burstGap, 2.0)
        XCTAssertEqual(BurstAnnotator.burstDifference, 0.6)
        XCTAssertEqual(BurstAnnotator.blurryFloor, 22.0)
        XCTAssertEqual(BurstAnnotator.burstBlurryDelta, 14.0)
    }
}
