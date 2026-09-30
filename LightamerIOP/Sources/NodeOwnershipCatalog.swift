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
//     ownership is semantic, not face-dependent).
//
//   NOTE (the plan M2-4-1 KD-3 deviation, signed in M2-4-1-DECISIONS):
//   passthrough_spike / testgain are NOT develop-owned. The plan listed
//   them under .develop by their non-UI status, but panel presence is not
//   a stage fact — a gain/no-op op is stage-agnostic and grade-capable,
//   and the existing layer-chain test corpus drives addModuleToLayer with
//   testgain (the AC that the grade interior stays writable). They answer
//   .grade through the default arm.
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
    ]

    /// The owner of an op. TOTAL over all op names: the default answer is
    /// .grade (the M2-4 grace table — M2-5 narrows the 18 catalogs from
    /// this one function without touching the validation seam).
    ///
    /// M2-5-1 (KD-1): the 18 catalog rows below now carry their owner
    /// EXPLICITLY (the information base for the strict-face work) and this
    /// function consults that column — the signature and semantics are
    /// UNCHANGED (the default arm still answers .grade for every non-catalog
    /// op: colisa, toneequal, colorbalancergb, the terminal trio, …), so the
    /// M2-4-1 validation seam and NodeOwnershipCatalogTests pass untouched.
    public static func owner(of opName: String) -> NodeOwnership {
        if drtPostOpNames.contains(opName) { return .drtPost }
        if developOpNames.contains(opName) { return .develop }
        if let item = GradeCatalog.item(opName: opName) {
            return item.owner
        }
        return .grade
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The grade catalog (Plan M2-5-1 T1, KD-1) — the 18 Alcedo adjustment
// catalogs as a five-tuple table (D-M2-5-CONTEXT-1's on-disk carrier):
//
//   catalogID      — the stable Alcedo catalog id (KD-1 camelCase form,
//                    e.g. "cat02WhiteBalance"; the add-face enumeration id).
//   opName         — the owning `<Module>.opName` CONSTANT (the zero-literal
//                    rule above applies verbatim — a module rename fails
//                    compilation here too). Shadows AND Highlights share the
//                    one `shadhi` op (the Alcedo catalog has two entries;
//                    `item(opName:)` answers the first — Shadows).
//   owner          — 13× .grade + Tint (.grade) + the four DRT/Post seats
//                    (Clarity/Sharpen/Halation/FilmGrain — the M2-4-1
//                    rulings, mirroring drtPostOpNames above).
//   identityJSON   — the identity parameter snapshot (the reset/new-grade
//                    single source, P2 consumes). Built from each module's
//                    own Params encoding — NOT hand-copied panel defaults
//                    (checker m5). The shadhi rows pin shadows 0/highlights
//                    0 — the KERNEL no-op point, distinct from the panel
//                    defaults (50/−50, a WORKING point): the snapshot and
//                    the panel default are two separate values by design
//                    (M2-5-1-DECISIONS carries the shadhi declaration).
//   panelExposures — the main-slider key list (the P2 provider's
//                    declarative source).
//
// Completeness (checker E7): ModuleRegistry's default face minus
// (the 18 catalog ops ∪ {testgain}) = ∅ — testgain is the DEBUG-only
// registration exemption (Registry.swift `#if DEBUG`; the Release face
// excludes it). GradeCatalogTests asserts the closure and carries the
// same note so nobody "fixes" testgain back in.
// ─────────────────────────────────────────────────────────────────────────────

/// One catalog row — the five-tuple (KD-1).
public struct GradeCatalogItem: Sendable, Equatable {
    public let catalogID: String
    public let opName: String
    public let owner: NodeOwnership
    public let identityJSON: String
    public let panelExposures: [String]

    public init(
        catalogID: String, opName: String, owner: NodeOwnership,
        identityJSON: String, panelExposures: [String]
    ) {
        self.catalogID = catalogID
        self.opName = opName
        self.owner = owner
        self.identityJSON = identityJSON
        self.panelExposures = panelExposures
    }
}

/// One default-look entry (KD-9) — the op to instantiate + the params JSON
/// to commit (the same ParamsCoding bytes a sidecar carries).
public struct DefaultLookEntry: Sendable, Equatable {
    public let opName: String
    public let paramsJSON: String

    public init(opName: String, paramsJSON: String) {
        self.opName = opName
        self.paramsJSON = paramsJSON
    }
}

public enum GradeCatalog {

    /// The canonical params JSON for a params value (the identityJSON /
    /// paramsJSON single source — each module's own Codable face).
    private static func json(of params: some Encodable) -> String {
        String(data: ParamsCoding.encode(params), encoding: .utf8) ?? ""
    }

    /// The 18 catalogs, FEATURE-MAP §2.1 table order (M2-5-1 KD-1).
    public static let items: [GradeCatalogItem] = [
        GradeCatalogItem(
            catalogID: "cat02WhiteBalance", opName: Cat02WBModule.opName, owner: .grade,
            identityJSON: json(of: Cat02WBModule.Params()),
            panelExposures: ["temperature", "tint"]),
        GradeCatalogItem(
            catalogID: "exposure", opName: ExposureModule.opName, owner: .grade,
            identityJSON: json(of: ExposureModule.Params()),
            panelExposures: ["exposure"]),
        GradeCatalogItem(
            catalogID: "contrast", opName: ContrastModule.opName, owner: .grade,
            identityJSON: json(of: ContrastModule.Params()),
            panelExposures: ["contrast"]),
        GradeCatalogItem(
            catalogID: "white", opName: WhiteModule.opName, owner: .grade,
            identityJSON: json(of: WhiteModule.Params()),
            panelExposures: ["white"]),
        GradeCatalogItem(
            catalogID: "black", opName: BlackModule.opName, owner: .grade,
            identityJSON: json(of: BlackModule.Params()),
            panelExposures: ["black"]),
        // Shadows/Highlights share the one shadhi op — the KERNEL no-op
        // identity (shadows 0 / highlights 0) is NOT the panel default
        // (50 / −50, a working point): the snapshot/panel split is the
        // checker-m5 declaration (M2-5-1-DECISIONS).
        GradeCatalogItem(
            catalogID: "shadows", opName: ShadhiModule.opName, owner: .grade,
            identityJSON: json(of: ShadhiModule.Params(shadows: 0, highlights: 0)),
            panelExposures: ["shadows"]),
        GradeCatalogItem(
            catalogID: "highlights", opName: ShadhiModule.opName, owner: .grade,
            identityJSON: json(of: ShadhiModule.Params(shadows: 0, highlights: 0)),
            panelExposures: ["highlights"]),
        GradeCatalogItem(
            catalogID: "curve", opName: ToneCurveModule.opName, owner: .grade,
            identityJSON: json(of: ToneCurveModule.Params()),
            panelExposures: ["curve"]),
        GradeCatalogItem(
            catalogID: "hls", opName: HlsModule.opName, owner: .grade,
            identityJSON: json(of: HlsModule.Params()),
            panelExposures: ["hueShift", "lightness", "chroma", "hueSmoothness"]),
        GradeCatalogItem(
            catalogID: "saturation", opName: SaturationModule.opName, owner: .grade,
            identityJSON: json(of: SaturationModule.Params()),
            panelExposures: ["saturation"]),
        GradeCatalogItem(
            catalogID: "vibrance", opName: VibranceModule.opName, owner: .grade,
            identityJSON: json(of: VibranceModule.Params()),
            panelExposures: ["vibrance"]),
        GradeCatalogItem(
            catalogID: "colorWheel", opName: ColorWheelsModule.opName, owner: .grade,
            identityJSON: json(of: ColorWheelsModule.Params()),
            panelExposures: ["lift", "gamma", "gain"]),
        GradeCatalogItem(
            catalogID: "lmt", opName: Lut3dModule.opName, owner: .grade,
            identityJSON: json(of: Lut3dModule.Params()),
            panelExposures: ["lutName"]),
        GradeCatalogItem(
            catalogID: "tint", opName: TintModule.opName, owner: .grade,
            identityJSON: json(of: TintModule.Params()),
            panelExposures: ["tint"]),
        // The DRT/Post four (the M2-4-1 rulings — mirrored from
        // drtPostOpNames above; the Look-page Detail/Texture family).
        GradeCatalogItem(
            catalogID: "clarity", opName: EqualizerModule.opName, owner: .drtPost,
            identityJSON: json(of: EqualizerModule.Params()),
            panelExposures: ["clarity"]),
        GradeCatalogItem(
            catalogID: "sharpen", opName: SharpenModule.opName, owner: .drtPost,
            identityJSON: json(of: SharpenModule.Params()),
            panelExposures: ["sharpen"]),
        GradeCatalogItem(
            catalogID: "halation", opName: BloomModule.opName, owner: .drtPost,
            // Bloom's Params() defaults (strength 25) are NOT pixel
            // identity — the registry seeds it DISABLED for exactly that
            // reason; the reset snapshot is the kernel no-op point
            // (strength 0, the glow weight off).
            identityJSON: json(of: BloomModule.Params(strength: 0)),
            panelExposures: ["strength"]),
        GradeCatalogItem(
            catalogID: "filmGrain", opName: GrainModule.opName, owner: .drtPost,
            // Same disposition as halation: strength 0 = the no-op point.
            identityJSON: json(of: GrainModule.Params(strength: 0)),
            panelExposures: ["strength"]),
    ]

    /// The catalog row for an op name (first match — Shadows wins the
    /// shared shadhi op; the envelope/boxing query only needs membership).
    public static func item(opName: String) -> GradeCatalogItem? {
        items.first { $0.opName == opName }
    }

    /// The grade-owned rows (13 Grade items + Tint — the 18 minus the four
    /// DRT/Post seats).
    public static func gradeItems() -> [GradeCatalogItem] {
        items.filter { $0.owner == .grade }
    }

    /// The product default look (KD-9, M2GRADE-03): +1.5 EV / contrast +15
    /// / saturation 1.3 — applied to NEW imports only (P2 mint branch
    /// consumes; Core ImportService only writes the pending flag). The
    /// exposure entry IS the existing exposure module instance (KD-9: only
    /// the `exposure` field deviates from identity).
    public static let defaultLook: [DefaultLookEntry] = [
        DefaultLookEntry(
            opName: ExposureModule.opName,
            paramsJSON: json(of: ExposureModule.Params(exposure: 1.5))),
        DefaultLookEntry(
            opName: ContrastModule.opName,
            paramsJSON: json(of: ContrastModule.Params(contrast: 15))),
        DefaultLookEntry(
            opName: SaturationModule.opName,
            paramsJSON: json(of: SaturationModule.Params(saturation: 1.3))),
    ]
}

/// M2-5-1 T1 tripwire: thrown by the seven new grade ops' `process` until
/// their implementation commits land (T3–T7). The ops are NOT registered
/// meanwhile, so nothing can dispatch them — an accidental dispatch fails
/// loudly instead of passing pixels through silently.
struct GradeCarrierKernelPending: Error {
    let op: String
}
