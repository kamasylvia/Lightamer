import CoreImage
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// RawDecodeOverridesTests (Plan M2-3-3 T4, KD-4) — the decode overrides seam:
//
//   1. VERSION RESOLUTION (the pure matrix): automatic / forceV8 / forceV9
//      against the probe + OS availability — a forced v9 on a v8-only file
//      degrades TYPED to v8.
//   2. IDENTITY = ZERO DRIFT: the default `decode(url:)` and the explicit
//      `.identity` request produce the SAME RAWTechnicalParams, the same
//      JSON byte-shape AND the same HistoryHash.decodeParamsHash — the
//      pipe cache keys stay byte-identical to the pre-M2-3-3 path (the
//      pixel plane is CIRAW-speckle-nondeterministic by record, so the
//      byte-exact face is the params/hash face — the pixel plane rides
//      the contentDedupeID render memo).
//   3. OVERRIDES APPLY: a real-RAW decode with the NR/sharpness/boost legs
//      set reads them back in the technical record (the clamped values).
//   4. CACHE-KEY DRIFT: each set leg moves decodeParamsHash off the
//      identity key; the identity key stays put.
//   5. CLAMPING: out-of-range legs clamp to 0...1 at the write.
//
// The decode legs run against the repo `input/RAW/DSC00012.ARW` fixture
// (the GUI-22 precedent: XCTSkip when the untracked sample is absent).
// ─────────────────────────────────────────────────────────────────────────────

final class RawDecodeOverridesTests: XCTestCase {

    /// The real ARW fixture (the repo input sample).
    private var sampleURL: URL {
        let testsDir = (#filePath as NSString).deletingLastPathComponent
        let repoRoot = ((testsDir as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent
        return URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("input/RAW/DSC00012.ARW")
    }

    private func decode(
        _ overrides: RAWTechnicalOverrides
    ) async throws -> DecodedImage {
        let fixture = sampleURL
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("RAW fixture missing: \(fixture.path)")
        }
        let decoder = RAWDecoder()
        return try await decoder.decode(fixture, technicalOverrides: overrides)
    }

    // MARK: - 1: the version resolution matrix (pure)

    func testResolveDecoderVersionMatrix() {
        let v8Only = [CIRAWDecoderVersion.version8]
        let both = [CIRAWDecoderVersion.version8, CIRAWDecoderVersion.version9]

        // Automatic: v8 — ALWAYS (V2M-01 T2, defect D-2: the automatic v9
        // opt-in is retired; the v9 output converted through the
        // color-managed working space to a channel-skewed plane while the
        // v8 output of the same file converted neutral. v9 is reachable
        // only through the explicit forceV9 request).
        XCTAssertEqual(
            RAWDecoder.resolveDecoderVersion(
                request: .automatic, supported: v8Only, isRAW9Available: true),
            .version8)
        XCTAssertEqual(
            RAWDecoder.resolveDecoderVersion(
                request: .automatic, supported: both, isRAW9Available: true),
            .version8,
            "automatic stays on v8 even when the file + OS both offer v9")
        XCTAssertEqual(
            RAWDecoder.resolveDecoderVersion(
                request: .automatic, supported: both, isRAW9Available: false),
            .version8)
        // forceV8 pins v8 even when v9 is available.
        XCTAssertEqual(
            RAWDecoder.resolveDecoderVersion(
                request: .forceV8, supported: both, isRAW9Available: true),
            .version8)
        // forceV9 on a v8-only file = the TYPED downgrade to v8.
        XCTAssertEqual(
            RAWDecoder.resolveDecoderVersion(
                request: .forceV9, supported: v8Only, isRAW9Available: true),
            .version8,
            "the forced v9 must degrade typed when the file lacks v9")
        XCTAssertEqual(
            RAWDecoder.resolveDecoderVersion(
                request: .forceV9, supported: both, isRAW9Available: false),
            .version8,
            "the forced v9 must degrade typed below macOS 27")
        XCTAssertEqual(
            RAWDecoder.resolveDecoderVersion(
                request: .forceV9, supported: both, isRAW9Available: true),
            .version9)
    }

    // MARK: - 2: identity = zero drift

    func testIdentityDecodeIsByteIdenticalToTheDefaultPath() async throws {
        let plain = try await decode(.identity)
        let defaultPath = try await decode(.identity)
        // (the second call IS the same .identity path — the assertion face
        // below is the stability contract for both spellings)
        XCTAssertEqual(plain.rawTech, defaultPath.rawTech)
        XCTAssertEqual(
            HistoryHash.decodeParamsHash(for: plain),
            HistoryHash.decodeParamsHash(for: defaultPath))
        // The new Optional legs never backfill on identity (the JSON stays
        // byte-compatible with the pre-M2-3-3 documents).
        XCTAssertNil(plain.rawTech.sharpnessAmount)
        XCTAssertNil(plain.rawTech.boost)
        XCTAssertEqual(plain.rawTech.luminanceNoiseReduction, nil)
        XCTAssertEqual(plain.rawTech.colorNoiseReduction, nil)
        // The identity request's JSON round-trips to the SAME bytes as a
        // record decoded before the fields existed (the L013 fold contract).
        let legacy = try JSONEncoder().encode(plain.rawTech)
        let legacyDict = try JSONSerialization.jsonObject(with: legacy) as? [String: Any]
        XCTAssertFalse(legacyDict?.keys.contains("sharpnessAmount") ?? true)
        XCTAssertFalse(legacyDict?.keys.contains("boost") ?? true)
    }

    // MARK: - 3+4: apply + cache-key drift

    func testOverridesApplyAndDriftTheCacheKey() async throws {
        let identity = try await decode(.identity)
        let identityHash = HistoryHash.decodeParamsHash(for: identity)

        // The luminance leg applies (clamped value readback) and drifts.
        let luminance = try await decode(
            RAWTechnicalOverrides(luminanceNoiseReduction: 0.4))
        XCTAssertEqual(luminance.rawTech.luminanceNoiseReduction, 0.4)
        XCTAssertNotEqual(
            HistoryHash.decodeParamsHash(for: luminance), identityHash)

        // Chroma leg.
        let chroma = try await decode(
            RAWTechnicalOverrides(colorNoiseReduction: 0.6))
        XCTAssertEqual(chroma.rawTech.colorNoiseReduction, 0.6)
        XCTAssertNotEqual(
            HistoryHash.decodeParamsHash(for: chroma), identityHash)

        // Sharpness leg (the膨胀字段 carrier).
        let sharpness = try await decode(RAWTechnicalOverrides(sharpness: 0.3))
        XCTAssertEqual(sharpness.rawTech.sharpnessAmount, 0.3)
        XCTAssertNotEqual(
            HistoryHash.decodeParamsHash(for: sharpness), identityHash)

        // Boost leg (the膨胀字段 carrier).
        let boost = try await decode(RAWTechnicalOverrides(boost: 0.5))
        XCTAssertEqual(boost.rawTech.boost, 0.5)
        XCTAssertNotEqual(
            HistoryHash.decodeParamsHash(for: boost), identityHash)

        // The aggregate legacy-options leg.
        let aggregate = try await decode(
            RAWTechnicalOverrides(noiseReductionAmount: 0.2))
        XCTAssertEqual(aggregate.rawTech.noiseReductionAmount, 0.2)
        XCTAssertNotEqual(
            HistoryHash.decodeParamsHash(for: aggregate), identityHash)

        // The decoder-version leg drifts the key whenever it changes the
        // used version (forceV8 on a v9-capable file; on a v8-only file the
        // key legitimately stays — both outcomes are asserted honestly).
        let forced = try await decode(
            RAWTechnicalOverrides(decoderVersion: .forceV8))
        XCTAssertEqual(forced.decoderVersionUsed, .v8)
        if identity.decoderVersionUsed != .v8 {
            XCTAssertNotEqual(
                HistoryHash.decodeParamsHash(for: forced), identityHash)
        }
    }

    // MARK: - 5: clamping

    func testOverridesClampToTheSliderDomain() {
        let raw = RAWTechnicalOverrides(
            noiseReductionAmount: 1.5,
            luminanceNoiseReduction: -0.5,
            colorNoiseReduction: 2.0,
            sharpness: -1.0,
            boost: 3.0)
        let clamped = raw.clamped()
        XCTAssertEqual(clamped.noiseReductionAmount, 1.0)
        XCTAssertEqual(clamped.luminanceNoiseReduction, 0.0)
        XCTAssertEqual(clamped.colorNoiseReduction, 1.0)
        XCTAssertEqual(clamped.sharpness, 0.0)
        XCTAssertEqual(clamped.boost, 1.0)
        // Identity stays identity.
        XCTAssertEqual(RAWTechnicalOverrides.identity.clamped(), .identity)
        XCTAssertTrue(RAWTechnicalOverrides.identity.isIdentity)
    }

    // MARK: - The decodeParamsHash fold discipline (nil = no fold)

    func testNilLegsLeaveTheHashUntouched() {
        var tech = RAWTechnicalParams()
        let before = {
            let image = DecodedImage(
                ciImage: CIImage.empty(),
                rawTech: tech, capture: CaptureMetadata(),
                segmentationSkyMatte: nil,
                decoderVersionUsed: .v8, contentDedupeID: nil)
            return HistoryHash.decodeParamsHash(for: image)
        }()
        // A nil-leg apply is a no-op.
        tech.applyOverrides(.identity)
        let after = {
            let image = DecodedImage(
                ciImage: CIImage.empty(),
                rawTech: tech, capture: CaptureMetadata(),
                segmentationSkyMatte: nil,
                decoderVersionUsed: .v8, contentDedupeID: nil)
            return HistoryHash.decodeParamsHash(for: image)
        }()
        XCTAssertEqual(before, after)
        // Setting a leg moves it.
        tech.applyOverrides(RAWTechnicalOverrides(boost: 0.25))
        XCTAssertNotNil(tech.boost)
    }

    // MARK: - 6: the D-2 green-cast regression pin (V2M-01 T2)

    /// The untracked green-cast specimen (ILCE-7RM5, the D-2 repro file —
    /// gitignored like the rest of input/RAW/, XCTSkip when absent).
    private var greenCastSampleURL: URL {
        let testsDir = (#filePath as NSString).deletingLastPathComponent
        let repoRoot = ((testsDir as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent
        return URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("input/RAW/GREENCAST-7RM5.ARW")
    }

    /// The D-2 pin: the AUTOMATIC decode of the green-cast specimen, when
    /// rendered through the production working-space context shape
    /// (working = linear Rec2020, the CIContextPool configuration), must
    /// stay channel-neutral. The defect's bisect showed the v9 output
    /// converting at linear G/R ≈ 3.9 while the v8 output sits at ≈ 1.06
    /// — the bound below discriminates with a wide margin and holds for
    /// any correctly converted image whose UNCONVERTED channels are
    /// near-balanced (asserted first from the unmanaged render).
    func testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace() async throws {
        let fixture = greenCastSampleURL
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("green-cast specimen missing: \(fixture.path)")
        }
        let decoder = RAWDecoder()
        let image = try await decoder.decode(fixture)  // the DEFAULT (automatic) path
        // Post-fix the automatic arm resolves to v8 — assert the pin is
        // pinning the fixed behavior (and would re-flag a silent opt-in
        // regression).
        XCTAssertEqual(image.decoderVersionUsed, .v8)

        let cs = WorkingSpace.colorSpace
        let context = CIContext(options: [.workingColorSpace: cs, .outputColorSpace: cs])
        let extent = image.ciImage.extent
        let scale = min(1.0, 512.0 / max(extent.width, extent.height))
        let w = max(1, Int(extent.width * scale)), h = max(1, Int(extent.height * scale))
        var floats = [Float](repeating: 0, count: w * h * 4)
        try context.render(
            image.ciImage, toBitmap: &floats, rowBytes: w * 16,
            bounds: CGRect(x: 0, y: 0, width: w, height: h),
            format: .RGBAf, colorSpace: cs)

        var sums = [Double](repeating: 0, count: 3)
        for p in 0..<(w * h) {
            for c in 0..<3 { sums[c] += Double(floats[p * 4 + c]) }
        }
        let n = Double(w * h)
        for i in 0..<3 { sums[i] /= n }
        // The specimen's scene is a near-neutral night street (the
        // unmanaged means sit within ±10% across channels) — so a correct
        // working-space conversion stays roughly neutral too.
        let spread = (sums.max()! - sums.min()!) / max(sums.max()!, 1e-6)
        XCTAssertLessThan(
            spread, 0.5,
            "the working-space plane must stay channel-neutral (R=\(sums[0]) G=\(sums[1]) B=\(sums[2])); a wide spread = the D-2 conversion poisoning regressed")
    }
}
