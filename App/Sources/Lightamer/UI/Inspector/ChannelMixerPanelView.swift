import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// ChannelMixer panel (Plan 05-03-T5, IOP-COLOR-04) — the Inspector surface
// for legacy dt `channelmixer`: output-channel Picker + 3 gain sliders +
// algorithm Picker. dt DEPRECATED note shown in-panel (channelmixer.c:126).
// D-H1 trio on sliders; Pickers/resets = applyDiscrete one-commit.
// ─────────────────────────────────────────────────────────────────────────

internal struct ChannelMixerPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @State private var outputChannel: ChannelMixerOutputChannel = .red

    private var params: ChannelMixerModule.Params {
        (try? instance.params(of: ChannelMixerModule.self)) ?? ChannelMixerModule.Params()
    }

    var body: some View {
        Form {
            Section {
                Text("panel_cm_deprecated_note")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .accessibilityIdentifier("inspector.note.channelmixer.deprecated")
                Picker(String(localized: "panel_cm_output"), selection: $outputChannel) {
                    Text("panel_cm_hue").tag(ChannelMixerOutputChannel.hue)
                    Text("panel_cm_saturation").tag(ChannelMixerOutputChannel.saturation)
                    Text("panel_cm_lightness").tag(ChannelMixerOutputChannel.lightness)
                    Text("panel_cm_red").tag(ChannelMixerOutputChannel.red)
                    Text("panel_cm_green").tag(ChannelMixerOutputChannel.green)
                    Text("panel_cm_blue").tag(ChannelMixerOutputChannel.blue)
                    Text("panel_cm_gray").tag(ChannelMixerOutputChannel.gray)
                }
                .accessibilityIdentifier("inspector.picker.channelmixer.output")
            } header: {
                Text("panel_cm_output_section")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_cm_red"),
                    value: Double(params.red[outputChannel.rawValue]),
                    range: -2...2,
                    defaultValue: Double(outputChannel == .red ? 1 : 0),
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(component: 0, $0) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixer")) },
                    onReset: { reset(component: 0) },
                    accessibilityID: "inspector.slider.channelmixer.red")
                LightamerSlider(
                    label: String(localized: "panel_cm_green"),
                    value: Double(params.green[outputChannel.rawValue]),
                    range: -2...2,
                    defaultValue: Double(outputChannel == .green ? 1 : 0),
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(component: 1, $0) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixer")) },
                    onReset: { reset(component: 1) },
                    accessibilityID: "inspector.slider.channelmixer.green")
                LightamerSlider(
                    label: String(localized: "panel_cm_blue"),
                    value: Double(params.blue[outputChannel.rawValue]),
                    range: -2...2,
                    defaultValue: Double(outputChannel == .blue ? 1 : 0),
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(component: 2, $0) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixer")) },
                    onReset: { reset(component: 2) },
                    accessibilityID: "inspector.slider.channelmixer.blue")
            } header: {
                Text("panel_cm_gains_section")
            }
            Section {
                Picker(String(localized: "panel_cm_algorithm"), selection: algorithmBinding) {
                    Text("panel_cm_v1").tag(ChannelMixerAlgorithm.v1)
                    Text("panel_cm_v2").tag(ChannelMixerAlgorithm.v2)
                }
                .accessibilityIdentifier("inspector.picker.channelmixer.algorithm")
            } header: {
                Text("panel_cm_algorithm_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.channelmixer")
    }

    private func set(component: Int, _ v: Double) {
        var p = params
        let i = outputChannel.rawValue
        if component == 0 { p.red[i] = Float(v) }
        else if component == 1 { p.green[i] = Float(v) }
        else { p.blue[i] = Float(v) }
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerModule.self) {
            edit.update(record)
        }
    }

    private func reset(component: Int) {
        var p = params
        let i = outputChannel.rawValue
        // dt init defaults: diagonal 1 on the matching RGB row, else 0.
        let d: Float = (component == 0 && outputChannel == .red)
            || (component == 1 && outputChannel == .green)
            || (component == 2 && outputChannel == .blue) ? 1 : 0
        if component == 0 { p.red[i] = d }
        else if component == 1 { p.green[i] = d }
        else { p.blue[i] = d }
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_channelmixer"))
        }
    }

    private var algorithmBinding: Binding<ChannelMixerAlgorithm> {
        Binding(
            get: { params.algorithm },
            set: { v in
                var p = params
                p.algorithm = v
                if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_channelmixer"))
                }
            })
    }
}

internal struct ChannelMixerPanelProvider: IOPPanelProvider {
    var opName: String { ChannelMixerModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ChannelMixerPanelView(instance: instance, edit: edit))
    }
}
