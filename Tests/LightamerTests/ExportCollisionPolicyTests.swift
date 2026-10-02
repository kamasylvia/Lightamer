import Foundation
import LightamerCore
import XCTest

/// M2-9-01 T3 — the collision three-tier face (OQ-5): the historical
/// increment default stays byte-identical (D-11-CONTEXT-4 扩档非换档),
/// `.fail` throws typed, `.replace` returns the occupied name. Case-
/// insensitive occupancy carries over to EVERY tier.
final class ExportCollisionPolicyTests: XCTestCase {

    private let directory = URL(fileURLWithPath: "/tmp/export-namer-policy")

    private func url(
        _ policy: ExportNamer.ExportCollisionPolicy?, stem: String = "photo",
        tag: String? = nil, ext: String = "jpg", occupied: Set<String> = []
    ) throws -> URL {
        if let policy {
            return try ExportNamer.destinationURL(
                directory: directory, stem: stem, tag: tag, ext: ext,
                occupiedNames: occupied, collisionPolicy: policy)
        }
        return ExportNamer.destinationURL(
            directory: directory, stem: stem, tag: tag, ext: ext,
            occupiedNames: occupied)
    }

    /// The DEFAULT-parameter overload is the `.increment` tier: same URL,
    /// same increment, same case-insensitive occupancy — the historical
    /// face untouched (ExportNamerTests stays zero-diff green as the
    /// byte-level proof; this pins the overload equality directly).
    func testDefaultOverloadEqualsIncrementTier() throws {
        let occupied: Set<String> = ["photo.jpg", "photo-1.jpg"]
        let viaDefault = ExportNamer.destinationURL(
            directory: directory, stem: "photo", tag: nil, ext: "jpg",
            occupiedNames: occupied)
        let viaIncrement = try url(
            .increment, occupied: occupied)
        XCTAssertEqual(viaDefault, viaIncrement)
        XCTAssertEqual(viaDefault.lastPathComponent, "photo-2.jpg")

        // Free target → the bare name, both faces.
        XCTAssertEqual(
            try url(nil), directory.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(
            try url(.increment), directory.appendingPathComponent("photo.jpg"))
    }

    /// `.fail` on a free name returns the base name; on an occupied base
    /// name it throws the typed error carrying the base NAME. The
    /// case-insensitive face: "PHOTO.JPG" on disk blocks "photo.jpg".
    func testFailTierTyped() throws {
        // Free → the base URL.
        XCTAssertEqual(
            try url(.fail), directory.appendingPathComponent("photo.jpg"))

        // Occupied → typed error.
        do {
            _ = try url(.fail, occupied: ["photo.jpg"])
            XCTFail("expected BaseNameOccupiedError")
        } catch let error as ExportNamer.BaseNameOccupiedError {
            XCTAssertEqual(error.name, "photo.jpg")
        }

        // Case-insensitive occupancy (D7 carries over to the new tiers).
        do {
            _ = try url(.fail, occupied: ["PHOTO.JPG"])
            XCTFail("expected BaseNameOccupiedError (case-insensitive)")
        } catch let error as ExportNamer.BaseNameOccupiedError {
            XCTAssertEqual(error.name, "photo.jpg", "the typed name is the BASE spelling")
        }

        // The tag participates in the base name (stem_tag.ext).
        let tagged = try url(.fail, tag: "print", occupied: ["photo_web.jpg"])
        XCTAssertEqual(tagged.lastPathComponent, "photo_print.jpg")
        do {
            _ = try url(.fail, tag: "web", occupied: ["photo_web.jpg"])
            XCTFail("expected BaseNameOccupiedError (tagged base)")
        } catch let error as ExportNamer.BaseNameOccupiedError {
            XCTAssertEqual(error.name, "photo_web.jpg")
        }
    }

    /// `.replace` returns the base name EVEN when occupied (the encoder
    /// overwrites it) — and stays case-preserving on the stem.
    func testReplaceTier() throws {
        let replaced = try url(
            .replace, stem: "Photo", occupied: ["photo.jpg", "other.png"])
        XCTAssertEqual(replaced.lastPathComponent, "Photo.jpg")
        XCTAssertEqual(
            replaced.deletingLastPathComponent().path, directory.path,
            "the directory joins verbatim")

        // A tag still prefixes the base name.
        let tagged = try url(.replace, tag: "print", occupied: ["photo_print.jpg"])
        XCTAssertEqual(tagged.lastPathComponent, "photo_print.jpg")
    }

    /// The policy type is Codable (recipe-mountable) with stable raw
    /// values; the enum IS the ExportNamer nested single source.
    func testPolicyCodableRoundTrip() throws {
        for policy in [
            ExportNamer.ExportCollisionPolicy.increment,
            .fail,
            .replace,
        ] {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(
                ExportNamer.ExportCollisionPolicy.self, from: data)
            XCTAssertEqual(decoded, policy, "\(policy.rawValue)")
        }
        XCTAssertEqual(ExportNamer.ExportCollisionPolicy.increment.rawValue, "increment")
    }

    /// The fail/replace tiers NEVER increment — the first free `-N` search
    /// is the increment tier's alone (a fail/replace caller cannot silently
    /// fan out -N copies).
    func testFailAndReplaceNeverIncrement() throws {
        let occupied: Set<String> = ["photo.jpg", "photo-1.jpg", "photo-2.jpg"]
        do {
            _ = try url(.fail, occupied: occupied)
            XCTFail("fail must not fall through to increments")
        } catch is ExportNamer.BaseNameOccupiedError {
            // expected
        }
        XCTAssertEqual(
            try url(.replace, occupied: occupied).lastPathComponent,
            "photo.jpg", "replace ignores every -N occupant")
    }
}
