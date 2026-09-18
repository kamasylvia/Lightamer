import Foundation
import Metal

/// The `gamma` terminal module (v50 order 78.0, the pipe TAIL) — the
/// display handoff (research §3.3; Darktable `gamma.c` analog).
///
/// **Semantics:** the exact sRGB segmented TRC ENCODE
/// (`c ≤ 0.04045 ? c/12.92 : 1.055·c^(1/2.4) − 0.055`), full float math
/// (L006), clamped to [0,1] (D-COL4: THE only clamp in the pipe — the
/// interior stays float32 unclamped; EDR headroom is Phase 8), written to
/// a `.bgra8Unorm` display plane. P3 and sRGB share this TRC, so one
/// kernel serves every resolved profile. The drawable is deliberately NOT
/// an `_srgb` variant — the software encode is ours (UI-SPEC/D-COL4);
/// the viewport's `CAMetalLayer` carries the matching `colorSpace` so the
/// compositor interprets the bytes without re-matching.
///
/// **Cache policy (research §3.3):** cached planes stop at the colorout
/// output (float linear, reusable across screens/displays); gamma is the
/// cheap display handoff (~1ms at 2560px) — the pipe allocates the FINAL
/// plane in the display format when the tail module is gamma
/// (`PixelPipe` tail policy), so a display change re-runs only the
/// colorout+gamma segment (the colorout `stableID` fold flips their keys).
///
/// No user params — presence in the chain is the point (Darktable parity:
/// gamma is always the last enabled module; `Params` exists only to prove
/// the `Codable & Hashable` plumbing, same shape as the pass-through).
public final class GammaModule: IOPModule {

    /// The display-format plane the tail module writes (the ONLY non-float
    /// format the pipe produces; the EditorMTKView blit passes it through
    /// to the `.bgra8Unorm` drawable).
    public static let outputPixelFormat: MTLPixelFormat = .bgra8Unorm

    public struct Params: Codable & Hashable, Sendable {
        public init() {}
    }

    public static let opName = "gamma"

    /// v50 order 78.0 (V50Order table — the chain tail, verbatim Darktable
    /// position).
    public static let iopOrder: Float = 78.0

    public static let flags: IOPFlags = []

    public static let defaultColorspace: IOPColorspace = .RGB

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        // Constant (empty params) — the display change propagates through
        // the colorout `stableID` fold upstream of this module, so gamma's
        // own hash needs no display component.
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
    }

    /// Identity ROI.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Identity ROI.
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
        #if DEBUG
        assert(
            output.pixelFormat == Self.outputPixelFormat,
            "gamma tail must write \(Self.outputPixelFormat.rawValue), got \(output.pixelFormat.rawValue)"
        )
        #endif
        try await metal.dispatch2DTexture(
            functionName: TerminalKernels.gammaEncode,
            input: input,
            output: output
        )
    }
}
