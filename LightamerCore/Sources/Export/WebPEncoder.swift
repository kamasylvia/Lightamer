import Foundation
import WebP

// ─────────────────────────────────────────────────────────────────────────────
// LightamerWebPEncoder — the libwebp conformer (Plan 11-02 T4).
//
// WebP WRITE does not exist in ImageIO on ANY macOS (the 11-01 UTI probe +
// the T5 anchor keep that fact pinned); ainame/Swift-WebP (libwebp 1.5+,
// the project's ONLY SPM dependency) is the single encode path.
//
// OQ-11-5 VERDICT (probed 2026-09-26): the Swift-WebP public surface exposes
// NO WebPMux face (zero mux/EXIF/ICC symbols in the package sources), so
// container-level metadata is not attachable — v1 ships WebP with NO
// embedded EXIF/ICC/XMP, a DOCUMENTED exception (ROADMAP Notes discount),
// Phase 12/14 re-review. The encoder carries no metadata code on purpose.
//
// Config mapping (11-01-DECISIONS D11 API face):
// - lossy  → `WebPEncoderConfig.preset(.default, quality: q*100)`
// - lossless → `WebPEncoderConfig.losslessPreset(level:)`; the spec's
//   0...1 quality knob folds to the 0...9 EFFORT level (a linear round,
//   pure + vector-pinned in WebPEncoderTests — libwebp lossless is exact
//   at every level, so the knob trades encode time, not fidelity).
// ─────────────────────────────────────────────────────────────────────────────

public struct LightamerWebPEncoder: ExportEncoder {

    public init() {}

    public func encode(_ request: ExportEncodeRequest) throws -> URL {
        guard request.plane.layout == .rgba8 else {
            throw AppError.invalidParameter(
                "webp is an 8-bit container (libwebp v1 capability edge) — needs an rgba8 plane, "
                    + "got \(request.plane.layout.rawValue)")
        }
        guard case .webp(let quality, let lossless) = request.spec else {
            throw AppError.invalidParameter("WebPEncoder dispatched a non-webp spec")
        }
        let config: WebPEncoderConfig = lossless
            ? try WebPEncoderConfig.losslessPreset(level: Self.losslessEffortLevel(forQuality: quality))
            : WebPEncoderConfig.preset(.default, quality: Float(quality) * 100.0)

        let plane = request.plane
        let data: Data
        do {
            data = try plane.data.withUnsafeBytes { raw in
                try WebPEncoder().encode(
                    raw.bindMemory(to: UInt8.self),
                    format: .rgba,
                    config: config,
                    originWidth: plane.width,
                    originHeight: plane.height,
                    stride: plane.rowBytes)
            }
        } catch {
            throw AppError.encodeFailed("webp encode failed: \(error)")
        }
        do {
            try data.write(to: request.destination, options: .atomic)
        } catch {
            throw AppError.encodeFailed("webp atomic write failed: \(error)")
        }
        return request.destination
    }

    /// The quality→effort fold: `round(quality * 9)` clamped to 0...9.
    /// Pure — the vector table lives in WebPEncoderTests.
    public static func losslessEffortLevel(forQuality quality: Double) -> Int {
        let clamped = min(max(quality, 0), 1)
        return Int((clamped * 9.0).rounded())
    }
}
