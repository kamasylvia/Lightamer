import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Vibrance panel (Plan 05-04-T4, IOP-COLOR-03) — the Inspector surface
// for dt `vibrance`: single amount slider. D-H1 trio on the slider;
// reset = applyDiscrete one-commit.
// ─────────────────────────────────────────────────────────────────────────

internal struct VibrancePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: VibranceModule.Params {
        (try? instance.params(of: VibranceModule.self)) ?? VibranceModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_vibrance_amount"),
                    value: Double(params.amount), range: 0...100, defaultValue: 0,
                    readoutFormat: "%.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.amount, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vibrance")) },
                    onReset: { reset(\.amount, 0) },
                    accessibilityID: "inspector.slider.vibrance.amount")
            } header: {
                Text("panel_vibrance_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.vibrance")
    }

    private func set(
        _ keyPath: WritableKeyPath<VibranceModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: VibranceModule.self) {
            edit.update(record)
        }
    }

    private func reset(
        _ keyPath: WritableKeyPath<VibranceModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: VibranceModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_vibrance"))
        }
    }
}

internal struct VibrancePanelProvider: IOPPanelProvider {
    var opName: String { VibranceModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(VibrancePanelView(instance: instance, edit: edit))
    }
}
