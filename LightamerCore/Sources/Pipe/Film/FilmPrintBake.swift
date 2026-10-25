import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// FilmPrintBake (Plan M3-3-02 T2, KD-3) — the print-segment 65³ composite
// table per film×paper pair, the `bakedCompositeTable` mechanism shape
// (65³ / Float64 CPU reference / concurrentPerform per lattice slice / LRU
// 16) self-held here: `LutEncodingCatalog` is ZERO-TOUCHED (the research
// red line — the catalog is the user LUT encoding-choice face; the film
// bake domain is an internal per-pair calibration, never a catalog row).
//
// DOMAIN RULING (KD-3's RESEARCH §4.3兑现): the print LUT input domain is
// the NORMALIZED NEGATIVE-DENSITY CUBE — the negative-segment density AFTER
// the filter-pack density shift (d′ = d − k, the algebraic twin of the
// solver's print-exposure form x = −d + k; the E3 channel mapping: the
// Magenta dial acts on GREEN, the Yellow dial on BLUE). Linear-domain LUT
// input was rejected (the filter gain is a density-domain scalar — the
// study's own erratum); the density cube is what makes "one LUT serves all
// filter combinations" hold.
//
// CONTENT (per voxel, per channel c):
//   1. d′_c  — the cube coordinate decoded back to density;
//   2. x_c   = −d′_c                       (the print exposure);
//   3. P_c   = paperCurve_c(x_c)           (status-A print density);
//   4. P′_c  = P_c − Dmin_c                (paper white → 0);
//   5. the FILM-CHANNEL INVERSION (RFC-028's gray-error-exactly-0
//      discipline — the inversion must use the film's own channel curves):
//      find e_c with SysC_c(e_c) = P′_c, where
//      SysC_c(e) = paperCurve_c(−(filmCurve_c(e) + base_c)) − Dmin_c
//      is the composite system response along the neutral axis (monotone
//      decreasing → bracketed bisection on the fixed log-exposure axis);
//   6. out_c = 10^(e_c)                    (scene-linear Rec2020; a
//      mid-gray round-trip is EXACT under the neutral pack — gray error 0).
// The "film terms" inversion (undo the curve completely) leaves the print
// flat and wide — the display tone belongs to the DRT tail (the
// architecture's scene-referred posture).
//
// DETERMINISM: Float64 channel math, concurrentPerform per lattice slice
// (deterministic index merge, no await), fixed bisection ladder — a double
// bake of the same pair is BIT-IDENTICAL (test-pinned). The baked table is
// Float32 STORAGE of Float64-computed values (the Lut3d bake posture).
//
// LICENSING: consumes the CC BY-SA profile data through the typed loader
// (the consumer-keys contract); no asset bytes are embedded or modified.
// ─────────────────────────────────────────────────────────────────────────────

/// One baked print table + its calibrated cube domain (per-pair; the bounds
/// ride WITH the table — the kernel consumes both as one unit).
public struct FilmPrintTable: Sendable, Equatable {
    /// The lattice level (65 — the bakedCompositeTable convention).
    public static let level = 65

    /// The composite table, lattice-ordered x + y·L + z·L² (RGB in .rgb).
    public let data: [SIMD3<Float>]
    /// The calibrated density-cube bounds (per channel): the film's density
    /// range over its log-exposure axis WIDENED by the filter-gain headroom
    /// (the pack shifts density DOWN by up to k_max = 100 CC × s).
    public let domainLo: SIMD3<Float>
    public let domainHi: SIMD3<Float>

    public init(data: [SIMD3<Float>], domainLo: SIMD3<Float>, domainHi: SIMD3<Float>) {
        self.data = data
        self.domainLo = domainLo
        self.domainHi = domainHi
    }

    public static func == (lhs: FilmPrintTable, rhs: FilmPrintTable) -> Bool {
        lhs.domainLo == rhs.domainLo && lhs.domainHi == rhs.domainHi
            && lhs.data.elementsEqual(rhs.data)
    }
}

public enum FilmPrintBake {

    /// The film log-exposure axis' bounds the solver family shares (the
    /// assets' 256-point −3…+4 axis — read per-profile at bake time, these
    /// constants only seed the clamp guards).
    public static let logExposureFloor = -3.0
    public static let logExposureCeiling = 4.0

    // MARK: - The bake (KD-3)

    /// Bake the print table for one pair. Float64 channel math throughout;
    /// the lattice slices run on the cooperative-perform pool.
    public static func bake(film: FilmProfile, paper: FilmProfile) throws -> FilmPrintTable {
        let level = FilmPrintTable.level
        let count = level * level * level
        let base = try film.baseDensityProjection()

        // The film density range over the axis (per channel) + the filter
        // headroom — the cube bounds (KD-3: film density domain + base +
        // gain headroom, per-pair calibrated, carried with the table).
        let axisLo = Double(film.logExposure.first ?? Float(logExposureFloor))
        let axisHi = Double(film.logExposure.last ?? Float(logExposureCeiling))
        var densityLo = SIMD3<Double>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var densityHi = SIMD3<Double>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        for i in 0..<film.logExposure.count {
            for c in 0..<3 {
                let d = Double(film.densityCurves[i][c])
                densityLo[c] = min(densityLo[c], d)
                densityHi[c] = max(densityHi[c], d)
            }
        }
        // The E3 filter vectors: M → G with s_m, Y → B with s_y (density
        // SUBTRACTED). Headroom = the full 100-CC dial travel.
        let headroom = SIMD3<Double>(
            0, 100 * FilmFilterPackSolver.magentaExposurePerCC,
            100 * FilmFilterPackSolver.yellowExposurePerCC)
        let domainLo = densityLo + SIMD3<Double>(base.r, base.g, base.b) - headroom
        let domainHi = densityHi + SIMD3<Double>(base.r, base.g, base.b)

        // The paper's per-channel Dmin (the curve minimum over the paper's
        // own axis — the paper-white floor of step 4).
        var dmin = SIMD3<Double>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        for i in 0..<paper.logExposure.count {
            for c in 0..<3 {
                dmin[c] = min(dmin[c], Double(paper.densityCurves[i][c]))
            }
        }

        // The per-pair EXPOSURE CALIBRATION K (the enlarger's exposure
        // time — the common print-exposure term, identical on all three
        // channels): the SOLVED-SESSION mid-gray must print at the paper's
        // mid density. Without it the negative densities (≥ ~0.5 + base)
        // only ever reach the paper's TOE; calibrating on the PACK-SHIFTED
        // density (the session's actual operating point — the neutral pack
        // rides the input coordinate) keeps the mid-gray print ON the
        // paper's working range. Monotone in K → bracketed bisection.
        let paperMidGreen = (dmin[1] + maxGreen(paper)) / 2
        let eMid = Foundation.log10(midGraySceneValue)
        let neutralPack = try FilmFilterPackSolver.solveNeutralPack(
            film: film, paper: paper)
        let sessionMidGreenDensity = FilmFilterPackSolver.curveValue(
            film, channel: 1, at: eMid) + base.g
            - neutralPack.magentaCC * FilmFilterPackSolver.magentaExposurePerCC
        let calibration = solveExposureCalibration(
            film: film, paper: paper, base: base,
            midGrayDensity: sessionMidGreenDensity,
            paperMid: paperMidGreen)

        var table = [SIMD3<Float>](repeating: .zero, count: count)
        let span = domainHi - domainLo
        table.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: level) { z in
                for y in 0..<level {
                    let baseIndex = z * level * level + y * level
                    for x in 0..<level {
                        let d = Double(level - 1)
                        let voxel = SIMD3<Double>(
                            Double(x) / d, Double(y) / d, Double(z) / d)
                        // Step 1-2: the cube coordinate → print exposure
                        // (the K calibration is the COMMON term — baked in).
                        let density = domainLo + voxel * span
                        var mapped = SIMD3<Double>()
                        for c in 0..<3 {
                            let printExposure = -density[c] + calibration
                            // Step 3-4: paper density, minus Dmin.
                            let paperDensity = max(
                                FilmFilterPackSolver.curveValue(
                                    paper, channel: c, at: printExposure)
                                    - dmin[c], 0)
                            // Step 5: the film-channel inversion — find the
                            // neutral-axis exposure whose system response
                            // equals the print density (monotone decreasing
                            // → bracketed bisection on the fixed axis).
                            // Step 6: out = 10^e — the scene-linear face.
                            let e = invertSystem(
                                film: film, paper: paper, base: base,
                                channel: c, targetDensity: paperDensity,
                                dmin: dmin[c], axisLo: axisLo, axisHi: axisHi,
                                calibration: calibration,
                                packM: neutralPack.magentaCC
                                    * FilmFilterPackSolver.magentaExposurePerCC,
                                packY: neutralPack.yellowCC
                                    * FilmFilterPackSolver.yellowExposurePerCC)
                            mapped[c] = Foundation.pow(10.0, e)
                        }
                        buffer[baseIndex + x] = SIMD3<Float>(
                            Float(mapped.x), Float(mapped.y), Float(mapped.z))
                    }
                }
            }
        }
        return FilmPrintTable(
            data: table,
            domainLo: SIMD3<Float>(domainLo),
            domainHi: SIMD3<Float>(domainHi))
    }

    /// The mid-gray the calibration anchors (the solver's 0.184 — one
    /// constant source value; spelled locally to avoid an IOP-facing import
    /// cycle in docs).
    static let midGraySceneValue = FilmFilterPackSolver.midGraySceneLinear

    /// The paper green curve's maximum (the density-range top).
    static func maxGreen(_ paper: FilmProfile) -> Double {
        paper.densityCurves.reduce(-Double.greatestFiniteMagnitude) {
            max($0, Double($1[1]))
        }
    }

    /// The per-pair exposure calibration: find K with
    /// paperCurve_G(−(curve_G(e_mid) + base_G) + K) = paperMidGreen —
    /// monotone rising in K → bracketed bisection (fixed ladder).
    static func solveExposureCalibration(
        film: FilmProfile, paper: FilmProfile, base: (r: Double, g: Double, b: Double),
        midGrayDensity: Double, paperMid: Double
    ) -> Double {
        func residual(_ k: Double) -> Double {
            FilmFilterPackSolver.curveValue(paper, channel: 1, at: -midGrayDensity + k)
                - paperMid
        }
        var lo = -5.0   // F < 0 (underexposed — the paper's toe)
        var hi = 12.0   // F > 0 (past Dmax)
        if residual(lo) > 0 { return lo }
        if residual(hi) < 0 { return hi }
        for _ in 0..<FilmFilterPackSolver.maxIterations {
            let mid = (lo + hi) / 2
            if residual(mid) < 0 {
                lo = mid
            } else {
                hi = mid
            }
            if hi - lo < FilmFilterPackSolver.convergenceEpsilon { break }
        }
        return (lo + hi) / 2
    }

    /// The composite SESSION system response SysC_c(e) (step 5's forward
    /// face; the calibration K rides the per-pair bake that closes over
    /// it). The SESSION density subtracts the solved pack (the E3 channel
    /// mapping: M → G with s_m, Y → B with s_y) — the inverse of the
    /// session system is what the LUT content needs (the kernel's input
    /// coordinate is the post-pack density).
    static func systemDensity(
        film: FilmProfile, paper: FilmProfile, base: (r: Double, g: Double, b: Double),
        channel: Int, exposure e: Double, dmin: Double, calibration: Double,
        packM: Double, packY: Double
    ) -> Double {
        let pack = channel == 1 ? packM : (channel == 2 ? packY : 0)
        let negative = FilmFilterPackSolver.curveValue(film, channel: channel, at: e)
            + [base.r, base.g, base.b][channel] - pack
        return max(
            FilmFilterPackSolver.curveValue(paper, channel: channel, at: -negative + calibration) - dmin, 0)
    }

    /// The bracketed bisection inverse of SysC (fixed 60-halving ladder on
    /// the film axis — deterministic; the flat clamped ends map the axis
    /// ends, the same closure the forward curves have).
    static func invertSystem(
        film: FilmProfile, paper: FilmProfile, base: (r: Double, g: Double, b: Double),
        channel: Int, targetDensity: Double,
        dmin: Double, axisLo: Double, axisHi: Double, calibration: Double,
        packM: Double, packY: Double
    ) -> Double {
        // SysC is DECREASING in e: high exposure → dense negative → less
        // print exposure → less paper density. F(e) = SysC(e) − target:
        // positive at the axis bottom (dense paper), negative at the top.
        var lo = axisLo   // F(lo) > 0 (dense end)
        var hi = axisHi   // F(hi) < 0 (clear end)
        let fLo = systemDensity(
            film: film, paper: paper, base: base, channel: channel,
            exposure: lo, dmin: dmin, calibration: calibration,
            packM: packM, packY: packY) - targetDensity
        if fLo <= 0 { return lo }
        let fHi = systemDensity(
            film: film, paper: paper, base: base, channel: channel,
            exposure: hi, dmin: dmin, calibration: calibration,
            packM: packM, packY: packY) - targetDensity
        if fHi >= 0 { return hi }
        for _ in 0..<FilmFilterPackSolver.maxIterations {
            let mid = (lo + hi) / 2
            let fMid = systemDensity(
                film: film, paper: paper, base: base, channel: channel,
                exposure: mid, dmin: dmin, calibration: calibration,
                packM: packM, packY: packY) - targetDensity
            if fMid > 0 {
                lo = mid
            } else {
                hi = mid
            }
            if hi - lo < FilmFilterPackSolver.convergenceEpsilon { break }
        }
        return (lo + hi) / 2
    }

    // MARK: - The per-pair LRU (the bakedCompositeTable LRU 16 shape)

    /// The bake cache: NSLock + dictionary + insertion-order LRU 16, keyed
    /// by `FilmMaterialStore.materialPairHash` (the 01 identity single
    /// source). A cache HIT returns the SAME table instance — the bake is
    /// deterministic, so hit-vs-miss is value-invisible (the test pins the
    /// bit-identity through a forced re-bake).
    public final class Cache: @unchecked Sendable {
        /// The process-wide cache (the bake is a pure function of the pair —
        /// sharing across pipes is value-invisible).
        public static let shared = Cache()

        private let lock = NSLock()
        private var tables: [UInt64: FilmPrintTable] = [:]
        private var order: [UInt64] = []
        private let capacity: Int

        public init(capacity: Int = 16) {
            self.capacity = capacity
        }

        public func table(
            forPairHash pairHash: UInt64,
            film: FilmProfile, paper: FilmProfile
        ) throws -> FilmPrintTable {
            lock.lock()
            if let hit = tables[pairHash] {
                // Touch: move to the MRU end.
                order.removeAll { $0 == pairHash }
                order.append(pairHash)
                lock.unlock()
                return hit
            }
            lock.unlock()
            // Bake OUTSIDE the lock (the bake is the expensive leg; the
            // same-pair concurrent bake bakes twice and both land — the
            // value-identical determinism makes the race harmless).
            let baked = try bake(film: film, paper: paper)
            lock.lock()
            tables[pairHash] = baked
            order.append(pairHash)
            while order.count > capacity {
                let evicted = order.removeFirst()
                tables.removeValue(forKey: evicted)
            }
            lock.unlock()
            return baked
        }

        /// Test face: the cached entry count.
        public var countForTesting: Int {
            lock.lock()
            defer { lock.unlock() }
            return tables.count
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SpectralPrintBake (Plan M8-2 T3, X7) — the spectral film core's per-pair
// bake cache family, the FilmPrintBake.Cache mechanism shape (NSLock +
// dictionary + insertion-order LRU + observable counts) applied to the
// M8-1a build engine's products:
//
//   • the TC_LUT SLOT — the build bundle itself (`SpectralFilmTables`):
//     the tc_lut carries its upstream fit + expand + integrate FULL cost
//     (the seconds-band build), and the engine emits it as one monolithic
//     Float64 build together with the PCHIP sets and the curve faces
//     (inseparable — the engine is zero-diff frozen), so the tc slot's
//     value is the whole bundle. This is the slot X7 names ("构建引擎的
//     tc_lut 产物跨 run 缓存——禁每 run 重建、禁逐帧重建");
//   • the PRINT PCHIP SLOT and the SCAN PCHIP SLOT — the two 33³
//     monotone-PCHIP sets as named slices, each its OWN LRU (X7: the three
//     slots 并存、各自 LRU 槽互不挤兑 — one family's eviction never touches
//     another's). Capacities are DECISIONS-declared (tc 6 / print 8 /
//     scan 8 — the bundle is ~5.6 MB, so the tc slot caps at ~34 MB).
//
// The consult facade fills all three slots from ONE build under a build
// lock (the seconds-band build serializes; a concurrent cold-start miss
// waits instead of building twice), and a tc-slot HIT touches the PCHIP
// slices (fill-if-missing from the hit bundle — no rebuild). The slots
// are keyed by `FilmMaterialStore.materialPairHash` (the 01 identity
// single source, the FilmSolveCache key-shape precedent).
// ─────────────────────────────────────────────────────────────────────────────

public enum SpectralPrintBake {

    /// One per-pair LRU slot (the mechanism-twin of `FilmPrintBake.Cache`:
    /// NSLock + dictionary + insertion-order LRU). `bakeCount` observes how
    /// many fills the slot performed (a re-fill of an existing key counts —
    /// it replaced the slot's content; a consult touch does not).
    public final class Slot<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [UInt64: Value] = [:]
        private var order: [UInt64] = []
        private let capacity: Int
        private var fills = 0

        public init(capacity: Int) {
            self.capacity = max(capacity, 1)
        }

        /// Consult + LRU touch (nil = miss).
        public func consult(_ key: UInt64) -> Value? {
            lock.lock()
            defer { lock.unlock() }
            guard let hit = entries[key] else { return nil }
            order.removeAll { $0 == key }
            order.append(key)
            return hit
        }

        /// Insert or replace + evict the LRU tail beyond capacity.
        public func store(_ value: Value, for key: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            entries[key] = value
            if !order.contains(key) { order.append(key) }
            fills += 1
            while order.count > capacity {
                let evicted = order.removeFirst()
                entries.removeValue(forKey: evicted)
            }
        }

        /// Test face: the cached entry count.
        public var countForTesting: Int {
            lock.lock()
            defer { lock.unlock() }
            return entries.count
        }

        /// Test face: the fill count (the bakeCount-observable form).
        public var bakeCountForTesting: Int {
            lock.lock()
            defer { lock.unlock() }
            return fills
        }
    }

    /// The tc_lut slot (the full build bundle — X7's named face).
    public static let tcLutSlot = Slot<SpectralFilmTables>(capacity: 6)
    /// The print PCHIP slot (the 33³ print set).
    public static let printSlot = Slot<SpectralFilmPchipSet>(capacity: 8)
    /// The scan PCHIP slot (the 33³ scan set).
    public static let scanSlot = Slot<SpectralFilmPchipSet>(capacity: 8)

    /// The seconds-band build serializes (a concurrent cold-start miss
    /// waits; the build is deterministic so either order lands the same
    /// bytes).
    private static let buildLock = NSLock()

    /// The consult facade the spectral film arm's payload construction
    /// consumes (X7's "T1 光谱臂 payload 构造消费缓存命中面"): a tc-slot
    /// hit returns the SAME bundle instance (the build is deterministic —
    /// hit-vs-miss is value-invisible) and touches the PCHIP slices; a
    /// miss builds ONCE and fills all three slots.
    public static func tables(
        forPairHash pairHash: UInt64, film: FilmProfile, paper: FilmProfile
    ) throws -> SpectralFilmTables {
        if let hit = tcLutSlot.consult(pairHash) {
            touchPchipSlices(of: hit, for: pairHash)
            return hit
        }
        buildLock.lock()
        defer { buildLock.unlock() }
        // Double-check under the build lock (a concurrent builder filled).
        if let hit = tcLutSlot.consult(pairHash) {
            touchPchipSlices(of: hit, for: pairHash)
            return hit
        }
        let built = try SpectralBuildEngine.build(film: film, paper: paper)
        tcLutSlot.store(built, for: pairHash)
        printSlot.store(built.print, for: pairHash)
        scanSlot.store(built.scan, for: pairHash)
        return built
    }

    /// Fill-if-missing the PCHIP slices from a hit bundle (no rebuild —
    /// the slices ARE the bundle's own values, bit-identical by
    /// construction; the test pins the bit face).
    private static func touchPchipSlices(
        of bundle: SpectralFilmTables, for pairHash: UInt64
    ) {
        if printSlot.consult(pairHash) == nil {
            printSlot.store(bundle.print, for: pairHash)
        }
        if scanSlot.consult(pairHash) == nil {
            scanSlot.store(bundle.scan, for: pairHash)
        }
    }
}
