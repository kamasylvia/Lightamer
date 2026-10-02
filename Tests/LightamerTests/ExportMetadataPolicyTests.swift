import Foundation
import LightamerCore
import XCTest

/// M2-9-01 T3 — the metadata strategy model (OQ-6): the Alcedo face
/// (mode + six carriers), the STANDARD-with-fixed-strips defaults, the
/// NONE extreme, and the Codable round-trip. The consumption legs are
/// M2-9-03; this pins the MODEL contract.
final class ExportMetadataPolicyTests: XCTestCase {

    /// The default IS the STANDARD face: the three carriers on, the three
    /// fixed strips OFF (location / serials / editing history stay
    /// excluded — the README-parity face).
    func testStandardDefaultsStripTheThreeFixedFaces() {
        let policy = ExportMetadataPolicy()
        XCTAssertEqual(policy.mode, .standard)
        XCTAssertTrue(policy.includeExif)
        XCTAssertTrue(policy.includeXMP)
        XCTAssertTrue(policy.includeIPTC)
        XCTAssertFalse(policy.includeLocation, "location is a FIXED STRIP default")
        XCTAssertFalse(policy.includeSerials, "serials are a FIXED STRIP default")
        XCTAssertFalse(
            policy.includeEditingHistory,
            "editing history (incl. the XMP summary packet) is a FIXED STRIP default")

        // The .standard constant is the same face.
        XCTAssertEqual(ExportMetadataPolicy.standard, ExportMetadataPolicy())
    }

    /// The NONE extreme strips everything (the bools are moot under the
    /// mode — the consumer short-circuits, M2-9-03).
    func testNoneExtremeStripsEverything() {
        let policy = ExportMetadataPolicy.none
        XCTAssertEqual(policy.mode, .none)
        XCTAssertFalse(policy.includeExif)
        XCTAssertFalse(policy.includeXMP)
        XCTAssertFalse(policy.includeIPTC)
        XCTAssertFalse(policy.includeLocation)
        XCTAssertFalse(policy.includeSerials)
        XCTAssertFalse(policy.includeEditingHistory)
    }

    /// The seven fields are all independently settable (the fine-grain UI
    /// face lands later; the MODEL carries the full face now — OQ-6 A).
    func testFineGrainCarriersAreSettable() {
        let policy = ExportMetadataPolicy(
            mode: .standard, exif: true, xmp: false, iptc: true,
            location: true, serials: true, editingHistory: true)
        XCTAssertTrue(policy.includeExif)
        XCTAssertFalse(policy.includeXMP)
        XCTAssertTrue(policy.includeIPTC)
        XCTAssertTrue(policy.includeLocation)
        XCTAssertTrue(policy.includeSerials)
        XCTAssertTrue(policy.includeEditingHistory)

        // Value semantics: mutating a copy moves nothing.
        var copy = policy
        copy.mode = .none
        XCTAssertEqual(policy.mode, .standard)
    }

    /// Codable round-trip (a new type with no legacy payloads — synthesized
    /// is safe) for both mode extremes and a fine-grain mix.
    func testCodableRoundTrip() throws {
        let policies: [ExportMetadataPolicy] = [
            .standard,
            .none,
            ExportMetadataPolicy(
                mode: .standard, exif: false, xmp: true, iptc: false,
                location: true, serials: false, editingHistory: true),
        ]
        for policy in policies {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(ExportMetadataPolicy.self, from: data)
            XCTAssertEqual(decoded, policy)
        }
    }
}
