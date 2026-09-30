import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// The node-ownership catalog (Plan M2-4-1 T3, KD-3; D-M2-4-CONTEXT-8) — the
// op → owner mapping table for the 18-catalog model (M2NODE-03). Layer 2 of
// the three-way split (see NodeOwnership.swift): this file lives in
// LightamerIOP so the entries can reference the `<Module>.opName` CONSTANTS
// — there is deliberately ONE string literal rule here: ZERO. A module
// rename must fail compilation instead of silently re-homing an op (the
// M2-1 Registry discipline, `defaultFaceDisabledOpNames` precedent).
//
// Membership (research/ALCEDO-FEATURE-MAP.md §2.1 + REQUIREMENTS
// M2GRADE-04 / IOP-DETAIL-02):
//
//   .drtPost — the Alcedo Detail panel family (applied once after the DRT):
//     Sharpen → Sharpen, FilmGrain → Grain, Halation → Bloom,
//     Clarity → Equalizer (the plan M2-4-1 ruling — the review sign-off
//     rides M2-4-1-DECISIONS; the local-contrast op stays .grade).
//
//   .develop — camera/geometry/terminal/dev faces that never live inside a
//     grade: Temperature (camera WB is a RAW Decode concern — M2GRADE-04),
//     Lens/Ashift/Flip/Crop/Liquify (geometry — the layerForbiddenGeometry
//     family), Borders/Watermark/TextOverlay (the yiyin terminal segment),
//     the M2-1 disabled six (FilmicRGB/Sigmoid/AgX are DRT-domain tone
//     mapping; DenoiseProfile/NLMeans/Bilateral are RAW-domain denoise —
//     enumerated by constant, NEVER derived from the disabled-set flag:
//     ownership is semantic, not face-dependent), and the two non-UI ops
//     (passthrough_spike / testgain).
//
//   Everything else answers .grade (the DEFAULT — M2-5 will narrow the 18
//   catalogs from this table without touching the validation seam).
// ─────────────────────────────────────────────────────────────────────────────

public enum NodeOwnershipCatalog {

    /// The DRT/Post-owned ops (the Detail-panel four).
    public static let drtPostOpNames: [String] = [
        SharpenModule.opName,
        GrainModule.opName,
        BloomModule.opName,
        EqualizerModule.opName,
    ]

    /// The develop-owned ops (RAW/geometry/terminal/dev faces).
    public static let developOpNames: [String] = [
        // Camera WB is a RAW Decode concern (M2GRADE-04).
        TemperatureModule.opName,
        // Geometry — the layerForbiddenGeometry family's semantic twin.
        LensModule.opName,
        AshiftModule.opName,
        FlipModule.opName,
        CropModule.opName,
        LiquifyModule.opName,
        // The yiyin terminal segment (frame / watermark / text).
        BordersModule.opName,
        WatermarkModule.opName,
        TextOverlayModule.opName,
        // The M2-1 disabled six — D1 tone mapping is DRT-domain (M2-6),
        // D2 denoise is RAW-domain (CIRAW NR). Enumerated by CONSTANT:
        // ownership is a semantic fact, independent of any face gate.
        FilmicRGBModule.opName,
        SigmoidModule.opName,
        AgXModule.opName,
        DenoiseProfileModule.opName,
        NLMeansModule.opName,
        BilateralModule.opName,
        // The two non-UI ops (Phase 1 spike + the dev-only gain).
        PassthroughModule.opName,
        TestGainModule.opName,
    ]

    /// The owner of an op. TOTAL over all op names: the default answer is
    /// .grade (the M2-4 grace table — M2-5 narrows the 18 catalogs from
    /// this one function without touching the validation seam).
    public static func owner(of opName: String) -> NodeOwnership {
        if drtPostOpNames.contains(opName) { return .drtPost }
        if developOpNames.contains(opName) { return .develop }
        return .grade
    }
}
