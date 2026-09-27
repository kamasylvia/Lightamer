@testable import LightamerCore
import CoreGraphics
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// HDRMergeMathTests (Plan 08-1 T3/T4) — the research §1.4 numerical golden
// set (known L patches × {shutter} brackets → |L̂−L|/L < 1%; the all-clipped
// HOLE → Σw == 0; the ghost rejection → |L̂−clean| < 0.02), the dual-gate
// boundary table, the σ-parameterization identities, the de-ghost math, the
// band-geometry cover, and the float TIFF write round-trip.
// ─────────────────────────────────────────────────────────────────────────────

final class HDRMergeMathTests: XCTestCase {

    // MARK: - Fixture machinery

    /// Fixed-seed LCG uniform [0,1).
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1 }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
    }

    /// Build a synthetic bracket for one known scene luminance L: pixel
    /// value = L·t (+ relative noise) per source exposure t. All frames are
    /// `size×size` patches of the SAME constant value per source.
    private func bracket(
        luminance L: Float, exposures: [Float], size: Int,
        noise: Float = 0, seed: UInt64 = 7
    ) -> [HDRMergeMath.SourceBand] {
        exposures.enumerated().map { index, t in
            var rng = LCG(seed: seed &+ UInt64(index &+ 1) &* 7919)
            var pixels = [Float](repeating: 0, count: size * size * 4)
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let value = max(0, L * t * (1 + (rng.next() * 2 - 1) * noise))
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
                pixels[index + 3] = 1
            }
            return HDRMergeMath.SourceBand(
                pixels: pixels, width: size, height: size, exposure: t)
        }
    }

    private func sampleRGB(_ rgba: [Float], at index: Int) -> (Float, Float, Float) {
        (rgba[index * 4], rgba[index * 4 + 1], rgba[index * 4 + 2])
    }

    // MARK: - §1.4 golden: the linear recovery table

    func testRecoveryWithinOnePercent() {
        // P2's patch table: known L set × {1/4, 1, 4} shutters under 1%
        // shot noise → the merged L̂ must recover L within 1%.
        let table: [(L: Float, t: [Float])] = [
            (0.02, [0.25, 1, 4]),
            (0.18, [0.25, 1, 4]),
            (0.5, [0.25, 1, 4]),
            (1.5, [0.25, 1, 4]),
            (3.5, [0.25, 1, 4]),
        ]
        for entry in table {
            let frames = bracket(
                luminance: entry.L, exposures: entry.t, size: 64, noise: 0.01,
                seed: 42)
            let merged = HDRMergeMath.mergeFrames(
                frames: frames,
                params: StackMergeService.MergeParams(deGhost: false),
                width: 64, height: 64)
            // The patch-level mean (the P2 recovery-error metric — per-pixel
            // values carry the injected noise; the MEAN is the golden).
            var channelSums = (0.0, 0.0, 0.0)
            for index in 0..<(64 * 64) {
                let (r, g, b) = sampleRGB(merged.rgb, at: index)
                channelSums.0 += Double(r)
                channelSums.1 += Double(g)
                channelSums.2 += Double(b)
            }
            let pixelCount = Double(64 * 64)
            for channel in [channelSums.0 / pixelCount,
                            channelSums.1 / pixelCount,
                            channelSums.2 / pixelCount] {
                let relativeError = abs(channel - Double(entry.L)) / Double(entry.L)
                XCTAssertLessThan(
                    relativeError, 0.01,
                    "L=\(entry.L): recovered \(channel), error "
                        + "\(relativeError * 100)%")
            }
            // The bracket's coverage spans L — no holes expected.
            XCTAssertEqual(merged.holeFraction, 0, accuracy: 1e-6, "L=\(entry.L)")
        }
    }

    // MARK: - §1.4 golden: the HOLE semantics

    func testAllClippedPatchIsHOLE() {
        // L=8.0 under a ±2EV bracket: EVERY source's pixel lands past the
        // clip gate → Σw == 0 → output 0.0 (black) + holeFraction 1.0.
        let frames = bracket(
            luminance: 8.0, exposures: [0.25, 1, 4], size: 32, noise: 0)
        let merged = HDRMergeMath.mergeFrames(
            frames: frames,
            params: StackMergeService.MergeParams(deGhost: false),
            width: 32, height: 32)
        XCTAssertEqual(merged.holeFraction, 1.0, accuracy: 1e-6)
        let (r, g, b) = sampleRGB(merged.rgb, at: 0)
        XCTAssertEqual(r, 0, accuracy: 1e-9)
        XCTAssertEqual(g, 0, accuracy: 1e-9)
        XCTAssertEqual(b, 0, accuracy: 1e-9)
        XCTAssertEqual(merged.weightMap[0], 0, accuracy: 1e-9)
    }

    // MARK: - §1.4 golden: the ghost rejection

    func testGhostRejectedWithinTolerance() {
        // L=0.4, exposures {0.5, 1, 2} → clean pixels {0.2, 0.4, 0.8}.
        // The t=2 source carries a −0.6-magnitude NON-clipping ghost
        // (0.8 → 0.2, p/t = 0.1 vs the 0.4 consensus).
        var frames = bracket(
            luminance: 0.4, exposures: [0.5, 1, 2], size: 32, noise: 0)
        let ghostBand = frames[2]
        var ghostPixels = ghostBand.pixels
        for index in stride(from: 0, to: ghostPixels.count, by: 4) {
            ghostPixels[index] = 0.2
            ghostPixels[index + 1] = 0.2
            ghostPixels[index + 2] = 0.2
        }
        frames[2] = HDRMergeMath.SourceBand(
            pixels: ghostPixels, width: ghostBand.width,
            height: ghostBand.height, exposure: ghostBand.exposure)

        let merged = HDRMergeMath.mergeFrames(
            frames: frames,
            params: StackMergeService.MergeParams(deGhost: true),
            width: 32, height: 32)
        let (r, g, b) = sampleRGB(merged.rgb, at: 0)
        for channel in [r, g, b] {
            XCTAssertLessThan(
                abs(channel - 0.4), 0.02,
                "ghost not suppressed: recovered \(channel)")
        }
        // The ghost pixels entered the union bitmap.
        XCTAssertEqual(merged.ghostUnion?[0], 1)
    }

    func testDeGhostOffKeepsGhostContamination() {
        // The SAME bracket with deGhost OFF: the ghost contaminates the
        // merge (no suppression) and NO union bitmap is produced.
        var frames = bracket(
            luminance: 0.4, exposures: [0.5, 1, 2], size: 32, noise: 0)
        let ghostBand = frames[2]
        var ghostPixels = ghostBand.pixels
        for index in stride(from: 0, to: ghostPixels.count, by: 4) {
            ghostPixels[index] = 0.2
            ghostPixels[index + 1] = 0.2
            ghostPixels[index + 2] = 0.2
        }
        frames[2] = HDRMergeMath.SourceBand(
            pixels: ghostPixels, width: ghostBand.width,
            height: ghostBand.height, exposure: ghostBand.exposure)
        let merged = HDRMergeMath.mergeFrames(
            frames: frames,
            params: StackMergeService.MergeParams(deGhost: false),
            width: 32, height: 32)
        XCTAssertNil(merged.ghostUnion)
        let (r, _, _) = sampleRGB(merged.rgb, at: 0)
        XCTAssertGreaterThan(abs(r - 0.4), 0.005, "without de-ghost the ghost pulls L̂")
    }

    // MARK: - The dual-gate weight boundaries (§1.1)

    func testWeightDualGateBoundaries() {
        let sigma: Float = 0.2
        let clip: Float = 0.995
        let floor: Float = 0.001
        XCTAssertEqual(
            HDRMergeMath.weight(clip, sigma: sigma, clipGate: clip,
                floorGate: floor), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(
            HDRMergeMath.weight(0.994, sigma: sigma, clipGate: clip,
                floorGate: floor), 0)
        XCTAssertEqual(
            HDRMergeMath.weight(floor, sigma: sigma, clipGate: clip,
                floorGate: floor), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(
            HDRMergeMath.weight(0.002, sigma: sigma, clipGate: clip,
                floorGate: floor), 0)
    }

    func testSigmaParameterizationIdentities() {
        // w(0.5) = 1 for EVERY σ (the identity); a fatter σ weights the
        // same off-center p higher.
        for sigma: Float in [0.1, 0.15, 0.2, 0.25, 0.4] {
            XCTAssertEqual(
                HDRMergeMath.weight(0.5, sigma: sigma, clipGate: 0.995,
                    floorGate: 0.001), 1, accuracy: 1e-9, "σ=\(sigma)")
        }
        let narrow = HDRMergeMath.weight(0.7, sigma: 0.15, clipGate: 0.995, floorGate: 0.001)
        let wide = HDRMergeMath.weight(0.7, sigma: 0.25, clipGate: 0.995, floorGate: 0.001)
        XCTAssertGreaterThan(wide, narrow)
    }

    func testWeightNoiseFloorKnobDefaultsOff() {
        // OFF: the pure gaussian (the default); ON: the additive cap term.
        let plain = HDRMergeMath.weight(0.3, sigma: 0.2, clipGate: 0.995, floorGate: 0.001)
        let capped = HDRMergeMath.weight(0.3, sigma: 0.2, clipGate: 0.995,
            floorGate: 0.001, weightNoiseFloor: true)
        XCTAssertGreaterThan(capped, plain, "the knob must ADD mass when on")
    }

    // MARK: - The σ̂ noise model + residual (§4.1)

    func testSigmaHatAndResidualShapes() {
        // σ̂ = 5% floor + shot term; larger in the shadows.
        XCTAssertGreaterThan(HDRMergeMath.sigmaHat(0.05), HDRMergeMath.sigmaHat(0.5))
        XCTAssertEqual(
            HDRMergeMath.sigmaHat(1.0), 0.07, accuracy: 1e-4)
        // r = |p/t − L̂| / max(L̂, ε).
        XCTAssertEqual(
            HDRMergeMath.residual(0.4, exposure: 1, lHat: 0.4), 0, accuracy: 1e-9)
        XCTAssertEqual(
            HDRMergeMath.residual(0.8, exposure: 2, lHat: 0.4), 0, accuracy: 1e-9)
        XCTAssertEqual(
            HDRMergeMath.residual(0.1, exposure: 0.25, lHat: 0.4), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(HDRMergeMath.residual(0.8, exposure: 1, lHat: 0.4), 0.9)
    }

    // MARK: - The streaming footprint contract (the memory-constant face)

    func testAccumulatorFootprintIndependentOfSourceCount() {
        // The R3 red line: the resident set must not grow with N. The
        // accumulator accounting depends ONLY on the plane size and the
        // de-ghost switch — the N-source count never enters.
        let pixels = 1024 * 1024
        let small = BandStreamer.accumulatorBytes(
            width: 1024, height: 1024, deGhost: false)
        let smallGhost = BandStreamer.accumulatorBytes(
            width: 1024, height: 1024, deGhost: true)
        // Same plane, "N=2 vs N=8" — byte-identical accounting.
        XCTAssertEqual(small, BandStreamer.accumulatorBytes(width: 1024, height: 1024, deGhost: false))
        XCTAssertEqual(smallGhost, BandStreamer.accumulatorBytes(width: 1024, height: 1024, deGhost: true))
        // The exact B/px contracts (D-08-1): 28 without the ghost pass,
        // 41 with it (the phase-1 pair released before phase 2 mints its
        // own; see HDRMergeMath.mergeFrames).
        XCTAssertEqual(small, pixels * 28)
        XCTAssertEqual(smallGhost, pixels * 41)
        // @100MP the de-ghost peak stays ≈4.2 GB — the 16 GB machine
        // survives with the transient decode render (the research R3
        // accumulator-bound posture).
        XCTAssertLessThanOrEqual(
            BandStreamer.accumulatorBytes(width: 11648, height: 8736, deGhost: true),
            4_400_000_000)
    }

    func testBandGeometryCoversPlaneExactly() {
        let bands = BandStreamer.bands(height: 1000)
        XCTAssertEqual(bands.count, 4) // 256×3 + 232
        var covered = 0
        for band in bands {
            XCTAssertEqual(band.x, 0)
            XCTAssertEqual(band.width, 1)
            covered += band.height
        }
        XCTAssertEqual(covered, 1000)
        XCTAssertEqual(bands.first?.y, 0)
        XCTAssertEqual(bands.last?.y, 768)
        // Degenerate inputs → zero bands.
        XCTAssertTrue(BandStreamer.bands(height: 0).isEmpty)
        XCTAssertTrue(BandStreamer.bands(height: -5).isEmpty)
    }

    // MARK: - The float TIFF write round-trip (the EXP-01 face)

    func testFloatTIFFWriteRoundTripPreservesDepth() async throws {
        // A 4×4 plane with known extreme values (the RAW-03 probe set) —
        // written through the product writer, read back through the REAL
        // decode chain (RAWDecoder raster leg), values must survive.
        let width = 4, height = 4
        var plane = [Float](repeating: 0, count: width * height * 4)
        let pinned: [(x: Int, y: Int, value: Float)] = [
            (0, 0, 0.0), (1, 0, 0.5), (2, 0, 1.0), (3, 0, 2.0),
            (0, 1, 4.0), (1, 1, 16.0), (2, 1, 65504.0), (3, 1, 0.25),
        ]
        for pinnedPixel in pinned {
            let index = pinnedPixel.y * width + pinnedPixel.x
            plane[index * 4] = pinnedPixel.value
            plane[index * 4 + 1] = pinnedPixel.value
            plane[index * 4 + 2] = pinnedPixel.value
            plane[index * 4 + 3] = 1
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-tiff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("merged_hdr.tif")
        defer { try? FileManager.default.removeItem(at: dir) }

        try BandStreamer.writeFloatTIFF(plane, width: width, height: height, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        // The tmp residue must be gone (the promotion is a RENAME).
        let residue = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(residue, ["merged_hdr.tif"], "promotion left residue: \(residue)")

        // Read back through the REAL raster decode leg.
        let decoded = try await RAWDecoder().decode(destination)
        let extent = decoded.ciImage.extent
        XCTAssertEqual(Int(extent.width), width)
        XCTAssertEqual(Int(extent.height), height)
        var bitmap = [Float](repeating: -1, count: width * height * 4)
        let context = CIContext()
        context.render(
            decoded.ciImage, toBitmap: &bitmap, rowBytes: width * 16,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        for pinnedPixel in pinned {
            let index = pinnedPixel.y * width + pinnedPixel.x
            let tolerance = max(1e-3, abs(pinnedPixel.value) * 1e-4)
            XCTAssertEqual(
                bitmap[index * 4], pinnedPixel.value, accuracy: tolerance,
                "R @ \(pinnedPixel.x),\(pinnedPixel.y)")
        }
    }

    func testFloatTIFFRefusesOverwrite() throws {
        // The D-08-CONTEXT-11 red line at the writer boundary: an existing
        // destination is never overwritten.
        let width = 2, height = 2
        let plane = [Float](repeating: 0.5, count: width * height * 4)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-tiff-ow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("merged_hdr.tif")
        defer { try? FileManager.default.removeItem(at: dir) }
        try BandStreamer.writeFloatTIFF(plane, width: width, height: height, to: destination)
        let before = try Data(contentsOf: destination)
        XCTAssertThrowsError(
            try BandStreamer.writeFloatTIFF(plane, width: width, height: height, to: destination)
        ) { error in
            guard case AppError.encodeFailed = error else {
                XCTFail("expected encodeFailed, got \(error)")
                return
            }
        }
        let after = try Data(contentsOf: destination)
        XCTAssertEqual(before, after, "the existing product was touched")
    }
}
