import LightamerCore
import LightamerIOP
import SwiftUI
import simd

// ─────────────────────────────────────────────────────────────────────────
// Filmic RGB panel (Plan 03-06-T5, IOP-FILM-01) — the scene-referred filmic
// view transform's Inspector surface: the contrast/latitude/balance shape
// sliders + the auto three keys (grey eyedropper + black/white full-image
// statistics, dt filmicrgb.c:2583-2660) + the preserve-chrominance picker
// + the colorscience picker (V5-locked note — T0 decision 1).
//
// D-H1 wiring: sliders = drag-begin/tick/end (one commit at the end); the
// auto keys and pickers are discrete one-commit edits. Auto-grey arms the
// viewport eyedropper (the D-T4 plumbing); auto black/white sample the
// linear chain's full-image min/max through the shared HistogramReduce.
// ─────────────────────────────────────────────────────────────────────────

internal struct FilmicRGBPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @Environment(InspectorState.self) private var inspectorState

    private var params: FilmicRGBModule.Params {
        PanelEditing.params(of: instance, as: FilmicRGBModule.self)
            ?? FilmicRGBModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_filmic_contrast"),
                    value: Double(params.contrast),
                    range: 0...5,
                    defaultValue: 1.0,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.contrast, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_filmicrgb")) },
                    onReset: { reset(\.contrast, 1.0) },
                    accessibilityID: "inspector.slider.filmicrgb.contrast"
                )
                LightamerSlider(
                    label: String(localized: "panel_filmic_latitude"),
                    value: Double(params.latitude),
                    range: 0.01...99,
                    defaultValue: 0.01,
                    readoutFormat: "%.2f",
                    unit: " %",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.latitude, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_filmicrgb")) },
                    onReset: { reset(\.latitude, 0.01) },
                    accessibilityID: "inspector.slider.filmicrgb.latitude"
                )
                LightamerSlider(
                    label: String(localized: "panel_filmic_balance"),
                    value: Double(params.balance),
                    range: -50...50,
                    defaultValue: 0,
                    readoutFormat: "%.1f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.balance, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_filmicrgb")) },
                    onReset: { reset(\.balance, 0) },
                    accessibilityID: "inspector.slider.filmicrgb.balance"
                )
                LightamerSlider(
                    label: String(localized: "panel_filmic_saturation"),
                    value: Double(params.saturation),
                    range: -200...200,
                    defaultValue: 0,
                    readoutFormat: "%.0f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturation, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_filmicrgb")) },
                    onReset: { reset(\.saturation, 0) },
                    accessibilityID: "inspector.slider.filmicrgb.saturation"
                )
            } header: {
                Text("panel_filmic_tone_section")
            }

            Section {
                autoGreyButton
                autoBlackButton
                autoWhiteButton
            } header: {
                Text("panel_filmic_auto_section")
            }

            Section {
                Picker("panel_filmic_preserve", selection: preserveBinding) {
                    Text("panel_filmic_norm_none").tag(FilmicRGBNorm.none)
                    Text("panel_filmic_norm_maxrgb").tag(FilmicRGBNorm.maxRGB)
                    Text("panel_filmic_norm_luminance").tag(FilmicRGBNorm.luminance)
                    Text("panel_filmic_norm_power").tag(FilmicRGBNorm.powerNorm)
                    Text("panel_filmic_norm_euclidean_v1").tag(FilmicRGBNorm.euclideanV1)
                    Text("panel_filmic_norm_euclidean_v2").tag(FilmicRGBNorm.euclideanV2)
                }
                .accessibilityIdentifier("inspector.filmicrgb.preserve")
                Picker("panel_filmic_version", selection: versionBinding) {
                    Text("panel_filmic_version_v1").tag(FilmicRGBColorscience.v1)
                    Text("panel_filmic_version_v2").tag(FilmicRGBColorscience.v2)
                    Text("panel_filmic_version_v3").tag(FilmicRGBColorscience.v3)
                    Text("panel_filmic_version_v4").tag(FilmicRGBColorscience.v4)
                    Text("panel_filmic_version_v5").tag(FilmicRGBColorscience.v5)
                }
                .accessibilityIdentifier("inspector.filmicrgb.version")
                Text("panel_filmic_v5_note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("panel_filmic_color_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.filmicrgb")
    }

    // MARK: - Auto keys (discrete one-commit edits; dt filmicrgb.c:2583-2660)

    private var autoGreyButton: some View {
        Button(String(localized: "panel_filmic_auto_grey")) {
            armEyedropper { picked in
                var p = params
                FilmicRGBModule.AutoKey.autoGrey(params: &p, picked: picked)
                applyDiscrete(p)
            }
        }
        .accessibilityIdentifier("inspector.button.filmicrgb.autoGrey")
    }

    private var autoBlackButton: some View {
        Button(String(localized: "panel_filmic_auto_black")) {
            Task {
                if let stats = await edit.sampleNormMinMax() {
                    var p = params
                    let blackNorm = max(stats.min.x, stats.min.y, stats.min.z)
                    FilmicRGBModule.AutoKey.autoBlack(params: &p, minMaxRGB: blackNorm)
                    applyDiscrete(p)
                }
            }
        }
        .accessibilityIdentifier("inspector.button.filmicrgb.autoBlack")
    }

    private var autoWhiteButton: some View {
        Button(String(localized: "panel_filmic_auto_white")) {
            Task {
                if let stats = await edit.sampleNormMinMax() {
                    var p = params
                    let whiteNorm = max(stats.max.x, stats.max.y, stats.max.z)
                    FilmicRGBModule.AutoKey.autoWhite(params: &p, maxMaxRGB: whiteNorm)
                    applyDiscrete(p)
                }
            }
        }
        .accessibilityIdentifier("inspector.button.filmicrgb.autoWhite")
    }

    private func armEyedropper(_ handler: @escaping (simd_float3) -> Void) {
        if inspectorState.isEyedropperActive {
            inspectorState.cancelEyedropper()
            return
        }
        inspectorState.beginEyedropper(handler)
    }

    // MARK: - Param plumbing

    private func set(_ keyPath: WritableKeyPath<FilmicRGBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: FilmicRGBModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<FilmicRGBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: FilmicRGBModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: FilmicRGBModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_filmicrgb"))
        }
    }

    private var preserveBinding: Binding<FilmicRGBNorm> {
        Binding(
            get: { params.preserveColor },
            set: { newValue in
                var p = params
                p.preserveColor = newValue
                applyDiscrete(p)
            }
        )
    }

    private var versionBinding: Binding<FilmicRGBColorscience> {
        Binding(
            get: { params.version },
            set: { newValue in
                var p = params
                p.version = newValue
                applyDiscrete(p)
            }
        )
    }
}

internal struct FilmicRGBPanelProvider: IOPPanelProvider {
    var opName: String { FilmicRGBModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(FilmicRGBPanelView(instance: instance, edit: edit))
    }
}
