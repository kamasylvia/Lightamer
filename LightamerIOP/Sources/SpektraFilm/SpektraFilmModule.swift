import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// SpektraFilmModule (spektra-module P1, T1') — the `spektraFilm` grade op,
// v50 slot 46.7 (the dt spektrafilm slot verbatim — Research §1.1: filmicrgb
// 46.0 → spektrafilm 46.7 → lut3d 36.0 in listing order).
//
// T1' SKELETON: registration + persistence shape only. Params = the
// FilmRecord verbatim (14 fields, the document-level singleton judgment
// retired — the record now rides ModuleInstance.paramsData); the render
// legs land in T2' (process seven steps + FilmLegFactory + FilmMaterialSeam).
// process is the bit-exact copy until T2' (the GradeCarrierKernelPending
// philosophy inverted — a skeleton must be pixel-silent, not loud, because
// the catalog identityJSON pins Params() and the bridge tests compare).
//
// DOMAIN (Research §4.1(a)): ACEScc in/out (the 46.7 slot sits INSIDE the
// [20.5, 69.9] grade envelope) — the ACEScc round-trip arms are T2' work;
// the T1' process below is domain-agnostic by construction (blit).
//
// flags: .supportsBlending (the layer mask chain applies as-is) +
// .oneInstance (Research OQ-1(a) — single enlarger). NO .allowTiling
// (P1 never tiles — pixelUm/cor-grid stay whole-plane, Research R1/R2).
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

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
    }

    /// T1' skeleton: the bit-exact copy (the T2' render legs replace this
    /// body wholesale — the ACEScc round-trip arms + the film-leg delegate
    /// + the material-seam guard).
    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
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
