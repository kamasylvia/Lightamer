import CommonCrypto
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmProfileTests (Plan M3-3-01 T2/T3, KD-2/KD-3 — LAYERS/Core level) —
//
//   T2 asset-integrity face (raw JSONSerialization — the integrity
//   contract holds independent of any Swift type):
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
//   T3 typed-loader face (FilmProfile):
//     5. Real film/paper assets decode with the consumer info face
//        (support/stage/densitometer/target_print) and the density-domain
//        shapes (256×3 curves, 81-point axis, the nullable film mask).
//     6. Re-encoding emits ONLY the consumer keys — the spectral payload
//        never enters the type face (the licensing mechanism, verified
//        mechanically).
//     7. Shape violations and unreadable/malformed files fail CLOSED with
//        the typed errors.
//     8. The registered base-density projection (E2): nearest-neighbour
//        λ sampling lands the portra_400 orange-mask constants, the paper
//        Dmin constants, and fails closed on nil/mis-shaped arrays.
//     9. Set-wide invariants: status_M (film) vs status_A (paper) across
//        all 28 (the m3 mixed-domain registration fact) and strictly
//        ascending λ axes.
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

    // MARK: - T3: the typed loader (real assets)

    private static let portraURL = profilesDirectory.appendingPathComponent(
        "kodak_portra_400.json")
    private static let enduraURL = profilesDirectory.appendingPathComponent(
        "kodak_portra_endura.json")

    func testFilmAssetDecodesWithTheConsumerFaces() throws {
        let profile = try FilmProfile.load(Self.portraURL)
        XCTAssertEqual(profile.info.stock, "kodak_portra_400")
        XCTAssertEqual(profile.info.support, "film")
        XCTAssertEqual(profile.info.stage, "filming")
        XCTAssertEqual(profile.info.densitometer, "status_M")
        XCTAssertEqual(profile.info.targetPrint, "kodak_portra_endura")
        XCTAssertEqual(profile.metadata.version, "0.3.2")
        // Density-domain shapes (the E2-consumed arrays).
        XCTAssertEqual(profile.logExposure.count, 256)
        XCTAssertEqual(profile.densityCurves.count, 256)
        XCTAssertEqual(profile.densityCurves[0].count, 3)
        XCTAssertEqual(profile.baseDensity.count, 81)
        XCTAssertEqual(profile.wavelengths.count, 81)
        // The film-side orange-mask array is nullable at the spectral
        // ends: 61 of 81 sampled, null leading 4 + trailing 16 (the E2
        // field fact, pinned so a re-vendor can't shift it silently).
        let nonNil = profile.baseDensity.compactMap { $0 }
        XCTAssertEqual(nonNil.count, 61)
        for index in 0..<4 {
            XCTAssertNil(profile.baseDensity[index], "leading 380-395nm null")
        }
        for index in 65..<81 {
            XCTAssertNil(profile.baseDensity[index], "trailing 705-780nm null")
        }
        XCTAssertEqual(profile.wavelengths.first, 380.0)
        XCTAssertEqual(profile.wavelengths.last, 780.0)
    }

    func testPaperAssetDecodesAndCarriesStatusADmin() throws {
        let profile = try FilmProfile.load(Self.enduraURL)
        XCTAssertEqual(profile.info.stock, "kodak_portra_endura")
        XCTAssertEqual(profile.info.support, "paper")
        XCTAssertEqual(profile.info.stage, "printing")
        XCTAssertEqual(profile.info.densitometer, "status_A")
        XCTAssertNil(profile.info.targetPrint, "paper profiles target nothing")
        // The paper-side Dmin array is dense: all 81 sampled, ~0.09.
        XCTAssertNil(profile.baseDensity.first { $0 == nil })
        let dmin = try profile.baseDensityProjection()
        XCTAssertGreaterThan(dmin.r, 0.05)
        XCTAssertLessThan(dmin.r, 0.15)
    }

    func testReencodingEmitsOnlyTheConsumerKeys() throws {
        // The licensing mechanism, verified mechanically: decode the real
        // asset, re-encode, and the emitted key set is the consumer face
        // only — the spectral payloads stay OUT of the type (and any
        // re-serialization can never leak them back).
        let profile = try FilmProfile.load(Self.portraURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(profile))
                as? [String: Any])

        XCTAssertEqual(
            Set(object.keys), ["metadata", "info", "data"],
            "the emitted document has only the three consumer sections")
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])
        XCTAssertEqual(
            Set(metadata.keys),
            ["version", "license", "copyright", "citation"])
        let info = try XCTUnwrap(object["info"] as? [String: Any])
        XCTAssertEqual(
            Set(info.keys),
            ["stock", "name", "type", "support", "stage", "target_print",
             "channel_model", "densitometer", "reference_illuminant"])
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(
            Set(data.keys),
            ["log_exposure", "density_curves", "base_density", "wavelengths"],
            "the data face carries the four consumed arrays only")
        XCTAssertFalse(
            data.keys.contains("log_sensitivity")
                || data.keys.contains("channel_density")
                || data.keys.contains("density_curves_layers"),
            "the spectral/layer payloads stay outside the type face")
    }

    // MARK: - T3: fail-closed validation

    private func writeTemporaryProfile(_ object: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("film-profile-\(UUID().uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A minimal shape-valid synthetic profile: 4 exposure points × 3
    /// channels, 3-point dense axis (payload nested under `data`, the
    /// on-disk grouping).
    private func syntheticValidObject() -> [String: Any] {
        [
            "metadata": ["version": "test", "license": "test", "citation": "t"],
            "info": ["stock": "synthetic", "support": "film"],
            "data": [
                "log_exposure": [-1.0, 0.0, 1.0, 2.0],
                "density_curves": [
                    [0.1, 0.2, 0.3], [0.4, 0.5, 0.6],
                    [0.7, 0.8, 0.9], [1.0, 1.1, 1.2],
                ],
                "base_density": [0.05, 0.10, 0.15],
                "wavelengths": [450.0, 550.0, 650.0],
            ],
        ]
    }

    func testCurveShapeMismatchesAreTypedRejects() throws {
        var object = syntheticValidObject()
        mutateData(&object, "log_exposure", [-1.0, 0.0]) // 2 vs 4 rows
        XCTAssertThrowsError(
            try FilmProfile.load(try writeTemporaryProfile(object)), "row count"
        ) {
            XCTAssertEqual(
                $0 as? FilmProfileError,
                .curveShapeMismatch(expected: 2, actual: 4))
        }

        object = syntheticValidObject()
        mutateData(&object, "density_curves", [
            [0.1, 0.2, 0.3], [0.4, 0.5], [0.7, 0.8, 0.9], [1.0, 1.1, 1.2],
        ]) // one ragged row
        XCTAssertThrowsError(
            try FilmProfile.load(try writeTemporaryProfile(object)), "row width"
        ) {
            XCTAssertEqual($0 as? FilmProfileError, .curveShapeMismatch(
                expected: 3, actual: 2))
        }

        object = syntheticValidObject()
        mutateData(&object, "base_density", [0.05, 0.10]) // 2 vs 3 axis points
        XCTAssertThrowsError(
            try FilmProfile.load(try writeTemporaryProfile(object)), "axis length"
        ) {
            XCTAssertEqual($0 as? FilmProfileError, .curveShapeMismatch(
                expected: 3, actual: 2))
        }
    }

    /// Set a nested `data` payload key (the on-disk grouping).
    private func mutateData(
        _ object: inout [String: Any], _ key: String, _ value: Any
    ) {
        var data = (object["data"] as? [String: Any]) ?? [:]
        data[key] = value
        object["data"] = data
    }

    func testUnreadableAndMalformedFilesFailClosed() throws {
        XCTAssertThrowsError(
            try FilmProfile.load(
                Self.profilesDirectory.appendingPathComponent("no_such.json"))
        ) {
            XCTAssertEqual($0 as? FilmProfileError, .fileUnreadable)
        }
        let garbage = FileManager.default.temporaryDirectory
            .appendingPathComponent("garbage-\(UUID().uuidString).json")
        try Data("{{not json".utf8).write(to: garbage)
        addTeardownBlock { try? FileManager.default.removeItem(at: garbage) }
        XCTAssertThrowsError(try FilmProfile.load(garbage)) { error in
            guard case FilmProfileError.schemaMismatch = error else {
                return XCTFail("expected schemaMismatch, got \(error)")
            }
        }
    }

    func testNonAscendingAxisIsTypedRejected() throws {
        var object = syntheticValidObject()
        mutateData(&object, "wavelengths", [550.0, 450.0, 650.0])
        XCTAssertThrowsError(
            try FilmProfile.load(try writeTemporaryProfile(object))
        ) {
            guard case FilmProfileError.schemaMismatch = $0 else {
                return XCTFail("expected schemaMismatch, got \($0)")
            }
        }
    }

    // MARK: - T3: the registered base-density projection (E2)

    func testProjectionLandsThePortraOrangeMaskConstants() throws {
        let profile = try FilmProfile.load(Self.portraURL)
        let base = try profile.baseDensityProjection()
        // The E2-registered values (the orange-mask physicality
        // self-check: blue-leaning mask — R sample lowest, B highest).
        XCTAssertEqual(base.r, 0.19455455664304927, accuracy: 1e-6)
        XCTAssertEqual(base.g, 0.6023983915617849, accuracy: 1e-6)
        XCTAssertEqual(base.b, 0.815047516822333, accuracy: 1e-6)
    }

    func testProjectionPicksNearestNeighbourOnOffGridTargets() throws {
        // An off-grid axis [451, 549, 649]: each calibration target snaps
        // to its nearest axis point (650→649, 550→549, 450→451) — no
        // hard-coded 5nm-grid assumption (the E2 ruling).
        var object = syntheticValidObject()
        mutateData(&object, "wavelengths", [451.0, 549.0, 649.0])
        mutateData(&object, "base_density", [0.45, 0.55, 0.65])
        let profile = try FilmProfile.load(
            try writeTemporaryProfile(object))
        let base = try profile.baseDensityProjection()
        // Float32 storage exactness (the arrays are the on-disk Floats;
        // the widening is exact, the literals below are not).
        XCTAssertEqual(base.r, Double(Float(0.65)), accuracy: 0)
        XCTAssertEqual(base.g, Double(Float(0.55)), accuracy: 0)
        XCTAssertEqual(base.b, Double(Float(0.45)), accuracy: 0)
    }

    func testProjectionFailsClosedOnNilSamplesAndNilOnlyAxes() throws {
        // nil AT a calibration point → typed fail-closed (never default 0).
        var object = syntheticValidObject()
        mutateData(&object, "base_density", [0.45, NSNull(), 0.65])
        let nilProfile = try FilmProfile.load(
            try writeTemporaryProfile(object))
        XCTAssertThrowsError(try nilProfile.baseDensityProjection()) { error in
            XCTAssertEqual(
                error as? FilmProfileError,
                .baseProjectionUnavailable(wavelength: 550.0))
        }

        // A single-point axis with a nil sample: the red query (sampled
        // first) fails closed on its own wavelength.
        object = syntheticValidObject()
        mutateData(&object, "wavelengths", [400.0])
        mutateData(&object, "base_density", [NSNull()])
        let single = try FilmProfile.load(
            try writeTemporaryProfile(object))
        XCTAssertThrowsError(try single.baseDensityProjection()) { error in
            XCTAssertEqual(
                error as? FilmProfileError,
                .baseProjectionUnavailable(wavelength: 650.0))
        }
    }

    // MARK: - T3: set-wide invariants (the m3 registration facts)

    func testDensitometerDomainsAcrossTheVendoredSet() throws {
        // The m3 boundary fact, machine-checked across the whole set at
        // its ACTUAL granularity (the plan's coarse "film=status_M /
        // paper=status_A" note refined by the vendored snapshot):
        //   paper                    → status_A (6/6);
        //   film, type=positive      → status_A (the 4 slide stocks);
        //   film, type=negative      → status_M — EXCEPT kodak_2383/2393,
        //     the two PRINT-film stocks (status_A — they back the print
        //     path, not the negative path; registered in DECISIONS).
        let printFilmStocks: Set<String> = ["kodak_2383", "kodak_2393"]
        let names = try FileManager.default.contentsOfDirectory(
            atPath: Self.profilesDirectory.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertEqual(names.count, 28)
        for name in names {
            let profile = try FilmProfile.load(
                Self.profilesDirectory.appendingPathComponent(name))
            let stock = try XCTUnwrap(profile.info.stock, name)
            switch (profile.info.support, profile.info.type) {
            case ("paper", _):
                XCTAssertEqual(profile.info.densitometer, "status_A", name)
            case ("film", "negative") where !printFilmStocks.contains(stock):
                XCTAssertEqual(profile.info.densitometer, "status_M", name)
            default:
                XCTAssertEqual(profile.info.densitometer, "status_A", name)
            }
        }
    }

    func testEveryAssetAxisPassesTheAscendingValidation() throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: Self.profilesDirectory.path)
            .filter { $0.hasSuffix(".json") }
        for name in names {
            let profile = try FilmProfile.load(
                Self.profilesDirectory.appendingPathComponent(name))
            XCTAssertEqual(profile.wavelengths.count, 81, name)
            XCTAssertEqual(profile.wavelengths.first, 380.0, name)
            XCTAssertEqual(profile.wavelengths.last, 780.0, name)
            // Every sampled base-density value is finite.
            for sample in profile.baseDensity.compactMap({ $0 }) {
                XCTAssertTrue(sample.isFinite, name)
            }
        }
    }

    // MARK: - T4: FilmMaterialStore (KD-4)

    func testRealDirectoryIndexesTheVendoredSplitDeterministically() throws {
        let store = try FilmMaterialStore(
            profilesDirectory: Self.profilesDirectory)
        let films = store.filmStocks()
        let papers = store.paperStocks()
        XCTAssertEqual(films.count, 22)
        XCTAssertEqual(papers.count, 6)
        // Deterministic id-sorted order (menu/UI face).
        XCTAssertEqual(
            films.map(\.info.stock), films.map(\.info.stock!).sorted())
        XCTAssertEqual(
            papers.map(\.info.stock), papers.map(\.info.stock!).sorted())
        // The id lookup resolves both ways.
        XCTAssertEqual(
            store.profile(id: "kodak_portra_400")?.info.name,
            "Kodak Portra 400")
        XCTAssertNil(store.profile(id: "no_such_stock"))
        XCTAssertTrue(films.allSatisfy { $0.info.support == "film" })
        XCTAssertTrue(papers.allSatisfy { $0.info.support == "paper" })
    }

    func testMaterialPairHashIsStableWithAMovingDifferenceFace() throws {
        let store = try FilmMaterialStore(
            profilesDirectory: Self.profilesDirectory)
        let portra = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let ektar = try XCTUnwrap(store.profile(id: "kodak_ektar_100"))
        let endura = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let ultra = try XCTUnwrap(store.profile(id: "kodak_ultra_endura"))

        // Determinism: the same pair hashes identically (and the hash
        // function is pure static — no instance state can leak in).
        XCTAssertEqual(
            FilmMaterialStore.materialPairHash(film: portra, paper: endura),
            FilmMaterialStore.materialPairHash(film: portra, paper: endura))
        // Fresh store instances over the same directory agree (load order
        // cannot influence the identity).
        let store2 = try FilmMaterialStore(
            profilesDirectory: Self.profilesDirectory)
        XCTAssertEqual(
            FilmMaterialStore.materialPairHash(
                film: store.profile(id: "kodak_portra_400")!,
                paper: store.profile(id: "kodak_portra_endura")!),
            FilmMaterialStore.materialPairHash(
                film: store2.profile(id: "kodak_portra_400")!,
                paper: store2.profile(id: "kodak_portra_endura")!))
        // Difference face: film change, paper change and operand order
        // each move the hash (set-fields-move).
        let portraEndura = FilmMaterialStore.materialPairHash(
            film: portra, paper: endura)
        XCTAssertNotEqual(
            portraEndura,
            FilmMaterialStore.materialPairHash(film: ektar, paper: endura))
        XCTAssertNotEqual(
            portraEndura,
            FilmMaterialStore.materialPairHash(film: portra, paper: ultra))
        XCTAssertNotEqual(
            portraEndura,
            FilmMaterialStore.materialPairHash(film: endura, paper: portra))
    }

    func testMaterialPairHashMatchesTheDocumentedFoldFormula() throws {
        // Independent re-derivation of the documented formula over a tiny
        // synthetic pair (the same independent-formula discipline as the
        // FilmRecord stableHash check): stock UTF-8 ‖ log_exposure bits ‖
        // density_curves bits ‖ base_density tag+bits ‖ wavelengths bits,
        // film then paper, FNV-1a over platform-order UInt64 folds.
        var objectA = syntheticValidObject()
        mutateData(&objectA, "wavelengths", [450.0, 550.0, 650.0])
        let a = try FilmProfile.load(try writeTemporaryProfile(objectA))
        var objectB = syntheticValidObject()
        mutateData(&objectB, "wavelengths", [460.0, 560.0, 660.0])
        mutateData(&objectB, "base_density", [0.15, 0.10, 0.05])
        if var info = objectB["info"] as? [String: Any] {
            info["stock"] = "synthetic_paper"
            info["support"] = "paper"
            objectB["info"] = info
        }
        let b = try FilmProfile.load(try writeTemporaryProfile(objectB))

        var expected = StableHash.fnvOffsetBasis
        for profile in [a, b] {
            for byte in (profile.info.stock ?? "").utf8 {
                withUnsafeBytes(of: byte) {
                    expected = StableHash.combine(expected, $0)
                }
            }
            for value in profile.logExposure {
                var v = UInt64(value.bitPattern)
                withUnsafeBytes(of: &v) {
                    expected = StableHash.combine(expected, $0)
                }
            }
            for row in profile.densityCurves {
                for value in row {
                    var v = UInt64(value.bitPattern)
                    withUnsafeBytes(of: &v) {
                        expected = StableHash.combine(expected, $0)
                    }
                }
            }
            for sample in profile.baseDensity {
                if let value = sample {
                    var tag = UInt64(1)
                    withUnsafeBytes(of: &tag) {
                        expected = StableHash.combine(expected, $0)
                    }
                    var v = UInt64(value.bitPattern)
                    withUnsafeBytes(of: &v) {
                        expected = StableHash.combine(expected, $0)
                    }
                } else {
                    var tag = UInt64(0)
                    withUnsafeBytes(of: &tag) {
                        expected = StableHash.combine(expected, $0)
                    }
                }
            }
            for value in profile.wavelengths {
                var v = UInt64(value.bitPattern)
                withUnsafeBytes(of: &v) {
                    expected = StableHash.combine(expected, $0)
                }
            }
        }
        XCTAssertEqual(
            FilmMaterialStore.materialPairHash(film: a, paper: b), expected)
    }

    func testDuplicateAndMissingStockIdsAreTypedRejected() throws {
        // Two files claiming one stock id.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("film-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.json", "b.json"] {
            let data = try JSONSerialization.data(
                withJSONObject: syntheticValidObject())
            try data.write(to: dir.appendingPathComponent(name))
        }
        XCTAssertThrowsError(try FilmMaterialStore(profilesDirectory: dir)) {
            XCTAssertEqual(
                $0 as? FilmMaterialStoreError, .duplicateStockId("synthetic"))
        }

        // A file with no info.stock.
        let dir2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("film-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir2, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir2) }
        var noStock = syntheticValidObject()
        var info = (noStock["info"] as? [String: Any]) ?? [:]
        info.removeValue(forKey: "stock")
        noStock["info"] = info
        let data = try JSONSerialization.data(withJSONObject: noStock)
        try data.write(to: dir2.appendingPathComponent("a.json"))
        XCTAssertThrowsError(try FilmMaterialStore(profilesDirectory: dir2)) {
            XCTAssertEqual(
                $0 as? FilmMaterialStoreError,
                .missingStockId("a.json"))
        }
    }

    func testUnreadableDirectoryIsTypedRejected() {
        XCTAssertThrowsError(
            try FilmMaterialStore(
                profilesDirectory: URL(
                    fileURLWithPath: "/no/such/film/dir-\(UUID().uuidString)"))
        ) {
            XCTAssertEqual(
                $0 as? FilmMaterialStoreError, .directoryUnreadable)
        }
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
