import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// VignettePanelView (Plan 08-2 T1) — the vignette parameter panel: the dt
// `vignette.c:57-72` slider face verbatim (fall-off start / fall-off
// radius / brightness / saturation / center x·y / w-h ratio / shape) plus
// the two switches (unbound / automatic ratio). dithering is NOT ported
// (D-08-CONTEXT-5 ③) so no dither control exists here.
//
// D-H1 三件套: slider drags live-tick (zero history), land exactly ONE
// layerScope commit at drag end; the switches + reset are discrete
// one-commit edits.
// ─────────────────────────────────────────────────────────────────────────

internal struct VignettePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: VignetteModule.Params {
        PanelEditing.params(of: instance, as: VignetteModule.self)
            ?? VignetteModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_vignette_scale"),
                    value: Double(params.scale),
                    range: 0...200,
                    defaultValue: 80,
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.scale, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.scale, 80) },
                    accessibilityID: "inspector.slider.vignette.scale"
                )
                LightamerSlider(
                    label: String(localized: "panel_vignette_falloff"),
                    value: Double(params.falloffScale),
                    range: 0...200,
                    defaultValue: 50,
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.falloffScale, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.falloffScale, 50) },
                    accessibilityID: "inspector.slider.vignette.falloff"
                )
                LightamerSlider(
                    label: String(localized: "panel_vignette_brightness"),
                    value: Double(params.brightness),
                    range: -1...1,
                    defaultValue: -0.5,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.brightness, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.brightness, -0.5) },
                    accessibilityID: "inspector.slider.vignette.brightness"
                )
                LightamerSlider(
                    label: String(localized: "panel_vignette_saturation"),
                    value: Double(params.saturation),
                    range: -1...1,
                    defaultValue: -0.5,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturation, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.saturation, -0.5) },
                    accessibilityID: "inspector.slider.vignette.saturation"
                )
            } header: {
                Text("panel_vignette_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_vignette_center_x"),
                    value: Double(params.centerX),
                    range: -1...1,
                    defaultValue: 0,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.centerX, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.centerX, 0) },
                    accessibilityID: "inspector.slider.vignette.centerx"
                )
                LightamerSlider(
                    label: String(localized: "panel_vignette_center_y"),
                    value: Double(params.centerY),
                    range: -1...1,
                    defaultValue: 0,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.centerY, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.centerY, 0) },
                    accessibilityID: "inspector.slider.vignette.centery"
                )
                LightamerSlider(
                    label: String(localized: "panel_vignette_whratio"),
                    value: Double(params.whratio),
                    range: 0...2,
                    defaultValue: 1,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.whratio, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.whratio, 1) },
                    accessibilityID: "inspector.slider.vignette.whratio"
                )
                LightamerSlider(
                    label: String(localized: "panel_vignette_shape"),
                    value: Double(params.shape),
                    range: 0...5,
                    defaultValue: 1,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.shape, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_vignette")) },
                    onReset: { reset(\.shape, 1) },
                    accessibilityID: "inspector.slider.vignette.shape"
                )
            } header: {
                Text("panel_vignette_geometry")
            }

            Section {
                discreteToggle(
                    String(localized: "panel_vignette_unbound"),
                    keyPath: \.unbound, accessibility: "inspector.toggle.vignette.unbound")
                discreteToggle(
                    String(localized: "panel_vignette_autoratio"),
                    keyPath: \.autoratio, accessibility: "inspector.toggle.vignette.autoratio")
            } header: {
                Text("panel_vignette_clipping")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.vignette")
    }

    // MARK: D-H1 legs

    private func set(_ keyPath: WritableKeyPath<VignetteModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: VignetteModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<VignetteModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: VignetteModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_vignette"))
        }
    }

    /// The Bool params are discrete: ONE commit per flip (D-H1 离散控件).
    private func discreteToggle(
        _ title: String, keyPath: WritableKeyPath<VignetteModule.Params, Bool>,
        accessibility: String
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { params[keyPath: keyPath] },
            set: { v in
                var p = params
                p[keyPath: keyPath] = v
                if let record = PanelEditing.updated(instance, params: p, as: VignetteModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_vignette"))
                }
            }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityIdentifier(accessibility)
    }
}

internal struct VignettePanelProvider: IOPPanelProvider {
    var opName: String { VignetteModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(VignettePanelView(instance: instance, edit: edit))
    }
}
