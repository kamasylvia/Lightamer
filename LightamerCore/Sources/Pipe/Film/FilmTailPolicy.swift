import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// FilmTailPolicy / FilmTailParams / FilmTailAssembly / FilmMethodBox
// (Plan M3-3-02 T1, KD-1) — the film sub-run seam. DrtTailAssembly's
// structural twin (PixelPipe.swift): a driver-constructed box set + a seed
// fold, run as a sub-run pipe at the fixed point AFTER the main chain's top
// plane and BEFORE the display tail.
//
// SEAM INVARIANT (KD-1's physical reading): the film consumes the
// PRE-colorout float32 working-linear plane (after placement/grades, before
// display encoding) and emits float32 working-linear Rec2020 — display
// encoding always happens AFTER film (legacy colorout→gamma, EDR colorout,
// or the DRT tail). The demotion arms live in `PixelPipe
// .isTerminalTailSkipped` (the 3×2 terminal-tail × film interaction matrix,
// checker E4); the replay chains live in `PixelPipe.runFilmDisplayReplayLeg`.
//
// SEED (KD-1, L013 fold order): fnv(recordHash ⊕ policyTag ⊕
// solvedPackHash ⊕ upstream) — the solvedPackHash fold makes a solve-only
// change (statistics/material/mode) re-run exactly the film sub-run, and a
// record-field change (strength/exposureEv/Y-M shifts ride the record hash)
// does the same. `DrtTailAssembly.seed(upstream:)` keeps its EXACT
// signature — the film hand-off replaces the VALUE the caller passes
// (levelHash[top] → the film output hash), never the function.
// ─────────────────────────────────────────────────────────────────────────────

/// The film sub-run payload (DrtTailParams twin): the document's FilmRecord
/// + its pre-computed stableHash + the RESOLVED material pair. The profiles
/// travel by value (Core structs — the App/coordinator resolves the record's
/// stock ids against its `FilmMaterialStore` and hands the pair in; a nil
/// profile = the typed degrade at the construction site, KD-6). The pair
/// hash is `FilmMaterialStore.materialPairHash` (the 01 single source — it
/// keys the runtime solve cache, KD-2).
public struct FilmTailParams: Sendable, Equatable {
    /// The document record (the pristine-carrier case never constructs a
    /// policy — the coordinator's `filmTailPolicy(for:)` gate).
    public let record: FilmRecord
    /// `record.stableHash()` folded once here (the DrtTailParams posture —
    /// the seed-fold single source).
    public let recordHash: UInt64
    /// The resolved negative profile (nil = unbound/unknown stock — the
    /// typed degrade; the leg refuses typed instead of silently passing).
    public let filmProfile: FilmProfile?
    /// The resolved paper profile.
    public let paperProfile: FilmProfile?
    /// `FilmMaterialStore.materialPairHash(film:paper:)` when both profiles
    /// are present; 0 otherwise (never a real pair hash — 0 is not a legal
    /// FNV output of the fold, so it cannot collide).
    public let materialPairHash: UInt64

    public init(
        record: FilmRecord, filmProfile: FilmProfile?, paperProfile: FilmProfile?,
        materialPairHash: UInt64
    ) {
        self.record = record
        self.recordHash = record.stableHash()
        self.filmProfile = filmProfile
        self.paperProfile = paperProfile
        self.materialPairHash = materialPairHash
    }

    /// Equatable over the identity fields (the profiles' consumer domain is
    /// already folded into `materialPairHash` — comparing the big arrays
    /// would be redundant work).
    public static func == (lhs: FilmTailParams, rhs: FilmTailParams) -> Bool {
        lhs.record == rhs.record
            && lhs.recordHash == rhs.recordHash
            && lhs.materialPairHash == rhs.materialPairHash
            && (lhs.filmProfile?.info.stock ?? "") == (rhs.filmProfile?.info.stock ?? "")
            && (lhs.paperProfile?.info.stock ?? "") == (rhs.paperProfile?.info.stock ?? "")
    }
}

/// The pipe-facing film-tail switch (KD-4's `filmTail: FilmTailPolicy?`
/// parameter face). nil = OFF — the zero path (every pre-M3-3 byte is
/// identical under it; the DrtTailTests + the whole LAYERS/IOPP corpus are
/// the standing gate). `TerminalTailPolicy` gains NO new case (the KD-1
/// ruling — film walks a SEPARATE seam).
public typealias FilmTailPolicy = FilmTailParams

/// The tail chain assembly (KD-1): the driver-constructed film box (zero
/// registry, zero sidecar, no add face — the DrtTailAssembly precedent) +
/// the display-replay resident filter for the 3×2 matrix rows.
public enum FilmTailAssembly {

    /// The policy tag (KD-1's constant — the REAL policy identity rides the
    /// record hash; the tag namespaces the fold).
    static let policyTag = "lightamer.film.subrun.v1"

    /// The spectral arm's namespace tag (M8-2, the「非 legacy 才折」fold):
    /// ONLY the resolved `.v2` arm folds this — the `.v1`/legacy documents
    /// keep `policyTag` verbatim, so every legacy cache key (the film
    /// sub-run seed above all) stays byte-identical forever (the
    /// filmRampPlaneHash freeze's key half). Review m1's narrow-fold
    /// declaration: the fold discriminator is the RESOLVED ARM, narrower
    /// than the RenderProcess header's literal `rawValue > 0` form (which
    /// would fold v1 too).
    static let spectralPolicyTag = "lightamer.film.subrun.v2-spectral"

    /// The arm's fold tag (the exhaustive switch is the compile-time half:
    /// a new RenderProcess case fails compilation HERE first — the `.v2`
    /// arm's tag lands WITH the M8-2 bump, the compiler points at this
    /// switch).
    static func policyTag(for arm: RenderProcess) -> String {
        switch arm {
        case .v1: return policyTag
        }
    }

    /// The display-replay sub-run's namespace tag (the replay keys must be
    /// distinct from every other sub-run's at the same upstream).
    static let replayTag = "lightamer.film.replay.v1"

    /// The film sub-run seed (KD-1): fnv(recordHash ⊕ policyTag ⊕
    /// solvedPackHash ⊕ upstream) — one canonical FNV-1a thread (the
    /// DrtTailAssembly.seed shape). T1 passes the placeholder 0; T2's solve
    /// cache fills the real value (the fold ORDER is final from day one so
    /// the T2 activation cannot move existing keys relative to the spec).
    /// This 3-arg form is the DENSITY arm's canonical face — every legacy
    /// (v1/absent process) key flows through it byte-identically.
    public static func seed(
        upstream: UInt64, params: FilmTailParams, solvedPackHash: UInt64
    ) -> UInt64 {
        seedFolding(
            upstream: upstream, params: params, solvedPackHash: solvedPackHash,
            tag: policyTag)
    }

    /// The process-aware seed (M8-2, the「非 legacy 才折」contract): the
    /// tag段 of the SAME four-term canonical order resolves through the
    /// arm's fold tag — v1/legacy resolve to `policyTag` (byte-identical
    /// keys, the negative-test-pinned face), the spectral arm folds
    /// `spectralPolicyTag` (a new keyspace; no legacy key can collide).
    /// The FOLD ORDER never changed — only the tag's VALUE per arm.
    public static func seed(
        upstream: UInt64, params: FilmTailParams, solvedPackHash: UInt64,
        renderProcess: RenderProcessVersion
    ) -> UInt64 {
        seedFolding(
            upstream: upstream, params: params, solvedPackHash: solvedPackHash,
            tag: policyTag(for: RenderProcess.resolving(renderProcess)))
    }

    /// The seed's single fold body (the KD-1 canonical order — the two
    /// public faces above differ ONLY in the tag they hand in).
    private static func seedFolding(
        upstream: UInt64, params: FilmTailParams, solvedPackHash: UInt64, tag: String
    ) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: params.recordHash) { h = StableHash.combine(h, $0) }
        let tagBytes = Array(tag.utf8)
        h = tagBytes.withUnsafeBufferPointer {
            StableHash.combine(h, UnsafeRawBufferPointer($0))
        }
        withUnsafeBytes(of: solvedPackHash) { h = StableHash.combine(h, $0) }
        withUnsafeBytes(of: upstream) { h = StableHash.combine(h, $0) }
        return h
    }

    /// The display-replay sub-run's seed: fnv over replayTag ⊕ upstream
    /// (the film output hash). A film-side change flips every replay plane;
    /// the replay boxes' own param values ride the sub-run's levelHash.
    public static func replaySeed(upstream: UInt64) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        let tagBytes = Array(replayTag.utf8)
        h = tagBytes.withUnsafeBufferPointer {
            StableHash.combine(h, UnsafeRawBufferPointer($0))
        }
        withUnsafeBytes(of: upstream) { h = StableHash.combine(h, $0) }
        return h
    }

    /// The film box's params identity — the leg computes the sub-run's
    /// output hash from the SAME derivation the box's commitParams uses
    /// (one source; the T2 solve payload rides Params, so the solve is IN
    /// the box hash — the seed's solvedPackHash term stays the
    /// cross-run locality fold).
    public static func methodParamsHash(method: FilmMethodBox.Params) -> UInt64 {
        StableHash.hash(ParamsCoding.encode(method))
    }

    /// `[FilmMethodBox]` — the film sub-run's whole chain (the fused
    /// transform is ONE box; the negative segment and the print LUT sample
    /// live in a single kernel, KD-1's no-intermediate-plane discipline).
    /// The run's GPU payloads ride the box INSTANCE (fix(film-leg): the
    /// per-run carrier — never a shared slot).
    public static func instances(
        method: FilmMethodBox.Params, payloads: FilmGPUPayloads?
    ) -> [any ModuleBoxing] {
        [ModuleBox(module: FilmMethodBox(
            record: method.record, method: method, payloads: payloads))]
    }

    /// The assembly-carrier form (M8-2): the forked factory's whole return
    /// rides ONE box — density and spectral payloads both travel by the
    /// instance, the arm-select happens inside the box's process face.
    public static func instances(assembly: FilmLegAssembly) -> [any ModuleBoxing] {
        [ModuleBox(module: FilmMethodBox(
            record: assembly.method.record, method: assembly.method,
            payloads: assembly.payloads,
            spectralPayloads: assembly.spectralPayloads))]
    }

    /// The display-replay resident filter (the 3×2 matrix's replay half,
    /// checker E4): the boxes the CURRENT policy demoted and must replay
    /// AFTER the film leg.
    ///
    ///   • `.sdrGamma` + film → colorout → borders → watermark → gamma (the
    ///     whole terminal resident set, v50 order preserved by the caller's
    ///     sort — 印框/水印 replay AFTER film so they are never film-graded,
    ///     the M2-6 E2 discipline's film extension);
    ///   • `.edrLinear` + film → colorout ONLY (gamma stays demoted and is
    ///     NEVER replayed — re-encoding through the SDR gamma would clamp
    ///     the EDR float plane);
    ///   • `.drt` → EMPTY (the DRT tail owns the replay — the film output
    ///     hash is its upstream seed; zero demotion change).
    ///
    /// film-off calls never reach here (the pipe short-circuits the replay
    /// leg when `filmTail == nil`).
    public static func displayReplayResidents(
        terminalTail: TerminalTailPolicy, residents: [any ModuleBoxing]
    ) -> [any ModuleBoxing] {
        let replayable: Set<String>
        switch terminalTail {
        case .sdrGamma:
            replayable = [
                ColorOutModule.opName,
                DrtMethodBox.tailResidentBordersOpName,
                DrtMethodBox.tailResidentWatermarkOpName,
                GammaModule.opName,
            ]
        case .edrLinear:
            replayable = [ColorOutModule.opName]
        case .drt:
            return []
        }
        return residents
            .filter { $0.enabled && replayable.contains($0.opName) }
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }
}

/// The film leg's assembly carrier (M8-2 — the forked factory's return,
/// the pre-M8-2 tuple's structural successor): the solved method params +
/// the per-run GPU payloads of the RESOLVED arm + the solvedPackHash seed
/// term. Exactly one payload face is populated per arm (the density arm
/// sets `payloads`, the spectral arm `spectralPayloads`; both nil = the
/// typed degrade — the byte-neutral identity carrier). The labels the
/// descriptor probe consumes (`method` / `payloads` / `solvedPackHash`
/// tuple labels before it) keep their spellings — the probe's call site
/// is untouched (the follow-the-factory guarantee).
public struct FilmLegAssembly {
    public let method: FilmMethodBox.Params
    /// The density arm's payloads (nil under the spectral arm).
    public let payloads: FilmGPUPayloads?
    /// The spectral arm's payloads (nil under the density arm). Non-Sendable
    /// by design (the payloads are per-run instance state — the M5-1-03
    /// single-owner discipline; the struct mirrors that posture).
    public let spectralPayloads: SpectralGPUPayloads?
    public let solvedPackHash: UInt64

    public init(
        method: FilmMethodBox.Params, payloads: FilmGPUPayloads?,
        spectralPayloads: SpectralGPUPayloads? = nil, solvedPackHash: UInt64
    ) {
        self.method = method
        self.payloads = payloads
        self.spectralPayloads = spectralPayloads
        self.solvedPackHash = solvedPackHash
    }
}

/// The film transform box (KD-1/T1 carrier, T2 fused kernel) — the
/// sub-run's sole module, driver-constructed (never registered, never in
/// sidecars, no add face).
///
/// T2: the box consumes the SOLVED print session (the neutral pack +
/// runtime exposure gain — `FilmSolveCache`'s output, resolved per run by
/// the pipe's film leg) and dispatches `film_subrun` (FilmSubRunKernels.metal
/// — negative segment → filter pack → print LUT → strength mix, ONE pass).
/// A nil `method` payload (the T1 face: unresolved materials) keeps the
/// routed-blit identity carrier — cache-neutral, byte-exact.
///
/// M8-2: the spectral arm's payloads ride the additive `runSpectralPayloads`
/// instance face (the fork's arm-select: spectral payloads present → the
/// spectral chain dispatches; otherwise the density face above, byte-untouched).
/// The box's external face (opName / iopOrder 74.0 / nil-payload blit
/// identity / the per-run instance carrier) is unchanged.
public final class FilmMethodBox: IOPModule {

    /// The box's committed payload: the record + the solved pack. The
    /// whole struct encodes into the params hash, so ANY solve-component
    /// change (pack or gain) flips the box's plane keys (and the seed's
    /// solvedPackHash term flips in step — one truth).
    public struct Params: Codable & Hashable & Sendable {
        public var record: FilmRecord
        /// The solved Magenta dial, CC points (0 = the T1 unresolved face).
        public var magentaCC: Float
        /// The solved Yellow dial, CC points.
        public var yellowCC: Float
        /// The exposure gain (auto normalization × 2^exposureEv), linear.
        public var exposureGain: Float

        public init(
            record: FilmRecord, magentaCC: Float = 0, yellowCC: Float = 0,
            exposureGain: Float = 1
        ) {
            self.record = record
            self.magentaCC = magentaCC
            self.yellowCC = yellowCC
            self.exposureGain = exposureGain
        }
    }

    public static let opName = "filmMethod"

    /// Tail-internal slot (the sole box of its own sub-run — the value is
    /// conventional, mirroring the DrtMethodBox 74.0 tail-internal face).
    public static let iopOrder: Float = 74.0

    public static let flags: IOPFlags = []
    public static let defaultColorspace: IOPColorspace = .RGB

    public let record: FilmRecord
    /// The resolved method params (the T1 identity face when the materials
    /// never resolved — the caller hands the same Params in).
    public let method: Params
    /// The run's GPU payloads, carried BY the box instance (the fix(film-leg)
    /// batch, M5-1-03 ACCEPTANCE §7): the film leg constructs this box fresh
    /// per run and hands the payloads in at construction — the former
    /// process-wide `runContext` static slot hung across the leg's await
    /// window, and concurrent coordinator renders over-released /
    /// cross-consumed each other's payloads (the `_swift_release_dealloc`
    /// crash family). Instance state has exactly one owner chain per run:
    /// the box lives in the leg pipe's pieces for the sub-run's duration.
    /// nil (or the test seam) = the identity degrade.
    public let runPayloads: FilmGPUPayloads?
    /// The spectral arm's payloads (M8-2, additive): present → the box
    /// dispatches the spectral chain (`SpectralFilmKernels` — A/blur/B +
    /// the strength mix), the density face stays untouched. Same instance
    /// ownership discipline as `runPayloads`.
    public let runSpectralPayloads: SpectralGPUPayloads?

    public init(
        record: FilmRecord, method: Params? = nil, payloads: FilmGPUPayloads? = nil,
        spectralPayloads: SpectralGPUPayloads? = nil
    ) {
        self.record = record
        self.method = method ?? Params(record: record)
        self.runPayloads = payloads
        self.runSpectralPayloads = spectralPayloads
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        method
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil  // uniforms ride the per-run assembly (upload leg)
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        // The spectral arm (M8-2): the forked factory hands the spectral
        // payloads in — the chain dispatch rides the payload instance (the
        // solved gain + CC deltas ride the per-run session tuning inside).
        if let spectral = runSpectralPayloads {
            try await spectral.dispatchFilmChain(
                input: input, output: output, metal: metal,
                exposureGain: method.exposureGain,
                kM: method.magentaCC * Float(FilmFilterPackSolver.magentaExposurePerCC),
                kY: method.yellowCC * Float(FilmFilterPackSolver.yellowExposurePerCC),
                strength: method.record.strength)
            return
        }
        // The fused leg needs the run's GPU payloads (the curve buffer +
        // the baked table — handed in at construction by the pipe's film
        // leg assembly). Absent payloads = the identity degrade: the T1
        // carrier face (a box processed outside the film leg's assembly —
        // unresolved materials, tests without profiles).
        guard let context = runPayloads ?? FilmMethodBox.assemblyContextForTesting,
            let command = context.payload(for: method)
        else {
            try blitIdentity(input: input, output: output, metal: metal)
            return
        }
        try await command.dispatch(input: input, output: output, metal: metal)
    }

    /// Whole-plane same-format blit (the T1 carrier — routed acquisition,
    /// L031; L008 endEncoding before commit).
    private func blitIdentity(
        input: any MTLTexture, output: any MTLTexture, metal: MetalContext
    ) throws {
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: input.width, height: input.height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()  // L008
        commandBuffer.commit()
    }

    // MARK: - The per-run assembly context (the GPU payload seam)

    /// The film leg uploads the curve buffer + the baked print table PER
    /// RUN (the profiles are per-document; the buffers are run-scoped —
    /// never cached beyond the run, the PlaneCache discipline). The payloads
    /// ride the BOX INSTANCE (`runPayloads`, handed in at construction) —
    /// the fix(film-leg) batch removed the former process-wide `runContext`
    /// static slot here: its set → await runSub → defer-clear window was
    /// cross-run shared state, and overlapping coordinator renders
    /// over-released / cross-consumed each other's payloads (the
    /// single-writer assumption broke under concurrency; M5-1-03
    /// ACCEPTANCE §7). The instance carries the same value with exactly one
    /// owner chain per run — no ambient channel, no window.
    ///
    /// The test injection face below remains the only static (never written
    /// by production code; a box with nil `runPayloads` consults it).
    nonisolated(unsafe) static var assemblyContextForTesting: FilmGPUPayloads?
}

/// The film sub-run's GPU payloads for ONE run (the curve buffer, the baked
/// table texture, the uniform carrier). Built by the pipe's film leg (T2
/// wiring) from the tail params' resolved profiles; dropped with the run.
public final class FilmGPUPayloads: @unchecked Sendable {

    public struct Command {
        public let uniforms: FilmSubRunUniforms
        public let curveBuffer: (any MTLBuffer)
        public let tableTexture: (any MTLTexture)

        public func dispatch(
            input: any MTLTexture, output: any MTLTexture, metal: MetalContext
        ) async throws {
            var u = uniforms
            try await metal.dispatch2DTexture(
                functionName: "film_subrun", input: input, output: output
            ) { encoder in
                encoder.setBuffer(curveBuffer, offset: 0, index: 0)
                encoder.setBytes(&u, length: MemoryLayout<FilmSubRunUniforms>.stride, index: 1)
                encoder.setTexture(tableTexture, index: 2)
            }
        }
    }

    private var commands: [FilmMethodBox.Params: Command] = [:]
    private let lock = NSLock()

    public init() {}

    /// Register the payload for one method params value (the assembly leg).
    public func install(_ method: FilmMethodBox.Params, command: Command) {
        lock.lock()
        commands[method] = command
        lock.unlock()
    }

    public func payload(for method: FilmMethodBox.Params) -> Command? {
        lock.lock()
        defer { lock.unlock() }
        return commands[method]
    }
}

/// The Swift mirror of the MSL `FilmSubRunUniforms` (the ABI single source
/// is the MSL struct; every member 4-byte aligned — no padding surprises at
/// 17 floats... the stride rounds to 68 → padded 80; `MemoryLayout.stride`
/// matches on both sides).
public struct FilmSubRunUniforms {
    var exposureGain: Float
    var kM: Float
    var kY: Float
    var strength: Float
    var baseR: Float
    var baseG: Float
    var baseB: Float
    var axisLo: Float
    var axisHi: Float
    var curveCountF: Float
    var domainLoX: Float
    var domainLoY: Float
    var domainLoZ: Float
    var domainHiX: Float
    var domainHiY: Float
    var domainHiZ: Float
    var width: Float
    var height: Float
}

// ─────────────────────────────────────────────────────────────────────────────
// The runtime statistics leg (KD-2) — the exposure-normalization side of
// FSIM-01b. The HISTOGRAM machinery lives in LightamerIOP
// (ScopeReduce.histogram); Core cannot import IOP (D-03), so the seam
// follows the LayerCompositeSeam precedent: Core holds the holder + the
// value type, IOP installs the adapter at populate time. Uninstalled (pure
// Core harnesses) = nil → the solve degrades to the bake-time neutral pack
// (the exposure gain rides 2^exposureEv alone) — the deterministic face.
// ─────────────────────────────────────────────────────────────────────────────

public enum FilmStatsSeam {

    /// The full-plane counting histogram (256 bins × R/G/B/luma — the
    /// ScopeReduce shape, Core-side value copy). The statsHash is FNV-1a
    /// over the flattened counts (L013 — the deterministic byte face).
    public struct PlaneHistogram: Sendable, Equatable {
        public let perChannel: [[UInt32]]

        public init(perChannel: [[UInt32]]) {
            self.perChannel = perChannel
        }

        public var statsHash: UInt64 {
            var h = StableHash.fnvOffsetBasis
            for channel in perChannel {
                for count in channel {
                    var v = count
                    h = withUnsafeBytes(of: &v) { StableHash.combine(h, $0) }
                }
            }
            return h
        }
    }

    /// The installed adapter (IOP's ScopeReduce bridge; L014 fence inside).
    public nonisolated(unsafe) static var histogram:
        @Sendable (_ plane: any MTLTexture, _ metal: MetalContext) async throws -> PlaneHistogram? =
            { _, _ in nil }
}

/// The runtime solve cache (KD-2): key = fnv(materialPairHash ⊕ statsHash ⊕
/// modeTag); value = the solved pack (M0, Y0) + the exposure gain + the
/// value-domain identity hash. NSLock + insertion-order LRU 8. Deterministic
/// by construction (the solve is a pure function of the key's terms).
public final class FilmSolveCache: @unchecked Sendable {

    public struct Solution: Equatable, Sendable {
        public let magentaCC: Double
        public let yellowCC: Double
        public let exposureGain: Double
        /// FNV over the bit patterns of (M, Y, gain) — the seed's
        /// solvedPackHash term (the value-domain identity).
        public var solvedPackHash: UInt64 {
            var h = StableHash.fnvOffsetBasis
            for value in [magentaCC, yellowCC, exposureGain] {
                var bits = value.bitPattern
                h = withUnsafeBytes(of: &bits) { StableHash.combine(h, $0) }
            }
            return h
        }
    }

    /// The AUTO core (the cached face): the neutral pack + the exposure
    /// normalization + the content-adaptive projection — a pure function of
    /// the cache key's terms. The RECORD terms (manual Y/M shifts, the
    /// exposure trim) layer at consumption and are NEVER cached.
    public struct AutoSolution: Equatable, Sendable {
        public let neutralMagentaCC: Double
        public let neutralYellowCC: Double
        public let autoGain: Double
        public let contentDeltaM: Double
        public let contentDeltaY: Double
    }

    private let lock = NSLock()
    private var solutions: [UInt64: AutoSolution] = [:]
    private var order: [UInt64] = []
    private let capacity: Int

    public init(capacity: Int = 8) {
        self.capacity = capacity
    }

    public func autoSolution(for key: UInt64) -> AutoSolution? {
        lock.lock()
        defer { lock.unlock() }
        guard let hit = solutions[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    public func store(_ solution: AutoSolution, for key: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        solutions[key] = solution
        order.append(key)
        while order.count > capacity {
            solutions.removeValue(forKey: order.removeFirst())
        }
    }

    public var countForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return solutions.count
    }

    /// The invalidation face (M3-3-03 T3, KD-3): the panel's Solve button
    /// forces a re-solve on the next consult. Value-invisible by
    /// construction (the solve is a pure function of the key's terms) — the
    /// face exists so the user gesture has a real edge to ride and so a
    /// future stats-face change (M3-4 descriptor) lands in one place.
    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        solutions.removeAll()
        order.removeAll()
    }
}

/// The runtime solve (KD-2): the bake-time neutral pack + the exposure
/// normalization (+ the optional content-adaptive channel shift), the
/// manual Y/M shifts ALWAYS added on top. All Float64 channel math; the
/// percentiles are INTEGER RANK (cumulative counts — never float
/// comparisons on percentile values). The Core solve does NOT clamp — the
/// CC totals clamp [0, 100] at consumption (the FilmRecord posture).
public enum FilmRuntimeSolve {

    /// The mode tag (the cache key's third term — contentAdaptiveShift only;
    /// NO ROI/context term: one solve per run over the FULL top plane — the
    /// per-ROI red line is structural here).
    public static func modeTag(contentAdaptive: Bool) -> String {
        contentAdaptive ? "film.solve.contentAdaptive.v1" : "film.solve.spektraLab.v1"
    }

    /// The spectral domain's mode tags (M8-2, D-M8-8's solve face): the
    /// SAME key shape, a DISTINCT tag space — the density and spectral
    /// cores are different kernels, so their AUTO solutions must never
    /// share a cache slot even for the identical pair ⊕ stats (the
    /// cross-core isolation the negative test pins).
    public static func spectralModeTag(contentAdaptive: Bool) -> String {
        contentAdaptive
            ? "film.solve.spectral.contentAdaptive.v1"
            : "film.solve.spectral.v1"
    }

    public static func cacheKey(
        materialPairHash: UInt64, statsHash: UInt64, contentAdaptive: Bool
    ) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: materialPairHash) { h = StableHash.combine(h, $0) }
        withUnsafeBytes(of: statsHash) { h = StableHash.combine(h, $0) }
        let tag = Array(modeTag(contentAdaptive: contentAdaptive).utf8)
        h = tag.withUnsafeBufferPointer {
            StableHash.combine(h, UnsafeRawBufferPointer($0))
        }
        return h
    }

    /// The key fold with the tag handed in DIRECTLY (M8-2, additive): the
    /// spectral solve passes its domain's tag — the fold CONTRACT (this
    /// exact fnv order over the three terms) is shared, only the tag's
    /// VALUE differs per core.
    public static func cacheKey(
        materialPairHash: UInt64, statsHash: UInt64, modeTag: String
    ) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: materialPairHash) { h = StableHash.combine(h, $0) }
        withUnsafeBytes(of: statsHash) { h = StableHash.combine(h, $0) }
        let tag = Array(modeTag.utf8)
        h = tag.withUnsafeBufferPointer {
            StableHash.combine(h, UnsafeRawBufferPointer($0))
        }
        return h
    }

    /// The integer-rank percentile of a 256-bin channel (the rank where the
    /// cumulative count crosses the fraction of the total). P50 of channel
    /// 3 = the exposure-normalization anchor.
    public static func percentileBin(
        _ counts: [UInt32], fraction: Double
    ) -> Int {
        let total = counts.reduce(0) { $0 + Int($1) }
        guard total > 0 else { return 0 }
        let target = Int(Double(total) * fraction)
        var cumulative = 0
        for (bin, count) in counts.enumerated() {
            cumulative += Int(count)
            if cumulative >= max(target, 1) {
                return bin
            }
        }
        return 255
    }

    /// The exposure gain: normalize the luma P50 to mid-gray (0.184). The
    /// TARGET is principled, not assumed: the bake's per-pair exposure
    /// calibration (FilmPrintBake.solveExposureCalibration) places the
    /// neutral mid-gray AT the paper's mid density — so "the paper
    /// mid-density's target EV" ≡ 0 EV, and the gain is the ratio 0.184 /
    /// P50. The [0,1] histogram domain is the ScopeReduce contract (an
    /// over-exposed P50 clamps at bin 255 — the registered stats boundary).
    public static func exposureGain(
        histogram: FilmStatsSeam.PlaneHistogram
    ) -> Double {
        let luma = histogram.perChannel[3]
        let p50Bin = percentileBin(luma, fraction: 0.5)
        let p50Linear = (Double(p50Bin) + 0.5) / 256.0
        guard p50Linear > 0 else { return 1.0 }
        return 0.184 / p50Linear
    }

    /// The content-adaptive channel shift (default OFF): the mid-gray
    /// three-channel imbalance projected onto the filter-gain basis — the
    /// closed form over the orthogonal basis (M → G, Y → B; R anchored).
    /// Returns (ΔM, ΔY) in CC points.
    public static func contentAdaptiveShift(
        histogram: FilmStatsSeam.PlaneHistogram
    ) -> (deltaM: Double, deltaY: Double) {
        // The per-channel P50 (integer rank) as EV offsets vs the luma P50.
        func channelEV(_ channel: Int) -> Double {
            let bin = percentileBin(histogram.perChannel[channel], fraction: 0.5)
            return log2((Double(bin) + 0.5) / 256.0 / 0.184)
        }
        let lumaEV = channelEV(3)
        // The imbalance in STOPS (per channel); the dial conversion
        // q = s × log2(10) stops per CC turns the projection into CC.
        let u = SIMD3<Double>(channelEV(0) - lumaEV, channelEV(1) - lumaEV, channelEV(2) - lumaEV)
        let qM = FilmFilterPackSolver.magentaExposurePerCC * Foundation.log2(10.0)
        let qY = FilmFilterPackSolver.yellowExposurePerCC * Foundation.log2(10.0)
        // The basis vectors (0, qM, 0) / (0, 0, qY): orthogonal → the
        // closed form is the coordinate projection.
        let deltaM = u.y / (qM * qM) * qM
        let deltaY = u.z / (qY * qY) * qY
        return (deltaM, deltaY)
    }

    /// The full solve: the AUTO core (cached — the neutral pack + the
    /// exposure normalization + the content-adaptive projection, a pure
    /// function of pair ⊕ stats ⊕ mode) with the RECORD terms layered at
    /// consumption (the manual Y/M shifts + the exposure trim are NOT cache
    /// terms — the KD-2 ruling: they ride the recordHash; the FINAL values
    /// return). All Float64 channel math; the percentiles are INTEGER RANK
    /// (cumulative counts — never float comparisons on percentile values).
    /// The Core solve does NOT clamp — the CC totals clamp [0, 100] at
    /// consumption (the FilmRecord posture).
    public static func solve(
        record: FilmRecord, film: FilmProfile, paper: FilmProfile,
        materialPairHash: UInt64, histogram: FilmStatsSeam.PlaneHistogram?
    ) throws -> FilmSolveCache.Solution {
        let statsHash = histogram?.statsHash ?? 0
        let key = cacheKey(
            materialPairHash: materialPairHash, statsHash: statsHash,
            contentAdaptive: record.contentAdaptiveShift)
        var auto: FilmSolveCache.AutoSolution
        if let cached = FilmSolveCache.shared.autoSolution(for: key) {
            auto = cached
        } else {
            // The bake-time neutral pack (the 01 solver single source).
            let neutral = try FilmFilterPackSolver.solveNeutralPack(film: film, paper: paper)
            var gain = 1.0
            var dM = 0.0
            var dY = 0.0
            if record.contentAdaptiveShift, let histogram {
                let shift = contentAdaptiveShift(histogram: histogram)
                dM = shift.deltaM
                dY = shift.deltaY
            }
            if let histogram {
                gain = exposureGain(histogram: histogram)
            }
            auto = FilmSolveCache.AutoSolution(
                neutralMagentaCC: neutral.magentaCC, neutralYellowCC: neutral.yellowCC,
                autoGain: gain, contentDeltaM: dM, contentDeltaY: dY)
            FilmSolveCache.shared.store(auto, for: key)
        }
        // The manual shifts ALWAYS on top (CC point domain, unclamped here —
        // the consumption clamp is the panel/consumer's face).
        let m = auto.neutralMagentaCC + auto.contentDeltaM + Double(record.mFilterShift)
        let y = auto.neutralYellowCC + auto.contentDeltaY + Double(record.yFilterShift)
        let totalGain = auto.autoGain * Foundation.pow(2.0, Double(record.exposureEv))
        return FilmSolveCache.Solution(magentaCC: m, yellowCC: y, exposureGain: totalGain)
    }

    /// The SPECTRAL-domain solve (M8-2, D-M8-8's consumption layer): the
    /// SAME Solution shape and the SAME cache contract (key =
    /// fnv(pair ⊕ stats ⊕ tag), the record terms layer at consumption and
    /// are NEVER cached), with the spectral arm's AUTO core:
    ///
    ///   • the neutral pair = the BUILD-RESOLVED print CC (`tables
    ///     .solvedPrintCC` — the spectral-domain neutral balance: the 2D
    ///     Newton ladder over the dichroic SPD × film spectral density ×
    ///     paper sensitivity integral drove the mid-gray log-channel
    ///     ratios to zero, M8-1a III.1's gray-error-exactly-0 discipline).
    ///     The CC lives in the TABLES via the solved dichroic light, so
    ///     only the DELTAS shift at run time (the E3 exposure form);
    ///   • the exposure normalization = the SAME runtime histogram face
    ///     as the density arm (the integer-rank P50 → mid-gray gain — the
    ///     consumption-layer semantic M3-4's descriptor math is anchored
    ///     to; the uninstalled seam degrades to gain 1 deterministically);
    ///   • the K calibration is the session operating point's spectral
    ///     face: `midgrayFactor` (baked by the build) + the solved pair —
    ///     the run-time face adds nothing to it (the solved values ARE
    ///     the calibration; the T2 test pins the gray-error-exactly-0
    ///     anchor through `midgrayPrintRaw`).
    ///
    /// The record terms ride the recordHash exactly as in the density arm:
    /// manual Y/M shifts add on top of the neutral pair (CC points), and
    /// `exposureEv` folds into the exposure gain (× 2^ev) — the solution
    /// GAIN changes, the neutral pair does not, and the cache key holds
    /// neither term.
    public static func solveSpectral(
        record: FilmRecord, tables: SpectralFilmTables,
        materialPairHash: UInt64, histogram: FilmStatsSeam.PlaneHistogram?
    ) throws -> FilmSolveCache.Solution {
        let statsHash = histogram?.statsHash ?? 0
        let key = cacheKey(
            materialPairHash: materialPairHash, statsHash: statsHash,
            modeTag: spectralModeTag(contentAdaptive: record.contentAdaptiveShift))
        var auto: FilmSolveCache.AutoSolution
        if let cached = FilmSolveCache.shared.autoSolution(for: key) {
            auto = cached
        } else {
            // The spectral AUTO core (the build's neutral balance + the
            // runtime histogram gain + the content deltas).
            var gain = 1.0
            var dM = 0.0
            var dY = 0.0
            if record.contentAdaptiveShift, let histogram {
                let shift = contentAdaptiveShift(histogram: histogram)
                dM = shift.deltaM
                dY = shift.deltaY
            }
            if let histogram {
                gain = exposureGain(histogram: histogram)
            }
            auto = FilmSolveCache.AutoSolution(
                neutralMagentaCC: Double(tables.solvedPrintCC.y),
                neutralYellowCC: Double(tables.solvedPrintCC.z),
                autoGain: gain, contentDeltaM: dM, contentDeltaY: dY)
            FilmSolveCache.shared.store(auto, for: key)
        }
        // The manual shifts ALWAYS on top (the density arm's consumption
        // shape verbatim — CC point domain, unclamped here).
        let m = auto.neutralMagentaCC + auto.contentDeltaM + Double(record.mFilterShift)
        let y = auto.neutralYellowCC + auto.contentDeltaY + Double(record.yFilterShift)
        let totalGain = auto.autoGain * Foundation.pow(2.0, Double(record.exposureEv))
        return FilmSolveCache.Solution(magentaCC: m, yellowCC: y, exposureGain: totalGain)
    }
}

extension FilmSolveCache {
    /// The process-wide cache (one per session — the solve is a pure
    /// function of the key, so sharing across pipes is value-invisible).
    public static let shared = FilmSolveCache()
}
