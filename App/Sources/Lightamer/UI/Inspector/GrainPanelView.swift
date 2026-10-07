import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// GrainPanelView (Plan 08-2 T2) — the grain parameter panel: the dt
// `grain.c` three-slider face — coarseness (shown as ISO through the
// GRAIN_SCALE_FACTOR = 213.2 bauhaus factor, the `~ISO of the film`
// semantics verbatim — D-08-CONTEXT-6 ①: NO separate ISO-sensitivity
// slider exists) / strength / mid-tones bias.
//
// D-H1 三件套: slider drags live-tick (zero history), land exactly ONE
// layerScope commit at drag end; reset is a discrete one-commit edit.
// ─────────────────────────────────────────────────────────────────────────

internal struct GrainPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: GrainModule.Params {
        PanelEditing.params(of: instance, as: GrainModule.self)
            ?? GrainModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_grain_scale"),
                    value: params.iso,
                    range: 20...6400,
                    defaultValue: 1600,
                    readoutFormat: "%.0f",
                    unit: " ISO",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.scale, Float($0) / GrainModule.grainScaleFactor) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_grain")) },
                    onReset: { reset(\.scale, 1600.0 / GrainModule.grainScaleFactor) },
                    accessibilityID: "inspector.slider.grain.scale"
                )
                LightamerSlider(
                    label: String(localized: "panel_grain_strength"),
                    value: Double(params.strength),
                    range: 0...100,
                    defaultValue: 25,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.strength, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_grain")) },
                    onReset: { reset(\.strength, 25) },
                    accessibilityID: "inspector.slider.grain.strength"
                )
                LightamerSlider(
                    label: String(localized: "panel_grain_midtones"),
                    value: Double(params.midtonesBias),
                    range: 0...100,
                    defaultValue: 0,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.midtonesBias, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_grain")) },
                    onReset: { reset(\.midtonesBias, 0) },
                    accessibilityID: "inspector.slider.grain.midtones"
                )
            } header: {
                Text("panel_grain_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.grain")
    }

    // MARK: D-H1 legs

    private func set(_ keyPath: WritableKeyPath<GrainModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: GrainModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<GrainModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: GrainModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_grain"))
        }
    }
}

internal struct GrainPanelProvider: IOPPanelProvider {
    var opName: String { GrainModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(GrainPanelView(instance: instance, edit: edit))
    }
}
