import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Tonecurve panel (Plan 03-03-T3/T6) — CurveEditorView for the selected
// channel (L/a/b) + the autoscale and preserve-color pickers.
//
// Data flow: node drags map onto the D-H1 trio exactly like a slider
// (begin → live updates → ONE commit); pickers are discrete one-commit
// edits; double-click on the editor resets the SELECTED channel to its
// identity curve. Values READ from the instance record (D-X1: panels
// never touch display textures).
// ─────────────────────────────────────────────────────────────────────────

internal struct ToneCurvePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private enum Channel: String, CaseIterable, Identifiable {
        case l, a, b
        var id: String { rawValue }
    }

    @State private var channel: Channel = .l

    private var params: ToneCurveModule.Params {
        PanelEditing.params(of: instance, as: ToneCurveModule.self)
            ?? ToneCurveModule.Params()
    }

    private var nodes: [ToneCurveModule.Node] {
        switch channel {
        case .l: return params.curveL
        case .a: return params.curveA
        case .b: return params.curveB
        }
    }

    private var curveType: ToneCurveLUT.CurveType {
        switch channel {
        case .l: return params.typeL
        case .a: return params.typeA
        case .b: return params.typeB
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("panel_tonecurve_channel", selection: $channel) {
                    Text("panel_tonecurve_channel_l").tag(Channel.l)
                    Text("panel_tonecurve_channel_a").tag(Channel.a)
                    Text("panel_tonecurve_channel_b").tag(Channel.b)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.tonecurve.channel")

                CurveEditorView(
                    nodes: nodes,
                    curveType: curveType,
                    onDragBegin: { edit.beginEditing() },
                    onNodesChanged: { updated in setNodes(updated) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_tonecurve")) }
                )
                .frame(maxWidth: .infinity)

                HStack {
                    Button("panel_tonecurve_preset_linear") {
                        var p = params
                        setChannelNodes(&p, linearNodes)
                        applyDiscrete(p, label: String(localized: "history_tonecurve"))
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("panel_tonecurve_preset_s") {
                        var p = params
                        setChannelNodes(&p, sNodes)
                        applyDiscrete(p, label: String(localized: "history_tonecurve"))
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
            } header: {
                Text("panel_tonecurve_curves")
            }

            Section {
                Picker("panel_tonecurve_autoscale", selection: autoscaleBinding) {
                    Text("panel_tonecurve_autoscale_manual").tag(ToneCurveLUT.AutoscaleAb.manual)
                    Text("panel_tonecurve_autoscale_lab").tag(ToneCurveLUT.AutoscaleAb.labLinked)
                    Text("panel_tonecurve_autoscale_xyz").tag(ToneCurveLUT.AutoscaleAb.xyzLinked)
                    Text("panel_tonecurve_autoscale_rgb").tag(ToneCurveLUT.AutoscaleAb.rgbLinked)
                }
                .accessibilityIdentifier("inspector.tonecurve.autoscale")

                Picker("panel_tonecurve_preserve", selection: preserveBinding) {
                    Text("panel_tonecurve_preserve_none").tag(ToneCurveLUT.RGBNorm.none)
                    Text("panel_tonecurve_preserve_luminance").tag(ToneCurveLUT.RGBNorm.luminance)
                    Text("panel_tonecurve_preserve_max").tag(ToneCurveLUT.RGBNorm.max)
                    Text("panel_tonecurve_preserve_average").tag(ToneCurveLUT.RGBNorm.average)
                    Text("panel_tonecurve_preserve_sum").tag(ToneCurveLUT.RGBNorm.sum)
                    Text("panel_tonecurve_preserve_norm").tag(ToneCurveLUT.RGBNorm.norm)
                    Text("panel_tonecurve_preserve_power").tag(ToneCurveLUT.RGBNorm.power)
                }
                .accessibilityIdentifier("inspector.tonecurve.preserve")

                Toggle("panel_tonecurve_unbound", isOn: unboundBinding)
                    .accessibilityIdentifier("inspector.tonecurve.unbound")
            } header: {
                Text("panel_tonecurve_options")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.tonecurve")
    }

    // MARK: Node sets

    private var linearNodes: [ToneCurveModule.Node] {
        stride(from: 0.0, through: 1.0, by: 0.25).map {
            ToneCurveModule.Node(x: Float($0), y: Float($0))
        }
    }

    private var sNodes: [ToneCurveModule.Node] {
        [
            .init(x: 0, y: 0), .init(x: 0.25, y: 0.15), .init(x: 0.5, y: 0.5),
            .init(x: 0.75, y: 0.85), .init(x: 1, y: 1),
        ]
    }

    // MARK: Bindings / edits

    private func setNodes(_ updated: [ToneCurveModule.Node]) {
        var p = params
        setChannelNodes(&p, updated)
        update(p)
    }

    private func setChannelNodes(_ p: inout ToneCurveModule.Params, _ updated: [ToneCurveModule.Node]) {
        switch channel {
        case .l: p.curveL = updated
        case .a: p.curveA = updated
        case .b: p.curveB = updated
        }
    }

    private var autoscaleBinding: Binding<ToneCurveLUT.AutoscaleAb> {
        Binding(
            get: { params.autoscaleAb },
            set: { newValue in
                var p = params
                p.autoscaleAb = newValue
                applyDiscrete(p, label: String(localized: "history_tonecurve"))
            }
        )
    }

    private var preserveBinding: Binding<ToneCurveLUT.RGBNorm> {
        Binding(
            get: { params.preserveColors },
            set: { newValue in
                var p = params
                p.preserveColors = newValue
                applyDiscrete(p, label: String(localized: "history_tonecurve"))
            }
        )
    }

    private var unboundBinding: Binding<Bool> {
        Binding(
            get: { params.unboundAb },
            set: { newValue in
                var p = params
                p.unboundAb = newValue
                applyDiscrete(p, label: String(localized: "history_tonecurve"))
            }
        )
    }

    private func applyDiscrete(_ p: ToneCurveModule.Params, label: String) {
        if let record = PanelEditing.updated(instance, params: p, as: ToneCurveModule.self) {
            edit.applyDiscrete(record, label: label)
        }
    }

    private func update(_ p: ToneCurveModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: ToneCurveModule.self) {
            edit.update(record)
        }
    }
}

/// The tonecurve panel factory (registered in `InspectorState
/// .registerDefaultProviders`, Plan 03-03-T6).
internal struct ToneCurvePanelProvider: IOPPanelProvider {
    var opName: String { ToneCurveModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ToneCurvePanelView(instance: instance, edit: edit))
    }
}
