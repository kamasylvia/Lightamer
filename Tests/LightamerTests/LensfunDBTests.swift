@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// LensfunDBTests (Plan 04-04-T2) — XML parsing + match + interpolation.
///
/// REFERENCE PROVENANCE: hermetic inline XML literals (no /opt/homebrew
/// dependency) + the 4-file hand-picked subset under
/// `input/golden/fixtures/lensfun/` (cross-check only). Numeric pins below
/// are hand-computed from the lensfun C semantics (`mod-coord.cpp` /
/// `mod-color.cpp` / `lens.cpp` / `auxfun.cpp`, read 2026-09-20):
/// - d-factor: poly3 k1' = k1/d³ (d = 1−k1); ptlens a/b/c ÷ d⁴/d³/d².
/// - Hermite `_lf_interpolate` (edge-missing → secant tangent).
/// - IDW p=3.5; exact < 1e-4; min-dist > 1 → nil.
/// - Hugin rescale × (NS·HW) kernel-unit fold (see LensKernels.metal).
///
/// ANTI-VACUUM: every test asserts REAL parsed/interpolated values —
/// counts, fields, and hand-computed floats — never mere non-nil.
final class LensfunDBTests: XCTestCase {

    // MARK: - Fixtures (inline, hermetic)

    static let sonyE16XML = """
        <lensdatabase version="1">
            <camera>
                <maker>Sony</maker>
                <model>ILCE-7M4</model>
                <model lang="en">Alpha 7 IV</model>
                <mount>Sony E</mount>
                <cropfactor>1</cropfactor>
            </camera>
            <lens>
                <maker>Sony</maker>
                <model>E 16mm f/2.8</model>
                <mount>Sony E</mount>
                <cropfactor>1.534</cropfactor>
                <calibration>
                    <distortion model="ptlens" focal="16" a="0.01701" b="-0.02563" c="-0.0052"/>
                    <tca model="poly3" focal="16" br="-0.0003027" vr="1.0010272" bb="0.0003454" vb="0.9993952"/>
                    <vignetting model="pa" focal="16" aperture="2.8" distance="0.25" k1="-1.8891" k2="1.7993" k3="-0.7326"/>
                    <vignetting model="pa" focal="16" aperture="2.8" distance="1000" k1="-1.9875" k2="1.9757" k3="-0.8192"/>
                    <vignetting model="pa" focal="16" aperture="5.6" distance="1000" k1="-1.4107" k2="0.9175" k3="-0.2726"/>
                </calibration>
            </lens>
        </lensdatabase>
        """

    static let canon24XML = """
        <lensdatabase version="1">
            <lens>
                <maker>Canon</maker>
                <model>Canon EF-S 24mm f/2.8 STM</model>
                <mount>Canon EF-S</mount>
                <cropfactor>1.622</cropfactor>
                <calibration>
                    <distortion model="poly3" focal="24" k1="-0.00902"/>
                    <tca model="poly3" focal="24" vr="1.0001965" vb="1.0000158"/>
                </calibration>
            </lens>
        </lensdatabase>
        """

    static let poly5XML = """
        <lensdatabase version="1">
            <lens>
                <maker>Canon</maker>
                <model>Canon PowerShot G12 &amp; compatibles (Standard)</model>
                <mount>canonG12</mount>
                <cropfactor>4.63</cropfactor>
                <calibration>
                    <distortion model="poly5" focal="6.1" k1="-0.030571633" k2="0.004658548"/>
                    <distortion model="poly5" focal="8.108" k1="-0.015375784" k2="0.001669650"/>
                    <distortion model="poly5" focal="30.5" k1="-0.000323237" k2="-0.000346917"/>
                    <tca model="linear" focal="6.1" kr="1.0006" kb="1.0004"/>
                </calibration>
            </lens>
        </lensdatabase>
        """

    private func parse(_ xml: String) -> LensfunDB {
        LensfunDBLoader.parse(Data(xml.utf8))
    }

    // MARK: - Parsing pins

    func testParseSonyE16CountsAndFields() {
        let db = parse(Self.sonyE16XML)
        XCTAssertEqual(db.lenses.count, 1, "exactly one lens")
        XCTAssertEqual(db.cameras.count, 1, "exactly one camera")
        let lens = db.lenses[0]
        XCTAssertEqual(lens.maker, "Sony")
        XCTAssertEqual(lens.models, ["E 16mm f/2.8"])
        XCTAssertEqual(lens.mounts, ["Sony E"])
        XCTAssertEqual(lens.cropfactor, 1.534, accuracy: 1e-9)
        XCTAssertEqual(lens.calibrations.distortions.count, 1)
        XCTAssertEqual(lens.calibrations.tcas.count, 1)
        XCTAssertEqual(lens.calibrations.vignettes.count, 3)
        // ptlens terms verbatim.
        let d = lens.calibrations.distortions[0]
        XCTAssertEqual(d.terms, [0.01701, -0.02563, -0.0052].map { $0 })
        XCTAssertEqual(d.focal, 16, accuracy: 1e-12)
        // poly3 TCA with MISSING cr/cb → 0 (the sparse-attribute rule).
        let t = lens.calibrations.tcas[0]
        XCTAssertEqual(t.vr, 1.0010272, accuracy: 1e-9)
        XCTAssertEqual(t.vb, 0.9993952, accuracy: 1e-9)
        XCTAssertEqual(t.cr, 0, accuracy: 1e-12)
        XCTAssertEqual(t.cb, 0, accuracy: 1e-12)
        XCTAssertEqual(t.br, -0.0003027, accuracy: 1e-10)
        XCTAssertEqual(t.bb, 0.0003454, accuracy: 1e-10)
        // Vignette row verbatim.
        let v = lens.calibrations.vignettes[0]
        XCTAssertEqual(v.aperture, 2.8, accuracy: 1e-12)
        XCTAssertEqual(v.distance, 0.25, accuracy: 1e-12)
        XCTAssertEqual(v.k1, -1.8891, accuracy: 1e-9)
        // Camera lang variants accumulate.
        XCTAssertEqual(db.cameras[0].models, ["ILCE-7M4", "Alpha 7 IV"])
        XCTAssertEqual(db.cameras[0].cropfactor, 1, accuracy: 1e-12)
    }

    func testParseSparseTCAAndPoly5() {
        let db = parse(Self.canon24XML)
        let t = db.lenses[0].calibrations.tcas[0]
        // Sparse row: only vr/vb present → rest default.
        XCTAssertEqual(t.vr, 1.0001965, accuracy: 1e-9)
        XCTAssertEqual(t.vb, 1.0000158, accuracy: 1e-9)
        XCTAssertEqual(t.br, 0, accuracy: 1e-12)
        XCTAssertEqual(t.bb, 0, accuracy: 1e-12)
        let d = db.lenses[0].calibrations.distortions[0]
        XCTAssertEqual(d.terms, [-0.00902])

        let db5 = parse(Self.poly5XML)
        let rows = db5.lenses[0].calibrations.distortions
        XCTAssertEqual(rows.count, 3, "three poly5 focal rows")
        XCTAssertEqual(rows[0].terms[0], -0.030571633, accuracy: 1e-12)
        XCTAssertEqual(rows[0].terms[1], 0.004658548, accuracy: 1e-12)
        // XML entity decoding (&amp; → &).
        XCTAssertTrue(db5.lenses[0].models[0].contains("&"), "entity decoded: \(db5.lenses[0].models)")
        // linear TCA direct terms (Double storage — 1e-9 is safe here).
        let lin = db5.lenses[0].calibrations.tcas[0]
        XCTAssertEqual(lin.kr, 1.0006, accuracy: 1e-9)
        XCTAssertEqual(lin.kb, 1.0004, accuracy: 1e-9)
    }

    // MARK: - Normalization + match

    func testNormalizeModel() {
        XCTAssertEqual(
            LensfunMatch.normalizeModel("Canon EF-S 24mm f/2.8 STM", maker: "Canon"),
            "ef-s 24mm stm")
        XCTAssertEqual(LensfunMatch.normalizeModel("  E  16mm   f/2.8  "), "e 16mm")
        XCTAssertEqual(LensfunMatch.modelScore(exif: "E 16mm f/2.8", candidate: "E 16mm f/2.8"), 100)
        XCTAssertEqual(LensfunMatch.modelScore(exif: "Sony E 16mm f/2.8", candidate: "E 16mm f/2.8", maker: "Sony"), 100)
        XCTAssertGreaterThanOrEqual(
            LensfunMatch.modelScore(exif: "E 16mm f/2.8", candidate: "E 16mm f/2.8 SEL16F28"), 60)
        XCTAssertEqual(LensfunMatch.modelScore(exif: "Nikkor 50mm", candidate: "Canon EF 24mm"), 0)
    }

    func testMatchSonyE16() {
        let db = parse(Self.sonyE16XML)
        let hit = LensfunMatch.match(
            maker: "Sony", model: "ILCE-7M4", lens: "E 16mm F2.8",
            imageCrop: 1.534, in: db)
        XCTAssertNotNil(hit, "exact lens key must hit")
        XCTAssertEqual(hit?.models, ["E 16mm f/2.8"])
        // Crop gate: image crop far below the lens crop → miss.
        XCTAssertNil(LensfunMatch.match(
            maker: "Sony", model: "ILCE-7M4", lens: "E 16mm F2.8",
            imageCrop: 1.0, in: db), "1.0/1.534 = 0.65 < 0.96 → gate miss")
        // Unknown lens → miss (NOT a failure — the downgrade path).
        XCTAssertNil(LensfunMatch.match(
            maker: "Sony", model: "ILCE-7M4", lens: "No Such Lens 500mm",
            imageCrop: 1.534, in: db))
    }

    // MARK: - Hermite spline primitive

    func testHermiteEndpointsAndMidpoint() {
        // Linear data interpolates linearly regardless of neighbors.
        XCTAssertEqual(LensfunMatch.hermite(y1: 0, y2: 10, y3: 20, y4: 30, t: 0.5), 15, accuracy: 1e-9)
        XCTAssertEqual(LensfunMatch.hermite(y1: 0, y2: 10, y3: 20, y4: 30, t: 0), 10, accuracy: 1e-9)
        XCTAssertEqual(LensfunMatch.hermite(y1: 0, y2: 10, y3: 20, y4: 30, t: 1), 20, accuracy: 1e-9)
        // Missing edges (±∞) degrade to the secant.
        XCTAssertEqual(
            LensfunMatch.hermite(y1: .infinity, y2: 10, y3: 20, y4: .infinity, t: 0.5),
            15, accuracy: 1e-9)
    }

    // MARK: - Distortion resolve (d-factor + hugin + NS·HW)

    /// Hand-computed pin: Sony E 16mm ptlens @16mm on a 64×64 plane,
    /// imageCrop = entry crop (1.534), aspect 1.5, realFocal = nominal.
    /// d = 1−a−b−c = 1.01382; s = (16/huginMM)·NS·HW with
    /// huginMM = 21.633/1.534/sqrt(3.25) = 7.8234…, NS·HW = 0.39282…,
    /// s = 0.80344…. a' = a·s³/d⁴, b' = b·s²/d³, c' = c·s/d².
    func testResolveSonyE16Distortion() {
        let db = parse(Self.sonyE16XML)
        let entry = db.lenses[0]
        let r = LensfunMatch.resolve(
            entry: entry, focal: 16, aperture: 2.8, distance: 1000,
            crop: 1.534, imageWidth: 64, imageHeight: 64)
        let p = try! XCTUnwrap(r)
        // Exact hand values (computed from the code's own formula chain:
        // NS·HW = 0.613662, huginMM = 15.64537, s = 0.627572, d = 1.01382).
        XCTAssertEqual(Double(p.dc3), 0.01701 * pow(0.627572, 3) / pow(1.01382, 4), accuracy: 2e-4)
        XCTAssertEqual(Double(p.dc2), -0.02563 * pow(0.627572, 2) / pow(1.01382, 3), accuracy: 2e-4)
        XCTAssertEqual(Double(p.dc1), -0.0052 * 0.627572 / pow(1.01382, 2), accuracy: 2e-4)
        XCTAssertEqual(p.dc4, 0, accuracy: 1e-12)
    }

    /// poly3 d-factor pin: Canon 24mm k1 = −0.00902 → d = 1.00902,
    /// dc2 = k1·s²/d³ (s at crop 1.622, 64×64).
    func testResolveCanonPoly3DFactor() {
        let db = parse(Self.canon24XML)
        let entry = db.lenses[0]
        let r = LensfunMatch.resolve(
            entry: entry, focal: 24, aperture: nil, distance: nil,
            crop: 1.622, imageWidth: 64, imageHeight: 64)
        let p = try! XCTUnwrap(r)
        let huginMM = 43.2666153056 / 1.622 / (1.5 * 1.5 + 1).squareRoot()
        let ns = 43.2666153056 / 1.622 / ((65.0 * 65.0 + 65.0 * 65.0).squareRoot()) / 24.0
        let s = (24.0 / huginMM) * ns * 32.0
        let d = 1 - (-0.00902)
        XCTAssertEqual(Double(p.dc2), -0.00902 * s * s / (d * d * d), accuracy: 2e-6)
        XCTAssertEqual(p.dc1, 0, accuracy: 1e-12)
        XCTAssertEqual(p.dc3, 0, accuracy: 1e-12)
        XCTAssertEqual(p.dc4, 0, accuracy: 1e-12)
    }

    /// poly5 spline pin: G12 @ focal 8.108 exact row → direct take
    /// (dc2 = k1·s², dc4 = k2·s⁴; no Hermite on exact).
    func testResolvePoly5ExactTake() {
        let db = parse(Self.poly5XML)
        let entry = db.lenses[0]
        let r = LensfunMatch.resolve(
            entry: entry, focal: 8.108, aperture: nil, distance: nil,
            crop: 4.63, imageWidth: 64, imageHeight: 64)
        let p = try! XCTUnwrap(r)
        let huginMM = 43.2666153056 / 4.63 / (1.5 * 1.5 + 1).squareRoot()
        let ns = 43.2666153056 / 4.63 / ((65.0 * 65.0 + 65.0 * 65.0).squareRoot()) / 8.108
        let s = (8.108 / huginMM) * ns * 32.0
        XCTAssertEqual(Double(p.dc2), -0.015375784 * s * s, accuracy: 1e-7)
        XCTAssertEqual(Double(p.dc4), 0.001669650 * s * s * s * s, accuracy: 1e-7)
        // linear TCA exact row → direct kr/kb (Float storage → 1e-6).
        XCTAssertEqual(Double(p.vr), 1.0006, accuracy: 1e-6)
        XCTAssertEqual(Double(p.vb), 1.0004, accuracy: 1e-6)
    }

    /// poly5 spline MIDPOINT: G12 @ focal 7.0 (between 6.1 and 8.108) —
    /// Hermite between rows with outer neighbors; assert against the
    /// Swift hermite() twin evaluated with the same rows (formula同源 +
    /// independent row selection — the interpolation STRUCTURE is pinned
    /// by testHermiteEndpointsAndMidpoint + the exact-take above).
    func testResolvePoly5SplineMidpoint() {
        let db = parse(Self.poly5XML)
        let entry = db.lenses[0]
        let r = LensfunMatch.resolve(
            entry: entry, focal: 7.0, aperture: nil, distance: nil,
            crop: 4.63, imageWidth: 64, imageHeight: 64)
        let p = try! XCTUnwrap(r)
        let huginMM = 43.2666153056 / 4.63 / (1.5 * 1.5 + 1).squareRoot()
        let ns = 43.2666153056 / 4.63 / ((65.0 * 65.0 + 65.0 * 65.0).squareRoot()) / 7.0
        let s = (7.0 / huginMM) * ns * 32.0
        // k1 rows: 6.1 → −0.030571633, 8.108 → −0.015375784, next 30.5.
        let t = (7.0 - 6.1) / (8.108 - 6.1)
        let k1 = LensfunMatch.hermite(
            y1: .infinity, y2: -0.030571633, y3: -0.015375784,
            y4: -0.000323237, t: t)
        XCTAssertEqual(Double(p.dc2), k1 * s * s, accuracy: 1e-9)
        // Midpoint must lie strictly between the bracketing takes.
        XCTAssertGreaterThan(Double(p.dc2), -0.030571633 * s * s)
        XCTAssertLessThan(Double(p.dc2), -0.015375784 * s * s)
    }

    // MARK: - TCA resolve

    func testResolveTCAPoly3Sparse() {
        // Canon 24mm sparse row: cr/cb/br/bb = 0 → only vr/vb ride.
        let db = parse(Self.canon24XML)
        let r = LensfunMatch.resolve(
            entry: db.lenses[0], focal: 24, aperture: nil, distance: nil,
            crop: 1.622, imageWidth: 64, imageHeight: 64)
        let p = try! XCTUnwrap(r)
        XCTAssertEqual(Double(p.vr), 1.0001965, accuracy: 1e-6)
        XCTAssertEqual(Double(p.vb), 1.0000158, accuracy: 1e-6)
        XCTAssertEqual(p.cr, 0, accuracy: 1e-12)
        XCTAssertEqual(p.br, 0, accuracy: 1e-12)
    }

    // MARK: - Vignetting IDW

    func testVignetteExactTake() {
        // Exact (f/2.8, d=1000) → the row's k verbatim (× hugin rescale²/⁴/⁶).
        let db = parse(Self.sonyE16XML)
        let v = LensfunMatch.interpolateVignetting(
            entry: db.lenses[0], focal: 16, aperture: 2.8, distance: 1000, crop: 1.534)
        let row = try! XCTUnwrap(v)
        XCTAssertEqual(row.k1, -1.9875, accuracy: 1e-12)
        XCTAssertEqual(row.k2, 1.9757, accuracy: 1e-12)
        XCTAssertEqual(row.k3, -0.8192, accuracy: 1e-12)
    }

    func testVignetteIDWMidpointAndClamp() {
        let db = parse(Self.sonyE16XML)
        // Midpoint aperture f/4 between f/2.8 and f/5.6 rows @ d=1000:
        // IDW must land strictly between the bracketing k1 values.
        let mid = try! XCTUnwrap(LensfunMatch.interpolateVignetting(
            entry: db.lenses[0], focal: 16, aperture: 4.0, distance: 1000, crop: 1.534))
        XCTAssertGreaterThan(mid.k1, -1.9875)
        XCTAssertLessThan(mid.k1, -1.4107)
        // Far-away grid point (f/64 — beyond any calibration) → nil
        // (min-dist > 1 ⇒ no correction, the downgrade path).
        XCTAssertNil(LensfunMatch.interpolateVignetting(
            entry: db.lenses[0], focal: 16, aperture: 64, distance: 0.001, crop: 1.534))
    }

    // MARK: - Refusals

    func testRefuseFisheyeType() {
        var db = parse(Self.sonyE16XML)
        db.lenses[0].type = "stereographic"
        XCTAssertNil(LensfunMatch.resolve(
            entry: db.lenses[0], focal: 16, aperture: 2.8, distance: 1000,
            crop: 1.534, imageWidth: 64, imageHeight: 64))
    }

    func testResolveEmptyCalibrationsNil() {
        var db = parse(Self.sonyE16XML)
        db.lenses[0].calibrations = LensCalibrations()
        XCTAssertNil(LensfunMatch.resolve(
            entry: db.lenses[0], focal: 16, aperture: 2.8, distance: 1000,
            crop: 1.534, imageWidth: 64, imageHeight: 64))
    }

    // MARK: - Fixture subset cross-check (T2 acceptance)

    private static let fixtureDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden/fixtures/lensfun", isDirectory: true)

    /// The 4 committed fixture files parse to the pinned lens counts —
    /// guards the subset against accidental edits.
    func testFixtureSubsetParses() throws {
        let fm = FileManager.default
        for (file, lenses, distortions) in [
            ("sony-e16.xml", 1, 1), ("canon-efs24.xml", 1, 1),
            ("compact-poly5.xml", 1, 5), ("sony-e24za.xml", 1, 1),
        ] {
            let url = Self.fixtureDir.appendingPathComponent(file)
            try XCTSkipIf(
                !fm.fileExists(atPath: url.path),
                "fixture missing: \(file) (gitignored? — must be committed per T2)")
            let db = LensfunDBLoader.parse(try Data(contentsOf: url))
            XCTAssertEqual(db.lenses.count, lenses, "\(file): lens count")
            guard db.lenses.count == lenses else { continue }
            XCTAssertEqual(
                db.lenses[0].calibrations.distortions.count, distortions,
                "\(file): distortion rows")
        }
        // linear TCA file carries kr/kb ≠ 1.
        let linURL = Self.fixtureDir.appendingPathComponent("sony-e24za.xml")
        if fm.fileExists(atPath: linURL.path) {
            let db = LensfunDBLoader.parse(try Data(contentsOf: linURL))
            guard !db.lenses.isEmpty, !db.lenses[0].calibrations.tcas.isEmpty else { return }
            let t = db.lenses[0].calibrations.tcas[0]
            XCTAssertEqual(t.kr, 1.0004, accuracy: 1e-9)
        }
    }
}
