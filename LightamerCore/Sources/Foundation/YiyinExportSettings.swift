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
///
/// M2-9-01 (Alcedo alignment, OQ-2): `OutputMode` grew the two Alcedo
/// faces — `bounds(w:h:)` (fit inside a W×H pixel box) and `physical(...)`
/// (print size + unit + DPI; Alcedo `PHYSICAL_SIZE`, `print` avoided as a
/// Swift keyword) — plus the `allowUpscale` switch (default false = the
/// historical never-upscale clamp) and the `maximumEdgePixels` cap (0 =
/// off, applied to ALL modes as a tail stage with DPI corrected
/// proportionally, Alcedo ApplyMaximumEdgeLimit semantics). The three
/// original cases remain untouched (superset). `resolveExportResolution`
/// is the single sizing math (KD-1); `targetSize` delegates to it and
/// keeps its historical signature/result so every existing call site is
/// byte-stable (the corrected DPI reaches the renderer in M2-9-03).
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

        /// Fit inside a `w`×`h` PIXEL box (aspect preserved; Alcedo
        /// `BOUNDING_BOX_PIXELS`). Either side may bind — the scale is
        /// `min(w/sw, h/sh)`.
        case bounds(w: Int, h: Int)

        /// Physical print size: `width`×`height` in `unit` at `dpi` PPI
        /// (Alcedo `PHYSICAL_SIZE`; `print` is a Swift keyword — Alcedo's
        /// semantic name is used instead). The DPI lives INSIDE the case
        /// (it is what makes the pixel translation meaningful): a
        /// non-positive DPI is a typed `resolveExportResolution` failure,
        /// not a silent fallback.
        case physical(width: Double, height: Double, unit: ExportPhysicalUnit, dpi: Int)
    }

    /// The physical-size unit (Alcedo `ExportPhysicalUnit`). Carries the
    /// units-per-inch translation face the physical mode's pixel math uses.
    public enum ExportPhysicalUnit: String, Codable, Hashable, Sendable {
        case inches
        case centimeters
        case millimeters

        /// Units per inch: in = 1, cm = 2.54, mm = 25.4 (the exact
        /// international-yard/pound definitions Alcedo uses).
        public var unitsPerInch: Double {
            switch self {
            case .inches: return 1.0
            case .centimeters: return 2.54
            case .millimeters: return 25.4
            }
        }
    }

    /// The sizing mode.
    public var mode: OutputMode

    /// Dots per inch written into the exported file's metadata
    /// (`kCGImagePropertyDPIWidth/Height` — Phase 11 EXP-03 consumes).
    public var dpi: Int

    /// `false` (default) = the historical never-upscale clamp: any fit
    /// larger than the source clamps to the source dims. `true` lets the
    /// fit grow past the source (Alcedo `allow_upscale_`; the M2EXP-01
    /// advanced-disclosure knob).
    public var allowUpscale: Bool

    /// The maximum-output-edge cap, 0 = OFF (Alcedo `maximum_edge_pixels_`).
    /// Applied as a TAIL stage to every mode (including `original`) — when
    /// the resolved max edge exceeds it, the result re-fits into a
    /// `maximumEdgePixels` square and the DPI is multiplied by the same
    /// WIDTH ratio so the physical print size stays constant.
    public var maximumEdgePixels: Int

    /// The pixel-value cap (D-08-3-T3-1: 1...100_000 — beyond any sane
    /// encoder surface, still far under the 128k tex-dimension cliffs;
    /// yiyin ships no cap, this is the Lightamer guard rail).
    public static let maxTargetPixels = 100_000

    /// The DPI range (D-08-3-T3-1: 1...2400 — 2400dpi covers fine-art
    /// plate output; 0/negative is meaningless, >2400 is a typo not a
    /// print shop).
    public static let dpiRange = 1...2400

    /// The physical-size domain (the Alcedo QML double-spin domain,
    /// 0.01...100_000 — one guard rail for both physical axes).
    public static let physicalSizeRange = 0.01...100_000.0

    public init(
        mode: OutputMode = .original, dpi: Int = 300,
        allowUpscale: Bool = false, maximumEdgePixels: Int = 0
    ) {
        self.mode = mode
        self.dpi = dpi
        self.allowUpscale = allowUpscale
        self.maximumEdgePixels = maximumEdgePixels
    }

    // MARK: - Codable (KD-2 additive decode tolerance)

    // Hand-written decode: the synthesized one would decode the two new
    // non-optional fields with `decode(_:forKey:)` and THROW on every
    // legacy payload (three-mode JSON without the new keys). The mode enum
    // itself decodes through its own synthesized case-name-keyed face —
    // the new cases only ADD keys, so old payloads decode untouched.
    private enum CodingKeys: String, CodingKey {
        case mode, dpi, allowUpscale, maximumEdgePixels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(OutputMode.self, forKey: .mode)
        dpi = try container.decode(Int.self, forKey: .dpi)
        allowUpscale = try container.decodeIfPresent(Bool.self, forKey: .allowUpscale) ?? false
        maximumEdgePixels = try container.decodeIfPresent(Int.self, forKey: .maximumEdgePixels) ?? 0
    }

    // MARK: - Validation

    /// The validation rules (正数/上限 — D-08-3-T3-1; M2-9-01 four-mode
    /// extension). Pure; Phase 11 export legs call this BEFORE encoding and
    /// surface the typed error.
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
        case .bounds(let w, let h):
            guard w >= 1, h >= 1 else {
                throw AppError.invalidParameter(
                    "yiyin export bounds \(w)×\(h) must be ≥ 1 px")
            }
            guard w <= Self.maxTargetPixels, h <= Self.maxTargetPixels else {
                throw AppError.invalidParameter(
                    "yiyin export bounds \(w)×\(h) exceeds the "
                        + "\(Self.maxTargetPixels) px cap")
            }
        case .physical(let width, let height, _, let physicalDpi):
            guard Self.physicalSizeRange.contains(width),
                Self.physicalSizeRange.contains(height)
            else {
                throw AppError.invalidParameter(
                    "yiyin export physical size \(width)×\(height) outside "
                        + "\(Self.physicalSizeRange)")
            }
            guard Self.dpiRange.contains(physicalDpi) else {
                throw AppError.invalidParameter(
                    "yiyin export physical dpi \(physicalDpi) outside "
                        + "\(Self.dpiRange.lowerBound)...\(Self.dpiRange.upperBound)")
            }
        }
        guard maximumEdgePixels >= 0 else {
            throw AppError.invalidParameter(
                "yiyin export maximumEdgePixels \(maximumEdgePixels) is negative "
                    + "(0 = the cap is off)")
        }
        guard Self.dpiRange.contains(dpi) else {
            throw AppError.invalidParameter(
                "yiyin export dpi \(dpi) outside \(Self.dpiRange.lowerBound)..."
                    + "\(Self.dpiRange.upperBound)")
        }
    }

    // MARK: - Resolution math (KD-1 — the single sizing source)

    /// The typed resolution product (Alcedo `ExportResolutionResult`
    /// shape): `success == false` carries the failure reason in `message`
    /// — the caller decides, nothing throws.
    public struct ExportResolutionResult: Equatable, Sendable {

        public let success: Bool
        public let width: Int
        public let height: Int
        public let dpi: Int
        public let message: String?

        public init(
            success: Bool, width: Int, height: Int, dpi: Int, message: String?
        ) {
            self.success = success
            self.width = width
            self.height = height
            self.dpi = dpi
            self.message = message
        }

        static func failure(_ message: String) -> ExportResolutionResult {
            ExportResolutionResult(
                success: false, width: 0, height: 0, dpi: 0, message: message)
        }
    }

    /// The pure sizing resolution (KD-1, Alcedo ResolveExportResolution
    /// semantics, self-written): mode dispatch → fit-inside scale (with
    /// the `allowUpscale` clamp) → the `maximumEdgePixels` tail stage with
    /// the width-ratio DPI correction. Typed failures do NOT throw.
    ///
    /// - The source dims are clamped to ≥ 1 (the historical `targetSize`
    ///   face — Alcedo instead fails on non-positive sources; the clamp
    ///   keeps every existing vector byte-identical, DECISIONS M2-9-01-D2).
    /// - The corrected DPI only diverges from `dpi` when the cap stage
    ///   actually shrinks the output — that corrected value is what keeps
    ///   the physical print size constant.
    public func resolveExportResolution(
        canvasWidth w: Int, canvasHeight h: Int
    ) -> ExportResolutionResult {
        let sw = max(w, 1)
        let sh = max(h, 1)
        let clampedDpi = min(max(dpi, Self.dpiRange.lowerBound), Self.dpiRange.upperBound)

        var result: ExportResolutionResult
        switch mode {
        case .original:
            result = ExportResolutionResult(
                success: true, width: sw, height: sh, dpi: clampedDpi, message: nil)
        case .longEdge(let px):
            let p = min(max(px, 1), Self.maxTargetPixels)
            result = Self.scaleIntoBox(
                sourceWidth: sw, sourceHeight: sh, boxWidth: Double(p),
                boxHeight: Double(p), allowUpscale: allowUpscale, dpi: clampedDpi)
        case .shortEdge(let px):
            // Our superset mode (Alcedo has no short-edge face): the same
            // family math keyed off the SHORT edge — the upscale clamp and
            // the cap tail apply identically.
            let p = min(max(px, 1), Self.maxTargetPixels)
            var scale = Double(p) / Double(min(sw, sh))
            if !allowUpscale { scale = min(scale, 1.0) }
            result = Self.assemble(
                sourceWidth: sw, sourceHeight: sh, scale: scale, dpi: clampedDpi)
        case .bounds(let bw, let bh):
            let boxW = Double(min(max(bw, 1), Self.maxTargetPixels))
            let boxH = Double(min(max(bh, 1), Self.maxTargetPixels))
            result = Self.scaleIntoBox(
                sourceWidth: sw, sourceHeight: sh, boxWidth: boxW, boxHeight: boxH,
                allowUpscale: allowUpscale, dpi: clampedDpi)
        case .physical(let physW, let physH, let unit, let physicalDpi):
            // D-M2-9-CONTEXT-6: a missing/non-positive print DPI is a typed
            // failure, never a silent fallback.
            guard physicalDpi > 0 else {
                return .failure("Physical-size export requires a positive DPI")
            }
            let upi = unit.unitsPerInch
            let widthPixels = physW > 0 ? physW / upi * Double(physicalDpi) : 0.0
            let heightPixels = physH > 0 ? physH / upi * Double(physicalDpi) : 0.0
            result = Self.scaleIntoBox(
                sourceWidth: sw, sourceHeight: sh, boxWidth: widthPixels,
                boxHeight: heightPixels, allowUpscale: allowUpscale, dpi: physicalDpi)
        }
        return Self.applyMaximumEdgeLimit(result, cap: maximumEdgePixels)
    }

    /// Fit-inside scale-into-box (Alcedo ScaleIntoBox semantics): the
    /// scale is the min of the positive box constraints, clamped to ≤ 1
    /// unless upscaling is allowed, rounded half-away-from-zero (llround)
    /// and clamped to ≥ 1 px.
    private static func scaleIntoBox(
        sourceWidth sw: Int, sourceHeight sh: Int,
        boxWidth: Double, boxHeight: Double,
        allowUpscale: Bool, dpi: Int
    ) -> ExportResolutionResult {
        var scale = Double.infinity
        if boxWidth.isFinite, boxWidth > 0 { scale = min(scale, boxWidth / Double(sw)) }
        if boxHeight.isFinite, boxHeight > 0 { scale = min(scale, boxHeight / Double(sh)) }
        if !allowUpscale { scale = min(scale, 1.0) }
        return assemble(sourceWidth: sw, sourceHeight: sh, scale: scale, dpi: dpi)
    }

    /// Shared scale → pixel-dims face (the scale validity guard lives here
    /// so the short-edge path and the box path fail identically).
    private static func assemble(
        sourceWidth sw: Int, sourceHeight sh: Int, scale: Double, dpi: Int
    ) -> ExportResolutionResult {
        guard scale.isFinite, scale > 0 else {
            return .failure("At least one output dimension must be positive")
        }
        let width = max(
            min(Int((Double(sw) * scale).rounded(.toNearestOrAwayFromZero)), Int.max), 1)
        let height = max(
            min(Int((Double(sh) * scale).rounded(.toNearestOrAwayFromZero)), Int.max), 1)
        return ExportResolutionResult(
            success: true, width: width, height: height, dpi: dpi, message: nil)
    }

    /// The tail cap stage (Alcedo ApplyMaximumEdgeLimit semantics): when
    /// the resolved max edge exceeds a positive cap, re-fit into a cap
    /// square (never upscaling) and correct the DPI by the WIDTH ratio so
    /// the physical print size is conserved.
    private static func applyMaximumEdgeLimit(
        _ result: ExportResolutionResult, cap: Int
    ) -> ExportResolutionResult {
        guard result.success, cap > 0,
            max(result.width, result.height) > cap
        else { return result }
        let limited = scaleIntoBox(
            sourceWidth: result.width, sourceHeight: result.height,
            boxWidth: Double(cap), boxHeight: Double(cap),
            allowUpscale: false, dpi: result.dpi)
        guard limited.success, result.width > 0 else { return limited }
        var correctedDpi = result.dpi
        if correctedDpi > 0 {
            correctedDpi = Int(
                (Double(result.dpi) * Double(limited.width) / Double(result.width))
                    .rounded())
        }
        return ExportResolutionResult(
            success: limited.success, width: limited.width, height: limited.height,
            dpi: correctedDpi, message: limited.message)
    }

    // MARK: - Historical face (delegates to the resolution math)

    /// The pure EXP-03 spec: the target pixel size for a source canvas.
    /// Kept for the existing call sites (ExportRenderer entry plane, the
    /// test vectors): delegates to `resolveExportResolution` and drops the
    /// DPI. On a typed failure (only the physical mode can fail) the
    /// source dims come back — the historical never-worse-than-source
    /// contract.
    public func targetSize(canvasWidth w: Int, canvasHeight h: Int) -> (width: Int, height: Int) {
        let resolved = resolveExportResolution(canvasWidth: w, canvasHeight: h)
        guard resolved.success else { return (max(w, 1), max(h, 1)) }
        return (resolved.width, resolved.height)
    }
}
