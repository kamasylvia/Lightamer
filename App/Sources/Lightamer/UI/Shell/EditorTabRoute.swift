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
// Vignette + the "DRT arrives with M2-6" placeholder section. AgX is in
// `LightamerIOPRegistry.defaultFaceDisabledOpNames` (the M2-1 narrowed face)
// and stays UNHOUSED — hanging it would violate the M2-1 narrowing and the
// plan's disabled-names grep zero-hit assertion.
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

/// One rehomed panel row (KD-2): the registry op + where it rehomes + the
/// Advanced folded-group marker (the Geometry D6-only items).
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
    /// ashift/channelmixer family/haze — kept out of the Alcedo IA's face).
    let isAdvancedGroup: Bool

    static func page(
        _ opName: String, _ tab: EditorTabRoute, advanced: Bool = false
    ) -> EditorPanelDescriptor {
        EditorPanelDescriptor(
            opName: opName, disposition: .page(tab), isAdvancedGroup: advanced)
    }
}

/// The page's non-IOP content (the honest-shell slots beside the panel
/// rows — machine-checkable so the TAB-MATRIX stays in lockstep).
enum EditorTabSpecialContent: Equatable, Sendable {
    case none
    /// RAW Decode page: the CIRAW parameter panel (T4 fills the slot).
    case rawDecodePanel
    /// Display Transform page: the "DRT arrives with M2-6" placeholder
    /// section (checker E1: AgX NOT housed — the M2-1 disabled face).
    case displayTransformPlaceholder
    /// Mask page: the adjustment-layers panel + the MaskToolbar linkage
    /// entry (the M2-7 replacement's pre-home).
    case layersPanel
}

/// The D4/OQ-4 mapping table, coded (KD-2). Everything the stack renders
/// and the TAB-MATRIX transcribes comes from HERE.
enum EditorTabRoutingTable {

    /// The seven pages' panel rows. Row order = the OQ-4 table order.
    static func panels(for tab: EditorTabRoute) -> [EditorPanelDescriptor] {
        switch tab {
        case .tone:
            // OQ-4 Tone row (WB/Exposure/Contrast/White/Black/Shadows/
            // Highlights/Curve semantics): exposure, temperature, tonecurve,
            // levels, colisa, shadhi, colorcontrast. + toneequal (the
            // dynamic-set completeness adds it; the OQ-4 draft omitted it —
            // TAB-MATRIX marks "no Alcedo counterpart").
            [
                .page(ExposureModule.opName, .tone),
                .page(TemperatureModule.opName, .tone),
                .page(ToneCurveModule.opName, .tone),
                .page(LevelsModule.opName, .tone),
                .page(ColisaModule.opName, .tone),
                .page(ShadhiModule.opName, .tone),
                .page(ColorContrastModule.opName, .tone),
                .page(ToneEqualModule.opName, .tone),
            ]
        case .look:
            // OQ-4 Look row: vibrance/velvia/monochrome/colorbalancergb/
            // colorzones/skinsmooth + the detail five (sharpen/highpass/
            // soften/localcontrast/equalizer — highpass+soften stay the one
            // view's two provider rows) + grain/bloom (the OQ-4 DT-row note:
            // Alcedo post-DRT semantics — parked on Look until M2-6).
            [
                .page(VibranceModule.opName, .look),
                .page(VelviaModule.opName, .look),
                .page(MonochromeModule.opName, .look),
                .page(ColorBalanceRGBModule.opName, .look),
                .page(ColorZonesModule.opName, .look),
                .page(SkinSmoothModule.opName, .look),
                .page(SharpenModule.opName, .look),
                .page(HighpassModule.opName, .look),
                .page(SoftenModule.opName, .look),
                .page(LocalContrastModule.opName, .look),
                .page(EqualizerModule.opName, .look),
                .page(GrainModule.opName, .look),
                .page(BloomModule.opName, .look),
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
