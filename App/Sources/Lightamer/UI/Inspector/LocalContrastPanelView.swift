import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Local contrast panel (Plan 04-05-T5) — the IOP-DETAIL-02 Inspector
// surface: detail (−1..4) + sigmaS/sigmaR sliders (D6 v1 semantics).
//
// D-H1 wiring: drag trio per slider (zero history items while dragging,
// exactly ONE commit at drag end). Values READ from the instance record.
// ─────────────────────────────────────────────────────────────────────────

internal struct LocalContrastPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: LocalContrastModule.Params {
        PanelEditing.params(of: instance, as: LocalContrastModule.self)
            ?? LocalContrastModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_localcontrast_detail"),
                    value: Double(params.detail),
                    range: -1...4,
                    defaultValue: 0,
                    readoutFormat: "%+.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.detail, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_localcontrast")) },
                    onReset: { reset(\.detail, 0) },
                    accessibilityID: "inspector.slider.localcontrast.detail"
                )
            } header: {
                Text("panel_localcontrast_strength_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_localcontrast_sigma_s"),
                    value: Double(params.sigmaS),
                    range: 1...100,
                    defaultValue: 20,
                    readoutFormat: "%.0f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.sigmaS, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_localcontrast")) },
                    onReset: { reset(\.sigmaS, 20) },
                    accessibilityID: "inspector.slider.localcontrast.sigmaS"
                )
                LightamerSlider(
                    label: String(localized: "panel_localcontrast_sigma_r"),
                    value: Double(params.sigmaR),
                    range: 0.05...2,
                    defaultValue: 0.5,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.sigmaR, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_localcontrast")) },
                    onReset: { reset(\.sigmaR, 0.5) },
                    accessibilityID: "inspector.slider.localcontrast.sigmaR"
                )
            } header: {
                Text("panel_localcontrast_radius_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.localcontrast")
    }

    private func set(_ keyPath: WritableKeyPath<LocalContrastModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: LocalContrastModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<LocalContrastModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: LocalContrastModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: LocalContrastModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_localcontrast"))
        }
    }
}

internal struct LocalContrastPanelProvider: IOPPanelProvider {
    var opName: String { LocalContrastModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(LocalContrastPanelView(instance: instance, edit: edit))
    }
}
