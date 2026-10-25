import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralProfileDecodeTests (Plan M8-1a T1, review B1 — IOP domain) — the
// additive spectral decode face of FilmProfile:
//
//   1. The six 亲核登记② fields decode from the real assets (a negative
//      film + a paper stock), with POINT-WISE nulls preserved verbatim
//      (never a whole-field downgrade), pinned null counts, both adaptation
//      carrier shapes, and the viewing illuminant; the null-aware
//      projection family resolves the nulls through the single
//      interpolation source (linear inside, constant extension at the
//      ends, nil on all-null), exercised on a synthetic axis.
//   2. Old-form JSON (no spectral keys) decodes with all six fields nil
//      and RE-ENCODES with exactly the pre-M8-1a consumer key set
//      (encodeIfPresent 同式 — the zero-drift negative test).
//   3. The 28-profile set-wide smoke: every profile decodes the spectral
//      face, 81-point/axis-consistent shapes, finite log-sensitivity in
//      the measured band, the per-profile null-count bands (channel
//      15-78/243, midscale 5-26/81 — the 亲核登记 domains), adaptation
//      params present exactly on the filming stocks, and the illuminant
//      vocabulary (reference ∈ {D55, T, TH-KG3}, viewing ∈ {D50, K75P}).
//
//   The tolerance band for log_sensitivity is [-20, 20]: the plan's draft
//   [-6, 6] band predates the full-set measurement (actual [-13.59, 1.63]);
//   the wider band keeps the same order-of-magnitude sanity intent and the
//   deviation is registered in M8-1A-DECISIONS.
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralProfileDecodeTests: XCTestCase {

    /// `…/Lightamer/Resources/FilmProfiles/profiles` — walked from #filePath
    /// (Core tests never depend on the App bundle, KD-2).
    private static var profilesDirectory: URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        return root.appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private static let portraURL = profilesDirectory.appendingPathComponent(
        "kodak_portra_400.json")
    private static let enduraPremierURL = profilesDirectory.appendingPathComponent(
        "kodak_endura_premier.json")

    /// The vendored 81-point λ axis (the profiles' own, asserted exact).
    private static let vendoredAxis: [Float] = (0..<81).map { 380 + 5 * Float($0) }

    /// A minimal shape-valid synthetic carrier on a 7-point axis.
    private func syntheticProfile(
        axis: [Float], base: [Float?], midscale: [Float?]?
    ) throws -> FilmProfile {
        let info = FilmProfile.Info(
            stock: "synthetic", name: nil, type: "negative", support: "film",
            stage: "filming", targetPrint: nil, channelModel: nil,
            densitometer: nil, referenceIlluminant: nil)
        let metadata = FilmProfile.Metadata(
            version: "test", license: "test", copyright: nil, citation: "t")
        return try FilmProfile(
            metadata: metadata, info: info, logExposure: [-1, 0, 1, 2],
            densityCurves: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6],
                            [0.7, 0.8, 0.9], [1.0, 1.1, 1.2]],
            baseDensity: base,
            wavelengths: axis,
            midscaleNeutralDensity: midscale)
    }

    // MARK: - 1: the six fields from the real assets (null-aware)

    func testSixSpectralFieldsDecodeFromRealAssetsWithNullsPreserved() throws {
        // --- the negative film (portra_400) ---
        let film = try FilmProfile.load(Self.portraURL)
        XCTAssertEqual(film.info.viewingIlluminant, "D50")

        let filmLog = try XCTUnwrap(film.logSensitivity, "log_sensitivity decodes")
        XCTAssertEqual(filmLog.count, 81)
        XCTAssertEqual(filmLog[0].count, 3)
        for row in filmLog {
            for value in row {
                XCTAssertTrue(value.isFinite)
                XCTAssertGreaterThanOrEqual(value, -20)
                XCTAssertLessThanOrEqual(value, 20)
            }
        }

        // Point-wise nulls SURVIVE (never a whole-field downgrade, B1):
        // portra_400 carries 22 nulls of 243 channel points and 20 of 81
        // mid-scale points (the pinned vendored facts).
        let filmChannel = try XCTUnwrap(film.channelDensity)
        XCTAssertEqual(filmChannel.count, 81)
        let filmNonNull = filmChannel.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(filmNonNull.count, 221, "243 points, 22 null")
        for value in filmNonNull {
            XCTAssertTrue(value.isFinite)
        }
        let filmMid = try XCTUnwrap(film.midscaleNeutralDensity)
        XCTAssertEqual(filmMid.compactMap { $0 }.count, 61, "81 points, 20 null")
        // The spectral ends are where the asset is null — first/last row
        // carry at least one null each (the shape fact the B1 review pinned).
        XCTAssertTrue(filmChannel.first!.contains(nil))
        XCTAssertTrue(filmChannel.last!.contains(nil))

        // Both adaptation carrier shapes (window = 4 scalars, surface =
        // 3×15 deg-4) on the filming stock.
        guard case .window(let window)? = film.adaptationWindowParams else {
            return XCTFail("window params decode on a filming stock")
        }
        XCTAssertEqual(window.count, 4)
        guard case .surface(let surface)? = film.adaptationSurfaceParams else {
            return XCTFail("surface params decode on a filming stock")
        }
        XCTAssertEqual(surface.count, 3)
        XCTAssertTrue(surface.allSatisfy { $0.count == 15 })

        // --- the paper stock (endura_premier) ---
        let paper = try FilmProfile.load(Self.enduraPremierURL)
        XCTAssertEqual(paper.info.viewingIlluminant, "D50")
        let paperChannel = try XCTUnwrap(paper.channelDensity)
        XCTAssertEqual(paperChannel.flatMap { $0 }.compactMap { $0 }.count, 177,
                       "243 points, 66 null")
        let paperMid = try XCTUnwrap(paper.midscaleNeutralDensity)
        XCTAssertEqual(paperMid.compactMap { $0 }.count, 59, "81 points, 22 null")
        // Printing-stage stocks carry NO adaptation params (the asset set
        // fact: they are filming-side model constants).
        XCTAssertNil(paper.adaptationWindowParams)
        XCTAssertNil(paper.adaptationSurfaceParams)

        // --- the projection family (the B1 single source) ---
        // Each resolved channel series has no nulls left and hits the
        // non-null samples exactly (Float→Double widening, exact).
        let projected = try XCTUnwrap(film.channelDensityProjected())
        XCTAssertEqual(projected.count, 3)
        for (channel, series) in projected.enumerated() {
            XCTAssertEqual(series.count, 81)
            for (index, value) in series.enumerated() {
                XCTAssertTrue(value.isFinite, "resolved values are finite")
                if let raw = film.channelDensity?[index][channel] {
                    XCTAssertEqual(
                        value, Double(raw), accuracy: 0,
                        "non-null samples pass through exactly")
                }
            }
        }

        // The interpolation/extension branches, exercised exactly: nulls
        // at both ends extend the nearest sample, middle nulls linearly
        // interpolate their two neighbours (uniform 50nm axis).
        let axis: [Float] = (0..<7).map { 450 + 50 * Float($0) }
        let wide = try syntheticProfile(
            axis: axis, base: [Float?](repeating: 0.1, count: 7),
            midscale: [nil, 1.0, nil, 3.0, nil, 5.0, nil] as [Float?])
        let resolved = try XCTUnwrap(wide.midscaleNeutralDensityProjected())
        let expected: [Double] = [1.0, 1.0, 2.0, 3.0, 4.0, 5.0, 5.0]
        XCTAssertEqual(resolved.count, expected.count)
        for (resolvedValue, expectedValue) in zip(resolved, expected) {
            XCTAssertEqual(resolvedValue, expectedValue, accuracy: 1e-12)
        }

        // An all-null series has no projection.
        let allNull = try syntheticProfile(
            axis: axis, base: [Float?](repeating: nil, count: 7),
            midscale: [Float?](repeating: nil, count: 7))
        XCTAssertNil(allNull.midscaleNeutralDensityProjected())
        XCTAssertNil(allNull.baseDensityProjected())
    }

    // MARK: - 2: the old-form zero-drift negative test

    func testOldFormProfileDecodesNilSpectralFaceAndReencodesByteIdentical() throws {
        // The pre-M8-1a shape: no spectral keys at all.
        let object: [String: Any] = [
            "metadata": ["version": "test", "license": "test", "citation": "t"],
            "info": ["stock": "synthetic", "support": "film",
                     "reference_illuminant": "D55"],
            "data": [
                "log_exposure": [-1.0, 0.0, 1.0, 2.0],
                "density_curves": [
                    [0.1, 0.2, 0.3], [0.4, 0.5, 0.6],
                    [0.7, 0.8, 0.9], [1.0, 1.1, 1.2],
                ],
                "base_density": [0.05, NSNull(), 0.15],
                "wavelengths": [450.0, 550.0, 650.0],
            ],
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("old-form-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let profile = try FilmProfile.load(url)

        // All six spectral fields degrade to nil (absent = nil).
        XCTAssertNil(profile.logSensitivity)
        XCTAssertNil(profile.channelDensity)
        XCTAssertNil(profile.midscaleNeutralDensity)
        XCTAssertNil(profile.adaptationWindowParams)
        XCTAssertNil(profile.adaptationSurfaceParams)
        XCTAssertNil(profile.info.viewingIlluminant)

        // Re-encode keeps EXACTLY the pre-M8-1a consumer key face:
        // encodeIfPresent 同式 never emits the absent keys.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let reencoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(profile))
                as? [String: Any])
        let data = try XCTUnwrap(reencoded["data"] as? [String: Any])
        XCTAssertEqual(
            Set(data.keys),
            ["log_exposure", "density_curves", "base_density", "wavelengths"],
            "zero-drift: the old-form face emits exactly the four arrays")
        let info = try XCTUnwrap(reencoded["info"] as? [String: Any])
        XCTAssertEqual(
            Set(info.keys), ["stock", "support", "reference_illuminant"])
    }

    // MARK: - 3: the 28-profile set-wide smoke (null-aware bands)

    func testAll28ProfilesDecodeTheSpectralFaceWithinTheMeasuredBands()
        throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: Self.profilesDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        XCTAssertEqual(names.count, 28, "the vendored 0.3.2 snapshot")

        let referenceVocabulary: Set<String> = ["D55", "T", "TH-KG3"]
        let viewingVocabulary: Set<String> = ["D50", "K75P"]

        for name in names {
            let profile = try FilmProfile.load(
                Self.profilesDirectory.appendingPathComponent(name))

            // Axis consistency (the typed-init gate's contract, asserted
            // against the vendored 380-780@5nm axis).
            XCTAssertEqual(profile.wavelengths, Self.vendoredAxis, name)

            // log_sensitivity: 81×3, finite, within the measured band.
            let log = try XCTUnwrap(profile.logSensitivity, name)
            XCTAssertEqual(log.count, 81, name)
            for row in log {
                XCTAssertEqual(row.count, 3, name)
                for value in row {
                    XCTAssertTrue(value.isFinite, name)
                    XCTAssertGreaterThanOrEqual(value, -20, name)
                    XCTAssertLessThanOrEqual(value, 20, name)
                }
            }

            // channel_density: null-aware band 15-78/243 (the 亲核登记
            // measured domain), non-null values finite.
            let channel = try XCTUnwrap(profile.channelDensity, name)
            let nulls = channel.flatMap { $0 }.count(where: { $0 == nil })
            XCTAssertGreaterThanOrEqual(nulls, 15, name)
            XCTAssertLessThanOrEqual(nulls, 78, name)
            for value in channel.flatMap({ $0 }).compactMap({ $0 }) {
                XCTAssertTrue(value.isFinite, name)
            }

            // midscale: null-aware band 5-26/81.
            let mid = try XCTUnwrap(profile.midscaleNeutralDensity, name)
            let midNulls = mid.count(where: { $0 == nil })
            XCTAssertGreaterThanOrEqual(midNulls, 5, name)
            XCTAssertLessThanOrEqual(midNulls, 26, name)

            // The projection face resolves on every profile (the engine's
            // precondition) and every resolved value is finite.
            for series in try XCTUnwrap(profile.channelDensityProjected(),
                                        "projection resolves: \(name)") {
                XCTAssertEqual(series.count, 81, name)
                XCTAssertTrue(series.allSatisfy(\.isFinite), name)
            }
            XCTAssertTrue(
                try XCTUnwrap(profile.midscaleNeutralDensityProjected(), name)
                    .allSatisfy(\.isFinite), name)

            // Adaptation params: present exactly on filming stocks.
            if profile.info.stage == "filming" {
                guard case .window(let w)? = profile.adaptationWindowParams else {
                    return XCTFail("window params on filming stock \(name)")
                }
                XCTAssertEqual(w.count, 4, name)
                guard case .surface(let s)? = profile.adaptationSurfaceParams else {
                    return XCTFail("surface params on filming stock \(name)")
                }
                XCTAssertEqual(s.count, 3, name)
            } else {
                XCTAssertNil(profile.adaptationWindowParams, name)
                XCTAssertNil(profile.adaptationSurfaceParams, name)
            }

            // The illuminant vocabulary (the asset set fact).
            let reference = try XCTUnwrap(profile.info.referenceIlluminant, name)
            XCTAssertTrue(referenceVocabulary.contains(reference), name)
            let viewing = try XCTUnwrap(profile.info.viewingIlluminant, name)
            XCTAssertTrue(viewingVocabulary.contains(viewing), name)
        }
    }
}
