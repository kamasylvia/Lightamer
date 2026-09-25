import Foundation

/// YIYIN-08 export configuration model (Plan 08-3 T3, D-08-CONTEXT-7).
///
/// An INDEPENDENT Codable value type — deliberately NOT attached to the
/// watermark/borders module params (EXP-07's multi-spec export requires
/// the ORTHOGONAL composition `module params × export settings`, one
/// params set fanned out over several settings). The physical application
/// (resize + `kCGImagePropertyDPIWidth/Height` write) is Phase 11 EXP-03;
/// the export-pipeline consumption point (EXPORT pipe terminal segment →
/// borders → watermark → encoder, gamma NOT in the export chain) is Phase
/// 11 EXP-05. THIS PHASE delivers only the model + its pure math + the
/// Codable stability the Phase 12 preset face can rely on.
///
/// Persistence channel: Phase 11 decides where the settings live (sidecar
/// extension vs export preset). No hash fields here — nothing enters a
/// cross-process identity (L013 territory untouched).
public struct YiyinExportSettings: Codable, Hashable, Sendable {

    /// The output sizing mode (yiyin `OutputOption.origin_wh_output` made
    /// REAL — yiyin declares the field but never consumes it; RESEARCH
    /// §1.1 — Lightamer implements it).
    public enum OutputMode: Codable, Hashable, Sendable {

        /// 保留原尺寸 — the canvas renders at its native pixel size.
        case original

        /// Fit the LONG edge to `px` (aspect preserved; never upscaled —
        /// `targetSize` clamps to the source dims).
        case longEdge(px: Int)

        /// Fit the SHORT edge to `px` (aspect preserved; never upscaled).
        case shortEdge(px: Int)
    }

    /// The sizing mode.
    public var mode: OutputMode

    /// Dots per inch written into the exported file's metadata
    /// (`kCGImagePropertyDPIWidth/Height` — Phase 11 EXP-03 consumes).
    public var dpi: Int

    /// The pixel-value cap (D-08-3-T3-1: 1...100_000 — beyond any sane
    /// encoder surface, still far under the 128k tex-dimension cliffs;
    /// yiyin ships no cap, this is the Lightamer guard rail).
    public static let maxTargetPixels = 100_000

    /// The DPI range (D-08-3-T3-1: 1...2400 — 2400dpi covers fine-art
    /// plate output; 0/negative is meaningless, >2400 is a typo not a
    /// print shop).
    public static let dpiRange = 1...2400

    public init(mode: OutputMode = .original, dpi: Int = 300) {
        self.mode = mode
        self.dpi = dpi
    }

    /// The validation rules (正数/上限 — D-08-3-T3-1). Pure; Phase 11
    /// export legs call this BEFORE encoding and surface the typed error.
    public func validate() throws {
        switch mode {
        case .original:
            break // no pixel value to validate
        case .longEdge(let px), .shortEdge(let px):
            guard px >= 1 else {
                throw AppError.invalidParameter(
                    "yiyin export target size must be ≥ 1 px, got \(px)")
            }
            guard px <= Self.maxTargetPixels else {
                throw AppError.invalidParameter(
                    "yiyin export target size \(px) px exceeds the "
                        + "\(Self.maxTargetPixels) px cap")
            }
        }
        guard Self.dpiRange.contains(dpi) else {
            throw AppError.invalidParameter(
                "yiyin export dpi \(dpi) outside \(Self.dpiRange.lowerBound)..."
                    + "\(Self.dpiRange.upperBound)")
        }
    }

    /// The pure EXP-03 spec: the target pixel size for a source canvas.
    /// Aspect preserved, never upscaled (a fit larger than the source
    /// clamps to the source dims — enlarging is the upscaler's business,
    /// not the exporter's). `original` returns the source verbatim.
    /// The Phase 11 resize leg consumes this; nothing here touches I/O.
    public func targetSize(canvasWidth w: Int, canvasHeight h: Int) -> (width: Int, height: Int) {
        let sw = max(w, 1)
        let sh = max(h, 1)
        switch mode {
        case .original:
            return (sw, sh)
        case .longEdge(let px):
            let target = min(max(px, 1), Self.maxTargetPixels)
            let long = max(sw, sh)
            guard long > target else { return (sw, sh) } // never upscale
            let scale = Double(target) / Double(long)
            return (width: max(Int((Double(sw) * scale).rounded(.down)), 1),
                    height: max(Int((Double(sh) * scale).rounded(.down)), 1))
        case .shortEdge(let px):
            let target = min(max(px, 1), Self.maxTargetPixels)
            let short = min(sw, sh)
            guard short > target else { return (sw, sh) } // never upscale
            let scale = Double(target) / Double(short)
            return (width: max(Int((Double(sw) * scale).rounded(.down)), 1),
                    height: max(Int((Double(sh) * scale).rounded(.down)), 1))
        }
    }
}
