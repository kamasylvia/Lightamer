import Foundation
import LightamerCore
import LightamerIOP
import Observation
import simd
import SwiftUI

/// Inspector-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the selected iop panel, panel expand/collapse state, the
/// D-T6 `IOPPanelProvider` registry (opName → panel factory dispatch), and
/// the D-T4 eyedropper interaction mode. Does NOT own image data and holds
/// no references to the other state objects.
///
/// Panel dispatch (Plan 03-02-T3): the app registers the hand-written
/// providers at launch (`registerDefaultProviders`); `panelView(for:edit:)`
/// resolves the selected instance's opName to its panel. Registry-driven
/// per the plan — a provider type lists itself here, the InspectorView
/// stays generic.
@Observable
@MainActor
final class InspectorState {

    /// Currently selected inspector panel (the instance UUID string of the
    /// selected iop instance; empty = nothing selected).
    private(set) var selectedPanel: String = ""

    /// Identifiers of expanded inspector sections.
    private(set) var expandedSections: Set<String> = []

    /// The opName → panel factory registry (v1: hand-written providers,
    /// reflection-based generation stays an extension point).
    private var providers: [String: any IOPPanelProvider] = [:]

    // ── D-T4 eyedropper plumbing ─────────────────────────────────────────

    /// True while the viewport is in eyedropper mode (crosshair cursor,
    /// clicks route to `PipeCoordinator` sampling instead of being ignored).
    private(set) var isEyedropperActive = false

    /// The pending completion handler for the active eyedropper session
    /// (set by the panel that armed the mode).
    private var eyedropperHandler: ((simd_float3) -> Void)?

    // MARK: - Provider registry

    /// Register one panel provider (idempotent per opName — last wins).
    func register(_ provider: any IOPPanelProvider) {
        providers[provider.opName] = provider
    }

    /// The Phase 3 default set: exposure + temperature + the 03-03 Lab
    /// trio (colisa / tonecurve / levels) + the 03-04 additions (sigmoid
    /// D-T2 baseline / shadhi). Later plans append theirs.
    ///
    /// M2-1: `defaultFace: true` skips the D1/D2 disable set's panel
    /// providers (KD-1) — the Inspector panel rows AND the layer
    /// add-module menu enumerate this registry, so both UI faces narrow
    /// with the seed face. Default `false` = full face (KD-2: every
    /// existing caller/test keeps all panels; only the app composition
    /// root passes the face — KD-3 `isFullFaceRequested`).
    func registerDefaultProviders(defaultFace: Bool = false) {
        // The gate (KD-2): providers are gated by their opName against the
        // registry's own disable-set constant — one source of truth, zero
        // duplicated names.
        let skip = defaultFace
            ? LightamerIOPRegistry.defaultFaceDisabledOpNames : []
        func gated(_ provider: any IOPPanelProvider) {
            guard !skip.contains(provider.opName) else { return }
            register(provider)
        }
        register(ExposurePanelProvider())
        register(TemperaturePanelProvider())
        register(ColisaPanelProvider())
        register(ToneCurvePanelProvider())
        register(LevelsPanelProvider())
        // M2-1 matrix rows 1-3 (D1: tone mapping → terminal DRT, M2-6) and
        // rows 4-6 (D2: denoise → RAW 9 decode layer) — gated below.
        gated(SigmoidPanelProvider())
        register(ShadhiPanelProvider())
        register(ToneEqualPanelProvider())
        // Plan 03-06: filmicrgb (the scene-referred filmic transform) +
        // agx (the filmic VARIANT).
        gated(FilmicRGBPanelProvider())
        gated(AgXPanelProvider())
        // Plan 04-02-T5: crop (the framing window).
        register(CropPanelProvider())
        // Plan 04-08-T1 (GUI-6): flip orientation Picker (EXIF auto + 8
        // states; dt flip.c gui_init 4-button XOR simplified to direct
        // select — D-08-T1-1).
        register(FlipPanelProvider())
        // Plan 04-03-T5: ashift (rotate + perspective + Vision auto-detect).
        register(AshiftPanelProvider())
        // Plan 04-04-T3: lens (embedded note + manual sliders + Lensfun).
        register(LensPanelProvider())
        // Plan 04-05-T5: detail five (sharpen + local contrast + highpass +
        // soften + equalizer; highpass/soften share one view, two providers).
        register(SharpenPanelProvider())
        register(LocalContrastPanelProvider())
        register(HighpassPanelProvider())
        register(SoftenPanelProvider())
        register(EqualizerPanelProvider())
        // Plan 05-02-T4: colorbalancergb (4-way hue discs + lane groups).
        register(ColorBalanceRGBPanelProvider())
        // Plan 05-03-T5: channelmixerrgb + channelmixer legacy + colorcontrast.
        register(ChannelMixerRGBPanelProvider())
        register(ChannelMixerPanelProvider())
        register(ColorContrastPanelProvider())
        // Plan 05-04-T4: vibrance + velvia + colorzones (L/C/h tabs).
        register(VibrancePanelProvider())
        register(VelviaPanelProvider())
        register(ColorZonesPanelProvider())
        // Plan 06-06-T4: liquify (node list + warp type + strength/radius).
        register(LiquifyPanelProvider())
        // Plan 05-05-T4: monochrome (Lab chroma wheel + size/highlights).
        register(MonochromePanelProvider())
        // Plan 05-06-T5: nlmeans (astrophoto denoise — 4 sliders).
        gated(NLMeansPanelProvider())
        // Plan 05-07-T6: denoiseprofile (mode/profile/force-curve panel).
        gated(DenoiseProfilePanelProvider())
        // Plan 05-08-T4: bilateral (surface blur — radius + 3 sigma sliders).
        gated(BilateralPanelProvider())
        // Plan 07-3 T3: skinSmooth (the 25TH panel — frequency-separation
        // skin smoothing + the「定位皮肤」skin-mask generator action).
        register(SkinSmoothPanelProvider())
        // Plan 08-2 T6: the 印框/水印 panel (the watermark section; the
        // borders section integrates in 08-3).
        register(YiyinPanelProvider())
        // Plan 08-3 T1: the SAME dual-section panel dispatches for the
        // borders row too (both yiyin sections ride one provider pair —
        // the dispatched record routes through the view; the sibling
        // rides the session lookup).
        register(YiyinBordersPanelProvider())
        // Plan 12-5 T5: lut3d (library import/picker + colorspace +
        // interpolation pickers + the 1D/missing hints).
        register(LutPanelProvider())
        // Plan 08-2 T1: vignette (the dt-verbatim falloff/shape panel).
        register(VignettePanelProvider())
        // Plan 08-2 T2: grain (coarseness-ISO / strength / mid-tones bias).
        register(GrainPanelProvider())
        // Plan 08-2 T3: bloom (the dt-verbatim size/threshold/strength panel).
        register(BloomPanelProvider())
        // Plan 08-5 T1: hazeremoval (the dt-verbatim strength/distance/
        // adaptive panel — the dark-channel-prior dehaze).
        register(DehazePanelProvider())
        // Plan 08-5 T2: textOverlay (the editing-time text layer face).
        register(TextOverlayPanelProvider())
        // Plan M2-5-2 T3: the six thin slider panels for the M2-5-1
        // catalog ops (CAT02 creative WB / Contrast / White / Black /
        // Tint / Saturation — the ranges/defaults cite the modules' own
        // constants). colorWheels (T4) and hls (T5) join with their
        // panels.
        register(Cat02WBPanelProvider())
        register(ContrastPanelProvider())
        register(WhitePanelProvider())
        register(BlackPanelProvider())
        register(TintPanelProvider())
        register(SaturationPanelProvider())
    }
    var panelOpNames: [String] {
        providers.keys.sorted()
    }

    /// Dispatch the selected instance's panel view; nil when the op has no
    /// registered panel (e.g. the terminal trio).
    func panelView(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView? {
        providers[instance.opName]?.panel(for: instance, edit: edit)
    }

    /// Select the instance whose panel the Inspector should show.
    func selectPanel(instanceID: UUID) {
        selectedPanel = instanceID.uuidString
    }

    /// Toggle a collapsible section.
    func toggleSection(_ id: String) {
        if expandedSections.contains(id) {
            expandedSections.remove(id)
        } else {
            expandedSections.insert(id)
        }
    }

    // MARK: - Eyedropper mode (D-T4)

    /// Arm eyedropper mode. The next viewport click samples the PREVIEW
    /// linear color and invokes `handler` once, then the mode disarms
    /// itself. `cancelEyedropper` disarms without invoking.
    func beginEyedropper(_ handler: @escaping (simd_float3) -> Void) {
        eyedropperHandler = handler
        isEyedropperActive = true
    }

    /// The viewport click resolved: deliver the picked color and disarm.
    func completeEyedropper(with picked: simd_float3) {
        guard isEyedropperActive, let handler = eyedropperHandler else { return }
        disarmEyedropper()
        handler(picked)
    }

    /// Disarm without delivering (second click on the toolbar button, ESC).
    func cancelEyedropper() {
        disarmEyedropper()
    }

    private func disarmEyedropper() {
        eyedropperHandler = nil
        isEyedropperActive = false
    }
}
