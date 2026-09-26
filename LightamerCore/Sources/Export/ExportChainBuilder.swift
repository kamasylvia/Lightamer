import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExportChainBuilder — the export chain ASSEMBLER (Plan 11-03 T2).
//
// The OQ-11-2 ruling, materialized:
// 1. **gamma 必剔** — the display handoff (sRGB TRC + the pipe's only clamp,
//    GammaModule 78.0) is stripped from EVERY export chain. With gamma gone
//    the pipe tail keeps float32 and the terminal-tail format policy
//    (`PixelPipe.tailPixelFormat`) can never trigger — the export plane stays
//    unclamped linear/encoded float until the quantizer's [0,1] (D-COL4's
//    clamp semantics relocated to the exit face, D-11-CONTEXT-7).
// 2. **colorout 保留 + target 覆写** — the colorout record stays (yiyin and
//    the preview share the colorout→borders→watermark display-domain
//    semantics; 11-RESEARCH §5) and its target is REWRITTEN to the variant's
//    output profile (additive `ColorOutModule.OutputProfile` cases — no
//    params schema change). The exact CGColorSpace (display-TRC vs LINEAR
//    variant) rides the module's `exportTargetOverride` socket at
//    materialization time — a record is configuration, the variant's bit
//    depth decides the flavor (TIFF 32f = linear variant, D-11-CONTEXT-7).
//
// With the override in place the IN-PIPE colorout performs the WHOLE target
// conversion (primaries + white + TRC, one ColorSync render — no new Metal
// matrix families, RESEARCH §3.2), so the exit leg
// (`renderToEncodedBitmap(sourceColorSpace: target, toSpace: target)`) is an
// IDENTITY — the 转换恰一次 invariant; a double conversion is a color-cast
// bug the E3 dual-state golden catches.
//
// PURE over the record list — no GPU, no filesystem, no boxes (the renderer
// materializes + sets the socket).
// ─────────────────────────────────────────────────────────────────────────────

public enum ExportChainBuilder {

    /// The assembled export chain. NOT Sendable (the override carries a
    /// CGColorSpace) — consumed where it is built, like `ExportEncodeRequest`.
    public struct Built {

        /// The export records: `gamma` stripped, the colorout record's
        /// params rewritten to the explicit target profile. v50 order
        /// preserved (a sorted subset + an edited member re-encoded in
        /// place). Disable states / instance identities are verbatim.
        public let instances: [ModuleInstance]

        /// The exact target space for the colorout override socket (and the
        /// exit leg's identity pass): the display-TRC variant for the
        /// quantized tiers, the LINEAR variant for TIFF 32f.
        public let exportTargetOverride: CGColorSpace

        /// The gamut the override expresses (diagnostics/logs).
        public let target: ExportColorSpace

        /// `true` = a colorout record was found and rewritten, so the
        /// in-pipe conversion happened and the exit leg is an identity
        /// (sourceColorSpace == target). `false` = the chain had NO colorout
        /// (non-standard document) — the exit leg must do the WHOLE
        /// conversion from the working space (the 11-02 default face,
        /// `sourceColorSpace == WorkingSpace.colorSpace`).
        public let coloroutOverridden: Bool
    }

    /// Assemble the export chain for one variant's color target.
    ///
    /// - Parameters:
    ///   - source: the record list to export from (the disk sidecar's
    ///     `instances`, or the live set — both are the full base ∪ effective
    ///     face the coordinator renders).
    ///   - target: the variant's output color space (five-choice, EXP-04).
    ///   - linearVariant: `true` = the TIFF 32f tier — the override targets
    ///     the LINEAR variant ICC (scene-referred handoff, values never
    ///     bent by a TRC); `false` = the display-TRC variant (RESEARCH §3.3
    ///     quantization tiers).
    public static func exportChain(
        from source: [ModuleInstance],
        target: ExportColorSpace,
        linearVariant: Bool
    ) throws -> Built {
        let override: CGColorSpace
        if linearVariant {
            override = try ExportColorSpaceMapper.linearCGColorSpace(for: target)
            // D-11-02-2: the system ships no linear AdobeRGB / ROMM — a
            // 32f export on those gamuts is a menu-pairing bug upstream;
            // surfaced here, not silently bent.
        } else {
            override = ExportColorSpaceMapper.displayCGColorSpace(for: target)
        }

        // gamma 必剔 — EVERY gamma record, enabled or not (the export chain
        // never carries the display handoff).
        var instances = source.filter { $0.opName != GammaModule.opName }

        // colorout target rewrite: find the record (the terminal trio's
        // resident; absent colorout = a non-standard chain, exported as-is
        // and the EXIT LEG does the whole conversion from the working
        // space — the 11-02 default face; the renderer reads
        // `coloroutOverridden` for the sourceColorSpace choice).
        var coloroutOverridden = false
        if let index = instances.firstIndex(where: { $0.opName == ColorOutModule.opName }) {
            coloroutOverridden = true
            var record = instances[index]
            let profile: ColorOutModule.OutputProfile
            switch target {
            case .sRGB: profile = .sRGB
            case .displayP3: profile = .displayP3
            case .adobeRGB: profile = .adobeRGB
            case .proPhoto: profile = .proPhoto
            case .rec2020: profile = .rec2020
            }
            var params = (try? record.params(of: ColorOutModule.self)) ?? ColorOutModule.Params()
            params.outputProfile = profile
            // Keep the intent face verbatim (relative colorimetric is the
            // only intent Phase 11 implements — D-COL3).
            try record.setParams(params, as: ColorOutModule.self)
            instances[index] = record
        }

        return Built(
            instances: instances,
            exportTargetOverride: override,
            target: target,
            coloroutOverridden: coloroutOverridden)
    }

    /// The quantization tier's flavor question in one place: TIFF 32f is
    /// the ONLY linear-variant consumer (RESEARCH §3.3 — the D-11-CONTEXT-7
    /// tiers; every display tier, 8/16/10/12-bit, encodes display TRC).
    public static func isLinearVariant(_ spec: ExportFormatSpec) -> Bool {
        if case .tiff(.float32, _) = spec {
            return true
        }
        return false
    }

    // MARK: - The XMP mount (Plan 12-3 T4, D-12-CONTEXT-2)

    /// The post-encode XMP outcome. The export NEVER hard-fails on
    /// metadata — every non-attached outcome is a documented degradation
    /// (the failure case logs; the tally face is the outcome value itself).
    public enum XMPMountOutcome: Equatable, Sendable {
        /// The packet was injected and atomically promoted.
        case attached
        /// No sidecar (or all-empty metadata) — no fields, no packet.
        case skippedNoFields
        /// HEIC / AVIF / WebP — the D-12-CONTEXT-10 documented exceptions
        /// (the export matrix's reverse anchors byte-scan their absence).
        case skippedUnsupportedFormat
        /// A typed injection error degraded the mount: the product exists,
        /// carries no XMP, the export continues. Payload = the reason.
        case failed(String)
    }

    /// The post-encode XMP mount: read the SOURCE's disk sidecar, project
    /// its five metadata fields (D-12-CONTEXT-2: reject → Rating -1, pick
    /// has no XMP seat), serialize, inject into the freshly encoded
    /// product, and promote atomically (L009 — same-directory tmp rename).
    ///
    /// The exported image has LEFT the session truth-chain (the D-2
    /// ruling's reason face): the XMP rides the product only — the
    /// original and its `.lra` are never touched (the red line: this
    /// mount's only write target is the export destination file).
    ///
    /// Called by the encode stage after the atomic promote; a throw from
    /// the encoder itself never reaches here.
    public static func mountXMP(
        destination: URL, format: ExportFormatSpec, sourceURL: URL
    ) -> XMPMountOutcome {
        guard let containerFormat = XMPContainerFormat(exportSpec: format) else {
            return .skippedUnsupportedFormat
        }
        guard let document = ExportRenderer.readDocument(imageURL: sourceURL) else {
            return .skippedNoFields
        }
        let fields = XMPWriter.project(
            rating: document.rating, flag: document.flag,
            colorLabel: document.colorLabel, keywords: document.keywords)
        guard let packet = XMPWriter.write(fields: fields) else {
            return .skippedNoFields
        }
        do {
            let container = try Data(contentsOf: destination)
            let injected = try XMPContainerInjector.inject(
                packet, into: container, format: containerFormat)
            try injected.write(to: destination, options: .atomic)
            return .attached
        } catch {
            return .failed("\(error)")
        }
    }
}

/// The export-spec → injection-format mapping (the mount's dispatch; the
/// injector itself stays a pure Data plane).
public extension XMPContainerFormat {
    init?(exportSpec: ExportFormatSpec) {
        switch exportSpec {
        case .jpeg: self = .jpeg
        case .png: self = .png
        case .tiff: self = .tiff
        case .heic, .avif, .webp: return nil
        }
    }
}
