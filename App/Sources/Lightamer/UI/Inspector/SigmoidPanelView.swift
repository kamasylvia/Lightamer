import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Sigmoid panel (Plan 03-04-T5) — the D-T2 scene-referred baseline's
// Inspector surface: the four dt scalars (contrast/skew/display
// white/black) + the color-processing picker + the dt preset menu
// (sigmoid.c:249-277). Per the plan scope the inset/rotation/purity/
// base-primaries six-tuple stays module-only (no panel controls yet).
//
// D-H1 wiring: every slider is the drag-begin/tick/end trio (zero history
// items during the drag, exactly ONE commit at the end); the preset menu
// and the mode picker are discrete one-commit edits.
// ─────────────────────────────────────────────────────────────────────────

internal struct SigmoidPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: SigmoidModule.Params {
        PanelEditing.params(of: instance, as: SigmoidModule.self)
            ?? SigmoidModule.Params()
    }

    /// dt sigmoid.c:249-277 presets (name, contrast, skewness).
    private static let presets: [(String, Float, Float)] = [
        ("panel_sigmoid_preset_default", 1.5, 0.0),
        ("panel_sigmoid_preset_neutral", 1.22, 0.65),
        ("panel_sigmoid_preset_aces", 1.6, -0.2),
        ("panel_sigmoid_preset_reinhard", 1.0, 0.0),
    ]

    var body: some View {
        Form {
            Section {
                Picker("panel_sigmoid_processing", selection: processingBinding) {
                    Text("panel_sigmoid_processing_per_channel")
                        .tag(SigmoidColorProcessing.perChannel)
                    Text("panel_sigmoid_processing_rgb_ratio")
                        .tag(SigmoidColorProcessing.rgbRatio)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.sigmoid.processing")
            } header: {
                Text("panel_sigmoid_processing_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_sigmoid_contrast"),
                    value: Double(params.middleGreyContrast),
                    range: 0.1...10,
                    defaultValue: 1.5,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: {
                        set(\.middleGreyContrast, Float($0))
                    },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_sigmoid")) },
                    onReset: { reset(\.middleGreyContrast, 1.5) },
                    accessibilityID: "inspector.slider.sigmoid.contrast"
                )
                LightamerSlider(
                    label: String(localized: "panel_sigmoid_skew"),
                    value: Double(params.contrastSkewness),
                    range: -1...1,
                    defaultValue: 0,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: {
                        set(\.contrastSkewness, Float($0))
                    },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_sigmoid")) },
                    onReset: { reset(\.contrastSkewness, 0) },
                    accessibilityID: "inspector.slider.sigmoid.skew"
                )
                LightamerSlider(
                    label: String(localized: "panel_sigmoid_white"),
                    value: Double(params.displayWhiteTarget),
                    range: 20...1600,
                    defaultValue: 100,
                    readoutFormat: "%.0f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: {
                        set(\.displayWhiteTarget, Float($0))
                    },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_sigmoid")) },
                    onReset: { reset(\.displayWhiteTarget, 100) },
                    accessibilityID: "inspector.slider.sigmoid.white"
                )
                LightamerSlider(
                    label: String(localized: "panel_sigmoid_black"),
                    value: Double(params.displayBlackTarget),
                    range: 0...15,
                    defaultValue: 0.0152,
                    readoutFormat: "%.4f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: {
                        set(\.displayBlackTarget, Float($0))
                    },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_sigmoid")) },
                    onReset: { reset(\.displayBlackTarget, 0.0152) },
                    accessibilityID: "inspector.slider.sigmoid.black"
                )
            } header: {
                Text("panel_sigmoid_tone_section")
            }

            Section {
                Menu(String(localized: "panel_sigmoid_presets")) {
                    ForEach(SigmoidPanelView.presets, id: \.0) { preset in
                        Button(String(localized: String.LocalizationValue(preset.0))) {
                            var p = params
                            p.middleGreyContrast = preset.1
                            p.contrastSkewness = preset.2
                            applyDiscrete(p)
                        }
                    }
                }
                .accessibilityIdentifier("inspector.sigmoid.presets")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.sigmoid")
    }

    private func set(_ keyPath: WritableKeyPath<SigmoidModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SigmoidModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<SigmoidModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: SigmoidModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: SigmoidModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_sigmoid"))
        }
    }

    private var processingBinding: Binding<SigmoidColorProcessing> {
        Binding(
            get: { params.colorProcessing },
            set: { newMode in
                var p = params
                p.colorProcessing = newMode
                applyDiscrete(p)
            }
        )
    }
}

internal struct SigmoidPanelProvider: IOPPanelProvider {
    var opName: String { SigmoidModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(SigmoidPanelView(instance: instance, edit: edit))
    }
}
