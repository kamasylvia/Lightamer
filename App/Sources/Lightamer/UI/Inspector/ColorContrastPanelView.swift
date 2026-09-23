import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// ColorContrast panel (Plan 05-03-T5, IOP-COLOR-09) — the Inspector surface
// for dt `colorcontrast`: a/b steepness + a/b offset sliders + unbound
// toggle. D-H1 trio on sliders; toggle/resets = applyDiscrete one-commit.
// ─────────────────────────────────────────────────────────────────────────

internal struct ColorContrastPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: ColorContrastModule.Params {
        (try? instance.params(of: ColorContrastModule.self)) ?? ColorContrastModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_cc_a_steepness"),
                    value: Double(params.aSteepness), range: 0...5, defaultValue: 1,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.aSteepness, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorcontrast")) },
                    onReset: { reset(\.aSteepness, 1) },
                    accessibilityID: "inspector.slider.colorcontrast.a_steepness")
                LightamerSlider(
                    label: String(localized: "panel_cc_a_offset"),
                    value: Double(params.aOffset), range: -50...50, defaultValue: 0,
                    readoutFormat: "%+.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.aOffset, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorcontrast")) },
                    onReset: { reset(\.aOffset, 0) },
                    accessibilityID: "inspector.slider.colorcontrast.a_offset")
                LightamerSlider(
                    label: String(localized: "panel_cc_b_steepness"),
                    value: Double(params.bSteepness), range: 0...5, defaultValue: 1,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.bSteepness, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorcontrast")) },
                    onReset: { reset(\.bSteepness, 1) },
                    accessibilityID: "inspector.slider.colorcontrast.b_steepness")
                LightamerSlider(
                    label: String(localized: "panel_cc_b_offset"),
                    value: Double(params.bOffset), range: -50...50, defaultValue: 0,
                    readoutFormat: "%+.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.bOffset, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorcontrast")) },
                    onReset: { reset(\.bOffset, 0) },
                    accessibilityID: "inspector.slider.colorcontrast.b_offset")
                Toggle(String(localized: "panel_cc_unbound"), isOn: unboundBinding)
                    .accessibilityIdentifier("inspector.toggle.colorcontrast.unbound")
            } header: {
                Text("panel_cc_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.colorcontrast")
    }

    private func set(
        _ keyPath: WritableKeyPath<ColorContrastModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ColorContrastModule.self) {
            edit.update(record)
        }
    }

    private func reset(
        _ keyPath: WritableKeyPath<ColorContrastModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ColorContrastModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_colorcontrast"))
        }
    }

    private var unboundBinding: Binding<Bool> {
        Binding(
            get: { params.unbound },
            set: { v in
                var p = params
                p.unbound = v
                if let record = PanelEditing.updated(instance, params: p, as: ColorContrastModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_colorcontrast"))
                }
            })
    }
}

internal struct ColorContrastPanelProvider: IOPPanelProvider {
    var opName: String { ColorContrastModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ColorContrastPanelView(instance: instance, edit: edit))
    }
}
