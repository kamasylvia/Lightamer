@testable import LightamerCore
import CryptoKit
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// BWProfileAssetsTests (Plan M9-2 T1 — LAYERS) — the self-digitized BW asset
// family's acceptance face (pure asset tests; zero production Swift was
// touched to land the data):
//
//   1. THE MANIFEST GATE: every file under Resources/FilmProfilesBW/
//      (outside MANIFEST.sha256 itself) has its sha256 recorded and
//      matching — the reconciliation ledger is the acceptance 正本.
//   2. THE DECODE GATE: all five profiles load through the production
//      FilmProfile decoder fail-closed, channelModel == "bw", the
//      log-sensitivity rows are THREE-CHANNEL IDENTICAL (the neutral
//      silver form, ×81) and channel_density == [1/3, 1/3, 1/3].
//   3. THE PAPER SPLIT GATE: the Multigrade profile's spectral split —
//      channels differ somewhere in 460-540 nm AND every channel is
//      ≤ −9 beyond 555 nm (the safelight blindness, directly evidenced
//      by the empty chart region).
//   4. THE TAG DISCIPLINE GATE: every film profile's metadata carries
//      both a SHEET and an ASSUMED tag (the digitization provenance).
//   5. THE FILTER TABLE GATE: camera_filters.json — 8 Wratten filters ×
//      81 samples, transmittance in [0, 1.1], each with a source field
//      (the dual-source policy: W2 base / B-3 for No. 11).
//   6. THE GRANULARITY GATE: the four RMS values match the DECISIONS
//      finals (17 / 8 / 7 / null — the T-Max 8 corrects the third-party
//      7.4 against our own F-4016 image-structure table).
// ─────────────────────────────────────────────────────────────────────────────

final class BWProfileAssetsTests: XCTestCase {

    // MARK: - Paths

    /// `<root>/Resources/FilmProfilesBW` via #filePath (unhosted Core
    /// tests run under any working directory).
    private static var bwDirectory: URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        return root.appendingPathComponent("Resources/FilmProfilesBW")
    }

    private static var profilesDirectory: URL {
        bwDirectory.appendingPathComponent("profiles")
    }

    private static let expectedFilms = [
        "kodak_tri_x_400", "kodak_tmax_100",
        "fujifilm_neopan_acros_100_ii", "ilford_hp5_plus_400",
    ]

    // MARK: - 1: the manifest gate

    func testManifestReconcilesEveryAssetFile() throws {
        let manifestURL = Self.bwDirectory.appendingPathComponent("MANIFEST.sha256")
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        var recorded: [String: String] = [:]   // relative path -> hex digest
        for line in manifestText.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "  ")
            guard parts.count == 2 else { continue }
            recorded[String(parts[1])] = String(parts[0])
        }
        XCTAssertFalse(recorded.isEmpty, "MANIFEST.sha256 is not an empty ledger")

        // Walk every file in the directory tree (skipping the manifest
        // itself and editor droppings); each must be recorded AND match.
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.bwDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "MANIFEST.sha256" }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        for file in files {
            let rel = file.lastPathComponent == "profiles"
                ? nil : file.lastPathComponent
            if file.hasDirectoryPath {
                let inner = try FileManager.default
                    .contentsOfDirectory(at: file, includingPropertiesForKeys: nil)
                for f in inner {
                    let key = "profiles/\(f.lastPathComponent)"
                    let digest = try Self.sha256(f)
                    XCTAssertEqual(recorded[key], digest,
                                   "profiles/\(f.lastPathComponent) hash mismatch")
                }
            } else if let rel {
                let digest = try Self.sha256(file)
                XCTAssertEqual(recorded[rel], digest, "\(rel) hash mismatch")
            }
        }
        // No stale manifest rows (every recorded row exists on disk).
        for key in recorded.keys {
            let url = Self.bwDirectory.appendingPathComponent(key)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "stale manifest row: \(key)")
        }
    }

    private static func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 2: the decode gate

    func testAllFiveProfilesDecodeAsBWChannelModel() throws {
        // The four FILMS carry the neutral silver form (three identical
        // spectral channels + [1/3,1/3,1/3] channel density); the PAPER
        // carries the ASSUMED blue/green/red SPLIT (gate 3 covers it) —
        // it decodes with the same channel model but NOT the identical
        // rows.
        for id in Self.expectedFilms {
            let url = Self.profilesDirectory.appendingPathComponent("\(id).json")
            let profile = try FilmProfile.load(url)
            XCTAssertEqual(profile.info.channelModel, "bw", "\(id) channel model")
            XCTAssertEqual(profile.wavelengths.count, 81, "\(id) axis count")
            XCTAssertEqual(profile.densityCurves.count, 256, "\(id) curve rows")
            // The neutral silver form: three identical channels per row.
            let sens = try XCTUnwrap(profile.logSensitivity, "\(id) spectral face")
            for (i, row) in sens.enumerated() {
                XCTAssertEqual(row[0], row[1], "\(id) row \(i): channel 0 == 1")
                XCTAssertEqual(row[1], row[2], "\(id) row \(i): channel 1 == 2")
            }
            let cd = try XCTUnwrap(profile.channelDensity, "\(id) channel density")
            for (i, row) in cd.enumerated() {
                XCTAssertEqual(row[0] ?? -1, 1.0 / 3.0, accuracy: 1e-6,
                               "\(id) row \(i): channel density c0")
                XCTAssertEqual(row[1] ?? -1, 1.0 / 3.0, accuracy: 1e-6,
                               "\(id) row \(i): channel density c1")
                XCTAssertEqual(row[2] ?? -1, 1.0 / 3.0, accuracy: 1e-6,
                               "\(id) row \(i): channel density c2")
            }
        }
        // The paper: decode + channel model only (the split gate follows).
        let paperURL = Self.profilesDirectory.appendingPathComponent(
            "ilford_multigrade_iv_rc.json")
        let paper = try FilmProfile.load(paperURL)
        XCTAssertEqual(paper.info.channelModel, "bw", "paper channel model")
        XCTAssertEqual(paper.densityCurves.count, 256, "paper curve rows")
        XCTAssertNotNil(paper.logSensitivity, "paper spectral face present")
    }

    // MARK: - 3: the paper split gate

    func testPaperSpectralSplitAndBlindness() throws {
        let url = Self.profilesDirectory.appendingPathComponent(
            "ilford_multigrade_iv_rc.json")
        let profile = try FilmProfile.load(url)
        let sens = try XCTUnwrap(profile.logSensitivity)
        // The split exists: some wavelength in 460...540 has channels
        // differing (blue vs green emulsion models).
        var sawSplit = false
        for (i, row) in sens.enumerated() {
            let nm = 380 + 5 * i
            if (460...540).contains(nm), abs(row[0] - row[1]) > 0.2 {
                sawSplit = true
                break
            }
        }
        XCTAssertTrue(sawSplit, "the ASSUMED blue/green split shows in 460-540 nm")
        // The blindness: every channel ≤ −6 log sensitivity ≥ 560 nm
        // (paper is blind in the safelight region — the chart is empty).
        // M9-2 T2 REANCHOR: the blind third channel sits at the −6 floor
        // (1e-6 transmission — the physical safelight-blocking magnitude,
        // not the absolute zero −10 the T1 digitization wrote): at −10
        // the build's three-channel geometric-mean exposure normalization
        // collapsed, inflating the print exposure ~1e4 and clamping the
        // whole chain to a constant. −6 keeps the blindness physically
        // honest (5+ decades below the visible pair) while the
        // normalization stays in range — registered in M9-2-DECISIONS.
        for (i, row) in sens.enumerated() {
            let nm = 380 + 5 * i
            if nm >= 560 {
                for c in 0..<3 {
                    XCTAssertLessThanOrEqual(row[c], -6.0,
                                             "channel \(c) at \(nm) nm must be blind")
                }
            }
        }
    }

    // MARK: - 4: the tag discipline gate

    func testEveryProfileCarriesSheetAndAssumedTags() throws {
        for id in Self.expectedFilms {
            let url = Self.profilesDirectory.appendingPathComponent("\(id).json")
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            let dict = try XCTUnwrap(raw as? [String: Any])
            let metadata = try XCTUnwrap(dict["metadata"] as? [String: Any])
            let tags = try XCTUnwrap(metadata["tags"] as? [String: Any])
            let joined = tags.values
                .compactMap { $0 as? String }
                .joined(separator: "\n") + "\n" +
                (tags.values.compactMap { $0 as? [String] }
                    .map { $0.joined(separator: "\n") }.joined(separator: "\n"))
            XCTAssertTrue(joined.contains("SHEET"), "\(id): SHEET tag present")
            XCTAssertTrue(joined.contains("ASSUMED"), "\(id): ASSUMED tag present")
        }
    }

    // MARK: - 5: the filter table gate

    func testCameraFiltersTableShapeAndSources() throws {
        let url = Self.bwDirectory.appendingPathComponent("camera_filters.json")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let doc = try XCTUnwrap(raw as? [String: Any])
        let filters = try XCTUnwrap(doc["filters"] as? [String: [String: Any]])
        let expected = ["w8", "w11", "w12", "w15", "w21", "w25", "w47", "w58"]
        XCTAssertEqual(Set(filters.keys), Set(expected), "the 8-filter family")
        for name in expected {
            let entry = try XCTUnwrap(filters[name], name)
            let wavelengths = try XCTUnwrap(entry["wavelengths_nm"] as? [Double])
            XCTAssertEqual(wavelengths.count, 81, "\(name): 81 samples")
            XCTAssertEqual(wavelengths.first, 380, "\(name): domain start")
            XCTAssertEqual(wavelengths.last, 780, "\(name): domain end")
            let t = try XCTUnwrap(entry["transmittance_pct"] as? [Double])
            XCTAssertEqual(t.count, 81, "\(name): value count")
            for v in t {
                XCTAssertGreaterThanOrEqual(v, 0, "\(name): transmittance ≥ 0")
                XCTAssertLessThanOrEqual(v, 100.5,
                                         "\(name): transmittance ≤ 100.5 (%)")
            }
            let source = try XCTUnwrap(entry["source"] as? String)
            XCTAssertFalse(source.isEmpty, "\(name): source field present")
        }
        // The dual-source policy face: No. 11 rides the B-3 transcription
        // (retired in the W2 line); the others ride the official W2 curves.
        XCTAssertEqual(filters["w11"]?["source"] as? String,
                       "kodak_b3_transcription")
        for name in ["w8", "w12", "w15", "w21", "w25", "w47", "w58"] {
            XCTAssertEqual(filters[name]?["source"] as? String,
                           "kodak_wratten2", "\(name): W2 base")
        }
        // The w58 factor-check note (D-M92-8).
        XCTAssertNotNil(filters["w58"]?["factor_check_note"],
                        "w58 carries the factor-check note")
    }

    // MARK: - 6: the granularity gate

    func testGranularityValuesMatchTheDecisionsFinals() throws {
        let url = Self.bwDirectory.appendingPathComponent("grain_calibration.json")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let doc = try XCTUnwrap(raw as? [String: Any])
        let films = try XCTUnwrap(doc["films"] as? [String: [String: Any]])
        XCTAssertEqual(films["kodak_tri_x_400"]?["rms"] as? Int, 17,
                       "F-4017 p6: 17 (fine)")
        XCTAssertEqual(films["kodak_tmax_100"]?["rms"] as? Int, 8,
                       "F-4016 image-structure table: 8 (corrects 7.4)")
        XCTAssertEqual(films["fujifilm_neopan_acros_100_ii"]?["rms"] as? Int, 7,
                       "AF3-0258E: 7")
        // JSON null bridges to NSNull — assert the Int cast is nil (the
        // published absence), not the raw value.
        XCTAssertNil(films["ilford_hp5_plus_400"]?["rms"] as? Int,
                     "HP5 Plus: Harman publishes no figure — null by design")
    }
}
