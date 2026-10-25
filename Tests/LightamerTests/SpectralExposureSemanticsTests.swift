@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralExposureSemanticsTests (Plan M8-3 T4 — IOPParity) — the exposure
// semantics terminal ledger (D-M8-8) + the NOTICE disclosure upgrade pins
// (D-M8-6):
//
//   1. THE CONSUMPTION LAYER (the ruling's machine face): FilmRecord
//      .exposureEv folds into the solve's exposure GAIN at consumption
//      (totalGain = autoGain × 2^ev) — the neutral pair and the cache key
//      hold NEITHER term (the record terms ride the recordHash and are
//      NEVER cached — the FilmSolveCache contract's end-to-end form).
//   2. THE CHAIN-HEAD REFUSAL: the expose stage's ev_scale stays ≡ 1 under
//      any record exposure — the ev is absorbed by the PRINT-exposure slot
//      (log10_print_exposure += log10(gain), the 印相曝光归一 semantics the
//      M3-4 latitude descriptor math is anchored to), never by the chain
//      head. The upstream chain-head form (×2^ev at expose) is the
//      REJECTED branch (D-M8-8's 晨审推翻点 — a re-derivation would
//      re-anchor the whole M3-4 panel/descriptor ecosystem for zero gain).
//   3. THE DESCRIPTOR'S EXPOSURE INVARIANCE: the latitude descriptor's
//      cache keyspace is pair-only (no exposure dimension) and the probe's
//      own solve face (the production call form) answers gain exactly 1 —
//      the medium measurement is exposure-free by construction.
//   4. THE NOTICE DISCLOSURE UPGRADE (D-M8-6): NOTICE §2 discloses the
//      per-wavelength material-chain consumption (metameric reconstruction
//      upstream of the material chain) — the old density-only claim is
//      gone; the profile/manifest byte-verbatim scope is untouched (NOTICE
//      is our file, the MANIFEST pins the data files only).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralExposureSemanticsTests: XCTestCase {

    // MARK: - Fixtures

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private var portra: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_400"))
        }
    }

    private var endura: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_endura"))
        }
    }

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func makeRecord(ev: Float) -> FilmRecord {
        var r = FilmRecord()
        r.filmStock = "kodak_portra_400"
        r.paperStock = "kodak_portra_endura"
        r.exposureEv = ev
        return r
    }

    // MARK: - 1: the consumption layer (solve gain; never the cache key)

    func testExposureEvRidesTheSolveGainAndNeverTheCacheKey() throws {
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)

        FilmSolveCache.shared.invalidateAll()
        let base = try FilmRuntimeSolve.solveSpectral(
            record: makeRecord(ev: 0), tables: try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper),
            materialPairHash: pairHash, histogram: nil)
        let lifted = try FilmRuntimeSolve.solveSpectral(
            record: makeRecord(ev: 1), tables: try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper),
            materialPairHash: pairHash, histogram: nil)

        // The neutral pair is exposure-invariant (the gain is a separate
        // consumption face — the two solve outputs share the CC totals).
        XCTAssertEqual(base.magentaCC, lifted.magentaCC)
        XCTAssertEqual(base.yellowCC, lifted.yellowCC)
        // The gain doubles exactly (nil histogram → autoGain 1 → ×2^1).
        XCTAssertEqual(base.exposureGain, 1.0)
        XCTAssertEqual(lifted.exposureGain, 2.0)

        // The cache holds ONE entry for the pair — the ev term never keys
        // (the record terms layer at consumption, the M8-2 T2 cache-key
        // assertion's end-to-end form).
        XCTAssertEqual(
            FilmSolveCache.shared.countForTesting, 1,
            "two solves differing only in exposureEv share ONE cache entry")
    }

    // MARK: - 2: the chain-head refusal (ev_scale ≡ 1; the print slot absorbs)

    func testExposureEvLandsOnThePrintSlotNeverTheExposeChainHead() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)

        func assembledFor(ev: Float) async throws
            -> (method: FilmMethodBox.Params, payloads: SpectralGPUPayloads) {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: 8, height: 8, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            let plane = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
            let assembled = PixelPipe.assembleFilmLeg(
                record: makeRecord(ev: ev), film: film, paper: paper,
                materialPairHash: pairHash, histogram: nil,
                plane: plane, metal: metal,
                renderProcess: RenderProcessVersion(rawValue: 2)!)
            let payloads = try XCTUnwrap(
                assembled.spectralPayloads,
                "the spectral arm must resolve for the exposure record")
            await Self.drain(metal)
            return (assembled.method, payloads)
        }

        func uniforms(of payloads: SpectralGPUPayloads) -> [Float] {
            Array(UnsafeBufferPointer(
                start: payloads.uniformsBuffer.contents()
                    .assumingMemoryBound(to: Float.self),
                count: SpectralGPUPayloads.UniformSlot.total))
        }

        let base = try await assembledFor(ev: 0)
        let lifted = try await assembledFor(ev: 1)

        // The METHOD's gain face doubles (the consumption layer's solve).
        XCTAssertEqual(base.method.exposureGain, 1.0)
        XCTAssertEqual(lifted.method.exposureGain, 2.0)

        // The uniform WRITE FACE (the dispatch-time tuning — the exact face
        // dispatchFilmChain drives): the ev-0 payload's session tuning with
        // the SOLVED gain (2.0 — the ev-1 record's consumption value) adds
        // EXACTLY log10(2) to the print-exposure slot; the expose chain
        // head's ev_scale slot is bit-untouched (the rejected chain-head
        // form would carry 2^ev THERE — D-M8-8's refusal pinned at the
        // uniform); the CC delta slots stay put (kM/kY = 0 here).
        let before = uniforms(of: base.payloads)
        base.payloads.applySessionTuning(
            exposureGain: 2.0, kM: 0, kY: 0, strength: 1)
        await Self.drain(metal)
        let after = uniforms(of: base.payloads)
        let evScale = SpectralGPUPayloads.UniformSlot.evScale
        XCTAssertEqual(
            before[evScale].bitPattern, after[evScale].bitPattern,
            "the tuning write never touches ev_scale")
        XCTAssertEqual(before[evScale], 1.0, "ev_scale ≡ 1 (the chain head)")
        let printSlot = SpectralGPUPayloads.UniformSlot.log10PrintExposure
        XCTAssertEqual(
            after[printSlot] - before[printSlot],
            Float(Foundation.log10(2.0)),
            "the print-exposure slot carries log10(gain) — the consumption face")
        let enlLo = SpectralGPUPayloads.UniformSlot.enlLo
        // Numeric equality (the -0.0 → +0.0 sign-bit flip under += 0.0 is
        // IEEE arithmetic, not a shift — the delta VALUE is what the E3
        // form consumes).
        XCTAssertEqual(before[enlLo + 1], after[enlLo + 1])
        XCTAssertEqual(before[enlLo + 2], after[enlLo + 2])
    }

    // MARK: - 3: the descriptor's exposure invariance

    func testLatitudeDescriptorKeyspaceIsExposureFree() throws {
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        // The descriptor cache key folds ONLY the pair hash (+ the probe
        // tag) — no exposure term exists in its domain (the medium is a
        // property of the materials, not of the document's exposure trim).
        let key = FilmDescriptorCache.cacheKey(materialPairHash: pairHash)
        XCTAssertEqual(
            key, FilmDescriptorCache.cacheKey(materialPairHash: pairHash))
        // The probe's own solve face (the production call form: the
        // default record, histogram nil) answers gain EXACTLY 1 — the
        // measurement never sees the exposure trim.
        let solution = try FilmRuntimeSolve.solveSpectral(
            record: FilmRecord(), tables: try SpectralPrintBake.tables(
                forPairHash: pairHash, film: film, paper: paper),
            materialPairHash: pairHash, histogram: nil)
        XCTAssertEqual(solution.exposureGain, 1.0)
    }

    // MARK: - 4: the NOTICE disclosure upgrade (D-M8-6)

    func testNoticeDisclosesThePerWavelengthMaterialChain() throws {
        let noticeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/NOTICE")
        let notice = try String(contentsOf: noticeURL, encoding: .utf8)

        // The upgraded disclosure semantics (the per-wavelength material
        // chain + the metameric reconstruction boundary).
        XCTAssertTrue(
            notice.lowercased().contains("per-wavelength"),
            "NOTICE §2 must disclose the per-wavelength material chain")
        XCTAssertTrue(
            notice.lowercased().contains("material chain"),
            "NOTICE §2 must name the material chain")
        XCTAssertTrue(
            notice.lowercased().contains("metameric"),
            "NOTICE §2 must disclose the metameric reconstruction boundary")
        // The OLD density-only claim is gone (the upgrade, not an append).
        XCTAssertFalse(
            notice.lowercased().contains("not consumed as a spectral forward model"),
            "the old spectral-unreachable claim must be retired")
        XCTAssertFalse(
            notice.lowercased().contains("density domain only"),
            "the old density-only consumer claim must be retired")

        // The byte-verbatim scope: NOTICE is OUR file (not manifest-pinned)
        // and the manifest's 30 data-file pins stay untouched — the
        // FilmProfileTests MANIFEST reconciliation (full, not sampled)
        // rides the same suite run as the zero-drift gate.
        let manifestURL = profilesDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("MANIFEST.sha256")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertFalse(
            manifest.contains("NOTICE"),
            "NOTICE is our disclosure file — the manifest pins the data files only")
        XCTAssertEqual(
            manifest.split(separator: "\n").count, 30,
            "the manifest's pin count (LICENSE + 28 profiles + the neutral "
                + "print-filter table) is untouched")
    }
}
