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
    func registerDefaultProviders() {
        register(ExposurePanelProvider())
        register(TemperaturePanelProvider())
        register(ColisaPanelProvider())
        register(ToneCurvePanelProvider())
        register(LevelsPanelProvider())
        register(SigmoidPanelProvider())
        register(ShadhiPanelProvider())
        register(ToneEqualPanelProvider())
        // Plan 03-06: filmicrgb (the scene-referred filmic transform) +
        // agx (the filmic VARIANT).
        register(FilmicRGBPanelProvider())
        register(AgXPanelProvider())
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
        register(NLMeansPanelProvider())
        // Plan 05-07-T6: denoiseprofile (mode/profile/force-curve panel).
        register(DenoiseProfilePanelProvider())
        // Plan 05-08-T4: bilateral (surface blur — radius + 3 sigma sliders).
        register(BilateralPanelProvider())
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
