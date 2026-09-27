import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// DehazePanelView (Plan 08-5 T1) — the hazeremoval parameter panel: the dt
// `hazeremoval.c:66-67,576` face — strength / distance / adaptive.
//
// D-H1 三件套: slider drags live-tick (zero history), land exactly ONE
// layerScope commit at drag end; the adaptive toggle is a discrete
// one-commit edit; reset is discrete.
// ─────────────────────────────────────────────────────────────────────────

internal struct DehazePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: DehazeModule.Params {
        PanelEditing.params(of: instance, as: DehazeModule.self)
            ?? DehazeModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_dehaze_strength"),
                    value: Double(params.strength),
                    range: -1...1,
                    defaultValue: 0.2,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.strength, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_dehaze")) },
                    onReset: { reset(\.strength, 0.2) },
                    accessibilityID: "inspector.slider.dehaze.strength"
                )
                LightamerSlider(
                    label: String(localized: "panel_dehaze_distance"),
                    value: Double(params.distance),
                    range: 0...1,
                    defaultValue: 0.2,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.distance, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_dehaze")) },
                    onReset: { reset(\.distance, 0.2) },
                    accessibilityID: "inspector.slider.dehaze.distance"
                )
                Toggle(
                    String(localized: "panel_dehaze_adaptive"),
                    isOn: Binding(
                        get: { params.adaptive },
                        set: { newValue in
                            var p = params
                            p.adaptive = newValue
                            if let record = PanelEditing.updated(
                                instance, params: p, as: DehazeModule.self) {
                                edit.applyDiscrete(
                                    record, label: String(localized: "history_dehaze"))
                            }
                        }))
                    .accessibilityIdentifier("inspector.toggle.dehaze.adaptive")
            } header: {
                Text("panel_dehaze_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.dehaze")
    }

    // MARK: D-H1 legs

    private func set(_ keyPath: WritableKeyPath<DehazeModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: DehazeModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<DehazeModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: DehazeModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_dehaze"))
        }
    }
}

internal struct DehazePanelProvider: IOPPanelProvider {
    var opName: String { DehazeModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(DehazePanelView(instance: instance, edit: edit))
    }
}
