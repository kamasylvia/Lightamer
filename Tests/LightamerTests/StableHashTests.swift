import Foundation
import LightamerCore
import XCTest

/// `StableHash` (FNV-1a 64) contract tests — the shared hashing primitive
/// for PipeCacheKey (02-02), history paramsHash (02-05), and sidecar drift
/// detection (02-06). Known vectors are the published FNV-1a 64 test
/// vectors; the empty hash pins the offset basis.
final class StableHashTests: XCTestCase {

    /// Published FNV-1a 64 vector: hash("") == offset basis.
    func testEmptyStringHashesToOffsetBasis() {
        XCTAssertEqual(StableHash.hash(""), StableHash.fnvOffsetBasis)
        XCTAssertEqual(StableHash.fnvOffsetBasis, 0xcbf29ce484222325)
    }

    /// Published FNV-1a 64 test vector.
    func testFoobarKnownVector() {
        XCTAssertEqual(StableHash.hash("foobar"), 0x85944171f73967e8)
    }

    /// Distinct single-byte inputs must not collide.
    func testDistinctInputsDiffer() {
        XCTAssertNotEqual(StableHash.hash("a"), StableHash.hash("b"))
        XCTAssertNotEqual(StableHash.hash("foobar"), StableHash.hash("fooba"))
    }

    /// Determinism across repeated calls (the cross-process "stable" core).
    func testDeterministicAcrossCalls() {
        let first = StableHash.hash("DSC09991.ARW-op-exposure-params")
        let second = StableHash.hash("DSC09991.ARW-op-exposure-params")
        XCTAssertEqual(first, second)
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(StableHash.hash(data), StableHash.hash(data))
    }

    /// Byte-order sensitivity: [01,02] and [02,01] are different sequences.
    func testByteOrderSensitivity() {
        XCTAssertNotEqual(
            StableHash.hash(Data([0x01, 0x02])),
            StableHash.hash(Data([0x02, 0x01]))
        )
    }

    /// `combine` incremental folds equal the one-shot hash (the upstreamHash
    /// accumulation pattern Plan 02-02 relies on).
    func testIncrementalCombineMatchesOneShot() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let oneShot = StableHash.hash(payload)
        let incremental = payload.withUnsafeBytes { buffer -> UInt64 in
            let half = 2
            let first = StableHash.combine(StableHash.fnvOffsetBasis, UnsafeRawBufferPointer(rebasing: buffer[..<half]))
            let second = StableHash.combine(first, UnsafeRawBufferPointer(rebasing: buffer[half...]))
            return second
        }
        XCTAssertEqual(oneShot, incremental)
    }

    /// String hash equals hashing the same string's UTF-8 bytes as Data.
    func testStringAndDataPathsAgree() {
        let s = "colorbalancergb"
        XCTAssertEqual(StableHash.hash(s), StableHash.hash(Data(s.utf8)))
    }
}
