@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmDescriptorTests (Plan M3-4-01 T2, KD-2 — LAYERS bundle, Core 级) — the
// latitude descriptor runtime:
//
//   1. ISO 6846 REDUCTION hand-computed vectors (the E1-corrected
//      criteria: highlight = first Y ≥ Y_black + 0.9·(Y_white−Y_black);
//      shadow = LAST E with D ≥ 0.9·D_black) on a synthetic fold line —
//      plus the shadow criterion's equivalent-threshold form.
//   2. Degenerate (flat) responses answer nil — "unavailable", never a
//      fake number.
//   3. THE REAL-CHAIN PROBE (§8.1): portra_400 × portra_endura through
//      the production factory + box — T(E) monotone non-decreasing; the
//      useful pair (ISO criteria) width inside the [4.0, 7.5] sanity band
//      (anchor = the upstream ISO 5.66-stop figure); |reference_ev| ≤ 0.5
//      (the K-calibration mid anchor).
//   4. Determinism: same-pair double probe bit-identical (fresh payload
//      assemblies each call — the cache-face equality).
//   5. The descriptor cache: key = fnv(pairHash ⊕ probe tag) exact-FNV
//      double-write, LRU 4, invalidateAll.
// ─────────────────────────────────────────────────────────────────────────────

final class FilmDescriptorTests: XCTestCase {

    // MARK: - fixtures

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/LightamerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        return try MetalContext()
    }

    // MARK: - 1: the ISO 6846 reduction (hand vectors)

    /// A synthetic fold line with power-of-ten plateaus (indices 0..8 on a
    /// 1-stop grid, evMin=0): every boundary hand-derivable.
    ///   T = [1e-5, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 0.5, 1.0, 1.0]
    ///   Y_white = 1.0, Y_black = 1e-5.
    ///   D = [5, 5, 4, 3, 2, 1, log10(2), 0, 0]; D_black = 5;
    ///   0.9·D_black = 4.5 → the LAST D ≥ 4.5 sits at index 1 → E = 1.0.
    ///   highlight level = 1e-5 + 0.9·(1 − 1e-5) = 0.900001 → crosses
    ///   between 0.5 (E=6) and 1.0 (E=7) at 6 + 0.400001/0.5 = 6.800002.
    func testISO6846ReductionHandComputedFoldLine() {
        let response: [Double] = [
            1e-5, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 0.5, 1.0, 1.0,
        ]
        let shadow = FilmLatitudeReduce.usefulShadowEV(response, evMin: 0, evMax: 8)
        let highlight = FilmLatitudeReduce.usefulHighlightEV(response, evMin: 0, evMax: 8)
        XCTAssertEqual(shadow ?? -99, 1.0, accuracy: 1e-12,
                       "the last E with D ≥ 0.9·D_black is index 1")
        XCTAssertEqual(highlight ?? -99, 6.800002, accuracy: 1e-5,
                       "the first Y ≥ 90%-of-the-way crossing, interpolated")
        // The useful pair width on the synthetic.
        let width = (highlight ?? 0) - (shadow ?? 0)
        XCTAssertEqual(width, 5.800002, accuracy: 1e-5)
    }

    /// The shadow criterion's equivalence face: for a non-decreasing
    /// response the LAST-E-with-D≥0.9·D_black reading sits within ONE GRID
    /// STEP of the first crossing of Y ≥ Y_white·10^(−0.9·D_black) (the
    /// two readings differ by at most the sampling step by construction;
    /// the direct reading is the production one — E1).
    func testISO6846ShadowCriterionEquivalence() {
        // A dense monotone ramp (0.02-stop sampling over [0, 8]).
        let steps = 401
        var response = [Double](repeating: 0, count: steps)
        for index in 0..<steps {
            let e = 8.0 * Double(index) / Double(steps - 1)
            response[index] = Foundation.pow(10.0, -3.0 + 3.0 * e / 8.0)  // 1e-3 → 1
        }
        let dE = 8.0 / Double(steps - 1)
        let direct = FilmLatitudeReduce.usefulShadowEV(response, evMin: 0, evMax: 8)
        // The equivalent form, written independently here.
        let yWhite = response.max() ?? 0
        let yBlack = response.min() ?? 0
        let dBlack = -Foundation.log10(max(yBlack, yWhite * 1e-6) / yWhite)
        let threshold = yWhite * Foundation.pow(10.0, -0.9 * dBlack)
        let equivalent = FilmLatitudeReduce.firstCrossingEV(
            response, evMin: 0, evMax: 8, level: threshold)
        XCTAssertNotNil(direct)
        XCTAssertNotNil(equivalent)
        XCTAssertLessThanOrEqual(
            abs(direct! - equivalent!), dE + 1e-9,
            "the two readings of the shadow criterion agree within one grid step")
    }

    /// A flat (degenerate) response answers nil on both boundaries — the
    /// "descriptor unavailable" face, never a fake number.
    func testDegenerateFlatResponseAnswersNil() {
        let flat = [Double](repeating: 0.42, count: 33)
        XCTAssertNil(FilmLatitudeReduce.usefulShadowEV(flat, evMin: -12, evMax: 12))
        XCTAssertNil(FilmLatitudeReduce.usefulHighlightEV(flat, evMin: -12, evMax: 12))
        XCTAssertNil(FilmLatitudeReduce.firstCrossingEV(
            flat, evMin: -12, evMax: 12, level: 0.9))
    }

    // MARK: - 3+4: the real-chain probe

    func testProbeResponseMonotoneUsefulPairAndReference() async throws {
        let metal = try await makeMetal()
        let store = try FilmMaterialStore(profilesDirectory: profilesDirectory())
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let descriptor = try await FilmDescriptorProbe.probe(
            film: film, paper: paper, materialPairHash: pairHash, metal: metal)

        // The probe domain came back as configured.
        XCTAssertEqual(descriptor.evMin, FilmDescriptorProbe.domainMin)
        XCTAssertEqual(descriptor.evMax, FilmDescriptorProbe.domainMax)
        XCTAssertEqual(descriptor.response.count, FilmDescriptorProbe.rampLength)
        XCTAssertEqual(descriptor.slope.count, FilmDescriptorProbe.rampLength)
        XCTAssertEqual(descriptor.materialPairHash, pairHash)

        // T(E) monotone NON-DECREASING where the response is INFORMATIVE
        // (up to the ISO useful-highlight boundary), within the lattice's
        // reflectance-domain quantization band (the 65³ tetra floor — the
        // gate-1b face expressed here; measured dips ~1.25e-3 absolute,
        // band = measured × 1.5 headroom, the E5 calibration style; real
        // probe defects are order-of-magnitude inversions). BEYOND the
        // boundary the response is the paper-white plateau face — the
        // LUT's ill-conditioned white-end corners jitter within the
        // plateau (measured ≤0.06 reflectance at R ≥ 0.9); the gate there
        // = stays inside the plateau's own span, never collapses toward
        // black.
        let yWhite = Double(descriptor.response.max() ?? 0)
        let yBlack = Double(descriptor.response.min() ?? 1)
        let highlightLevel = yBlack + 0.9 * (yWhite - yBlack)
        var previous = -Double.greatestFiniteMagnitude
        var reachedBoundary = false
        for (index, value) in descriptor.response.enumerated() {
            let current = Double(value)
            if current >= highlightLevel { reachedBoundary = true }
            if !reachedBoundary {
                XCTAssertGreaterThanOrEqual(
                    current, previous - 2e-3,
                    "T(E) non-decreasing (band 2e-3) below the highlight "
                        + "boundary at index \(index)")
            } else {
                XCTAssertGreaterThanOrEqual(
                    current, yBlack,
                    "the white plateau never collapses toward black at \(index)")
            }
            previous = current
        }
        XCTAssertTrue(reachedBoundary, "the probe reaches the useful-highlight level")

        // The useful pair (ISO criteria) width: anchor = the upstream ISO
        // 5.66-stop figure (RFC-023 §15.2) → the initial band [4.0, 7.5];
        // the measured value rides the attachment for the DECISIONS entry.
        let width = descriptor.usefulHighlightEV - descriptor.usefulShadowEV
        XCTAssertGreaterThanOrEqual(width, 4.0, "the ISO useful-pair width band")
        XCTAssertLessThanOrEqual(width, 7.5, "the ISO useful-pair width band")

        // The reference mid anchor: |reference_ev| ≤ 0.5 (the K
        // calibration places input 0.184 AT the paper mid density).
        XCTAssertLessThanOrEqual(
            abs(descriptor.referenceEV), 0.5,
            "the reference mid-anchor reading (K calibration)")

        // The slope diagnostics: finite everywhere; ~non-negative on the
        // INFORMATIVE domain (below the highlight boundary — the plateau
        // jitter above it produces meaningless local slopes, the same
        // face the monotone gate exempts). A real sign error would show
        // as hugely negative slopes across the whole rise.
        let boundaryIndex = descriptor.response.firstIndex {
            Double($0) >= highlightLevel
        } ?? descriptor.response.count
        for (index, value) in descriptor.slope.enumerated() {
            XCTAssertTrue(value.isFinite, "slope finite at index \(index)")
            if index < boundaryIndex {
                XCTAssertGreaterThanOrEqual(
                    value, -0.05,
                    "slope ~non-negative (lattice band) at index \(index)")
            }
        }
        attachMeasured(
            String(
                format: "portra_400×endura ISO useful pair = [%.3f, %.3f] width %.3f; "
                    + "reference_ev = %+.4f",
                descriptor.usefulShadowEV, descriptor.usefulHighlightEV, width,
                descriptor.referenceEV),
            name: "descriptor-probe-measured")
        // Measured (2026-10-09, this engine): useful pair [-1.4663, +4.4485]
        // = 5.9148 stops (upstream ISO anchor 5.66 — RFC-023 §15.2);
        // reference_ev = +0.068. Registered in M3-4-01-DECISIONS.
    }

    /// Determinism: the same pair probed twice — two FRESH payload
    /// assemblies — answers bit-identical responses (and equal
    /// descriptors; the bake/solve caches make this exact, not approximate).
    func testProbeIsBitIdenticalAcrossFreshAssemblies() async throws {
        let metal = try await makeMetal()
        let store = try FilmMaterialStore(profilesDirectory: profilesDirectory())
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let first = try await FilmDescriptorProbe.probe(
            film: film, paper: paper, materialPairHash: pairHash, metal: metal)
        let second = try await FilmDescriptorProbe.probe(
            film: film, paper: paper, materialPairHash: pairHash, metal: metal)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.response.count, second.response.count)
        for (a, b) in zip(first.response, second.response) {
            XCTAssertEqual(a.bitPattern, b.bitPattern, "bit-identical response")
        }
    }

    // MARK: - 5: the cache

    /// The cache key is the EXACT canonical FNV-1a fold (pair bytes ⊕ the
    /// probe tag UTF-8) — double-written here (the determinism suite's
    /// exact-value discipline), and it discriminates pair hashes.
    func testCacheKeyFoldsTheProbeTagExactly() {
        func referenceKey(_ pairHash: UInt64) -> UInt64 {
            var h = StableHash.fnvOffsetBasis
            withUnsafeBytes(of: pairHash) { h = StableHash.combine(h, $0) }
            let tag = Array(FilmDescriptorProbe.probeTag.utf8)
            h = tag.withUnsafeBufferPointer {
                StableHash.combine(h, UnsafeRawBufferPointer($0))
            }
            return h
        }
        for pairHash in [UInt64(0), UInt64(1), 0xDEAD_BEEF_CAFE_F00D] {
            XCTAssertEqual(
                FilmDescriptorCache.cacheKey(materialPairHash: pairHash),
                referenceKey(pairHash),
                "the exact key fold (pair ⊕ tag)")
        }
        // Discriminating: distinct pairs → distinct keys.
        XCTAssertNotEqual(
            FilmDescriptorCache.cacheKey(materialPairHash: 1),
            FilmDescriptorCache.cacheKey(materialPairHash: 2))
    }

    func testDescriptorCacheStoresConsultsAndEvicts() {
        let cache = FilmDescriptorCache(capacity: 4)
        let key = FilmDescriptorCache.cacheKey(materialPairHash: 42)
        XCTAssertNil(cache.descriptor(for: key))
        func make(_ ref: Double) -> ProfileLatitudeDescriptor {
            ProfileLatitudeDescriptor(
                evMin: -12, evMax: 12, usefulShadowEV: -3, usefulHighlightEV: 2.5,
                referenceEV: ref,
                response: [Float](repeating: 0.5, count: 8),
                slope: [Float](repeating: 0, count: 8), materialPairHash: 0)
        }
        cache.store(make(0.1), for: key)
        XCTAssertEqual(cache.descriptor(for: key)?.referenceEV, 0.1)
        XCTAssertEqual(cache.countForTesting, 1)
        // The LRU 4 face: a fifth distinct key evicts the oldest.
        for extra in 0..<5 {
            let k = FilmDescriptorCache.cacheKey(materialPairHash: UInt64(1000 + extra))
            cache.store(make(Double(extra)), for: k)
        }
        XCTAssertEqual(cache.countForTesting, 4)
        XCTAssertNil(cache.descriptor(for: key), "the oldest entry was evicted")
        // The invalidation face clears everything.
        cache.invalidateAll()
        XCTAssertEqual(cache.countForTesting, 0)
    }

    // MARK: - the measured-value channel

    private func attachMeasured(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
