@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MTBAlignTests (Plan 08-1 T2) — synthetic bracket fixtures with KNOWN
// shifts (the research P1 exact-hit table: (17,-11) and (-9,23), including
// 4×/0.25× exposure deltas), the shrink-window out-of-bounds regression,
// the failure/degradation labels, the EXIF precheck matrix, and the runtime
// exposure-ratio self-check.
// ─────────────────────────────────────────────────────────────────────────────

final class MTBAlignTests: XCTestCase {

    // MARK: - Fixture machinery

    /// Fixed-seed LCG texture — a rich histogram (the MTB median needs
    /// spread) that is highly discriminative under shifts.
    private static func texture(_ width: Int, _ height: Int, seed: UInt64) -> [Float] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        var pixels = [Float](repeating: 0, count: width * height)
        for index in pixels.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let uniform = Float((state >> 33) & 0xFFFFF) / Float(0xFFFFF)
            pixels[index] = 0.05 + 0.9 * uniform
        }
        // Pin the MAX at a position the shifted fixture's clamp cannot drop
        // (the clamp drops the dx/dy edge strips; a lost max would shift the
        // per-frame normalization and speckle the median-threshold bitmaps).
        pixels[(height / 2) * width + width / 2] = 1.5
        return pixels
    }

    /// Build an AlignmentFrame from a float gray luma (a gray pixel has a
    /// channel-equal RGB triple — the luma coefficients reconstruct it).
    private static func frame(
        gray: [Float], width: Int, height: Int
    ) -> AlignmentFrame {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            let value = gray[index]
            rgba[index * 4 + 0] = value
            rgba[index * 4 + 1] = value
            rgba[index * 4 + 2] = value
            rgba[index * 4 + 3] = 1
        }
        return rgba.withUnsafeBufferPointer { buffer in
            AlignmentFrame(
                rgbaFloat: UnsafeRawBufferPointer(buffer),
                width: width, height: height, bytesPerRow: width * 16)
        }
    }

    /// `cmp(x, y) = ref(x - dx, y - dy)` (the SHIFT CONVENTION; edges clamp
    /// to the nearest in-bounds sample).
    private static func shifted(
        _ source: [Float], width: Int, height: Int, dx: Int, dy: Int
    ) -> [Float] {
        var result = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sx = min(max(x - dx, 0), width - 1)
                let sy = min(max(y - dy, 0), height - 1)
                result[y * width + x] = source[sy * width + sx]
            }
        }
        return result
    }

    private static func scaled(_ source: [Float], gain: Float) -> [Float] {
        source.map { min($0 * gain, 8.0) }
    }

    // MARK: - Exact-hit table (research P1)

    func testExactHitNoExposureDelta() {
        let width = 512, height = 384
        let ref = Self.texture(width, height, seed: 0xA)
        let refFrame = Self.frame(gray: ref, width: width, height: height)
        for (dx, dy) in [(17, -11), (-9, 23), (0, 0), (5, 5), (-1, -1)] {
            let cmp = Self.shifted(ref, width: width, height: height, dx: dx, dy: dy)
            let cmpFrame = Self.frame(gray: cmp, width: width, height: height)
            let refPyramid = MTBAlign.pyramid(refFrame.luma)
            let cmpPyramid = MTBAlign.pyramid(cmpFrame.luma)
            let shift = MTBAlign.findShift(reference: refPyramid, compare: cmpPyramid)
            XCTAssertEqual(
                shift.dx, dx, "dx mismatch for shift (\(dx),\(dy))")
            XCTAssertEqual(
                shift.dy, dy, "dy mismatch for shift (\(dx),\(dy))")
            XCTAssertEqual(shift.verdict, .full, "verdict for (\(dx),\(dy))")
        }
    }

    func testExactHitWithExposureDeltas() {
        // 4× (over) and 0.25× (under) — the MTB threshold is
        // monotonic-gain invariant; the max normalization inside
        // AlignmentFrame cancels the gain exactly.
        let width = 512, height = 384
        let ref = Self.texture(width, height, seed: 0xB)
        let refFrame = Self.frame(gray: ref, width: width, height: height)
        for (dx, dy, gain) in [(17, -11, Float(4.0)), (-9, 23, Float(0.25))] {
            let cmp = Self.scaled(
                Self.shifted(ref, width: width, height: height, dx: dx, dy: dy),
                gain: gain)
            let cmpFrame = Self.frame(gray: cmp, width: width, height: height)
            let shift = MTBAlign.findShift(
                reference: MTBAlign.pyramid(refFrame.luma),
                compare: MTBAlign.pyramid(cmpFrame.luma))
            XCTAssertEqual(shift.dx, dx, "dx @ gain \(gain)")
            XCTAssertEqual(shift.dy, dy, "dy @ gain \(gain)")
            XCTAssertEqual(shift.verdict, .full, "verdict @ gain \(gain)")
        }
    }

    // MARK: - Out-of-bounds regression (the P1 shrink-window lesson)

    func testShiftBeyondSearchCoverageDegrades() {
        let width = 512, height = 384
        let ref = Self.texture(width, height, seed: 0xC)
        let refFrame = Self.frame(gray: ref, width: width, height: height)
        // 40 px exceeds the 6-level reach (2^5 = 32) — the verdict must
        // NOT be a trusted `.full`.
        let cmp = Self.shifted(ref, width: width, height: height, dx: 40, dy: 0)
        let cmpFrame = Self.frame(gray: cmp, width: width, height: height)
        let shift = MTBAlign.findShift(
            reference: MTBAlign.pyramid(refFrame.luma),
            compare: MTBAlign.pyramid(cmpFrame.luma))
        XCTAssertNotEqual(shift.verdict, .full)
        XCTAssertNotEqual(shift.label, "full")
    }

    func testLowTextureFrameSkipsAlignment() {
        let width = 128, height = 96
        let flat = [Float](repeating: 0.5, count: width * height)
        let frame = Self.frame(gray: flat, width: width, height: height)
        let pyramid = MTBAlign.pyramid(frame.luma)
        let shift = MTBAlign.findShift(
            reference: pyramid, compare: MTBAlign.pyramid(frame.luma))
        XCTAssertEqual(shift.verdict, .lowTexture)
        XCTAssertEqual(shift.label, "skipped-low-texture")
        XCTAssertEqual(shift.dx, 0)
        XCTAssertEqual(shift.dy, 0)
    }

    // MARK: - XOR distance (intersection shrink correctness)

    func testXorDistanceZeroAtPerfectAndPositiveOff() {
        let width = 128, height = 64
        let gray = Self.texture(width, height, seed: 0xD)
        let frame = Self.frame(gray: gray, width: width, height: height)
        let ref = MTBAlign.pyramid(frame.luma)[0]
        // A TOROIDAL shift (the pixel-value multiset is preserved — a
        // bijection): the clamp variant drops edge strips, which shifts the
        // histogram MEDIAN by one bin and speckles the threshold bitmaps
        // near it (~the median-boundary pixel count). The exact-zero
        // assertion needs the bijection.
        var wrap = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                wrap[y * width + x] = gray[((y + 2) % height) * width + ((x - 3 + width) % width)]
            }
        }
        let cmp = MTBAlign.pyramid(
            Self.frame(gray: wrap, width: width, height: height).luma)[0]
        // The convention's shift: cmp(x,y) == ref(x-3, y+2) → a PERFECT
        // bit match at (dx, dy) = (3, -2).
        let atShift = MTBAlign.xorDistance(reference: ref, compare: cmp, dx: 3, dy: -2)
        XCTAssertEqual(atShift, 0.0, accuracy: 1e-12)
        // A wrong shift leaves a large XOR distance.
        let offShift = MTBAlign.xorDistance(reference: ref, compare: cmp, dx: 0, dy: 0)
        XCTAssertGreaterThan(offShift, 0.1)
    }

    // MARK: - EXIF precheck matrix (research §2.4)

    private static let refCapture = CaptureMetadata(
        cameraModel: "Sony ILCE-7RM5", lensModel: "FE 24-70mm F2.8 GM II",
        focalLength: 70, aperture: 2.8, shutterSpeed: 1 / 250, iso: 100)

    func testPrecheckPassesCanonicalBracket() {
        let candidate = CaptureMetadata(
            cameraModel: "Sony ILCE-7RM5", lensModel: "FE 24-70mm F2.8 GM II",
            focalLength: 70, aperture: 2.8, shutterSpeed: 1 / 1000, iso: 100)
        let verdict = ExifPrecheck.precheck(
            reference: Self.refCapture, candidate: candidate, allowOverrides: false)
        guard case .ok(let ev) = verdict else {
            XCTFail("expected .ok, got \(verdict)")
            return
        }
        // 1/250 → 1/1000 = −2 EV in BRIGHTNESS-multiple semantics: the
        // candidate's FASTER shutter collects 1/4 the light —
        // log2(t_c/t_ref) = log2(0.25) = −2 (the 08-1 acceptance sign
        // fix; the merge divides the candidate's pixels by 2^ΔEV = 0.25).
        XCTAssertEqual(ev, -2.0, accuracy: 1e-9)
    }

    func testPrecheckRejectsApertureMismatchWithoutOverride() {
        let candidate = CaptureMetadata(
            cameraModel: "Sony ILCE-7RM5", lensModel: "FE 24-70mm F2.8 GM II",
            focalLength: 70, aperture: 4.0, shutterSpeed: 1 / 1000, iso: 100)
        let verdict = ExifPrecheck.precheck(
            reference: Self.refCapture, candidate: candidate, allowOverrides: false)
        guard case .rejected = verdict else {
            XCTFail("aperture mismatch must reject, got \(verdict)")
            return
        }
    }

    func testPrecheckOverrideAdmitsApertureMismatchWithWarning() {
        let candidate = CaptureMetadata(
            cameraModel: "Sony ILCE-7RM5", lensModel: "FE 24-70mm F2.8 GM II",
            focalLength: 70, aperture: 4.0, shutterSpeed: 1 / 1000, iso: 100)
        let verdict = ExifPrecheck.precheck(
            reference: Self.refCapture, candidate: candidate, allowOverrides: true)
        guard case .admittedWithWarning(_, let reasons) = verdict else {
            XCTFail("override must admit, got \(verdict)")
            return
        }
        XCTAssertTrue(reasons.contains { $0.contains("aperture") })
    }

    func testPrecheckRejectsISOMismatchWithoutOverride() {
        let candidate = CaptureMetadata(
            cameraModel: "Sony ILCE-7RM5", lensModel: "FE 24-70mm F2.8 GM II",
            focalLength: 70, aperture: 2.8, shutterSpeed: 1 / 1000, iso: 200)
        let verdict = ExifPrecheck.precheck(
            reference: Self.refCapture, candidate: candidate, allowOverrides: false)
        guard case .rejected = verdict else {
            XCTFail("ISO mismatch must reject, got \(verdict)")
            return
        }
    }

    func testPrecheckOverrideAdmitsISOMismatchAndFoldsISOIntoEV() {
        let candidate = CaptureMetadata(
            cameraModel: "Sony ILCE-7RM5", lensModel: "FE 24-70mm F2.8 GM II",
            focalLength: 70, aperture: 2.8, shutterSpeed: 1 / 1000, iso: 200)
        let verdict = ExifPrecheck.precheck(
            reference: Self.refCapture, candidate: candidate, allowOverrides: true)
        guard case .admittedWithWarning(let ev, _) = verdict else {
            XCTFail("override must admit, got \(verdict)")
            return
        }
        // ΔEV = log2(t_c/t_ref) + log2(ISO_c/ISO_ref) = −2 + 1 = −1 — the
        // brightness multiple 2^−1 = 0.5× (1/4 the shutter light × 2×
        // ISO amplification), the factor the merge divides by
        // (the 08-1 acceptance sign fix).
        XCTAssertEqual(ev, -1.0, accuracy: 1e-9)
    }

    func testPrecheckRejectsCameraMismatch() {
        let candidate = CaptureMetadata(
            cameraModel: "Canon EOS R5", lensModel: "FE 24-70mm F2.8 GM II",
            focalLength: 70, aperture: 2.8, shutterSpeed: 1 / 1000, iso: 100)
        let verdict = ExifPrecheck.precheck(
            reference: Self.refCapture, candidate: candidate, allowOverrides: true)
        guard case .rejected(let reasons) = verdict else {
            XCTFail("camera mismatch must reject even with override, got \(verdict)")
            return
        }
        XCTAssertTrue(reasons.contains { $0.contains("camera") })
    }

    func testPrecheckRejectsIdenticalShutter() {
        let candidate = CaptureMetadata(
            cameraModel: "Sony ILCE-7RM5", lensModel: "FE 24-70mm F2.8 GM II",
            focalLength: 70, aperture: 2.8, shutterSpeed: 1 / 250, iso: 100)
        let verdict = ExifPrecheck.precheck(
            reference: Self.refCapture, candidate: candidate, allowOverrides: true)
        guard case .rejected(let reasons) = verdict else {
            XCTFail("identical shutter must reject, got \(verdict)")
            return
        }
        XCTAssertTrue(reasons.contains { $0.contains("not a bracket") })
    }

    // MARK: - Runtime exposure-ratio self-check (research §1.2, R2)

    func testExposureRatioCheckPassesWithinTolerance() {
        let width = 256, height = 192
        let ref = Self.texture(width, height, seed: 0xE)
        // cmp = ref × 4 (the EXIF expectation matches the physical gain).
        let cmp = Self.scaled(ref, gain: 4)
        let refLuma = AlignmentFrame.RatioLuma(
            width: width, height: height, pixels: ref)
        let cmpLuma = AlignmentFrame.RatioLuma(
            width: width, height: height, pixels: cmp)
        let check = ExifPrecheck.exposureRatioCheck(
            reference: refLuma, candidate: cmpLuma, expectedEV: 2.0)
        XCTAssertTrue(check.verified, "measured \(check.measuredRatio)")
        XCTAssertEqual(check.measuredRatio, 4.0, accuracy: 0.2)
    }

    func testExposureRatioCheckFailsBeyondFivePercent() {
        let width = 256, height = 192
        let ref = Self.texture(width, height, seed: 0xF)
        // Physical gain 4.5 vs the EXIF expectation 4.0 → 12.5% deviation.
        let cmp = Self.scaled(ref, gain: 4.5)
        let refLuma = AlignmentFrame.RatioLuma(
            width: width, height: height, pixels: ref)
        let cmpLuma = AlignmentFrame.RatioLuma(
            width: width, height: height, pixels: cmp)
        let check = ExifPrecheck.exposureRatioCheck(
            reference: refLuma, candidate: cmpLuma, expectedEV: 2.0)
        XCTAssertFalse(check.verified, "measured \(check.measuredRatio)")
    }
}
