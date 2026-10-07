import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorTabRoute + EditorTabRoutingTable (Plan M2-3-3 T2, KD-2) — the D4/OQ-4
// seven-tab rehoming map as CODE: the single source of truth the adjustment
// stack renders from and the TAB-MATRIX markdown is transcribed from (the T2
// acceptance includes the line-by-line reconciliation).
//
// PAGE ORDER = the Alcedo `EditorAdjustmentStack.qml:10-16` sequence:
// Tone / Look / LUT / Display Transform / Geometry / RAW Decode / Mask.
//
// THE CHECKER E1 CORRECTION (2026-09-29): the Display Transform page is
// Vignette + a special-content slot. AgX is in
// `LightamerIOPRegistry.defaultFaceDisabledOpNames` (the M2-1 narrowed face)
// and stays UNHOUSED — hanging it would violate the M2-1 narrowing and the
// plan's disabled-names grep zero-hit assertion.
// M2-6-3 T2 (KD-2): the special-content slot now mounts the LIVE DRT panel
// (`DrtPanelView`) — the `displayTransformPlaceholder` case remains the
// routing-table marker for that slot, but the honest-shell PLACEHOLDER view
// is retired (the reinterpretation signed in M2-6-3-DECISIONS).
//
// THE CHECKER m3 CORRECTION: the rehome-completeness assertion domain is the
// DYNAMIC populated panel-provider set minus {TextOverlay} — Yiyin (the
// watermark/borders pair) rides the top-bar sheet DISPOSITION inside this
// table (exactly-once still holds), Preset is the stack header's global
// entry (no registry op — outside the domain), Lut is a registered op and
// rehomes ONCE on the LUT page. TextOverlay is the yiyin sheet's text
// carrier and is NOT in the table at all.
// ─────────────────────────────────────────────────────────────────────────────

/// The seven adjustment-stack tabs (the Alcedo page order).
enum EditorTabRoute: String, CaseIterable, Sendable, Identifiable {
    case tone
    case look
    case lut
    case displayTransform
    case geometry
    case rawDecode
    case mask

    var id: String { rawValue }

    /// The stable page marker (`editor.stack.tab.<name>`).
    var marker: String { "editor.stack.tab.\(rawValue)" }

    /// The localized tab label (the Alcedo tab captions).
    var label: String {
        switch self {
        case .tone:
            String(localized: "editor_tab_tone", defaultValue: "Tone")
        case .look:
            String(localized: "editor_tab_look", defaultValue: "Look")
        case .lut:
            String(localized: "editor_tab_lut", defaultValue: "LUT")
        case .displayTransform:
            String(localized: "editor_tab_display_transform",
                   defaultValue: "Display Transform")
        case .geometry:
            String(localized: "editor_tab_geometry", defaultValue: "Geometry")
        case .rawDecode:
            String(localized: "editor_tab_raw_decode", defaultValue: "RAW Decode")
        case .mask:
            String(localized: "editor_tab_mask", defaultValue: "Mask")
        }
    }
}

/// The Look page's four Alcedo group shells + the Tone page's compat fold
/// (Plan M2-5-2 KD-1). Grouping is a PURE PRESENTATION PROJECTION over the
/// routing table — `panels(for:)` row order IS the in-group order, the
/// stack buckets by `group` at render time, and there is NO second grouping
/// state source, so drift is unconstructible.
enum PanelGroup: String, CaseIterable, Sendable {

    /// Master: Saturation / Vibrance (§2.3).
    case master
    /// Look: the four DRT seats (Clarity/Sharpen/Halation/FilmGrain) with
    /// the D9 "pre-DRT for now" note — the M2-6 placeholder group.
    case look
    /// Color: White Balance (CAT02) / Selective Color / Color Wheels / Tint.
    case color
    /// Detail/Texture: the detail family + colorzones (checker m1 — the
    /// D6 收纳 seat; every existing Look row keeps a home here or above).
    case detailTexture
    /// The Tone page's「Darktable 兼容件」folded group (D5/D10): the D6-era
    /// tone pieces (levels/colisa/colorcontrast/toneequal/temperature) stay
    /// EDITABLE but out of the Alcedo IA's face. Rides the EXISTING
    /// `isAdvancedGroup` fold slot (the Geometry-page precedent) — this
    /// case only renames the group header on the Tone page.
    case compat

    /// The main-group rendering order (compat is NOT in it — it renders in
    /// the trailing fold like Geometry's Advanced).
    static let mainOrder: [PanelGroup] = [.master, .look, .color, .detailTexture]

    /// The localized group header (the Alcedo §2.3 captions).
    var label: String {
        switch self {
        case .master:
            String(localized: "panel_group_master", defaultValue: "Master")
        case .look:
            String(localized: "panel_group_look", defaultValue: "Look")
        case .color:
            String(localized: "panel_group_color", defaultValue: "Color")
        case .detailTexture:
            String(localized: "panel_group_detail_texture",
                   defaultValue: "Detail / Texture")
        case .compat:
            String(localized: "editor_stack_compat",
                   defaultValue: "Darktable compatibility")
        }
    }
}

/// One rehomed panel row (KD-2): the registry op + where it rehomes + the
/// Advanced folded-group marker (the Geometry D6-only items).
///
/// M2-5-2 KD-1 additive extension: `group` (the presentation shell) and
/// `note` (the D9-style honest copy under a row). The legacy three-argument
/// `page(...)` constructor keeps compiling with nil defaults — zero
/// breakage for the ungrouped pages.
struct EditorPanelDescriptor: Equatable, Sendable {
    /// Where the panel rehomes (D4).
    enum Disposition: Equatable, Sendable {
        /// A seven-tab page row.
        case page(EditorTabRoute)
        /// The top-bar yiyin sheet (the D4 独有入口: watermark/borders —
        /// export-domain first-class citizens, no Alcedo counterpart).
        case topBarSheet
    }

    /// The registry op this panel edits (`<Module>.opName` CONSTANT —
    /// never a string literal, so a rename fails compilation).
    let opName: String
    let disposition: Disposition
    /// The Geometry page's Advanced folded group (D6 独有项 — liquify/
    /// ashift/channelmixer family/haze — kept out of the Alcedo IA's face);
    /// the Tone compat group reuses this fold slot (KD-1).
    let isAdvancedGroup: Bool
    /// The Look-page group shell (nil = ungrouped — the flat render path).
    var group: PanelGroup?
    /// The row note's LOCALIZATION KEY (D9: "applies pre-DRT for now —
    /// moves post-DRT with M2-6"); rendered as a caption under the row.
    /// KD-1 sketched `StaticString?` — StaticString carries no value
    /// `==`/hash, so the synthesized `Equatable` face pins `String?` (call
    /// sites stay literal keys; the DECISIONS entry records the spelling).
    var note: String?

    static func page(
        _ opName: String, _ tab: EditorTabRoute, advanced: Bool = false
    ) -> EditorPanelDescriptor {
        EditorPanelDescriptor(
            opName: opName, disposition: .page(tab), isAdvancedGroup: advanced,
            group: nil, note: nil)
    }

    /// The grouped-page row constructor (KD-1): group shell + optional note.
    static func grouped(
        _ opName: String, _ tab: EditorTabRoute, group: PanelGroup,
        advanced: Bool = false, note: String? = nil
    ) -> EditorPanelDescriptor {
        EditorPanelDescriptor(
            opName: opName, disposition: .page(tab), isAdvancedGroup: advanced,
            group: group, note: note)
    }
}

/// The page's non-IOP content (the honest-shell slots beside the panel
/// rows — machine-checkable so the TAB-MATRIX stays in lockstep).
enum EditorTabSpecialContent: Equatable, Sendable {
    case none
    /// RAW Decode page: the CIRAW parameter panel (T4 fills the slot).
    case rawDecodePanel
    /// The Mask page: the adjustment-layers panel + the MaskToolbar linkage
    /// entry (the M2-7 replacement's pre-home).
    case layersPanel
    /// Display Transform page: the DRT panel slot. M2-6-3 T2 (KD-2): the
    /// case NAME is the M2-3 era's shell marker; since the live panel
    /// landed the value renders `DrtPanelView` — the honest-shell
    /// placeholder copy is retired (grep-zero on
    /// "editor.stack.drt.placeholder"; the rename-in-place choice over an
    /// enum removal is the diff-minimum face, M2-6-3-DECISIONS).
    case displayTransformPlaceholder
}

/// The D4/OQ-4 mapping table, coded (KD-2). Everything the stack renders
/// and the TAB-MATRIX transcribes comes from HERE.
enum EditorTabRoutingTable {

    /// The seven pages' panel rows. Row order = the OQ-4 table order.
    static func panels(for tab: EditorTabRoute) -> [EditorPanelDescriptor] {
        switch tab {
        case .tone:
            // M2-5-2 KD-1 / checker m2 — the Alcedo Tone convergence: the
            // MAIN face is the Alcedo Tone catalog (six rows at the T3
            // provider batch: Exposure / Contrast / White / Black / the ONE
            // "Shadows / Highlights" shadhi row — the two-slider panel, the
            // two-row branch is DELETED for the `ForEach(id: \.opName)`
            // static-id conflict — / Curve; T1 carries the three rows whose
            // providers already populate). The D6-era five (levels/colisa/
            // colorcontrast/toneequal/temperature) fold into the compat
            // group (D5: temperature's main-face removal IS the "Tone −1
            // row"; D10: kept editable, never deleted).
            [
                .page(ExposureModule.opName, .tone),
                .page(ContrastModule.opName, .tone),
                .page(WhiteModule.opName, .tone),
                .page(BlackModule.opName, .tone),
                .page(ShadhiModule.opName, .tone),
                .page(ToneCurveModule.opName, .tone),
                .grouped(LevelsModule.opName, .tone, group: .compat, advanced: true),
                .grouped(ColisaModule.opName, .tone, group: .compat, advanced: true),
                .grouped(ColorContrastModule.opName, .tone, group: .compat, advanced: true),
                .grouped(ToneEqualModule.opName, .tone, group: .compat, advanced: true),
                .grouped(TemperatureModule.opName, .tone, group: .compat, advanced: true),
            ]
        case .look:
            // M2-5-2 KD-1 — the Alcedo four-group IA (§2.3). The 13-row
            // zero-loss ledger (every pre-M2-5-2 row keeps a home):
            //   Master        { saturation (T3), vibrance }
            //   Look          { equalizer→Clarity, sharpen, grain→Film
            //                   Grain, bloom→Halation } — the .drtPost four
            //                   seats; M2-6-3 T5 (M2DRT-05): the seats RUN
            //                   post-DRT now — the pre-DRT notes are RETIRED
            //                   (the rows stay on the Look page, M2-3 IA).
            //   Color         { cat02WhiteBalance (T3), tint (T3); hls (T5)
            //                   + colorWheels (T4) complete the seat }
            //   Detail/Texture{ velvia, monochrome, colorbalancergb,
            //                   colorzones (checker m1 — the D6 收纳 seat),
            //                   skinsmooth, highpass, soften, localcontrast }
            [
                .grouped(SaturationModule.opName, .look, group: .master),
                .grouped(VibranceModule.opName, .look, group: .master),
                .grouped(EqualizerModule.opName, .look, group: .look),
                .grouped(SharpenModule.opName, .look, group: .look),
                .grouped(GrainModule.opName, .look, group: .look),
                .grouped(BloomModule.opName, .look, group: .look),
                .grouped(Cat02WBModule.opName, .look, group: .color),
                .grouped(HlsModule.opName, .look, group: .color),
                .grouped(ColorWheelsModule.opName, .look, group: .color),
                .grouped(TintModule.opName, .look, group: .color),
                .grouped(VelviaModule.opName, .look, group: .detailTexture),
                .grouped(MonochromeModule.opName, .look, group: .detailTexture),
                .grouped(ColorBalanceRGBModule.opName, .look, group: .detailTexture),
                .grouped(ColorZonesModule.opName, .look, group: .detailTexture),
                .grouped(SkinSmoothModule.opName, .look, group: .detailTexture),
                .grouped(HighpassModule.opName, .look, group: .detailTexture),
                .grouped(SoftenModule.opName, .look, group: .detailTexture),
                .grouped(LocalContrastModule.opName, .look, group: .detailTexture),
            ]
        case .lut:
            // OQ-4 LUT row: the lut3d panel (recursive scan / root picker =
            // M2-5, the page mounts the current face).
            [.page(Lut3dModule.opName, .lut)]
        case .displayTransform:
            // Checker E1 勘误: Vignette ONLY — AgX stays unhoused (the M2-1
            // disabled face); the DRT placeholder rides `specialContent`.
            [.page(VignetteModule.opName, .displayTransform)]
        case .geometry:
            // OQ-4 Geometry row: crop/flip/lens = the Alcedo framing basics;
            // the D6-only items (liquify/ashift/channelmixer family/haze)
            // fold into the Advanced group.
            [
                .page(CropModule.opName, .geometry),
                .page(FlipModule.opName, .geometry),
                .page(LensModule.opName, .geometry),
                .page(AshiftModule.opName, .geometry, advanced: true),
                .page(LiquifyModule.opName, .geometry, advanced: true),
                .page(ChannelMixerRGBModule.opName, .geometry, advanced: true),
                .page(ChannelMixerModule.opName, .geometry, advanced: true),
                .page(DehazeModule.opName, .geometry, advanced: true),
            ]
        case .rawDecode:
            // No registry op rehomes here: the page's content is the T4
            // CIRAW parameter panel (`specialContent`).
            []
        case .mask:
            // No registry op rehomes here either: the page is the layers
            // panel + MaskToolbar linkage (`specialContent`; the M2-7 Mask
            // Groups replace it).
            []
        }
    }

    /// The non-IOP page content (the complement of `panels(for:)`).
    static func specialContent(for tab: EditorTabRoute) -> EditorTabSpecialContent {
        switch tab {
        case .rawDecode: .rawDecodePanel
        case .displayTransform: .displayTransformPlaceholder
        case .mask: .layersPanel
        case .tone, .look, .lut, .geometry: .none
        }
    }

    /// The D4 top-bar sheet entries (the yiyin pair: the watermark +
    /// borders panel faces — one sheet, two provider rows).
    static let topBarSheetPanels: [EditorPanelDescriptor] = [
        EditorPanelDescriptor(
            opName: WatermarkModule.opName, disposition: .topBarSheet,
            isAdvancedGroup: false),
        EditorPanelDescriptor(
            opName: BordersModule.opName, disposition: .topBarSheet,
            isAdvancedGroup: false),
    ]

    /// EVERY rehomed row (page rows + the sheet rows) — the exactly-once
    /// assertion domain (the dynamic populated-provider set − {TextOverlay}
    /// must equal this set).
    static var allRehomedPanels: [EditorPanelDescriptor] {
        EditorTabRoute.allCases.flatMap { panels(for: $0) } + topBarSheetPanels
    }
}
