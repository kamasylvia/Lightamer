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

    /// The display-replay sub-run's namespace tag (the replay keys must be
    /// distinct from every other sub-run's at the same upstream).
    static let replayTag = "lightamer.film.replay.v1"

    /// The film sub-run seed (KD-1): fnv(recordHash ⊕ policyTag ⊕
    /// solvedPackHash ⊕ upstream) — one canonical FNV-1a thread (the
    /// DrtTailAssembly.seed shape). T1 passes the placeholder 0; T2's solve
    /// cache fills the real value (the fold ORDER is final from day one so
    /// the T2 activation cannot move existing keys relative to the spec).
    public static func seed(
        upstream: UInt64, params: FilmTailParams, solvedPackHash: UInt64
    ) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: params.recordHash) { h = StableHash.combine(h, $0) }
        let tagBytes = Array(policyTag.utf8)
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
    /// (one source; the T2 solve payload extends the Params struct and this
    /// function is its only hash site).
    public static func methodParamsHash(params: FilmTailParams) -> UInt64 {
        StableHash.hash(ParamsCoding.encode(FilmMethodBox.Params(record: params.record)))
    }

    /// `[FilmMethodBox]` — the film sub-run's whole chain (the fused
    /// transform is ONE box; the negative segment and the print LUT sample
    /// live in a single kernel, KD-1's no-intermediate-plane discipline).
    public static func instances(params: FilmTailParams) -> [any ModuleBoxing] {
        [ModuleBox(module: FilmMethodBox(record: params.record))]
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

/// The film transform box (KD-1/T1) — the sub-run's sole module,
/// driver-constructed (never registered, never in sidecars, no add face).
/// The fused single-pass kernel lands with T2 (negative-segment density
/// lookup → base → crosstalk → print-exposure → print-LUT tetrahedral
/// sample → log-domain strength mix); T1 ships the BLIT IDENTITY carrier so
/// the seam/demotion/replay semantics are exercisable and cache-neutral
/// (the exposure-0EV style: the same-format whole-plane blit writes every
/// pixel, so the plane identity is honest for the cache).
public final class FilmMethodBox: IOPModule {

    /// The box's committed payload (T1: the record only — the seed carries
    /// the solve identity; T2 extends with the solve payload and the hash
    /// derivation stays on `FilmTailAssembly.methodParamsHash`).
    public struct Params: Codable & Hashable & Sendable {
        public var record: FilmRecord
        public init(record: FilmRecord) { self.record = record }
    }

    public static let opName = "filmMethod"

    /// Tail-internal slot (the sole box of its own sub-run — the value is
    /// conventional, mirroring the DrtMethodBox 74.0 tail-internal face).
    public static let iopOrder: Float = 74.0

    public static let flags: IOPFlags = []
    public static let defaultColorspace: IOPColorspace = .RGB

    public let record: FilmRecord

    public init(record: FilmRecord) {
        self.record = record
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params(record: record)
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil  // T1: no uniforms (the fused kernel arrives with T2)
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
        // T1 carrier: the same-format whole-plane blit (the Ashift/Crop
        // blitIdentity shape — makeRoutedCommandBuffer, L008 endEncoding
        // before commit, L031 routed acquisition). T2 replaces this body
        // with the fused kernel dispatch.
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
}
