import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Colisa panel (Plan 03-03-T6) — three sliders (contrast / brightness /
// saturation ∈ [-1,1]), the D-T6 slider trio per drag. Double-click resets
// to the identity (all 0) through the compressed discrete commit.
// ─────────────────────────────────────────────────────────────────────────

internal struct ColisaPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: ColisaModule.Params {
        PanelEditing.params(of: instance, as: ColisaModule.self)
            ?? ColisaModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_colisa_contrast"),
                    value: Double(params.contrast),
                    range: -1...1,
                    defaultValue: 0,
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.contrast, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colisa")) },
                    onReset: { set(\.contrast, 0) },
                    accessibilityID: "inspector.slider.colisa.contrast"
                )
                LightamerSlider(
                    label: String(localized: "panel_colisa_brightness"),
                    value: Double(params.brightness),
                    range: -1...1,
                    defaultValue: 0,
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.brightness, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colisa")) },
                    onReset: { set(\.brightness, 0) },
                    accessibilityID: "inspector.slider.colisa.brightness"
                )
                LightamerSlider(
                    label: String(localized: "panel_colisa_saturation"),
                    value: Double(params.saturation),
                    range: -1...1,
                    defaultValue: 0,
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturation, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colisa")) },
                    onReset: { set(\.saturation, 0) },
                    accessibilityID: "inspector.slider.colisa.saturation"
                )
            } header: {
                Text("panel_colisa_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.colisa")
    }

    private func set(_ keyPath: WritableKeyPath<ColisaModule.Params, Float>, _ value: Float) {
        var p = params
        p[keyPath: keyPath] = value
        if let record = PanelEditing.updated(instance, params: p, as: ColisaModule.self) {
            edit.update(record)
        }
    }
}

internal struct ColisaPanelProvider: IOPPanelProvider {
    var opName: String { ColisaModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ColisaPanelView(instance: instance, edit: edit))
    }
}
