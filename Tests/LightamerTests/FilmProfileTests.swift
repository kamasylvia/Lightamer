import CommonCrypto
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmProfileTests (Plan M3-3-01 T2/T3, KD-2/KD-3 — LAYERS/Core level) —
//
//   T2 asset-integrity face (raw JSONSerialization — the typed loader does
//   not exist yet at this layer of the plan; the integrity contract must
//   hold independent of any Swift type):
//     1. MANIFEST.sha256 reconciles EVERY file it lists, and the manifest
//        covers the whole asset set (LICENSE + 28 profiles + the neutral
//        print-filter table) — full reconciliation, never sampling
//        (checker ①: the asset-integrity true chain).
//     2. Profile count = 28 with the film/paper split pinned to the
//        vendored snapshot (22 film / 6 paper by info.support).
//     3. Every profile's metadata.license names CC BY-SA 4.0 and
//        metadata.version = the vendored 0.3.2.
//     4. neutral_print_filters.json shape: 8 paper stocks × TH-KG3 head ×
//        film entries, [C, M, Y] triplets with C ≡ 0, and the two sanity
//        named combos present with the measured values the solver band
//        (T5) centers on.
//
//   The directory is located via #filePath (walk to the repo root) — Core
//   tests never depend on the App bundle (KD-2).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmProfileTests: XCTestCase {

    // MARK: - Paths

    /// `…/Lightamer/Resources/FilmProfiles` — walked from #filePath so the
    /// suite runs under any working directory (Core tests are not hosted
    /// by the App bundle).
    private static var filmProfilesDirectory: URL {
        // <root>/Tests/LightamerTests/FilmProfileTests.swift → <root>
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        return root.appendingPathComponent("Resources/FilmProfiles")
    }

    private static var profilesDirectory: URL {
        filmProfilesDirectory.appendingPathComponent("profiles")
    }

    private static func json(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "not a JSON object: \(url.lastPathComponent)")
    }

    // MARK: - 1: the MANIFEST reconciliation (full, not sampled)

    func testManifestReconcilesEveryListedFileByteForByte() throws {
        let manifestURL = Self.filmProfilesDirectory
            .appendingPathComponent("MANIFEST.sha256")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let lines = manifest.split(separator: "\n").filter { !$0.isEmpty }

        var checked = 0
        for line in lines {
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else {
                XCTFail("malformed manifest line: \(line)")
                continue
            }
            let expected = String(parts[0])
            let relative = line
                .drop(while: { $0 == " " })
                .dropFirst(64) // hash + two separator chars
                .drop(while: { $0 == " " })
            let fileURL = Self.filmProfilesDirectory.appendingPathComponent(
                String(relative))
            let data = try Data(contentsOf: fileURL)
            let digest = SHA256Hex.of(data)
            XCTAssertEqual(
                digest, expected,
                "asset byte drift: \(relative) — CC BY-SA files are never "
                    + "edited in place; re-vendor with a CHANGELOG entry")
            checked += 1
        }
        XCTAssertEqual(
            checked, 30,
            "manifest covers LICENSE + 28 profiles + neutral_print_filters")
    }

    func testManifestCoversTheWholeAssetTree() throws {
        // The inverse direction: every asset file in the directory IS
        // listed (no orphan asset outside the reconciliation set).
        let manifestURL = Self.filmProfilesDirectory
            .appendingPathComponent("MANIFEST.sha256")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let listed = Set(manifest.split(separator: "\n").map { line in
            String(line.drop(while: { $0 == " " }).dropFirst(64)
                .drop(while: { $0 == " " }))
        })

        var present: Set<String> = ["LICENSE"]
        for name in try FileManager.default.contentsOfDirectory(
            atPath: Self.filmProfilesDirectory.path)
        where !name.hasSuffix(".sha256") && name != "NOTICE"
            && name != "CHANGELOG.md" && !name.hasPrefix("profiles") {
            present.insert(name)
        }
        for name in try FileManager.default.contentsOfDirectory(
            atPath: Self.profilesDirectory.path) {
            present.insert("profiles/\(name)")
        }
        XCTAssertEqual(present, listed, "manifest and tree must match exactly")
    }

    // MARK: - 2: profile inventory

    func testProfileCountIs28WithTheVendoredFilmPaperSplit() throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: Self.profilesDirectory.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertEqual(names.count, 28, "the vendored 0.3.2 snapshot")

        var film = 0
        var paper = 0
        for name in names {
            let object = try Self.json(
                at: Self.profilesDirectory.appendingPathComponent(name))
            let info = try XCTUnwrap(object["info"] as? [String: Any])
            let support = try XCTUnwrap(info["support"] as? String)
            if support == "film" { film += 1 } else if support == "paper" {
                paper += 1
            } else {
                XCTFail("unknown support \(support) in \(name)")
            }
        }
        XCTAssertEqual(film, 22, "film stocks in the vendored snapshot")
        XCTAssertEqual(paper, 6, "paper stocks in the vendored snapshot")
    }

    // MARK: - 3: license + version fields

    func testEveryProfileNamesCcBySaAndTheVendoredVersion() throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: Self.profilesDirectory.path)
            .filter { $0.hasSuffix(".json") }
        for name in names {
            let object = try Self.json(
                at: Self.profilesDirectory.appendingPathComponent(name))
            let metadata = try XCTUnwrap(
                object["metadata"] as? [String: Any], name)
            let license = try XCTUnwrap(
                metadata["license"] as? String, name)
            XCTAssertTrue(
                license.contains("CC BY-SA 4.0"),
                "\(name) metadata.license must name CC BY-SA 4.0")
            XCTAssertTrue(
                license.contains("andreavolpato/spektrafilm"),
                "\(name) metadata.license must link the canonical source")
            let version = try XCTUnwrap(metadata["version"] as? String, name)
            XCTAssertEqual(version, "0.3.2", "the vendored snapshot version")
            let citation = try XCTUnwrap(metadata["citation"] as? String, name)
            XCTAssertTrue(citation.contains("spektrafilm"), name)
        }
    }

    // MARK: - 4: the neutral print-filter table

    func testNeutralPrintFilterTableShapeAndNamedCombos() throws {
        let object = try Self.json(
            at: Self.filmProfilesDirectory
                .appendingPathComponent("neutral_print_filters.json"))

        // 8 paper stocks, each under a TH-KG3 head key, each mapping film
        // stock → [C, M, Y] CC triplets.
        var combos = 0
        for (paper, heads) in object {
            let headsDict = try XCTUnwrap(heads as? [String: Any], paper)
            let head = try XCTUnwrap(
                headsDict["TH-KG3"] as? [String: Any],
                "\(paper): TH-KG3 head expected")
            for (filmStock, triplet) in head {
                let values = try XCTUnwrap(triplet as? [Double], filmStock)
                XCTAssertEqual(values.count, 3, filmStock)
                XCTAssertEqual(
                    values[0], 0.0, accuracy: 1e-9,
                    "C is neutral-fixed at 0 for every combo (\(filmStock))")
                combos += 1
            }
        }
        XCTAssertEqual(combos, 160, "the measured combination table")

        // The two solver-sanity named combos (T5's band centers), verbatim
        // measured values from the vendored table.
        let endura = try XCTUnwrap(
            (object["kodak_portra_endura"] as? [String: Any])?["TH-KG3"]
                as? [String: Any])
        let portra = try XCTUnwrap(
            endura["kodak_portra_400"] as? [Double],
            "portra_400 × portra_endura named combo")
        XCTAssertEqual(portra[0], 0.0, accuracy: 1e-9)
        XCTAssertEqual(portra[1], 51.56801468495496, accuracy: 1e-6)
        XCTAssertEqual(portra[2], 52.53400422349596, accuracy: 1e-6)

        let ultra = try XCTUnwrap(
            (object["kodak_ultra_endura"] as? [String: Any])?["TH-KG3"]
                as? [String: Any])
        let ektar = try XCTUnwrap(
            ultra["kodak_ektar_100"] as? [Double],
            "ektar_100 × ultra_endura named combo")
        XCTAssertEqual(ektar[0], 0.0, accuracy: 1e-9)
        XCTAssertEqual(ektar[1], 71.21744659598852, accuracy: 1e-6)
        XCTAssertEqual(ektar[2], 55.58437666939118, accuracy: 1e-6)
    }
}

/// Hex SHA-256 (the MANIFEST format) — CryptoKit-free one-file helper so
/// the integrity check has no dependency beyond Foundation/CommonCrypto.
private enum SHA256Hex {
    static func of(_ data: Data) -> String {
        // CommonCrypto CC_SHA256 (system libcrypto is not linked into the
        // test bundles; CommonCrypto ships with libSystem).
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(
                buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
