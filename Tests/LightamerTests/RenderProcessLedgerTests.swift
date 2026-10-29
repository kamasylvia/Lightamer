@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RenderProcessLedgerTests (Plan M8-2 T4 — Layers) — the process v2 bump's
// ledger face (the五件套's machine-checkable half):
//
//   1. THE LEDGER TABLE (oldest-first, current = last, the inverse map):
//      [.v1, .v2], current = .v2, processVersion {v1→1, v2→2} — the
//      exhaustive switches (all / processVersion) are the compile-time
//      half, this pins the value half.
//   2. THE CLAMP TABLE, FOUR DOMAINS: 0 (legacy) → .v1 (the freeze made
//      executable); 1 → .v1 (the frozen arm); 2 → .v2 (its own case);
//      forward numbers (3 / 7 / u32 max) → clamp to current .v2 (the
//      stored value never rewritten).
//   3. THE MINT: the current generation's number is 2 and the sidecar
//      write face emits "process": 2 for a `.current` document (the
//      App-layer mint point zero-changed — current IS 2).
//   4. THE FOLD NEGATIVE (the「非 legacy 才折」contract): a v1 document's
//      seed is byte-identical to the canonical 3-arg fold (the frozen
//      tag face); a v2 document's seed folds the spectral tag through the
//      SAME four-term canonical order (the exact FNV recomputation) — a
//      new keyspace no legacy key can collide with.
//   5. THE DEFERRED V2 PAYLOAD SHAPE (the T1 review-m4 hand-off): after
//      the bump the factory resolves the spectral arm for a v2 document —
//      spectralPayloads non-nil, payloads nil — while v1/legacy resolve
//      the density shape (the two arms' shapes are mutually exclusive).
// ─────────────────────────────────────────────────────────────────────────────

final class RenderProcessLedgerTests: XCTestCase {

    // MARK: - 1: the ledger table

    func testLedgerTableOldestFirstWithCurrentLast() {
        // M9-4 T2: retargeted to the v3 bump (the ledger table grows;
        // the inverse map stays the 1-based position face).
        XCTAssertEqual(RenderProcess.all, [.v1, .v2, .v3])
        XCTAssertEqual(RenderProcess.all.last, RenderProcess.current)
        XCTAssertEqual(RenderProcess.current, .v3)
        let inverse: [RenderProcess: Int] = [
            .v1: 1, .v2: 2, .v3: 3,
        ]
        for (generation, number) in inverse {
            XCTAssertEqual(generation.processVersion.rawValue, number,
                           "the case's number = its 1-based position in all")
        }
    }

    // MARK: - 2: the clamp table, four domains

    func testResolvingClampTableCoversTheFourDomains() {
        // raw ≤ 0 → the OLDEST case (the legacy freeze).
        XCTAssertEqual(RenderProcess.resolving(.legacy), .v1)
        // In-domain → its own case.
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 1)!), .v1)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 2)!), .v2)
        // M9-4 T2: v3 is an in-domain generation now; forward clamps to
        // current (the stored value never rewritten).
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 3)!), .v3)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 7)!), .v3)
        XCTAssertEqual(
            RenderProcess.resolving(RenderProcessVersion(rawValue: 0xFFFF_FFFF)!), .v3)
    }

    // MARK: - 3: the mint (the current generation = 2, the write face)

    func testMintWritesProcessTwoIntoTheSidecar() throws {
        // M9-4 T2: current = 3 (the name keeps the M8-2-era spelling).
        XCTAssertEqual(RenderProcessVersion.current.rawValue, 3,
                       "the M9-4 bump: the colorWheels generation mints")
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(uuidString: "B7B7B7B7-0000-4000-8000-00000000B7B7")!,
            decoderVersionUsed: "v8", decodeParamsHash: 0x1234,
            instances: [], history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0x1234),
            appVersion: "test", process: .current)
        let bytes = try JSONEncoder().encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["process"] as? Int, 3,
                       "a new document mints process=3 (the write face)")
        // The legacy nil face keeps the key ABSENT (the never-passively-
        // upgraded promise untouched by the bump).
        let legacy = LightamerSidecar(
            imageID: UUID(uuidString: "B7B7B7B7-0000-4000-8000-00000000B7B7")!,
            decoderVersionUsed: "v8", decodeParamsHash: 0x1234,
            instances: [], history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0x1234),
            appVersion: "test")
        let legacyBytes = try JSONEncoder().encode(legacy)
        let legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyBytes) as? [String: Any])
        XCTAssertFalse(legacyObject.keys.contains("process"),
                       "the nil (legacy) face keeps the key ABSENT")
    }

    // MARK: - 4: the fold negative (the「非 legacy 才折」contract)

    func testV1SeedStaysByteIdenticalAndV2OpensANewKeyspace() throws {
        let pair: UInt64 = 0x1234_5678_9ABC_DEF0
        let pack: UInt64 = 0x0FED_CBA9_8765_4321
        let upstream: UInt64 = 0x5555_5555_AAAA_AAAA
        let record = FilmRecord()
        let params = FilmTailParams(
            record: record, filmProfile: nil, paperProfile: nil,
            materialPairHash: pair)
        let recordHash = params.recordHash

        // The canonical 3-arg fold (the density arm's face — byte-stable
        // since M3-3-02; FilmLegTests pins its discriminations).
        let canonical = FilmTailAssembly.seed(
            upstream: upstream, params: params, solvedPackHash: pack)

        // v1 document: byte-identical to the canonical fold (the frozen tag).
        XCTAssertEqual(
            FilmTailAssembly.seed(
                upstream: upstream, params: params, solvedPackHash: pack,
                renderProcess: RenderProcessVersion(rawValue: 1)!),
            canonical,
            "a v1 document's seed IS the canonical fold (the key freeze)")
        // Legacy document: byte-identical too.
        XCTAssertEqual(
            FilmTailAssembly.seed(
                upstream: upstream, params: params, solvedPackHash: pack,
                renderProcess: .legacy),
            canonical, "a legacy document's seed IS the canonical fold")

        // v2 document: the SAME four-term canonical order with the
        // spectral tag — the exact FNV recomputation (the fold order never
        // changed, only the tag's value per arm).
        var h: UInt64 = 0xCBF29CE484222325
        for shift in stride(from: 0, through: 56, by: 8) {
            h ^= (recordHash >> UInt64(shift)) & 0xFF
            h = h &* 0x100000001B3
        }
        for byte in "lightamer.film.subrun.v2-spectral".utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001B3
        }
        for shift in stride(from: 0, through: 56, by: 8) {
            h ^= (pack >> UInt64(shift)) & 0xFF
            h = h &* 0x100000001B3
        }
        for shift in stride(from: 0, through: 56, by: 8) {
            h ^= (upstream >> UInt64(shift)) & 0xFF
            h = h &* 0x100000001B3
        }
        let spectral = FilmTailAssembly.seed(
            upstream: upstream, params: params, solvedPackHash: pack,
            renderProcess: RenderProcessVersion(rawValue: 2)!)
        XCTAssertEqual(spectral, h,
                       "the v2 seed folds the spectral tag in the canonical order")
        XCTAssertNotEqual(spectral, canonical,
                          "the spectral tag opens a keyspace no legacy key shares")
    }

    // MARK: - 5: the deferred v2 payload shape (the arm's shape face)

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

    func testFactoryResolvesTheSpectralArmForAV2Document() async throws {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let film = try portra
        let paper = try endura
        let image = CIImage(
            color: CIColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1)
        ).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24))
        let decoded = DecodedImage(
            ciImage: image,
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
        let (plane, _) = try await RenderPipeline.process(
            image: decoded, instances: [], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal)
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()

        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)

        // The v1 document → the density shape (payloads face).
        let v1 = PixelPipe.assembleFilmLeg(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: nil,
            plane: plane, metal: metal,
            renderProcess: RenderProcessVersion(rawValue: 1)!)
        XCTAssertNotNil(v1.payloads, "v1 resolves the density arm")
        XCTAssertNil(v1.spectralPayloads, "v1 carries no spectral payloads")

        // The v2 document → the spectral shape (spectralPayloads face).
        let v2 = PixelPipe.assembleFilmLeg(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: nil,
            plane: plane, metal: metal,
            renderProcess: RenderProcessVersion(rawValue: 2)!)
        XCTAssertNil(v2.payloads, "v2 carries no density payloads")
        XCTAssertNotNil(v2.spectralPayloads,
                        "v2 resolves the spectral arm (the bump made it real)")
        XCTAssertNotEqual(v2.solvedPackHash, 0, "the spectral solve solved")
        // The arms are mutually exclusive per assembly.
        XCTAssertNotEqual(v1.method, v2.method,
                          "the two arms' solved params differ (different cores)")
        // The solved CCs differ from the density solver's neutral pack —
        // the two cores solve their own neutrals in their own domains.
        XCTAssertGreaterThan(v2.method.magentaCC, 0,
                             "the spectral neutral M is the build's solved pair")
        XCTAssertGreaterThan(v2.method.yellowCC, 0,
                             "the spectral neutral Y is the build's solved pair")
    }
}
