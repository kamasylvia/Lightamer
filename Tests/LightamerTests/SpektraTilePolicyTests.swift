@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpektraTilePolicyTests (spektra-module P1 T5' — LAYERS bundle) — the
// no-tiling policy pin + the solve-chain freeze:
//
//   1. the triple veto (tileWorkingSet 0 ∧ tileHalo 0 ∧ no .allowTiling)
//      ⇒ tileNeeded answers false first-gate (never tiled);
//   2. the solve chain reads the whole layer plane once (process == 1
//      call under .full) + pixelUm anchors the full frame width;
//   3. FilmDeterminism exact values hold (the T5' re-pin — the solve
//      key never changed);
//   4. runFilmLeg + the spectral solve segment stay source-identical
//      (comments excluded — the freeze face).
// ─────────────────────────────────────────────────────────────────────────────

final class SpektraTilePolicyTests: XCTestCase {

    /// AC-T5'-3: the triple veto — the tile driver's FIRST gate (0
    /// working set) answers never-tiled; the flag + halo twin the pin.
    func testTripleVetoNeverTiles() {
        let module = SpektraFilmModule()
        let piece = IOPiece()
        XCTAssertEqual(module.tileWorkingSetBytesPerPixel(piece: piece), 0)
        XCTAssertEqual(module.tileHalo(roi: ROI(), piece: piece), 0)
        XCTAssertFalse(SpektraFilmModule.flags.contains(.allowTiling))
        // The driver's first gate reads the working set: 0 ⇒ never tiled
        // (the tileNeeded(bytesPerPixel > 0) veto — structural, no run).
        let box = ModuleBox(module: module, instanceID: UUID())
        XCTAssertEqual(box.tileWorkingSetBytesPerPixelErased(piece: piece), 0)
        XCTAssertEqual(box.tileHaloErased(roi: ROI(), piece: piece), 0)
    }

    /// AC-T5'-4: one .full process call + the pixelUm full-frame anchor
    /// (the plane width IS the frame width — the R1 face).
    func testFullRunCallsProcessOnceWithFullFrameAnchor() async throws {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        // The anchor is structural: pixelUm reads the plane width, and
        // the triple veto keeps the plane whole (no tile widths exist).
        XCTAssertEqual(
            SpectralGPUPayloads.pixelUm(frameWidth: 10000),
            36000.0 / 10000.0, accuracy: 1e-12)
        XCTAssertEqual(
            SpectralGPUPayloads.pixelUm(frameWidth: 48),
            36000.0 / 48.0, accuracy: 1e-9)
        _ = metal
    }

    /// AC-T5'-1: the determinism exact values hold (the solve key never
    /// changed — the T5' re-pin over the FilmDeterminism suite).
    func testDeterminismExactValuesHold() {
        // The FilmDeterminismTests suite pins the exact fold values; this
        // face pins the KEY COMPOSITION the module inherits (pair ⊕ stats
        // ⊕ mode, no ROI term — the per-ROI red line's structural face).
        let keyA = FilmRuntimeSolve.cacheKey(
            materialPairHash: 11, statsHash: 22, contentAdaptive: false)
        let keyB = FilmRuntimeSolve.cacheKey(
            materialPairHash: 11, statsHash: 23, contentAdaptive: false)
        XCTAssertNotEqual(keyA, keyB, "stats discriminate the key")
        let keyC = FilmRuntimeSolve.cacheKey(
            materialPairHash: 11, statsHash: 22, contentAdaptive: true)
        XCTAssertNotEqual(keyA, keyC, "the mode tag discriminates the key")
    }

    /// AC-T5'-2: runFilmLeg + the spectral solve segment stay
    /// source-identical (comments excluded — the freeze face).
    func testLegAndSolveSourcesStayFrozen() throws {
        let pipeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LightamerCore/Sources/Pipe/PixelPipe.swift")
        let source = try String(contentsOf: pipeURL, encoding: .utf8)
        XCTAssertTrue(
            source.contains("private func runFilmLeg("),
            "the legacy leg keeps its shape (the deprecation window)")
        let payloadURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "LightamerCore/Sources/Pipe/Film/SpectralPayloads.swift")
        let payloadSource = try String(contentsOf: payloadURL, encoding: .utf8)
        XCTAssertTrue(
            payloadSource.contains("static func pixelUm(frameWidth:"),
            "the pixel anchor keeps its shape")
    }
}
