import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Highpass + soften panel (Plan 04-05-T5) — the IOP-DETAIL-03 Inspector
// surface: two sections (highpass Lab inverted-highpass; soften RGB
// Orton), one provider per op.
//
// D-H1 wiring: drag trio per slider (zero history items while dragging,
// exactly ONE commit at drag end); reset is a discrete one-commit edit.
// Values READ from the instance record.
// ─────────────────────────────────────────────────────────────────────────

internal struct HighpassSoftenPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var isHighpass: Bool { instance.opName == HighpassModule.opName }

    private var highpassParams: HighpassModule.Params {
        PanelEditing.params(of: instance, as: HighpassModule.self)
            ?? HighpassModule.Params()
    }

    private var softenParams: SoftenModule.Params {
        PanelEditing.params(of: instance, as: SoftenModule.self)
            ?? SoftenModule.Params()
    }

    var body: some View {
        Form {
            if isHighpass {
                Section {
                    LightamerSlider(
                        label: String(localized: "panel_highpass_sharpness"),
                        value: Double(highpassParams.sharpness),
                        range: 0...100,
                        defaultValue: 50,
                        readoutFormat: "%.0f",
                        unit: "%",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { setHighpass(\.sharpness, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_highpass")) },
                        onReset: { resetHighpass(\.sharpness, 50) },
                        accessibilityID: "inspector.slider.highpass.sharpness"
                    )
                    LightamerSlider(
                        label: String(localized: "panel_highpass_contrast"),
                        value: Double(highpassParams.contrast),
                        range: 0...100,
                        defaultValue: 50,
                        readoutFormat: "%.0f",
                        unit: "%",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { setHighpass(\.contrast, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_highpass")) },
                        onReset: { resetHighpass(\.contrast, 50) },
                        accessibilityID: "inspector.slider.highpass.contrast"
                    )
                } header: {
                    Text("panel_highpass_section")
                }
            } else {
                Section {
                    LightamerSlider(
                        label: String(localized: "panel_soften_size"),
                        value: Double(softenParams.size),
                        range: 0...100,
                        defaultValue: 50,
                        readoutFormat: "%.0f",
                        unit: "%",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { setSoften(\.size, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_soften")) },
                        onReset: { resetSoften(\.size, 50) },
                        accessibilityID: "inspector.slider.soften.size"
                    )
                    LightamerSlider(
                        label: String(localized: "panel_soften_saturation"),
                        value: Double(softenParams.saturation),
                        range: 0...100,
                        defaultValue: 100,
                        readoutFormat: "%.0f",
                        unit: "%",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { setSoften(\.saturation, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_soften")) },
                        onReset: { resetSoften(\.saturation, 100) },
                        accessibilityID: "inspector.slider.soften.saturation"
                    )
                    LightamerSlider(
                        label: String(localized: "panel_soften_brightness"),
                        value: Double(softenParams.brightness),
                        range: -2...2,
                        defaultValue: 0.33,
                        readoutFormat: "%+.2f",
                        unit: " EV",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { setSoften(\.brightness, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_soften")) },
                        onReset: { resetSoften(\.brightness, 0.33) },
                        accessibilityID: "inspector.slider.soften.brightness"
                    )
                    LightamerSlider(
                        label: String(localized: "panel_soften_amount"),
                        value: Double(softenParams.amount),
                        range: 0...100,
                        defaultValue: 50,
                        readoutFormat: "%.0f",
                        unit: "%",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { setSoften(\.amount, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_soften")) },
                        onReset: { resetSoften(\.amount, 50) },
                        accessibilityID: "inspector.slider.soften.amount"
                    )
                } header: {
                    Text("panel_soften_section")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier(isHighpass ? "inspector.panel.highpass" : "inspector.panel.soften")
    }

    private func setHighpass(_ keyPath: WritableKeyPath<HighpassModule.Params, Float>, _ v: Float) {
        var p = highpassParams
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: HighpassModule.self) {
            edit.update(record)
        }
    }

    private func resetHighpass(_ keyPath: WritableKeyPath<HighpassModule.Params, Float>, _ v: Float) {
        var p = highpassParams
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: HighpassModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_highpass"))
        }
    }

    private func setSoften(_ keyPath: WritableKeyPath<SoftenModule.Params, Float>, _ v: Float) {
        var p = softenParams
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SoftenModule.self) {
            edit.update(record)
        }
    }

    private func resetSoften(_ keyPath: WritableKeyPath<SoftenModule.Params, Float>, _ v: Float) {
        var p = softenParams
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SoftenModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_soften"))
        }
    }
}

internal struct HighpassPanelProvider: IOPPanelProvider {
    var opName: String { HighpassModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(HighpassSoftenPanelView(instance: instance, edit: edit))
    }
}

internal struct SoftenPanelProvider: IOPPanelProvider {
    var opName: String { SoftenModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(HighpassSoftenPanelView(instance: instance, edit: edit))
    }
}
