import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// AgX panel (Plan 03-06-T6, IOP-FILM-03) — the Blender AgX-inspired filmic
// VARIANT's Inspector surface: the look five-tuple + the log range EVs +
// the curve contrast/gamma/pivot axes. The primaries inset/rotation
// six-tuple stays module-only (the sigmoid-panel precedent — the values
// round-trip through sidecar/params, they just have no panel controls yet).
// hatchless has no dt counterpart and no control (REQUIREMENTS note).
//
// D-H1 wiring identical to the other tone panels (one commit per drag).
// ─────────────────────────────────────────────────────────────────────────

internal struct AgXPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: AgXModule.Params {
        PanelEditing.params(of: instance, as: AgXModule.self)
            ?? AgXModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_agx_contrast"),
                    value: Double(params.curveContrastAroundPivot),
                    range: 0.1...10,
                    defaultValue: 3.0,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.curveContrastAroundPivot, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_agx")) },
                    onReset: { reset(\.curveContrastAroundPivot, 3.0) },
                    accessibilityID: "inspector.slider.agx.contrast"
                )
                LightamerSlider(
                    label: String(localized: "panel_agx_gamma"),
                    value: Double(params.curveGamma),
                    range: 0.01...100,
                    defaultValue: 2.2,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.curveGamma, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_agx")) },
                    onReset: { reset(\.curveGamma, 2.2) },
                    accessibilityID: "inspector.slider.agx.gamma"
                )
                LightamerSlider(
                    label: String(localized: "panel_agx_saturation"),
                    value: Double(params.lookSaturation),
                    range: 0...10,
                    defaultValue: 1.0,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.lookSaturation, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_agx")) },
                    onReset: { reset(\.lookSaturation, 1.0) },
                    accessibilityID: "inspector.slider.agx.saturation"
                )
            } header: {
                Text("panel_agx_curve_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_agx_black_ev"),
                    value: Double(params.rangeBlackRelativeEv),
                    range: -20...(-0.1),
                    defaultValue: -10,
                    readoutFormat: "%.1f",
                    unit: " EV",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.rangeBlackRelativeEv, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_agx")) },
                    onReset: { reset(\.rangeBlackRelativeEv, -10) },
                    accessibilityID: "inspector.slider.agx.blackev"
                )
                LightamerSlider(
                    label: String(localized: "panel_agx_white_ev"),
                    value: Double(params.rangeWhiteRelativeEv),
                    range: 0.1...20,
                    defaultValue: 6.5,
                    readoutFormat: "%.1f",
                    unit: " EV",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.rangeWhiteRelativeEv, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_agx")) },
                    onReset: { reset(\.rangeWhiteRelativeEv, 6.5) },
                    accessibilityID: "inspector.slider.agx.whiteev"
                )
            } header: {
                Text("panel_agx_range_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_agx_hue_mix"),
                    value: Double(params.lookOriginalHueMixRatio),
                    range: 0...1,
                    defaultValue: 0.6,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.lookOriginalHueMixRatio, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_agx")) },
                    onReset: { reset(\.lookOriginalHueMixRatio, 0.6) },
                    accessibilityID: "inspector.slider.agx.huemix"
                )
                LightamerSlider(
                    label: String(localized: "panel_agx_brightness"),
                    value: Double(params.lookBrightness),
                    range: 0...100,
                    defaultValue: 1.0,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.lookBrightness, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_agx")) },
                    onReset: { reset(\.lookBrightness, 1.0) },
                    accessibilityID: "inspector.slider.agx.brightness"
                )
            } header: {
                Text("panel_agx_look_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.agx")
    }

    private func set(_ keyPath: WritableKeyPath<AgXModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: AgXModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<AgXModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: AgXModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: AgXModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_agx"))
        }
    }
}

internal struct AgXPanelProvider: IOPPanelProvider {
    var opName: String { AgXModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(AgXPanelView(instance: instance, edit: edit))
    }
}
