import LightamerCore
import Metal
import os

// ─────────────────────────────────────────────────────────────────────────
// SpektraFilmModule (spektra-module P1) — the `spektraFilm` grade op,
// v50 slot 46.7 (the dt spektrafilm slot verbatim — Research §1.1: filmicrgb
// 46.0 → spektraFilm 46.7 → lut3d 36.0 in listing order).
//
// Params = the FilmRecord verbatim (14 fields, the document-level singleton
// judgment retired — the record now rides ModuleInstance.paramsData); the
// solve values (M/Y/gain) NEVER enter Params (they are run-derived).
//
// D-SM-1 (the staleness guard): same params + different upstream statistics
// MUST key different planes. Mechanism: the process step STAMPS the run's
// solved-pack hash into `piece.paramsHash` (the colorout adoption precedent:
// the cache chain reads the BOX hash, and the run's plane key folds the
// stamped piece hash — so a new solve flips the level keys downstream).
// The run is self-consistent by construction: stamp-then-render in ONE
// pass, no prepareChain/process split window.
//
// DOMAIN (Research §4.1(a)): ACEScc in/out (the 46.7 slot sits INSIDE the
// [20.5, 69.9] grade envelope) — the process step unwraps to linear,
// delegates the EXISTING film-leg assembly (FilmLegFactory — the density /
// spectral arms byte-identical), forwards through a per-run FilmMethodBox,
// and re-wraps to ACEScc. Zero new kernels (the ACEScc pair reuses the
// envelope PSOs).
//
// flags: .supportsBlending (the layer mask chain applies as-is) +
// .oneInstance (Research OQ-1(a) — single enlarger). NO .allowTiling
// (P1 never tiles — pixelUm/corr-grid stay whole-plane, Research R1/R2).
//
// TILE POLICY (T5' pin — the per-ROI red line's structural face):
// tileHalo default 0 + tileWorkingSetBytesPerPixel default 0 + no
// .allowTiling ⇒ the tile driver NEVER tiles this module (the 4σ halo +
// per-tile corr rebuild = P2, Research §4.1(b) — the tiling turn-on).
// ─────────────────────────────────────────────────────────────────────────

public final class SpektraFilmModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        public var record: FilmRecord

        public init(record: FilmRecord = FilmRecord()) {
            self.record = record
        }
    }

    public static let opName = "spektraFilm"
    public static let iopOrder: Float = 46.7
    public static let flags: IOPFlags = [.supportsBlending, .oneInstance]
    public static let defaultColorspace: IOPColorspace = .RGB

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "spektraFilm"
    )

    /// The self-held surface census (the ADVISORY test seam — the
    /// FilmStatsSnapshot.last precedent: production reads NOTHING from
    /// this slot; the allocation tests assert the ≤1 face through it).
    public nonisolated(unsafe) static var liveSurfaceCount: Int = 0

    /// The committed record (the Lut3dModule `committed` precedent: the
    /// commit/process channel — `commitParams` snapshots it, `process`
    /// consumes the snapshot; the pipe never decodes params mid-run).
    private var committed: Params?

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
        committed = params
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let record = committed?.record else {
            try blitIdentity(input: input, output: output, metal: metal)
            return
        }
        try await process(
            record: record, input: input, output: output,
            piece: &piece, metal: metal)
    }

    /// The testable process face (the record rides explicitly — the pipe
    /// face above feeds the committed snapshot).
    func process(
        record: FilmRecord,
        input: any MTLTexture,
        output: any MTLTexture,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        // ① the material resolution (D-SM-0 lifeline 1): uninstalled seam
        // or unknown stocks = the blit-identity degrade (one error log —
        // the pristine guard keeps pristine renders log-silent — T2'-1
        // 二选一: the module-side `isFilmRecordDefault` early-identity).
        guard !isFilmRecordDefault(record),
            let materials = FilmMaterialSeam.resolver(record)
        else {
            if !isFilmRecordDefault(record) {
                Self.logger.error(
                    "spektraFilm: materials unresolved (film '\(record.filmStock, privacy: .public)' / paper '\(record.paperStock, privacy: .public)') — the identity degrade")
            }
            try blitIdentity(input: input, output: output, metal: metal)
            return
        }
        // ②/⑦ the ACEScc round-trip arms + ③ the self-held run-scoped
        // intermediate (D-SM-12R — NOT borrowed from any allocator).
        let linear = try mintWorkingSurface(like: input, metal: metal)
        Self.liveSurfaceCount += 1
        defer { Self.liveSurfaceCount -= 1 }
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.outFunctionName,
            input: input, output: linear)
        // ④ the statistics (the SAME seam the legacy leg consumes).
        let histogram = try? await FilmStatsSeam.histogram(linear, metal)
        // ⑤ the leg assembly (the EXISTING factory — arms byte-identical).
        let assembled = FilmLegFactory.assemble(
            record: record, film: materials.film, paper: materials.paper,
            materialPairHash: materials.materialPairHash, histogram: histogram,
            plane: linear, metal: metal, renderProcess: piece.renderProcess)
        // D-SM-1: stamp the run's solved identity into the piece hash —
        // the plane keys downstream flip with the solve (the colorout
        // adoption precedent). The identity degrade (pack 0) keeps the
        // committed hash (cache-stable across unresolved renders).
        if assembled.solvedPackHash != 0 {
            var pack = assembled.solvedPackHash
            piece.paramsHash = withUnsafeBytes(of: &pack) {
                StableHash.combine(piece.paramsHash, $0)
            }
        }
        // ⑥ the per-run forward (a FRESH FilmMethodBox per run — instance
        // payloads, the M5-1-03 single-owner discipline).
        let box = FilmMethodBox(
            record: record, method: assembled.method,
            payloads: assembled.payloads,
            spectralPayloads: assembled.spectralPayloads)
        var boxPiece = piece
        let frame = ROI(x: 0, y: 0, width: linear.width, height: linear.height)
        try await box.process(
            input: linear, output: linear, roiIn: frame,
            roiOut: frame, piece: &boxPiece, metal: metal)
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.inFunctionName,
            input: linear, output: output)
    }

    /// The run-scoped working surface (D-SM-12R self-held face — minted
    /// per run, released at the defer above; never pooled, never shared).
    private func mintWorkingSurface(
        like input: any MTLTexture, metal: MetalContext
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: input.width, height: input.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let surface = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(
                input.width * input.height * WorkingSpace.bytesPerPixel)
        }
        return surface
    }

    /// Whole-window routed blit (the FilmPlacement/Lut3d shape, L031).
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
        blit.endEncoding() // L008: encode close precedes commit
        commandBuffer.commit()
    }
}
