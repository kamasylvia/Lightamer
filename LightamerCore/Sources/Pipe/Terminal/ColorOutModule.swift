import CoreImage
import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// Derivation of the two compile-time constant matrices (Plan 02-04-03; the
// plan requires the derivation comment verbatim-able at the source):
//
// Both matrices are plain linear-primaries conversions computed from the
// standard primaries and the shared D65 white point (x=0.3127, y=0.3290) —
// same white ⇒ NO chromatic adaptation, M = XYZ→RGB(target) · RGB→XYZ(Rec2020):
//
//   Rec2020 primaries (BT.2020):  R(0.708,0.291) G(0.170,0.797) B(0.131,0.046)
//   Display P3 primaries (DCI-P3 D65 / SMPTE EG 432-1):
//                                 R(0.680,0.320) G(0.265,0.690) B(0.150,0.060)
//   sRGB primaries (BT.709):      R(0.640,0.330) G(0.300,0.600) B(0.150,0.060)
//
// Derived with the generator checked into `.work/plans/02-04/matrix-derive.swift`
// (2026-09-19; row-major, out_i = Σ_j M[i][j]·in_j):
//
//   Rec2020 → Display P3 (linear):
//     [  1.343930183, -0.282585998, -0.061344185 ]
//     [ -0.066855841,  1.077337009, -0.010481169 ]
//     [  0.003750840, -0.019626716,  1.015875875 ]
//
//   Rec2020 → sRGB (linear) — agrees with the published 4-decimal matrix
//   (1.6605/−0.5876/−0.0728 …) to rounding of the input primaries:
//     [  1.661272640, -0.588487320, -0.072785321 ]
//     [ -0.126189204,  1.134531230, -0.008342025 ]
//     [ -0.017014775, -0.100723728,  1.117738502 ]
//
//   Invariants verified by the generator: (0.5,0.5,0.5) → (0.5,0.5,0.5)
//   exactly and D65 → (1,1,1) in both — grays stay neutral across the
//   conversion (the D-COL1 criterion-1 precondition).
// ─────────────────────────────────────────────────────────────────────────────

/// The `colorout` terminal module (v50 order 70.0): linear Rec2020 →
/// linear display-gamut RGB (gamut matrix ONLY — the TRC encode is the
/// gamma module's job, D-COL4 keeps this stage float32 unclamped).
///
/// **Dual path** (research §3.2):
/// - **Metal fast path** — `colorout_matrix` kernel, function-constant
///   `isP3` selecting one of the two compile-time constant matrices above
///   (two PSO entries, D-16/D-17). Covers the `DisplayProfile` matching
///   table (`.displayP3` / `.sRGB`). Matrix math preserves grays exactly,
///   so the D-COL1 neutrality criterion rides on this path unchanged.
/// - **ColorSync precise path** — any other profile:
///   `MetalContext.convertToLinearSpace` (CIContext bitmap render, full
///   ICC primaries/white handling) then a `terminal_copy` blit into the
///   pipe's output plane. Also the D-COL1 criterion-2 independent
///   baseline's domain. 10-30ms at 2560px — one-shot on screen change,
///   never the drag hot path.
///
/// **D-COL3 reservation:** `Params.outputProfile` / `Params.intent` are
/// the Phase 13 plug-in points (printer/soft-proof profiles + rendering
/// intents). `.display` resolves the actual screen at process time.
///
/// **Terminal-segment invalidation:** `commitParams` folds the resolved
/// target's `DisplayProfile.stableID` into `piece.paramsHash` — a display
/// change (re-committed by the coordinator after setting
/// `displayProfileOverride`) flips exactly the cache keys at positions
/// ≥ colorout; upstream planes survive (SC#2 terminal variant).
public final class ColorOutModule: IOPModule {

    /// D-COL3: the output profile parameter. `display` = resolve the
    /// window's screen at process time (D-COL2); the explicit cases pin
    /// the fast path (tests, export, Phase 11/13 profiles later).
    ///
    /// Plan 11-03 T2 additive cases — the EXPORT targets (D-COL3's
    /// "Phase 11/13 profiles later" reservation materialized). They resolve
    /// through the ColorSync precise path; the EDITING chain never sets
    /// them (the coordinator injects `displayProfileOverride` or `.display`)
    /// so the display fast path is untouched (zero-regression red line).
    /// `OutputProfile` carries the gamut IDENTITY only — the TRC flavor
    /// (display-encoded vs linear variant) rides the per-instance
    /// `exportTargetOverride` socket the export chain builder sets
    /// (a record is configuration, the variant's bit depth decides the
    /// flavor; TIFF 32f = linear variant, everything else = display TRC).
    public enum OutputProfile: String, Codable, Sendable {
        /// Follow the display (D-COL2). Phase 13+ adds printer/soft-proof
        /// profiles here (D-COL3).
        case display
        case sRGB
        case displayP3
        /// Export targets (11-03): Adobe RGB (1998) / ProPhoto (ROMM) /
        /// Rec. 2020 — the ColorSync precise path (RESEARCH §3.2: no Metal
        /// matrix families are added for export).
        case adobeRGB
        case proPhoto
        case rec2020
    }

    /// D-COL3 reservation — relative colorimetric is the only intent
    /// Phase 2 implements; the parameter is persisted for Phase 13.
    public enum RenderingIntent: String, Codable, Sendable {
        case relativeColorimetric
        // Phase 13+: perceptual, saturation, absoluteColorimetric
    }

    public struct Params: Codable & Hashable, Sendable {
        public var outputProfile: OutputProfile
        public var intent: RenderingIntent

        public init(
            outputProfile: OutputProfile = .display,
            intent: RenderingIntent = .relativeColorimetric
        ) {
            self.outputProfile = outputProfile
            self.intent = intent
        }
    }

    public static let opName = "colorout"

    /// v50 order 70.0 (V50Order table, verbatim Darktable position).
    public static let iopOrder: Float = 70.0

    public static let flags: IOPFlags = []

    /// colorout's OUTPUT is display-gamut linear — still RGB (the sRGB TRC
    /// applied by gamma is shared by P3 and sRGB).
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Coordinator-injected display override (D-COL2 screen follow). nil =
    /// resolve from `NSScreen.main` at target-resolution time. The
    /// coordinator sets this BEFORE re-committing params on a screen
    /// change so the folded `stableID` matches the new display.
    public var displayProfileOverride: DisplayProfile?

    /// Plan 11-03 T2 — the EXPORT target-override socket. When set, the
    /// module converts the plane to THIS EXACT CGColorSpace (primaries +
    /// white + TRC in ONE ColorSync render): the display-TRC variant for
    /// the quantized tiers, the LINEAR variant for TIFF 32f (OQ-11-2:
    /// colorout stays in the export chain and carries the whole target
    /// conversion, so the exit leg is an identity). HIGHEST precedence —
    /// above `displayProfileOverride` (an export render never follows a
    /// screen). Like the display override, the builder sets it BEFORE
    /// re-committing params so the folded hash carries it.
    ///
    /// NOT a param (schema untouched): per-run DATA like `captureExif` —
    /// L013, injection is not configuration. Sendability: CGColorSpace is
    /// an immutable thread-safe CF type.
    public var exportTargetOverride: CGColorSpace?

    /// The cached function-constant set for the P3 specialization (D-16:
    /// one stable instance per module → stable PSOKey → cache hits).
    private var p3Constants: MTLFunctionConstantValues?
    private var srgbConstants: MTLFunctionConstantValues?

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// Resolve the effective target profile for the current process run.
    /// Precedence: the export target override (11-03, the variant's exact
    /// space) → coordinator override (live display) → explicit param →
    /// `NSScreen.main` resolution (defensive; `.display` with no override).
    private func resolvedTarget(params: Params) -> DisplayProfile {
        if let export = exportTargetOverride {
            return .colorSyncFallback(export)
        }
        if let override = displayProfileOverride {
            return override
        }
        switch params.outputProfile {
        case .displayP3: return .displayP3
        case .sRGB: return .sRGB
        case .adobeRGB: return .colorSyncFallback(Self.displayTRCSpace(for: .adobeRGB))
        case .proPhoto: return .colorSyncFallback(Self.displayTRCSpace(for: .proPhoto))
        case .rec2020: return .colorSyncFallback(Self.displayTRCSpace(for: .rec2020))
        case .display: return DisplayProfile.current()
        }
    }

    /// The DISPLAY-TRC CGColorSpace of an explicit export profile — the
    /// same five-space table `ExportColorSpaceMapper.displayCGColorSpace`
    /// owns (single source of truth within Core; the module maps its own
    /// enum onto it). The LINEAR variants are the EXPORT-side override
    /// socket's business (the builder decides via the format bit depth),
    /// never this table.
    static func displayTRCSpace(for profile: OutputProfile) -> CGColorSpace {
        switch profile {
        case .sRGB: return ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        case .displayP3: return ExportColorSpaceMapper.displayCGColorSpace(for: .displayP3)
        case .adobeRGB: return ExportColorSpaceMapper.displayCGColorSpace(for: .adobeRGB)
        case .proPhoto: return ExportColorSpaceMapper.displayCGColorSpace(for: .proPhoto)
        case .rec2020: return ExportColorSpaceMapper.displayCGColorSpace(for: .rec2020)
        case .display:
            // `.display` has no static space — the caller resolves the
            // screen first. Defensive fall-back to sRGB (the resolver's
            // own degenerate answer).
            return ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        }
    }

    /// Stable identity of an arbitrary CGColorSpace (the export override's
    /// invalidation atom — ICC bytes when present, else the registered
    /// name). Same discipline as `DisplayProfile.stableID`.
    private static func stableID(of space: CGColorSpace) -> UInt64 {
        if let icc = space.copyICCData() as Data? {
            return StableHash.hash(icc)
        }
        let name = space.name as String? ?? "unnamed-\(space)"
        return StableHash.hash("lightamer.export.colorSync:\(name)")
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        lastCommittedParams = params // `process` reads the committed params here
        let encoded = ParamsCoding.encode(params)
        var hash = StableHash.hash(encoded)
        // Terminal-segment invalidation atom: fold the RESOLVED display identity so a screen change re-commits to a different hash even
        // though the JSON params are unchanged (`.display` case).
        var displayID = resolvedTarget(params: params).stableID
        hash = withUnsafeBytes(of: &displayID) { StableHash.combine(hash, $0) }
        // 11-03: the export override refines the identity further — the
        // linear variant of the SAME profile must re-commit (different
        // conversion than the display-TRC flavor).
        if let export = exportTargetOverride {
            var exportID = Self.stableID(of: export)
            hash = withUnsafeBytes(of: &exportID) { StableHash.combine(hash, $0) }
        }
        piece.paramsHash = hash
    }

    /// Identity ROI (a gamut matrix does not resample).
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
        let params = lastCommittedParams ?? Params()
        // 11-03 EXPORT OVERRIDE — highest precedence, BEFORE the display
        // switch: convert to the variant's EXACT space (display-TRC or
        // linear variant) in one ColorSync render through the row-order-
        // fixed leg (L029's defective convertTexture twin is never
        // consumed here). The arriving plane is linear Rec2020; the output
        // carries the WHOLE target conversion so the export exit leg is an
        // identity (checker E3's consumption face).
        if let exportTarget = exportTargetOverride {
            try await renderViaExportTarget(
                input: TextureBox(texture: input),
                output: output,
                target: exportTarget,
                metal: metal)
            return
        }
        let target = resolvedTarget(params: params)
        switch target {
        case .displayP3:
            try await metal.dispatch2DTexture(
                functionName: TerminalKernels.coloroutMatrix,
                input: input,
                output: output,
                constants: constants(forP3: true, metal: metal)
            )
        case .sRGB:
            try await metal.dispatch2DTexture(
                functionName: TerminalKernels.coloroutMatrix,
                input: input,
                output: output,
                constants: constants(forP3: false, metal: metal)
            )
        case .colorSyncFallback:
            // Linear sRGB workalike (documented at
            // `DisplayProfile.linearCGColorSpace`). 13-2 T6 NOTE: the
            // exact-primaries linear variant EXISTS (the matrix-shaper
            // parser + calibrated rebuild) but is DELIBERATELY not wired
            // here — the render leg proved order-sensitive against a
            // shared CGColorSpace instance in the CI leg (the
            // CullingPipeline collapse forensics, 13-2-DECISIONS D-13-2-7);
            // the render integration is deferred to a dedicated validation
            // batch. The AC's ICC byte identity (resolve PRODUCT carries
            // the hand-picked bytes) is test-pinned regardless.
            // TextureBox (the pipe's @unchecked Sendable ownership-transfer
            // wrap) carries the plane across the pool actor boundary — the
            // plane is renounced by this call (not used afterwards).
            try await renderViaColorSync(
                input: TextureBox(texture: input),
                output: output,
                linearSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                metal: metal
            )
        }
    }

    /// The ColorSync precise path (`research §3.2`; the D-COL1 criterion-2
    /// baseline's domain): full-ICC primaries conversion to the target's
    /// LINEAR space via `MetalContext.convertToLinearSpace`, then a
    /// `terminal_copy` blit into the pipe-allocated output plane.
    private func renderViaColorSync(
        input: TextureBox,
        output: any MTLTexture,
        linearSpace: CGColorSpace,
        metal: MetalContext
    ) async throws {
        let converted = try await metal.convertToLinearSpace(input.texture, target: linearSpace)
        try await metal.dispatch2DTexture(
            functionName: TerminalKernels.copy,
            input: converted,
            output: output
        )
    }

    /// The EXPORT override leg (Plan 11-03 T2): one ColorSync render lands
    /// the WHOLE target conversion (primaries + white + TRC — or the linear
    /// variant, whatever `target` is) then a `terminal_copy` blit into the
    /// pipe's output plane. The pipe stays float32 unclamped (D-COL4): the
    /// [0,1] SDR-white clamp is the EXPORT QUANTIZER's (the gamma module's
    /// clamp semantics relocated to the exit face, D-11-CONTEXT-7). The
    /// conversion rides `convertToEncodedSpace` — the row-order-fixed,
    /// export-pool (R8) leg.
    private func renderViaExportTarget(
        input: TextureBox,
        output: any MTLTexture,
        target: CGColorSpace,
        metal: MetalContext
    ) async throws {
        let converted = try await metal.convertToEncodedSpace(input.texture, target: target)
        try await metal.dispatch2DTexture(
            functionName: TerminalKernels.copy,
            input: converted,
            output: output
        )
    }

    /// Last params committed through `commitParams` (the box commits
    /// before the pipe runs the module — the piece hash carries the same
    /// commit). `process` needs the resolved target, and params cannot be
    /// recovered from the one-way hash.
    private var lastCommittedParams: Params?

    /// Function-constant sets (D-17: ALL declared constants must be set;
    /// one bool at index 0 — `isP3` in `TerminalKernels.metal`). Cached per
    /// instance for a stable PSO fingerprint (D-16).
    private func constants(forP3 isP3: Bool, metal: MetalContext) -> MTLFunctionConstantValues {
        let cached = isP3 ? p3Constants : srgbConstants
        if let cached { return cached }
        let built = metal.makeConstants(isP3, at: 0, type: .bool)
        if isP3 { p3Constants = built } else { srgbConstants = built }
        return built
    }
}
