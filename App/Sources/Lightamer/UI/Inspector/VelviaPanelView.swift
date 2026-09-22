import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Velvia panel (Plan 05-04-T4, IOP-COLOR-07) — the Inspector surface
// for dt `velvia`: strength + mid-tones bias sliders. D-H1 trio on
// sliders; resets = applyDiscrete one-commit.
// ─────────────────────────────────────────────────────────────────────────

internal struct VelviaPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: VelviaModule.Params {
        (try? instance.params(of: VelviaModule.self)) ?? VelviaModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_velvia_strength"),
                    value: Double(params.strength), range: 0...100, defaultValue: 0,
                    readoutFormat: "%.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.strength, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_velvia")) },
                    onReset: { reset(\.strength, 0) },
                    accessibilityID: "inspector.slider.velvia.strength")
                LightamerSlider(
                    label: String(localized: "panel_velvia_bias"),
                    value: Double(params.bias), range: 0...1, defaultValue: 1,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.bias, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_velvia")) },
                    onReset: { reset(\.bias, 1) },
                    accessibilityID: "inspector.slider.velvia.bias")
            } header: {
                Text("panel_velvia_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.velvia")
    }

    private func set(
        _ keyPath: WritableKeyPath<VelviaModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: VelviaModule.self) {
            edit.update(record)
        }
    }

    private func reset(
        _ keyPath: WritableKeyPath<VelviaModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: VelviaModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_velvia"))
        }
    }
}

internal struct VelviaPanelProvider: IOPPanelProvider {
    var opName: String { VelviaModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(VelviaPanelView(instance: instance, edit: edit))
    }
}
