import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Shadhi panel (Plan 03-04-T5) — the shadows & highlights Inspector
// surface: radius/shadows/highlights/compress + the two ccorrect sliders
// + the algo picker. The BILATERAL leg is a Phase 5 port (plan checkpoint
// decision recorded on the module): the picker shows dt's default option
// DISABLED with the Phase 5 note, and `process` runs the gaussian leg for
// both algo values.
//
// D-H1 wiring: drag trio per slider (zero history items while dragging,
// exactly ONE commit at drag end); the algo picker is a discrete
// one-commit edit.
// ─────────────────────────────────────────────────────────────────────────

internal struct ShadhiPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: ShadhiModule.Params {
        PanelEditing.params(of: instance, as: ShadhiModule.self)
            ?? ShadhiModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_shadhi_radius"),
                    value: Double(params.radius),
                    range: 0.1...500,
                    defaultValue: 100,
                    readoutFormat: "%.0f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.radius, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_shadhi")) },
                    onReset: { reset(\.radius, 100) },
                    accessibilityID: "inspector.slider.shadhi.radius"
                )
            } header: {
                Text("panel_shadhi_radius_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_shadhi_shadows"),
                    value: Double(params.shadows),
                    range: -100...100,
                    defaultValue: 50,
                    readoutFormat: "%.0f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.shadows, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_shadhi")) },
                    onReset: { reset(\.shadows, 50) },
                    accessibilityID: "inspector.slider.shadhi.shadows"
                )
                LightamerSlider(
                    label: String(localized: "panel_shadhi_highlights"),
                    value: Double(params.highlights),
                    range: -100...100,
                    defaultValue: -50,
                    readoutFormat: "%.0f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.highlights, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_shadhi")) },
                    onReset: { reset(\.highlights, -50) },
                    accessibilityID: "inspector.slider.shadhi.highlights"
                )
            } header: {
                Text("panel_shadhi_strength_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_shadhi_compress"),
                    value: Double(params.compress),
                    range: 0...100,
                    defaultValue: 50,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.compress, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_shadhi")) },
                    onReset: { reset(\.compress, 50) },
                    accessibilityID: "inspector.slider.shadhi.compress"
                )
                LightamerSlider(
                    label: String(localized: "panel_shadhi_shadows_ccorrect"),
                    value: Double(params.shadowsCCorrect),
                    range: 0...100,
                    defaultValue: 100,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.shadowsCCorrect, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_shadhi")) },
                    onReset: { reset(\.shadowsCCorrect, 100) },
                    accessibilityID: "inspector.slider.shadhi.scc"
                )
                LightamerSlider(
                    label: String(localized: "panel_shadhi_highlights_ccorrect"),
                    value: Double(params.highlightsCCorrect),
                    range: 0...100,
                    defaultValue: 50,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.highlightsCCorrect, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_shadhi")) },
                    onReset: { reset(\.highlightsCCorrect, 50) },
                    accessibilityID: "inspector.slider.shadhi.hcc"
                )
            } header: {
                Text("panel_shadhi_color_section")
            }

            Section {
                Picker("panel_shadhi_algo", selection: algoBinding) {
                    Text("panel_shadhi_algo_gaussian")
                        .tag(ShadhiModule.Params.Algo.gaussian)
                    Text("panel_shadhi_algo_bilateral")
                        .tag(ShadhiModule.Params.Algo.bilateral)
                        .disabled(true) // Phase 5 leg (plan checkpoint T2)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.shadhi.algo")

                Text("panel_shadhi_bilateral_note")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
            } header: {
                Text("panel_shadhi_algo_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.shadhi")
    }

    private func set(_ keyPath: WritableKeyPath<ShadhiModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ShadhiModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<ShadhiModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: ShadhiModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: ShadhiModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_shadhi"))
        }
    }

    private var algoBinding: Binding<ShadhiModule.Params.Algo> {
        Binding(
            get: { params.algo },
            set: { newAlgo in
                guard newAlgo == .gaussian else { return } // bilateral = Phase 5
                var p = params
                p.algo = newAlgo
                applyDiscrete(p)
            }
        )
    }
}

internal struct ShadhiPanelProvider: IOPPanelProvider {
    var opName: String { ShadhiModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ShadhiPanelView(instance: instance, edit: edit))
    }
}
