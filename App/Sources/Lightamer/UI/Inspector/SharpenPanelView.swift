import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Sharpen panel (Plan 04-05-T5) — the IOP-DETAIL-01 Inspector surface:
// radius/amount/threshold sliders (dt sharpen.c:45-47 ranges).
//
// D-H1 wiring: drag trio per slider (zero history items while dragging,
// exactly ONE commit at drag end). Values READ from the instance record.
// ─────────────────────────────────────────────────────────────────────────

internal struct SharpenPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: SharpenModule.Params {
        PanelEditing.params(of: instance, as: SharpenModule.self)
            ?? SharpenModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_sharpen_radius"),
                    value: Double(params.radius),
                    range: 0...8,
                    defaultValue: 2,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.radius, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_sharpen")) },
                    onReset: { reset(\.radius, 2) },
                    accessibilityID: "inspector.slider.sharpen.radius"
                )
                LightamerSlider(
                    label: String(localized: "panel_sharpen_amount"),
                    value: Double(params.amount),
                    range: 0...2,
                    defaultValue: 0,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.amount, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_sharpen")) },
                    onReset: { reset(\.amount, 0) },
                    accessibilityID: "inspector.slider.sharpen.amount"
                )
                LightamerSlider(
                    label: String(localized: "panel_sharpen_threshold"),
                    value: Double(params.threshold),
                    range: 0...100,
                    defaultValue: 0.5,
                    readoutFormat: "%.1f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.threshold, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_sharpen")) },
                    onReset: { reset(\.threshold, 0.5) },
                    accessibilityID: "inspector.slider.sharpen.threshold"
                )
            } header: {
                Text("panel_sharpen_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.sharpen")
    }

    private func set(_ keyPath: WritableKeyPath<SharpenModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SharpenModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<SharpenModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: SharpenModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: SharpenModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_sharpen"))
        }
    }
}

internal struct SharpenPanelProvider: IOPPanelProvider {
    var opName: String { SharpenModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(SharpenPanelView(instance: instance, edit: edit))
    }
}
